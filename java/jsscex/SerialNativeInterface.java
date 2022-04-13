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

import java.io.BufferedReader;
import java.io.InputStreamReader;

/**
 * Класс реализующий интерфейс работы с нативными функциями библиотеки.
 */
final class SerialNativeInterface {

    private static final String libVersion = "2.9";

    static final long ERR_PORT_BUSY = -1;
    static final long ERR_PORT_NOT_FOUND = -2;
    static final long ERR_PERMISSION_DENIED = -3;
    static final long ERR_INCORRECT_SERIAL_PORT = -4;
    static final long ERR_PORT_NOT_OPENED = -5;
    static final long ERR_PORT_OPENED = -6; // Ошибка возникающая при проверке порта (если он свободно открывается, хотя и не должен!)

    static final String PROPERTY_JSSC_NO_TIOCEXCL = "JSSC_NO_TIOCEXCL";
    static final String PROPERTY_JSSC_IGNPAR = "JSSC_IGNPAR";
    static final String PROPERTY_JSSC_PARMRK = "JSSC_PARMRK";

    // Инициализация и загрузка нативной библиотеки.
    static {
        String osName = System.getProperty("os.name").toLowerCase();
        String architecture = System.getProperty("os.arch").toLowerCase();
        String fileSeparator = System.getProperty("file.separator");
        String userDir = System.getProperty("user.dir");

        if (osName.startsWith("lin")) {
            osName = "linux";
        } else if (osName.startsWith("win")) {
            osName = "windows";
        } else if (osName.startsWith("sun")) {
            osName = "solaris";
        } else if (osName.startsWith("mac") || osName.startsWith("darwin")) {
            osName = "mac_os_x";
        }

        switch (architecture) {
            case "i386":
            case "i686":
                architecture = "x86";
                break;
            case "amd64":
            case "universal":
                architecture = "x86_64";
                break;
            case "arm":
                String javaLibPath = System.getProperty("java.library.path").toLowerCase();
                String floatStr = "sf";
                if (javaLibPath.contains("gnueabihf") || javaLibPath.contains("armhf")) {
                    floatStr = "hf";
                } else {
                    try {
                        Process readelfProcess = Runtime.getRuntime().exec("readelf -A /proc/self/exe");
                        BufferedReader reader = new BufferedReader(new InputStreamReader(readelfProcess.getInputStream()));
                        String buffer = "";
                        while ((buffer = reader.readLine()) != null && !buffer.isEmpty()) {
                            if (buffer.toLowerCase().contains("Tag_ABI_VFP_args".toLowerCase())) {
                                floatStr = "hf";
                                break;
                            }
                        }
                        reader.close();
                    } catch (Exception ex) {
                        //Do nothing
                    }
                }
                architecture = "arm" + floatStr;
                break;
        }

        // Т.к. библиотека доработана, то делаем приставку к имени для отличия от оригинальной.
        String libName = "jSSC-Ex-" + libVersion + "_" + architecture;
        libName = System.mapLibraryName(libName);
        if (libName.endsWith(".dylib")) libName = libName.replace(".dylib", ".jnilib");

        // Выводим информацию о параметрах библиотеки и предупреждаем, если версии библиотеки и нативного кода не совпадают.
        String lib = userDir + fileSeparator + osName + "_" + libName; // linux_libjSSC-2.8_x86_64.so
        //System.out.println("jSSCEx Loading native library: " + lib); // Для отладки!
        System.load(lib);
        String versionNative = getNativeLibraryVersion();
        if (!libVersion.equals(versionNative)) {
            System.err.println("Warning! jSSCEx Java and Native versions mismatch (Java: " + libVersion + ", Native: " + versionNative + ")");
        } else {
            System.out.println("jSSCEx Versions (Java: " + libVersion + ", Native: " + versionNative + ")");
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //  ОТКРЫТИЕ-КОНФИГУРАЦИЯ-ЗАКРЫТИЕ
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * Получение строки с версией нативной библиотеки.
     *
     * @return Версия нативной библиотеки. Например: "2.9".
     */
    static native String getNativeLibraryVersion();

    /**
     * Открытие порта.
     *
     * @param portName    Имя порта.
     * @param useTIOCEXCL Флаг использования <b>TIOCEXCL</b>. Имеет эффект только для *nix систем!
     * @return Дескриптор порта или отрицательный код ошибки ERR_*.
     */
    static native long openPort(String portName, boolean useTIOCEXCL);

    /**
     * Установка параметров порта.
     *
     * @param handle   Дескриптор порта.
     * @param baudRate Битрейт.
     * @param dataBits Биты данных.
     * @param stopBits Стоповые биты (STOPBITS_1 = 0, STOPBITS_1_5 = 1, STOPBITS_2 = 2).
     * @param parity   Биты четности.
     * @param setRTS   Стартовое состояние RTS линии (ON/OFF).
     * @param setDTR   Стартовое состояние DTR линии (ON/OFF).
     * @param flags    Дополнительные Native флаги. Имеет эффект только для *nix систем.
     * @return Флаг успешного выполнения операции: true - успех, false - ошибка.
     */
    static native boolean setParams(long handle, int baudRate, int dataBits, int stopBits, int parity, boolean setRTS, boolean setDTR, int flags);

    /**
     * Очистка входного и выходного буферов.
     *
     * @param handle Дескриптор порта.
     * @param flags  Вид операции очистки.
     * @return Флаг успешного выполнения операции: true - успех, false - ошибка.
     */
    static native boolean purgePort(long handle, int flags);

    /**
     * Закрытие порта.
     *
     * @param handle Дескриптор порта.
     * @return Флаг успешного выполнения операции: true - успех, false - ошибка.
     */
    static native boolean closePort(long handle);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //  УПРАВЛЕНИЕ ПАРАМЕТРАМИ ПОРТА
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * Получение списка доступных портов.
     *
     * @return Массив строк с именами портов (не сортирован!) или NULL в случае ошибки.
     */
    static native String[] getSerialPortNames();

    /**
     * Установка состояния линии RTS.
     *
     * @param handle Дескриптор порта.
     * @param value  Новое состояние.
     * @return Флаг успешного выполнения операции: true - успех, false - ошибка.
     */
    static native boolean setRTS(long handle, boolean value);

    /**
     * Установка состояния линии DTR.
     *
     * @param handle Дескриптор порта.
     * @param value  Новое состояние.
     * @return Флаг успешного выполнения операции: true - успех, false - ошибка.
     */
    static native boolean setDTR(long handle, boolean value);

    /**
     * Установка режима контроля потока.
     *
     * @param handle Дескриптор порта.
     * @param mask   Режим контроля потока.
     * @return Флаг успешного выполнения операции: true - успех, false - ошибка.
     */
    static native boolean setFlowControlMode(long handle, int mask);

    /**
     * Получение режима контроля потока.
     *
     * @param handle Дескриптор порта.
     * @return Режим контроля потока или -1 при ошибке.
     */
    static native int getFlowControlMode(long handle);

    /**
     * Посылка сигнала прерывания в течение заданного времени.
     *
     * @param handle   Дескриптор порта.
     * @param duration Время посылки сигнала в миллисекундах.
     * @return Флаг успешного выполнения операции: true - успех, false - ошибка.
     */
    static native boolean sendBreak(long handle, int duration);

    /**
     * Получение состояния линий.
     *
     * @param handle Дескриптор порта.
     * @return Состояние линии (биты 1-4) или -1 при ошибке.
     */
    static native int getLinesStatus(long handle);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //  ЧТЕНИЕ\ЗАПИСЬ
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * Неблокирующее чтение данных из порта в заданный участок массива. Чтение происходит за одно обращение, ожидания
     * чтения всех данных не происходит! Если в приёмном буфере данных нет - возвращается ноль, если ошибка -
     * возвращается -1.
     *
     * @param handle Дескриптор порта.
     * @param buffer Буфер.
     * @param index  Смещение начала данных от начала буфера.
     * @param length Максимальная длина считываемых данных.
     * @return Кол-во считанных байт (может быть нулевым) или -1 в случае ошибки чтения.
     */
    static native int readBytes(long handle, byte[] buffer, int index, int length);

    /**
     * Неблокирующее чтение одного байта из порта. Чтение происходит за одно обращение, ожидания чтения всех данных не
     * происходит! Если в приёмном буфере данных нет - возвращается -2, если ошибка - возвращается -1.
     *
     * @param handle Дескриптор порта.
     * @return Значение считанного байта (0-255) или -1 в случае ошибки чтения или -2 в случае отсутствия данных.
     */
    static native int readByte(long handle);

    /**
     * Неблокирующая запись в порт заданного участка массива. Запись происходит за одно обращение, ожидания записи всех
     * данных не происходит! Если произошла ошибка записи - возвращается -1.
     *
     * @param handle Дескриптор порта.
     * @param buffer Буфер.
     * @param index  Смещение начала данных от начала буфера.
     * @param length Длина записываемых данных.
     * @return Кол-во записанных байт (может быть нулевым). Или -1 в случае ошибки записи.
     */
    static native int writeBytes(long handle, byte[] buffer, int index, int length);

    /**
     * Неблокирующая запись в порт одного байта. Запись происходит за одно обращение. Если произошла ошибка записи -
     * возвращается -1.
     *
     * @param handle Дескриптор порта.
     * @param value  Значение записываемого байта.
     * @return Кол-во записанных байт (0 или 1) или -1 в случае ошибки записи.
     */
    static native int writeByte(long handle, int value);

    /**
     * Получение кол-ва байт доступных для чтения в буфере чтения порта.
     *
     * @param handle Дескриптор порта.
     * @return Кол-во байт, доступных для чтения или -1 в случае ошибки.
     */
    static native int getInputBufferBytesCount(long handle);

    /**
     * Получение кол-ва байт ожидающих отправки в буфере записи порта.
     *
     * @param handle Дескриптор порта.
     * @return Кол-во байт, ожидающих записи или -1 в случае ошибки.
     */
    static native int getOutputBufferBytesCount(long handle);

    /**
     * Проверка работоспособности порта. Используется для детекции дисконнекта устройства.
     * <p>
     * ПРИМЕЧАНИЕ: В разных ОС используются разные методы детекции. В Linux - задействуется действующий дескриптор, в
     * Windows - имя порта (т.к. операция проверки производится вне действующего дескриптора). Подробнее в исходниках
     * нативных библиотек.
     *
     * @param handle   Дескриптор порта (используется только в Linux).
     * @param portname Имя порта (используется только в Windows).
     * @return Результат проверки: 0 - порт рабочий, иначе - ошибка (-1 или код ошибки).
     */
    static native int checkPort(long handle, String portname);
}
