package Biodiverse::SpatialConditions::Vectorise;
use strict;
use warnings;
use 5.036;
use PDL::Lite qw /pdl/;
use PPR;
use Carp qw/croak/;
use Ref::Util qw / is_coderef /;
use Scalar::Util qw /weaken/;

our $VERSION = '5.0';

#  generalised list "and" call using PDLs
#  assumes all ndarrays have same dimensions
#  or are scalars
sub _gland {
    my ($self, @args) = @_;
    return $args[0] if @args == 1;
    return PDL::cat(map {pdl $_} (@args))->transpose->minover;
}

#  generalised list "or" call using PDLs
sub _glor {
    my ($self, @args) = @_;
    return $args[0] if @args == 1;
    return PDL::cat(map {pdl $_} (@args))->transpose->maxover;
}

sub vectorise_condition {
    my ($self, %args) = @_;

    my $conditions = $args{conditions} // $self->get_conditions_nws;

    state $re_sp_func = qr/
        (?<sp_func>
            !*
            \$self->sp_\w+
            (?&PerlParenthesesList)
        )
        $PPR::GRAMMAR
    /x;
    state $re_gland = qr/
        (?<sp_func>
            !*
            \$self->(?: sp_\w+ | _gland )
            (?&PerlParenthesesList)
        )
        $PPR::GRAMMAR
    /x;

    state %op_names = (
        '<=>' => 'spaceship',
        '<'   => 'lt',
        '>='  => 'ge',
        '=='  => 'eq',
        '>'   => 'gt',
        '<='  => 'le',
    );
    state $ops = join '|', map {quotemeta} sort keys %op_names;

    my $re_sp_get_spatial_output_list_value = qr/
        (?<spvf_name>
            !*
            \$self->sp_get_spatial_output_list_value
        )
        (?<spvf_args>
            (?&PerlParenthesesList)
        )
        (?<spvf_op>  $ops )
        (?<spvf_num> (?&PerlNumber) )
        $PPR::GRAMMAR
    /x;

    #  match && sequence
    my $re_andand = qr/
        (?<andand>
            $re_sp_func
            (?:
                \&\&
                $re_sp_func
            )+
        )
        $PPR::GRAMMAR
    /x;

    #  match || sequence
    my $re_oror = qr/
        (?<oror>
            $re_gland
            (?:
                \|\|
                $re_gland
             )+
        )
        $PPR::GRAMMAR
    /x;

    #  work on copies for easier debug
    my $code1 = $conditions;

    #  Bail out if there is any use of variables except $self.
    #  Otherwise calls to $D etc will mess things up.
    #  PPR gets the whole method call.
    #  One day we might relax this.
    my @vars = grep {$_ !~ '^\$self->'} grep {defined} $code1 =~ /( (?&PerlVariable) ) $PPR::GRAMMAR/gx;
    return if @vars;

    my @vec_methods = $self->get_subs_with_prefix_as_array( prefix => 'vec_sp_' );
    my %sp_methods  = $self->get_subs_with_prefix( prefix => 'sp_' );
    my %valid_sp_methods = map {my $m = $_ =~ s/^vec_//r; $self->can($m) ? ($m => $_) : ()} @vec_methods;
    my %invalid = %sp_methods;
    delete @invalid{keys %valid_sp_methods};

    ###  FOR DEBUG
    # @vec_methods = sort map {"vec_$_"} keys %sp_methods;
    # %invalid = ();
    # %valid_sp_methods = map {my $m = $_ =~ s/^vec_//r; ($m => $_)} @vec_methods;
    ###


    #  we only work with sp_ methods that have vec_sp equivalents
    if (%invalid) {
        my $re_invalid = join '|', map {"\\b$_\\b"} sort keys %invalid;
        return if $code1 =~ /$re_invalid/;
    }

    #  sp_get_spatial_output_list_value is the only method that does not return a boolean,
    #  so turn any trailing op into an arg.
    #  And prefixed ops?  '5 < sp_()'?
    my $code2 = $code1 =~
        s[$re_sp_get_spatial_output_list_value]
         ["$+{spvf_name}($+{spvf_args},$op_names{$+{spvf_op}}=>$+{spvf_num})"]gxre;
    #  not if an element arg is specified
    return if ($+{spvf_args} // '') =~ /element\=\>/;

    my $code3 = $code2 =~
        s[(?<gotone> $re_andand) $PPR::GRAMMAR]
         ['$self->_gland(' . $+{gotone}=~s{\&\&}{,}rg . ')']gxre;

    my $code4 = $code3 =~
        s[(?<gotone> $re_oror) $PPR::GRAMMAR]
         ['$self->_glor(' . $+{gotone}=~s{\|\|}{,}rg . ')']gxre;

    #  next is to rename any sp_ method to its vec_sp_ equivalent
    my $re_spvalid = join '|', sort keys %valid_sp_methods;
    my $code5 = $code4 =~
        s[(?<gotone> $re_spvalid )]
         [$valid_sp_methods{$+{gotone}}]gxre;
    return $code5;
}

sub _aggregate_hash_to_pdl {
    my ($self, $href, $badval) = @_;

    my $universe = $self->get_vector_set_universe;

    #  create an array of zeroes
    my @vals = (0) x keys %$universe;
    # set the relevant ones to the contents of href
    @vals[@{$universe}{keys %$href}] = values %$href;
    #  then create an ndarray
    my $ndarray = PDL->new (PDL::double(), \@vals);
    if (defined $badval) {
        $ndarray->inplace->setvaltobad ($badval);
    }
    my @undefs = grep {!defined $vals[$_]} (0..$#vals);
    if (@undefs) {
        my $idx = PDL::indx (\@undefs);
        $ndarray->badflag(1);
        $ndarray->index($idx) .= $ndarray->badvalue;
    }

    return $ndarray;
}

sub get_vector_set_universe {
    my ($self, %args) = @_;

    state $cache_key = 'VECTOR_SET_UNIVERSE';
    my $universe = $self->get_cached_value ($cache_key);
    if (!defined $universe) {
        my $bd = $self->get_basedata_ref // $args{basedata_ref};
        my $groups = $bd->get_groups;
        my @gps_sorted = sort @$groups;
        my %by_key;
        @by_key{@gps_sorted} = (0 .. $#gps_sorted);
        $universe = \%by_key;
        $self->set_cached_value ($cache_key => $universe);
    }
    return $universe;
}

#  Universe set keyed by index.
#  Saves time in the conditions evaluations.
sub get_vector_set_universe_reversed {
    my ($self, %args) = @_;

    state $cache_key = 'VECTOR_SET_UNIVERSE_REVERSED';
    my $universe = $self->get_cached_value ($cache_key);
    if (!defined $universe) {
        $universe = $self->get_vector_set_universe(%args);
        $universe = {reverse %$universe};
        $self->set_cached_value ($cache_key => $universe);
    }
    return $universe;
}

#  Universe set keyed by index.
#  Saves time in the conditions evaluations.
sub get_vector_set_universe_array {
    my ($self, %args) = @_;

    state $cache_key = 'VECTOR_SET_UNIVERSE_ARRAY';
    my $universe = $self->get_cached_value ($cache_key);
    if (!defined $universe) {
        $universe = $self->get_vector_set_universe(%args);
        my %u = reverse %$universe;
        $universe = [@u{0..scalar keys %u}];
        $self->set_cached_value ($cache_key => $universe);
    }
    return $universe;
}


sub get_vector_set_coords_pdl {
    my $self = shift;

    state $cache_key = 'get_vector_set_coords_pdl';
    my $cache = $self->get_volatile_cache;
    my $cached = $cache->get_cached_value ($cache_key);
    return $cached if defined $cached;

    my $bd = $self->get_basedata_ref;
    my $gp = $bd->get_groups_ref;
    my @all_coords = map {scalar $gp->get_element_name_as_array_aa($_)} sort $bd->get_groups;
    my $all_coord_pdl = pdl (@all_coords);
    $cache->set_cached_value ($cache_key => $all_coord_pdl);
    return $all_coord_pdl;
}

sub get_vector_set_cell_coords_pdl {
    my $self = shift;

    state $cache_key = 'get_vector_set_cell_coords_pdl';
    my $cache = $self->get_volatile_cache;
    my $cached = $cache->get_cached_value ($cache_key);
    return $cached if defined $cached;

    my $bd = $self->get_basedata_ref;

    my $all_coord_pdl = $self->get_vector_set_coords_pdl;

    my @cellsizes = $bd->get_cell_sizes;
    my @origins   = $bd->get_cell_origins;

    my $cellsize_pdl = pdl \@cellsizes;
    my $origin_pdl   = pdl \@origins;
# say STDERR $cellsize_pdl;
#     say STDERR $origin_pdl;
#     say STDERR $all_coord_pdl;
    my $cell_ndarray = ($all_coord_pdl - $origin_pdl)->inplace->divide($cellsize_pdl)->floor;
# say STDERR $cell_ndarray->transpose;
    $cache->set_cached_value ($cache_key => $cell_ndarray);
    return $all_coord_pdl;
}



#  evaluate a vectorised condition
sub evaluate_vectorised {
    my ($self, %args) = @_;

    my $code_ref = $self->get_vectorised_conditions_code_ref;

    return if !defined $code_ref;

    #  no explicit return here for speed reasons
    $self->$code_ref (%args);
}

#  get a subroutine reference based on the conditions
sub get_vectorised_conditions_code_ref {
    my $self = shift;

    state $cache_key = 'CODE_REF_AGGREGATE';
    my $code_ref = $self->get_cached_value ($cache_key);

    #  need to check for valid code?
    return $code_ref
        if is_coderef ($code_ref);

    return if defined $code_ref && !is_coderef ($code_ref);

    my $conditions_code = <<~'END_OF_CONDITIONS_CODE'
        sub {
            my $self = shift;
            my %args = @_;

            use experimental qw /refaliasing declared_refs/;

            #  CHEATING... should use a generic means of getting at the caller object
            my $basedata = $args{basedata} || $args{caller_object};

            #  These are used by the sp_* subs
            my $current_args = {
                basedata    => $basedata,
                coord_array => ($args{coord_array} // []),
                coord_id1   => $args{coord_id1},
            };

            $self->set_current_args ( $current_args );

            my $result = eval { CONDITIONS_STRING_GOES_HERE };
            my $error  = $@;

            delete $current_args->{basedata};

            croak $error if $error;

            my $passed_idx = $result->which->unpdl;
            \my @u_keys = $self->get_vector_set_universe_array(basedata_ref => $basedata);
            my %passed;
            @passed{@u_keys[@$passed_idx]} = ();

            return \%passed;
        }
        END_OF_CONDITIONS_CODE
    ;

    my $conditions = $self->vectorise_condition;
    if (!defined $conditions) {
        $self->set_cached_value ($cache_key => '0');
        return;
    }

    if (!$self->get_param('NO_LOG')) {
        say "PARSED CONDITIONS (VECTORISED):  $conditions";
    }
    $conditions_code =~ s/CONDITIONS_STRING_GOES_HERE/$conditions/m;

    $code_ref = eval $conditions_code;
    croak $@ if $@;

    $self->set_cached_value ($cache_key => $code_ref);
    return $code_ref;
}

1;