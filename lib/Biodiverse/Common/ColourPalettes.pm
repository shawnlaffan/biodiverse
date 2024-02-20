package Biodiverse::Common::ColourPalettes;
use strict;
use warnings;

our $VERSION = '4.99_002';

#  A set of colour palettes.
#  Add to as needed.

sub get_palette_colorbrewer_paired {
    # Paired colour scheme from colorbrewer, plus a dark grey
    #  note - this works poorly when 9 or fewer groups are selected
    no warnings 'qw';  #  we know the hashes are not comments
    my @palette = (
        '#A6CEE3', '#1F78B4', '#B2DF8A', '#33A02C',
        '#FB9A99', '#E31A1C', '#FDBF6F', '#FF7F00',
        '#CAB2D6', '#6A3D9A', '#FFFF99', '#B15928',
        '#4B4B4B',
    );
    return wantarray ? @palette : [@palette];
}

sub get_palette_colorbrewer_set1 {
    # 9 class colour scheme from www.colorbrewer2.org
    my @palette = (
        '#E41A1C', '#377EB8', '#4DAF4A', '#984EA3',
        '#FF7F00', '#FFFF33', '#A65628', '#F781BF',
        '#999999',
    );
    return wantarray ? @palette : [@palette];
}

sub get_palette_colorbrewer_set2 {
    # 8 class colour scheme from www.colorbrewer2.org
    my @palette = (
        '#66c2a5', '#fc8d62', '#8da0cb', '#e78ac3',
        '#a6d854', '#ffd92f', '#e5c494', '#b3b3b3',
    );
    return wantarray ? @palette : [@palette];
}

sub get_palette_colorbrewer_set3 {
    # 12 class colour scheme from www.colorbrewer2.org
    my @palette = (
        '#8dd3c7', '#ffffb3', '#bebada', '#fb8072',
        '#80b1d3', '#fdb462', '#b3de69', '#fccde5',
        '#d9d9d9', '#bc80bd', '#ccebc5', '#ffed6f',
    );
    return wantarray ? @palette : [@palette];
}

sub get_palette_colorbrewer_pastel1 {
    # 9 class colour scheme from www.colorbrewer2.org
    my @palette = (
        '#fbb4ae', '#b3cde3', '#ccebc5', '#decbe4',
        '#fed9a6', '#ffffcc', '#e5d8bd', '#fddaec',
        '#f2f2f2'
    );
    return wantarray ? @palette : [@palette];
}

sub get_palette_colorbrewer_pastel2 {
    # 8 class colour scheme from www.colorbrewer2.org
    my @palette = (
        '#b3e2cd', '#fdcdac', '#cbd5e8', '#f4cae4',
        '#e6f5c9', '#fff2ae', '#f1e2cc', '#cccccc'
    );
    return wantarray ? @palette : [@palette];
}

sub get_palette_colorbrewer_accent {
    # 8 class colour scheme from www.colorbrewer2.org
    my @palette = (
        '#7fc97f', '#beaed4', '#fdc086', '#ffff99',
        '#386cb0', '#f0027f', '#bf5b17', '#666666'
    );
    return wantarray ? @palette : [@palette];
}

sub get_palette_colorbrewer_dark2 {
    # 8 class colour scheme from www.colorbrewer2.org
    my @palette = (
        '#1b9e77', '#d95f02', '#7570b3', '#e7298a',
        '#66a61e', '#e6ab02', '#a6761d', '#666666',
    );
    return wantarray ? @palette : [@palette];
}



1;