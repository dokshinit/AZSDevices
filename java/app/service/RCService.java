/*
 * Copyright (c) 2016. Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */

package app.service;

import app.DataBuffer;
import app.ExError;
import app.LoggerExt;

import java.net.InetSocketAddress;
import java.net.SocketAddress;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Абстрактный сервис для удаленного управления путём подачи команд по сети. На базе этого класса потомки должны
 * реализовать конкретные схемы выполнения команд (как последовательное выполнение, так и параллельное - каждая команда
 * в своём отдельном потоке).
 * <pre>
 * 1. UDP пакет содержит сообщение.
 * 2. Сообщение представляет собой запрос сервису (перечень типов запросов фиксирован) и состоит из метаданных и
 * данных.
 * 3. Метаданные содержат служебную информацию и описание запроса. Запрос исполняется немедленно в потоке сервиса.
 * 4. Данные содержат дополнительную информацию, например для типа запроса EXECUTE или в ответах на запрос.
 * </pre>
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
public abstract class RCService extends NetUDPService {

    private final LoggerExt logger;

    /**
     * Конструктор.
     *
     * @param name    Название сервиса.
     * @param udpport Номер порта для сетевого обмена.
     */
    public RCService(String name, int udpport, int maxmsgsize) {
        super(name, udpport, maxmsgsize);
        this.logger = LoggerExt.getNewLogger("RCService-" + name).enable(true).toFile();
    }

    /** Успешно. */
    public static final int RESULT_OK = 0;
    /** Другая ошибка. */
    public static final int RESULT_ERROR = 100;

    /** Неверное состояние. */
    public static final int RESULT_RESULTNOTREADY = 1;
    /** Повтор команды которая уже есть в слотах. */
    public static final int RESULT_DUPLICATECOMMAND = 2;
    /** Нет свободных слотов для запуска команды. */
    public static final int RESULT_CANNOTEXECUTE = 3;
    /** Слот не найден (для команды). */
    public static final int RESULT_COMMANDNOTFOUND = 4;
    /** Неверный формат сообщения. */
    public static final int RESULT_WRONGFORMAT = 5;
    /** Неверное значение. */
    public static final int RESULT_WRONGVALUE = 6;
    /** Неверный ResultID. */
    public static final int RESULT_WRONGFINALIZATIONID = 7;

    /**
     * Обработчик поступившего сообщения. Ответ возвращается в том же буфере.
     *
     * @param address     Адрес отправителя сообщения.
     * @param receivetime Врема получения сообщения (локальное).
     * @param msgbuffer   Буфер с "телом" сообщения (рабочее окно).
     * @throws ExWrongMessage
     */
    protected void processMessage(SocketAddress address, long receivetime, DataBuffer msgbuffer) throws ExWrongMessage {

        Meta meta;
        try {
            // Парсим метаданные сообщения (полностью вместе с доп.параметрами!).
            meta = new Meta();
            meta.parseRequest(msgbuffer.rewind()).tail(); // Окно на остаток данных (тело команды).
        } catch (Exception ex) {
            throw new ExWrongMessage(ex.getMessage()); // Если метаданные не распарсились - ответ не отсылается!
        }
        logger.infof("rc:start:processMessage(%s)", meta.toString());

        // Если метаданные верные, то при ошибках обработки - отсылается ответ с ошибкой!
        try {
            switch (meta.requestType) {
                case GETSTATE: // Получение состояния сервиса и процессора команд.
                    requestGetState(meta, msgbuffer);
                    break;
                case EXECUTE: // Передача команды на испонение процессору.
                    requestExecute(address, receivetime, meta, msgbuffer);
                    break;
                case GETRESULT: // Запрос результата исполнения команды.
                    requestGetResult(meta, msgbuffer);
                    break;
                case FINALIZE:
                    requestFinalize(meta, msgbuffer);
                    break;
                case STOP: // Остановка сервиса (нужно ли вообще?).
                    requestStop(meta, msgbuffer);
                    break;
            }
        } catch (ExResultError ex) {
            meta.answerErrorID = ex.errorID;
            meta.answerErrorMessage = ex.getMessage();
            logger.infof("Результат-ошибка! {%s}", meta.toString());
        } catch (Exception ex) {
            meta.answerErrorID = RESULT_ERROR;
            meta.answerErrorMessage = ex.getMessage();
            logger.errorf(ex, "Ошибка при обработке! {%s}", meta.toString());
        }
        try {
            if (meta.answerErrorID != RESULT_OK) {
                meta.buildAnswer(msgbuffer.reset()).flipBuffer();
            }
        } catch (Exception ex) {
            logger.errorf(ex, "Ошибка постоения ответа! {%s}", meta.toString());
            throw new ExWrongMessage(ex.getMessage()); // Ответ не отсылается!
        }
        logger.infof("rc:end:processMessage(%s)", meta.toString());
    }

    /**
     * Выполнение команды сервиса: "GETSTATE".
     * <p>
     * Возвращает информацию о сервисе и процессоре команд.
     *
     * @param buffer Буфер.
     */
    protected void requestGetState(final Meta meta, final DataBuffer buffer) throws ExResultError {
        meta.buildAnswer(buffer.reset())
                .putLong(getLastStartTime()).putLong(getLastAutoRestartTime()).putLong(getLastStopTime()).flipBuffer();
        // TODO: Востребованы ли будут счетчики (сообщений\битых сообщений\...)? Надо ли?
        // TODO: Подумать, надо ли передавать информацию в виде текстовой XConfig строки? Для универсальности и независимости.
    }

    /**
     * Выполнение команды сервиса: "EXECUTE".
     * <p>
     * Если команда не дубль и есть свободные слоты - команда помещается в очередь на выполнение процессором. ВАЖНО:
     * Предварительно происходит освобождение слотов с истекшими таймаутами!
     *
     * @param meta   Метаданные сообщения команды.
     * @param buffer Данные команды (определяются как рабочая область).
     */
    protected abstract void requestExecute(final SocketAddress address, final long receivetime, final Meta meta,
                                           final DataBuffer buffer) throws ExResultError;

    /**
     * Выполнение команды сервиса: "GETRESULT". Возвращает или ошибку или имеющийся результат исполнения команды.
     *
     * @param meta   Метаданные сообщения команды.
     * @param buffer Данные команды (определяются как рабочая область).
     * @throws ExResultError
     */
    protected abstract void requestGetResult(final Meta meta, final DataBuffer buffer) throws ExResultError;

    /**
     * Выполнение команды сервиса: "FINALIZE".
     * <p>
     * Возвращается результат операции освобождения слота.
     *
     * @param meta   Метаданные сообщения команды.
     * @param buffer Данные команды (определяются как рабочая область).
     * @throws ExResultError
     */
    protected abstract void requestFinalize(final Meta meta, final DataBuffer buffer) throws ExResultError;

    /**
     * Выполнение команды сервиса: "STOP".
     *
     * @param buffer Буфер.
     */
    protected void requestStop(final Meta meta, final DataBuffer buffer) throws ExResultError {
        // Если задан таймаут автостарта - он перезаписывает его у сервиса: = -1 - окончательный останов, >= 0 - рестарт сервиса.
        // Если не задан - используется значение сервиса (т.е. также или окончательный останов или рестарт).
        if (buffer.remaining() >= 4) setAutoRestartTimeout(buffer.getInt());
        terminate();
        meta.buildAnswer(buffer.reset()).flipBuffer();
    }

    /** Текущий cmdID для финализации результатов исполнения команд. */
    private final AtomicLong finalizationID = new AtomicLong(System.currentTimeMillis());

    /** Генератор cmdID для финализации результатов исполнения команд  - атомарно инкрементируется. */
    protected long generateFinalizationID() {
        return finalizationID.addAndGet(1);
    }

    /** Нумератор типов запросов (не путать с командами в теле сообщения!). */
    public enum RequestType {

        /** Получение состояния сервиса. */
        GETSTATE(1),
        /** Выполнение команды. */
        EXECUTE(2),
        /** Получение результата выполнения команды. */
        GETRESULT(3),
        /** Финализация результата (освобождение результата). */
        FINALIZE(4),
        /** Остановка сервиса (в зависимости от параметров - остановка или рестарт). */
        STOP(100);

        /** Код типа запроса. */
        public int id;

        RequestType(int id) {
            this.id = id;
        }

        public static RequestType byId(int id) {
            for (RequestType s : RequestType.values()) if (s.id == id) return s;
            return null;
        }
    }

    /**
     * Метаданные сообщения. Данные касающиеся получения\отправки сообщения - в слоте.
     * <pre>
     * Бинарная структура сообщения (общая):
     * [2] CRC16.
     * [2] Длина сообщения (за вычетом 4 первых байт - CRC16 и длины).
     * ---
     * [4] cmdID отправителя.
     * [8] cmdID сообщения.
     * [1] cmdID типа запроса.
     * --- для типа запроса EXECUTE ---
     * [8] cmdID команды (уникальный для отправителя).
     * [4] Таймаут исполнения.
     * --- для типа запроса RESULT ---
     * [8] cmdID команды (уникальный для отправителя).
     * --- для типа запроса FINALIZE ---
     * [8] cmdID команды (уникальный для отправителя).
     * [8] cmdID верификации.
     * ---
     *
     * Если это ответ на команду, добавляется:
     * [1] Результат обработки запроса.
     * [N] Если результат не равен RESULT_OK=0, то добавляется строка с сообщением об ошибке иначе далее идут данные,
     * если они предусмотрены.
     *
     *
     * Команды ПЦ:
     * 1. Запрос отпуска Н\П по МК (блокировка средств). [dbsync]
     * 2. Фиксация отпуска Н\П по МК (списание и снятие блокировки). [dbsync]
     * 3. Синхронизация данных АЗС\ПЦ. [dbsync]
     * </pre>
     *
     * @author Aleksey Dokshin <dant.it@gmail.com> (20.02.16).
     */
    public static class Meta {

        /** [4] ID отправителя (уникальный среди отправителей). */
        public int senderID;
        /** [8] ID сообщения (уникальный на отправителе, возрастает при отправке(!) сообщения). */
        public long messageID;
        /** [1] Команда. */
        public RequestType requestType;
        /**
         * [8] cmdID команды (уникальный на отправителе, возрастает при создании команды(!), при повторе отправки
         * команды - не изменяется (!)). Используется для того, чтобы различать перепосылки команды. А также для
         * однозначного сопоставления команды и ответа на нее.
         */
        public long commandID;
        /**
         * [4] Предельное время ожидания результата выполнения команды (после чего результат отбрасывается). Отсчёт идёт
         * от времени приёма сообщения с командой EXECUTE. Если до его истечения исполнение переданной команды не
         * начато, то и не начинается. Если начато, но не закончено, то после завершения исполнения команды результат
         * очищается сразу. В противном случае результат хранится до истечения этого таймаута.
         */
        public int executeTimeout;
        /** [8] Код для предъявления при финализации результата. */
        public long finalizationID;

        /** Для ответа на запрос: Код ошибки (именно исполнения запроса, не путать с исполнением команды). */
        public int answerErrorID;
        /** Для ответа на запрос: Текст ошибки (именно исполнения запроса, не путать с исполнением команды). */
        public String answerErrorMessage;

        /** Конструктор. */
        public Meta() {
            this.senderID = 0;
            this.messageID = 0;
            this.requestType = null;
            this.commandID = 0;
            this.executeTimeout = 0;
            this.finalizationID = 0;
            this.answerErrorID = RESULT_OK;
            this.answerErrorMessage = "";
        }

        /** Конструктор копии. */
        public Meta(Meta src) {
            this.senderID = src.senderID;
            this.messageID = src.messageID;
            this.requestType = src.requestType;
            this.commandID = src.commandID;
            this.executeTimeout = src.executeTimeout;
            this.finalizationID = src.finalizationID;
            this.answerErrorID = src.answerErrorID;
            this.answerErrorMessage = src.answerErrorMessage;
        }

        /** Создание метаданных из данных буфера. */
        public DataBuffer parse(boolean isanswer, DataBuffer buffer) throws ExResultError {
            try {
                senderID = buffer.getInt();
                messageID = buffer.getLong();
                int id = buffer.get();
                requestType = RequestType.byId(id);
                if (requestType == null) {
                    throw new ExResultError(RESULT_WRONGVALUE, "Неверный код команды сервиса! {id=%d}", id);
                }

                commandID = 0;
                executeTimeout = 0;
                finalizationID = 0;
                answerErrorID = RESULT_OK;
                answerErrorMessage = "";

                switch (requestType) {
                    case EXECUTE:
                        // Для команды EXECUTE должны следовать дополнительные параметры для исполнения.
                        commandID = buffer.getLong();
                        executeTimeout = buffer.getInt();
                        break;

                    case GETRESULT:
                        // Для команды RESULT должны следовать дополнительные параметры.
                        commandID = buffer.getLong();
                        if (isanswer) { // Ответ содержит также cmdID для финализации.
                            finalizationID = buffer.getLong();
                        }
                        break;
                    case FINALIZE:
                        // Для команды FINALIZE должны следовать дополнительные параметры.
                        commandID = buffer.getLong();
                        finalizationID = buffer.getLong();
                }

                if (isanswer) { // Для ответа добавляем результат.
                    answerErrorID = buffer.getInt2();
                    if (answerErrorID != RESULT_OK && buffer.remaining() > 0) {
                        answerErrorMessage = buffer.getString(buffer.remaining());
                    } else {
                        answerErrorMessage = "";
                    }
                }

            } catch (ExResultError ex) {
                throw ex;
            } catch (Exception ex) {
                throw new ExResultError(RESULT_WRONGFORMAT, "Ошибка при разборе заголовка сообщения - %s!", ExError.exMsg(ex));
            }
            return buffer;
        }

        /** Создание метаданных запроса из данных буфера. */
        public DataBuffer parseRequest(DataBuffer buffer) throws ExResultError {
            return parse(false, buffer);
        }

        /** Создание метаданных ответа из данных буфера. */
        public DataBuffer parseAnswer(DataBuffer buffer) throws ExResultError {
            return parse(true, buffer);
        }

        /** Формирование данных в буфере из метаданных. */
        public DataBuffer build(boolean isanswer, DataBuffer buffer) throws ExResultError {
            try {
                if (requestType == null) {
                    throw new ExResultError(RESULT_WRONGVALUE, "Не задана команда!");
                }
                buffer.putInt(senderID).putLong(messageID).put(requestType.id);

                switch (requestType) {
                    case EXECUTE:
                        // Для команды EXECUTE должны следовать дополнительные параметры для исполнения.
                        buffer.putLong(commandID).putInt(executeTimeout);
                        break;

                    case GETRESULT:
                        // Для команды RESULT должны следовать дополнительные параметры.
                        buffer.putLong(commandID);
                        if (isanswer) { // Ответ содержит также cmdID для финализации.
                            buffer.putLong(finalizationID);
                        }
                        break;
                    case FINALIZE:
                        // Для команды FINALIZE должны следовать дополнительные параметры.
                        buffer.putLong(commandID).putLong(finalizationID);
                }

                if (isanswer) { // Для ответа добавляем результат.
                    buffer.putInt2(answerErrorID);
                    if (answerErrorID != RESULT_OK && !answerErrorMessage.isEmpty()) {
                        buffer.putFullString(answerErrorMessage);
                    }
                }

            } catch (ExResultError ex) {
                throw ex;
            } catch (Exception ex) {
                throw new ExResultError(RESULT_WRONGFORMAT, "Ошибка при построении сообщения - %s!", ExError.exMsg(ex));
            }
            return buffer;
        }

        /** Формирование данных запроса в буфере из метаданных. */
        public DataBuffer buildRequest(DataBuffer buffer) throws ExResultError {
            return build(false, buffer);
        }

        /** Формирование данных ответа в буфере из метаданных. */
        public DataBuffer buildAnswer(DataBuffer buffer) throws ExResultError {
            return build(true, buffer);
        }

        @Override
        public String toString() {
            return String.format(
                    "senderID=0x%X messageID=0x%X requestType=%d (%s)" +
                            " [timeout=%d finID=0x%X errID=%d errMsg=%s]",
                    senderID, messageID, requestType.id, requestType.name(),
                    executeTimeout, finalizationID, answerErrorID, answerErrorMessage);
        }
    }

    /**
     * Метаданные для исполнения команды. Хранит информацию об отправителе команды, о параметрах её получения, объект
     * команды.
     */
    public static class ExecMeta {

        /** Адрес отправителя команды (для информации). */
        public InetSocketAddress address;
        /** Время приема команды на стороне сервиса (для проверки таймаута исполнения). */
        public long receiveTime;
        /** Время начала ожидания получения результата (время завершение выполнения команды). */
        public long resultTime;
        /** Метаданные команды (формируются из заголовка сообщения с командой). */
        public Meta meta;
        /**
         * Буфер с данными команды или данными результата исполнения команды.
         * <p>
         * ВНИМАНИЕ! Предназначается ТОЛЬКО для слоя команд, данные из слоя запросов НЕ включает - например
         * answerErrorID / answerErrorMessage.
         */
        public DataBuffer buffer;

        public ExecMeta(int buffersize) {
            this.address = null;
            this.receiveTime = 0;
            this.resultTime = 0;
            this.meta = null;
            this.buffer = new DataBuffer(buffersize);
        }

        @Override
        public String toString() {
            return String.format("Address=%s reciveTime=%d resultTime=%d meta={%s}",
                    address, receiveTime, resultTime, meta.toString());
        }
    }

    /**
     * Исключение для прерывания исполнения запроса или команды с кодом ошибки и текстовой детализацией ошибки.
     */
    public static class ExResultError extends ExError {
        /** Код ошибки. */
        public final int errorID;

        public ExResultError(int errid, String msg) {
            super(msg);
            this.errorID = errid;
        }

        public ExResultError(int errid, String fmt, Object... params) {
            super(fmt, params);
            this.errorID = errid;
        }
    }
}
