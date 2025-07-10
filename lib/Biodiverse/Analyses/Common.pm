package Biodiverse::Analyses::Common;
use 5.036;
use strict;
use warnings;

use Carp qw /croak/;
use List::Util qw /first/;

use experimental qw /refaliasing for_list/;

use constant DEFAULT_PRECISION_SMALL => 1e-10;

sub compare_lists_by_item {
    my $self = shift;
    my %args = @_;

    \my %base_ref = $args{base_list_ref};
    \my %comp_ref = $args{comp_list_ref};
    \my %results  = $args{results_list_ref};
    my $diff;

    COMP_BY_ITEM:
    foreach my ($index, $base_val) (%base_ref) {

        next COMP_BY_ITEM
            if !(defined $comp_ref{$index} && defined $base_val);

        #  compare at 10 decimal place precision
        #  this also allows for serialisation which
        #     rounds the numbers to 15 decimals
        $diff = $base_val - $comp_ref{$index};

        #  for debug, but leave just in case
        #carp "$element, $op\n$comp\n$base  " . ($comp - $base) if $increment;

        #   C is count passed
        #   Q is quantum, or number of comparisons
        #   P is the percentile rank amongst the valid comparisons,
        #      and has a range of [0,1]
        #   SUMX  is the sum of compared values
        #   SUMXX is the sum of squared compared values
        #   The latter two are used in z-score calcs
        #  obfuscated to squeeze as much speed as we can
        # $results{"C_$index"} += $increment;
        # $results{"Q_$index"} ++;
        $results{"P_$index"} =   ($results{"C_$index"} += $diff > DEFAULT_PRECISION_SMALL)
            / (++$results{"Q_$index"});
        # use original vals for sums
        $results{"SUMX_$index"}  +=  $comp_ref{$index};
        $results{"SUMXX_$index"} += ($comp_ref{$index}**2);

        #  track the number of ties
        $results{"T_$index"} ++
            if (abs($diff) <= DEFAULT_PRECISION_SMALL);
    }

    return;
}

sub check_canape_protocol_is_valid {
    my $self = shift;

    #  argh the hard coding of index names...
    my $analysis_args = $self->get_param('SP_CALC_ARGS') || $self->get_param('ANALYSIS_ARGS');
    my $valid_calcs   = $analysis_args->{calculations} // $analysis_args->{spatial_calculations} // [];
    my %vk;
    @vk{@$valid_calcs} = (1) x @$valid_calcs;
    return ($vk{calc_phylo_rpe2} && $vk{calc_pe});
    # || ($vk{calc_phylo_rpe_central} && $vk{calc_pe_central}) ;  #  central later
}

sub get_valid_canape_types  {
    my $self = shift;

    #  argh the hard coding of index names...
    my $analysis_args = $self->get_param('SP_CALC_ARGS') || $self->get_param('ANALYSIS_ARGS');
    my $valid_calcs   = $analysis_args->{calculations} // $analysis_args->{spatial_calculations} // [];
    my %vk;
    @vk{@$valid_calcs} = (1) x @$valid_calcs;
    my $result = {};
    if ($vk{calc_phylo_rpe2} && $vk{calc_pe}) {
        $result->{normal}++;
    }
    if ($vk{calc_phylo_rpe_central} && $vk{calc_pe_central}) {
        $result->{central}++;
    }
    return $result;
}

sub assign_canape_codes_from_p_rank_results {
    my $self = shift;
    my %args = @_;

    #  could alias this
    my $p_rank_list_ref = $args{p_rank_list_ref}
        // croak "p_rank_list_ref argument not specified\n";
    #  need the observed values
    my $base_list_ref = $args{base_list_ref}
        // croak "base_list_ref argument not specified\n";

    my $results_list_ref = $args{results_list_ref} // {};

    # state $default_names = {
    #     PE_obs => 'PE_WE',
    #     PE_alt => 'PHYLO_RPE_NULL2',
    #     RPE    => 'PHYLO_RPE2',
    # };
    \my %index_names = ($args{index_names} // {});

    my $canape_code;
    if (defined $base_list_ref->{$index_names{PE_obs} // 'PE_WE'}) {
        my $PE_sig_obs = $p_rank_list_ref->{$index_names{PE_obs} // 'PE_WE'} // 0.5;
        my $PE_sig_alt = $p_rank_list_ref->{$index_names{PE_alt} // 'PHYLO_RPE_NULL2'} // 0.5;
        my $RPE_sig    = $p_rank_list_ref->{$index_names{RPE}    // 'PHYLO_RPE2'}  // 0.5;

        $canape_code
            = $PE_sig_obs <= 0.95 && $PE_sig_alt <= 0.95 ? 0  #  non-sig
            : $RPE_sig < 0.025 ? 1                            #  neo
            : $RPE_sig > 0.975 ? 2                            #  palaeo
            : $PE_sig_obs > 0.99  && $PE_sig_alt > 0.99  ? 4  #  super
            : 3;                                              #  mixed
        #say '';
    }
    $results_list_ref->{CANAPE_CODE} = $canape_code;
    if (defined $canape_code) {  #  numify booleans
        $results_list_ref->{NEO}    = 0 + ($canape_code == 1);
        $results_list_ref->{PALAEO} = 0 + ($canape_code == 2);
        $results_list_ref->{MIXED}  = 0 + ($canape_code == 3);
        $results_list_ref->{SUPER}  = 0 + ($canape_code == 4);
    }
    else {  #  clear any pre-existing values
        @$results_list_ref{qw /NEO PALAEO MIXED SUPER/} = (undef) x 4;
    }

    return wantarray ? %$results_list_ref : $results_list_ref;
}

sub get_zscore_from_comp_results {
    my $self = shift;
    my %args = @_;

    #  could alias this
    \my %comp_list_ref = $args{comp_list_ref}
        // croak "comp_list_ref argument not specified\n";
    #  need the observed values
    \my %base_list_ref = $args{base_list_ref}
        // croak "base_list_ref argument not specified\n";

    my $results_list_ref = $args{results_list_ref} // {};

    KEY:
    foreach my $index_name (keys %base_list_ref) {

        my $n = $comp_list_ref{'Q_' . $index_name};
        next KEY if !$n;

        my $x_key  = 'SUMX_'  . $index_name;
        my $xx_key = 'SUMXX_' . $index_name;

        #  sum of x vals and x vals squared
        my $sumx  = $comp_list_ref{$x_key};
        my $sumxx = $comp_list_ref{$xx_key};

        #  n better be large, as we do not use n-1
        my $variance = ($sumxx - ($sumx**2) / $n) / $n;

        $results_list_ref->{$index_name}
            = $variance > 0
            ? ($base_list_ref{$index_name} - ($sumx / $n)) / sqrt ($variance)
            : 0;
    }

    return wantarray ? %$results_list_ref : $results_list_ref;
}

sub get_significance_from_comp_results {
    my $self = shift;
    my %args = @_;

    #  could alias this
    my $comp_list_ref = $args{comp_list_ref}
        // croak "comp_list_ref argument not specified\n";

    my $results_list_ref = $args{results_list_ref} // {};

    my (@sig_thresh_lo_1t, @sig_thresh_hi_1t, @sig_thresh_lo_2t, @sig_thresh_hi_2t);
    #  this is recalculated every call - cheap, but perhaps should be optimised or cached?
    if ($args{thresholds}) {
        @sig_thresh_lo_1t = sort {$a <=> $b} @{$args{thresholds}};
        @sig_thresh_hi_1t = map {1 - $_} @sig_thresh_lo_1t;
        @sig_thresh_lo_2t = map {$_ / 2} @sig_thresh_lo_1t;
        @sig_thresh_hi_2t = map {1 - ($_ / 2)} @sig_thresh_lo_1t;
    }
    else {
        @sig_thresh_lo_1t = (0.01, 0.05);
        @sig_thresh_hi_1t = (0.99, 0.95);
        @sig_thresh_lo_2t = (0.005, 0.025);
        @sig_thresh_hi_2t = (0.995, 0.975);
    }

    foreach my $p_key (grep {$_ =~ /^P_/} keys %$comp_list_ref) {
        no autovivification;
        (my $index_name = $p_key) =~ s/^P_//;

        my $c_key = 'C_' . $index_name;
        my $t_key = 'T_' . $index_name;
        my $q_key = 'Q_' . $index_name;
        my $sig_1t_name = 'SIG_1TAIL_' . $index_name;
        my $sig_2t_name = 'SIG_2TAIL_' . $index_name;

        #  proportion observed higher than random
        my $p_high = $comp_list_ref->{$p_key};
        #  proportion observed lower than random
        my $p_low
            =   ($comp_list_ref->{$c_key} + ($comp_list_ref->{$t_key} // 0))
            /  $comp_list_ref->{$q_key};

        $results_list_ref->{$sig_1t_name} = undef;
        $results_list_ref->{$sig_2t_name} = undef;

        if (my $sig_hi_1t = first {$p_high > $_} @sig_thresh_hi_1t) {
            $results_list_ref->{$sig_1t_name} = 1 - $sig_hi_1t;
            if (my $sig_hi_2t = first {$p_high > $_} @sig_thresh_hi_2t) {
                $results_list_ref->{$sig_2t_name} = 2 * (1 - $sig_hi_2t);
            }
        }
        elsif (my $sig_lo_1t = first {$p_low  < $_} @sig_thresh_lo_1t) {
            $results_list_ref->{$sig_1t_name} = -$sig_lo_1t;
            if (my $sig_lo_2t = first {$p_low  < $_} @sig_thresh_lo_2t) {
                $results_list_ref->{$sig_2t_name} = -2 * $sig_lo_2t;
            }
        }
    }

    return wantarray ? %$results_list_ref : $results_list_ref;
}

#  almost the same as get_significance_from_comp_results
sub get_sig_rank_threshold_from_comp_results {
    my $self = shift;
    my %args = @_;

    #  could alias this
    my $comp_list_ref = $args{comp_list_ref}
        // croak "comp_list_ref argument not specified\n";

    my $results_list_ref = $args{results_list_ref} // {};

    my (@sig_thresh_lo, @sig_thresh_hi);
    #  this is recalculated every call - cheap, but perhaps should be optimised or cached?
    if ($args{thresholds}) {
        @sig_thresh_lo = sort {$a <=> $b} @{$args{thresholds}};
        @sig_thresh_hi = map  {1 - $_}    @sig_thresh_lo;
    }
    else {
        @sig_thresh_lo = (0.005, 0.01, 0.025, 0.05);
        @sig_thresh_hi = (0.995, 0.99, 0.975, 0.95);
    }

    foreach my $key (grep {$_ =~ /^C_/} keys %$comp_list_ref) {
        no autovivification;
        (my $index_name = $key) =~ s/^C_//;

        my $c_key = 'C_' . $index_name;
        my $t_key = 'T_' . $index_name;
        my $q_key = 'Q_' . $index_name;
        my $p_key = 'P_' . $index_name;

        #  proportion observed higher than random
        my $p_high = $comp_list_ref->{$p_key};
        #  proportion observed lower than random
        my $p_low
            =   ($comp_list_ref->{$c_key} + ($comp_list_ref->{$t_key} // 0))
            /  $comp_list_ref->{$q_key};

        if (   my $sig_hi = first {$p_high > $_} @sig_thresh_hi) {
            $results_list_ref->{$index_name} = $sig_hi;
        }
        elsif (my $sig_lo = first {$p_low  < $_} @sig_thresh_lo) {
            $results_list_ref->{$index_name} = $sig_lo;
        }
        else {
            $results_list_ref->{$index_name} = undef;
        }
    }

    return wantarray ? %$results_list_ref : $results_list_ref;
}

sub get_sig_rank_from_comp_results {
    my $self = shift;
    my %args = @_;

    \my %comp_list_ref = $args{comp_list_ref}
        // croak "comp_list_ref argument not specified\n";

    \my %results_list_ref = $args{results_list_ref} // {};

    #  base_list_ref will usually be shorter so fewer comparisons will be needed
    my @keys = $args{base_list_ref}
        ? grep {exists $comp_list_ref{'C_' . $_}} keys %{$args{base_list_ref}}
        : map {substr $_, 2} grep {$_ =~ /^C_/} keys %comp_list_ref;

    foreach my $index_name (@keys) {

        my $c_key = 'C_' . $index_name;

        if (!defined $comp_list_ref{$c_key}) {
            $results_list_ref{$index_name} = undef;
            next;
        }

        #  proportion observed higher than random
        if ($comp_list_ref{"P_${index_name}"} > 0.5) {
            $results_list_ref{$index_name} = $comp_list_ref{"P_${index_name}"};
        }
        else {
            my $t_key = 'T_' . $index_name;
            my $q_key = 'Q_' . $index_name;

            #  proportion observed lower than random
            $results_list_ref{$index_name}
                =   ($comp_list_ref{$c_key} + ($comp_list_ref{$t_key} // 0))
                /  $comp_list_ref{$q_key};
        }
    }

    return wantarray ? %results_list_ref : \%results_list_ref;
}



1;
