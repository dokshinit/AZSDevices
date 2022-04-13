/*
 * Copyright (c) 2016. Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */

package app.service;

import app.DataBuffer;
import app.LoggerExt;
import app.device.SBPinpadDevice.TRResult;
import app.device.SBPinpadDevice.PrinterTextBlock;
import util.CommonTools;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.text.SimpleDateFormat;
import java.util.Date;

import static app.service.SBPinpadRCService.*;

/**
 * Клиент удаленного управления пинпадом СБ.
 *
 * @author Aleksey Dokshin <dant.it@gmail.com> (03.03.16).
 */
public class SBPinpadRCClient extends RCClient {

    private static final LoggerExt logger = LoggerExt.getNewLogger("SBPinpadRCClient").enable(true).toFile();

    protected final DataBuffer cmdbuffer;
    /** Разрешение дисплея: кол-во символов в строке. */
    protected int displayColumnsCount;
    /** Разрешение дисплея: кол-во строк. */
    protected int displayRowsCount;

    public SBPinpadRCClient(int clientid, InetSocketAddress address, int maxmsgsize,
                            int displayColumnsCount, int displayRowsCount) throws IOException {
        super(clientid, address, maxmsgsize);
        this.cmdbuffer = new DataBuffer(maxmsgsize);
        this.displayColumnsCount = displayColumnsCount;
        this.displayRowsCount = displayRowsCount;
    }

    public SBPinpadRCClient(int clientid, InetSocketAddress address, int maxmsgsize) throws IOException {
        this(clientid, address, maxmsgsize, 21, 13); // Разрешение по умолчанию для модели Verifone VX820.
    }

    public static class ResultGetState extends RCClient.ResultGetState {
        public int processingMode;
        public boolean isSingleSerialMode;
        public int processorState;
        public int slotsFree, slotsExecute, slotsResult;
        public int queueFree, queurSize;
        /** Флаг дисконнекта устройства. */
        public boolean isDeviceConnected;

        public ResultGetState(RCClient.ResultGetState src, DataBuffer buffer) {
            super(src);
            // QueuedRCService
            processingMode = buffer.get();
            isSingleSerialMode = buffer.get() != 0;
            processorState = buffer.get();
            slotsFree = buffer.getInt2();
            slotsExecute = buffer.getInt2();
            slotsResult = buffer.getInt2();
            queueFree = buffer.getInt2();
            queurSize = buffer.getInt2();
            // RS232RCService
            isDeviceConnected = (buffer.get() != 0);
        }
    }

    @Override
    public synchronized ResultGetState remoteGetState(int answertimeout) throws ExRequestError, ExTimeout {
        return new ResultGetState(super.remoteGetState(answertimeout), tmpBuffer);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    private void execCmd(int answertimeout, int executetimeout) throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
        ResultExecute rExec = remoteExecute(answertimeout, executetimeout, cmdbuffer);
        if (rExec.answerErrorID != RCService.RESULT_OK) {
            throw new ExAnswerError(rExec.answerErrorID, rExec.answerErrorMessage);
        }
        cmdbuffer.rewind();
        int errid = cmdbuffer.getInt2();
        if (errid != DEV_OK) {
            String errmsg = cmdbuffer.getNString();
            logger.errorf("Ошибка СБ = %d:%s '%s'", errid, getDeviceErrName(errid), errmsg);
            throw new ExSBError(errid, errmsg);
        }
    }

    private void execCmd() throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
        execCmd(1000, 10000); // 1 сек - на ответ сервиса, 10 сек - на выполнение команд.
    }

    private void execTRCmd() throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
        execCmd(1000, 65000); // 1 сек - на ответ сервиса, 65 сек - на выполнение финансовых команд.
    }

    public String cmd_GetReady() throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
        cmdbuffer.reset().put(CMD_GETREADY).flip();
        execCmd();
        return cmdbuffer.getNString();
    }

    public int cmd_CardTest() throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
        cmdbuffer.reset().put(CMD_CARDTEST).flip();
        execCmd();
        return cmdbuffer.get(); // 0 - вставлена, иначе - нет.
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /** Описатель строки для вывода на дисплей пинпада. */
    public static class MCDRow {
        /** Номер строки для вывода текста (если = -100 - очистка экрана, текст игнорируется) */
        public int row;
        /** Отобразаемый текст. */
        public String text;

        /** Конструктор. */
        public MCDRow(int row, String text) {
            this.row = row;
            this.text = text;
        }
    }

    /**
     * Вывод текстовой информации на дисплей пинпада. Вариант с гибким использованием аргументов (позволяющий удобно
     * записывать выводимую информацию). Вывод всех строк осуществляется за один RC вызов, в отличии от cmd_MC_Display,
     * которая выводит одну строку за один RC вызов.
     *
     * @param vals Могут быть значения двух типов: integer - позиционирование на номер строки (-100 - очистка дисплея и
     *             позиционирование на первую строку), string - вывод текста в текущую строку (после чего текущей
     *             становится следующая строка, null - переход к следующей строке. Иные типы игнорируются.
     */
    public void cmd_MC_DisplayFlex(Object... vals) throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
        cmdbuffer.reset().put(CMD_MC_DISPLAY).mark().putInt2(0); // Заносим нулевое кол-во.
        int n = 0; // Общее кол-во команд.
        int row = 1; // Номер начальной строки.
        for (Object val : vals) {
            if (val == null) { // Переход на след.строку.
                row++;
                continue;
            }
            if (val instanceof Integer) { // Позиционирование.
                row = (Integer) val;
                if (row == -100) { // Если это очистка экрана - создаём команду (НЕ НУЖНО ПУСТУЮ СТРОКУ ДОБАВЛЯТЬ!).
                    cmdbuffer.put(-100).putNString("");
                    row = 1;
                    n++;
                }
                continue;
            }
            if (val instanceof String) { // Если это строка - создаём команду.
                cmdbuffer.put(row).putNString((String) val);
                row++;
                n++;
            }
        }
        cmdbuffer.putInt2At(cmdbuffer.markedPos(), n).flip(); // Заносим итоговое число команд.
        execCmd();
    }

    /**
     * Вывод текстовой информации на дисплей пинпада. Вариант с использованием массива описателей строк (позволяющий
     * удобно записывать выводимую информацию). Вывод всех строк осуществляется за один RC вызов, в отличии от
     * cmd_MC_Display, которая выводит одну строку за один RC вызов.
     *
     * @param rows Массив описателей выводимых строк.
     */
    public void cmd_MC_DisplayRows(MCDRow... rows) throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
        cmdbuffer.reset().put(CMD_MC_DISPLAY).putInt2(rows.length);
        for (MCDRow row : rows) cmdbuffer.put(row.row).putNString(row.text);
        cmdbuffer.flip();
        execCmd();
    }

    public void cmd_MC_Display(int row, String text) throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
        cmdbuffer.reset().put(CMD_MC_DISPLAY).putInt2(1).put(row).putNString(text).flip();
        execCmd();
    }

    public void cmd_MC_Beep(int type) throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
        cmdbuffer.reset().put(CMD_MC_BEEP).put(type).flip();
        execCmd();
    }

//    public String cmd_MC_Keyboard() throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
//        cmdbuffer.reset().put(CMD_MC_KEYBOARD).flip();
//        execCmd();
//        return cmdbuffer.getNString();
//    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    public TRResult cmd_TR_Purchase(int amount)
            throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
        cmdbuffer.reset().put(CMD_TR_PURCHASE).putInt(amount).flip();
        execTRCmd();
        return new TRResult(cmdbuffer);
    }

    public TRResult cmd_TR_Refund(int amount, String rrn, String hexencdata)
            throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
        cmdbuffer.reset().put(CMD_TR_REFUND).putInt(amount).putNString(rrn).putNString(hexencdata).flip();
        execTRCmd();
        return new TRResult(cmdbuffer);
    }

//    public TRResult cmd_TR_Cancel(int amount, String rrn, String hexencdata)
//            throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
//        cmdbuffer.reset().put(CMD_TR_CANCEL).putInt(amount).putNString(rrn).putNString(hexencdata).flip();
//        execTRCmd();
//        return new TRResult(cmdbuffer);
//    }
//
//    public TRResult cmd_TR_Rollback(int amount, String authCode)
//            throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
//        cmdbuffer.reset().put(CMD_TR_ROLLBACK).putInt(amount).putNString(authCode).flip();
//        execTRCmd();
//        return new TRResult(cmdbuffer);
//    }
//
//    public TRResult cmd_TR_Balance()
//            throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
//        cmdbuffer.reset().put(CMD_TR_BALANCE).flip();
//        execTRCmd();
//        return new TRResult(cmdbuffer);
//    }
//
//    public TRResult cmd_TR_PreAuthorize(int amount)
//            throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
//        cmdbuffer.reset().put(CMD_TR_PREAUTHORIZE).putInt(amount).flip();
//        execTRCmd();
//        return new TRResult(cmdbuffer);
//    }
//
//    public TRResult cmd_TR_PreComplete(int amount, String rrn, String hexencdata)
//            throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
//        cmdbuffer.reset().put(CMD_TR_PRECOMPLETE).putInt(amount).putNString(rrn).putNString(hexencdata).flip();
//        execTRCmd();
//        return new TRResult(cmdbuffer);
//    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    public PrinterTextBlock[] getLastPrintedTextAsBlocks(DataBuffer buf) {
        int n = buf.getInt2();
        PrinterTextBlock[] lines = new PrinterTextBlock[n];
        for (int i = 0; i < n; i++) {
            lines[i] = new PrinterTextBlock(buf.get(), buf.getNString());
        }
        return lines;
    }

    public PrinterTextBlock[] cmd_TR_CloseSession()
            throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
        cmdbuffer.reset().put(CMD_TR_CLOSESESSION).flip();
        execTRCmd();
        return getLastPrintedTextAsBlocks(cmdbuffer);
    }

    public PrinterTextBlock[] cmd_TR_Totals(int type)
            throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
        cmdbuffer.reset().put(CMD_TR_TOTALS).put(type).flip();
        execTRCmd();
        return getLastPrintedTextAsBlocks(cmdbuffer);
    }

    public PrinterTextBlock[] cmd_TR_Help()
            throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
        cmdbuffer.reset().put(CMD_TR_HELP).flip();
        execTRCmd();
        return getLastPrintedTextAsBlocks(cmdbuffer);
    }

//    public TRResult cmd_TR_ReadCard()
//            throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
//        cmdbuffer.reset().put(CMD_TR_READCARD).flip();
//        execTRCmd();
//        return new TRResult(cmdbuffer);
//    }

    public PrinterTextBlock[] cmd_GetPrinter()
            throws ExRequestError, ExAnswerError, ExTimeout, ExSBError {
        cmdbuffer.reset().put(CMD_GETPRINTER).flip();
        execCmd();
        return getLastPrintedTextAsBlocks(cmdbuffer);
    }

    public static SimpleDateFormat df = new SimpleDateFormat("dd.MM.yyyy HH:mm:SS");

    public static String ldf(long time) {
        return df.format(new Date(time));
    }

    public static void test2() {
        try {
            logger.setConsoleFormatter();

            SBPinpadRCClient client = new SBPinpadRCClient(1, new InetSocketAddress("127.0.0.1", 10000), 65000);
            CommonTools.safeInterruptedSleep(1000);

            DataBuffer buf = new DataBuffer(5000);

            //logger.info("=== КОМАНДА: Stop ===");
            //ResultStop rStop2 = client.remoteStop(100, null);
            //logger.info("FINISH...");
            //if (true) return;

            //client.cmd_TR_Cancel(0, "610581290873", "3E2FE7A4352976160DC9FD9CA81A7C3C7C6B0781B565364DE7E3CCDEB6BCA5E1");
            //client.cmd_TR_CloseSession();
            //client.cmd_GetReady();
            //if (true) return;

            logger.info("=== КОМАНДА: GetState ===");
            ResultGetState rState = client.remoteGetState(100);
            logger.infof(" STATE1: err=%d msg=%s tm(start=%s, stop=%s, restart=%s)",
                    rState.answerErrorID, rState.answerErrorMessage,
                    ldf(rState.lastStartTime), ldf(rState.lastStopTime), ldf(rState.lastAutoRestartTime));
            logger.infof(" STATE2: prcMode=%d isSingle=%d pcState=%d slot(free=%d exec=%d res=%d) queue(free=%d size=%d)",
                    rState.processingMode, rState.isSingleSerialMode ? 1:0, rState.processorState,
                    rState.slotsFree, rState.slotsExecute, rState.slotsResult,
                    rState.queueFree, rState.queurSize);
            logger.infof(" STATE3: devsatet=%s",
                    rState.isDeviceConnected ? "CONNECTED" : "DISCONNECTED");
            //CommonTools.safeInterruptedSleep(1000);

            if (rState.answerErrorID == RCService.RESULT_OK) {
                logger.info("=== КОМАНДА: Execute[CMD_GETREADY] ===");
                String info = client.cmd_GetReady();
                logger.infof(" РЕЗУЛЬТАТ: %s", info);
                //logger.info(" SLEEP(100)...");
                //CommonTools.safeInterruptedSleep(100);

                logger.info("=== КОМАНДА: Execute[CMD_CARDTEST] ===");
                int ict = client.cmd_CardTest();
                logger.infof(" РЕЗУЛЬТАТ: %d", ict);

                logger.info("=== КОМАНДА: Execute[CMD_TR_TOTALS] ===");
                PrinterTextBlock[] blocks = client.cmd_TR_Totals(1);
                logger.infof(" РЕЗУЛЬТАТ: %d линий", blocks.length);
                for (int i = 0; i < blocks.length; i++) {
                    logger.infof(" [%02d]: (0x%02X) '%s'", i, blocks[i].mode, blocks[i].text);
                }

                logger.info("=== КОМАНДА: Execute[CMD_MC_DISPLAY] ===");

                client.cmd_MC_DisplayFlex(-100,
                        1, "     АЗС N1",
                        "_____________________",
                        "ТРК N3: \"АИ-95\"",
                        "Объем        1.00 л",
                        "Цена        35.00 р/л",
                        "---------------------",
                        "Сумма     = 35.00 р",
                        "_____________________",
                        "  ДО ПОЛНОГО БАКА!",
                        11, "    Подтвердить?"
                );

//                client.cmd_MC_DisplayRows(new MCDRow(-100, ""),
//                        new MCDRow(1, "     АЗС N1"),
//                        new MCDRow(2, "_____________________"),
//                        new MCDRow(3, "ТРК N3: \"АИ-95\""),
//                        new MCDRow(4, "Объем        1.00 л"),
//                        new MCDRow(5, "Цена        35.00 р/л"),
//                        new MCDRow(6, "---------------------"),
//                        new MCDRow(7, "Сумма     = 35.00 р"),
//                        new MCDRow(8, "_____________________"),
//                        new MCDRow(9, "  ДО ПОЛНОГО БАКА!"),
//                        new MCDRow(11, "    Подтвердить?")
//                );

//                client.cmd_MC_Display(-100, "");
//                client.cmd_MC_Display(1, "     АЗС N1");
//                client.cmd_MC_Display(2, "_____________________");
//                client.cmd_MC_Display(3, "ТРК N3: \"АИ-95\"");
//                client.cmd_MC_Display(4, "Объем        1.00 л");
//                client.cmd_MC_Display(5, "Цена        35.00 р/л");
//                client.cmd_MC_Display(6, "---------------------");
//                client.cmd_MC_Display(7, "Сумма     = 35.00 р");
//                client.cmd_MC_Display(8, "_____________________");
//                client.cmd_MC_Display(9, "  ДО ПОЛНОГО БАКА!");
//                client.cmd_MC_Display(11, "    Подтвердить?");

//                logger.info("=== КОМАНДА: Execute[CMD_MC_KEYBOARD] ===");
//                client.cmd_MC_Keyboard();
//                int mode = 0;
//                while (mode == 0) {
//                    String keys = client.cmd_MC_Keyboard();
//                    if (!keys.isEmpty()) {
//                        int k = keys.charAt(0);
//                        logger.infof("KEYBOARD: '%02X'", k);
//                        if (k == 0x0D) if (client.cmd_CardTest() == 0) mode = 1;
//                        if (k == 0x1B) mode = 2;
//                    } else {
//                        Thread.sleep(100);
//                    }
//                }
//                logger.info("=== КОМАНДА: Execute[CMD_MC_DISPLAY] ===");
//                client.cmd_MC_Display(11, mode == 1 ? "    ПОДТВЕРЖДЕНО" : "      ОТМЕНЕНО");
//                client.cmd_MC_Display(12, "      КЛИЕНТОМ");
//
//                if (true) return;

//                TRResult tr;
//                if (mode == 1) {
//                    tr = client.cmd_TR_Purchase(100);
//                    //
//                    client.cmd_MC_Display(-100, "");
//                    client.cmd_MC_Display(9, "  ОТМЕНА ОПЕРАЦИИ!");
//                    client.cmd_MC_Display(11, "    Подтвердить?");
//                    client.cmd_MC_Keyboard();
//                    mode = 0;
//                    while (mode == 0) {
//                        String keys = waitKeys(client);
//                        int k = keys.charAt(0);
//                        if (k == 0x0D) {
//                            mode = 1;
//                        }
//                        if (k == 0x1B) {
//                            mode = 2;
//                        }
//                    }
//                    //
//                    if (mode == 1) {
//                        tr = client.cmd_TR_Rollback(100, tr.authCode);
//                    }
//
//                } else if (mode == 2) {
//                    tr = client.cmd_TR_Cancel(0, "", "");
//                }
            }
            logger.info("=== КОМАНДА: Stop ===");
            ResultStop rStop = client.remoteStop(100, -1);
            logger.info("FINISH...");

        } catch (Exception ex) {
            ex.printStackTrace();
        }
    }

    public static void main(String[] args) {
        test2();
    }

}
