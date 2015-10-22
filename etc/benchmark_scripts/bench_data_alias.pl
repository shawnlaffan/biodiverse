
use Benchmark qw {:all};
use 5.016;
use Data::Dumper;
use Data::Alias qw /alias/;


my %hashbase;
#@hash{1..1000} = (rand()) x 1000;
for my $i (1..1000) {
    $hashbase{$i} = rand() + 1;
}
my $hashref = \%hashbase;

cmpthese (
    -5,
    {
        hash_deref_once => sub {hash_deref_once ()},
        data_alias => sub {data_alias ()},
        hash_deref_rep => sub {hash_deref_rep ()},
    }
);


sub hash_deref_once {
    my %hashd1 = %$hashref;
    my %hashd2 = %$hashref;
    my %hashd3 = %$hashref;
    my $sum = 0;
    foreach my $key (keys %hashd1) {
        $sum += $hashd1{$key} * $hashd2{$key} / $hashd3{$key};
    }
}

sub hash_deref_rep {
    my $sum = 0;
    my $href1 = $hashref;
    my $href2 = $hashref;
    my $href3 = $hashref;
    foreach my $key (keys %$hashref) {
        $sum += $href1->{$key} * $href2->{$key} / $href3->{$key};
    }
}

sub data_alias {
    alias my %hasha1 = %$hashref;
    alias my %hasha2 = %$hashref;
    alias my %hasha3 = %$hashref;
    
    my $sum = 0;
    foreach my $key (keys %hasha1) {
        $sum += $hasha1{$key} * $hasha2{$key} / $hasha3{$key};
    }
}


__END__

This is perl 5, version 20, subversion 1 (v5.20.1) built for MSWin32-x64-multi-thread

                  Rate hash_deref_once  hash_deref_rep      data_alias
hash_deref_once 1194/s              --            -64%            -67%
hash_deref_rep  3342/s            180%              --             -8%
data_alias      3614/s            203%              8%              --

