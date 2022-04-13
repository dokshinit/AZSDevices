# WIN32
CC_WIN32= i586-mingw32msvc-g++
LIB_WIN32= -I/usr/i586-mingw32msvc/include -L/usr/i586-mingw32msvc/lib -I./
#/usr/lib/jvm/default-java/include
#-lmingw32 -luser32 -lgdi32 -lwinmm -ldxguid
CFLAGS_WIN32= -mwindows
ARCH = x86
NAME = windows_jSSC-Ex-$(VER)_$(ARCH)

# Одномоментная сборка с линковкой (для исключения @ из имён: -Wl,--add-stdcall-alias )
# CFLAGS = -Wall -c -fpic 
all:
	$(CC_WIN32) -o $(NAME).dll -s -g0 -O3 jsscex.cpp $(LIB_WIN32) $(CFLAGS_WIN32) -shared -Wl,--add-stdcall-alias
#$(NAME).def
	i586-mingw32msvc-strip $(NAME).dll


clean:
	rm -rf *.obj *.dll
