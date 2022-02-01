use 5.016;


use Algorithm::BitVector;

my $bv = Algorithm::BitVector->new( size => 20000 );

$bv->set_bit(19000, 1);
$bv->set_bit(233, 1);
$bv->set_bit(243, 1);
$bv->set_bit(18, 1);
$bv->set_bit(785, 1);

say $bv->count_bits;

say $bv->count_bits_sparse;

say $bv->rank_of_bit_set_at_index (19000);

say $bv->next_set_bit (200);

my $va = $bv->{_vector};
say scalar @$va;



