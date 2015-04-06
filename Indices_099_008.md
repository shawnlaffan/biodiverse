---
layout: recipe
title: Indices_test
---

# Indices available in Biodiverse 
_Generated GMT Sun Apr  5 11:09:41 2015 using build_indices_table.pl, Biodiverse version 0.99_008._


This is a listing of the indices available in Biodiverse,
ordered by the calculations used to generate them.
It is generated from the system metadata and contains all the 
information visible in the GUI, plus some additional details.

Most of the headings are self-explanatory.  For the others:
  * The *Subroutine* is the name of the subroutine used to call the function if you are using Biodiverse through a script.  
  * The *Index* is the name of the index in the SPATIAL_RESULTS list, or if it is its own list then this will be its name.  These lists can contain a variety of values, but are usually lists of labels with some value, for example the weights used in an endemism calculation.  The names of such lists typically end in "LIST", "ARRAY", "HASH", "LABELS" or "STATS". 
  * *Valid cluster metric* is whether or not the index can be used as a clustering metric.  A blank value means it cannot.
  * The *Minimum number of neighbour sets* dictates whether or not a calculation or index will be run.  If you specify only one neighbour set then all those calculations that require two sets will be dropped from the analysis.  (This is always the case for calculations applied to cluster nodes as there is only one neighbour set, defined by the set of groups linked to the terminal nodes below a cluster node).  Note that many of the calculations lump neighbour sets 1 and 2 together.  See the [SpatialConditions](SpatialConditions.md) page for more details on neighbour sets.

Note that calculations can provide different numbers of indices depending on the nature of the BaseData set used.
This currently applies to the hierarchically partitioned endemism calculations (both [central](#Endemism_central_hierarchical_partition) and [whole](#Endemism_whole_hierarchical_partition)) and [hierarchical labels](#Hierarchical_Labels).


**Indices available in Biodiverse:**
  * [Element Properties](#element-properties)
    * [Group property Gi* statistics](#group-property-gi-statistics)
    * [Group property hashes](#group-property-hashes)
    * [Group property data](#group-property-data)
    * [Group property quantiles](#group-property-quantiles)
    * [Group property summary stats](#group-property-summary-stats)
    * [Label property data](#label-property-data)
    * [Label property Gi* statistics](#label-property-gi-statistics)
    * [Label property Gi* statistics (local range weighted)](#label-property-gi-statistics-local-range-weighted)
    * [Label property hashes](#label-property-hashes)
    * [Label property hashes (local range weighted)](#label-property-hashes-local-range-weighted)
    * [Label property lists](#label-property-lists)
    * [Label property quantiles](#label-property-quantiles)
    * [Label property quantiles (local range weighted)](#label-property-quantiles-local-range-weighted)
    * [Label property summary stats](#label-property-summary-stats)
    * [Label property summary stats (local range weighted)](#label-property-summary-stats-local-range-weighted)
  * [Endemism](#endemism)
    * [Absolute endemism](#absolute-endemism)
    * [Absolute endemism lists](#absolute-endemism-lists)
    * [Endemism central](#endemism-central)
    * [Endemism central hierarchical partition](#endemism-central-hierarchical-partition)
    * [Endemism central lists](#endemism-central-lists)
    * [Endemism central normalised](#endemism-central-normalised)
    * [Endemism whole](#endemism-whole)
    * [Endemism whole hierarchical partition](#endemism-whole-hierarchical-partition)
    * [Endemism whole lists](#endemism-whole-lists)
    * [Endemism whole normalised](#endemism-whole-normalised)
  * [Hierarchical Labels](#hierarchical-labels)
    * [Ratios of hierarchical labels](#ratios-of-hierarchical-labels)
  * [Inter-event Interval Statistics](#inter-event-interval-statistics)
    * [Inter-event interval statistics data](#inter-event-interval-statistics-data)
    * [Inter-event interval statistics](#inter-event-interval-statistics)
  * [Lists and Counts](#lists-and-counts)
    * [Label counts](#label-counts)
    * [Label counts not in sample](#label-counts-not-in-sample)
    * [Element lists](#element-lists)
    * [Element counts](#element-counts)
    * [Rank relative sample counts per label](#rank-relative-sample-counts-per-label)
    * [Local range lists](#local-range-lists)
    * [Local range summary statistics](#local-range-summary-statistics)
    * [Sample count lists](#sample-count-lists)
    * [Sample count quantiles](#sample-count-quantiles)
    * [Sample count summary stats](#sample-count-summary-stats)
    * [Redundancy](#redundancy)
    * [Richness](#richness)
  * [Matrix](#matrix)
    * [Compare dissimilarity matrix values](#compare-dissimilarity-matrix-values)
    * [Matrix statistics](#matrix-statistics)
    * [Rao's quadratic entropy, matrix weighted](#raos-quadratic-entropy-matrix-weighted)
  * [Numeric Labels](#numeric-labels)
    * [Numeric labels Gi* statistic](#numeric-labels-gi-statistic)
    * [Numeric label data](#numeric-label-data)
    * [Numeric label dissimilarity](#numeric-label-dissimilarity)
    * [Numeric label harmonic and geometric means](#numeric-label-harmonic-and-geometric-means)
    * [Numeric label quantiles](#numeric-label-quantiles)
    * [Numeric label statistics](#numeric-label-statistics)
  * [PhyloCom Indices](#phylocom-indices)
    * [NRI and NTI, unweighted](#nri-and-nti-unweighted)
    * [NRI and NTI, local range weighted](#nri-and-nti-local-range-weighted)
    * [NRI and NTI, abundance weighted](#nri-and-nti-abundance-weighted)
    * [NRI and NTI expected values](#nri-and-nti-expected-values)
    * [Phylogenetic and Nearest taxon distances, unweighted](#phylogenetic-and-nearest-taxon-distances-unweighted)
    * [Phylogenetic and Nearest taxon distances, local range weighted](#phylogenetic-and-nearest-taxon-distances-local-range-weighted)
    * [Phylogenetic and Nearest taxon distances, abundance weighted](#phylogenetic-and-nearest-taxon-distances-abundance-weighted)
  * [Phylogenetic Endemism](#phylogenetic-endemism)
    * [PD-Endemism](#pd-endemism)
    * [Phylogenetic Endemism](#phylogenetic-endemism)
    * [Phylogenetic Endemism central](#phylogenetic-endemism-central)
    * [Corrected weighted phylogenetic endemism, central variant](#corrected-weighted-phylogenetic-endemism-central-variant)
    * [Phylogenetic Endemism central lists](#phylogenetic-endemism-central-lists)
    * [PE clade contributions](#pe-clade-contributions)
    * [PE clade loss](#pe-clade-loss)
    * [PE clade loss (ancestral component)](#pe-clade-loss-ancestral-component)
    * [Phylogenetic Endemism lists](#phylogenetic-endemism-lists)
    * [Phylogenetic Endemism single](#phylogenetic-endemism-single)
    * [Corrected weighted phylogenetic endemism](#corrected-weighted-phylogenetic-endemism)
    * [Corrected weighted phylogenetic rarity](#corrected-weighted-phylogenetic-rarity)
  * [Phylogenetic Indices](#phylogenetic-indices)
    * [Count labels on tree](#count-labels-on-tree)
    * [Labels not on tree](#labels-not-on-tree)
    * [Labels on tree](#labels-on-tree)
    * [Phylogenetic Diversity](#phylogenetic-diversity)
    * [PD clade contributions](#pd-clade-contributions)
    * [PD clade loss](#pd-clade-loss)
    * [PD clade loss (ancestral component)](#pd-clade-loss-ancestral-component)
    * [Phylogenetic Diversity node list](#phylogenetic-diversity-node-list)
    * [Phylogenetic Diversity terminal node count](#phylogenetic-diversity-terminal-node-count)
    * [Phylogenetic Diversity terminal node list](#phylogenetic-diversity-terminal-node-list)
    * [Evolutionary distinctiveness](#evolutionary-distinctiveness)
    * [Evolutionary distinctiveness per site](#evolutionary-distinctiveness-per-site)
    * [Evolutionary distinctiveness per terminal taxon per site](#evolutionary-distinctiveness-per-terminal-taxon-per-site)
    * [Taxonomic/phylogenetic distinctness](#taxonomicphylogenetic-distinctness)
    * [Taxonomic/phylogenetic distinctness, binary weighted](#taxonomicphylogenetic-distinctness-binary-weighted)
  * [Phylogenetic Indices (relative)](#phylogenetic-indices-relative)
    * [Labels not on trimmed tree](#labels-not-on-trimmed-tree)
    * [Labels on trimmed tree](#labels-on-trimmed-tree)
    * [Relative Phylogenetic Diversity, type 1](#relative-phylogenetic-diversity-type-)
    * [Relative Phylogenetic Diversity, type 2](#relative-phylogenetic-diversity-type-)
    * [Relative Phylogenetic Endemism, type 1](#relative-phylogenetic-endemism-type-)
    * [Relative Phylogenetic Endemism, type 2](#relative-phylogenetic-endemism-type-)
  * [Phylogenetic Turnover](#phylogenetic-turnover)
    * [Phylogenetic ABC](#phylogenetic-abc)
    * [Phylo Jaccard](#phylo-jaccard)
    * [Phylo S2](#phylo-s)
    * [Phylo Sorenson](#phylo-sorenson)
  * [Rarity](#rarity)
    * [Rarity central](#rarity-central)
    * [Rarity central lists](#rarity-central-lists)
    * [Rarity whole](#rarity-whole)
    * [Rarity whole lists](#rarity-whole-lists)
  * [Taxonomic Dissimilarity and Comparison](#taxonomic-dissimilarity-and-comparison)
    * [Beta diversity](#beta-diversity)
    * [Bray-Curtis non-metric](#bray-curtis-non-metric)
    * [Bray-Curtis non-metric, group count normalised](#bray-curtis-non-metric-group-count-normalised)
    * [Jaccard](#jaccard)
    * [Kulczynski 2](#kulczynski-)
    * [Nestedness-resultant](#nestedness-resultant)
    * [S2](#s)
    * [Simpson and Shannon](#simpson-and-shannon)
    * [Sorenson](#sorenson)
    * [Rao's quadratic entropy, taxonomically weighted](#raos-quadratic-entropy-taxonomically-weighted)

## Element Properties ##
 
 

 
### Group property Gi* statistics ###
 
**Description:**   List of Getis-Ord Gi* statistics for each group property across both neighbour sets

**Subroutine:**   calc_gpprop_gistar

**Reference:**   Getis and Ord (1992) Geographical Analysis. http://dx.doi.org/10.1111/j.1538-4632.1992.tb00261.x
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 1 | GPPROP_GISTAR_LIST | List of Gi* scores |   | 1 |



 
 

 
### Group property data ###
 
**Description:**   Lists of the groups and their property values used in the group properties calculations

**Subroutine:**   calc_gpprop_lists

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 2 | GPPROP_STATS_EXAMPLE_GPROP1_DATA | List of values for property EXAMPLE_GPROP1 |   | 1 |
| 3 | GPPROP_STATS_EXAMPLE_GPROP2_DATA | List of values for property EXAMPLE_GPROP2 |   | 1 |



 
 

 
### Group property hashes ###
 
**Description:**   Hashes of the groups and their property values used in the group properties calculations. Hash keys are the property values, hash values are the property value frequencies.

**Subroutine:**   calc_gpprop_hashes

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 4 | GPPROP_STATS_EXAMPLE_GPROP1_HASH | Hash of values for property EXAMPLE_GPROP1 |   | 1 |
| 5 | GPPROP_STATS_EXAMPLE_GPROP2_HASH | Hash of values for property EXAMPLE_GPROP2 |   | 1 |



 
 

 
### Group property quantiles ###
 
**Description:**   Quantiles for each group property across both neighbour sets

**Subroutine:**   calc_gpprop_quantiles

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 6 | GPPROP_QUANTILE_LIST | List of quantiles for the label properties (05 10 20 30 40 50 60 70 80 90 95) |   | 1 |



 
 

 
### Group property summary stats ###
 
**Description:**   List of summary statistics for each group property across both neighbour sets

**Subroutine:**   calc_gpprop_stats

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 7 | GPPROP_STATS_LIST | List of summary statistics (count mean min max median sum sd iqr) |   | 1 |



 
 

 
### Label property Gi* statistics ###
 
**Description:**   List of Getis-Ord Gi* statistic for each label property across both neighbour sets

**Subroutine:**   calc_lbprop_gistar

**Reference:**   Getis and Ord (1992) Geographical Analysis. http://dx.doi.org/10.1111/j.1538-4632.1992.tb00261.x
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 8 | LBPROP_GISTAR_LIST | List of Gi* scores |   | 1 |



 
 

 
### Label property Gi* statistics (local range weighted) ###
 
**Description:**   List of Getis-Ord Gi* statistic for each label property across both neighbour sets (local range weighted)

**Subroutine:**   calc_lbprop_gistar_abc2

**Reference:**   Getis and Ord (1992) Geographical Analysis. http://dx.doi.org/10.1111/j.1538-4632.1992.tb00261.x
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 9 | LBPROP_GISTAR_LIST_ABC2 | List of Gi* scores |   | 1 |



 
 

 
### Label property data ###
 
**Description:**   Lists of the labels and their property values used in the label properties calculations

**Subroutine:**   calc_lbprop_data

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 10 | LBPROP_STATS_EXAMPLE_PROP1_DATA | List of data for property EXAMPLE_PROP1 |   | 1 |
| 11 | LBPROP_STATS_EXAMPLE_PROP2_DATA | List of data for property EXAMPLE_PROP2 |   | 1 |



 
 

 
### Label property hashes ###
 
**Description:**   Hashes of the labels and their property values used in the label properties calculations. Hash keys are the property values, hash values are the property value frequencies.

**Subroutine:**   calc_lbprop_hashes

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 12 | LBPROP_STATS_EXAMPLE_PROP1_HASH | Hash of values for property EXAMPLE_PROP1 |   | 1 |
| 13 | LBPROP_STATS_EXAMPLE_PROP2_HASH | Hash of values for property EXAMPLE_PROP2 |   | 1 |



 
 

 
### Label property hashes (local range weighted) ###
 
**Description:**   Hashes of the labels and their property values
used in the local range weighted label properties calculations.
Hash keys are the property values,
hash values are the property value frequencies.


**Subroutine:**   calc_lbprop_hashes_abc2

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 14 | LBPROP_STATS_EXAMPLE_PROP1_HASH2 | Hash of values for property EXAMPLE_PROP1 |   | 1 |
| 15 | LBPROP_STATS_EXAMPLE_PROP2_HASH2 | Hash of values for property EXAMPLE_PROP2 |   | 1 |



 
 

 
### Label property lists ###
 
**Description:**   Lists of the labels and their property values within the neighbour sets

**Subroutine:**   calc_lbprop_lists

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 16 | LBPROP_LIST_EXAMPLE_PROP1 | List of data for property EXAMPLE_PROP1 |   | 1 |
| 17 | LBPROP_LIST_EXAMPLE_PROP2 | List of data for property EXAMPLE_PROP2 |   | 1 |



 
 

 
### Label property quantiles ###
 
**Description:**   List of quantiles for each label property across both neighbour sets


**Subroutine:**   calc_lbprop_quantiles

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 18 | LBPROP_QUANTILES | List of quantiles for the label properties: (05 10 20 30 40 50 60 70 80 90 95) |   | 1 |



 
 

 
### Label property quantiles (local range weighted) ###
 
**Description:**   List of quantiles for each label property across both neighbour sets (local range weighted)


**Subroutine:**   calc_lbprop_quantiles_abc2

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 19 | LBPROP_QUANTILES_ABC2 | List of quantiles for the label properties: (05 10 20 30 40 50 60 70 80 90 95) |   | 1 |



 
 

 
### Label property summary stats ###
 
**Description:**   List of summary statistics for each label property across both neighbour sets


**Subroutine:**   calc_lbprop_stats

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 20 | LBPROP_STATS | List of summary statistics (count mean min max median sum skewness kurtosis sd iqr) |   | 1 |



 
 

 
### Label property summary stats (local range weighted) ###
 
**Description:**   List of summary statistics for each label property across both neighbour sets, weighted by local ranges


**Subroutine:**   calc_lbprop_stats_abc2

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 21 | LBPROP_STATS_ABC2 | List of summary statistics (count mean min max median sum skewness kurtosis sd iqr) |   | 1 |


## Endemism ##
 
 

 
### Absolute endemism ###
 
**Description:**   Absolute endemism scores.


**Subroutine:**   calc_endemism_absolute

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 22 | END_ABS1 | Count of labels entirely endemic to neighbour set 1 |   | 1 |
| 23 | END_ABS1_P | Proportion of labels entirely endemic to neighbour set 1 |   | 1 |
| 24 | END_ABS2 | Count of labels entirely endemic to neighbour set 2 |   | 1 |
| 25 | END_ABS2_P | Proportion of labels entirely endemic to neighbour set 2 |   | 1 |
| 26 | END_ABS_ALL | Count of labels entirely endemic to neighbour sets 1 and 2 combined |   | 1 |
| 27 | END_ABS_ALL_P | Proportion of labels entirely endemic to neighbour sets 1 and 2 combined |   | 1 |



 
 

 
### Absolute endemism lists ###
 
**Description:**   Lists underlying the absolute endemism scores.


**Subroutine:**   calc_endemism_absolute_lists

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 28 | END_ABS1_LIST | List of labels entirely endemic to neighbour set 1 |   | 1 |
| 29 | END_ABS2_LIST | List of labels entirely endemic to neighbour set 1 |   | 1 |
| 30 | END_ABS_ALL_LIST | List of labels entirely endemic to neighbour sets 1 and 2 combined |   | 1 |



 
 

 
### Endemism central ###
 
**Description:**   Calculate endemism for labels only in neighbour set 1, but with local ranges calculated using both neighbour sets

**Subroutine:**   calc_endemism_central

**Reference:**   Crisp et al. (2001) J Biogeog. http://dx.doi.org/10.1046/j.1365-2699.2001.00524.x ; Laffan and Crisp (2003) J Biogeog. http://www3.interscience.wiley.com/journal/118882020/abstract
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* | *Reference* |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| 31 | ENDC_CWE | Corrected weighted endemism |   | 1 | ![= \\frac{ENDC\\_WE}{ENDC\\_RICHNESS}](http://latex.codecogs.com/png.latex?= \\frac{ENDC\\_WE}{ENDC\\_RICHNESS}%.png)  |   |
| 32 | ENDC_RICHNESS | Richness used in ENDC_CWE (same as index RICHNESS_SET1) |   | 1 |   |   |
| 33 | ENDC_SINGLE | Endemism unweighted by the number of neighbours. Counts each label only once, regardless of how many groups in the neighbourhood it is found in.   Useful if your data have sampling biases and best applied with a small window. |   | 1 | ![= \\sum_{t \\in T} \\frac {1} {R_t}](http://latex.codecogs.com/png.latex?= \\sum_{t \\in T} \\frac {1} {R_t}%.png) where ![t](http://latex.codecogs.com/png.latex?t%.png) is a label (taxon) in the set of labels (taxa) ![T](http://latex.codecogs.com/png.latex?T%.png) in neighbour set 1, and ![R_t](http://latex.codecogs.com/png.latex?R_t%.png) is the global range of label ![t](http://latex.codecogs.com/png.latex?t%.png) across the data set (the number of groups it is found in, unless the range is specified at import).  | Slatyer et al. (2007) J. Biogeog http://dx.doi.org/10.1111/j.1365-2699.2006.01647.x |
| 34 | ENDC_WE | Weighted endemism |   | 1 | ![= \\sum_{t \\in T} \\frac {r_t} {R_t}](http://latex.codecogs.com/png.latex?= \\sum_{t \\in T} \\frac {r_t} {R_t}%.png) where ![t](http://latex.codecogs.com/png.latex?t%.png) is a label (taxon) in the set of labels (taxa) ![T](http://latex.codecogs.com/png.latex?T%.png) in neighbour set 1, ![r_t](http://latex.codecogs.com/png.latex?r_t%.png) is the local range (the number of elements containing label ![t](http://latex.codecogs.com/png.latex?t%.png) within neighbour sets 1 & 2, this is also its value in list ABC2_LABELS_ALL), and ![R_t](http://latex.codecogs.com/png.latex?R_t%.png) is the global range of label ![t](http://latex.codecogs.com/png.latex?t%.png) across the data set (the number of groups it is found in, unless the range is specified at import).  |   |



 
 

 
### Endemism central hierarchical partition ###
 
**Description:**   Partition the endemism central results based on the taxonomic hierarchy inferred from the label axes. (Level 0 is the highest).

**Subroutine:**   calc_endemism_central_hier_part

**Reference:**   Laffan et al. (2013) J Biogeog. http://dx.doi.org/10.1111/jbi.12001
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 35 | ENDC_HPART_0 | List of the proportional contribution of labels to the endemism central calculations, hierarchical level 0 |   | 1 |
| 36 | ENDC_HPART_1 | List of the proportional contribution of labels to the endemism central calculations, hierarchical level 1 |   | 1 |
| 37 | ENDC_HPART_C_0 | List of the proportional count of labels to the endemism central calculations (equivalent to richness per hierarchical grouping), hierarchical level 0 |   | 1 |
| 38 | ENDC_HPART_C_1 | List of the proportional count of labels to the endemism central calculations (equivalent to richness per hierarchical grouping), hierarchical level 1 |   | 1 |
| 39 | ENDC_HPART_E_0 | List of the expected proportional contribution of labels to the endemism central calculations (richness per hierarchical grouping divided by overall richness), hierarchical level 0 |   | 1 |
| 40 | ENDC_HPART_E_1 | List of the expected proportional contribution of labels to the endemism central calculations (richness per hierarchical grouping divided by overall richness), hierarchical level 1 |   | 1 |
| 41 | ENDC_HPART_OME_0 | List of the observed minus expected proportional contribution of labels to the endemism central calculations , hierarchical level 0 |   | 1 |
| 42 | ENDC_HPART_OME_1 | List of the observed minus expected proportional contribution of labels to the endemism central calculations , hierarchical level 1 |   | 1 |



 
 

 
### Endemism central lists ###
 
**Description:**   Lists used in endemism central calculations

**Subroutine:**   calc_endemism_central_lists

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 43 | ENDC_RANGELIST | List of ranges for each label used in the endemism central calculations |   | 1 |
| 44 | ENDC_WTLIST | List of weights for each label used in the endemism central calculations |   | 1 |



 
 

 
### Endemism central normalised ###
 
**Description:**   Normalise the WE and CWE scores by the neighbourhood size.
(The number of groups used to determine the local ranges).


**Subroutine:**   calc_endemism_central_normalised

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 45 | ENDC_CWE_NORM | Corrected weighted endemism normalised by groups |   | 1 | ![= \\frac{ENDC\\_CWE}{EL\\_COUNT\\_ALL}](http://latex.codecogs.com/png.latex?= \\frac{ENDC\\_CWE}{EL\\_COUNT\\_ALL}%.png)  |
| 46 | ENDC_WE_NORM | Weighted endemism normalised by groups |   | 1 | ![= \\frac{ENDC\\_WE}{EL\\_COUNT\\_ALL}](http://latex.codecogs.com/png.latex?= \\frac{ENDC\\_WE}{EL\\_COUNT\\_ALL}%.png)  |



 
 

 
### Endemism whole ###
 
**Description:**   Calculate endemism using all labels found in both neighbour sets

**Subroutine:**   calc_endemism_whole

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* | *Reference* |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| 47 | ENDW_CWE | Corrected weighted endemism |   | 1 | ![= \\frac{ENDW\\_WE}{ENDW\\_RICHNESS}](http://latex.codecogs.com/png.latex?= \\frac{ENDW\\_WE}{ENDW\\_RICHNESS}%.png)  |   |
| 48 | ENDW_RICHNESS | Richness used in ENDW_CWE (same as index RICHNESS_ALL) |   | 1 |   |   |
| 49 | ENDW_SINGLE | Endemism unweighted by the number of neighbours. Counts each label only once, regardless of how many groups in the neighbourhood it is found in.   Useful if your data have sampling biases and best applied with a small window. |   | 1 | ![= \\sum_{t \\in T} \\frac {1} {R_t}](http://latex.codecogs.com/png.latex?= \\sum_{t \\in T} \\frac {1} {R_t}%.png) where ![t](http://latex.codecogs.com/png.latex?t%.png) is a label (taxon) in the set of labels (taxa) ![T](http://latex.codecogs.com/png.latex?T%.png) across neighbour sets 1 & 2, and ![R_t](http://latex.codecogs.com/png.latex?R_t%.png) is the global range of label ![t](http://latex.codecogs.com/png.latex?t%.png) across the data set (the number of groups it is found in, unless the range is specified at import).  | Slatyer et al. (2007) J. Biogeog http://dx.doi.org/10.1111/j.1365-2699.2006.01647.x |
| 50 | ENDW_WE | Weighted endemism |   | 1 | ![= \\sum_{t \\in T} \\frac {r_t} {R_t}](http://latex.codecogs.com/png.latex?= \\sum_{t \\in T} \\frac {r_t} {R_t}%.png) where ![t](http://latex.codecogs.com/png.latex?t%.png) is a label (taxon) in the set of labels (taxa) ![T](http://latex.codecogs.com/png.latex?T%.png) across both neighbour sets, ![r_t](http://latex.codecogs.com/png.latex?r_t%.png) is the local range (the number of elements containing label ![t](http://latex.codecogs.com/png.latex?t%.png) within neighbour sets 1 & 2, this is also its value in list ABC2_LABELS_ALL), and ![R_t](http://latex.codecogs.com/png.latex?R_t%.png) is the global range of label ![t](http://latex.codecogs.com/png.latex?t%.png) across the data set (the number of groups it is found in, unless the range is specified at import).  |   |



 
 

 
### Endemism whole hierarchical partition ###
 
**Description:**   Partition the endemism whole results based on the taxonomic hierarchy inferred from the label axes. (Level 0 is the highest).

**Subroutine:**   calc_endemism_whole_hier_part

**Reference:**   Laffan et al. (2013) J Biogeog. http://dx.doi.org/10.1111/jbi.12001
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 51 | ENDW_HPART_0 | List of the proportional contribution of labels to the endemism whole calculations, hierarchical level 0 |   | 1 |
| 52 | ENDW_HPART_1 | List of the proportional contribution of labels to the endemism whole calculations, hierarchical level 1 |   | 1 |
| 53 | ENDW_HPART_C_0 | List of the proportional count of labels to the endemism whole calculations (equivalent to richness per hierarchical grouping), hierarchical level 0 |   | 1 |
| 54 | ENDW_HPART_C_1 | List of the proportional count of labels to the endemism whole calculations (equivalent to richness per hierarchical grouping), hierarchical level 1 |   | 1 |
| 55 | ENDW_HPART_E_0 | List of the expected proportional contribution of labels to the endemism whole calculations (richness per hierarchical grouping divided by overall richness), hierarchical level 0 |   | 1 |
| 56 | ENDW_HPART_E_1 | List of the expected proportional contribution of labels to the endemism whole calculations (richness per hierarchical grouping divided by overall richness), hierarchical level 1 |   | 1 |
| 57 | ENDW_HPART_OME_0 | List of the observed minus expected proportional contribution of labels to the endemism whole calculations , hierarchical level 0 |   | 1 |
| 58 | ENDW_HPART_OME_1 | List of the observed minus expected proportional contribution of labels to the endemism whole calculations , hierarchical level 1 |   | 1 |



 
 

 
### Endemism whole lists ###
 
**Description:**   Lists used in the endemism whole calculations

**Subroutine:**   calc_endemism_whole_lists

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 59 | ENDW_RANGELIST | List of ranges for each label used in the endemism whole calculations |   | 1 |
| 60 | ENDW_WTLIST | List of weights for each label used in the endemism whole calculations |   | 1 |



 
 

 
### Endemism whole normalised ###
 
**Description:**   Normalise the WE and CWE scores by the neighbourhood size.
(The number of groups used to determine the local ranges). 


**Subroutine:**   calc_endemism_whole_normalised

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 61 | ENDW_CWE_NORM | Corrected weighted endemism normalised by groups |   | 1 | ![= \\frac{ENDW\\_CWE}{EL\\_COUNT\\_ALL}](http://latex.codecogs.com/png.latex?= \\frac{ENDW\\_CWE}{EL\\_COUNT\\_ALL}%.png)  |
| 62 | ENDW_WE_NORM | Weighted endemism normalised by groups |   | 1 | ![= \\frac{ENDW\\_WE}{EL\\_COUNT\\_ALL}](http://latex.codecogs.com/png.latex?= \\frac{ENDW\\_WE}{EL\\_COUNT\\_ALL}%.png)  |


## Hierarchical Labels ##
 
 

 
### Ratios of hierarchical labels ###
 
**Description:**   Analyse the diversity of labels using their hierarchical levels.
The A, B and C scores are the same as in the Label Counts analysis (calc_label_counts)
but calculated for each hierarchical level, e.g. for three axes one could have
A0 as the Family level, A1 for the Family:Genus level,
and A2 for the Family:Genus:Species level.
The number of indices generated depends on how many axes are used in the labels.
In this case there are 2.  Axes are numbered from zero
as the highest level in the hierarchy, so level 0 is the top level
of the hierarchy.


**Subroutine:**   calc_hierarchical_label_ratios

**Reference:**   Jones and Laffan (2008) Trans Philol Soc http://dx.doi.org/10.1111/j.1467-968X.2008.00209.x
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 63 | HIER_A0 | A score for level 0 |   | 1 |
| 64 | HIER_A1 | A score for level 1 |   | 1 |
| 65 | HIER_ARAT1_0 | Ratio of A scores, (HIER_A1 / HIER_A0) |   | 1 |
| 66 | HIER_ASUM0 | Sum of shared label sample counts, level 0 |   | 1 |
| 67 | HIER_ASUM1 | Sum of shared label sample counts, level 1 |   | 1 |
| 68 | HIER_ASUMRAT1_0 | 1 - Ratio of shared label sample counts, (HIER_ASUM1 / HIER_ASUM0) | cluster metric | 1 |
| 69 | HIER_B0 | B score  for level 0 |   | 1 |
| 70 | HIER_B1 | B score  for level 1 |   | 1 |
| 71 | HIER_BRAT1_0 | Ratio of B scores, (HIER_B1 / HIER_B0) |   | 1 |
| 72 | HIER_C0 | C score for level 0 |   | 1 |
| 73 | HIER_C1 | C score for level 1 |   | 1 |
| 74 | HIER_CRAT1_0 | Ratio of C scores, (HIER_C1 / HIER_C0) |   | 1 |


## Inter-event Interval Statistics ##
 
 

 
### Inter-event interval statistics ###
 
**Description:**   Calculate summary statistics from a set of numeric labels that represent event times.
Event intervals are calculated within groups, then aggregated across the neighbourhoods, and then summary stats are calculated.

**Subroutine:**   calc_iei_stats

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 75 | IEI_CV | Coefficient of variation (IEI_SD / IEI_MEAN) |   | 1 |
| 76 | IEI_GMEAN | Geometric mean |   | 1 |
| 77 | IEI_KURT | Kurtosis |   | 1 |
| 78 | IEI_MAX | Maximum value (100th percentile) |   | 1 |
| 79 | IEI_MEAN | Mean | cluster metric | 1 |
| 80 | IEI_MIN | Minimum value (zero percentile) |   | 1 |
| 81 | IEI_N | Number of samples |   | 1 |
| 82 | IEI_RANGE | Range (max - min) |   | 1 |
| 83 | IEI_SD | Standard deviation |   | 1 |
| 84 | IEI_SKEW | Skewness |   | 1 |



 
 

 
### Inter-event interval statistics data ###
 
**Description:**   The underlying data used for the IEI stats.

**Subroutine:**   calc_iei_data

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 85 | IEI_DATA_ARRAY | Interval data in array form.  Multiple occurrences are repeated  |   | 1 |
| 86 | IEI_DATA_HASH | Interval data in hash form where the  interval is the key and number of occurrences is the value |   | 1 |


## Lists and Counts ##
 
 

 
### Element counts ###
 
**Description:**   Counts of elements used in neighbour sets 1 and 2.


**Subroutine:**   calc_elements_used

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 87 | EL_COUNT_ALL | Count of elements in both neighbour sets |   | 2 |
| 88 | EL_COUNT_SET1 | Count of elements in neighbour set 1 |   | 1 |
| 89 | EL_COUNT_SET2 | Count of elements in neighbour set 2 |   | 2 |



 
 

 
### Element lists ###
 
**Description:**   Lists of elements used in neighbour sets 1 and 2.
These form the basis for all the spatial calculations.

**Subroutine:**   calc_element_lists_used

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 90 | EL_LIST_ALL | List of elements in both neighour sets |   | 2 |
| 91 | EL_LIST_SET1 | List of elements in neighbour set 1 |   | 1 |
| 92 | EL_LIST_SET2 | List of elements in neighbour set 2 |   | 2 |



 
 

 
### Label counts ###
 
**Description:**   Counts of labels in neighbour sets 1 and 2.
These form the basis for the Taxonomic Dissimilarity and Comparison indices.

**Subroutine:**   calc_abc_counts

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 93 | ABC_A | Count of labels common to both neighbour sets |   | 1 |
| 94 | ABC_ABC | Total label count across both neighbour sets (same as RICHNESS_ALL) |   | 1 |
| 95 | ABC_B | Count of labels unique to neighbour set 1 |   | 1 |
| 96 | ABC_C | Count of labels unique to neighbour set 2 |   | 1 |



 
 

 
### Label counts not in sample ###
 
**Description:**   Count of basedata labels not in either neighbour set (shared absence)
Used in some of the dissimilarity metrics.

**Subroutine:**   calc_d

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 97 | ABC_D | Count of labels not in either neighbour set (D score) |   | 1 |



 
 

 
### Local range lists ###
 
**Description:**   Lists of labels with their local ranges as values. 
The local ranges are the number of elements in which each label is found in each neighour set.

**Subroutine:**   calc_local_range_lists

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 98 | ABC2_LABELS_ALL | List of labels in both neighbour sets |   | 2 |
| 99 | ABC2_LABELS_SET1 | List of labels in neighbour set 1 |   | 1 |
| 100 | ABC2_LABELS_SET2 | List of labels in neighbour set 2 |   | 2 |



 
 

 
### Local range summary statistics ###
 
**Description:**   Summary stats of the local ranges within neighour sets.

**Subroutine:**   calc_local_range_stats

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 101 | ABC2_MEAN_ALL | Mean label range in both element sets |   | 1 |
| 102 | ABC2_MEAN_SET1 | Mean label range in neighbour set 1 |   | 1 |
| 103 | ABC2_MEAN_SET2 | Mean label range in neighbour set 2 |   | 2 |
| 104 | ABC2_SD_ALL | Standard deviation of label ranges in both element sets |   | 2 |
| 105 | ABC2_SD_SET1 | Standard deviation of label ranges in neighbour set 1 |   | 1 |
| 106 | ABC2_SD_SET2 | Standard deviation of label ranges in neighbour set 2 |   | 2 |



 
 

 
### Rank relative sample counts per label ###
 
**Description:**   Find the per-group percentile rank of all labels across both neighbour sets,  relative to the processing group. An absence is treated as a sample count of zero.

**Subroutine:**   calc_label_count_quantile_position

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 107 | LABEL_COUNT_RANK_PCT | List of percentile ranks for each label's sample count |   | 1 |



 
 

 
### Redundancy ###
 
**Description:**   Ratio of labels to samples.
Values close to 1 are well sampled while zero means 
there is no redundancy in the sampling


**Subroutine:**   calc_redundancy

**Reference:**   Garcillan et al. (2003) J Veget. Sci. http://dx.doi.org/10.1111/j.1654-1103.2003.tb02174.x
 

**Formula:**
   ![= 1 - \\frac{richness}{sum\\ of\\ the\\ sample\\ counts}](http://latex.codecogs.com/png.latex?= 1 - \\frac{richness}{sum\\ of\\ the\\ sample\\ counts}%.png)

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 108 | REDUNDANCY_ALL | for both neighbour sets |   | 1 | ![= 1 - \\frac{RICHNESS\\_ALL}{ABC3\\_SUM\\_ALL}](http://latex.codecogs.com/png.latex?= 1 - \\frac{RICHNESS\\_ALL}{ABC3\\_SUM\\_ALL}%.png)  |
| 109 | REDUNDANCY_SET1 | for neighour set 1 |   | 1 | ![= 1 - \\frac{RICHNESS\\_SET1}{ABC3\\_SUM\\_SET1}](http://latex.codecogs.com/png.latex?= 1 - \\frac{RICHNESS\\_SET1}{ABC3\\_SUM\\_SET1}%.png)  |
| 110 | REDUNDANCY_SET2 | for neighour set 2 |   | 2 | ![= 1 - \\frac{RICHNESS\\_SET2}{ABC3\\_SUM\\_SET2}](http://latex.codecogs.com/png.latex?= 1 - \\frac{RICHNESS\\_SET2}{ABC3\\_SUM\\_SET2}%.png)  |



 
 

 
### Richness ###
 
**Description:**   Count the number of labels in the neighbour sets

**Subroutine:**   calc_richness

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 111 | RICHNESS_ALL | for both sets of neighbours |   | 1 |
| 112 | RICHNESS_SET1 | for neighbour set 1 |   | 1 |
| 113 | RICHNESS_SET2 | for neighbour set 2 |   | 2 |



 
 

 
### Sample count lists ###
 
**Description:**   Lists of sample counts for each label within the neighbour sets.
These form the basis of the sample indices.

**Subroutine:**   calc_local_sample_count_lists

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 114 | ABC3_LABELS_ALL | List of labels in both neighbour sets with their sample counts as the values. |   | 2 |
| 115 | ABC3_LABELS_SET1 | List of labels in neighbour set 1. Values are the sample counts.   |   | 1 |
| 116 | ABC3_LABELS_SET2 | List of labels in neighbour set 2. Values are the sample counts. |   | 2 |



 
 

 
### Sample count quantiles ###
 
**Description:**   Quantiles of the sample counts across the neighbour sets.


**Subroutine:**   calc_local_sample_count_quantiles

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 117 | ABC3_QUANTILES_ALL | List of quantiles for both neighbour sets |   | 2 |
| 118 | ABC3_QUANTILES_SET1 | List of quantiles for neighbour set 1 |   | 1 |
| 119 | ABC3_QUANTILES_SET2 | List of quantiles for neighbour set 2 |   | 2 |



 
 

 
### Sample count summary stats ###
 
**Description:**   Summary stats of the sample counts across the neighbour sets.


**Subroutine:**   calc_local_sample_count_stats

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 120 | ABC3_MEAN_ALL | Mean of label sample counts across both element sets. |   | 2 |
| 121 | ABC3_MEAN_SET1 | Mean of label sample counts in neighbour set1. |   | 1 |
| 122 | ABC3_MEAN_SET2 | Mean of label sample counts in neighbour set 2. |   | 2 |
| 123 | ABC3_SD_ALL | Standard deviation of label sample counts in both element sets. |   | 2 |
| 124 | ABC3_SD_SET1 | Standard deviation of sample counts in neighbour set 1. |   | 1 |
| 125 | ABC3_SD_SET2 | Standard deviation of label sample counts in neighbour set 2. |   | 2 |
| 126 | ABC3_SUM_ALL | Sum of the label sample counts across both neighbour sets. |   | 2 |
| 127 | ABC3_SUM_SET1 | Sum of the label sample counts across both neighbour sets. |   | 1 |
| 128 | ABC3_SUM_SET2 | Sum of the label sample counts in neighbour set2. |   | 2 |


## Matrix ##
 
 

 
### Compare dissimilarity matrix values ###
 
**Description:**   Compare the set of labels in one neighbour set with those in another using their matrix values. Labels not in the matrix are ignored. This calculation assumes a matrix of dissimilarities and uses 0 as identical, so take care).

**Subroutine:**   calc_compare_dissim_matrix_values

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 129 | MXD_COUNT | Count of comparisons used. |   | 1 |
| 130 | MXD_LIST1 | List of the labels used from neighbour set 1 (those in the matrix). The list values are the number of times each label was used in the calculations. This will always be 1 for labels in neighbour set 1. |   | 1 |
| 131 | MXD_LIST2 | List of the labels used from neighbour set 2 (those in the matrix). The list values are the number of times each label was used in the calculations. This will equal the number of labels used from neighbour set 1. |   | 1 |
| 132 | MXD_MEAN | Mean dissimilarity of labels in set 1 to those in set 2. | cluster metric | 1 |
| 133 | MXD_VARIANCE | Variance of the dissimilarity values, set 1 vs set 2. | cluster metric | 1 |



 
 

 
### Matrix statistics ###
 
**Description:**   Calculate summary statistics of matrix elements in the selected matrix for labels found across both neighbour sets.
Labels not in the matrix are ignored.

**Subroutine:**   calc_matrix_stats

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 134 | MX_KURT | Kurtosis |   | 1 |
| 135 | MX_LABELS | List of the matrix labels in the neighbour sets |   | 1 |
| 136 | MX_MAXVALUE | Maximum value |   | 1 |
| 137 | MX_MEAN | Mean |   | 1 |
| 138 | MX_MEDIAN | Median |   | 1 |
| 139 | MX_MINVALUE | Minimum value |   | 1 |
| 140 | MX_N | Number of samples (matrix elements, not labels) |   | 1 |
| 141 | MX_PCT05 | 5th percentile value |   | 1 |
| 142 | MX_PCT25 | First quartile (25th percentile) |   | 1 |
| 143 | MX_PCT75 | Third quartile (75th percentile) |   | 1 |
| 144 | MX_PCT95 | 95th percentile value |   | 1 |
| 145 | MX_RANGE | Range (max-min) |   | 1 |
| 146 | MX_SD | Standard deviation |   | 1 |
| 147 | MX_SKEW | Skewness |   | 1 |
| 148 | MX_VALUES | List of the matrix values |   | 1 |



 
 

 
### Rao's quadratic entropy, matrix weighted ###
 
**Description:**   Calculate Rao's quadratic entropy for a matrix weights scheme.
BaseData labels not in the matrix are ignored

**Subroutine:**   calc_mx_rao_qe

**Formula:**
   ![= \\sum_{i \\in L} \\sum_{j \\in L} d_{ij} p_i p_j](http://latex.codecogs.com/png.latex?= \\sum_{i \\in L} \\sum_{j \\in L} d_{ij} p_i p_j%.png) where ![p_i](http://latex.codecogs.com/png.latex?p_i%.png) and ![p_j](http://latex.codecogs.com/png.latex?p_j%.png) are the sample counts for the i'th and j'th labels, ![d_{ij}](http://latex.codecogs.com/png.latex?d_{ij}%.png) is the matrix value for the pair of labels ![ij](http://latex.codecogs.com/png.latex?ij%.png) and ![L](http://latex.codecogs.com/png.latex?L%.png) is the set of labels across both neighbour sets that occur in the matrix.

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 149 | MX_RAO_QE | Matrix weighted quadratic entropy |   | 1 |
| 150 | MX_RAO_TLABELS | List of labels and values used in the MX_RAO_QE calculations |   | 1 |
| 151 | MX_RAO_TN | Count of comparisons used to calculate MX_RAO_QE |   | 1 |


## Numeric Labels ##
 
 

 
### Numeric label data ###
 
**Description:**   The underlying data used for the numeric labels stats, as an array.
For the hash form, use the ABC3_LABELS_ALL index from the 'Sample count lists' calculation.

**Subroutine:**   calc_numeric_label_data

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 152 | NUM_DATA_ARRAY | Numeric label data in array form.  Multiple occurrences are repeated based on their sample counts. |   | 1 |



 
 

 
### Numeric label dissimilarity ###
 
**Description:**   Compare the set of numeric labels in one neighbour set with those in another. 

**Subroutine:**   calc_numeric_label_dissimilarity

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 153 | NUMD_ABSMEAN | Mean absolute dissimilarity of labels in set 1 to those in set 2. | cluster metric | 1 | ![= \\frac{\\sum_{l_{1i} \\in L_1} \\sum_{l_{2j} \\in L_2} abs (l_{1i} - l_{2j})(w_{1i} \\times w_{2j})}{n_1 \\times n_2}](http://latex.codecogs.com/png.latex?= \\frac{\\sum_{l_{1i} \\in L_1} \\sum_{l_{2j} \\in L_2} abs (l_{1i} - l_{2j})(w_{1i} \\times w_{2j})}{n_1 \\times n_2}%.png)where![L1](http://latex.codecogs.com/png.latex?L1%.png) and ![L2](http://latex.codecogs.com/png.latex?L2%.png) are the labels in neighbour sets 1 and 2 respectively, and ![n1](http://latex.codecogs.com/png.latex?n1%.png) and ![n2](http://latex.codecogs.com/png.latex?n2%.png) are the sample counts in neighbour sets 1 and 2  |
| 154 | NUMD_COUNT | Count of comparisons used. |   | 1 | ![= n1 * n2](http://latex.codecogs.com/png.latex?= n1 * n2%.png)where values are as for ![NUMD\\_ABSMEAN](http://latex.codecogs.com/png.latex?NUMD\\_ABSMEAN%.png)  |
| 155 | NUMD_VARIANCE | Variance of the dissimilarity values (mean squared deviation), set 1 vs set 2. | cluster metric | 1 | ![= \\frac{\\sum_{l_{1i} \\in L_1} \\sum_{l_{2j} \\in L_2} (l_{1i} - l_{2j})^2(w_{1i} \\times w_{2j})}{n_1 \\times n_2}](http://latex.codecogs.com/png.latex?= \\frac{\\sum_{l_{1i} \\in L_1} \\sum_{l_{2j} \\in L_2} (l_{1i} - l_{2j})^2(w_{1i} \\times w_{2j})}{n_1 \\times n_2}%.png)where values are as for ![NUMD\\_ABSMEAN](http://latex.codecogs.com/png.latex?NUMD\\_ABSMEAN%.png)  |



 
 

 
### Numeric label harmonic and geometric means ###
 
**Description:**   Calculate geometric and harmonic means for a set of numeric labels.


**Subroutine:**   calc_numeric_label_other_means

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 156 | NUM_GMEAN | Geometric mean |   | 1 |
| 157 | NUM_HMEAN | Harmonic mean |   | 1 |



 
 

 
### Numeric label quantiles ###
 
**Description:**   Calculate quantiles from a set of numeric labels.
Weights by samples so multiple occurrences are accounted for.


**Subroutine:**   calc_numeric_label_quantiles

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 158 | NUM_Q005 | 5th percentile |   | 1 |
| 159 | NUM_Q010 | 10th percentile |   | 1 |
| 160 | NUM_Q015 | 15th percentile |   | 1 |
| 161 | NUM_Q020 | 20th percentile |   | 1 |
| 162 | NUM_Q025 | 25th percentile |   | 1 |
| 163 | NUM_Q030 | 30th percentile |   | 1 |
| 164 | NUM_Q035 | 35th percentile |   | 1 |
| 165 | NUM_Q040 | 40th percentile |   | 1 |
| 166 | NUM_Q045 | 45th percentile |   | 1 |
| 167 | NUM_Q050 | 50th percentile |   | 1 |
| 168 | NUM_Q055 | 55th percentile |   | 1 |
| 169 | NUM_Q060 | 60th percentile |   | 1 |
| 170 | NUM_Q065 | 65th percentile |   | 1 |
| 171 | NUM_Q070 | 70th percentile |   | 1 |
| 172 | NUM_Q075 | 75th percentile |   | 1 |
| 173 | NUM_Q080 | 80th percentile |   | 1 |
| 174 | NUM_Q085 | 85th percentile |   | 1 |
| 175 | NUM_Q090 | 90th percentile |   | 1 |
| 176 | NUM_Q095 | 95th percentile |   | 1 |



 
 

 
### Numeric label statistics ###
 
**Description:**   Calculate summary statistics from a set of numeric labels.
Weights by samples so multiple occurrences are accounted for.


**Subroutine:**   calc_numeric_label_stats

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 177 | NUM_CV | Coefficient of variation (NUM_SD / NUM_MEAN) |   | 1 |
| 178 | NUM_KURT | Kurtosis |   | 1 |
| 179 | NUM_MAX | Maximum value (100th quantile) |   | 1 |
| 180 | NUM_MEAN | Mean |   | 1 |
| 181 | NUM_MIN | Minimum value (zero quantile) |   | 1 |
| 182 | NUM_N | Number of samples |   | 1 |
| 183 | NUM_RANGE | Range (max - min) |   | 1 |
| 184 | NUM_SD | Standard deviation |   | 1 |
| 185 | NUM_SKEW | Skewness |   | 1 |



 
 

 
### Numeric labels Gi* statistic ###
 
**Description:**   Getis-Ord Gi* statistic for numeric labels across both neighbour sets

**Subroutine:**   calc_num_labels_gistar

**Reference:**   Getis and Ord (1992) Geographical Analysis. http://dx.doi.org/10.1111/j.1538-4632.1992.tb00261.x
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 186 | NUM_GISTAR | List of Gi* scores |   | 1 |


## PhyloCom Indices ##
 
 

 
### NRI and NTI expected values ###
 
**Description:**   Expected values used in the NRI and NTI calculations. 
Derived using a null model without resampling where 
each label has an equal probability of being selected
(a null model of even distrbution).
The expected mean and SD are the same for each unique number
of labels across all neighbour sets.  This means if you have
three neighbour sets, each with three labels, then the expected
values will be identical for each, even if the labels are
completely different.


**Subroutine:**   calc_nri_nti_expected_values

**Reference:**   Webb et al. (2008) http://dx.doi.org/10.1093/bioinformatics/btn358
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 187 | PHYLO_NRI_NTI_SAMPLE_N | Number of random resamples used |   | 1 |   |
| 188 | PHYLO_NRI_SAMPLE_MEAN | Expected mean of pair-wise distances |   | 1 |   |
| 189 | PHYLO_NRI_SAMPLE_SD | Expected standard deviation of pair-wise distances |   | 1 |   |
| 190 | PHYLO_NTI_SAMPLE_MEAN | Expected mean of nearest taxon distances |   | 1 |   |
| 191 | PHYLO_NTI_SAMPLE_SD | Expected standard deviation of nearest taxon distances |   | 1 |   |



 
 

 
### NRI and NTI, abundance weighted ###
 
**Description:**   NRI and NTI for the set of labels
on the tree in the sample. This
version is -1* the Phylocom implementation,
so values >0 have longer branches than expected.
 Abundance weighted.

**Subroutine:**   calc_nri_nti3

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 192 | PHYLO_NRI3 | Net Relatedness Index, abundance weighted |   | 1 |   |
| 193 | PHYLO_NTI3 | Nearest Taxon Index, abundance weighted |   | 1 |   |



 
 

 
### NRI and NTI, local range weighted ###
 
**Description:**   NRI and NTI for the set of labels
on the tree in the sample. This
version is -1* the Phylocom implementation,
so values >0 have longer branches than expected.
 Local range weighted.

**Subroutine:**   calc_nri_nti2

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 194 | PHYLO_NRI2 | Net Relatedness Index, local range weighted |   | 1 |   |
| 195 | PHYLO_NTI2 | Nearest Taxon Index, local range weighted |   | 1 |   |



 
 

 
### NRI and NTI, unweighted ###
 
**Description:**   NRI and NTI for the set of labels
on the tree in the sample. This
version is -1* the Phylocom implementation,
so values >0 have longer branches than expected.
 Not weighted by sample counts, so each label counts once only.

**Subroutine:**   calc_nri_nti1

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 196 | PHYLO_NRI1 | Net Relatedness Index, unweighted |   | 1 | ![NRI = \\frac{MPD_{obs} - mean(MPD_{rand})}{sd(MPD_{rand})}](http://latex.codecogs.com/png.latex?NRI = \\frac{MPD_{obs} - mean(MPD_{rand})}{sd(MPD_{rand})}%.png)  |
| 197 | PHYLO_NTI1 | Nearest Taxon Index, unweighted |   | 1 | ![NTI = \\frac{MNTD_{obs} - mean(MNTD_{rand})}{sd(MNTD_{rand})}](http://latex.codecogs.com/png.latex?NTI = \\frac{MNTD_{obs} - mean(MNTD_{rand})}{sd(MNTD_{rand})}%.png)  |



 
 

 
### Phylogenetic and Nearest taxon distances, abundance weighted ###
 
**Description:**   Distance stats from each label to the nearest label along the tree.  Compares with all other labels across both neighbour sets. Weighted by sample counts (which currently must be integers)

**Subroutine:**   calc_phylo_mpd_mntd3

**Reference:**   Webb et al. (2008) http://dx.doi.org/10.1093/bioinformatics/btn358
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 198 | PMPD3_MAX | Maximum of pairwise phylogenetic distances |   | 1 |   |
| 199 | PMPD3_MEAN | Mean of pairwise phylogenetic distances |   | 1 | ![MPD = \\frac {\\sum_{t_i = 1}^{n_t-1} \\sum_{t_j = 1}^{n_t} d_{t_i \\leftrightarrow t_j}}{(n_t-1)^2}, i \\neq j](http://latex.codecogs.com/png.latex?MPD = \\frac {\\sum_{t_i = 1}^{n_t-1} \\sum_{t_j = 1}^{n_t} d_{t_i \\leftrightarrow t_j}}{(n_t-1)^2}, i \\neq j%.png)where ![d_{t_i \\leftrightarrow t_j} = \\sum_{b \\in B_{t_i \\leftrightarrow t_j}} L_b](http://latex.codecogs.com/png.latex?d_{t_i \\leftrightarrow t_j} = \\sum_{b \\in B_{t_i \\leftrightarrow t_j}} L_b%.png)is the sum of the branch lengths along the path connecting ![t_i](http://latex.codecogs.com/png.latex?t_i%.png)and![t_j](http://latex.codecogs.com/png.latex?t_j%.png)such that ![L_b](http://latex.codecogs.com/png.latex?L_b%.png)is the length of each branch in the set of branches![B](http://latex.codecogs.com/png.latex?B%.png)  |
| 200 | PMPD3_MIN | Minimum of pairwise phylogenetic distances |   | 1 |   |
| 201 | PMPD3_N | Count of pairwise phylogenetic distances |   | 1 |   |
| 202 | PMPD3_RMSD | Root mean squared pairwise phylogenetic distances |   | 1 |   |
| 203 | PNTD3_MAX | Maximum of nearest taxon distances |   | 1 |   |
| 204 | PNTD3_MEAN | Mean of nearest taxon distances |   | 1 |   |
| 205 | PNTD3_MIN | Minimum of nearest taxon distances |   | 1 |   |
| 206 | PNTD3_N | Count of nearest taxon distances |   | 1 |   |
| 207 | PNTD3_RMSD | Root mean squared nearest taxon distances |   | 1 |   |



 
 

 
### Phylogenetic and Nearest taxon distances, local range weighted ###
 
**Description:**   Distance stats from each label to the nearest label along the tree.  Compares with all other labels across both neighbour sets. Weighted by sample counts

**Subroutine:**   calc_phylo_mpd_mntd2

**Reference:**   Webb et al. (2008) http://dx.doi.org/10.1093/bioinformatics/btn358
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 208 | PMPD2_MAX | Maximum of pairwise phylogenetic distances |   | 1 |   |
| 209 | PMPD2_MEAN | Mean of pairwise phylogenetic distances |   | 1 | ![MPD = \\frac {\\sum_{t_i = 1}^{n_t-1} \\sum_{t_j = 1}^{n_t} d_{t_i \\leftrightarrow t_j}}{(n_t-1)^2}, i \\neq j](http://latex.codecogs.com/png.latex?MPD = \\frac {\\sum_{t_i = 1}^{n_t-1} \\sum_{t_j = 1}^{n_t} d_{t_i \\leftrightarrow t_j}}{(n_t-1)^2}, i \\neq j%.png)where ![d_{t_i \\leftrightarrow t_j} = \\sum_{b \\in B_{t_i \\leftrightarrow t_j}} L_b](http://latex.codecogs.com/png.latex?d_{t_i \\leftrightarrow t_j} = \\sum_{b \\in B_{t_i \\leftrightarrow t_j}} L_b%.png)is the sum of the branch lengths along the path connecting ![t_i](http://latex.codecogs.com/png.latex?t_i%.png)and![t_j](http://latex.codecogs.com/png.latex?t_j%.png)such that ![L_b](http://latex.codecogs.com/png.latex?L_b%.png)is the length of each branch in the set of branches![B](http://latex.codecogs.com/png.latex?B%.png)  |
| 210 | PMPD2_MIN | Minimum of pairwise phylogenetic distances |   | 1 |   |
| 211 | PMPD2_N | Count of pairwise phylogenetic distances |   | 1 |   |
| 212 | PMPD2_RMSD | Root mean squared pairwise phylogenetic distances |   | 1 |   |
| 213 | PNTD2_MAX | Maximum of nearest taxon distances |   | 1 |   |
| 214 | PNTD2_MEAN | Mean of nearest taxon distances |   | 1 |   |
| 215 | PNTD2_MIN | Minimum of nearest taxon distances |   | 1 |   |
| 216 | PNTD2_N | Count of nearest taxon distances |   | 1 |   |
| 217 | PNTD2_RMSD | Root mean squared nearest taxon distances |   | 1 |   |



 
 

 
### Phylogenetic and Nearest taxon distances, unweighted ###
 
**Description:**   Distance stats from each label to the nearest label along the tree.  Compares with all other labels across both neighbour sets. 

**Subroutine:**   calc_phylo_mpd_mntd1

**Reference:**   Webb et al. (2008) http://dx.doi.org/10.1093/bioinformatics/btn358
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 218 | PMPD1_MAX | Maximum of pairwise phylogenetic distances |   | 1 |   |
| 219 | PMPD1_MEAN | Mean of pairwise phylogenetic distances |   | 1 | ![MPD = \\frac {\\sum_{t_i = 1}^{n_t-1} \\sum_{t_j = 1}^{n_t} d_{t_i \\leftrightarrow t_j}}{(n_t-1)^2}, i \\neq j](http://latex.codecogs.com/png.latex?MPD = \\frac {\\sum_{t_i = 1}^{n_t-1} \\sum_{t_j = 1}^{n_t} d_{t_i \\leftrightarrow t_j}}{(n_t-1)^2}, i \\neq j%.png)where ![d_{t_i \\leftrightarrow t_j} = \\sum_{b \\in B_{t_i \\leftrightarrow t_j}} L_b](http://latex.codecogs.com/png.latex?d_{t_i \\leftrightarrow t_j} = \\sum_{b \\in B_{t_i \\leftrightarrow t_j}} L_b%.png)is the sum of the branch lengths along the path connecting ![t_i](http://latex.codecogs.com/png.latex?t_i%.png)and![t_j](http://latex.codecogs.com/png.latex?t_j%.png)such that ![L_b](http://latex.codecogs.com/png.latex?L_b%.png)is the length of each branch in the set of branches![B](http://latex.codecogs.com/png.latex?B%.png)  |
| 220 | PMPD1_MIN | Minimum of pairwise phylogenetic distances |   | 1 |   |
| 221 | PMPD1_N | Count of pairwise phylogenetic distances |   | 1 |   |
| 222 | PMPD1_RMSD | Root mean squared pairwise phylogenetic distances |   | 1 |   |
| 223 | PNTD1_MAX | Maximum of nearest taxon distances |   | 1 |   |
| 224 | PNTD1_MEAN | Mean of nearest taxon distances |   | 1 |   |
| 225 | PNTD1_MIN | Minimum of nearest taxon distances |   | 1 |   |
| 226 | PNTD1_N | Count of nearest taxon distances |   | 1 |   |
| 227 | PNTD1_RMSD | Root mean squared nearest taxon distances |   | 1 |   |


## Phylogenetic Endemism ##
 
 

 
### Corrected weighted phylogenetic endemism ###
 
**Description:**   What proportion of the PD is range-restricted to this neighbour set?

**Subroutine:**   calc_phylo_corrected_weighted_endemism

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* | *Reference* |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| 228 | PE_CWE | Corrected weighted endemism.  This is the phylogenetic analogue of corrected weighted endemism. |   | 1 | ![PE_WE / PD](http://latex.codecogs.com/png.latex?PE_WE / PD%.png)  |   |



 
 

 
### Corrected weighted phylogenetic endemism, central variant ###
 
**Description:**   What proportion of the PD in neighbour set 1 is range-restricted to neighbour sets 1 and 2?

**Subroutine:**   calc_pe_central_cwe

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 229 | PEC_CWE | Corrected weighted phylogenetic endemism, central variant |   | 1 |
| 230 | PEC_CWE_PD | PD used in the PEC_CWE index. |   | 1 |



 
 

 
### Corrected weighted phylogenetic rarity ###
 
**Description:**   What proportion of the PD is abundance-restricted to this neighbour set?

**Subroutine:**   calc_phylo_corrected_weighted_rarity

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* | *Reference* |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| 231 | PHYLO_RARITY_CWR | Corrected weighted phylogenetic rarity.  This is the phylogenetic rarity analogue of corrected weighted endemism. |   | 1 | ![AED_T / PD](http://latex.codecogs.com/png.latex?AED_T / PD%.png)  |   |



 
 

 
### PD-Endemism ###
 
**Description:**   Absolute endemism analogue of PE.  It is the sum of the branch lengths restricted to the neighbour sets.

**Subroutine:**   calc_pd_endemism

**Reference:**   See Faith (2004) Cons Biol.  http://dx.doi.org/10.1111/j.1523-1739.2004.00330.x
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 232 | PD_ENDEMISM | Phylogenetic Diversity Endemism |   | 1 |
| 233 | PD_ENDEMISM_P | Phylogenetic Diversity Endemism, as a proportion of the whole tree |   | 1 |
| 234 | PD_ENDEMISM_WTS | Phylogenetic Diversity Endemism weights per node found only in the neighbour set |   | 1 |



 
 

 
### PE clade contributions ###
 
**Description:**   Contribution of each node and its descendents to the Phylogenetic endemism (PE) calculation.

**Subroutine:**   calc_pe_clade_contributions

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 235 | PE_CLADE_CONTR | List of node (clade) contributions to the PE calculation |   | 1 |
| 236 | PE_CLADE_CONTR_P | List of node (clade) contributions to the PE calculation, proportional to the entire tree |   | 1 |
| 237 | PE_CLADE_SCORE | List of PE scores for each node (clade), being the sum of all descendent PE weights |   | 1 |



 
 

 
### PE clade loss ###
 
**Description:**   How much of the PE would be lost if a clade were to be removed? Calculates the clade PE below the last ancestral node in the neighbour set which would still be in the neighbour set.

**Subroutine:**   calc_pe_clade_loss

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 238 | PE_CLADE_LOSS_CONTR | List of the proportion of the PE score which would be lost if each clade were removed. |   | 1 |
| 239 | PE_CLADE_LOSS_CONTR_P | As per PE_CLADE_LOSS but proportional to the entire tree |   | 1 |
| 240 | PE_CLADE_LOSS_SCORE | List of how much PE would be lost if each clade were removed. |   | 1 |



 
 

 
### PE clade loss (ancestral component) ###
 
**Description:**   How much of the PE clade loss is due to the ancestral branches? The score is zero when there is no ancestral loss.

**Subroutine:**   calc_pe_clade_loss_ancestral

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 241 | PE_CLADE_LOSS_ANC | List of how much ancestral PE would be lost if each clade were removed.  The value is 0 when no ancestral PE is lost. |   | 1 |
| 242 | PE_CLADE_LOSS_ANC_P | List of the proportion of the clade's PE loss that is due to the ancestral branches. |   | 1 |



 
 

 
### Phylogenetic Endemism ###
 
**Description:**   Phylogenetic endemism (PE).Uses labels in both neighbourhoods and trims the tree to exclude labels not in the BaseData object.

**Subroutine:**   calc_pe

**Reference:**   Rosauer et al (2009) Mol. Ecol. http://dx.doi.org/10.1111/j.1365-294X.2009.04311.x
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 243 | PE_WE | Phylogenetic endemism |   | 1 |
| 244 | PE_WE_P | Phylogenetic weighted endemism as a proportion of the total tree length |   | 1 |



 
 

 
### Phylogenetic Endemism central ###
 
**Description:**   Phylogenetic endemism (PE).
Uses labels from neighbour set one but local ranges from across
both neighbour sets.
Trims the tree to exclude labels not in the BaseData object.


**Subroutine:**   calc_pe_central

**Reference:**   Rosauer et al (2009) Mol. Ecol. http://dx.doi.org/10.1111/j.1365-294X.2009.04311.x
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 245 | PEC_WE | Phylogenetic endemism, central variant |   | 1 |
| 246 | PEC_WE_P | Phylogenetic weighted endemism as a proportion of the total tree length, central variant |   | 1 |



 
 

 
### Phylogenetic Endemism central lists ###
 
**Description:**   Lists underlying the phylogenetic endemism central indices.
Uses labels from neighbour set one but local ranges from across
both neighbour sets.


**Subroutine:**   calc_pe_central_lists

**Reference:**   Rosauer et al (2009) Mol. Ecol. http://dx.doi.org/10.1111/j.1365-294X.2009.04311.x
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 247 | PEC_LOCAL_RANGELIST | Phylogenetic endemism local range lists, central variant |   | 1 |
| 248 | PEC_RANGELIST | Phylogenetic endemism global range lists, central variant |   | 1 |
| 249 | PEC_WTLIST | Phylogenetic endemism weights, central variant |   | 1 |



 
 

 
### Phylogenetic Endemism lists ###
 
**Description:**   Lists used in the Phylogenetic endemism (PE) calculations.

**Subroutine:**   calc_pe_lists

**Reference:**   Rosauer et al (2009) Mol. Ecol. http://dx.doi.org/10.1111/j.1365-294X.2009.04311.x
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 250 | PE_LOCAL_RANGELIST | Local node ranges used in PE calculations (number of groups in which a node is found) |   | 1 |
| 251 | PE_RANGELIST | Node ranges used in PE calculations |   | 1 |
| 252 | PE_WTLIST | Node weights used in PE calculations |   | 1 |



 
 

 
### Phylogenetic Endemism single ###
 
**Description:**   PE scores, but not weighted by local ranges.

**Subroutine:**   calc_pe_single

**Reference:**   Rosauer et al (2009) Mol. Ecol. http://dx.doi.org/10.1111/j.1365-294X.2009.04311.x
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 253 | PE_WE_SINGLE | Phylogenetic endemism unweighted by the number of neighbours. Counts each label only once, regardless of how many groups in the neighbourhood it is found in. Useful if your data have sampling biases. Better with small sample windows. |   | 1 |
| 254 | PE_WE_SINGLE_P | Phylogenetic endemism unweighted by the number of neighbours as a proportion of the total tree length. Counts each label only once, regardless of how many groups in the neighbourhood it is found. Useful if your data have sampling biases. |   | 1 |


## Phylogenetic Indices ##
 
 

 
### Count labels on tree ###
 
**Description:**   Count the number of labels that are on the tree

**Subroutine:**   calc_count_labels_on_tree

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 255 | PHYLO_LABELS_ON_TREE_COUNT | The number of labels that are found on the tree, across both neighbour sets |   | 1 |



 
 

 
### Evolutionary distinctiveness ###
 
**Description:**   Evolutionary distinctiveness metrics (AED, ED, ES)
Label values are constant for all neighbourhoods in which each label is found. 

**Subroutine:**   calc_phylo_aed

**Reference:**   Cadotte & Davies (2010) http://dx.doi.org/10.1111/j.1472-4642.2010.00650.x
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Reference* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 256 | PHYLO_AED_LIST | Abundance weighted ED per terminal label |   | 1 | Cadotte & Davies (2010) http://dx.doi.org/10.1111/j.1472-4642.2010.00650.x |
| 257 | PHYLO_ED_LIST | "Fair proportion" partitioning of PD per terminal label |   | 1 | Isaac et al. (2007) http://dx.doi.org/10.1371/journal.pone.0000296 |
| 258 | PHYLO_ES_LIST | Equal splits partitioning of PD per terminal label |   | 1 | Redding & Mooers (2006) http://dx.doi.org/10.1111%2Fj.1523-1739.2006.00555.x |



 
 

 
### Evolutionary distinctiveness per site ###
 
**Description:**   Site level evolutionary distinctiveness

**Subroutine:**   calc_phylo_aed_t

**Reference:**   Cadotte & Davies (2010) http://dx.doi.org/10.1111/j.1472-4642.2010.00650.x
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Reference* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 259 | PHYLO_AED_T | Abundance weighted ED_t (sum of values in PHYLO_AED_LIST times their abundances). This is equivalent to a phylogenetic rarity score (see phylogenetic endemism) |   | 1 | Cadotte & Davies (2010) http://dx.doi.org/10.1111/j.1472-4642.2010.00650.x |



 
 

 
### Evolutionary distinctiveness per terminal taxon per site ###
 
**Description:**   Site level evolutionary distinctiveness per terminal taxon

**Subroutine:**   calc_phylo_aed_t_wtlists

**Reference:**   Cadotte & Davies (2010) http://dx.doi.org/10.1111/j.1472-4642.2010.00650.x
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Reference* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 260 | PHYLO_AED_T_WTLIST | Abundance weighted ED per terminal taxon (the AED score of each taxon multiplied by its abundance in the sample) |   | 1 | Cadotte & Davies (2010) http://dx.doi.org/10.1111/j.1472-4642.2010.00650.x |
| 261 | PHYLO_AED_T_WTLIST_P | Proportional contribution of each terminal taxon to the AED_T score |   | 1 | Cadotte & Davies (2010) http://dx.doi.org/10.1111/j.1472-4642.2010.00650.x |



 
 

 
### Labels not on tree ###
 
**Description:**   Create a hash of the labels that are not on the tree

**Subroutine:**   calc_labels_not_on_tree

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 262 | PHYLO_LABELS_NOT_ON_TREE | A hash of labels that are not found on the tree, across both neighbour sets |   | 1 |
| 263 | PHYLO_LABELS_NOT_ON_TREE_N | Number of labels not on the tree |   | 1 |
| 264 | PHYLO_LABELS_NOT_ON_TREE_P | Proportion of labels not on the tree |   | 1 |



 
 

 
### Labels on tree ###
 
**Description:**   Create a hash of the labels that are on the tree

**Subroutine:**   calc_labels_on_tree

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 265 | PHYLO_LABELS_ON_TREE | A hash of labels that are found on the tree, across both neighbour sets |   | 1 |



 
 

 
### PD clade contributions ###
 
**Description:**   Contribution of each node and its descendents to the Phylogenetic diversity (PD) calculation.

**Subroutine:**   calc_pd_clade_contributions

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 266 | PD_CLADE_CONTR | List of node (clade) contributions to the PD calculation |   | 1 |
| 267 | PD_CLADE_CONTR_P | List of node (clade) contributions to the PD calculation, proportional to the entire tree |   | 1 |
| 268 | PD_CLADE_SCORE | List of PD scores for each node (clade), being the sum of all descendent branch lengths |   | 1 |



 
 

 
### PD clade loss ###
 
**Description:**   How much of the PD would be lost if a clade were to be removed? Calculates the clade PD below the last ancestral node in the neighbour set which would still be in the neighbour set.

**Subroutine:**   calc_pd_clade_loss

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 269 | PD_CLADE_LOSS_CONTR | List of the proportion of the PD score which would be lost if each clade were removed. |   | 1 |
| 270 | PD_CLADE_LOSS_CONTR_P | As per PD_CLADE_LOSS but proportional to the entire tree |   | 1 |
| 271 | PD_CLADE_LOSS_SCORE | List of how much PD would be lost if each clade were removed. |   | 1 |



 
 

 
### PD clade loss (ancestral component) ###
 
**Description:**   How much of the PD clade loss is due to the ancestral branches? The score is zero when there is no ancestral loss.

**Subroutine:**   calc_pd_clade_loss_ancestral

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 272 | PD_CLADE_LOSS_ANC | List of how much ancestral PE would be lost if each clade were removed.  The value is 0 when no ancestral PD is lost. |   | 1 |
| 273 | PD_CLADE_LOSS_ANC_P | List of the proportion of the clade's PD loss that is due to the ancestral branches. |   | 1 |



 
 

 
### Phylogenetic Diversity ###
 
**Description:**   Phylogenetic diversity (PD) based on branch lengths back to the root of the tree.
Uses labels in both neighbourhoods.

**Subroutine:**   calc_pd

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* | *Reference* |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| 274 | PD | Phylogenetic diversity |   | 1 | ![= \\sum_{c \\in C} L_c](http://latex.codecogs.com/png.latex?= \\sum_{c \\in C} L_c%.png) where ![C](http://latex.codecogs.com/png.latex?C%.png)is the set of branches in the minimum spanning path joining the labels in both neighbour sets to the root of the tree,![c](http://latex.codecogs.com/png.latex?c%.png) is a branch (a single segment between two nodes) in the spanning path ![C](http://latex.codecogs.com/png.latex?C%.png), and ![L_c](http://latex.codecogs.com/png.latex?L_c%.png) is the length of branch ![c](http://latex.codecogs.com/png.latex?c%.png).  | Faith (1992) Biol. Cons. http://dx.doi.org/10.1016/0006-3207(92)91201-3 |
| 275 | PD_P | Phylogenetic diversity as a proportion of total tree length |   | 1 | ![= \\frac { PD }{ \\sum_{c \\in C} L_c }](http://latex.codecogs.com/png.latex?= \\frac { PD }{ \\sum_{c \\in C} L_c }%.png) where terms are the same as for PD, but ![c](http://latex.codecogs.com/png.latex?c%.png), ![C](http://latex.codecogs.com/png.latex?C%.png) and ![L_c](http://latex.codecogs.com/png.latex?L_c%.png) are calculated for all nodes in the tree.  |   |
| 276 | PD_P_per_taxon | Phylogenetic diversity per taxon as a proportion of total tree length |   | 1 | ![= \\frac { PD\\_P }{ RICHNESS\\_ALL }](http://latex.codecogs.com/png.latex?= \\frac { PD\\_P }{ RICHNESS\\_ALL }%.png)  |   |
| 277 | PD_per_taxon | Phylogenetic diversity per taxon |   | 1 | ![= \\frac { PD }{ RICHNESS\\_ALL }](http://latex.codecogs.com/png.latex?= \\frac { PD }{ RICHNESS\\_ALL }%.png)  |   |



 
 

 
### Phylogenetic Diversity node list ###
 
**Description:**   Phylogenetic diversity (PD) nodes used.

**Subroutine:**   calc_pd_node_list

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 278 | PD_INCLUDED_NODE_LIST | List of tree nodes included in the PD calculations |   | 1 |



 
 

 
### Phylogenetic Diversity terminal node count ###
 
**Description:**   Number of terminal nodes in neighbour sets 1 and 2.

**Subroutine:**   calc_pd_terminal_node_count

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 279 | PD_INCLUDED_TERMINAL_NODE_COUNT | Count of tree terminal nodes included in the PD calculations |   | 1 |



 
 

 
### Phylogenetic Diversity terminal node list ###
 
**Description:**   Phylogenetic diversity (PD) terminal nodes used.

**Subroutine:**   calc_pd_terminal_node_list

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 280 | PD_INCLUDED_TERMINAL_NODE_LIST | List of tree terminal nodes included in the PD calculations |   | 1 |



 
 

 
### Taxonomic/phylogenetic distinctness ###
 
**Description:**   Taxonomic/phylogenetic distinctness and variation. THIS IS A BETA LEVEL IMPLEMENTATION.

**Subroutine:**   calc_taxonomic_distinctness

**Reference:**   Warwick & Clarke (1995) Mar Ecol Progr Ser. http://dx.doi.org/10.3354/meps129301 ; Clarke & Warwick (2001) Mar Ecol Progr Ser. http://dx.doi.org/10.3354/meps216265
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 281 | TD_DENOMINATOR | Denominator from TD_DISTINCTNESS calcs |   | 1 |
| 282 | TD_DISTINCTNESS | Taxonomic distinctness |   | 1 |
| 283 | TD_NUMERATOR | Numerator from TD_DISTINCTNESS calcs |   | 1 |
| 284 | TD_VARIATION | Variation of the taxonomic distinctness |   | 1 |



 
 

 
### Taxonomic/phylogenetic distinctness, binary weighted ###
 
**Description:**   Taxonomic/phylogenetic distinctness and variation using presence/absence weights.  THIS IS A BETA LEVEL IMPLEMENTATION.

**Subroutine:**   calc_taxonomic_distinctness_binary

**Reference:**   Warwick & Clarke (1995) Mar Ecol Progr Ser. http://dx.doi.org/10.3354/meps129301 ; Clarke & Warwick (2001) Mar Ecol Progr Ser. http://dx.doi.org/10.3354/meps216265
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 285 | TDB_DENOMINATOR | Denominator from TDB_DISTINCTNESS |   | 1 |   |
| 286 | TDB_DISTINCTNESS | Taxonomic distinctness, binary weighted |   | 1 | ![= \\frac{\\sum \\sum_{i \\neq j} \\omega_{ij}}{s(s-1))}](http://latex.codecogs.com/png.latex?= \\frac{\\sum \\sum_{i \\neq j} \\omega_{ij}}{s(s-1))}%.png)where ![\\omega_{ij}](http://latex.codecogs.com/png.latex?\\omega_{ij}%.png)is the path length from label ![i](http://latex.codecogs.com/png.latex?i%.png)to the ancestor node shared with ![j](http://latex.codecogs.com/png.latex?j%.png)  |
| 287 | TDB_NUMERATOR | Numerator from TDB_DISTINCTNESS |   | 1 |   |
| 288 | TDB_VARIATION | Variation of the binary taxonomic distinctness |   | 1 | ![= \\frac{\\sum \\sum_{i \\neq j} \\omega_{ij}^2}{s(s-1))} - \\bar{\\omega}^2](http://latex.codecogs.com/png.latex?= \\frac{\\sum \\sum_{i \\neq j} \\omega_{ij}^2}{s(s-1))} - \\bar{\\omega}^2%.png)where ![\\bar{\\omega} = \\frac{\\sum \\sum_{i \\neq j} \\omega_{ij}}{s(s-1))} \\equiv TDB\\_DISTINCTNESS](http://latex.codecogs.com/png.latex?\\bar{\\omega} = \\frac{\\sum \\sum_{i \\neq j} \\omega_{ij}}{s(s-1))} \\equiv TDB\\_DISTINCTNESS%.png)  |


## Phylogenetic Indices (relative) ##
 
 

 
### Labels not on trimmed tree ###
 
**Description:**   Create a hash of the labels that are not on the trimmed tree

**Subroutine:**   calc_labels_not_on_trimmed_tree

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 289 | PHYLO_LABELS_NOT_ON_TRIMMED_TREE | A hash of labels that are not found on the tree after it has been trimmed to the basedata, across both neighbour sets |   | 1 |
| 290 | PHYLO_LABELS_NOT_ON_TRIMMED_TREE_N | Number of labels not on the trimmed tree |   | 1 |
| 291 | PHYLO_LABELS_NOT_ON_TRIMMED_TREE_P | Proportion of labels not on the trimmed tree |   | 1 |



 
 

 
### Labels on trimmed tree ###
 
**Description:**   Create a hash of the labels that are on the trimmed tree

**Subroutine:**   calc_labels_on_trimmed_tree

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 292 | PHYLO_LABELS_ON_TRIMMED_TREE | A hash of labels that are found on the tree after it has been trimmed to match the basedata, across both neighbour sets |   | 1 |



 
 

 
### Relative Phylogenetic Diversity, type 1 ###
 
**Description:**   Relative Phylogenetic Diversity (RPD).  The ratio of the tree's PD to a null model of PD evenly distributed across terminals and where ancestral nodes are collapsed to zero length.

**Subroutine:**   calc_phylo_rpd1

**Reference:**   Mishler et al. (2014) http://dx.doi.org/10.1038/ncomms5473
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 293 | PHYLO_RPD1 | RPD1 |   | 1 |   |
| 294 | PHYLO_RPD_DIFF1 | How much more or less PD is there than expected, in original tree units. |   | 1 | ![= tree\\_length \\times (PD\\_P - PHYLO\\_RPD\\_NULL1)](http://latex.codecogs.com/png.latex?= tree\\_length \\times (PD\\_P - PHYLO\\_RPD\\_NULL1)%.png)  |
| 295 | PHYLO_RPD_NULL1 | Null model score used as the denominator in the RPD1 calculations |   | 1 |   |



 
 

 
### Relative Phylogenetic Diversity, type 2 ###
 
**Description:**   Relative Phylogenetic Diversity (RPD), type 2.  The ratio of the tree's PD to a null model of PD evenly distributed across all nodes (all branches are of equal length).

**Subroutine:**   calc_phylo_rpd2

**Reference:**   Mishler et al. (2014) http://dx.doi.org/10.1038/ncomms5473
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 296 | PHYLO_RPD2 | RPD2 |   | 1 |   |
| 297 | PHYLO_RPD_DIFF2 | How much more or less PD is there than expected, in original tree units. |   | 1 | ![= tree\\_length \\times (PD\\_P - PHYLO\\_RPD\\_NULL2)](http://latex.codecogs.com/png.latex?= tree\\_length \\times (PD\\_P - PHYLO\\_RPD\\_NULL2)%.png)  |
| 298 | PHYLO_RPD_NULL2 | Null model score used as the denominator in the RPD2 calculations |   | 1 |   |



 
 

 
### Relative Phylogenetic Endemism, type 1 ###
 
**Description:**   Relative Phylogenetic Endemism (RPE).  The ratio of the tree's PE to a null model of PD evenly distributed across terminals, but with the same range per terminal and where ancestral nodes are of zero length (as per RPD1).

**Subroutine:**   calc_phylo_rpe1

**Reference:**   Mishler et al. (2014) http://dx.doi.org/10.1038/ncomms5473
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 299 | PHYLO_RPE1 | Relative Phylogenetic Endemism score |   | 1 |   |
| 300 | PHYLO_RPE_DIFF1 | How much more or less PE is there than expected, in original tree units. |   | 1 | ![= tree\\_length \\times (PE\\_WE\\_P - PHYLO\\_RPE\\_NULL1)](http://latex.codecogs.com/png.latex?= tree\\_length \\times (PE\\_WE\\_P - PHYLO\\_RPE\\_NULL1)%.png)  |
| 301 | PHYLO_RPE_NULL1 | Null score used as the denominator in the RPE calculations |   | 1 |   |



 
 

 
### Relative Phylogenetic Endemism, type 2 ###
 
**Description:**   Relative Phylogenetic Endemism (RPE).  The ratio of the tree's PE to a null model where PE is calculated using a tree where all branches are of equal length.

**Subroutine:**   calc_phylo_rpe2

**Reference:**   Mishler et al. (2014) http://dx.doi.org/10.1038/ncomms5473
 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 302 | PHYLO_RPE2 | Relative Phylogenetic Endemism score, type 2 |   | 1 |   |
| 303 | PHYLO_RPE_DIFF2 | How much more or less PE is there than expected, in original tree units. |   | 1 | ![= tree\\_length \\times (PE\\_WE\\_P - PHYLO\\_RPE\\_NULL1)](http://latex.codecogs.com/png.latex?= tree\\_length \\times (PE\\_WE\\_P - PHYLO\\_RPE\\_NULL1)%.png)  |
| 304 | PHYLO_RPE_NULL2 | Null score used as the denominator in the RPE2 calculations |   | 1 |   |


## Phylogenetic Turnover ##
 
 

 
### Phylo Jaccard ###
 
**Description:**   Jaccard phylogenetic dissimilarity between two sets of taxa, represented by spanning sets of branches


**Subroutine:**   calc_phylo_jaccard

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 305 | PHYLO_JACCARD | Phylo Jaccard score | cluster metric | 1 | ![= 1 - (A / (A + B + C))](http://latex.codecogs.com/png.latex?= 1 - (A / (A + B + C))%.png) where A is the length of shared branches, and B and C are the length of branches found only in neighbour sets 1 and 2  |



 
 

 
### Phylo S2 ###
 
**Description:**   S2 phylogenetic dissimilarity between two sets of taxa, represented by spanning sets of branches


**Subroutine:**   calc_phylo_s2

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 306 | PHYLO_S2 | Phylo S2 score | cluster metric | 1 | ![= 1 - (A / (A + min (B, C)))](http://latex.codecogs.com/png.latex?= 1 - (A / (A + min (B, C)))%.png) where A is the length of shared branches, and B and C are the length of branches found only in neighbour sets 1 and 2  |



 
 

 
### Phylo Sorenson ###
 
**Description:**   Sorenson phylogenetic dissimilarity between two sets of taxa, represented by spanning sets of branches


**Subroutine:**   calc_phylo_sorenson

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 307 | PHYLO_SORENSON | Phylo Sorenson score | cluster metric | 1 | ![1 - (2A / (2A + B + C))](http://latex.codecogs.com/png.latex?1 - (2A / (2A + B + C))%.png) where A is the length of shared branches, and B and C are the length of branches found only in neighbour sets 1 and 2  |



 
 

 
### Phylogenetic ABC ###
 
**Description:**   Calculate the shared and not shared branch lengths between two sets of labels

**Subroutine:**   calc_phylo_abc

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 308 | PHYLO_A | Length of branches shared by labels in nbr sets 1 and 2 |   | 1 |
| 309 | PHYLO_ABC | Length of all branches associated with labels in nbr sets 1 and 2 |   | 1 |
| 310 | PHYLO_B | Length of branches unique to labels in nbr set 1 |   | 1 |
| 311 | PHYLO_C | Length of branches unique to labels in nbr set 2 |   | 1 |


## Rarity ##
 
 

 
### Rarity central ###
 
**Description:**   Calculate rarity for species only in neighbour set 1, but with local sample counts calculated from both neighbour sets. 
Uses the same algorithm as the endemism indices but weights by sample counts instead of by groups occupied.

**Subroutine:**   calc_rarity_central

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 312 | RAREC_CWE | Corrected weighted rarity |   | 1 | ![= \\frac{RAREC\\_WE}{RAREC\\_RICHNESS}](http://latex.codecogs.com/png.latex?= \\frac{RAREC\\_WE}{RAREC\\_RICHNESS}%.png)  |
| 313 | RAREC_RICHNESS | Richness used in RAREC_CWE (same as index RICHNESS_SET1). |   | 1 |   |
| 314 | RAREC_WE | Weighted rarity |   | 1 | ![= \\sum_{t \\in T} \\frac {s_t} {S_t}](http://latex.codecogs.com/png.latex?= \\sum_{t \\in T} \\frac {s_t} {S_t}%.png) where ![t](http://latex.codecogs.com/png.latex?t%.png) is a label (taxon) in the set of labels (taxa) ![T](http://latex.codecogs.com/png.latex?T%.png) across neighbour set 1, ![s_t](http://latex.codecogs.com/png.latex?s_t%.png) is sum of the sample counts for ![t](http://latex.codecogs.com/png.latex?t%.png) across the elements in neighbour sets 1 & 2 (its value in list ABC3_LABELS_ALL), and ![S_t](http://latex.codecogs.com/png.latex?S_t%.png) is the total number of samples across the data set for label ![t](http://latex.codecogs.com/png.latex?t%.png) (unless the total sample count is specified at import).  |



 
 

 
### Rarity central lists ###
 
**Description:**   Lists used in rarity central calculations

**Subroutine:**   calc_rarity_central_lists

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 315 | RAREC_RANGELIST | List of ranges for each label used in the rarity central calculations |   | 1 |
| 316 | RAREC_WTLIST | List of weights for each label used in therarity central calculations |   | 1 |



 
 

 
### Rarity whole ###
 
**Description:**   Calculate rarity using all species in both neighbour sets.
Uses the same algorithm as the endemism indices but weights 
by sample counts instead of by groups occupied.


**Subroutine:**   calc_rarity_whole

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 317 | RAREW_CWE | Corrected weighted rarity |   | 1 | ![= \\frac{RAREW\\_WE}{RAREW\\_RICHNESS}](http://latex.codecogs.com/png.latex?= \\frac{RAREW\\_WE}{RAREW\\_RICHNESS}%.png)  |
| 318 | RAREW_RICHNESS | Richness used in RAREW_CWE (same as index RICHNESS_ALL). |   | 1 |   |
| 319 | RAREW_WE | Weighted rarity |   | 1 | ![= \\sum_{t \\in T} \\frac {s_t} {S_t}](http://latex.codecogs.com/png.latex?= \\sum_{t \\in T} \\frac {s_t} {S_t}%.png) where ![t](http://latex.codecogs.com/png.latex?t%.png) is a label (taxon) in the set of labels (taxa) ![T](http://latex.codecogs.com/png.latex?T%.png) across both neighbour sets, ![s_t](http://latex.codecogs.com/png.latex?s_t%.png) is sum of the sample counts for ![t](http://latex.codecogs.com/png.latex?t%.png) across the elements in neighbour sets 1 & 2 (its value in list ABC3_LABELS_ALL), and ![S_t](http://latex.codecogs.com/png.latex?S_t%.png) is the total number of samples across the data set for label ![t](http://latex.codecogs.com/png.latex?t%.png) (unless the total sample count is specified at import).  |



 
 

 
### Rarity whole lists ###
 
**Description:**   Lists used in rarity whole calculations

**Subroutine:**   calc_rarity_whole_lists

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 320 | RAREW_RANGELIST | List of ranges for each label used in the rarity whole calculations |   | 1 |
| 321 | RAREW_WTLIST | List of weights for each label used in therarity whole calculations |   | 1 |


## Taxonomic Dissimilarity and Comparison ##
 
 

 
### Beta diversity ###
 
**Description:**   Beta diversity between neighbour sets 1 and 2.


**Subroutine:**   calc_beta_diversity

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 322 | BETA_2 | The other beta | cluster metric | 1 | ![= \\frac{A + B + C}{max((A+B), (A+C))} - 1](http://latex.codecogs.com/png.latex?= \\frac{A + B + C}{max((A+B), (A+C))} - 1%.png) where ![A](http://latex.codecogs.com/png.latex?A%.png)is the count of labels found in both neighbour sets, ![B](http://latex.codecogs.com/png.latex?B%.png) is the count unique to neighbour set 1, and ![C](http://latex.codecogs.com/png.latex?C%.png) is the count unique to neighbour set 2. Use the [Label counts](#Label_counts) calculation to derive these directly.  |



 
 

 
### Bray-Curtis non-metric ###
 
**Description:**   Bray-Curtis dissimilarity between two sets of labels.
Reduces to the Sorenson metric for binary data (where sample counts are 1 or 0).

**Subroutine:**   calc_bray_curtis

**Formula:**
   ![= 1 - \\frac{2W}{A + B}](http://latex.codecogs.com/png.latex?= 1 - \\frac{2W}{A + B}%.png) where ![A](http://latex.codecogs.com/png.latex?A%.png) is the sum of the sample counts in neighbour set 1, ![B](http://latex.codecogs.com/png.latex?B%.png) is the sum of sample counts in neighbour set 2, and ![W=\\sum^n_{i=1} min(sample\\_count\\_label_{i_{set1}},sample\\_count\\_label_{i_{set2}})](http://latex.codecogs.com/png.latex?W=\\sum^n_{i=1} min(sample\\_count\\_label_{i_{set1}},sample\\_count\\_label_{i_{set2}})%.png) (meaning it sums the minimum of the sample counts for each of the ![n](http://latex.codecogs.com/png.latex?n%.png) labels across the two neighbour sets), 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 323 | BC_A | The A factor used in calculations (see formula) |   | 1 |
| 324 | BC_B | The B factor used in calculations (see formula) |   | 1 |
| 325 | BC_W | The W factor used in calculations (see formula) |   | 1 |
| 326 | BRAY_CURTIS | Bray Curtis dissimilarity | cluster metric | 1 |



 
 

 
### Bray-Curtis non-metric, group count normalised ###
 
**Description:**   Bray-Curtis dissimilarity between two neighbourhoods, 
where the counts in each neighbourhood are divided 
by the number of groups in each neighbourhood to correct
for unbalanced sizes.


**Subroutine:**   calc_bray_curtis_norm_by_gp_counts

**Formula:**
   ![= 1 - \\frac{2W}{A + B}](http://latex.codecogs.com/png.latex?= 1 - \\frac{2W}{A + B}%.png) where ![A](http://latex.codecogs.com/png.latex?A%.png) is the sum of the sample counts in neighbour set 1 normalised (divided) by the number of groups, ![B](http://latex.codecogs.com/png.latex?B%.png) is the sum of the sample counts in neighbour set 2 normalised by the number of groups, and ![W = \\sum^n_{i=1} min(sample\\_count\\_label_{i_{set1}},sample\\_count\\_label_{i_{set2}})](http://latex.codecogs.com/png.latex?W = \\sum^n_{i=1} min(sample\\_count\\_label_{i_{set1}},sample\\_count\\_label_{i_{set2}})%.png) (meaning it sums the minimum of the normalised sample counts for each of the ![n](http://latex.codecogs.com/png.latex?n%.png) labels across the two neighbour sets), 

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 327 | BCN_A | The A factor used in calculations (see formula) |   | 1 |
| 328 | BCN_B | The B factor used in calculations (see formula) |   | 1 |
| 329 | BCN_W | The W factor used in calculations (see formula) |   | 1 |
| 330 | BRAY_CURTIS_NORM | Bray Curtis dissimilarity normalised by groups | cluster metric | 1 |



 
 

 
### Jaccard ###
 
**Description:**   Jaccard dissimilarity between the labels in neighbour sets 1 and 2.

**Subroutine:**   calc_jaccard

**Formula:**
   ![= 1 - \\frac{A}{A + B + C}](http://latex.codecogs.com/png.latex?= 1 - \\frac{A}{A + B + C}%.png) where ![A](http://latex.codecogs.com/png.latex?A%.png) is the count of labels found in both neighbour sets, ![B](http://latex.codecogs.com/png.latex?B%.png) is the count unique to neighbour set 1, and ![C](http://latex.codecogs.com/png.latex?C%.png) is the count unique to neighbour set 2. Use the [Label counts](#Label_counts) calculation to derive these directly.

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 331 | JACCARD | Jaccard value, 0 is identical, 1 is completely dissimilar | cluster metric | 1 |



 
 

 
### Kulczynski 2 ###
 
**Description:**   Kulczynski 2 dissimilarity between two sets of labels.


**Subroutine:**   calc_kulczynski2

**Formula:**
   ![= 1 - 0.5 * (\\frac{A}{A + B} + \\frac{A}{A + C})](http://latex.codecogs.com/png.latex?= 1 - 0.5 * (\\frac{A}{A + B} + \\frac{A}{A + C})%.png) where ![A](http://latex.codecogs.com/png.latex?A%.png) is the count of labels found in both neighbour sets, ![B](http://latex.codecogs.com/png.latex?B%.png) is the count unique to neighbour set 1, and ![C](http://latex.codecogs.com/png.latex?C%.png) is the count unique to neighbour set 2. Use the [Label counts](#Label_counts) calculation to derive these directly.

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 332 | KULCZYNSKI2 | Kulczynski 2 index | cluster metric | 1 |



 
 

 
### Nestedness-resultant ###
 
**Description:**   Nestedness-resultant index between the labels in neighbour sets 1 and 2. 

**Subroutine:**   calc_nestedness_resultant

**Reference:**   Baselga (2010) Glob Ecol Biogeog.  http://dx.doi.org/10.1111/j.1466-8238.2009.00490.x
 

**Formula:**
   ![=\\frac{ \\left | B - C \\right | }{ 2A + B + C } \\times \\frac { A }{ A + min (B, C) }= SORENSON - S2](http://latex.codecogs.com/png.latex?=\\frac{ \\left | B - C \\right | }{ 2A + B + C } \\times \\frac { A }{ A + min (B, C) }= SORENSON - S2%.png) where ![A](http://latex.codecogs.com/png.latex?A%.png) is the count of labels found in both neighbour sets, ![B](http://latex.codecogs.com/png.latex?B%.png) is the count unique to neighbour set 1, and ![C](http://latex.codecogs.com/png.latex?C%.png) is the count unique to neighbour set 2. Use the [Label counts](#Label_counts) calculation to derive these directly.

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 333 | NEST_RESULTANT | Nestedness-resultant index | cluster metric | 1 |



 
 

 
### Rao's quadratic entropy, taxonomically weighted ###
 
**Description:**   Calculate Rao's quadratic entropy for a taxonomic weights scheme.
Should collapse to be the Simpson index for presence/absence data.

**Subroutine:**   calc_tx_rao_qe

**Formula:**
   ![= \\sum_{i \\in L} \\sum_{j \\in L} d_{ij} p_i p_j](http://latex.codecogs.com/png.latex?= \\sum_{i \\in L} \\sum_{j \\in L} d_{ij} p_i p_j%.png) where ![p_i](http://latex.codecogs.com/png.latex?p_i%.png) and ![p_j](http://latex.codecogs.com/png.latex?p_j%.png) are the sample counts for the i'th and j'th labels, ![d_{ij}](http://latex.codecogs.com/png.latex?d_{ij}%.png) is a value of zero if ![i = j](http://latex.codecogs.com/png.latex?i = j%.png) , and a value of 1 otherwise. ![L](http://latex.codecogs.com/png.latex?L%.png) is the set of labels across both neighbour sets.

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 334 | TX_RAO_QE | Taxonomically weighted quadratic entropy |   | 1 |
| 335 | TX_RAO_TLABELS | List of labels and values used in the TX_RAO_QE calculations |   | 1 |
| 336 | TX_RAO_TN | Count of comparisons used to calculate TX_RAO_QE |   | 1 |



 
 

 
### S2 ###
 
**Description:**   S2 dissimilarity between two sets of labels


**Subroutine:**   calc_s2

**Reference:**   Lennon et al. (2001) J Animal Ecol.  http://dx.doi.org/10.1046/j.0021-8790.2001.00563.x
 

**Formula:**
   ![= 1 - \\frac{A}{A + min(B, C)}](http://latex.codecogs.com/png.latex?= 1 - \\frac{A}{A + min(B, C)}%.png) where ![A](http://latex.codecogs.com/png.latex?A%.png) is the count of labels found in both neighbour sets, ![B](http://latex.codecogs.com/png.latex?B%.png) is the count unique to neighbour set 1, and ![C](http://latex.codecogs.com/png.latex?C%.png) is the count unique to neighbour set 2. Use the [Label counts](#Label_counts) calculation to derive these directly.

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 337 | S2 | S2 dissimilarity index | cluster metric | 1 |



 
 

 
### Simpson and Shannon ###
 
**Description:**   Simpson and Shannon diversity metrics using samples from all neighbourhoods.


**Subroutine:**   calc_simpson_shannon

**Formula:**
    For each index formula, ![p_i](http://latex.codecogs.com/png.latex?p_i%.png) is the number of samples of the i'th label as a proportion of the total number of samples ![n](http://latex.codecogs.com/png.latex?n%.png) in the neighbourhoods.

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* | *Formula* |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 338 | SHANNON_E | Shannon's evenness (H / HMAX) |   | 1 | ![Evenness = \\frac{H}{HMAX}](http://latex.codecogs.com/png.latex?Evenness = \\frac{H}{HMAX}%.png)  |
| 339 | SHANNON_H | Shannon's H |   | 1 | ![H = - \\sum^n_{i=1} (p_i \\cdot ln (p_i))](http://latex.codecogs.com/png.latex?H = - \\sum^n_{i=1} (p_i \\cdot ln (p_i))%.png)  |
| 340 | SHANNON_HMAX | maximum possible value of Shannon's H |   | 1 | ![HMAX = ln(richness)](http://latex.codecogs.com/png.latex?HMAX = ln(richness)%.png)  |
| 341 | SIMPSON_D | Simpson's D. A score of zero is more similar. |   | 1 | ![D = 1 - \\sum^n_{i=1} p_i^2](http://latex.codecogs.com/png.latex?D = 1 - \\sum^n_{i=1} p_i^2%.png)  |



 
 

 
### Sorenson ###
 
**Description:**   Sorenson dissimilarity between two sets of labels.
It is the complement of the (unimplemented) Czechanowski index, and numerically the same as Whittaker's beta.

**Subroutine:**   calc_sorenson

**Formula:**
   ![= 1 - \\frac{2A}{2A + B + C}](http://latex.codecogs.com/png.latex?= 1 - \\frac{2A}{2A + B + C}%.png) where ![A](http://latex.codecogs.com/png.latex?A%.png) is the count of labels found in both neighbour sets, ![B](http://latex.codecogs.com/png.latex?B%.png) is the count unique to neighbour set 1, and ![C](http://latex.codecogs.com/png.latex?C%.png) is the count unique to neighbour set 2. Use the [Label counts](#Label_counts) calculation to derive these directly.

| *Index #* | *Index* | *Index description* | *Valid cluster metric?* | *Minimum number of neighbour sets* |
| ---- | ---- | ---- | ---- | ---- |
| 342 | SORENSON | Sorenson index | cluster metric | 1 |


<img src="http://www.codecogs.com/images/poweredbycc.gif" width="102" height="34" vspace="5" border="0" alt="Powered by CodeCogs"/>
http://www.codecogs.com
