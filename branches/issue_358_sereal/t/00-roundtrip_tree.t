#!/usr/bin/perl -w

#  Tests for self referential tree save and reload.
#  Assures us that the data can be serialised, saved out and then reloaded
#  without throwing an exception.

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };

use Scalar::Util qw /blessed unweaken/;
use Devel::Refcount qw /refcount/;

use Data::Dumper;
use Sereal ();
use Storable ();
#use YAML::Syck ();
use YAML::XS qw /Load Dump/;

use Scalar::Util qw /weaken/;


local $| = 1;

use Test::More;
use Test::Exception;

test_save_and_reload();
test_save_and_reload('no_weaken');

done_testing();

sub get_data {
    my $no_weaken_refs = shift;

    my @children;

    my $root = {
        name     => 'root',
        children => \@children,
    };

    my %hash = (
        TREE => $root,
        TREE_BY_NAME => {},
    );

    foreach my $i (0 .. 3) {
        my $child = {
            PARENT => $root,
            NAME => $i,
        };
        if (!$no_weaken_refs) {
            weaken $child->{PARENT};
        }
        push @children, $child;
        $hash{TREE_BY_NAME}{$i} = $child;
    }

    return \%hash;
}


sub test_save_and_reload {
    my $no_weaken = shift;
    my $data = get_data ($no_weaken);

    local $Data::Dumper::Purity    = 1;
    local $Data::Dumper::Terse     = 1;
    local $Data::Dumper::Sortkeys  = 1;
    local $Data::Dumper::Indent    = 1;
    local $Data::Dumper::Quotekeys = 0;

    my $weaken_text = $no_weaken ? 'not weakened' : 'weakened';

    my $encoded_data;
    
    #diag "Working on Sereal";

    my $encoder = Sereal::Encoder->new;
    my $decoder = Sereal::Decoder->new;
    my $decoded_data;

    lives_ok {
        $encoded_data = $encoder->encode($data)
    } "Encoded using Sereal, $weaken_text";

    lives_ok {
        $decoder->decode ($encoded_data, $decoded_data);
    } "Decoded using Sereal, $weaken_text";

    is_deeply ($decoded_data, $data, "Data structures match for Sereal, $weaken_text");

    #diag "Working on YAML::XS";

    lives_ok {
        $encoded_data = Dump $data;
    } "Encoded using YAML::XS, $weaken_text";

    lives_ok {
        $decoded_data = Load $encoded_data;
    } "Decoded using YAML::XS, $weaken_text";

    is_deeply ($decoded_data, $data, "Data structures match for YAML::XS, $weaken_text");

}




1;
