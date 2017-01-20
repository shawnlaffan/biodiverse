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
# e.g. "color:#ffffff,foo:bar" etc.
sub decode_bootstrap_block {
    my ($self, %args) = @_;
    my $input = $args{ raw_bootstrap };

    return if !$input;
    
    # get rid of leading and trailing square brackets 
    $input =~ s/^\[//;
    $input =~ s/\[$//;

    $input = "{".$input."}";
    
    # fix up unquoted key/value pairs i.e. add quotes because the json
    # decoder doesn't work without them.
    $input = $self->fix_up_unquoted_bootstrap_block( block => $input );

    my $decoded_hash = decode_json $input;

    foreach my $key (keys %$decoded_hash) {
        $self->set_value( key => $key, value => $decoded_hash->{$key} );
        #print "Setting $key to be $decoded_hash->{$key}\n";
    }    
    
}

# returns the values in this object formatted so they are ready to be
# written straight to a nexus/newick file.
# e.g. returns "["color":"#ffffff","foo":"bar"]" etc.
# excluded_keys is an array ref of keys not to include in the block
sub encode_bootstrap_block {
    my ($self, %args) = @_;
    my %boot_values = %$self;
    
    if($args{exclusions}) {
        my @excluded_keys = @{$args{exclusions}};
        # print "Exclusions are: @excluded_keys\n";
        foreach my $exclusion (@excluded_keys) {
            delete $boot_values{$exclusion};
        }
    }
    
    my $json_string = encode_json \%boot_values;

    # the json encoder uses { and } to delimit data, but bootstrap
    # block uses [ and ].

    # will replace first and last use of { and } respectively.
    $json_string =~ s/\{/\[/;
    $json_string = scalar reverse $json_string; # cheeky
    $json_string =~ s/\}/\]/;
    $json_string = scalar reverse $json_string;

    # if we have nothing in this block, we probably don't want to
    # write out [], makes the nexus file ugly.
    return $json_string eq "[]" ? "" : $json_string;
}



# add quotes to unquoted json blocks. Needed for the json decoder
# e.g. {key:value,key2:value2} goes to {"key":"value","key2":"value2"}
sub fix_up_unquoted_bootstrap_block {
    my ($self, %args) = @_;
    my $block = $args{block};

    # Basic idea is to find a block starting and ending with '{' or
    # ','. Take what is inside this block, and find a 'key' and
    # 'value' separated by a ':'. If these aren't already quoted, put
    # quotes around them. We need to do this loop because the final
    # comma of one block is the starting comma of the next block. 
        
    my $old = "";
    while(!($old eq $block)) {
        $old = $block;
        # crazy regex here
        $block =~ s/([\{,])([^\"]*?)\:([^\"]*?)([\},])/$1\"$2\":\"$3\"$4/;
    }
    return $block;
}


1;
