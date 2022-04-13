/*
 * Copyright (c) 2016. Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */

package app.service;

import app.DataBuffer;
import app.ExError;
import app.LoggerExt;
import util.CommonTools;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.SocketAddress;
import java.nio.channels.DatagramChannel;
import java.util.concurrent.atomic.AtomicLong;

import static app.service.RCService.Meta;

/**
 * Клиент для сервиса удаленного управления.
 *
 * @author Aleksey Dokshin <dant.it@gmail.com> (19.02.16).
 */
public class RCClient {

    private final LoggerExt logger;

    private final int clientID;

    private final DatagramChannel channel;
    private final InetSocketAddress address;
    private final DataBuffer ioBuffer;
    protected final DataBuffer tmpBuffer; // Оставляем доступным для потомков - для доп.разбора!

    private AtomicLong messageID = new AtomicLong(System.currentTimeMillis());
    private AtomicLong commandID = new AtomicLong(System.currentTimeMillis());


    public RCClient(int clientid, InetSocketAddress address, int maxmsgsize) throws IOException {
        this.logger = LoggerExt.getNewLogger("RCClient-" + clientid);
        this.clientID = clientid;
        this.channel = DatagramChannel.open();
        this.channel.configureBlocking(false);
        this.address = address;
        this.ioBuffer = new DataBuffer(maxmsgsize);
        this.tmpBuffer = new DataBuffer(maxmsgsize);
    }

    /** Объект для генерации CRC16 для сообщений и их проверки (тот же класс, что и у сервиса!). */
    private final RCService.MessageCRC crc16 = new RCService.MessageCRC();

    /** Генерация cmdID для нового сообщения запроса. */
    protected long generateMessageID() {
        return messageID.addAndGet(1);
    }

    /** Генерация cmdID для новой команды. */
    protected long generateCommandID() {
        return commandID.addAndGet(1);
    }

    /** Ошибка при подготовке запроса. */
    public static final int ERR_REQ_BUILD = 1;
    /** Ошибка при отправке запроса. */
    public static final int ERR_REQ_SEND = 2;
    /** Ошибка при получении ответа. Отсутствие пакетов к этой ошибке не относится! */
    public static final int ERR_ANSW_RECEIVE = 3;
    /** Ошибка при разборе ответа. */
    public static final int ERR_ANSW_PARSE = 4;

    /**
     * Отправка запроса сервису и получение ответа на запрос.
     *
     * @param answertimeout Время ожидания ответа от сервиса.
     * @param meta          Метаданные запроса.
     * @param body          Данные запроса (тело запроса).
     * @throws IOException
     * @throws Service.ExTerminate
     * @throws Service.ExTimeout
     * @throws RCService.ExResultError
     */
    private void request(int answertimeout, Meta meta, DataBuffer body) throws ExRequestError, ExTimeout {

        long dt = System.currentTimeMillis();

        try {
            ioBuffer.reset().shift(4); // оставляем для длины и CRC16.
            meta.buildRequest(ioBuffer).putArea(body).flip();
            int len = ioBuffer.length() - 4;
            int crc = crc16.calculate(ioBuffer, 4, len);
            ioBuffer.putInt2At(0, len).putInt2At(2, crc);
        } catch (Exception ex) {
            throw new ExRequestError(ERR_REQ_BUILD, "Ошибка построения запроса - %s!", ExError.exMsg(ex));
        }

        try {
            // Убираем из приёмного буфера все сообщения.
            while (channel.receive(ioBuffer.getBB()) != null);
            // Отправляем (должно уйти с первого раза - иначе ошибка!).
            int sendsize = channel.send(ioBuffer.getBB(), address);
            // Если не всё отправили - ошибка!
            if (sendsize != ioBuffer.length()) {
                throw new ExRequestError(ERR_REQ_SEND, "Ошибка отправки запроса для %s! {отправлено %d из %d}",
                        address, sendsize, ioBuffer.length());
            }
            logger.infof("Отправлено в %s {meta={%s} datahex=%s",
                    address, meta.toString(), body.getHexAt(0, body.length()));
        } catch (ExRequestError ex) {
            throw ex;
        } catch (Exception ex) {
            throw new ExRequestError(ERR_REQ_SEND, "Ошибка отправки запроса - %s!", ExError.exMsg(ex));
        }

        String err = null;

        while (true) {
            SocketAddress client;
            try {
                client = channel.receive(ioBuffer.reset().getBB());
            } catch (Exception ex) {
                throw new ExRequestError(ERR_ANSW_RECEIVE, "Ошибка получения ответа - %s!", ExError.exMsg(ex));
            }

            if (client == null) {
                if (System.currentTimeMillis() - dt > answertimeout) {
                    if (err != null) {
                        throw new ExRequestError(ERR_ANSW_PARSE, err);
                    } else {
                        throw new ExTimeout("Истекло время получения ответа на запрос!");
                    }
                }
                CommonTools.safeInterruptedSleep(10); // Если нет пакетов - ожидаем.

            } else {
                try {
                    int len = ioBuffer.flip().length(); // После этого окно равно полученному пакету.
                    if (len < 4) {
                        throw new ExRequestError(ERR_ANSW_PARSE, "Длина датаграммы меньше 4 байт! {len=%d}", len);
                    }
                    int msglen = ioBuffer.getInt2();
                    int msgcrc = ioBuffer.getInt2();

                    // Проверяем длину сообщения.
                    if (msglen != len - 4) {
                        throw new ExRequestError(ERR_ANSW_PARSE, "Длина сообщения не совпадает с длиной в сообщении! {len=%d-4 msglen=%d}", len, msglen);
                    }
                    // Проверяем контрольную сумму.
                    int crc = crc16.calculate(ioBuffer, 4, len - 4);
                    if (msgcrc != crc) {
                        throw new ExRequestError(ERR_ANSW_PARSE, "Не совпадает контрольная сумма! [crc=0x%04X msgcrc=0x%04X}", crc, msgcrc);
                    }

                    // Если сообщение не битое - парсим метаданные!
                    Meta mm = new Meta();
                    mm.parseAnswer(ioBuffer.tail()); // Окно от тек.позиции и до конца данных.

                    logger.infof("Получено от %s {meta={%s} datahex=%s}",
                            client.toString(), mm.toString(), ioBuffer.getHexAt(ioBuffer.pos(), ioBuffer.remaining()));

                    // Сравниваем поля запроса и ответа - должны совпадать!
                    if (mm.senderID != meta.senderID) {
                        throw new ExRequestError(ERR_ANSW_PARSE, "Не совпадает запрос и ответ - senderID!");
                    }
                    if (mm.messageID != meta.messageID) {
                        throw new ExRequestError(ERR_ANSW_PARSE, "Не совпадает запрос и ответ - messageID!");
                    }
                    if (mm.requestType != meta.requestType) {
                        throw new ExRequestError(ERR_ANSW_PARSE, "Не совпадает запрос и ответ - requestType!");
                    }
                    if (mm.commandID != meta.commandID) {
                        throw new ExRequestError(ERR_ANSW_PARSE, "Не совпадает запрос и ответ - commandID!");
                    }
                    meta.finalizationID = mm.finalizationID;
                    meta.answerErrorID = mm.answerErrorID;
                    meta.answerErrorMessage = mm.answerErrorMessage;

                    // Обрабатываем команду.
                    int datasize = ioBuffer.tail().length();
                    body.reset();
                    if (datasize > 0) body.putArea(ioBuffer);
                    body.flip();

                } catch (ExRequestError ex) {
                    logger.errorf("Неверный формат сообщения - %s!", ExError.exMsg(ex));
                    //throw ex;
                    err = String.format("Неверный формат сообщения - %s!", ExError.exMsg(ex));

                } catch (Exception ex) {
                    logger.errorf("Ошибка при разборе сообщения - %s!", ExError.exMsg(ex));
                    //throw new ExRequestError(ERR_ANSW_PARSE, "Неверный формат сообщения - %s!", ExError.exMsg(ex));
                    err = String.format("Ошибка при разборе сообщения - %s!", ExError.exMsg(ex)); //throw ex;
                }
                break;
            }
        }
    }

    /**
     * Исключение выбрасываемое при неверном формате сообщения.
     */
    public static class ExRequestError extends ExError {
        public int errorID;

        public ExRequestError(int errorid, String msg) {
            super(msg);
            errorID = errorid;
        }

        public ExRequestError(int errorid, String fmt, Object... params) {
            super(fmt, params);
            errorID = errorid;
        }
    }

    /**
     * Исключение выбрасываемое при истечении таймаута.
     */
    public static class ExTimeout extends ExError {

        public ExTimeout(String msg) {
            super(msg);
        }

        public ExTimeout(String fmt, Object... params) {
            super(fmt, params);
        }
    }

    // TODO: Возможно будет нужно реализовать команду запроса результата последней команды клиента (для SINGLE режима).
    // TODO: Это даст возможность дополнительно запросить результат позже (при ошибках в начальном запросе).
    // TODO: Команды низкого уровня не реализовывать?! По зрелому размышлению они ни к чему - нигде не будут использоваться.

    public static class ResultGetState extends Meta {
        /** Время последнего запуска сервиса. */
        public long lastStartTime;
        /** Время последнего перезапуска сервиса (после ошибок). */
        public long lastAutoRestartTime;
        /** Время последней остановки сервиса. */
        public long lastStopTime;

        public ResultGetState(Meta src, DataBuffer buffer) {
            super(src);
            lastStartTime = buffer.getLong();
            lastAutoRestartTime = buffer.getLong();
            lastStopTime = buffer.getLong();
        }

        public ResultGetState(ResultGetState src) {
            super(src);
            this.lastStartTime = src.lastStartTime;
            this.lastAutoRestartTime = src.lastAutoRestartTime;
            this.lastStopTime = src.lastStopTime;
        }
    }

    public synchronized ResultGetState remoteGetState(int answertimeout) throws ExRequestError, ExTimeout {
        Meta meta = new Meta();
        meta.senderID = clientID;
        meta.messageID = generateMessageID();
        meta.requestType = RCService.RequestType.GETSTATE;
        request(answertimeout, meta, tmpBuffer.reset().flip());
        return new ResultGetState(meta, tmpBuffer);
    }

    public static class ResultStop extends Meta {
        public ResultStop(Meta src, DataBuffer buffer) {
            super(src);
        }
    }

    public synchronized ResultStop remoteStop(int answertimeout, Integer timeout) throws ExRequestError, ExTimeout {
        Meta meta = new Meta();
        meta.senderID = clientID;
        meta.messageID = generateMessageID();
        meta.requestType = RCService.RequestType.STOP;
        tmpBuffer.reset();
        if (timeout != null) tmpBuffer.putInt(timeout);
        request(answertimeout, meta, tmpBuffer.flip());
        return new ResultStop(meta, tmpBuffer);
    }

    public static class ResultExecute extends Meta {
        public ResultExecute(Meta src) {
            super(src);
        }
    }

    /**
     * Выполнение команды и получение результата в течение таймаута.
     *
     * @param answertimeout  Таймаут ожидания ответов на команды сервиса.
     * @param executetimeout Таймаут ожидания завершения выполнения удалённой команды. Если отрицательный - исполнение
     *                       только при свободной очереди (сам таймаут берется по модулю). Если ноль, то результат не
     *                       запрашивается.
     */
    public synchronized ResultExecute remoteExecute(int answertimeout, int executetimeout, DataBuffer buf)
            throws ExRequestError, ExTimeout {

        long dt = System.currentTimeMillis();

        // Выполнение запроса: EXECUTE.
        Meta meta = new Meta();
        meta.senderID = clientID;
        meta.messageID = generateMessageID();
        meta.requestType = RCService.RequestType.EXECUTE;
        meta.commandID = generateCommandID();
        meta.executeTimeout = executetimeout;
        request(answertimeout, meta, buf.rewind());
        buf.reset().flip();
        if (meta.answerErrorID != RCService.RESULT_OK) {
            return new ResultExecute(meta);
        }
        if (executetimeout != 0) {
            executetimeout = Math.abs(executetimeout); // Берем по модулю - реальный таймаут на исполнение команды.
            // Выполнение запроса: GETRESULT.
            while (true) {
                meta.messageID = generateMessageID();
                meta.requestType = RCService.RequestType.GETRESULT;
                request(answertimeout, meta, buf.reset().flip());
                if (meta.answerErrorID == RCService.RESULT_OK) {
                    break; // Результат получен.
                }
                if (meta.answerErrorID != RCService.RESULT_RESULTNOTREADY) {
                    return new ResultExecute(meta); // Какая-то ошибка помимо "результат не готов".
                }
                if (System.currentTimeMillis() - dt > executetimeout) {
                    return new ResultExecute(meta); // Истекло время получения результата.
                }
                CommonTools.safeInterruptedSleep(30); // Пауза перед повторным запросом результата.
            }

            // Выполнение запроса: FINALIZATION.
            // Даже если он не удастся - не должен влиять на результат (т.к. команда выполнена и результат получен).
            try {
                Meta fmeta = new Meta(meta);
                fmeta.messageID = generateMessageID();
                fmeta.requestType = RCService.RequestType.FINALIZE;
                request(answertimeout, fmeta, tmpBuffer.reset().flip());
                if (fmeta.answerErrorID == RCService.RESULT_COMMANDNOTFOUND) {
                    fmeta.answerErrorID = RCService.RESULT_OK;
                }
            } catch (Exception ignore) {
            }
        }
        return new ResultExecute(meta);
    }

    /** Исключение при возврате кода ошибки в ответе на запрос. */
    public static class ExAnswerError extends ExError {
        public int errorID;

        public ExAnswerError(int errorid, String msg) {
            super(msg);
            errorID = errorid;
        }

        public ExAnswerError(int errorid, String fmt, Object... params) {
            super(fmt, params);
            errorID = errorid;
        }
    }

    /** Исключение при наличии кода ошибки в результате исполнения команды. */
    public static class ExSBError extends ExError {
        public int errorID;

        public ExSBError(int errorid, String msg) {
            super(msg);
            errorID = errorid;
        }

        public ExSBError(int errorid, String fmt, Object... params) {
            super(fmt, params);
            errorID = errorid;
        }
    }

}
