#!/usr/bin/perl -w
use strict;
use warnings;

use English qw { -no_match_vars };
use Carp;

use FindBin qw { $Bin };
use File::Spec;
use POSIX qw { fmod };
use File::Basename;
use Ref::Util qw { :all };


#use lib File::Spec->catfile( $Bin, '..', 'lib');
#eval 'use mylib';
use rlib;

use Data::Dumper;

use Biodiverse::BaseData;
use Biodiverse::Common;
use Biodiverse::Cluster;


#  load up the user defined libs
use Biodiverse::Config qw /use_base add_lib_paths/;
BEGIN {
    add_lib_paths();
    use_base();
}

$| = 1;


#  Create a sparse matrix from which correlograms can be derived.
#  Prints the matrix out as it goes to avoid memory limits.
#  See the usage sub for how to call it with arguments

my $bd_file   = $ARGV[0];
my $out_file  = $ARGV[1];
my %rest;
eval {
    %rest = @ARGV;
};
croak $EVAL_ERROR if $EVAL_ERROR;

die ("BaseData file not specified\n" . usage())
  if not defined $bd_file;
die ("Output file not specified\n" . usage())
  if not defined $out_file;

print 'Args are: ' . Dumper \%rest;

my $index     = $rest{metric}  || 'SORENSON';
my $max_lag   = $rest{max_lag};
my $sp_cond_f = $rest{sp_cond};
my $def_q_f   = $rest{def_q};
my $no_dir    = $rest{no_dir};
my $overwrite = $rest{overwrite} // 1;
my $lag_size  = $rest{lag_size} || 0;

#die usage() if ! defined $bd_file;

my @coord_flds = [0,1];  #  assuming first two axes are the coord fields


my $bd = eval {
    Biodiverse::BaseData->new(file => $bd_file);
};
croak $EVAL_ERROR if $EVAL_ERROR;

my $out_filex = $out_file . 'x';

if ($overwrite or not -e $out_filex) {
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

    build_matrix($bd, $out_filex, $sp_cond, $def_q);
};

process_results ($bd, $out_filex);




sub process_results {
    my ($bd, $out_filex) = @_;
    
    print "Processing results\n";
    
    open (my $fh, '<', $out_filex)
      or croak "Unable to open $out_filex to read the results";
    open (my $ofh, '>', $out_file)
      or croak "Unable to open $out_file to write the distance results";
    
    my $csv = $bd->get_csv_object;
    my $gp  = $bd->get_groups_ref;
    my %done;
    
    #  and now read the file back, calculating the distances
    #  it is inefficient to write then read, but should work
    my $header = <$fh>;
    my @orig_header = $bd->csv2list(
        csv_object => $csv,
        string     => $header,
    );
    my @header = qw /x1 y1 x2 y2/;
    push @header, $orig_header[-1];
    push @header, 'distance';
    if (! $no_dir) {
        push @header, 'direction';
    };
    print {$ofh}
      $bd->list2csv(list => \@header, csv_object => $csv)
      . "\n";

    LINE:
    while (my $line = <$fh>) {

        my @line = $bd->csv2list(
            csv_object => $csv,
            string     => $line,
        );
        my ($from, $to, $value) = @line;

        next LINE if exists $done{$from}{$to} or exists $done{$to}{$from};

        my @coord1 = $gp->get_element_name_as_array (element => $from);
        my @coord2 = $gp->get_element_name_as_array (element => $to);

        my $offsets = [
            $coord1[0] - $coord2[0],
            $coord1[1] - $coord2[1],
        ];

        my $dist = sqrt (
            $offsets->[0] ** 2
          + $offsets->[1] ** 2
        );
        if ($lag_size) {
            $dist -= fmod ($dist, $lag_size);
        }
        next if $max_lag and $dist > $max_lag;
    
        my @result = (@coord1, @coord2, $value, $dist);
        if (! $no_dir) {
            my $dir = atan2 ($offsets->[1], $offsets->[0]);
            push @result, $dir;
        }

        my $line2 = $bd->list2csv(list => \@result, csv_object => $csv);
        print {$ofh} $line2 . "\n";

        $done{$from}{$to} ++;
    }

    return;
}

sub build_matrix {
    my ($bd, $outfile, $spatial_conditions, $def_query) = @_;

    open (my $ofh, '>', $outfile) or croak "Cannot open $outfile for writing";

    my $clus = $bd->add_cluster_output (name => $out_file);
    
    my $no_cache_abc = 1;
    
    #  experimental
    #my $def_query = "sp_match_text (type => q{proc}, text => q{Abrolhos}, axis => -1)";
    #my $def_query = $def_q;
    
    #my $spatial_conditions = [
    #    $sp_cond,
    #];
    if (defined $spatial_conditions && !is_arrayref($spatial_conditions)) {
        $spatial_conditions = [$spatial_conditions];
    }

    my %args = (
        definition_query   => $def_query,
        index              => $index,
        no_cache_abc       => $no_cache_abc,
        spatial_conditions => $spatial_conditions,
    );

    #print {$ofh} "FROM,TO,$index\n";

    my $success = eval {
        $clus-> build_matrices (
            %args,
            flatten_tree => 1,
            no_cache_abc => 1,
            file_handles => [$ofh],
        );
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    $ofh->close;

    return;
}

sub usage {
    my($filename, $directories, $suffix) = File::Basename::fileparse($0);

    my $usage = << "END_OF_USAGE";
Biodiverse - A spatial analysis tool for species (and other) diversity.

usage: \n
    $filename <basedata file> <out file name>
        metric    {index}
        max_lag   {max_lag}
        sp_cond   {spatial conditions file}
        def_q     {definition query file}
        overwrite {1 | 0}
        lag_size  {0}
        no_dir    {0}    

    The default index is SORENSON.
    Variables after <out file name> are keyword/value pairs, all on one line.  e.g.:
    $filename fred.bds out.csv sp_cond sp.txt

END_OF_USAGE

    return $usage;
}
 
