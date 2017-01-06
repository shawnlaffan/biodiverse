package Biodiverse::ExportRemap;

use 5.010;
use strict;
use warnings;

our $VERSION = '1.99_006';

use English( -no_match_vars );

use Carp;


use Biodiverse::GUI::Export qw /:all/;
use Biodiverse::GUI::YesNoCancel;


sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}


# given a hash mapping from one set of labels to another, exports them
# to a csv file.
sub export_remap {
    my ($self, %args) = @_;
    my $remap = $args{remap};
    

    # choose the filepath to export to
    my $gui = Biodiverse::GUI::GUIManager->instance;
    
    my $results = Biodiverse::GUI::Export::choose_file_location_dialog (
        gui => $gui,
        params => undef,
        selected_format => "CSV",
        );

    return if (!$results->{success});

    my $chooser = $results->{chooser};
    my $parameters_table = $results->{param_table};
    my $extractors = $results->{extractors};
    my $dlg = $results->{dlg};
    
    my $filename = $chooser->get_filename();
    $filename = Path::Class::File->new($filename)->stringify;  #  normalise the file name

    say "Found export filename $filename";

    if ( (not -e $filename)
        || Biodiverse::GUI::YesNoCancel->run({
            header => "Overwrite file $filename?"})
                eq 'yes'
        ) {

        # get the actual contents of the file
        my $content_string 
        = $self->build_csv_string_from_remap_hash (remap => $remap);

        
        $self->export_csv(
            filename => $filename,
            content => $content_string,
            )
    }
    else {
        goto RUN_DIALOG; # my first ever goto!
    }

    
    $dlg->destroy;
    $gui->activate_keyboard_snooper (1);

}


# given a remap hash, build a string which will be the contents of a
# csv manual remap file.
sub build_csv_string_from_remap_hash {
    my ($self, %args) = @_;
    my %remap = %{$args{remap}};


    my @lines = ();

    # keep track of how many fields we use so we know what to do with headers
    my $max_columns_used = 1;

    # TODO don't assume that there is an equal number of colons in
    # every label. Fairly safe assumption, but not entirely
    # general. To fix this, add empty fields e.g. field,,, for labels
    # missing colons.
    foreach my $key (keys %remap) {
        # problem: we aren't allowed to have ':'s in label names.
        # so split labels with them into multiple columns.
        my @output_fields = split(":", $remap{$key});

        if(scalar(@output_fields) > $max_columns_used) {
            $max_columns_used = scalar(@output_fields);
        }

        my $output_string = join(',', @output_fields);
        
        push @lines, "'$key',$output_string,1";
    }

    my @headers = ("original_label");
    foreach my $i (1..$max_columns_used) {
        push @headers, "remapped_column$i";
    }
    push @headers, "include";
    my $header_string = join(",", @headers);

    unshift @lines, $header_string;
    
    
    return join("\n", @lines);
}


# given some content and a filepath (assumes we've already checked
# whether it's ok to overwrite an existing file) writes the content to
# the file.
sub export_csv {
    my ($self, %args) = @_;
    my $file = $args{filename};
    my $content = $args{content};

    say "[ExportRemap] writing to $file";

    open( my $fh, '>', $file ) 
        || croak "Could not open file '$file' for writing\n";

    print {$fh} $content;

    $fh->close;
}

1;
