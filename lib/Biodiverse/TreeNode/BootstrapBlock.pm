package Biodiverse::TreeNode::BootstrapBlock;

use strict;
use warnings;
use Carp;

use Cpanel::JSON::XS;
use Data::Structure::Util qw( unbless );


our $VERSION = '1.99_006';

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

# add or update a key:value pair to this object.
sub set_value {
    my ($self, %args) = @_;
    my $key    =   $args{ key   };
    my $value  =   $args{ value };
    $self->{$key} = $value;
    return $value;
}

# given a key, get value. returns undef if the value hasn't been set.
sub get_value {
    my ($self, %args) = @_;
    my $key = $args{ key };
    return $self->{$key};
}

# removes given key from the bootstrap block
sub delete_value {
    my ($self, %args) = @_;
    my $key = $args{ key };
    delete $self->{$key};
}

# given a boostrap block as it was imported, populate this object.
# e.g. "[color:#ffffff,foo:bar]" etc.
sub decode_bootstrap_block {
    my ($self, %args) = @_;
    my $input = $args{ raw_bootstrap };

    # will replace first and last use of [ and ] respectively.
    $input =~ s/\[/\{/;
    $input = scalar reverse $input; # cheeky
    $input =~ s/\]/\}/;
    $input = scalar reverse $input;


    # TODO Make this deal with unquoted bootstrap blocks: currently fails.
    
    my $decoded_hash = decode_json $input;

    foreach my $key (keys %$decoded_hash) {
        $self->set_value( key => $key, value => $decoded_hash->{$key} );
    }    
    
}

# returns the values in this object formatted so they are ready to be
# written straight to a nexus/newick file.
# e.g. returns "["color":"#ffffff","foo":"bar"]" etc.
# excluded_keys is an array ref of keys not to include in the block
sub encode_bootstrap_block {
    my ($self, %args) = @_;
    my @excluded_keys = @{$args{exclusions}};

    my %boot_values = %{unbless($self)};
    delete $boot_values{@excluded_keys};
        
    my $json_string = encode_json \%boot_values;

    # the json encoder uses { and } to delimit data, but bootstrap
    # block uses [ and ].

    # will replace first and last use of { and } respectively.
    $json_string =~ s/\{/\[/;
    $json_string = scalar reverse $json_string; # cheeky
    $json_string =~ s/\}/\]/;
    $json_string = scalar reverse $json_string;
    
    return $json_string;
}


1;
