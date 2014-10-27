#  benchmark direct repeated use of list2csv or using a hash structure with a cache

use 5.016;

use Carp;
use Scalar::Util qw /reftype/;
use rlib '../lib', '../t/lib';

use English qw / -no_match_vars /;
local $| = 1;


use Biodiverse::BaseData;

use Benchmark qw {:all};

my $bd = Biodiverse::BaseData->new (name => 'kk');

#  array of random triples, with each triple repeated some number of times
my @array;
for (1 .. 3000) {
    my $subarray = [rand(), rand(), rand(), rand(), rand()];
    push @array, ($subarray) x 10;
}

my $compare = 0;

if ($compare) {
    my $s1 = use_csv();
    my $s2 = use_hash_cache();
    my $s3 = use_hash_cache_mk2();

    say $s1 eq $s2 ? 'SAME S1&S2' : 'NOT SAME S1 & S2';
    say $s1 eq $s3 ? 'SAME S1&S3' : 'NOT SAME S1 & S3';
}
else {
    cmpthese (
        -10,
        {
            use_csv         => sub {use_csv()},
            use_hash_cache  => sub {use_hash_cache()},
            use_hash_cache2  => sub {use_hash_cache_mk2()},
        }
    );
}


sub use_csv {
    my $csv_object = $bd->get_csv_object (
        quote_char => $bd->get_param ('QUOTES'),
        sep_char => $bd->get_param ('JOIN_CHAR'),
    );
    
    my $res = q{};
    
    foreach my $arr (@array) {
        my $string = $bd->list2csv (list => $arr, csv_object => $csv_object);
        $res .= $string if $compare;
    }
    
    return $res;
}


sub use_hash_cache {
    my $cache = {};
    my $csv_object = $bd->get_csv_object (
        quote_char => $bd->get_param ('QUOTES'),
        sep_char   => $bd->get_param ('JOIN_CHAR'),
    );
    
    my $res = q{};
    foreach my $arr (@array) {
        my $hashref = $cache;
        my ($col, $string, $prev_hashref);
        my $colval = 0;
        my $maxcolval = scalar @$arr;
        foreach $col (@$arr) {
            $prev_hashref = $hashref;
            $hashref = $hashref->{$col}
              // do {
                $hashref->{$col} = $colval < $maxcolval ? {} : undef
            };
            $colval++;
        }
        if (reftype ($hashref)) {
            $string = $bd->list2csv (list => $arr, csv_object => $csv_object);
            $prev_hashref->{$arr->[-1]} = $string;
        }
        else {
            $string = $prev_hashref->{$arr->[-1]};
        }

        $res .= $string if $compare;
    }
    
    return $res;
}

sub use_hash_cache_mk2 {
    my $cache = {};
    my $csv_object = $bd->get_csv_object (
        quote_char => $bd->get_param ('QUOTES'),
        sep_char => $bd->get_param ('JOIN_CHAR'),
    );
    
    my $res = q{};
    
    foreach my $arr (@array) {
        my $hashref = $cache;
        my ($col, $string, $prev_hashref);
        my $maxcolval = scalar @$arr;
        foreach $col (@$arr) {
            $prev_hashref = $hashref;
            $hashref = $hashref->{$col}
              // do {$hashref->{$col} = {}};
        }
        if (reftype ($hashref)) {
            $string = $bd->list2csv (list => $arr, csv_object => $csv_object);
            $prev_hashref->{$arr->[-1]} = $string;
        }
        else {
            $string = $prev_hashref->{$arr->[-1]};
        }
        $res .= $string if $compare;
    }

    return $res;
}

