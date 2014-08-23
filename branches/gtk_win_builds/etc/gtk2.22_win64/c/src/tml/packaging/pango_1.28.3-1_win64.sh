# This is a shell script that calls functions and scripts from
# tml@iki.fi's personal work environment. It is not expected to be
# usable unmodified by others, and is included only for reference.

MOD=pango
VER=1.28.3
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

DEPS=`latest --arch=${ARCH} gettext-runtime zlib glib pkg-config libpng pixman cairo expat fontconfig freetype`
GETTEXT_RUNTIME=`latest --arch=${ARCH} gettext-runtime`

PKG_CONFIG_PATH=/dummy
for D in $DEPS; do
    PKG_CONFIG_PATH=/devel/dist/${ARCH}/$D/lib/pkgconfig:$PKG_CONFIG_PATH
    PATH=/devel/dist/${ARCH}/$D/bin:$PATH
done

# Brute force solution for problems with libtool: use
# lt_cv_deplibs_check_method= pass_all

lt_cv_deplibs_check_method='pass_all' \
CC='x86_64-w64-mingw32-gcc' \
CXX='x86_64-w64-mingw32-g++' \
LDFLAGS="-L/devel/dist/${ARCH}/${GETTEXT_RUNTIME}/lib \
-Wl,--enable-auto-image-base" \
CFLAGS=-O2 \
./configure --host=x86_64-w64-mingw32 \
--enable-debug=yes \
--disable-gtk-doc \
--without-x \
--enable-explicit-deps=no \
--with-included-modules=yes \
--prefix=c:/devel/target/$HEX &&

make -j3 install &&

./pango-zip.sh &&

cd $TARGET

zip /tmp/${MOD}-dev-${VER}.zip bin/pango-view.exe
zip /tmp/${MOD}-dev-${VER}.zip share/man/man1/*.1

mv /tmp/${MOD}-${VER}.zip /tmp/$RUNZIP &&
mv /tmp/${MOD}-dev-${VER}.zip /tmp/$DEVZIP

) 2>&1 | tee /devel/src/tml/packaging/$THIS.log

(cd /devel && zip /tmp/$DEVZIP src/tml/packaging/$THIS.{sh,log}) &&
manifestify /tmp/$RUNZIP /tmp/$DEVZIP
