#!/usr/bin/perl -w
use strict;
use warnings;
use English qw / -no_match_vars /;

use Test::More tests => 1;
use Test::Exception;

use mylib;

use Biodiverse::TestHelpers qw /:element_properties/;

local $| = 1;

use mylib;

use Biodiverse::ElementProperties;
use Data::Dumper;

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
    my $remap = Biodiverse::ElementProperties -> new;
    my $success = eval { $remap->import_data(%remap_data, file => $ep_f) };    
    diag $EVAL_ERROR if $EVAL_ERROR;
    
    is ($success, 1, $string);
    
    #  need to add tests for get methods
}


sub get_import_data {
    my $tmp_obj = File::Temp->new;
    my $ep_f = $tmp_obj->filename;
    print $tmp_obj get_element_properties_test_data();
    $tmp_obj -> close;
    
    return $tmp_obj;
}

