/*
 * Copyright (c) 2013, Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */
package util;

/**
 * Строковые вспомогательные ф-ции.
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
public class StringTools {

    public static boolean isEmptySafe(final String s) {
        return s == null || s.isEmpty();
    }

    public static boolean isTrimEmptySafe(final String s) {
        return s == null || s.trim().isEmpty();
    }

    public static int hexCharToNumber(char ch) {
        if (ch >= '0' && ch <= '9') {
            return (byte) (ch - '0');
        }
        if (ch >= 'A' && ch <= 'F') {
            return (byte) (ch - 'A' + 10);
        }
        if (ch >= 'a' && ch <= 'f') {
            return (byte) (ch - 'a' + 10);
        }
        return 0;
    }

    public static char numberToHexChar(int v) {
        if (v >= 0 && v <= 9) {
            return (char) ('0' + v);
        }
        if (v >= 10 && v <= 15) {
            return (char) ('A' + v - 10);
        }
        return '0';
    }

    public static String arrayToHex(byte[] array, int index, int length) {
        StringBuilder sb = new StringBuilder(length * 2 + 1);
        for (; length > 0; length--) {
            int value = array[index++];
            sb.append(numberToHexChar((value >> 4) & 0xF));
            sb.append(numberToHexChar(value & 0xF));
        }
        return sb.toString();
    }

    public static String arrayToHex(byte[] array) {
        return arrayToHex(array, 0, array.length);
    }

    /**
     * Записывает в массив байты заданные HEX строкой. Если данных заданных HEX строкой меньше, чем указанная длина -
     * остаток заполняется нолями.
     *
     * @param hex    HEX-cтрока.
     * @param array  Байт-массив.
     * @param index  Начальное смещение в байт-массиве записываемых байт.
     * @param length Длина записываемого блока данных (количество байт).
     * @return Массив байт заполненный из HEX строки.
     */
    public static byte[] hexToArray(String hex, byte[] array, int index, int length) {
        if (hex != null && !hex.isEmpty()) {
            int slen = (hex.length() / 2) * 2;
            for (int k = 0; length > 0 && k < slen; length--) {
                int hi = hexCharToNumber(hex.charAt(k++));
                int low = hexCharToNumber(hex.charAt(k++));
                array[index++] = (byte) ((hi << 4) | low);
            }
        }
        for (; length > 0; length--) {
            array[index++] = 0;
        }
        return array;
    }

    public static byte[] hexToArray(String hex) {
        int n = hex.length() / 2;
        return hexToArray(hex, new byte[n], 0, n);
    }


    /**
     * Преобразование значений байт указанной части массива в HEX строку, где каждый HEX символ соответствует одному
     * байту массива (старшие разряды байта отбрасываются!).
     *
     * @param array  Байт-массив.
     * @param index  Начальный индекс обрабатываемой части массива.
     * @param length Длина обрабатываемой части.
     * @return BCD Hex строка.
     */
    public static String arrayToBCDHex(byte[] array, int index, int length) {
        StringBuilder sb = new StringBuilder(length + 1);
        for (; length > 0; length--) sb.append(numberToHexChar(array[index++] & 0xF));
        return sb.toString();
    }

    public static String arrayToBCDHex(byte[] array) {
        return arrayToBCDHex(array, 0, array.length);
    }


    /**
     * Преобразование BCD HEX строки в байты и запись в указанную часть массива. Каждый HEX символ преобразуется в один
     * байт массива по формуле - value(hex)+0x30. Таким образом все значения байт-массива в диапазоне - 0x30-0x3F.
     *
     * @param bcdhex BCD HEX строка.
     * @param array  Байт-массив.
     * @param index  Начальный индекс обрабатываемой части массива.
     * @param length Длина обрабатываемой части. Если HEX строка короче - область массива добивается нулями.
     * @return Массив байт заполненный из BCD HEX строки.
     */
    public static byte[] bcdHexToArray(String bcdhex, byte[] array, int index, int length) {
        if (bcdhex != null && !bcdhex.isEmpty()) {
            int slen = Math.min(bcdhex.length(), length);
            for (int k = 0; k < slen; k++, index++, length--) {
                array[index] = (byte) (0x30 + hexCharToNumber(bcdhex.charAt(k)));
            }
        }
        for (; length > 0; index++, length--) array[index] = 0;
        return array;
    }

    public static byte[] bcdHexToArray(String bcdhex) {
        int n = bcdhex.length();
        return bcdHexToArray(bcdhex, new byte[n], 0, n);
    }


    /** Класс-надстройка над StringBuilder - для удобства формирования текста. */
    public static class TextBuilder {
        private final StringBuilder sb; // Билдер сткроки.
        private final String cr; // Строка добавляемая при "переводе строки".

        /** Конструктор. Позволяет задать последовательность добавляемую для "перевода строки". */
        public TextBuilder(String cr) {
            this.sb = new StringBuilder();
            this.cr = cr;
        }

        /** Конструктор. */
        public TextBuilder() {
            this("\n"); // По умолчанию стандартный перевод строки.
        }

        /**
         * Добавление строки без перехода на новую строку. Если не задан ни один пераметр, то строка считается обычной,
         * иначе - форматная.
         *
         * @param fmt    Форматная строка. Если не задан ни один пераметр, то строка считается обычной.
         * @param params Параметры для форматной строки.
         */
        public TextBuilder print(String fmt, Object... params) {
            if (fmt != null && !fmt.isEmpty()) {
                if (params.length == 0) {
                    sb.append(fmt);
                } else {
                    sb.append(String.format(fmt, params));
                }
            }
            return this;
        }

        /** Добавление перевода строки. */
        public TextBuilder println() {
            sb.append(cr);
            return this;
        }

        /**
         * Добавление строки с переходом на новую строку. Если не задан ни один пераметр, то строка считается обычной,
         * иначе - форматная.
         *
         * @param fmt    Форматная строка. Если не задан ни один пераметр, то строка считается обычной.
         * @param params Параметры для форматной строки.
         */
        public TextBuilder println(String fmt, Object... params) {
            return print(fmt, params).println();
        }

        /** Получение текущего текста в виде строки. */
        @Override
        public String toString() {
            return sb.toString();
        }
    }
}
