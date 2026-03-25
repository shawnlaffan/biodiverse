use strict;
use warnings;
use 5.036;

use Carp;
use English qw { -no_match_vars };

use FindBin qw/$Bin/;

use rlib;
use Test2::V0;

# use Geo::GDAL::FFI;
# use Path::Tiny qw /path/;
use Test::TempDir::Tiny qw /tempdir/;
use List::Util qw /max/;

local $| = 1;

use Biodiverse::TestHelpers qw {get_basedata_object_from_site_data get_tree_object_from_sample_data};
use Biodiverse::BaseData;
use Biodiverse::SpatialConditions;

# BEGIN {$ENV{PERL_TEST_TEMPDIR_TINY_NOCLEANUP} = 1}

use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__);
my @subs = grep {$_ =~ 'main::test_'} $obj->functions();

exit main( @ARGV );

sub main {
    my @args  = @_;

    if (@args) {
        for my $name (@args) {
            die "No test method test_$name\n"
                if not my $func = (__PACKAGE__->can( 'test_' . $name ) || __PACKAGE__->can( $name ));
            $func->();
        }
        done_testing;
        return 0;
    }

    foreach my $sub (@subs) {
        no strict 'refs';
        $sub->();
    }

    done_testing;
    return 0;
}

sub test_vectorised_conditions {
    my $bd = Biodiverse::BaseData->new (
        NAME       => 'test_spcond_listification',
        CELL_SIZES => [1,1],
    );
    my %all_gps;
    foreach my $i (1..5) {
        foreach my $j (1..5) {
            my $gp = "$i:$j";
            foreach my $k (max(1, $i-1)..$i) {
                #  fully nested
                $bd->add_element (label => "$k", group => $gp);
            }
            $all_gps{$gp}++;
        }
    }

    my $tree = Biodiverse::Tree->new (name => 'for testing');

    my @nodes;
    foreach my $name (1..6) {
        my $node = $tree->add_node(name => $name);
        push @nodes, $node;
    }
    my @nodes_l1;
    foreach my $n (1,3,5) {
        my $node = $tree->add_node(name => "inner_$n");
        $node->add_children(children => [@nodes[$n-1, $n]]);
        push @nodes_l1, $node;
    }
    my $root = $tree->add_node(name => 'root');
    $root->add_children(children => \@nodes_l1);
    # say STDERR $tree->to_newick;



    my $sp_to_test1 = $bd->add_spatial_output (name => 'test_1');
    $sp_to_test1->run_analysis (
        calculations       => ['calc_endemism_whole', 'calc_element_lists_used'],
        spatial_conditions => ['sp_self_only()'],
    );

    my $cl_to_test1 = $bd->add_cluster_output (name => 'cl_for_tests');
    $cl_to_test1->run_analysis ();

    {
        my %hash = ('1:1' => 1, '1:2' => undef, '3:3' => 2);
        my $sp_cond = Biodiverse::SpatialConditions->new (conditions => '1', basedata_ref => $bd);
        my $ndarray = $sp_cond->_aggregate_hash_to_pdl(\%hash);
        my $as_list = $ndarray->unpdl;
        my $exp = [qw/1 BAD 0 0 0 0 0 0 0 0 0 0 2 0 0 0 0 0 0 0 0 0 0 0 0/];
        is ($as_list, $exp, '_aggregate_hash_to_pdl: undef to bad vals')
    }

    {
        #  should return undef due to $D
        my $cond = '$D < 200';
        my $sp_cond = Biodiverse::SpatialConditions->new (conditions => $cond, vectorise => 1);
        $sp_cond->get_conditions_parsed;
        my $listified = $sp_cond->vectorise_condition;
        my $exp = undef;
        is $listified, $exp, 'non-vectorisable condition returns undef';
    }

    {
        #  a relatively simple case to start
        my $cond = <<~'EOC'
            $self->sp_point_in_poly_shape(
               file => qq'C:\a \b \c.shp' ,
               buffer => 10
            )
            EOC
        ;
        my $sp_cond = Biodiverse::SpatialConditions->new (conditions => $cond, vectorise => 1);
        $sp_cond->get_conditions_parsed;
        my $listified = $sp_cond->vectorise_condition;

        my $exp = q{$self->vec_sp_point_in_poly_shape(file=>qq'C:\a \b \c.shp',buffer=>10)};
        is $listified, $exp, 'vectorise simple condition';
    }

    {
        #  the y in empty was triggering a quote-like match as the y/// operator
        my $cond = q{ $self->sp_group_not_empty() && $self->sp_in_label_range(label => '1') };
        my $sp_cond = Biodiverse::SpatialConditions->new (conditions => $cond, vectorise => 1);
        $sp_cond->get_conditions_parsed;
        my $listified = $sp_cond->vectorise_condition;

        my $exp = q{$self->_gland($self->vec_sp_group_not_empty(),$self->vec_sp_in_label_range(label=>'1'))};
        is $listified, $exp, 'vectorise simple condition';
    }

    {
        my $cond = <<~'EOC'
            !$self->sp_point_in_poly_shape(
               file => qq'C:\a \b \c.shp' ,
               buffer => 10
            )
            && $self->sp_get_spatial_output_list_value(output => 'test_1', index => 'ENDW_WE') >= 5.3
            ||
            !$self->sp_circle(radius => 6)
            && !$self->sp_square (size => 2)
            && $self->sp_circle(radius => 2)
            ;
            EOC
        ;
        my $sp_cond = Biodiverse::SpatialConditions->new (conditions => $cond, vectorise => 1);
        $sp_cond->get_conditions_parsed;
        my $listified = $sp_cond->vectorise_condition;

        my $exp =<<~'EOC'
            $self->_glor(
              $self->_gland(
                !$self->vec_sp_point_in_poly_shape(file=>qq'C:\a \b \c.shp',buffer=>10),
                $self->vec_sp_get_spatial_output_list_value((output=>'test_1',index=>'ENDW_WE'),ge=>5.3)
              ),
              $self->_gland(
                !$self->vec_sp_circle(radius=>6),
                !$self->vec_sp_square(size=>2),
                $self->vec_sp_circle(radius=>2)
              )
            );
            EOC
        ;
        $exp = join '', map {$_ =~ s/^\s+//r} split "[\r\n]+", $exp;
        is $listified, $exp, 'vectorise more complex condition';
    }

    my $cond_i = 0;

    #  now try to run some
    my @conditions = (
        q{sp_circle(radius => 2)},
        q{sp_circle(radius => 2, axes => [0])},
        q{sp_circle_cell(radius => 2)},
        q{sp_circle_cell(radius => 2, axes => [0])},
        q{sp_circle(radius => 2) || sp_self_only()},
        q{sp_circle(radius => 2) || sp_select_all()},
        q{sp_square(size => 2)},
        q{sp_square_cell(size => 2)},
        q{sp_block(size => 1.9)},  #  could use 2 but there was a bug in sp_block
        q{sp_block(size => 1.9, origin => 1)},
        q{sp_block(size => [1.9, undef])},
        q{sp_block(size => [1.9, 1.9])},
        q{sp_annulus(inner_radius => 1, outer_radius => 2.3)},
        q{sp_ellipse(minor_radius => 1, major_radius => 3)},
        q{sp_get_spatial_output_list_value(output => 'test_1', index => 'ENDW_WE') >= .12},
        q{sp_in_label_ancestor_range(label => '1', by_depth => 1, target => 1)},
        q{sp_in_label_ancestor_range(label => 'not_in_tree', by_depth => 1, target => 1)},
        q{sp_shape_of_label_range (label => '1')},
        q{sp_shape_of_label_ancestor_range (label => '1', by_depth => 1, target => 1)},
        #  defq twice - code below will run a defq for the first but not the second
        q{sp_spatial_output_passed_defq()},
        q{sp_spatial_output_passed_defq()},
        q{sp_spatial_output_passed_defq(element => '3:3')},
        q{sp_group_not_empty()},
        q{sp_group_not_empty(element => '3:3')},
        q{sp_in_label_range(label => '1') && sp_group_not_empty()},  #  there was a bug in sp_in_label_range
        q{sp_richness_greater_than (threshold => 2)},
        q{sp_richness_greater_than (threshold => 2, element => '3:3')},
        q{sp_redundancy_greater_than (threshold => 0.2)},
        q{sp_point_in_cluster (output => 'cl_for_tests', from_node => '17___')},
        q{sp_points_in_same_cluster(output => 'cl_for_tests', num_clusters => 4)},
    );
    push @conditions, <<~'EOC'
        sp_shape_of_label_ancestor_range (label => '1', by_depth => 1, target => 1)
        && !sp_shape_of_label_range (label => '1', buffer_dist => -2)
        EOC
    ;
    push @conditions, <<~'EOC'
        sp_get_spatial_output_list_value(output => 'test_1', index => 'ENDW_WE') >= .15
        && sp_in_label_range (label => '5')
        EOC
    ;
    push @conditions, <<~'EOC'
        #  glor
        sp_in_label_range (label => '5') || sp_in_label_range (label => '1')
        EOC
    ;
    push @conditions, <<~'EOC'
        #   gland glor
        sp_in_label_range (label => '1')
        && sp_in_label_range (label => '2')
        || sp_in_label_range (label => '5')
        EOC
    ;

    $bd->build_spatial_index(resolutions => [1,1]);

    my %seen;

    foreach my $cond (@conditions) {
        $cond_i++;

        diag $cond;

        my $defq = !$seen{$cond} && $cond =~ /sp_spatial_output_passed_defq/
            ? Biodiverse::SpatialConditions::DefQuery->new(conditions => '$y > 2')
            : undef;
        diag "Defq: $defq" if $defq;

        $seen{$cond}++;

        my %common_spcond_args = (
            conditions   => $cond,
            tree_ref     => $tree,
            basedata_ref => $bd,
        );
        my %common_sp_args = (
            calculations     => ['calc_element_lists_used'],
            definition_query => $defq,
        );

        my $name_pfx = length ($cond) >= 25 ? substr ($cond, 0, 25) : $cond;

        my $sp_cond = Biodiverse::SpatialConditions->new (
            %common_spcond_args,
            vectorise  => 0,
        );
        my $sp_novec = $bd->add_spatial_output(name => "nv $cond_i: $name_pfx");
        $sp_novec->run_analysis (
            %common_sp_args,
            spatial_conditions => [$sp_cond],
        );
        #  delete the sp or an optimisation means the vectorised version is not run
        $bd->delete_output(output => $sp_novec);

        $sp_cond = Biodiverse::SpatialConditions->new (
            %common_spcond_args,
            vectorise  => 1,
        );
        my $sp_vec = $bd->add_spatial_output(name => "v $cond_i: $name_pfx");
        $sp_vec->run_analysis (
            %common_sp_args,
            spatial_conditions => [$sp_cond],
        );
        my (%exp_hash, %got_hash);
        foreach my $element (sort $sp_novec->get_element_list) {
            $exp_hash{$element} = scalar $sp_novec->get_list_ref(element => $element, list => 'EL_LIST_SET1');
            $got_hash{$element} = scalar $sp_vec->get_list_ref(element => $element, list => 'EL_LIST_SET1');
        }
        is \%got_hash, \%exp_hash, "expected nbrs for $cond";
    }

    $bd->save;

}
