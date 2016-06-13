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
use Geo::ShapeFile;
use Tree::R;
use Biodiverse::Progress;
use Scalar::Util qw /looks_like_number blessed reftype/;
use List::MoreUtils qw /uniq/;
use List::Util qw /min max/;

use parent qw /Biodiverse::Common/;

our $VERSION = '1.99_002';

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
        KEEP_LAST_DISTANCES => $args{keep_last_distances},
    );

    eval {$self->parse_distances};
    croak $EVAL_ERROR if $EVAL_ERROR;

    $self->get_result_type;

    return $self;
}

sub get_type {return 'spatial conditions'};

sub metadata_class {
    return $metadata_class;
}

sub get_metadata {
    my $self = shift;
    return $self->SUPER::get_metadata (@_, no_use_cache => 1);
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

    #  some default values
    #  - inefficient as they are duplicated from sub verify
    my $D = my $C = my $Dsqr = my $Csqr = 1;
    my @D = my @C = (1) x 20;
    my @d = my @c = (1) x 20;
    my @coord = @d;
    my ( $x, $y, $z ) = ( 1, 1, 1 );
    my @nbrcoord = @d;
    my ( $nbr_x, $nbr_y, $nbr_z ) = ( 1, 1, 1 );


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
                my $a = $metadata->$method;
                croak "Incorrect metadata for sub $sub.  $key should be an array.\n"
                  if not reftype $a eq 'ARRAY';
                foreach my $dist (@$a) {
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

    my $valid = 1;

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

        my $basedata = $bd;  #  should use this for the distances
        #my $bd = $args{basedata};

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
    if ( ( ref $cellsizes ) =~ /ARRAY/ ) {
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
        croak
            'coord1 value is not numeric: '
            . ( defined $coord1 ? $coord1 : 'undef' )
            . "\n$locale_warning"
            if !looks_like_number($coord1);

        my $coord2 = $element2[$i];
        croak
            'coord2 value is not numeric: '
            . ( defined $coord2 ? $coord2 : 'undef' )
            . "\n$locale_warning"
            if !looks_like_number($coord2);

        my $d_val = 
            eval { $coord2 - $coord1 }; #  trap errors from non-numeric coords

        $d[$i] = 0 + $self->set_precision_aa ($d_val, '%.10f');
        $D[$i] = 0 + $self->set_precision_aa (abs $d_val, '%.10f');
        $sum_D_sqr += $d_val**2;

        #  won't need these most of the time
        if ( $params->{use_cell_distance}
            or scalar keys %{ $params->{use_cell_distances} } )
        {

            croak "Cannot use cell distances with cellsize of $cellsize[$i]\n"
                if $cellsize[$i] <= 0;

            my $c_val = eval { $d_val / $cellsize[$i] };
            $c[$i] = 0 + $self->set_precision_aa ($c_val, '%.10f');
            $C[$i] = 0 + $self->set_precision_aa (eval { abs $c_val }, '%.10f');
            $sum_C_sqr += eval { $c_val**2 } || 0;
        }
    }

    #  use sprintf to avoid precision issues at 14 decimals or so
    #  - a bit of a kludge, but unavoidable if using storable's clone methods.
    my $D = $params->{use_euc_distance}
        ? 0 + $self->set_precision_aa(sqrt($sum_D_sqr), '%.10f')
        : undef;
    my $C = $params->{use_cell_distance}
        ? 0 + $self->set_precision_aa(sqrt($sum_C_sqr), '%.10f')
        : undef;

    my %hash = (
        d_list => [map {0 + $self->set_precision_aa ($_)} @d],
        D_list => [map {0 + $self->set_precision_aa ($_)} @D],
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
    my $self = shift // croak "\$self is undefined";
    my %args = (
        calc_distances => $self->get_param('CALC_DISTANCES'),
        @_,
    );

    my $code_ref = $self->get_conditions_code_ref (%args);

    #  no explicit return here for speed reasons
    $self->$code_ref (%args);
}

#  get a subroutine reference based on the conditions
sub get_conditions_code_ref {
    my $self = shift;

    my $code_ref = $self->get_cached_value ('CODE_REF');

    return $code_ref if defined $code_ref && reftype ($code_ref) eq 'CODE';  #  need to check for valid code?

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
    my ( $x, $y, $z ) = ( $coord[0], $coord[1], $coord[2] );

    my @nbrcoord = $args{coord_array2} ? @{ $args{coord_array2} } : ();

    #  shorthands - most cases will be 2D
    my ( $nbr_x, $nbr_y, $nbr_z ) =
      ( $nbrcoord[0], $nbrcoord[1], $nbrcoord[2] );

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
    say "PARSED CONDITIONS:  $conditions";
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

#  is the condition always true, always false or variable?
#  and we have different types of variable
sub get_result_type {
    my $self = shift;
    my %args = @_;

    my $type = $self->get_param('RESULT_TYPE');

    #  must contain some non-whitespace
    if ( defined $type and length $type and $type =~ /\S/ ) {
        return $type;
    }

    my $condition = $self->get_conditions;

    #  Check if always true
    my $check = looks_like_number($condition)
        and $condition    #  a non-zero number
        or $condition =~ /^\$[DC]\s*>=\s*0$/    #  $D>=0, $C>=0
        ;
    if ($check) {
        $self->set_param( 'RESULT_TYPE' => 'always_true' );
        return 'always_true';
    }

    #  check if always false
    $check = $condition =~ /^0*$/               #  one or more zeros
        or $condition =~ /^\$[DC]\s*<\s*0$/     #  $D<0, $C<0 with whitespace
        ;
    if ($check) {
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

    #  '$D>=0 and $D<=5' etc.  The (?:) groups don't assign to $1 etc
    my $RE_GE_LE = qr
        {
            ^
            (?:
                \$[DC](
                    [<>]
                )
                =+
                $RE_NUMBER
            )\s*
            (?:
                and|&&
            )
            \s*
            (?:
                \$[DC]
            )
            (
                [<>]
            )
            (?:
                <=+$RE_NUMBER
            )
            $
        }xo;

    $check = $condition =~ $RE_GE_LE;
    if ( $check and $1 ne $2 ) {
        $self->set_param( 'RESULT_TYPE' => 'complex annulus' );
        return 'complex annulus';
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

################################################################################
#  now for a set of shortcut subs so people don't have to learn so much perl syntax,
#    and it doesn't have to guess things

#  process still needs thought - eg the metadata

sub get_metadata_sp_circle {
    my $self = shift;
    my %args = @_;

    my $example = <<'END_CIRC_EX'
#  A circle of radius 1000 across all axes
sp_circle (radius => 1000)

#  use only axes 0 and 3
sp_circle (radius => 1000, axes => [0, 3])
END_CIRC_EX
  ;

    my %metadata = (
        description =>
            "A circle.  Assessed against all dimensions by default (more properly called a hypersphere)\n"
            . "but use the optional \"axes => []\" arg to specify a subset.\n"
            . 'Uses group (map) distances.',
        use_abs_euc_distances => ($args{axes} // []),
        #  don't need $D if we're using a subset
        use_euc_distance      => !$args{axes},
                #  flag index dist if easy to determine
        index_max_dist =>
            ( looks_like_number $args{radius} ? $args{radius} : undef ),
        required_args => ['radius'],
        optional_args => [qw /axes/],
        result_type   => 'circle',
        example       => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

#  sub to run a circle (or hypersphere for n-dimensions)
sub sp_circle {
    my $self = shift;
    my %args = @_;

    my $h = $self->get_param('CURRENT_ARGS');

    my $dist;
    if ( $args{axes} ) {
        my $axes  = $args{axes};
        my $dists = $h->{dists}{D_list};
        my $d_sqr = 0;
        foreach my $axis (@$axes) {

            #  drop out clause to save some comparisons over large data sets
            return if $dists->[$axis] > $args{radius};

            # increment
            $d_sqr += $dists->[$axis]**2;
        }
        $dist = sqrt $d_sqr;
    }
    else {
        $dist = $h->{dists}{D}; 
    }

    #  could put into the return, but this helps debugging
    my $test = $dist <= $args{radius};    

    return $test;
}

sub get_metadata_sp_circle_cell {
    my $self = shift;
    my %args = @_;

    my $example = <<'END_CIRC_CELL_EX'
#  A circle of radius 3 cells across all axes
sp_circle (radius => 3)

#  use only axes 0 and 3
sp_circle_cell (radius => 3, axes => [0, 3])
END_CIRC_CELL_EX
  ;

    my %metadata = (
        description =>
            "A circle.  Assessed against all dimensions by default (more properly called a hypersphere)\n"
            . "but use the optional \"axes => []\" arg to specify a subset.\n"
            . 'Uses cell distances.',
        use_abs_cell_distances => ($args{axes} // []),
        #  don't need $C if we're using a subset
        use_cell_distance      => !$args{axes},    
        required_args => ['radius'],
        result_type   => 'circle',
        example       => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

#  cell based circle.
#  As with the other version, should add an option to use a subset of axes
sub sp_circle_cell {
    my $self = shift;
    my %args = @_;

    my $h = $self->get_param('CURRENT_ARGS');

    my $dist;
    if ( $args{axes} ) {
        my $axes  = $args{axes};
        my $dists = $h->{dists}{C_list};
        my $d_sqr = 0;
        foreach my $axis (@$axes) {
            $d_sqr += $dists->[$axis]**2;
        }
        $dist = sqrt $d_sqr;
    }
    else {
        $dist = $h->{dists}{C};
    }

    #  could put into the return, but still debugging
    my $test = $dist <= $args{radius};

    return $test;
}


my $rectangle_example = <<'END_RECTANGLE_EXAMPLE'
#  A rectangle of equal size on the first two axes,
#  and 100 on the third.
sp_rectangle (sizes => [100000, 100000, 100])

#  The same, but with the axes reordered
#  (an example of using the axes argument)
sp_rectangle (
    sizes => [100000, 100, 100000],
    axes  => [0, 2, 1],
)

#  Use only the first an third axes
sp_rectangle (sizes => [100000, 100000], axes => [0,2])
END_RECTANGLE_EXAMPLE
  ;

sub get_metadata_sp_rectangle {
    my $self = shift;
    my %args = @_;

    my $shape_type = 'rectangle';

    #  sometimes complex conditions are passed, not just numeric scalars
    my @unique_axis_vals = uniq @{$args{sizes}};
    my $non_numeric_axis_count = grep {!looks_like_number $_} @unique_axis_vals;
    my ($largest_axis, $axis_count);
    $axis_count = 0;
    if ($non_numeric_axis_count == 0) {
        $largest_axis = max @unique_axis_vals;
        $axis_count   = scalar @{$args{sizes}};
    }

    if ($axis_count > 1 && scalar @unique_axis_vals == 1) {
        $shape_type = 'square';
    }

    my %metadata = (
        description =>
              'A rectangle.  Assessed against all dimensions by default '
            . "(more properly called a hyperbox)\n"
            . "but use the optional \"axes => []\" arg to specify a subset.\n"
            . 'Uses group (map) distances.',
        use_euc_distance => 1,
        required_args => ['sizes'],
        optional_args => [qw /axes/],
        result_type   => 'circle',  #  centred on processing group, so leave as type circle
        example       => $rectangle_example,
        index_max_dist => $largest_axis,
        shape_type     => $shape_type,
    );

    return $self->metadata_class->new (\%metadata);
}

#  sub to run a circle (or hypersphere for n-dimensions)
sub sp_rectangle {
    my $self = shift;
    my %args = @_;

    my $sizes = $args{sizes};
    my $axes = $args{axes} // [0 .. $#$sizes];

    #  should check this in the metadata phase
    croak "Too many axes in call to sp_rectangle\n"
      if $#$axes > $#$sizes;

    my $h     = $self->get_param('CURRENT_ARGS');
    my $dists = $h->{dists}{D_list};

    my $i = -1;  #  @$sizes is in the same order as @$axes
    foreach my $axis (@$axes) {
        ###  need to trap refs to non-existent axes.

        $i++;
        #  coarse filter
        return if $dists->[$axis] > $sizes->[$i];
        #  now check with precision adjusted
        my $d = $self->set_precision_aa ($dists->[$axis]);
        return if $d > $sizes->[$i] / 2;
    }

    return 1;
}


sub get_metadata_sp_annulus {
    my $self = shift;
    my %args = @_;

    my %metadata = (
        description =>
            "An annulus.  Assessed against all dimensions by default\n"
            . "but use the optional \"axes => []\" arg to specify a subset.\n"
            . 'Uses group (map) distances.',
        use_abs_euc_distances => ($args{axes} // []),
            #  don't need $D if we're using a subset
        use_euc_distance  => $args{axes} ? undef : 1,    
            #  flag index dist if easy to determine
        index_max_dist => $args{outer_radius},
        required_args      => [ 'inner_radius', 'outer_radius' ],
        optional_args      => [qw /axes/],
        result_type        => 'circle',
        example            => "#  an annulus assessed against all axes\n"
            . qq{sp_annulus (inner_radius => 2000000, outer_radius => 4000000)\n}
            . "#  an annulus assessed against axes 0 and 1\n"
            . q{sp_annulus (inner_radius => 2000000, outer_radius => 4000000, axes => [0,1])},
    );

    return $self->metadata_class->new (\%metadata);
}

#  sub to run an annulus
sub sp_annulus {
    my $self = shift;
    my %args = @_;

    my $h = $self->get_param('CURRENT_ARGS');

    my $dist;
    if ( $args{axes} ) {
        my $axes  = $args{axes};
        my $dists = $h->{dists}{D_list};
        my $d_sqr = 0;
        foreach my $axis (@$axes) {

            #  drop out clause to save some comparisons over large data sets
            return if $dists->[$axis] > $args{outer_radius};

            # increment
            $d_sqr += $dists->[$axis]**2;
        }
        $dist = sqrt $d_sqr;
    }
    else {
        $dist = $h->{dists}{D};
    }

    my $test =
        eval { $dist >= $args{inner_radius} && $dist <= $args{outer_radius} };
    croak $EVAL_ERROR if $EVAL_ERROR;

    return $test;
}

sub get_metadata_sp_square {
    my $self = shift;
    my %args = @_;
    
    my $example = <<'END_SQR_EX'
#  An overlapping square, cube or hypercube
#  depending on the number of axes
#   Note - you cannot yet specify which axes to use
#   so it will be square on all sides
sp_square (size => 300000)
END_SQR_EX
  ;

    my %metadata = (
        description =>
            "An overlapping square assessed against all dimensions (more properly called a hypercube).\n"
            . 'Uses group (map) distances.',
        use_euc_distance => 1,    #  need all the distances
                                  #  flag index dist if easy to determine
        index_max_dist =>
            ( looks_like_number $args{size} ? $args{size} : undef ),
        required_args => ['size'],
        result_type   => 'square',
        shape_type    => 'square',
        example       =>  $example,
    );

    return $self->metadata_class->new (\%metadata);
}

#  sub to run a square (or hypercube for n-dimensions)
#  should allow control over which axes to use
sub sp_square {
    my $self = shift;
    my %args = @_;

    my $size = $args{size} / 2;

    my $h = $self->get_param('CURRENT_ARGS');

    #my @x = @{ $h->{dists}{D_list} }; 
    foreach my $dist (@{ $h->{dists}{D_list} }) {
        warn "$dist, $size"
          if    $args{size} == 0.2
             && (abs ($size - $dist) < 0.00001)
             && (abs ($size - $dist) > 0);
        return 0 if $dist > $size;
    }

    return 1;  #  if we get this far then we are OK.
}

sub get_metadata_sp_square_cell {
    my $self = shift;
    my %args = @_;

    my $index_max_dist;
    my $bd = eval {$self->get_basedata_ref};
    if (defined $args{size} && $bd) {
        my $cellsizes = $bd->get_cell_sizes;
        my @u = uniq @$cellsizes;
        if (@u == 1 && looks_like_number $u[0]) {
            $index_max_dist = $args{size} * $u[0] / 2;
        }
    }

    my $description =
      'A square assessed against all dimensions '
      . "(more properly called a hypercube).\n"
      . q{Uses 'cell' distances.};

    my %metadata = (
        description => $description,
        use_cell_distance => 1,    #  need all the distances
        index_max_dist    => $index_max_dist,
        required_args => ['size'],
        result_type   => 'square',
        example       => 'sp_square_cell (size => 3)',
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_square_cell {
    my $self = shift;
    my %args = @_;

    my $size = $args{size} / 2;

    my $h = $self->get_param('CURRENT_ARGS');

    #my @x = @{ $h->{dists}{C_list} };
    foreach my $dist (@{ $h->{dists}{C_list} }) {
        return 0 if $dist > $size;
    }

    #  if we get this far then we are OK.
    return 1;
}

sub get_metadata_sp_block {
    my $self = shift;
    my %args = @_;

    my $shape_type = 'complex';
    if (looks_like_number $args{size} && !defined $args{origin}) {
        $shape_type = 'square';
    }
    
    my $index_max_dist = looks_like_number $args{size} ? $args{size} : undef;

    my %metadata = (
        description =>
            'A non-overlapping block.  Set an axis to undef to ignore it.',
        index_max_dist => $index_max_dist,
        shape_type     => $shape_type,
        required_args  => ['size'],
        optional_args  => ['origin'],
        result_type    => 'non_overlapping'
        , #  we can recycle results for this (but it must contain the processing group)
          #  need to add optionals for origin and axes_to_use
        example => "sp_block (size => 3)\n"
            . 'sp_block (size => [3,undef,5]) #  rectangular block, ignores second axis',
    );

    return $self->metadata_class->new (\%metadata);
}

#  non-overlapping block, cube or hypercube
#  should drop the guts into another sub so we can call it with cell based args
sub sp_block {
    my $self = shift;
    my %args = @_;

    croak "sp_block: argument 'size' not specified\n"
        if not defined $args{size};

    my $h = $self->get_param('CURRENT_ARGS');

    my $coord    = $h->{coord_array};
    my $nbrcoord = $h->{nbrcoord_array};

    my $size = $args{size};    #  need a handler for size == 0
    if ( (reftype ( $size ) // '') ne 'ARRAY' ) {
        $size = [ ($size) x scalar @$coord ];
    };    #  make it an array if necessary;

    #  the origin allows the user to shift the blocks around
    my $origin = $args{origin} || [ (0) x scalar @$coord ];
    if ( (reftype ( $origin ) // '') ne 'ARRAY' ) {
        $origin = [ ($origin) x scalar @$coord ];
    }    #  make it an array if necessary

    foreach my $i ( 0 .. $#$coord ) {
        #  should add an arg to use a slice (subset) of the coord array
        #  Should also use floor() instead of fmod()

        next if not defined $size->[$i];    #  ignore if this is undef
        my $axis   = $coord->[$i];
        my $tmp    = $axis - $origin->[$i];
        my $offset = fmod( $tmp, $size->[$i] );
        my $edge   = $offset < 0               #  "left" edge
            ? $axis - $offset - $size->[$i]    #  allow for -ve fmod results
            : $axis - $offset;
        my $dist = $nbrcoord->[$i] - $edge;
        return 0 if $dist < 0 or $dist > $size->[$i];
    }
    return 1;
}

sub get_metadata_sp_ellipse {
    my $self = shift;
    my %args = @_;

    my $axes = $args{axes};
    if ( ( ref $axes ) !~ /ARRAY/ ) {
        $axes = [ 0, 1 ];
    }

    my $description =
        q{A two dimensional ellipse.  Use the 'axes' argument to control }
      . q{which are used (default is [0,1]).  The default rotate_angle is 0, }
      . q{such that the major axis is east-west.};
    my $example = <<'END_ELLIPSE_EX'
# North-south aligned ellipse
sp_ellipse (
    major_radius => 300000,
    minor_radius => 100000,
    axes => [0,1],
    rotate_angle => 1.5714,
)
END_ELLIPSE_EX
  ;

    my %metadata = (
        description => $description,
        use_euc_distances => $axes,
        use_euc_distance  => $axes ? undef : 1,

        #  flag the index dist if easy to determine
        index_max_dist => (
            looks_like_number $args{major_radius}
            ? $args{major_radius}
            : undef
        ),
        required_args => [qw /major_radius minor_radius/],
        optional_args => [qw /axes rotate_angle rotate_angle_deg/],
        result_type   => 'ellipse',
        example       => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

#  a two dimensional ellipse -
#  it would be nice to generalise to more dimensions,
#  but that involves getting mediaeval with matrices
sub sp_ellipse {
    my $self = shift;
    my %args = @_;

    my $axes = $args{axes};
    if ( defined $axes ) {
        croak "sp_ellipse:  axes arg is not an array ref\n"
            if ( ref $axes ) !~ /ARRAY/;
        my $axis_count = scalar @$axes;
        croak
            "sp_ellipse:  axes array needs two axes, you have given $axis_count\n"
            if $axis_count != 2;
    }
    else {
        $axes = [ 0, 1 ];
    }

    my $h = $self->get_param('CURRENT_ARGS');

    my @d = @{ $h->{dists}{d_list} };

    my $major_radius = $args{major_radius};    #  longest axis
    my $minor_radius = $args{minor_radius};    #  shortest axis

    #  set the default offset as east-west in radians (anticlockwise 1.57 is north)
    my $rotate_angle = $args{rotate_angle};
    if ( defined $args{rotate_angle_deg} and not defined $rotate_angle ) {
            $rotate_angle = deg2rad ( $args{rotate_angle_deg} );
    }
    $rotate_angle //= 0;

    my $d0 = $d[ $axes->[0] ];
    my $d1 = $d[ $axes->[1] ];
    my $D  = sqrt ($d0 ** 2 + $d1 ** 2);

    #  now calc the bearing to rotate the coords by
    my $bearing = atan2( $d0, $d1 ) + $rotate_angle;

    my $r_x = sin($bearing) * $D;    #  rotated x coord
    my $r_y = cos($bearing) * $D;    #  rotated y coord

    my $a_dist = ( $r_y ** 2 ) / ( $major_radius**2 );
    my $b_dist = ( $r_x ** 2 ) / ( $minor_radius**2 );
    my $precision = '%.14f';
    $a_dist = $self->set_precision_aa ($a_dist, $precision) + 0;
    $b_dist = $self->set_precision_aa ($b_dist, $precision) + 0;

    my $test = eval { 1 >= ( $a_dist + $b_dist ) };
    croak $EVAL_ERROR if $EVAL_ERROR;

    return $test;
}

sub get_metadata_sp_select_all {
    my $self = shift;
    my %args = @_;

    my %metadata = (
        description    => 'Select all elements as neighbours',
        result_type    => 'always_true',
        example        => 'sp_select_all() #  select every group',
        index_max_dist => -1,  #  search whole index if using this in a complex condition
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_select_all {
    my $self = shift;
    #my %args = @_;

    return 1;    #  always returns true
}

sub get_metadata_sp_self_only {
    my $self = shift;

    my %metadata = (
        description    => 'Select only the processing group',
        result_type    => 'self_only',
        index_max_dist => 0,    #  search only self if using index
        example        => 'sp_self_only() #  only use the proceessing cell',
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_self_only {
    my $self = shift;
    my %args = @_;

    my $h = $self->get_param('CURRENT_ARGS');

    return $h->{coord_id1} eq $h->{coord_id2};
}

sub get_metadata_sp_select_element {
    my $self = shift;

    my $example =<<'END_SP_SELECT_ELEMENT'
# match where the whole coordinate ID (element name)
# is 'Biome1:savannah forest'
sp_select_element (element => 'Biome1:savannah forest')
END_SP_SELECT_ELEMENT
  ;

    my %metadata = (
        description => 'Select a specific element.  Basically the same as sp_match_text, but with optimisations enabled',
        index_max_dist => undef,

        required_args => [
            'element',  #  the element name
        ],
        optional_args => [
            'type',  #  nbr or proc to control use of nbr or processing groups
        ],
        index_no_use => 1,
        result_type  => 'always_same',
        example => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_select_element {
    my $self = shift;
    my %args = @_;

    delete $args{axes};  #  remove the axes arg if set

    my $comparator = $self->get_comparator_for_text_matching (%args);

    return $args{element} eq $comparator;
}


sub get_metadata_sp_match_text {
    my $self = shift;

    my $example =<<'END_SP_MT_EX'
#  use any neighbour where the first axis has value of "type1"
sp_match_text (text => 'type1', axis => 0, type => 'nbr')

# match only when the third neighbour axis is the same
#   as the processing group's second axis
sp_match_text (text => $coord[2], axis => 2, type => 'nbr')

# match where the whole coordinate ID (element name)
# is 'Biome1:savannah forest'
sp_match_text (text => 'Biome1:savannah forest')

# Set a definition query to only use groups with 'NK' in the third axis
sp_match_text (text => 'NK', axis => 2, type => 'proc')
END_SP_MT_EX
  ;

    my %metadata = (
        description        => 'Select all neighbours matching a text string',
        index_max_dist => undef,

        #required_args => ['axis'],
        required_args => [
            'text',  #  the match text
        ],
        optional_args => [
            'axis',  #  which axis from nbrcoord to use in the match
            'type',  #  nbr or proc to control use of nbr or processing groups
        ],
        index_no_use => 1,                   #  turn the index off
        result_type  => 'text_match_exact',
        example => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_match_text {
    my $self = shift;
    my %args = @_;

    my $comparator = $self->get_comparator_for_text_matching (%args);
    
    return $args{text} eq $comparator;
}

sub get_metadata_sp_match_regex {
    my $self = shift;

    my $example = <<'END_RE_EXAMPLE'
#  use any neighbour where the first axis includes the text "type1"
sp_match_regex (re => qr'type1', axis => 0, type => 'nbr')

# match only when the third neighbour axis starts with
# the processing group's second axis
sp_match_regex (re => qr/^$coord[2]/, axis => 2, type => 'nbr')

# match the whole coordinate ID (element name)
# where Biome can be 1 or 2 and the rest of the name contains "dry"
sp_match_regex (re => qr/^Biome[12]:.+dry/)

# Set a definition query to only use groups where the
# third axis ends in 'park' (case insensitive)
sp_match_regex (text => qr{park$}i, axis => 2, type => 'proc')

END_RE_EXAMPLE
    ;

    my $description = 'Select all neighbours with an axis matching '
        . 'a regular expresion';

    my %metadata = (
        description        => $description,
        index_max_dist => undef,

        required_args => [
            're',    #  the regex
        ],
        optional_args => [
            'type',  #  nbr or proc to control use of nbr or processing groups
            'axis',  #  which axis from nbrcoord to use in the match
        ],
        index_no_use => 1,                   #  turn the index off
        result_type  => 'non_overlapping',
        example      => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_match_regex {
    my $self = shift;
    my %args = @_;

    my $comparator = $self->get_comparator_for_text_matching (%args);

    return $comparator =~ $args{re};
}

#  get the relevant string for the text match subs
sub get_comparator_for_text_matching {
    my $self = shift;
    my %args = @_;

    my $type = $args{type};
    $type ||= eval {$self->is_def_query()} ? 'proc' : 'nbr';

    my $h = $self->get_param('CURRENT_ARGS');

    my $axis = $args{axis};
    my $compcoord;
    
    if (defined $axis) { #  check against one axis

        if ( $type eq 'proc' ) {
            $compcoord = $h->{coord_array};
        }
        elsif ( $type eq 'nbr' ) {
            $compcoord = $h->{nbrcoord_array};
        }

        croak ("axis argument $args{axis} beyond array bounds, comparing with "
            . join (q{ }, @$compcoord)
            )
          if abs ($axis) > $#$compcoord;
    
        return $compcoord->[ $axis ];
    }

    if ( $type eq 'proc' ) {
        $compcoord = $h->{coord_id1};
    }
    elsif ( $type eq 'nbr' ) {
        $compcoord = $h->{coord_id2};
    }
    
    return $compcoord;  #  deref scalar reference
}

sub get_metadata_sp_is_left_of {
    my $self = shift;
    my %args = @_;

    my $axes = $args{axes};
    if ( ( ref $axes ) !~ /ARRAY/ ) {
        $axes = [ 0, 1 ];
    }

    my $description =
        q{Are we to the left of a vector radiating out from the processing cell? }
      . q{Use the 'axes' argument to control }
      . q{which are used (default is [0,1])};

    my %metadata = (
        description => $description,

        #  flag the index dist if easy to determine
        index_max_dist => undef,
        optional_args => [qw /axes vector_angle vector_angle_deg/],
        result_type   => 'side',
        example       =>
              'sp_is_left_of (vector_angle => 1.5714)',
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_is_left_of {
    my $self = shift;
    #my %args = @_;

    #  no explicit return here for speed reasons
    $self->_sp_side(@_) < 0; 
}

sub get_metadata_sp_is_right_of {
    my $self = shift;
    my %args = @_;

    my $axes = $args{axes};
    if ( ( ref $axes ) !~ /ARRAY/ ) {
        $axes = [ 0, 1 ];
    }

    my $description =
        q{Are we to the right of a vector radiating out from the processing cell? }
      . q{Use the 'axes' argument to control }
      . q{which are used (default is [0,1])};

    my %metadata = (
        description => $description,

        #  flag the index dist if easy to determine
        index_max_dist => undef,
        optional_args => [qw /axes vector_angle vector_angle_deg/],
        result_type   => 'side',
        example       =>
              'sp_is_right_of (vector_angle => 1.5714)',
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_is_right_of {
    my $self = shift;
    #my %args = @_;

    #  no explicit return here for speed reasons
    $self->_sp_side(@_) > 0; 
}

sub get_metadata_sp_in_line_with {
    my $self = shift;
    my %args = @_;

    my $axes = $args{axes};
    if ( ( ref $axes ) !~ /ARRAY/ ) {
        $axes = [ 0, 1 ];
    }

    my $description =
        q{Are we in line with a vector radiating out from the processing cell? }
      . q{Use the 'axes' argument to control }
      . q{which are used (default is [0,1])};

    my %metadata = (
        description => $description,

        #  flag the index dist if easy to determine
        index_max_dist => undef,
        optional_args => [qw /axes vector_angle vector_angle_deg/],
        result_type   => 'side',
        example       =>
              'sp_in_line_with (vector_angle => Math::Trig::pip2) #  pi/2 = 90 degree angle',
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_in_line_with {
    my $self = shift;
    #my %args = @_;

    #  no explicit return here for speed reasons
    $self->_sp_side(@_) == 0; 
}


sub _sp_side {
    my $self = shift;
    my %args = @_;

    my $axes = $args{axes};
    if ( defined $axes ) {
        croak "_sp_side:  axes arg is not an array ref\n"
            if ( ref $axes ) !~ /ARRAY/;
        my $axis_count = scalar @$axes;
        croak
          "_sp_side:  axes array needs two axes, you have given $axis_count\n"
          if $axis_count != 2;
    }
    else {
        $axes = [0,1];
    }

    my $h = $self->get_param('CURRENT_ARGS');

    #  Need to de-ref to get the values
    my @coord     = @{ $h->{coord_array} };
    my @nbr_coord = @{ $h->{nbrcoord_array} };

    #  coincident points are in line
    return 0 if (
           $nbr_coord[$axes->[1]] == $coord[$axes->[1]]
        && $nbr_coord[$axes->[0]] == $coord[$axes->[0]]
    );

    #  set the default offset as east in radians
    my $vector_angle = $args{vector_angle};
    if ( defined $args{vector_angle_deg} && !defined $args{vector_angle} ) {
        $vector_angle = deg2rad ( $args{vector_angle_deg} );
    }
    else {
        $vector_angle = $args{vector_angle} // 0;
    }

    #  get the direction and rotate it so vector_angle is zero
    my $dir = atan2 (
        $nbr_coord[$axes->[1]] - $coord[$axes->[1]],
        $nbr_coord[$axes->[0]] - $coord[$axes->[0]],
    )
    - $vector_angle;

    #  Do we need to do this?  Must modify checks below if removed.
    if ($dir < 0) {
        $dir += Math::Trig::pi2;
    };

    #  Is to the left of the input vector if $dir is < PI,
    #  to the right if PI < $dir < 2PI,
    #  otherwise it is in line
    my $test = 0;
    if ($dir > 0 && $dir < pi) {
        $test = -1;
    }
    elsif ($dir > pi && $dir < Math::Trig::pi2) {
        $test = 1;
    }

    #  no explicit return here for speed reasons
    $test;
}


sub get_metadata_sp_select_sequence {
    my $self = shift;

    my $example = <<'END_SEL_SEQ_EX'
# Select every tenth group (groups are sorted alphabetically)
sp_select_sequence (frequency => 10)

#  Select every tenth group, starting from the third
sp_select_sequence (frequency => 10, first_offset => 2)

#  Select every tenth group, starting from the third last 
#  and working backwards
sp_select_sequence (
    frequency     => 10,
    first_offset  =>  2,
    reverse_order =>  1,
)
END_SEL_SEQ_EX
  ;

    my %metadata = (
        description =>
            'Select a subset of all available neighbours based on a sample sequence '
            . '(note that groups are sorted south-west to north-east)',

        #  flag index dist if easy to determine
        index_max_dist => undef,
        required_args      => [qw /frequency/]
        ,    #  frequency is how many groups apart they should be
        optional_args => [
            'first_offset',     #  the first offset, defaults to 0
            'use_cache',        #  a boolean flag, defaults to 1
            'reverse_order',    #  work from the other end
            'cycle_offset',
        ],
        index_no_use => 1,          #  turn the index off
        result_type  => 'subset',
        example      => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_select_sequence {
    my $self = shift;
    my %args = @_;

    my $h           = $self->get_param('CURRENT_ARGS');

    my $bd        = $args{caller_object} || $h->{basedata};
    my $coord_id1 = $h->{coord_id1};
    my $coord_id2 = $h->{coord_id2};

    my $verifying = $self->get_param('VERIFYING');

    my $spacing      = $args{frequency};
    my $cycle_offset = $args{cycle_offset} // 1;
    my $use_cache    = $args{use_cache} // 1;

    if ($args{clear_cache}) {
        $self->set_param(SP_SELECT_SEQUENCE_CLEAR_CACHE => 1);
    }

    my $ID                = join q{,}, @_;
    my $cache_gp_name     = 'SP_SELECT_SEQUENCE_CACHED_GROUP_LIST' . $ID;
    my $cache_nbr_name    = 'SP_SELECT_SEQUENCE_CACHED_NBRS' . $ID;
    my $cache_offset_name = 'SP_SELECT_SEQUENCE_LAST_OFFSET' . $ID;
    my $cache_last_coord_id_name = 'SP_SELECT_SEQUENCE_LAST_COORD_ID1' . $ID;
    
    #  inefficient - should put in metadata
    $self->set_param(NBR_CACHE_PFX => 'SP_SELECT_SEQUENCE_CACHED_NBRS');

    #  get the offset and increment if needed
    my $offset = $self->get_cached_value($cache_offset_name);

    #my $start_pos;

    my $last_coord_id1;
    if ( not defined $offset ) {
        $offset = $args{first_offset} || 0;

        #$start_pos = $offset;
    }
    else {    #  should we increment the offset?
        $last_coord_id1 = $self->get_cached_value($cache_last_coord_id_name);
        if ( defined $last_coord_id1 and $last_coord_id1 ne $coord_id1 ) {
            $offset++;
            if ( $cycle_offset and $offset >= $spacing ) {
                $offset = 0;
            }
        }
    }
    $self->set_cached_value( $cache_last_coord_id_name => $coord_id1 );
    $self->set_cached_value( $cache_offset_name        => $offset );

    my $cached_nbrs = $self->get_cached_value_dor_set_default_aa($cache_nbr_name, {});

    my $nbrs;
    if (    $use_cache
        and scalar keys %$cached_nbrs
        and exists $cached_nbrs->{$coord_id1} )
    {
        $nbrs = $cached_nbrs->{$coord_id1};
    }
    else {
        my @groups;
        my $cached_gps = $self->get_cached_value($cache_gp_name);
        if ( $use_cache and $cached_gps ) {
            @groups = @$cached_gps;
        }
        else {

            #  get in some order
            #  (should also put in a random option)

            if ( $args{reverse_order} ) {
                @groups = reverse $bd->get_groups_ref->get_element_list_sorted;
            }
            else {
                @groups = $bd->get_groups_ref->get_element_list_sorted;
            }

            if ( $use_cache and not $verifying ) {
                $self->set_cached_value( $cache_gp_name => \@groups );
            }
        }

        my $last_i = -1;
        for ( my $i = $offset; $i <= $#groups; $i += $spacing ) {
            my $ii = int $i;

            #print "$ii ";

            next if $ii == $last_i;    #  if we get spacings less than 1

            my $gp = $groups[$ii];

            #  should we skip this comparison?
            #next if ($args{ignore_after_use} and exists $cached_nbrs->{$gp});

            $nbrs->{$gp} = 1;
            $last_i = $ii;
        }

        #if ($use_cache and not $verifying) {
        if ( not $verifying ) {
            $cached_nbrs->{$coord_id1} = $nbrs;
        }
    }

    return defined $coord_id2 ? exists $nbrs->{$coord_id2} : 0;
}

#  get the list of cached nbrs - VERY BODGY needs generalising
sub get_cached_subset_nbrs {
    my $self = shift;
    my %args = @_;

    #  this sub only works for simple cases
    return
        if $self->get_result_type ne 'subset';

    my $cache_name;
    my $cache_pfx = $self->get_param('NBR_CACHE_PFX');
    #'SP_SELECT_SEQUENCE_CACHED_NBRS';    #  BODGE

    my %params = $self->get_params_hash;    #  find the cache name
    foreach my $param ( keys %params ) {
        next if not $param =~ /^$cache_pfx/;
        $cache_name = $param;
    }

    return if not defined $cache_name;

    my $cache     = $self->get_param($cache_name);
    my $sub_cache = $cache->{ $args{coord_id} };

    return wantarray ? %$sub_cache : $sub_cache;
}

sub clear_cached_subset_nbrs {
    my $self = shift;
    my %args = @_;

    my $clear = $self->get_param('SP_SELECT_SEQUENCE_CLEAR_CACHE');
    return if ! $clear;
    
    my $cache_name;
    my $cache_pfx = 'SP_SELECT_SEQUENCE_CACHED';    #  BODGE
    
    my %params = $self->get_params_hash;    #  find the cache name
    foreach my $param ( keys %params ) {
        next if not $param =~ /^$cache_pfx/;
        $cache_name = $param;
        $self->delete_param ($cache_name);
    }

    return;
}


sub get_metadata_sp_select_block {
    my $self = shift;
    my %args = @_;
    
    my $example = <<'END_SPSB_EX'
# Select up to two groups per block with each block being 5 groups
on a side where the group size is 100
sp_select_block (size => 500, count => 2)

#  Now do it non-randomly and start from the lower right
sp_select_block (size => 500, count => 10, random => 0, reverse => 1)

#  Rectangular block with user specified PRNG starting seed
sp_select_block (size => [300, 500], count => 1, prng_seed => 454678)

# Lower memory footprint (but longer running times for neighbour searches)
sp_select_block (size => 500, count => 2, clear_cache => 1)
END_SPSB_EX
  ;

    my %metadata = (
        description =>
            'Select a subset of all available neighbours based on a block sample sequence',

        #  flag index dist if easy to determine
        index_max_dist =>
            ( looks_like_number $args{size} ? $args{size} : undef ),
        required_args      => [
            'size',           #  size of the block
        ],    
        optional_args => [
            'count',          #  how many groups per block?
            'use_cache',      #  a boolean flag, defaults to 1
            'reverse_order',  #  work from the other end
            'random',         #  randomise within blocks?
            'prng_seed',      #  seed for the PRNG
        ],
        result_type  => 'complex',  #  need to make it a subset, but that part needs work
        example      => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_select_block {
    my $self = shift;
    my %args = @_;

    #  do stuff here
    my $h = $self->get_param('CURRENT_ARGS');

    my $bd        = $args{caller_object} || $h->{basedata} || $self->get_basedata_ref;
    my $coord_id1 = $h->{coord_id1};
    my $coord_id2 = $h->{coord_id2};

    my $verifying = $self->get_param('VERIFYING');

    my $frequency    = $args{count} // 1;
    my $size         = $args{size}; #  should be a function of cellsizes
    my $prng_seed    = $args{prng_seed};
    my $random       = $args{random} // 1;
    my $use_cache    = $args{use_cache} // 1;

    if ($args{clear_cache}) {
        $self->set_param(SP_SELECT_BLOCK_CLEAR_CACHE => 1);
    }

    my $cache_sp_out_name   = 'SP_SELECT_BLOCK_CACHED_SP_OUT';
    my $cached_sp_list_name = 'SP_BLOCK_NBRS';

    #  generate the spatial output and get the relevant groups
    #  NEED TO USE THE PARENT DEF QUERY IF SET? Not if this is to calculate it...
    my $sp = $self->get_param ($cache_sp_out_name);
    my $prng;
    if (! $sp) {
        $sp = $self->get_spatial_output_sp_select_block (
            basedata_ref => $bd,
            size         => $size,
        );    
        $self->set_param($cache_sp_out_name => $sp);
        $prng = $sp->initialise_rand(seed => $prng_seed);
        $sp->set_param(PRNG => $prng);
    }
    else {
        $prng = $sp->get_param ('PRNG');
    }

    my $nbrs = {};
    my @groups;
    
    if ( $sp->exists_list(list => $cached_sp_list_name, element => $coord_id1) ) {
        $nbrs = $sp->get_list_values (
            element => $coord_id1,
            list    => $cached_sp_list_name,
        );
    }
    else {
        my $these_nbrs = $sp->get_list_values (
            element => $coord_id1,
            list    => '_NBR_SET1',
        );
        my $sorted_nbrs = $sp->get_element_list_sorted(list => $these_nbrs);

        if ( $args{reverse_order} ) {
            $sorted_nbrs = [reverse @$sorted_nbrs];
        }
        if ($random) {
            $sorted_nbrs = $prng->shuffle($sorted_nbrs);
        }

        my $target = min (($frequency - 1), $#$sorted_nbrs);
        @groups = @$sorted_nbrs[0 .. $target];
        @$nbrs{@groups} = (1) x scalar @groups;

        foreach my $nbr (@$these_nbrs) {  #  cache it
            $sp->add_to_lists (
                element              => $nbr,
                $cached_sp_list_name => $nbrs,
                use_ref              => 1,
            );
        }
    }

    return defined $coord_id2 ? exists $nbrs->{$coord_id2} : 0;
}


sub get_spatial_output_sp_select_block {
    my $self = shift;
    my %args = @_;

    my $size = $args{size};

    my $bd = $args{basedata_ref} // $self->get_basedata_ref;
    my $sp = $bd->add_spatial_output (name => 'get nbrs for sp_select_block ' . time());
    $bd->delete_output(output => $sp, delete_basedata_ref => 0);

    #  add a null element to avoid some errors
    #$sp->add_element(group => 'null_group', label => 'null_label');

    my $spatial_conditions = ["sp_block (size => $size)"];

    $sp->run_analysis(
        calculations                  => [],
        override_valid_analysis_check => 1,
        spatial_conditions            => $spatial_conditions,
        #definition_query              => $definition_query,
        no_create_failed_def_query    => 1,  #  only want those that pass the def query
        calc_only_elements_to_calc    => 1,
        #basedata_ref                  => $bd,
    );

    return $sp;
}

sub get_metadata_sp_point_in_poly {
    my $self = shift;
    
    my %args = @_;
    
    my $example = <<'END_SP_PINPOLY'
# Is the neighbour coord in a square polygon?
sp_point_in_poly (
    polygon => [[0,0],[0,1],[1,1],[1,0],[0,0]],
    point   => \@nbrcoord,
)

END_SP_PINPOLY
  ;

    my %metadata = (
        description =>
            "Select groups that occur within a user-defined polygon \n"
            . '(see sp_point_in_poly_shape for an altrnative)',
        required_args      => [
            'polygon',           #  array of vertices, or a Math::Polygon object
        ],
        optional_args => [
            'point',      #  point to use 
        ],
        index_no_use => 1,
        result_type  => 'always_same',
        example      => $example,
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_point_in_poly {
    my $self = shift;
    my %args = @_;
    my $h = $self->get_param('CURRENT_ARGS');

    my $vertices = $args{polygon};
    my $point = $args{point};
    $point ||= eval {$self->is_def_query} ? $h->{coord_array} : $h->{nbrcoord_array};

    my $poly = (blessed ($vertices) || $NULL_STRING) eq 'Math::Polygon'
                ? $vertices
                : Math::Polygon->new( points => $vertices );

    return $poly->contains($point);
}

sub _get_shp_examples {
        my $examples = <<'END_OF_SHP_EXAMPLES'
# Is the neighbour coord in a shapefile?
sp_point_in_poly_shape (
    file  => 'c:\biodiverse\data\coastline_lamberts',
    point => \@nbrcoord,
)
# Is the neighbour coord in a shapefile's second polygon (counting from 1)?
sp_point_in_poly_shape (
    file      => 'c:\biodiverse\data\coastline_lamberts',
    field_val => 2,
    point     => \@nbrcoord,
)
# Is the neighbour coord in a polygon with value 2 in the OBJECT_ID field?
sp_point_in_poly_shape (
    file      => 'c:\biodiverse\data\coastline_lamberts',
    field     => 'OBJECT_ID',
    field_val => 2,
    point     => \@nbrcoord,
)
END_OF_SHP_EXAMPLES
  ;
    return $examples;
}

sub get_metadata_sp_point_in_poly_shape {
    my $self = shift;
    my %args = @_;
    
    my $examples = $self->_get_shp_examples;

    my %metadata = (
        description =>
            'Select groups that occur within a polygon or polygons extracted from a shapefile',
        required_args => [
            qw /file/,
        ],
        optional_args => [
            qw /point field_name field_val axes no_cache/,
        ],
        index_no_use => 1,
        result_type  => 'always_same',
        example => $examples,
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_point_in_poly_shape {
    my $self = shift;
    my %args = @_;
    my $h = $self->get_param('CURRENT_ARGS');

    my $no_cache = $args{no_cache};
    my $axes = $args{axes} || [0,1];

    my $point = $args{point};
    if (!defined $point) {  #  convoluted, but syntax highlighting plays up with ternary op
        if (eval {$self->is_def_query}) {
            $point = $h->{coord_array};
        }
        else {
            $point = $h->{nbrcoord_array};
        }
    }

    my $x_coord = $point->[$axes->[0]];
    my $y_coord = $point->[$axes->[1]];

    my $cached_results = $self->get_cache_sp_point_in_poly_shape(%args);
    my $point_string = join (':', $x_coord, $y_coord);
    if (!$no_cache && exists $cached_results->{$point_string}) {
        return $cached_results->{$point_string};
    }

    my $polys = $self->get_polygons_from_shapefile (%args);

    my $pointshape = Geo::ShapeFile::Point->new(X => $x_coord, Y => $y_coord);

    my $rtree = $self->get_rtree_for_polygons_from_shapefile (%args, shapes => $polys);
    my $bd = $h->{basedata};
    my @cell_sizes = $bd->get_cell_sizes;
    my ($cell_x, $cell_y) = ($cell_sizes[$axes->[0]], $cell_sizes[$axes->[1]]);
    my @rect = (
        $x_coord - $cell_x / 2,
        $y_coord - $cell_y / 2,
        $x_coord + $cell_x / 2,
        $y_coord + $cell_y / 2,
    );

    my $rtree_polys = [];
    $rtree->query_partly_within_rect(@rect, $rtree_polys);

    #  need a progress dialogue for involved searches
    #my $progress = Biodiverse::Progress->new(text => 'Point in poly search');
    my ($i, $target) = (1, scalar @$rtree_polys);

    foreach my $poly (@$rtree_polys) {
        #$progress->update(
        #    "Checking if point $point_string\nis in polygon\n$i of $target",
        #    $i / $target,
        #);
        if ($poly->contains_point($pointshape, 0)) {
            if (!$no_cache) {
                $cached_results->{$point_string} = 1;
            }
            return 1;
        }
    }

    if (!$no_cache) {
        $cached_results->{$point_string} = 0;
    }

    return;
}



sub get_metadata_sp_points_in_same_poly_shape {
    my $self = shift;
    my %args = @_;

    my $examples = 'NEED SOME EXAMPLES';

    my %metadata = (
        description =>
            'Returns true when two points are within the same shapefile polygon',
        required_args => [
            qw /file/,
        ],
        optional_args => [
            qw /point1 point2 axes no_cache/,
        ],
        index_no_use => 1,
        result_type  => 'non_overlapping',
        example => $examples,
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_points_in_same_poly_shape {
    my $self = shift;
    my %args = @_;
    my $h = $self->get_param('CURRENT_ARGS');

    my $no_cache = $args{no_cache};
    my $axes = $args{axes} || [0,1];

    my $point1 = $args{point1} // $h->{coord_array};
    my $point2 = $args{point2} // $h->{nbrcoord_array};

    my $x_coord1 = $point1->[$axes->[0]];
    my $y_coord1 = $point1->[$axes->[1]];
    my $x_coord2 = $point2->[$axes->[0]];
    my $y_coord2 = $point2->[$axes->[1]];

    my $cached_results     = $self->get_cache_sp_points_in_same_poly_shape(%args);
    my $cached_pts_in_poly = $self->get_cache_points_in_shapepoly(%args);

    my $point_string1 = join (':', $x_coord1, $y_coord1, $x_coord2, $y_coord2);
    my $point_string2 = join (':', $x_coord2, $y_coord2, $x_coord1, $y_coord1);    
    if (!$no_cache) {
        for my $point_string ($point_string1, $point_string2) {
            return $cached_results->{$point_string}
              if (exists $cached_results->{$point_string});
        }
    }

    my $polys = $self->get_polygons_from_shapefile (%args);

    my $pointshape1 = Geo::ShapeFile::Point->new(X => $x_coord1, Y => $y_coord1);
    my $pointshape2 = Geo::ShapeFile::Point->new(X => $x_coord2, Y => $y_coord2);

    my $rtree = $self->get_rtree_for_polygons_from_shapefile (%args, shapes => $polys);
    my $bd = $h->{basedata};
    my @cell_sizes = $bd->get_cell_sizes;
    my ($cell_x, $cell_y) = ($cell_sizes[$axes->[0]], $cell_sizes[$axes->[1]]);
    
    my @rect1 = (
        $x_coord1 - $cell_x / 2,
        $y_coord1 - $cell_y / 2,
        $x_coord1 + $cell_x / 2,
        $y_coord1 + $cell_y / 2,
    );
    my $rtree_polys1 = [];
    $rtree->query_partly_within_rect(@rect1, $rtree_polys1);

    my @rect2 = (
        $x_coord2 - $cell_x / 2,
        $y_coord2 - $cell_y / 2,
        $x_coord2 + $cell_x / 2,
        $y_coord2 + $cell_y / 2,
    );
    my $rtree_polys2 = [];
    $rtree->query_partly_within_rect(@rect2, $rtree_polys2);
    
    #  get the list of common polys
    my @rtree_polys_common = grep {
        my $check = $_;
        List::MoreUtils::any {$_ eq $check} @$rtree_polys2
    } @$rtree_polys1;

    my ($i, $target) = (1, scalar @$rtree_polys1);
    my $point1_str = join ':', $x_coord1, $y_coord1;
    my $point2_str = join ':', $x_coord2, $y_coord2;
    

    foreach my $poly (@rtree_polys_common) {
        my $poly_id     = $poly->shape_id();

        my $pt1_in_poly = $cached_pts_in_poly->{$poly_id}{$point1_str};
        if (!defined $pt1_in_poly) {
            $pt1_in_poly = $poly->contains_point($pointshape1, 0);
            $cached_pts_in_poly->{$poly_id}{$point1_str} = $pt1_in_poly ? 1 : 0;
        }

        my $pt2_in_poly = $cached_pts_in_poly->{$poly_id}{$point2_str};
        if (!defined $pt2_in_poly) {
            $pt2_in_poly = $poly->contains_point($pointshape2, 0);
            $cached_pts_in_poly->{$poly_id}{$point2_str} = $pt2_in_poly ? 1 : 0;
        }

        if ($pt1_in_poly || $pt2_in_poly) {
            my $result = $pt1_in_poly && $pt2_in_poly;
            if (!$no_cache) {
                $cached_results->{$point_string1} = $result;
            }
            return $result;
        }
    }

    if (!$no_cache) {
        $cached_results->{$point_string1} = 0;
    }

    return;
}

sub get_cache_name_sp_point_in_poly_shape {
    my $self = shift;
    my %args = @_;
    my $cache_name = join ':',
        'sp_point_in_poly_shape',
        $args{file},
        ($args{field_name} || $NULL_STRING),
        (defined $args{field_val} ? $args{field_val} : $NULL_STRING);
    return $cache_name;
}

sub get_cache_name_sp_points_in_same_poly_shape {
    my $self = shift;
    my %args = @_;
    my $cache_name = join ':',
        'sp_points_in_same_poly_shape',
        $args{file};
    return $cache_name;
}

sub get_cache_points_in_shapepoly {
    my $self = shift;
    my %args = @_;

    my $cache_name = 'cache_' . $args{file};
    my $cache = $self->get_cached_value_dor_set_default_aa ($cache_name, {});
    return $cache;
}

sub get_cache_sp_point_in_poly_shape {
    my $self = shift;
    my %args = @_;
    my $cache_name = $self->get_cache_name_sp_point_in_poly_shape(%args);
    my $cache = $self->get_cached_value($cache_name, {});
    return $cache;
}

sub get_cache_sp_points_in_same_poly_shape {
    my $self = shift;
    my %args = @_;
    my $cache_name = $self->get_cache_name_sp_points_in_same_poly_shape(%args);
    my $cache = $self->get_cached_value_dor_set_default_aa($cache_name, {});
    return $cache;
}

sub get_polygons_from_shapefile {
    my $self = shift;
    my %args = @_;

    my $file = $args{file};
    $file =~ s/\.(shp|shx|dbf)$//;

    my $field = $args{field_name};

    my $field_val = $args{field_val};

    my $cache_name = join ':', 'SHAPEPOLYS', $file, ($field // $NULL_STRING), ($field_val // $NULL_STRING);
    my $cached     = $self->get_cached_value($cache_name);

    return (wantarray ? @$cached : $cached) if $cached;

    my $shapefile = Geo::ShapeFile->new($file);

    my @shapes;
    if ((!defined $field || $field eq 'FID') && defined $field_val) {
        my $shape = $shapefile->get_shp_record($field_val);
        push @shapes, $shape;
    }
    else {
        my $progress_bar = Biodiverse::Progress->new(gui_only => 1);
        my $n_shapes = $shapefile->shapes();

        REC:
        for my $rec (1 .. $n_shapes) {  #  brute force search

            $progress_bar->update(
                "Processing $file\n" .
                "Shape $rec of $n_shapes\n",
                $rec / $n_shapes,
            );

            #  get the lot
            if ((!defined $field || $field eq 'FID') && !defined $field_val) {
                push @shapes, $shapefile->get_shp_record($rec);
                next REC;
            }

            #  get all that satisfy the condition
            my %db = $shapefile->get_dbf_record($rec);
            my $is_num = looks_like_number ($db{$field});
            if ($is_num ? $field_val == $db{$field} : $field_val eq $db{$field}) {
                push @shapes, $shapefile->get_shp_record($rec);
                #last REC;
            }
        }
    }

    $self->set_cached_value($cache_name => \@shapes);

    return wantarray ? @shapes : \@shapes;
}

sub get_rtree_for_polygons_from_shapefile {
    my $self = shift;
    my %args = @_;
    
    my $shapes = $args{shapes};

    my $rtree_cache_name = $self->get_cache_name_rtree(%args);
    my $rtree = $self->get_cached_value($rtree_cache_name);

    if (!$rtree) {
        #print "Building R-Tree $rtree_cache_name\n";
        $rtree = $self->build_rtree_for_shapepolys (shapes => $shapes);
        $self->set_cached_value($rtree_cache_name => $rtree);
    }
    
    return $rtree;
}

sub get_cache_name_rtree {
    my $self = shift;
    my %args = @_;
    my $cache_name = join ':',
        'RTREE',
        $args{file},
        ($args{field} || $NULL_STRING),
        (defined $args{field_val} ? $args{field_val} : $NULL_STRING);
    return $cache_name;
}

sub build_rtree_for_shapepolys {
    my $self = shift;
    my %args = @_;

    my $shapes = $args{shapes};

    my $rtree = Tree::R->new();
    foreach my $shape (@$shapes) {
        my @bbox = ($shape->x_min, $shape->y_min, $shape->x_max, $shape->y_max);
        $rtree->insert($shape, @bbox);
    }

    return $rtree;
}

sub get_metadata_sp_group_not_empty {
    my $self = shift;
    
    my %args = @_;

    my $example = <<'END_GP_NOT_EMPTY_EX'
# Restrict calculations to those non-empty groups.
#  Will use the processing group if a def query,
#  the neighbour group otherwise.
sp_group_not_empty ()

# The same as above, but being specific about which group (element) to test.
#  This is probably best used in cases where the element
#  to check is varied spatially.}
sp_group_not_empty (element => '5467:9876')
END_GP_NOT_EMPTY_EX
  ;

    my %metadata = (
        description   => 'Is a basedata group non-empty? (i.e. contains one or more labels)',
        required_args => [],
        optional_args => [
            'element',      #  which element to use 
        ],
        result_type   => $NULL_STRING,
        example       => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

sub sp_group_not_empty {
    my $self = shift;
    my %args = @_;
    my $h = $self->get_param('CURRENT_ARGS');
    
    my $element = $args{element};
    if (not defined $element) {
        $element = eval {$self->is_def_query()} ? $h->{coord_id1} : $h->{coord_id2};
        #$element = ${$element};  #  deref it
    }

    my $bd  = $h->{basedata};

    return $bd->get_richness (element => $element) ? 1 : 0;
}

sub get_metadata_sp_in_label_range {
    my $self = shift;

    my %args = @_;

    my %metadata = (
        description   => "Is a group within a label's range?",
        required_args => ['label'],
        optional_args => [
            'type',  #  nbr or proc to control use of nbr or processing groups
        ],
        result_type   => 'always_same',
        index_no_use  => 1,  #  turn index off since this doesn't cooperate with the search method
        example       =>
              qq{# Are we in the range of label called Genus:Sp1?\n}
            . q{sp_in_label_range(label => 'Genus:Sp1')}
            . q{#  The type argument determines is the processing or neighbour group is assessed}
    );

    return $self->metadata_class->new (\%metadata);
}


sub sp_in_label_range {
    my $self = shift;
    my %args = @_;

    my $h = $self->get_param('CURRENT_ARGS');

    my $label = $args{label} // croak "argument label not defined\n";

    my $type = $args{type};
    $type ||= eval {$self->is_def_query()} ? 'proc' : 'nbr';

    my $group;
    if ( $type eq 'proc' ) {
        $group = $h->{coord_id1};
    }
    elsif ( $type eq 'nbr' ) {
        $group = $h->{coord_id2};
    }

    my $bd  = $h->{basedata};

    my $labels_in_group = $bd->get_labels_in_group_as_hash_aa ($group);

    my $exists = exists $labels_in_group->{$label};

    return $exists;
}



#sub max { return $_[0] > $_[1] ? $_[0] : $_[1] }
#sub min { return $_[0] < $_[1] ? $_[0] : $_[1] }


sub get_example_sp_get_spatial_output_list_value {

    my $ex = <<"END_EXAMPLE_GSOLV"
#  get the spatial results value for the current neighbour group
# (or processing group if used as a def query)
sp_get_spatial_output_list_value (
    output  => 'sp1',              #  using spatial output called sp1
    list    => 'SPATIAL_RESULTS',  #  from the SPATIAL_RESULTS list
    index   => 'PE_WE_P',          #  get index value for PE_WE_P
)

#  get the spatial results value for group 128:254
sp_get_spatial_output_list_value (
    output  => 'sp1',
    element => '128:254',
    list    => 'SPATIAL_RESULTS',
    index   => 'PE_WE_P',
)
END_EXAMPLE_GSOLV
  ;

    return $ex;
}


sub get_metadata_sp_get_spatial_output_list_value {
    my $self = shift;
    my %args = @_;

    my $description =
        q{Obtain a value from a list in a previously calculated spatial output.};

    my $example = $self->get_example_sp_get_spatial_output_list_value;

    my %metadata = (
        description => $description,
        index_no_use   => 1,  #  turn index off since this doesn't cooperate with the search method
        required_args  => [qw /output index/],
        optional_args  => [qw /list element/],
        result_type    => 'always_same',
        example        => $example,
    );

    return $self->metadata_class->new (\%metadata);
}

#  get the value from another spatial output
sub sp_get_spatial_output_list_value {
    my $self = shift;
    my %args = @_;

    my $list_name = $args{list} // 'SPATIAL_RESULTS';
    my $index     = $args{index};
    
    my $h = $self->get_param('CURRENT_ARGS');

    my $default_element
      = eval {$self->is_def_query}
        ? $h->{coord_id1}
        : $h->{coord_id2};  #?

    my $element = $args{element} // $default_element;

    my $bd      = eval {$self->get_basedata_ref} || $h->{basedata} || $h->{caller_object};
    my $sp_name = $args{output};
    croak "Spatial output name not defined\n" if not defined $sp_name;

    my $sp = $bd->get_spatial_output_ref (name => $sp_name)
      or croak 'Spatial output $sp_name does not exist in basedata '
                . $bd->get_param ('NAME')
                . "\n";

    croak "element $element is not in spatial output\n"
      if not $sp->exists_element (element => $element);

    my $list = $sp->get_list_ref (list => $list_name, element => $element);
    return if not exists $list->{$index};

    return $list->{$index};
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
        croak (join "\n", $sub_name, @len_check) if scalar @len_check;
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
