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
#include <jni.h>
#include <stdlib.h>
#include <windows.h>
#include "../jsscex_SerialNativeInterface.h"

//#include <iostream>


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение версии нативной библиотеки.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jstring JNICALL Java_jsscex_SerialNativeInterface_getNativeLibraryVersion(JNIEnv *env, jobject object) {
    return env->NewStringUTF(jSSCEx_NATIVE_LIB_VERSION);
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Открытие порта. При ошибках - вместо хендла порта - код ошибки (отрицатиельные). useTIOCEXCL не используется (только для Linix)
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jlong JNICALL Java_jsscex_SerialNativeInterface_openPort(JNIEnv *env, jobject object, jstring portName, jboolean useTIOCEXCL){
    char prefix[] = "\\\\.\\";
    const char* port = env->GetStringUTFChars(portName, JNI_FALSE);

    //since 2.1.0 -> string concat fix
    char portFullName[strlen(prefix) + strlen(port) + 1];
    strcpy(portFullName, prefix);
    strcat(portFullName, port);
    //<- since 2.1.0

    HANDLE hComm = CreateFile(portFullName,
                              GENERIC_READ | GENERIC_WRITE,
                              0,
                              0,
                              OPEN_EXISTING,
                              FILE_FLAG_OVERLAPPED,
                              0);
    env->ReleaseStringUTFChars(portName, port);

    //since 2.3.0 ->
    if (hComm != INVALID_HANDLE_VALUE) {
        DCB *dcb = new DCB();
        if (!GetCommState(hComm, dcb)) {
            CloseHandle(hComm);//since 2.7.0
            hComm = (HANDLE)jsscex_SerialNativeInterface_ERR_INCORRECT_SERIAL_PORT;//(-4)Incorrect serial port
        }
        delete dcb;
    } else {
        DWORD errorValue = GetLastError();
        if (errorValue == ERROR_ACCESS_DENIED) {
            hComm = (HANDLE)jsscex_SerialNativeInterface_ERR_PORT_BUSY;//(-1)Port busy
        } else if (errorValue == ERROR_FILE_NOT_FOUND) {
            hComm = (HANDLE)jsscex_SerialNativeInterface_ERR_PORT_NOT_FOUND;//(-2)Port not found
        } else {
            hComm = (HANDLE)jsscex_SerialNativeInterface_ERR_PORT_NOT_OPENED; //(-5) Other error (not opened)
        }
    }
    //<- since 2.3.0
    return (jlong)hComm;//since 2.4.0 changed to jlong
};


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Установка параметов порта.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_setParams
  (JNIEnv *env, jobject object, jlong portHandle, jint baudRate, jint byteSize, jint stopBits, jint parity, jboolean setRTS, jboolean setDTR, jint flags){
    HANDLE hComm = (HANDLE)portHandle;
    DCB *dcb = new DCB();
    jboolean returnValue = JNI_FALSE;
    if (GetCommState(hComm, dcb)) {
        dcb->BaudRate = baudRate;
        dcb->ByteSize = byteSize;
        dcb->StopBits = stopBits;
        dcb->Parity = parity;
        //since 0.8 ->
        dcb->fRtsControl = setRTS == JNI_TRUE ? RTS_CONTROL_ENABLE : RTS_CONTROL_DISABLE;
        dcb->fDtrControl = setDTR == JNI_TRUE ? DTR_CONTROL_ENABLE : DTR_CONTROL_DISABLE;
        dcb->fOutxCtsFlow = FALSE;
        dcb->fOutxDsrFlow = FALSE;
        dcb->fDsrSensitivity = FALSE;
        dcb->fTXContinueOnXoff = TRUE;
        dcb->fOutX = FALSE;
        dcb->fInX = FALSE;
        dcb->fErrorChar = FALSE;
        dcb->fNull = FALSE;
        dcb->fAbortOnError = TRUE; // TODO: Возможно из-за этого и не видит дисконнекта?
        dcb->XonLim = 2048;
        dcb->XoffLim = 512;
        dcb->XonChar = (char)17; //DC1
        dcb->XoffChar = (char)19; //DC3
        //<- since 0.8

        if (SetCommState(hComm, dcb)) {
            //since 2.1.0 -> previously setted timeouts by another application should be cleared
            COMMTIMEOUTS *lpCommTimeouts = new COMMTIMEOUTS();
            lpCommTimeouts->ReadIntervalTimeout = 0;
            lpCommTimeouts->ReadTotalTimeoutConstant = 0;
            lpCommTimeouts->ReadTotalTimeoutMultiplier = 0;
            lpCommTimeouts->WriteTotalTimeoutConstant = 0;
            lpCommTimeouts->WriteTotalTimeoutMultiplier = 0;
            if (SetCommTimeouts(hComm, lpCommTimeouts)) returnValue = JNI_TRUE;
            delete lpCommTimeouts;
            //<- since 2.1.0
        }
    }
    delete dcb;
    return returnValue;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Очистка буферов порта согласно указанным флагам.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_purgePort(JNIEnv *env, jobject object, jlong portHandle, jint flags){
    HANDLE hComm = (HANDLE)portHandle;
    DWORD dwFlags = (DWORD)flags;
    return (PurgeComm(hComm, dwFlags) ? JNI_TRUE : JNI_FALSE);
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Закрытие порта.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_closePort(JNIEnv *env, jobject object, jlong portHandle){
    HANDLE hComm = (HANDLE)portHandle;
    return (CloseHandle(hComm) ? JNI_TRUE : JNI_FALSE);
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение массива строк - имен портов.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jobjectArray JNICALL Java_jsscex_SerialNativeInterface_getSerialPortNames(JNIEnv *env, jobject object) {
    HKEY phkResult;
    LPCSTR lpSubKey = "HARDWARE\\DEVICEMAP\\SERIALCOMM\\";
    jobjectArray returnArray = NULL;
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, lpSubKey, 0, KEY_READ, &phkResult) == ERROR_SUCCESS) {
        boolean hasMoreElements = true;
        DWORD keysCount = 0;
        char valueName[256];
        DWORD valueNameSize;
        DWORD enumResult;
        while (hasMoreElements) {
            valueNameSize = 256;
            enumResult = RegEnumValueA(phkResult, keysCount, valueName, &valueNameSize, NULL, NULL, NULL, NULL);

            if (enumResult == ERROR_SUCCESS) {
                keysCount++;
            } else if (enumResult == ERROR_NO_MORE_ITEMS) {
                hasMoreElements = false;
            } else {
                hasMoreElements = false;
            }
        }
        if (keysCount > 0) {
            jclass stringClass = env->FindClass("java/lang/String");
            returnArray = env->NewObjectArray((jsize)keysCount, stringClass, NULL);
            char lpValueName[256];
            DWORD lpcchValueName;
            byte lpData[256];
            DWORD lpcbData;
            DWORD result;
            for (DWORD i = 0; i < keysCount; i++) {
                lpcchValueName = 256;
                lpcbData = 256;
                result = RegEnumValueA(phkResult, i, lpValueName, &lpcchValueName, NULL, NULL, lpData, &lpcbData);
                if (result == ERROR_SUCCESS) {
                    env->SetObjectArrayElement(returnArray, i, env->NewStringUTF((char*)lpData));
                }
            }
        }
        CloseHandle(phkResult);
    }
    return returnArray;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Установка состояния линии RTS.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_setRTS(JNIEnv *env, jobject object, jlong portHandle, jboolean enabled) {
    HANDLE hComm = (HANDLE)portHandle;
    if (enabled == JNI_TRUE) {
        return (EscapeCommFunction(hComm, SETRTS) ? JNI_TRUE : JNI_FALSE);
    } else {
        return (EscapeCommFunction(hComm, CLRRTS) ? JNI_TRUE : JNI_FALSE);
    }
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Установка состояния линии DTR.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_setDTR(JNIEnv *env, jobject object, jlong portHandle, jboolean enabled){
    HANDLE hComm = (HANDLE)portHandle;
    if (enabled == JNI_TRUE) {
        return (EscapeCommFunction(hComm, SETDTR) ? JNI_TRUE : JNI_FALSE);
    } else {
        return (EscapeCommFunction(hComm, CLRDTR) ? JNI_TRUE : JNI_FALSE);
    }
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Установка режима контроля потока.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
const jint FLOWCONTROL_NONE = 0;
const jint FLOWCONTROL_RTSCTS_IN = 1;
const jint FLOWCONTROL_RTSCTS_OUT = 2;
const jint FLOWCONTROL_XONXOFF_IN = 4;
const jint FLOWCONTROL_XONXOFF_OUT = 8;

JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_setFlowControlMode(JNIEnv *env, jobject object, jlong portHandle, jint mask){
    HANDLE hComm = (HANDLE)portHandle;
    jboolean returnValue = JNI_FALSE;
    DCB *dcb = new DCB();
    if (GetCommState(hComm, dcb)) {
        dcb->fRtsControl = RTS_CONTROL_ENABLE;
        dcb->fOutxCtsFlow = FALSE;
        dcb->fOutX = FALSE;
        dcb->fInX = FALSE;
        if (mask != FLOWCONTROL_NONE) {
            if ((mask & FLOWCONTROL_RTSCTS_IN) == FLOWCONTROL_RTSCTS_IN) dcb->fRtsControl = RTS_CONTROL_HANDSHAKE;
            if ((mask & FLOWCONTROL_RTSCTS_OUT) == FLOWCONTROL_RTSCTS_OUT) dcb->fOutxCtsFlow = TRUE;
            if ((mask & FLOWCONTROL_XONXOFF_IN) == FLOWCONTROL_XONXOFF_IN) dcb->fInX = TRUE;
            if ((mask & FLOWCONTROL_XONXOFF_OUT) == FLOWCONTROL_XONXOFF_OUT) dcb->fOutX = TRUE;
        }
        if (SetCommState(hComm, dcb)) returnValue = JNI_TRUE;
    }
    delete dcb;
    return returnValue;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Получение режима контроля потока. (-1 - ошибка).
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_getFlowControlMode
  (JNIEnv *env, jobject object, jlong portHandle){
    HANDLE hComm = (HANDLE)portHandle;
    jint returnValue = -1;
    DCB *dcb = new DCB();
    if (GetCommState(hComm, dcb)) {
        returnValue = 0;
        if (dcb->fRtsControl == RTS_CONTROL_HANDSHAKE) returnValue |= FLOWCONTROL_RTSCTS_IN;
        if (dcb->fOutxCtsFlow == TRUE) returnValue |= FLOWCONTROL_RTSCTS_OUT;
        if (dcb->fInX == TRUE) returnValue |= FLOWCONTROL_XONXOFF_IN;
        if (dcb->fOutX == TRUE) returnValue |= FLOWCONTROL_XONXOFF_OUT;
    }
    delete dcb;
    return returnValue;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Посылка сигнала прерывания в течение заданного времени.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_sendBreak(JNIEnv *env, jobject object, jlong portHandle, jint duration) {
    HANDLE hComm = (HANDLE)portHandle;
    jboolean returnValue = JNI_FALSE;
    if (duration > 0){
        if (SetCommBreak(hComm) > 0) {
            Sleep(duration);
            if (ClearCommBreak(hComm) > 0) returnValue = JNI_TRUE;
        }
    }
    return returnValue;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Запрос состояний линий. Результат - независимый от архитектуры битовый набор флагов. (-1 - ошибка)
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_getLinesStatus(JNIEnv *env, jobject object, jlong portHandle){
    HANDLE hComm = (HANDLE)portHandle;
    DWORD lpModemStat;
    if (!GetCommModemStatus(hComm, &lpModemStat)) return -1;
    jint result = 0;
    if ((MS_CTS_ON & lpModemStat) == MS_CTS_ON)   result |= 1;
    if ((MS_DSR_ON & lpModemStat) == MS_DSR_ON)   result |= 2;
    if ((MS_RING_ON & lpModemStat) == MS_RING_ON) result |= 4;
    if ((MS_RLSD_ON & lpModemStat) == MS_RLSD_ON) result |= 8;
    return result;
}









/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Чтение из порта в заданную часть массива! Возвращает кол-во считанных байт!!! (=-1 - ошибка)
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jint JNICALL JavaCritical_jsscex_SerialNativeInterface_readBytes(jlong portHandle, jbyte* buffer, jint index, jint length) {
    HANDLE hComm = (HANDLE)portHandle;
    DWORD result = (DWORD)-1;
    OVERLAPPED *overlapped = new OVERLAPPED();
    overlapped->hEvent = CreateEventA(NULL, true, false, NULL);
    if (!ReadFile(hComm, buffer + index, (DWORD)length, &result, overlapped)) {
        result = (DWORD)-1;
        // Проверка на асинхронное чтение.
        if (GetLastError() == ERROR_IO_PENDING) {
            if (WaitForSingleObject(overlapped->hEvent, INFINITE) == WAIT_OBJECT_0) {
                if (!GetOverlappedResult(hComm, overlapped, &result, false)) result = (DWORD)-1; // Если успех, то кол-во считанных байт берем из overlap.
            }
    }
    }
    CloseHandle(overlapped->hEvent);
    delete overlapped;
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
    HANDLE hComm = (HANDLE)portHandle;
    jint value = 0;
    DWORD result = (DWORD)-1;
    OVERLAPPED *overlapped = new OVERLAPPED();
    overlapped->hEvent = CreateEventA(NULL, true, false, NULL);
    if (ReadFile(hComm, &value, (DWORD)1, &result, overlapped)) {
        result = (result == 0) ? ((DWORD)-2) : (value & 0xFF);
    } else {
        result = (DWORD)-1;
    // Проверка на асинхронное чтение.
        if (GetLastError() == ERROR_IO_PENDING) {
            if (WaitForSingleObject(overlapped->hEvent, INFINITE) == WAIT_OBJECT_0) {
                if (GetOverlappedResult(hComm, overlapped, &result, false)) { // Если успех, то кол-во считанных байт берем из overlap.
            result = (result == 0) ? ((DWORD)-2) : (value & 0xFF);
        } else {
            result = (DWORD)-1;
        }
            }
    }
    }
    CloseHandle(overlapped->hEvent);
    delete overlapped;
    return result;
}


JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_readByte(JNIEnv *env, jobject object, jlong portHandle) {
    return JavaCritical_jsscex_SerialNativeInterface_readByte(portHandle);
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Запись в порт заданной части массива! Возвращает кол-во записанных байт!!! (=-1 - ошибка)
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jint JNICALL JavaCritical_jsscex_SerialNativeInterface_writeBytes(jlong portHandle, jbyte* buffer, jint index, jint length) {
    HANDLE hComm = (HANDLE)portHandle;
    DWORD result = (DWORD)-1;
    OVERLAPPED *overlapped = new OVERLAPPED();
    overlapped->hEvent = CreateEventA(NULL, true, false, NULL);
    if (!WriteFile(hComm, buffer + index, (DWORD)length, &result, overlapped)) {
        result = (DWORD)-1;
        if (GetLastError() == ERROR_IO_PENDING) {
            if (WaitForSingleObject(overlapped->hEvent, INFINITE) == WAIT_OBJECT_0) {
                if (!GetOverlappedResult(hComm, overlapped, &result, false)) result = -1;
            }
        }
    }
    CloseHandle(overlapped->hEvent);
    delete overlapped;
    return result;
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
    HANDLE hComm = (HANDLE)portHandle;
    DWORD result = (DWORD)-1;
    OVERLAPPED *overlapped = new OVERLAPPED();
    overlapped->hEvent = CreateEventA(NULL, true, false, NULL);
    if (!WriteFile(hComm, &value, (DWORD)1, &result, overlapped)) {
        result = (DWORD)-1;
        if (GetLastError() == ERROR_IO_PENDING) {
            if (WaitForSingleObject(overlapped->hEvent, INFINITE) == WAIT_OBJECT_0) {
                if (!GetOverlappedResult(hComm, overlapped, &result, false)) result = -1;
            }
        }
    }
    CloseHandle(overlapped->hEvent);
    delete overlapped;
    return result;
}

JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_writeByte(JNIEnv *env, jobject object, jlong portHandle, jint value) {
    return JavaCritical_jsscex_SerialNativeInterface_writeByte(portHandle, value);
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Получение кол-ва доступных для чтения байт во входном буфере порта (= -1 - ошибка).
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jint JNICALL JavaCritical_jsscex_SerialNativeInterface_getInputBufferBytesCount(jlong portHandle) {
    HANDLE hComm = (HANDLE)portHandle;
    jint result = -1;
    DWORD lpErrors;
    COMSTAT *comstat = new COMSTAT();
    if (ClearCommError(hComm, &lpErrors, comstat)) {
//        if (lpErrors & CE_BREAK) {
//            result = -1; // TODO: Проверить какие ошибки выкидываются при дисконнекте!
//            // Может быть для детекции состояния дисконнекта придется использовать проверку состояние порта?
//            // TODO: Возможно стоит сделать отдельную ф-цию проверки дисконнекта. Для каджой ОС - своя реализация.
//        } else {
            result = (jint)comstat->cbInQue;
//        }
    } else {
        result = -1;
    }
    delete comstat;
    return result;
}

JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_getInputBufferBytesCount(JNIEnv *env, jobject object, jlong portHandle) {
    return JavaCritical_jsscex_SerialNativeInterface_getInputBufferBytesCount(portHandle);
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Получение кол-ва байт в выходном буфере порта (=-1 - ошибка). По идее редко используемая функция.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jint JNICALL JavaCritical_jsscex_SerialNativeInterface_getOutputBufferBytesCount(jlong portHandle) {
    HANDLE hComm = (HANDLE)portHandle;
    jint result = -1;
    DWORD lpErrors = 0;
    COMSTAT *comstat = new COMSTAT();
    if (ClearCommError(hComm, &lpErrors, comstat)) {
        result = (jint)comstat->cbOutQue;
    } else {
        result = -1;
    }
    delete comstat;
    return result;
}

JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_getOutputBufferBytesCount(JNIEnv *env, jobject object, jlong portHandle) {
    return JavaCritical_jsscex_SerialNativeInterface_getOutputBufferBytesCount(portHandle);
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DANT 2016.03.11
// Проверка работоспособности порта. Используется для проверки дисконнекта! (0-работает, иначе код ошибки, дисконнект)
//===================================================================================================================================================
// * Не выявил методов, которыми можно было бы детектировать отключение устройства!!!
// * Все методы обращения к порту (за исключением read\write) возвращают успех операции (!) после отключения устройства!
// * Остаётся лишь пинговать устройство на уровне приложения... при этом как-то синхронизацию производить...
//
// * Реализовал через попытку открыть порт заново и произвести анализ ошибок - работает нормально:
//   - При подключенном устройстве - ERROR_ACCESS_DENIED - возвращается ноль.
//   - При отключении - ERROR_FILE_NOT_FOUND (но наверное могут быть и другие) - возвращается код ошибки.
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_checkPort(JNIEnv *env, jobject object, jlong portHandle, jstring portName) {
    // Для проверки соединения используется проверка кол-ва доступных для чтения байт во входном буфере.
    //return JavaCritical_jsscex_SerialNativeInterface_getInputBufferBytesCount(portHandle) >= 0 ? 0 : -1;
    char prefix[] = "\\\\.\\";
    const char* port = env->GetStringUTFChars(portName, JNI_FALSE);
    char portFullName[strlen(prefix) + strlen(port) + 1];
    strcpy(portFullName, prefix);
    strcat(portFullName, port);
    env->ReleaseStringUTFChars(portName, port);

    HANDLE hComm = CreateFile(portFullName,
                              GENERIC_READ | GENERIC_WRITE,
                              0,
                              0,
                              OPEN_EXISTING,
                              FILE_FLAG_OVERLAPPED,
                              0);
    if (hComm != INVALID_HANDLE_VALUE) {
        // Порт открывается без проблем - это проблема, значит предыдущий дескриптор битый ???
        jint result = jsscex_SerialNativeInterface_ERR_PORT_OPENED;
        DCB *dcb = new DCB();
        if (!GetCommState(hComm, dcb))
            result = jsscex_SerialNativeInterface_ERR_INCORRECT_SERIAL_PORT; // (-4) Это не последовательный порт!
        CloseHandle(hComm); // Закрываем файл в любом случае!
        delete dcb;
        return result;
    } else {
        DWORD errorValue = GetLastError();
        switch (errorValue) {
            case ERROR_ACCESS_DENIED: // Порт уже занят. Так и должно быть, если он до сих пор открыт, всё ОК!
                return 0;
            case ERROR_FILE_NOT_FOUND: // (-2) Порт не найден.
                return jsscex_SerialNativeInterface_ERR_PORT_NOT_FOUND;
            default:
                return jsscex_SerialNativeInterface_ERR_PORT_NOT_OPENED; // Какая-то иная ошибка.
        }
    }
}

