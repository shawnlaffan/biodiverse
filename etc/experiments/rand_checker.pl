use 5.022;
use strict;
use warnings;
use Path::Tiny;
use Time::HiRes qw /time tv_interval gettimeofday/;
use Sort::Key::Natural qw /natsort/;

use Biodiverse::BaseData;

use FindBin qw /$Bin/;

my $data_dir = path ($Bin)->parent->parent->child('data');

my $bd = Biodiverse::BaseData->new (
    file => $data_dir->child ("example_data_x64.bds"),
);

#$bd = $bd->clone(no_outputs => 1);
my %gp_lb_hash;
my %moved_hash;
my $ident;  #  a unique ID
foreach my $label (natsort $bd->get_labels) {
    my $groups = $bd->get_groups_with_label_as_hash_aa($label);
    foreach my $group (natsort keys %$groups) {
        $ident++;
        $gp_lb_hash{$group}{$label} = $ident;
        $moved_hash{$group}{$label} = 0;
    }
}
my $bd2 = Biodiverse::BaseData->new (
    NAME => 'rand_comparator',
    CELL_SIZES => [$bd->get_cell_sizes],
);
my $csv = $bd->get_csv_object;
$bd2->add_elements_collated (
    data => \%gp_lb_hash,
    csv_object => $csv,
);

$bd = $bd2;

my $sp = $bd->add_spatial_output (name => 'glorg');
$sp->run_analysis (
    calculations => ['calc_endemism_central'],
    spatial_conditions => ['sp_self_only()'],
);

my $rand = $bd->add_randomisation_output (name => 'rando');
my $prng_seed  = 2345;
my $rand_iters = 100;
my $rand_function   = 'rand_independent_swaps';

my $start_time = [gettimeofday];
my $rand_bd_array = $rand->run_analysis (
    function   => $rand_function,
    iterations => $rand_iters,
    seed       => $prng_seed,
    return_rand_bd_array => 1,
    retain_outputs       => 1,
    stop_on_all_swapped  => 1,
    swap_count           =>   1300,
    max_swap_attempts    => 100000,
);
my $time_taken = sprintf "%.3f", tv_interval ($start_time);
say "Total time taken to randomise: $time_taken";


say $#$rand_bd_array;

my %results_set;

foreach my $rbd (@$rand_bd_array) {
    foreach my $group (keys %gp_lb_hash) {
        
        foreach my $label (keys %{$gp_lb_hash{$group}}) {
            #$results_set{$label}{$group} = $gp_lb_hash{$group}{$label};  #  unique ID
            my $rgps = $rbd->get_labels_in_group_as_hash (group => $group);
            if (!$rgps->{$label}
                || $rgps->{$label} != $gp_lb_hash{$group}{$label}
                ) {
                $moved_hash{$group}{$label}++;
            }
        }
    }
}

my $fname = "rand_check_${rand_function}_${rand_iters}_" . int (time()) . ".csv";
open my $ofh, '>', $fname or die "Unable to open file $fname, $!";
print {$ofh} "Label,Group,LGID,GpRichness,LbRange,MovedCount\n";

my %richness_hash;
my %range_hash;
foreach my $group (natsort keys %gp_lb_hash) {
    my $richness = $richness_hash{$group} //= $bd->get_richness_aa($group);
    foreach my $label (natsort keys %{$gp_lb_hash{$group}}) {
        my $range = $range_hash{$label} //= $bd->get_range (element => $label);
        my $moved = $moved_hash{$group}{$label} // -1;
        print {$ofh} "$label,$group,$gp_lb_hash{$group}{$label},$richness,$range,$moved\n";
    }
}
$ofh->close;


