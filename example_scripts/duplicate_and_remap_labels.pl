use strict;
use warnings;
use 5.010;

use rlib;

use Getopt::Long::Descriptive;
 
use Carp;
use English qw { -no_match_vars };

use Biodiverse::BaseData;
use Biodiverse::ElementProperties;

if ($ENV{BDV_PP_BUILDING}) {
    say 'Building pp file';
    use File::BOM qw / :subs /;          #  we need File::BOM.
    open my $fh, '<:via(File::BOM)', $0  #  just read ourselves
      or croak "Cannot open $0 via File::BOM\n";
    $fh->close;
    exit ;
}

my ($opt, $usage) = describe_options(
  '%c <arguments>',
  [ 'basedata|input_bd=s',   'The input basedata file', { required => 1 } ],
  [ 'out_file|output_bd=s',  'The output basedata file', { required => 1 }],
  [ 'remap_file|rf=s',       'The text file containing label remap details', { required => 1 } ],
  [ 'input_cols|ic=s',       'The columns in the remap file that match the original labels, comma separated, no spaces [default= "1"]', { default => '1' } ],
  [ 'remapped_cols|rc=s',    'The columns in the remap file to generate the remapped labels, comma separated, no spaces [default = "1,2"]', { default => '1,2' } ],
  [ 'input_sep_char|is=s',   'Column separator character in the remap file [default = ","]', { default => q{,} } ],
  [ 'input_quote_char|iq=s', 'Quotes character in the remap file [default = "]', { default => q{"} } ],
  [ 'verbose|v!',            'Warns if labels are not remapped when copied across [default = 1]', { default => 1 } ],
  [],
  [ 'help',       "print usage message and exit" ],
);
 
if ($opt->help) {
    print($usage->text);
    exit;
}

my $bd_file           = $opt->basedata;
my $out_file          = $opt->out_file;
my $remap_file        = $opt->remap_file;
my $input_cols_str    = $opt->input_cols;
my $remapped_cols_str = $opt->remapped_cols;
my $input_sep_char    = $opt->input_sep_char;
my $input_quote_char  = $opt->input_quote_char;
my $verbose           = $opt->verbose;


my $bd = eval {Biodiverse::BaseData->new(file => $bd_file)};
croak $@ if $@;

#  flip the order since we want one to many, and props do one to one
my @remapped_cols = split ',', $input_cols_str;
my @input_cols    = split ',', $remapped_cols_str;

my $remap = Biodiverse::ElementProperties->new();
$remap->import_data (
    file                  => $remap_file,
    input_element_cols    => \@input_cols,
    remapped_element_cols => \@remapped_cols,
    input_sep_char        => $input_sep_char,
    input_quote_char      => $input_quote_char,
);


#  Get a hash of arrays, where each original label has an array
#  of labels it is to be remapped to.
my %label_remap_hash;
foreach my $element ($remap->get_element_list()) {
    my $bd_label = $remap->get_element_remapped(element => $element);
    if (!exists $label_remap_hash{$bd_label}) {
        $label_remap_hash{$bd_label} = [];
    }
    push @{$label_remap_hash{$bd_label}}, $element;
}

#  Create the new basedata to be populated.
my $new_bd = Biodiverse::BaseData->new(
    CELL_SIZES => $bd->get_param('CELL_SIZES'),
    NAME       => $bd->get_param('NAME'),
);

#  Now iterate over the original basedata, copying across remapped labels
#  Warn when labels aren't remapped.
BD_LABEL:
foreach my $bd_label ($bd->get_labels) {
    my $remapped = $label_remap_hash{$bd_label};
    if (!$remapped && $verbose) {
        warn "Label $bd_label has not been remapped\n";
        $remapped = [$bd_label];
        #next BD_LABEL;
    }
    
    my %bd_groups = $bd->get_groups_with_label_as_hash(label => $bd_label);
    foreach my $new_label (@$remapped) {
        while (my ($gp, $count) = each %bd_groups) {
            $new_bd->add_element (label => $new_label, group => $gp, count => $count);
        }
    }
}

$new_bd->save (filename => $out_file);

say 'Completed';
