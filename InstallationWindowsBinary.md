**These instructions apply to version 0.17 and later.**
**Note that this executable will not work on Windows 2000 and earlier.**

# Installation #

  * These instructions assume you have [downloaded](http://code.google.com/p/biodiverse/downloads/list) and extracted the Biodiverse zip file to your hard drive.
  * The following assumes you have unzipped it to `C:\biodiverse`.  If you use a different path then modify the commands below as appropriate.

# Running it #

  * Biodiverse can be run by double clicking on `C:\biodiverse\BiodiverseGUI.exe`.
    * Do not use the `BiodiverseGUI.bat` file.  It is used for the source code version.
  * If you want to keep the command log visible after you close Biodiverse then run it from a command prompt.
    * Under `Start Menu -> Run` type `cmd`.
    * In the resulting command window, type `C:\biodiverse\BiodiverseGUI.exe`.


# Troubleshooting and changes #

  * The Windows executable is generated using the [pp tool](https://metacpan.org/pod/pp).  It will work provided you do not move or rename the Gtk or Gdal folders.  If you do, then make sure their `bin` folders are in your system path so it finds the appropriate binaries that it depends on.  For an example of how to set the path, see http://www.computerhope.com/issues/ch000549.htm.

  * Please report any other issues using the [project issue tracker](http://code.google.com/p/biodiverse/issues/list)