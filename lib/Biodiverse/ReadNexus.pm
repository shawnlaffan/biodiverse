package Biodiverse::ReadNexus;

#  Read in a nexus tree file and extract the trees into Biodiverse::Tree files
#  Initial work by Dan Rosauer
#  regex based approach by Shawn Laffan
use 5.010;
use strict;
use warnings;
use Carp;
use English ( -no_match_vars );

use Scalar::Util qw /looks_like_number/;
use List::Util qw /max/;

use Biodiverse::Tree;
use Biodiverse::TreeNode;
use Biodiverse::Exception;
use Biodiverse::Progress;

our $VERSION = '2.99_005';

use parent qw /Biodiverse::Common/;

#  hunt for any decimal number format
use Regexp::Common qw /number delimited/;
my $RE_NUMBER = qr /$RE{num}{real}/xms;
my $RE_QUOTED = qr /$RE{delimited}{-delim=>"'"}{-esc=>"'"}/;

my $RE_TEXT_IN_QUOTES
    = qr{
        \A
        (['"])
        (.+)  #  text inside quotes is \2 and $2
        \1
        \z
    }xms;

my $EMPTY_STRING = q{};

#$text_in_brackets = qr / ( [^()] )* /x; #  from page 328, but doesn't work here
my $re_text_in_brackets;  #  straight from Friedl, page 330.  Could be overkill, but works
$re_text_in_brackets = qr / (?> [^()]+ | \(  (??{ $re_text_in_brackets }) \) )* /xo; #/
#  poss alternative for perl 5.10 and later:  qr /(\\((?:[^()]++|(?-1))*+\\))/xo
#  from http://blogs.perl.org/users/jeffrey_kegler/2012/08/marpa-v-perl-regexes-a-rematch.html

my $re_text_in_square_brackets;  #  modified from Friedl, page 330.
$re_text_in_square_brackets = qr / (?> [^\[\]]+ | \[  (??{ $re_text_in_square_brackets }) \] )* /xo; #/


sub new {
    my $class = shift;
    
    my %PARAMS = (
        JOIN_CHAR   => q{:},
        QUOTES      => q{'},
    );
    
    my $self = bless {
        'TREE_ARRAY' => [],
    }, $class;
    
    $self->set_params (%PARAMS, @_);
    $self->set_default_params;  #  and any user overrides
    
    return $self;
}

sub add_tree {
    my $self = shift;
    my %args = @_;

    return if ! defined $args{tree};

    push @{$self->{TREE_ARRAY}}, $args{tree};

    return;
}



#  now we need to set up the methods to load the tree etc

sub import_data {
    my $self = shift;
    my %args = @_;
    
    my $element_properties = $args{element_properties};
    my $use_element_properties = exists $args{use_element_properties}  #  just a flag of convenience
                                    ? $args{use_element_properties}
                                    : defined $element_properties;
    $self->set_param (ELEMENT_PROPERTIES => $element_properties);
    $self->set_param (USE_ELEMENT_PROPERTIES => $use_element_properties);
    
    my @import_methods = qw /import_nexus import_phylip import_tabular_tree/;
    if (defined $args{file} && $args{file} =~ /(txt|csv)$/) {  #  dirty hack
        @import_methods = ('import_tabular_tree');
    }
    my $success;
    
  IMPORT_METHOD:
    foreach my $method (@import_methods) {
        eval {
            $self->$method (%args);
        };
        if ($EVAL_ERROR) {
            if (Biodiverse::ReadNexus::IncorrectFormat->caught) {
                next IMPORT_METHOD;
            }
            else {
                Biodiverse::ReadNexus::IncorrectFormat->throw (
                    message => "Unable to import data:\n" . $EVAL_ERROR,
                    type    => 'generic',
                );
            }
        }
        $success = 1;
        last IMPORT_METHOD;
    }

    if (!$success) {
        Biodiverse::ReadNexus::IncorrectFormat->throw (
            message => "Unable to import data",
            type    => 'generic',
        );
    }

    $self->process_zero_length_trees;
    $self->process_unrooted_trees;

    return 1;
}

#  import the tree from a newick file
sub import_newick {
    my $self = shift;
    my %args = @_;

    my $newick = $args{data};

    croak "Neither file nor data arg specified\n"
        if not defined $newick and not defined $args{file};

    if (! defined $newick) {
        $newick = $self->read_whole_file (file => $args{file});
    }

    my $tree = Biodiverse::Tree->new (
        NAME => $args{NAME}
            || 'anonymous from newick'
        );

    my $count = 0;
    my $node_count = \$count;

    $self->parse_newick (
        string          => $newick,
        tree            => $tree,
        node_count      => $node_count,
    );
    
    $self->add_tree (tree => $tree);

    return 1;
}

#  Import trees from the phylip format
#  This is just a collection of semicolon separate newicks
#  should really combine with or replace import_newick
#  as they do almost the same thing
sub import_phylip {
    my $self = shift;
    my %args = @_;

    my $data = $args{data};

    croak "Neither file nor data arg specified\n"
      if not defined $data and not defined $args{file};

    if (! defined $data) {
        $data = $self->read_whole_file (file => $args{file});
    }

    #  lazy split - does not allow for quoted semicolons
    my @newicks = split /;/, $data;

    my $progress = Biodiverse::Progress->new;
    my $target_count = scalar @newicks;
    my $i = 0;

    foreach my $nwk (@newicks) {
        next if $nwk =~ /^[\s\n]*$/;

        my $tree_name = 'anonymous_' . $i;
        my $tree = Biodiverse::Tree->new (NAME => $tree_name);

        $i++;
        $progress->update("Tree $i of $target_count\n$tree_name", $i / $target_count);

        my $count = 0;
        my $node_count = \$count;

        eval {
            $self->parse_newick (
                string          => $nwk,
                tree            => $tree,
                node_count      => $node_count,
            );
        };
        if ($EVAL_ERROR) {  #  not sure this will work
            Biodiverse::ReadNexus::IncorrectFormat->throw (
                message => 'Data has no trees in it, or is not Nexus format',
                type    => 'phylip',
            );
        }

        $self->add_tree (tree => $tree);
    }
    
    
}

# import the trees from a nexus file
sub import_nexus {
    my $self = shift;
    my %args = @_;

    my $nexus = $args{data};

    croak "Neither file nor data arg specified\n"
      if not defined $nexus and not defined $args{file};

    if (! defined $nexus) {
        $nexus = $self->read_whole_file (file => $args{file});
    }

    my @nexus = split (/[\r\n]+/, $nexus);
    my %translate;
    my @newicks;

    pos ($nexus) = 0;
    my $in_trees_block = 0;

    #  now we extract the tree block
    BY_LINE:
    while (defined (my $line = shift @nexus)) {  #  haven't hit the end of the file yet
        #print "position is " . pos ($nexus) . "\n";

        # skip any lines before the tree block
        if (not $in_trees_block and $line =~ m/\s*begin trees;/i) {
            $in_trees_block = 1;
            $line = shift @nexus;  #  get the next line now we're in the trees block
            next BY_LINE if not defined $line;
        }

        next BY_LINE if not $in_trees_block;

        #print "$line\n";

        #  drop out if we are at the end or endblock that closes the trees block
        last if $line =~ m/\s*end(?:block)?;/i;

        #  now we are in the tree block, process the lines as appropriate

        if ($line =~ m/^\s*\[/) {  #  comment - munch to the end of the comment
            next BY_LINE if $line =~ /\]/;  #  comment closer is on this line
            while (my $comment = shift @nexus) {
                next unless $comment =~ /\]/;
                next BY_LINE;  #  we hit the closing comment marker, move to the next line
            }
        }
        elsif ($line =~ m/\s*Translate/i) {  #  translate block - munch to the end of it and store the translations

            TRANSLATE_BLOCK:
            while (my $trans = shift @nexus) {
                #print "$trans\n";
                my ($trans_code, $trans_name)
                    = $trans =~  m{  \s*     #  zero or more whitespace chars
                                    (\S+)    #  typically a number
                                     \s+     #  one or more whitespace chars
                                    ($RE_QUOTED | \S+)    #  the label
                                  }x;
                if (defined $trans_code) {
                    #  delete trailing comma or semicolon
                    $trans_name =~ s{ [,;]
                                      \s*
                                      \z
                                    }
                                    {}xms;
                    #if ($trans_name =~ / ^\' /) {
                    #if (my @components = $trans_name =~ $RE_TEXT_IN_QUOTES) {
                        #$trans_name = $1;
                        #$trans_name =~ s/^'//;  #  strip back the quotes
                        #$trans_name =~ s/'$//;
                        #$trans_name =~ s/''/'/g;
                    #}
                    $translate{$trans_code} = $trans_name;
                }
                last TRANSLATE_BLOCK if $trans =~ /;\s*\z/;  #  semicolon marks the end
            }
        }
        elsif ($line =~ m/^\s*tree/i) {  #  tree - extract it

            my $nwk = $line;
            if (not $line =~ m/;\s*$/) {  #  tree is not finished unless we end in a semi colon, maybe with some white space
                
                TREE_LINES:
                while (my $tree_line = shift @nexus) {
                    $tree_line =~ s{[\r\n]} {};  #  delete any newlines, although they should already be gone...
                    $nwk .= $tree_line;
                    last if $tree_line =~ m/;\s*$/;  #  ends in a semi-colon
                }
            }

            push @newicks, $nwk;
        }
    }

    if (scalar @newicks == 0) {
        Biodiverse::ReadNexus::IncorrectFormat->throw (
            message => 'Data has no trees in it, or is not Nexus format',
            type    => 'nexus',
        );
    }

    $self->set_param (TRANSLATE_HASH => \%translate);  #  store for future use
    
    my $progress = Biodiverse::Progress->new;
    my $target_count = scalar @newicks;
    my $i = 0;

    foreach my $nwk (@newicks) {
            $i++;

            #  remove trailing semi-colon
            $nwk =~ s/;$//;

            my $tree_name = $EMPTY_STRING;
            my $rooted    = $EMPTY_STRING;
            my $rest      = $EMPTY_STRING;

            #  get the tree name and whether it is unrooted etc
            if (my $x = $nwk =~ m/
                                \s*
                                tree\s+
                                (.+?)       #  capture the name of the tree into $1
                                \s*=\s*
                                (\[..\])?  #  get the rooted unrooted bit
                                \s*
                                (.*)     #  get the rest
                            /xgcsi
            ) {

                $tree_name = $1;
                $rooted    = $2;
                $rest      = $3;
            }

            $tree_name =~ s/\s+$//;  #  trim trailing whitespace

            print "[ReadNexus] Processing tree $tree_name\n";
            $progress->update ("Tree $i of $target_count\n$tree_name", $i / $target_count);

            my $tree = Biodiverse::Tree->new (NAME => $tree_name);
            #$tree->set_param ()

            my $count = 0;
            my $node_count = \$count;

            $self->parse_newick (
                string          => $rest,
                tree            => $tree,
                node_count      => $node_count,
                translate_hash  => \%translate,
            );

            $self->add_tree (tree => $tree);
    }
    
    #print "";
    
    return 1;
}

#  rough and ready - assumes a set structure
sub import_tabular_tree {
    my $self = shift;
    my %args = @_;

    #  inefficient - should just open a file handle on $args{data} or $args{file}
    $args{data} //= $self->read_whole_file (file => $args{file});
    my $data = $args{data};
    
    croak "No data provided or read from a file"
      if !length ($data);

    # get column map from arguments 
    my $column_map = $args{column_map} // {};
    my %col_nums = %$column_map;

    my $csv = $self->get_csv_object_for_tabular_tree_import (%args);

    #  use scalar as a file handle
    open my $io, '<', \$data
      or croak "Could not open scalar variable \$data as a file handle\n";

    my $header = $csv->getline ($io);
    $csv->column_names (@$header);

    my $node_hash = {};

    my @trees;

    # set up columns to grab relevant data.  if any were not passed as args,
    # look for values with given names in header. (just add to args map)
    my %header_col_nums; 
    @header_col_nums{@$header} = (0..$#$header);

    # check if all required fields are defined (?)
    foreach my $p (sort keys %header_col_nums) { #/
        my $param = $p . '_COL';
        $col_nums{$param} //= $header_col_nums{$p};
        say "Param $param col $col_nums{$param}";
    }
    my $max_target_col = max (values %col_nums);

    #  read first line to get an initial default tree name
    my @data = ($csv->getline($io));
    my @line_arr = @{$data[0]};

    # note use of $args{NAME} will only work if name col is not provided
    # ?? really?
    my $tree_name = $args{NAME}
                 // $line_arr[$col_nums{TREENAME_COL}]
                 // 'TABULAR_TREE'; 
    my $tree = Biodiverse::Tree->new (NAME => $tree_name);
    push @trees, $tree;

    #  process the data and generate the nodes
  LINE:
    while (my $line_array = shift @data) {
        push @data, $csv->getline ($io);

        #  skip line if we don't have sufficient values - safe in all cases?
        next LINE if $max_target_col > $#$line_array;
        
        my %line_hash;
        @line_hash{keys %col_nums} = @$line_array[values %col_nums];

        my $treename_col = $line_hash{TREENAME_COL};

        # have we have started a new tree?
        if (defined($treename_col) && $treename_col ne $tree_name) {  
            #  clean up the previous tree
            $self->assign_parents_for_tabular_tree_import (
                tree_ref  => $tree,
                node_hash => $node_hash,
            );

            #  and start afresh
            $tree_name = $treename_col;
            $tree = Biodiverse::Tree->new (NAME => $tree_name);
            push @trees, $tree;
            $node_hash = {};
        }

        my $node_name
          = $line_hash{NAME_COL}
          //= $tree->get_free_internal_name;

        $tree->add_node (
            name   => $node_name,
            length => $line_hash{LENGTHTOPARENT_COL},
        );

        my $node_number = $line_hash{NODE_NUMBER_COL};
        next if !defined $node_number;

        $node_hash->{$node_number} = \%line_hash; 
    }

    $self->assign_parents_for_tabular_tree_import (
        tree_ref  => $tree,
        node_hash => $node_hash,
    );

    foreach my $tree_ref (@trees) {
        $self->add_tree (tree => $tree_ref);
    }

    return 1;
}

#  Now pass over the data again and assign parents.
#  Needs to be post-import as we won't have all the parents
#  loaded on the first pass.
sub assign_parents_for_tabular_tree_import {
    my $self = shift;
    my %args = @_;
    
    my $tree      = $args{tree_ref};
    my $node_hash = $args{node_hash};

    foreach my $node_number (sort keys %$node_hash) {
        my $node_name = $node_hash->{$node_number}{NAME_COL};
        my $node_ref  = $tree->get_node_ref_aa ($node_name);

        my $parent_number = $node_hash->{$node_number}{PARENTNODE_COL};
        my $parent_name   = $node_hash->{$parent_number}{NAME_COL};

        next if !defined $parent_name;

        my $parent_ref = $tree->get_node_ref_aa ($parent_name);
        $parent_ref->add_children(children => [$node_ref]);
    }
    
    return;
}

sub get_csv_object_for_tabular_tree_import {
    my $self = shift;
    my %args = @_;
    
    #  need to get the csv params
    my $input_quote_char = $args{input_quote_char};
    my $sep_char         = $args{input_sep_char};    

    my $csv_in = $self->get_csv_object_using_guesswork (
        sep_char   => $sep_char,
        quote_char => $input_quote_char,
        string     => \$args{data},
    );

    return $csv_in;
}


sub process_unrooted_trees {
    my $self = shift;
    my @trees = $self->get_tree_array;
    
  BY_LOADED_TREE:
    foreach my $tree (@trees) {
        $tree->root_unrooted_tree;
    }
    
    return;
}

sub process_zero_length_trees {
    my $self = shift;
    
    my @trees = $self->get_tree_array;
    
    #  now we check if the tree has all zero-length nodes.  Change these to length 1.
  BY_LOADED_TREE:
    foreach my $tree (@trees) {
        my $nodes = $tree->get_node_hash;
        my $len_sum = 0;

      LEN_SUM:
        foreach my $node (values %$nodes) {
            #  skip this tree if we have a non-zero length
            next BY_LOADED_TREE if $node->get_length;
        }

        say '[READNEXUS] All nodes are of length zero, converting all to length 1';
        foreach my $node (values %$nodes) {
            $node->set_length (length => 1);
        }
    }

    return;
}

sub read_whole_file {
    my $self = shift;
    my %args = @_;
    
    my $file = $args{file};

    croak "file arg not specified\n"
        if not defined $file;

    #  now we open the file and suck it all in
    my $fh = $self->get_file_handle (
        file_name => $file,
        use_bom   => 1,
    );
    
    my $text;
    {
        local $/ = undef;
        $text = eval {<$fh>};  #  suck the whole thing in
        croak $EVAL_ERROR if $EVAL_ERROR;
    }

    $fh->close or warn "[READNEXUS] Cannot close $file, $!\n";

    return $text;
}


#  parse the sub tree into its component nodes
sub parse_newick {
    my $self = shift;
    my %args = @_;

    my $string    = $args{string};
    my $str_len   = length ($string);
    my $tree      = $args{tree};
    my $tree_name = $tree->get_param ('NAME');

    my $node_count      = $args{node_count} // croak 'node_count arg not passed (must be scalar ref)';
    my $translate_hash  = $args{translate_hash}
                        || $self->get_param ('TRANSLATE_HASH');
    #  clunky that we need to do this - was convenient once, but not now
    my $use_element_properties = $self->get_param ('USE_ELEMENT_PROPERTIES');
    my $element_properties     = $use_element_properties
      ? ($args{element_properties} || $self->get_param ('ELEMENT_PROPERTIES'))
      : undef;
    

    my $quote_char = $self->get_param ('QUOTES') || q{'};
    my $csv_obj    = $args{csv_object} // $self->get_csv_object (quote_char => $quote_char, sep_char => ':');

    my ($length, $default_length) = (0, 0);
    my ($name, $boot_value, $est_node_count, @nodes_added);
    my $children_of_current_node = [];

    my $progress_bar = $args{progress_bar};
    if (!$progress_bar) {
        $est_node_count = $string =~ tr/,(//;  #  tr shortcuts to count items matching /,(/
        $est_node_count ||= 1;
        #say "Estimated node count is $est_node_count";
        $tree->set_cached_value (ESTIMATED_NODE_COUNT => $est_node_count);
        $tree->set_node_hash_key_count ($est_node_count);
        $progress_bar = Biodiverse::Progress->new ();
    }
    else {
        $est_node_count = $tree->get_cached_value ('ESTIMATED_NODE_COUNT');
    }

    my $nc = $tree->get_node_count;
    $progress_bar->update (
        "node $nc of an estimated $est_node_count",
        $nc / $est_node_count,
    );

    pos ($string) = 0;

    while (not $string =~ m/ \G \z /xgcs) {  #  haven't hit the end of line yet
        #print "\nParsing $string\n";
        #print "Nodecount is $$node_count\n";
        #print "Position is " . (pos $string) . " of $str_len\n";

        #  march through any whitespace and newlines
        if ($string =~ m/ \G [\s\n\r]+ /xgcs) {  
            #print "found some whitespace\n";
            #print "Position is " . (pos $string) . " of $str_len\n";
        }

        #  we have a comma or are at the end of the string, so we create this node and start a new one
        elsif ($string =~ m/ \G (?:,)/xgcs) {  

            $name //= $tree->get_free_internal_name (exclude => $translate_hash);

            if (exists $translate_hash->{$name}) {
                $name = $translate_hash->{$name} ;
            }
            if ($name =~ $RE_TEXT_IN_QUOTES) {
                my $tmp = $self->csv2list (csv_object => $csv_obj, string => $name);
                if (scalar @$tmp == 1) {
                    $name = $tmp->[0];
                }
                else {
                    $name   = $self->list2csv (csv_object => $csv_obj, list => $tmp);
                }
                $name = $self->dequote_element (element => $name, quote_char => $quote_char);
            }

            if ($use_element_properties) {
                my $element = $element_properties->get_element_remapped (element => $name);

                if (defined $element) {
                    my $original_name = $name;
                    $name = $element;
                    say "$tree_name: Remapped $original_name to $element";
                }
            }

            #print "Adding new node to tree, name is $name, length is $length\n";
            my $node = $self->add_node_to_tree (
                tree   => $tree,
                name   => $name,
                length => $length,
                boot   => $boot_value,
                translate_hash => $translate_hash,
            );
            push @nodes_added, $node;
            #  add any relevant children
            if (scalar @$children_of_current_node) {
                $node->add_children (children => $children_of_current_node);
            }
            #  reset name, length and children
            $$node_count ++;
            $name        = undef;
            $length      = undef;
            $boot_value  = undef;
            $children_of_current_node = [];
        }

        #  use positive look-ahead to find if we start with an opening bracket
        elsif ($string =~ m/ \G (?= \( ) /xgcs) {  
            #print "found an open bracket\n";
            #print "Position is " . (pos $string) . " of $str_len\n";
            
            if ($string =~ m/\G \( ( $re_text_in_brackets) \) /xgcs) {
                my $sub_newick = $1;
                #print "Eating to closing bracket\n";
                #print "Position is " . (pos $string) . " of $str_len\n";
                
                $children_of_current_node = $self->parse_newick (
                    string         => $sub_newick,
                    tree           => $tree,
                    node_count     => $node_count,
                    translate_hash => $translate_hash,
                    csv_object     => $csv_obj,
                    progress_bar   => $progress_bar,
                );
            }
            else {
                pos $string = 0;
                my @left_side  = ($string =~ / \( /gx);
                my @right_side = ($string =~ / \) /gx);
                my $left_count  = scalar @left_side;
                my $right_count = scalar @right_side;
                croak "Tree has unbalanced parentheses "
                      . "(left is $left_count, "
                      . "right is $right_count), "
                      . "unable to parse\n";
            }
        }

        #  do we have a square bracket for bootstrap and other values?
        elsif ($string =~ m/ \G (?= \[ ) /xgcs) {  
            #print "found an open square bracket\n";
            #print "Position is " . (pos $string) . " of $str_len\n";
            
            $string =~ m/\G \[ ( .*? ) \] /xgcs;
            #print "Eating to closing square bracket\n";
            #print "Position is " . (pos $string) . " of $str_len\n";
            
            $boot_value = $1;
        }

        #  we have found a quote char, match to the next quote
        elsif ($string =~ m/ \G (?=') /xgcs) { 
            #print "found a quote char\n";
            #print "Position is " . (pos $string) . " of $str_len\n";

            $string =~ m/\G ($RE_QUOTED) /xgcs;  #  eat up to the next non-escaped quote
            $name = $1;
        }

        #  next value is a length if we have a colon
        elsif ($string =~ m/ \G :/xgcs) {  
            #print "found a length value\n";
            #print "Position is " . (pos $string) . " of $str_len\n";

            #  get the number
            $string =~ m/\G ( $RE_NUMBER ) /xgcs;
            #print "length value is $1\n";
            $length = $1;
            if (! looks_like_number $length) {
                $length //= q{};
                croak "Length '$length' does not look like a number\n";
            }
            $length += 0;  #  make it numeric
            #my $x = $length;
        }

        #  next value is a name, but it can be empty
        #  anything except special chars is fair game
        elsif ($string =~ m/ \G ( [^(),:'\[\]]* )  /xgcs) {  
            #print "found a name value $1\n";
            #print "\tbut it is anonymous\n" if length ($1) == 0;
            #print "Position is " . (pos $string) . " of $str_len\n";

            $name = $1;
        }

        #  unexpected character found, or other failure - croak
        else { 
            #print "found nothing valid\n";
            #print "Position is " . (pos $string) . " of $str_len\n";
            #print "$string\n";
            $string =~ m/ \G ( . )  /xgcs;
            my $char = $1;
            my $posn = pos ($string);
            croak "[ReadNexus] Unexpected character '$char' found at position $posn\n";
        }  
    }
    
    
    #print "hit the end of line\n";
    #print "Position is " . (pos $string) . " of $str_len\n";

    #  try to avoid leaktrace warnings
    #undef $children_of_current_node;

    #  the following is a duplicate of code from above, but converting to a sub uses
    #  almost as many lines as the two blocks combined
    #  (later --- not sure this is still the case now)

    #print "Tree is $tree";
    $name //= $tree->get_free_internal_name (exclude => $translate_hash);

    if (exists $translate_hash->{$name}) {
        $name = $translate_hash->{$name};
    }
    #  strip any quotes - let the csv object decide
    if ($name =~ $RE_TEXT_IN_QUOTES) {
        my $tmp = $self->csv2list (csv_object => $csv_obj, string => $name);
        if (scalar @$tmp == 1) {
            $name = $tmp->[0];
        }
        else {
            $name = $self->list2csv (csv_object => $csv_obj, list => $tmp);
        }
        $name = $self->dequote_element (element => $name, quote_char => $quote_char);
    }

    if ($use_element_properties) {
        my $element = $element_properties->get_element_remapped (element => $name);
        if (defined $element) {
            my $original_name = $name;
            $name = $element;
            say "$tree_name: Remapped $original_name to $element";
        }
    }

    my $node = $self->add_node_to_tree (
        tree   => $tree,
        name   => $name,
        length => $length,
        boot   => $boot_value,
        translate_hash => $translate_hash,
    );
    
    push @nodes_added, $node;

    #  add any relevant children
    if (scalar @$children_of_current_node) {
        $node->add_children (children => $children_of_current_node);
    }

    return wantarray ? @nodes_added : \@nodes_added;
}

#  add a node to the tree, avoiding duplicates as we go
sub add_node_to_tree {
    my $self = shift;
    my %args = @_;

    my $tree   = $args{tree};
    my $name   = $args{name};
    my $length = $args{length};
    my $boot   = $args{boot};
    my $translate_hash = $args{translate_hash};


    if (defined $name && $tree->exists_node (name => $name)) {
        $name = $tree->get_unique_name(
            prefix  => $name,
            exclude => $translate_hash,
        );
    }

  ADD_NODE_TO_TREE:
    my $node = eval {
        $tree->add_node (
            name   => $name,
            length => $length,
            boot   => $boot,
        )
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    return $node;
}


#  SWL: method to get the tree array.  Needed for GUI.
sub get_tree_array {
  my $self = shift;
  return wantarray ? @{$self->{TREE_ARRAY}} : $self->{TREE_ARRAY};
}

sub numerically {$a <=> $b};


1;


__END__

=head1 NAME

Biodiverse::????

=head1 SYNOPSIS

  use Biodiverse::????;
  $object = Biodiverse::Statistics->new();

=head1 DESCRIPTION

TO BE FILLED IN

=head1 METHODS

=over

=item INSERT METHODS

=back

=head1 REPORTING ERRORS

Use the issue tracker at http://www.purl.org/biodiverse

=head1 COPYRIGHT

Copyright (c) 2010 Shawn Laffan. All rights reserved.  

=head1 LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

For a full copy of the license see <http://www.gnu.org/licenses/>.

=cut
