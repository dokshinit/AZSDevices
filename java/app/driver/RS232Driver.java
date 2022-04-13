/*
 * Copyright (c) 2016. Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */

package app.driver;

import app.ExError;
import app.LoggerExt;
import jsscex.SerialPort;
import util.CommonTools;

import java.io.Closeable;

/**
 * Драйвер для работы с RS232 портом ориентированный на использование переработанной библиотеки JSSC v2.9.
 * <p>
 * ВАЖНО! Проверка дисконнекта производится специализированной нативной функцией!
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
public class RS232Driver implements Closeable {

    /** Вывод отладочной информации. */
    private final LoggerExt logger;
    /** RS232 порт. */
    private SerialPort port;

    /** Наименование устройства (для удобства и логов). */
    private final String devname;
    /** Наименоавание порта: COM1-X для Windows, /dev/ttyUSB1-X для Linux. */
    private final String portname;
    /** Скорость (битрейт) порта (бит\сек). */
    private int bitrate;
    /** Биты данных. */
    private int databits;
    /** Стоповые биты. */
    private int stopbits;
    /** Биты четности. */
    private int parity;

    /** Таймаут ожидания первого байта при чтении (мс). */
    private int timeout;
    /** Контрольная сумма (изменяется при каждом чтении или записи (XOR)). */
    private int xor;

    /** Включение логирования (в т.ч. в файл). */
    public void enableLogger(boolean isEnable) {
        logger.setConsoleFormatter();
        logger.enable(isEnable).toFile();
    }

    /** Конструктор. */
    public RS232Driver(String devname, String portname) {
        this.logger = LoggerExt.getNewLogger("RS232-" + devname);
        this.devname = devname;
        this.portname = portname;
        this.bitrate = 19200;
        this.databits = SerialPort.DATABITS_8;
        this.stopbits = SerialPort.STOPBITS_1;
        this.parity = SerialPort.PARITY_NONE;
        this.timeout = 100; // Время ожидания первого байта (при приёме) (по умолчанию).
        this.port = new SerialPort(portname);
    }

    /** Установка битрейта. */
    public RS232Driver bitrate(int bitrate) {
        this.bitrate = bitrate;
        return this;
    }

    /** Установка режима битов данных (SerialPort.DATABITS_8). */
    public RS232Driver databits(int databits) {
        this.databits = databits;
        return this;
    }

    /** Установка режима стоповых бит (SerialPort.STOPBITS_1). */
    public RS232Driver stopbits(int stopbits) {
        this.stopbits = stopbits;
        return this;
    }

    /** Установка режима контроля четности (SerialPort.PARITY_NONE). */
    public RS232Driver parity(int parity) {
        this.parity = parity;
        return this;
    }

    /** Установка таймаута ожидания первого байта при чтении. */
    public RS232Driver timeout(int timeout) {
        this.timeout = timeout;
        return this;
    }

    /** Получение наименования устройства. */
    public String getDevName() {
        return devname;
    }

    /** Получение наименования порта. */
    public String getPortName() {
        return portname;
    }

    /** Получение битрейта. */
    public int getBitrate() {
        return bitrate;
    }

    /** Получение таймаута ожидания первого байта при чтении. */
    public int getTimeout() {
        return timeout;
    }

    /** Очистка значение контрольной суммы (XOR). */
    public void clearXOR() {
        xor = 0;
    }

    /** Получение текущего значения контрольной суммы (XOR). */
    public int getXOR() {
        return xor;
    }

    /** Регистрация (отражение) байта данных в контрольной сумме. */
    private void xor(int value) {
        xor = (xor ^ (value & 0xFF)) & 0xFF;
    }

    /**
     * Открытие порта для связи.
     *
     * @return Возвращает ссылку на себя для возможности создания цепочки вызовов.
     * @throws ExDevice Исключение при ошибке открытия порта.
     */
    public synchronized RS232Driver open() throws ExDevice {
        if (!isClosed()) close();
        logger.info("Открытие порта...");
        try {
            port.openPort(); // Не проверяем возвращаемое значение т.к. по коду или true или исключение!
        } catch (SerialPort.PortOpeningException ex) {
            logger.errorf("Ошибка при откытии порта - %s!", ExError.exMsg(ex));
            close();
            throw new ExDevice(ex);
        }
        try {
            port.setParams(bitrate, databits, stopbits, parity);
        } catch (Exception ex) {
            logger.errorf("Ошибка при установке параметров порта - %s!", ExError.exMsg(ex));
            close();
            throw new ExDevice(ExDevice.OPERATION_FAULT, "Ошибка установки параметров порта!");
        }
        logger.infof("Порт успешно открыт {bitrate=%d databit=%d stopbit=%d paritybit=%d}", bitrate, databits, stopbits, parity);
        return this;
    }

    /** Закрытие порта. */
    @Override
    public synchronized void close() {
        logger.info("Закрытие порта...");
        try {
            if (port.isOpened()) port.closePort();
            logger.info("Порт успешно закртыт.");
        } catch (Exception e) {
            logger.errorf("Ошибка при закрытии порта - %s!", ExError.exMsg(e));
        }
    }

    /**
     * Проверка программного закрытия порта. При этом фактическая работоспособность порта НЕ ПРОВЕРЯЕТСЯ!
     *
     * @return Флаг закрытия: true - порт закрыт, false - открыт.
     */
    public synchronized boolean isClosed() {
        return !port.isOpened();
    }

    /**
     * Проверка дисконнекта устройства. Тестирование доступности связи с устройством путём совершения операции проверки
     * наличия данных во входном потоке. Если операция не может быть выполнена - значит устройство отключено (или
     * проблемы со связью).
     *
     * @return Флаг дисконнекта: true - связи нет (устройство отключено), false - связь есть.
     */
    public synchronized boolean checkDisconnect() {
        if (isClosed()) return true;
        if (port.checkPort() != 0) return true;
        return false; // Если операция проверки данных выполняется без ошибок - значит устройство в наличии.
    }

    public static final int REG_OK = 0;
    public static final int REG_DISCONNECTED = 1;
    public static final int REG_OPENED = 2;
    public static final int REG_NOTOPENED = 3;

    /**
     * Регенерация связи с устройством. Открытие порта в случае его закрытия или закрытие в случае дисконнекта.
     *
     * @return Код результата.
     */
    public synchronized int regenerate() {
        // Если порт закрыт - пробуем открыть.
        if (isClosed()) {
            try {
                open();
                return REG_OPENED;
            } catch (Exception ex) {
                return REG_NOTOPENED;
            }
        } else {
            // Если порт открыт - проверяем потерю связи.
            if (checkDisconnect()) {
                close(); // Связь потеряна - закрываем порт!
                return REG_DISCONNECTED;
            } else {
                return REG_OK;
            }
        }
    }


    /**
     * Чтение одного байта из порта.
     *
     * @param timeout Таймаут ожидания первого байта в миллисекундах.
     * @return Считанное значение (-1 - ошибка).
     * @throws ExTimeout    Таймаут ожидания истёк.
     * @throws ExDevice     Ошибка устройства.
     * @throws ExDisconnect Отсутствие связи с устройством.
     */
    public synchronized int read(int timeout) throws ExTimeout, ExDevice, ExDisconnect {
        if (timeout < this.timeout) timeout = this.timeout;
        if (isClosed()) throw new ExDisconnect();
        try {
            long time = System.currentTimeMillis();
            while (System.currentTimeMillis() - time <= timeout) {
                if (port.getInputBufferBytesCount() > 0) {
                    int value = port.readByte();
                    if (value >= 0) {
                        xor(value);
                        logger.infof("<- %02X", value);
                        return value;
                    }
                }
                CommonTools.safeInterruptedSleep(1);
            }
        } catch (SerialPort.PortNotOpenedException ex) {
            throw new ExDisconnect();
        } catch (SerialPort.FaultNativeException ex) {
            if (checkDisconnect()) throw new ExDisconnect();
            throw new ExDevice(ExDevice.OPERATION_FAULT, ex.getMessage());
        }
        throw new ExTimeout();
    }

    /**
     * Чтение одного байта из порта с таймаутом по умолчанию.
     *
     * @return Значение считанного байта.
     * @throws ExTimeout    Таймаут ожидания истёк.
     * @throws ExDevice     Ошибка устройства.
     * @throws ExDisconnect Отсутствие связи с устройством.
     */
    public synchronized int read() throws ExTimeout, ExDevice, ExDisconnect {
        return read(timeout);
    }

    /**
     * Запись одного байта в порт.
     *
     * @param value Значение для записи.
     * @throws ExDevice     Ошибка устройства.
     * @throws ExDisconnect Отсутствие связи с устройством.
     */
    public synchronized void write(int value) throws ExDevice, ExDisconnect {
        if (isClosed()) throw new ExDisconnect();
        try {
            value = value & 0xFF;
            if (port.writeByte(value) != 1)
                throw new SerialPort.FaultNativeException("Байт не записан!"); // Например переполнен буфер!
            xor(value);
            logger.infof("-> %02X", value);
        } catch (SerialPort.PortNotOpenedException ex) {
            throw new ExDisconnect();
        } catch (SerialPort.FaultNativeException ex) {
            if (checkDisconnect()) throw new ExDisconnect();
            throw new ExDevice(ExDevice.OPERATION_FAULT, ex.getMessage());
        }
    }

    /**
     * Запись значения XOR в порт (один байт).
     *
     * @throws ExDevice     Ошибка устройства.
     * @throws ExDisconnect Отсутствие связи с устройством.
     */
    public synchronized void writeXOR() throws ExDevice, ExDisconnect {
        write(xor);
    }

    /**
     * Очистка буфера чтения (безопасная) от возможного остаточного "мусора".
     *
     * @return Количество удаленных байт.
     */
    public synchronized int safeClearRead() {
        if (isClosed()) return 0;
        try {
            int count = port.getInputBufferBytesCount();
            if (count > 0) {
                port.purgePort(SerialPort.PURGE_RXCLEAR | SerialPort.PURGE_RXABORT);
                logger.infof("<- %02d bytes purged (read)!", count);
            } else {
                count = 0;
            }
            return count;
        } catch (Exception ex) {
            return 0;
        }
    }

    /**
     * Очистка буфера записи (безопасная) от возможного остаточного "мусора".
     *
     * @return Количество удаленных байт.
     */
    public synchronized int safeClearWrite() {
        if (isClosed()) return 0;
        try {
            int count = port.getOutputBufferBytesCount();
            if (count > 0) {
                port.purgePort(SerialPort.PURGE_TXCLEAR | SerialPort.PURGE_TXABORT);
                logger.infof("<- %02d bytes purged (write)!", count);
            } else {
                count = 0;
            }
            return count;
        } catch (Exception ex) {
            return 0;
        }
    }

    /**
     * Исключение при ошибках операций с устройством. Анонимизирует реализацию устройства (коды ошибок драйвера
     * устройства).
     */
    public static class ExDevice extends ExError {

        /** Ошибки при открытии порта. */
        public static final int PORT_ALREADY_OPENED = SerialPort.PortOpeningException.ERR_PORT_ALREADY_OPENED;
        public static final int NULL_PORT_NAME = SerialPort.PortOpeningException.ERR_NULL_PORT_NAME;
        public static final int PORT_BUSY = SerialPort.PortOpeningException.ERR_PORT_BUSY;
        public static final int PORT_NOT_FOUND = SerialPort.PortOpeningException.ERR_PORT_NOT_FOUND;
        public static final int PERMISSION_DENIED = SerialPort.PortOpeningException.ERR_PERMISSION_DENIED;
        public static final int INCORRECT_SERIAL_PORT = SerialPort.PortOpeningException.ERR_INCORRECT_SERIAL_PORT;
        /** Общая ошибка совершения операции. */
        public static final int OPERATION_FAULT = 100;

        /** Код ошибки. */
        public int errorID;

        /**
         * Конструктор.
         *
         * @param errorid Код ошибки.
         * @param fmt     Форматная строка.
         * @param params  Параметры-значения для форматной строки.
         */
        public ExDevice(int errorid, String fmt, Object... params) {
            super(fmt, params);
            this.errorID = errorid;
        }

        /**
         * Конструктор с инициализацией по исключению.
         *
         * @param ex Исключение из которого берутся код ошибки и текст сообщения.
         */
        public ExDevice(SerialPort.PortOpeningException ex) {
            this(ex.errorID, ex.getMessage());
        }

        @Override
        public String getMessage() {
            return String.format("erroID=%d, msg=%s", errorID, super.getMessage());
        }
    }

    /** Исключение при истечении таймаута ожидании данных при чтении из устройства. */
    public static class ExTimeout extends ExError {

        /** Конструктор. */
        public ExTimeout() {
            super();
        }

        /**
         * Конструктор.
         *
         * @param fmt    Форматная строка.
         * @param params Параметры-значения для форматной строки.
         */
        public ExTimeout(String fmt, Object... params) {
            super(fmt, params);
        }
    }

    /** Исключение при операциях с отключенным устройством. */
    public static class ExDisconnect extends ExError {

        /** Конструктор. */
        public ExDisconnect() {
            super();
        }

        /**
         * Конструктор.
         *
         * @param fmt    Форматная строка.
         * @param params Параметры-значения для форматной строки.
         */
        public ExDisconnect(String fmt, Object... params) {
            super(fmt, params);
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //  ТЕСТЫ
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * ТЕСТ: Тест открытия порта и проверки ошибок при отключении устройства.
     * <p>
     * Открытие порта, ожидание нажатия Enter, попытка чтения байта, закрытие порта.
     */
    private static void test1() {
        RS232Driver drv = new RS232Driver("tty9", "/dev/ttyS9").bitrate(115200);
        try {
            drv.open();

            System.out.println("Open OK! Unconnect device and press Enter!");
            System.in.read();

            System.out.println("Read for 100ms and Error!");
            int v = drv.read(100);
        } catch (ExDisconnect ex) {
            System.out.println("Device is unplugged!");
        } catch (Exception ex) {
            ex.printStackTrace();
        }
        drv.close();
    }

    /**
     * ТЕСТ: Тест детекции отключения устройства и возобновления коннекта при подключении (суть - регенератор порта).
     * <p>
     * В цикле: открытие порта, при дисконнекте - закрытие порта.
     *
     * @param name Имя устройства. Если не задано, то по умолчанию "/dev/ttyS9".
     */
    private static void test2(String name) {
        if (name == null) name = "/dev/ttyS9";
        RS232Driver drv = new RS232Driver("tty9", name).bitrate(115200);
        drv.enableLogger(true);
        try {
            while (true) {
                if (drv.isClosed()) { // Если порт закрыт - пробуем открыть.
                    try {
                        System.out.println("Device connecting...");
                        drv.open(); // Без потока отслеживания дисконнекта для своевременного закрытия порта!
                        System.out.println("Device connected!");
                        CommonTools.safeInterruptedSleep(500); // Пауза до первой проверки открытого порта.
                    } catch (Exception ex) {
                        System.out.println("Device connection ERROR! " + ex.getMessage());
                        CommonTools.safeInterruptedSleep(500); // Пауза до следующей попытки открыть порт.
                    }
                } else { // Если порт окрыт - проверяем потерю связи.
                    // Проверяем на дисконнект.
                    int res = drv.port.checkPort();
                    if (res != 0) {
                        System.out.printf("Device disconnecting... code[0x%X]\n", res);
                        drv.close(); // Связь потеряна - закрываем порт!
                        System.out.println("Device disconnected!");
                    } else {
                        System.out.println("Device connected...");
                    }
                    CommonTools.safeInterruptedSleep(1000); // Пауза до следующей проверки порта.
                }
            }
        } catch (Exception ex) {
            System.out.println("ОШИБКА РЕГЕНЕРАТОРА! " + ex.toString());
        }
        System.out.println("Device regenerator off!");
        drv.close(); // На всякий случай.
    }

    public static void main(String[] args) {
        test2(args.length > 0 ? args[0] : null);
    }
}
