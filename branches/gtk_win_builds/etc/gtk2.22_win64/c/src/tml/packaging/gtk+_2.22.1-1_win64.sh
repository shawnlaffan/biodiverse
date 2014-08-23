# This is a shell script that calls functions and scripts from
# tml@iki.fi's personal work envíronment. It is not expected to be
# usable unmodified by others, and is included only for reference.

MOD=gtk+
VER=2.22.1
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

# Yes, we're kinda cross-compiling but still we depend on a previous
# 64-bit version of ourselves for gdk-pixbuf-csource and
# gtk-update-icon-cache, heh.

DEPS=`latest --arch=${ARCH} gettext-runtime zlib glib pkg-config atk libpng pixman cairo expat fontconfig freetype pango gtk+ gdk-pixbuf`
GETTEXT_RUNTIME=`latest --arch=${ARCH} gettext-runtime`

PKG_CONFIG_PATH=/dummy
for D in $DEPS; do
    [ -d /devel/dist/${ARCH}/$D/lib/pkgconfig ] && PKG_CONFIG_PATH=/devel/dist/${ARCH}/$D/lib/pkgconfig:$PKG_CONFIG_PATH
    PATH=/devel/dist/${ARCH}/$D/bin:$PATH
done

LIBPNG=`latest --arch=${ARCH} libpng`
ZLIB=`latest --arch=${ARCH} zlib`

# Brute force solution for problems with libtool
lt_cv_deplibs_check_method='pass_all' \
CC='x86_64-w64-mingw32-gcc' \
CXX='x86_64-w64-mingw32-g++' \
CPPFLAGS="-I/devel/dist/${ARCH}/${LIBPNG}/include \
-I/devel/dist/${ARCH}/${ZLIB}/include \
-I/devel/dist/${ARCH}/${GETTEXT_RUNTIME}/include" \
LDFLAGS="-L/devel/dist/${ARCH}/${LIBPNG}/lib \
-L/devel/dist/${ARCH}/${ZLIB}/lib \
-L/devel/dist/${ARCH}/${GETTEXT_RUNTIME}/lib \
-Wl,--enable-auto-image-base" \
LIBS=-lintl \
CFLAGS=-O2 \
./configure --host=x86_64-w64-mingw32 --build=i686-pc-mingw32 \
--with-gdktarget=win32 \
--with-included-immodules \
--enable-debug=yes \
--enable-explicit-deps=no \
--disable-gtk-doc \
--disable-static \
--prefix=$TARGET &&

rm gtk/gtk.def &&

mkdir -p $TARGET/lib &&

make -j3 install &&

./gtk-zip.sh &&

# Package also the gtk-update-icon-cache.exe.manifest
(cd $TARGET && zip /tmp/${MOD}-dev-${VER}.zip bin/gtk-update-icon-cache.exe.manifest) &&

mv /tmp/${MOD}-${VER}.zip /tmp/$RUNZIP &&
mv /tmp/${MOD}-dev-${VER}.zip /tmp/$DEVZIP &&

: ) 2>&1 | tee /devel/src/tml/packaging/$THIS.log

(cd /devel && zip /tmp/$DEVZIP src/tml/packaging/$THIS.{sh,log}) &&
manifestify /tmp/$RUNZIP /tmp/$DEVZIP &&

:
