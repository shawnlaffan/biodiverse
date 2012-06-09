package Biodiverse::SpatialParams;

use warnings;
use strict;

use English qw ( -no_match_vars );

use Carp;
use PadWalker qw /peek_my/;
use POSIX qw /fmod floor ceil/;
use Math::Trig;
use Math::Trig ':pi';
use Math::Polygon;
use Geo::ShapeFile;
use Tree::R;
use Biodiverse::Progress;
use Scalar::Util qw /looks_like_number blessed/;

use base qw /Biodiverse::Common/;

our $VERSION = '0.16';

our $NULL_STRING = q{};

use Regexp::Common qw /number/;
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

    $self->set_param(
        CONDITIONS    => $conditions,
        WARNING_COUNT => 0,
        KEEP_LAST_DISTANCES => $args{keep_last_distances},
    );

    $self->parse_distances;
    $self->get_result_type;

    return $self;
}

sub get_type {return 'spatial conditions'};


sub get_conditions {
    my $self = shift;
    my %args = @_;

    #  don't want to see the $self etc that parsing inserts
    return $self->get_param('CONDITIONS')
        if $args{unparsed};

    return $self->get_param('PARSED_CONDITIONS')
        || $self->get_param('CONDITIONS');
}

sub get_conditions_unparsed {
    my $self = shift;

    return $self->get_conditions( @_, unparsed => 1 );
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

sub get_used_dists {
    my $self = shift;
    return $self->get_param('USES');
}

sub parse_distances {
    my $self = shift;
    my %args = @_;

    my $conditions = $self->get_conditions;
    $conditions .= "\n";
    $conditions =~ s/$RE_COMMENT//g;

    my %params;
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

    $params{use_euc_distance} = undef;

    #  match $D with no trailing subscript, any amount of whitespace
    #  check all possible matches
    foreach my $match ( $conditions =~ /\$D\b\s*\W/g ) {
        next if ( $match =~ /\[/ );
        $params{use_euc_distance} = 1;
        last;    # drop out if found
    }

    $params{use_cell_distance} = undef;

    #  match $C with no trailing subscript, any amount of whitespace
    #  check all possible matches
    foreach my $match ( $conditions =~ /\$C\b\s*\W/g ) {
        next if ( $match =~ /\[/ );
        $params{use_cell_distance} = 1;
        last;
    }

    $params{use_euc_distances} = {};

    #  matches $d[0], $d[1] etc.  Loops over any subscripts present
    foreach my $dist ( $conditions =~ /\$d\[\s*($RE_INT)\]/g ) {

        #  hash indexed by distances used
        $params{use_euc_distances}{$dist}++;
    }

    $params{use_abs_euc_distances} = {};

    #  matches $D[0], $D[1] etc.
    foreach my $dist ( $conditions =~ /\$D\[\s*($RE_INT)\]/g ) {
        $params{use_abs_euc_distances}{$dist}++;
    }

    $params{use_cell_distances} = {};

    #  matches $c[0], $c[1] etc.
    foreach my $dist ( $conditions =~ /\$c\[\s*($RE_INT)\]/g ) {
        $params{use_cell_distances}{$dist}++;
    }

    $params{use_abs_cell_distances} = {};

    #  matches $C[0], $C[1] etc.
    foreach my $dist ( $conditions =~ /\$C\[\s*($RE_INT)\]/g ) {
        $params{use_abs_cell_distances}{$dist}++;
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

            my %res = $self->get_args( sub => $sub, %hash_1 );

            foreach my $key ( keys %res ) {

                #  what params do we need?
                #  (handle the use_euc_distances flags etc)
                #  just use the ones we care about
                if ( exists $params{$key} ) {
                    if ( ref( $res{$key} ) =~ /HASH/ ) {
                        my $h = $res{$key};
                        foreach my $dist ( keys %$h ) {
                            $params{$key}{$dist}++;
                        }
                    }
                    elsif ( ref( $res{$key} ) =~ /ARRAY/ ) {
                        my $a = $res{$key};
                        foreach my $dist (@$a) {
                            $params{$key}{$dist}++;
                        }
                    }
                    else {  #  get the max of all the inputs, assuming numeric
                        $params{$key} =
                            max( $res{$key} || 0, $params{$key} || 0 );
                    }
                }

                #  check required args are present (but not that they are valid)
                if ( $key eq 'required_args' ) {
                    foreach my $req ( @{ $res{$key} } ) {
                        if ( not exists $hash_1{$req} ) {
                            $missing_args{$sub_name_and_args}{$req}++;
                        }
                    }
                }

                #  check which optional args are missing (but not that they are valid)
                if ( $key eq 'optional_args' ) {
                    foreach my $req ( @{ $res{$key} } ) {
                        if ( not exists $hash_1{$req} ) {
                            $missing_opt_args{$sub_name_and_args}{$req}++;
                        }
                    }
                }

                #  REALLY BAD CODE - does not allow for other
                #  functions and operators
                elsif ( $key eq 'result_type' ) {
                    $results_types .= " $res{$key}";
                }

                #  need to handle -ve values to turn off the index
                elsif (     $key eq 'index_max_dist'
                        and defined $res{$key}
                        and not $index_max_dist_off )
                {
                    $index_max_dist =
                      defined $index_max_dist
                        ? max( $index_max_dist, $res{$key} )
                        : $res{$key};
                    if ( $res{$key} < 0 ) {
                        $index_max_dist_off = 1;
                        $index_max_dist     = undef;
                    }
                }

                #  should we not use a spatial index?
                elsif ( $key eq 'index_no_use' and $res{$key} ) {
                    $index_no_use = 1;
                }
            }
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
    $self->set_param( USES           => \%params );

    #  do we need to calculate the distances?  NEEDS A BIT MORE THOUGHT
    $self->set_param( CALC_DISTANCES => undef );
    foreach my $value ( values %params ) {

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

    #  add $self -> to each condition that does not have it
    my $re_object_call = qr {
                (
                  (?<!\-\>\s)    #  negative lookbehind for method call, eg '$self-> '
                  (?<!\-\>)      #  negative lookbehind for method call, eg '$self->'
                  sp_(?:.+?)\b
                )
            }xms;

    #my $xtest = $conditions =~ $re_object_call;

    #  add $self -> to all the sp_ object calls
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

    my %metadata = $self->get_args (sub => $args{sub});

    foreach my $key (qw /required_args optional_args/) {
        my $list = $metadata{$key} || [];
        delete @called_args_hash{@$list};
    }

    my @invalid = keys %called_args_hash;

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
        foreach my $sub ( keys %$missing_opt_args ) {
            my $sub_m = $missing_opt_args->{$sub};
            $msg .= "$sub : " . join( ', ', keys %$sub_m ) . "\n";
        }
        $msg .= "\n";
    }
    
    my $incorrect_args = $self->get_param('INCORRECT_ARGS');
    if ( $incorrect_args and scalar keys %$incorrect_args ) {
        $msg .= "\nSubs have incorrectly specified arguments\n";
        foreach my $sub ( keys %$incorrect_args ) {
            $msg .= $incorrect_args->{$sub} . "\n";
        }
        $valid = 0;
        $msg .= "\n";
    }

    my $invalid_args = $self->get_param ('INVALID_ARGS');
    if ( $incorrect_args and scalar keys %$invalid_args ) {
        $msg .= "\nSubs have invalid arguments - they might not work as you hope.\n";
        foreach my $sub ( keys %$invalid_args ) {
            my $sub_m = $invalid_args->{$sub};
            $msg .= "$sub : " . join( ', ', @$sub_m ) . "\n";
        }
        $valid = 0;
    }

    if ($valid) {

        my $basedata = $args{basedata};  #  should use this for the distances
        my $bd = $args{basedata};

        $self->set_param( VERIFYING => 1 );

        my $conditions = $self->get_conditions;
        
        #  Get the first two elements
        my $elements = $bd->get_groups;
        my $element1 = $elements->[0];
        my $element2 = $elements->[1];

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

        my $cellsizes = $bd->get_param ('CELL_SIZES');

        my $success = eval {
            $self->evaluate (
                %eval_args,
                cellsizes     => $cellsizes,
                caller_object => $bd,
                basedata      => $bd,
            );
        };
        my $error  = $EVAL_ERROR;

        if ($error) {
            $msg = "Syntax error:\n\n$EVAL_ERROR";
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

    my ( @d, $sumDsqr, @D );
    my ( @c, $sumCsqr, @C );
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
            'coord1 value is not numeric (if you think it is numeric then check your locale): '
            . ( defined $coord1 ? $coord1 : 'undef' )
            . "\n"
            if !looks_like_number($coord1);

        my $coord2 = $element2[$i];
        croak
            'coord2 value is not numeric (if you think it is numeric then check your locale): '
            . ( defined $coord2 ? $coord2 : 'undef' )
            . "\n"
            if !looks_like_number($coord2);

        $d[$i] =
            eval { $coord2 - $coord1 }; #  trap errors from non-numeric coords

        $D[$i] = abs $d[$i];
        $sumDsqr += $d[$i]**2;

        #  won't need these most of the time
        if ( $params->{use_cell_distance}
            or scalar keys %{ $params->{use_cell_distances} } )
        {

            croak "Cannot use cell distances with cellsize of $cellsize[$i]\n"
                if $cellsize[$i] <= 0;

            $c[$i] = eval { $d[$i] / $cellsize[$i] };
            $C[$i] = eval { abs $c[$i] };
            $sumCsqr += eval { $c[$i]**2 } || 0;
        }
    }

    #  use sprintf to avoid precision issues at 14 decimals or so
    #  - a bit of a kludge, but unavoidable if using storable's clone methods.
    my $D =
        $params->{use_euc_distance}
        ? 0 + $self->set_precision(
            precision => '%.10f',
            value     => sqrt($sumDsqr),
        )
        : undef;
    my $C =
        $params->{use_cell_distance}
        ? 0 + $self->set_precision(
            precision => '%.10f',
            value     => sqrt($sumCsqr),
        )
        : undef;

    #  and now trim off any extraneous zeroes after the decimal point
    #  ...now handled by the 0+ on conversion
    #$D += 0 if defined $D;
    #$C += 0 if defined $C;

    my %hash = (
        d_list => \@d,
        D_list => \@D,
        D      => $D,
        Dsqr   => $sumDsqr,
        C      => $C,
        Csqr   => $sumCsqr,
        C_list => \@C,
        c_list => \@c,
    );

    return wantarray ? %hash : \%hash;
}

#  evaluate a pair of coords
sub evaluate {
    my $self = shift;
    my %args = (
        calc_distances => $self->get_param('CALC_DISTANCES'),
        @_,
    );

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
            $self -> set_param (LAST_DISTS => \%dists);
        }
    }

    my $coord_id1 = $args{coord_id1};
    my $coord_id2 = $args{coord_id2};

    my @coord = @{ $args{coord_array1} };
    
    #  shorthands - most cases will be 2D
    my ( $x, $y, $z ) = ( $coord[0], $coord[1], $coord[2] );

    my @nbrcoord = $args{coord_array2} ? @{ $args{coord_array2} } : ();
    
    #  shorthands - most cases will be 2D
    my ( $nbr_x, $nbr_y, $nbr_z ) =
      ( $nbrcoord[0], $nbrcoord[1], $nbrcoord[2] );

    $self->set_param( CURRENT_ARGS => peek_my(0) );

    my $conditions = $self->get_conditions;

    my $result = eval $conditions;
    my $error  = $EVAL_ERROR;
    
    #  clear the args, avoid ref cycles
    $self->set_param( CURRENT_ARGS => undef );

    croak $error if $error;

    return $result;
}

#  is the condition always true, always false or variable?
#  and we have different types of variable
sub get_result_type {
    my $self = shift;
    my %args = @_;

    my $type = $self->get_param('RESULT_TYPE');

    if ( defined $type and length $type and $type =~ /\S/ )
    {    #  must contain some non-whitespace
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

#  should put some checks in here?  or restructure the get_result_type to find both at once
}


################################################################################
#  now for a set of shortcut subs so people don't have to learn so much perl syntax,
#    and it doesn't have to guess things

#  process still needs thought - eg the metadata

sub get_metadata_sp_circle {
    my $self = shift;
    my %args = @_;

    my %args_r = (
        description =>
            "A circle.  Assessed against all dimensions by default (more properly called a hypersphere)\n"
            . "but use the optional \"axes => []\" arg to specify a subset.\n"
            . 'Uses group (map) distances.',
        use_euc_distances => $args{axes},
        use_euc_distance  => $args{axes}
        ? undef
        : 1,    #  don't need $D if we're using a subset
                #  flag index dist if easy to determine
        index_max_dist =>
            ( looks_like_number $args{radius} ? $args{radius} : undef ),
        required_args => ['radius'],
        optional_args => [qw /axes/],
        result_type   => 'circle',
    );

    return wantarray ? %args_r : \%args_r;
}

#  sub to run a circle (or hypersphere for n-dimensions)
sub sp_circle {
    my $self = shift;
    my %args = @_;

    #my $h = peek_my (1);  # get a hash of the $D etc from the level above
    my $h = $self->get_param('CURRENT_ARGS');

    my $dist;
    if ( $args{axes} ) {
        my $axes  = $args{axes};
        my $dists = $h->{'@D'};
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
        $dist =
            ${ $h->{'$D'}
            }; #  PadWalker gives hashrefs of scalar refs, so need to de-ref to get the value
    }

    my $test = $dist
        <= $args{radius};    #  could put into the return, but still debugging

    return $test;
}

sub get_metadata_sp_circle_cell {
    my $self = shift;
    my %args = @_;

    my %args_r = (
        description =>
            "A circle.  Assessed against all dimensions by default (more properly called a hypersphere)\n"
            . "but use the optional \"axes => []\" arg to specify a subset.\n"
            . 'Uses cell distances.',
        use_cell_distances => $args{axes},
        use_cell_distance  => $args{axes}
                            ? undef
                            : 1,    #  don't need $C if we're using a subset
         #index_max_dist => (looks_like_number $args{radius} ? $args{radius} : undef),
        required_args => ['radius'],
        result_type   => 'circle',
    );

    return wantarray ? %args_r : \%args_r;

}

#  cell based circle.
#  As with the other version, should add an option to use a subset of axes
sub sp_circle_cell {
    my $self = shift;
    my %args = @_;

    #my $h = peek_my (1);  # get a hash of the $C etc from the level above
    my $h = $self->get_param('CURRENT_ARGS');

    my $dist;
    if ( $args{axes} ) {
        my $axes  = $args{axes};
        my $dists = $h->{'@C'};
        my $d_sqr = 0;
        foreach my $axis (@$axes) {
            $d_sqr += $dists->[$axis]**2;
        }
        $dist = sqrt $d_sqr;
    }
    else {
        $dist =
            ${ $h->{'$C'}
            }; #  PadWalker gives hash of refs, so need to de-ref scalars to get the value
    }

    my $test = $dist
        <= $args{radius};    #  could put into the return, but still debugging

    return $test;
}

sub get_metadata_sp_annulus {
    my $self = shift;
    my %args = @_;

    my %args_r = (
        description =>
            "An annulus.  Assessed against all dimensions by default\n"
            . "but use the optional \"axes => []\" arg to specify a subset.\n"
            . 'Uses group (map) distances.',
        use_euc_distances => $args{axes},
        use_euc_distance  => $args{axes}
        ? undef
        : 1,    #  don't need $D if we're using a subset
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

    return wantarray ? %args_r : \%args_r;
}

#  sub to run an annulus
sub sp_annulus {
    my $self = shift;
    my %args = @_;

    #my $h = peek_my (1);  # get a hash of the $D etc from the level above
    my $h = $self->get_param('CURRENT_ARGS');

    my $dist;
    if ( $args{axes} ) {
        my $axes  = $args{axes};
        my $dists = $h->{'@D'};
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
        $dist =
            ${ $h->{'$D'}
            }; #  PadWalker gives hashrefs of scalar refs, so need to de-ref to get the value
    }

    #  could put into the return, but still debugging
    my $test =
        eval { $dist >= $args{inner_radius} && $dist <= $args{outer_radius} };
    croak $EVAL_ERROR if $EVAL_ERROR;

    return $test;
}

sub get_metadata_sp_square {
    my $self = shift;
    my %args = @_;

    my %args_r = (
        description =>
            "An overlapping square assessed against all dimensions (more properly called a hypercube).\n"
            . 'Uses group (map) distances.',
        use_euc_distance => 1,    #  need all the distances
                                  #  flag index dist if easy to determine
        index_max_dist =>
            ( looks_like_number $args{size} ? $args{size} : undef ),
        required_args => ['size'],
        result_type   => 'square',
        example =>
            q{#  an overlapping square, cube or hypercube depending on the number of axes}
            . q{#    note - you cannot yet specify which axes to use }
            . q{#    so it will be square on all sides}
            . q{sp_square (size => 300000)},
    );

    return wantarray ? %args_r : \%args_r;
}

#  sub to run a square (or hypercube for n-dimensions)
#  should allow control over which axes to use
sub sp_square {
    my $self = shift;
    my %args = @_;

    my $size = $args{size} / 2;

    #my $h = peek_my (1);  # get a hash of the $D etc from the level above
    my $h = $self->get_param('CURRENT_ARGS');

    my @x =
        @{ $h->{'@D'}
        }; #  PadWalker gives hashrefs of scalar refs, so need to de-ref to get the value
    foreach my $dist (@x) {    #  should use List::Util::any for speed
        return 0 if $dist > $size;
    }
    return 1;                  #  if we get this far then we are OK.

}

sub get_metadata_sp_square_cell {
    my $self = shift;
    my %args = @_;

    my $description =
      'A square assessed against all dimensions '
      . "(more properly called a hypercube).\n"
      . q{Uses 'cell' distances.};

    my %args_r = (
        description => $description,
        use_cell_distance => 1,    #  need all the distances
                                   #  flag index dist if easy to determine
          #index_max_dist => (looks_like_number $args{size} ? $args{size} : undef),
        required_args => ['size'],
        result_type   => 'square',
        example       => 'sp_square_cell (size => 3)',
    );

    return wantarray ? %args_r : \%args_r;
}

sub sp_square_cell {
    my $self = shift;
    my %args = @_;

    my $size = $args{size} / 2;

    #my $h = peek_my (1);  # get a hash of the $D etc from the level above
    my $h = $self->get_param('CURRENT_ARGS');

    my @x =
        @{ $h->{'@C'}
        }; #  PadWalker gives hashrefs of scalar refs, so need to de-ref to get the value
    foreach my $dist (@x) {    #  should use List::Util::any for speed
        return 0 if $dist > $size;
    }
    return 1;                  #  if we get this far then we are OK.

}

sub get_metadata_sp_block {
    my $self = shift;
    my %args = @_;

    my %args_r = (
        description =>
            'A non-overlapping block.  Set an axis to undef to ignore it.'
        ,                      #  should add an example field
                               #  flag index dist if easy to determine
        index_max_dist =>
            ( looks_like_number $args{size} ? $args{size} : undef ),
        required_args => ['size'],
        optional_args => ['origin'],
        result_type   => 'non_overlapping'
        , #  we can recycle results for this (but it must contain the processing group)
          #  need to add optionals for origin and axes_to_use
        example => "sp_block (size => 3)\n"
            . 'sp_block (size => [3,undef,5]) #  rectangular block, ignores second axis',
    );

    return wantarray ? %args_r : \%args_r;
}

#  non-overlapping block, cube or hypercube
#  should drop the guts into another sub so we can call it with cell based args
#*block = &sp_block;  #  for short term backwards compatibility
sub sp_block {
    my $self = shift;
    my %args = @_;

    croak "sp_block: argument 'size' not specified\n"
        if not defined $args{size};

    #my $h = peek_my (1);  # get a hash of the $D etc from the level above
    my $h = $self->get_param('CURRENT_ARGS');

    my $coord    = $h->{'@coord'};
    my $nbrcoord = $h->{'@nbrcoord'};

    my $size = $args{size};    #  need a handler for size == 0
    if ( ( ref $size ) !~ /ARRAY/ ) {
        $size = [ ($size) x scalar @$coord ];
    };    #  make it an array if necessary;

    #  the origin allows the user to shift the blocks around
    my $origin = $args{origin} || [ (0) x scalar @$coord ];
    if ( ( ref $origin ) !~ /ARRAY/ ) {
        $origin = [ ($origin) x scalar @$coord ];
    }    #  make it an array if necessary

    foreach my $i ( 0 .. $#$coord ) {
        #  should add an arg to use a slice (subset) of the coord array

        next if not defined $size->[$i];    #  ignore if this is undef
        my $axis   = $coord->[$i];
        my $tmp    = $axis - $origin->[$i];
        my $offset = fmod( $tmp, $size->[$i] );
        my $edge   = $offset < 0                  #  "left" edge
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
      . q{which are used (default is [0,1]).  The default rotate_angle is pi/2.};

    my %args_r = (
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
        example       =>
              '# East west aligned ellipse'
            . 'sp_ellipse (major_radius => 300000, '
            . 'minor_radius => 100000, axes => [0,1], '
            . 'rotate_angle => 1.5714)',
    );

    return wantarray ? %args_r : \%args_r;
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

    #  PadWalker gives hashrefs of scalar refs,
    #  so need to de-ref to get the value
    my @d = @{ $h->{'@d'} };

    my $major_radius = $args{major_radius};    #  longest axis
    my $minor_radius = $args{minor_radius};    #  shortest axis

    #  set the default offset as north in radians, anticlockwise 1.57 is north
    my $rotate_angle =
        defined $args{rotate_angle} ? $args{rotate_angle} : Math::Trig::pi2;
    if ( defined $args{rotate_angle_deg} and not defined $rotate_angle ) {
        $rotate_angle = deg2rad ( $args{rotate_angle_deg} );
    }

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
    $a_dist = $self->set_precision(value => $a_dist, precision => $precision) + 0;
    $b_dist = $self->set_precision(value => $b_dist, precision => $precision) + 0;

    my $test = eval { 1 >= ( $a_dist + $b_dist ) };
    croak $EVAL_ERROR if $EVAL_ERROR;

    return $test;
}

#sub _sp_random_select {
#    my %args = @_;
#
#    ARGS: if ($args{get_args}) {
#        my %args_r = (
#                    description => "Randomly select a set of neighbours",
#                    #  flag index dist if easy to determine
#                    index_max_dist => undef,
#                    required_args => [qw //],
#                    optional_args => [qw //],
#                    result_type => "random",
#                    );
#        return wantarray ? %args_r : \%args_r;
#    }
#
#}

sub get_metadata_sp_select_all {
    my $self = shift;
    my %args = @_;

    my %args_r = (
        description    => 'Select all elements as neighbours',
        result_type    => 'always_true',
        example        => 'sp_select_all() #  select every group',
        index_max_dist => -1,  #  search whole index if using this in a complex condition
    );

    return wantarray ? %args_r : \%args_r;
}

sub sp_select_all {
    my $self = shift;
    my %args = @_;

    return 1;    #  always returns true
}

sub get_metadata_sp_self_only {
    my $self = shift;

    my %args_r = (
        description    => 'Select only the processing group',
        result_type    => 'self_only',
        index_max_dist => 0,    #  search only self if using index
        example        => 'sp_self_only() #  only use the proceessing cell',
    );

    return wantarray ? %args_r : \%args_r;
}

sub sp_self_only {
    my $self = shift;
    my %args = @_;

    #my $h = peek_my (1);  # get a hash of the $D etc from the level above
    my $h           = $self->get_param('CURRENT_ARGS');
    my $caller_args = $h->{'%args'};

    return $caller_args->{coord_id1} eq $caller_args->{coord_id2};
}

sub get_metadata_sp_match_text {
    my $self = shift;

    my $example =<<'END_SP_MT_EX'
#  use any neighbour where the first axis has value of "type1"
sp_match_text (text => 'type1', axis => 0, type => 'nbr')

# match only when the third neighbour axis is the same
#   as the processing group's second axis
sp_match_text (text => $coord[2], axis => 2, type => 'nbr')

# Set a definition query to only use groups with 'NK' in the third axis
sp_match_text (text => 'NK', axis => 2, type => 'proc')
END_SP_MT_EX
  ;

    my %args_r = (
        description        => 'Select all neighbours matching a text string',
        index_max_dist => undef,

        #required_args => ['axis'],
        required_args => [
            'text',  #  the match text
            'axis',  #  which axis from nbrcoord to use in the match
        ],
        optional_args => [
            'type',  #  nbr or proc to control use of nbr or processing groups
        ],
        index_no_use => 1,                   #  turn the index off
        result_type  => 'text_match_exact',
        example => $example,
    );

    return wantarray ? %args_r : \%args_r;
}

sub sp_match_text {
    my $self = shift;
    my %args = @_;

    my $type = $args{type};
    $type ||= eval {$self->is_def_query()} ? 'proc' : 'nbr';

    my $h = $self->get_param('CURRENT_ARGS');

    my $compcoord;
    if ( $type eq 'proc' ) {
        $compcoord = $h->{'@coord'};
    }
    elsif ( $type eq 'nbr' ) {
        $compcoord = $h->{'@nbrcoord'};
    }

    #  (currently does not check negative offsets)
    croak ("axis argument $args{axis} beyond array bounds, comparing with "
        . join (q{ }, @$compcoord)
        )
      if $args{axis} > $#$compcoord;

    return $args{text} eq $compcoord->[ $args{axis} ];
}

sub get_metadata_sp_match_regex {
    my $self = shift;

    my $example = <<'END_RE_EXAMPLE'
#  use any neighbour where the first axis includes the text "type1"
sp_match_regex (re => qr'type1', axis => 0, type => 'nbr')

# match only when the third neighbour axis starts with
# the processing group's second axis
sp_match_regex (re => qr/^$coord[2]/, axis => 2, type => 'nbr')

# Set a definition query to only use groups where the
# third axis ends in 'park' (case insensitive)
sp_match_regex (text => qr{park$}i, axis => 2, type => 'proc')
END_RE_EXAMPLE
    ;

    my $description = 'Select all neighbours with an axis matching '
        . 'a regular expresion';

    my %args_r = (
        description        => $description,
        index_max_dist => undef,

        #required_args => ['axis'],
        required_args => [
            're',    #  the regex
            'axis',  #  which axis from nbrcoord to use in the match
        ],
        optional_args => [
            'type',  #  nbr or proc to control use of nbr or processing groups
        ],
        index_no_use => 1,                   #  turn the index off
        result_type  => 'non_overlapping',
        example      => $example,
    );

    return wantarray ? %args_r : \%args_r;
}

sub sp_match_regex {
    my $self = shift;
    my %args = @_;

    my $type = $args{type};
    $type ||= eval {$self->is_def_query()} ? 'proc' : 'nbr';

    # get a hash of the $D etc from the level above
    my $h = $self->get_param('CURRENT_ARGS');

    #my $coord = $h->{'@coord'};
    my $compcoord;
    if ( $type eq 'proc' ) {
        $compcoord = $h->{'@coord'};
    }
    elsif ( $type eq 'nbr' ) {
        $compcoord = $h->{'@nbrcoord'};
    }

    #  (currently does not check negative offsets)
    croak ("axis argument $args{axis} beyond array bounds, comparing with "
        . join (q{ }, @$compcoord)
        )
      if $args{axis} > $#$compcoord;

    return $compcoord->[ $args{axis} ] =~ $args{re};
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

    my %args_r = (
        description => $description,

        #  flag the index dist if easy to determine
        index_max_dist => undef,
        optional_args => [qw /axes vector_angle vector_angle_deg/],
        result_type   => 'side',
        example       =>
              'sp_is_left_of (vector_angle => 1.5714)',
    );

    return wantarray ? %args_r : \%args_r;
}


sub sp_is_left_of {
    my $self = shift;
    my %args = @_;
    
    return $self->_sp_side(@_) < 0; 
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

    my %args_r = (
        description => $description,

        #  flag the index dist if easy to determine
        index_max_dist => undef,
        optional_args => [qw /axes vector_angle vector_angle_deg/],
        result_type   => 'side',
        example       =>
              'sp_is_right_of (vector_angle => 1.5714)',
    );

    return wantarray ? %args_r : \%args_r;
}


sub sp_is_right_of {
    my $self = shift;
    my %args = @_;
    
    return $self->_sp_side(@_) > 0; 
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

    my %args_r = (
        description => $description,

        #  flag the index dist if easy to determine
        index_max_dist => undef,
        optional_args => [qw /axes vector_angle vector_angle_deg/],
        result_type   => 'side',
        example       =>
              'sp_in_line_with (vector_angle => Math::Trig::pip2) #  pi/2 = 90 degree angle',
    );

    return wantarray ? %args_r : \%args_r;
}


sub sp_in_line_with {
    my $self = shift;
    my %args = @_;
    
    return $self->_sp_side(@_) == 0; 
}


sub _sp_side {
    my $self = shift;
    my %args = @_;

    my $axes = defined $args{axes} ? $args{axes} : [0,1];
    if ( defined $axes ) {
        croak "_sp_side:  axes arg is not an array ref\n"
            if ( ref $axes ) !~ /ARRAY/;
        my $axis_count = scalar @$axes;
        croak
          "_sp_side:  axes array needs two axes, you have given $axis_count\n"
          if $axis_count != 2;
    }

    #my $h = peek_my (1);  # get a hash of the $C etc from the level above
    my $h = $self->get_param('CURRENT_ARGS');

    #  PadWalker gives hashrefs of scalar refs,
    #  so need to de-ref to get the value
    my @coord     = @{ $h->{'@coord'} };
    my @nbr_coord = @{ $h->{'@nbrcoord'} };

    #  coincident points are in line
    return 0 if (
           $nbr_coord[$axes->[1]] == $coord[$axes->[1]]
        && $nbr_coord[$axes->[0]] == $coord[$axes->[0]]
    );

    #  set the default offset as east in radians
    my $vector_angle = $args{vector_angle};
    if ( defined $args{vector_angle_deg} and not defined $args{vector_angle} ) {
        $vector_angle = deg2rad ( $args{vector_angle_deg} );
    }
    else {
        $vector_angle = defined $args{vector_angle} ? $args{vector_angle} : 0
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
    return $test;
}


sub get_metadata_sp_select_sequence {
    my $self = shift;

    my %args_r = (
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
             #"ignore_after_use",  #  boolean - should we ignore coords after they've been processed - REDUNDANT?
            'cycle_offset'
            , #  boolean, default=1.  cycle the offset back to zero when it exceeds the frequency
        ],
        index_no_use => 1,          #  turn the index off
        result_type  => 'subset',
        example =>
            "# Select every tenth group (groups are sorted alphabetically)\n"
            . q{sp_select_sequence (frequency => 10)}
            . "#  Select every tenth group, starting from the third\n"
            . q{sp_select_sequence (frequency => 10, first_offset => 2)}
            . "#  Select every tenth group, starting from the third last and working backwards\n"
            . q{sp_select_sequence (frequency => 10, first_offset => 2, reverse_order => 1)},
    );

    return wantarray ? %args_r : \%args_r;
}

sub sp_select_sequence {
    my $self = shift;
    my %args = @_;

    #my $h = peek_my (1);  # get a hash of the $D etc from the level above
    my $h           = $self->get_param('CURRENT_ARGS');
    my $caller_args = $h->{'%args'};

    my $bd        = $args{caller_object} || $caller_args->{caller_object};
    my $coord_id1 = $caller_args->{coord_id1};
    my $coord_id2 = $caller_args->{coord_id2};

    #my $self = ${$h->{'$self'}};

    my $verifying = $self->get_param('VERIFYING');

    my $spacing      = $args{frequency};
    my $cycle_offset = defined $args{cycle_offset} ? $args{cycle_offset} : 1;
    my $use_cache    = defined $args{use_cache} ? $args{use_cache} : 1;

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

    my $cached_nbrs = $self->get_cached_value($cache_nbr_name);
    if ( not $cached_nbrs ) {

        #  cache this regardless - what matters is where it is used
        $cached_nbrs = {};
        $self->set_cached_value( $cache_nbr_name => $cached_nbrs );
    }

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
            'count',      #  how many groups per block?
            'use_cache',      #  a boolean flag, defaults to 1
            'reverse_order',  #  work from the other end
            'random',         #  randomise within blocks?
            'prng_seed',      #  seed for the PRNG
        ],
        #index_no_use => 1,          #  turn the index off
        #result_type  => 'subset',
        #result_type  => 'non_overlapping',
        result_type  => 'complex',  #  need to make it a subset, but that part needs work
        example =>
            '# Select up to two groups per block with each block being 5 groups '
            . "on a side where the group size is 100\n"
            . q{sp_select_block (size => 500, count => 2)}
            . "#  Now do it non-randomly and start from the lower right\n"
            . q{sp_select_block (size => 500, count => 10, random => 0, reverse => 1)}
            . "#  Rectangular block with user specified PRNG starting seed\n"
            . q{sp_select_block (size => [300, 500], count => 1, prng_seed => 454678)}
            . "# Lower memory footprint (but longer running times for neighbour searches)\n"
            . q{sp_select_block (size => 500, count => 2, clear_cache => 1)}
    );

    return wantarray ? %metadata : \%metadata;
}

sub sp_select_block {
    my $self = shift;
    my %args = @_;

    #  do stuff here
    my $h           = $self->get_param('CURRENT_ARGS');
    my $caller_args = $h->{'%args'};

    my $bd        = $args{caller_object} || $caller_args->{caller_object};
    my $coord_id1 = $caller_args->{coord_id1};
    my $coord_id2 = $caller_args->{coord_id2};

    my $verifying = $self->get_param('VERIFYING');

    my $frequency    = defined $args{count} ? $args{count} : 1;
    my $size         = $args{size}; #  should be a function of cellsizes
    my $prng_seed    = $args{prng_seed};
    my $random       = defined $args{random} ? $args{random} : 1;
    my $use_cache    = defined $args{use_cache} ? $args{use_cache} : 1;

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

    my $bd = $args{basedata_ref};
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

    my %metadata = (
        description =>
            'Select groups that occur within a user-defined polygon',
        required_args      => [
            'polygon',           #  array of vertices, or a Math::Polygon object
        ],
        optional_args => [
            'point',      #  point to use 
        ],
        index_no_use => 1,
        result_type  => 'complex',  #  is it really complex?  depends on whether it is a def query or not
        example =>
              q{# Is the neighbour coord in a square polygon?}
            . q{sp_point_in_poly (polygon => [[0,0],[0,1],[1,1],[1,0],[0,0]], point => \@nbrcoord)}
    );

    return wantarray ? %metadata : \%metadata;
}


sub sp_point_in_poly {
    my $self = shift;
    my %args = @_;
    my $h = $self->get_param('CURRENT_ARGS');

    my $vertices = $args{polygon};
    my $point = $args{point};
    $point ||= eval {$self->is_def_query} ? $h->{'@coord'} : $h->{'@nbrcoord'};

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
        required_args      => [
            qw /file/,
        ],
        optional_args => [
            qw /point field_name field_val axes no_cache/,
        ],
        index_no_use => 1,
        result_type  => 'complex',
        example => $examples,
    );

    return wantarray ? %metadata : \%metadata;
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
            $point = $h->{'@coord'};
        }
        else {
            $point = $h->{'@nbrcoord'};
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
    my $bd = ${$h->{'$basedata'}};
    my @cell_sizes = @{$bd->get_param('CELL_SIZES')};
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
    my $progress = Biodiverse::Progress->new(text => 'Point in poly search');
    my ($i, $target) = (1, scalar @$rtree_polys);

    foreach my $poly (@$rtree_polys) {
        $progress->update(
            "Checking if point $point_string\nis in polygon\n$i of $target",
            $i / $target,
        );
        if ($poly->contains_point($pointshape)) {
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

sub get_cache_name_sp_point_in_poly_shape {
    my $self = shift;
    my %args = @_;
    my $cache_name = join ':',
        'sp_point_in_poly_shape',
        $args{file},
        ($args{field} || $NULL_STRING),
        (defined $args{field_val} ? $args{field_val} : $NULL_STRING);
    return $cache_name;
}

sub get_cache_sp_point_in_poly_shape {
    my $self = shift;
    my %args = @_;
    my $cache_name = $self->get_cache_name_sp_point_in_poly_shape(%args);
    my $cache = $self->get_cached_value($cache_name);
    if (!$cache) {
        $cache = {};
        $self->set_cached_value($cache_name => $cache);
    }
    return $cache;
}

sub get_polygons_from_shapefile {
    my $self = shift;
    my %args = @_;

    my $file = $args{file};
    $file =~ s/\.(shp|shx|dbf)$//;

    my $field = $args{field_name};

    my $field_val = $args{field_val};

    my $cache_name = join ':', 'SHAPEPOLYS', $file, ($field || $NULL_STRING), (defined $field_val ? $field_val : $NULL_STRING);
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

    my %metadata = (
        description   => 'Is an element non-empty?',
        required_args => [],
        optional_args => [
            'element',      #  which element to use 
        ],
        result_type   => $NULL_STRING,
        example       =>
              q{# Restrict calculations to those non-empty groups.}
            . q{#  Will use the processing group if a def query, the neighbour group otherwise.}
            . q{sp_group_not_empty ()}
            . q{# The same as above, but being specific about which group (element) to test.}
            . q{#  This is probably best used in cases where the element to check is varied spatially.}
            . q{sp_group_not_empty (element => '5467:9876')},
    );

    return wantarray ? %metadata : \%metadata;
}

sub sp_group_not_empty {
    my $self = shift;
    my %args = @_;
    my $h = $self->get_param('CURRENT_ARGS');
    
    my $element = $args{element};
    if (not defined $element) {
        $element = eval {$self->is_def_query()} ? $h->{'$coord_id1'} : $h->{'$coord_id2'};
        $element = ${$element};  #  deref it
    }

    my $bd  = ${$h->{'$basedata'}};

    return $bd->get_richness (element => $element) ? 1 : 0;
}

sub max { return $_[0] > $_[1] ? $_[0] : $_[1] }
sub min { return $_[0] < $_[1] ? $_[0] : $_[1] }



=head1 NAME

Biodiverse::SpatialParams

=head1 SYNOPSIS

  use Biodiverse::SpatialParams;
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
