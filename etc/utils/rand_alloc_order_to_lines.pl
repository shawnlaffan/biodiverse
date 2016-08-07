#  utility script to to convert a label allocation order shapefile to a set of lines

use 5.016;

use Geo::ShapeFile;
use Geo::Shapefile::Writer;

my $in_file = shift;
my $out_file = shift;

my $shape_file = Geo::ShapeFile->new($in_file);

#  could add order as z
my $shp_writer = Geo::Shapefile::Writer->new( $out_file, 'POLYLINE',
    [ label => 'C', 100 ],
);

my %points;

#  read them in
foreach my $i (1 .. $shape_file->shapes()) {
    my $shape = $shape_file->get_shp_record($i); 
    my %db    = $shape_file->get_dbf_record($i);
    
    my $label = $db{KEY};
    my $alloc = $db{VALUE};
    
    #  won't handle -1 if we end up using it to mark swapped cases
    $points{$label}[$alloc] = $shape;
}

foreach my $label (sort keys %points) {
    my @vertices;
    foreach my $i (1 .. $#{$points{$label}}) {
        my $shape = $points{$label}[$i];
        my $points = $shape->points;  #  assuming only one part and one point
        push @vertices, [$points->[0]->X, $points->[0]->Y]; 
    }
    $shp_writer->add_shape ([\@vertices], {label => $label}); 
}

$shp_writer->finalize;
