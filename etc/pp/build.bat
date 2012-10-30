rem run from bin directory
call pp -v -p -B -o BiodiverseGUI.par BiodiverseGUI.pl -x
rem above line will open Biodiverse. it needs to be closed for script to continue
rem TODO: maybe add logic to BiodiverseGUI.pl to detect when that's happening and
rem automatically close
call parl -B -OBiodiverseGUI.exe BiodiverseGUI.par