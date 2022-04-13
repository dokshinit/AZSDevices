/*
 * Copyright (c) 2016. Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */

package app.service;

import app.DataBuffer;
import app.ExError;
import app.FireCallback;
import app.LoggerExt;

import java.net.InetSocketAddress;
import java.net.SocketAddress;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Абстрактный сервис для удаленного управления, реализующий очередь команд и возможность их последовательной и
 * параллельной обработки. В отдельном потоке запущен процессор команд, который осуществляет мониторинг очереди и запуск
 * команд на исполнение. Команды выполняются в отдельных потоках.
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
public abstract class QueuedRCService extends RCService {

    /** Логгер. */
    private final LoggerExt logger;

    /**
     * Массив слотов для команд (используется в качестве пула). Информацию в слотах проверяем и изменяем только
     * синхронизированно на cmdSlots! Слот занимется при постановке задачи в очередь и освобождается при финализации
     * команды или при истечении таймаута (при выделении слота для новой команды). В режиме SERIAL+SINGLE при
     * поступлении SERIAL команды может досрочно освобождаться (только в состоянии RESULT). Не подлежит любому
     * освобождению в состоянии EXECUTE.
     */
    private final Slot[] cmdSlots;
    /**
     * Общая сквозная очередь слотов, содержащих команды для выполнения. Информацию в очереди проверяем и изменяем
     * только синхронизированно на cmdSlots! В очереди находятся только команды ожидающие обработки. Команды, запущенные
     * на исполнение удаляются из списка! Таким образом в очереди не может быть больше элементов, чем общее количество
     * слотов.
     */
    private final LinkedBlockingQueue<Slot> cmdQueue;
    /**
     * Режим обработки команд очереди.
     */
    private final ProcessingMode prcMode;
    /**
     * Флаг режима постановки в очередь последовательных команд: true - допускается только одна команда (иначе -
     * занято), false - много команд (ждут своей очереди на последовательное выполнение). Проверка происходит среди всех
     * слотов, а не только в очереди!
     */
    private boolean isSingleSerialMode = false;

    /** Поток процессора команд. Занимается обслуживаением очереди и запуском команд на исполнение. */
    private Thread prcThread;


    /** Нумератор режима работы очереди. */
    public enum ProcessingMode {

        /** Полная параллельная обработка команд. */
        PARALLEL_FOR_ALL(1),
        /** Последовательная обработка для команд одного клиента. */
        SERIAL_FOR_CLIENT(2),
        /** Полная последовательная обработка всех команд. */
        SERIAL_FOR_ALL(3);

        public int id;

        ProcessingMode(int id) {
            this.id = id;
        }

        public static ProcessingMode byId(int id) {
            for (ProcessingMode s : ProcessingMode.values()) if (s.id == id) return s;
            return null;
        }
    }


    /**
     * Конструктор.
     *
     * @param name               Название сервиса.
     * @param udpport            Номер порта для сетевого обмена.
     * @param maxmsgsize         Максимальный размер сообщения.
     * @param queuesize          Размер очереди.
     * @param processingmode     Режим обработки команд.
     * @param issingleserialmode Режим размещения последовательных команд в очереди.
     */
    public QueuedRCService(String name, int udpport, int maxmsgsize, int queuesize,
                           ProcessingMode processingmode, boolean issingleserialmode) {
        super(name, udpport, maxmsgsize);
        this.logger = LoggerExt.getNewLogger("QueuedRCService-" + name).enable(true).toFile();
        this.cmdSlots = new Slot[queuesize]; // Заполнение массива слотами происходит по мере необходимости!
        this.cmdQueue = new LinkedBlockingQueue<>(queuesize);
        this.prcMode = processingmode;
        this.isSingleSerialMode = issingleserialmode;
    }

    @Override
    protected void fireOnStart() {
        FireCallback.safe(super::fireOnStart);
        if (!isTerminating()) {
            try {
                // Создание потока процессора команд (поток поледовательного исполнения команд).
                prcThread = new Thread(this::commandProcessorThreadBody);
                prcThread.start();
            } catch (Exception ex) {
                logger.errorf("Ошибка запуска потока процессора команд - %s!", ExError.exMsg(ex));
                terminate();
            }
        }
    }

    @Override
    protected void fireOnStop() {
        try {
            // Прерывание процессора (выполнение команды прерывается)!
            if (prcThread != null && prcThread.isAlive()) {
                prcThread.interrupt(); // Для досрочного истечения таймаутов.
                prcThread.join(); // Ожидаем завершения.
            }
        } catch (Exception ignore) {
        }
        FireCallback.safe(super::fireOnStop);
    }

    /**
     * Выполнение запроса: "GETSTATE".
     * <p>
     * Возвращает информацию о сервисе и процессоре команд.
     *
     * @param buffer Буфер.
     */
    @Override
    protected void requestGetState(final Meta meta, DataBuffer buffer) throws ExResultError {
        int qsize, qfree, sfree = 0, sexec = 0, sres = 0;

        // Синхронизация межпотокового доступа к слотам и очереди.
        logger.infof("Q:syncON:requestGetState(%s)", meta.toString());
        synchronized (cmdSlots) {
            for (Slot slot : cmdSlots) {
                if (slot == null) {
                    sfree++;
                } else {
                    switch (slot.state) {
                        case FREE:
                            sfree++;
                            break;
                        case QUEUE: // Тоже относим к исполняемым.
                        case EXECUTE:
                            sexec++;
                            break;
                        case RESULT:
                            sres++;
                            break;
                    }
                }
            }
            qfree = cmdQueue.remainingCapacity();
            qsize = cmdQueue.size();
        }
        logger.infof("Q:syncOFF:requestGetState(%s)", meta.toString());

        // Состояние сервиса.
        super.requestGetState(meta, buffer);

        // Добавляем информацию о состоянии командного процессора.
        buffer.posToEnd().tailBuffer(); // Расширяем буфер.
        buffer.put(prcMode.id).put(isSingleSerialMode ? 0 : 1).put(processorState.get().id)
                .putInt2(sfree).putInt2(sexec).putInt2(sres)
                .putInt2(qfree).putInt2(qsize);
        buffer.flipBuffer();
    }

    /**
     * Вспомогательная ф-ция. Проверка метаданных слота и указанных метаданных на совпадение отправителя.
     *
     * @param s Слот.
     * @param m Метаданные.
     * @return Результат: true - отправитель совпадает, false - нет.
     */
    private boolean isSameSender(Slot s, Meta m) {
        return s.execmeta.meta.senderID == m.senderID;
    }

    /**
     * Вспомогательная ф-ция. Проверка метаданных слота и указанных метаданных на совпадение команды (для этого должен
     * совпасть и отправитель).
     *
     * @param s Слот.
     * @param m Метаданные.
     * @return Результат: true - комада совпадает, false - нет.
     */
    private boolean isSameCommand(Slot s, Meta m) {
        return (s.execmeta.meta.senderID == m.senderID) && (s.execmeta.meta.commandID == m.commandID);
    }

    /** Вспомогательная функция для purgeSlotsAndGetFree: "выбирает" первый свободный. */
    private int _purge_GetFirstFree(final Slot s, int idxfree, int i) {
        if (idxfree == -1) { // Первый свободный слот запоминаем.
            logger.infof("PURGE_SLOTS - Select %s slot %d as free!", s == null ? "NULL" : "FREE", i);
            return i;
        }
        return idxfree;
    }

    /** Вспомогательная функция для purgeSlotsAndGetFree: освобождает слот, "выбирает" первый свободный. */
    private int _purge_Free(final Slot s, int idxfree, int i) {
        if (s != null && s.state != Slot.State.FREE) {
            if (s.state == Slot.State.QUEUE) cmdQueue.remove(s); // Если в очереди - удаляем из неё.
            s.state = Slot.State.FREE;
        }
        return _purge_GetFirstFree(s, idxfree, i);
    }

    /**
     * Проверка ВСЕХ слотов и освобождение, если необходимо. Проверка на наличие этой команды в слотах. Возвращает
     * индекс первого свободного слота (в массива слотов).
     *
     * @param meta Метаданные добавляемой команды.
     * @return Индекс свободного слота для размещения команды.
     * @throws ExResultError Ошибка операции.
     */
    private int purgeSlotsAndGetFree(final Meta meta) throws ExResultError {
        int free = 0; // Кол-во освобожденных слотов.
        int idxfree = -1; // Индекс первого свободного слота.
        int err_dup = -1; // Индекс слота дублирующейся команды.
        int err_cmdclientexist = -1; // Индекс слота с рабочей командой того же клиента (в SERIAL_CLIENT режиме).
        int err_cmdexist = -1; // Индекс слота с рабочей командой (в SERIAL_ALL режиме).
        long dt = System.currentTimeMillis(); // Фиксация текущего момента (время операции) для расчёта истечения таймаута.

        logger.infof("PURGE_SLOTS_START {slots=%d}", cmdSlots.length);

        // Пробегаем по ВСЕМ слотам в обязательном порядке.
        for (int i = 0; i < cmdSlots.length; i++) {
            Slot s = cmdSlots[i];
            if (s == null || s.state == Slot.State.FREE) { // Если слот свободен.
                idxfree = _purge_GetFirstFree(s, idxfree, i);
                continue; // Если свободен, то дальнейшие проверки не нужны.
            }

            // Освобождение слота с истекшим таймаутом.
            if ((s.state != Slot.State.EXECUTE) && (dt - s.execmeta.receiveTime > s.execmeta.meta.executeTimeout)) {
                idxfree = _purge_Free(s, idxfree, i);
                free++;
                continue; // Если освободили, то дальнейшие проверки не нужны.
            }

            // Если у нас есть ограничения на постановку в очередь - проверяем.
            if (isSingleSerialMode) {
                switch (prcMode) {
                    case SERIAL_FOR_ALL:
                        if (err_cmdexist == -1) { // Если пока ошибок не было и есть команда.
                            if (s.state == Slot.State.RESULT) { // Можно освобождать только в этом состоянии.
                                idxfree = _purge_Free(s, idxfree, i);
                                free++;
                                continue; // Если освободили, то дальнейшие проверки не нужны.
                            } else {
                                err_cmdexist = i;
                            }
                        }
                        break;
                    case SERIAL_FOR_CLIENT:
                        if (err_cmdclientexist == -1 && isSameSender(s, meta)) { // Если пока ошибок не было и есть команда клиента.
                            if (s.state == Slot.State.RESULT) { // Можно освобождать только в этом состоянии.
                                idxfree = _purge_Free(s, idxfree, i);
                                free++;
                                continue; // Если освободили, то дальнейшие проверки не нужны.
                            } else {
                                err_cmdclientexist = i;
                            }
                        }
                        break;
                    case PARALLEL_FOR_ALL: // Нет ограничений!
                        break;
                }
            }

            // Если слот не освобождён и команда уже подавалась - ошибка!
            if (err_dup == -1 && isSameCommand(s, meta)) {
                logger.infof("PURGE_SLOTS - Select slot %d as dup command! slot={%s}", meta.commandID, s.toString());
                err_dup = i;
            }
        }

        logger.infof("PURGE_SLOTS_END {err_dup=%d err_cmd=%d err_cmdclient=%d idxfree=%d}", err_dup, err_cmdexist, err_cmdclientexist, idxfree);

        if (err_dup != -1) {
            if (free > 0) notifyProcessor(); // Уведомляем процессор.
            throw new ExResultError(RESULT_DUPLICATECOMMAND, "Дублирование команды! {cmdid=%d}", meta.commandID);
        }

        if (err_cmdexist != -1) {
            if (free > 0) notifyProcessor(); // Уведомляем процессор.
            throw new ExResultError(RESULT_CANNOTEXECUTE, "В SERIAL_ALL + SINGLE режиме одновременно возможна только одна команда! " +
                    "{cmdid=%d senderid=%d}", meta.commandID, meta.senderID);
        }

        if (err_cmdclientexist != -1) {
            if (free > 0) notifyProcessor(); // Уведомляем процессор.
            throw new ExResultError(RESULT_CANNOTEXECUTE, "В SERIAL_CLIENT + SINGLE режиме одновременно возможна только одна команда " +
                    "для одного клиента {cmdid=%d senderid=%d}", meta.commandID, meta.senderID);
        }

        if (idxfree == -1) {
            if (free > 0) notifyProcessor(); // Уведомляем процессор.
            throw new ExResultError(RESULT_CANNOTEXECUTE, "Нет свободных слотов!");
        }

        // Проверка на специальный режим исполнения - без ожидания (таймаут <= 0). При котором выполнение только
        // если процессор свободен (нет команд в очереди). Если таймаут = 0, то команда выполняется, но результат
        // освобождается сразу!
        if (meta.executeTimeout <= 0 && !cmdQueue.isEmpty()) {
            if (free > 0) notifyProcessor(); // Уведомляем процессор.
            throw new ExResultError(RESULT_CANNOTEXECUTE,
                    "Невозможно выполнение команды без ожидания - очередь команд не пуста!");
        }

        // Если ошибок не было - не уведомляем процессор - он уведомится командой!
        return idxfree;
    }

    /**
     * Выполнение запроса: "EXECUTE".
     * <p>
     * Постановка команды в очередь на исполнение процессором команд (в потоке процессора команд). ВАЖНО: Только в этом
     * методе осуществляется отложенное создание слотов (в пределах массива) и освобождение слотов с истекшими
     * таймаутами!
     * <p>
     * Если команда - дублирует уже имеющуюся в слотах или нет свободных слотов - выбрасывается ошибка!
     *
     * @param meta   Метаданные сообщения команды.
     * @param buffer Данные команды (определяются как рабочая область).
     */
    @Override
    protected void requestExecute(final SocketAddress address, final long receivetime, final Meta meta,
                                  final DataBuffer buffer) throws ExResultError {

        // Синхронизация межпотокового доступа к слотам и очереди.
        synchronized (cmdSlots) {

            // Освобождаем неактуальные слоты. И получаем индекс свободного слота (если не нашли - исключение!).
            int idxfree = purgeSlotsAndGetFree(meta);

            // Убираем минус (т.к. минус - индикатор немедленного исполнения!).
            meta.executeTimeout = Math.abs(meta.executeTimeout);

            // Если свободный слот не был создан, то производим отложенное создание слота.
            if (cmdSlots[idxfree] == null) {
                cmdSlots[idxfree] = new Slot(buffer.capacity());
            }
            Slot slot = cmdSlots[idxfree];

            // Подготовка команды.
            slot.state = Slot.State.QUEUE;
            slot.execmeta.address = (InetSocketAddress) address;
            slot.execmeta.receiveTime = receivetime;
            slot.execmeta.resultTime = 0;
            slot.execmeta.meta = meta;
            slot.execmeta.buffer.reset().putArea(buffer).flip(); // Рабочая область по данным команды.

            // Строим успешный ответ за запрос.
            meta.buildAnswer(buffer.reset()).flipBuffer();

            cmdQueue.add(slot);
            notifyProcessor(); // Уведомляем процессор.
        }
    }

    /**
     * Выполнение команды сервиса: "GETRESULT". Возвращает или ошибку или имеющийся результат исполнения команды.
     *
     * @param meta   Метаданные.
     * @param buffer Буфер.
     * @throws ExResultError
     */
    @Override
    protected void requestGetResult(final Meta meta, final DataBuffer buffer) throws ExResultError {

        // Синхронизация межпотокового доступа к слотам и очереди.
        synchronized (cmdSlots) {
            // Находим слот с совпадающей командой и проверяем его состояние.
            for (Slot s : cmdSlots) {
                if (s != null && isSameCommand(s, meta)) {
                    // Нашли совпадающую команду.
                    switch (s.state) {
                        case FREE:
                            throw new ExResultError(RESULT_COMMANDNOTFOUND, "Слот уже освобожден!");
                        case QUEUE:
                        case EXECUTE:
                            throw new ExResultError(RESULT_RESULTNOTREADY, "Результат еще не готов!");
                        case RESULT:
                            // Копируем cmdID финализации в метаданные ответа.
                            meta.finalizationID = s.execmeta.meta.finalizationID;
                            // Формируем и возвращаем результат.
                            meta.buildAnswer(buffer.reset()).putArea(s.execmeta.buffer).flipBuffer();
                            return;
                    }
                }
            }
            // Не нашли совпадений.
            throw new ExResultError(RESULT_COMMANDNOTFOUND, "Нет слота с данной командой!");
        }
    }

    /**
     * Выполнение запроса: "FINALIZE".
     * <p>
     * Освобождение слота содержащего результат выполнения команды.
     *
     * @param meta   Метаданные.
     * @param buffer Буфер.
     * @throws ExResultError
     */
    @Override
    protected void requestFinalize(final Meta meta, final DataBuffer buffer) throws ExResultError {

        // Синхронизация межпотокового доступа к слотам и очереди.
        synchronized (cmdSlots) {
            // Находим слот с совпадающей командой и проверяем его состояние.
            for (Slot s : cmdSlots) {
                if (s != null && isSameCommand(s, meta)) {
                    // Нашли совпадающую команду.
                    switch (s.state) {
                        case FREE:
                            throw new ExResultError(RESULT_COMMANDNOTFOUND, "Слот уже освобожден!");
                        case QUEUE:
                        case EXECUTE:
                            throw new ExResultError(RESULT_RESULTNOTREADY, "Слот не в режиме хранения результата! {state=%s}",
                                    s.state.name());
                        case RESULT:
                            // Если совпадает код финализации (это указывает на то, что результат был получен).
                            if (s.execmeta.meta.finalizationID == meta.finalizationID) {
                                s.state = Slot.State.FREE; // Освобождаем слот!
                                meta.buildAnswer(buffer.reset()).flipBuffer();
                                notifyProcessor(); // Уведомляем процессор.
                                return;
                            }
                            throw new ExResultError(RESULT_WRONGFINALIZATIONID, "Неверный ID финализации! {finid=%d msgfinid=%d}",
                                    s.execmeta.meta.finalizationID, meta.finalizationID);
                    }
                }
            }
            // Не нашли совпадений.
            throw new ExResultError(RESULT_COMMANDNOTFOUND, "Нет слота с данной командой!");
        }
    }

    /** Нумератор состояний процессора команд. */
    public enum ProcessorState {

        /** Процессор команд не запущен или остановлен. */
        STOPPED(1),
        /** Ожидание поступления команды. Процессор команд свободен и готов к поступлению команд. */
        READY(2),
        /** Обработка команды. Процессор команд занят обработкой команды. */
        PROCESSING(3);

        /** Код состояния. */
        public int id;

        ProcessorState(int id) {
            this.id = id;
        }

        public static ProcessorState byId(int id) {
            for (ProcessorState s : ProcessorState.values()) if (s.id == id) return s;
            return null;
        }
    }

    /**
     * Состояние процессора команд (изменяется исключительно процедурой самого процессора!). Фигурирует в информации о
     * состоянии сервиса.
     */
    private AtomicReference<ProcessorState> processorState = new AtomicReference<>(ProcessorState.STOPPED);

    /** Возвращает ближайщую команду, которую можно обработать. */
    protected Slot peekQueue() {
        switch (prcMode) {
            case SERIAL_FOR_ALL:
                // Проверяем на отсутствие исполнения команд среди слотов и если нет - возвращаем первый элемент.
                for (Slot s : cmdSlots) {
                    if (s != null && s.state == Slot.State.EXECUTE) return null;
                }
                return cmdQueue.peek(); // Берем самый первый элемент.

            case SERIAL_FOR_CLIENT:
                // Если нужно - пробегаем всю очередь.
                for (Slot qs : cmdQueue) {
                    // Проверяем на отсутствие исполнения команд клиента среди слотов и если нет - возвращаем элемент.
                    boolean isexec = false;
                    for (Slot s : cmdSlots) {
                        if (s != null && isSameSender(qs, s.execmeta.meta) && s.state == Slot.State.EXECUTE) {
                            isexec = true;
                            break;
                        }
                    }
                    if (!isexec) return qs; // Если нет исполняемых этого клиента - возвращаем.
                }
                return null;

            case PARALLEL_FOR_ALL:
                return cmdQueue.peek(); // Берем самый первый элемент.
        }
        return null;
    }


    /** Тело потока процессора команд. */
    protected void commandProcessorThreadBody() {
        logger.info("Запуск потока выполнения команд!");
        processorState.set(ProcessorState.READY);

        while (!isTerminating()) {
            Slot slot = null;
            // Синхронизация межпотокового доступа к слотам и очереди.
            synchronized (cmdSlots) {
                // Проверяем в цикле слоты на исполнение.
                while (!isTerminating() && slot == null) {
                    slot = peekQueue(); // Проверяем очередь на наличие команд для исполнения.
                    logger.infof("peekQueue(%s)", slot == null ? "null" : slot.toString());
                    if (slot != null) {
                        cmdQueue.remove(slot); // По дизайну в очереди должны находиться только слоты в состоянии QUEUE.
                        slot.state = Slot.State.EXECUTE;
                    } else {
                        try {
                            logger.info("wait");
                            cmdSlots.wait();
                        } catch (InterruptedException ignore) { // Реагируем на прерывание штатно.
                        }
                        logger.info("stop wait");
                    }
                }
            }
            if (!isTerminating() && slot != null) {
                processorState.set(ProcessorState.PROCESSING);
                Slot f_slot = slot;
                slot.cmdThread = new Thread(() -> commandExecutionThreadBody(f_slot));
                slot.cmdThread.start();
                processorState.set(ProcessorState.READY);
            }
        }
        processorState.set(ProcessorState.STOPPED);
        logger.info("Завершение потока выполнения команд!");
    }

    /**
     * Тело потока исполнения команды - осуществляет безопасный вызова реального обработчика и производит корректное
     * завершение слота.
     */
    private void commandExecutionThreadBody(Slot slot) {
        logger.infof("Выполнение команды: %s", slot.toString());
        String err = null;
        try {
            commandExecutionBody(slot);
        } catch (Exception ex) {
            err = ex.getMessage();
        }
        // Изменяем состояние.
        // Синхронизация межпотокового доступа к слотам и очереди.
        synchronized (cmdSlots) {
            slot.execmeta.resultTime = System.currentTimeMillis();
            if (slot.execmeta.meta.executeTimeout == 0) {
                slot.state = Slot.State.FREE; // Освобождаем сразу - минуя ожидание финализации, cmdID не нужен.
            } else {
                slot.state = Slot.State.RESULT;
                // Задаём cmdID для последующей финализации результата!
                slot.execmeta.meta.finalizationID = generateFinalizationID();
                if (err != null) {
                    slot.execmeta.meta.answerErrorID = RESULT_ERROR;
                    slot.execmeta.meta.answerErrorMessage = err;
                }
                // Даже если таймаут уже истёк - результат сохраняем. Он будет доступен до следующего вызова
                // EXECUTE, который почистит все просроченные слоты в соответствии с режимом очереди.
            }
            notifyProcessor(); // Уведомляем процессор.
        }
        logger.infof("Завершение выполнения команды: %s", slot.toString());
    }

    /** Уведомлление процессора о изменении в слотах (возможно появилась возможность запустить ожидающую команду). */
    private void notifyProcessor() {
        synchronized (cmdSlots) {
            cmdSlots.notifyAll();
        }
    }

    /**
     * Обработчик выполнения команды (выполняется в отдельном потоке процессора команд).
     * <p>
     * ВНИМАНИЕ! Должен все внутренние ошибки корректно обработать - нельзя выкидывать исключения наружу. Результат
     * исполнения регулируется исключительно содержимым буфера с ответом! Если необходимо прерывание сервиса - только с
     * помощью terminate()!
     */
    protected abstract void commandExecutionBody(Slot slot);

    /**
     * Слот для хранения данных при обработке (исполнении) команды. Хранит информацию об отправителе команды, о
     * параметрах её получения, объект команды.
     */
    protected static class Slot {
        /** Состояния слота. Только для внутренних нужд класса! */
        private State state;
        /** Информация о команде для процессора. */
        public ExecMeta execmeta;
        /** Поток исполнения команды. Если null - исполняется в потоке процессора. */
        public Thread cmdThread;

        public Slot(int buffersize) {
            this.state = State.FREE;
            this.execmeta = new ExecMeta(buffersize);
            this.cmdThread = null;
        }

        @Override
        public String toString() {
            return String.format("State=%s execMeta={%s}", state.name(), execmeta.toString());
        }

        /** Нумератор состояний слота. */
        public enum State {

            /** Слот свободен, может быть выделен для исполнения команды. */
            FREE(1),
            /** Слот занят, поставлен в очередь на исполнение. */
            QUEUE(2),
            /** Слот занят, идёт просцесс исполнения команды. */
            EXECUTE(3),
            /** Слот занят, ожидает запроса получения результата исполнения команды и финализации. */
            RESULT(4);

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
}
