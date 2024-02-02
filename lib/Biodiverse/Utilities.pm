package Biodiverse::Utilities;

use strict;
use warnings;
use 5.022;
use Carp;
use Sort::Key::Natural qw /natsort/;
use Ref::Util qw /:all/;

our $VERSION = '4.99_002';

our @ISA = qw (Exporter);
our @EXPORT = ();
our @EXPORT_OK = qw /sort_list_with_tree_names_aa/;



#  verbose name...
sub sort_list_with_tree_names_aa {
    my ($data) = @_;
    
    croak 'data arg must be an array ref'
      if !is_arrayref $data;
    
    return wantarray ? () : []
      if !@$data;

    my $re_branch_name = qr /^[0-9]+___$/;
    
    my @data = @$data;

    #  move any internal branch names to the end.
    #  We cannot guarantee that all branches will
    #  be at either end as numeric labels get mixed in
    my @branches;
    my @not_branches;
    foreach my $item (@data) {
        if ($item =~ $re_branch_name) {
            push @branches, $item;
        }
        else {
            push @not_branches, $item;
        }
    }
    my @sorted;
    if (@branches) {
        @sorted = ((natsort @not_branches), (natsort @branches));
    }
    else {
        @sorted = natsort @data;
    }

    return wantarray ? @sorted : \@sorted;    
}


1;
