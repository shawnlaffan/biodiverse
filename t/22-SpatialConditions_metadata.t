#!/usr/bin/perl -w

use strict;
use warnings;
use Carp;
use English qw{
    -no_match_vars
};

use Scalar::Util qw /reftype/;

use Test::Lib;
use Test::More;

use Biodiverse::BaseData;
use Biodiverse::SpatialConditions;


test_metadata();

done_testing();

sub test_metadata {
    my $bd = Biodiverse::BaseData->new(CELL_SIZES => [1,1]);
    my $object = eval {
        Biodiverse::SpatialConditions->new(BASEDATA_REF => $bd, conditions => 'sp_select_all()');
    };
    croak $@ if $@;

    my $pfx = 'get_metadata_sp_';  #  avoid export subs
    my $x = $object->get_subs_with_prefix (prefix => $pfx);
    
    my %meta_defaults = Biodiverse::Metadata::SpatialConditions->_get_method_default_hash();

    my %meta_keys;

    my (%descr, %parameters);
    foreach my $meta_sub (sort keys %$x) {
        my $calc = $meta_sub;
        $calc =~ s/^get_metadata_//;

        my $metadata = $object->get_metadata (sub => $calc);

        $descr{$metadata->get_description}{$meta_sub}++;
        
        @meta_keys{keys %$metadata} = (1) x scalar keys %$metadata;
        
        #  check the reftypes are valid (match the defaults)
        subtest "reftypes for $calc match defaults" => sub {   
            foreach my $key (keys %$metadata) {
                is (
                    reftype ($metadata->{$key}),
                    reftype ($meta_defaults{$key}),
                    $key,
                );
            }
        }
    }

    subtest 'No duplicate descriptions' => sub {
        check_duplicates (\%descr);
    };
}

sub check_duplicates {
    my $hashref = shift;
    foreach my $key (sort keys %$hashref) {
        my $count = scalar keys %{$hashref->{$key}};
        my $res = is ($count, 1, "$key is unique");
        if (!$res) {
            diag "Source calcs for $key are: " . join ' ', sort keys %{$hashref->{$key}};
        }
    }
    foreach my $null_key (qw /no_name no_description/) {
        my $res = ok (!exists $hashref->{$null_key}, "hash does not contain $null_key");
        if (exists $hashref->{$null_key}) {
            diag "Source calcs for $null_key are: " . join ' ', sort keys %{$hashref->{$null_key}};
        }
    }    
    
}

1;
