# This is a shell script that is sourced, not executed. It uses
# functions and scripts from tml@iki.fi's work envíronment and is
# included only for reference

MOD=pixman
VER=0.20.0
REV=1
ARCH=win64

THIS=${MOD}_${VER}-${REV}_${ARCH}

RUNZIP=${MOD}_${VER}-${REV}_${ARCH}.zip
DEVZIP=${MOD}-dev_${VER}-${REV}_${ARCH}.zip

HEX=`echo $THIS | md5sum | cut -d' ' -f1`
TARGET=c:/devel/target/$HEX

usedev
usemingw64

(

set -x

DEPS=`latest --arch=${ARCH} glib pkg-config`

for D in $DEPS; do
    PATH=/devel/dist/${ARCH}/$D/bin:$PATH
done

for F in pixman/pixman-{mmx,sse2}.c; do
    sed -e 's!(unsigned long)!(uintptr_t)!' <$F >$F.tmp && mv $F.tmp $F
done

CC='x86_64-w64-mingw32-gcc' \
CFLAGS=-O2 \
./configure --host=x86_64-w64-mingw32 --disable-shared --prefix=c:/devel/target/$HEX &&
PATH=/devel/target/$HEX/bin:$PATH make install &&

rm -f /tmp/$RUNZIP /tmp/$DEVZIP &&

(cd /devel/target/$HEX &&

# I build pixman as a static library only, so the "run-time" package
# is actually empty. I create it here anyway to be able to use some
# scripts that assume each library has both a run-time and developer
# version.

zip /tmp/$RUNZIP nul &&
zip -d /tmp/$RUNZIP nul &&
zip -r -D /tmp/$DEVZIP include/pixman-1 &&
zip /tmp/$DEVZIP lib/libpixman-1.a &&
zip -r -D /tmp/$DEVZIP lib/pkgconfig &&

: )

) 2>&1 | tee /devel/src/tml/packaging/$THIS.log &&

(cd /devel && zip /tmp/$DEVZIP src/tml/packaging/$THIS.{sh,log}) &&
manifestify /tmp/$RUNZIP /tmp/$DEVZIP &&

:
