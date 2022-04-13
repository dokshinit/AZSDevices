/*
 * Copyright (c) 2016. Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */

package app.service;

import app.ExError;
import app.FireCallback;
import app.LoggerExt;

/**
 * Абстрактный сервис. Может быть создан, запущен и остановлен.
 * <p>
 * Запускает в отдельном потоке "контроллер", который вызывает переопределяемый обработчик serviceBody(). При
 * возникновении исключений в обработчике сервис останавливается. После чего, если задан неотрицательный таймаут
 * перезапуска по его истечении перезапускается (не покидая того же потока!).
 * <p>
 * start() - если сервис еще не запущен, то запускается новый отдельный поток (ожидает успеха в течение таймаута).
 * <p>
 * stop() - если сервис еще не остановлен, то выставляется флаг прерывания работы и в течение таймаута ожидается
 * завершение обработчика, завершение потока и физической остановки сервиса.
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
public abstract class Service {

    private final LoggerExt logger;

    /** Таймаут для ожидания изменения состояния (при запуске\остановке). */
    public static final long DEFAULT_WAIT_TIMEOUT = 5000;
    /** Таймаут между автоматическими рестартами сервиса (при ошибках). */
    public static final long DEFAULT_AUTORESTART_TIMEOUT = -1;

    /** Название сервиса (для идентификации и логов). */
    public final String name;
    /** Поток выполняющий работу сервиса "в фоне". */
    private Thread thread;
    /** Таймаут ожидания запуска сервиса (время от запуска потока до состояния WORKING). */
    private long startTimeout;
    /** Таймаут ожидания остановки сервиса (время от подачи команды до состояния STOPPED). */
    private long  stopTimeout;
    /** Таймаут между авторестартами сервиса (если = -1, то авторестарт не производится!). */
    private long autoRestartTimeout;
    /** Текущее состояние сервиса. */
    private State state;
    /** Синхронизатор для состояния. */
    private final Object syncState = new Object();
    /** Флаг необходимости (запроса) прерывания обработчика и остановки сервиса. */
    private int terminating; // 0-нет прерывания, 1-прерывание сервиса, 2-прерывание без рестарта.

    public static final int TERMINATING_NO = 0;
    public static final int TERMINATING_STOP = 1;
    public static final int TERMINATING_HALT = 2;

    /** Время последнего запуска сервиса. */
    private long lastStartTime;
    /** Время последнего перезапуска сервиса (после ошибок). */
    private long lastAutoRestartTime;
    /** Время последней остановки сервиса. */
    private long lastStopTime;

    /**
     * Конструктор.
     *
     * @param name               Название сервиса.
     * @param starttimeout       Таймаут ожидания запуска сервиса.
     * @param stoptimeout        Таймаут ожидания остановки сервиса.
     * @param autorestarttimeout Таймаут для авторестарта сервиса при ошибках.
     */
    public Service(String name, long starttimeout, long stoptimeout, long autorestarttimeout) {
        this.logger = LoggerExt.getNewLogger("Service-" + name);
        this.name = name;
        this.state = State.CREATED;
        this.terminating = TERMINATING_NO;
        this.thread = null;
        this.startTimeout = starttimeout;
        this.stopTimeout = stoptimeout;
        this.autoRestartTimeout = autorestarttimeout;
        this.lastStartTime = 0;
        this.lastAutoRestartTime = 0;
        this.lastStopTime = 0;
    }

    /**
     * Конструктор.
     *
     * @param name               Название сервиса.
     * @param autorestarttimeout Таймаут для авторестарта сервиса при ошибках.
     */
    public Service(String name, long autorestarttimeout) {
        this(name, DEFAULT_WAIT_TIMEOUT, DEFAULT_WAIT_TIMEOUT, autorestarttimeout);
    }

    /**
     * Конструктор.
     *
     * @param name Название сервиса.
     */
    public Service(String name) {
        this(name, DEFAULT_AUTORESTART_TIMEOUT);
    }

    /** Получение названия сервиса. */
    public String getName() {
        return name;
    }

    /** Получение времени последнего старта сервиса. */
    public long getLastStopTime() {
        return lastStopTime;
    }

    /** Получение времени последнего рестарта сервиса. */
    public long getLastAutoRestartTime() {
        return lastAutoRestartTime;
    }

    /** Получение времени последней остановки сервиса. */
    public long getLastStartTime() {
        return lastStartTime;
    }

    public void setTimeouts(long startTimeout, long stopTimeout, long autoRestartTimeout) {
        this.startTimeout = startTimeout;
        this.stopTimeout = stopTimeout;
        this.autoRestartTimeout = autoRestartTimeout;
    }

    public void setWaitTimeouts(long startTimeout, long stopTimeout) {
        this.startTimeout = startTimeout;
        this.stopTimeout = stopTimeout;
    }

    public void setAutoRestartTimeout(long timeout) {
        this.autoRestartTimeout = timeout;
    }

    /**
     * Проверка на необходимость прерывания обработчика и остановки сервиса (обычной или полной).
     *
     * @return true - необходимо прервать сервис, false - нет.
     */
    public boolean isTerminating() {
        synchronized (syncState) {
            return terminating != TERMINATING_NO;
        }
    }

    /**
     * Проверка на необходимость полной остановки сервиса (с прерыванием обработчика и игнорированием рестарта).
     *
     * @return true - необходимо остановить сервис, false - нет.
     */
    public boolean isHalting() {
        synchronized (syncState) {
            return terminating == TERMINATING_HALT;
        }
    }

    /**
     * Получение значения флага-сигнализатора о необходимости прерывания сервиса.
     *
     * @return Значение флага прерывания сервиса: TERMINATING_NO, TERMINATING_STOP, TERMINATING_HALT.
     */
    public int getTerminating() {
        synchronized (syncState) {
            return terminating;
        }
    }

    /** Установка флага-сигнализатора о необходимости прерывания сервиса. */
    protected void terminate() {
        synchronized (syncState) {
            // Если сигнализатор утсановлен в HALT - не меняется, т.к. это более сильный сигнал.
            terminating = Math.max(terminating, TERMINATING_STOP);
        }
    }

    /** Установка флага-сигнализатора о необходимости прерывания сервиса и завершения его работы. */
    protected void halt() {
        synchronized (syncState) {
            terminating = TERMINATING_HALT;
        }
    }

    /**
     * Получение состояния сервиса.
     *
     * @return Состояние.
     */
    public State getState() {
        synchronized (syncState) {
            return state;
        }
    }

    /** Обработчик сервиса (реализация в потомках). Выполняется "контроллером". */
    protected abstract void serviceBody() throws ExError;

    /** Обработчик события. Запускается при старте сервиса. */
    protected void fireOnStart() {
        logger.infof("fireOnStart()");
    }

    /** Обработчик события. Запускается после остановки сервиса. */
    protected void fireOnStop() {
        logger.infof("fireOnStop()");
    }

    /** Обработчик события. Запускается после полной остановки сервиса. */
    protected void fireOnHalt() {
        logger.infof("fireOnHalt()");
    }

    /**
     * Установка состояния сервиса. Если состояние изменилось, то после изменения происходит уведомление всех ожидающих
     * изменения состояния! Только для внутренних нужд класса! Потомки и прочие классы к изменению состояния доступа
     * иметь не должны!
     *
     * @param newstate Состояние.
     */
    private void setState(State newstate) {
        synchronized (syncState) {
            if (this.state != newstate) {
                this.state = newstate;
                syncState.notifyAll(); // Уведомляем всех ожидающих о изменении состояния.
            }
        }
    }

    /** Рабочая процедура потока сервиса. */
    private void threadBody() {
        // Для восстановления значения после каждого перезапуска (сервис может менять его).
        final long savetimeout = autoRestartTimeout;

        lastStartTime = lastStopTime = lastAutoRestartTime = 0;
        // Крутим в цикле рабочую процедуру.
        while (!isHalting()) {
            // Запускаем сервис.
            lastStartTime = System.currentTimeMillis();
            autoRestartTimeout = savetimeout;
            setState(State.STARTING);
            FireCallback.safe(this::fireOnStart);

            if (!isTerminating()) {
                try {
                    setState(State.WORKING);
                    serviceBody();
                } catch (Exception ex) {
                    logger.errorf("Прерывание сервиса с ошибкой - %s!", ExError.exMsg(ex));
                }
            }
            // Обязательно выставляем флаг прерывания - для сигнализации другим потокам.
            if (autoRestartTimeout < 0) {
                halt(); // Если не задан рестарт - то это полная остановка сервиса.
            } else {
                terminate();
            }

            // Останавливаем сервис.
            setState(State.STOPPING);
            FireCallback.safe(this::fireOnStop);
            lastStopTime = System.currentTimeMillis();

            synchronized (syncState) {
                // Если это не полная остановка сервиса - авторестарт.
                if (!isHalting()) {
                    setState(State.AUTORESTARTING);
                    terminating = TERMINATING_NO;
                    try {
                        syncState.wait(autoRestartTimeout);
                    } catch (InterruptedException ex) {
                        // На прерывания не реагируем. Если было досрочное завершения ожидания,
                        // то это мог быть только вызов внешнего завершения. В этом случае
                        // обработка штатная.
                    }
                    lastAutoRestartTime = System.currentTimeMillis();
                }
            }
        }
        setState(State.STOPPED);
        FireCallback.safe(this::fireOnHalt);
    }

    /**
     * Ожидание достижения сервисом указанного состояния.
     *
     * @param st
     * @param isthreadcheck
     * @param timeout
     * @throws ExError
     */
    private void waitState(final State st, boolean isthreadcheck, long timeout) throws ExThread, ExTimeout {
        final long starttime = System.currentTimeMillis();
        synchronized (syncState) {
            while (getState() != st) {
                if (isthreadcheck) {
                    if (thread == null || !thread.isAlive()) {
                        throw new ExThread("Поток сервиса закрыт! {timeout=%d state=%s waitstate=%s}", timeout, getState(), st);
                    }
                }
                if (System.currentTimeMillis() - starttime > timeout) {
                    throw new ExTimeout("Истекло время ожидания состояния сервиса! {timeout=%d state=%s waitstate=%s}", timeout, getState(), st);
                }
                try {
                    syncState.wait(10);
                } catch (InterruptedException ignore) {
                    // На попытки прерывания не реагируем, дожидаемся нужного состояния или таймаута.
                }
            }
        }
    }

    /**
     * Запуск сервиса.
     *
     * @param timeout Время ожидания успешного запуска сервиса.
     * @throws ExWrongState
     * @throws ExThread
     * @throws ExTimeout
     */
    @SuppressWarnings("NestedSynchronizedStatement")
    public synchronized void start(long timeout) throws ExWrongState, ExThread, ExTimeout {
        synchronized (syncState) {
            switch (getState()) {
                case CREATED:
                case STOPPED:
                    // Если сервис не был запущен или был остановлен, тогда запускаем.
                    break;
                case STARTING:
                case WORKING:
                case AUTORESTARTING:
                    // Если запускается, работает или перезапускается, то ничего не делаем.
                    return;

                default:
                    // Прочие состояния - ошибочные (например состояние остановки), по идее не должны быть возможны из-за
                    // синхронизации start\stop! НО на самом деле вполне возможны, т.к. данные методы могут
                    // завершаться досрочно по таймауту не дождавшись нужного состояния сервиса!
                    throw new ExWrongState("Неверное состояние сервиса! {state=%s}", getState().name());
            }
            try {
                // Процесс рассылки запросов и приёма ответов.
                terminating = TERMINATING_NO;
                thread = new Thread(this::threadBody);
                thread.start();
            } catch (Exception ex) {
                throw new ExThread("Ошибка запуска потока сервиса - %s!", ExError.exMsg(ex));
            }
            waitState(State.WORKING, true, timeout);
        }
    }

    public synchronized void start() throws ExWrongState, ExThread, ExTimeout {
        start(startTimeout);
    }

    /**
     * Остановка процесса. Ожидает завершения.
     *
     * @param timeout Таймаут ожидания успешной остановки сервиса.
     * @throws ExThread
     * @throws ExTimeout
     */
    @SuppressWarnings("NestedSynchronizedStatement")
    public synchronized void stop(long timeout) throws ExThread, ExTimeout {
        synchronized (syncState) {
            switch (getState()) {
                case CREATED:
                case STOPPED:
                    // Если сервис не был запущен или был остановлен, тогда выходим.
                    return;
                default:
                    // Если работает или находится в промежуточном состоянии, то всеравно пытаемся остановить!
                    break;
            }
            if (thread == null || !thread.isAlive()) {
                // Да, вроде как сервис остановлен и можно было бы просто возврат сделать,
                // но завершенный сервис без состояния STOPPED - это явный косяк!
                throw new ExThread("Поток сервиса закрыт! {timeout=%d state=%s}", timeout, getState().name());
            }
            terminate();
            syncState.notifyAll(); // Уведомляем всех ожидающих.
            thread.interrupt(); // Инициируем прерывание (для выхода из sleep/wait).
            waitState(State.STOPPED, false, timeout);
        }
    }

    /** Остановка процесса. Ожидает завершения в течение таймаута по умолчанию. */
    public synchronized void stop() throws ExThread, ExTimeout {
        stop(stopTimeout);
    }

    /** Прерывание при истечении таймаута. */
    public static class ExTimeout extends ExError {

        public ExTimeout(String fmt, Object... params) {
            super(fmt, params);
        }
    }

    /** Прерывание при ошибках процесса сервиса. */
    public static class ExThread extends ExError {

        public ExThread(String msg) {
            super(msg);
        }

        public ExThread(String fmt, Object... params) {
            super(fmt, params);
        }
    }

    /** Исключение при неверных состояниях сервиса. */
    public static class ExWrongState extends ExError {

        public ExWrongState(String fmt, Object... params) {
            super(fmt, params);
        }
    }

    /** Исключение при прерывании сервиса. */
    public static class ExTerminate extends ExError {

        public ExTerminate(String fmt, Object... params) {
            super(fmt, params);
        }
    }

    /**
     * Нумератор состояний процесса.
     *
     * @author Докшин Алексей Николаевич <dant.it@gmail.com>
     */
    public enum State {

        /** Инициализирован. */
        CREATED(1),
        /** Запускается. */
        STARTING(2),
        /** Работает. */
        WORKING(3),
        /** Останавливается. */
        STOPPING(4),
        /** Перезагружается (момент паузы при автоперезагрузках). */
        AUTORESTARTING(5),
        /** Остановлен. */
        STOPPED(6);

        public int id;

        State(int id) {
            this.id = id;
        }

        public static State byId(int id) {
            for (State s : State.values()) if (s.id == id) return s;
            return null;
        }
    }
}
