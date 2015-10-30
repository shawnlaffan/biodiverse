
use Benchmark qw {:all};
use 5.016;
use Data::Dumper;
use Data::Alias qw /alias/;
use PDL;

my %hashbase;
#@hash{1..1000} = (rand()) x 1000;
for my $i (1..1000) {
    $hashbase{$i} = rand() + 1;
}
my $hashref = \%hashbase;

my @keys = keys %$hashref;
my $gpdl1 = pdl @$hashref{@keys};
my $gpdl2 = pdl @$hashref{@keys};
my $gpdl3 = pdl @$hashref{@keys};


cmpthese (
    -5,
    {
        #hash_deref_once => sub {hash_deref_once ()},
        data_alias => sub {data_alias ()},
        hash_deref_rep => sub {hash_deref_rep ()},
        pdl_build_each_time => sub {pdl_build_each_time ()},
        pdl_build_once      => sub {pdl_build_once ()},
    }
);


sub pdl_build_once {
    my $pdlsum = $gpdl1 * $gpdl2 / $gpdl3;
    my $sum = $pdlsum->sum;
    return $sum;
}

sub pdl_build_each_time {
    #my @keys = keys %$hashref;
    my $pdl1 = pdl [@$hashref{@keys}];
    my $pdl2 = pdl [@$hashref{@keys}];
    my $pdl3 = pdl [@$hashref{@keys}];
    my $pdlsum = $pdl1 * $pdl2 / $pdl3;
    #print $pdlsum;
    my $sum = $pdlsum->sum;
    #print $sum . "\n";
    return $sum;
}

sub hash_deref_once {
    my %hashd1 = %$hashref;
    my %hashd2 = %$hashref;
    my %hashd3 = %$hashref;
    my $sum = 0;
    foreach my $key (keys %hashd1) {
        $sum += $hashd1{$key} * $hashd2{$key} / $hashd3{$key};
    }
    return $sum;
}

sub hash_deref_rep {
    my $sum = 0;
    my $href1 = $hashref;
    my $href2 = $hashref;
    my $href3 = $hashref;
    foreach my $key (keys %$hashref) {
        $sum += $href1->{$key} * $href2->{$key} / $href3->{$key};
    }
    return $sum;
}

sub data_alias {
    alias my %hasha1 = %$hashref;
    alias my %hasha2 = %$hashref;
    alias my %hasha3 = %$hashref;
    
    my $sum = 0;
    foreach my $key (keys %hasha1) {
        $sum += $hasha1{$key} * $hasha2{$key} / $hasha3{$key};
    }
    return $sum;
}


__END__

Results are more mixed for 5.16.  5.20 not all listed, but are pretty consistent.

This is perl 5, version 20, subversion 1 (v5.20.1) built for MSWin32-x64-multi-thread

                  Rate hash_deref_once  hash_deref_rep      data_alias
hash_deref_once 1194/s              --            -64%            -67%
hash_deref_rep  3342/s            180%              --             -8%
data_alias      3614/s            203%              8%              --

This is perl 5, version 16, subversion 3 (v5.16.3) built for MSWin32-x64-multi-thread

                  Rate hash_deref_once      data_alias  hash_deref_rep
hash_deref_once  792/s              --            -74%            -75%
data_alias      3020/s            281%              --             -6%
hash_deref_rep  3210/s            305%              6%              --

                  Rate hash_deref_once  hash_deref_rep      data_alias
hash_deref_once 1282/s              --            -60%            -64%
hash_deref_rep  3221/s            151%              --             -9%
data_alias      3533/s            176%             10%              --

                  Rate hash_deref_once  hash_deref_rep      data_alias
hash_deref_once 1297/s              --            -59%            -65%
hash_deref_rep  3181/s            145%              --            -15%
data_alias      3724/s            187%             17%              --

                  Rate hash_deref_once  hash_deref_rep      data_alias
hash_deref_once 1297/s              --            -60%            -62%
hash_deref_rep  3256/s            151%              --             -5%
data_alias      3413/s            163%              5%              --
