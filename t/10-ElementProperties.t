#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use Test::Lib;

use Test::More;
use Test::Exception;

use English qw(
    -no_match_vars
);

use Data::Section::Simple qw(
    get_data_section
);
use Data::Dumper;

use Biodiverse::TestHelpers qw /:element_properties/;
use Biodiverse::ElementProperties;


{
    my %remap_data = (
        input_element_cols => [1,2],
        remapped_element_cols => [3,4],
    );

    my $string = Data::Dumper::Dumper \%remap_data;
    $string =~ s/[\s\n\r]//g;
    $string =~ s/^\$VAR1=//;
    $string =~ s/;$//;

    my $tmp_obj = get_import_data();
    my $ep_f = $tmp_obj->filename;
    my $remap = Biodiverse::ElementProperties->new;
    my $success = eval { $remap->import_data(%remap_data, file => $ep_f) };
    diag $EVAL_ERROR if $EVAL_ERROR;

    is ($success, 1, $string);

    #print Dumper ($remap);

    #  need to add tests for get methods
}


#  add properties after importation
{
    my $tmp_bd_file = write_data_to_temp_file (get_basedata_data());
    my $bd_fname = $tmp_bd_file->filename;
    my $bd = Biodiverse::BaseData->new (
        NAME       => 'test add label props after import',
        CELL_SIZES => [100000, 100000],
    );
    $bd->import_data (
        input_files   => [$bd_fname],
        label_columns => [1, 2],
        group_columns => [3, 4],
        #cell_sizes    => [100000, 100000],
        skip_lines_with_undef_groups => 1,
    );
    
    #  need to adapt to the data in the data block
    my @prop_names = qw /range sample_count exclude someprop/;
    my %prop_col_hash;
    @prop_col_hash{@prop_names} = (5 .. 8);
    
    my $tmp_remap_file = write_data_to_temp_file (get_label_properties_data());
    my $fname = $tmp_remap_file->filename;
    my %lbprops_args = (
        input_element_cols => [1,2],
        %prop_col_hash,
    );

    my $lb_props = Biodiverse::ElementProperties->new;
    my $success = eval { $lb_props->import_data(%lbprops_args, file => $fname) };    
    diag $EVAL_ERROR if $EVAL_ERROR;
    
    ok ($success == 1, 'import label properties without error');
    
    eval {
        $bd->assign_element_properties (
            type              => 'labels',
            properties_object => $lb_props,
        );
    };
    my $e = $EVAL_ERROR;
    isnt ($e, undef, 'no eval errors assigning label properties');
    
    #  now iterate over the props and check we are defined correctly (and in some cases undef)
    my $fld_text = uc 'range sample_count someprop';
    my @flds = (split / /, $fld_text);
    my %expected = (
        'Genus:sp1' => [undef, 1,     5],
        'Genus:sp2' => [200,   1000,  7],
        'Genus:sp3' => [undef, undef, undef],
        'Genus:sp4' => [undef, undef, undef],
    );
    my %empty = (
        'Genus:sp1' => 0,
        'Genus:sp2' => 0,
        'Genus:sp3' => 1,
        'Genus:sp4' => 1,
    );

    my $lb = $bd->get_labels_ref;
    foreach my $label (sort keys %expected) {
        my $list = $lb->get_list_ref (
            element => $label,
            list    => 'PROPERTIES',
        );
        if ($empty{$label}) {
            ok (scalar keys %$list == 0, "$label list is empty");
        }
        else {
            ok (scalar keys %$list > 0, "$label list has values");
        }

        my $i = 0;
        foreach my $fld_name (@flds) {
            my $expval = $expected{$label}->[$i];
            my $expstr = $expval // 'undef';
            is ($list->{$fld_name}, $expval, "$label $fld_name is $expstr");
            $i ++;
        }
    }

    # now test deleting the element properties, making sure everything is gone.
    $bd->delete_element_properties();
    
    $lb = $bd->get_labels_ref;

    foreach my $label ($bd->get_labels) {
        my $list = $lb->get_list_ref (
            element => $label,
            list    => 'PROPERTIES',
            );
        ok (scalar keys %$list == 0, "$label list is empty");
    }

    my $gp = $bd->get_groups_ref;
    foreach my $group ($bd->get_groups) {
        my $list = $gp->get_list_ref (
            element => $group,
            list    => 'PROPERTIES',
            );
        ok (scalar keys %$list == 0, "$group list is empty");
    }

    
}

done_testing();


#######################################

sub get_import_data {
    my $tmp_obj = File::Temp->new (TEMPLATE => 'biodiverseXXXX');
    my $ep_f = $tmp_obj->filename;
    print $tmp_obj get_element_properties_test_data();
    $tmp_obj -> close;
    
    return $tmp_obj;
}

sub get_label_properties_data {
    return get_data_section('LABEL_PROPERTIES');
}

sub get_basedata_data {
    return get_data_section('BASEDATA');
}

__DATA__


@@ LABEL_PROPERTIES
rec_num,genus,species,new_genus,new_species,range,sample_count,exclude,someprop
1,Genus,sp1,Genus,sp2,,1,1,5
10,Genus,sp18,Genus,sp2,,,,6
2000,Genus,sp2,,,200,1000,,7

@@ BASEDATA
num,genus,species,x,y
1,Genus,sp1,3229628.144,3078197.708
2,Genus,sp1,3216986.364,2951192.309
3,Genus,sp1,3216038.331,2960749.322
4,Genus,sp2,3217265.071,2960874.379
5,Genus,sp2,3205745.731,2963059.801
6,Genus,sp2,3214891.41,2928147.063
7,Genus,sp2,3219317.279,2971029.526
8,Genus,sp2,3222862.015,2964370.214
10,Genus,sp2,3212458.146,2941450.158
11,Genus,sp2,3190927.597,2934733.879
13,Genus,sp1,3219062.392,2957000.395
14,Genus,sp2,3214927.972,2957598.276
17,Genus,sp2,3224316.252,2949812.85
18,Genus,sp2,3213747.029,2958541.561
19,Genus,sp3,3217002.785,2851990.43
20,Genus,sp3,3218154.45,2860837.224
21,Genus,sp3,3269737.444,2861722.441
22,Genus,sp3,3271211.081,2856803.277
27,Genus,sp1,3674506.462,2346302.09
32,Genus,sp4,3508293.759,2205062.899

