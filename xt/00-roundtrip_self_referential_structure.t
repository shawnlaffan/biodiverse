#  Tests for self referential tree save and reload.
#  Assures us that the data can be serialised, saved out and then reloaded.

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };

use Scalar::Util qw /blessed unweaken weaken/;
use Devel::Refcount qw /refcount/;

use Data::Dumper;
use Sereal ();
use Storable ();
use YAML::XS ();

#  YAML::Syck needs patching to work on x64 Windows
#  - https://github.com/toddr/YAML-Syck/pull/9
#use YAML::Syck ();  


local $| = 1;

use Test::More;
use Test::Exception;

if (0) {
    # dump the basic data structure (weak refs, no blessing, single root ref)
    # This is reproduced after the __END__ token
    local $Data::Dumper::Purity    = 1;
    local $Data::Dumper::Terse     = 1;
    local $Data::Dumper::Sortkeys  = 1;
    local $Data::Dumper::Indent    = 1;
    local $Data::Dumper::Quotekeys = 0;
    print Dumper get_data();
}


#  Child to parent refs are weak, root node is stored once in the hash
#  Fails on x64 Strawberry perls 5.16.3, 5.18.4, 5.20.1
test_save_and_reload ();

#  Child to parent refs are weak, but we store the root node twice in the hash
#  (second time is in the "TREE_BY_NAME" subhash)
#  Fails on x64 Strawberry perls 5.16.3, passes on 5.18.4, 5.20.1
test_save_and_reload (store_root_by_name => 1);

#  Try with blessed nodes (trying to trigger a YAML::XS problem with this data)
#  -- skip to avoid further cluttering the output --
#test_save_and_reload (store_root_by_name => 1, bless_nodes => 1);


#  child to parent refs are strong
#  Should pass
test_save_and_reload (no_weaken_refs => 1);


done_testing();

exit;


sub get_data {
    my %args = @_;

    #diag $];
    my $classname = 'Meaningless::ClassName';

    my @children;

    my $root = {
        name     => 'root',
        children => \@children,
    };

    if ($args{bless_nodes}) {
        bless $root, $classname;
    }

    my %hash = (
        TREE => $root,
        TREE_BY_NAME => {},
    );

    if ($args{store_root_by_name}) {
        $hash{TREE_BY_NAME}{root} = $root;
    }

    foreach my $i (0 .. 1) {
        my $child = {
            PARENT => $root,
            NAME => $i,
        };

        if ($args{bless_nodes}) {
            bless $child, $classname;
        }

        if (!$args{no_weaken_refs}) {
            weaken $child->{PARENT};
        }

        push @children, $child;
        #  store it in the by-name cache
        $hash{TREE_BY_NAME}{$i} = $child;
    }

    return \%hash;
}


sub test_save_and_reload {
    my %args = @_;
    my $data = get_data (%args);

    #diag '=== ARGS ARE:  ' . join ' ', %args;

    my $context_text;
    $context_text .= $args{no_weaken} ? 'not weakened' : 'weakened';
    $context_text .= $args{store_root_by_name}
        ? ', extra root ref stored'
        : ', extra root ref not stored';
    $context_text .= $args{bless_nodes}
        ? ', blessed nodes'
        : ', not blessed nodes';

    #diag "Working on Sereal";

    my $encoder = Sereal::Encoder->new;
    my $decoder = Sereal::Decoder->new;
    my ($encoded_data, $decoded_data);

    lives_ok {
        $encoded_data = $encoder->encode($data)
    } "Encoded using Sereal, $context_text";

    #  no point testing if serialisation failed
    if ($encoded_data) {
        lives_ok {
            $decoder->decode ($encoded_data, $decoded_data);
        } "Decoded using Sereal, $context_text";
    
        is_deeply (
            $decoded_data,
            $data,
            "Data structures match for Sereal, $context_text",
        );
    }

    #  Try YAML::XS - we get undef root nodes ($h{TREE} = undef)
    #  using DumpFile/LoadFile for the full blown original case,
    #  but it seems not to occur with this cut-down case.
    #  My (evidence free) speculation is that it is to do with objects.
    #  Does not happen with YAML::Syck.

    #diag "Working on YAML::XS";

    lives_ok {
        $encoded_data = YAML::XS::Dump $data;
    } "Encoded using YAML::XS, $context_text";

    lives_ok {
        $decoded_data = YAML::XS::Load $encoded_data;
    } "Decoded using YAML::XS, $context_text";

    is_deeply (
        $decoded_data,
        $data,
        "Data structures match for YAML::XS, $context_text",
    );

    #diag 'try YAML DumpFile and LoadFile';
    
    my $fname = 'dump.yml';
    
    lives_ok {
        YAML::XS::DumpFile ($fname, $data);
    } "Dumped to file using YAML::XS, $context_text";

    lives_ok {
        $decoded_data = YAML::XS::LoadFile ($fname);
    } "Loaded from file using YAML::XS, $context_text";

    is_deeply (
        $decoded_data,
        $data,
        "Data structures match for YAML::XS from file, $context_text",
    );

    #diag 'try Storable';

    lives_ok {
        $encoded_data = Storable::freeze ($data);
    } "Frozen using Storable, $context_text";

    lives_ok {
        $decoded_data = Storable::thaw ($encoded_data);
    } "Thawed using Storable, $context_text";

    is_deeply (
        $decoded_data,
        $data,
        "Data structures match for Storable freeze/thaw, $context_text",
    );

}


1;

__END__


Data::Dumper::Dumper output of the simplest data structure looks like this:


$VAR1 = {
  TREE => {
    children => [
      {
        NAME => 0,
        PARENT => {}
      },
      {
        NAME => 1,
        PARENT => {}
      }
    ],
    name => 'root'
  },
  TREE_BY_NAME => {
    '0' => {},
    '1' => {}
  }
};
$VAR1->{TREE}{children}[0]{PARENT} = $VAR1->{TREE};
$VAR1->{TREE}{children}[1]{PARENT} = $VAR1->{TREE};
$VAR1->{TREE_BY_NAME}{'0'} = $VAR1->{TREE}{children}[0];
$VAR1->{TREE_BY_NAME}{'1'} = $VAR1->{TREE}{children}[1];
