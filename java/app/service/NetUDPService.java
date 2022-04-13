/*
 * Copyright (c) 2016. Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */

package app.service;

import app.DataBuffer;
import app.ExError;
import app.FireCallback;
import app.LoggerExt;
import util.CRC16sb;
import util.CommonTools;

import java.io.IOException;
import java.io.Serializable;
import java.net.InetSocketAddress;
import java.net.SocketAddress;
import java.nio.channels.DatagramChannel;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Абстрактный сервис для удаленного управления путём подачи команд по сети. На базе этого класса потомки должны
 * реализовать конкретные схемы выполнения команд (как последовательное выполнение, так и параллельное - каждая команда
 * в своём отдельном потоке).
 * <pre>
 * 1. UDP пакет содержит сообщение.
 * 2. Сообщение представляет собой команду управления сервисом (перечень фиксирован) и состоит из метаданных и данных.
 * 3. Метаданные содержат служебную информацию и описание команды сервиса. Команда сервиса исполняется немедленно в
 * потоке сервиса.
 * 4. Данные содержат дополнительную информацию, например для команды сервиса EXECUTE или в ответах на команду сервиса.
 * </pre>
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
public abstract class NetUDPService extends Service {

    private final LoggerExt logger;

    /** Канал для приёма\передачи датаграмм. */
    private DatagramChannel channel;
    /** Номер UDP порта для сетевого обмена (для входящих\исходящих сообщений). */
    private final int port;

    /** Буфер для приёма и передачи пакетов-сообщений. */
    private final DataBuffer ioBuffer;

    /**
     * Конструктор.
     *
     * @param name    Название сервиса.
     * @param udpport Номер порта для сетевого обмена.
     */
    public NetUDPService(String name, int udpport, int maxmsgsize) {
        super(name);
        this.logger = LoggerExt.getNewLogger("NetUDPService-" + name).enable(true).toFile();
        this.channel = null;
        this.port = udpport;
        this.ioBuffer = new DataBuffer(maxmsgsize);
    }

    /** Объект для генерации CRC16 для сообщений и их проверки (один объект - для оптимизации выделения памяти). */
    public static class MessageCRC {
        private final CRC16sb crc16 = new CRC16sb();

        /** Расчёт CRC16 для указанной части буфера (синхронизирована). */
        public synchronized int calculate(DataBuffer buf, int offset, int length) {
            crc16.reset();
            for (int i = 0; i < length; i++) {
                crc16.update(buf.getAt(offset + i));
            }
            return crc16.value();
        }
    }

    /** Объект для генерации CRC16 для сообщений и их проверки (один объект - для оптимизации выделения памяти). */
    private final MessageCRC crc16 = new MessageCRC();


    @Override
    protected void fireOnStart() {
        FireCallback.safe(super::fireOnStart);
        if (!isTerminating()) {
            logger.infof("Запуск сетевого UDP сервиса (port=%d)!", port);
            // Создание канала приёма-отправки датаграмм-сообщений.
            try {
                channel = DatagramChannel.open();
                channel.configureBlocking(false);
                channel.bind(new InetSocketAddress(port));
            } catch (Exception ex) {
                logger.errorf("Ошибка создания UDP канала - %s!", ExError.exMsg(ex));
                terminate();
            }
        }
    }

    @Override
    protected void fireOnStop() {
        try {
            if (channel != null) {
                channel.close();
                channel = null;
            }
        } catch (Exception ignore) {
        }
        logger.infof("Остановка сетевого UDP сервиса (port=%d)!", port);
        FireCallback.safe(super::fireOnStop);
    }

    /**
     * Тело обработчика сервиса. Запускает отдельный процесс - обработчик команд. Реализует непрерывный цикл приёма
     * входящих датаграмм-сообщений. По получении сообщения, оно парсится и преобразуется в команду. В зависимости от
     * режима выполнения команды она или выполняется сразу в потоке приёма или ставится в очередь на исполнение
     * процессором (при наличии свободных слотов). После этого отправителю отсылается подтверждение получения (для
     * немедленного исполнения - может содержать и результат исполнения). Результат исполнения команды в процессоре
     * отправитель получает путём отправки запроса результата. После чего освобождает слот.
     *
     * @throws ExError
     */
    @Override
    protected void serviceBody() throws ExError {
        try {
            // Буфер для сообщений (чтобы нельзя было перезаписать начальные 4 байта).
            final DataBuffer msgbuffer = ioBuffer.wrap(4);

            // До момента разрыва - крутим цикл приёма сообщений.
            while (!isTerminating()) {
                // Попытка получения сообщения.
                SocketAddress client = channel.receive(ioBuffer.reset().getBB());
                // Если сообщение получено - обрабатываем.
                if (client != null) {
                    ioBuffer.flip(); // После этого окно равно полученному пакету.
                    int len = ioBuffer.length();
                    logger.infof("Получено сообщение от %s {size=%d hex=%s}", client.toString(), len, ioBuffer.getHexAt(0, len));
                    try {
                        if (len < 4) {
                            throw new ExWrongMessage("Длина датаграммы меньше 4 байт! {len=%d}", len);
                        }
                        int msglen = ioBuffer.getInt2();
                        int msgcrc = ioBuffer.getInt2();

                        // Проверяем длину сообщения.
                        if (msglen != len - 4) {
                            throw new ExWrongMessage("Длина сообщения не совпадает с длиной в сообщении! {len=%d-4 msglen=%d}", len, msglen);
                        }
                        // Проверяем контрольную сумму.
                        int crc = crc16.calculate(ioBuffer, 4, len - 4);
                        if (msgcrc != crc) {
                            throw new ExWrongMessage("Не совпадает контрольная сумма! {crc=0x%04X msgcrc=0x%04X}", crc, msgcrc);
                        }

                        // Если сообщение не битое - обрабатываем!
                        msgbuffer.area(0, len - 4); // Общий байт-массив с ioBuffer (!) со сдвигом.
                        processMessage(client, System.currentTimeMillis(), msgbuffer);

                        // Если нет ошибок - отсылаем подготовленный обработчиком ответ клиенту.
                        msgbuffer.offset(0); // Устанавливаем начало окна (конец не изменяется!).
                        len = msgbuffer.length(); // Считаем данными к отправке - всё до конца окна.
                        // Если есть данные (кроме первых 4 байт) - отправляем.
                        if (len > 0) {
                            crc = crc16.calculate(msgbuffer, 0, len);
                            // Записываем первые 4 байта - дескриптор.
                            ioBuffer.area(0, len + 4).putInt2(len).putInt2(crc).rewind();
                            // Отправляем.
                            int sendsize = channel.send(ioBuffer.getBB(), client);
                            // Если не всё отправили - ошибка!
                            if (sendsize == ioBuffer.length()) {
                                logger.infof("Отправлено сообщение для %s {size=%d hex=%s}", client.toString(), sendsize, ioBuffer.getHexAt(0, sendsize));
                            } else {
                                logger.errorf("Ошибка отправки сообщения для %s! {отправлено %d из %d}", client.toString(), sendsize, ioBuffer.length());
                            }
                        }

                    } catch (ExWrongMessage ex) {
                        logger.errorf("Неверный формат сообщения - %s!", ExError.exMsg(ex));
                    } catch (Exception ex) {
                        logger.errorf("Ошибка при разборе сообщения - %s!", ExError.exMsg(ex));
                    }
                } else {
                    CommonTools.safeInterruptedSleep(5); // Если нет пакетов - ожидаем.
                }
            }

        } catch (IOException ex) {
            logger.errorf("Ошибка IO - %s!", ExError.exMsg(ex));
        } catch (Exception ex) {
            logger.errorf("Ошибка сервиса - %s!", ExError.exMsg(ex));
        }
    }

    /**
     * Обработчик поступившего сообщения. Ответ возвращается в том же буфере.
     *
     * @param address     Адрес отправителя сообщения.
     * @param receivetime Врема получения сообщения (локальное).
     * @param msgbuffer   Буфер с "телом" сообщения (рабочее окно).
     * @throws ExWrongMessage
     */
    protected abstract void processMessage(SocketAddress address, long receivetime, DataBuffer msgbuffer) throws ExWrongMessage;

    /**
     * Исключение выбрасываемое при неверном формате сообщения.
     */
    public static class ExWrongMessage extends ExError {

        public ExWrongMessage(String msg) {
            super(msg);
        }

        public ExWrongMessage(String fmt, Object... params) {
            super(fmt, params);
        }
    }
}
