package Biodiverse::Indices;

#  package to run the calculations for a Biodiverse analysis 
#  generally they are called from a Biodiverse::Spatial or Biodiverse::Cluster object
use 5.010;

use Carp;
use strict;
use warnings;
#use Devel::Symdump;
use Data::Dumper;
use Scalar::Util qw /blessed weaken reftype/;
use List::MoreUtils qw /uniq/;
use English ( -no_match_vars );
#use MRO::Compat;
use Class::Inspector;

use Biodiverse::Exception;

our $VERSION = '1.99_002';

my $EMPTY_STRING = q{};

#  The Biodiverse::Indices::* modules are the indices themselves 
use parent qw {
    Biodiverse::Indices::Indices
    Biodiverse::Indices::Numeric_Labels
    Biodiverse::Indices::IEI
    Biodiverse::Indices::Hierarchical_Labels
    Biodiverse::Indices::Phylogenetic
    Biodiverse::Indices::PhylogeneticRelative
    Biodiverse::Indices::PhyloCom
    Biodiverse::Indices::Matrix_Indices
    Biodiverse::Indices::Endemism
    Biodiverse::Indices::Rarity
    Biodiverse::Indices::LabelProperties
    Biodiverse::Indices::LabelPropertiesRangeWtd
    Biodiverse::Indices::GroupProperties
    Biodiverse::Indices::LabelCounts
    Biodiverse::Indices::RWTurnover
    Biodiverse::Indices::RichnessEstimation
    Biodiverse::Common
};

my $metadata_class = 'Biodiverse::Metadata::Indices';
use Biodiverse::Metadata::Indices;


sub new {
    my $class = shift;
    my %args = @_;

    my $self = bless {}, $class;

    my %PARAMS = (  #  default params
        TYPE            => 'INDICES',
        OUTSUFFIX       => 'bis',
        OUTSUFFIX_YAML  => 'biy',
    );
    $self->set_params (%PARAMS, %args);
    $self->set_default_params;  #  load any user overrides

    $self->reset_results(global => 1);

    #  avoid memory leak probs with circular refs to parents
    #  ensures children are destroyed when parent is destroyed
    $self->weaken_basedata_ref;  

    return $self;
}

sub metadata_class {
    return $metadata_class;
}

sub reset_results {
    my $self = shift;
    my %args = @_;
    
    if ($args{global}) {
        $self->set_param (AS_RESULTS_FROM_GLOBAL => {});
    }

    return;
}


###########################
#
#   Methods to get valid calculations depending on conditions

#  get a list of the all the publicly available calculations.
sub get_calculations {
    my $self = shift;

    my %calculations;

    my $list = Class::Inspector->methods (blessed $self);

    foreach my $method (grep {$_ =~ /^calc_/} @$list) {
        next if $method =~ /calc_abc\d?$/;  #  skip calc_abc1,2&3
        my $metadata = $self->get_metadata (sub => $method);
        push @{$calculations{$metadata->get_type}}, $method;
    }

    return wantarray ? %calculations : \%calculations;
}

sub get_calculations_as_flat_hash {
    my $self = shift;
    my $list = $self->get_calculations;
    return $self->get_list_as_flat_hash (list => $list);
}

#  needed for GUI help and so forth
sub get_calculation_metadata_as_wiki {
    my $self = shift;

    my %calculations = $self->get_calculations (@_);

    #  the html version
    my @header = (  
        #"Name",
        #"Analysis description",
        #"Subroutine",
        'Index #',
        'Index',
        'Index description',
        'Valid cluster metric?',
        'Minimum number of neighbour sets',
        'Formula',
        'Reference',
    );

    foreach my $text (@header) {
        $text =~ s/\*/`\*`/;  #  escape any highlight characters
        $text =~ s/\b([A-Z][a-z]+[A-Z][a-z]+)\b/!$1/;  #  escape any wiki page confusion, e.g. PhyloCom
        $text = "*$text*";
    }

    my %hash;

    #my @place_holder = (undef, undef);

    my %indices;
    my %calculation_hash;
    foreach my $type (sort keys %calculations) {
        foreach my $calculations (@{$calculations{$type}}) {
            my $ref = $self->get_metadata (sub => $calculations);
            $ref->{analysis} = $calculations;
            $calculation_hash{$type}{$calculations} = $ref;
        }
    }

    #my $sort_by_type_then_name = sub {   $a->{type} cmp $b->{type}
    #                                  || $a->{name} cmp $b->{name}
    #                                  };

    my $html;

    my %done;
    my $count = 1;
    my $SPACE = q{ };

    my $gadget_start_text
        #= q{<wiki:gadget url="http://mathml-gadget.googlecode.com/svn/trunk/mathml-gadget.xml" border="0" up_content="};
        = '<img src="http://latex.codecogs.com/png.latex?';
    my $gadget_end_text
        #= q{"/>};
        = ' />';

    #loop through the types
  BY_TYPE:
    foreach my $type (sort keys %calculation_hash) {
        my $type_text = $type;
        $type_text =~ s/\*/`\*`/;  #  escape any highlight characters
        $type_text =~ s/\b([A-Z][a-z]+[A-Z][a-z]+)\b/!$1/;  #  escape any wiki page confusion, e.g. PhyloCom
        $html .= "==$type_text==";

        my $type_ref = $calculation_hash{$type};

      BY_NAME:  #  loop through the names
        foreach my $ref (sort {$a->get_name cmp $b->get_name} values %$type_ref) {

            my $name = $ref->{name};
            my $description = $ref->get_description;
            foreach ($name, $description) {
                $_ =~ s/\*/`\*`/;  #  escape any highlight characters
                $_ =~ s/\b([A-Z][a-z]+[A-Z][a-z]+)\b/!$1/;  #  escape any wiki page confusion, e.g. PhyloCom
            }

            $html .= "\n \n \n";
            $html .= "\n \n  ===$name===\n \n";
            $html .= "*Description:*   $description\n\n";
            $html .= "*Subroutine:*   $ref->{analysis}\n\n";
            #$html .= "<p><b>Module:</b>   $ref->{source_module}</p>\n";  #  not supported yet
            if (my $reference = $ref->get_reference) {
                $html .= "*Reference:*   $reference\n \n\n";
            }

            my $formula = $ref->get_formula;
            croak 'Formula is not an array'
              if defined $formula and not (ref $formula) =~ /ARRAY/;

            if ($formula and (ref $formula) =~ /ARRAY/) {
                my $formula_url;
                my $iter = 0;

              FORMULA_ELEMENT_OVERVIEW:
                foreach my $element (@{$formula}) {
                    if (! defined $element
                        || $element eq q{}) {
                        $iter ++;
                        next FORMULA_ELEMENT_OVERVIEW;
                       }

                    if ($iter % 2) {
                        #$formula .= "\n";
                        if ($element =~ /^\s/) {
                            $formula_url .= $element;
                        }
                        else {
                            $formula_url .= " $element";
                        }
                    }
                    else {
                        #$formula .= "\n";
                        $formula_url .= $gadget_start_text;
                        $formula_url .= $element;
                        $formula_url .= qq{%.png" title="$element"};
                        $formula_url .= $gadget_end_text;
                    }
                    $iter++;
                }

                $html .= "*Formula:*\n   $formula_url\n\n";
            }

            my @table;
            push @table, [@header];

            my $i = 0;
            my $uses_reference = 0;
            my $uses_formula = 0;
            foreach my $index (sort keys %{$ref->get_indices}) {

                #  repeated code from above - need to generalise to a sub
                my $formula_url;
                my $formula = $ref->get_index_formula ($index);
                croak "Formula for $index is not an array"
                  if defined $formula and not ((ref $formula) =~ /ARRAY/);

                if (1 and $formula and (ref $formula) =~ /ARRAY/) {

                    $uses_formula = 1;

                    my $iter = 0;
                    foreach my $element (@$formula) {
                        if ($iter % 2) {
                            if ($element =~ /^\s/) {
                                $formula_url .= $element;
                            }
                            else {
                                $formula_url .= " $element";
                            }
                        }
                        else {
                            $formula_url .= $gadget_start_text;
                            $formula_url .= $element;
                            $formula_url .= qq{%.png" title="$element"};
                            $formula_url .= $gadget_end_text;
                        }
                        $iter++;
                    }
                }
                $formula_url .= $SPACE;

                my @line;

                push @line, $count;
                push @line, $index;

                my $description = $ref->get_index_description ($index) || $SPACE;
                $description =~ s{\n}{ }gmo;  # purge any newlines
                $description =~ s/\*/`\*`/;  #  avoid needless bolding
                push @line, $description;

                push @line, $ref->get_index_is_cluster_metric ($index) ? "cluster metric" : $SPACE;
                push @line, $ref->get_index_uses_nbr_lists ($index) || $ref->get_uses_nbr_lists || $SPACE;
                push @line, $formula_url;
                my $reference = $ref->get_index_reference ($index);
                if (defined $reference) {
                    $uses_reference = 1;
                    $reference =~s{\n}{ }gmo;
                }
                push @line, $reference || $SPACE;

                push @table, \@line;

                $i++;
                $count ++;
            }

            #  remove the reference col if none given
            if (! $uses_reference) {
                foreach my $row (@table) {
                    pop @$row;
                }
            }

            #  and remove the formula also if need be
            if (! $uses_formula) {
                foreach my $row (@table) {
                    splice @$row, 5, 1;
                }
            }

            #$html .= $table;

            foreach my $line (@table) {
                my $line_text;
                $line_text .= q{|| };
                $line_text .= join (q{ || }, @$line);
                $line_text .= q{ ||};
                $line_text .= "\n";

                my $x = grep {! defined $_} @$line;

                $html .= $line_text;
            }

            $html .= "\n\n";
        }
    }

    return $html;
}

#  now we have moved to github
sub get_calculation_metadata_as_markdown {
    my $self = shift;

    my %calculations = $self->get_calculations (@_);

    #  the html version
    my @header = (
        'Index #',
        'Index',
        'Index description',
        'Grouping metric?',
        'Minimum number of neighbour sets',
        'Formula',
        'Reference',
    );

    foreach my $text (@header) {
        #$text =~ s/\*/`\*`/;  #  escape any highlight characters
        #$text =~ s/\b([A-Z][a-z]+[A-Z][a-z]+)\b/!$1/;  #  escape any wiki page confusion, e.g. PhyloCom
        $text = "*$text*";
    }

    my %hash;

    #my @place_holder = (undef, undef);

    my @toc;

    my %indices;
    my %calculation_hash;
    foreach my $type (sort keys %calculations) {
        my $wiki_anchor = lc $type;
        $wiki_anchor    =~ s/ /-/g;
        $wiki_anchor    =~ s/[^a-z0-9-]//g;
        push @toc, "  * [$type](#$wiki_anchor)";
        foreach my $calculations (@{$calculations{$type}}) {
            my $ref = $self->get_metadata (sub => $calculations);
            $ref->{analysis} = $calculations;
            $calculation_hash{$type}{$calculations} = $ref;
            my $wiki_anchor = lc $ref->{name};
            $wiki_anchor    =~ s/ /-/g;
            $wiki_anchor    =~ s/[^a-z0-9-]//g;
            push @toc, "    * [$ref->{name}](#$wiki_anchor)";
        }
    }

    #my $sort_by_type_then_name = sub {   $a->{type} cmp $b->{type}
    #                                  || $a->{name} cmp $b->{name}
    #                                  };

    my $markdown;

    $markdown .= "**Indices available in Biodiverse:**\n";
    $markdown .= join "\n", @toc;
    $markdown .= "\n\n";

    my %done;
    my $count = 1;
    my $SPACE = q{ };

    my $codecogs_url = 'http://latex.codecogs.com/png.latex?';
    #my $codecogs_prefix
    #    #= q{<wiki:gadget url="http://mathml-gadget.googlecode.com/svn/trunk/mathml-gadget.xml" border="0" up_content="};
    #    = '<img src="http://latex.codecogs.com/png.latex?';
    #my $codecogs_suffix
    #    #= q{"/>};
    #    = ' />';
    my %region_grower_indices = $self->get_valid_region_grower_indices;

    #loop through the types
  BY_TYPE:
    foreach my $type (sort keys %calculation_hash) {
        my $type_text = $type;
        #$type_text =~ s/\*/`\*`/;  #  escape any highlight characters
        #$type_text =~ s/\b([A-Z][a-z]+[A-Z][a-z]+)\b/!$1/;  #  escape any wiki page confusion, e.g. PhyloCom
        $markdown .= "## $type_text ##";

        my $type_ref = $calculation_hash{$type};

      BY_NAME:  #  loop through the names
        foreach my $ref (sort {$a->get_name cmp $b->get_name} values %$type_ref) {

            my $name = $ref->{name};
            my $description = $ref->get_description;
            foreach ($name, $description) {
                #$_ =~ s/\*/`\*`/;  #  escape any highlight characters
                #$_ =~ s/\b([A-Z][a-z]+[A-Z][a-z]+)\b/!$1/;  #  escape any wiki page confusion, e.g. PhyloCom
            }

            $markdown .= "\n \n \n";
            $markdown .= "\n \n### $name ###\n \n";
            $markdown .= "**Description:**   $description\n\n";
            $markdown .= "**Subroutine:**   $ref->{analysis}\n\n";
            #$markdown .= "<p><b>Module:</b>   $ref->{source_module}</p>\n";  #  not supported yet
            if (my $reference = $ref->get_reference) {
                $markdown .= "**Reference:**   $reference\n \n\n";
            }

            my $formula = $ref->get_formula;
            croak 'Formula is not an array'
              if defined $formula and not (ref $formula) =~ /ARRAY/;

            if ($formula and (ref $formula) =~ /ARRAY/) {
                my $formula_url;
                my $iter = 0;

              FORMULA_ELEMENT_OVERVIEW:
                foreach my $element (@{$formula}) {
                    if (! defined $element
                        || $element eq q{}) {
                        $iter ++;
                        next FORMULA_ELEMENT_OVERVIEW;
                       }

                    if ($iter % 2) {
                        #$formula .= "\n";
                        if (not $element =~ /^\s/) {
                            $formula_url .= ' ';
                        }
                        $formula_url .= $element;
                    }
                    else {
                        #$formula .= "\n";
                        my $eqn = $element;
                        $eqn =~ s/\\/\\\\/g;  #  need to escape the backslashes for github to work
                        $eqn =~ s/^= /=/;
                        $formula_url .= "![$eqn]($codecogs_url";
                        $formula_url .= $eqn;
                        #$formula_url .= "%.png) ";
                        $formula_url .= ")";
                    }
                    $iter++;
                }

                $markdown .= "**Formula:**\n   $formula_url\n\n";
            }

            my @table;
            push @table, [@header];

            my $i = 0;
            my $uses_reference = 0;
            my $uses_formula = 0;
            foreach my $index (sort keys %{$ref->get_indices}) {

                #  repeated code from above - need to generalise to a sub
                my $formula_url;
                my $formula = $ref->get_index_formula ($index);
                croak "Formula for $index is not an array"
                  if defined $formula and not ((ref $formula) =~ /ARRAY/);

                if (1 and $formula and (ref $formula) =~ /ARRAY/) {

                    $uses_formula = 1;

                    my $iter = 0;
                    foreach my $element (@$formula) {
                        if ($iter % 2) {
                            if (not $element =~ /^\s/) {
                                $formula .= ' ';
                            }
                            $formula_url .= $element;
                        }
                        else {
                            my $eqn = $element;
                            $eqn =~ s/\\/\\\\/g;  #  need to escape the backslashes for github to work
                            $eqn =~ s/^= /=/;
                            $formula_url .= "![$eqn]($codecogs_url";
                            $formula_url .= $eqn;
                            #$formula_url .= '%.png) ';
                            #$formula_url .= $codecogs_suffix;
                            $formula_url .= ')'
                        }
                        $iter++;
                    }
                }
                $formula_url .= $SPACE;

                my @line;

                push @line, $count;
                push @line, $index;

                my $description = $ref->get_index_description ($index) || $SPACE;
                $description =~ s{\n}{ }gmo;  # purge any newlines
                #$description =~ s/\*/`\*`/;  #  avoid needless bolding
                push @line, $description;

                my $clus_text = $ref->get_index_is_cluster_metric ($index) ? "cluster metric"
                              : exists ($region_grower_indices{$index})    ? 'region grower'
                              : $SPACE;
                push @line, $clus_text;
                push @line, $ref->get_index_uses_nbr_lists ($index) || $ref->get_uses_nbr_lists || $SPACE;
                push @line, $formula_url;
                my $reference = $ref->get_index_reference ($index);
                if (defined $reference) {
                    $uses_reference = 1;
                    $reference =~s{\n}{ }gmo;
                }
                push @line, $reference || $SPACE;

                push @table, \@line;

                $i++;
                $count ++;
            }

            #  remove the reference col if none given
            if (! $uses_reference) {
                foreach my $row (@table) {
                    pop @$row;
                }
            }

            #  and remove the formula also if need be
            if (! $uses_formula) {
                foreach my $row (@table) {
                    splice @$row, 5, 1;
                }
            }

            #$markdown .= $table;

            #  splice in the separator text
            my @separator = ('----') x scalar @{$table[0]};
            splice @table, 1, 0, \@separator;

            foreach my $line (@table) {    
                my $line_text;
                $line_text .= q{| };
                $line_text .= join (q{ | }, @$line);
                $line_text .= q{ |};
                $line_text .= "\n";

                #my $x = grep {! defined $_} @$line;

                $markdown .= $line_text;
            }

            $markdown .= "\n\n";
        }
    }

    return $markdown;
}


sub _convert_to_hash {
    my $self = shift;
    my %args = @_;
    
    my $input = $args{input};
    
    Biodiverse::MissingArgument->throw ('Input undefined in _convert_to_hash')
      if !defined $input;

    my %hash;

    if (defined $input) {
        my $reftype = reftype $input;
        if (!defined $reftype) {
            $hash{$input} = $input;
        }
        elsif ($reftype eq 'ARRAY') {
            @hash{@$input} = (1) x scalar @$input;
        }
        elsif ($reftype eq 'HASH') {
            %hash = %$input;
        }
    }

    return wantarray ? %hash : \%hash;
}

sub _convert_to_array {
    my $self = shift;
    my %args = @_;
    
    my $input = $args{input};
    
    return if !defined $input;

    my @array;

    if (defined $input) {
        my $reftype = reftype $input;
        if (!defined $reftype) {
            @array = ($input);
        }
        elsif ($reftype eq 'ARRAY') {
            @array = @$input;  #  makes a copy
        }
        elsif ($reftype eq 'HASH') {
            @array = keys %$input;
        }
        #  anything else is not returned
    }

    return wantarray ? @array : \@array;
}


sub parse_dependencies_for_calc {
    my $self = shift;
    my %args = @_;

    my $calcs = [$args{calculation}];  # array is a leftover - need to correct it

    my $nbr_list_count = $args{nbr_list_count} || $self->get_param ('NBR_LIST_COUNT') || 1;
    my $calc_args      = $args{calc_args} || \%args;

    #  Types of calculation.
    #  Order is important.
    #  pre_calc can depend on any other type,
    #  post_calc and post_calc_global can only depend on themselves and pre_calc_global,
    #  post_calc_global can only depend on itself and pre_calc_global
    my @types     = qw /pre_calc post_calc post_calc_global pre_calc_global/;
    my @type_list = @types;

    my %calcs_by_type;
    foreach my $type (@types) {
        $calcs_by_type{$type} = [];
    }
    #  Start with the ones we want results for.
    $calcs_by_type{pre_calc} = $calcs;

    #  hash of dependencies per calculation, and the reverse
    my %deps_by_type;
    my %reverse_deps;
    my %metadata_hash;
    my %indices_to_clear;

    #  Iterate over each type, adding to the lists for
    #  itself and each subsequent type
    #  (hence the unusual while condition and the shifting at the end)
    while (defined (my $type = $type_list[0])) {
        my $list = $calcs_by_type{$type};
        foreach my $calc (@$list) {
            my $metadata;
            if ($metadata_hash{$calc}) {
                $metadata = $metadata_hash{$calc};
            }
            else {
                $metadata = eval {$self->get_metadata (sub => $calc)};
                croak $EVAL_ERROR if $EVAL_ERROR;
                $metadata_hash{$calc} = $metadata;
            }

            #  run some validity checks
            my $uses_nbr_lists = $metadata->get_uses_nbr_lists;
            if (defined $uses_nbr_lists && $uses_nbr_lists > $nbr_list_count) {
                Biodiverse::Indices::InsufficientElementLists->throw (
                    error => "[INDICES] WARNING: Insufficient neighbour lists for $calc. "
                            . "Need $uses_nbr_lists but only $nbr_list_count available.\n",
                );
            }
            #  check the indices have sufficient nbr sets
            foreach my $index (keys %{$metadata->get_indices}) {
                my $index_uses_nbr_lists = $metadata->get_index_uses_nbr_lists($index);
                if ($index_uses_nbr_lists > $nbr_list_count) {
                    $indices_to_clear{$index} ++;
                }
            }

            if (my $required_args = $metadata->get_required_args) {
                my $reqd_args_a = $self->_convert_to_array (input => $required_args);

                foreach my $required_arg (sort @$reqd_args_a) {
                    my $re = qr /^($required_arg)$/;  #  match is used in the grep?  Was used in now-removed code.
                    my $is_defined;
                  CALC_ARG:
                    foreach my $calc_arg (sort grep {$_ =~ $re} keys %$calc_args) {
                        if (defined $calc_args->{$calc_arg}) {
                            $is_defined ++;
                            last CALC_ARG;
                        }
                    }

                    if (! $is_defined) {
                        Biodiverse::Indices::MissingRequiredArguments->throw (
                            error => "[INDICES] WARNING: $calc missing required "
                                    . "parameter $required_arg, "
                                    . "dropping it and any calc that depends on it\n",
                        );
                    }
                }
            }
            if (my $pre_cond = $metadata->get_pre_conditions) {
                my $pre_cond_a = $self->_convert_to_array (input => $pre_cond);

                foreach my $pre_cond (sort @$pre_cond_a) {
                    my $check = $self->$pre_cond (%$calc_args);
                    if (! $check) {
                        Biodiverse::Indices::FailedPreCondition->throw (
                            error => "[INDICES] WARNING: $calc failed precondition. "
                                    . "Dropping it and any calc that depends on it\n",
                        );
                    }
                }
            }

            foreach my $secondary_type (@types) {
                #  $pc is the secondary pre or post calc (global or not)
                #my $method = 'get_' . $secondary_type . '_list';
                my $pc = $metadata->get_dep_list ($secondary_type);
                next if ! defined $pc;
                $pc = $self->_convert_to_array (input => $pc);
                my $secondary_list = $calcs_by_type{$secondary_type};
                push @$secondary_list, @$pc;

                $deps_by_type{$secondary_type}{$calc} = $pc;
                foreach my $c (@$pc) {
                    $reverse_deps{$c}{$calc}++;
                }
            }
        }
        shift @type_list;
    }

    #  now we reverse the pre_calc and pre_calc_global lists
    #  and clear any dups 
    foreach my $type (@types) {
        my $list = $calcs_by_type{$type};
        my @u_list = uniq ($type =~ /^post/ ? @$list : reverse @$list);
        $calcs_by_type{$type} = \@u_list;
    }

    my %results = (
        calcs_by_type         => \%calcs_by_type,
        deps_by_type_per_calc => \%deps_by_type,
        reverse_deps          => \%reverse_deps,
        indices_to_clear      => \%indices_to_clear,
    );

    return wantarray ? %results : \%results;
}

my @valid_calc_exceptions = qw /
    Biodiverse::Indices::MissingRequiredArguments
    Biodiverse::Indices::InsufficientElementLists
    Biodiverse::Indices::FailedPreCondition
/;

sub get_valid_calculations {
    my $self = shift;
    my %args = @_;

    my $calcs = $self->_convert_to_hash (input => $args{calculations});
    $calcs    = [sort keys %$calcs];  #  Alpha sort for consistent order of eval.

    my %valid_calcs;
    my @removed;

  CALC:
    foreach my $calc (@$calcs) {
        #print "$calc\n";
        my $deps = eval {
            $self->parse_dependencies_for_calc (
                calculation => $calc,
                %args,
            );
        };
        my $e = $EVAL_ERROR;
        if ($e) {
            for my $exception (@valid_calc_exceptions) {
                if ($exception->caught) {
                    print $e;
                    push @removed, $calc;
                    next CALC;
                }
            }
            croak $EVAL_ERROR;
        }

        $valid_calcs{$calc} = $deps;
    }
    
    if (scalar @removed) {
        say "[INDICES] The following calcs are not valid and have been removed:\n"
            . join q{ }, @removed;
    }

    my %aggregated_calc_lists = $self->aggregate_calc_lists_by_type (
        calc_hash => \%valid_calcs,
    );
    
    my %aggregated_deps_per_calc = $self->get_deps_per_calc_by_type (
        calc_hash => \%valid_calcs,
    );

    my %results = (
        calculations_to_run => \%valid_calcs,
        calc_lists_by_type  => \%aggregated_calc_lists,
        calc_deps_by_type   => \%aggregated_deps_per_calc,
    );

    $self->set_param(VALID_CALCULATIONS   => \%results);
    $self->set_param(INVALID_CALCULATIONS => \@removed);

    return wantarray ? %results : \%results;
}

#  run after valid calcs
sub get_invalid_calculations {
    my $self = shift;

    my $invalid = $self->get_param ('INVALID_CALCULATIONS');
    croak 'Need to run get_valid_calculations first'
      if !defined $invalid;

    return wantarray ? @$invalid : [@$invalid];
}

my @dep_types = qw /pre_calc pre_calc_global post_calc post_calc_global/;

#  get all dependency subs -  not working yet
sub get_full_dependency_list {
    my $self = shift;
    my %args = @_;
    
    my $calc_hash = $args{calc_hash} || $self->get_calculations_as_flat_hash;
    my @calc_list = sort keys %$calc_hash;  #  make it predictable to start with
    my %dep_list;

    no autovivification;

    my %done;
  CALC:
    while (my $calc = shift @calc_list) {
        next CALC if $done{$calc};

        my $meta = $self->get_metadata (sub => $calc);
        foreach my $type (@dep_types) {
            my $deps = $meta->get_dep_list ($type);
            next if !defined $deps;
            
            if (!reftype ($deps)) {
                $dep_list{$deps}++;
            }
            else {
                @dep_list{@$deps} = (1) x @$deps;
            }
        }
    }

    return wantarray ? keys %dep_list : [keys %dep_list];
}


sub get_deps_per_calc_by_type {
    my $self = shift;
    my %args = @_;
    
    my $calc_hash = $args{calc_hash};
    
    my @types = qw /pre_calc_global pre_calc post_calc post_calc_global/;
    my %aggregated;
    foreach my $type (@types) {
        $aggregated{$type} = {};
    }
    
    foreach my $calc (keys %$calc_hash) {
        my $sub_hash = $calc_hash->{$calc};
        my $calcs_by_type = $sub_hash->{deps_by_type_per_calc};
        while (my ($type, $hash) = each %$calcs_by_type) {
            while (my ($dep_calc, $array) = each %$hash) {
                $aggregated{$type}{$dep_calc} = $array;
            }
        }
    }

    return wantarray ? %aggregated : \%aggregated;    
}

sub aggregate_calc_lists_by_type {
    my $self = shift;
    my %args = @_;

    my $calc_hash = $args{calc_hash};
    
    my @types = qw /pre_calc_global pre_calc post_calc post_calc_global/;
    my %aggregated;
    foreach my $type (@types) {
        $aggregated{$type} = [];
    }
    
    while (my ($calc, $sub_hash) = each %$calc_hash) {
        my $calcs_by_type = $sub_hash->{calcs_by_type};
        while (my ($type, $array) = each %$calcs_by_type) {
            my $agg_array = $aggregated{$type};
            push @$agg_array, @$array;
        }
    }
    
    #  now uniquify
    foreach my $type (@types) {
        my $array = $aggregated{$type};
        my @u_array = uniq @$array;
        $aggregated{$type} = \@u_array;
    }

    return wantarray ? %aggregated : \%aggregated;
}

#  not used anywhere?  
sub get_indices_uses_lists_count {
    my $self = shift;
    my %args = @_;

    my $list = $args{calculations} || $self->get_calculations;
    my %list = $self->get_list_as_flat_hash (list => $list);

    my %indices;
    foreach my $calculations (keys %list) {
        my $ref = $self->get_metadata (sub => $calculations);
        foreach my $index (keys %{$ref->get_indices}) {
            $indices{$index} = $ref->get_index_uses_nbr_lists ($index);
        }
    }

    return wantarray ? %indices : \%indices;
}

#  get a list of indices in a set of calculations
sub get_indices {
    my $self = shift;

    return $self->get_index_source_hash (@_);    
}

sub get_index_source {  #  return the source sub for an index
    my $self = shift;
    my %args = @_;
    croak "index argument not specified\n" if ! defined $args{index};

    my $source = $self->get_index_source_hash;
    my @tmp = %{$source->{$args{index}}};
    return $tmp[0];  #  the hash key is the first value.  Messy, but it works.
}

#  get a hash of indices arising from these calculations (keys),
#   with the analysis as the value
sub get_index_source_hash { 
    my $self = shift;
    my %args = @_;
    my $list = $args{calculations} || $self->get_calculations_as_flat_hash;
    my %list2;
    my $using_nbr_list_count = $args{uses_nbr_lists} // 2;  #  need to use 2 for back compat

    CALC:
    foreach my $calculations (keys %$list) {
        my $meta = $self->get_metadata (sub => $calculations);

        next CALC if $using_nbr_list_count < $meta->get_uses_nbr_lists;

        INDEX:
        foreach my $index (keys %{$meta->get_indices}) {
            my $index_uses_nbr_lists = $meta->get_index_uses_nbr_lists ($index) // 1;
            next INDEX if $using_nbr_list_count < $index_uses_nbr_lists;

            $list2{$index}{$calculations}++;
        }
    }

    return wantarray ? %list2 : \%list2;
}

#  return a hash of the required args for a set of methods
sub get_required_args {
    my $self = shift;
    my %args = @_;
    my $list = $args{calculations} || $self->get_calculations_as_flat_hash;
    my %params;

    foreach my $calculations (keys %$list) {
        my $ref = $self->get_metadata (sub => $calculations);
        if (my $reqd_ags = $ref->get_required_args) {  #  make it a hash if it not already
            if ((ref $reqd_ags) =~ /ARRAY/) {
                my %hash;
                @hash{@$reqd_ags} = (1) x scalar @$reqd_ags;
                $reqd_ags = \%hash;
            }
            elsif (not ref $reqd_ags) {
                $reqd_ags = {$reqd_ags => 1};
            }
            $params{$calculations} = $reqd_ags;
        }
    }

    return wantarray ? %params : \%params;
}

#  Get the required args without all the other cruft leading to them
#  These methods need a cleanout.  
sub get_required_args_as_flat_array {
    my $self = shift;
    my %args = @_;

    my $reqd = $self->get_required_args (%args);
    
    my %results;
    foreach my $calc (keys %$reqd) {
        my $href = $reqd->{$calc};
        foreach my $arg_name (keys %$href) {
            $results{$arg_name}++
        }
    }

    my @a = sort keys %results;
    return wantarray ? @a : \@a;
}


#  return a hash of the required args for a set of methods, including their dependencies
sub get_required_args_including_dependencies {
    my $self = shift;
    my %args = @_;

    no autovivification;

    my $list = $self->get_param('VALID_CALCULATIONS');
    my $calcs_to_run = $list->{calculations_to_run};
    my @calculations = keys %$calcs_to_run;
    foreach my $calc (keys %$calcs_to_run) {
        my $reverse_deps = $calcs_to_run->{$calc}{reverse_deps};
        push @calculations, keys %$reverse_deps;
    }

    my %params;
    my %done;

    foreach my $calc (@calculations) {
        next if $done{$calc};
        my $ref = $self->get_metadata (sub => $calc);
        if (my $reqd_args = $ref->get_required_args) {  #  make it a hash if it not already
            if ((ref $reqd_args) =~ /ARRAY/) {
                my @r = @$reqd_args;
                if ($args{no_regexp}) {  #  dirty hack to skip regexps since these are currently only for locals
                    @r = grep {ref ($_) ne 'Regexp'} @$reqd_args;
                }
                my %hash;
                @hash{@r} = (1) x scalar @r;
                $reqd_args = \%hash;
            }
            elsif (not ref $reqd_args) {
                $reqd_args = {$reqd_args => 1};
            }
            if (scalar keys %$reqd_args) {
                $params{$calc} = $reqd_args;
            }
        }
        $done{$calc}++;
    }

    return wantarray ? %params : \%params;
}


sub is_region_grower_index {
    my $self = shift;
    my %args = @_;
    my $index = $args{index};
    croak "index argument missing\n"
      if !defined $index;
    
    my %valid = $self->get_valid_region_grower_indices;
    
    return exists $valid{$index};
}

sub is_cluster_index {
    my $self = shift;
    my %args = @_;
    my $index = $args{index};
    croak "index argument missing\n"
      if !defined $index;
    
    my %valid = $self->get_valid_cluster_indices;
    
    return exists $valid{$index};
}

sub get_valid_cluster_indices {
    my $self = shift;
    my %args = @_;
    my $list = $args{calculations} || $self->get_calculations_as_flat_hash;

    my %indices;
    foreach my $calculations (keys %$list) {
        my $meta = $self->get_metadata (sub => $calculations);
      INDEX:
        foreach my $index (keys %{$meta->get_indices}) {
            next INDEX if ! $meta->get_index_is_cluster_metric ($index);
            $indices{$index} = $meta->get_index_description ($index);
        }
    }

    return wantarray ? %indices : \%indices;
}

sub get_valid_region_grower_indices {
    my $self = shift;
    my %args = @_;
    my $list = $args{calculations} || $self->get_calculations_as_flat_hash;

    my %indices;
    foreach my $calc (keys %$list) {
        my $meta = $self->get_metadata (sub => $calc);
      INDEX:
        foreach my $index (keys %{$meta->get_indices}) {
            next INDEX if
                !$meta->get_index_is_lumper ($index)
              || $meta->get_index_is_cluster_metric ($index)
              || $meta->get_index_is_list ($index);

            $indices{$index} = $meta->get_index_description ($index);
        }
    }

    return wantarray ? %indices : \%indices;
}

sub get_list_indices {
    my $self = shift;
    my %args = @_;
    my $list = $args{calculations} || $self->get_calculations_as_flat_hash;

    my %indices;
    foreach my $calculations (keys %$list) {
        my $meta = $self->get_metadata (sub => $calculations);
      INDEX:
        foreach my $index (keys %{$meta->get_indices}) {
            next INDEX if !$meta->get_index_is_list ($index);
            $indices{$index} = $meta->get_index_description ($index);
        }
    }

    return wantarray ? %indices : \%indices;
}

sub get_valid_calculations_to_run {
    my $self = shift;
    
    my $valid_calcs = $self->get_param('VALID_CALCULATIONS');
    my $calcs = $valid_calcs->{calculations_to_run};

    return wantarray ? %$calcs : $calcs;
}

sub get_valid_calculation_count {
    my $self = shift;
    my $calcs = $self->get_valid_calculations_to_run;
    return scalar keys %$calcs;
}

sub run_dependencies {
    my $self = shift;
    my %args = @_;

    my $type = $args{type};

    my $validated_calcs = $self->get_param ('VALID_CALCULATIONS');
    my $calc_list       = $validated_calcs->{calc_lists_by_type}{$type};

    #  Drop out of we have nothing to do.      
    return wantarray ? () : {} if !scalar @$calc_list;

    my $dep_list        = $validated_calcs->{calc_deps_by_type}{$type};
    my $dep_list_global = $validated_calcs->{calc_deps_by_type}{pre_calc_global};

    my $tmp = $self->get_param('AS_RESULTS_FROM_GLOBAL') || {};
    my %as_results_from_global = %$tmp;  #  make a copy

    #  Now we run the calculations at this level.
    #  We also keep track of what has been run
    #  to avoid repetition through multiple dependencies.
    my %results;
    my %as_results_from;
    foreach my $calc (@$calc_list) {
        my $calc_results;
        #  if already cached then just grab it - should never happen now?
        if (exists $as_results_from{$calc}) {
            $calc_results = $as_results_from{$calc};
        }
        else {
            my %dep_results;
            if (exists $dep_list->{$calc}) {
                my $deps = $dep_list->{$calc} || [];
                foreach my $dep (@$deps) {
                    my $dep_res = exists $as_results_from{$dep}
                        ? $as_results_from{$dep}
                        : {};
                    @dep_results{keys %$dep_res} = values %$dep_res;
                }
            }
            if (exists $dep_list_global->{$calc}) {
                my $deps = $dep_list_global->{$calc} || [];
                foreach my $dep (@$deps) {
                    my $dep_res = exists $as_results_from_global{$dep}
                        ? $as_results_from_global{$dep}
                        : {};
                    @dep_results{keys %$dep_res} = values %$dep_res;
                }
            }

            $calc_results = eval {
                $self->$calc (  
                    %args,
                    %dep_results,
                );
            };
            croak $EVAL_ERROR if $EVAL_ERROR;
            $as_results_from{$calc} = $calc_results;
            if ($type eq 'pre_calc_global') {
                $as_results_from_global{$calc} = $calc_results;
            }
        }
        $results{$calc} = $calc_results;
    }

    if ($type eq 'pre_calc_global') {
        $self->set_param (AS_RESULTS_FROM_GLOBAL => \%as_results_from_global);
    }

    return wantarray ? %results : \%results;
}


sub run_calculations {
    my $self = shift;
    my %args = @_;

    $self->reset_results;  #  clear any previous local results - poss redundant now

    my $pre_calc_local_results = $self->run_precalc_locals (%args);

    my %calcs_to_run = $self->get_valid_calculations_to_run;

    my %results;  #  stores the results
    foreach my $calc (keys %calcs_to_run) {
        my $calc_results = $pre_calc_local_results->{$calc};

        #  remove those that are invalid
        my $indices_to_clear = $calcs_to_run{$calc}{indices_to_clear};
        if ($indices_to_clear) {
            delete @{$calc_results}{keys %$indices_to_clear};
        }

        @results{keys %$calc_results} = values %$calc_results;
    }

    $self->run_postcalc_locals (%args);

    return wantarray ? %results : \%results;
}

#  Allow access to the pre_calc_global results.
#  Local results are more problematic as they can be cleaned up by post_calc_locals.
#  Or are they?  However, the fact remains that, at the moment, they are not stored anywhere.  
sub get_results_from_pre_calc_global {
    my $self = shift;
    my %args = @_;
    
    no autovivification;
    
    my $results = $self->get_param ('AS_RESULTS_FROM_GLOBAL');
    my $calc_results = $results->{$args{calculation}};
    
    return wantarray ? %$calc_results : $calc_results;
}


sub run_precalc_globals {
    my $self = shift;
    my %args = @_;

    my $results = $self->run_dependencies (
        %args,
        type => 'pre_calc_global',
    );

    return wantarray ? %$results : $results;
}

sub run_precalc_locals {
    my $self = shift;
    my %args = @_;

    return $self->run_dependencies (
        %args,
        type => 'pre_calc',
    );
}

sub run_postcalc_locals {
    my $self = shift;
    my %args = @_;
    
    return $self->run_dependencies (
        %args,
        type => 'post_calc',
    );
}


sub run_postcalc_globals {
    my $self = shift;
    my %args = @_;

    return $self->run_dependencies (
        %args,
        type => 'post_calc_global',
    );
}

sub set_pairwise_mode {
    my ($self, $mode) = @_;
    
    $self->{pairwise_mode} = $mode;
    
    return $mode;
}

sub get_pairwise_mode {
    my $self = shift;

    return $self->{pairwise_mode};
}



1;

__END__

=head1 NAME

Biodiverse::Indices

=head1 SYNOPSIS

  use Biodiverse::Indices;
  my $indices = Biodiverse::Indices->new;

=head1 DESCRIPTION

Indices handler for the Biodiverse system.
See L<http://purl.org/biodiverse/wiki/Indices> for the list of available indices.

=head1 METHODS

=over

=item NEED TO INSERT METHODS

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
