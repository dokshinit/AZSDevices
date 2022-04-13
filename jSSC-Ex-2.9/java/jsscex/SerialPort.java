/*
 * jSSCEx (Java Simple Serial Connector Extended). Based on jSSC v2.8.0.
 * Modified 2016 by Aleksey Nikolaevich Dokshin.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 *
 * [+] Убран лишний функционал.
 * [+] Переделаны функции чтения-записи под нужды приложения.
 * [+] Доработана инициализация библиотеки.
 * [+] Доработаны нативные библиотеки.
 *
 * =====================================================================================================================
 * jSSC (Java Simple Serial Connector) - serial port communication library.
 * © Alexey Sokolov (scream3r), 2010-2014.
 *
 * This file is part of jSSC.
 *
 * jSSC is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * jSSC is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with jSSC.  If not, see <http://www.gnu.org/licenses/>.
 *
 * If you use jSSC in public project you can inform me about this by e-mail,
 * of course if you want it.
 *
 * e-mail: scream3r.org@gmail.com
 * web-site: http://scream3r.org | http://code.google.com/p/java-simple-serial-connector/
 */

package jsscex;

import util.CommonTools;

/**
 * Реализация последовательного порта.
 */
public class SerialPort {

    private long portHandle;
    private String portName;
    private boolean portOpened = false;

    // Константы...
    public static final int BAUDRATE_110 = 110;
    public static final int BAUDRATE_300 = 300;
    public static final int BAUDRATE_600 = 600;
    public static final int BAUDRATE_1200 = 1200;
    public static final int BAUDRATE_4800 = 4800;
    public static final int BAUDRATE_9600 = 9600;
    public static final int BAUDRATE_14400 = 14400;
    public static final int BAUDRATE_19200 = 19200;
    public static final int BAUDRATE_38400 = 38400;
    public static final int BAUDRATE_57600 = 57600;
    public static final int BAUDRATE_115200 = 115200;
    public static final int BAUDRATE_128000 = 128000;
    public static final int BAUDRATE_256000 = 256000;

    public static final int DATABITS_5 = 5;
    public static final int DATABITS_6 = 6;
    public static final int DATABITS_7 = 7;
    public static final int DATABITS_8 = 8;

    // DANT: Привел с общему знаменателю (как они передаются в нативную библиотеку!).
    public static final int STOPBITS_1 = 0;
    public static final int STOPBITS_1_5 = 1;
    public static final int STOPBITS_2 = 2;

    public static final int PARITY_NONE = 0;
    public static final int PARITY_ODD = 1;
    public static final int PARITY_EVEN = 2;
    public static final int PARITY_MARK = 3;
    public static final int PARITY_SPACE = 4;

    public static final int PURGE_RXABORT = 0x0002;
    public static final int PURGE_RXCLEAR = 0x0008;
    public static final int PURGE_TXABORT = 0x0001;
    public static final int PURGE_TXCLEAR = 0x0004;

    public static final int FLOWCONTROL_NONE = 0;
    public static final int FLOWCONTROL_RTSCTS_IN = 1;
    public static final int FLOWCONTROL_RTSCTS_OUT = 2;
    public static final int FLOWCONTROL_XONXOFF_IN = 4;
    public static final int FLOWCONTROL_XONXOFF_OUT = 8;

    // Добавлены для унификации состояния линий (как битовый набор в int).
    public static final int LINESSTATUS_CTS = 1;
    public static final int LINESSTATUS_DSR = 2;
    public static final int LINESSTATUS_RING = 4;
    public static final int LINESSTATUS_RSLD = 8;

    public static final int ERROR_FRAME = 0x0008;
    public static final int ERROR_OVERRUN = 0x0002;
    public static final int ERROR_PARITY = 0x0004;

    private static final int PARAMS_FLAG_IGNPAR = 1;
    private static final int PARAMS_FLAG_PARMRK = 2;

    /**
     * Конструктор.
     *
     * @param portName Имя порта.
     */
    public SerialPort(String portName) {
        this.portName = portName;
    }

    /**
     * Получение имени порта.
     *
     * @return Имя порта.
     */
    public String getPortName() {
        return portName;
    }

    /**
     * Получение состояния открытости порта.
     *
     * @return Флаг открытости порта: true - открыт, false - закрыт.
     */
    public boolean isOpened() {
        return portOpened;
    }

    /**
     * Проверка открытости порта. Если не открыт - выбрасывается исключение.
     *
     * @param infomsg Сообщение для лога (например - название точки проверки).
     * @throws PortNotOpenedException
     */
    private void exIfPortNotOpened(String infomsg) throws PortNotOpenedException {
        if (!portOpened) throw new PortNotOpenedException("Порт '%s' не открыт! [%s]", portName, infomsg);
    }

    /**
     * Проверка boolean значения. Если false - выбрасывается исключение.
     *
     * @param result  Проверяемое значение.
     * @param infomsg Сообщение для лога (например - название точки проверки).
     * @throws FaultNativeException
     */
    private void exIfFalse(boolean result, String infomsg) throws FaultNativeException {
        if (!result) throw new FaultNativeException("Ошибка операции с портом '%s'! [%s]", portName, infomsg);
    }

    /**
     * Проверка int значения. Если = -1 - выбрасывается исключение.
     *
     * @param result  Проверяемое значение.
     * @param infomsg Сообщение для лога (например - название точки проверки).
     * @throws FaultNativeException
     */
    private int exIfNegOne(int result, String infomsg) throws FaultNativeException {
        if (result == -1) throw new FaultNativeException("Ошибка операции с портом '%s'! [%s]", portName, infomsg);
        return result;
    }

    /**
     * Открытие порта. Вид ошибки открытия порта - в типе выбрасываемого исключения.
     *
     * @throws PortOpeningException
     */
    public synchronized void openPort() throws PortOpeningException {
        if (portOpened)
            throw new PortOpeningException(PortOpeningException.ERR_PORT_ALREADY_OPENED, "Порт '%s' уже открыт!", portName);
        if (portName == null)
            throw new PortOpeningException(PortOpeningException.ERR_NULL_PORT_NAME, "Не задано имя порта!");
        // Если ключ в любом регистре отсутствует, то значит TIOCEXCL не используется.
        boolean useTIOCEXCL =
                (System.getProperty(SerialNativeInterface.PROPERTY_JSSC_NO_TIOCEXCL) == null &&
                        System.getProperty(SerialNativeInterface.PROPERTY_JSSC_NO_TIOCEXCL.toLowerCase()) == null);
        portHandle = SerialNativeInterface.openPort(portName, useTIOCEXCL); //since 2.3.0 -> (if JSSC_NO_TIOCEXCL defined, exclusive lock for serial port will be disabled)
        if (portHandle == SerialNativeInterface.ERR_PORT_BUSY) {
            throw new PortOpeningException(PortOpeningException.ERR_PORT_BUSY, "Порт '%s' занят!", portName);
        } else if (portHandle == SerialNativeInterface.ERR_PORT_NOT_FOUND) {
            throw new PortOpeningException(PortOpeningException.ERR_PORT_NOT_FOUND, "Порт '%s' не найден!", portName);
        } else if (portHandle == SerialNativeInterface.ERR_PERMISSION_DENIED) {
            throw new PortOpeningException(PortOpeningException.ERR_PERMISSION_DENIED, "Нет прав доступа к порту '%s'!", portName);
        } else if (portHandle == SerialNativeInterface.ERR_INCORRECT_SERIAL_PORT) {
            throw new PortOpeningException(PortOpeningException.ERR_INCORRECT_SERIAL_PORT, "Неверный последовательный порт '%s'!", portName);
        } else if (portHandle == SerialNativeInterface.ERR_PORT_NOT_OPENED) {
            throw new PortOpeningException(PortOpeningException.ERR_PORT_NOT_OPENED, "Порт не открыт (прочие ошибки) '%s'!", portName);
        }
        portOpened = true;
    }

    /**
     * Установка параметров порта.
     *
     * @param baudRate Битрейт.
     * @param dataBits Биты данных.
     * @param stopBits Стоповые биты.
     * @param parity   Биты четности.
     * @param setRTS   Стартовое состояние RTS линии (ON/OFF).
     * @param setDTR   Стартовое состояние DTR линии (ON/OFF).
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized void setParams(int baudRate, int dataBits, int stopBits, int parity, boolean setRTS, boolean setDTR)
            throws PortNotOpenedException, FaultNativeException {
        exIfPortNotOpened("setParams()");
        int flags = 0;
        if (System.getProperty(SerialNativeInterface.PROPERTY_JSSC_IGNPAR) != null ||
                System.getProperty(SerialNativeInterface.PROPERTY_JSSC_IGNPAR.toLowerCase()) != null) {
            flags |= PARAMS_FLAG_IGNPAR;
        }
        if (System.getProperty(SerialNativeInterface.PROPERTY_JSSC_PARMRK) != null ||
                System.getProperty(SerialNativeInterface.PROPERTY_JSSC_PARMRK.toLowerCase()) != null) {
            flags |= PARAMS_FLAG_PARMRK;
        }
        exIfFalse(SerialNativeInterface.setParams(portHandle, baudRate, dataBits, stopBits, parity, setRTS, setDTR, flags), "setParams()");
    }

    /**
     * Установка параметров порта (RTS & DTR = ON).
     *
     * @param baudRate Битрейт.
     * @param dataBits Биты данных.
     * @param stopBits Стоповые биты.
     * @param parity   Биты четности.
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized void setParams(int baudRate, int dataBits, int stopBits, int parity)
            throws PortNotOpenedException, FaultNativeException {
        setParams(baudRate, dataBits, stopBits, parity, true, true);
    }

    /**
     * Выполнение операции освобождения порта. Некторые устройства могут не поддерживать эту функцию!
     *
     * @param flags Вид операции: PURGE_RXCLEAR - очистка входного буфера, PURGE_TXCLEAR - очистка выходного буфера,
     *              PURGE_RXABORT - немедленное прерывание всех операций чтения порта (игнорируется в linux),
     *              PURGE_TXABORT - немедленное прерывание всех операций записи в порт (игнорируется в linux). Можно
     *              комбириновать флаги!
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized void purgePort(int flags) throws PortNotOpenedException, FaultNativeException {
        exIfPortNotOpened("purgePort()");
        exIfFalse(SerialNativeInterface.purgePort(portHandle, flags), "purgePort()");
    }

    /**
     * Очистка входного и выходного буферов с прерыванием операций чтения\записи. Некторые устройства могут не
     * поддерживать эту функцию!
     *
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized void purgePort() throws PortNotOpenedException, FaultNativeException {
        purgePort(PURGE_RXABORT | PURGE_RXCLEAR | PURGE_TXABORT | PURGE_TXCLEAR);
    }

    /**
     * Закрытие порта. Сначала удаляет слушателей.
     *
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     * @throws PortOpeningException
     */
    public synchronized void closePort() throws PortNotOpenedException, FaultNativeException {
        exIfPortNotOpened("closePort()");
        exIfFalse(SerialNativeInterface.closePort(portHandle), "closePort()");
        portOpened = false;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //  СОСТОЯНИЕ ПОРТА
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * Установка состояния RTS линии.
     *
     * @param enabled Новое состояние.
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized void setRTS(boolean enabled) throws PortNotOpenedException, FaultNativeException {
        exIfPortNotOpened("setRTS()");
        exIfFalse(SerialNativeInterface.setRTS(portHandle, enabled), "setRTS()");
    }

    /**
     * Установка состояния DTR линии.
     *
     * @param enabled Новое состояние.
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized void setDTR(boolean enabled) throws PortNotOpenedException, FaultNativeException {
        exIfPortNotOpened("setDTR()");
        exIfFalse(SerialNativeInterface.setDTR(portHandle, enabled), "setDTR()");
    }

    /**
     * Установка режима контроля потока.
     *
     * @param mask Режим контроля потока: FLOWCONTROL_XXX. Можно комбинировать значения.
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized void setFlowControlMode(int mask) throws PortNotOpenedException, FaultNativeException {
        exIfPortNotOpened("setFlowControlMode()");
        exIfFalse(SerialNativeInterface.setFlowControlMode(portHandle, mask), "setFlowControlMode()");
    }

    /**
     * Получение режима контроля потока.
     *
     * @return Режим контроля потока.
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized int getFlowControlMode() throws PortNotOpenedException, FaultNativeException {
        exIfPortNotOpened("getFlowControlMode()");
        return exIfNegOne(SerialNativeInterface.getFlowControlMode(portHandle), "getFlowControlMode()");
    }

    /**
     * Посылка сигнала прерывания в течение заданного времени.
     *
     * @param duration Время посылки сигнала в миллисекундах.
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized void sendBreak(int duration) throws PortNotOpenedException, FaultNativeException {
        exIfPortNotOpened("sendBreak()");
        exIfFalse(SerialNativeInterface.sendBreak(portHandle, duration), "sendBreak()");
    }

    /**
     * Получение состояний линий.
     *
     * @return Состояние линии: LINESSTATUS_XXX. Биты отвечают за соответствующие маске состояния.
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized int getLinesStatus() throws PortNotOpenedException, FaultNativeException {
        exIfPortNotOpened("getLinesStatus()");
        return exIfNegOne(SerialNativeInterface.getLinesStatus(portHandle), "getLinesStatus()");
    }

    /**
     * Получение состояния линии CTS.
     *
     * @return Состояние линии.
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized boolean isCTS() throws PortNotOpenedException, FaultNativeException {
        return (getLinesStatus() & LINESSTATUS_CTS) != 0;
    }

    /**
     * Получение состояния линии DSR.
     *
     * @return Состояние линии.
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized boolean isDSR() throws PortNotOpenedException, FaultNativeException {
        return (getLinesStatus() & LINESSTATUS_DSR) != 0;
    }

    /**
     * Получение состояния линии RING.
     *
     * @return Состояние линии.
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized boolean isRING() throws PortNotOpenedException, FaultNativeException {
        return (getLinesStatus() & LINESSTATUS_RING) != 0;
    }

    /**
     * Получение состояния линии RLSD.
     *
     * @return Состояние линии.
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized boolean isRLSD() throws PortNotOpenedException, FaultNativeException {
        return (getLinesStatus() & LINESSTATUS_RSLD) != 0;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //  ОПЕРАЦИИ С ДАННЫМИ
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * Неблокирующее чтение данных из порта в заданный участок массива. Чтение происходит за одно обращение, ожидания
     * чтения всех данных не происходит! Если в приёмном буфере данных нет - возвращается ноль.
     *
     * @param buffer Буфер.
     * @param index  Начало в буфере области для считываемых данных.
     * @param length Длина области для считываемых данных (максимальное кол-во считываемых байтов).
     * @return Возвращает кол-во считанных байт (>=0).
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized int readBytes(byte[] buffer, int index, int length) throws PortNotOpenedException, FaultNativeException {
        exIfPortNotOpened("readBytes()");
        return exIfNegOne(SerialNativeInterface.readBytes(portHandle, buffer, index, length), "readBytes()");
    }

    /**
     * Неблокирующее чтение одного байта из порта. Чтение происходит за одно обращение, ожидания чтения всех данных не
     * происходит! Если в приёмном буфере данных нет - возвращается -1.
     *
     * @return Значение считанного байта (0-255) или -1 в случае отсутствия данных.
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized int readByte() throws PortNotOpenedException, FaultNativeException {
        exIfPortNotOpened("readByte()");
        int sz = exIfNegOne(SerialNativeInterface.readByte(portHandle), "readByte()");
        return sz == -2 ? -1 : sz; // Если не байт не считан - возвращаем -1.
    }

    /**
     * Неблокирующая запись в порт заданного участка массива. Запись происходит за одно обращение, ожидания записи всех
     * данных не происходит! Если произошла ошибка записи - возвращается -1.
     *
     * @param buffer Буфер.
     * @param index  Начало в буфере области с записываемыми данными.
     * @param length Длина области записываемых данных (максимальное кол-во записываемых байтов).
     * @return Возвращает кол-во записанных байт (>=0).
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized int writeBytes(byte[] buffer, int index, int length) throws PortNotOpenedException, FaultNativeException {
        exIfPortNotOpened("writeBytes()");
        return exIfNegOne(SerialNativeInterface.writeBytes(portHandle, buffer, index, length), "writeBytes()");
    }

    /**
     * Неблокирующая запись в порт одного байта. Запись происходит за одно обращение.
     *
     * @param value Значение записываемого байта.
     * @return Кол-во записанных байт (0 или 1).
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized int writeByte(int value) throws PortNotOpenedException, FaultNativeException {
        exIfPortNotOpened("writeByte()");
        return exIfNegOne(SerialNativeInterface.writeByte(portHandle, value), "writeByte()");
    }

    /**
     * Получение кол-ва байт доступных для чтения в буфере чтения порта.
     *
     * @return Кол-во байт, доступных для чтения (>=0).
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized int getInputBufferBytesCount() throws PortNotOpenedException, FaultNativeException {
        exIfPortNotOpened("getInputBufferBytesCount()");
        return exIfNegOne(SerialNativeInterface.getInputBufferBytesCount(portHandle), "getInputBufferBytesCount()");
    }

    /**
     * Получение кол-ва байт ожидающих отправки в буфере записи порта.
     *
     * @return Кол-во байт, ожидающих записи (>=0).
     * @throws PortNotOpenedException
     * @throws FaultNativeException
     */
    public synchronized int getOutputBufferBytesCount() throws PortNotOpenedException, FaultNativeException {
        exIfPortNotOpened("getOutputBufferBytesCount()");
        return exIfNegOne(SerialNativeInterface.getOutputBufferBytesCount(portHandle), "getOutputBufferBytesCount()");
    }

    /**
     * Проверка работоспособности порта.
     *
     * @return Результат проверки: 0 - порт работоспособный, иначе код ошибки (-1 или код ошибки операции).
     */
    public synchronized int checkPort() {
        if (!isOpened()) return -1;
        return SerialNativeInterface.checkPort(portHandle, portName);
    }


    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //  ИСКЛЮЧЕНИЯ
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /** Исключение при попытке совершении операции при закрытом порте. */
    public static class PortNotOpenedException extends Exception {

        public PortNotOpenedException(String fmt, Object... args) {
            super(args == null ? fmt : String.format(fmt, args));
        }
    }

    /** Исключение при ошибке выполнения операции в нативном коде. */
    public static class FaultNativeException extends Exception {

        public FaultNativeException(String fmt, Object... args) {
            super(args == null ? fmt : String.format(fmt, args));
        }
    }

    /** Исключение при ошибке открытия порта. */
    public static class PortOpeningException extends Exception {

        public static final int ERR_PORT_ALREADY_OPENED = 1;
        public static final int ERR_NULL_PORT_NAME = 2;
        public static final int ERR_PORT_BUSY = 3;
        public static final int ERR_PORT_NOT_FOUND = 4;
        public static final int ERR_PERMISSION_DENIED = 5;
        public static final int ERR_INCORRECT_SERIAL_PORT = 6;
        public static final int ERR_PORT_NOT_OPENED = 7;

        public final int errorID;

        public PortOpeningException(int errorid, String fmt, Object... args) {
            super(args == null ? fmt : String.format(fmt, args));
            this.errorID = errorid;
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //  ТЕСТЫ
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    static void test1() {
        SerialPort drv = new SerialPort("/dev/ttyS9");
        try {
            while (true) {
                if (!drv.isOpened()) { // Если порт закрыт - пробуем открыть.
                    try {
                        System.out.println("Device connecting...");
                        drv.openPort();
                        drv.setParams(115200, DATABITS_8, STOPBITS_1, PARITY_NONE);
                        System.out.println("Device connected!");
                        CommonTools.safeInterruptedSleep(500); // Пауза до первой проверки открытого порта.
                    } catch (Exception ex) {
                        System.out.println("Device connection ERROR! " + ex.getMessage());
                        CommonTools.safeInterruptedSleep(500); // Пауза до следующей попытки открыть порт.
                    }
                } else { // Если порт окрыт - проверяем потерю связи.
                    if (drv.checkPort() != 0) {
                        try {
                            System.out.println("Device disconnecting...");
                            drv.closePort();
                            System.out.println("Device disconnected!");
                        } catch (Exception exx) {
                            System.out.println("Device disconnect ERROR! " + exx.toString());
                        }
                    } else {
                        CommonTools.safeInterruptedSleep(500); // Пауза до следующей проверки порта.
                    }
                }
            }
        } catch (Exception ex) {
            System.out.println("ОШИБКА РЕГЕНЕРАТОРА! " + ex.toString());
        }
        System.out.println("Device regenerator off!");
    }


    public static void main(String[] args) {
        test1();
    }
}
