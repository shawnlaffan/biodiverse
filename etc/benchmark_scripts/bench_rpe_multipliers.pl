
use Benchmark qw {:all :hireswallclock};
use 5.024;
use Data::Dumper;
use PDL;
use Biodiverse::Utils qw /get_rpe_null/;

use Inline 'C';

use experimental qw /refaliasing/;

my %hashbase;
#@hash{1..1000} = (rand()) x 1000;
for my $i (1..1000) {
    $hashbase{$i} = rand() + 1;
}
my $hashref = \%hashbase;

my @hash_keys_sorted = sort keys %$hashref;
my $gpdl1 = pdl @$hashref{@hash_keys_sorted};
my $gpdl2 = pdl @$hashref{@hash_keys_sorted};
my $gpdl3 = pdl @$hashref{@hash_keys_sorted};
my $buf_blen_global = pack "d*", @$hashref{@hash_keys_sorted};
my $buf_lr_global   = pack "d*", @$hashref{@hash_keys_sorted};
my $buf_gr_global   = pack "d*", @$hashref{@hash_keys_sorted};

say ref_alias();
say hash_deref_rep();
say pdl_build_each_time();
say pdl_build_once();
say bd_utils();
say use_xs_buffer();
say use_xs_buffer_keys();
say use_xs_buffers_build_once();

say "Hash size: " . scalar keys %$hashref;

cmpthese (
    -2,
    {
        ref_alias      => sub {ref_alias ()},
        hash_deref_rep => sub {hash_deref_rep ()},
        pdl_build_each_time => sub {pdl_build_each_time ()},
        pdl_build_once      => sub {pdl_build_once ()},
        bd_utils            => sub {bd_utils()},
        xs_buffers          => sub {use_xs_buffer()},
        xs_buffer_keys      => sub {use_xs_buffer_keys()},
        xs_buffers_build_once => sub {use_xs_buffers_build_once()},
    }
);


sub bd_utils {
    my $href1 = $hashref;
    my $href2 = $hashref;
    my $href3 = $hashref;
    
    return get_rpe_null ($href1, $href2, $href3);
}

sub pdl_build_once {
    return ($gpdl1 * $gpdl2 / $gpdl3)->sum;
}

sub pdl_build_each_time {
    #my @hash_keys_sorted = keys %$hashref;
    my $pdl1 = pdl [@$hashref{@hash_keys_sorted}];
    my $pdl2 = pdl [@$hashref{@hash_keys_sorted}];
    my $pdl3 = pdl [@$hashref{@hash_keys_sorted}];
    my $pdlsum = $pdl1 * $pdl2 / $pdl3;
    #print $pdlsum;
    my $sum = $pdlsum->sum;
    #print $sum . "\n";
    return $sum;
}


sub hash_deref_rep {
    my $sum = 0;
    my $href1 = $hashref;
    my $href2 = $hashref;
    my $href3 = $hashref;
    foreach my $key (@hash_keys_sorted) {
        $sum += $href1->{$key} * $href2->{$key} / $href3->{$key};
    }
    return $sum;
}

sub ref_alias {
    \my %hasha1 = $hashref;
    \my %hasha2 = $hashref;
    \my %hasha3 = $hashref;
    
    my $sum = 0;
    foreach my $key (@hash_keys_sorted) {
        $sum += $hasha1{$key} * $hasha2{$key} / $hasha3{$key};
    }
    return $sum;
}

sub use_xs_buffer {
    my $b_buf  = pack "d*", @{$hashref}{@hash_keys_sorted};
    my $lr_buf = pack "d*", @{$hashref}{@hash_keys_sorted};
    my $gr_buf = pack "d*", @{$hashref}{@hash_keys_sorted};

    return xs_buffer_it ($b_buf, $lr_buf, $gr_buf);
}

sub use_xs_buffer_keys {
    my @keys   = keys %$hashref;
    my $b_buf  = pack "d*", @{$hashref}{@keys};
    my $lr_buf = pack "d*", @{$hashref}{@keys};
    my $gr_buf = pack "d*", @{$hashref}{@keys};

    return xs_buffer_it ($b_buf, $lr_buf, $gr_buf);
}

sub use_xs_buffers_build_once {
    return xs_buffer_it ($buf_blen_global, $buf_lr_global, $buf_gr_global);
}

__END__

Hash size: 1000
                          Rate pdl_build_each_time hash_deref_rep ref_alias bd_utils xs_buffers pdl_build_once xs_buffers_build_once
pdl_build_each_time     2876/s                  --           -35%      -39%     -62%       -77%           -94%                 -100%
hash_deref_rep          4416/s                 54%             --       -6%     -42%       -65%           -91%                  -99%
ref_alias               4708/s                 64%             7%        --     -38%       -63%           -90%                  -99%
bd_utils                7640/s                166%            73%       62%       --       -39%           -84%                  -99%
xs_buffers             12588/s                338%           185%      167%      65%         --           -73%                  -98%
pdl_build_once         46995/s               1534%           964%      898%     515%       273%             --                  -92%
xs_buffers_build_once 614663/s              21269%         13820%    12956%    7946%      4783%          1208%                    --

Hash size: 10000
                         Rate pdl_build_each_time hash_deref_rep ref_alias bd_utils xs_buffers pdl_build_once xs_buffers_build_once
pdl_build_each_time     309/s                  --           -21%      -23%     -58%       -73%           -98%                 -100%
hash_deref_rep          390/s                 26%             --       -3%     -47%       -66%           -98%                  -99%
ref_alias               403/s                 30%             3%        --     -45%       -65%           -97%                  -99%
bd_utils                736/s                138%            89%       83%       --       -35%           -95%                  -99%
xs_buffers             1140/s                269%           192%      183%      55%         --           -93%                  -98%
pdl_build_once        15816/s               5015%          3953%     3827%    2049%      1288%             --                  -78%
xs_buffers_build_once 71106/s              22897%         18120%    17554%    9560%      6139%           350%                    --


__C__

const strlen_size = sizeof(STRLEN);
const nv_size = sizeof(NV);

#define xlort sizeof(NV)

NV
xs_buffer_it (SV *b_len_buf, SV *lr_buf, SV *gr_buf) {
    STRLEN lr_len;
    STRLEN gr_len;
    STRLEN b_len;
    NV *lr_pos = (NV*) SvPV(lr_buf, lr_len);
    NV *gr_pos = (NV*) SvPV(gr_buf, gr_len);
    NV *b_pos  = (NV*) SvPV(b_len_buf, b_len);
    NV *b_end  = b_pos + (b_len / xlort);
    
    NV wt_sum = 0;

    if (b_len == 0) {
        return 0.0;  // avoid some segfaults
    }
    else if (lr_len != b_len || gr_len != gr_len) {
        croak ("buffer sizes do not match (%d, %d, %d)", b_len, lr_len, gr_len);
    }

    for (;b_pos < b_end; b_pos++) {
        NV gr = (NV) *gr_pos;

        if (gr != 0) {
            NV b  = (NV) *b_pos;
            NV lr = (NV) *lr_pos;
            wt_sum += b * (lr / gr);
        }

        lr_pos++;
        gr_pos++;
    }

    return wt_sum;
}
