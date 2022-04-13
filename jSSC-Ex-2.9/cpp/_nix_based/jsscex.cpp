// DANT 2016.03.11
// ==========================================================================================================
// Апргейд библиотеки.
// [Java]====================================================================================================
// 1. Сделать ВСЕ методы статичными - для ускорения.
// 2. Сделать какие можно методы критичными - для уменьшения накладных расходов.
// 3. Сделать методы чтения\записи указанной части буфера с возвратом кол-ва считанных\записанных байт.
// 4. Сделать методы чтения\записи одного байта (чтобы лишний раз не создавать массивы в джаве).
// 5. ???
// [Java]====================================================================================================
// 1. Из инициализации убрать экстракцию библиотеки - должна лежать в текущем каталоге программы.
// 2. Добавить новые методы.
// 3. ???
// ==========================================================================================================
/* jSSC (Java Simple Serial Connector) - serial port communication library.
 * . Alexey Sokolov (scream3r), 2010-2014.
 *
 * This file is part of jSSC.
 *
 * jSSC is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * jSSC is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with jSSC.  If not, see <http://www.gnu.org/licenses/>.
 *
 * If you use jSSC in public project you can inform me about this by e-mail,
 * of course if you want it.
 *
 * e-mail: scream3r.org@gmail.com
 * web-site: http://scream3r.org | http://code.google.com/p/java-simple-serial-connector/
 */
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <time.h>
#include <errno.h>//-D_TS_ERRNO use for Solaris C++ compiler

#include <sys/select.h>//since 2.5.0

#ifdef __linux__
    #include <linux/serial.h>
#endif
#ifdef __SunOS
    #include <sys/filio.h>//Needed for FIONREAD in Solaris
    #include <string.h>//Needed for select() function
#endif
#ifdef __APPLE__
    #include <serial/ioss.h>//Needed for IOSSIOSPEED in Mac OS X (Non standard baudrate)
#endif

#include <jni.h>
#include "../jsscex_SerialNativeInterface.h"

//#include <iostream> //-lCstd use for Solaris linker


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение версии нативной библиотеки.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jstring JNICALL Java_jsscex_SerialNativeInterface_getNativeLibraryVersion(JNIEnv *env, jobject object) {
    return env->NewStringUTF(jSSCEx_NATIVE_LIB_VERSION);
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Открытие порта. При ошибках - вместо хендла порта - код ошибки (отрицатиельные).
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jlong JNICALL Java_jsscex_SerialNativeInterface_openPort(JNIEnv *env, jobject object, jstring portName, jboolean useTIOCEXCL){
    const char* port = env->GetStringUTFChars(portName, JNI_FALSE);
    jlong hComm = open(port, O_RDWR | O_NOCTTY | O_NDELAY);
    if(hComm != -1){
        //since 2.2.0 -> (check termios structure for separating real serial devices from others)
        termios *settings = new termios();
        if(tcgetattr(hComm, settings) == 0){
        #if defined TIOCEXCL //&& !defined __SunOS
            if(useTIOCEXCL == JNI_TRUE){
                ioctl(hComm, TIOCEXCL);
            }
        #endif
            int flags = fcntl(hComm, F_GETFL, 0);
            flags &= ~O_NDELAY;
            fcntl(hComm, F_SETFL, flags);
        } else {
            close(hComm);//since 2.7.0
            hComm = jsscex_SerialNativeInterface_ERR_INCORRECT_SERIAL_PORT;//-4;
        }
        delete settings;
        //<- since 2.2.0
    } else {//since 0.9 ->
        if(errno == EBUSY){//Port busy
            hComm = jsscex_SerialNativeInterface_ERR_PORT_BUSY;//-1
        } else if(errno == ENOENT){//Port not found
            hComm = jsscex_SerialNativeInterface_ERR_PORT_NOT_FOUND;//-2;
        } else if(errno == EACCES){//Permission denied
            hComm = jsscex_SerialNativeInterface_ERR_PERMISSION_DENIED;//-3;
        } else {
            hComm = jsscex_SerialNativeInterface_ERR_PORT_NOT_FOUND;//-2;
        }//<- since 2.2.0
    }//<- since 0.9
    env->ReleaseStringUTFChars(portName, port);
    return hComm;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение нативного битрейта по java значению. -1 при ошибочных значениях.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
speed_t getBaudRateByNum(jint baudRate) {
    switch(baudRate){
        case 0:
            return B0;
        case 50:
            return B50;
        case 75:
            return B75;
        case 110:
            return B110;
        case 134:
            return B134;
        case 150:
            return B150;
        case 200:
            return B200;
        case 300:
            return B300;
        case 600:
            return B600;
        case 1200:
            return B1200;
        case 1800:
            return B1800;
        case 2400:
            return B2400;
        case 4800:
            return B4800;
        case 9600:
            return B9600;
        case 19200:
            return B19200;
        case 38400:
            return B38400;
    #ifdef B57600
        case 57600:
            return B57600;
    #endif
    #ifdef B115200
        case 115200:
            return B115200;
    #endif
    #ifdef B230400
        case 230400:
            return B230400;
    #endif
    #ifdef B460800
        case 460800:
            return B460800;
    #endif

    #ifdef B500000
        case 500000:
            return B500000;
    #endif
    #ifdef B576000
        case 576000:
            return B576000;
    #endif
    #ifdef B921600
        case 921600:
            return B921600;
    #endif
    #ifdef B1000000
        case 1000000:
            return B1000000;
    #endif

    #ifdef B1152000
        case 1152000:
            return B1152000;
    #endif
    #ifdef B1500000
        case 1500000:
            return B1500000;
    #endif
    #ifdef B2000000
        case 2000000:
            return B2000000;
    #endif
    #ifdef B2500000
        case 2500000:
            return B2500000;
    #endif

    #ifdef B3000000
        case 3000000:
            return B3000000;
    #endif
    #ifdef B3500000
        case 3500000:
            return B3500000;
    #endif
    #ifdef B4000000
        case 4000000:
            return B4000000;
    #endif
        default:
            return -1;
    }
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение нативного значения битов данных по java значению. -1 при ошибочных значениях.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
int getDataBitsByNum(jint byteSize) {
    switch(byteSize){
        case 5:
            return CS5;
        case 6:
            return CS6;
        case 7:
            return CS7;
        case 8:
            return CS8;
        default:
            return -1;
    }
}

//since 2.6.0 ->
const jint PARAMS_FLAG_IGNPAR = 1;
const jint PARAMS_FLAG_PARMRK = 2;
//<- since 2.6.0


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Установка параметов порта.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_setParams
  (JNIEnv *env, jobject object, jlong portHandle, jint baudRate, jint byteSize, jint stopBits, jint parity, jboolean setRTS, jboolean setDTR, jint flags){

    jboolean returnValue = JNI_FALSE;
    speed_t baudRateValue = getBaudRateByNum(baudRate);
    int dataBits = getDataBitsByNum(byteSize);
    
    termios *settings = new termios();
    if (tcgetattr(portHandle, settings) == 0) {
        if (baudRateValue != -1) {
            //Set standart baudrate from "termios.h"
            if (cfsetispeed(settings, baudRateValue) < 0 || cfsetospeed(settings, baudRateValue) < 0) {
                goto methodEnd;
            }
        } else {
        #ifdef __SunOS
            goto methodEnd;//Solaris don't support non standart baudrates
        #elif defined __linux__
            //Try to calculate a divisor for setting non standart baudrate
            serial_struct *serial_info = new serial_struct();
            if (ioctl(portHandle, TIOCGSERIAL, serial_info) < 0) { //Getting serial_info structure
                delete serial_info;
                goto methodEnd;
            } else {
                serial_info->flags |= ASYNC_SPD_CUST;
                serial_info->custom_divisor = (serial_info->baud_base/baudRate); //Calculate divisor
                if (serial_info->custom_divisor == 0){ //If divisor == 0 go to method end to prevent "division by zero" error
                    delete serial_info;
                    goto methodEnd;
                }
                settings->c_cflag |= B38400;
                if (cfsetispeed(settings, B38400) < 0 || cfsetospeed(settings, B38400) < 0) {
                    delete serial_info;
                    goto methodEnd;
                }
                if (ioctl(portHandle, TIOCSSERIAL, serial_info) < 0){//Try to set new settings with non standart baudrate
                    delete serial_info;
                    goto methodEnd;
                }
                delete serial_info;
            }
        #endif
        }
    }

    // Setting data bits
    if (dataBits != -1) {
        settings->c_cflag &= ~CSIZE;
        settings->c_cflag |= dataBits;
    } else {
        goto methodEnd;
    }

    // Setting stop bits
    if (stopBits == 0) { //1 stop bit (for info see ->> MSDN)
        settings->c_cflag &= ~CSTOPB;
    } else if ((stopBits == 1) || (stopBits == 2)) { //1 == 1.5 stop bits; 2 == 2 stop bits (for info see ->> MSDN)
        settings->c_cflag |= CSTOPB;
    } else {
        goto methodEnd;
    }

    settings->c_cflag |= (CREAD | CLOCAL);
    settings->c_cflag &= ~CRTSCTS;
    settings->c_lflag &= ~(ICANON | ECHO | ECHOE | ECHOK | ECHONL | ECHOCTL | ECHOPRT | ECHOKE | ISIG | IEXTEN);

    settings->c_iflag &= ~(IXON | IXOFF | IXANY | INPCK | IGNPAR | PARMRK | ISTRIP | IGNBRK | BRKINT | INLCR | IGNCR| ICRNL);
#ifdef IUCLC
    settings->c_iflag &= ~IUCLC;
#endif
    settings->c_oflag &= ~OPOST;

    //since 2.6.0 ->
    if ((flags & PARAMS_FLAG_IGNPAR) == PARAMS_FLAG_IGNPAR) {
        settings->c_iflag |= IGNPAR;
    }
    if ((flags & PARAMS_FLAG_PARMRK) == PARAMS_FLAG_PARMRK) {
        settings->c_iflag |= PARMRK;
    }
    //<- since 2.6.0

    //since 0.9 ->
    settings->c_cc[VMIN] = 0;
    settings->c_cc[VTIME] = 0;
    //<- since 0.9

    // Parity bits
#ifdef PAREXT
    settings->c_cflag &= ~(PARENB | PARODD | PAREXT);//Clear parity settings
#elif defined CMSPAR
    settings->c_cflag &= ~(PARENB | PARODD | CMSPAR);//Clear parity settings
#else
    settings->c_cflag &= ~(PARENB | PARODD);//Clear parity settings
#endif
    if (parity == 1) {//Parity ODD
        settings->c_cflag |= (PARENB | PARODD);
        settings->c_iflag |= INPCK;
    } else if (parity == 2) {//Parity EVEN
        settings->c_cflag |= PARENB;
        settings->c_iflag |= INPCK;
    } else if (parity == 3) {//Parity MARK
    #ifdef PAREXT
        settings->c_cflag |= (PARENB | PARODD | PAREXT);
        settings->c_iflag |= INPCK;
    #elif defined CMSPAR
        settings->c_cflag |= (PARENB | PARODD | CMSPAR);
        settings->c_iflag |= INPCK;
    #endif
    } else if (parity == 4) {//Parity SPACE
    #ifdef PAREXT
        settings->c_cflag |= (PARENB | PAREXT);
        settings->c_iflag |= INPCK;
    #elif defined CMSPAR
        settings->c_cflag |= (PARENB | CMSPAR);
        settings->c_iflag |= INPCK;
    #endif
    } else if (parity == 0) {
        //Do nothing (Parity NONE)
    } else {
        goto methodEnd;
    }

    if (tcsetattr(portHandle, TCSANOW, settings) == 0) {//Try to set all settings
    #ifdef __APPLE__
        //Try to set non-standard baud rate in Mac OS X
        if (baudRateValue == -1) {
            speed_t speed = (speed_t)baudRate;
            if (ioctl(portHandle, IOSSIOSPEED, &speed) < 0) {//IOSSIOSPEED must be used only after tcsetattr
                goto methodEnd;
            }
        }
    #endif
        int lineStatus;
        if (ioctl(portHandle, TIOCMGET, &lineStatus) >= 0) {
            if (setRTS == JNI_TRUE) {
                lineStatus |= TIOCM_RTS;
            } else {
                lineStatus &= ~TIOCM_RTS;
            }
            if (setDTR == JNI_TRUE) {
                lineStatus |= TIOCM_DTR;
            } else {
                lineStatus &= ~TIOCM_DTR;
            }
            if (ioctl(portHandle, TIOCMSET, &lineStatus) >= 0) {
                returnValue = JNI_TRUE;
            }
        }
    }
    methodEnd: {
        delete settings;
        return returnValue;
    }
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Очистка буферов порта согласно указанным флагам.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
const jint PURGE_RXABORT = 0x0002; //ignored
const jint PURGE_RXCLEAR = 0x0008;
const jint PURGE_TXABORT = 0x0001; //ignored
const jint PURGE_TXCLEAR = 0x0004;

JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_purgePort(JNIEnv *env, jobject object, jlong portHandle, jint flags) {
    int clearValue = -1;
    if ((flags & PURGE_RXCLEAR) && (flags & PURGE_TXCLEAR)){
        clearValue = TCIOFLUSH;
    } else if (flags & PURGE_RXCLEAR) {
        clearValue = TCIFLUSH;
    } else if (flags & PURGE_TXCLEAR) {
        clearValue = TCOFLUSH;
    } else if ((flags & PURGE_RXABORT) || (flags & PURGE_TXABORT)){
        return JNI_TRUE;
    } else {
        return JNI_FALSE;
    }
    return tcflush(portHandle, clearValue) == 0 ? JNI_TRUE : JNI_FALSE;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Закрытие порта.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_closePort(JNIEnv *env, jobject object, jlong portHandle) {
#if defined TIOCNXCL //&& !defined __SunOS
    ioctl(portHandle, TIOCNXCL);//since 2.1.0 Clear exclusive port access on closing
#endif
    return close(portHandle) == 0 ? JNI_TRUE : JNI_FALSE;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение массива строк - имен портов. Не используется в линукс!
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jobjectArray JNICALL Java_jsscex_SerialNativeInterface_getSerialPortNames(JNIEnv *env, jobject object) {
    return NULL; //Don't needed in linux, implemented in java code (Note: null will be returned)
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Установка состояния линии RTS.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_setRTS(JNIEnv *env, jobject object, jlong portHandle, jboolean enabled) {
    int status = 0;
    if (ioctl(portHandle, TIOCMGET, &status) < 0) return JNI_FALSE; // DANT
    status = (enabled == JNI_TRUE) ? status | TIOCM_RTS : status & ~TIOCM_RTS;
    return ioctl(portHandle, TIOCMSET, &status) < 0 ? JNI_FALSE : JNI_TRUE;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Установка состояния линии DTR.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_setDTR(JNIEnv *env, jobject object, jlong portHandle, jboolean enabled) {
    int status = 0;
    if (ioctl(portHandle, TIOCMGET, &status) < 0) return JNI_FALSE; // DANT
    status = (enabled == JNI_TRUE) ? status | TIOCM_DTR : status & ~TIOCM_DTR;
    return ioctl(portHandle, TIOCMSET, &status) < 0 ? JNI_FALSE : JNI_TRUE;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Установка режима контроля потока.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
const jint FLOWCONTROL_NONE = 0;
const jint FLOWCONTROL_RTSCTS_IN = 1;
const jint FLOWCONTROL_RTSCTS_OUT = 2;
const jint FLOWCONTROL_XONXOFF_IN = 4;
const jint FLOWCONTROL_XONXOFF_OUT = 8;

JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_setFlowControlMode(JNIEnv *env, jobject object, jlong portHandle, jint mask) {
    jboolean returnValue = JNI_FALSE;
    termios *settings = new termios();
    if (tcgetattr(portHandle, settings) == 0) {
        settings->c_cflag &= ~CRTSCTS;
        settings->c_iflag &= ~(IXON | IXOFF);
        if (mask != FLOWCONTROL_NONE) {
            if (((mask & FLOWCONTROL_RTSCTS_IN) == FLOWCONTROL_RTSCTS_IN) || ((mask & FLOWCONTROL_RTSCTS_OUT) == FLOWCONTROL_RTSCTS_OUT)) {
                settings->c_cflag |= CRTSCTS;
            }
            if ((mask & FLOWCONTROL_XONXOFF_IN) == FLOWCONTROL_XONXOFF_IN) {
                settings->c_iflag |= IXOFF;
            }
            if ((mask & FLOWCONTROL_XONXOFF_OUT) == FLOWCONTROL_XONXOFF_OUT) {
                settings->c_iflag |= IXON;
            }
        }
        if (tcsetattr(portHandle, TCSANOW, settings) == 0) returnValue = JNI_TRUE;
    }
    delete settings;
    return returnValue;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение режима контроля потока. (-1 - ошибка).
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_getFlowControlMode(JNIEnv *env, jobject object, jlong portHandle) {
    jint returnValue = -1;
    termios *settings = new termios();
    if (tcgetattr(portHandle, settings) == 0) {
        returnValue = 0;
        if (settings->c_cflag & CRTSCTS) {
            returnValue |= (FLOWCONTROL_RTSCTS_IN | FLOWCONTROL_RTSCTS_OUT);
        }
        if (settings->c_iflag & IXOFF) {
            returnValue |= FLOWCONTROL_XONXOFF_IN;
        }
        if (settings->c_iflag & IXON) {
            returnValue |= FLOWCONTROL_XONXOFF_OUT;
        }
    }
    return returnValue;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Посылка сигнала прерывания в течение заданного времени.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_sendBreak(JNIEnv *env, jobject object, jlong portHandle, jint duration) {
    jboolean returnValue = JNI_FALSE;
    if (duration > 0) {
        if (ioctl(portHandle, TIOCSBRK, 0) >= 0) {
            int sec = (duration >= 1000 ? duration/1000 : 0);
            int nanoSec = (sec > 0 ? duration - sec*1000 : duration)*1000000;
            struct timespec *timeStruct = new timespec();
            timeStruct->tv_sec = sec;
            timeStruct->tv_nsec = nanoSec;
            nanosleep(timeStruct, NULL);
            delete(timeStruct);
            if (ioctl(portHandle, TIOCCBRK, 0) >= 0) {
                returnValue = JNI_TRUE;
            }
        }
    }
    return returnValue;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Запрос состояний линий. Результат - независимый от архитектуры битовый набор флагов. (-1 - ошибка)
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_getLinesStatus(JNIEnv *env, jobject object, jlong portHandle){
    jint result = 0;
    int status = 0;
    if (ioctl(portHandle, TIOCMGET, &status) < 0) return -1;
    if (status & TIOCM_CTS) result |= 1; // CTS status
    if (status & TIOCM_DSR) result |= 2; // DSR status
    if (status & TIOCM_RNG) result |= 4; // RING status
    if (status & TIOCM_CAR) result |= 8; // RLSD(DCD) status
    return result;
}











/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Чтение из порта в заданную часть массива! Возвращает кол-во считанных байт!!! (=-1 - ошибка)
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jint JNICALL JavaCritical_jsscex_SerialNativeInterface_readBytes(jlong portHandle, jbyte* buffer, jint index, jint length) {
    fd_set read_fd_set;
    FD_ZERO(&read_fd_set);
    FD_SET(portHandle, &read_fd_set);
    select(portHandle + 1, &read_fd_set, NULL, NULL, NULL);
    int result = read(portHandle, buffer + index, length);
    if (result < 0) result = -1;
    FD_CLR(portHandle, &read_fd_set);
    return result;
}

JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_readBytes(JNIEnv *env, jobject object, jlong portHandle, jbyteArray buffer, jint index, jint length) {
    jboolean isCopy;
    jbyte* buf = (jbyte*) env->GetPrimitiveArrayCritical(buffer, &isCopy);
    jint result = JavaCritical_jsscex_SerialNativeInterface_readBytes(portHandle, buf, index, length);
    env->ReleasePrimitiveArrayCritical(buffer, buf, 0);
    return result;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Чтение из порта одного байта! Возвращает значение считанного байта (=-1 - ошибка, =-2 - байт не считан)!!!
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jint JNICALL JavaCritical_jsscex_SerialNativeInterface_readByte(jlong portHandle) {
    fd_set read_fd_set;
    FD_ZERO(&read_fd_set);
    FD_SET(portHandle, &read_fd_set);
    select(portHandle + 1, &read_fd_set, NULL, NULL, NULL);
    int value = 0;
    int result = read(portHandle, &value, 1);
    if (result < 0) value = -1;
    if (result == 0) value = -2;
    FD_CLR(portHandle, &read_fd_set);
    return value;
}

JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_readByte(JNIEnv *env, jobject object, jlong portHandle) {
    return JavaCritical_jsscex_SerialNativeInterface_readByte(portHandle);
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Запись в порт заданной части массива! Возвращает кол-во записанных байт!!! (=-1 - ошибка)
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jint JNICALL JavaCritical_jsscex_SerialNativeInterface_writeBytes(jlong portHandle, jbyte* buffer, jint index, jint length) {
    int res = write(portHandle, buffer + index, (size_t)length);
    return res < 0 ? -1 : res;
}

JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_writeBytes(JNIEnv *env, jobject object, jlong portHandle, jbyteArray buffer, jint index, jint length) {
    jboolean isCopy;
    jbyte* buf = (jbyte*) env->GetPrimitiveArrayCritical(buffer, &isCopy);
    jint result = JavaCritical_jsscex_SerialNativeInterface_writeBytes(portHandle, buf, index, length);
    env->ReleasePrimitiveArrayCritical(buffer, buf, 0);
    return result;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Запись в порт одного байта! Возвращает кол-во записанных байт!!! (=-1 - ошибка)
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jint JNICALL JavaCritical_jsscex_SerialNativeInterface_writeByte(jlong portHandle, jint value) {
    int res = write(portHandle, &value, (size_t)1);
    return res < 0 ? -1 : res;
}

JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_writeByte(JNIEnv *env, jobject object, jlong portHandle, jint value) {
    return JavaCritical_jsscex_SerialNativeInterface_writeByte(portHandle, value);
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Получение кол-ва доступных для чтения байт во входном буфере порта (= -1 - ошибка).
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jint JNICALL JavaCritical_jsscex_SerialNativeInterface_getInputBufferBytesCount(jlong portHandle) {
    jint result = 0;
    if (ioctl(portHandle, FIONREAD, &result) >= 0) return result;
    return -1;
}

JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_getInputBufferBytesCount(JNIEnv *env, jobject object, jlong portHandle) {
    return JavaCritical_jsscex_SerialNativeInterface_getInputBufferBytesCount(portHandle);
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Получение кол-ва байт в выходном буфере порта (=-1 - ошибка). По идее редко используемая функция.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jint JNICALL JavaCritical_jsscex_SerialNativeInterface_getOutputBufferBytesCount(jlong portHandle) {
    jint result = 0;
    if (ioctl(portHandle, TIOCOUTQ, &result) >= 0) return result;
    return -1;
}

JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_getOutputBufferBytesCount(JNIEnv *env, jobject object, jlong portHandle) {
    return JavaCritical_jsscex_SerialNativeInterface_getOutputBufferBytesCount(portHandle);
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Проверка работоспособности порта. Используется для проверки дисконнекта! (0-работает, -1 - ошибка, дисконнект)
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_checkPort(JNIEnv *env, jobject object, jlong portHandle, jstring portName) {
    // Для проверки соединения используется проверка кол-ва доступных для чтения байт во входном буфере.
    // В Линукс используется хендл открытого порта, имя порта не используется!
    return JavaCritical_jsscex_SerialNativeInterface_getInputBufferBytesCount(portHandle) >= 0 ? 0 : -1;
}


