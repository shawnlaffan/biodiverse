# This is a shell script that calls functions and scripts from
# tml@iki.fi's personal work environment. It is not expected to be
# usable unmodified by others, and is included only for reference.

MOD=pkg-config
VER=0.23
REV=2
ARCH=win64

THIS=${MOD}_${VER}-${REV}_${ARCH}

RUNZIP=${MOD}_${VER}-${REV}_${ARCH}.zip
DEVZIP=${MOD}-dev_${VER}-${REV}_${ARCH}.zip

HEX=`echo $THIS | md5sum | cut -d' ' -f1`
TARGET=c:/devel/target/$HEX

usestable
usemingw64

(

set -x

GLIB=`latest-${ARCH} glib`

sed -e 's/need_relink=yes/need_relink=no # no way --tml/' <ltmain.sh >ltmain.temp && mv ltmain.temp ltmain.sh &&

sed -e 's/-lglib-2.0 -liconv -lintl/-lglib-2.0/' <configure >configure.temp && mv configure.temp configure &&

PKG_CONFIG_PATH=/devel/dist/$ARCH/$GLIB/lib/pkgconfig

patch -p0 <<'EOF'
diff -ru ../orig-0.23/ChangeLog ./ChangeLog
--- ../orig-0.23/ChangeLog	2008-01-17 00:49:33.000000000 +0200
+++ ./ChangeLog	2008-02-19 16:18:22.370500000 +0200
@@ -1,3 +1,23 @@
+2008-02-19  Tor Lillqvist  <tml@novell.com>
+
+	* main.c: Remove the possibility to have a default PKG_CONFIG_PATH
+	in the Registry. It is much more flexible to just use environment
+	variables. In general the Registry is not used in the ports of
+	GTK+ or GNOME libraries and software to Windows.
+
+	* parse.c (parse_line): On Windows, handle also .pc files found in
+	a share/pkgconfig folder when automatically redefining a prefix
+	variable for the package.
+
+	* pkg-config.1: Corresponding changes.
+
+2008-02-18  Tor Lillqvist  <tml@novell.com>
+
+	* main.c: Fix some bitrot: On Windows, don't use the compile-time
+	PKG_CONFIG_PC_PATH, but deduce a default one at run-time based on
+	the location of the executable. This was originally what
+	pkg-config did on Windows, but it had bit-rotted.
+
 2008-01-16  Tollef Fog Heen  <tfheen@err.no>
 
 	* NEWS, configure.in: Release 0.23
diff -ru ../orig-0.23/main.c ./main.c
--- ../orig-0.23/main.c	2008-01-17 00:06:48.000000000 +0200
+++ ./main.c	2008-02-19 16:10:08.214250000 +0200
@@ -38,9 +38,13 @@
 
 #ifdef G_OS_WIN32
 /* No hardcoded paths in the binary, thanks */
-#undef PKGLIBDIR
-/* It's OK to leak this, as PKGLIBDIR is invoked only once */
-#define PKG_CONFIG_PATH g_strconcat (g_win32_get_package_installation_directory (PACKAGE, NULL), "\\lib\\pkgconfig", NULL)
+/* It's OK to leak this */
+#undef PKG_CONFIG_PC_PATH
+#define PKG_CONFIG_PC_PATH \
+  g_strconcat (g_win32_get_package_installation_subdirectory (NULL, NULL, "lib/pkgconfig"), \
+	       ";", \
+	       g_win32_get_package_installation_subdirectory (NULL, NULL, "share/pkgconfig"), \
+	       NULL)
 #endif
 
 static int want_debug_spew = 0;
@@ -296,57 +300,6 @@
       add_search_dirs(PKG_CONFIG_PC_PATH, G_SEARCHPATH_SEPARATOR_S);
     }
 
-#ifdef G_OS_WIN32
-  {
-    /* Add search directories from the Registry */
-
-    HKEY roots[] = { HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE };
-    gchar *root_names[] = { "HKEY_CURRENT_USER", "HKEY_LOCAL_MACHINE" };
-    HKEY key;
-    int i;
-    gulong max_value_name_len, max_value_len;
-
-    for (i = 0; i < G_N_ELEMENTS (roots); i++)
-      {
-	key = NULL;
-	if (RegOpenKeyEx (roots[i], "Software\\" PACKAGE "\\PKG_CONFIG_PATH", 0,
-			  KEY_QUERY_VALUE, &key) == ERROR_SUCCESS &&
-	    RegQueryInfoKey (key, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
-			     &max_value_name_len, &max_value_len,
-			     NULL, NULL) == ERROR_SUCCESS)
-	  {
-	    int index = 0;
-	    gchar *value_name = g_malloc (max_value_name_len + 1);
-	    gchar *value = g_malloc (max_value_len + 1);
-
-	    while (TRUE)
-	      {
-		gulong type;
-		gulong value_name_len = max_value_name_len + 1;
-		gulong value_len = max_value_len + 1;
-
-		if (RegEnumValue (key, index++, value_name, &value_name_len,
-				  NULL, &type,
-				  value, &value_len) != ERROR_SUCCESS)
-		  break;
-
-		if (type != REG_SZ)
-		  continue;
-
-		value_name[value_name_len] = '\0';
-		value[value_len] = '\0';
-		debug_spew ("Adding directory '%s' from %s\\Software\\"
-			    PACKAGE "\\PKG_CONFIG_PATH\\%s\n",
-			    value, root_names[i], value_name);
-		add_search_dir (value);
-	      }
-	  }
-	if (key != NULL)
-	  RegCloseKey (key);
-      }
-  }
-#endif
-
   pcsysrootdir = getenv ("PKG_CONFIG_SYSROOT_DIR");
   if (pcsysrootdir)
     {
diff -ru ../orig-0.23/parse.c ./parse.c
--- ../orig-0.23/parse.c	2008-01-16 22:42:49.000000000 +0200
+++ ./parse.c	2008-02-19 16:13:04.339250000 +0200
@@ -1011,18 +1011,25 @@
 	  gchar *prefix = pkg->pcfiledir;
 	  const int prefix_len = strlen (prefix);
 	  const char *const lib_pkgconfig = "\\lib\\pkgconfig";
+	  const char *const share_pkgconfig = "\\share\\pkgconfig";
 	  const int lib_pkgconfig_len = strlen (lib_pkgconfig);
+	  const int share_pkgconfig_len = strlen (share_pkgconfig);
 
-	  if (strlen (prefix) > lib_pkgconfig_len &&
-	      pathnamecmp (prefix + prefix_len - lib_pkgconfig_len,
-			   lib_pkgconfig) == 0)
+	  if ((strlen (prefix) > lib_pkgconfig_len &&
+	       pathnamecmp (prefix + prefix_len - lib_pkgconfig_len, lib_pkgconfig) == 0) ||
+	      (strlen (prefix) > share_pkgconfig_len &&
+	       pathnamecmp (prefix + prefix_len - share_pkgconfig_len, share_pkgconfig) == 0))
 	    {
-	      /* It ends in lib\pkgconfig. Good. */
+	      /* It ends in lib\pkgconfig or share\pkgconfig. Good. */
 	      
 	      gchar *p;
 	      
 	      prefix = g_strdup (prefix);
-	      prefix[prefix_len - lib_pkgconfig_len] = '\0';
+	      if (strlen (prefix) > lib_pkgconfig_len &&
+		  pathnamecmp (prefix + prefix_len - lib_pkgconfig_len, lib_pkgconfig) == 0)
+		prefix[prefix_len - lib_pkgconfig_len] = '\0';
+	      else
+		prefix[prefix_len - share_pkgconfig_len] = '\0';
 	      
 	      /* Turn backslashes into slashes or
 	       * poptParseArgvString() will eat them when ${prefix}
diff -ru ../orig-0.23/pkg-config.1 ./pkg-config.1
--- ../orig-0.23/pkg-config.1	2008-01-16 23:26:50.000000000 +0200
+++ ./pkg-config.1	2008-02-19 16:14:53.417375000 +0200
@@ -274,20 +274,10 @@
 
 .SH WINDOWS SPECIALITIES
 If a .pc file is found in a directory that matches the usual
-conventions (i.e., ends with \\lib\\pkgconfig), the prefix for that
-package is assumed to be the grandparent of the directory where the
-file was found, and the \fIprefix\fP variable is overridden for that
-file accordingly.
-
-In addition to the \fIPKG_CONFIG_PATH\fP environment variable, the
-Registry keys
-.DW
-\fIHKEY_CURRENT_USER\\Software\\pkgconfig\\PKG_CONFIG_PATH\fP and
-.EW
-\fIHKEY_LOCAL_MACHINE\\Software\\pkgconfig\\PKG_CONFIG_PATH\fP can be
-used to specify directories to search for .pc files. Each (string)
-value in these keys is treated as a directory where to look for .pc
-files.
+conventions (i.e., ends with \\lib\\pkgconfig or \\share\\pkgconfig),
+the prefix for that package is assumed to be the grandparent of the
+directory where the file was found, and the \fIprefix\fP variable is
+overridden for that file accordingly.
 
 .SH AUTOCONF MACROS
 
EOF

mkdir /devel/target/$HEX

CC='x86_64-pc-mingw32-gcc' CPPFLAGS="`$PKG_CONFIG --cflags glib-2.0` -I/opt/proxy-libintl/include" LDFLAGS="`$PKG_CONFIG --libs glib-2.0` -L/opt/proxy-libintl/lib64 -Wl,--exclude-libs=libintl.a" CFLAGS=-O2 ./configure --host=x86_64-pc-mingw32 --disable-static --prefix=c:/devel/target/$HEX &&
make -j3 install &&

rm -f /tmp/$RUNZIP /tmp/$DEVZIP

cd /devel/target/$HEX && 
zip /tmp/$RUNZIP bin/pkg-config.exe &&
zip /tmp/$DEVZIP man/man1/pkg-config.1 share/aclocal/pkg.m4

) 2>&1 | tee /devel/src/tml/make/$THIS.log

(cd /devel && zip /tmp/$DEVZIP src/tml/make/$THIS.{sh,log}) &&
manifestify /tmp/$RUNZIP /tmp/$DEVZIP
