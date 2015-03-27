# Introduction #

These are notes for the installation of Geo::GDAL on Ubuntu and Windows.


# Ubuntu #


The latest GDAL package can be obtained from https://launchpad.net/~ubuntugis/+archive/ppa

These commands will add that repo to the apt-get list:
```
sudo add-apt-repository ppa:ubuntugis/ppa 
sudo apt-get update
```


The following extra libs need to be installed:
```
libarmadillo-dev
libpoppler-dev
libepsilon-dev
liblzma-dev
```


Compilation might need to go through the normal  steps.  Download and uncompress the tarball (maybe using cpanm).  Then in the relevant folder (editing the config path to point to bin/gdal-config):
```
perl Makefile.PL --no-version-check --gdal-config=/path/to/gdal-config
make
make test
make install
```


To test that it worked, type the following.  It should throw no errors.

```
  perl -MGeo::GDAL -e 'print "1"'
```


# Windows #

1.  Open a command prompt.  The rest of these instructions assume you are at the prompt.

2.  Run these commands, editing the folder paths as needed to match your system.

```
  :: Change gdal_win64 to gdal_win32 if you are using a 32 bit installation.
  set GDAL_PATH=c:\gdal_win64
  set PATH=%GDAL_PATH%\bin;%PATH%
```

3. Download the GDAL binaries from the Biodiverse subversion repository.
> TortoiseSVN is the easiest way, but this command line will work if you installed the shell options with TortoiseSVN (or you have a different svn client). Remember to change gdal\_win64 to gdal\_win32 if you are using a 32 bit installation.

> svn co https://biodiverse.googlecode.com/svn/branches/gdal_win_builds/etc/gdal_win64 %GDAL\_PATH%


4.  Now we need to install some files using the ppm and cpanm utilities.  Run the ppm install command for all ppd files.  You can copy and paste these into the command prompt.  If you are using a 32 bit perl then change ppm516\_x64 to be ppm516.

```
  :: Install the precompiled binaries needed for the GUI.
  :: Edit the next line to match the perl version you are using, 
  :: e.g. ppm516 for the 32 bit version, ppm516_x64 for 64 bit
  set BDV_PPM=http://biodiverse.googlecode.com/svn/branches/ppm/ppm516_x64
  ppm install %BDV_PPM%/Geo-GDAL.ppd 

```

To test that it worked, type the following.  It should throw no errors, providing your path includes the GDAL bin folder (see step 2).

```
  perl -MGeo::GDAL -e "print '1'"
```

# Running it #

There is no change to running the Biodiverse code on Ubuntu.

There is no change to running the Biodiverse code on Windows provided you have not changed the name of the gdal folder and that it is above the biodiverse/bin folder in the folder hierarchy (Biodiverse looks for it).  If you do keep it somewhere else or use a different name then you will need to add the gdal bin folder to your system path.