#!/usr/bin/perl -w
use strict;
use warnings;
use 5.016;

use English qw { -no_match_vars };
use Carp;

use Scalar::Util qw /isweak/;

#use Data::Section::Simple qw(get_data_section);

use FindBin qw /$Bin/;
use lib "$Bin/../../lib";
use lib "$Bin/../../t/lib";

#use File::Temp qw /tempfile/;

#  load up the user defined libs
use Biodiverse::Config;

use Biodiverse::BaseData;
use Biodiverse::Common;

use Biodiverse::TestHelpers qw {:basedata};

local $| = 1;

main();
exit;

sub main {
    my $use_small = 1;
    my $rand_iterations = 1;
    

    my $debug = q{};
    $debug = 'array';
    #$debug = 'file';
    
    if ($debug eq 'array') {
        use Test::LeakTrace;
        print "Debug is array\n";
        my @leaks = leaked_info {
            run_process();
        };
        process_leaks (@leaks);
    }
    elsif ($debug eq 'file') {
        use Test::LeakTrace;
        print "Debug is file\n";
        leaktrace {
            run_process();
        } -verbose;
    }
    else {
        run_process();
    }

}


sub process_leaks {
    my @leaks = @_;

    use Devel::Size qw(size total_size);
    #use Devel::Cycle;

    my @leakers;
    foreach my $leak (@leaks) {
        #next if not $leak->[1] =~ 'Biodiverse';
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
    my $bd = Biodiverse::BaseData->new(file => 'numeric_data.bds');
    $bd //= get_numeric_labels_basedata_object_from_site_data(
        CELL_SIZES => [100000, 100000],
        sample_count_columns => undef,
    );
    $bd->build_spatial_index (resolutions => [100000, 100000]);
    
    process_data ($bd);

}

sub process_data {
    my ($bd) = @_;
    print "...In process() sub\n";
    #print "Loading basedata $bd_file\n";
    
    my $calcs = [qw /calc_numeric_label_stats calc_numeric_label_quantiles/];
    #$calcs = [qw/calc_richness/];  #  simplest sub
    
    my $sp_cond = ['sp_circle(radius => 200000)'];
    #$sp_cond = ['sp_self_only()'];  #  is optimised to not be needed

    
    my $sp = $bd->add_spatial_output (
        name => 'glurgle',
    );
    $sp->run_analysis (
        calculations => $calcs,
        spatial_conditions => $sp_cond,
    );

    #say 'WEAK' if isweak $sp->{PARAMS}{BASEDATA_REF};

    #$bd->find_circular_refs ($sp);

    #undef $bd;
    #undef $sp;
    
    print "...process completed\n";
}



1;

__END__

