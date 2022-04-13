/*
 * Copyright (c) 2015, Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */

package app;

/**
 * Функциональный интерфейс для реализации безопасного вызова методов fireOn*.
 */
@FunctionalInterface
public interface FireCallback {

    void call() throws ExError;

    /**
     * Безопасный вызов call.
     *
     * @param cb Метод.
     * @return Флаг ошибки: true - без ошибок, false - с ошибками.
     */
    static boolean safe(FireCallback cb) {
        try {
            cb.call();
            return true;
        } catch (Exception ex) {
            return false;
        }
    }

    static void unsafe(FireCallback cb) throws ExError {
        cb.call();
    }
}
