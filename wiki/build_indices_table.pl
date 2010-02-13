#!/usr/bin/perl -w
use strict;
use warnings;
use Carp;


use Biodiverse::BaseData;
use Data::Dumper;

#use HTML::HashTable;
use HTML::QuickTable;

my $self = Biodiverse::BaseData -> new;
$self -> set_param (CELLSIZE => [1,1]);
$self -> add_element (                    
    label => 'a:b',
    group => '1:1',
    count => 1,
);


my $html = $self -> get_calculation_metadata_as_wiki;

#  The YAML version
#use YAML::Syck;
#my $yaml = YAML::Syck::Dump (\%analyses_hash);
#open (my $fh_yaml, '>', 'Indices.yaml');
#print $fh_yaml $yaml;
#close $fh_yaml;



use File::Basename;

my $wiki_leader = "= Indices available in Biodiverse =\n";
   $wiki_leader .= '_Generated GMT '
                    . (gmtime)
                    . " using "
                    . basename ($0)
                    . ", Biodiverse version $Biodiverse::VERSION._\n";

my $intro_wiki = <<"END_OF_INTRO";
#summary Table of available indices

$wiki_leader

This is a listing of the indices available in Biodiverse,
ordered by the calculations used to generate them.
It is generated from the system metadata and contains all the 
information visible in the GUI, plus some addtional details.

Most of the headings are self-explanatory.  For the others:
  * The *Subroutine* is the name of the subroutine used to call the function if you are using Biodiverse through a script.  
  * The *Index* is the name of the index in the SPATIAL_RESULTS list, or if it is its own list then this will be its name.  These lists can contain a variety of values, but are usually lists of labels with some value, for example the weights used in an endemism calculation.  The names of such lists typically end in "LIST", "ARRAY", "HASH" or "LABELS". 
  * *Valid cluster metric* is whether or not the index can be used as a clustering metric.  A blank value means it cannot.
  * The *Minimum number of neighbour sets* dictates whether or not a calculation or index will be run.  If you specify only one neighbour set then all those calculations that require two sets will be dropped from the analysis.  (This is always the case for calculations applied to cluster nodes as there is only one neighbour set, defined by the set of groups linked to the terminal nodes below a cluster node).  Note that many of the calculations lump neighbour sets 1 and 2 together.  See the SpatialConditions page for more details on neighbour sets.

Note that calculations can provide different numbers of indices depending on the nature of the !BaseData set used.
This currently applies only to the [#Hierarchical_Labels Hierarchical Labels].

Table of contents:
<wiki:toc max_depth="4" />

END_OF_INTRO

my $wiki_text = $intro_wiki
                    #. $wc->html2wiki( $html );
                    . $html;

my $fh;
open ($fh, '>', 'indices.wiki') || croak;

print $fh $wiki_text;
close $fh;

#
#{
#    use HTML::WikiConverter;
#    my $wc = HTML::WikiConverter -> new ( dialect => 'MoinMoin' );
#    local $/=undef;
#    my $success = open (my $html_fh, '<', 'indices.html');
#    $html = <$html_fh>;
#    $html_fh -> close;
#    
#    my $gadget_start_text
#        = q{<wiki:gadget url="http://mathml-gadget.googlecode.com/svn/trunk/mathml-gadget.xml" border="0" up_content="};
#    my $gadget_end_text = q{"/>};
#    
#    my $wiki_text = $intro_wiki
#                    #. $wc->html2wiki( $html );
#                    . $html;
#    
#    $wiki_text =~ s{[']{3}}{\*}g;  #  google don't like '''
#    $wiki_text =~ s{[']{2}}{_}g;   #  google don't like '' neither
#    $wiki_text =~ s{^(===\s)}{\n \n $1}xgsm;  #  add space between tables and next headers
#    #$wiki_text =~ s/GADGETGADGETSTARTSTART/$gadget_start_text/g;
#    #$wiki_text =~ s/GADGETGADGETENDEND/$gadget_end_text/g;
#    $success = open (my $w_fh, '>', 'Indices.wiki');
#    print {$w_fh} $wiki_text;
#    $w_fh -> close;
#}


#$self -> write_table (type => 'GROUPS', file => 'fred.html', data => \@table);




