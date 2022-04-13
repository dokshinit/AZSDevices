#include <jni.h>

#ifndef _Included_jsscex_SerialNativeInterface
#define _Included_jsscex_SerialNativeInterface
#ifdef __cplusplus
extern "C" {
#endif

#undef jSSCEx_NATIVE_LIB_VERSION
#define jSSCEx_NATIVE_LIB_VERSION "2.9"

#undef jsscex_SerialNativeInterface_OS_LINUX
#define jsscex_SerialNativeInterface_OS_LINUX 0L
#undef jsscex_SerialNativeInterface_OS_WINDOWS
#define jsscex_SerialNativeInterface_OS_WINDOWS 1L
#undef jsscex_SerialNativeInterface_OS_SOLARIS
#define jsscex_SerialNativeInterface_OS_SOLARIS 2L
#undef jsscex_SerialNativeInterface_OS_MAC_OS_X
#define jsscex_SerialNativeInterface_OS_MAC_OS_X 3L

#undef jsscex_SerialNativeInterface_ERR_PORT_BUSY
#define jsscex_SerialNativeInterface_ERR_PORT_BUSY -1LL
#undef jsscex_SerialNativeInterface_ERR_PORT_NOT_FOUND
#define jsscex_SerialNativeInterface_ERR_PORT_NOT_FOUND -2LL
#undef jsscex_SerialNativeInterface_ERR_PERMISSION_DENIED
#define jsscex_SerialNativeInterface_ERR_PERMISSION_DENIED -3LL
#undef jsscex_SerialNativeInterface_ERR_INCORRECT_SERIAL_PORT
#define jsscex_SerialNativeInterface_ERR_INCORRECT_SERIAL_PORT -4LL
#undef jsscex_SerialNativeInterface_ERR_PORT_NOT_OPENED
#define jsscex_SerialNativeInterface_ERR_PORT_NOT_OPENED -5LL
#undef jsscex_SerialNativeInterface_ERR_PORT_OPENED
#define jsscex_SerialNativeInterface_ERR_PORT_OPENED -6LL

// Для JavaCritical функций обязательно наличие функций-заглушек Java!
// Т.к. JavaCritical может не поддерживаться JVM или вызов из горячего кода (JavaCritical только из скомпилированного!).

JNIEXPORT jstring JNICALL Java_jsscex_SerialNativeInterface_getNativeLibraryVersion(JNIEnv *, jobject);

JNIEXPORT jlong JNICALL Java_jsscex_SerialNativeInterface_openPort(JNIEnv *, jobject, jstring, jboolean);
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_setParams(JNIEnv *, jobject, jlong, jint, jint, jint, jint, jboolean, jboolean, jint);
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_purgePort(JNIEnv *, jobject, jlong, jint);
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_closePort(JNIEnv *, jobject, jlong);
JNIEXPORT jobjectArray JNICALL Java_jsscex_SerialNativeInterface_getSerialPortNames(JNIEnv *, jobject);

JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_setRTS(JNIEnv *, jobject, jlong, jboolean);
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_setDTR(JNIEnv *, jobject, jlong, jboolean);
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_setFlowControlMode(JNIEnv *, jobject, jlong, jint);
JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_getFlowControlMode(JNIEnv *, jobject, jlong);
JNIEXPORT jboolean JNICALL Java_jsscex_SerialNativeInterface_sendBreak(JNIEnv *, jobject, jlong, jint);
JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_getLinesStatus(JNIEnv *, jobject, jlong);


JNIEXPORT jint JNICALL JavaCritical_jsscex_SerialNativeInterface_readBytes(jlong, jbyte*, jint, jint); // DANT
JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_readBytes(JNIEnv *, jobject, jlong, jbyte*, jint, jint); // DANT заглушка.
JNIEXPORT jint JNICALL JavaCritical_jsscex_SerialNativeInterface_readByte(jlong); // DANT
JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_readByte(JNIEnv *, jobject, jlong); // DANT заглушка.
JNIEXPORT jint JNICALL JavaCritical_jsscex_SerialNativeInterface_writeBytes(jlong, jbyte*, jint, jint); // DANT
JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_writeBytes(JNIEnv *, jobject, jlong, jbyte*, jint, jint); // DANT заглушка.
JNIEXPORT jint JNICALL JavaCritical_jsscex_SerialNativeInterface_writeByte(jlong, jint); // DANT
JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_writeByte(JNIEnv *, jobject, jlong, jint); // DANT заглушка.
JNIEXPORT jint JNICALL JavaCritical_jsscex_SerialNativeInterface_getInputBufferBytesCount(jlong); // DANT
JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_getInputBufferBytesCount(JNIEnv *, jobject, jlong); // DANT заглушка.
JNIEXPORT jint JNICALL JavaCritical_jsscex_SerialNativeInterface_getOutputBufferBytesCount(jlong); // DANT
JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_getOutputBufferBytesCount(JNIEnv *, jobject, jlong); // DANT заглушка.

JNIEXPORT jint JNICALL Java_jsscex_SerialNativeInterface_checkPort(JNIEnv *, jobject, jlong, jstring);

#ifdef __cplusplus
}
#endif
#endif
