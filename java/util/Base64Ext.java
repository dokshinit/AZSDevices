/*
 * Copyright (c) 2015, Aleksey Nikolaevich Dokshin. All right reserved.
 * Contacts: dant.it@gmail.com, dokshin@list.ru.
 */
package util;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/**
 * Расширенный Base64 энкодер\декодер. Был взят за основу стандартный и добавлены методы *X для
 * кодирования\декодирования произвольной части байт-массива (наследование не использовалось т.к.
 * нужные методы в базовом классе были скрыты).
 *
 * @author Докшин Алексей Николаевич <dant.it@gmail.com>
 */
public class Base64Ext {

    private Base64Ext() {
    }

    public static Encoder getEncoder() {
        return Encoder.RFC4648;
    }

    public static Decoder getDecoder() {
        return Decoder.RFC4648;
    }

    public static class Encoder {

        private final byte[] newline;
        private final int linemax;
        private final boolean doPadding;

        private Encoder(byte[] newline, int linemax, boolean doPadding) {
            this.newline = newline;
            this.linemax = linemax;
            this.doPadding = doPadding;
        }

        /**
         * This array is a lookup table that translates 6-bit positive integer index values into
         * their "Base64 Alphabet" equivalents as specified in "Table 1: The Base64 Alphabet" of RFC
         * 2045 (and RFC 4648).
         */
        private static final char[] toBase64 = {
            'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
            'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
            'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
            'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '/'
        };

        static final Encoder RFC4648 = new Encoder(null, -1, true);

        private int outLength(int srclen) {
            int len;
            if (doPadding) {
                len = 4 * ((srclen + 2) / 3);
            } else {
                int n = srclen % 3;
                len = 4 * (srclen / 3) + (n == 0 ? 0 : n + 1);
            }
            if (linemax > 0) // line separators
            {
                len += (len - 1) / linemax * newline.length;
            }
            return len;
        }

        public byte[] encode(byte[] src) {
            int len = outLength(src.length);          // dst array size
            byte[] dst = new byte[len];
            int ret = encode0(src, 0, src.length, dst, 0);
            if (ret != dst.length) {
                return Arrays.copyOf(dst, ret);
            }
            return dst;
        }

        public String encodeToString(byte[] src) {
            byte[] encoded = encode(src);
            return new String(encoded, 0, encoded.length);
        }

        public ByteBuffer encode(ByteBuffer buffer) {
            int len = outLength(buffer.remaining());
            byte[] dst = new byte[len];
            int ret = 0;
            if (buffer.hasArray()) {
                ret = encode0(buffer.array(),
                        buffer.arrayOffset() + buffer.position(),
                        buffer.arrayOffset() + buffer.limit(),
                        dst, 0);
                buffer.position(buffer.limit());
            } else {
                byte[] src = new byte[buffer.remaining()];
                buffer.get(src);
                ret = encode0(src, 0, src.length, dst, 0);
            }
            if (ret != dst.length) {
                dst = Arrays.copyOf(dst, ret);
            }
            return ByteBuffer.wrap(dst);
        }

        public int encodeX(byte[] src, byte[] dst) {
            return encodeX(src, 0, src.length, dst, 0);
        }

        public int encodeX(ByteBuffer src, ByteBuffer dst) {
            return encodeX(src.array(), src.position(), src.limit(), dst.array(), dst.position());
        }

        public int encodeX(byte[] src, int off, int end, byte[] dst, int dstoff) {
            if (off < 0 || off >= src.length) {
                throw new IllegalArgumentException("Input array offset is wrong!");
            }
            if (end < off || end >= src.length) {
                throw new IllegalArgumentException("Input array end is wrong!");
            }
            if (dstoff < 0 || dstoff >= dst.length) {
                throw new IllegalArgumentException("Output array offset is wrong!");
            }
            int len = outLength(end - off);
            if (dst.length - dstoff < len) {
                throw new IllegalArgumentException("Output array remaining is too small!");
            }
            return encode0(src, off, end, dst, dstoff);
        }

        private int encode0(byte[] src, int off, int end, byte[] dst, int dstoff) {
            char[] base64 = toBase64;
            int sp = off;
            int slen = (end - off) / 3 * 3;
            int sl = off + slen;
            if (linemax > 0 && slen > linemax / 4 * 3) {
                slen = linemax / 4 * 3;
            }
            int dp = 0;
            while (sp < sl) {
                int sl0 = Math.min(sp + slen, sl);
                for (int sp0 = sp, dp0 = dp; sp0 < sl0;) {
                    int bits = (src[sp0++] & 0xff) << 16
                            | (src[sp0++] & 0xff) << 8
                            | (src[sp0++] & 0xff);
                    dst[dstoff + dp0++] = (byte) base64[(bits >>> 18) & 0x3f];
                    dst[dstoff + dp0++] = (byte) base64[(bits >>> 12) & 0x3f];
                    dst[dstoff + dp0++] = (byte) base64[(bits >>> 6) & 0x3f];
                    dst[dstoff + dp0++] = (byte) base64[bits & 0x3f];
                }
                int dlen = (sl0 - sp) / 3 * 4;
                dp += dlen;
                sp = sl0;
                if (dlen == linemax && sp < end) {
                    for (byte b : newline) {
                        dst[dstoff + dp++] = b;
                    }
                }
            }
            if (sp < end) {               // 1 or 2 leftover bytes
                int b0 = src[sp++] & 0xff;
                dst[dstoff + dp++] = (byte) base64[b0 >> 2];
                if (sp == end) {
                    dst[dstoff + dp++] = (byte) base64[(b0 << 4) & 0x3f];
                    if (doPadding) {
                        dst[dstoff + dp++] = '=';
                        dst[dstoff + dp++] = '=';
                    }
                } else {
                    int b1 = src[sp++] & 0xff;
                    dst[dstoff + dp++] = (byte) base64[(b0 << 4) & 0x3f | (b1 >> 4)];
                    dst[dstoff + dp++] = (byte) base64[(b1 << 2) & 0x3f];
                    if (doPadding) {
                        dst[dstoff + dp++] = '=';
                    }
                }
            }
            return dp;
        }
    }

    public static class Decoder {

        private Decoder() {
        }

        /**
         * Lookup table for decoding unicode characters drawn from the "Base64 Alphabet" (as
         * specified in Table 1 of RFC 2045) into their 6-bit positive integer equivalents.
         * Characters that are not in the Base64 alphabet but fall within the bounds of the array
         * are encoded to -1.
         *
         */
        private static final int[] fromBase64 = new int[256];

        static {
            Arrays.fill(fromBase64, -1);
            for (int i = 0; i < Encoder.toBase64.length; i++) {
                fromBase64[Encoder.toBase64[i]] = i;
            }
            fromBase64['='] = -2;
        }

        static final Decoder RFC4648 = new Decoder();

        public byte[] decode(byte[] src, int offset, int length) {
            byte[] dst = new byte[outLength(src, 0, src.length)];
            int ret = decode0(src, 0, src.length, dst, 0);
            if (ret != dst.length) {
                dst = Arrays.copyOf(dst, ret);
            }
            return dst;
        }

        public byte[] decode(byte[] src) {
            return decode(src, 0, src.length);
        }

        public byte[] decode(String src) {
            return decode(src.getBytes(StandardCharsets.ISO_8859_1));
        }

        public ByteBuffer decode(ByteBuffer buffer) {
            int pos0 = buffer.position();
            try {
                byte[] src;
                int sp, sl;
                if (buffer.hasArray()) {
                    src = buffer.array();
                    sp = buffer.arrayOffset() + buffer.position();
                    sl = buffer.arrayOffset() + buffer.limit();
                    buffer.position(buffer.limit());
                } else {
                    src = new byte[buffer.remaining()];
                    buffer.get(src);
                    sp = 0;
                    sl = src.length;
                }
                byte[] dst = new byte[outLength(src, sp, sl)];
                return ByteBuffer.wrap(dst, 0, decode0(src, sp, sl, dst, 0));
            } catch (IllegalArgumentException iae) {
                buffer.position(pos0);
                throw iae;
            }
        }

        private int outLength(byte[] src, int sp, int sl) {
            int paddings = 0;
            int len = sl - sp;
            if (len == 0) {
                return 0;
            }
            if (len < 2) {
                throw new IllegalArgumentException(
                        "Input byte[] should at least have 2 bytes for base64 bytes");
            }
            if (src[sl - 1] == '=') {
                paddings++;
                if (src[sl - 2] == '=') {
                    paddings++;
                }
            }
            if (paddings == 0 && (len & 0x3) != 0) {
                paddings = 4 - (len & 0x3);
            }
            return 3 * ((len + 3) / 4) - paddings;
        }

        public int decodeX(byte[] src, byte[] dst) {
            return decodeX(src, 0, src.length, dst, 0);
        }

        public int decodeX(ByteBuffer src, ByteBuffer dst) {
            return decodeX(src.array(), src.position(), src.limit(), dst.array(), dst.position());
        }

        public int decodeX(byte[] src, int off, int end, byte[] dst, int dstoff) {
            if (off < 0 || off >= src.length) {
                throw new IllegalArgumentException("Input array offset is wrong!");
            }
            if (end < off || end >= src.length) {
                throw new IllegalArgumentException("Input array end is wrong!");
            }
            if (dstoff < 0 || dstoff >= dst.length) {
                throw new IllegalArgumentException("Output array offset is wrong!");
            }
            int len = outLength(src, off, end);
            if (dst.length - dstoff < len) {
                throw new IllegalArgumentException("Output array remaining is too small!");
            }
            return decode0(src, off, end, dst, dstoff);
        }

        private int decode0(byte[] src, int sp, int sl, byte[] dst, int dstoff) {
            int[] base64 = fromBase64;
            int dp = 0;
            int bits = 0;
            int shiftto = 18;       // pos of first byte of 4-byte atom
            while (sp < sl) {
                int b = src[sp++] & 0xff;
                if ((b = base64[b]) < 0) {
                    if (b == -2) {         // padding byte '='
                        // =     shiftto==18 unnecessary padding
                        // x=    shiftto==12 a dangling single x
                        // x     to be handled together with non-padding case
                        // xx=   shiftto==6&&sp==sl missing last =
                        // xx=y  shiftto==6 last is not =
                        if (shiftto == 6 && (sp == sl || src[sp++] != '=')
                                || shiftto == 18) {
                            throw new IllegalArgumentException(
                                    "Input byte array has wrong 4-byte ending unit");
                        }
                        break;
                    }
                    throw new IllegalArgumentException(
                            "Illegal base64 character "
                            + Integer.toString(src[sp - 1], 16));
                }
                bits |= (b << shiftto);
                shiftto -= 6;
                if (shiftto < 0) {
                    dst[dstoff + dp++] = (byte) (bits >> 16);
                    dst[dstoff + dp++] = (byte) (bits >> 8);
                    dst[dstoff + dp++] = (byte) (bits);
                    shiftto = 18;
                    bits = 0;
                }
            }
            // reached end of byte array or hit padding '=' characters.
            if (shiftto == 6) {
                dst[dstoff + dp++] = (byte) (bits >> 16);
            } else if (shiftto == 0) {
                dst[dstoff + dp++] = (byte) (bits >> 16);
                dst[dstoff + dp++] = (byte) (bits >> 8);
            } else if (shiftto == 12) {
                // dangling single "x", incorrectly encoded.
                throw new IllegalArgumentException(
                        "Last unit does not have enough valid bits");
            }
            // anything left is invalid, if is not MIME.
            // if MIME, ignore all non-base64 character
            if (sp < sl) {
                throw new IllegalArgumentException(
                        "Input byte array has incorrect ending byte at " + sp);
            }
            return dp;
        }
    }
}
