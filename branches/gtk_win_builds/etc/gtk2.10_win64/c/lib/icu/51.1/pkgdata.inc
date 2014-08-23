GENCCODE_ASSEMBLY_TYPE=-a gcc-mingw64
SO=dll
SOBJ=dll
A=a
LIBPREFIX=
LIB_EXT_ORDER=51.dll
COMPILE=x86_64-w64-mingw32-gcc   -DHAVE_DLOPEN=0 -DU_HAVE_MMAP=0  -DU_ATTRIBUTE_DEPRECATED= -O2 -g -pipe -Wall -fexceptions --param=ssp-buffer-size=4 -mms-bitfields -Wall -std=c99 -pedantic -Wshadow -Wpointer-arith -Wmissing-prototypes -Wwrite-strings -mthreads -c
LIBFLAGS=-I/usr/x86_64-w64-mingw32/sys-root/mingw/include -DPIC 
GENLIB=x86_64-w64-mingw32-gcc -O2 -g -pipe -Wall -fexceptions --param=ssp-buffer-size=4 -mms-bitfields -Wall -std=c99 -pedantic -Wshadow -Wpointer-arith -Wmissing-prototypes -Wwrite-strings -mthreads -Wl,--exclude-libs=libintl.a -Wl,--exclude-libs=libiconv.a -Wl,--no-keep-memory  -shared -Wl,-Bsymbolic -Wl,--enable-auto-import -Wl,--out-implib=./all.dll.a
LDICUDTFLAGS=
LD_SONAME=
RPATH_FLAGS=
BIR_LDFLAGS=
AR=/usr/bin/x86_64-w64-mingw32-ar
ARFLAGS=r
RANLIB=/usr/bin/x86_64-w64-mingw32-ranlib
INSTALL_CMD=/usr/bin/install -c
