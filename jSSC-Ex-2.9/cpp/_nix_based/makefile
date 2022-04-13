CC = $(CROSS_COMPILE)g++
CFLAGS = -Wall -c -fpic -I./
#-I/usr/lib/jvm/default-java/include
NAME = linux_libjSSC-Ex-$(VER)_$(ARCH)

all:
	$(CC) $(CFLAGS) jsscex.cpp
	$(CC) -shared -o $(NAME).so jsscex.o
	strip $(NAME).so

clean:
	rm -rf *.o *.so
