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

#  Child to parent refs are weak, root node is stored once in the hash
test_save_and_reload();

#  Child to parent refs are weak, but we store the root node twice in the hash
#  (second time is in the "by name" subhash)
test_save_and_reload(store_root_by_name => 1);

#  child to parent refs are strong
#  Should pass
test_save_and_reload(no_weaken => 1);


done_testing();

sub get_data {
    my %args = @_;

    diag $];

    my @children;

    my $root = {
        name     => 'root',
        children => \@children,
    };

    my %hash = (
        TREE => $root,
        TREE_BY_NAME => {},
    );

    if ($args{store_root_by_name}) {
        $hash{TREE_BY_NAME}{root} = $root;
    }

    foreach my $i (0 .. 3) {
        my $child = {
            PARENT => $root,
            NAME => $i,
        };
        if (!$args{no_weaken_refs}) {
            weaken $child->{PARENT};
        }
        push @children, $child;
        $hash{TREE_BY_NAME}{$i} = $child;
    }

    return \%hash;
}


sub test_save_and_reload {
    my %args = @_;
    my $data = get_data (%args);

    #local $Data::Dumper::Purity    = 1;
    #local $Data::Dumper::Terse     = 1;
    #local $Data::Dumper::Sortkeys  = 1;
    #local $Data::Dumper::Indent    = 1;
    #local $Data::Dumper::Quotekeys = 0;

    my $context_text;
    $context_text .= $args{no_weaken} ? 'not weakened' : 'weakened';
    $context_text .= $args{store_root_by_name}
        ? ', extra root ref stored'
        : ', extra root ref not stored';

    #diag "Working on Sereal";

    my $encoder = Sereal::Encoder->new;
    my $decoder = Sereal::Decoder->new;
    my ($encoded_data, $decoded_data);

    lives_ok {
        $encoded_data = $encoder->encode($data)
    } "Encoded using Sereal, $context_text";

    lives_ok {
        $decoder->decode ($encoded_data, $decoded_data);
    } "Decoded using Sereal, $context_text";

    is_deeply ($decoded_data, $data, "Data structures match for Sereal, $context_text");

    #diag "Working on YAML::XS";

    lives_ok {
        $encoded_data = Dump $data;
    } "Encoded using YAML::XS, $context_text";

    lives_ok {
        $decoded_data = Load $encoded_data;
    } "Decoded using YAML::XS, $context_text";

    is_deeply ($decoded_data, $data, "Data structures match for YAML::XS, $context_text");

    diag 'try Dump and Load';
    
    my $fname = 'dump.yml';
    #open(my $fh, '>', $fname) or die "Cannot open dump.yml";
    
    lives_ok {
        YAML::XS::DumpFile $fname, $data;
    } "Dumped to file using YAML::XS, $context_text";

    #close $fh;

    lives_ok {
        $decoded_data = YAML::XS::LoadFile $fname;
    } "Loaded from file using YAML::XS, $context_text";

    is_deeply ($decoded_data, $data, "Data structures match for YAML::XS from file, $context_text");
}




1;
