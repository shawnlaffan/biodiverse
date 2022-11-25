package Biodiverse::Statistics;

use strict;
use warnings;

our $VERSION = '4.0';

use Carp;

use POSIX qw ( ceil );
use List::Util;
use List::MoreUtils;
use Ref::Util qw /is_ref is_arrayref is_hashref/;

use Statistics::Descriptive;
use base qw /Statistics::Descriptive::Full/;

##Create a list of fields not to remove when data is updated
my %fields = (
    _permitted => undef,  ##Place holder for the inherited key hash
    data       => undef,  ##Our data
    presorted  => undef,  ##Flag to indicate the data is already sorted
    _reserved  => undef,  ##Place holder for this lookup hash
    #standard_deviation => undef,
);


#  same as from Statistics::Descriptive::Full::new
##Have to override the base method to add the data to the object
##The proxy method from above is still valid
sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    # Create my self via SUPER
    my $self = $class->SUPER::new();  
    bless ($self, $class);  #Re-anneal the object
    #$self->_clear_fields();
    return $self;
}

#  override the Stats::Descriptive::Full method to use List::Util and List::MoreUtils functions
sub add_data {
    my $self = shift;  ##Myself
  
    my $aref;

    if (is_arrayref $_[0]) {
      $aref = $_[0];
    }
    else {
      $aref = \@_;
    }
  
    ##If we were given no data, we do nothing.
    return 1 if (!@{ $aref });
  
    my $oldmean;
    my ($min, $max, $sum, $sumsq);
    my $count = $self->count;

    #  $count is modified lower down, but we need this flag after that
    my $has_existing_data = $count;  

    # Take care of appending to an existing data set
    if ($has_existing_data) {
        $min   = $self->min();
        $max   = $self->max();
        $sum   = $self->sum();
        $sumsq = $self->sumsq();
    }
    else {
        $min   = $aref->[0];
        $max   = $aref->[0];
        $sum   = 0;
        $sumsq = 0;
    }

    #  need to allow for already having data
    $sum    += List::Util::sum (@$aref);
    $sumsq  += List::Util::sum (map $_ ** 2, @$aref);
    $max    =  List::Util::max ($max, @$aref);
    $min    =  List::Util::min ($min, @$aref);
    $count  +=  scalar @$aref;
    my $mean = $sum / $count;

    #$self->min($min);
    #$self->max($max);
    #$self->sample_range($max - $min);
    #$self->sum($sum);
    #$self->sumsq($sumsq);
    #$self->mean($mean);
    #$self->count($count);

    #  dirty approach since it stops any abstraction, but faster
    #  - should access via a "fast_data_add" object flag
    #  saves 50% of the call time (= 4s for ~55k calls), so will scale for monster jobs
    $self->{sum}   = $sum;
    $self->{sumsq} = $sumsq;
    $self->{mean}  = $mean;
    $self->{count} = $count;
    $self->{min}   = $min;
    $self->{max}   = $max;
    $self->{sample_range} = $max - $min;
    
    
    ##Variance isn't commonly enough
    ##used to recompute every single data add, so just clear its cache.
    #$self->_variance(undef);
    $self->{variance} = undef;  #  Dirty approach, as above
    
    push @{ $self->_data() }, @{ $aref };

    #  no need to clear keys if we are newly populated object,
    #  and profiling shows it takes a long time when creating
    #  and populating many stats objects
    if ($has_existing_data) {
        ##Clear the presorted flag
        $self->presorted(0);
        $self->_delete_all_cached_keys();
    }
  
    return 1;
}

sub _delete_all_cached_keys
{
    my $self = shift;
    
    my %keys = %{ $self };

    # Remove reserved keys for this class from the deletion list
    delete @keys{keys %{$self->_reserved}};
    delete @keys{keys %{$self->_permitted}};
    delete $keys{_trimmed_mean_cache};

    KEYS_LOOP:
    foreach my $key (keys %keys) { # Check each key in the object
        delete $self->{$key};  # Delete any out of date cached key
    }
    $self->{_trimmed_mean_cache} = {};  #  just reset this one
    return;
}

##Return variance; if needed, compute and cache it.
sub variance {
    my $self = shift;  ##Myself
  
    my $count = $self->count();
  
    return undef if !$count;
  
    return 0 if $count == 1;

    if (!defined($self->_variance())) {
        my $variance = ($self->sumsq()- $count * $self->mean()**2);

        # Sometimes due to rounding errors we get a number below 0.
        # This makes sure this is handled as gracefully as possible.
        #
        # See:
        #
        # https://rt.cpan.org/Public/Bug/Display.html?id=46026
        if ($variance < 0) {
            $variance = 0;
        }
        else {
            #  Commented code is a left-over from early version.
            #  Assume it was to allow for biased method variance,
            #  but docs do not list it so assume it is unnecessary
            #  Actually, it is trapped by the $count == 1 condition above, so shouldn't be needed
            #my $div = scalar @_ ? 0 : 1;  
            #$variance /= $count - $div;
            $variance /= $count - 1;
        }

        $self->_variance($variance);

        #  return now to avoid sub re-entry (and therefore time when many objects are used)
        return $variance;  
    }

    return $self->_variance();
}


sub maxdex {
    my $self = shift;

    return undef if !$self->count;
    my $maxdex;

    if ($self->presorted) {
        $maxdex = $self->count - 1;
    }
    else {
        my $max = $self->max;
        $maxdex =  List::MoreUtils::first_index {$_ == $max} $self->get_data;
    }

    $self->{maxdex} = $maxdex;

    return $maxdex;
}

sub mindex {
    my $self = shift;

    return undef if !$self->count;
    #my $maxdex = $self->{maxdex};
    #return $maxdex if defined $maxdex;
    my $mindex;

    if ($self->presorted) {
        $mindex = 0;
    }
    else {
        my $min = $self->min;
        $mindex =  List::MoreUtils::first_index {$_ == $min} $self->get_data;
    }

    $self->{mindex} = $mindex;

    return $mindex;
}


sub median {
    my $self = shift;
    return undef if ! $self->count;
    
    return $self->SUPER::median;
}


sub sd {
    my $self = shift;
    return $self->standard_deviation (@_);
}

sub stdev {
    my $self = shift;
    return $self->standard_deviation (@_);
}

sub standard_deviation {
  my $self = shift;  ##Myself
  #  $self->variance checks for count==0, so don't double up
  my $variance = $self->variance();
  return defined $variance ? sqrt $variance : undef;
}

#  Snaps percentiles to range 1..100,
#  does not return undef if percentile is < bin size
sub percentile {  
    my $self = shift;
    my $percentile = shift || 0;

    my $count = $self->count;
    return if ! $count; #  no records, return undef
  
    $percentile = 100 if $percentile > 100;
    $percentile = 0   if $percentile < 0;
  
    $self->sort_data() if ! $self->presorted;

    my $num = ($count - 1) * $percentile / 100;
    my $index = int ($num + 0.5);

    #  a bit risky - depends on Statistics::Descriptive internals
    my $val = $self->_data->[$index];
    return wantarray
      ? ($val, $index)
      : $val;
}

sub percentiles {
    my ($self, @percentiles) = @_;

    my $count = $self->count;
    return if ! $count; #  no records, return undef
  
    $self->sort_data() if ! $self->presorted;

    my @vals;
    #  does not check for non-numeric, so don't pass them...
    foreach my $percentile (@percentiles) {
        $percentile
          = $percentile > 100 ? 100
          : $percentile < 0   ? 0
          : $percentile;

        my $index = int (0.5 + ($count - 1) * $percentile / 100);
    
        #  a bit risky - depends on Statistics::Descriptive internals
        push @vals, $self->_data->[$index];
    }

    return wantarray ? @vals : \@vals;
}

sub percentile_RFC2330 {
    my $self = shift;
    return $self->SUPER::percentile (@_);
}

#  inter-quartile range
sub iqr {
    my $self = shift;

    return undef if !$self->count;

    my ($q25, $q75) = $self->percentiles(25, 75);
    #my $q75 = $self->percentile(75);
    
    return $q75 - $q25;
}


sub skewness {
    my $self = shift;

    if (!defined($self->_skewness()))
    {
        my $n    = $self->count();
        my $sd   = $self->standard_deviation();

        my $skew;

        #  skip if insufficient records
        if ( $sd && $n > 2) {
            
            my $mean = $self->mean();

            my $sum_pow3;
            foreach my $rec ( $self->get_data() ) {
                $sum_pow3 +=  (($rec - $mean) / $sd) ** 3;
            }
            #  these are not as fast
            #my @tmp = List::MoreUtils::apply { $_ = (($_ - $mean) / $sd) ** 3 } $self->get_data();
            #my $sum_pow3 = List::Util::sum map { (($_ - $mean) / $sd) ** 3 } $self->get_data();

            my $correction = $n / ( ($n-1) * ($n-2) );

            $skew = $correction * $sum_pow3;
        }

        $self->_skewness($skew);
    }

    return $self->_skewness();
}

sub kurtosis {
    my $self = shift;

    if (!defined($self->_kurtosis()))
    {
        my $kurt;
        
        my $n  = $self->count();
        my $sd   = $self->standard_deviation();
        
        if ( $sd && $n > 3) {

            my $mean = $self->mean();

            my $sum_pow4;
            foreach my $rec ( $self->get_data() ) {
                $sum_pow4 +=  (($rec - $mean) / $sd) ** 4;
            }
            #  these are not as fast
            #my @tmp = List::MoreUtils::apply { $_ = (($_ - $mean) / $sd) ** 4 } $self->get_data();
            #my $sum_pow4 = List::Util::sum map { (($_ - $mean) / $sd) ** 4 } $self->get_data();

            my $correction1 = ( $n * ($n+1) ) / ( ($n-1) * ($n-2) * ($n-3) );
            my $correction2 = ( 3  * ($n-1) ** 2) / ( ($n-2) * ($n-3) );
            
            $kurt = ( $correction1 * $sum_pow4 ) - $correction2;
        }
        
        $self->_kurtosis($kurt);
    }

    return $self->_kurtosis();
}


1;

__END__

=head1 NAME

Biodiverse::Statistics - Basic descriptive statistical functions.

=head1 SYNOPSIS

  use Biodiverse::Statistics;
  $stat = Biodiverse::Statistics->new();
  $stat->add_data(1,2,3,4);
  $x = $stat->percentile(25);
  ($x, $index_x) = $stat->percentile(25);
  $y = $stat->percentile_RFC2330(25);
  ($y, $index_y) = $stat->percentile_RFC2330(25);


=head1 DESCRIPTION

Basic descriptive statistics.
Everything from module Statistics::Descriptive::Full but with a
different percentile algorithm
(the original can be called using percentile_RFC2330).

The median method also returns undef when there are no records.  


=head1 METHODS

=over

=item $stat = Biodiverse::Statistics->new();

Create a new object.

=item $x = $stat->percentile(25);

=item ($x, $index) = $stat->percentile(25);

Sorts the data and returns the value that corresponds to the
percentile.

=item $x = $stat->percentile_RFC2330(25);

=item ($x, $index) = $stat->percentile_RFC2330(25);

Sorts the data and returns the value that corresponds to the
percentile as defined in RFC2330.  This is the percentile
method from Statistics::Descriptive::Full.

=item $iqr = $stat->iqr();

Calculates the inter-quartile range (q75 - q25).

=back

=head1 REPORTING ERRORS

Use the issue tracker at http://www.purl.org/biodiverse

=head1 COPYRIGHT

Copyright (c) 2010 Shawn Laffan. All rights reserved.  

=head1 LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

For a full copy of the license see <http://www.gnu.org/licenses/>.

=cut
