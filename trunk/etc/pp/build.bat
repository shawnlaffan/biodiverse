rem run from bin directory

rem ======== 2 step procedure. doesn't allow icon
rem call pp -vvv -p -B -o BiodiverseGUI.par BiodiverseGUI.pl -x
rem above line will open Biodiverse. it needs to be closed for script to continue
rem TODO: maybe add logic to BiodiverseGUI.pl to detect when that's happening and
rem automatically close
rem call parl -B -OBiodiverseGUI.exe BiodiverseGUI.par


rem ======== 1 step procedure
call pp -vvv -B -z 9 -i Biodiverse_icon.ico -x -o BiodiverseGUI.exe BiodiverseGUI.pl