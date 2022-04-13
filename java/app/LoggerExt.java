/*
 * Copyright (c) 2015, Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */

package app;

import java.io.File;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.ResourceBundle;
import java.util.function.Supplier;
import java.util.logging.*;

/**
 * Расширенный логгер. Правильно определяет точку вызова (производит анализ стека - выбирает первый элемент лежащий
 * после методов этого класса и его предка). Ради этого правильного определения точки вызова и был написан! Также
 * реализован механизм исключения помеченных методов\классов при определении точки вызова.
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
@LoggerExt.LoggerRules(logger = true)
public final class LoggerExt extends Logger {

    /**
     * Анотация, позволяющая задать правила логирования для классов.
     */
    @Target(ElementType.TYPE)
    @Retention(value = RetentionPolicy.RUNTIME)
    public @interface LoggerRules {

        /**
         * Флаг-индикатор, является ли класс логгером.
         *
         * @return true - класс является логгером, все методы игнорируются как точки вызова, false - не является,
         * игнорируются только методы, указанные в methods.
         */
        boolean logger() default false;

        /**
         * Список игнорируемых методов у "не логгеров".
         *
         * @return Список игнорируемых методов. Применяется только при logger=false. ВНИМАНИЕ! Требуется полное
         * совпадение имени! Меторы с одинаковыми именами и различными аргументами - не различаются!
         */
        String[] methods() default {};
    }

    private static final LoggerExt logger = new LoggerExt("app");

    private boolean isEnabled; // true-идёт логирование, false-нет.
    private boolean isCallerFind; // true-производится поиск источника точки вызова лога, false-нет.
    private boolean isToFile;
    private int mask; // Маска для управления логированием (для пользовательского управления выводом информации в лог), самим логгером не используется!

    private LoggerExt(String name) {
        super(name, null);
        isEnabled = false;
        isCallerFind = true;
        isToFile = false;
        mask = -1;
        LogManager.getLogManager().addLogger(LoggerExt.this);
    }

    public static LoggerExt getCommonLogger() {
        return logger;
    }

    public static LoggerExt getNewLogger(String name) {
        return new LoggerExt(name);
    }

    public LoggerExt enable(boolean isEnabled) {
        this.isEnabled = isEnabled;
        return this;
    }

    public boolean isEnabled() {
        return isEnabled;
    }

    public LoggerExt mask(int mask) {
        this.mask = mask;
        return this;
    }

    public int getMask() {
        return mask;
    }

    public boolean isMask(int mask) {
        return (this.mask & mask) != 0;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    public static void setConsoleFormatter(Formatter formatter) {
        // Переводим консольный логгер на наш форматер.
        Logger rootLogger = Logger.getLogger("");
        Handler[] handlers = rootLogger.getHandlers();
        if (handlers[0] instanceof ConsoleHandler) {
            handlers[0].setFormatter(formatter);
            handlers[0].setLevel(Level.ALL);
            if (isWindowsOS()) {
                // Удаление консольного логирования в винде! Там и с кодировками проблемы и не нужно!
                rootLogger.removeHandler(handlers[0]);
            }
        }
    }

    public static void setConsoleFormatter() {
        LoggerExt.setConsoleFormatter(new LogFormatter(false, false, true));
    }

    public static String getOSName3() {
        return System.getProperty("os.name", "").toLowerCase().substring(0, 3);
    }

    public static boolean isWindowsOS() {
        return getOSName3().equals("win");
    }

    public static boolean isLinuxOS() {
        return getOSName3().equals("lin");
    }

    private static final SimpleDateFormat df = new SimpleDateFormat("yyyyMMdd");

    /**
     * Создание каталога, если он еще не существует.
     *
     * @param path Имя каталога.
     * @return Файл каталога.
     * @throws ExError
     */
    private static File createDirectoryIfNotExist(String path) throws ExError {
        try {
            File dir = new File(path);
            if (!dir.exists())
                if (!dir.mkdir()) throw new ExError("Ошибка создания каталога!");
            return dir;
        } catch (ExError ex) {
            throw ex;
        } catch (Exception e) {
            throw new ExError(e, "Ошибка создания каталога!");
        }
    }

    public LoggerExt toFile() {
        if (!isToFile) {
            // Логгируем все сообщения.
            setLevel(Level.ALL);

            // Настраиваем логгер для файлового вывода.
            try {
                createDirectoryIfNotExist("./log");
                // В паттерне разделители заменяются на локальные!
                FileHandler handler = new FileHandler("./log/" + getName() + "_" + df.format(new Date()) + ".log", 0, 1, true);
                handler.setLevel(Level.ALL);
                handler.setFormatter(new LogFormatter());
                addHandler(handler);
                isToFile = true;

            } catch (Exception e) {
                error("Ошибка создания лог-файла! Вывод в лог-файл будет игнорироваться!", e);
            }
        }
        return this;
    }

    public LoggerExt flush() {
        if (isToFile) {
            try {
                for (Handler h : getHandlers()) h.flush();
            } catch (Exception e) {
                error("Ошибка сохранения буферов лог-файла!", e);
            }
        }
        return this;
    }

    public LoggerExt close() {
        if (isToFile) {
            try {
                for (Handler h : getHandlers()) {
                    h.flush();
                    removeHandler(h);
                    h.close();
                }
                isToFile = false;
            } catch (Exception e) {
                error("Ошибка закрытия лог-файла!", e);
            }
        }
        return this;
    }

    protected StackTraceElement findCallerPoint() {
        final StackTraceElement[] stack = new Throwable().getStackTrace();
        boolean isinnerlevel = true;
        for (StackTraceElement e : stack) {
            boolean islog = false;
            try {
                Class clazz = Class.forName(e.getClassName());
                if (islog = Logger.class.isAssignableFrom(clazz)) {
                    // Если основа - логгер, то все методы не могут быть точками вызова.
                    islog = true;
                } else if (clazz.isAnnotationPresent(LoggerRules.class)) {
                    // Если класс имеет анотацию с правилами логировани.
                    String name = e.getMethodName();
                    LoggerRules ma = (LoggerRules) clazz.getAnnotation(LoggerRules.class);
                    if (ma.logger()) {
                        // Если помечен как логгер, то все методы не могут быть точками вызова.
                        islog = true;
                    } else {
                        // Если не помечен как логгер, то проверяем на совпадение со списком исключаемых методов.
                        for (String s : ma.methods()) {
                            if (name.equals(s)) {
                                // Если совпал, то метод не может быть точкой вызова.
                                islog = true;
                                break;
                            }
                        }
                    }
                }
            } catch (ClassNotFoundException ignore) {
            }
            if (isinnerlevel) {
                if (islog) isinnerlevel = false;
            } else {
                if (!islog) return e;
            }
        }
        return null;
    }

    @Override
    public void log(LogRecord record) {
        if (isEnabled) {
            if (isCallerFind) {
                StackTraceElement e = findCallerPoint();
                if (e != null) {
                    record.setSourceClassName(e.getClassName());
                    record.setSourceMethodName(e.getMethodName());
                }
            }
            super.log(record); //To change body of generated methods, choose Tools | Templates.
        }
    }

    @Override
    public void throwing(String sourceClass, String sourceMethod, Throwable thrown) {
        if (isEnabled) {
            isCallerFind = false;
            super.throwing(sourceClass, sourceMethod, thrown); //To change body of generated methods, choose Tools | Templates.
        }
    }

    @Override
    public void exiting(String sourceClass, String sourceMethod, Object result) {
        if (isEnabled) {
            isCallerFind = false;
            super.exiting(sourceClass, sourceMethod, result); //To change body of generated methods, choose Tools | Templates.
        }
    }

    @Override
    public void exiting(String sourceClass, String sourceMethod) {
        if (isEnabled) {
            isCallerFind = false;
            super.exiting(sourceClass, sourceMethod); //To change body of generated methods, choose Tools | Templates.
        }
    }

    @Override
    public void entering(String sourceClass, String sourceMethod, Object[] params) {
        if (isEnabled) {
            isCallerFind = false;
            super.entering(sourceClass, sourceMethod, params); //To change body of generated methods, choose Tools | Templates.
        }
    }

    @Override
    public void entering(String sourceClass, String sourceMethod, Object param1) {
        if (isEnabled) {
            isCallerFind = false;
            super.entering(sourceClass, sourceMethod, param1); //To change body of generated methods, choose Tools | Templates.
        }
    }

    @Override
    public void entering(String sourceClass, String sourceMethod) {
        if (isEnabled) {
            isCallerFind = false;
            super.entering(sourceClass, sourceMethod); //To change body of generated methods, choose Tools | Templates.
        }
    }

    @Override
    public void logrb(Level level, String sourceClass, String sourceMethod, ResourceBundle bundle, String msg, Throwable thrown) {
        if (isEnabled) {
            isCallerFind = false;
            super.logrb(level, sourceClass, sourceMethod, bundle, msg, thrown); //To change body of generated methods, choose Tools | Templates.
        }
    }

    @Override
    public void logp(Level level, String sourceClass, String sourceMethod, Throwable thrown, Supplier<String> msgSupplier) {
        if (isEnabled) {
            isCallerFind = false;
            super.logp(level, sourceClass, sourceMethod, thrown, msgSupplier); //To change body of generated methods, choose Tools | Templates.
        }
    }

    @Override
    public void logp(Level level, String sourceClass, String sourceMethod, String msg, Throwable thrown) {
        if (isEnabled) {
            isCallerFind = false;
            super.logp(level, sourceClass, sourceMethod, msg, thrown); //To change body of generated methods, choose Tools | Templates.
        }
    }

    @Override
    public void logp(Level level, String sourceClass, String sourceMethod, String msg, Object[] params) {
        if (isEnabled) {
            isCallerFind = false;
            super.logp(level, sourceClass, sourceMethod, msg, params); //To change body of generated methods, choose Tools | Templates.
        }
    }

    @Override
    public void logp(Level level, String sourceClass, String sourceMethod, String msg, Object param1) {
        if (isEnabled) {
            isCallerFind = false;
            super.logp(level, sourceClass, sourceMethod, msg, param1); //To change body of generated methods, choose Tools | Templates.
        }
    }

    @Override
    public void logp(Level level, String sourceClass, String sourceMethod, Supplier<String> msgSupplier) {
        if (isEnabled) {
            isCallerFind = false;
            super.logp(level, sourceClass, sourceMethod, msgSupplier); //To change body of generated methods, choose Tools | Templates.
        }
    }

    @Override
    public void logp(Level level, String sourceClass, String sourceMethod, String msg) {
        if (isEnabled) {
            isCallerFind = false;
            super.logp(level, sourceClass, sourceMethod, msg); //To change body of generated methods, choose Tools | Templates.
        }
    }

    public void configf(String fmt, Object... params) {
        if (isEnabled) {
            super.config(String.format(fmt, params));
        }
    }

    public void infof(String fmt, Object... params) {
        if (isEnabled) {
            super.info(String.format(fmt, params));
        }
    }

    public void warning(String message, Throwable w) {
        if (isEnabled) {
            super.log(Level.WARNING, message, w);
        }
    }

    public void warningf(String fmt, Object... params) {
        if (isEnabled) {
            super.warning(String.format(fmt, params));
        }
    }

    public void warningf(Throwable w, String fmt, Object... params) {
        if (isEnabled) {
            super.log(Level.WARNING, String.format(fmt, params), w);
        }
    }

    public void error(String message) {
        if (isEnabled) {
            super.log(Level.SEVERE, message);
        }
    }

    public void error(String message, Throwable w) {
        if (isEnabled) {
            super.log(Level.SEVERE, message, w);
        }
    }

    public void errorf(String fmt, Object... params) {
        if (isEnabled) {
            super.log(Level.SEVERE, String.format(fmt, params));
        }
    }

    public void errorf(Throwable w, String fmt, Object... params) {
        if (isEnabled) {
            super.log(Level.SEVERE, String.format(fmt, params), w);
        }
    }
}
