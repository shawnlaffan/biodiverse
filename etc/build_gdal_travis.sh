#!/bin/sh

echo Running gdal build script

export gdal_version=2.1.3
export perl_gdal_version=2.010301
export geo_gdal_tar=Geo-GDAL-${perl_gdal_version}.tar.gz
export geo_gdal_dir=Geo-GDAL-${perl_gdal_version}
export gdal_home=$TRAVIS_BUILD_DIR/gdal_builds/${gdal_version}
echo gdal_home is $gdal_home

startdir=`pwd`
mkdir -p ${gdal_home}
cd ${gdal_home}
pwd
find $gdal_home -name 'gdal-config' -print
gdalconfig=`find $gdal_home -name 'gdal-config' -print | grep apps | head -1`
echo gdal config is $gdalconfig
if [ -n "$gdalconfig" ]; then build_gdal=false; else build_gdal=true; fi;
echo build_gdal var is $build_gdal
if [ "$build_gdal" = true ]; then wget http://download.osgeo.org/gdal/${gdal_version}/gdal-${gdal_version}.tar.gz; fi
  #  should use -C and --strip-components to simplify the dir structure
if [ "$build_gdal" = true ]; then tar -xzf gdal-${gdal_version}.tar.gz; fi
if [ "$build_gdal" = true ]; then cd gdal-${gdal_version} && ./configure --prefix=${gdal_home} && make -j4 && make install; fi
cd ${startdir}
if [ "$build_gdal" = true ]; then gdalconfig=`find $gdal_home -name 'gdal-config' -print | grep apps | head -1`; fi
find $gdal_home -name 'gdal-config' -print
  #  using env vars avoids cpanm parsing the --gdal-config type arguments in cpanm Geo::GDAL
export PERL_GDAL_NO_DOWNLOADS=1
export PERL_GDAL_SOURCE_TREE=${gdal_home}/gdal-${gdal_version}
echo PERL_GDAL_SOURCE_TREE is $PERL_GDAL_SOURCE_TREE

# Here as well as cpanfile because -v stops travis from timing out and killing the build
# (and -v for the whole install produces a ridiculously large log)
#  -v should not be needed now we build our own
cpanm -v Geo::GDAL