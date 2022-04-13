/*
 * Copyright (c) 2014, Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */

package app;

import java.io.PrintWriter;
import java.io.StringWriter;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.logging.Formatter;
import java.util.logging.LogRecord;

/**
 * Форматер для форматирования текста при выводе в лог.
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
public class LogFormatter extends Formatter {

    private static final SimpleDateFormat dateformatlong = new SimpleDateFormat("dd.MM.yyyy HH:mm:ss.SSS ");
    private static final SimpleDateFormat dateformatshort = new SimpleDateFormat("HH:mm:ss.SSS ");
    private final SimpleDateFormat dateformat;
    private final Date dt;

    private final boolean issource;
    private final boolean istrowable;

    public LogFormatter() {
        this(true, true, true);
    }

    public LogFormatter(boolean isdatefull, boolean issource, boolean isthrowable) {
        this.dt = new Date();
        this.issource = issource;
        this.istrowable = isthrowable;
        this.dateformat = isdatefull ? dateformatlong : dateformatshort;
    }

    @SuppressWarnings("ThrowableResultOfMethodCallIgnored")
    @Override
    public synchronized String format(LogRecord record) {
        dt.setTime(record.getMillis());
        String source;
        if (record.getSourceClassName() != null) {
            source = record.getSourceClassName();
            if (record.getSourceMethodName() != null) {
                source += "->" + record.getSourceMethodName();
            }
        } else {
            source = record.getLoggerName();
        }
        String message = formatMessage(record);
        String throwable = "";
        if (record.getThrown() != null) {
            StringWriter sw = new StringWriter();
            try (PrintWriter pw = new PrintWriter(sw)) {
                pw.println();
                record.getThrown().printStackTrace(pw);
            }
            throwable = sw.toString();
        }
        String msg = dateformat.format(dt) + record.getLevel().getName() + " [" + record.getLoggerName() + "]:";
        if (!message.isEmpty()) {
            msg += " " + message;
        }

        if (issource && !source.isEmpty()) {
            msg += "    @" + source + "";
        }
        if (istrowable && !throwable.isEmpty()) {
            msg += "\n" + throwable;
        }
        return msg + "\n";
    }

    /**
     * Форматер строки лога. Изменен механизм детекции форматной строки, дополнен для случая строкового форматирования
     * (на мой взгляд - актуально).
     *
     * @param record Запись лога.
     * @return Форматированная строка.
     */
    @Override
    public synchronized String formatMessage(LogRecord record) {
        String format = record.getMessage();
        java.util.ResourceBundle catalog = record.getResourceBundle();
        if (catalog != null) {
            try {
                format = catalog.getString(record.getMessage());
            } catch (java.util.MissingResourceException ex) {
                // Drop through.  Use record message as format
                format = record.getMessage();
            }
        }
        // Do the formatting.
        try {
            Object parameters[] = record.getParameters();
            if (parameters == null || parameters.length == 0) {
                // No parameters.  Just return format string.
                return format;
            }
            int i = format.indexOf("{");
            if (i >= 0 && format.length() > i + 2) {
                int n = format.codePointAt(i + 1) - 0x30;
                if (n >= 0 && n <= 9 && format.charAt(i + 2) == '}') {
                    return java.text.MessageFormat.format(format, parameters);
                }
            }
            return String.format(format, parameters);

        } catch (Exception ex) {
            // Formatting failed: use localized format string.
            return format;
        }
    }
}
