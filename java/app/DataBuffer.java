/*
 * Copyright (c) 2015, Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */

package app;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.Charset;
import java.util.Arrays;
import java.util.Date;

import util.StringTools;

/**
 * Буфер для удобной работы с RAW данными (прямых\обратных преобразований).
 * <p>
 * Может использовать не весь массив, а только его часть - фиксированная доступная область массива. Доступная область
 * задаётся при создании буфера и не может быть изменена в процессе работы.
 * <p>
 * В пределах доступной области массива может быть задана рабочая область (рабочее окно). Оно может произвольно изменять
 * свои параметры в пределах доступной области массива.
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
public class DataBuffer {

    /**
     * Рабочая область (окно).
     */
    public static class Area {

        /** Смещение (начало рабочего окна в доступной области массива). */
        public int offset;
        /** Длина (размер рабочего окна в доступоной области массива). */
        public int length;

        /**
         * Конструктор.
         *
         * @param offset Смещение рабочего окна.
         * @param length Длина рабочего окна.
         */
        public Area(int offset, int length) {
            this.offset = offset;
            this.length = length;
        }
    }

    /** Кодировка WIN1251 для строковых преобразований (используется по умолчанию при создании буфера). */
    public static final Charset defaultCharset = Charset.forName("UTF-8");
    /** Текущая кодировка для строковых преобразований по умолчанию (если не указывается в явном виде). */
    private Charset charset;
    /** Буфер для преобразований. */
    private final ByteBuffer bb;

    /** Смещение рабочего окна относительно начала рабочей области массива (bb.arrayOffset()). */
    private int areaOffset;
    /** Размер рабочего окна. */
    private int areaLength;

    /**
     * Конструктор.
     *
     * @param backbuffer Массив. Может быть = null, тогда массив будет создан по заданной длине.
     * @param offset     Начальное смещение доступной области в массиве (игнорируется, если массив не задан).
     * @param length     Длина доступной области в массиве. Если задан буфер, то может быть нулевой (тогда длина
     *                   вычисляется от смещения до конца массива) или меньше нуля (тогда длина вычисляется от смещения
     *                   и до конца массива уменьшенная на модуль указанной длины).
     * @param charset    Кодировка по умолчанию для строковых операций.
     */
    public DataBuffer(byte[] backbuffer, int offset, int length, Charset charset) {
        int bblen = backbuffer != null ? backbuffer.length : 0;

        if (backbuffer == null) {
            // Если буфер не задан, то отступ игнорируется (т.к. невозможно будет использовать пространство до него)!
            if (offset != 0 || length < 0)
                throw new ExOutOfRange("DataBuffer(0,%d,%d)", offset, length);
            backbuffer = new byte[length];
            Arrays.fill(backbuffer, (byte) 0);
        } else {
            // Если смещение выходит за массив - ошибка.
            if (offset < 0 || offset >= backbuffer.length)
                throw new ExOutOfRange("DataBuffer(%d,%d,%d)", bblen, offset, length);
            if (length == 0) {
                length = backbuffer.length - offset;
            } else if (length < 0) {
                length = backbuffer.length - offset + length;
            } else {
                // Если длина задана в явном виде (>0) - проверяем на укладывание в массив.
                if (offset + length > backbuffer.length)
                    throw new ExOutOfRange("DataBuffer(%d,%d,%d)", bblen, offset, length);
            }
        }
        this.bb = ByteBuffer.wrap(backbuffer, offset, length).slice(); // Вырезаем буфер по смещению и длине.
        this.bb.order(ByteOrder.LITTLE_ENDIAN);
        this.charset = charset;
        reset(); // Для начальной инициализации рабочего окна на всю доступную область.
    }

    /**
     * Конструктор.
     *
     * @param backbuffer Массив. Может быть = null, тогда массив будет создан по заданной длине.
     * @param offset     Начальное смещение доступной области в массиве (игнорируется, если массив не задан).
     * @param length     Длина доступной области в массиве. Если задан буфер, то может быть нулевой (тогда длина
     *                   вычисляется от смещения до конца массива) или меньше нуля (тогда длина вычисляется от смещения
     *                   и до конца массива уменьшенная на модуль указанной длины).
     */
    public DataBuffer(byte[] backbuffer, int offset, int length) {
        this(backbuffer, offset, length, defaultCharset);
    }

    /**
     * Конструктор.
     *
     * @param length  Длина доступной области в массиве. Если задан буфер, то может быть нулевой (тогда длина
     *                вычисляется от смещения до конца массива) или меньше нуля (тогда длина вычисляется от смещения и
     *                до конца массива уменьшенная на модуль указанной длины).
     * @param charset Кодировка по умолчанию для строковых операций.
     */
    public DataBuffer(int length, Charset charset) {
        this(null, 0, length, charset);
    }

    /**
     * Конструктор.
     *
     * @param length Длина доступной области в массиве. Если задан буфер, то может быть нулевой (тогда длина вычисляется
     *               от смещения до конца массива) или меньше нуля (тогда длина вычисляется от смещения и до конца
     *               массива уменьшенная на модуль указанной длины).
     */
    public DataBuffer(int length) {
        this(length, defaultCharset);
    }

    /**
     * Конструктор.
     */
    public DataBuffer() {
        this(256, defaultCharset);
    }

    /**
     * Создание нового буфера на базе буфера-источника. Позиционирование происходит относительно и в пределах доступной
     * области буфера-источника.
     *
     * @param offset  Смещение начала буфера относительно начала доступной области буфера-источника.
     * @param length  Длина буфера. Может быть нулевой (тогда длина вычисляется от смещения до конца доступной области
     *                буфера-источника) или меньше нуля (тогда длина вычисляется от смещения и до конца доступной
     *                области буфера-источника уменьшенная на модуль указанной длины).
     * @param charset Кодировка для строковых операций буфера.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer wrap(int offset, int length, Charset charset) {
        return new DataBuffer(bb.array(), bb.arrayOffset() + offset, length, charset);
    }

    /**
     * Создание нового буфера на базе буфера-источника. Позиционирование происходит относительно и в пределах доступной
     * области буфера-источника.
     *
     * @param offset Смещение начала буфера относительно начала доступной области буфера-источника.
     * @param length Длина буфера. Может быть нулевой (тогда длина вычисляется от смещения до конца доступной области
     *               буфера-источника) или меньше нуля (тогда длина вычисляется от смещения и до конца доступной области
     *               буфера-источника уменьшенная на модуль указанной длины).
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer wrap(int offset, int length) {
        return wrap(offset, length, charset);
    }

    /**
     * Создание нового буфера на базе буфера-источника. Позиционирование происходит относительно и в пределах доступной
     * области буфера-источника.
     *
     * @param offset Смещение начала буфера относительно начала доступной области буфера-источника.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer wrap(int offset) {
        return wrap(offset, 0, charset);
    }

    /**
     * Получение смещения рабочего окна.
     *
     * @return Смещение начала рабочего окна в буфере.
     */
    public int offset() {
        return areaOffset;
    }

    /**
     * Получение размера рабочего окна.
     *
     * @return Размер рабочего окна.
     */
    public int length() {
        return areaLength;
    }

    /**
     * Получение рабочего окна.
     *
     * @return Описатель рабочего окна.
     */
    public Area area() {
        return new Area(areaOffset, areaLength);
    }

    /**
     * Установка рабочей области (окна). Тек.позиция устанавливается в начало окна.
     *
     * @param offset Смещение рабочей области окна относительно начала буфера.
     * @param length Длина рабочей области окна.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer area(int offset, int length) throws ExOutOfRange {
        if (offset < 0 || length < 0 || offset + length > capacity())
            throw new ExOutOfRange("area(%d,%d) [%d]", offset, length, capacity());
        this.areaOffset = offset;
        this.areaLength = length;
        bb.limit(areaOffset + areaLength);
        bb.position(areaOffset);
        mark(); // По умолчанию маркер устанавливается на начало окна.
        return this;
    }

    /**
     * Установка рабочей области окна. Тек.позиция устанавливается в начало окна.
     *
     * @param area Рабочее окно.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer area(Area area) {
        if (area == null) {
            return reset();
        } else {
            return area(area.offset, area.length);
        }
    }

    /**
     * Обновление текущего рабочего окна. Применяется для восстановления актуальных параметорв ByteBuffer при их внешнем
     * изменении. Тек.указатель и маркер не изменяются!
     *
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer refresh() {
        bb.limit(areaOffset + areaLength);
        return this;
    }

    /**
     * Установка рабочей области окна на весь буфер с установкой тек.позиция в начало окна.
     *
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer reset() {
        return area(0, capacity());
    }

    /**
     * Обновление текущего рабочего окна с установкой тек.позицией в начало текущего окна.
     *
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer rewind() {
        return area(areaOffset, areaLength);
    }

    /**
     * Установка рабочего окна от начала окна и до тек.позиции (не включительно) с установкой тек.позиции в начало
     * окна.
     *
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer flip() {
        return area(areaOffset, pos());
    }

    /**
     * Установка рабочего окна от начала буфера (!) и до тек.позиции (не включительно). Тек.позиция в начало.
     *
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer flipBuffer() {
        return area(0, areaOffset + pos());
    }

    /**
     * Установка рабочего окна от тек.позиции и до конца окна с установкой тек.позиции в начало окна.
     *
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer tail() {
        return area(areaOffset + pos(), areaLength - pos());
    }

    /**
     * Установка рабочего окна от тек.позиции и до конца буфера (!). Тек.позиция в начало.
     *
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer tailBuffer() {
        return area(areaOffset + pos(), capacity() - (areaOffset + pos()));
    }

    /**
     * Установка смещения рабочего окна с сохранением позиции его конца - размер окна изменяется. Установка тек.позиции
     * в начало окна.
     *
     * @param offset Смещение начала рабочего окна.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer offset(int offset) {
        return area(offset, areaOffset + areaLength - offset);
    }

    /**
     * Установка длины рабочего окна с установкой тек.позиции в начало окна.
     *
     * @param length Длина рабочего окна.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer length(int length) {
        return area(areaOffset, length);
    }

    /**
     * Установка длины рабочего окна от начала окна и до конца буфера (!).
     *
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer lengthMaximize() {
        return area(areaOffset, capacity() - areaOffset);
    }

    /**
     * Сдвиг рабочего окна на указанную величину. Рамер окна не изменяется.
     *
     * @param shift Величина сдвига рабочего окна.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer shiftArea(int shift) {
        return area(areaOffset + shift, areaLength);
    }

    /**
     * Сдвиг начала рабочего окна с сохранением позиции его конца. Размер окна изменяется на размер сдвига.
     *
     * @param shift Величина сдвига начала рабочего окна.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer shiftOffset(int shift) {
        return area(areaOffset + shift, areaLength - shift);
    }

    /**
     * Сдвиг размера рабочего окна. Начало окна не изменяется, размер окна изменяется на размер сдвига.
     *
     * @param shift Величина сдвига размера рабочего окна.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer shiftLength(int shift) {
        return area(areaOffset, areaLength + shift);
    }

    /**
     * Получение бэк-массива.
     *
     * @return Массив.
     */
    public byte[] buffer() {
        return bb.array();
    }

    /**
     * Получение начала доступной области массива.
     *
     * @return Позиция начала доступной области массива (нулевая позиция для начала рабочего окна).
     */
    public int arrayOffset() {
        return bb.arrayOffset();
    }

    /**
     * Получение длины доступной области массива. Максимальная длина рабочего окна.
     *
     * @return Длина доступной области массива.
     */
    public int capacity() {
        return bb.capacity();
    }

    /**
     * Получение кол-ва байт от тек.позиции до конца окна.
     *
     * @return Кол-во оставшихся байт до конца окна.
     */
    public int remaining() {
        return areaLength - pos();
    }

    /**
     * Проверка наличия данных. Т.е. недостижения конца рабочего окна.
     *
     * @return Флаг наличия данных: true - есть, false - нет, конец рабочего окна достигнут.
     */
    public boolean hasRemaining() {
        return bb.hasRemaining();
    }

    /**
     * Маркер для пометки текущей позиции и возможности последующего вычисления разницы между отмеченной и текущей
     * позицией. Может использоваться для определения кол-ва считанных или записанных байт при различных операциях, для
     * этого используется связка команд: mark() + marked().
     */
    private int mark = 0;

    /**
     * Маркировка текущей позиции. Может использоваться для определения кол-ва считанных или записанных байт при
     * различных операциях, для этого используется связка команд: mark() + marked().
     *
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer mark() {
        mark = bb.position();
        return this;
    }

    /**
     * Получение разницы между маркированной позицией и текущей. Может использоваться для определения кол-ва считанных
     * или записанных байт при различных операциях, для этого используется связка команд: mark() + marked().
     *
     * @return Кол-во маркированных байт.
     */
    public int marked() {
        return bb.position() - mark;
    }

    /**
     * Получение маркированной позиции.
     *
     * @return Позиция маркера.
     */
    public int markedPos() {
        return mark;
    }

    /**
     * Получение байт-буфера для операций требующих байт-буфер. Если будут вызываться команды изменения позиции или
     * лимита, то необходимо вызвать area() для восстановления валидных позиции и лимита.
     *
     * @return Байт-буфер. При внесении изменений в байт-буфер (limit) для синхронизации с буфером необходимо вызовать
     * метод refresh().
     */
    public ByteBuffer getBB() {
        return bb;
    }

    /**
     * Получение нового байт-буфера как части от тек.позиции до конца окна (лимит).
     *
     * @return Часть байт-буфера.
     */
    public ByteBuffer sliceBB() {
        return bb.slice();
    }

    /**
     * Получение нового байт-буфера как части равной рабочему окну.
     *
     * @return Часть байт-буфера равная рабочему окну.
     */
    public ByteBuffer areaBB() {
        int curpos = getPosAndPos(0); // Сохраняем позицию и переходим в начало окна.
        ByteBuffer b = bb.slice();
        pos(curpos);
        return b;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //  ОПЕРАЦИИ ПОЗИЦИОНИРОВАНИЯ
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * Получение текущей позиции в рабочем окне.
     *
     * @return Текущая позиция.
     */
    public int pos() {
        return bb.position() - areaOffset;
    }

    /**
     * Установка текущей позиции в рабочем окне.
     *
     * @param newpos Новая текущая позиция.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer pos(int newpos) {
        if (newpos < 0 || newpos > areaLength)
            throw new ExOutOfRange("pos(%d) [%d]", newpos, areaLength);
        bb.position(areaOffset + newpos);
        return this;
    }

    /**
     * Установка текущей позиции в конец рабочего окна.
     *
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer posToEnd() {
        return pos(length());
    }

    /**
     * Сдвиг текущей позиции на заданное кол-во байт.
     *
     * @param shift Значение сдвига текущей позиции.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer shift(int shift) {
        pos(pos() + shift);
        return this;
    }

    /**
     * Получение текущей позиции и установка новой текущей позиции в рабочем окне.
     *
     * @param newpos Новая текущая позиция.
     * @return Старая текущая позиция (до операции установки).
     */
    public int getPosAndPos(int newpos) {
        int pos = pos();
        pos(newpos);
        return pos;
    }

    /**
     * Получение текущей позиции и сдвиг текущей позиции в рабочем окне.
     *
     * @param shift Значение сдвига текущей позиции.
     * @return Старая текущая позиция (до операции сдвига).
     */
    public int getPosAndShift(int shift) {
        int pos = pos();
        shift(shift);
        return pos;
    }


    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // ОПЕРАЦИИ ЧТЕНИЯ ДАННЫХ ИЗ БУФЕРА
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * Чтение byte (1 байт) из указанной позиции в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Считанное значение.
     */
    public int getAt(int index) {
        exIfOutOfArea(index, 1, "getAt");
        return bb.get(areaOffset + index) & 0xFF;
    }

    /**
     * Чтение byte (1 байт) из текущей позиции в рабочем окне и сдвиг текущей позиции вперед на кол-во считаных байт.
     *
     * @return Считанное значение.
     */
    public int get() {
        return getAt(getPosAndShift(1));
    }

    /**
     * Чтение int (4 байта) из указанной позиции в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Считанное значение.
     */
    public int getIntAt(int index) {
        exIfOutOfArea(index, 4, "getIntAt");
        return bb.getInt(areaOffset + index);
    }

    /**
     * Чтение int (4 байта) из текущей позиции в рабочем окне и сдвиг текущей позиции вперед на кол-во считаных байт.
     *
     * @return Считанное значение.
     */
    public int getInt() {
        return getIntAt(getPosAndShift(4));
    }

    /**
     * Чтение int (2 байта) из указанной позиции в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Считанное значение.
     */
    public int getInt2At(int index) {
        exIfOutOfArea(index, 2, "getInt2At");
        return bb.getShort(areaOffset + index) & 0xFFFF;
    }

    /**
     * Чтение int (2 байта) из текущей позиции в рабочем окне и сдвиг текущей позиции вперед на кол-во считаных байт.
     *
     * @return Считанное значение.
     */
    public int getInt2() {
        return getInt2At(getPosAndShift(2));
    }

    /**
     * Чтение int (3 байта) из указанной позиции в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Считанное значение.
     */
    public int getInt3At(int index) {
        exIfOutOfArea(index, 3, "getInt3At");
        return getInt2At(index) | (getAt(index + 2) << 16);
    }

    /**
     * Чтение int (3 байта) из текущей позиции в рабочем окне и сдвиг текущей позиции вперед на кол-во считаных байт.
     *
     * @return Считанное значение.
     */
    public int getInt3() {
        return getInt3At(getPosAndShift(3));
    }

    /**
     * Чтение long (8 байт) из указанной позиции в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Считанное значение.
     */
    public long getLongAt(int index) {
        exIfOutOfArea(index, 8, "getLongAt");
        return bb.getLong(areaOffset + index);
    }

    /**
     * Чтение long (8 байт) из текущей позиции в рабочем окне и сдвиг текущей позиции вперед на кол-во считаных байт.
     *
     * @return Считанное значение.
     */
    public long getLong() {
        return getLongAt(getPosAndShift(8));
    }

    /**
     * Чтение long (5 байт) из указанной позиции в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Считанное значение.
     */
    public long getLong5At(int index) {
        exIfOutOfArea(index, 5, "getLong5At");
        return (bb.getInt(areaOffset + index) & 0xFFFFFFFFL)
                | ((bb.get(areaOffset + index + 4) & 0xFFL) << 32);
    }

    /**
     * Чтение long (5 байт) из текущей позиции в рабочем окне и сдвиг текущей позиции вперед на кол-во считаных байт.
     *
     * @return Считанное значение.
     */
    public long getLong5() {
        return getLong5At(getPosAndShift(5));
    }

    /**
     * Чтение long (6 байт) из указанной позиции в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Считанное значение.
     */
    public long getLong6At(int index) {
        exIfOutOfArea(index, 6, "getLong6At");
        return (bb.getInt(areaOffset + index) & 0xFFFFFFFFL)
                | ((bb.getShort(areaOffset + index + 4) & 0xFFFFL) << 32);
    }

    /**
     * Чтение long (6 байт) из текущей позиции в рабочем окне и сдвиг текущей позиции вперед на кол-во считаных байт.
     *
     * @return Считанное значение.
     */
    public long getLong6() {
        return getLong6At(getPosAndShift(6));
    }

    /**
     * Чтение long (7 байт) из указанной позиции в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Считанное значение.
     */
    public long getLong7At(int index) {
        exIfOutOfArea(index, 7, "getLong7At");
        return (bb.getInt(areaOffset + index) & 0xFFFFFFFFL)
                | ((bb.getShort(areaOffset + index + 4) & 0xFFFFL) << 32)
                | ((bb.get(areaOffset + index + 6) & 0xFFL) << 48);
    }

    /**
     * Чтение long (7 байт) из текущей позиции в рабочем окне и сдвиг текущей позиции вперед на кол-во считаных байт.
     *
     * @return Считанное значение.
     */
    public long getLong7() {
        return getLong7At(getPosAndShift(7));
    }

    /**
     * Чтение long из текста (старшие регистры в начале) из указанной позиции. Не влияет на текущую позицию.
     *
     * @param index  Позиция в рабочем окне.
     * @param length Кол-во считываемых байт.
     * @return Считанное значение.
     */
    public long getLongFromStringAt(int index, int length) {
        exIfOutOfArea(index, length, "getLongFromStringAt");
        long res = 0;
        length = index + length > length() ? length() - index : length;
        for (int i = 0; i < length; i++) {
            res = res * 10 + ((bb.get(areaOffset + index + i) & 0xFF) - 0x30);
        }
        return res;
    }

    /**
     * Чтение long из текста (старшие регистры в начале) из текущей позиции в рабочем окне и сдвиг текущей позиции
     * вперед на кол-во считаных байт.
     *
     * @return Считанное значение.
     */
    public long getLongFromString(int length) {
        return getLongFromStringAt(getPosAndShift(length), length);
    }

    /**
     * Чтение int из текста (старшие регистры в начале) из указанной позиции. Не влияет на текущую позицию. Метод
     * добавлен исключительно для удобства - для ислючения преобразования (использует метод для чтения long).
     *
     * @param index  Позиция в рабочем окне.
     * @param length Кол-во считываемых байт.
     * @return Считанное значение.
     */
    public int getIntFromString(int index, int length) {
        return (int) (getLongFromStringAt(index, length) & 0xFFFFFFFFL);
    }

    /**
     * Чтение long из текста (старшие регистры в начале) из текущей позиции в рабочем окне и сдвиг текущей позиции
     * вперед на кол-во считаных байт. Метод добавлен исключительно для удобства - для ислючения преобразования
     * (использует метод для чтения long).
     *
     * @param length Кол-во считываемых байт.
     * @return Считанное значение.
     */
    public int getIntFromString(int length) {
        return (int) (getLongFromString(length) & 0xFFFFFFFFL);
    }

    /**
     * Чтение Date (8 байт) из указанной позиции в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Считанное значение.
     */
    public Date getDateAt(int index) {
        exIfOutOfArea(index, 8, "getDateAt");
        return new Date(bb.getLong(areaOffset + index));
    }

    /**
     * Чтение Date (8 байт) из текущей позиции в рабочем окне и сдвиг текущей позиции вперед на кол-во считаных байт.
     *
     * @return Считанное значение.
     */
    public Date getDate() {
        return getDateAt(getPosAndShift(8));
    }

    /**
     * Чтение byte[] из указанной позиции в рабочем окне и заданной длины. Не влияет на текущую позицию.
     *
     * @param index  Позиция в рабочем окне.
     * @param length Кол-во считываемых байт.
     * @return Считанное значение.
     */
    public byte[] getArrayAt(int index, int length) {
        exIfOutOfArea(index, length, "getArrayAt");
        int off = arrayOffset() + areaOffset + index;
        return Arrays.copyOfRange(buffer(), off, off + length);
    }

    /**
     * Чтение byte[] из текущей позиции в рабочем окне и сдвиг текущей позиции вперед на кол-во считаных байт.
     *
     * @param length Кол-во считываемых байт.
     * @return Считанное значение.
     */
    public byte[] getArray(int length) {
        return getArrayAt(getPosAndShift(length), length);
    }

    /**
     * Чтение строки из указанной позиции в рабочем окне (преобразование массива в строку). Не влияет на текущую
     * позицию.
     *
     * @param index   Позиция в рабочем окне.
     * @param length  Кол-во считываемых байт.
     * @param charset Кодировка.
     * @return Считанное значение.
     */
    public String getStringAt(int index, int length, Charset charset) {
        exIfOutOfArea(index, length, "getStringAt");
        return new String(buffer(), arrayOffset() + areaOffset + index, length, charset != null ? charset : this.charset);
    }

    /**
     * Чтение строки из указанной позиции в рабочем окне (преобразование массива в строку). Не влияет на текущую
     * позицию.
     *
     * @param index  Позиция в рабочем окне.
     * @param length Кол-во считываемых байт.
     * @return Считанное значение.
     */
    public String getStringAt(int index, int length) {
        return getStringAt(index, length, charset);
    }

    /**
     * Чтение строки из текущей позиции в рабочем окне и сдвиг текущей позиции вперед на кол-во считаных байт.
     *
     * @param length  Кол-во считываемых байт.
     * @param charset Кодировка.
     * @return Считанное значение.
     */
    public String getString(int length, Charset charset) {
        return getStringAt(getPosAndShift(length), length, charset);
    }

    /**
     * Чтение строки из текущей позиции в рабочем окне и сдвиг текущей позиции вперед на кол-во считаных байт.
     *
     * @param length Кол-во считываемых байт.
     * @return Считанное значение.
     */
    public String getString(int length) {
        return getString(length, charset);
    }

    /**
     * Чтение ZString (строки с завершающим нулевым символом) из указанной позиции в рабочем окне (преобразование
     * массива в строку). Не влияет на текущую позицию. Первый нулевой символ в пределах заданной длины - ограничивает
     * строку. Нулевого символа может не быть, если строка занимает всю указанную длину.
     *
     * @param index   Позиция в рабочем окне.
     * @param length  Длина - максимальное кол-во считываемых байт.
     * @param charset Кодировка.
     * @return Считанное значение.
     */
    public String getZStringAt(int index, int length, Charset charset) {
        exIfOutOfArea(index, length, "getZStringAt");
        // Первый нулевой символ - конец строки - обрезаем по нему.
        byte[] buffer = buffer();
        int off = arrayOffset() + areaOffset + index;
        for (int i = 0; i < length; i++) {
            if (buffer[off + i] == 0) {
                length = i;
                break;
            }
        }
        return new String(buffer, areaOffset + index, length, charset != null ? charset : this.charset);
    }

    /**
     * Чтение ZString (строки с завершающим нулевым символом) из указанной позиции в рабочем окне (преобразование
     * массива в строку). Не влияет на текущую позицию. Первый нулевой символ в пределах заданной длины - ограничивает
     * строку. Нулевого символа может не быть, если строка занимает всю указанную длину.
     *
     * @param index  Позиция в рабочем окне.
     * @param length Длина - максимальное кол-во считываемых байт.
     * @return Считанное значение.
     */
    public String getZStringAt(int index, int length) {
        return getZStringAt(index, length, charset);
    }

    /**
     * Чтение ZString (строки с завершающим нулевым символом) из текущей позиции в рабочем окне (преобразование массива
     * в строку) и сдвиг текущей позиции вперед на заданную длину (<u>ВНИМАНИЕ именно на заданную длину!!!</u>). Первый
     * нулевой символ в пределах заданной длины - ограничивает строку. Нулевого символа может не быть, если строка
     * занимает всю указанную длину.
     *
     * @param length  Длина - максимальное кол-во считываемых байт.
     * @param charset Кодировка.
     * @return Считанное значение.
     */
    public String getZString(int length, Charset charset) {
        return getZStringAt(getPosAndShift(length), length, charset);
    }

    /**
     * Чтение ZString (строки с завершающим нулевым символом) из текущей позиции в рабочем окне (преобразование массива
     * в строку) и сдвиг текущей позиции вперед на заданную длину (<u>ВНИМАНИЕ именно на заданную длину!!!</u>). Первый
     * нулевой символ в пределах заданной длины - ограничивает строку. Нулевого символа может не быть, если строка
     * занимает всю указанную длину.
     *
     * @param length Длина - максимальное кол-во считываемых байт.
     * @return Считанное значение.
     */
    public String getZString(int length) {
        return getZString(length, charset);
    }

    /**
     * Чтение NString (строки с записанной длиной) (длина занимает от одного до четырех байт) из указанной позиции
     * рабочего окна. Не влияет на текущую позицию.
     *
     * @param index Позиция начала в рабочем окне.
     * @return Строка.
     */
    public String getNStringAt(int index) {
        int len = 0, i = 0, v;
        do {
            v = getAt(index + i);
            len = (v & 0x7F) << (7 * i) | len;
            i++;
        } while (i < 4 && v > 0x7F);
        return getStringAt(index + i, len);
    }

    /**
     * Чтение NString (строки с записанной длиной) (длина занимает от одного до четырех байт) из текущей позиции в
     * рабочем окне и сдвиг текущей позиции вперед на кол-во считаных байт.
     *
     * @param charset Кодировка.
     * @return Считанное значение.
     */
    public String getNString(Charset charset) {
        int len = 0, i = 0, v;
        do {
            v = get();
            len = (v & 0x7F) << (7 * i) | len;
            i++;
        } while (i < 4 && v > 0x7F);
        return getString(len, charset);
    }

    /**
     * Чтение NString (строки с записанной длиной) (длина занимает от одного до четырех байт) из текущей позиции в
     * рабочем окне и сдвиг текущей позиции вперед на кол-во считаных байт.
     *
     * @return Считанное значение.
     */
    public String getNString() {
        return getNString(charset);
    }

    /**
     * Чтение HEX строки из указанной позиции в рабочем окне (преобразование массива в HEX строку). Не влияет на текущую
     * позицию. HEX = один байт массива (0x00-0xFF) преобразуется в двухсимвольный hex ('00'-'FF').
     *
     * @param index  Позиция в рабочем окне.
     * @param length Кол-во считываемых байт.
     * @return Считанное значение.
     */
    public String getHexAt(int index, int length) {
        exIfOutOfArea(index, length, "getHexAt");
        return StringTools.arrayToHex(buffer(), arrayOffset() + areaOffset + index, length);
    }

    /**
     * Чтение HEX строки из указанной позиции в рабочем окне (преобразование массива в HEX строку) и сдвиг текущей
     * позиции вперед на кол-во считаных байт. HEX = один байт массива (0x00-0xFF) преобразуется в двухсимвольный hex
     * ('00'-'FF').
     *
     * @param length Кол-во считываемых байт.
     * @return Считанное значение.
     */
    public String getHex(int length) {
        return getHexAt(getPosAndShift(length), length);
    }

    /**
     * Чтение BCD HEX строки из указанной позиции в рабочем окне (преобразование массива в BCD HEX строку). Не влияет на
     * текущую позицию. BCD HEX = один байт массива (0xN0-0xNF) преобразуется в один символ HEX строки ('0'-'F').
     *
     * @param index  Позиция в рабочем окне.
     * @param length Кол-во считываемых байт.
     * @return Считанное значение.
     */
    public String getBCDHexAt(int index, int length) {
        exIfOutOfArea(index, length, "getBCDHexAt");
        return StringTools.arrayToBCDHex(buffer(), arrayOffset() + areaOffset + index, length);
    }

    /**
     * Чтение BCD HEX строки из текущей позиции в рабочем окне (преобразование массива в BCD HEX строку) и сдвиг текущей
     * позиции вперед на кол-во считаных байт. BCD HEX = один байт массива (0xN0-0xNF) преобразуется в один символ HEX
     * строки ('0'-'F').
     *
     * @param length Кол-во считываемых байт.
     * @return Считанное значение.
     */
    public String getBCDHex(int length) {
        return getBCDHexAt(getPosAndShift(length), length);
    }


    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    // ОПЕРАЦИИ ЗАПИСИ ДАННЫХ В БУФЕР
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * Запись byte (1 байт) в указанную позицию в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putAt(int index, int value) {
        exIfOutOfArea(index, 1, "putAt");
        bb.put(areaOffset + index, (byte) (value & 0xFF));
        return this;
    }

    /**
     * Запись byte (1 байт) в указанную позицию в рабочем окне и сдвиг текущей позиции вперед на кол-во записанных
     * байт.
     *
     * @param value Записываемое значение.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer put(int value) {
        return DataBuffer.this.putAt(pos(), value).shift(1);
    }

    /**
     * Запись int (4 байта) в указанную позицию в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putIntAt(int index, int value) {
        exIfOutOfArea(index, 4, "putIntAt");
        bb.putInt(areaOffset + index, value);
        return this;
    }

    /**
     * Запись int (4 байта) в указанную позицию в рабочем окне и сдвиг текущей позиции вперед на кол-во записанных
     * байт.
     *
     * @param value Записываемое значение.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putInt(int value) {
        return putIntAt(pos(), value).shift(4);
    }

    /**
     * Запись int (2 байта) в указанную позицию в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putInt2At(int index, int value) {
        exIfOutOfArea(index, 2, "putInt2At");
        bb.putShort(areaOffset + index, (short) (value & 0xFFFF));
        return this;
    }

    /**
     * Запись int (2 байта) в указанную позицию в рабочем окне и сдвиг текущей позиции вперед на кол-во записанных
     * байт.
     *
     * @param value Записываемое значение.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putInt2(int value) {
        return putInt2At(pos(), value).shift(2);
    }

    /**
     * Запись int (3 байта) в указанную позицию в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putInt3At(int index, int value) {
        exIfOutOfArea(index, 3, "putInt3At");
        bb.putShort(areaOffset + index, (short) (value & 0xFFFF))
                .put(areaOffset + index + 2, (byte) ((value >> 16) & 0xFF));
        return this;
    }

    /**
     * Запись int (3 байта) в указанную позицию в рабочем окне и сдвиг текущей позиции вперед на кол-во записанных
     * байт.
     *
     * @param value Записываемое значение.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putInt3(int value) {
        return putInt3At(pos(), value).shift(3);
    }

    /**
     * Запись long (8 байт) в указанную позицию в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putLongAt(int index, long value) {
        exIfOutOfArea(index, 8, "putLongAt");
        bb.putLong(areaOffset + index, value);
        return this;
    }

    /**
     * Запись long (8 байт) в указанную позицию в рабочем окне и сдвиг текущей позиции вперед на кол-во записанных
     * байт.
     *
     * @param value Записываемое значение.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putLong(long value) {
        return putLongAt(pos(), value).shift(8);
    }

    /**
     * Запись long (5 байт) в указанную позицию в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putLong5At(int index, long value) {
        exIfOutOfArea(index, 5, "putLong5At");
        bb.putInt(areaOffset + index, (int) (value & 0xFFFFFFFF))
                .put(index + 4, (byte) ((value >> 32) & 0xFF));
        return this;
    }

    /**
     * Запись long (5 байт) в указанную позицию в рабочем окне и сдвиг текущей позиции вперед на кол-во записанных
     * байт.
     *
     * @param value Записываемое значение.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putLong5(long value) {
        return putLong5At(pos(), value).shift(5);
    }

    /**
     * Запись long (6 байт) в указанную позицию в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putLong6At(int index, long value) {
        exIfOutOfArea(index, 6, "putLong6At");
        bb.putInt(areaOffset + index, (int) (value & 0xFFFFFFFF))
                .putShort(index + 4, (short) ((value >> 32) & 0xFFFF));
        return this;
    }

    /**
     * Запись long (6 байт) в указанную позицию в рабочем окне и сдвиг текущей позиции вперед на кол-во записанных
     * байт.
     *
     * @param value Записываемое значение.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putLong6(long value) {
        return putLong6At(pos(), value).shift(6);
    }

    /**
     * Запись long (7 байт) в указанную позицию в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putLong7At(int index, long value) {
        exIfOutOfArea(index, 7, "putLong7At");
        bb.putInt(areaOffset + index, (int) (value & 0xFFFFFFFF))
                .putShort(index + 4, (short) ((value >> 32) & 0xFFFF))
                .putShort(index + 6, (byte) ((value >> 48) & 0xFF));
        return this;
    }

    /**
     * Запись long (7 байт) в указанную позицию в рабочем окне и сдвиг текущей позиции вперед на кол-во записанных
     * байт.
     *
     * @param value Записываемое значение.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putLong7(long value) {
        return putLong7At(pos(), value).shift(7);
    }

    /**
     * Запись long как текст в указанную позицию в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index  Позиция в рабочем окне.
     * @param value  Записываемое значение.
     * @param length Кол-во записываемых байт.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putLongAsStringAt(int index, long value, int length) {
        exIfOutOfArea(index, length, "putLongAsStringAt");
        for (int i = length - 1; i >= 0; i--) {
            bb.put(areaOffset + index + i, (byte) ((value % 10) + 0x30));
            value /= 10;
        }
        return this;
    }

    /**
     * Запись long как текст в текущую позицию в рабочем окне и сдвиг текущей позиции вперед на кол-во записанных байт.
     *
     * @param value  Записываемое значение.
     * @param length Кол-во записываемых байт.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putLongAsString(long value, int length) {
        return putLongAsStringAt(pos(), value, length).shift(length);
    }

    /**
     * Запись Date (8 байт) в указанную позицию в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index Позиция в рабочем окне.
     * @param value Записываемое значение.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putDateAt(int index, Date value) {
        exIfOutOfArea(index, 8, "putDateAt");
        bb.putLong(areaOffset + index, value.getTime());
        return this;
    }

    /**
     * Запись Date (8 байт) в текущую позицию в рабочем окне и сдвиг текущей позиции вперед на кол-во записанных байт.
     *
     * @param value Записываемое значение.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putDate(Date value) {
        return putDateAt(pos(), value).shift(8);
    }

    /**
     * Запись byte[] в указанную позицию в рабочем окне. Не влияет на текущую позицию.
     * <p>
     * Подразумевается, что параметры заданы корректно (т.е. указанная часть находится в пределах массива-источника и
     * помещается в рабочем окне буфера-приёмника).
     *
     * @param index  Позиция в рабочем окне.
     * @param array  Записываемый массив-источник.
     * @param offset Начальное смещение в массиве-источнике.
     * @param length Кол-во записываемых байт. Если выходит за рамки массива-источника, то добивает приёмник нулями до
     *               необходимой длины.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putArrayAt(int index, byte[] array, int offset, int length) {
        if (offset < 0 || offset + length > array.length)
            throw new ExOutOfRange("putArrayAt(%d,%d) dst:[%d]", offset, length, array.length);
        if (index < 0 || index + length > areaLength)
            throw new ExOutOfRange("putArrayAt(%d,%d) src:[%d]", index, length, areaLength);
        for (int i = 0; i < length; i++) {
            bb.put(areaOffset + index + i, array[offset + i]);
        }
        return this;
    }

    /**
     * Запись byte[] в текущую позицию в рабочем окне и сдвиг текущей позиции вперед на кол-во записанных байт.
     * <p>
     * Подразумевается, что параметры заданы корректно (т.е. указанная часть находится в пределах массива-источника и
     * помещается в рабочем окне буфера-приёмника).
     *
     * @param array  Записываемый массив-источник.
     * @param offset Начальное смещение в массиве-источнике.
     * @param length Кол-во записываемых байт. Если выходит за рамки массива-источника, то добивает приёмник нулями до
     *               необходимой длины.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putArray(byte[] array, int offset, int length) {
        return putArrayAt(pos(), array, offset, length).shift(length);
    }

    /**
     * Запись рабочего окна буфера-источника в указанную позицию в рабочем окне. Не влияет на текущую позицию.
     * <p>
     * Подразумевается, что параметры заданы корректно (т.е. данные помещаются в рабочем окне буфера-приёмника).
     *
     * @param index Позиция в рабочем окне.
     * @param buf   Буфер-источник.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putAreaAt(int index, DataBuffer buf) {
        return putArrayAt(index, buf.buffer(), buf.arrayOffset() + buf.offset(), buf.length());
    }

    /**
     * Запись рабочего окна буфера-источника в текущую позицию рабочем окне и сдвиг текущей позиции вперед на кол-во
     * записанных байт.
     * <p>
     * Подразумевается, что параметры заданы корректно (т.е. данные помещаются в рабочем окне буфера-приёмника).
     *
     * @param buf Буфер-источник.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putArea(DataBuffer buf) {
        return putArray(buf.buffer(), buf.arrayOffset() + buf.offset(), buf.length());
    }

    /**
     * Запись набора чисел как байт в указанную позицию в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index  Позиция в рабочем окне.
     * @param values Записываемые значения.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putsAt(int index, int... values) {
        if (values != null && values.length > 0) {
            exIfOutOfArea(index, values.length, "putsAt");
            for (int v : values) {
                bb.put(areaOffset + index++, (byte) (v & 0xFF));
            }
        }
        return this;
    }

    /**
     * Запись набора чисел как байт в текущую позицию рабочем окне и сдвиг текущей позиции вперед на кол-во записанных
     * байт.
     *
     * @param values Записываемые значения.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer puts(int... values) {
        return putsAt(pos(), values).shift(values.length);
    }

    /**
     * Запись byte (заполнение одним байтом области) в указанную позицию в рабочем окне. Не влияет на текущую позицию.
     *
     * @param index  Позиция в рабочем окне.
     * @param length Кол-во записываемых байт (размер заполняемой байтом области).
     * @param value  Записываемое значение.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer fillAt(int index, int length, int value) {
        exIfOutOfArea(index, length, "fillAt");
        int off = arrayOffset() + areaOffset + index;
        Arrays.fill(buffer(), off, off + length, (byte) (value & 0xFF));
        return this;
    }

    /**
     * Запись byte (заполнение одним байтом области) в текущую позицию рабочем окне и сдвиг текущей позиции вперед на
     * кол-во записанных байт.
     *
     * @param length Кол-во записываемых байт (размер заполняемой байтом области).
     * @param value  Записываемое значение.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer fill(int length, int value) {
        return fillAt(pos(), length, value).shift(length);
    }

    /**
     * Запись полной строки (преобразование в байт-массив) в указанную позицию в рабочем окне. Не влияет на текущую
     * позицию.
     *
     * @param index   Позиция в рабочем окне.
     * @param str     Записываемая строка.
     * @param charset Кодировка.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putFullStringAt(int index, String str, Charset charset) {
        if (str != null && !str.isEmpty()) {
            byte[] arr = str.getBytes(charset != null ? charset : this.charset);
            putArrayAt(index, arr, 0, arr.length);
        }
        return this;
    }

    /**
     * Запись полной строки (преобразование в байт-массив) в указанную позицию в рабочем окне. Не влияет на текущую
     * позицию.
     *
     * @param index Позиция в рабочем окне.
     * @param str   Записываемая строка.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putFullStringAt(int index, String str) {
        return putFullStringAt(index, str, charset);
    }

    /**
     * Запись полной строки (преобразование в байт-массив) в текущую позицию рабочем окне и сдвиг текущей позиции вперед
     * на кол-во записанных байт.
     *
     * @param str     Записываемая строка.
     * @param charset Кодировка.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putFullString(String str, Charset charset) {
        if (str != null && !str.isEmpty()) {
            byte[] arr = str.getBytes(charset != null ? charset : this.charset);
            putArray(arr, 0, arr.length);
        }
        return this;
    }

    /**
     * Запись полной строки (преобразование в байт-массив) в текущую позицию рабочем окне и сдвиг текущей позиции вперед
     * на кол-во записанных байт.
     *
     * @param str Записываемая строка.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putFullString(String str) {
        return putFullString(str, charset);
    }

    /**
     * Запись ZString (строки с завершающим нулевым символом) (преобразование в байт-массив) в указанную позицию в
     * рабочем окне. Не влияет на текущую позицию. Если длина строки меньше заданной длины - остаток добивается нулями.
     * Завершающий нулевой символ может отсутствовать, если длина строки больше или равна заданной длине.
     *
     * @param index   Позиция в рабочем окне.
     * @param str     Записываемая строка.
     * @param length  Длина - максимальное кол-во записываемых байт.
     * @param charset Кодировка.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putZStringAt(int index, String str, int length, Charset charset) {
        fillAt(index, length, 0);
        if (str != null && !str.isEmpty()) {
            byte[] arr = str.getBytes(charset != null ? charset : this.charset);
            putArrayAt(index, arr, 0, Math.min(length, arr.length));
        }
        return this;
    }

    /**
     * Запись ZString (строки с завершающим нулевым символом) (преобразование в байт-массив) в указанную позицию в
     * рабочем окне. Не влияет на текущую позицию. Если длина строки меньше заданной длины - остаток добивается нулями.
     * Завершающий нулевой символ может отсутствовать, если длина строки больше или равна заданной длине.
     *
     * @param index  Позиция в рабочем окне.
     * @param str    Записываемая строка.
     * @param length Длина - максимальное кол-во записываемых байт.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putZStringAt(int index, String str, int length) {
        return putZStringAt(index, str, length, charset);
    }

    /**
     * Запись ZString (строки с завершающим нулевым символом) (преобразование в байт-массив) в текущую позицию в рабочем
     * окне и сдвиг текущей позиции вперед на заданную длину (<u>ВНИМАНИЕ именно на заданную длину!!!</u>). Если длина
     * строки меньше заданной длины - остаток добивается нулями. Завершающий нулевой символ может отсутствовать, если
     * длина строки больше или равна заданной длине.
     *
     * @param str     Записываемая строка.
     * @param length  Длина - максимальное кол-во записываемых байт.
     * @param charset Кодировка.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putZString(String str, int length, Charset charset) {
        return putZStringAt(pos(), str, length, charset).shift(length);
    }

    /**
     * Запись ZString (строки с завершающим нулевым символом) (преобразование в байт-массив) в текущую позицию в рабочем
     * окне и сдвиг текущей позиции вперед на заданную длину (<u>ВНИМАНИЕ именно на заданную длину!!!</u>). Если длина
     * строки меньше заданной длины - остаток добивается нулями. Завершающий нулевой символ может отсутствовать, если
     * длина строки больше или равна заданной длине.
     *
     * @param str    Записываемая строка.
     * @param length Длина - максимальное кол-во записываемых байт.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putZString(String str, int length) {
        return putZString(str, length, charset);
    }

    /**
     * Запись длины для NString (строки с записанной длиной) (от 1 до 4 байт) в указанную позицию в рабочем окне. Не
     * влияет на текущую позицию. Кол-во записанных байт зависит от значения длины. Каждый байт содержит 7 бит данных и
     * один бит, указывающий на то, что далее следует еще один байт длины. Т.е. длина < (1<<7) - занимает 1 байт, длина
     * менее (1<<14) - два байта, причем у первого байта 7бит=1, и т.д. Минимальное кол-во записанных байт - 1 байт (для
     * записи нулевой длины).
     *
     * @param index  Позиция в рабочем окне.
     * @param length Записываемое значение.
     * @return Кол-во записанных байт.
     */
    private int putNStringLengthAt(int index, int length) {
        int i = 0, v;
        do {
            v = length & 0x7F;
            length >>= 7;
            if (length != 0) v |= 0x80;
            putAt(index + i, v);
            i++;
        } while (i < 4 && length != 0);
        return i;
    }

    /**
     * Запись NString (строки с записанной длиной) в указанную позицию в рабочем окне. Не влияет на текущую позицию.
     * Минимальное кол-во записанных байт - 1 байт (для записи нулевой длины).
     *
     * @param index   Позиция в рабочем окне.
     * @param str     Записываемое значение.
     * @param charset Кодировка.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putNStringAt(int index, String str, Charset charset) {
        if (str != null && !str.isEmpty()) {
            byte[] arr = str.getBytes(charset != null ? charset : this.charset);
            int sz = putNStringLengthAt(index, arr.length);
            putArrayAt(index + sz, arr, 0, arr.length);
        } else {
            putNStringLengthAt(index, 0);
        }
        return this;
    }

    /**
     * Запись NString (строки с записанной длиной) в указанную позицию в рабочем окне. Не влияет на текущую позицию.
     * Минимальное кол-во записанных байт - 1 байт (для записи нулевой длины).
     *
     * @param index Позиция в рабочем окне.
     * @param str   Записываемое значение.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putNStringAt(int index, String str) {
        return putNStringAt(index, str, charset);
    }

    /**
     * Запись NString (строки с записанной длиной) в текущую позицию в рабочем окне и сдвиг текущей позиции вперед на
     * кол-во записанных байт. Минимальное кол-во записанных байт - 1 байт (для записи нулевой длины).
     *
     * @param str     Записываемое значение.
     * @param charset Кодировка.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putNString(String str, Charset charset) {
        int index = pos();
        if (str != null && !str.isEmpty()) {
            byte[] arr = str.getBytes(charset != null ? charset : this.charset);
            int sz = putNStringLengthAt(index, arr.length);
            putArrayAt(index + sz, arr, 0, arr.length).shift(sz + arr.length);
        } else {
            shift(putNStringLengthAt(index, 0));
        }
        return this;
    }

    /**
     * Запись NString (строки с записанной длиной) в текущую позицию в рабочем окне и сдвиг текущей позиции вперед на
     * кол-во записанных байт. Минимальное кол-во записанных байт - 1 байт (для записи нулевой длины).
     *
     * @param str Записываемое значение.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putNString(String str) {
        return putNString(str, charset);
    }

    /**
     * Запись HEX строки (преобразование каждой пары hex в один байт) в указанную позицию в рабочем окне. Не влияет на
     * текущую позицию. Если данных в HEX строке меньше, чем указанная длина - остаток добивается нулями.
     *
     * @param hex    Записываемое значение.
     * @param index  Позиция в рабочем окне.
     * @param length Длина - максимальное кол-во записываемых байт.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putHexAt(String hex, int index, int length) {
        exIfOutOfArea(index, length, "putHexAt");
        StringTools.hexToArray(hex, buffer(), arrayOffset() + areaOffset + index, length);
        return this;
    }

    /**
     * Запись HEX строки (преобразование каждой пары hex в один байт) в текущую позицию в рабочем окне и сдвиг текущей
     * позиции вперед на заданную длину (<u>ВНИМАНИЕ именно на заданную длину!!!</u>). Если данных в HEX строке меньше,
     * чем указанная длина - остаток добивается нулями.
     *
     * @param hex    Записываемое значение.
     * @param length Длина - максимальное кол-во записываемых байт.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putHex(String hex, int length) {
        return putHexAt(hex, pos(), length).shift(length);
    }

    /**
     * Запись BCD HEX строки (преобразование каждого символа hex в один байт 0x30-0x3F) в указанную позицию в рабочем
     * окне. Не влияет на текущую позицию. Если данных в BCD HEX строке меньше, чем указанная длина - остаток добивается
     * нулями.
     *
     * @param bcdhex Записываемое значение.
     * @param index  Позиция в рабочем окне.
     * @param length Длина - максимальное кол-во записываемых байт.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putBCDHexAt(String bcdhex, int index, int length) {
        exIfOutOfArea(index, length, "putBCDHexAt");
        StringTools.bcdHexToArray(bcdhex, buffer(), arrayOffset() + areaOffset + index, length);
        return this;
    }

    /**
     * Запись BCD HEX строки (преобразование каждого символа hex в один байт 0x30-0x3F) в текущую позицию в рабочем окне
     * и сдвиг текущей позиции вперед на заданную длину (<u>ВНИМАНИЕ именно на заданную длину!!!</u>). Если данных в BCD
     * HEX строке меньше, чем указанная длина - остаток добивается нулями.
     *
     * @param bcdhex Записываемое значение.
     * @param length Длина - максимальное кол-во записываемых байт.
     * @return Ссылка на себя для возможности создания цепочек вызовов.
     */
    public DataBuffer putBCDHex(String bcdhex, int length) {
        return putBCDHexAt(bcdhex, pos(), length).shift(length);
    }


    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //  ИСКЛЮЧЕНИЯ
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * Исключение при параметрах операции выходящих за рабочее окно буфера.
     */
    public static class ExOutOfRange extends RuntimeException {
        /** Конструктор. */
        public ExOutOfRange(String fmt, Object... args) {
            super(args.length > 0 ? String.format(fmt, args) : fmt);
        }
    }

    /**
     * Проверка на попадание указанной области в рабочее окно буфера. При выходе за пределы рабочего окна -
     * выбрасывается исключение.
     *
     * @param index  Позиция.
     * @param length Длина.
     * @param name   Наименование операции - для включения в текст исключения.
     */
    private void exIfOutOfArea(int index, int length, String name) {
        if (index < 0 || length < 0 || index + length > areaLength)
            throw new ExOutOfRange("%s(%d,%d) [%d]", name, index, length, areaLength);
    }
}
