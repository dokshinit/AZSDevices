/*
 * Copyright (c) 2014, Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */
package app.device;

import app.DataBuffer;
import app.ExError;
import app.LoggerExt;
import app.driver.RS232Driver;
import jsscex.SerialPort;

import java.io.Closeable;

import static app.driver.RS232Driver.*;

/**
 * "Fuel Dispenser Topaz Device" Драйвер устройства управления ТРК, управляемого по протоколу Топаз.
 * <p>
 * <pre> АКТУАЛЬНЫЕ КОМАНДЫ ПРОТОКОЛА "ТОПАЗ" ДЛЯ РЕАЛИЗАЦИИ
 *
 * = СЛУЖЕБНЫЕ ================================================================
 * [+] Запрос статуса ТРК '1' (0x31)
 * [+] Санкционирование ТРК '2' (0x32)
 * [+] Сброс ТРК '3' (0x33)
 * [+] Запрос текущих данных отпуска топлива '4' (0x34)
 * [+] Запрос полных данных отпуска топлива '5' (0x35)
 * [+] Запрос показаний суммарников '6' (0x36)
 *      [-] Запись суммарников '6' (0x36)
 * [+deprecated] Запрос типа ТРК * '7' (0x37)
 * [+] Подтверждение записи итогов отпуска '8' (0x38)
 * [+] Запрос дополнительного статуса ТРК '9' (0x39)
 * [+] Чтение параметров ТРК 'N' (0x4E)
 *      [-] Запись параметров в ТРК 'O' (0x4F)
 * [+deprecated] Запрос номера версии протокола * 'P' (0x50)
 * [+] Установка цены за литр 'Q' (0x51)
 *      [-] Установка порога отключения клапана снижения * 'R' (0x52)
 *      [-] Установка дозы отпуска топлива в рублях 'S' (0x53)
 * [+] Установка дозы отпуска топлива в литрах 'T' (0x54)
 * [+] Долив дозы 'U' (0x55)
 * [+] Безусловный старт раздачи 'V' (0x56)
 * [+] Задание общих параметров 'W' (0x57)
 * [+] Чтение заданной дозы 'X' (0х58)
 *      [-] Запрос номера текущей транзакции * 'Y' (0x59)
 * [+] Сигнализация о внешней ошибке '[' (0х5B)
 * [+] Запрос кода внутренней ошибки '\' (0х5C)
 *      [-] Задание сетевого номера ТРК (раздаточного крана); чтение сетевого номера
 *          и режима работы рукава; чтение параметра модуля расширения ']' (0х5D)
 *
 * </pre>
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
@LoggerExt.LoggerRules(methods = {"logReq", "logAnsw"})
public final class FDTopazDevice implements Closeable {

    /** Логгер для отладки кода. */
    private final LoggerExt logger;

    /** Коммуникационный драйвер. */
    private final RS232Driver driver;
    /** Имя устройства (для логов). */
    private final String devname;

    /** Таймаут получения первого байта ответа на команду (35 сек.). */
    private final int answerTimeout = 400;

    /** Буфер для передаваемых команд. Длина данных определяется окном. */
    private final DataBuffer outbuffer;
    /** Флаг для отдельного хранения стартового байта запроса (может быть не STX при номере канала > 15). */
    private int outstx = 0;

    /** Буфер для принимаемых команд. Длина данных определяется окном. */
    private final DataBuffer inbuffer;
    /** Флаг для отдельного хранения типа ответа. */
    private int instx = 0;

    // Кол-во разрядов для внутреннего оперирования! Не имеет отношение к табло!!!
    private int volumeDigits = 5; // Кол-во разрядов для дозы.
    private int priceDigits = 4; // Кол-во разрядов для цены.
    private int sumDigits = 7; // Кол-во разрядов для стоимости.

    public FDTopazDevice(String devname, RS232Driver driver) {

        logger = LoggerExt.getNewLogger("FDTopazDevice-" + devname);

        this.driver = driver;
        this.devname = devname;
        outbuffer = new DataBuffer(3000);
        inbuffer = new DataBuffer(3000);
    }

    /**
     * Включение\выключение вывода отладочной информации с дублированием в файл.
     *
     * @param isEnable Флаг включения: true - включить, false - выключить.
     */
    public void enableLogger(boolean isEnable) {
        logger.enable(isEnable).toFile();
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

    // Служебные байт-коды протокола.
    private static final int DEL = 0x7F;
    private static final int ACK = 0x06;
    private static final int NAK = 0x15;
    private static final int CAN = 0x18;
    private static final int STX = 0x02;
    private static final int ETX = 0x03;
    private static final int BEL = 0x07;

    /**
     * Отправка команды устройству (из outcmdbuffer). Подтверждение приёма не предусмотрено.
     */
    private void send() throws ExDevice, ExDisconnect {
        int len = outbuffer.length();
        // Отправка команды.
        driver.write(DEL);
        driver.write(outstx); // Для номеров каналов от 1 до 15.
        int sum = 0; // Т.к. нестандартный механизм подсчёта контрольной суммы, то реализуем сами.
        for (int i = 0; i < len; i++) {
            int value = outbuffer.getAt(i);
            driver.write(value);
            driver.write(value ^ 0x7F); // Комплементарный байт.
            sum ^= value;
        }
        driver.write(ETX);
        sum = (sum ^ ETX) | 0x40; // Сумма захватывает один ETX.
        driver.write(ETX);
        driver.write(sum);
    }

    /**
     * Получение ответа от устройства (в incmdbuffer). Посылка подтверждения не предусмотрена.
     */
    private void receive() throws ExDevice, ExTimeout, ExDisconnect, ExFormat, ExControlSum {
        instx = 0;
        inbuffer.reset();
        int value = driver.read(answerTimeout); // Чтение маркера DEL (как первый байт ответа - должен поступить в пределах таймаута).
        if (value != DEL) {
            throw new ExFormat("Ожидается DEL! (" + value + ")");
        }
        instx = driver.read(); // Стартовый байт ответа (является флагом!).
        switch (instx) {
            case STX: // Стандартный ответ.
                int calcsum = 0;
                while (true) { // Читаем в цикле данные пока не дойдем до конца ответа.
                    value = driver.read();
                    if (value >= 0x20) { // Это данные.
                        int covalue = driver.read(); // Считываем комплементарный байт к данным.
                        if (covalue < 0x21) {
                            throw new ExFormat("Ко-значение вне диапазона! (value=" + value + " co=" + covalue + ")");
                        }
                        if ((value ^ 0x7F) != covalue) {
                            throw new ExFormat("Неверное ко-значение! (value=" + value + " co=" + covalue + ")");
                        }
                        calcsum ^= value;
                        inbuffer.put(value);
                    } else { // Не данные - ожидаем завершающий блок.
                        if (value != ETX) {
                            throw new ExFormat("Ожидается ETX1! (" + value + ")");
                        }
                        calcsum = (calcsum ^ ETX) | 0x40;
                        if ((value = driver.read()) != ETX) {
                            throw new ExFormat("Ожидается ETX2! (" + value + ")");
                        }
                        int sum = driver.read();
                        if (sum != calcsum) {
                            throw new ExControlSum("Контрольная сумма! (calc=" + calcsum + " sum=" + sum + ")");
                        }
                        break; // Прерываем цикл.
                    }
                }
                break;

            case ACK: // Короткий ответ - команда принята.
            case CAN: // Короткий ответ - команда принята, но исполнена быть не может.
            case NAK: // Короткий ответ - команда не принята (не поддерживается).
                break;

            default:
                throw new ExFormat("Неверный тип ответа! (" + instx + ")");
        }
        inbuffer.flip(); // Фиксируем размер ответа.
    }

    /**
     * Выполнение команды, содержащейся в outcmdbuffer с помещением ответа в answ. При неудачной передаче команды или её
     * неисполнении (по любой причине) - выбрасывается соответствующий тип исключения.
     *
     * @param ishaveanswer Флаг необходимости получения ответа на команду.
     */
    private void execute(boolean ishaveanswer) throws ExDevice, ExTimeout, ExDisconnect,
            ExFormat, ExControlSum, ExUnsupportedCommand, ExCannotExecute, ExAttempts {

        // Делаем 3 попытки цикла отправки+получения.
        for (int n = 3; n > 0; n--) {
            try {
                driver.safeClearRead(); // Очистка входящего потока от возможных недополученных данных.
                send();
                if (!ishaveanswer) return; // Если ответ не подразумевается - выходим.
                receive();
                // Анализ ответа.
                switch (instx) {
                    case STX:
                    case ACK: // Команда выполнена и подтверждена ответом.
                        return;
                    case NAK: // Команда отвергнута - не поддерживается. Сразу прерываем цикл!
                        throw new ExUnsupportedCommand();
                    case CAN: // Команда не может быть выполнена в данный момент - продолжаем попытки.
                        throw new ExCannotExecute();
                }
            } catch (ExFormat | ExControlSum ex) { // Ошибка передачи - можно пытаться повторить.
                if (n == 1) throw ex; // Если это последняя попытка - выдаём ошибку.
            } catch (ExDevice | ExTimeout | ExDisconnect | ExCannotExecute | ExUnsupportedCommand ex) {
                throw ex; // Сразу прерываем цикл.
            }
        }
        throw new ExAttempts(); // Исчерпано количество попыток.
    }

    /** По умолчанию подразумевается, что принимается ответ. */
    private void execute() throws ExDevice, ExTimeout, ExDisconnect, ExFormat, ExControlSum, ExUnsupportedCommand, ExCannotExecute, ExAttempts {
        execute(true);
    }

    ////////////////////////////////////////////////////////////////////////////
    // Состояния раздаточного рукава ТРК.
    ////////////////////////////////////////////////////////////////////////////
    /**
     * ТРК выключена, пистолет повешен.
     */
    public static final int FD_STATE_OFF = 0;
    /**
     * ТРК выключена, пистолет снят.
     */
    public static final int FD_STATE_ON = 1;
    /**
     * ТРК выключена, ожидание снкционирования налива.
     */
    public static final int FD_STATE_ACCEPT = 2;
    /**
     * ТРК включена, отпуск топлива.
     */
    public static final int FD_STATE_FUEL = 3;
    /**
     * ТРК выключена, налив завершен, ожидание подтверждения отпуска.
     */
    public static final int FD_STATE_FINISH = 4;

    ////////////////////////////////////////////////////////////////////////////
    // Причины состояний (только для FD_STATE_FINISH), как дополнительный флаг состояния.
    ////////////////////////////////////////////////////////////////////////////
    /**
     * Отпущенная доза меньше или соответствует заданной.
     */
    public static final int FD_REASON_NORMAL = 0;
    /**
     * Перелив (или несанкционированный отпуск).
     * <p>
     * Примечание: Несанкционированный отпуск возникает при обнаружении отпуска топлива при отсутствии команды
     * САНКЦИОНИРОВАНИЕ или при наличии этой команды, но без пуска ТРК клиентом. Также несанкционированным отпуском
     * считается любой повторно зафиксированный отпуск НП после окончания отпуска заданной дозы, поэтому переход ТРК в
     * статус ‘4’ (0x34)+’1’ (0х31) возможен из любого состояния.
     */
    public static final int FD_REASON_OVER = 1;

    ////////////////////////////////////////////////////////////////////////////
    // Флаги состояний (только для FD_STATE_FINISH).
    ////////////////////////////////////////////////////////////////////////////
    public static final int FD_STATEFLAG_ERROR = 1; // Флаг наличия внутренней ошибки (битовое поле).

    ////////////////////////////////////////////////////////////////////////////
    // КОМАНДЫ УПРАВЛЕНИЯ ТРК
    ////////////////////////////////////////////////////////////////////////////

    /**
     * Очистка OUT буфера и установка номера канала и кода команды.
     *
     * @param channel Канал.
     * @param idcmd   Код команды.
     */
    private DataBuffer outSet(int channel, int idcmd) {
        outstx = STX;
        if (channel > 15) {
            outstx = BEL + (channel / 15) - 1; // смещение 7(BEL)=15, 8=30, 9=45 и т.д.
            channel = channel % 15; // остаток от деления = адрес.
        }
        return outbuffer.reset().puts(((channel & 0xF) | 0x20) & 0x7F, idcmd & 0x7F);
    }

    /**
     * Очистка OUT буфера и установка кода команды (широковещательные запросы).
     *
     * @param idcmd Код команды.
     */
    private DataBuffer outSet(int idcmd) {
        outstx = STX;
        return outbuffer.reset().put(idcmd & 0x7F);
    }

    /**
     * Проверка наличия указанного кол-ва байт для чтения в IN буфере. Если меньше - выбрасывается исключение.
     *
     * @param mustbe Кол-во необходимых байт.
     * @throws ExFormat
     */
    private void exIfInFewRemaining(int mustbe) throws ExFormat {
        if (inbuffer.remaining() < mustbe) {
            throw new ExFormat("Недостаточная длина данных! (" + inbuffer.remaining() + " < " + mustbe + ")!");
        }
    }

    /**
     * Перемотка в начало IN буфера и проверка наличия указанного кол-ва байт для чтения. Если меньше - выбрасывается
     * исключение.
     *
     * @param mustbe Кол-во необходимых байт.
     * @throws ExFormat
     */
    private void exIfInRewindFewRemaining(int mustbe) throws ExFormat {
        inbuffer.rewind();
        exIfInFewRemaining(mustbe);
    }

    public class Result_GetState { // <editor-fold defaultstate="collapsed">

        /** Состояние. */
        public int idstate;
        /** Для состояния 4 - причина состояния. */
        public int idreason;
        /** Для состояния 4 - флаги состояний (пока только один флаг 0x1 - наличие внутренней ошибки). */
        public int iflags;

        public Result_GetState() {
            idstate = inbuffer.rewind().get() & 0xF;
            idreason = iflags = 0;
            if (inbuffer.hasRemaining()) {
                idreason = inbuffer.get() & 0xF;
                if (inbuffer.hasRemaining()) iflags = inbuffer.get() & 0xF;
            }
        }

        @Override
        public String toString() {
            return String.format("Состояние=%d Причина=%d Флаги=0x%0X", idstate, idreason, iflags);
        }
    } // </editor-fold>


    /**
     * 0x31 Запрос статуса ТРК. Возможные статусы ТРК до запроса – все допустимые. Возможные статусы ТРК после запроса –
     * не меняются.
     *
     * @param channel Канал.
     * @return Ответ.
     */
    public synchronized Result_GetState cmd_GetState(int channel) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x31).flip();
        execute();
        return new Result_GetState();
    }

    /**
     * 0x32 Санкционирование ТРК. Возможные статусы ТРК до запроса – '0', '1' или '8'. Возможные статусы ТРК после
     * запроса – '2'.
     * <p>
     * Примечание. Команда САНКЦИОНИРОВАНИЕ ТРК должна поступать в ТРК только в следующих случаях: после прохождения
     * команды УСТАНОВКА ДОЗЫ ОТПУСКА. При этом после ответа АСК регистр полных данных отпуска ТРК обнуляется и любой
     * зафиксированный отпуск топлива ведет к инкременту данного регистра вплоть до следующей команды САНКЦИОНИРОВАНИЕ;
     * после прохождения команды ДОЛИВ ДОЗЫ, при этом не происходит обнуления регистра полных данных отпуска ТРК и любой
     * зафиксированный отпуск топлива ведет к инкременту данного регистра вплоть до следующей команды САНКЦИОНИРОВАНИЕ;
     * после обнаружения СУ статуса '8' для санкционирования отпуска заданной с БМУ дозы, при этом после ответа АСК
     * регистр полных данных отпуска ТРК обнуляется и любой зафиксированный отпуск топлива ведет к инкременту данного
     * регистра вплоть до следующей команды САНКЦИОНИРОВАНИЕ.
     *
     * @param channel Канал.
     */
    public synchronized void cmd_Accept(int channel) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x32).flip();
        execute();
    }

    /**
     * 0x33 Сброс ТРК. Возможные статусы ТРК до запроса – '2' ,'3' или '8'. Возможные статусы ТРК после запроса – '4' +
     * '0' или '4'+'1'; '1' или '0'.
     * <p>
     * Примечания: 1. При поступлении команды СБРОС ТРК должно произойти выключение ТРК, если она была включена; 2.
     * Переход в статусы '4' + '0' или '4' + '1' осуществляется из статусов '2' или '3'; 3. Переход в статусы '0' или
     * '1' осуществляется ТОЛЬКО из статуса '8'.
     *
     * @param channel Канал.
     */
    public synchronized void cmd_Reset(int channel) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x33).flip();
        execute();
    }

    /**
     * 0x34 Запрос текущих данных отпуска топлива. Возможные статусы ТРК до запроса – все допустимые. Возможные статусы
     * ТРК после запроса – не меняются.
     *
     * @param channel Канал.
     * @return Ответ.
     */
    public synchronized long cmd_GetDoseVolume(int channel) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x34).flip();
        execute();
        exIfInRewindFewRemaining(6);
        return inbuffer.getLongFromString(6); // Причем первый символ - '0'.
    }

    public class Result_GetDose { // <editor-fold defaultstate="collapsed">

        /** Доза. */
        public long volume;
        /** Сумма. */
        public long sum;
        /** Цена. */
        public long price;

        public Result_GetDose() throws ExFormat {
            exIfInRewindFewRemaining(volumeDigits + sumDigits + priceDigits);
            volume = inbuffer.getLongFromString(volumeDigits);
            sum = inbuffer.getLongFromString(sumDigits);
            price = inbuffer.getLongFromString(priceDigits);
        }

        @Override
        public String toString() {
            return String.format("Доза=%d Цена=%d Сумма=%d", volume, price, sum);
        }
    }

    /**
     * 0x35 Запрос полных данных отпуска топлива. Возможные статусы ТРК до запроса – все допустимые. Возможные статусы
     * ТРК после запроса – не меняются.
     *
     * @param channel Канал.
     * @return Ответ.
     */
    public synchronized Result_GetDose cmd_GetDose(int channel) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x35).flip();
        execute();
        return new Result_GetDose();
    }

    public class Result_GetCounter { // <editor-fold defaultstate="collapsed">

        /** Показания счётчика литров. */
        public long volume;
        /** Показания счётчика рублей. */
        public long sum;

        public Result_GetCounter() throws ExFormat {
            exIfInRewindFewRemaining(16);
            int n = inbuffer.rewind().remaining() / 2;
            volume = inbuffer.getLongFromString(n);
            sum = inbuffer.getLongFromString(n);
        }

        @Override
        public String toString() {
            return String.format("Литры=%d Рубли=%d", volume, sum);
        }
    }

    /**
     * 0x36 Запрос показаний суммарников. Возможные статусы ТРК до запроса – все допустимые. Возможные статусы ТРК после
     * запроса – не меняются.
     * <p>
     * Примечания: Для получения корректных данных опрос суммарников рекомендуется производить в статусах '0' или '1'.
     *
     * @param channel Канал.
     * @return Ответ.
     */
    public synchronized Result_GetCounter cmd_GetCounter(int channel) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x36).flip();
        execute();
        return new Result_GetCounter();
    }

    public class Result_GetType { // <editor-fold defaultstate="collapsed">

        /** Тип ТРК. */
        public int type;
        /** Кол-во разрядов в соответствующих полях. */
        public int volumeDigits, sumDigits, priceDigits;

        public Result_GetType() throws ExFormat {
            type = inbuffer.rewind().get();
            switch (type) {
                case 0x41:
                    volumeDigits = 6;
                    sumDigits = 4;
                    priceDigits = 6;
                    break;
                case 0x42:
                    volumeDigits = 6;
                    sumDigits = 6;
                    priceDigits = 8;
                    break;
                case 0x43:
                    volumeDigits = 6;
                    sumDigits = 4;
                    priceDigits = 6;
                    break;
                case 0x44:
                    volumeDigits = 6;
                    sumDigits = 4;
                    priceDigits = 6;
                    break;
                case 0x45:
                    volumeDigits = 6;
                    sumDigits = 4;
                    priceDigits = 6;
                    break;
                case 0x46:
                    volumeDigits = 6;
                    sumDigits = 6;
                    priceDigits = 8;
                    break;
                case 0x47:
                    volumeDigits = 6;
                    sumDigits = 6;
                    priceDigits = 8;
                    break;
                case 0x48:
                    volumeDigits = 5;
                    sumDigits = 4;
                    priceDigits = 7;
                    break;
                default:
                    throw new ExFormat("Неверный тип ТРК! (" + type + ")");
            }
        }

        @Override
        public String toString() {
            return String.format("Тип=0x%0X Кол-во цифр в: Доза=%d Цена=%d Сумма=%d", type, volumeDigits, priceDigits, sumDigits);
        }
    }

    /**
     * 0x37 Запрос типа ТРК. Возможные статусы ТРК после запроса – все допустимые. Возможные статусы ТРК после запроса –
     * не меняются.
     * <p>
     * Примечания: 1. Количество разрядов L, М и Т не связано с количеством разрядов на табло ТРК. 2. Устройства серий
     * "Топаз-106К" всегда имеют идентификатьор 'H'.
     * <p>
     * <pre>
     * ID - Идентификатор
     * L  - Кол-во разрядов литров,
     * M  - Кол-во разрядов цены,
     * T  - Кол-во разрядов стоимости
     * ---------------------
     * ID          L  M  T
     * ---------------------
     * 'A' (0х41)  6  4  6
     * 'В' (0х42)  6  6  8
     * 'С' (0х43)  6  4  6
     * 'D' (0х44)  6  4  6
     * 'E' (0х45)  6  4  6
     * 'F' (0х46)  6  6  8
     * 'G' (0х47)  6  6  8
     * 'H' (0x48)  5  4  7
     * </pre>
     *
     * @param channel Канал.
     * @return Ответ.
     */
    @Deprecated
    public synchronized Result_GetType cmd_GetType(int channel) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x37).flip();
        execute();
        return new Result_GetType();
    }

    /**
     * 0x38 Подтверждение записи итогов отпуска. Возможные статусы ТРК до запроса – '4' + '0' или '4' + '1'. Возможные
     * статусы ТРК после запроса – '0' или '1'.
     * <p>
     * Примечание: Для успешного выполнения команды требуется предварительный успешный вызов команды 0x35 и неизменность
     * этих данных (отсутствие отпуска топлива) до момента подачи команды 0x38. В противном случае ответ будет CAN и
     * будет необходимо повторить считывание и подтверждение. Если используется расширенный запрос данных отпуска, то
     * вместо команды 0x35 необходимо считывание базового параметра ТРК. Пераметр определяется типом отпуска (по объему
     * или по стоимости, пересчитанной в объем) - отпущенный объем - код параметра = 1.
     *
     * @param channel Канал.
     */
    public synchronized void cmd_Confirm(int channel) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x38).flip();
        execute();
    }

    public class Result_GetExtState { // <editor-fold defaultstate="collapsed">

        public int intstate, extstate;
        public int nover, nstep, ownstate;

        public Result_GetExtState() throws ExFormat {
            exIfInRewindFewRemaining(9);
            intstate = inbuffer.getIntFromString(1);
            extstate = inbuffer.getIntFromString(1);
            nover = inbuffer.getIntFromString(2);
            nstep = inbuffer.getIntFromString(2);
            ownstate = inbuffer.getIntFromString(3);
        }

        @Override
        public String toString() {
            return String.format("Внутр.остояние=0x%0X Внеш.состояние=0x%0X Переход=%d Шаг=%d Родное состояние=%d", intstate, extstate, nover, nstep, ownstate);
        }
    }

    /**
     * 0x39 Запрос дополнительного статуса ТРК. Возможные статусы ТРК до запроса – все допустимые. Возможные статусы ТРК
     * после запроса – не меняются.
     *
     * @param channel Канал.
     * @return Ответ.
     */
    public synchronized Result_GetExtState cmd_GetExtState(int channel) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x39).flip();
        execute();
        return new Result_GetExtState();
    }

    /**
     * 0x50 Запрос номера версии протокола. Возможные статусы ТРК до запроса – все допустимые. Возможные статусы ТРК
     * после запроса – не меняются.
     *
     * @param channel Канал.
     * @return Версия протокола.
     */
    @Deprecated
    public synchronized int cmd_GetProtocolVersion(int channel) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x50).flip();
        execute();
        exIfInRewindFewRemaining(8);
        return inbuffer.getIntFromString(8);
    }

    /**
     * 0x51 Установка цены за литр. Возможные статусы ТРК до запроса – '0', '1' или '8'. Возможные статусы ТРК после
     * запроса – не меняются.
     * <p>
     * Примечание: При изменении цены нефтепродукта (далее НП) данные о предыдущей заправке в контроллере ТРК
     * обнуляются!
     *
     * @param channel Канал.
     * @param price   Цена.
     */
    public synchronized void cmd_SetPrice(int channel, long price) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x51).putLongAsString(price, 4).flip();
        execute();
    }

    /**
     * 0x54 Установка дозы отпуска топлива в литрах. Возможные статусы ТРК до запроса – '0', '1'. Возможные статусы ТРК
     * после запроса – не меняются.
     *
     * @param channel Канал.
     * @param volume  Доза.
     * @param isfull  Флаг заправки "до полного бака".
     */
    public synchronized void cmd_SetVolume(int channel, long volume, boolean isfull) throws ExTimeout, ExControlSum,
            ExUnsupportedCommand, ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x54).putLongAsString(volume, 5).put(isfull ? 0x31 : 0x30).flip(); // Поле юстировки не используем!
        execute();
    }

    /**
     * 0x55 Долив дозы. Возможные статусы ТРК до запроса – '0' + '1'. Возможные статусы ТРК после запроса – не
     * меняются.
     * <p>
     * Примечание – После команды ДОЛИВ ДОЗЫ должна поступать команда САНКЦИОНИРОВАНИЕ ТРК.
     *
     * @param channel Канал.
     */
    public synchronized void cmd_TopUp(int channel) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x55).flip();
        execute();
    }

    /**
     * 0x56 Безусловный старт раздачи. Команда вызывает пуск колонки НЕЗАВИСИМО от положения раздаточного крана. В
     * остальном эффект от команды полностью аналогичен пуску ТРК при снятии крана (нажатии кнопки ПУСК/СТОП). Возможные
     * статусы ТРК до запроса – '2'. Возможные статусы ТРК после запроса – '3'.
     *
     * @param channel Канал.
     */
    public synchronized void cmd_ForceStart(int channel) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x56).flip();
        execute();
    }

    /**
     * 0x57 Задание общих параметров. Широковещательная команда, принимается одновременно всеми ТРК на линии. Возможные
     * статусы ТРК до запроса – определяются номером параметра. Возможные статусы ТРК после запроса – не меняются.
     *
     * @param idparam Код параметра (0x0-0xF / 0x30-0x3F).
     * @param values  Значения параметров (массив, 0x0-0xF / 0x30-0x3F).
     */
    public synchronized void cmd_SetCommonParamerer(int idparam, int... values) throws ExTimeout, ExControlSum,
            ExUnsupportedCommand, ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(0x57).puts(0x30 | (idparam & 0xF));
        for (int v : values) outbuffer.put(0x30 | (v & 0xF));
        outbuffer.flip();
        execute(false);
    }

    public class Result_GetParamCodes { // <editor-fold defaultstate="collapsed">

        public int[] codes;

        public Result_GetParamCodes() throws ExFormat {
            exIfInRewindFewRemaining(1);
            int len = inbuffer.remaining();
            codes = new int[len];
            for (int i = 0; i < len; i++) codes[i] = inbuffer.get();
        }
    }

    /**
     * 0x4E чтение кодов параметров, поддерживаемых ТРК. Возможные статусы ТРК до запроса – все допустимые. Возможные
     * статусы ТРК после запроса – не меняются.
     * <p>
     * Для увеличения количества программируемых параметров, поддерживаемых протоколом, в дополнение к обычным
     * параметрам с кодами 0х30–0х5D, вводятся расширенные параметры с кодами 0х5E–0х8B. В качестве признака расширенных
     * параметров используется код 0х5Е, наличие которого непосредственно за кодом команды (или за кодом STX ответа)
     * означает, что все параметры, указанные в посылке, являются расширенными. В этом случае все коды параметров в
     * посылке, отличаются от фактических на величину 0х2Е (например, код 0х30 означает параметр 0х5Е и т.д.). При
     * работе с обычными параметрами, а также в коротких ответах (NAK, CAN) признак расширенных параметров в посылку не
     * вставляется.
     *
     * @param channel Канал.
     * @return Ответ.
     */
    public synchronized Result_GetParamCodes cmd_GetParamCodes(int channel) throws ExTimeout, ExControlSum,
            ExUnsupportedCommand, ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x4E).flip();
        execute();
        return new Result_GetParamCodes();
    }

    public class Result_GetExtParamCodes { // <editor-fold defaultstate="collapsed">

        public int[] codes;

        public Result_GetExtParamCodes() throws ExFormat {
            exIfInRewindFewRemaining(2);
            int marker = inbuffer.get();
            if (marker == 0x5E) throw new ExFormat("Неверный маркер! (" + marker + " != 0x5E)");
            codes = new int[inbuffer.remaining()];
            for (int i = 0; i < codes.length; i++)
                codes[i] = inbuffer.get() + 0x2E; // Коды расширенных параметров (0x5E-0x8B)!
        }
    }

    /**
     * 0x4E чтение кодов расширенных параметров, поддерживаемых ТРК. Возможные статусы ТРК до запроса – все допустимые.
     * Возможные статусы ТРК после запроса – не меняются.
     *
     * @param channel Канал.
     * @return Ответ.
     */
    public synchronized Result_GetExtParamCodes cmd_GetExtParamCodes(int channel) throws ExTimeout, ExControlSum,
            ExUnsupportedCommand, ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x4E).put(0x5E).flip();
        execute();
        return new Result_GetExtParamCodes();
    }

    /**
     * 0x4E Чтение параметров ТРК. Вариант 2 – чтение значений конкретных параметров ТРК. Возможные статусы ТРК до
     * запроса – все допустимые.
     * <p>
     * В случае если ТРК не поддерживает ни одного из запрашиваемых параметров, используется ответ NAK.
     * <p>
     * При запросе СУ значения параметра, не поддерживаемого ТРК, в ответе ТРК данный параметр просто игнорируется и не
     * включается в данные ответа. При превышении в сформированном ответном пакете максимально допустимого для данного
     * протокола числа байт в пакете пакет не передается и следует ответ CAN. Для предотвращения подобных ситуаций при
     * запросе большого числа параметров необходимо пользоваться несколькими командами чтения параметров с разными
     * номерами параметров.
     *
     * @param channel Канал.
     * @param idparam Код параметра (0x30-0x5D, 0x5E-0x8B);
     * @return Ответ - параметр в виде строки.
     */
    public synchronized String cmd_GetStrParam(int channel, int idparam) throws ExTimeout, ExControlSum,
            ExUnsupportedCommand, ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        if (idparam < 0x5E) { // Обычный параметр.
            outSet(channel, 0x4E).put(idparam).flip();
            execute();
            if (inbuffer.rewind().remaining() > 1 && inbuffer.get() == idparam) {
                return inbuffer.getBCDHex(inbuffer.remaining());
            }
        } else { // Расширенный параметр.
            outSet(channel, 0x4E).put(0x5E).put(idparam - 0x2E).flip();
            execute();
            if (inbuffer.rewind().remaining() > 2 && inbuffer.get() == 0x5E && inbuffer.get() == idparam - 0x2E) {
                return inbuffer.getBCDHex(inbuffer.remaining());
            }
        }
        throw new ExFormat("Неверный ответ!");
    }

    /**
     * 0x4E Чтение параметров ТРК. Вариант 2 – чтение значений конкретных параметров ТРК. Возможные статусы ТРК до
     * запроса – все допустимые.
     *
     * @param channel Канал.
     * @param idparam Код параметра (0x30-0x4F, 0x5E-0x7D);
     * @return Ответ - параметр в виде числе (т.к. диапазоны позволяют - использован int, если нужно - можно переделать
     * на long).
     */
    public synchronized long cmd_GetLongParam(int channel, int idparam) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        if (idparam < 0x5E) {
            outSet(channel, 0x4E).put(idparam).flip();
            execute();
            if (inbuffer.rewind().remaining() > 1 && inbuffer.get() == idparam) {
                return inbuffer.getLongFromString(inbuffer.remaining());
            }
        } else {
            outSet(channel, 0x4E).put(0x5E).put(idparam - 0x2E).flip();
            execute();
            if (inbuffer.rewind().remaining() > 2 && inbuffer.get() == 0x5E && inbuffer.get() == idparam - 0x2E) {
                return inbuffer.getLongFromString(inbuffer.remaining());
            }
        }
        throw new ExFormat("Неверный ответ!");
    }

    public synchronized int cmd_GetIntParam(int channel, int idparam) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        return (int) cmd_GetLongParam(channel, idparam);
    }

    /**
     * 0x58 Чтение заданной дозы. Возможные статусы ТРК до запроса – '0','1' или '8'. Возможные статусы ТРК после
     * запроса – не меняются.
     * <p>
     * Данная команда используется для контроля заданной дозы после задания дозы командами задания дозы, командой долива
     * или заданием дозы с БМУ до выполнения команды САНКЦИОНИРОВАНИЯ. При отсутствии предварительно заданной дозы в
     * статусах '0' или '1' используется ответ CAN.
     *
     * @param channel Канал.
     * @return Объем заданной дозы.
     */
    public synchronized long cmd_CheckVolume(int channel) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x58).flip();
        execute();
        exIfInRewindFewRemaining(6);
        return inbuffer.getLongFromString(inbuffer.remaining());
    }

    /**
     * 0x5B Сигнализация о внешней ошибке. Возможные статусы ТРК до запроса – '0','1'. Возможные статусы ТРК после
     * запроса – не меняются.
     * <p>
     * Примечания:<br> 1. Данная команда содержит значение кода ошибки в диапазоне от 0 до 999 и время, в течение
     * которого необходимо сигнализировать об этой ошибке (на табло устройства или другим способом), в интервале от 0 до
     * 99 секунд.<br> 2. Нулевое значение поля "Код ошибки" означает отмену режима сигнализации об ошибке. Кроме того,
     * выход из режима сигнализации об ошибке происходит при подаче любой команды, отличной от запроса статуса ТРК.<br>
     * 3. Нулевое значение поля "Продолжительность сигнала" означает неограниченную по времени (постоянную)
     * сигнализацию. 4. Ответ CAN используется в случае, если статус ТРК не является разрешенным для данной команды.
     *
     * @param channel Канал.
     * @param iderror Код ошибки.
     * @param time    Время индикации.
     */
    public synchronized void cmd_ShowError(int channel, int iderror, int time) throws ExTimeout, ExControlSum,
            ExUnsupportedCommand, ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x5B).putLongAsString(iderror, 3).putLongAsString(time, 2).flip();
        execute();
    }

    public class Result_GetError { // <editor-fold defaultstate="collapsed">

        public int iderror;
        public int idadd1;
        public int idadd2;

        public Result_GetError() throws ExFormat {
            exIfInRewindFewRemaining(3);
            iderror = inbuffer.getIntFromString(3);
            idadd1 = idadd2 = 0;
            if (inbuffer.remaining() >= 2) {
                idadd1 = inbuffer.getIntFromString(2);
                if (inbuffer.remaining() >= 2) {
                    idadd2 = inbuffer.getIntFromString(2);
                }
            }
        }
    }

    /**
     * 0x5C Запрос кода внутренней ошибки. Возможные статусы ТРК до запроса – все допустимые. Возможные статусы ТРК
     * после запроса – не меняются.
     * <p>
     * Примечание – Каждый из дополнительных кодов может отсутствовать (при условии отсутствия всех полей, следующих за
     * ним). При отсутствии внутренних ошибок (т.е. в нормальном состоянии ТРК) используется короткий ответ CAN.
     * <pre>
     * Код  Описание   Доп.Код1    Доп.Код2
     * ----------------------------------------------------------------------
     * 1   Ошибка энергонезависимой памяти
     * 2   Отключены все рукава ТРК
     * 3   Имеются одинаковые сетевые адреса в одной ТРК
     * 4   Неверное использование специального (3-го) режима работы рукава
     * 5   Необходимо отключить рукав 3 и 4 или не использовать режим работы рукава "2-я сторона"
     * 6   Неисправность одной из гидроветвей  1=[Номер гидроветви]
     * 7   Неисправность одного из каналов датчика расхода  1=[Номер рукава]  2=[Номер канала]
     * 8   Неисправность или отсутствие электромеханического суммарника, встроеннго в табло NP-1 или NP-2
     * 9   Неисправность топливного термодатчика
     * 10  Недопустимая температура топлива
     * 11  Неисправность внутреннего термодатчика
     * 12  Потеря связи с модулем расширения
     * 13  Нет связи с системой управления
     * 14  Недостаточное количество модулей расширения для обслуживания всех задействованных рукавов
     * 15  Неисправность табло КОР-1
     * ----------------------------------------------------------------------
     * </pre>
     *
     * @param channel Канал.
     * @return Ответ.
     */
    public synchronized Result_GetError cmd_GetError(int channel) throws ExTimeout, ExControlSum, ExUnsupportedCommand,
            ExAttempts, ExCannotExecute, ExFormat, ExDevice, ExDisconnect {
        outSet(channel, 0x5C).flip();
        execute();
        return new Result_GetError();
    }

    public static class ExFormat extends ExError {
        public ExFormat(String message) {
            super(message);
        }
    }

    public static class ExControlSum extends ExError {
        public ExControlSum(String message) {
            super(message);
        }
    }

    public static class ExUnsupportedCommand extends ExError {
    }

    public static class ExCannotExecute extends ExError {
    }

    public static class ExAttempts extends ExError {
    }

    ////////////////////////////////////////////////////////////////////////////
    // ПРОВЕРКА ОТПУСКА
    ////////////////////////////////////////////////////////////////////////////
    public static void main(String[] args) throws Exception {
        LoggerExt dbg = LoggerExt.getCommonLogger().enable(true);
        RS232Driver driver = new RS232Driver("rs232", "/dev/ttyUSB0").bitrate(4800)
                .databits(SerialPort.DATABITS_7).stopbits(SerialPort.STOPBITS_2).parity(SerialPort.PARITY_EVEN);
        FDTopazDevice dev = new FDTopazDevice("Topaz", driver);

        try {
            dev.getDriver().open();

            /**
             * Алгоритм отпуска дозы:
             * <pre>
             * 0. Ожидание команды на отпуск топлива.
             * 1. Проверка состояния ТРК (getstate: должно быть: 0 или 1).
             * 2. Задание цены (setprice).
             * 3. Задание дозы (setvolume).
             * 4. Проверка информации о дозе (getdose: объём=0, цена, сумма=0).
             * 5. Проверка объёма (checkvolume).
             * 5.1. Считывание показаний суммарника (getcounter). Нужно ли?
             * 6. Санкционирование.
             * 7. Нужен ли безусловный пуск?
             * 8. Циклическая проверка состояния налива (getstate + getdose\getdosevolume).
             * 9. При завершении налива подтверждение дозы (confirm).
             * 9.1. Считывание показаний суммарника (getcounter).
             * 10. Переход к началу.
             * </pre>
             */
            int ch = 1;
            int volume = 1000;
            int price = 1234;

            Result_GetState state = dev.cmd_GetState(ch);
            dbg.infof("Тестирование отпуска топлива на ТРК №%d:", ch);
            dbg.infof("1. Текущее состояние (GetState): state=0x%02X reason=0x%02X flag=0x%02X", state.idstate, state.idreason, state.iflags);
            Result_GetDose x = dev.cmd_GetDose(ch);
            dbg.infof("1.1. Последняя доза (GetDose): Доза=%d Цена=%d Сумма=%d", x.volume, x.price, x.sum);
            Result_GetCounter c = dev.cmd_GetCounter(ch);
            dbg.infof("1.2. Текущий счетчик (GetCounter): Литры=%d Рубли=%d", c.volume, c.sum);
            Result_GetError rerr = dev.cmd_GetError(ch); // Не поддерживается Топаз-133!
            dbg.infof("1.3. Текущая ошибка (GetError): Код=%d", rerr.iderror, rerr.idadd1, rerr.idadd2);


        if (state.idstate == FD_STATE_OFF || state.idstate == FD_STATE_ON) {
            dev.cmd_SetPrice(1, price);
            dbg.infof("2. Установка цены (SetPrice): %.2f", (double) price / 100.0);

            dev.cmd_SetVolume(1, volume, false);
            dbg.infof("3. Установка объема (SetVolume): %.2f", (double) volume / 100.0);

            Result_GetDose dose = dev.cmd_GetDose(1);
            dbg.infof("4. Проверка дозы (GetDose): (volume=%.2f L * price=%.2f) = sum=%.2f", (double) dose.volume / 100.0, (double) dose.price / 100.0, (double) dose.sum / 100.0);

            if (dose.volume == 0 && dose.sum == 0 && dose.price == price) {
                long checkvolume = dev.cmd_CheckVolume(1);
                dbg.infof("5. Проверка объема (CheckVolume): %.2f L", (double) checkvolume / 100.0);

                if (checkvolume == volume) {
                    dev.cmd_Accept(1);
                    dbg.infof("6. Разрешение отпуска (Accept)!");

                    int n = 0;
                    while (state.idstate != FD_STATE_FINISH && n < 5) {
                        try {
                            state = dev.cmd_GetState(1);
                            if (state.idstate == FD_STATE_FUEL || state.idstate == FD_STATE_FINISH) {
                                dose = dev.cmd_GetDose(1);
                            }
                            dbg.infof("7. Отпуск (GetState+GetDose) [0x%02X:%02X:%02X] Dose [%.2f * %.2f = %.2f]",
                                    state.idstate, state.idreason, state.iflags,
                                    (double) dose.volume / 100.0, (double) dose.price / 100.0, (double) dose.sum / 100.0);
                            Thread.sleep(100);
                            n = 0;
                        } catch (Exception ex) {
                            n++;
                        }
                    }

                    dose = dev.cmd_GetDose(1);
                    dbg.infof("7. Проверка дозы (GetDose): (volume=%.2f L * price=%.2f) = sum=%.2f", (double) dose.volume / 100.0, (double) dose.price / 100.0, (double) dose.sum / 100.0);

                    dev.cmd_Confirm(1);
                    dbg.infof("8. Подтверждение отпуска (Confirm)!");

                    long counter = dev.cmd_GetCounter(1).volume;
                    dbg.infof("9. Получение счетчика (GetCounter) = %.2f L", (double) counter / 100.0);

                    dbg.infof("END");

                } else {
                    dbg.errorf("Error checkvolume!");
                }
            } else {
                dbg.errorf("Error dose!");
            }
        } else {
            dbg.errorf("Error state!");
            if (state.idstate == FD_STATE_FINISH) {
                Result_GetDose dose = dev.cmd_GetDose(1);
                dev.cmd_Confirm(1);
            }
            if (state.idstate == FD_STATE_OFF || state.idstate == FD_STATE_ON || state.idstate == FD_STATE_ACCEPT) {
                dev.cmd_Reset(1);
            }
        }


        } catch (Exception ex) {
            ex.printStackTrace();
        } finally {
            dev.close();
            dbg.info("FINISH!");
        }
    }
}
