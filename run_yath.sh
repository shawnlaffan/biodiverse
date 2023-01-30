#!/bin/bash

yath -I t/lib \
  -PBiodiverse::TestHelpers \
  -PBiodiverse::BaseData \
  -PGeo::GDAL::FFI \
  -PPDL -D \
  -PMoose \
  test -j 4 --max-open-jobs 18 $@
