/*
 * Copyright (c) 2015, Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */
package app;

/**
 * Базовое исключение для обработки ошибок.
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
public class ExError extends Exception {

    /**
     * Конструктор.
     */
    public ExError() {
        super();
    }

    /**
     * Конструктор по исключению.
     *
     * @param cause Исключение.
     */
    public ExError(Throwable cause) {
        super(cause);
    }

    /**
     * Конструктор с форматированием сообщения.
     *
     * @param fmt    Форматная строка.
     * @param params Параметры-значения для форматной строки.
     */
    public ExError(String fmt, Object... params) {
        super(params == null || params.length == 0 ? fmt : String.format(fmt, params));
    }

    /**
     * Конструктор по исключению с форматированием сообщения.
     *
     * @param cause  Исключение.
     * @param fmt    Форматная строка.
     * @param params Параметры-значения для форматной строки.
     */
    public ExError(Throwable cause, String fmt, Object... params) {
        super(params == null || params.length == 0 ? fmt : String.format(fmt, params), cause);
    }

    /**
     * Статическая генерация исключения. По исключению с форматированием сообщения.
     *
     * @param cause  Исключение.
     * @param fmt    Форматная строка.
     * @param params Параметры-значения для форматной строки.
     */
    public static void ex(Throwable cause, String fmt, Object... params) throws ExError {
        throw new ExError(cause, fmt, params);
    }

    /**
     * Статическая генерация исключения. C форматированием сообщения.
     *
     * @param fmt    Форматная строка.
     * @param params Параметры-значения для форматной строки.
     */
    public static void ex(String fmt, Object... params) throws ExError {
        throw new ExError(fmt, params);
    }

    /**
     * Статическая генерация исключения по условию. По исключению с форматированием сообщения.
     *
     * @param exp    Условие: true - генерируется исключение, false - нет.
     * @param cause  Исключение.
     * @param fmt    Форматная строка.
     * @param params Параметры-значения для форматной строки.
     */
    public static void exIf(boolean exp, Throwable cause, String fmt, Object... params) throws ExError {
        if (exp) throw new ExError(cause, fmt, params);
    }

    /**
     * Статическая генерация исключения по условию. С форматированием сообщения.
     *
     * @param exp    Условие: true - генерируется исключение, false - нет.
     * @param fmt    Форматная строка.
     * @param params Параметры-значения для форматной строки.
     */
    public static void exIf(boolean exp, String fmt, Object... params) throws ExError {
        if (exp) throw new ExError(fmt, params);
    }

    /**
     * Формирование комбинированной строки-описателя исключения.
     *
     * @param ex Исключение.
     * @return Строка, описывающая исключение. Содержит класс исключения и сообщение (если задано).
     */
    public static String exMsg(Throwable ex) {
        String clazz = ex.getClass().getCanonicalName();
        String msg = ex.getMessage();
        return msg == null ? clazz : (clazz + ": " + msg);
    }
}
