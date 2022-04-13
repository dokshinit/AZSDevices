/*
 * Copyright (c) 2013, Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */
package util;

/**
 * Общие вспомогательные ф-ции.
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
public class CommonTools {

    /**
     * Сравнивает два объекта на идентичность значений.
     *
     * @param v1 Первый объект,
     * @param v2 Второй объект.
     * @return Результат сравнения. Положительный результат, если оба объекта равны null или оба не равны null и равны
     * по значению. Иначе отрицательный результат.
     */
    @SuppressWarnings("RedundantConditionalExpression,SimplifiableConditionalExpression")
    public static boolean isEqualValues(Object v1, Object v2) {
        if (v1 == null) {
            return v2 == null ? true : false;
        } else {
            return v2 == null ? false : v1.equals(v2);
        }
    }

    /**
     * Сравнивает два объекта на null. Данная функция используется как предварительное сравнение (т.е. только если она
     * возвращает неопределенность - 100, тогда надо сравнивать значение).
     *
     * @param o1 Первый объект.
     * @param o2 Второй объект.
     * @return Результат сравнения на null: Если один из объектов null, то он меньше (-1\1). Если оба null - равны (0).
     * Если оба не null - если указатели совпадают - равны (0), если нет - код необходимости сравнения значений объектов
     * (100).
     */
    public static int compareNullForwardWOValue(Object o1, Object o2) {
        if (o1 == null) {
            return o2 == null ? 0 : -1;
        } else {
            return o2 == null ? 1 : (o1 == o2 ? 0 : 100);
        }
    }

    /**
     * Сравнивает два объекта с учётом null (постулируется, что null всегда меньше заданного и между собой null равны).
     *
     * @param o1 Первый объект.
     * @param o2 Второй объект.
     * @return Результат сравнения: Если один из объектов null, то он меньше (-1\1). Если оба null - равны (0). Если оба
     * не null - сравниваются (-1\0\1).
     */
    @SuppressWarnings("unchecked")
    public static int compareNullForward(Comparable o1, Comparable o2) {
        int res = compareNullForwardWOValue(o1, o2);
        return res == 100 ? o1.compareTo(o2) : res;
    }

    /**
     * Проверка объекта на совпадение хотя бы с одним из значений.
     *
     * @param obj  Объект.
     * @param vals Значения.
     * @return Результат проверки: true - совпал с одним из значений, false - нет совпадений.
     */
    public static boolean isIn(Object obj, Object... vals) {
        if (obj == null) {
            for (Object v : vals) if (v == null) return true;
        } else {
            for (Object v : vals) if (obj.equals(v)) return true;
        }
        return false;
    }

    /**
     * Безопасное засыпание на указанное время. При прерывании просто досрочно возвращает управление.
     *
     * @param time Время паузы.
     * @return Флаг индикации прерывания: true - пауза выдержана, false - было преждевременное завершение по прерыванию.
     */
    public static boolean safeInterruptedSleep(long time) {
        try {
            Thread.sleep(time);
            return true;
        } catch (InterruptedException ex) {
            return false;
        }
    }

    /**
     * Безопасное засыпание строго на указанное время, без досрочного прерывания.
     *
     * @param time Время паузы.
     */
    public static void safeNonInterruptedSleep(long time) {
        long tm, t2 = System.currentTimeMillis() + time;
        while ((tm = t2 - System.currentTimeMillis()) > 0) {
            try {
                Thread.sleep(tm);
            } catch (InterruptedException ignore) {
            }
        }
    }

}
