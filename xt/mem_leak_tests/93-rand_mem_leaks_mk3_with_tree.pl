#!/usr/bin/perl -w
use strict;
use warnings;

use English qw { -no_match_vars };
use Carp;

use Test::Memory::Cycle;

#  need to consider Class::Inspector for the method hunting

## is it possible the increase is due to hash keys being assigned when clone methods track refs they have already traversed???
# see also last post in http://www.perlmonks.org/?node_id=226251

use Data::Section::Simple qw(get_data_section);

use FindBin qw /$Bin/;
use lib "$Bin/lib";
use lib "$Bin/../t/lib";

use File::Temp qw /tempfile/;

#  load up the user defined libs
use Biodiverse::Config;

use Biodiverse::BaseData;
use Biodiverse::Common;
use Biodiverse::Tree;

use Biodiverse::TestHelpers qw {:basedata :tree};

local $| = 1;

my $use_small = 1;
my $rand_iterations = 1;

my $debug = q{};
   #$debug = 'array';
   #$debug = 'file';

#run_process();  #  avoid all the globs etc

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

#done_testing();

exit;

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
    my $bd = get_basedata();
    my $tree = get_tree_object_from_sample_data();
    run_spatial ($bd, $tree);

    my ($tmp_fh, $tmp_name) = tempfile();
    $tmp_name .= '.bds';
    $bd->save_to (filename => $tmp_name);
    $bd = Biodiverse::BaseData->new (file => $tmp_name);

    process_rand ($bd);
    
    if (!$debug) {
        memory_cycle_ok ($tree, 'Found no memory cycles in the tree');
        weakened_memory_cycle_exists( $tree, 'Found weakened memory cycles in tree, as expected');
    }
}

sub process_rand {
    my ($bd) = @_;
    print "...In process() sub\n";
    #print "Loading basedata $bd_file\n";
    
    my $function = 'rand_structured';
    $function = 'rand_csr_by_group';

    my $rand = $bd->add_randomisation_output (
        name => 'glurgle',
    );
    $rand->run_analysis (
        function   => $function,
        iterations => $rand_iterations,
    );

    undef $bd;
    
    print "...process completed\n";
}

sub run_spatial {
    my ($bd, $tree) = @_;
    
    my $sp = $bd->add_spatial_output (name => 'lklk');
    $sp->run_analysis (
        spatial_conditions => ['sp_self_only()'],
        calculations       => [qw /calc_richness calc_phylo_rpe2 calc_pd/],
        tree_ref           => $tree,
    );

    return;
}

sub get_basedata {
    
    my $bd;
    if ($use_small) {
        my $bd_data = get_data_section('BASEDATA');
        my $bd_file = write_data_to_temp_file ($bd_data);
        
        $bd = Biodiverse::BaseData->new(
            NAME       => 'blah',
            CELL_SIZES => [100000, 100000],
        );
        $bd->import_data (
            input_files   => [$bd_file],
            label_columns => [3],
            group_columns => [1,2],
        );
    }
    else {
        $bd = get_basedata_object_from_site_data(
            NAME       => 'blah',
            CELL_SIZES => [100000, 100000],
        );
        return $bd;
    }
    
    return $bd;
}

1;

__END__

__DATA__

@@ BASEDATA
ELEMENT,Axis_0,Axis_1,Key,Value
3350000:750000,3350000,750000,Genus:sp1,6
3350000:750000,3350000,750000,Genus:sp11,4
3350000:750000,3350000,750000,Genus:sp12,1
3350000:750000,3350000,750000,Genus:sp15,7
3350000:750000,3350000,750000,Genus:sp20,1
3350000:750000,3350000,750000,Genus:sp23,2
3350000:750000,3350000,750000,Genus:sp26,4
3350000:750000,3350000,750000,Genus:sp27,1
3350000:750000,3350000,750000,Genus:sp29,5
3350000:750000,3350000,750000,Genus:sp30,1
3350000:750000,3350000,750000,Genus:sp5,1
3450000:950000,3450000,950000,Genus:sp1,7
3450000:950000,3450000,950000,Genus:sp10,16
3450000:950000,3450000,950000,Genus:sp11,6
3450000:950000,3450000,950000,Genus:sp12,5
3450000:950000,3450000,950000,Genus:sp15,2
3450000:950000,3450000,950000,Genus:sp19,3
3450000:950000,3450000,950000,Genus:sp20,12
3450000:950000,3450000,950000,Genus:sp21,1
3550000:1050000,3550000,1050000,Genus:sp1,5
3550000:1050000,3550000,1050000,Genus:sp10,2
3550000:1050000,3550000,1050000,Genus:sp11,13
3550000:1050000,3550000,1050000,Genus:sp12,3
3550000:1050000,3550000,1050000,Genus:sp15,7
3550000:1050000,3550000,1050000,Genus:sp19,4
3550000:1050000,3550000,1050000,Genus:sp21,1
3550000:1050000,3550000,1050000,Genus:sp5,10
