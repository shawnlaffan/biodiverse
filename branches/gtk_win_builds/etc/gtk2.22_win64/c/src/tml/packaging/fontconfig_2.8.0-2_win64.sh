# This is a shell script that calls functions and scripts from
# tml@iki.fi's personal work environment. It is not expected to be
# usable unmodified by others, and is included only for reference.

MOD=fontconfig
VER=2.8.0
REV=2
ARCH=win64

THIS=${MOD}_${VER}-${REV}_${ARCH}

RUNZIP=${MOD}_${VER}-${REV}_${ARCH}.zip
DEVZIP=${MOD}-dev_${VER}-${REV}_${ARCH}.zip

# We use a string of hex digits to make it more evident that it is
# just a hash value and not supposed to be relevant at end-user
# machines.
HEX=`echo $THIS | md5sum | cut -d' ' -f1`
TARGET=c:/devel/target/$HEX

usedev
usemingw64
usemsvs9x64

(

set -x

DEPS=`latest --arch=${ARCH} glib pkg-config expat freetype`
EXPAT=`latest --arch=${ARCH} expat`
FREETYPE=`latest --arch=${ARCH} freetype`

PKG_CONFIG_PATH=/dummy
for D in $DEPS; do
    PATH=/devel/dist/${ARCH}/$D/bin:$PATH
    PKG_CONFIG_PATH=/devel/dist/${ARCH}/$D/lib/pkgconfig:$PKG_CONFIG_PATH
done

# Don't let libtool do its relinking dance. Don't know how relevant
# this is, but it doesn't hurt anyway.

sed -e 's/need_relink=yes/need_relink=no # no way --tml/' <ltmain.sh >ltmain.temp && mv ltmain.temp ltmain.sh

patch -p1 <<\EOF &&
EOF

patch -p0 <<\EOF &&
--- src/Makefile.in
+++ src/Makefile.in
@@ -620,6 +620,7 @@
 # gcc import library install/uninstall
 
 @OS_WIN32_TRUE@install-libtool-import-lib: 
+@OS_WIN32_TRUE@	$(MKDIR_P) $(DESTDIR)$(libdir)
 @OS_WIN32_TRUE@	$(INSTALL) .libs/libfontconfig.dll.a $(DESTDIR)$(libdir)
 @OS_WIN32_TRUE@	$(INSTALL) fontconfig.def $(DESTDIR)$(libdir)/fontconfig.def
 
@@ -630,9 +630,10 @@
 @OS_WIN32_FALSE@uninstall-libtool-import-lib:
 
 @MS_LIB_AVAILABLE_TRUE@fontconfig.lib : libfontconfig.la
-@MS_LIB_AVAILABLE_TRUE@	lib -name:libfontconfig-@LIBT_CURRENT_MINUS_AGE@.dll -def:fontconfig.def -out:$@
+@MS_LIB_AVAILABLE_TRUE@	lib -machine:X64 -name:libfontconfig-@LIBT_CURRENT_MINUS_AGE@.dll -def:fontconfig.def -out:$@
 
 @MS_LIB_AVAILABLE_TRUE@install-ms-import-lib:
+@MS_LIB_AVAILABLE_TRUE@	$(mkdir_p) $(DESTDIR)$(libdir)
 @MS_LIB_AVAILABLE_TRUE@	$(INSTALL) fontconfig.lib $(DESTDIR)$(libdir)
 
 @MS_LIB_AVAILABLE_TRUE@uninstall-ms-import-lib:
EOF

# Brute force solution for problems with libtool: use
# lt_cv_deplibs_check_method= pass_all

lt_cv_deplibs_check_method='pass_all' \
CC='x86_64-w64-mingw32-gcc' \
LDFLAGS='-Wl,--enable-auto-image-base' \
CFLAGS=-O2 \
./configure --host=x86_64-w64-mingw32 --with-arch=${ARCH} --with-expat="/devel/dist/${ARCH}/$EXPAT" --with-freetype-config="/devel/dist/${ARCH}/$FREETYPE/bin/freetype-config" --prefix=c:/devel/target/$HEX  --with-confdir=c:/devel/target/$HEX/etc/fonts --disable-static &&

PATH=/devel/target/$HEX/bin:$PATH make -j3 install &&

(cd /devel/target/$HEX/lib && lib.exe -machine:X64 -def:fontconfig.def -out:fontconfig.lib) &&

sed -e "s/@VERSION@/$VER/" <fontconfig-zip.in >fontconfig-zip.in.tem && mv fontconfig-zip.in.tem fontconfig-zip.in &&

./config.status --file=fontconfig-zip &&
./fontconfig-zip &&

mv /tmp/$MOD-$VER.zip /tmp/$RUNZIP &&
mv /tmp/$MOD-dev-$VER.zip /tmp/$DEVZIP

) 2>&1 | tee /devel/src/tml/packaging/$THIS.log

(cd /devel && zip /tmp/$DEVZIP src/tml/packaging/$THIS.{sh,log}) &&
manifestify /tmp/$RUNZIP /tmp/$DEVZIP
