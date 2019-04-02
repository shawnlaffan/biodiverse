package Biodiverse::TreeNode::BootstrapBlock;

use 5.022;
use strict;
use warnings;
use Carp;

#  avoid redefined warnings due to
#  https://github.com/rurban/Cpanel-JSON-XS/issues/65
use JSON::PP ();

use JSON::MaybeXS;
use Data::Structure::Util qw( unbless );
use Ref::Util qw /is_arrayref is_hashref/;

use parent qw /Biodiverse::Common/;

our $VERSION = '2.99_002';

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

# add or update a key:value pair to this object.
sub set_value {
    my ($self, %args) = @_;
    my $key    =   $args{ key   }
      // croak "key arg not passed\n";
    my $value  =   $args{ value };
    $self->{_data}{$key} = $value;
    return $value;
}

sub set_value_aa {
    my ($self, $key, $value) = @_;
    $self->{_data}{$key} = $value;
    return $value;
}

# given a key, get value. returns undef if the value hasn't been set.
sub get_value {
    my ($self, %args) = @_;
    my $key = $args{ key };
    return $self->{_data}{$key};
}

# removes given key from the bootstrap block
sub delete_value {
    my ($self, %args) = @_;
    my $key = $args{ key };
    delete $self->{_data}{$key};
}

sub delete_value_aa {
    my ($self, $key) = @_;
    delete $self->{_data}{$key};
}

sub get_data {
    my $self = shift;
    my $data =  $self->{_data} //= {};
    return wantarray ? %$data : $data;
}

sub clear_data {
    my $self = shift;
    $self->{_data} = {};
}

sub set_colour {
    my ($self, %args) = @_;
    $self->{colour} = $args{colour};
}

sub set_colour_aa {
    my ($self, $colour) = @_;
    $self->{colour} = $colour;
}

sub get_colour {
    my $self = shift;
    return $self->{colour};
}

sub get_colour_8bit_rgb {
    my $self = shift;
    return $self->reformat_colour_spec (colour => $self->{colour});
}

sub delete_colour {
    my $self= shift;
    delete $self->{colour};
}

sub decode_bootstrap_block {
    my $self = shift;
    return $self->decode (@_);
}

# given a boostrap block as it was imported, populate this object.
# e.g. "color:#ffffff,foo:bar" etc.
sub decode {
    my ($self, %args) = @_;
    my $input = $args{ raw_bootstrap };

    return if !$input;
    
    # get rid of leading and trailing square brackets 
    $input =~ s/^\[//;
    $input =~ s/\]$//;

    $input = '{' . $input . '}';
    
    # fix up unquoted key/value pairs i.e. add quotes because the json
    # decoder doesn't work without them.
    $input = $self->fix_up_unquoted_bootstrap_block( block => $input );

    my $decoded_hash = decode_json $input;

    foreach my $key (keys %$decoded_hash) {
        if ($key eq '!color') {
            $self->set_colour_aa ($decoded_hash->{$key});
        }
        else {
            $self->set_value_aa( $key => $decoded_hash->{$key} );
        }
    }    
    
}

sub encode_bootstrap_block {
    my $self = shift;
    return $self->encode (@_);
}

# returns the values in this object formatted so they are ready to be
# written straight to a nexus file.
# e.g. returns [&!color="#ffffff","foo"="bar"] etc.
# excluded_keys is an array ref of keys not to include in the block
sub encode {
    my ($self, %args) = @_;
    my %boot_values = $self->get_data;

    my @bootstrap_strings;
    foreach my $boot_key (sort keys %boot_values) {
        my $value = $boot_values{$boot_key};
        if (is_arrayref($value)) {
            my $formatted = join (',', map {$boot_key . '__' . $_ . '=' . $value->[$_]} keys @$value);
            push @bootstrap_strings, $formatted;
        }
        elsif (is_hashref ($value)) {
            #  make them key=value pairs,
            #  with list name as a prefix on each key
            #  to ensure uniqueness if multiple lists are one day attached
            my @arr
              = map {$boot_key . '__' . $_ . '=' . $value->{$_}}
                sort keys %$value;
            my $formatted = join (',', @arr);
            push @bootstrap_strings, $formatted;
        }
        else {
            push @bootstrap_strings, ($boot_key . '=' . $value);
        }
    }
    if ($args{include_colour}) {
        my $colour = $self->get_colour;
        if (defined $colour) {
            #  should test if the value looks like a valid colour value
            $colour = $self->reformat_colour_spec (colour => $colour);
            unshift @bootstrap_strings, "!color=" . $colour;
        }
    }

    # if we have nothing in this block, we probably don't want to
    # write out [], as it makes the nexus file ugly.
    return '' if !scalar @bootstrap_strings;

    my $bootstrap_string = '[&' . join(",", @bootstrap_strings) . ']';

    return $bootstrap_string;
}


sub reformat_colour_spec {
    my ($self, %args) = @_;
    my $colour = $args{colour};

    #  only worry about #RRRRGGGGBBBB
    return $colour if !defined $colour || $colour !~ /^#[a-fA-F\d]{12}$/;

    # the way colours are selected in the dendrogram only allows for 2
    # hex digits for each color. Unless this is change, we don't lose
    # precision by truncating two of the four digits for each colour
    # that are stored in the colour ref.
    my $proper_form_string = "#";
    my @wanted_indices = (1, 2, 5, 6, 9, 10);
    foreach my $index (@wanted_indices) {
        $proper_form_string .= substr($colour, $index, 1);
    }

    return $proper_form_string;
}

# add quotes to unquoted json blocks. Needed for the json decoder
# e.g. {&key=value,key2=value2} goes to {"key":"value","key2":"value2"}
sub fix_up_unquoted_bootstrap_block {
    my ($self, %args) = @_;
    my $block = $args{block};

    # Basic idea is to find a block starting and ending with '{' or
    # ','. Take what is inside this block, and find a 'key' and
    # 'value' separated by '='. If these aren't already quoted, put
    # quotes around them. We need to do this loop because the final
    # comma of one block is the starting comma of the next block. 

    # first remove the leading ampersand
    $block =~ s/\{\&/{/;
    my $old = "";
    while($old ne $block) {
        $old = $block;
        # crazy regex here
        $block =~ s/([\{,])([^\"]*?)\=([^\"]*?)([\},])/$1\"$2\":\"$3\"$4/;
    }
    
    # also replace equals signs between quotes with colons so we can
    # use a json decoder.
    $block =~ s/\"=\"/\":\"/g;
    
    return $block;
}


# pass in a string, no bootstrap block value with this string as its
# key will be included in 'encode_bootstrap_block'.
sub add_exclusion {
    my ($self, %args) = @_;

    my $key = $args{exclusion};
    my $exclusions = $self->{exclusions} //= [];

    push @$exclusions, $key;
}


sub clear_exclusions {
    my ($self, %args) = @_;
    $self->{exclusions} = undef;
}

sub has_exclusion {
    my ($self, %args) = @_;
    my $key = $args{key};

    my $exclusions = $self->{exclusions};
    return if !$exclusions;

    return grep {$_ eq $key} @$exclusions;
}

1;
