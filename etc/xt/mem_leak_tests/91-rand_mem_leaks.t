use strict;
use warnings;

use File::Temp;

local $| = 1;

use constant HAS_LEAKTRACE => eval{ require Test::LeakTrace };

use Test::More;

#  skip until test gets faster or the root problem is fixed
#plan skip_all => "This test takes too long and the bug isn't fixed yet";

plan HAS_LEAKTRACE ? (tests => 2) : (skip_all => 'require Test::LeakTrace');

use Test::LeakTrace;

#use Data::Structure::Util qw /has_circular_ref get_refs/;
use FindBin qw { $Bin };

use Biodiverse::Config;
require Biodiverse::BaseData;
require Biodiverse::Randomise;

my $data_dir = File::Spec->catfile( $Bin, q{..}, 'data' );
print "Data dir is $data_dir\n";


#leaktrace {my $bd = Biodiverse::BaseData->new()} -verbose;
#leaktrace {
#    my $bd = Biodiverse::BaseData->new();
#    $bd->add_randomisation_output (name => 'xx');
#};
#my $bd = Biodiverse::BaseData->new();

#leaktrace {
#    my $r = Biodiverse::Randomise->new;
#};

my $in_file = File::Spec->catfile( $data_dir, 'Example_site_data.csv' );
my $bd = Biodiverse::BaseData -> new (
    NAME => 'test',
);
$bd->set_param(CELL_SIZES => [500000, 500000]);
$bd->import_data (
    input_files   => [$in_file],
    label_columns => [1, 2],
    group_columns => [3, 4],
);
undef $in_file;


my $descr = 'load, run, delete';
diag ($descr);
#no_leaks_ok {
my @leaked = leaked_info {
    my $r = $bd->add_randomisation_output (
        name     => 'csr',
        FUNCTION => 'rand_nochange',
    );

    $r->run_analysis (iterations => 1);

    $bd->delete_output (output => $r);

    undef $r;
    undef $bd;
};
#} $descr;

use Data::Dump qw {pp};
pp (\@leaked);



$descr = 'load, run, save, delete';
diag ($descr);
SKIP:
{
    skip "skipping $descr, it takes too long", 1;

    no_leaks_ok {
        
    
        my $in_file = File::Spec->catfile( $data_dir, 'Example_site_data.csv' );
        my $bd = Biodiverse::BaseData -> new (
            NAME => 'test',
        );
        $bd->set_param(CELL_SIZES => [500000, 500000]);
        $bd->import_data (
            input_files   => [$in_file],
            label_columns => [1, 2],
            group_columns => [3, 4],
        );
    
        my $r = $bd -> add_randomisation_output (
            name     => 'csr',
            FUNCTION => 'rand_structured',
        );
    
        $r -> run_analysis;
    
        my $fh = File::Temp->new(SUFFIX => '.bds' );
        my $fname = $fh->filename;
        $fh = undef;
    
        $bd->save ( filename=> $fname );
    
        $bd->delete_output (output => $r);
        
        undef $r;
        undef $bd;
        unlink $fname;
    
    } $descr;
}

$descr = 'load, save, load, run, delete';
diag ($descr);
SKIP:
{
    skip "skipping $descr, it takes too long", 1;  # need to use a smaller file

    no_leaks_ok {

            my $in_file = File::Spec->catfile( $data_dir, 'Example_site_data.csv' );
            my $bd = Biodiverse::BaseData -> new (
                NAME => 'test',
            );
            $bd->set_param(CELL_SIZES => [500000, 500000]);
            $bd->import_data (
                input_files   => [$in_file],
                label_columns => [1, 2],
                group_columns => [3, 4],
            );
    
            my $fh = File::Temp->new(SUFFIX => '.bds' );
            my $fname = $fh->filename;
            $fh = undef;
    
            $bd->save ( filename=> $fname );
    
            $bd = Biodiverse::BaseData->new( file => $fname );
            
            my $r = $bd -> add_randomisation_output (
                name     => 'csr',
                FUNCTION => 'rand_structured',
            );
    
            $r -> run_analysis;
    
            $bd->delete_output (output => $r);
            
            undef $r;
            undef $bd;
    
            unlink $fname;
    
    } $descr;
}
