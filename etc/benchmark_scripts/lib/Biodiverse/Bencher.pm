package Biodiverse::Bencher;
use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw/
    merge_hash_keys
    copy_values_from
    merge_hash_keys_lastif
/;

use Inline 'C';

1;

__DATA__

__C__

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
    //  Could use hv_fetch_ent with the lval arg set to 1.
    //  That will autovivify an undef entry
    //  http://stackoverflow.com/questions/19832153/hash-keys-behavior
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

