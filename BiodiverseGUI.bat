:: Change to the directory that this batch file is in
:: NB: it must be invoked with a full path, as should any arguments!
::  This is because it is a bodge and not a full solution.

:: set oldcd=%CD%
:: for /f %%i in ("%0") do set curpath=%%~dpi
:: cd /d %curpath% 

set batch_path=%~dp0
:: set GTK_BASEPATH=%batch_path%gtk\bin
:: set BIODIVERSE_BIN_PATH=%batch_path%bin
:: set PATH=%GTK_BASEPATH%;%BIODIVERSE_BIN_PATH%;%PATH%
:: set PATH=%BIODIVERSE_BIN_PATH%;%PATH%

:: set PATH

:: set argument=exec (DIR /B /S %1)

perl %batch_path%\bin\BiodiverseGUI.pl %1

:: cd /d %oldcd%

pause

