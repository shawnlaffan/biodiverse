:: run from bin directory

:: ======== 2 step procedure. doesn't allow icon
:: call pp -vvv -p -B -o BiodiverseGUI.par BiodiverseGUI.pl -x
:: above line will open Biodiverse. it needs to be closed for script to continue
:: TODO: maybe add logic to BiodiverseGUI.pl to detect when that's happening and
:: automatically close
:: call parl -B -OBiodiverseGUI.exe BiodiverseGUI.par

:: Copy across some files needed to run the system

echo off

if "%1"=="32" goto :32bit
if "%1"=="64" goto :64bit

echo "Need to pass argument 32 or 64"
exit /B

:32bit
echo "using 32 bit"
set perl_path=C:\strawberry_51611_x32
set perl_c_path=%perl_path%\c\bin
set lib_expat=libexpat-1_.dll
set bits=32

goto :copy_files

:64bit
echo "using 64 bit"
set perl_path=C:\strawberry51611
set perl_c_path=%perl_path%\c\bin
set lib_expat=libexpat-1__.dll
set bits=64

:copy_files
echo %perl_c_path%
copy "%perl_c_path%\libgcc_s_sjlj-1.dll"
copy "%perl_c_path%\libstdc++-6.dll"
copy "%perl_c_path%\%lib_expat%"

:: set the path to ensure we're using the correct perl

call %perl_path%\set_paths.bat

:: ======== 1 step procedure
:: === Biodiverse will open.  It can then be closed.
:: === This will load the relevant external libs.

set BDV_PP_BUILDING=1
set BIODIVERSE_EXTENSIONS_IGNORE=1
set verbosity=-v
call pp %verbosity% -B -z 9 -i Biodiverse_icon.ico -a glade -a Biodiverse_icon.ico -x -o BiodiverseGUI_x%bits%.exe BiodiverseGUI.pl

set BDV_PP_BUILDING=0


:: Need to build into a target directory.