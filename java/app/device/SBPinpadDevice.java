/*
 * Copyright (c) 2016. Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */

package app.device;

import app.DataBuffer;
import app.ExError;
import app.LoggerExt;
import app.driver.RS232Driver;
import util.Base64Ext;
import util.CRC16sb;
import util.CommonTools;

import java.io.Closeable;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.Inet4Address;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.logging.Level;

import static util.StringTools.arrayToHex;
import static app.driver.RS232Driver.*;

/**
 * "SberBank Pinpad Device" Драйвер для управления пинпадом СБЕРБАНК по новому протоколу UPOS.
 * <p>
 * <pre>
 *
 * Разрабатывалось и тестировалось с пинпадом "Verifone VX 820".
 *
 * 0. Физический уровень RS232:
 *    {маркер начала}[1] + {'#'}[1] + {base64 данные}[K] + {маркер конца}[1]
 *
 *    Блок base64 декодируется и результат содержит данные транспортного уровня.
 *
 * 1. Транспортный уровень:
 *    {Номер фрагмента+флаг незавершенности}[1] + {длина данных}[1] + {данные}[M] + {crc16}[2].
 *
 *    Требует подтверждения получения\передачи данных или промежуточного подтверждения, при
 *    фрагментации данных уровня команды (отправка\получение по частям - когда размер данных для
 *    транспортировки превышает максимально возможный).
 *
 * 2. Уровень команды:
 *    {код команды\ответа}[1] + {длина данных}[2] + {idsync+флаг ответа}[4] + {данные}[N]
 *
 *    В ответ на команду требует ответ (команда). У команды и ответа должны совпадать младшие 31 бит
 *    idsync, последний бит - индикатор ответа (0-команда, 1-ответ).
 *    У ответа в коде команды передаётся результат выполнения команды, 0 - успех, иначе код ошибки.
 *    Если код ошибки = 0xE и длина данных = 2, то расширенный результат в данных (2 байта).
 *
 * 3. Уровень управления (Команда = 0xA0: CMD_MASTERCALL):
 *    {код инструкции}[1] + {код устройства}[1] + {0x00}[1] + {длина данных}[2] + {данные}[N-5]
 *
 *    В ответ на команду требует ответ (команду того же уровня). В отличии от других команд - эта
 *    двусторонняя, т.е. команду может подавать как ПК, так и терминал.
 *    Используется для связи терминала с ПЦ через ПК и для "печати" чеков терминалом на ПК.
 *
 *
 * </pre>
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
@LoggerExt.LoggerRules(methods = {"logMsg", "logFrame", "logPhys", "logCmd", "logCmdMC"})
public final class SBPinpadDevice implements Closeable {

    /** Логгеры для отладки кода. */
    private final LoggerExt logRaw, logCmd;

    /** Коммуникационный драйвер. */
    private final RS232Driver driver;
    /** Имя устройства (для логов). */
    private final String devname;

    /** Таймаут получения подтверждения об отправке на транспортном уровне (300 мсек.). */
    private final int transportConfirmationTimeout = 300;
    /** Таймаут получения первого байта ответа на команду (35 сек.). */
    private final int answerTimeout = 35000;
    /** Кодировка для текстовых данных команд. */
    private final Charset charset;

    /** Битовые флаги для логгера RAW, позволяющие настроить вывод в лог нужных уровней кода. */
    public static final int LOGRAW_ALL = -1;
    public static final int LOGRAW_PHYS = 1;
    public static final int LOGRAW_FRAME = 2;
    public static final int LOGRAW_MSG = 4;

    /** Битовые флаги для логгера CMD, позволяющие настроить вывод в лог нужных уровней кода. */
    public static final int LOGCMD_ALL = -1;
    public static final int LOGCMD_CMD = 1;
    public static final int LOGCMD_TRANS = 2;

    public static final int KEY_0 = 0x30; // '0'
    public static final int KEY_1 = 0x31; // '1'
    public static final int KEY_2 = 0x32; // '2'
    public static final int KEY_3 = 0x33; // '3'
    public static final int KEY_4 = 0x34; // '4'
    public static final int KEY_5 = 0x35; // '5'
    public static final int KEY_6 = 0x36; // '6'
    public static final int KEY_7 = 0x37; // '7'
    public static final int KEY_8 = 0x38; // '8'
    public static final int KEY_9 = 0x39; // '9'
    public static final int KEY_STAR = 0x2E; // '*'
    public static final int KEY_HASH = 0x23; // '#'
    public static final int KEY_CANCEL = 0x1B; // Красная кнопка омены операции.
    public static final int KEY_CLEAR = 0x09; // Желтая кнопка сброса\удаления символа.
    public static final int KEY_OK = 0x0D; // Зеленая кнопка подтверждения операции.

    ////////////////////////////////////////////////////////////////////////////////////////////////
    public SBPinpadDevice(String devname, final RS232Driver driver, final String charset) {

        logRaw = LoggerExt.getNewLogger("RAW-" + devname);
        logCmd = LoggerExt.getNewLogger("CMD-" + devname);

        this.driver = driver;
        this.devname = devname;
        this.charset = Charset.forName(charset);

        // Буферы для команд.
        outcmdbuffer = new DataBuffer(3000, this.charset);
        incmdbuffer = new DataBuffer(3000, this.charset);
    }

    /** Получение драйвера устройства (RS232). */
    public RS232Driver getDriver() {
        return driver;
    }

    /** Получение имени устройства. */
    public String getDeviceName() {
        return devname;
    }

    /** Метод автозавершения работы с устройством. Реализован для удобства, в рамках Closeable. */
    @Override
    public void close() {
        if (driver != null) driver.close();
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //  ПЕРВЫЙ УРОВЕНЬ: СООБЩЕНИЯ + ТРАНСПОРТНЫЙ (фреймы) + ФИЗИЧЕСКИЙ
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Служебные байт-коды протокола.
    private static final int STX = 0x02; // Начало транспортного фрейма.
    private static final int STX2 = 0x23; // '#' - индикатор нового протокола.
    private static final int ETX = 0x03; // Конец транспортного фрейма.
    private static final int ACK = 0x04; // Подтверждение успешной передачи сообщения (все части переданы).
    private static final int ACKEVEN = 0x06; // Подтверждение промежуточной передачи (четные пакеты).
    private static final int ACKODD = 0x07; // Подтверждение промежуточной передачи (нечетные пакеты).
    private static final int NAK = 0x15; // Подтверждение ошибки передачи.

    // Временный буфер для формирования фреймов транспортного (физического) уровня.
    private final byte[] tmpbuffer = new byte[3000];
    // Буфер для кодирования\декодирования base64 данных.
    private final byte[] base64buffer = new byte[3000];
    // Для расчёта контрольных сумм (для оптимизации используется один и тот же объект).
    private final CRC16sb crc16sb = new CRC16sb();
    // Ограничение на длину данных для транспортного уровня.
    private final int MAX_TRANSPORT_DATASIZE = 0xB4;

    // Копирование части одного массива в другой.
    private int copyArray(byte[] src, int index, int length, byte[] dst, int dstindex) {
        length = Math.min(length, src.length - index); // Обрезаем по массиву-источнику.
        length = Math.min(length, dst.length - dstindex); // Обрезаем по массиву-приёмнику.
        int n = 0;
        for (; n < length; n++) dst[dstindex + n] = src[index + n];
        return n; // Кол-во скопированных байт (которые можно было скопировать корректно).
    }

    // Подсчет контрольной суммы части массива.
    private int crcArray(byte[] src, int index, int length) {
        crc16sb.reset();
        for (int i = 0; i < length; i++) {
            crc16sb.update(src[index + i]);
        }
        return crc16sb.value();
    }

    /**
     * Выполнение отмены приёма передаваемых устройством данных. Повторяется цикл: очистка входного потока и отправка
     * NAK, до тех пор пока во входной поток не перестанут поступать данные в ответ на NAK.
     */
    private void safeDropInput() {
        try {
            while (true) {
                int count = driver.safeClearRead();
                logRaw.infof("safeDropInput() {%d bytes}", count);

                driver.write(NAK);
                // Когда нет входящих данных - цикл завершится исключением по таймауту.
                driver.read(transportConfirmationTimeout);
            }
        } catch (Exception ex) {
        }
    }


    // Отправка сообщения (с формированием транспортного фрейма (или фреймов, если в один не помещается)).
    @SuppressWarnings("UseSpecificCatch")
    private void write(byte[] buffer, int length) throws
            ExProtocol, ExBuilding, ExNAK, ExOtherError, ExDisconnect {

        // Команда уже подготовлена в буфере.
        int writed = 0; // Кол-во переданных байт.
        int part = 0; // Номер части (при фрагментации данных).
        int attempt = 0; // Текущее кол-во ошибок передачи (подряд, при успешной передаче обнуляется).

        logMsg(false, buffer, length);

        while (writed < length) {

            try {
                boolean notlast = false;
                int psize = length - writed; // остаток к передаче
                if (psize > MAX_TRANSPORT_DATASIZE) { // если остаток больше максимального размера для одной части
                    psize = MAX_TRANSPORT_DATASIZE;
                    notlast = true; // не последний!
                }
                // Формируем транспортный пакет.
                int msglen = 0;
                tmpbuffer[msglen++] = (byte) ((part & 0x7F) | (notlast ? 0x80 : 0x00));
                tmpbuffer[msglen++] = (byte) (psize & 0xFF); // Длина сообщения (контрольная сумма не включается).
                // Заполняем блок данных.
                int n = copyArray(buffer, writed, psize, tmpbuffer, msglen);
                if (n != psize) {
                    throw new ExBuilding("Потеря данных при копировании! {cкопировано %d из %d}", n, psize);
                }
                msglen += n;
                int crc = crcArray(tmpbuffer, 0, msglen); // Контрольная сумма включ рассчитывается по всем данным.
                tmpbuffer[msglen++] = (byte) (crc & 0xFF);
                tmpbuffer[msglen++] = (byte) ((crc >> 8) & 0xFF);
                // Транспортный пакет сформирован.

                logMsg(false, tmpbuffer, msglen);
                logFrame(false, tmpbuffer, msglen);

                // На основе сформированного тела запроса формируем кодированный фрейм для передачи.
                int len64 = Base64Ext.getEncoder().encodeX(tmpbuffer, 0, msglen, base64buffer, 0);

                logMsg(false, base64buffer, len64);
                logPhys(false, base64buffer, len64);

                // Передаём маркеры начала фрейма.
                driver.write(STX);
                driver.write(STX2);

                // Передаём сообщение.
                for (int i = 0; i < len64; i++) {
                    driver.write(base64buffer[i]);
                }
                // Передаём маркер конца фрейма.
                driver.write(ETX);

                // Проверяем подтверждение приёма (ACK-принят, NAK-отвергнут, NEXT... - принята часть).
                int confirm = driver.read(transportConfirmationTimeout);
                logPhys(true, confirm);
                if (notlast) { // Если это не последняя часть, то ожидается промежуточное подтверждение.
                    if (confirm == NAK) {
                        throw new ExNAK();
                    }
                    if (confirm != ((part & 0x1) == 0 ? ACKEVEN : ACKODD)) {
                        // Некорретное подтверждение!
                        throw new ExProtocol("Неверный маркер промежуточного подтверждения записи! {0x%02X}", confirm);
                    }
                } else { // Если это последняя часть или единственная.
                    if (confirm == NAK) {
                        throw new ExNAK();
                    }
                    if (confirm != ACK) {
                        // Некорретное подтверждение!
                        throw new ExProtocol("Неверный маркер подтверждения записи! {0x%02X}", confirm);
                    }
                }
                // Подтверждение корректное - продолжаем передачу (если есть что передавать).
                writed += psize;
                part++;
                attempt = 0;

            } catch (ExNAK ex) {
                logRaw.errorf("Получен NAK!");
                if (++attempt >= 3) throw ex;
            } catch (ExProtocol | ExBuilding ex) {
                logRaw.errorf("Ошибка протокола - %s!", ExError.exMsg(ex));
                safeDropInput();
                if (++attempt >= 3) throw ex;
            } catch (ExDisconnect ex) {
                logRaw.errorf("Дисконнект - %s!", ExError.exMsg(ex));
                throw ex;
            } catch (Exception ex) {
                logRaw.errorf(ex, "Прочая ошибка - %s!", ExError.exMsg(ex));
                safeDropInput();
                throw new ExOtherError(ex);
            }
        }
    }

    /**
     * Получение сообщения (с декодированием из транспортного пакета(ов)).
     *
     * @param buffer           Буфер для данных.
     * @param devanswertimeout Таймаут ожидания первого байта. Если < 0, то берется таймаут по умолчанию для
     *                         устройства.
     * @return Кол-во считанных байт.
     */
    @SuppressWarnings("UseSpecificCatch")
    private int read(byte[] buffer, int devanswertimeout) throws
            ExProtocol, ExStructure, ExBuilding, ExCRC, ExOtherError, ExDisconnect {

        // Если таймаут не задан - берем по умолчанию для этого устройства.
        if (devanswertimeout < 0) devanswertimeout = answerTimeout;
        int readed = 0; // Кол-во принятых байт.
        int part = 0; // Номер части (при фрагментации данных).
        boolean notlast = true;
        int attempt = 0;

        while (notlast) {

            try {
                // Чтение маркеров начала фрейма.
                int value;
                while (true) {
                    value = driver.read(devanswertimeout);
                    if (value == STX) {
                        break;
                    }
                    devanswertimeout = -1;
                    // После получения первого байта - остальные считываем с дефолтным для устройства таймаутом.
                }
                value = driver.read();
                if (value != STX2) {
                    throw new ExProtocol("Неверный маркер нового протокола! (0x%02X)", value);
                }
                // Считываем закодированный фрейм (до маркера конца фрейма).
                int len64 = 0;
                while (true) {
                    value = driver.read();
                    if (value == ETX) { // Маркер конца фрейма.
                        break;
                    }
                    base64buffer[len64++] = (byte) (value & 0xFF);
                }

                logPhys(true, base64buffer, len64);

                // Раскодируем во временный буфер.
                int msglen = Base64Ext.getDecoder().decodeX(base64buffer, 0, len64, tmpbuffer, 0);

                logFrame(true, tmpbuffer, msglen);

                notlast = (tmpbuffer[0] & 0x80) != 0;
                int p = (tmpbuffer[0] & 0x7F);
                if (p != part) {
                    throw new ExStructure("Неверный номер фрейма! %d <> pc=%d", p, part);
                }
                int psize = (tmpbuffer[1] & 0xFF);
                if (psize != msglen - 2 - 2) {
                    throw new ExStructure("Неверная длина фрейма! %d <> msglen-4=%d", psize, msglen - 2 - 2);
                }

                int crc = crcArray(tmpbuffer, 0, msglen - 2); // Контрольная сумма включ рассчитывается по всем данным.
                int c = (tmpbuffer[msglen - 2] & 0xFF) | ((tmpbuffer[msglen - 1] & 0xFF) << 8);
                if (crc != c) {
                    throw new ExCRC("Неверная контрольная сумма! %d <> calc=%d", c, crc);
                }

                int n = copyArray(tmpbuffer, 2, psize, buffer, readed);
                if (n != psize) {
                    throw new ExBuilding("Потеря данных при копировании! Скопировано: %d из %d", n, psize);
                }

                int confirm = notlast ? ((part & 0x1) == 0 ? ACKEVEN : ACKODD) : ACK;
                driver.write(confirm);
                logPhys(false, confirm);

                readed += psize;
                part++;
                attempt = 0;

            } catch (ExCRC | ExProtocol | ExStructure | ExBuilding ex) {
                logRaw.errorf("Error! %s", ex.getMessage());
                safeDropInput();
                if (++attempt >= 3) {
                    throw ex;
                }
            } catch (ExDisconnect ex) {
                logRaw.errorf("Disconnect! %s", ex.getMessage());
                throw ex;
            } catch (Exception ex) {
                logRaw.errorf(ex, "Other exception - break! %s", ex.getMessage());
                safeDropInput();
                throw new ExOtherError(ex);
            }
        }
        logMsg(true, buffer, readed);

        return readed;
    }


    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //  ВТОРОЙ УРОВЕНЬ:  КОМАНДНЫЙ
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /** Типы команд первого уровня. */
    private static final int CMD_GETREADY = 0x50;   // Опрос готовности МА.
    private static final int CMD_CARDTEST = 0xEF;   // Проверка наличия карты в ридере.
    private static final int CMD_MASTERCALL = 0xA0; // Управление устройствами.
    private static final int CMD_TRANSACTION = 0x6D; // Транзакция.

    /** Для команды CMD_MASTERCALL: Типы исполняющих устройств. */
    private static final int MCDEV_NO = 0x00;
    private static final int MCDEV_DISPLAY = 0x01;
    private static final int MCDEV_KEYBOARD = 0x02;
    private static final int MCDEV_PRINTER = 0x03;
    private static final int MCDEV_MAGREADER = 0x04;
    private static final int MCDEV_CLOCK = 0x05;
    private static final int MCDEV_LAN = 0x19;
    private static final int MCDEV_MENU = 0x1E;
    private static final int MCDEV_INPUTLINE = 0x1F;
    private static final int MCDEV_BEEPER = 0x20;
    private static final int MCDEV_REBOOT = 0x29;

    /** Для команды CMD_MASTERCALL: Типы операций. */
    private static final int MCOPER_OPEN = 0x01;
    private static final int MCOPER_READ = 0x02;
    private static final int MCOPER_WRITE = 0x03;
    private static final int MCOPER_CLOSE = 0x04;

    /**
     * Метаданные команды первого уровня.
     */
    private static class Meta {

        /** Код команды (в ответе - результат выполнения команды). */
        protected int cmdID;
        /** cmdID для синхронизации команд-ответов. */
        protected int syncID;
        /** Флаг-индикатор типа метаданных: True - ответ, False - запрос. */
        protected boolean isAnswer;
        /** Длина данных в буфере (длина данных команды или команды управления, если присутствует). */
        protected int dataLength;
        /** Расширенный результат. Только для ответа, при cmdID = 0xE. */
        protected int extResultCode;

        /** Конструктор. */
        protected Meta() {
            set(0, 0, 0, false, 0);
        }

        /** Установка параметров команды. */
        private Meta set(int cmdid, int datalength, int syncid, boolean isanswer, int extresultcode) {
            this.cmdID = cmdid;
            this.dataLength = datalength;
            this.syncID = syncid & 0x7FFFFFFF;
            this.isAnswer = isanswer;
            // Установка расширенного кода ошибки, если параметры это подразумевают - см. setResultCode().
            setResultCode(cmdid, extresultcode);
            return this;
        }

        public int getResultCode() {
            if (isAnswer) {
                return (cmdID == 0xE && dataLength == 2) ? extResultCode : cmdID;
            }
            return 0;
        }

        public void setResultCode(int code, int extcode) {
            if (isAnswer) {
                cmdID = code; // Обычный код ошибки в коде команды.
                extResultCode = (code == 0xE && dataLength == 2) ? extcode : 0; // Если вернулся расширенный код - присваиваем.
            } else {
                extResultCode = 0; // Сбрасываем расширенный код ошибки для команды.
            }
        }

        ////////////////////////////////////////////////////////////////////////////////////////////////
        public static int getMetaLength() {
            return 7;
        }

        public int getDataLength() {
            return dataLength;
        }

        public void setDataLength(int datalength) {
            this.dataLength = datalength;
        }

        public int getRawLength() {
            return getMetaLength() + getDataLength();
        }

        public static DataBuffer setAreaToMeta(DataBuffer buf) {
            return buf.area(0, getMetaLength());
        }

        public DataBuffer setAreaToData(DataBuffer buf) {
            return buf.area(getMetaLength(), getDataLength());
        }

        public DataBuffer setAreaToRAW(DataBuffer buf) {
            return buf.area(0, getRawLength());
        }

        ////////////////////////////////////////////////////////////////////////////////////////////////
        public Meta setAsCmd(int cmdid, int datalength, int extresultcode) {
            return set(cmdid, datalength, 0, false, extresultcode);
        }

        public Meta setAsAnswer(Meta meta, int errid, int dataLength) {
            return set(errid, dataLength, meta.syncID, true, 0);
        }

        public Meta setAsAnswer() {
            return set(0, 0, 0, true, 0);
        }

        ////////////////////////////////////////////////////////////////////////////////////////////////

        /**
         * Сохраняет метаданные команды в буфер.
         * <p>
         * ВНИМАНИЕ! Подразумевается, что после выполнения этого метода в буфере настроено окно на область данных
         * команды (при этом не важно, какого уровня команда)!
         *
         * @param meta
         * @param raw
         * @return
         */
        public static Meta metaTo(Meta meta, DataBuffer raw) {
            // Заголовок = 7 байт.
            Meta.setAreaToMeta(raw);
            raw.putAt(0, meta.cmdID);
            raw.putInt2At(1, meta.dataLength);
            raw.putIntAt(3, (meta.syncID & 0x7FFFFFFF) | (meta.isAnswer ? 0x80000000 : 0x00));

            meta.setAreaToData(raw);
            // Заполняем блок данных в случае расширенной ошибки.
            if (meta.isAnswer && meta.cmdID == 0xE && meta.dataLength == 2) {
                raw.putInt2At(0, meta.extResultCode);
            }
            return meta;
        }

        public Meta metaTo(DataBuffer raw) {
            return Meta.metaTo(this, raw);
        }

        public static Meta metaFrom(Meta meta, DataBuffer raw, int size) throws ExStructure {

            if (meta == null) meta = new Meta();
            if (size < Meta.getMetaLength()) {
                throw new ExStructure("Недостаточная длина принятого сообщения! {%d < %d}", size, Meta.getMetaLength());
            }
            Meta.setAreaToMeta(raw);
            int cmdid = raw.getAt(0);
            int datalength = raw.getInt2At(1);
            int syncid = raw.getIntAt(3);
            boolean isanswer = (syncid & 0x80000000) != 0;
            meta.set(cmdid, datalength, syncid & 0x7FFFFFFF, isanswer, 0);

            if (size != meta.getRawLength()) {
                throw new ExStructure("Неверная длина сообщения! {readed=%d <> rawlen=%d}", size, meta.getRawLength());
            }
            if (meta.syncID < 1 || meta.syncID > 999999) {
                throw new ExStructure("Номер сообщения выходит за рамки! {%d}", meta.syncID);
            }
            meta.setAreaToData(raw);
            if (cmdid == 0xE && isanswer && datalength == 2) {
                meta.extResultCode = raw.getInt2At(0);
            }
            return meta;
        }

        public Meta metaFrom(DataBuffer raw, int size) throws ExStructure {
            return Meta.metaFrom(this, raw, size);
        }

        public static Meta command(int cmdid, int datalength) {
            return new Meta().setAsCmd(cmdid, datalength, 0);
        }

        public static Meta answer() {
            return new Meta().setAsAnswer();
        }

        public static Meta answer(Meta meta, int errid, int datalength) {
            return new Meta().setAsAnswer(meta, errid, datalength);
        }
    }

    /** Буфер для передаваемых команд. Рабочее окно на весь буфер - длина команды определяется метаданными. */
    private final DataBuffer outcmdbuffer;
    /** Буфер для принимаемых команд. Рабочее окно на весь буфер - длина команды определяется метаданными. */
    private final DataBuffer incmdbuffer;

    /**
     * Отправка команды/ответа устройству (команда записана в outcmddata => outcmdbuffer[7]. Если это ответ -
     * расширенный результат, то он берется из метаданных, а не из данных!!!
     */
    private void sendCmd(Meta meta) throws
            ExProtocol, ExBuilding, ExNAK, ExOtherError, ExDisconnect {
        // Если это команда и не задан syncID - присваиваем новый.
        if (!meta.isAnswer && meta.syncID == 0) meta.syncID = generateCommandID();
        try {
            logCmd(false, meta, outcmdbuffer);
            meta.metaTo(outcmdbuffer);
            write(outcmdbuffer.buffer(), meta.getRawLength());
        } catch (ExNAK | ExBuilding | ExOtherError ex) {
            throw ex;
        }
    }

    /**
     * Получение команды/ответа от устройства в буфер для поступающих команд (incmdbuffer).
     * <p>
     * После выполнения команды рабочая область в incmdbuffer установлена на данные!
     *
     * @param meta             Метаданные команды.
     * @param devanswertimeout Таймаут ожидания первого байта ответа.
     * @param isloglater       Флаг вывода в лог: true - не выводить в лог (подразумевается, что вывод будет сделан в
     *                         вышестоящих методах), false - вывести в лог сразу.
     */
    private void receiveCmd(Meta meta, int devanswertimeout, boolean isloglater) throws
            ExProtocol, ExStructure, ExBuilding, ExCRC, ExOtherError, ExDisconnect {

        int size = read(incmdbuffer.buffer(), devanswertimeout);
        // Выделяем и проверяем транспортные параметры.
        meta.metaFrom(incmdbuffer, size);
        if (!isloglater) logCmd(true, meta, incmdbuffer);
    }

    /**
     * Получение команды/ответа от устройства в буфер для поступающих команд (incmdbuffer). Вывод в лог сразу.
     * <p>
     * После выполнения команды рабочая область в incmdbuffer установлена на данные!
     *
     * @param meta             Метаданные команды.
     * @param devanswertimeout Таймаут ожидания первого байта ответа.
     */
    private void receiveCmd(Meta meta, int devanswertimeout) throws
            ExProtocol, ExStructure, ExBuilding, ExCRC, ExOtherError, ExDisconnect {
        receiveCmd(meta, devanswertimeout, false);
    }

    private void testAnswer(Meta req, Meta answ) throws ExWrongAnswer {
        if (req.syncID != answ.syncID) throw new ExWrongAnswer("Не совпадают номера сообщений у команды и ответа!");
        if (!answ.isAnswer) throw new ExWrongAnswer("Сообщение не является ответом!");
    }

    private void testAnswerAndResult(Meta req, Meta answ, boolean ischeckresult) throws ExWrongAnswer, ExResultCode {
        testAnswer(req, answ);
        int errcode = answ.getResultCode();
        if (errcode != 0) throw new ExResultCode(errcode, "Возвращен код ошибки! {%d}", errcode);
    }


    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //  РЕАЛИЗАЦИЯ КОМАНД КОМАНДНОГО УРОВНЯ
    //
    //  НЕ РЕАЛИЗОВАНЫ (нет необходимости):
    //    0xA5  (CMD_GET_PARAMS) : Получить значение настроек модуля
    //    0xEA  (CMD_SET_PARAMS) : Установить значение настроек модуля
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /** Последний сгенерированный ID команды. */
    private int lastCommandID = (int) ((System.currentTimeMillis() / 100) % 999999);

    /** Получение (генерация) нового ID для команды. */
    private int generateCommandID() {
        if (++lastCommandID > 999999) lastCommandID = 1;
        return lastCommandID;
    }

    /**
     * 0x50 (CMD_GETREADY): Опрос готовности МА.
     *
     * @param devanswertimeout Таймаут ожидания первого байта ответа.
     * @return Строка, содержащая информацию о терминале.
     * @throws ExError Ошибка при совершении операции.
     */
    public String cmd_GetReady(int devanswertimeout) throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        Meta meta = Meta.command(CMD_GETREADY, 0);
        Meta res = Meta.answer();
        //
        sendCmd(meta);
        receiveCmd(res, devanswertimeout);
        //
        testAnswer(meta, res);
        return incmdbuffer.getZStringAt(0, res.getDataLength());
    }

    public String cmd_GetReady() throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        return cmd_GetReady(-1);
    }

    /**
     * 0xEF (CMD_CARDTEST): Проверка наличия карты в ридере.
     *
     * @param devanswertimeout Таймаут ожидания первого байта ответа.
     * @return 0 - карта в ридере, иначе - отсутствует.
     * @throws ExError Ошибка при совершении операции.
     */
    public int cmd_CardTest(int devanswertimeout) throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        Meta meta = Meta.command(CMD_CARDTEST, 1);
        meta.setAreaToData(outcmdbuffer).put(0); // 0 = клиентский ридер.
        Meta res = Meta.answer();
        //
        sendCmd(meta);
        receiveCmd(res, devanswertimeout);
        //
        testAnswer(meta, res);
        return res.getResultCode();
    }

    public int cmd_CardTest() throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        return cmd_CardTest(-1);
    }

    /**
     * Метаданные команды второго уровня: 0xA0 (CMD_MASTERCALL). Управление устройствами МА или УК. Расширяет метаданные
     * команды первого уровня!
     */
    public static class MCMeta extends Meta {

        private int mcDevType;
        private int mcOpType;
        private int mcDataLength;

        protected MCMeta() {
            super();
            set(0, 0, 0);
        }

        private MCMeta set(int devtype, int optype, int datalength) {
            this.mcDevType = devtype;
            this.mcOpType = optype;
            setMCDataLength(datalength);
            return this;
        }

        ////////////////////////////////////////////////////////////////////////////////////////////////
        public int getMCDataLength() {
            return mcDataLength;
        }

        public void setMCDataLength(int datalength) {
            super.setDataLength(datalength + MCMeta.getMCMetaLength());
            this.mcDataLength = datalength;
        }

        @Override
        public void setDataLength(int datalength) {
            super.setDataLength(datalength);
            this.mcDataLength = datalength - MCMeta.getMCMetaLength();
        }

        ////////////////////////////////////////////////////////////////////////////////////////////////
        public static int getMCMetaOffset() {
            return getMetaLength();
        }

        public static int getMCMetaLength() {
            return 5;
        }

        public static int getMCDataOffset() {
            return getMCMetaOffset() + getMCMetaLength();
        }

        public int getMCRawLength() {
            return getMCMetaLength() + getMCDataLength();
        }

        public static DataBuffer setAreaToMCMeta(DataBuffer buf) {
            return buf.area(getMCMetaOffset(), getMCMetaLength());
        }

        public DataBuffer setAreaToMCData(DataBuffer buf) {
            return buf.area(getMCDataOffset(), getMCDataLength());
        }

        public DataBuffer setAreaToMCRAW(DataBuffer buf) {
            return buf.area(getMCMetaOffset(), getMCRawLength());
        }

        ////////////////////////////////////////////////////////////////////////////////////////////////
        public MCMeta setAsCmd(int cmdid, int datalength, int extresultcode) {
            super.setAsCmd(CMD_MASTERCALL, 0, 0);
            return set(cmdid, datalength, extresultcode);
        }

        public MCMeta setAsAnswer(MCMeta req, int errid, int datalength) {
            super.setAsAnswer(req, errid, 0);
            return set(req.mcDevType, req.mcOpType, datalength);
        }

        @Override
        public MCMeta setAsAnswer() {
            super.setAsAnswer();
            return set(0, 0, 0);
        }

        /**
         * Сохраняет метаданные команды в буфер.
         * <p>
         * ВНИМАНИЕ! Подразумевается, что после выполнения этого метода в буфере настроено окно на область данных
         * команды (при этом не важно, какого уровня команда)!
         *
         * @param mc
         * @param raw
         * @return
         */
        public static MCMeta metaTo(MCMeta mc, DataBuffer raw) {
            // Заголовок команды = 7 байт.
            Meta.metaTo(mc, raw);

            // Заголовок = 5 байт.
            MCMeta.setAreaToMCMeta(raw);
            raw.putAt(0, mc.mcOpType);
            raw.putAt(1, mc.mcDevType);
            raw.putAt(2, 0); // резерв.
            raw.putInt2At(3, mc.mcDataLength);

            mc.setAreaToMCData(raw);
            return mc;
        }

        @Override
        public MCMeta metaTo(DataBuffer raw) {
            return MCMeta.metaTo(this, raw);
        }

        public static MCMeta metaFrom(MCMeta mc, DataBuffer raw, int size) throws ExStructure {

            if (mc == null) {
                mc = new MCMeta();
            }

            // Заголовок команды = 7 байт.
            Meta.metaFrom(mc, raw, size);

            if (size < MCMeta.getMCDataOffset()) {
                throw new ExStructure("Недостаточная длина принятого сообщения! {%d < %d}",
                        size, MCMeta.getMCDataOffset());
            }
            // Заголовок = 5 байт.
            MCMeta.setAreaToMCMeta(raw);
            mc.set(raw.getAt(1), raw.getAt(0), raw.getInt2At(3));

            if (size != MCMeta.getMCDataOffset() + mc.getMCDataLength()) {
                throw new ExStructure("Неверная длина сообщения! {readed=%d <> rawlen=%d}",
                        size, MCMeta.getMCDataOffset() + mc.getMCDataLength());
            }
            mc.setAreaToMCData(raw);
            return mc;
        }

        @Override
        public MCMeta metaFrom(DataBuffer raw, int size) throws ExStructure {
            return MCMeta.metaFrom(this, raw, size);
        }

        public static MCMeta command(int devtype, int optype, int dataLength) {
            return new MCMeta().setAsCmd(devtype, optype, dataLength);
        }

        public static MCMeta answer() {
            return new MCMeta().setAsAnswer();
        }

        public static MCMeta answer(MCMeta mc, int errid, int datalength) {
            return new MCMeta().setAsAnswer(mc, errid, datalength);
        }
    }

    /**
     * 0xA0 (CMD_MASTERCALL) : Управление устройствами.
     * <p>
     * Посылка команды MASTERCALL терминалу. Данные команды находятся в исходящем буфере. Результат выполнения команды
     * имеет тот же тип, что и команда!
     *
     * @param mc Команда.
     * @return Команда-результат. Данные во входящем буфере.
     * @throws ExError
     */
    private MCMeta cmd_MasterCall(MCMeta mc, int devanswertimeout) throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        MCMeta res = MCMeta.answer();
        //
        sendCmd(mc);
        receiveCmd(res, devanswertimeout);
        //
        testAnswer(mc, res);
        return res;
    }

    /**
     * Вывод на дисплей пинпада строки текста. Дисплей может иметь разлиное разрешение у разных устройств!!!
     *
     * @param row  Строка. Если = -100 - очистка экрана.
     * @param text Текст.
     * @throws ExError
     */
    public void cmd_MC_Display(int row, String text, int devanswertimeout) throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        int n = text.length();
        MCMeta mc = MCMeta.command(MCDEV_DISPLAY, MCOPER_WRITE, n + 2);
        mc.setAreaToMCData(outcmdbuffer).putAt(0, row).putZStringAt(1, text, n + 1);
        mc.setAreaToRAW(outcmdbuffer);
        System.out.printf("hex[%d]=%s\n", mc.getRawLength(), outcmdbuffer.getHexAt(0, mc.getRawLength()));
        cmd_MasterCall(mc, devanswertimeout);
    }

    public void cmd_MC_Display(int row, String text) throws ExError {
        cmd_MC_Display(row, text, -1);
    }

    /** Искусственная надстройка над cmd_MC_Display - очистка эркана. */
    public void cmd_MC_DisplayCls() throws ExError {
        cmd_MC_Display(-100, "", -1);
    }

    /** Искусственная надстройка над cmd_MC_Display - для удобного вывода форматированного текста. */
    public void cmd_MC_DisplayFmt(int row, String fmt, Object... args) throws ExError {
        cmd_MC_Display(row, String.format(fmt, args), -1);
    }

    /**
     * Подача пинпадом звукового сигнала.
     *
     * @param type Тип сигнала: 0-короткий (OK), 1-длинный (ERROR).
     * @throws ExError
     */
    public void cmd_MC_Beep(int type, int devanswertimeout) throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        MCMeta mc = MCMeta.command(MCDEV_BEEPER, MCOPER_WRITE, 1);
        mc.setAreaToMCData(outcmdbuffer).putAt(0, type);
        cmd_MasterCall(mc, devanswertimeout);
    }

    public void cmd_MC_Beep(int type) throws ExError {
        cmd_MC_Beep(type, -1);
    }

    /**
     * Проверка буфера клавиатуры пинпада. Возвращает символы, нажатые на пинпаде с момента последней подачи данной
     * команды. Каждый символ строки представляет одну нажатую клавишу. '0'-'9', '*', '#', ESC=0x1B, DEL=0x8, OK=0xD.
     *
     * @return
     * @throws ExError
     */
    public String cmd_MC_Keyboard(int devanswertimeout) throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        MCMeta mc = cmd_MasterCall(MCMeta.command(MCDEV_KEYBOARD, MCOPER_READ, 0), devanswertimeout);
        return mc.getMCDataLength() == 0 ? "" : incmdbuffer.getZStringAt(0, mc.getMCDataLength());
    }

    public String cmd_MC_Keyboard() throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        return cmd_MC_Keyboard(-1);
    }

    public static class PrinterTextBlock {

        public int mode;
        public String text;

        public PrinterTextBlock(int mode, String text) {
            this.mode = mode;
            this.text = text;
        }
    }

    // LAN
    private Socket lanSocket = null;
    // PRINTER
    private int printerMode = 0;
    private final ArrayList<PrinterTextBlock> printerText = new ArrayList<>();
    // REBOOT
    private int rebootTimeout = 0; // 0 - не выставлен.

    public int getLastPrintedMode() {
        return printerMode;
    }

    public ArrayList<PrinterTextBlock> getLastPrintedTextAsBlocks() {
        return printerText;
    }

    /**
     * Получение текущего (последнего) текста (чека) выведенного на принтер командами MASTERCALL (MCDEV_PRINTER,
     * MCOPER_WRITE) в виде одной форматированной строки с переносами строк.
     * <p>
     * ФОРМАТ: {Режим вывода строки в HEX виде (2 символа)} + {текст строки} + {\n} + ...
     *
     * @return
     */
    public String getLastPrintedTextAsString() {
        StringBuilder sb = new StringBuilder();
        for (PrinterTextBlock b : printerText) sb.append(b.text);
        return sb.toString();
    }

    /**
     * Выполнение команды поступившей от терминала и отправка результата в терминал. Выполняет необходимые действия и
     * отправляет команду-результат в терминал. Исполняемая команда во входящем буфере. Отправляемый результат в
     * исходящем.
     *
     * @param mc Исполняемая команда. Данные во входящем буфере.
     * @throws ExError
     */
    private void execute_MasterCall(MCMeta mc) throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {

        int errid = 0x00;
        rebootTimeout = 0; // Сбрасываем.
        // По умолчанию ответ нулевой!
        outcmdbuffer.area(MCMeta.getMCDataOffset(), 0);
        // Парсим команду поступившую из терминала.
        mc.setAreaToMCData(incmdbuffer);
        try {
            switch (mc.mcDevType) {
                case MCDEV_LAN:
                    switch (mc.mcOpType) {
                        case MCOPER_OPEN:
                            // Если старый сокет по какой-то причине не закрыт - закрываем.
                            if (lanSocket != null && !lanSocket.isClosed()) {
                                lanSocket.close();
                            }
                            byte[] ip = {
                                    (byte) incmdbuffer.getAt(2),
                                    (byte) incmdbuffer.getAt(3),
                                    (byte) incmdbuffer.getAt(4),
                                    (byte) incmdbuffer.getAt(5)
                            };
                            int port = incmdbuffer.getInt2At(6);
                            // Установка соединения.
                            lanSocket = new Socket(Inet4Address.getByAddress(ip), port);
                            // Формирование результата операции (успех\неудача) в терминал.
                            break;

                        case MCOPER_READ:
                            int maxsize = incmdbuffer.getInt2At(0);
                            // Чтение информации из ПЦ.
                            InputStream is = lanSocket.getInputStream();
                            int size = Math.min(is.available(), maxsize);
                            if (size > 0) {
                                size = is.read(outcmdbuffer.buffer(), outcmdbuffer.offset(), size);
                            }
                            // Формирование результата операции (данные из ПЦ) в терминал.
                            outcmdbuffer.length(size);
                            break;

                        case MCOPER_WRITE:
                            // Оправка информации в ПЦ.
                            OutputStream os = lanSocket.getOutputStream();
                            os.write(incmdbuffer.buffer(), incmdbuffer.offset(), mc.getMCDataLength());
                            // Формирование результата операции (кол-во отправленных байт) в терминал.
                            outcmdbuffer.length(2).putInt2(mc.getMCDataLength());
                            break;

                        case MCOPER_CLOSE:
                            // Закрытие соединения.
                            if (lanSocket != null && !lanSocket.isClosed()) {
                                lanSocket.close();
                            }
                            // Формирование результата операции (успех) в терминал.
                            break;
                    }
                    break;

                case MCDEV_PRINTER:
                    switch (mc.mcOpType) {
                        case MCOPER_OPEN:
                            printerMode = incmdbuffer.getAt(0);
                            if (printerMode == 0) {
                                // Если новая печать - очищаем старый чек, если повтор - нет.
                                printerText.clear();
                            }
                            break;
                        case MCOPER_WRITE:
                            printerText.add(new PrinterTextBlock(
                                    incmdbuffer.getAt(0),
                                    incmdbuffer.getZStringAt(1, mc.getMCDataLength() - 1)));
                            break;
                        default:
                            break;
                    }
                    break;

                case MCDEV_REBOOT:
                    switch (mc.mcOpType) {
                        case MCOPER_OPEN:
                            rebootTimeout = incmdbuffer.getIntAt(0);
                            if (rebootTimeout < 0) rebootTimeout = 60000; // 60 сек.
                            break;
                        default:
                            break;
                    }
                    break;

                default:
                    // Для всех прочих устройств - заглушка (рапорт об успехе операции).
                    // Передача результата операции (успех) в терминал.
                    break;
            }

        } catch (Exception ex) {
            errid = 0x15;
            outcmdbuffer.length(0);
        }

        try {
            // Создаём и отправляем ответ на команду.
            sendCmd(MCMeta.answer(mc, errid, outcmdbuffer.length()));

        } catch (ExDisconnect ex) {
            throw ex;
        } catch (ExError ex) {
            throw ex; // TODO: везде реализовать подробное логирование
        }
    }

    /** Типы операций в команде транзакции. */
    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Торговые операции.
    ////////////////////////////////////////////////////////////////////////////////////////////////
    private static final int TR_PURCHASE = 0x01; // 0x01: Продажа.
    private static final int TR_CASH = 0x02; // 0x02: Выдача наличных.
    private static final int TR_REFUND = 0x03; // 0x03: Возврат платежа.
    private static final int TR_BALANCE = 0x04; // 0x04: Запрос баланса.
    private static final int TR_PAYMENT = 0x05; // 0x05: Оплата.
    private static final int TR_FUNDS = 0x06; // 0x06: Безналичный перевод.
    private static final int TR_CANCEL = 0x08; // 0x08: Отмена операции.
    private static final int TR_ROLLBACK = 0x0D; // Откат последней транзакции.
    private static final int TR_SUSPEND = 0x0F; // Перевод последней транзакции в подвешенное состояние.
    private static final int TR_COMMIT = 0x10; // Закрепление последней транзакции.
    private static final int TR_PRE_AUTH = 0x11; // 0x11: Преавторизация.
    private static final int TR_PRE_COMPLETE = 0x12; // 0x12: Завершение преавторизации.
    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Регламентные операции.
    ////////////////////////////////////////////////////////////////////////////////////////////////
    private static final int TR_CLOSESESSION = 0x07; // 0x07: Закрытие смены (дня).
    private static final int TR_TOTALS = 0x09; // 0x09: Отчеты (Контрольная лента, сводный). [ИЗ ИССЛЕДОВАНИЯ ПРОТОКОЛА]
    private static final int TR_GETTLVDATA = 0x0A; // Чтение данных из настроек??? [Тэг]
    private static final int TR_SERVICEMENU = 0x0B; // 0x0B: Вход в сервисное меню (отчеты,итоги,...). [ИЗ ИССЛЕДОВАНИЯ ПРОТОКОЛА]
    private static final int TR_REPRINT = 0x0C; // 0x0C: Повтор печати последнего чека.
    private static final int TR_READTRACK = 0x14; // 0x14: Чтение трека карты. [ИЗ ИССЛЕДОВАНИЯ ПРОТОКОЛА]
    private static final int TR_SHOWSCREEN = 0x1B; // 0x1B: Вывод на экран пинпада экранной формы с указанным номером. [номер в amount]
    private static final int TR_WAITCARD_ON = 0x1D; // 0x1D: Включить режим ожидания карты.
    private static final int TR_WAITCARD_CHECK = 0x1E; // 0x1E: Проверить наличие карты в режиме ожидания карты.
    private static final int TR_WAITCARD_OFF = 0x1F; // 0x1F: Выключить режим ожидания карты.
    private static final int TR_PRINTHELP = 0x24; // 0x24: Распечатать чек «Помощь».
    ////////////////////////////////////////////////////////////////////////////////////////////////
    //ID_14(0x0E) // Загрузка TLV.
    //ID_19(0x13) // Загрузить TLV-файл с предварительной очисткой старых настроек.
    //ID_21(0x15) // Удаленная загрузка обновлений
    //ID_22(0x16) // Удаление мастер-МАС-ключа
    //ID_23(0x17) // Проверка, есть ли в журнале несверенные операции (что это?)
    //ID_37(0x25) // Загрузить TLV-настройки в пинпад
    ////////////////////////////////////////////////////////////////////////////////////////////////

    /** Данные команды CMD_TRANSACTION. */
    public final class TRCommand {

        public int amount; // [4] сумма в копейках
        public int cardType; // [1] тип карты = 0 - авто
        public int currencyType; // [1] валюта = 0
        public int opType; // [1] тип операции: TR_XXX
        public String track2; // [40] вторая дорожка, Если первый символ 'E', то остальное - HEX!!!
        public int requestID; // [4] cmdID запроса (<0)
        public String RRN; //[12+1]
        public int flags; // [4]
        //public int extraData; // [MAX_PILOT_EXTRA] - не будет использоваться?!
        //ber-tlv coded buffer. len in first byte.
        //in T_Message translate only signefed part of ExtraData (ExtraData[0])

        public TRCommand(int amount, int optype) {
            this.amount = amount;
            this.cardType = 0;
            this.currencyType = 0;
            this.opType = optype;
            this.track2 = "";
            this.requestID = (int) ((System.currentTimeMillis() & 0x7FFFFFFF) | 0x80000000);
            this.RRN = "";
            this.flags = 0;
        }
    }


    /** Данные результата выполнения команды CMD_TRANSACTION. */
    public static final class TRResult { // в 16.0 размер = 0x9F.

        public int resultCode; // [2] =0 - платеж выполнен, иначе - код ошибки.
        public String authCode; // [6+1]
        public String RRN; // [12+1]
        public String opNumber; // [4+1]
        public String cardNumber; // [19+1]
        public String cardExpire; // [5+1]
        public String message; // [32]
        public int date; // [4]
        public int time; // [4]
        public int isSberbankCard; // [1]
        public String terminalNumber; // [8+1]
        public String cardName; // [16]
        public String merchantID; // [12]
        public int spasiboAmt; // [4]
        public String SHA1; // [20] HEX
        public String encryptedData; // [32] HEX Зашифрованные данные карты (в 19.0 размер = 0xBF).
        public String cardID; // [1] (в 24.0 размер = 0xD3)
        public int requestID; // [4] Есть только если в запросе был requestID < 0.
        // Остальные поля только если в ответе есть RequestID и он меньше ноля.
        public String res2; // [19] (в 24.0 размер = 0xD3)

        /** Конструктор. Считывание данных из буфера с текущей позиции. */
        public TRResult(DataBuffer buf) {
            TRResult.this.parse(buf);
        }

        /** Чтение данных из буфера с текущей позиции и заполнение полей считанными значениями. */
        public DataBuffer parse(DataBuffer buf) {
            resultCode = buf.getInt2();
            authCode = buf.getZString(7);
            RRN = buf.getZString(13);
            opNumber = buf.getZString(5);
            cardNumber = buf.getZString(20);
            cardExpire = buf.getZString(6);
            message = buf.getZString(32);
            date = buf.getInt();
            time = buf.getInt();
            isSberbankCard = buf.get();
            terminalNumber = buf.getZString(9);
            cardName = buf.getZString(16);
            merchantID = buf.getZString(12);
            spasiboAmt = buf.getInt();
            SHA1 = buf.getHex(20);
            if (buf.remaining() >= 32 + 4) { // if (len == 0xBF) {  v19.0
                encryptedData = buf.getHex(32);
            } else {
                encryptedData = null;
            }
            if (buf.remaining() >= 1 + 4) { // if (len == 0xD3) {  v24.0
                cardID = buf.getHex(1);
            } else {
                cardID = null;
            }
            requestID = buf.getInt();
            if (buf.remaining() >= 19) {  // if (len == 0xD3) {  v24.0
                res2 = buf.getHex(19);
            } else {
                res2 = null;
            }
            return buf;
        }

        /** Запись значений полей в буфер с текущей позиции. */
        public DataBuffer build(DataBuffer buf) {
            buf.putInt2(resultCode).putZString(authCode, 7);
            buf.putZString(RRN, 13);
            buf.putZString(opNumber, 5);
            buf.putZString(cardNumber, 20);
            buf.putZString(cardExpire, 6);
            buf.putZString(message, 32);
            buf.putInt(date);
            buf.putInt(time);
            buf.put(isSberbankCard);
            buf.putZString(terminalNumber, 9);
            buf.putZString(cardName, 16);
            buf.putZString(merchantID, 12);
            buf.putInt(spasiboAmt);
            buf.putHex(SHA1, 20);
            if (encryptedData != null) buf.putHex(encryptedData, 32);
            if (cardID != null) buf.putHex(cardID, 1);
            buf.putInt(requestID);
            if (res2 != null) buf.putHex(res2, 19);
            return buf;
        }
    }

    /**
     * 0x6D (CMD_TRANSACTION): Транзакция.
     * <p>
     * Посылка команды CMD_TRANSACTION на выполнение терминалу.
     *
     * @param meta Метаданные транзакции.
     * @return Результат выполнения транзакции.
     * @throws ExError Ошибка при выполнении операции.
     */
    private TRResult cmd_Transaction(TRCommand meta) throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {

        logTrans(meta);

        printerMode = 0;
        printerText.clear();

        // Первый этап - передача команды терминалу.
        Meta cmd = Meta.command(CMD_TRANSACTION, 0x44);
        cmd.setAreaToData(outcmdbuffer);
        outcmdbuffer.putInt(meta.amount).put(meta.cardType).put(meta.currencyType).put(meta.opType);
        if (meta.track2 != null && meta.track2.startsWith("hex:")) {
            outcmdbuffer.put('E');
            outcmdbuffer.putHex(meta.track2.substring(4), 39);
        } else {
            outcmdbuffer.putZString(meta.track2, 40);
        }
        outcmdbuffer.putInt(meta.requestID).putZString(meta.RRN, 13).putInt(meta.flags);
        Meta res = Meta.answer();

        sendCmd(cmd);

        // Второй этап - выполнение промежуточных команд терминала (если поступят).
        while (true) {
            // Выполняется приём команды без логирования! Т.к. могут быть команды разных классов!
            // Логирование производится позднее исходя из типа команды.
            receiveCmd(res, 65000, true); // 60 сек таймаут + 5 сек на всякий случай.

            // Если получили ответ, то это должен быть ответ на начальную команду!
            if (res.isAnswer) {
                logCmd(true, res, incmdbuffer);
                break;
            }

            // Если это команда от терминала, выполняем её и снова ждём ответа на начальную команду.
            if (res.cmdID == CMD_MASTERCALL) {
                MCMeta mc = MCMeta.metaFrom(null, incmdbuffer, res.getRawLength());
                logCmd(true, mc, incmdbuffer);

                execute_MasterCall(mc);

                // Если была команда перезагрузки терминала - надо выдержать паузу и переподключиться.
                if (rebootTimeout > 0) {
                    // Ждем заданное время для возобновления связи.
                    CommonTools.safeNonInterruptedSleep(rebootTimeout);
                    // Переподключаемся (если внешний регенератор еще не переподключил).
                    getDriver().regenerate();
                    rebootTimeout = 0;
                }

                continue;
            }

            // Прочие команды - по идее таких быть не должно!
            logCmd(true, cmd, incmdbuffer);
        }

        // Третий этап - получение ответа.
        testAnswer(cmd, res);

        res.setAreaToData(incmdbuffer); // Рабочее окно на данные. На всякий случай.
        TRResult trres = new TRResult(incmdbuffer);

        logTransResult(trres);

        if (trres.requestID != meta.requestID) {
            throw new ExWrongAnswer("Неверный requestID в ответе!");
        }
        return trres;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Торговые операции.
    ////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * Выполнение команды "ПРОДАЖА" на терминале.
     *
     * @param amount Сумма в копейках.
     * @return Результат выполнения команды.
     * @throws ExError Исключение при ошибке выполнения операции.
     */
    public TRResult cmd_TR_Purchase(int amount) throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        TRCommand meta = new TRCommand(amount, TR_PURCHASE);
        return cmd_Transaction(meta);
    }

    /**
     * Выполнение команды "ВОЗВРАТ ПРОДАЖИ" на терминале.
     * <p>
     * Возврат клиенту суммы на карту. После возврата уже нельзя отменить операцию никаким образом! RRN+ENC - успешно
     * возвращает без предъявления карты!
     *
     * @param amount     Сумма в копейках.
     * @param rrn        Код RRN транзакции продажи.
     * @param hexencdata Строка содержащая HEX кодированных данных карты (вместо предъявления карты).
     * @return Результат выполнения команды.
     * @throws ExError Исключение при ошибке выполнения операции.
     */
    public TRResult cmd_TR_Refund(int amount, String rrn, String hexencdata) throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        TRCommand meta = new TRCommand(amount, TR_REFUND);
        if (rrn != null && !rrn.isEmpty()) meta.RRN = rrn;
        if (hexencdata != null && !hexencdata.isEmpty()) meta.track2 = "hex:" + hexencdata;
        return cmd_Transaction(meta);
    }

    /**
     * Выполнение команды "ОТМЕНА ТРАНЗАКЦИИ" на терминале.
     * <p>
     * Отмена транзакции (не только продаж!). Не требует карты при предоставлении hexencdata! RRN - не воспринимается!!!
     * На терминале выдаст список возможных транзакций - надо будет там подтверждать! Если не задана сумма - выдаст все
     * транзакции, которые можно отменить! Это видимо недоработка в прошивке!
     *
     * @param amount     Сумма в копейках.
     * @param rrn        Код RRN отменяемой транзакции.
     * @param hexencdata Строка содержащая HEX кодированных данных карты (вместо предъявления карты).
     * @return Результат выполнения команды.
     * @throws ExError Исключение при ошибке выполнения операции.
     */
    public TRResult cmd_TR_Cancel(int amount, String rrn, String hexencdata) throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        TRCommand meta = new TRCommand(amount, TR_CANCEL);
        if (rrn != null && !rrn.isEmpty()) meta.RRN = rrn;
        if (hexencdata != null && !hexencdata.isEmpty()) meta.track2 = "hex:" + hexencdata;
        return cmd_Transaction(meta); // TODO: Проверить позже - можно ли отменять транзакцию без карты!
    }

    /**
     * Выполнение команды "ОТМЕНА ТРАНЗАКЦИИ" на терминале.
     * <p>
     * Откат последней транзакции. Именно последней, а не произвольной! Не требует предъявления карты!
     *
     * @param amount   Сумма в копейках.
     * @param authCode Код авторизации откадываемой транзакции.
     * @return Результат выполнения команды.
     * @throws ExError Исключение при ошибке выполнения операции.
     */
    public TRResult cmd_TR_Rollback(int amount, String authCode) throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        TRCommand meta = new TRCommand(amount, TR_ROLLBACK);
        if (amount != 0 && authCode != null && !authCode.isEmpty()) meta.track2 = authCode;
        return cmd_Transaction(meta);
    }

    /**
     * Выполнение команды "ЗАПРОС БАЛАНСА КАРТЫ" на терминале.
     * <p>
     * Может быть запрещен банком вообще или для конкретного терминала или для конкретного типа карты!
     *
     * @return Результат выполнения команды.
     * @throws ExError Исключение при ошибке выполнения операции.
     */
    public TRResult cmd_TR_Balance() throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        TRCommand meta = new TRCommand(0, TR_BALANCE);
        return cmd_Transaction(meta);
    }

    /**
     * Выполнение команды "ПРЕАВТОРИЗАЦИЯ" на терминале.
     * <p>
     * Преавторизация на сумму - заморозка данной суммы на карте до подтверждения списания (полного или частичного) или
     * до конца смены (сама разморозится?).
     *
     * @param amount Сумма в копейках.
     * @return Результат выполнения команды.
     * @throws ExError Исключение при ошибке выполнения операции.
     */
    public TRResult cmd_TR_PreAuthorize(int amount) throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        TRCommand meta = new TRCommand(amount, TR_PRE_AUTH);
        return cmd_Transaction(meta);
    }

    /**
     * Выполнение команды "ЗАВЕРШЕНИЕ ПРЕАВТОРИЗАЦИИ" на терминале.
     * <p>
     * Завершение преавторизации с фиксацией суммы (списание средств в рамках замороженной суммы). Завершение не
     * является окончательной операцией! Она может быть отменена, как и преавторизация, причем независимо друг от друга!
     * Видимо ошибка в прошивке!
     *
     * @param amount     Сумма в копейках.
     * @param rrn        Код RRN операции преавторизации.
     * @param hexencdata Строка содержащая HEX кодированных данных карты (вместо предъявления карты).
     * @return Результат выполнения команды.
     * @throws ExError Исключение при ошибке выполнения операции.
     */
    public TRResult cmd_TR_PreComplete(int amount, String rrn, String hexencdata) throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        TRCommand meta = new TRCommand(amount, TR_PRE_COMPLETE);
        meta.cardType = 0;
        if (rrn != null && !rrn.isEmpty()) meta.RRN = rrn;
        if (hexencdata != null && !hexencdata.isEmpty()) meta.track2 = "hex:" + hexencdata;
        return cmd_Transaction(meta);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Регламентные операции.
    ////////////////////////////////////////////////////////////////////////////////////////////////

    /** Выполнение команды "ЗАКРЫТИЕ СМЕНЫ" на терминале. */
    public TRResult cmd_TR_CloseSession() throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        TRCommand meta = new TRCommand(0, TR_CLOSESESSION);
        return cmd_Transaction(meta);
    }

    /** Выполнение команды "ОТЧЕТ ИТОГО ЗА СМЕНУ" на терминале. */
    public TRResult cmd_TR_Totals(int type) throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        TRCommand meta = new TRCommand(0, TR_TOTALS);
        meta.cardType = type; // 0-контрольная лента, 1-итоги.
        return cmd_Transaction(meta);
    }

    /** Выполнение команды "ОЧЕТ СПРАВКА" на терминале. */
    public TRResult cmd_TR_Help() throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        TRCommand meta = new TRCommand(0, TR_PRINTHELP);
        return cmd_Transaction(meta);
    }

    /** Выполнение команды "СЧИТЫВАНИЕ КАРТЫ" на терминале. */
    public TRResult cmd_TR_ReadCard() throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        TRCommand meta = new TRCommand(0, TR_READTRACK);
        return cmd_Transaction(meta);
    }

    /** Выполнение команды "ВХОД В СЕРВИСНОЕ МЕНЮ"  на терминале. */
    public TRResult cmd_TR_ServiceMenu() throws
            ExOtherError, ExBuilding, ExNAK, ExProtocol, ExStructure, ExCRC, ExWrongAnswer, ExDisconnect {
        TRCommand meta = new TRCommand(0, TR_SERVICEMENU);
        // TODO: Нужно разобраться, как происходит процесс обновки.
        // TODO: (макс.время ожидания получения обновлений? происходит перезапуск терминала?
        // TODO: требуется продолжать цикл исполнения после перезагрузки? какой результат операции?)
        return cmd_Transaction(meta);
    }


    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //  Исключения.
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /** Ошибка при построении команды\результата. */
    public static class ExBuilding extends ExError {

        public ExBuilding(String msg) {
            super(msg);
        }

        public ExBuilding(String fmt, Object... params) {
            super(fmt, params);
        }
    }

    /** Неверная контрольная сумма. */
    public static class ExCRC extends ExError {

        public ExCRC(String fmt, Object... params) {
            super(fmt, params);
        }
    }

    /** При отказе терминала от переданного транспортного пакета. */
    public class ExNAK extends ExError {

        public ExNAK() {
            super();
        }
    }

    /** Прочие ошибки. */
    public class ExOtherError extends ExError {

        public ExOtherError() {
            super();
        }

        public ExOtherError(Throwable cause) {
            super(cause);
        }
    }

    /** Ошибки при неверных физических данных. */
    public static class ExProtocol extends ExError {

        public ExProtocol(String msg) {
            super(msg);
        }

        public ExProtocol(String fmt, Object... params) {
            super(fmt, params);
        }
    }

    /** Ответ с ненулевым кодом ошибки. */
    public static class ExResultCode extends ExError {

        /** Код ошибки. */
        public int resultCode;

        public ExResultCode(int code) {
            super();
            resultCode = code;
        }

        public ExResultCode(int code, String fmt, Object... params) {
            super(fmt, params);
        }

        public int getResultCode() {
            return resultCode;
        }
    }

    /** Ошибка структуры данных (в заголовке команды или субкоманды). */
    public static class ExStructure extends ExError {

        public ExStructure(String msg) {
            super(msg);
        }

        public ExStructure(String fmt, Object... params) {
            super(fmt, params);
        }
    }

    /** Неверная команда ответа. */
    public static class ExWrongAnswer extends ExError {

        public ExWrongAnswer() {
            super();
        }

        public ExWrongAnswer(String fmt, Object... params) {
            super(fmt, params);
        }
    }


    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //  Протоколирование и отладочная информация.
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * Включение\выключение вывода отладочной информации RAW с дублированием в файл и задание детализации вывода.
     *
     * @param isEnable Флаг включения: true - включить, false - выключить.
     * @param mask     Битовая маска для управления выводом. Группируются биты: LOGRAW_XXX.
     */
    public void enableRawLogger(boolean isEnable, int mask) {
        logRaw.enable(isEnable).toFile().mask(mask);
    }

    /**
     * Включение\выключение вывода отладочной информации CMD с дублированием в файл и задание детализации вывода.
     *
     * @param isEnable Флаг включения: true - включить, false - выключить.
     * @param mask     Битовая маска для управления выводом. Группируются биты: LOGCMD_XXX.
     */
    public void enableCmdLogger(boolean isEnable, int mask) {
        logCmd.enable(isEnable).toFile().mask(mask);
    }

    private static String sdir(boolean isin) {
        return isin ? "<-" : "->";
    }

    private void logMsg(boolean isin, byte[] buffer, int length) {
        if (logRaw.isEnabled() && logRaw.isMask(LOGRAW_MSG)) {
            logRaw.infof("%s (%4d) [MSG] { %s }",
                    sdir(isin), length, arrayToHex(buffer, 0, length));
        }
    }

    private void logFrame(boolean isin, byte[] buffer, int length) {
        if (logRaw.isEnabled() && logRaw.isMask(LOGRAW_FRAME)) {
            logRaw.infof("%s (%4d) [FRAME] %02X %02X { %s } %04X",
                    sdir(isin), length, buffer[0], buffer[1], arrayToHex(buffer, 2, length - 4),
                    ((buffer[length - 2] & 0xFF) | ((buffer[length - 1] & 0xFF) << 8)));
        }
    }

    private static final String physHeadFmt = "%s (%4d) [RS232] ";

    // Передача одного байта (для подтверждений приёма\передачи).
    private void logPhys(boolean isin, int value) {
        if (logRaw.isEnabled() && logRaw.isMask(LOGRAW_PHYS)) {
            logRaw.infof(physHeadFmt + "{ %02X }", sdir(isin), 1, value);
        }
    }

    private void logPhys(boolean isin, byte[] buffer64, int length64) {
        if (logRaw.isEnabled() && logRaw.isMask(LOGRAW_PHYS)) {
            logRaw.infof(physHeadFmt + "02 2B { %s } 03",
                    sdir(isin), length64 + 3, arrayToHex(buffer64, 0, length64));
        }
    }


    private void logCmd(boolean isin, Meta meta, DataBuffer cmdbuffer) {
        if (logCmd.isEnabled() && logCmd.isMask(LOGCMD_CMD)) {
            StringBuilder sb = new StringBuilder();
            sb.append(String.format("(%4d) [CMD] %s %04X %08X ",
                    meta.getRawLength(), cidCMD(meta.cmdID, meta.isAnswer), meta.getDataLength(), meta.syncID));
            if (meta instanceof MCMeta) {
                MCMeta mc = (MCMeta) meta;
                sb.append(String.format("{ [MC] %s %s %04X { %s }}",
                        cidMCOP(mc.mcOpType), cidMCDEV(mc.mcDevType), mc.getMCDataLength(),
                        arrayToHex(cmdbuffer.buffer(), MCMeta.getMCDataOffset(), mc.getMCDataLength())));
            } else {
                sb.append(String.format("{ %s }",
                        arrayToHex(cmdbuffer.buffer(), Meta.getMetaLength(), meta.getDataLength())));
            }
            sb.append("}");
            logCmd.infof("%s %s", isin ? "<-" : "->", sb.toString());
        }
    }

    private void logTrans(TRCommand meta) {
        if (logCmd.isEnabled() && logCmd.isMask(LOGCMD_TRANS)) {
            StringBuilder sb = new StringBuilder();
            logCmd.infof("TRANS[%s] { amount=%d cardType=%d currType=%d track2=%s "
                            + "RRN=%s flags=0x%X reqID=0x%08X }",
                    cidTR(meta.opType), meta.amount, meta.cardType, meta.currencyType, meta.track2,
                    meta.RRN, meta.flags, meta.requestID);
        }
    }

    private void logTransResult(TRResult res) {
        if (logCmd.isEnabled() && logCmd.isMask(LOGCMD_TRANS)) {
            logCmd.infof("TRANS-RESULT: res=%d auth=%s RRN=%s opNum=%s cardNum=%s "
                            + "cardEx=%s msg=%s date=%d time=%d isSB=%b "
                            + "termNum=%s cardName=%s SHA1=hex:%s reqID=0x%08X encryptedData=hex:%s cardID=hex:%s res2=hex:%s",
                    res.resultCode, res.authCode, res.RRN, res.opNumber, res.cardNumber,
                    res.cardExpire, res.message, res.date, res.time, res.isSberbankCard,
                    res.terminalNumber, res.cardName, res.SHA1, res.requestID, res.encryptedData, res.cardID, res.res2);
            ArrayList<SBPinpadDevice.PrinterTextBlock> prn = getLastPrintedTextAsBlocks();
            if (!prn.isEmpty()) {
                StringBuilder sb = new StringBuilder(500);
                sb.append("\n############################################################\n");
                for (SBPinpadDevice.PrinterTextBlock b : prn) {
                    sb.append(b.text);
                }
                sb.append("\n############################################################");
                logCmd.info(sb.toString());
            }
        }
    }

    /** Для удобства вывода информации - визуализация для ID. */
    private String cidCMD(int id, boolean isanswer) {
        if (!isanswer) {
            switch (id) {
                /** Типы команд первого уровня. */
                case CMD_GETREADY:
                    return "GETREADY";
                case CMD_CARDTEST:
                    return "CARDTEST";
                case CMD_MASTERCALL:
                    return "MASTERCALL";
                case CMD_TRANSACTION:
                    return "TRANSACTION";
                default:
                    return String.format("UNDEF=%02X", id); // Если неверный код.
            }
        }
        return String.format("%02X", id); // Если это ответ.
    }

    /** Для команды CMD_MASTERCALL: Типы исполняющих устройств. */
    private String cidMCDEV(int id) {
        switch (id) {
            case MCDEV_NO:
                return "NO";
            case MCDEV_DISPLAY:
                return "DISPLAY";
            case MCDEV_KEYBOARD:
                return "KEYBOARD";
            case MCDEV_PRINTER:
                return "PRINTER";
            case MCDEV_MAGREADER:
                return "MAGREADER";
            case MCDEV_CLOCK:
                return "CLOCK";
            case MCDEV_LAN:
                return "LAN";
            case MCDEV_MENU:
                return "MENU";
            case MCDEV_INPUTLINE:
                return "INPUTLINE";
            case MCDEV_BEEPER:
                return "BEEPER";
            case MCDEV_REBOOT:
                return "REBOOT";
            default:
                return "UNDEF=" + id;
        }
    }

    /** Для команды CMD_MASTERCALL: Типы операций. */
    private String cidMCOP(int id) {
        switch (id) {
            case MCOPER_OPEN:
                return "OPEN";
            case MCOPER_READ:
                return "READ";
            case MCOPER_WRITE:
                return "WRITE";
            case MCOPER_CLOSE:
                return "CLOSE";
            default:
                return "UNDEF=" + id;
        }
    }

    private String cidTR(int id) {
        switch (id) {
            case TR_PURCHASE:
                return "PURCHASE";
            case TR_CASH:
                return "CASH";
            case TR_REFUND:
                return "REFUND";
            case TR_BALANCE:
                return "BALANCE";
            case TR_PAYMENT:
                return "PAYMENT";
            case TR_FUNDS:
                return "FUNDS";
            case TR_CANCEL:
                return "CANCEL";
            case TR_ROLLBACK:
                return "ROLLBACK";
            case TR_SUSPEND:
                return "SUSPEND";
            case TR_COMMIT:
                return "COMMIT";
            case TR_PRE_AUTH:
                return "AUTH";
            case TR_PRE_COMPLETE:
                return "COMPLETE";
            case TR_CLOSESESSION:
                return "CLOSESESSION";
            case TR_TOTALS:
                return "TOTALS";
            case TR_GETTLVDATA:
                return "GETTLVDATA";
            case TR_SERVICEMENU:
                return "SERVICEMENU";
            case TR_REPRINT:
                return "REPRINT";
            case TR_READTRACK:
                return "READTRACK";
            case TR_SHOWSCREEN:
                return "SHOWSCREEN";
            case TR_WAITCARD_ON:
                return "ON";
            case TR_WAITCARD_CHECK:
                return "CHECK";
            case TR_WAITCARD_OFF:
                return "OFF";
            case TR_PRINTHELP:
                return "PRINTHELP";
            default:
                return "UNDEF=" + id;
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //  ТЕСТЫ (временный вариант для проверок на скорую руку)
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Тестирование проведения операций с пинпадом.
    private static void test1(String name) {
        LoggerExt.setConsoleFormatter();
        LoggerExt log = LoggerExt.getNewLogger("test1");
        log.enable(true).setLevel(Level.ALL);
        log.config("Инициализация приложения");

        if (name == null) name = "/dev/usb_SB";
        RS232Driver driver = new RS232Driver("tty9", name).bitrate(115200);
        SBPinpadDevice dev = new SBPinpadDevice("sbterm", driver, "cp866");
        dev.enableCmdLogger(true, LOGCMD_ALL);
        dev.enableRawLogger(true, LOGRAW_MSG);

        try {
            dev.getDriver().open();

            String info = dev.cmd_GetReady();
            log.infof("TESTPINPAD: %s", info);

            //dev.enableRawLogger(true, SBPinPadDevice.RAW_ALL);
            //dev.enableCmdLogger(true, LOGCMD_TRANS);

            TRResult rt = null;
            dev.cmd_MC_Display(1, "     АЗС N1");
            dev.cmd_MC_DisplayCls();//play(-100, "");
            dev.cmd_MC_Display(2, "_____________________");
            dev.cmd_MC_Display(3, "ТРК N3: \"АИ-95\"");
            dev.cmd_MC_Display(4, "Объем        1.00 л");
            dev.cmd_MC_Display(5, "Цена        35.00 р/л");
            dev.cmd_MC_Display(6, "---------------------");
            dev.cmd_MC_Display(7, "Сумма     = 35.00 р");
            dev.cmd_MC_Display(8, "_____________________");
            dev.cmd_MC_Display(9, "  ДО ПОЛНОГО БАКА!");
            dev.cmd_MC_Display(11, "    Подтвердить?");
            dev.cmd_MC_Beep(1);

            dev.cmd_MC_Keyboard();
            int mode = 0;
            while (mode == 0) {
                String keys = dev.cmd_MC_Keyboard();
                if (!keys.isEmpty()) {
                    int k = keys.charAt(0);
                    log.infof("KEYBOARD: '0x%02X'", k);
                    if (k == 0x0D) {
                        mode = 1;
                    }
                    if (k == 0x1B) {
                        mode = 2;
                    }
                } else {
                    Thread.sleep(100);
                }
            }
            dev.cmd_MC_Display(11, mode == 1 ? "    ПОДТВЕРЖДЕНО" : "      ОТМЕНЕНО");
            dev.cmd_MC_Display(12, "      КЛИЕНТОМ");

            if (mode == 1) {
                rt = dev.cmd_TR_Purchase(100);
                //
                dev.cmd_MC_Display(-100, "");
                dev.cmd_MC_Display(9, "  ОТМЕНА ОПЕРАЦИИ!");
                dev.cmd_MC_Display(11, "    Подтвердить?");
                dev.cmd_MC_Keyboard();
                mode = 0;
                while (mode == 0) {
                    String keys = dev.cmd_MC_Keyboard();
                    if (!keys.isEmpty()) {
                        int k = keys.charAt(0);
                        log.infof("KEYBOARD: '0x%02X'", k);
                        if (k == 0x0D) {
                            mode = 1;
                        }
                        if (k == 0x1B) {
                            mode = 2;
                        }
                    } else {
                        Thread.sleep(100);
                    }
                }
                //
                if (mode == 1) {
                    rt = dev.cmd_TR_Rollback(100, rt.authCode);
                }

            } else if (mode == 2) {
                rt = dev.cmd_TR_Cancel(100, "", "");
            }
            //rt = dev.cmd_TR_ReadCard();

        } catch (Exception ex) {
            ex.printStackTrace();
        } finally {
            dev.getDriver().close();
        }
    }

    public static void main(String[] args) {
        test1(null);
    }
}
