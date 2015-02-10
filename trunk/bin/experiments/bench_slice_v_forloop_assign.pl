
use Benchmark qw {:all};
use 5.016;


$| = 1;

use constant USE_TWO_HASHES => 1;

my $check_count = 1000;

my $other_hash = {0 .. 1001};  #  we need deref as part of this benchmark

no warnings 'uninitialized';

cmpthese (
    -1,
    {
        slice_assign => sub {slice_assign()},
        loop_assign  => sub {loop_assign()},
        loop_bkgnd   => sub {loop_bkgnd()},
    }
);


sub slice_assign {
    my %hash = (0 .. 101);
    my %hash2;
    @hash{keys %$other_hash} = values %$other_hash;
    if (USE_TWO_HASHES) {
        while (my ($key, $value) = each %$other_hash) {
            $hash2{$key} = $value;
        }
    }
}

sub loop_assign {
    my %hash = (0 .. 101);
    my %hash2;
    while (my ($key, $value) = each %$other_hash) {
        $hash{$key}  = $value;
        if (USE_TWO_HASHES) {
            $hash2{$key} = $value;
        }
    }
}

#  how much does the loop take?
sub loop_bkgnd {
    my %hash = (0 .. 101);
    my %hash2;
    while (my ($key, $value) = each %$other_hash) {
        #$hash{$key} = $value;
    }
}

__END__


Loop approach pays off if more than one hash is assigned to.
Results differ if run under the debugger, but that's not how the code is used in the wild. 

#  sample run with USE_TWO_HASHES = 1
#  $other_hash = {0 .. 1001}

               Rate slice_assign  loop_assign   loop_bkgnd
slice_assign 2666/s           --          -3%         -48%
loop_assign  2739/s           3%           --         -47%
loop_bkgnd   5157/s          93%          88%           --

#  sample run with USE_TWO_HASHES = 0
#  $other_hash = {0 .. 1001}

               Rate  loop_assign   loop_bkgnd slice_assign
loop_assign  3413/s           --         -30%         -63%
loop_bkgnd   4859/s          42%           --         -47%
slice_assign 9150/s         168%          88%           --
