# Indices available in Biodiverse #
_Generated GMT Mon Sep  8 05:18:48 2014 using build\_indices\_table.pl, Biodiverse version 0.99\_004._


This is a listing of the indices available in Biodiverse,
ordered by the calculations used to generate them.
It is generated from the system metadata and contains all the
information visible in the GUI, plus some additional details.

Most of the headings are self-explanatory.  For the others:
  * The **Subroutine** is the name of the subroutine used to call the function if you are using Biodiverse through a script.
  * The **Index** is the name of the index in the SPATIAL\_RESULTS list, or if it is its own list then this will be its name.  These lists can contain a variety of values, but are usually lists of labels with some value, for example the weights used in an endemism calculation.  The names of such lists typically end in "LIST", "ARRAY", "HASH", "LABELS" or "STATS".
  * **Valid cluster metric** is whether or not the index can be used as a clustering metric.  A blank value means it cannot.
  * The **Minimum number of neighbour sets** dictates whether or not a calculation or index will be run.  If you specify only one neighbour set then all those calculations that require two sets will be dropped from the analysis.  (This is always the case for calculations applied to cluster nodes as there is only one neighbour set, defined by the set of groups linked to the terminal nodes below a cluster node).  Note that many of the calculations lump neighbour sets 1 and 2 together.  See the SpatialConditions page for more details on neighbour sets.

Note that calculations can provide different numbers of indices depending on the nature of the BaseData set used.
This currently applies to the hierarchically partitioned endemism calculations (both [central](#Endemism_central_hierarchical_partition.md) and [whole](#Endemism_whole_hierarchical_partition.md)) and [hierarchical labels](#Hierarchical_Labels.md).

Table of contents:


## Element Properties ##




> ### Group property Gi`*` statistics ###

**Description:**   List of Getis-Ord Gi`*` statistics for each group property across both neighbour sets

**Subroutine:**   calc\_gpprop\_gistar

**Reference:**   Getis and Ord (1992) Geographical Analysis. http://dx.doi.org/10.1111/j.1538-4632.1992.tb00261.x


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 1 | GPPROP\_GISTAR\_LIST | List of Gi`*` scores |   | 1 |







> ### Group property data ###

**Description:**   Lists of the groups and their property values used in the group properties calculations

**Subroutine:**   calc\_gpprop\_lists

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 2 | GPPROP\_STATS\_EXAMPLE\_GPROP1\_DATA | List of values for property EXAMPLE\_GPROP1 |   | 1 |
| 3 | GPPROP\_STATS\_EXAMPLE\_GPROP2\_DATA | List of values for property EXAMPLE\_GPROP2 |   | 1 |







> ### Group property hashes ###

**Description:**   Hashes of the groups and their property values used in the group properties calculations. Hash keys are the property values, hash values are the property value frequencies.

**Subroutine:**   calc\_gpprop\_hashes

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 4 | GPPROP\_STATS\_EXAMPLE\_GPROP1\_HASH | Hash of values for property EXAMPLE\_GPROP1 |   | 1 |
| 5 | GPPROP\_STATS\_EXAMPLE\_GPROP2\_HASH | Hash of values for property EXAMPLE\_GPROP2 |   | 1 |







> ### Group property quantiles ###

**Description:**   Quantiles for each group property across both neighbour sets

**Subroutine:**   calc\_gpprop\_quantiles

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 6 | GPPROP\_QUANTILE\_LIST | List of quantiles for the label properties (05 10 20 30 40 50 60 70 80 90 95) |   | 1 |







> ### Group property summary stats ###

**Description:**   List of summary statistics for each group property across both neighbour sets

**Subroutine:**   calc\_gpprop\_stats

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 7 | GPPROP\_STATS\_LIST | List of summary statistics (count mean min max median sum sd iqr) |   | 1 |







> ### Label property Gi`*` statistics ###

**Description:**   List of Getis-Ord Gi`*` statistic for each label property across both neighbour sets

**Subroutine:**   calc\_lbprop\_gistar

**Reference:**   Getis and Ord (1992) Geographical Analysis. http://dx.doi.org/10.1111/j.1538-4632.1992.tb00261.x


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 8 | LBPROP\_GISTAR\_LIST | List of Gi`*` scores |   | 1 |







> ### Label property Gi`*` statistics (local range weighted) ###

**Description:**   List of Getis-Ord Gi`*` statistic for each label property across both neighbour sets (local range weighted)

**Subroutine:**   calc\_lbprop\_gistar\_abc2

**Reference:**   Getis and Ord (1992) Geographical Analysis. http://dx.doi.org/10.1111/j.1538-4632.1992.tb00261.x


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 9 | LBPROP\_GISTAR\_LIST\_ABC2 | List of Gi`*` scores |   | 1 |







> ### Label property data ###

**Description:**   Lists of the labels and their property values used in the label properties calculations

**Subroutine:**   calc\_lbprop\_data

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 10 | LBPROP\_STATS\_EXAMPLE\_PROP1\_DATA | List of data for property EXAMPLE\_PROP1 |   | 1 |
| 11 | LBPROP\_STATS\_EXAMPLE\_PROP2\_DATA | List of data for property EXAMPLE\_PROP2 |   | 1 |







> ### Label property hashes ###

**Description:**   Hashes of the labels and their property values used in the label properties calculations. Hash keys are the property values, hash values are the property value frequencies.

**Subroutine:**   calc\_lbprop\_hashes

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 12 | LBPROP\_STATS\_EXAMPLE\_PROP1\_HASH | Hash of values for property EXAMPLE\_PROP1 |   | 1 |
| 13 | LBPROP\_STATS\_EXAMPLE\_PROP2\_HASH | Hash of values for property EXAMPLE\_PROP2 |   | 1 |







> ### Label property hashes (local range weighted) ###

**Description:**   Hashes of the labels and their property values
used in the local range weighted label properties calculations.
Hash keys are the property values,
hash values are the property value frequencies.


**Subroutine:**   calc\_lbprop\_hashes\_abc2

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 14 | LBPROP\_STATS\_EXAMPLE\_PROP1\_HASH2 | Hash of values for property EXAMPLE\_PROP1 |   | 1 |
| 15 | LBPROP\_STATS\_EXAMPLE\_PROP2\_HASH2 | Hash of values for property EXAMPLE\_PROP2 |   | 1 |







> ### Label property lists ###

**Description:**   Lists of the labels and their property values within the neighbour sets

**Subroutine:**   calc\_lbprop\_lists

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 16 | LBPROP\_LIST\_EXAMPLE\_PROP1 | List of data for property EXAMPLE\_PROP1 |   | 1 |
| 17 | LBPROP\_LIST\_EXAMPLE\_PROP2 | List of data for property EXAMPLE\_PROP2 |   | 1 |







> ### Label property quantiles ###

**Description:**   List of quantiles for each label property across both neighbour sets


**Subroutine:**   calc\_lbprop\_quantiles

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 18 | LBPROP\_QUANTILES | List of quantiles for the label properties: (05 10 20 30 40 50 60 70 80 90 95) |   | 1 |







> ### Label property quantiles (local range weighted) ###

**Description:**   List of quantiles for each label property across both neighbour sets (local range weighted)


**Subroutine:**   calc\_lbprop\_quantiles\_abc2

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 19 | LBPROP\_QUANTILES\_ABC2 | List of quantiles for the label properties: (05 10 20 30 40 50 60 70 80 90 95) |   | 1 |







> ### Label property summary stats ###

**Description:**   List of summary statistics for each label property across both neighbour sets


**Subroutine:**   calc\_lbprop\_stats

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 20 | LBPROP\_STATS | List of summary statistics (count mean min max median sum skewness kurtosis sd iqr) |   | 1 |







> ### Label property summary stats (local range weighted) ###

**Description:**   List of summary statistics for each label property across both neighbour sets, weighted by local ranges


**Subroutine:**   calc\_lbprop\_stats\_abc2

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 21 | LBPROP\_STATS\_ABC2 | List of summary statistics (count mean min max median sum skewness kurtosis sd iqr) |   | 1 |


## Endemism ##




> ### Absolute endemism ###

**Description:**   Absolute endemism scores.


**Subroutine:**   calc\_endemism\_absolute

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 22 | END\_ABS1 | Count of labels entirely endemic to neighbour set 1 |   | 1 |
| 23 | END\_ABS1\_P | Proportion of labels entirely endemic to neighbour set 1 |   | 1 |
| 24 | END\_ABS2 | Count of labels entirely endemic to neighbour set 2 |   | 1 |
| 25 | END\_ABS2\_P | Proportion of labels entirely endemic to neighbour set 2 |   | 1 |
| 26 | END\_ABS\_ALL | Count of labels entirely endemic to neighbour sets 1 and 2 combined |   | 1 |
| 27 | END\_ABS\_ALL\_P | Proportion of labels entirely endemic to neighbour sets 1 and 2 combined |   | 1 |







> ### Absolute endemism lists ###

**Description:**   Lists underlying the absolute endemism scores.


**Subroutine:**   calc\_endemism\_absolute\_lists

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 28 | END\_ABS1\_LIST | List of labels entirely endemic to neighbour set 1 |   | 1 |
| 29 | END\_ABS2\_LIST | List of labels entirely endemic to neighbour set 1 |   | 1 |
| 30 | END\_ABS\_ALL\_LIST | List of labels entirely endemic to neighbour sets 1 and 2 combined |   | 1 |







> ### Endemism central ###

**Description:**   Calculate endemism for labels only in neighbour set 1, but with local ranges calculated using both neighbour sets

**Subroutine:**   calc\_endemism\_central

**Reference:**   Crisp et al. (2001) J Biogeog. http://dx.doi.org/10.1046/j.1365-2699.2001.00524.x ; Laffan and Crisp (2003) J Biogeog. http://www3.interscience.wiley.com/journal/118882020/abstract


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** | **Reference** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|:--------------|
| 31 | ENDC\_CWE | Corrected weighted endemism |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \frac{ENDC\_WE}{ENDC\_RICHNESS}%.png' title='= \frac{ENDC\_WE}{ENDC\_RICHNESS}' />  |   |
| 32 | ENDC\_RICHNESS | Richness used in ENDC\_CWE (same as index RICHNESS\_SET1) |   | 1 |   |   |
| 33 | ENDC\_SINGLE | Endemism unweighted by the number of neighbours. Counts each label only once, regardless of how many groups in the neighbourhood it is found in.   Useful if your data have sampling biases and best applied with a small window. |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \sum_{t \in T} \frac {1} {R_t}%.png' title='= \sum_{t \in T} \frac {1} {R_t}' /> where <img src='http://latex.codecogs.com/png.latex?t%.png' title='t' /> is a label (taxon) in the set of labels (taxa) <img src='http://latex.codecogs.com/png.latex?T%.png' title='T' /> in neighbour set 1, and <img src='http://latex.codecogs.com/png.latex?R_t%.png' title='R_t' /> is the global range of label <img src='http://latex.codecogs.com/png.latex?t%.png' title='t' /> across the data set (the number of groups it is found in, unless the range is specified at import).  | Slatyer et al. (2007) J. Biogeog http://dx.doi.org/10.1111/j.1365-2699.2006.01647.x |
| 34 | ENDC\_WE | Weighted endemism |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \sum_{t \in T} \frac {r_t} {R_t}%.png' title='= \sum_{t \in T} \frac {r_t} {R_t}' /> where <img src='http://latex.codecogs.com/png.latex?t%.png' title='t' /> is a label (taxon) in the set of labels (taxa) <img src='http://latex.codecogs.com/png.latex?T%.png' title='T' /> in neighbour set 1, <img src='http://latex.codecogs.com/png.latex?r_t%.png' title='r_t' /> is the local range (the number of elements containing label <img src='http://latex.codecogs.com/png.latex?t%.png' title='t' /> within neighbour sets 1 & 2, this is also its value in list ABC2\_LABELS\_ALL), and <img src='http://latex.codecogs.com/png.latex?R_t%.png' title='R_t' /> is the global range of label <img src='http://latex.codecogs.com/png.latex?t%.png' title='t' /> across the data set (the number of groups it is found in, unless the range is specified at import).  |   |







> ### Endemism central hierarchical partition ###

**Description:**   Partition the endemism central results based on the taxonomic hierarchy inferred from the label axes. (Level 0 is the highest).

**Subroutine:**   calc\_endemism\_central\_hier\_part

**Reference:**   Laffan et al. (2013) J Biogeog. http://dx.doi.org/10.1111/jbi.12001


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 35 | ENDC\_HPART\_0 | List of the proportional contribution of labels to the endemism central calculations, hierarchical level 0 |   | 1 |
| 36 | ENDC\_HPART\_1 | List of the proportional contribution of labels to the endemism central calculations, hierarchical level 1 |   | 1 |
| 37 | ENDC\_HPART\_C\_0 | List of the proportional count of labels to the endemism central calculations (equivalent to richness per hierarchical grouping), hierarchical level 0 |   | 1 |
| 38 | ENDC\_HPART\_C\_1 | List of the proportional count of labels to the endemism central calculations (equivalent to richness per hierarchical grouping), hierarchical level 1 |   | 1 |
| 39 | ENDC\_HPART\_E\_0 | List of the expected proportional contribution of labels to the endemism central calculations (richness per hierarchical grouping divided by overall richness), hierarchical level 0 |   | 1 |
| 40 | ENDC\_HPART\_E\_1 | List of the expected proportional contribution of labels to the endemism central calculations (richness per hierarchical grouping divided by overall richness), hierarchical level 1 |   | 1 |
| 41 | ENDC\_HPART\_OME\_0 | List of the observed minus expected proportional contribution of labels to the endemism central calculations , hierarchical level 0 |   | 1 |
| 42 | ENDC\_HPART\_OME\_1 | List of the observed minus expected proportional contribution of labels to the endemism central calculations , hierarchical level 1 |   | 1 |







> ### Endemism central lists ###

**Description:**   Lists used in endemism central calculations

**Subroutine:**   calc\_endemism\_central\_lists

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 43 | ENDC\_RANGELIST | List of ranges for each label used in the endemism central calculations |   | 1 |
| 44 | ENDC\_WTLIST | List of weights for each label used in the endemism central calculations |   | 1 |







> ### Endemism central normalised ###

**Description:**   Normalise the WE and CWE scores by the neighbourhood size.
(The number of groups used to determine the local ranges).


**Subroutine:**   calc\_endemism\_central\_normalised

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 45 | ENDC\_CWE\_NORM | Corrected weighted endemism normalised by groups |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \frac{ENDC\_CWE}{EL\_COUNT\_ALL}%.png' title='= \frac{ENDC\_CWE}{EL\_COUNT\_ALL}' />  |
| 46 | ENDC\_WE\_NORM | Weighted endemism normalised by groups |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \frac{ENDC\_WE}{EL\_COUNT\_ALL}%.png' title='= \frac{ENDC\_WE}{EL\_COUNT\_ALL}' />  |







> ### Endemism whole ###

**Description:**   Calculate endemism using all labels found in both neighbour sets

**Subroutine:**   calc\_endemism\_whole

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** | **Reference** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|:--------------|
| 47 | ENDW\_CWE | Corrected weighted endemism |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \frac{ENDW\_WE}{ENDW\_RICHNESS}%.png' title='= \frac{ENDW\_WE}{ENDW\_RICHNESS}' />  |   |
| 48 | ENDW\_RICHNESS | Richness used in ENDW\_CWE (same as index RICHNESS\_ALL) |   | 1 |   |   |
| 49 | ENDW\_SINGLE | Endemism unweighted by the number of neighbours. Counts each label only once, regardless of how many groups in the neighbourhood it is found in.   Useful if your data have sampling biases and best applied with a small window. |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \sum_{t \in T} \frac {1} {R_t}%.png' title='= \sum_{t \in T} \frac {1} {R_t}' /> where <img src='http://latex.codecogs.com/png.latex?t%.png' title='t' /> is a label (taxon) in the set of labels (taxa) <img src='http://latex.codecogs.com/png.latex?T%.png' title='T' /> across neighbour sets 1 & 2, and <img src='http://latex.codecogs.com/png.latex?R_t%.png' title='R_t' /> is the global range of label <img src='http://latex.codecogs.com/png.latex?t%.png' title='t' /> across the data set (the number of groups it is found in, unless the range is specified at import).  | Slatyer et al. (2007) J. Biogeog http://dx.doi.org/10.1111/j.1365-2699.2006.01647.x |
| 50 | ENDW\_WE | Weighted endemism |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \sum_{t \in T} \frac {r_t} {R_t}%.png' title='= \sum_{t \in T} \frac {r_t} {R_t}' /> where <img src='http://latex.codecogs.com/png.latex?t%.png' title='t' /> is a label (taxon) in the set of labels (taxa) <img src='http://latex.codecogs.com/png.latex?T%.png' title='T' /> across both neighbour sets, <img src='http://latex.codecogs.com/png.latex?r_t%.png' title='r_t' /> is the local range (the number of elements containing label <img src='http://latex.codecogs.com/png.latex?t%.png' title='t' /> within neighbour sets 1 & 2, this is also its value in list ABC2\_LABELS\_ALL), and <img src='http://latex.codecogs.com/png.latex?R_t%.png' title='R_t' /> is the global range of label <img src='http://latex.codecogs.com/png.latex?t%.png' title='t' /> across the data set (the number of groups it is found in, unless the range is specified at import).  |   |







> ### Endemism whole hierarchical partition ###

**Description:**   Partition the endemism whole results based on the taxonomic hierarchy inferred from the label axes. (Level 0 is the highest).

**Subroutine:**   calc\_endemism\_whole\_hier\_part

**Reference:**   Laffan et al. (2013) J Biogeog. http://dx.doi.org/10.1111/jbi.12001


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 51 | ENDW\_HPART\_0 | List of the proportional contribution of labels to the endemism whole calculations, hierarchical level 0 |   | 1 |
| 52 | ENDW\_HPART\_1 | List of the proportional contribution of labels to the endemism whole calculations, hierarchical level 1 |   | 1 |
| 53 | ENDW\_HPART\_C\_0 | List of the proportional count of labels to the endemism whole calculations (equivalent to richness per hierarchical grouping), hierarchical level 0 |   | 1 |
| 54 | ENDW\_HPART\_C\_1 | List of the proportional count of labels to the endemism whole calculations (equivalent to richness per hierarchical grouping), hierarchical level 1 |   | 1 |
| 55 | ENDW\_HPART\_E\_0 | List of the expected proportional contribution of labels to the endemism whole calculations (richness per hierarchical grouping divided by overall richness), hierarchical level 0 |   | 1 |
| 56 | ENDW\_HPART\_E\_1 | List of the expected proportional contribution of labels to the endemism whole calculations (richness per hierarchical grouping divided by overall richness), hierarchical level 1 |   | 1 |
| 57 | ENDW\_HPART\_OME\_0 | List of the observed minus expected proportional contribution of labels to the endemism whole calculations , hierarchical level 0 |   | 1 |
| 58 | ENDW\_HPART\_OME\_1 | List of the observed minus expected proportional contribution of labels to the endemism whole calculations , hierarchical level 1 |   | 1 |







> ### Endemism whole lists ###

**Description:**   Lists used in the endemism whole calculations

**Subroutine:**   calc\_endemism\_whole\_lists

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 59 | ENDW\_RANGELIST | List of ranges for each label used in the endemism whole calculations |   | 1 |
| 60 | ENDW\_WTLIST | List of weights for each label used in the endemism whole calculations |   | 1 |







> ### Endemism whole normalised ###

**Description:**   Normalise the WE and CWE scores by the neighbourhood size.
(The number of groups used to determine the local ranges).


**Subroutine:**   calc\_endemism\_whole\_normalised

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 61 | ENDW\_CWE\_NORM | Corrected weighted endemism normalised by groups |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \frac{ENDW\_CWE}{EL\_COUNT\_ALL}%.png' title='= \frac{ENDW\_CWE}{EL\_COUNT\_ALL}' />  |
| 62 | ENDW\_WE\_NORM | Weighted endemism normalised by groups |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \frac{ENDW\_WE}{EL\_COUNT\_ALL}%.png' title='= \frac{ENDW\_WE}{EL\_COUNT\_ALL}' />  |


## Hierarchical Labels ##




> ### Ratios of hierarchical labels ###

**Description:**   Analyse the diversity of labels using their hierarchical levels.
The A, B and C scores are the same as in the Label Counts analysis (calc\_label\_counts)
but calculated for each hierarchical level, e.g. for three axes one could have
A0 as the Family level, A1 for the Family:Genus level,
and A2 for the Family:Genus:Species level.
The number of indices generated depends on how many axes are used in the labels.
In this case there are 2.  Axes are numbered from zero
as the highest level in the hierarchy, so level 0 is the top level
of the hierarchy.


**Subroutine:**   calc\_hierarchical\_label\_ratios

**Reference:**   Jones and Laffan (2008) Trans Philol Soc http://dx.doi.org/10.1111/j.1467-968X.2008.00209.x


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 63 | HIER\_A0 | A score for level 0 |   | 1 |
| 64 | HIER\_A1 | A score for level 1 |   | 1 |
| 65 | HIER\_ARAT1\_0 | Ratio of A scores, (HIER\_A1 / HIER\_A0) |   | 1 |
| 66 | HIER\_ASUM0 | Sum of shared label sample counts, level 0 |   | 1 |
| 67 | HIER\_ASUM1 | Sum of shared label sample counts, level 1 |   | 1 |
| 68 | HIER\_ASUMRAT1\_0 | 1 - Ratio of shared label sample counts, (HIER\_ASUM1 / HIER\_ASUM0) | cluster metric | 1 |
| 69 | HIER\_B0 | B score  for level 0 |   | 1 |
| 70 | HIER\_B1 | B score  for level 1 |   | 1 |
| 71 | HIER\_BRAT1\_0 | Ratio of B scores, (HIER\_B1 / HIER\_B0) |   | 1 |
| 72 | HIER\_C0 | C score for level 0 |   | 1 |
| 73 | HIER\_C1 | C score for level 1 |   | 1 |
| 74 | HIER\_CRAT1\_0 | Ratio of C scores, (HIER\_C1 / HIER\_C0) |   | 1 |


## Inter-event Interval Statistics ##




> ### Inter-event interval statistics ###

**Description:**   Calculate summary statistics from a set of numeric labels that represent event times.
Event intervals are calculated within groups, then aggregated across the neighbourhoods, and then summary stats are calculated.

**Subroutine:**   calc\_iei\_stats

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 75 | IEI\_CV | Coefficient of variation (IEI\_SD / IEI\_MEAN) |   | 1 |
| 76 | IEI\_GMEAN | Geometric mean |   | 1 |
| 77 | IEI\_KURT | Kurtosis |   | 1 |
| 78 | IEI\_MAX | Maximum value (100th percentile) |   | 1 |
| 79 | IEI\_MEAN | Mean | cluster metric | 1 |
| 80 | IEI\_MIN | Minimum value (zero percentile) |   | 1 |
| 81 | IEI\_N | Number of samples |   | 1 |
| 82 | IEI\_RANGE | Range (max - min) |   | 1 |
| 83 | IEI\_SD | Standard deviation |   | 1 |
| 84 | IEI\_SKEW | Skewness |   | 1 |







> ### Inter-event interval statistics data ###

**Description:**   The underlying data used for the IEI stats.

**Subroutine:**   calc\_iei\_data

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 85 | IEI\_DATA\_ARRAY | Interval data in array form.  Multiple occurrences are repeated  |   | 1 |
| 86 | IEI\_DATA\_HASH | Interval data in hash form where the  interval is the key and number of occurrences is the value |   | 1 |


## Lists and Counts ##




> ### Element counts ###

**Description:**   Counts of elements used in neighbour sets 1 and 2.


**Subroutine:**   calc\_elements\_used

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 87 | EL\_COUNT\_ALL | Count of elements in both neighbour sets |   | 2 |
| 88 | EL\_COUNT\_SET1 | Count of elements in neighbour set 1 |   | 1 |
| 89 | EL\_COUNT\_SET2 | Count of elements in neighbour set 2 |   | 2 |







> ### Element lists ###

**Description:**   Lists of elements used in neighbour sets 1 and 2.
These form the basis for all the spatial calculations.

**Subroutine:**   calc\_element\_lists\_used

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 90 | EL\_LIST\_ALL | List of elements in both neighour sets |   | 2 |
| 91 | EL\_LIST\_SET1 | List of elements in neighbour set 1 |   | 1 |
| 92 | EL\_LIST\_SET2 | List of elements in neighbour set 2 |   | 2 |







> ### Label counts ###

**Description:**   Counts of labels in neighbour sets 1 and 2.
These form the basis for the Taxonomic Dissimilarity and Comparison indices.

**Subroutine:**   calc\_abc\_counts

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 93 | ABC\_A | Count of labels common to both neighbour sets |   | 1 |
| 94 | ABC\_ABC | Total label count across both neighbour sets (same as RICHNESS\_ALL) |   | 1 |
| 95 | ABC\_B | Count of labels unique to neighbour set 1 |   | 1 |
| 96 | ABC\_C | Count of labels unique to neighbour set 2 |   | 1 |







> ### Label counts not in sample ###

**Description:**   Count of basedata labels not in either neighbour set (shared absence)
Used in some of the dissimilarity metrics.

**Subroutine:**   calc\_d

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 97 | ABC\_D | Count of labels not in either neighbour set (D score) |   | 1 |







> ### Local range lists ###

**Description:**   Lists of labels with their local ranges as values.
The local ranges are the number of elements in which each label is found in each neighour set.

**Subroutine:**   calc\_local\_range\_lists

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 98 | ABC2\_LABELS\_ALL | List of labels in both neighbour sets |   | 2 |
| 99 | ABC2\_LABELS\_SET1 | List of labels in neighbour set 1 |   | 1 |
| 100 | ABC2\_LABELS\_SET2 | List of labels in neighbour set 2 |   | 2 |







> ### Local range summary statistics ###

**Description:**   Summary stats of the local ranges within neighour sets.

**Subroutine:**   calc\_local\_range\_stats

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 101 | ABC2\_MEAN\_ALL | Mean label range in both element sets |   | 1 |
| 102 | ABC2\_MEAN\_SET1 | Mean label range in neighbour set 1 |   | 1 |
| 103 | ABC2\_MEAN\_SET2 | Mean label range in neighbour set 2 |   | 2 |
| 104 | ABC2\_SD\_ALL | Standard deviation of label ranges in both element sets |   | 2 |
| 105 | ABC2\_SD\_SET1 | Standard deviation of label ranges in neighbour set 1 |   | 1 |
| 106 | ABC2\_SD\_SET2 | Standard deviation of label ranges in neighbour set 2 |   | 2 |







> ### Redundancy ###

**Description:**   Ratio of labels to samples.
Values close to 1 are well sampled while zero means
there is no redundancy in the sampling


**Subroutine:**   calc\_redundancy

**Reference:**   Garcillan et al. (2003) J Veget. Sci. http://dx.doi.org/10.1111/j.1654-1103.2003.tb02174.x


**Formula:**
> <img src='http://latex.codecogs.com/png.latex?= 1 - \frac{richness}{sum\ of\ the\ sample\ counts}%.png' title='= 1 - \frac{richness}{sum\ of\ the\ sample\ counts}' />

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 107 | REDUNDANCY\_ALL | for both neighbour sets |   | 1 | <img src='http://latex.codecogs.com/png.latex?= 1 - \frac{RICHNESS\_ALL}{ABC3\_SUM\_ALL}%.png' title='= 1 - \frac{RICHNESS\_ALL}{ABC3\_SUM\_ALL}' />   |
| 108 | REDUNDANCY\_SET1 | for neighour set 1 |   | 1 | <img src='http://latex.codecogs.com/png.latex?= 1 - \frac{RICHNESS\_SET1}{ABC3\_SUM\_SET1}%.png' title='= 1 - \frac{RICHNESS\_SET1}{ABC3\_SUM\_SET1}' />   |
| 109 | REDUNDANCY\_SET2 | for neighour set 2 |   | 2 | <img src='http://latex.codecogs.com/png.latex?= 1 - \frac{RICHNESS\_SET2}{ABC3\_SUM\_SET2}%.png' title='= 1 - \frac{RICHNESS\_SET2}{ABC3\_SUM\_SET2}' />   |







> ### Richness ###

**Description:**   Count the number of labels in the neighbour sets

**Subroutine:**   calc\_richness

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 110 | RICHNESS\_ALL | for both sets of neighbours |   | 1 |
| 111 | RICHNESS\_SET1 | for neighbour set 1 |   | 1 |
| 112 | RICHNESS\_SET2 | for neighbour set 2 |   | 2 |







> ### Sample count lists ###

**Description:**   Lists of sample counts for each label within the neighbour sets.
These form the basis of the sample indices.

**Subroutine:**   calc\_local\_sample\_count\_lists

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 113 | ABC3\_LABELS\_ALL | List of labels in both neighbour sets with their sample counts as the values. |   | 2 |
| 114 | ABC3\_LABELS\_SET1 | List of labels in neighbour set 1. Values are the sample counts.   |   | 1 |
| 115 | ABC3\_LABELS\_SET2 | List of labels in neighbour set 2. Values are the sample counts. |   | 2 |







> ### Sample count summary stats ###

**Description:**   Summary stats of the sample counts across the neighbour sets.


**Subroutine:**   calc\_local\_sample\_count\_stats

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 116 | ABC3\_MEAN\_ALL | Mean of label sample counts across both element sets. |   | 2 |
| 117 | ABC3\_MEAN\_SET1 | Mean of label sample counts in neighbour set1. |   | 1 |
| 118 | ABC3\_MEAN\_SET2 | Mean of label sample counts in neighbour set 2. |   | 2 |
| 119 | ABC3\_SD\_ALL | Standard deviation of label sample counts in both element sets. |   | 2 |
| 120 | ABC3\_SD\_SET1 | Standard deviation of sample counts in neighbour set 1. |   | 1 |
| 121 | ABC3\_SD\_SET2 | Standard deviation of label sample counts in neighbour set 2. |   | 2 |
| 122 | ABC3\_SUM\_ALL | Sum of the label sample counts across both neighbour sets. |   | 2 |
| 123 | ABC3\_SUM\_SET1 | Sum of the label sample counts across both neighbour sets. |   | 1 |
| 124 | ABC3\_SUM\_SET2 | Sum of the label sample counts in neighbour set2. |   | 2 |


## Matrix ##




> ### Compare dissimilarity matrix values ###

**Description:**   Compare the set of labels in one neighbour set with those in another using their matrix values. Labels not in the matrix are ignored. This calculation assumes a matrix of dissimilarities and uses 0 as identical, so take care).

**Subroutine:**   calc\_compare\_dissim\_matrix\_values

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 125 | MXD\_COUNT | Count of comparisons used. |   | 1 |
| 126 | MXD\_LIST1 | List of the labels used from neighbour set 1 (those in the matrix). The list values are the number of times each label was used in the calculations. This will always be 1 for labels in neighbour set 1. |   | 1 |
| 127 | MXD\_LIST2 | List of the labels used from neighbour set 2 (those in the matrix). The list values are the number of times each label was used in the calculations. This will equal the number of labels used from neighbour set 1. |   | 1 |
| 128 | MXD\_MEAN | Mean dissimilarity of labels in set 1 to those in set 2. | cluster metric | 1 |
| 129 | MXD\_VARIANCE | Variance of the dissimilarity values, set 1 vs set 2. | cluster metric | 1 |







> ### Matrix statistics ###

**Description:**   Calculate summary statistics of matrix elements in the selected matrix for labels found across both neighbour sets.
Labels not in the matrix are ignored.

**Subroutine:**   calc\_matrix\_stats

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 130 | MX\_KURT | Kurtosis |   | 1 |
| 131 | MX\_LABELS | List of the matrix labels in the neighbour sets |   | 1 |
| 132 | MX\_MAXVALUE | Maximum value |   | 1 |
| 133 | MX\_MEAN | Mean |   | 1 |
| 134 | MX\_MEDIAN | Median |   | 1 |
| 135 | MX\_MINVALUE | Minimum value |   | 1 |
| 136 | MX\_N | Number of samples (matrix elements, not labels) |   | 1 |
| 137 | MX\_PCT05 | 5th percentile value |   | 1 |
| 138 | MX\_PCT25 | First quartile (25th percentile) |   | 1 |
| 139 | MX\_PCT75 | Third quartile (75th percentile) |   | 1 |
| 140 | MX\_PCT95 | 95th percentile value |   | 1 |
| 141 | MX\_RANGE | Range (max-min) |   | 1 |
| 142 | MX\_SD | Standard deviation |   | 1 |
| 143 | MX\_SKEW | Skewness |   | 1 |
| 144 | MX\_VALUES | List of the matrix values |   | 1 |







> ### Rao's quadratic entropy, matrix weighted ###

**Description:**   Calculate Rao's quadratic entropy for a matrix weights scheme.
BaseData labels not in the matrix are ignored

**Subroutine:**   calc\_mx\_rao\_qe

**Formula:**
> <img src='http://latex.codecogs.com/png.latex?= \sum_{i \in L} \sum_{j \in L} d_{ij} p_i p_j%.png' title='= \sum_{i \in L} \sum_{j \in L} d_{ij} p_i p_j' /> where <img src='http://latex.codecogs.com/png.latex?p_i%.png' title='p_i' /> and <img src='http://latex.codecogs.com/png.latex?p_j%.png' title='p_j' /> are the sample counts for the i'th and j'th labels, <img src='http://latex.codecogs.com/png.latex?d_{ij}%.png' title='d_{ij}' /> is the matrix value for the pair of labels <img src='http://latex.codecogs.com/png.latex?ij%.png' title='ij' /> and <img src='http://latex.codecogs.com/png.latex?L%.png' title='L' /> is the set of labels across both neighbour sets that occur in the matrix.

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 145 | MX\_RAO\_QE | Matrix weighted quadratic entropy |   | 1 |
| 146 | MX\_RAO\_TLABELS | List of labels and values used in the MX\_RAO\_QE calculations |   | 1 |
| 147 | MX\_RAO\_TN | Count of comparisons used to calculate MX\_RAO\_QE |   | 1 |


## Numeric Labels ##




> ### Numeric label data ###

**Description:**   The underlying data used for the numeric labels stats, as an array.
For the hash form, use the ABC3\_LABELS\_ALL index from the 'Sample count lists' calculation.

**Subroutine:**   calc\_numeric\_label\_data

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 148 | NUM\_DATA\_ARRAY | Numeric label data in array form.  Multiple occurrences are repeated based on their sample counts. |   | 1 |







> ### Numeric label dissimilarity ###

**Description:**   Compare the set of numeric labels in one neighbour set with those in another.

**Subroutine:**   calc\_numeric\_label\_dissimilarity

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 149 | NUMD\_ABSMEAN | Mean absolute dissimilarity of labels in set 1 to those in set 2. | cluster metric | 1 | <img src='http://latex.codecogs.com/png.latex?= \frac{\sum_{l_{1i} \in L_1} \sum_{l_{2j} \in L_2} abs (l_{1i} - l_{2j})(w_{1i} \times w_{2j})}{n_1 \times n_2}%.png' title='= \frac{\sum_{l_{1i} \in L_1} \sum_{l_{2j} \in L_2} abs (l_{1i} - l_{2j})(w_{1i} \times w_{2j})}{n_1 \times n_2}' /> where<img src='http://latex.codecogs.com/png.latex?L1%.png' title='L1' /> and <img src='http://latex.codecogs.com/png.latex?L2%.png' title='L2' /> are the labels in neighbour sets 1 and 2 respectively, and <img src='http://latex.codecogs.com/png.latex?n1%.png' title='n1' /> and <img src='http://latex.codecogs.com/png.latex?n2%.png' title='n2' /> are the sample counts in neighbour sets 1 and 2  |
| 150 | NUMD\_COUNT | Count of comparisons used. |   | 1 | <img src='http://latex.codecogs.com/png.latex?= n1 * n2%.png' title='= n1 * n2' /> where values are as for <img src='http://latex.codecogs.com/png.latex?NUMD\_ABSMEAN%.png' title='NUMD\_ABSMEAN' />  |
| 151 | NUMD\_VARIANCE | Variance of the dissimilarity values (mean squared deviation), set 1 vs set 2. | cluster metric | 1 | <img src='http://latex.codecogs.com/png.latex?= \frac{\sum_{l_{1i} \in L_1} \sum_{l_{2j} \in L_2} (l_{1i} - l_{2j})^2(w_{1i} \times w_{2j})}{n_1 \times n_2}%.png' title='= \frac{\sum_{l_{1i} \in L_1} \sum_{l_{2j} \in L_2} (l_{1i} - l_{2j})^2(w_{1i} \times w_{2j})}{n_1 \times n_2}' /> where values are as for <img src='http://latex.codecogs.com/png.latex?NUMD\_ABSMEAN%.png' title='NUMD\_ABSMEAN' />  |







> ### Numeric label harmonic and geometric means ###

**Description:**   Calculate geometric and harmonic means for a set of numeric labels.


**Subroutine:**   calc\_numeric\_label\_other\_means

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 152 | NUM\_GMEAN | Geometric mean |   | 1 |
| 153 | NUM\_HMEAN | Harmonic mean |   | 1 |







> ### Numeric label quantiles ###

**Description:**   Calculate quantiles from a set of numeric labels.
Weights by samples so multiple occurrences are accounted for.


**Subroutine:**   calc\_numeric\_label\_quantiles

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 154 | NUM\_Q005 | 5th percentile |   | 1 |
| 155 | NUM\_Q010 | 10th percentile |   | 1 |
| 156 | NUM\_Q015 | 15th percentile |   | 1 |
| 157 | NUM\_Q020 | 20th percentile |   | 1 |
| 158 | NUM\_Q025 | 25th percentile |   | 1 |
| 159 | NUM\_Q030 | 30th percentile |   | 1 |
| 160 | NUM\_Q035 | 35th percentile |   | 1 |
| 161 | NUM\_Q040 | 40th percentile |   | 1 |
| 162 | NUM\_Q045 | 45th percentile |   | 1 |
| 163 | NUM\_Q050 | 50th percentile |   | 1 |
| 164 | NUM\_Q055 | 55th percentile |   | 1 |
| 165 | NUM\_Q060 | 60th percentile |   | 1 |
| 166 | NUM\_Q065 | 65th percentile |   | 1 |
| 167 | NUM\_Q070 | 70th percentile |   | 1 |
| 168 | NUM\_Q075 | 75th percentile |   | 1 |
| 169 | NUM\_Q080 | 80th percentile |   | 1 |
| 170 | NUM\_Q085 | 85th percentile |   | 1 |
| 171 | NUM\_Q090 | 90th percentile |   | 1 |
| 172 | NUM\_Q095 | 95th percentile |   | 1 |







> ### Numeric label statistics ###

**Description:**   Calculate summary statistics from a set of numeric labels.
Weights by samples so multiple occurrences are accounted for.


**Subroutine:**   calc\_numeric\_label\_stats

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 173 | NUM\_CV | Coefficient of variation (NUM\_SD / NUM\_MEAN) |   | 1 |
| 174 | NUM\_KURT | Kurtosis |   | 1 |
| 175 | NUM\_MAX | Maximum value (100th quantile) |   | 1 |
| 176 | NUM\_MEAN | Mean |   | 1 |
| 177 | NUM\_MIN | Minimum value (zero quantile) |   | 1 |
| 178 | NUM\_N | Number of samples |   | 1 |
| 179 | NUM\_RANGE | Range (max - min) |   | 1 |
| 180 | NUM\_SD | Standard deviation |   | 1 |
| 181 | NUM\_SKEW | Skewness |   | 1 |







> ### Numeric labels Gi`*` statistic ###

**Description:**   Getis-Ord Gi`*` statistic for numeric labels across both neighbour sets

**Subroutine:**   calc\_num\_labels\_gistar

**Reference:**   Getis and Ord (1992) Geographical Analysis. http://dx.doi.org/10.1111/j.1538-4632.1992.tb00261.x


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 182 | NUM\_GISTAR | List of Gi`*` scores |   | 1 |


## PhyloCom Indices ##




> ### NRI and NTI expected values ###

**Description:**   Expected values used in the NRI and NTI calculations.
Derived using a null model without resampling where
each label has an equal probability of being selected
(a null model of even distrbution).
The expected mean and SD are the same for each unique number
of labels across all neighbour sets.  This means if you have
three neighbour sets, each with three labels, then the expected
values will be identical for each, even if the labels are
completely different.


**Subroutine:**   calc\_nri\_nti\_expected\_values

**Reference:**   Webb et al. (2008) http://dx.doi.org/10.1093/bioinformatics/btn358


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 183 | PHYLO\_NRI\_NTI\_SAMPLE\_N | Number of random resamples used |   | 1 |   |
| 184 | PHYLO\_NRI\_SAMPLE\_MEAN | Expected mean of pair-wise distances |   | 1 |   |
| 185 | PHYLO\_NRI\_SAMPLE\_SD | Expected standard deviation of pair-wise distances |   | 1 |   |
| 186 | PHYLO\_NTI\_SAMPLE\_MEAN | Expected mean of nearest taxon distances |   | 1 |   |
| 187 | PHYLO\_NTI\_SAMPLE\_SD | Expected standard deviation of nearest taxon distances |   | 1 |   |







> ### NRI and NTI, abundance weighted ###

**Description:**   NRI and NTI for the set of labels
on the tree in the sample. This
version is -1 times the Phylocom implementation,
so values >0 have longer branches than expected.
> Abundance weighted.

**Subroutine:**   calc\_nri\_nti3

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 188 | PHYLO\_NRI3 | Net Relatedness Index, abundance weighted |   | 1 |   |
| 189 | PHYLO\_NTI3 | Nearest Taxon Index, abundance weighted |   | 1 |   |







> ### NRI and NTI, local range weighted ###

**Description:**   NRI and NTI for the set of labels
on the tree in the sample. This
version is -1 times the Phylocom implementation,
so values >0 have longer branches than expected.
> Local range weighted.

**Subroutine:**   calc\_nri\_nti2

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 190 | PHYLO\_NRI2 | Net Relatedness Index, local range weighted |   | 1 |   |
| 191 | PHYLO\_NTI2 | Nearest Taxon Index, local range weighted |   | 1 |   |







> ### NRI and NTI, unweighted ###

**Description:**   NRI and NTI for the set of labels
on the tree in the sample. This
version is -1 times the Phylocom implementation,
so values >0 have longer branches than expected.
> Not weighted by sample counts, so each label counts once only.

**Subroutine:**   calc\_nri\_nti1

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 192 | PHYLO\_NRI1 | Net Relatedness Index, unweighted |   | 1 |   |
| 193 | PHYLO\_NTI1 | Nearest Taxon Index, unweighted |   | 1 |   |







> ### Phylogenetic and Nearest taxon distances, abundance weighted ###

**Description:**   Distance stats from each label to the nearest label along the tree.  Compares with all other labels across both neighbour sets. Weighted by sample counts (which currently must be integers)

**Subroutine:**   calc\_phylo\_mpd\_mntd3

**Reference:**   Webb et al. (2008) http://dx.doi.org/10.1093/bioinformatics/btn358


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 194 | PMPD3\_MAX | Maximum of pairwise phylogenetic distances |   | 1 |
| 195 | PMPD3\_MEAN | Mean of pairwise phylogenetic distances |   | 1 |
| 196 | PMPD3\_MIN | Minimum of pairwise phylogenetic distances |   | 1 |
| 197 | PMPD3\_N | Count of pairwise phylogenetic distances |   | 1 |
| 198 | PMPD3\_RMSD | Root mean squared pairwise phylogenetic distances |   | 1 |
| 199 | PNTD3\_MAX | Maximum of nearest taxon distances |   | 1 |
| 200 | PNTD3\_MEAN | Mean of nearest taxon distances |   | 1 |
| 201 | PNTD3\_MIN | Minimum of nearest taxon distances |   | 1 |
| 202 | PNTD3\_N | Count of nearest taxon distances |   | 1 |
| 203 | PNTD3\_RMSD | Root mean squared nearest taxon distances |   | 1 |







> ### Phylogenetic and Nearest taxon distances, local range weighted ###

**Description:**   Distance stats from each label to the nearest label along the tree.  Compares with all other labels across both neighbour sets. Weighted by sample counts

**Subroutine:**   calc\_phylo\_mpd\_mntd2

**Reference:**   Webb et al. (2008) http://dx.doi.org/10.1093/bioinformatics/btn358


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 204 | PMPD2\_MAX | Maximum of pairwise phylogenetic distances |   | 1 |
| 205 | PMPD2\_MEAN | Mean of pairwise phylogenetic distances |   | 1 |
| 206 | PMPD2\_MIN | Minimum of pairwise phylogenetic distances |   | 1 |
| 207 | PMPD2\_N | Count of pairwise phylogenetic distances |   | 1 |
| 208 | PMPD2\_RMSD | Root mean squared pairwise phylogenetic distances |   | 1 |
| 209 | PNTD2\_MAX | Maximum of nearest taxon distances |   | 1 |
| 210 | PNTD2\_MEAN | Mean of nearest taxon distances |   | 1 |
| 211 | PNTD2\_MIN | Minimum of nearest taxon distances |   | 1 |
| 212 | PNTD2\_N | Count of nearest taxon distances |   | 1 |
| 213 | PNTD2\_RMSD | Root mean squared nearest taxon distances |   | 1 |







> ### Phylogenetic and Nearest taxon distances, unweighted ###

**Description:**   Distance stats from each label to the nearest label along the tree.  Compares with all other labels across both neighbour sets.

**Subroutine:**   calc\_phylo\_mpd\_mntd1

**Reference:**   Webb et al. (2008) http://dx.doi.org/10.1093/bioinformatics/btn358


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 214 | PMPD1\_MAX | Maximum of pairwise phylogenetic distances |   | 1 |
| 215 | PMPD1\_MEAN | Mean of pairwise phylogenetic distances |   | 1 |
| 216 | PMPD1\_MIN | Minimum of pairwise phylogenetic distances |   | 1 |
| 217 | PMPD1\_N | Count of pairwise phylogenetic distances |   | 1 |
| 218 | PMPD1\_RMSD | Root mean squared pairwise phylogenetic distances |   | 1 |
| 219 | PNTD1\_MAX | Maximum of nearest taxon distances |   | 1 |
| 220 | PNTD1\_MEAN | Mean of nearest taxon distances |   | 1 |
| 221 | PNTD1\_MIN | Minimum of nearest taxon distances |   | 1 |
| 222 | PNTD1\_N | Count of nearest taxon distances |   | 1 |
| 223 | PNTD1\_RMSD | Root mean squared nearest taxon distances |   | 1 |


## Phylogenetic Endemism ##




> ### Corrected weighted phylogenetic endemism ###

**Description:**   What proportion of the PD is range-restricted to this neighbour set?

**Subroutine:**   calc\_phylo\_corrected\_weighted\_endemism

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** | **Reference** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|:--------------|
| 224 | PE\_CWE | Corrected weighted endemism.  This is the phylogenetic analogue of corrected weighted endemism. |   | 1 | <img src='http://latex.codecogs.com/png.latex?PE_WE / PD%.png' title='PE_WE / PD' />  |   |







> ### Corrected weighted phylogenetic endemism, central variant ###

**Description:**   What proportion of the PD in neighbour set 1 is range-restricted to neighbour sets 1 and 2?

**Subroutine:**   calc\_pe\_central\_cwe

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 225 | PEC\_CWE | Corrected weighted phylogenetic endemism, central variant |   | 1 |
| 226 | PEC\_CWE\_PD | PD used in the PEC\_CWE index. |   | 1 |







> ### Corrected weighted phylogenetic rarity ###

**Description:**   What proportion of the PD is abundance-restricted to this neighbour set?

**Subroutine:**   calc\_phylo\_corrected\_weighted\_rarity

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** | **Reference** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|:--------------|
| 227 | PHYLO\_RARITY\_CWR | Corrected weighted phylogenetic rarity.  This is the phylogenetic rarity analogue of corrected weighted endemism. |   | 1 | <img src='http://latex.codecogs.com/png.latex?AED_T / PD%.png' title='AED_T / PD' />  |   |







> ### PE clade contributions ###

**Description:**   Contribution of each node and its descendents to the Phylogenetic endemism (PE) calculation.

**Subroutine:**   calc\_pe\_clade\_contributions

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 228 | PE\_CLADE\_CONTR | List of node (clade) contributions to the PE calculation |   | 1 |
| 229 | PE\_CLADE\_CONTR\_P | List of node (clade) contributions to the PE calculation, proportional to the entire tree |   | 1 |
| 230 | PE\_CLADE\_SCORE | List of PE scores for each node (clade), being the sum of all descendent PE weights |   | 1 |







> ### PE clade loss ###

**Description:**   How much of the PE would be lost if a clade were to be removed? Calculates the clade PE below the last ancestral node in the neighbour set which would still be in the neighbour set.

**Subroutine:**   calc\_pe\_clade\_loss

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 231 | PE\_CLADE\_LOSS\_CONTR | List of the proportion of the PE score which would be lost if each clade were removed. |   | 1 |
| 232 | PE\_CLADE\_LOSS\_CONTR\_P | As per PE\_CLADE\_LOSS but proportional to the entire tree |   | 1 |
| 233 | PE\_CLADE\_LOSS\_SCORE | List of how much PE would be lost if each clade were removed. |   | 1 |







> ### PE clade loss (ancestral component) ###

**Description:**   How much of the PE clade loss is due to the ancestral branches? The score is zero when there is no ancestral loss.

**Subroutine:**   calc\_pe\_clade\_loss\_ancestral

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 234 | PE\_CLADE\_LOSS\_ANC | List of how much ancestral PE would be lost if each clade were removed.  The value is 0 when no ancestral PE is lost. |   | 1 |
| 235 | PE\_CLADE\_LOSS\_ANC\_P | List of the proportion of the clade's PE loss that is due to the ancestral branches. |   | 1 |







> ### Phylogenetic Endemism ###

**Description:**   Phylogenetic endemism (PE).Uses labels in both neighbourhoods and trims the tree to exclude labels not in the BaseData object.

**Subroutine:**   calc\_pe

**Reference:**   Rosauer et al (2009) Mol. Ecol. http://dx.doi.org/10.1111/j.1365-294X.2009.04311.x


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 236 | PE\_WE | Phylogenetic endemism |   | 1 |
| 237 | PE\_WE\_P | Phylogenetic weighted endemism as a proportion of the total tree length |   | 1 |







> ### Phylogenetic Endemism central ###

**Description:**   Phylogenetic endemism (PE).
Uses labels from neighbour set one but local ranges from across
both neighbour sets.
Trims the tree to exclude labels not in the BaseData object.


**Subroutine:**   calc\_pe\_central

**Reference:**   Rosauer et al (2009) Mol. Ecol. http://dx.doi.org/10.1111/j.1365-294X.2009.04311.x


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 238 | PEC\_WE | Phylogenetic endemism, central variant |   | 1 |
| 239 | PEC\_WE\_P | Phylogenetic weighted endemism as a proportion of the total tree length, central variant |   | 1 |







> ### Phylogenetic Endemism central lists ###

**Description:**   Lists underlying the phylogenetic endemism central indices.
Uses labels from neighbour set one but local ranges from across
both neighbour sets.


**Subroutine:**   calc\_pe\_central\_lists

**Reference:**   Rosauer et al (2009) Mol. Ecol. http://dx.doi.org/10.1111/j.1365-294X.2009.04311.x


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 240 | PEC\_LOCAL\_RANGELIST | Phylogenetic endemism local range lists, central variant |   | 1 |
| 241 | PEC\_RANGELIST | Phylogenetic endemism global range lists, central variant |   | 1 |
| 242 | PEC\_WTLIST | Phylogenetic endemism weights, central variant |   | 1 |







> ### Phylogenetic Endemism lists ###

**Description:**   Lists used in the Phylogenetic endemism (PE) calculations.

**Subroutine:**   calc\_pe\_lists

**Reference:**   Rosauer et al (2009) Mol. Ecol. http://dx.doi.org/10.1111/j.1365-294X.2009.04311.x


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 243 | PE\_LOCAL\_RANGELIST | Local node ranges used in PE calculations (number of groups in which a node is found) |   | 1 |
| 244 | PE\_RANGELIST | Node ranges used in PE calculations |   | 1 |
| 245 | PE\_WTLIST | Node weights used in PE calculations |   | 1 |







> ### Phylogenetic Endemism single ###

**Description:**   PE scores, but not weighted by local ranges.

**Subroutine:**   calc\_pe\_single

**Reference:**   Rosauer et al (2009) Mol. Ecol. http://dx.doi.org/10.1111/j.1365-294X.2009.04311.x


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 246 | PE\_WE\_SINGLE | Phylogenetic endemism unweighted by the number of neighbours. Counts each label only once, regardless of how many groups in the neighbourhood it is found in. Useful if your data have sampling biases. Better with small sample windows. |   | 1 |
| 247 | PE\_WE\_SINGLE\_P | Phylogenetic endemism unweighted by the number of neighbours as a proportion of the total tree length. Counts each label only once, regardless of how many groups in the neighbourhood it is found. Useful if your data have sampling biases. |   | 1 |


## Phylogenetic Indices ##




> ### Count labels on tree ###

**Description:**   Count the number of labels that are on the tree

**Subroutine:**   calc\_count\_labels\_on\_tree

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 248 | PHYLO\_LABELS\_ON\_TREE\_COUNT | The number of labels that are found on the tree, across both neighbour sets |   | 1 |







> ### Evolutionary distinctiveness ###

**Description:**   Evolutionary distinctiveness metrics (AED, ED, ES)
Label values are constant for all neighbourhoods in which each label is found.

**Subroutine:**   calc\_phylo\_aed

**Reference:**   Cadotte & Davies (2010) http://dx.doi.org/10.1111/j.1472-4642.2010.00650.x


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Reference** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:--------------|
| 249 | PHYLO\_AED\_LIST | Abundance weighted ED per terminal label |   | 1 | Cadotte & Davies (2010) http://dx.doi.org/10.1111/j.1472-4642.2010.00650.x |
| 250 | PHYLO\_ED\_LIST | "Fair proportion" partitioning of PD per terminal label |   | 1 | Isaac et al. (2007) http://dx.doi.org/10.1371/journal.pone.0000296 |
| 251 | PHYLO\_ES\_LIST | Equal splits partitioning of PD per terminal label |   | 1 | Redding & Mooers (2006) http://dx.doi.org/10.1111%2Fj.1523-1739.2006.00555.x |







> ### Evolutionary distinctiveness per site ###

**Description:**   Site level evolutionary distinctiveness

**Subroutine:**   calc\_phylo\_aed\_t

**Reference:**   Cadotte & Davies (2010) http://dx.doi.org/10.1111/j.1472-4642.2010.00650.x


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Reference** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:--------------|
| 252 | PHYLO\_AED\_T | Abundance weighted ED\_t (sum of values in PHYLO\_AED\_LIST times their abundances). This is equivalent to a phylogenetic rarity score (see phylogenetic endemism) |   | 1 | Cadotte & Davies (2010) http://dx.doi.org/10.1111/j.1472-4642.2010.00650.x |







> ### Evolutionary distinctiveness per terminal taxon per site ###

**Description:**   Site level evolutionary distinctiveness per terminal taxon

**Subroutine:**   calc\_phylo\_aed\_t\_wtlists

**Reference:**   Cadotte & Davies (2010) http://dx.doi.org/10.1111/j.1472-4642.2010.00650.x


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Reference** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:--------------|
| 253 | PHYLO\_AED\_T\_WTLIST | Abundance weighted ED per terminal taxon (the AED score of each taxon multiplied by its abundance in the sample) |   | 1 | Cadotte & Davies (2010) http://dx.doi.org/10.1111/j.1472-4642.2010.00650.x |
| 254 | PHYLO\_AED\_T\_WTLIST\_P | Proportional contribution of each terminal taxon to the AED\_T score |   | 1 | Cadotte & Davies (2010) http://dx.doi.org/10.1111/j.1472-4642.2010.00650.x |







> ### Labels not on tree ###

**Description:**   Create a hash of the labels that are not on the tree

**Subroutine:**   calc\_labels\_not\_on\_tree

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 255 | PHYLO\_LABELS\_NOT\_ON\_TREE | A hash of labels that are not found on the tree, across both neighbour sets |   | 1 |
| 256 | PHYLO\_LABELS\_NOT\_ON\_TREE\_N | Number of labels not on the tree |   | 1 |
| 257 | PHYLO\_LABELS\_NOT\_ON\_TREE\_P | Proportion of labels not on the tree |   | 1 |







> ### Labels on tree ###

**Description:**   Create a hash of the labels that are on the tree

**Subroutine:**   calc\_labels\_on\_tree

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 258 | PHYLO\_LABELS\_ON\_TREE | A hash of labels that are found on the tree, across both neighbour sets |   | 1 |







> ### PD clade contributions ###

**Description:**   Contribution of each node and its descendents to the Phylogenetic diversity (PD) calculation.

**Subroutine:**   calc\_pd\_clade\_contributions

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 259 | PD\_CLADE\_CONTR | List of node (clade) contributions to the PD calculation |   | 1 |
| 260 | PD\_CLADE\_CONTR\_P | List of node (clade) contributions to the PD calculation, proportional to the entire tree |   | 1 |
| 261 | PD\_CLADE\_SCORE | List of PD scores for each node (clade), being the sum of all descendent branch lengths |   | 1 |







> ### PD clade loss ###

**Description:**   How much of the PD would be lost if a clade were to be removed? Calculates the clade PD below the last ancestral node in the neighbour set which would still be in the neighbour set.

**Subroutine:**   calc\_pd\_clade\_loss

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 262 | PD\_CLADE\_LOSS\_CONTR | List of the proportion of the PD score which would be lost if each clade were removed. |   | 1 |
| 263 | PD\_CLADE\_LOSS\_CONTR\_P | As per PD\_CLADE\_LOSS but proportional to the entire tree |   | 1 |
| 264 | PD\_CLADE\_LOSS\_SCORE | List of how much PD would be lost if each clade were removed. |   | 1 |







> ### PD clade loss (ancestral component) ###

**Description:**   How much of the PD clade loss is due to the ancestral branches? The score is zero when there is no ancestral loss.

**Subroutine:**   calc\_pd\_clade\_loss\_ancestral

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 265 | PD\_CLADE\_LOSS\_ANC | List of how much ancestral PE would be lost if each clade were removed.  The value is 0 when no ancestral PD is lost. |   | 1 |
| 266 | PD\_CLADE\_LOSS\_ANC\_P | List of the proportion of the clade's PD loss that is due to the ancestral branches. |   | 1 |







> ### PD-Endemism ###

**Description:**   Absolute endemism analogue of PE.  It is the sum of the branch lengths restricted to the neighbour sets.

**Subroutine:**   calc\_pd\_endemism

**Reference:**   See Faith (2004) Cons Biol.  http://dx.doi.org/10.1111/j.1523-1739.2004.00330.x


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 267 | PD\_ENDEMISM | Phylogenetic Diversity Endemism |   | 1 |
| 268 | PD\_ENDEMISM\_P | Phylogenetic Diversity Endemism, as a proportion of the whole tree |   | 1 |
| 269 | PD\_ENDEMISM\_WTS | Phylogenetic Diversity Endemism weights per node found only in the neighbour set |   | 1 |







> ### Phylogenetic Diversity ###

**Description:**   Phylogenetic diversity (PD) based on branch lengths back to the root of the tree.
Uses labels in both neighbourhoods.

**Subroutine:**   calc\_pd

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** | **Reference** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|:--------------|
| 270 | PD | Phylogenetic diversity |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \sum_{c \in C} L_c%.png' title='= \sum_{c \in C} L_c' /> where <img src='http://latex.codecogs.com/png.latex?C%.png' title='C' /> is the set of branches in the minimum spanning path joining the labels in both neighbour sets to the root of the tree,<img src='http://latex.codecogs.com/png.latex?c%.png' title='c' /> is a branch (a single segment between two nodes) in the spanning path <img src='http://latex.codecogs.com/png.latex?C%.png' title='C' /> , and <img src='http://latex.codecogs.com/png.latex?L_c%.png' title='L_c' /> is the length of branch <img src='http://latex.codecogs.com/png.latex?c%.png' title='c' /> .  | Faith (1992) Biol. Cons. http://dx.doi.org/10.1016/0006-3207(92)91201-3 |
| 271 | PD\_P | Phylogenetic diversity as a proportion of total tree length |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \frac { PD }{ \sum_{c \in C} L_c }%.png' title='= \frac { PD }{ \sum_{c \in C} L_c }' /> where terms are the same as for PD, but <img src='http://latex.codecogs.com/png.latex?c%.png' title='c' /> , <img src='http://latex.codecogs.com/png.latex?C%.png' title='C' /> and <img src='http://latex.codecogs.com/png.latex?L_c%.png' title='L_c' /> are calculated for all nodes in the tree.  |   |
| 272 | PD\_P\_per\_taxon | Phylogenetic diversity per taxon as a proportion of total tree length |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \frac { PD\_P }{ RICHNESS\_ALL }%.png' title='= \frac { PD\_P }{ RICHNESS\_ALL }' />  |   |
| 273 | PD\_per\_taxon | Phylogenetic diversity per taxon |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \frac { PD }{ RICHNESS\_ALL }%.png' title='= \frac { PD }{ RICHNESS\_ALL }' />  |   |







> ### Phylogenetic Diversity node list ###

**Description:**   Phylogenetic diversity (PD) nodes used.

**Subroutine:**   calc\_pd\_node\_list

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 274 | PD\_INCLUDED\_NODE\_LIST | List of tree nodes included in the PD calculations |   | 1 |







> ### Phylogenetic Diversity terminal node count ###

**Description:**   Number of terminal nodes in neighbour sets 1 and 2.

**Subroutine:**   calc\_pd\_terminal\_node\_count

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 275 | PD\_INCLUDED\_TERMINAL\_NODE\_COUNT | Count of tree terminal nodes included in the PD calculations |   | 1 |







> ### Phylogenetic Diversity terminal node list ###

**Description:**   Phylogenetic diversity (PD) terminal nodes used.

**Subroutine:**   calc\_pd\_terminal\_node\_list

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 276 | PD\_INCLUDED\_TERMINAL\_NODE\_LIST | List of tree terminal nodes included in the PD calculations |   | 1 |







> ### Taxonomic/phylogenetic distinctness ###

**Description:**   Taxonomic/phylogenetic distinctness and variation. THIS IS A BETA LEVEL IMPLEMENTATION.

**Subroutine:**   calc\_taxonomic\_distinctness

**Reference:**   Warwick & Clarke (1995) Mar Ecol Progr Ser. http://dx.doi.org/10.3354/meps129301 ; Clarke & Warwick (2001) Mar Ecol Progr Ser. http://dx.doi.org/10.3354/meps216265


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 277 | TD\_DENOMINATOR | Denominator from TD\_DISTINCTNESS calcs |   | 1 |
| 278 | TD\_DISTINCTNESS | Taxonomic distinctness |   | 1 |
| 279 | TD\_NUMERATOR | Numerator from TD\_DISTINCTNESS calcs |   | 1 |
| 280 | TD\_VARIATION | Variation of the taxonomic distinctness |   | 1 |







> ### Taxonomic/phylogenetic distinctness, binary weighted ###

**Description:**   Taxonomic/phylogenetic distinctness and variation using presence/absence weights.  THIS IS A BETA LEVEL IMPLEMENTATION.

**Subroutine:**   calc\_taxonomic\_distinctness\_binary

**Reference:**   Warwick & Clarke (1995) Mar Ecol Progr Ser. http://dx.doi.org/10.3354/meps129301 ; Clarke & Warwick (2001) Mar Ecol Progr Ser. http://dx.doi.org/10.3354/meps216265


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 281 | TDB\_DENOMINATOR | Denominator from TDB\_DISTINCTNESS |   | 1 |   |
| 282 | TDB\_DISTINCTNESS | Taxonomic distinctness, binary weighted |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \frac{\sum \sum_{i \neq j} \omega_{ij}}{s(s-1))}%.png' title='= \frac{\sum \sum_{i \neq j} \omega_{ij}}{s(s-1))}' /> where <img src='http://latex.codecogs.com/png.latex?\omega_{ij}%.png' title='\omega_{ij}' /> is the path length from label <img src='http://latex.codecogs.com/png.latex?i%.png' title='i' /> to the ancestor node shared with <img src='http://latex.codecogs.com/png.latex?j%.png' title='j' />  |
| 283 | TDB\_NUMERATOR | Numerator from TDB\_DISTINCTNESS |   | 1 |   |
| 284 | TDB\_VARIATION | Variation of the binary taxonomic distinctness |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \frac{\sum \sum_{i \neq j} \omega_{ij}^2}{s(s-1))} - \bar{\omega}^2%.png' title='= \frac{\sum \sum_{i \neq j} \omega_{ij}^2}{s(s-1))} - \bar{\omega}^2' /> where <img src='http://latex.codecogs.com/png.latex?\bar{\omega} = \frac{\sum \sum_{i \neq j} \omega_{ij}}{s(s-1))} \equiv TDB\_DISTINCTNESS%.png' title='\bar{\omega} = \frac{\sum \sum_{i \neq j} \omega_{ij}}{s(s-1))} \equiv TDB\_DISTINCTNESS' />  |


## Phylogenetic Indices (relative) ##




> ### Labels not on trimmed tree ###

**Description:**   Create a hash of the labels that are not on the trimmed tree

**Subroutine:**   calc\_labels\_not\_on\_trimmed\_tree

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 285 | PHYLO\_LABELS\_NOT\_ON\_TRIMMED\_TREE | A hash of labels that are not found on the tree after it has been trimmed to the basedata, across both neighbour sets |   | 1 |
| 286 | PHYLO\_LABELS\_NOT\_ON\_TRIMMED\_TREE\_N | Number of labels not on the trimmed tree |   | 1 |
| 287 | PHYLO\_LABELS\_NOT\_ON\_TRIMMED\_TREE\_P | Proportion of labels not on the trimmed tree |   | 1 |







> ### Labels on trimmed tree ###

**Description:**   Create a hash of the labels that are on the trimmed tree

**Subroutine:**   calc\_labels\_on\_trimmed\_tree

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 288 | PHYLO\_LABELS\_ON\_TRIMMED\_TREE | A hash of labels that are found on the tree after it has been trimmed to match the basedata, across both neighbour sets |   | 1 |







> ### Relative Phylogenetic Diversity, type 1 ###

**Description:**   Relative Phylogenetic Diversity (RPD).  The ratio of the tree's PD to a null model of PD evenly distributed across terminals and where ancestral nodes are collapsed to zero length.

**Subroutine:**   calc\_phylo\_rpd1

**Reference:**   Mishler et al. (2014) http://dx.doi.org/10.1038/ncomms5473


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 289 | PHYLO\_RPD1 | RPD1 |   | 1 |   |
| 290 | PHYLO\_RPD\_DIFF1 | How much more or less PD is there than expected, in original tree units. |   | 1 | <img src='http://latex.codecogs.com/png.latex?= tree\_length \times (PD\_P - PHYLO\_RPD\_NULL1)%.png' title='= tree\_length \times (PD\_P - PHYLO\_RPD\_NULL1)' />  |
| 291 | PHYLO\_RPD\_NULL1 | Null model score used as the denominator in the RPD1 calculations |   | 1 |   |







> ### Relative Phylogenetic Diversity, type 2 ###

**Description:**   Relative Phylogenetic Diversity (RPD), type 2.  The ratio of the tree's PD to a null model of PD evenly distributed across all nodes (all branches are of equal length).

**Subroutine:**   calc\_phylo\_rpd2

**Reference:**   Mishler et al. (2014) http://dx.doi.org/10.1038/ncomms5473


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 292 | PHYLO\_RPD2 | RPD2 |   | 1 |   |
| 293 | PHYLO\_RPD\_DIFF2 | How much more or less PD is there than expected, in original tree units. |   | 1 | <img src='http://latex.codecogs.com/png.latex?= tree\_length \times (PD\_P - PHYLO\_RPD\_NULL2)%.png' title='= tree\_length \times (PD\_P - PHYLO\_RPD\_NULL2)' />  |
| 294 | PHYLO\_RPD\_NULL2 | Null model score used as the denominator in the RPD2 calculations |   | 1 |   |







> ### Relative Phylogenetic Endemism, type 1 ###

**Description:**   Relative Phylogenetic Endemism (RPE).  The ratio of the tree's PE to a null model of PD evenly distributed across terminals, but with the same range per terminal and where ancestral nodes are of zero length (as per RPD1).

**Subroutine:**   calc\_phylo\_rpe1

**Reference:**   Mishler et al. (2014) http://dx.doi.org/10.1038/ncomms5473


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 295 | PHYLO\_RPE1 | Relative Phylogenetic Endemism score |   | 1 |   |
| 296 | PHYLO\_RPE\_DIFF1 | How much more or less PE is there than expected, in original tree units. |   | 1 | <img src='http://latex.codecogs.com/png.latex?= tree\_length \times (PE\_WE\_P - PHYLO\_RPE\_NULL1)%.png' title='= tree\_length \times (PE\_WE\_P - PHYLO\_RPE\_NULL1)' />  |
| 297 | PHYLO\_RPE\_NULL1 | Null score used as the denominator in the RPE calculations |   | 1 |   |







> ### Relative Phylogenetic Endemism, type 2 ###

**Description:**   Relative Phylogenetic Endemism (RPE).  The ratio of the tree's PE to a null model where PE is calculated using a tree where all branches are of equal length.

**Subroutine:**   calc\_phylo\_rpe2

**Reference:**   Mishler et al. (2014) http://dx.doi.org/10.1038/ncomms5473


| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 298 | PHYLO\_RPE2 | Relative Phylogenetic Endemism score, type 2 |   | 1 |   |
| 299 | PHYLO\_RPE\_DIFF2 | How much more or less PE is there than expected, in original tree units. |   | 1 | <img src='http://latex.codecogs.com/png.latex?= tree\_length \times (PE\_WE\_P - PHYLO\_RPE\_NULL1)%.png' title='= tree\_length \times (PE\_WE\_P - PHYLO\_RPE\_NULL1)' />  |
| 300 | PHYLO\_RPE\_NULL2 | Null score used as the denominator in the RPE2 calculations |   | 1 |   |


## Phylogenetic Turnover ##




> ### Phylo Jaccard ###

**Description:**   Jaccard phylogenetic dissimilarity between two sets of taxa, represented by spanning sets of branches


**Subroutine:**   calc\_phylo\_jaccard

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 301 | PHYLO\_JACCARD | Phylo Jaccard score | cluster metric | 1 | <img src='http://latex.codecogs.com/png.latex?= 1 - (A / (A + B + C))%.png' title='= 1 - (A / (A + B + C))' /> where A is the length of shared branches, and B and C are the length of branches found only in neighbour sets 1 and 2  |







> ### Phylo S2 ###

**Description:**   S2 phylogenetic dissimilarity between two sets of taxa, represented by spanning sets of branches


**Subroutine:**   calc\_phylo\_s2

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 302 | PHYLO\_S2 | Phylo S2 score | cluster metric | 1 | <img src='http://latex.codecogs.com/png.latex?= 1 - (A / (A + min (B, C)))%.png' title='= 1 - (A / (A + min (B, C)))' /> where A is the length of shared branches, and B and C are the length of branches found only in neighbour sets 1 and 2  |







> ### Phylo Sorenson ###

**Description:**   Sorenson phylogenetic dissimilarity between two sets of taxa, represented by spanning sets of branches


**Subroutine:**   calc\_phylo\_sorenson

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 303 | PHYLO\_SORENSON | Phylo Sorenson score | cluster metric | 1 | <img src='http://latex.codecogs.com/png.latex?1 - (2A / (2A + B + C))%.png' title='1 - (2A / (2A + B + C))' /> where A is the length of shared branches, and B and C are the length of branches found only in neighbour sets 1 and 2  |







> ### Phylogenetic ABC ###

**Description:**   Calculate the shared and not shared branch lengths between two sets of labels

**Subroutine:**   calc\_phylo\_abc

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 304 | PHYLO\_A | Length of branches shared by labels in nbr sets 1 and 2 |   | 1 |
| 305 | PHYLO\_ABC | Length of all branches associated with labels in nbr sets 1 and 2 |   | 1 |
| 306 | PHYLO\_B | Length of branches unique to labels in nbr set 1 |   | 1 |
| 307 | PHYLO\_C | Length of branches unique to labels in nbr set 2 |   | 1 |


## Rarity ##




> ### Rarity central ###

**Description:**   Calculate rarity for species only in neighbour set 1, but with local sample counts calculated from both neighbour sets.
Uses the same algorithm as the endemism indices but weights by sample counts instead of by groups occupied.

**Subroutine:**   calc\_rarity\_central

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 308 | RAREC\_CWE | Corrected weighted rarity |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \frac{RAREC\_WE}{RAREC\_RICHNESS}%.png' title='= \frac{RAREC\_WE}{RAREC\_RICHNESS}' />  |
| 309 | RAREC\_RICHNESS | Richness used in RAREC\_CWE (same as index RICHNESS\_SET1). |   | 1 |   |
| 310 | RAREC\_WE | Weighted rarity |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \sum_{t \in T} \frac {s_t} {S_t}%.png' title='= \sum_{t \in T} \frac {s_t} {S_t}' /> where <img src='http://latex.codecogs.com/png.latex?t%.png' title='t' /> is a label (taxon) in the set of labels (taxa) <img src='http://latex.codecogs.com/png.latex?T%.png' title='T' /> across neighbour set 1, <img src='http://latex.codecogs.com/png.latex?s_t%.png' title='s_t' /> is sum of the sample counts for <img src='http://latex.codecogs.com/png.latex?t%.png' title='t' /> across the elements in neighbour sets 1 & 2 (its value in list ABC3\_LABELS\_ALL), and <img src='http://latex.codecogs.com/png.latex?S_t%.png' title='S_t' /> is the total number of samples across the data set for label <img src='http://latex.codecogs.com/png.latex?t%.png' title='t' /> (unless the total sample count is specified at import).  |







> ### Rarity central lists ###

**Description:**   Lists used in rarity central calculations

**Subroutine:**   calc\_rarity\_central\_lists

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 311 | RAREC\_RANGELIST | List of ranges for each label used in the rarity central calculations |   | 1 |
| 312 | RAREC\_WTLIST | List of weights for each label used in therarity central calculations |   | 1 |







> ### Rarity whole ###

**Description:**   Calculate rarity using all species in both neighbour sets.
Uses the same algorithm as the endemism indices but weights
by sample counts instead of by groups occupied.


**Subroutine:**   calc\_rarity\_whole

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 313 | RAREW\_CWE | Corrected weighted rarity |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \frac{RAREW\_WE}{RAREW\_RICHNESS}%.png' title='= \frac{RAREW\_WE}{RAREW\_RICHNESS}' />  |
| 314 | RAREW\_RICHNESS | Richness used in RAREW\_CWE (same as index RICHNESS\_ALL). |   | 1 |   |
| 315 | RAREW\_WE | Weighted rarity |   | 1 | <img src='http://latex.codecogs.com/png.latex?= \sum_{t \in T} \frac {s_t} {S_t}%.png' title='= \sum_{t \in T} \frac {s_t} {S_t}' /> where <img src='http://latex.codecogs.com/png.latex?t%.png' title='t' /> is a label (taxon) in the set of labels (taxa) <img src='http://latex.codecogs.com/png.latex?T%.png' title='T' /> across both neighbour sets, <img src='http://latex.codecogs.com/png.latex?s_t%.png' title='s_t' /> is sum of the sample counts for <img src='http://latex.codecogs.com/png.latex?t%.png' title='t' /> across the elements in neighbour sets 1 & 2 (its value in list ABC3\_LABELS\_ALL), and <img src='http://latex.codecogs.com/png.latex?S_t%.png' title='S_t' /> is the total number of samples across the data set for label <img src='http://latex.codecogs.com/png.latex?t%.png' title='t' /> (unless the total sample count is specified at import).  |







> ### Rarity whole lists ###

**Description:**   Lists used in rarity whole calculations

**Subroutine:**   calc\_rarity\_whole\_lists

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 316 | RAREW\_RANGELIST | List of ranges for each label used in the rarity whole calculations |   | 1 |
| 317 | RAREW\_WTLIST | List of weights for each label used in therarity whole calculations |   | 1 |


## Taxonomic Dissimilarity and Comparison ##




> ### Beta diversity ###

**Description:**   Beta diversity between neighbour sets 1 and 2.


**Subroutine:**   calc\_beta\_diversity

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 318 | BETA\_2 | The other beta | cluster metric | 1 | <img src='http://latex.codecogs.com/png.latex?= \frac{A + B + C}{max((A+B), (A+C))} - 1%.png' title='= \frac{A + B + C}{max((A+B), (A+C))} - 1' /> where <img src='http://latex.codecogs.com/png.latex?A%.png' title='A' /> is the count of labels found in both neighbour sets, <img src='http://latex.codecogs.com/png.latex?B%.png' title='B' /> is the count unique to neighbour set 1, and <img src='http://latex.codecogs.com/png.latex?C%.png' title='C' /> is the count unique to neighbour set 2. Use the [Label counts](#Label_counts.md) calculation to derive these directly.  |







> ### Bray-Curtis non-metric ###

**Description:**   Bray-Curtis dissimilarity between two sets of labels.
Reduces to the Sorenson metric for binary data (where sample counts are 1 or 0).

**Subroutine:**   calc\_bray\_curtis

**Formula:**
> <img src='http://latex.codecogs.com/png.latex?= 1 - \frac{2W}{A + B}%.png' title='= 1 - \frac{2W}{A + B}' /> where <img src='http://latex.codecogs.com/png.latex?A%.png' title='A' /> is the sum of the sample counts in neighbour set 1, <img src='http://latex.codecogs.com/png.latex?B%.png' title='B' /> is the sum of sample counts in neighbour set 2, and <img src='http://latex.codecogs.com/png.latex?W=\sum^n_{i=1} min(sample\_count\_label_{i_{set1}},sample\_count\_label_{i_{set2}})%.png' title='W=\sum^n_{i=1} min(sample\_count\_label_{i_{set1}},sample\_count\_label_{i_{set2}})' /> (meaning it sums the minimum of the sample counts for each of the <img src='http://latex.codecogs.com/png.latex?n%.png' title='n' /> labels across the two neighbour sets),

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 319 | BC\_A | The A factor used in calculations (see formula) |   | 1 |
| 320 | BC\_B | The B factor used in calculations (see formula) |   | 1 |
| 321 | BC\_W | The W factor used in calculations (see formula) |   | 1 |
| 322 | BRAY\_CURTIS | Bray Curtis dissimilarity | cluster metric | 1 |







> ### Bray-Curtis non-metric, group count normalised ###

**Description:**   Bray-Curtis dissimilarity between two neighbourhoods,
where the counts in each neighbourhood are divided
by the number of groups in each neighbourhood to correct
for unbalanced sizes.


**Subroutine:**   calc\_bray\_curtis\_norm\_by\_gp\_counts

**Formula:**
> <img src='http://latex.codecogs.com/png.latex?= 1 - \frac{2W}{A + B}%.png' title='= 1 - \frac{2W}{A + B}' /> where <img src='http://latex.codecogs.com/png.latex?A%.png' title='A' /> is the sum of the sample counts in neighbour set 1 normalised (divided) by the number of groups, <img src='http://latex.codecogs.com/png.latex?B%.png' title='B' /> is the sum of the sample counts in neighbour set 2 normalised by the number of groups, and <img src='http://latex.codecogs.com/png.latex?W = \sum^n_{i=1} min(sample\_count\_label_{i_{set1}},sample\_count\_label_{i_{set2}})%.png' title='W = \sum^n_{i=1} min(sample\_count\_label_{i_{set1}},sample\_count\_label_{i_{set2}})' /> (meaning it sums the minimum of the normalised sample counts for each of the <img src='http://latex.codecogs.com/png.latex?n%.png' title='n' /> labels across the two neighbour sets),

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 323 | BCN\_A | The A factor used in calculations (see formula) |   | 1 |
| 324 | BCN\_B | The B factor used in calculations (see formula) |   | 1 |
| 325 | BCN\_W | The W factor used in calculations (see formula) |   | 1 |
| 326 | BRAY\_CURTIS\_NORM | Bray Curtis dissimilarity normalised by groups | cluster metric | 1 |







> ### Jaccard ###

**Description:**   Jaccard dissimilarity between the labels in neighbour sets 1 and 2.

**Subroutine:**   calc\_jaccard

**Formula:**
> <img src='http://latex.codecogs.com/png.latex?= 1 - \frac{A}{A + B + C}%.png' title='= 1 - \frac{A}{A + B + C}' /> where <img src='http://latex.codecogs.com/png.latex?A%.png' title='A' /> is the count of labels found in both neighbour sets, <img src='http://latex.codecogs.com/png.latex?B%.png' title='B' /> is the count unique to neighbour set 1, and <img src='http://latex.codecogs.com/png.latex?C%.png' title='C' /> is the count unique to neighbour set 2. Use the [Label counts](#Label_counts.md) calculation to derive these directly.

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 327 | JACCARD | Jaccard value, 0 is identical, 1 is completely dissimilar | cluster metric | 1 |







> ### Kulczynski 2 ###

**Description:**   Kulczynski 2 dissimilarity between two sets of labels.


**Subroutine:**   calc\_kulczynski2

**Formula:**
> <img src='http://latex.codecogs.com/png.latex?= 1 - 0.5 * (\frac{A}{A + B} + \frac{A}{A + C})%.png' title='= 1 - 0.5 * (\frac{A}{A + B} + \frac{A}{A + C})' /> where <img src='http://latex.codecogs.com/png.latex?A%.png' title='A' /> is the count of labels found in both neighbour sets, <img src='http://latex.codecogs.com/png.latex?B%.png' title='B' /> is the count unique to neighbour set 1, and <img src='http://latex.codecogs.com/png.latex?C%.png' title='C' /> is the count unique to neighbour set 2. Use the [Label counts](#Label_counts.md) calculation to derive these directly.

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 328 | KULCZYNSKI2 | Kulczynski 2 index | cluster metric | 1 |







> ### Nestedness-resultant ###

**Description:**   Nestedness-resultant index between the labels in neighbour sets 1 and 2.

**Subroutine:**   calc\_nestedness\_resultant

**Reference:**   Baselga (2010) Glob Ecol Biogeog.  http://dx.doi.org/10.1111/j.1466-8238.2009.00490.x


**Formula:**
> <img src='http://latex.codecogs.com/png.latex?=\frac{ \left | B - C \right | }{ 2A + B + C } \times \frac { A }{ A + min (B, C) }= SORENSON - S2%.png' title='=\frac{ \left | B - C \right | }{ 2A + B + C } \times \frac { A }{ A + min (B, C) }= SORENSON - S2' /> where <img src='http://latex.codecogs.com/png.latex?A%.png' title='A' /> is the count of labels found in both neighbour sets, <img src='http://latex.codecogs.com/png.latex?B%.png' title='B' /> is the count unique to neighbour set 1, and <img src='http://latex.codecogs.com/png.latex?C%.png' title='C' /> is the count unique to neighbour set 2. Use the [Label counts](#Label_counts.md) calculation to derive these directly.

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 329 | NEST\_RESULTANT | Nestedness-resultant index | cluster metric | 1 |







> ### Rao's quadratic entropy, taxonomically weighted ###

**Description:**   Calculate Rao's quadratic entropy for a taxonomic weights scheme.
Should collapse to be the Simpson index for presence/absence data.

**Subroutine:**   calc\_tx\_rao\_qe

**Formula:**
> <img src='http://latex.codecogs.com/png.latex?= \sum_{i \in L} \sum_{j \in L} d_{ij} p_i p_j%.png' title='= \sum_{i \in L} \sum_{j \in L} d_{ij} p_i p_j' /> where <img src='http://latex.codecogs.com/png.latex?p_i%.png' title='p_i' /> and <img src='http://latex.codecogs.com/png.latex?p_j%.png' title='p_j' /> are the sample counts for the i'th and j'th labels, <img src='http://latex.codecogs.com/png.latex?d_{ij}%.png' title='d_{ij}' /> is a value of zero if <img src='http://latex.codecogs.com/png.latex?i = j%.png' title='i = j' /> , and a value of 1 otherwise. <img src='http://latex.codecogs.com/png.latex?L%.png' title='L' /> is the set of labels across both neighbour sets.

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 330 | TX\_RAO\_QE | Taxonomically weighted quadratic entropy |   | 1 |
| 331 | TX\_RAO\_TLABELS | List of labels and values used in the TX\_RAO\_QE calculations |   | 1 |
| 332 | TX\_RAO\_TN | Count of comparisons used to calculate TX\_RAO\_QE |   | 1 |







> ### S2 ###

**Description:**   S2 dissimilarity between two sets of labels


**Subroutine:**   calc\_s2

**Reference:**   Lennon et al. (2001) J Animal Ecol.  http://dx.doi.org/10.1046/j.0021-8790.2001.00563.x


**Formula:**
> <img src='http://latex.codecogs.com/png.latex?= 1 - \frac{A}{A + min(B, C)}%.png' title='= 1 - \frac{A}{A + min(B, C)}' /> where <img src='http://latex.codecogs.com/png.latex?A%.png' title='A' /> is the count of labels found in both neighbour sets, <img src='http://latex.codecogs.com/png.latex?B%.png' title='B' /> is the count unique to neighbour set 1, and <img src='http://latex.codecogs.com/png.latex?C%.png' title='C' /> is the count unique to neighbour set 2. Use the [Label counts](#Label_counts.md) calculation to derive these directly.

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 333 | S2 | S2 dissimilarity index | cluster metric | 1 |







> ### Simpson and Shannon ###

**Description:**   Simpson and Shannon diversity metrics using samples from all neighbourhoods.


**Subroutine:**   calc\_simpson\_shannon

**Formula:**
> For each index formula, <img src='http://latex.codecogs.com/png.latex?p_i%.png' title='p_i' /> is the number of samples of the i'th label as a proportion of the total number of samples <img src='http://latex.codecogs.com/png.latex?n%.png' title='n' /> in the neighbourhoods.

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** | **Formula** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|:------------|
| 334 | SHANNON\_E | Shannon's evenness (H / HMAX) |   | 1 | <img src='http://latex.codecogs.com/png.latex?Evenness = \frac{H}{HMAX}%.png' title='Evenness = \frac{H}{HMAX}' />  |
| 335 | SHANNON\_H | Shannon's H |   | 1 | <img src='http://latex.codecogs.com/png.latex?H = - \sum^n_{i=1} (p_i \cdot ln (p_i))%.png' title='H = - \sum^n_{i=1} (p_i \cdot ln (p_i))' />  |
| 336 | SHANNON\_HMAX | maximum possible value of Shannon's H |   | 1 | <img src='http://latex.codecogs.com/png.latex?HMAX = ln(richness)%.png' title='HMAX = ln(richness)' />  |
| 337 | SIMPSON\_D | Simpson's D. A score of zero is more similar. |   | 1 | <img src='http://latex.codecogs.com/png.latex?D = 1 - \sum^n_{i=1} p_i^2%.png' title='D = 1 - \sum^n_{i=1} p_i^2' />  |







> ### Sorenson ###

**Description:**   Sorenson dissimilarity between two sets of labels.
It is the complement of the (unimplemented) Czechanowski index, and numerically the same as Whittaker's beta.

**Subroutine:**   calc\_sorenson

**Formula:**
> <img src='http://latex.codecogs.com/png.latex?= 1 - \frac{2A}{2A + B + C}%.png' title='= 1 - \frac{2A}{2A + B + C}' /> where <img src='http://latex.codecogs.com/png.latex?A%.png' title='A' /> is the count of labels found in both neighbour sets, <img src='http://latex.codecogs.com/png.latex?B%.png' title='B' /> is the count unique to neighbour set 1, and <img src='http://latex.codecogs.com/png.latex?C%.png' title='C' /> is the count unique to neighbour set 2. Use the [Label counts](#Label_counts.md) calculation to derive these directly.

| **Index #** | **Index** | **Index description** | **Valid cluster metric?** | **Minimum number of neighbour sets** |
|:------------|:----------|:----------------------|:--------------------------|:-------------------------------------|
| 338 | SORENSON | Sorenson index | cluster metric | 1 |


<img src='http://www.codecogs.com/images/poweredbycc.gif' alt='Powered by CodeCogs' border='0' width='102' height='34' />
http://www.codecogs.com