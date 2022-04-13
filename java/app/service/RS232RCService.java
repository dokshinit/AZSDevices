/*
 * Copyright (c) 2016. Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */

package app.service;

import app.DataBuffer;
import app.ExError;
import app.LoggerExt;
import app.driver.RS232Driver;
import util.CommonTools;

import static app.driver.RS232Driver.*;

/**
 * Абстрактный класс для сервиса удаленного управления RS232 устройством с последовательным выполнением команд.
 * Используется как базовый класс при реализации конкретных устройств.
 *
 * @author Aleksey Dokshin <dant.it@gmail.com> (01.09.16).
 */
public abstract class RS232RCService extends QueuedRCService {

    /** Логгер. */
    private final LoggerExt logger;

    /** Драйвер RS232 порта. */
    private final RS232Driver rs232driver;
    /** Таймаут между попытками открыть порт, если он закрыт. */
    private int regOpenTimeout = 500;
    /** Таймаут между проверками работоспособности порта, если он открыт. */
    private int regCheckTimeout = 500;
    /** Поток регенерации ком-порта. */
    private Thread regThread;

    /**
     * Конструктор.
     *
     * @param name        Имя сервиса.
     * @param udpport     Номер порта.
     * @param maxmsgsize  Максимальный размер сообщения.
     * @param queuesize   Размер очереди.
     * @param queuemode   Режим работы очереди.
     * @param comportname Имя устройства COM-порта.
     * @throws ExError Исключение при ошибках.
     */
    public RS232RCService(String name, int udpport, int maxmsgsize, int queuesize, ProcessingMode queuemode,
                          String comportname) throws ExError {
        super(name, udpport, maxmsgsize, queuesize, queuemode, true);
        this.logger = LoggerExt.getNewLogger("RS232RCService-" + name).enable(true).toFile();
        // Создание драйвера RS232 (до попытки его открытия ошибок быть не может).
        rs232driver = new RS232Driver("RS232-" + name, comportname);
        //driver.enableLogger(true);
    }

    /** Получение RS232 драйвера устройства. */
    protected RS232Driver getDriver() {
        return rs232driver;
    }

    /** Установка таймаутов регенератора порта. */
    protected void setRegeneratorTimeouts(int opentimeout, int checktimeout) {
        regOpenTimeout = opentimeout;
        regCheckTimeout = checktimeout;
    }

    /**
     * Регенератор порта. Осуществляет своевременное закрытие порта при потере связи, а также его открытие после
     * восстановлении связи (циклические попытки). Завершает работу при прерывании сервиса.
     */
    protected void rs232RegeneratorThreadBody() {
        logger.info("Начало работы регенератора!");
        try {
            while (!isTerminating()) {
                int n = rs232driver.regenerate();
                switch (n) {
                    case REG_OK: // Порт открыт, связь есть.
                        CommonTools.safeInterruptedSleep(regCheckTimeout); // Пауза до следующей проверки порта.
                        break;
                    case REG_DISCONNECTED: // Порт открыт, связи нет. (закрыли)
                        logger.info("Регенератор: Устройство отключено!");
                        break;
                    case REG_OPENED: // Порт закрыт, открыли.
                        logger.info("Регенератор: Устройство подключено!");
                        CommonTools.safeInterruptedSleep(regCheckTimeout); // Пауза до первой проверки открытого порта.
                        break;
                    case REG_NOTOPENED: // Порт закрыт, не открыли.
                        CommonTools.safeInterruptedSleep(regOpenTimeout); // Пауза до следующей попытки открыть порт.
                        break;
                }
            }
        } catch (Exception ex) {
            logger.errorf(ex, "Ошибка регенератора - %s!", ExError.exMsg(ex));
        }
        logger.info("Завершение работы регенератора!");
        rs232driver.close(); // На всякий случай.
    }

    @Override
    protected void fireOnStart() {
        super.fireOnStart();
        // Запуск регенератора COM-порта.
        if (!isTerminating()) {
            regThread = new Thread(this::rs232RegeneratorThreadBody);
            regThread.start();
        }
    }

    @Override
    protected void fireOnStop() {
        // Ожидаем прекращения потока регенератора.
        try {
            if (regThread != null && regThread.isAlive()) {
                regThread.interrupt(); // Для досрочного истечения таймаутов.
                regThread.join(); // Ожидаем завершения.
            }
        } catch (Exception ignore) {
        }
        rs232driver.close(); // Закрытие COM-порта.

        super.fireOnStop();
    }

    @Override
    protected void requestGetState(Meta meta, DataBuffer buffer) throws ExResultError {
        super.requestGetState(meta, buffer);

        // Добавляем информацию о состоянии командного процессора.
        buffer.posToEnd().tailBuffer(); // Расширяем буфер.
        logger.infof("RS:checkON:requestGetState(%s)", meta.toString());
        // 0-устройство отключено, 1-подключено (не используется checkDisconnect для исключения блокировки!).
        buffer.put(rs232driver.isClosed() ? 0 : 1);
        logger.infof("RS:checkOFF:requestGetState(%s)", meta.toString());
        buffer.flipBuffer();
    }

    // Коды ошибок-результатов выполнения команд устройства.
    public static final int DEV_OK = 0;
    public static final int DEV_DISCONNECTED = 1;
    public static final int DEV_UNSUPPORTED = 2;
    public static final int DEV_ERROR = 100;

    /**
     * Преобразование кода результата выполнения команды устройством в текстовый вид.
     *
     * @param deverrid Код результатов выполнения команды устройством.
     * @return Текстовое представление результата.
     */
    public static String getDeviceErrName(int deverrid) {
        switch (deverrid) {
            case DEV_OK:
                return "DEV_OK";
            case DEV_DISCONNECTED:
                return "DEV_DISCONNECTED";
            case DEV_UNSUPPORTED:
                return "DEV_UNSUPPORTED";
            case DEV_ERROR:
                return "DEV_ERROR";
            default:
                return "";
        }
    }

    /** Ошибка при поступлении неподдерживаемой команды. */
    public static class ExUnsupported extends ExError {
        public ExUnsupported(String fmt, Object... params) {
            super(fmt, params);
        }
    }
}
