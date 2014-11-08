#!/usr/bin/perl -w
use strict;
use warnings;

use English qw { -no_match_vars };
use Carp;

#  need to consider Class::Inspector for the method hunting

## is it possible the increase is due to hash keys being assigned when clone methods track refs they have already traversed???
# see also last post in http://www.perlmonks.org/?node_id=226251

use Data::Section::Simple qw(get_data_section);

use FindBin qw /$Bin/;
use lib "$Bin/../../lib";
use lib "$Bin/../../t/lib";
use rlib;

use File::Temp qw /tempfile/;

#  load up the user defined libs
use Biodiverse::Config;

use Biodiverse::BaseData;
use Biodiverse::Common;

use Biodiverse::TestHelpers qw {:basedata};

local $| = 1;

do {
    my $use_small = 1;
    my $rand_iterations = 1;
    
    my $bd = get_numeric_labels_basedata_object_from_site_data(
        CELL_SIZES => [100000, 100000],
        sample_count_columns => undef,
    );
    $bd->build_spatial_index (resolutions => [100000, 100000]);

    my $debug = q{};
    $debug = 'array';
    #$debug = 'file';
    
    if ($debug eq 'array') {
        use Test::LeakTrace;
        print "Debug is array\n";
        my @leaks = leaked_info {
            run_process($bd);
        };
        process_leaks (@leaks);
    }
    elsif ($debug eq 'file') {
        use Test::LeakTrace;
        print "Debug is file\n";
        leaktrace {
            run_process($bd);
        } -verbose;
    }
    else {
        run_process($bd);
    }
    
    undef $bd;

};

exit;

sub process_leaks {
    my @leaks = @_;

    use Devel::Size qw(size total_size);
    #use Devel::Cycle;

    my @leakers;
    foreach my $leak (@leaks) {
        #next if not $leak->[1] =~ 'Biodiverse';
        #next if not $leak->[0] =~ /ARRAY/;
        next if not $leak->[0] =~ /^\w/;  #  skip regexps
        my $tot_size = total_size ($leak->[0]); 
        #next if $tot_size < 1650000;

        push @leakers, [$tot_size, @$leak];
        #my $cycle = find_cycle($leak->[0]);
        #next if !$cycle;
        #print STDERR "Cycle found: $cycle\n";
    }

    foreach my $leak (reverse sort {$a->[0] <=> $b->[0] || $a->[-1] <=> $b->[-1]} @leakers) {
        print STDERR join ("\t", @$leak), "\n";
    }

    return;
}

sub run_process {
    my ($bd) = @_;

    $bd //= get_numeric_labels_basedata_object_from_site_data(CELL_SIZES => [100000, 100000]);
    
    process_data ($bd);

}

sub process_data {
    my ($bd) = @_;
    print "...In process() sub\n";
    #print "Loading basedata $bd_file\n";
    
    my $sp = $bd->add_spatial_output (
        name => 'glurgle',
    );
    $sp->run_analysis (
        calculations => [qw /calc_numeric_label_stats calc_numeric_label_quantiles/],
        spatial_conditions => ['sp_circle(radius => 200000)'],
    );

    undef $bd;
    
    print "...process completed\n";
}



1;

__END__

