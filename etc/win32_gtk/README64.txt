Approximate procedure for building libart_lgpl-2.3.21 and libgnomecanvas-2.30.3 on x86_64.
Uses Cygwin and it's mingw32-w64-* packages.

Currently results in perl.exe crashing with the infamous "has stopped working" dialog due to Canvas.dll.
Not sure about the cause, but may be because I used PPMs from sisyphusion.tk for everything except Gnome2::Canvas and there may be a binary incompatability in the way we built the libraries.

export PATH="/cygdrive/c/biodiverse/svn/etc/win32_gtk/ex/bin:$PATH" # to get pkg-config.exe
export PKG_CONFIG_PATH='/cygdrive/c/biodiverse/svn/etc/win32_gtk/ex/lib/pkgconfig'
./configure --prefix=/cygdrive/c/biodiverse/svn/etc/win32_gtk/ex --host=x86_64-w64-mingw32 --disable-dependency-tracking # to disable generation of Makefile fragments that contain colons
make
make install

For libgnomecanvas-2.30.3, glib-genmarshal doesn't seem to work properly, so I generated libgnomecanvas/gnome-canvas-marshal.{c,h} on a Linux system and copied them to the "libgnomecanvas" directory before running "make".

They are included in the same directory as this README64.txt.

After installing libgnomecanvas-2.30.3, I manually edited lib/pkgconfig/libgnomecanvas-2.0.pc to have
pango pangoft2 gail
in Requires as well as Requires.private

gtk+-bundle_2.22.1-20101229_win64_custom.zip in this directory is the result of the above work.