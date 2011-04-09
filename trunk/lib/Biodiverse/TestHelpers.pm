#  helper functions for testing
package Biodiverse::TestHelpers;

use strict;
use warnings;

our $VERSION = '0.16';

use File::Temp;

use Exporter::Easy (
    TAGS => [
        basedata => [
            qw(
                get_basedata_import_data_file
                get_basedata_test_data
                get_basedata_object
            ),
        ],
        element_properties => [
            qw (
                get_element_properties_test_data
            )
        ],
    ],
);


sub get_basedata_import_data_file {
    my %args = @_;

    my $tmp_obj = File::Temp->new;
    my $ep_f = $tmp_obj->filename;
    print $tmp_obj get_basedata_test_data(@_);
    $tmp_obj -> close;

    return $tmp_obj;
}

sub get_basedata_test_data {
    my %args = (
        x_spacing => 1,
        y_spacing => 1,
        x_max     => 100,
        y_max     => 100,
        x_min     => 1,
        y_min     => 1,
        count     => 1,
        @_,
    );

    my $count = $args{count} || 0;

    my $data;
    $data .= "label,x,y,count\n";
    foreach my $i ($args{x_min} .. $args{x_max}) {
        my $ii = $i * $args{x_spacing};
        foreach my $j ($args{y_min} .. $args{y_max}) {
            my $jj = $j * $args{y_spacing};
            $data .= "$i"."_$j,$ii,$jj,$count\n";
        }
    }

    return $data;
}

sub get_basedata_object {
    my %args = @_;

    my $bd_f = get_basedata_import_data_file(@_);

    print "Temp file is $bd_f\n";

    my $bd = Biodiverse::BaseData->new(
        CELL_SIZES => $args{CELL_SIZES},
    );
    $bd->import_data(
        input_files   => [$bd_f],
        group_columns => [1, 2],
        label_columns => [0],
    );
    
    return $bd;
}


sub get_element_properties_test_data {

    my $data = <<'END_DATA'
rec_num,genus,species,new_genus,new_species,range,sample_count,num
1,Genus,sp1,Genus,sp2,,1
10,Genus,sp18,Genus,sp2,,1
2000,Genus,sp2,,,200,1000,2
END_DATA
  ;

}



__END__


=head1 NAME

Biodiverse::TestHelpers - helper functions for Biodiverse tests.

=head1 SYNOPSIS

  use Biodiverse::TestHelpers;

=head1 DESCRIPTION

Helper functions for Biodiverse tests.  Mostly provides data.

=head1 METHODS

=over 4

=item get_element_properties_test_data();

Element properties table data.

=back

=head1 AUTHOR

Shawn Laffan

=head1 LICENSE

LGPL

=head1 SEE ALSO

See http://www.purl.org/biodiverse for more details.

