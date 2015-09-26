#  Benchmark two approaches which could be used to get a total tree path length
#  It is actually to do with a hash slice vs for-last approach
use 5.016;

use Benchmark qw {:all};
use List::Util qw /max/;
use Test::More;
use Math::Random::MT::Auto;

my $prng = Math::Random::MT::Auto->new;

local $| = 1;

#srand (2000);

my $n = 20;   #  depth of the paths
my $m = 1800;  #  number of paths
my $r = $n - 1;    #  how far to be the same until (irand)
my $subset_size = int ($m/4);
my %path_arrays;  #  ordered keys
my %path_hashes;  #  unordered key-value pairs
my %len_hash;

#$n = 5;
#$m = 8;
#$r = 2;
#$subset_size = $n;

#  generate a set of paths 
foreach my $i (0 .. $m) {
    my $same_to = max (1, int (rand() * $r));
    my @a;
    #@a = map {((1+$m)*$i*$n+$_), 1} (0 .. $same_to);
    @a = map {$_ => $_} (0 .. $same_to);
    push @a, map {((1+$m)*$i*$n+$_) => $_} ($same_to+1 .. $n);
    #say join ' ', @a;
    my %hash = @a;
    $path_hashes{$i} = \%hash;
    $path_arrays{$i} = [reverse sort {$a <=> $b} keys %hash];
    
    @len_hash{keys %hash} = values %hash;
}

my $sliced = slice (\%path_hashes);
my $forled = for_last (\%path_arrays);
my $slice2 = slice_mk2 (\%path_hashes);
my $inline = inline_assign (\%path_arrays);

is_deeply ($sliced, \%len_hash, 'slice results are the same');
is_deeply ($slice2, \%len_hash, 'slice2 results are the same');
is_deeply ($forled, \%len_hash, 'forled results are the same');
is_deeply ($inline, \%len_hash, 'inline results are the same');


done_testing;

#exit();

for (0..2) {
    say "Testing $subset_size of $m paths of length $n and overlap up to $r";
    
    my @subset = ($prng->shuffle (0..$m))[0..$subset_size];
    #say scalar @subset;
    #say join ' ', @subset[0..4];
    my (%path_hash_subset, %path_array_subset);
    @path_hash_subset{@subset}  = @path_hashes{@subset};
    @path_array_subset{@subset} = @path_arrays{@subset};
    
    cmpthese (
        -4,
        {
            slice1 => sub {slice (\%path_hash_subset)},
            slice2 => sub {slice_mk2 (\%path_hash_subset)},
            forled => sub {for_last (\%path_array_subset)},
            inline => sub {inline_assign (\%path_array_subset)},
        }
    );
    say '';
}


sub slice {
    my $paths = shift;
    
    my %combined;
    
    foreach my $path (values %$paths) {
        @combined{keys %$path} = values %$path;
    }
    #@combined{keys %combined} = @len_hash{keys %combined};

    return \%combined;
}

#  assign values at end
sub slice_mk2 {
    my $paths = shift;
    
    my %combined;
    
    foreach my $path (values %$paths) {
        @combined{keys %$path} = undef;
    }
    
    @combined{keys %combined} = @len_hash{keys %combined};
    
    return \%combined;
}

sub for_last {
    my $paths = shift;
    
    
    #  initialise
    my %combined;

  LIST:
    foreach my $list (values %$paths) {
        if (!scalar keys %combined) {
            @combined{@$list} = undef;
            next LIST;
        }
        
        foreach my $key (@$list) {
            last if exists $combined{$key};
            $combined{$key} = undef;
        }
    }
    @combined{keys %combined} = @len_hash{keys %combined};

    return \%combined;
}

sub inline_assign {
    my $paths = shift;

    my %combined;

    foreach my $path (values %$paths) {
        merge_hash_keys_lastif (\%combined, $path);
    }

    copy_values_from (\%combined, \%len_hash);

    return \%combined;
}

use Inline C => <<'END_OF_C_CODE';
 
void merge_hash_keys(SV* dest, SV* from) {
  HV* hash_dest;
  HV* hash_from;
  HE* hash_entry;
  int num_keys_from, num_keys_dest, i;
  SV* sv_key;
 
  if (! SvROK(dest))
    croak("dest is not a reference");
  if (! SvROK(from))
    croak("from is not a reference");
 
  hash_from = (HV*)SvRV(from);
  hash_dest = (HV*)SvRV(dest);
  
  num_keys_from = hv_iterinit(hash_from);
  // printf ("There are %i keys in hash_from\n", num_keys_from);
  // num_keys_dest = hv_iterinit(hash_dest);
  // printf ("There are %i keys in hash_dest\n", num_keys_dest);

  for (i = 0; i < num_keys_from; i++) {
    hash_entry = hv_iternext(hash_from);
    sv_key = hv_iterkeysv(hash_entry);
    if (hv_exists_ent (hash_dest, sv_key, 0)) {
    //    printf ("Found key %s\n", SvPV(sv_key, PL_na));
    }
    else {
    //    printf ("Did not find key %s\n", SvPV(sv_key, PL_na));
        // hv_store_ent(hash_dest, sv_key, &PL_sv_undef, 0);
        hv_store_ent(hash_dest, sv_key, newSV(0), 0);
    }
    // printf ("%i: %s\n", i, SvPV(sv_key, PL_na));
  }
  return;
}

void copy_values_from (SV* dest, SV* from) {
  HV* hash_dest;
  HV* hash_from;
  HE* hash_entry_dest;
  HE* hash_entry_from;
  int num_keys_from, num_keys_dest, i;
  SV* sv_key;
  SV* sv_val_from;
 
  if (! SvROK(dest))
    croak("dest is not a reference");
  if (! SvROK(from))
    croak("from is not a reference");
 
  hash_from = (HV*)SvRV(from);
  hash_dest = (HV*)SvRV(dest);
  
  // num_keys_from = hv_iterinit(hash_from);
  // printf ("There are %i keys in hash_from\n", num_keys_from);
  num_keys_dest = hv_iterinit(hash_dest);
  // printf ("There are %i keys in hash_dest\n", num_keys_dest);

  for (i = 0; i < num_keys_dest; i++) {
    hash_entry_dest = hv_iternext(hash_dest);  
    sv_key = hv_iterkeysv(hash_entry_dest);
    // printf ("Checking key %i: '%s' (%x)\n", i, SvPV(sv_key, PL_na), sv_key);
    // exists = hv_exists_ent (hash_from, sv_key, 0);
    // printf (exists ? "Exists\n" : "not exists\n");
    if (hv_exists_ent (hash_from, sv_key, 0)) {
        // printf ("Found key %s\n", SvPV(sv_key, PL_na));
        hash_entry_from = hv_fetch_ent (hash_from, sv_key, 0, 0);
        sv_val_from = SvREFCNT_inc(HeVAL(hash_entry_from));
        // printf ("Using value '%s'\n", SvPV(sv_val_from, PL_na));
        HeVAL(hash_entry_dest) = sv_val_from;
    }
  }
  return;
}

void merge_hash_keys_lastif(SV* dest, SV* from) {
  HV* hash_dest;
  AV* arr_from;
  int i;
  SV* sv_key;
  int num_keys_from;
 
  if (! SvROK(dest))
    croak("dest is not a reference");
  if (! SvROK(from))
    croak("from is not a reference");

  arr_from  = (AV*)SvRV(from);
  hash_dest = (HV*)SvRV(dest);

  num_keys_from = av_len (arr_from);
  // printf ("There are %i keys in from list\n", num_keys_from+1);
  
  //  should use a while loop with condition being the key does not exist in dest?
  for (i = 0; i <= num_keys_from; i++) {
    SV **sv_key = av_fetch(arr_from, i, 0);  //  cargo culted from List::MoreUtils::insert_after
    // printf ("Checking key %s\n", SvPV(*sv_key, PL_na));
    if (hv_exists_ent (hash_dest, *sv_key, 0)) {
        // printf ("Found key %s\n", SvPV(*sv_key, PL_na));
        break;
    }
    else {
        // hv_store_ent(hash_dest, *sv_key, &PL_sv_undef, 0);
        hv_store_ent(hash_dest, *sv_key, newSV(0), 0);
    }
  }
  return;
}


END_OF_C_CODE



1;

__END__

Sample results below.
Some runs have no meaningful difference from sliced to slice2,
but slice2 is always faster (even if only 2%).
Normally it is ~15% faster.  


Testing 800 paths of depth 20
         Rate forled sliced slice2
forled 59.2/s     --   -69%   -73%
sliced  192/s   225%     --   -13%
slice2  222/s   275%    15%     --

Testing 800 paths of depth 20
         Rate forled sliced slice2
forled 49.5/s     --   -74%   -77%
sliced  194/s   292%     --   -12%
slice2  219/s   342%    13%     --
