#  Tests for basedata import
#  Need to add tests for the number of elements returned,
#  amongst the myriad of other things that a basedata object does.

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };
use Data::Dumper;
use List::Util 1.45 qw /uniq/;
use Test::Lib;
use POSIX qw /floor/;
use rlib;

use Data::Section::Simple qw(
    get_data_section
);
use Biodiverse::Config;

local $| = 1;

use Test2::V0;

use Biodiverse::BaseData;
use Biodiverse::ElementProperties;
use Biodiverse::TestHelpers qw /:basedata/;

use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__); 
my @test_subs = grep {$_ =~ 'main::test_'} $obj->functions();


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

    foreach my $sub (@test_subs) {
        no strict 'refs';
        $sub->();
    }

    done_testing;
    return 0;
}


sub test_import_unicode_name_bd {
    use utf8;
    use FindBin;
    my $fname = 'años.txt';
    my $dir = "$FindBin::Bin/data";
    my $bd = Biodiverse::BaseData->new(
        NAME => $fname,
        CELL_SIZES => [100000, 100000],
    );
    
    ok (lives {
        $bd->import_data (
                input_files   => ["$dir/años.txt"],
                group_columns => [3,4],
                label_columns => [1,2],
            )
        },
        'imported csv data in file with unicode name without an exception'
    ) or note $@;

}

sub test_import_unicode_name_mx {
    use utf8;
    use FindBin;
    my $dir = "$FindBin::Bin/data";

    #   a matrix
    use Biodiverse::Matrix;
    my $fname = "$dir/años_mx_sparse.txt";
    my $mx = Biodiverse::Matrix->new (name => $fname);

    ok (
        lives {
            $mx->import_data_sparse (
                file => $fname,
                label_row_columns => [0],
                label_col_columns => [1],
                value_column      =>  2,
            );
        },
        'imported sparse matrix csv data in file with unicode name without an exception'
    ) or note $@;
    
    $fname = "$dir/años_mx.txt";
    $mx = Biodiverse::Matrix->new (name => $fname);

    ok (lives {
            $mx->import_data (
                file => $fname,
            );
        },
        'imported matrix csv data in file with unicode name without an exception'
    );

}
