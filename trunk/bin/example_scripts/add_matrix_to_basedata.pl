#!/usr/bin/perl -w
use strict;
use warnings;

use English qw { -no_match_vars };
use Carp;

use FindBin qw { $Bin };
use File::Spec;

use File::Basename;

#  fragile - does not allow for file moves
use lib File::Spec->catfile( $Bin, '..', '..', 'lib');


use Biodiverse::BaseData;
use Biodiverse::Common;
use Biodiverse::Cluster;
use Biodiverse::Tree;
use Biodiverse::Matrix;

#  load up the user defined libs
use Biodiverse::Config qw /use_base add_lib_paths/;
BEGIN {
    add_lib_paths();
    use_base();
}

local $| = 1;



#  Add a matrix to a basedata file
#
#  perl add_matrix_to_basedata.pl input.bds NAME {index SORENSON} {rest_of_args}

my $bd_file = $ARGV[0];
my $name    = $ARGV[1];
my %rest_of_args;
eval {
    %rest_of_args = @ARGV;
};
croak $EVAL_ERROR if $EVAL_ERROR;

die ("BaseData file not specified\n" . usage())
  if not defined $bd_file;

my $index     = $rest_of_args{metric}  || 'SORENSON';
my $sp_cond_f = $rest_of_args{sp_cond};
my $def_q_f   = $rest_of_args{def_q};


print "Loading basedata $bd_file\n";
my $bd = eval {
    Biodiverse::BaseData->new(file => $bd_file);
};
croak $EVAL_ERROR if $EVAL_ERROR;


my ($sp_cond, $def_q);
if ($sp_cond_f) {
    open (my $sp_cond_fh, '<', $sp_cond_f)
      or croak "Cannot open spatial conditions file $sp_cond_f";
    local $/ = undef;
    $sp_cond = <$sp_cond_fh>;
}
if ($def_q_f) {
    open (my $def_q_fh, '<', $def_q_f)
      or croak "Cannot open definition query file $def_q_f";
    local $/ = undef;
    $def_q = <$def_q_fh>;
}

$rest_of_args{tree_ref}   = load_tree (%rest_of_args);
$rest_of_args{matrix_ref} = load_matrix (%rest_of_args);

print "Building matrix\n";
build_matrix($bd, $name, $sp_cond, $def_q, %rest_of_args);

$bd->save (filename => $bd_file);

undef $bd;

exit;


sub build_matrix {
    my ($bd, $name, $spatial_conditions, $def_query, %mx_args) = @_;

    my $clus = $bd->add_cluster_output (name => $name);
    
    my $no_cache_abc = 1;

    if (defined $spatial_conditions && (ref $spatial_conditions) !~ /ARRAY/) {
        $spatial_conditions = [$spatial_conditions];
    }

    my %args = (
        definition_query   => $def_query,
        index              => $index,
        no_cache_abc       => $no_cache_abc,
        spatial_conditions => $spatial_conditions,
        %mx_args,
    );

    #print {$ofh} "FROM,TO,$index\n";
    print "Building matrix elements\n";
    my $matrices = eval {
        $clus->build_matrices (
            %args,
            flatten_tree => 1,
            build_matrices_only => 1,
        );
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    $clus->add_matrices_to_basedata(matrices => $matrices);

    return;
}

sub load_tree {
    my %args = @_;
    
    return if not $args{tree};
    
    my $tree = Biodiverse::Tree->new(file => $args{tree});
    return $tree;
}

sub load_matrix {
    my %args = @_;
    
    return if not $args{matrix};
    
    my $tree = Biodiverse::Matrix->new(file => $args{matrix});
    return $tree;
}

sub usage {
    my($filename, $directories, $suffix) = File::Basename::fileparse($0);

    my $usage = << "END_OF_USAGE";
Biodiverse - A spatial analysis tool for species (and other) diversity.

usage: \n
    $filename <basedata file> <results name>
        index     {index}
        sp_cond   {spatial conditions file}
        def_q     {definition query file}
        tree      {Biodiverse tree file (e.g. tree.bts)}
        matrix    {Biodiverse matrix file (e.g. mx.bms)}

    The default index is SORENSON.
    Variables after <results name> are keyword/value pairs, all on one line.  e.g.:
    $filename fred.bds mx sp_cond sp.txt index PHYLOSORENSON tree tree.bts

END_OF_USAGE

    return $usage;
}
 