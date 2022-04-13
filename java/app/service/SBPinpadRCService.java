/*
 * Copyright (c) 2016. Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */

package app.service;

import app.DataBuffer;
import app.ExError;
import app.LoggerExt;
import app.driver.RS232Driver;
import app.device.SBPinpadDevice;

import java.util.ArrayList;

/**
 * Сетевой сервис для удаленного управления устройством с последовательным выполнением команд. Данная конкретная
 * реализация - для управления банковским пинпадом Сбербанка.
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
public class SBPinpadRCService extends RS232RCService {

    private final LoggerExt logger;

    private final SBPinpadDevice pinpad;

    public SBPinpadRCService(String name, int udpport, String comportname, int bitrate) throws ExError {
        super(name, udpport, 2000, 2, ProcessingMode.SERIAL_FOR_CLIENT, comportname);
        this.logger = LoggerExt.getNewLogger("SBPinpadRCService-" + name).enable(true).toFile();
        //driver.enableLogger(true);
        // Создание пинпада СБ.
        pinpad = new SBPinpadDevice(name, getDriver().bitrate(bitrate), "cp866");
    }

    /**
     * Реализация обработчика выполнения команд терминала-СБ (выполняется в отдельном потоке процессора команд).
     * <p>
     * ВНИМАНИЕ! Должен все внутренние ошибки корректно обработать - нельзя выкидывать исключения наружу. Результат
     * исполнения регулируется исключительно содержимым буфера с ответом! Если необходимо прерывание сервиса - только с
     * помощью terminate()!
     */
    @Override
    protected void commandExecutionBody(Slot slot) {
        try {
            logger.infof("Начало выполнения СБ команды! slot={%s}", slot.toString());

            // Разбор, выполнениние команды, формирование результата.
            parseAndExecute(slot.execmeta.buffer.rewind());

        } catch (RS232Driver.ExDisconnect ex) {
            // При дисконнекте связь автоматически должен восстанавливать регенератор!
            // Сброс результатов, внесение кода и текста ошибки (для команды, не путать с запросом!).
            slot.execmeta.buffer.reset().putInt2(DEV_DISCONNECTED).putNString(ex.getMessage()).flip();
        } catch (ExUnsupported ex) {
            // Сброс результатов, внесение кода и текста ошибки (для команды, не путать с запросом!).
            slot.execmeta.buffer.reset().putInt2(DEV_UNSUPPORTED).putNString(ex.getMessage()).flip();
        } catch (Exception ex) {
            ex.printStackTrace();
            // Сброс результатов, внесение кода и текста ошибки (для команды, не путать с запросом!).
            slot.execmeta.buffer.reset().putInt2(DEV_ERROR).putNString(ex.getMessage()).flip();
        } finally {
            logger.infof("Завершение выполнения СБ команды! slot={%s}", slot.toString());
        }
    }

    public static final int CMD_GETREADY = 1;
    public static final int CMD_CARDTEST = 2;
    //
    public static final int CMD_MC_DISPLAY = 10;
    public static final int CMD_MC_BEEP = 11;
    //public static final int CMD_MC_KEYBOARD = 12;
    //
    public static final int CMD_TR_PURCHASE = 20;
    public static final int CMD_TR_REFUND = 21;
    //public static final int CMD_TR_CANCEL = 22;
    //public static final int CMD_TR_ROLLBACK = 23;
    //public static final int CMD_TR_BALANCE = 24;
    //public static final int CMD_TR_PREAUTHORIZE = 25;
    //public static final int CMD_TR_PRECOMPLETE = 26;
    //
    public static final int CMD_TR_CLOSESESSION = 30;
    public static final int CMD_TR_TOTALS = 31;
    public static final int CMD_TR_HELP = 32;
    //public static final int CMD_TR_READCARD = 33;
    // Получение информации о последнем режиме печати принтера и массиве отпечатанных строк.
    public static final int CMD_GETPRINTER = 40;

    /** Запись в буфер строк последнего отпечатанного чека (MASTERCALL-PRINTER-WRITE). */
    private DataBuffer putLastPrintedTextAsBlocks(DataBuffer buf) {
        ArrayList<SBPinpadDevice.PrinterTextBlock> lines = pinpad.getLastPrintedTextAsBlocks();
        buf.putInt2(lines.size()); // Заносим кол-во строк.
        for (SBPinpadDevice.PrinterTextBlock block : lines) buf.put(block.mode).putNString(block.text);
        return buf;
    }

    /** Парсит окно буфера как входящую команду терминалу, исполняет её и помещает в буфер результат для ответа. */
    private void parseAndExecute(DataBuffer buf) throws ExError {
        SBPinpadDevice.TRResult tr;
        SBPinpadDevice.MCMeta mc;
        String s, rrn, hexenc, authcode;
        int n, row, amount;

        buf.rewind();
        int cmdid = buf.get(); // [1]
        switch (cmdid) {
            ////////////////////////////////////////////////////////////////////////////////////////////////////////////
            case CMD_GETREADY:
                s = pinpad.cmd_GetReady(-1);
                buf.reset().putInt2(DEV_OK).putNString(s).flip(); // [?]
                break;
            case CMD_CARDTEST:
                n = pinpad.cmd_CardTest(-1);
                buf.reset().putInt2(DEV_OK).put(n).flip(); // [1]
                break;
            ////////////////////////////////////////////////////////////////////////////////////////////////////////////
            case CMD_MC_DISPLAY:
                n = buf.getInt2(); // [2]
                for (int i = 0; i < n; i++) {
                    row = buf.get(); // [1]
                    s = buf.getNString(); // [?]
                    pinpad.cmd_MC_Display(row, s, -1);
                }
                buf.reset().putInt2(DEV_OK).flip();
                break;
            case CMD_MC_BEEP:
                n = buf.get(); // [1]
                pinpad.cmd_MC_Beep(n, -1);
                buf.reset().putInt2(DEV_OK).flip();
                break;
//            case CMD_MC_KEYBOARD:
//                s = pinpad.cmd_MC_Keyboard(-1);
//                buf.reset().putInt2(DEV_OK).putNString(s).flip(); // [?]
//                break;
            ////////////////////////////////////////////////////////////////////////////////////////////////////////////
            // TODO: Подумать, может быть вместо TRResult возвращать только необходимые в каждом случае поля?
            case CMD_TR_PURCHASE:
                amount = buf.getInt(); // [4]
                tr = pinpad.cmd_TR_Purchase(amount);
                tr.build(buf.reset().putInt2(DEV_OK)).flip(); // [TRResult]
                break;
            case CMD_TR_REFUND:
                amount = buf.getInt(); // [4]
                rrn = buf.getNString(); // [?]
                hexenc = buf.getNString(); // [?]
                tr = pinpad.cmd_TR_Refund(amount, rrn, hexenc);
                tr.build(buf.reset().putInt2(DEV_OK)).flip(); // [TRResult]
                break;
//            case CMD_TR_CANCEL:
//                amount = buf.getInt(); // [4]
//                rrn = buf.getNString(); // [?]
//                hexenc = buf.getNString(); // [?]
//                tr = pinpad.cmd_TR_Cancel(amount, rrn, hexenc);
//                tr.build(buf.reset().putInt2(DEV_OK)).flip(); // [TRResult]
//                break;
//            case CMD_TR_ROLLBACK:
//                amount = buf.getInt(); // [4]
//                authcode = buf.getNString(); // [?]
//                tr = pinpad.cmd_TR_Rollback(amount, authcode);
//                tr.build(buf.reset().putInt2(DEV_OK)).flip(); // [TRResult]
//                break;
//            case CMD_TR_BALANCE:
//                tr = pinpad.cmd_TR_Balance();
//                tr.build(buf.reset().putInt2(DEV_OK)).flip(); // [TRResult]
//                break;
//            case CMD_TR_PREAUTHORIZE:
//                amount = buf.getInt(); // [4]
//                tr = pinpad.cmd_TR_PreAuthorize(amount);
//                tr.build(buf.reset().putInt2(DEV_OK)).flip(); // [TRResult]
//                break;
//            case CMD_TR_PRECOMPLETE:
//                amount = buf.getInt(); // [4]
//                rrn = buf.getNString(); // [?]
//                hexenc = buf.getNString(); // [?]
//                tr = pinpad.cmd_TR_PreComplete(amount, rrn, hexenc);
//                tr.build(buf.reset().putInt2(DEV_OK)).flip(); // [TRResult]
//                break;
            ////////////////////////////////////////////////////////////////////////////////////////////////////////////
            case CMD_TR_CLOSESESSION:
                tr = pinpad.cmd_TR_CloseSession();
                putLastPrintedTextAsBlocks(buf.reset().putInt2(DEV_OK)).flip(); // [чек] TODO: Инфа в TRResult не нужна?
                break;
            case CMD_TR_TOTALS:
                n = buf.get(); // [1]
                tr = pinpad.cmd_TR_Totals(n);
                putLastPrintedTextAsBlocks(buf.reset().putInt2(DEV_OK)).flip(); // [чек] TODO: Инфа в TRResult не нужна?
                break;
            case CMD_TR_HELP:
                tr = pinpad.cmd_TR_Help();
                putLastPrintedTextAsBlocks(buf.reset().putInt2(DEV_OK)).flip(); // [чек]
                break;
//            case CMD_TR_READCARD:
//                tr = pinpad.cmd_TR_ReadCard();
//                tr.build(buf.reset().putInt2(DEV_OK)).flip(); // [TRResult]
//                break;
            ////////////////////////////////////////////////////////////////////////////////////////////////////////////
            case CMD_GETPRINTER:
                putLastPrintedTextAsBlocks(buf.reset().putInt2(DEV_OK)).flip();
                break;
            default:
                throw new ExUnsupported("Операция не поддерживается протоколом! {cmdid=%d}", cmdid);
        }
    }
}
