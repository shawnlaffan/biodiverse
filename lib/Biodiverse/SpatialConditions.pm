package Biodiverse::SpatialConditions;

use warnings;
use strict;
use 5.016;

use feature 'unicode_strings';

use English qw ( -no_match_vars );

use Carp;
use POSIX qw /fmod floor ceil/;
use Math::Trig;
use Math::Trig ':pi';
use Math::Polygon;
#use Geo::ShapeFile;
#use Tree::R;
use Biodiverse::Progress;
use Scalar::Util qw /looks_like_number blessed/;
use List::MoreUtils qw /uniq/;
use List::Util qw /min max/;
use Ref::Util qw { :all };


use parent qw /
    Biodiverse::Common
    Biodiverse::SpatialConditions::SpCalc
/;

our $VERSION = '5.0';

my $metadata_class = 'Biodiverse::Metadata::SpatialConditions';
use Biodiverse::Metadata::SpatialConditions;

our $NULL_STRING = q{};

use Regexp::Common qw /comment number/;
my $RE_NUMBER  = qr /$RE{num}{real}/xms;
my $RE_INT     = qr /$RE{num}{int}/xms;
my $RE_COMMENT = $RE{comment}{Perl};

my $BOUNDED_COND_RE = qr {
    \$nbr                   #  leading variable sigil
    (?:
       _[xyz]
       |
       coord\[$RE_INT\]     #  _x,_y,_z or coord[..]
    )
    \s*
    (?:
       <|>|<=|>=|==         #  condition
     )
    \s*
    (?:
       $RE_NUMBER           #  the value
     )
}x;

#  straight from Friedl, page 330.  Could be overkill, but works
my $re_text_in_brackets;
$re_text_in_brackets =
    qr / (?> [^()]+ | \(  (??{ $re_text_in_brackets }) \) )* /xo;


sub new {
    my $class = shift;
    my $self = bless {}, $class;

    my %args = @_;
    if ( !defined $args{conditions} ) {
        carp "[SPATIALPARAMS] Warning, no conditions specified\n";
        $args{conditions} = $NULL_STRING;
    }
    
    $self->set_basedata_ref (BASEDATA_REF => $args{basedata_ref});

    my $conditions = $args{conditions};

    #  strip any leading or trailing whitespace
    $conditions =~ s/^\s+//xms;
    $conditions =~ s/\s+$//xms;

    $self->set_params(
        CONDITIONS    => $conditions,
        WARNING_COUNT => 0,
        NO_LOG        => $args{no_log},
        KEEP_LAST_DISTANCES => $args{keep_last_distances},
    );
    $self->set_promise_current_label($args{promise_current_label});
    $self->set_tree_ref($args{tree_ref});

    eval {$self->parse_distances};
    croak $EVAL_ERROR if $EVAL_ERROR;

    $self->get_result_type;

    return $self;
}

sub get_type {return 'spatial conditions'};

sub is_def_query {return}

sub metadata_class {
    return $metadata_class;
}

sub get_metadata {
    my $self = shift;
    return $self->SUPER::get_metadata (@_, no_use_cache => 1);
}

sub get_basedata_ref {
    my $self = shift;

    return $self->SUPER::get_basedata_ref // do {
        my $h = $self->get_param('CURRENT_ARGS');
        $h->{basedata} || $h->{caller_object};
    };
}

sub get_tree_ref {
    my ($self) = @_;
    $self->get_param('TREE_REF');
}

sub set_tree_ref {
    my ($self, $tree_ref) = @_;
    if (my $old_tree = $self->get_tree_ref) {
        $self->delete_cached_values
          if ref $tree_ref ne ref $old_tree;
    }
    $self->set_param(TREE_REF => $tree_ref);
}

sub get_conditions {
    my $self = shift;
    my %args = @_;

    #  don't want to see the $self etc that parsing inserts
    return $self->get_param('CONDITIONS')
        if $args{unparsed};

    return $self->get_param('PARSED_CONDITIONS')
        || $self->get_param('CONDITIONS');  #  THIS NEEDS TO CHANGE
}

sub get_conditions_unparsed {
    my $self = shift;

    return $self->get_conditions( @_, unparsed => 1 );
}

sub get_conditions_parsed {
    my $self = shift;

    my $conditions = $self->get_param('PARSED_CONDITIONS');
    croak "Conditions have not been parsed\n" if !defined $conditions;
    
    return $conditions;
}

sub has_conditions {
    my $self       = shift;
    my $conditions = $self->get_conditions;

    # anything left after whitespace means it has a condition
    # - will this always work? nope - comments not handled
    # update - should do now as comments are stripped in parsing
    $conditions =~ s/\s//g;
    return length $conditions;
}

#  should callers ignore recycling if detected?
sub set_no_recycling_flag {
    my ($self, $flag) = @_;
    $self->{no_recycling} = $flag;
}

sub get_no_recycling_flag {
    my $self = shift;
    return $self->{no_recycling};
}


sub set_ignore_spatial_index_flag {
    my ($self, $flag) = @_;
    $self->{ignore_spatial_index} = $flag;
}

sub get_ignore_spatial_index_flag {
    my $self = shift;
    return $self->{ignore_spatial_index};    
}

sub set_volatile_flag {
    my ($self, $flag) = @_;
    return $self->{is_volatile} = $flag;
}
sub get_volatile_flag {
    my ($self) = @_;
    return $self->{is_volatile};
}
sub is_volatile {
    my ($self) = @_;
    return !!$self->{is_volatile};
}

#  Do we promise to set the current label when condition is evaluated?
#  Needed for verification.
sub get_promise_current_label {
    my ($self) = @_;
    return $self->{promise_current_label};
}

sub set_promise_current_label {
    my ($self, $promise) = @_;
    return $self->{promise_current_label} = $promise;
}

sub get_requires_tree_ref {
    my ($self) = @_;
    return $self->{requires_tree_ref};
}

sub set_requires_tree_ref {
    my ($self, $bool) = @_;
    return $self->{requires_tree_ref} = $bool;
}


sub get_used_dists {
    my $self = shift;
    return $self->get_param('USES');
}

sub parse_distances {
    my $self = shift;
    my %args = @_;

    my $conditions = $self->get_conditions;  #  should call unparsed??
    $conditions .= "\n";
    $conditions =~ s/$RE_COMMENT//g;

    my %uses_distances;
    my %missing_args;
    my %missing_opt_args;
    my %invalid_args;
    my %incorrect_args;
    my $results_types = $NULL_STRING;
    my $index_max_dist;
    my $index_max_dist_off;
    my $index_no_use;

    my @dist_scalar_flags = qw /
        use_euc_distance
        use_cell_distance
    /;
    my @dist_list_flags = qw /
        use_euc_distances
        use_abs_euc_distances
        use_cell_distances
        use_abs_cell_distances
    /;

    #  initialise the params hash items
    foreach my $key (@dist_scalar_flags) {
        $uses_distances{$key} = undef;
    }
    foreach my $key (@dist_list_flags) {
        $uses_distances{$key} = {};
    }

    #  match $D with no trailing subscript, any amount of whitespace
    #  check all possible matches
    foreach my $match ( $conditions =~ /\$D\b\s*\W/g ) {
        next if ( $match =~ /\[/ );
        $uses_distances{use_euc_distance} = 1;
        last;    # drop out if found
    }

    #  match $C with no trailing subscript, any amount of whitespace
    #  check all possible matches
    foreach my $match ( $conditions =~ /\$C\b\s*\W/g ) {
        next if ( $match =~ /\[/ );
        $uses_distances{use_cell_distance} = 1;
        last;
    }

    #  matches $d[0], $d[1] etc.  Loops over any subscripts present
    foreach my $dist ( $conditions =~ /\$d\[\s*($RE_INT)\]/g ) {

        #  hash indexed by distances used
        $uses_distances{use_euc_distances}{$dist}++;
    }

    #  matches $D[0], $D[1] etc.
    foreach my $dist ( $conditions =~ /\$D\[\s*($RE_INT)\]/g ) {
        $uses_distances{use_abs_euc_distances}{$dist}++;
    }

    #  matches $c[0], $c[1] etc.
    foreach my $dist ( $conditions =~ /\$c\[\s*($RE_INT)\]/g ) {
        $uses_distances{use_cell_distances}{$dist}++;
    }

    #  matches $C[0], $C[1] etc.
    foreach my $dist ( $conditions =~ /\$C\[\s*($RE_INT)\]/g ) {
        $uses_distances{use_abs_cell_distances}{$dist}++;
    }

    #  match $nbr_z==5, $nbrcoord[1]<=10 etc
    foreach my $dist ( $conditions =~ /$BOUNDED_COND_RE/gc ) {
        $results_types .= ' non_overlapping';
    }

    #  nested function finder from Friedl's book Mastering Regular Expressions
    #my $levelN;
    #$levelN = qr /\(( [^()] | (??{ $levelN }) )* \) /x;
    #  need to trap sets, eg:
    #  sp_circle (dist => sp_square (c => 5), radius => (f => 10))

    #  search for all relevant subs
    my %subs_to_check     = $self->get_subs_with_prefix( prefix => 'sp_' );
    my @subs_to_check     = keys %subs_to_check;
    my $re_sub_names_text = '\b(?:' . join( q{|}, @subs_to_check ) . ')\b';
    my $re_sub_names      = qr /$re_sub_names_text/xsm;
    my $is_volatile;

    #  maybe the user calls this in the condition somewhere
    my $requires_tree_ref = $conditions =~ /\$self\s*\-\>\s*get_tree_ref\b/;

    my %shape_hash;

    my $str_len = length $conditions;
    pos($conditions) = 0;

    #  loop idea also courtesy Friedl

    CHECK_CONDITIONS:
    while ( not $conditions =~ m/ \G \z /xgcs ) {

        #  haven't hit the end of line yet

        #print "\nParsing $conditions\n";
        #print "Position is " . (pos $conditions) . " of $str_len\n";

        #  march through any whitespace and newlines
        if ( $conditions =~ m/ \G [\s\n\r]+ /xgcs ) {
            next CHECK_CONDITIONS;
        }

        #  find anything that matches our valid subs
        elsif ( $conditions =~ m/ \G ( $re_sub_names ) \s* /xgcs ) {

            my $sub = $1;

            my $sub_args = $NULL_STRING;

            #  get the contents of the sub's arguments (text in brackets)
            $conditions =~ m/ \G \( ( $re_text_in_brackets ) \) /xgcs;
            if ( defined $1 ) {
                $sub_args = $1;
            }

            my $sub_name_and_args = "$sub ($sub_args)";

            #  Get all the args and components.
            #  This does not allow for variables,
            #  which we haven't handled here.
            my %hash_1;
            if ($sub_args) {
                use warnings FATAL => qw(all);  #  make warnings fatal so we get any eval error
                eval {
                    %hash_1 = ( eval $sub_args );
                };
                if ($EVAL_ERROR) {
                    $incorrect_args{$sub} = qq{$sub_name_and_args . "\n" . $EVAL_ERROR};
                    $conditions =~ m/ \G (.) /xgcs; #  bump along by one
                    next CHECK_CONDITIONS;          #  and move to the next part
                }
            }

            my $invalid = $self->get_invalid_args_for_sub_call (sub => $sub, args => \%hash_1);
            if (scalar @$invalid) {
                $invalid_args{$sub_name_and_args} = $invalid;
            }

            my $metadata = $self->get_metadata ( sub => $sub, %hash_1 );

            #  what params do we need?
            #  (handle the use_euc_distances flags etc)
            #  just use the ones we care about
            foreach my $key ( @dist_scalar_flags ) {
                my $method = "get_$key";
                $uses_distances{$key} ||= $metadata->$method;
            }
            foreach my $key ( @dist_list_flags ) {
                my $method = "get_$key";
                my $aa = $metadata->$method;
                croak "Incorrect metadata for sub $sub.  $key should be an array.\n"
                  if !is_arrayref($aa);
                foreach my $dist (@$aa) {
                    $uses_distances{$key}{$dist}++;
                }
            }
            
            #  check required args are present (but not that they are valid)
            my $required_args = $metadata->get_required_args;
            foreach my $req ( @$required_args ) {
                if ( not exists $hash_1{$req} ) {
                    $missing_args{$sub_name_and_args}{$req}++;
                }
            }

            #  check which optional args are missing (but not that they are valid)
            my $optional_args = $metadata->get_optional_args;
            foreach my $req ( @$optional_args ) {
                if ( not exists $hash_1{$req} ) {
                    $missing_opt_args{$sub_name_and_args}{$req}++;
                }
            }

            if (my $cb = $metadata->get_is_volatile_cb) {
                $is_volatile ||= $self->$cb(%hash_1);
            }

            $requires_tree_ref ||= $metadata->get_requires_tree_ref;

            #  REALLY BAD CODE - does not allow for other
            #  functions and operators
            $results_types .= ' ' . $metadata->get_result_type;

            #  need to handle -ve values to turn off the index
            my $this_index_max_dist = $metadata->get_index_max_dist;
            if (defined $this_index_max_dist && !$index_max_dist_off ) {
                if ( $this_index_max_dist < 0 ) {
                    $index_max_dist_off = 1;
                    $index_max_dist     = undef;
                }
                else {
                    $index_max_dist //= $this_index_max_dist;
                    $index_max_dist = max( $index_max_dist, $this_index_max_dist );
                }
            }
            
            my $shape = $metadata->get_shape_type;
            $shape_hash{$shape} ++;

            #  Should we not use a spatial index?  True if any of the conditions say so
            $index_no_use ||= $metadata->get_index_no_use;

        }
        else {    #  bumpalong by one
            $conditions =~ m/ \G (.) /xgcs;
        }
    }

    $results_types =~ s/^\s+//;    #  strip any leading whitespace
    $self->set_param( RESULT_TYPE    => $results_types );
    $self->set_param( INDEX_MAX_DIST => $index_max_dist );
    $self->set_param( INDEX_NO_USE   => $index_no_use );
    $self->set_param( MISSING_ARGS   => \%missing_args );
    $self->set_param( INVALID_ARGS   => \%invalid_args );
    $self->set_param( INCORRECT_ARGS => \%incorrect_args );
    $self->set_param( MISSING_OPT_ARGS => \%missing_opt_args );
    $self->set_param( USES             => \%uses_distances );
    $self->set_param( SHAPE_TYPES      => join ' ', sort keys %shape_hash);
    $self->set_volatile_flag($is_volatile);
    $self->set_requires_tree_ref($requires_tree_ref);

    if (!$requires_tree_ref) {
        #  clear the tree if we do not need it
        $self->set_tree_ref(undef);
    }

    #  do we need to calculate the distances?  NEEDS A BIT MORE THOUGHT
    $self->set_param( CALC_DISTANCES => undef );
    foreach my $value ( values %uses_distances ) {

        if ( ref $value ) {        #  assuming hash here
            my $count = scalar keys %$value;
            if ($count) {
                $self->set_param( CALC_DISTANCES => 1 );
                last;
            }
        }
        elsif ( defined $value ) {
            $self->set_param( CALC_DISTANCES => 1 );
            last;
        }

    }

    #  prepend $self-> to all the sp_xx sub calls
    my $re_object_call = qr {
                (
                  (?<!\w)     #  negative lookbehind for any non-punctuation in case a valid sub name is used in text 
                  (?<!\-\>\s) #  negative lookbehind for method call, eg '$self-> '
                  (?<!\-\>)   #  negative lookbehind for method call, eg '$self->'
                  (?:$re_sub_names)  #  one of our valid sp_ subs - should require a "("?
                )
            }xms;
    $conditions =~ s{$re_object_call}
                    {\$self->$1}gxms;

    #print $conditions;
    $self->set_param( PARSED_CONDITIONS => $conditions );

    return;
}


sub get_invalid_args_for_sub_call {
    my $self = shift;
    my %args = @_;

    my %called_args_hash = %{$args{args}};

    my $metadata = $self->get_metadata (sub => $args{sub});

    foreach my $key (qw /required_args optional_args/) {
        my $method = "get_$key";
        my $list = $metadata->$method;
        delete @called_args_hash{@$list};
    }

    my @invalid = sort keys %called_args_hash;

    return wantarray ? @invalid : \@invalid;
}

#  verify if a user defined set of spatial params will compile cleanly
#  returns any exceptions raised, or a success message
#  it does not test if they will work...
sub verify {
    my $self = shift;
    my %args = @_;

    my $msg;
    my $SPACE = q{ };    #  looks weird, but is Perl Best Practice.

    my $clear_current_label;
    if ($self->get_promise_current_label && !defined $self->get_current_label) {
        $self->set_current_label ('a');
        $clear_current_label = 1;
    }

    my $valid = 1;

    $self->parse_distances;

    #  this needs refactoring, but watch for validity flag in opt args
    my $missing = $self->get_param('MISSING_ARGS');
    if ( $missing and scalar keys %$missing ) {
        $msg .= "Subs are missing required arguments\n";
        foreach my $sub ( keys %$missing ) {
            my $sub_m = $missing->{$sub};
            $msg .= "$sub : " . join( ', ', keys %$sub_m ) . "\n";
        }
        $valid = 0;
        $msg .= "\n";
    }

    my $missing_opt_args = $self->get_param('MISSING_OPT_ARGS');
    if ( $missing_opt_args and scalar keys %$missing_opt_args ) {
        $msg .= "Unused optional arguments\n";
        foreach my $sub ( sort keys %$missing_opt_args ) {
            my $sub_m = $missing_opt_args->{$sub};
            $msg .= "$sub : " . join( ', ', keys %$sub_m ) . "\n";
        }
        $msg .= "\n";
    }
    
    my $incorrect_args = $self->get_param('INCORRECT_ARGS');
    if ( $incorrect_args and scalar keys %$incorrect_args ) {
        $msg .= "\nSubs have incorrectly specified arguments\n";
        foreach my $sub ( sort keys %$incorrect_args ) {
            $msg .= $incorrect_args->{$sub} . "\n";
        }
        $valid = 0;
        $msg .= "\n";
    }

    my $invalid_args = $self->get_param ('INVALID_ARGS');
    if ( $incorrect_args and scalar keys %$invalid_args ) {
        $msg .= "\nSubs have invalid arguments - they might not work as you hope.\n";
        foreach my $sub ( sort keys %$invalid_args ) {
            my $sub_m = $invalid_args->{$sub};
            $msg .= "$sub : " . join( ', ', @$sub_m ) . "\n";
        }
        $valid = 0;
    }

    if ($valid) {
        my $bd = $self->get_basedata_ref // $args{basedata};

        my $clear_label;
        # if (!defined $self->get_current_label) {
        #     $self->set_current_label('a');
        #     $clear_label = 1;
        # }

        $self->set_param( VERIFYING => 1 );

        #my $conditions = $self->get_conditions;  #  not used in this block
        my $error;

        #  Get the first two elements
        my $elements = $bd->get_groups;
        if (! scalar @$elements) {
            $error = 'Basedata has no groups, cannot run spatial conditions';
            goto IFERROR;
        }
        
        my $element1 = $elements->[0];
        my $element2 = scalar @$elements > 1 ? $elements->[1] : $elements->[0];

        my $coord_array1 =
           $bd->get_group_element_as_array (element => $element1);
        my $coord_array2 =
           $bd->get_group_element_as_array (element => $element2);

        my %eval_args;   
        if (eval {$self->is_def_query}) {  
            %eval_args = (
                coord_array1 => $coord_array2,
                coord_id1    => $element2,
                coord_id2    => $element2,
            );
        }
        else {
            %eval_args = (
                coord_array1 => $coord_array1,
                coord_array2 => $coord_array2,
                coord_id1    => $element1,
                coord_id2    => $element2,
            );
        }

        my $cellsizes = $bd->get_cell_sizes;

        my $success = eval {
            $self->evaluate (
                %eval_args,
                cellsizes     => $cellsizes,
                caller_object => $bd,
                basedata      => $bd,
            );
        };
        $error  = $EVAL_ERROR;

      IFERROR:
        if ($error) {
            $msg = "Syntax error:\n\n$error";
            $valid = 0;
        }

        $self->set_param( VERIFYING => undef );
        # if ($clear_label) {
        #     $self->set_current_label();
        # }
    }

    if ($clear_current_label) {
        $self->set_current_label();
    }

    my %hash = (
        msg => "Syntax OK\n"
            . "(note that this does not\n"
            . "guarantee that it will\n"
            . 'work as desired)',
        type => 'info',
        ret  => 'ok',
    );

    if ($msg) {
        if ($valid) {  #  append optional args messages
            $hash{msg} = $hash{msg} . "\n\n" . $msg;
        }
        else {         #  flag errors
            %hash = (
                msg  => $msg,
                type => 'error',
                ret  => 'error',
            );
        }
    }
    return wantarray ? %hash : \%hash;
}

my $locale_warning
  =  "(this is often caused by locale issues - \n"
   . "it is safest to run Biodiverse under a local that uses a . as the decimal place, e.g. 33.5 not 33,5)";


#  calculate the distances between two sets of coords
#  expects refs to two element arrays
#  at the moment we are only calculating the distances
#  - k-order stuff can be done later
sub get_distances {

    my $self = shift;
    my %args = @_;

    croak "coord_array1 argument not specified\n"
        if !defined $args{coord_array1};
    croak "coord_array2 argument not specified\n"
        if !defined $args{coord_array2};

    my @element1 = @{ $args{coord_array1} };
    my @element2 = @{ $args{coord_array2} };

    my @cellsize;
    my $cellsizes = $args{cellsizes};
    if ( is_arrayref($cellsizes) ) {
        @cellsize = @$cellsizes;
    }

    my $params = $self->get_param('USES');

    my ( @d, $sum_D_sqr, @D );
    my ( @c, $sum_C_sqr, @C );
    my @iters;

#if ((not $params->{use_euc_distance}) and (not $params->{use_cell_distance})) {
    if (not(   $params->{use_euc_distance}
            or $params->{use_cell_distance} )
        )
    {

        # don't need all dists, so only calculate the distances we need,
        # as determined when parsing the spatial params
        my %all_distances = (
            %{ $params->{use_euc_distances} },
            %{ $params->{use_abs_euc_distances} },
            %{ $params->{use_cell_distances} },
            %{ $params->{use_abs_cell_distances} },
        );
        @iters = keys %all_distances;
    }
    else {
        @iters = ( 0 .. $#element1 );    #  evaluate all the coords
    }

    foreach my $i (@iters) {

        #no warnings qw /numeric/;
        #  die on numeric errors
        #use warnings FATAL => qw { numeric };

        my $coord1 = $element1[$i];
        croak sprintf ("coord1 value is not numeric: %s\n%s",
            ( $coord1 // 'undef' ),
            $locale_warning)
          if !looks_like_number($coord1);

        my $coord2 = $element2[$i];
        croak sprintf ("coord2 value is not numeric: %s\n%s",
            ( $coord2 // 'undef' ),
            $locale_warning)
          if !looks_like_number($coord2);

        #  trap errors from non-numeric coords
        my $d_val   = eval { $coord2 - $coord1 }; 
        $sum_D_sqr += $d_val**2;
        $d_val = $self->round_to_precision_aa ($d_val);
        $d[$i] = $d_val;
        $D[$i] = abs $d_val;
        
        #  won't need these most of the time
        if ( $params->{use_cell_distance}
            or scalar keys %{ $params->{use_cell_distances} } )
        {

            croak "Cannot use cell distances with cellsize of $cellsize[$i]\n"
                if $cellsize[$i] <= 0;

            my $c_val   = eval { $d_val / $cellsize[$i] };
            $sum_C_sqr += eval { $c_val**2 } || 0;
            $c_val = $self->round_to_precision_aa ($c_val);
            $c[$i] = $c_val;
            $C[$i] = abs $c_val;
        }
    }

    #  avoid precision issues at 14 decimals or so
    #  - a bit of a kludge, but unavoidable if using storable's clone methods.
    my $D = $params->{use_euc_distance}
        ? $self->round_to_precision_aa(sqrt($sum_D_sqr))
        : undef;
    my $C = $params->{use_cell_distance}
        ? $self->round_to_precision_aa(sqrt($sum_C_sqr))
        : undef;

    my %hash = (
        d_list => \@d,
        D_list => \@D,
        D      => $D,
        Dsqr   => $sum_D_sqr,
        C      => $C,
        Csqr   => $sum_C_sqr,
        C_list => \@C,
        c_list => \@c,
    );

    return wantarray ? %hash : \%hash;
}

#  evaluate a pair of coords
sub evaluate {
    my ($self, %args) = @_;

    my $code_ref = $self->get_conditions_code_ref;

    $args{calc_distances} //= $self->get_param('CALC_DISTANCES');

    #  no explicit return here for speed reasons
    $self->$code_ref (%args);
}

#  get a subroutine reference based on the conditions
sub get_conditions_code_ref {
    my $self = shift;

    my $code_ref = $self->get_cached_value ('CODE_REF');

    #  need to check for valid code?
    return $code_ref
      if is_coderef ($code_ref);  

    my $conditions_code = <<'END_OF_CONDITIONS_CODE'
sub {
    my $self = shift;
    my %args = @_;

    #  CHEATING... should use a generic means of getting at the caller object
    my $basedata = $args{basedata} || $args{caller_object}; 

    my %dists;

    my ( @d, @D, $D, $Dsqr, @c, @C, $C, $Csqr );

    if ( $args{calc_distances} ) {
        %dists = eval { $self->get_distances(@_) };
        croak $EVAL_ERROR if $EVAL_ERROR;

        @d    = @{ $dists{d_list} };
        @D    = @{ $dists{D_list} };
        $D    = $dists{D};
        $Dsqr = $dists{Dsqr};
        @c    = @{ $dists{c_list} };
        @C    = @{ $dists{C_list} };
        $C    = $dists{C};
        $Csqr = $dists{Csqr};

        if ($self->get_param ('KEEP_LAST_DISTANCES')) {
            $self->set_param (LAST_DISTS => \%dists);
        }
    }

    #  Should only generate the shorthands when they are actually needed.

    my $coord_id1 = $args{coord_id1};
    my $coord_id2 = $args{coord_id2};

    my @coord = @{ $args{coord_array1} };

    #  shorthands - most cases will be 2D
    my ( $x, $y, $z ) = @coord[0,1,2];

    my @nbrcoord = $args{coord_array2} ? @{ $args{coord_array2} } : ();

    #  shorthands - most cases will be 2D
    my ( $nbr_x, $nbr_y, $nbr_z ) = @nbrcoord[0,1,2];

    #  These are used by the sp_* subs
    my $current_args = {
        basedata   => $basedata,
        dists      => \%dists,
        coord_array    => \@coord,
        nbrcoord_array => \@nbrcoord,
        coord_id1 => $coord_id1,
        coord_id2 => $coord_id2,
    };

    $self->set_param( CURRENT_ARGS => $current_args );

    my $result = eval { CONDITIONS_STRING_GOES_HERE };
    my $error  = $EVAL_ERROR;

    #  clear the args, avoid ref cycles
    $self->set_param( CURRENT_ARGS => undef );

    croak $error if $error;

    return $result;
}
END_OF_CONDITIONS_CODE
      ;

    my $conditions = $self->get_conditions_parsed;
    if (!$self->get_param('NO_LOG')) {
        say "PARSED CONDITIONS:  $conditions";
    }
    $conditions_code =~ s/CONDITIONS_STRING_GOES_HERE/$conditions/m;

    $code_ref = eval $conditions_code;
    croak $EVAL_ERROR if $EVAL_ERROR;

    $self->set_cached_value (CODE_REF => $code_ref);
    return $code_ref;
}

#  Clear the code ref as Storable does not like such things unless
#  its deparse is set to true, and we don't really want to save code refs
sub clear_conditions_code_ref {
    my $self = shift;
    #$self->{code_ref} = undef;
    return;
}

#  Is the condition always true, always false or variable?
#  and we have different types of variable
#  A relatively basic approach but parsing perl needs more than basic regexes.
sub get_result_type {
    my $self = shift;
    my %args = @_;

    my $type = $self->get_param('RESULT_TYPE');

    #  must contain some non-whitespace
    if ( defined $type and length $type and $type =~ /\S/ ) {
        return $type;
    }

    my $condition = $self->get_conditions_parsed;
    $condition =~ s/\n\z//;

    #  Check if always true
    my $check
        = (looks_like_number($condition) && $condition != 0)    #  a non-zero number
        || ($condition =~ /^\s*\$[DC]\s*>=\s*($RE_NUMBER)\s*(?:#.*)*$/ and $1 == 0);    #  $D>=0, $C>=0, poss with comment

    if ($check) {
        $self->set_param( 'RESULT_TYPE' => 'always_true' );
        return 'always_true';
    }

    #  check if always false
    $check = (
             $condition =~ /^\s*($RE_NUMBER)+\s*(?:#.*)*$/ #  one or more zeros, poss with trailing comment
           or $condition =~ /^\$[DC]\s*<\s*($RE_NUMBER)$/   #  $D<0, $C<0 with whitespace
        ) && $1 == 0;

    if ($check or $condition eq '' or $condition =~ /^[\r\n]+$/) {
        $self->set_param( 'RESULT_TYPE' => 'always_false' );
        return 'always_false';
    }

    if ($condition =~ /^\$[DC]\s*<=+\s*(.+)$/    #  $D<=5 etc
        and looks_like_number($1)
        )
    {
        $self->set_param( 'RESULT_TYPE' => 'circle' );
        return 'circle';
    }

    if ( $condition =~ /^\$[DC][<=]=0$/ ) {      #  $D==0, $C<=0 etc
        $self->set_param( 'RESULT_TYPE' => 'self_only' );
        return 'self_only';
    }

    #  '$D>=0 and $D<=5' etc.
    my $RE_GE_LE = qr
        {
            ^
            \$[DC]\s*

            (
                [<>]
            )

            =
            \s*
            ( $RE_NUMBER )
            \s*

            (?:and|&&)

            \s*
            \$[DC]
            \s*

            (
                [<>]
            )

            =
            \s*
            ( $RE_NUMBER )
            \s*
            (?:\#.*)*
            $
        }xo;

    $check = $condition =~ $RE_GE_LE;
    if ( $check && ($1 ne $3 && $2 <= $4) ) {
        #  an annulus is type circle
        $self->set_param( 'RESULT_TYPE' => 'circle' );
        return 'circle';
    }

    #  otherwise it is a "complex" case which is
    #  too hard to work out, and so any analyses have to check all candidates
    $self->set_param( 'RESULT_TYPE' => 'complex' );
    return 'complex';
}

sub get_index_max_dist {
    my $self = shift;
    my %args = @_;

    return $self->get_param('INDEX_MAX_DIST');
    #  should put some checks in here?
    #  or restructure the get_result_type to find both at once
}

sub get_shape_type {
    my $self = shift;
    return $self->get_param('SHAPE_TYPES') // '';
}

#  some conditions can use a label, and some analyses can set the one to process
sub set_current_label {
    my ($self, $label) = @_;
    $self->set_param(CURRENT_LABEL => $label);
}

sub get_current_label {
    my ($self) = @_;
    return $self->get_param('CURRENT_LABEL');
}

sub get_conditions_metadata_as_markdown {
    my $self = shift;

    my $condition_subs = $self->get_subs_with_prefix (prefix => 'sp_');

    #my @keys_of_interest = qw /
    #    description
    #    required_args
    #    optional_args
    #    example
    #/;
    #  also need to know if it uses the index, disables it or has no effect

    my $md;

    foreach my $sub_name (sort keys %$condition_subs) {
        say $sub_name;
        my $metadata = $self->get_metadata (sub => $sub_name);
        #say join ' ', sort keys %$metadata;
        my @md_this_sub;
        push @md_this_sub, "### $sub_name ###";
        push @md_this_sub, $metadata->get_description;

        my $required_args = $metadata->get_required_args;
        if (!scalar @$required_args) {
            $required_args = ['*none*'];
        }
        push @md_this_sub, '**Required args:**  ' . join ', ', sort @$required_args;

        my $optional_args = $metadata->get_optional_args;
        if (!scalar @$optional_args) {
            $optional_args = ['*none*'];
        }
        push @md_this_sub, '**Optional args:**  ' . join ', ', sort @$optional_args;

        my $example = $metadata->get_example;
        my @ex = split "\n", $example;
        my @len_check = grep {length ($_) > 78} @ex;
        croak ("Text exceeds 72 chars width\n" . join "\n", $sub_name, @len_check)
          if scalar @len_check;
        croak "$sub_name has no example" if !$example || $example eq 'no_example';

        push @md_this_sub, "**Example:**\n```perl\n$example\n```";

        $md .= join "\n\n", @md_this_sub;
        $md .= "\n\n";

    }
    
    return $md;
}



=head1 NAME

Biodiverse::SpatialConditions

=head1 SYNOPSIS

  use Biodiverse::SpatialConditions;
  $object = Biodiverse::SpatialParams->new();

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

1;
