#!/usr/bin/perl -w
use strict;
use warnings;
use English qw { -no_match_vars };
use Carp;

use Test::More;
#use Test::Exception;
#use Test::Deep;

use Data::Section::Simple qw(get_data_section);

local $| = 1;

use Biodiverse::BaseData;
use Biodiverse::Indices;
use Biodiverse::TestHelpers qw {:basedata :tree};

use Scalar::Util qw /looks_like_number/;

#  start with a subset
my @phylo_calcs_to_test = qw /
    calc_pd
    calc_pe
    calc_phylo_mntd1
    calc_phylo_mntd3
/;


{
    my ($e, $is_error, %results);

    my $bd   = get_basedata_object_from_site_data(CELL_SIZES => [100000, 100000]);
    my $tree = get_tree_object_from_sample_data();

    my $indices = Biodiverse::Indices->new(BASEDATA_REF => $bd);

    my %elements = (
	element_list1 => ['3350000:850000'],
	element_list2 => [qw /
	    3250000:850000
	    3350000:750000
	    3350000:950000
	    3450000:850000
	/],
    );

    my $calc_args = {tree_ref => $tree};

    foreach my $nbr_list_count (2, 1) {
	if ($nbr_list_count == 1) {
	    delete $elements{element_list2};
	}

	my $valid_calcs = eval {
	    $indices->get_valid_calculations (
		calculations   => \@phylo_calcs_to_test,
		nbr_list_count => $nbr_list_count,
		calc_args      => $calc_args,
	    );
	};
	$e = $EVAL_ERROR;
	note $e if $e;
	ok (!$e, "Obtained valid calcs without eval error");
    
	eval {
	    $indices->run_precalc_globals(%$calc_args);
	};
	$e = $EVAL_ERROR;
	note $e if $e;
	ok (!$e, "Ran global precalcs without eval error");

	%results = eval {$indices->run_calculations(%$calc_args)};
	$e = $EVAL_ERROR;
	#note $e if $e;
	ok ($e, "Ran calculations without elements and got eval error");

	%results = eval {
	    $indices->run_calculations(%$calc_args, %elements);
	};
	$e = $EVAL_ERROR;
	note $e if $e;
	ok (!$e, "Ran calculations without eval error");

	eval {
	    $indices->run_postcalc_globals(%$calc_args);
	};
	$e = $EVAL_ERROR;
	note $e if $e;
	ok (!$e, "Ran global postalcs without eval error");

	#  now we need to check the results
	print "";
	my %expected = get_expected_results(nbr_list_count => $nbr_list_count);
	my $subtest_name = "Result set matches for neighbour count $nbr_list_count";
	subtest $subtest_name => sub {
	    compare_hash_vals (hash1 => \%results, hash2 => \%expected)
	};
    }
}

done_testing();

sub compare_hash_vals {
    my %args = @_;

    my $hash1 = $args{hash1};
    my $hash2 = $args{hash2};
    
    is (scalar keys %$hash1, scalar keys %$hash2, 'hashes are same size');

    foreach my $key (sort keys %$hash1) {
	my $val1 = snap_to_precision (value => $hash1->{$key}, precision => $args{precision});
	my $val2 = snap_to_precision (value => $hash2->{$key}, precision => $args{precision});
	is ($val1, $val2, "Got expected value for $key");
    }

    return;
}


sub snap_to_precision {
    my %args = @_;
    my $value = $args{value};
    my $precision = defined $args{precision} ? $args{precision} : '%.13f';
    
    return defined $value && looks_like_number $value
        ? sprintf ($precision, $value)
        : $value;
}

sub get_expected_results {
    my %args = @_;

    my $data;
    
    if ($args{nbr_list_count} == 1) {
	$data = get_data_section ('RESULTS_1_NBR_LISTS');
    }
    elsif ($args{nbr_list_count} == 2) {
	$data = get_data_section ('RESULTS_2_NBR_LISTS');
    }
    else {
	croak 'Invalid value for argument nbr_list_count';
    }

    $data =~ s/\n+$//s;
    my %expected = split (/\s+/, $data);
    return wantarray ? %expected : \%expected;
}

1;


__DATA__

@@ RESULTS_1_NBR_LISTS
PD	1.49276923076923
PD_P	0.07047267380194
PD_P_per_taxon	0.03523633690097
PD_per_taxon	0.746384615384615
PE_WE	0.261858249294739
PE_WE_P	0.0123621592705162
PE_WE_SINGLE	0.261858249294739
PE_WE_SINGLE_P	0.0123621592705162
PNTD1_MAX	1
PNTD1_MEAN	1
PNTD1_MIN	1
PNTD1_N	2
PNTD1_SD	0
PNTD3_MAX	1
PNTD3_MEAN	1
PNTD3_MIN	1
PNTD3_N	6
PNTD3_SD	0

@@ RESULTS_2_NBR_LISTS
PD	9.55665348225732
PD_P	0.451163454880595
PD_P_per_taxon	0.0322259610628996
PD_per_taxon	0.682618105875523
PE_WE	1.58308662511342
PE_WE_P	0.0747364998100494
PE_WE_SINGLE	1.02058686362188
PE_WE_SINGLE_P	0.0481812484100488
PNTD1_MAX	1.86377675442101
PNTD1_MEAN	1.09027062122407
PNTD1_MIN	0.5
PNTD1_N	14
PNTD1_SD	0.368844918238016
PNTD3_MAX	1.86377675442101
PNTD3_MEAN	1.17079993908642
PNTD3_MIN	0.5
PNTD3_N	83
PNTD3_SD	0.261537668675783
