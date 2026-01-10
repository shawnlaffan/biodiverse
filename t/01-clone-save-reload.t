#  Tests for object clone, save and reload.
#  Assures us that the data can be serialised, saved out and then reloaded
#  validly.

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };

use Scalar::Util qw /blessed/;

#use Test::Lib;
use rlib;
use Biodiverse::Config;

local $| = 1;

use Test2::V0;
#use Test::Exception;

use Biodiverse::BaseData;
use Biodiverse::ElementProperties;
use Biodiverse::TestHelpers qw /:basedata :matrix :tree :utils/;
use Path::Tiny qw/path/;

exit main( @ARGV );

sub main {
    my @args = @_;
    
    my $bd = get_basedata_object_for_save_and_reload_tests();

    my %objects_to_test = (
        basedata => $bd,
        matrix   => get_matrix_object_from_sample_data(),
        tree     => get_tree_object_from_sample_data(),
    );

    if (@args) {
        for my $name (@args) {
            die "No test method $name\n"
              if not my $func = (__PACKAGE__->can( 'test_' . $name ) or __PACKAGE__->can( $name ));
            foreach my $type (sort keys %objects_to_test) {
                my $object = $objects_to_test{$type};
                $func->($object);
            }
        }
        done_testing;
        return 0;
    }

    test_vcache();

    test_save_and_reload_no_suffix ($bd);
    test_save_and_reload_bung_file ($bd);

    #  do we get a consistent clone/saved version?
    foreach my $type (sort keys %objects_to_test) {
        #diag "Testing $type\n";
        my $object = $objects_to_test{$type};
        test_save_and_reload_storable ($object);
        test_save_and_reload ($object);
        test_clone ($object);
        test_save_and_reload_non_existent_folder ($object);
        test_save_and_reload_yaml ($object);
    }

    done_testing;
    return 0;
}


sub get_basedata_object_for_save_and_reload_tests {
    #  generate one basedata for all tests
    my @cell_sizes = (10, 10);
    my $args = {
        CELL_SIZES => [@cell_sizes],
        name       => 'Test save, reload and clone',
        x_spacing => 1,
        y_spacing => 1,
        x_max     => 13,
        y_max     => 13,
        x_min     => 1,
        y_min     => 1,
        count     => 1,
    };
    my $bd = eval {
        get_basedata_object ( %$args, );
    };
    my $error = $EVAL_ERROR;

    $bd->build_spatial_index (resolutions => [@cell_sizes]);
    #$bd->save_to (filename => 'xx.bdy');

    my $cond = ['sp_circle (radius => 2.5)', 'sp_circle (radius => 5)'];
    my $defq = '$y > 6';

    my $sp = $bd->add_spatial_output (
        name => 'Spatial',
    );
    $sp->run_analysis(
        spatial_conditions => $cond,
        definition_query   => $defq,
        calculations       => ['calc_richness'],
    );
    
    my $cl = $bd->add_cluster_output (
        name => 'Cluster',
    );
    $cl->run_analysis(
        definition_query => $defq,
    );
    
    my $rand = $bd->add_randomisation_output (
        name => 'Rand',
    );
    $rand->run_analysis (
        function   => 'rand_nochange',
        iterations => 1,
    );

    return $bd;
}

sub test_save_and_reload {
    my $object = shift;
    my %args = @_;

    $args{suffix} //= $object->get_file_suffix;
    my $suffix = $args{suffix};

    my $class = blessed $object;

    my $fname = get_temp_file_path("biodiverse.$suffix");
    my $suffix_feedback = $suffix || 'a null string';

    ok (
        lives {
            $fname = $object->save_to (filename => $fname, %args)
        },
        "Saved to file, suffix is $suffix_feedback"
    ) or note ($@);

    my $new_object;
    my %load_args = $suffix =~ /b[dtm]y/ ? (loadblessed => 1) : ();
    if ($suffix =~ /s$/) {
        ok (
            lives {
                $new_object = $class->new (file => $fname, %load_args)
            },
            "Opened without exception thrown, suffix is $suffix_feedback"
        ) or note ($@);

        #  if we are using storable then check it is set as the last serialisation format
        if (($args{method} // '') =~ /storable/) {
            is ($new_object->get_last_file_serialisation_format,
                'storable',
                'set last serialisation format parameter correctly'
            );
        }
    }
    elsif ($suffix =~ /s$/) {
        ok (
            dies {
                $new_object = $class->new (file => $fname, %load_args)
            },
            "File with YAML suffix throws exception"
        ) or note ($@);
    }

}

sub test_clone {
    my $object = shift;

    my $new_object;
    ok (
        lives { $new_object = $object->clone },
        'Cloned without exception thrown'
    ) or note ($@);
    #  cyclic ref issues with Test2
    if (not blessed ($object) =~ /BaseData|Tree/) {
        is ($new_object, $object, "Cloned object matches");
    }
}

sub test_save_and_reload_no_suffix {
    my $object = shift;
    test_save_and_reload ($object, suffix => '');
}

sub test_save_and_reload_yaml {
    my $object = shift;
    test_save_and_reload ($object, suffix => $object->get_file_suffix_yaml);
}

sub test_save_and_reload_storable {
    my $object = shift;
    test_save_and_reload ($object, method => 'save_to_storable');
}

sub test_save_and_reload_non_existent_folder {
    my $object = shift;
    my %args = @_;

    $args{suffix} //= $object->get_file_suffix;
    my $suffix = $args{suffix};

    my $class = blessed $object;

    my $fname = get_temp_file_path("biodiverse.$suffix");
    $fname = path($fname, 'fnargle' . (int rand() * 1000));

    my $suffix_feedback = $suffix || 'a null string';

    ok (
        dies {
            $fname = $object->save_to (filename => $fname, %args)
        },
        "Did not save to file in non-existent directory, suffix is $suffix_feedback"
    ) or note ($@);
    
}

sub test_save_and_reload_bung_file {
    my $object = shift;

    state $iter;
    $iter++;
    my $fname = get_temp_file_path("biodiverse$iter.bds");
    open my $fh, '>', $fname
      or die "Unable to open $fname, $!";
    print {$fh} "blahdeblahblahblah\n";
    $fh->close;
    undef $fh;
    
    ok (
        dies {$object->load_file (file => $fname)},
        "Error raised on loading non-conformant file"
    ) or note ($@);
}

sub test_vcache {
    use Biodiverse::VCache;

    my $vcache = Biodiverse::VCache->new;

    my $cache_name = 'TEST_CACHE_NAME';

    $vcache->get_cached_value_dor_set_default_href($cache_name);

    my $encoder = Sereal::Encoder->new({
        undef_unknown    => 1, #  strip any code refs
        freeze_callbacks => 1,
    });

    my $serialised;
    my $decoder = Sereal::Decoder->new();
    eval {
        $decoder->decode ($encoder->encode($vcache), $serialised);
        1;
    };
    die $@ if $@;

    isnt $serialised, $vcache;
    is [keys %$serialised], [], 'serialised object has no keys';

    my $tree = Biodiverse::Tree->new (NAME => 'for testing');
    my $vcache2 = $tree->get_volatile_cache;
    ok $tree->{_vcache}, 'object has the vcache';
    $tree->clear_volatile_cache;
    ok !$tree->{_vcache}, 'object no longer has the vcache';

    #  now check a slightly deeper serialisation
    $vcache2 = $tree->get_volatile_cache;
    $vcache2->get_cached_value_dor_set_default_href($cache_name);
    is [keys %{$tree->{_vcache}{_cache}}], [$cache_name], 'tree object has expected vcache keys';
    $decoder->decode ($encoder->encode($tree), $serialised);
    is [keys %{$serialised->{_vcache}}], [], 'serialised object has no vcache';

}

1;
