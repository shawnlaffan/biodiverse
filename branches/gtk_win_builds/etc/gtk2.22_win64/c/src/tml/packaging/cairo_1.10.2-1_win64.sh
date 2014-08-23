# This is a shell script that calls functions and scripts from
# tml@iki.fi's personal work environment. It is not expected to be
# usable unmodified by others, and is included only for reference.

MOD=cairo
VER=1.10.2
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

sed -e 's/need_relink=yes/need_relink=no # no way --tml/' <build/ltmain.sh >build/ltmain.temp && mv build/ltmain.temp build/ltmain.sh

DEPS=`latest --arch=${ARCH} zlib glib gettext-runtime pkg-config pixman libpng fontconfig freetype`

PKG_CONFIG_PATH=/dummy
for D in $DEPS; do
    PATH=/devel/dist/${ARCH}/$D/bin:$PATH
    PKG_CONFIG_PATH=/devel/dist/${ARCH}/$D/lib/pkgconfig:$PKG_CONFIG_PATH
done

GETTEXT_RUNTIME=`latest --arch=${ARCH} gettext-runtime`
ZLIB=`latest --arch=${ARCH} zlib`

patch -p0 <<'EOF' &&
--- src/cairo.c
+++ src/cairo.c
@@ -238,6 +238,17 @@
     cairo_atomic_int_t occupied;
 } _context_stash;
 
+cairo_atomic_int_t
+ffs(cairo_atomic_int_t i)
+{
+    cairo_atomic_int_t j;
+    if (i == 0)
+        return 0;
+    for (j = 1; (i & 1) == 0; j++)
+        i >>= 1;
+    return j;
+}
+
 static cairo_t *
 _context_get (void)
 {
EOF

# Brute force solution for problems with libtool: use
# lt_cv_deplibs_check_method= pass_all
lt_cv_deplibs_check_method='pass_all' \
png_REQUIRES=libpng \
CC='x86_64-w64-mingw32-gcc' \
CPPFLAGS="-I/devel/dist/${ARCH}/${ZLIB}/include" \
LDFLAGS="-L/devel/dist/${ARCH}/${ZLIB}/lib \
-L/devel/dist/${ARCH}/${GETTEXT_RUNTIME}/lib" \
CFLAGS=-O2 \
./configure --host=x86_64-w64-mingw32 --disable-static --enable-ft=yes --prefix=c:/devel/target/$HEX &&

make -j3 zips &&

cp $MOD-$VER.zip /tmp/$RUNZIP &&
cp $MOD-dev-$VER.zip /tmp/$DEVZIP &&

cp -p src/cairo.def /devel/target/$HEX/lib &&

mkdir -p /devel/target/$HEX/share/doc/$THIS &&
cp -p COPYING COPYING-LGPL-2.1 COPYING-MPL-1.1 /devel/target/$HEX/share/doc/$THIS &&

cd /devel/target/$HEX &&

zip /tmp/$RUNZIP bin/libcairo-gobject-2.dll &&
zip /tmp/$RUNZIP bin/libcairo-script-interpreter-2.dll &&

zip /tmp/$DEVZIP lib/libcairo-gobject.dll.a &&
zip /tmp/$DEVZIP lib/libcairo-script-interpreter.dll.a &&

(cd lib && lib.exe -machine:X64 -def:cairo.def -out:cairo.lib) &&

zip /tmp/$DEVZIP lib/cairo.def lib/cairo.lib &&
zip -r -D /tmp/$RUNZIP share/doc/$THIS &&

# Don't depend on pixman
sed -e 's/ pixman-1 >= 0.12.0//' <lib/pkgconfig/cairo.pc >lib/pkgconfig/cairo.pc.temp && mv lib/pkgconfig/cairo.pc.temp lib/pkgconfig/cairo.pc &&
zip /tmp/$DEVZIP lib/pkgconfig/cairo.pc &&

: ) 2>&1 | tee /devel/src/tml/packaging/$THIS.log &&

(cd /devel && zip /tmp/$DEVZIP src/tml/packaging/$THIS.{sh,log}) &&
manifestify /tmp/$RUNZIP /tmp/$DEVZIP &&

:
