These are a set of example files to use when trying Biodiverse.  
Note that these are fictional data so the results have no meaning beyond example purposes.

Data files that can be imported:

Example_site_data.csv               Species sample data in a Lambert Conformal Conic projection for Australia (see coastline.prj for definition)
Example_site_data.shp, dbf, shx, sbn, prj    Species sample data as a shapefile.  
Example_site_data_matrix_form.csv    Species data in matrix form (resolution 25000 units)
Example_matrix.txt                  Matrix data (dissimilarity)
Example_tree.nex                    Tree data
Example_tree_remap.txt              Remap table to change the tree names to match the site data

Data files that have already been imported (easier to start off with):

example_data_x64.bps    Example project file for use on 64 bit systems.
example_data_x64.bds    Example basedata file.  This is the first basedata object from the 64 bit project file.  
example_matrix.bms      Example matrix file
example_tree.bts        Example tree file

Note that randomisations cannot be extended between architectures due to the random number generator library being used, hence the above files are labelled for 64 bit systems.
More recent versions of Biodiverse than 0.17 support only 64 bit architectures in any case.  


Additional data:
coastline.shp and associated files are vector data to overlay when plotting a map.  They are in the same coordinate system as the example data.

