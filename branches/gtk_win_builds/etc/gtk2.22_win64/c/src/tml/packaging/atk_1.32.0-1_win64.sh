# This is a shell script that calls functions and scripts from
# tml@iki.fi's personal work environment. It is not expected to be
# usable unmodified by others, and is included only for reference.

MOD=atk
VER=1.32.0
REV=1
ARCH=win64

THIS=${MOD}_${VER}-${REV}_${ARCH}

RUNZIP=${MOD}_${VER}-${REV}_${ARCH}.zip
DEVZIP=${MOD}-dev_${VER}-${REV}_${ARCH}.zip

HEX=`echo $THIS | md5sum | cut -d' ' -f1`
TARGET=c:/devel/target/$HEX

usedev
usemingw64
usemsvs9x64

(

set -x

DEPS=`latest --arch=${ARCH} glib pkg-config zlib gettext-runtime`
GETTEXT_RUNTIME=`latest --arch=${ARCH} gettext-runtime`

for D in $DEPS; do
    [ -d /devel/dist/${ARCH}/$D/lib/pkgconfig ] && PKG_CONFIG_PATH=/devel/dist/${ARCH}/$D/lib/pkgconfig:$PKG_CONFIG_PATH
    [ -d /devel/dist/${ARCH}/$D/bin ] && PATH=/devel/dist/${ARCH}/$D/bin:$PATH
done

lt_cv_deplibs_check_method='pass_all' \
CC='x86_64-w64-mingw32-gcc' \
CPPFLAGS="-I/devel/dist/${ARCH}/${GETTEXT_RUNTIME}/include" \
LDFLAGS="-L/devel/dist/${ARCH}/${GETTEXT_RUNTIME}/lib \
-Wl,--enable-auto-image-base" \
CFLAGS=-O2 ./configure --host=x86_64-w64-mingw32 --build=i686-pc-mingw32 --disable-gtk-doc --disable-static --prefix=c:/devel/target/$HEX

(cd atk; make atkmarshal.h atkmarshal.c) &&
make install &&

./atk-zip.sh &&

mv /tmp/${MOD}-${VER}.zip /tmp/$RUNZIP &&
mv /tmp/${MOD}-dev-${VER}.zip /tmp/$DEVZIP

) 2>&1 | tee /devel/src/tml/packaging/$THIS.log

(cd /devel && zip /tmp/$DEVZIP src/tml/packaging/$THIS.{sh,log}) &&
manifestify /tmp/$RUNZIP /tmp/$DEVZIP
