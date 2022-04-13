/*
 * Copyright (c) 2013, Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */
package util;

import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;

/**
 * Расширение функционала операций с датами.
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
public class DateTools {

    /**
     * Предопределенный формат для вывода даты с номером года 2 знака.
     */
    public static SimpleDateFormat formatShort = new SimpleDateFormat("dd.MM.yy");
    /**
     * Предопределенный формат для вывода даты с номером года 4 знака.
     */
    public static SimpleDateFormat formatFull = new SimpleDateFormat("dd.MM.yyyy");

    /**
     * Возвращает формат для преобразования даты в строку в соответствии с флагом.
     *
     * @param isShort Флаг - короткий формат (true) или длинный (false).
     * @return Форматер.
     */
    public static SimpleDateFormat getFormat(boolean isShort) {
        if (isShort) {
            return formatShort;
        } else {
            return formatFull;
        }
    }

    /**
     * Комбинирует дату из двух дат. Из первого параметра берёт дату, из второго - время.
     *
     * @param date Дата.
     * @param time Время.
     * @return Комбинированная дата.
     */
    public static Date getDT(Date date, Date time) {
        // ВНИМАНИЕ!!!
        // Переносим именно поля даты из первого аргумента во второй!
        // Т.к. при операциях с полями времени заморочки с UTS и поясами,
        // что может вызвать ошибки с неправильным преобразованием времени! (гемор)
        Calendar d = Calendar.getInstance();
        d.setTime(date);
        Calendar t = Calendar.getInstance();
        t.setTime(time);
        t.set(Calendar.YEAR, d.get(Calendar.YEAR));
        t.set(Calendar.MONTH, d.get(Calendar.MONTH));
        t.set(Calendar.DAY_OF_MONTH, d.get(Calendar.DAY_OF_MONTH));
        return t.getTime();
    }

    /**
     * Добавляет к дате заданное количество дней.
     *
     * @param date  Дата.
     * @param count Количество дней. Может быть отрицательным для уменьшения.
     * @return Инкрементированная дата.
     */
    public static Date addDay(Date date, int count) {
        Calendar c = Calendar.getInstance();
        c.setTime(date);
        c.add(Calendar.DAY_OF_MONTH, count);
        return c.getTime();
    }

    /**
     * Добавляет к дате заданное количество месяцев.
     *
     * @param date  Дата.
     * @param count Количество месяцев. Может быть отрицательным для уменьшения.
     * @return Инкрементированная дата.
     */
    public static Date addMonth(Date date, int count) {
        Calendar c = Calendar.getInstance();
        c.setTime(date);
        c.add(Calendar.MONTH, count);
        return c.getTime();
    }

    /**
     * Возвращает дату, переданную в значении.
     *
     * @param value Значение.
     * @return Если значение - дата, то возвращается дата, если нет - null.
     */
    public static Date getDateFromValue(Object value) {
        if ((value != null) && (value instanceof Date)) {
            return (Date) value;
        } else {
            return null;
        }
    }

    /**
     * Возвращает значение из переданной даты.
     *
     * @param date Дата.
     * @return Если дата не null, то возвращается дата, если нет - целое = 0.
     */
    public static Object getValueFromDate(Date date) {
        if (date != null) {
            return date;
        } else {
            return (Integer) 0;
        }
    }

    /**
     * Возвращает дату начала месяца.
     *
     * @param date Исходная дата.
     * @return Дата начала месяца.
     */
    public static Date getStartMonth(Date date) {
        Calendar c = Calendar.getInstance();
        c.setTime(date);
        c.set(Calendar.DAY_OF_MONTH, 1);
        return c.getTime();
    }

    /**
     * Возвращает дату конца месяца.
     *
     * @param date Исходная дата.
     * @return Дата конца месяца.
     */
    public static Date getEndMonth(Date date) {
        Calendar c = Calendar.getInstance();
        c.setTime(date);
        c.set(Calendar.DAY_OF_MONTH, 1);
        c.roll(Calendar.DAY_OF_MONTH, -1);
        return c.getTime();
    }

    /**
     * Возвращает дату по указанным числовым данным (с нулевым временем!).
     *
     * @param year  Год.
     * @param month Месяц (1..12)!
     * @param day   День.
     * @return Дата.
     */
    public static Date getDate(int year, int month, int day) {
        Calendar c = Calendar.getInstance();
        c.set(year, month - 1, day, 0, 0, 0);
        c.set(Calendar.MILLISECOND, 0);
        return c.getTime();
    }

    /**
     * Возвращает указанную дату без времени.
     *
     * @param date Дата.
     * @return Дата с обнуленным временем.
     */
    public static Date getDateWOTime(Date date) {
        Calendar c = Calendar.getInstance();
        c.setTime(date);
        c.set(Calendar.HOUR_OF_DAY, 0);
        c.set(Calendar.MINUTE, 0);
        c.set(Calendar.SECOND, 0);
        c.set(Calendar.MILLISECOND, 0);
        return c.getTime();
    }

    /**
     * Возвращает время из указанной даты.
     *
     * @param date Дата.
     * @return Дата с обнуленной датой (только время).
     */
    public static Date getTimeWODate(Date date) {
        Calendar c = Calendar.getInstance();
        c.setTime(date);
        c.set(Calendar.YEAR, 0);
        c.set(Calendar.MONTH, 0);
        c.set(Calendar.DAY_OF_MONTH, 0);
        return c.getTime();
    }

    /**
     * Возвращает дату с добавлением в неё текущего времени.
     *
     * @param date Дата.
     * @return Дата с установленным текущим временем.
     */
    public static Date getDateWithCurrentTime(Date date) {
        return getDT(date, new Date());
    }

    /**
     * Проверка на попадание даты в диапазон дат.
     *
     * @param value Проверяемая дата.
     * @param d1    Начало периода (включительно!).
     * @param d2    Конец периода (НЕ включительно!).
     * @return Если хоть один из аргументов равен null или проверяемая дата выходит за диапазон, то возвращает false,
     * иначе true.
     */
    public static boolean isInPeriodSafe(Date value, Date d1, Date d2) {
        if (value == null || d1 == null || d2 == null) {
            return false;
        } else {
            return !(value.before(d1) || !value.before(d2));
        }
    }

    /**
     * Проверка на попадание даты в диапазон дат (конечная дата включается!).
     *
     * @param value Проверяемая дата.
     * @param d1    Начало периода (включительно!).
     * @param d2    Конец периода (НЕ включительно!).
     * @return Если хоть один из аргументов равен null или проверяемая дата выходит за диапазон, то возвращает false,
     * иначе true.
     */
    public static boolean isInPeriodIncSafe(Date value, Date d1, Date d2) {
        if (value == null || d1 == null || d2 == null) {
            return false;
        } else {
            return !(value.before(d1) || value.after(d2));
        }
    }

    /**
     * Извлечение года из даты.
     *
     * @param date Дата.
     * @return Год (полное значение - четырехзначное число).
     */
    public static int extractYear(Date date) {
        Calendar c = Calendar.getInstance();
        c.setTime(date);
        return c.get(Calendar.YEAR);
    }

    /**
     * Извлечение времени из таймштампа в виде кол-ва миллисекунд с начала суток.
     *
     * @param dt Таймштамп.
     * @return Кол-во миллисекунд с начала суток.
     */
    public static long extractTimeAsMillis(Date dt) {
        Calendar c = Calendar.getInstance();
        c.setTime(dt);
        int h = c.get(Calendar.HOUR_OF_DAY);
        int m = c.get(Calendar.MINUTE);
        int s = c.get(Calendar.SECOND);
        int ms = c.get(Calendar.MILLISECOND);
        return ms + s * 1000 + m * 60 * 1000 + h * 60 * 60 * 1000;
    }

    public static long extractTimeAsMillis(long dt) {
        return extractTimeAsMillis(new Date(dt));
    }

    /**
     * Представление кол-ва миллисекунд в виде строки (HH:MM:SS) миллисекунды отбрасываются.
     *
     * @param mseconds Кол-во миллисекунд.
     * @return Строка.
     */
    public static String formatHHMMSS(long mseconds) {
        long val = mseconds < 0 ? -mseconds : mseconds;
        long h = val / 3600000;
        long m = (val % 3600000) / 60000;
        long s = (val % 60000) / 1000;
        return String.format("%s%d:%02d:%02d", mseconds < 0 ? "-" : "", h, m, s);
    }
}
