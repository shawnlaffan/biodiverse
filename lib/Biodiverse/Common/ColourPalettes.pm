package Biodiverse::Common::ColourPalettes;
use strict;
use warnings;

#  common colour palettes

#  should be in a Common.pm subclass
sub get_palette_colorbrewer13_paired {
    # Paired colour scheme from colorbrewer, plus a dark grey
    #  note - this works poorly when 9 or fewer groups are selected
    no warnings 'qw';  #  we know the hashes are not comments
    my @palette = qw  '#A6CEE3 #1F78B4 #B2DF8A #33A02C
        #FB9A99 #E31A1C #FDBF6F #FF7F00
        #CAB2D6 #6A3D9A #FFFF99 #B15928
        #4B4B4B';
    return wantarray ? @palette : [@palette];
}

sub get_palette_colorbrewer9_paired {
    # 9 class paired colour scheme from www.colorbrewer2.org
    my @palette = ('#a6cee3','#1f78b4','#b2df8a','#33a02c','#fb9a99','#e31a1c','#fdbf6f','#ff7f00','#cab2d6');
    return wantarray ? @palette : [@palette];
}

sub get_palette_colorbrewer9_set1 {
    # Set1 colour scheme from www.colorbrewer2.org
    my @palette = ('#E41A1C', '#377EB8', '#4DAF4A', '#984EA3',
        '#FF7F00', '#FFFF33', '#A65628', '#F781BF',
        '#999999');
    return wantarray ? @palette : [@palette];
}

sub get_palette_colorbrewer9_set3 {
    # 9 class paired colour scheme from www.colorbrewer2.org
    my @palette = ('#8dd3c7','#ffffb3','#bebada','#fb8072','#80b1d3','#fdb462','#b3de69','#fccde5','#d9d9d9');
    return wantarray ? @palette : [@palette];
}

1;