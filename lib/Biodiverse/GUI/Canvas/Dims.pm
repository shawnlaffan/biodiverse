package Biodiverse::GUI::Canvas::Dims;
use strict;
use warnings;

our $VERSION = '4.99_002';

sub new {
    my ($class, %args) = @_;
    # $args{scale} //= 1;
    my $self = \%args;
    bless $self, $class;
}

{
    #  accessors
    no strict 'refs';
    my $pkg = __PACKAGE__;
    foreach my $key (qw/xmin xmax ymin ymax/) {
        my $method = $key;
        *{"${pkg}::${method}"} =
            do {
                sub {
                    defined $_[1] ? $_[0]->{$key} = $_[1] : $_[0]->{$key};
                };
            };
    }
}

sub scale {
    my ($self, $scale) = @_;
    if (defined $scale) {
        $self->{scale} = $scale;
    }
    $self->{scale} //= 1;
}

sub multiply_scale {
    my ($self, $m) = @_;
    $self->{scale} //= 1;
    return $self->{scale} *= $m;
}

sub xcen {
    my ($self, $c) = @_;
    if (defined $c) {
        $self->{xcen} = $c;
    }
    return $self->{xcen} //= ($self->{xmin} + $self->{xmax}) / 2;
}

sub ycen {
    my ($self, $c) = @_;
    if (defined $c) {
        $self->{ycen} = $c;
    }
    return $self->{ycen} //= ($self->{ymin} + $self->{ymax}) / 2;
}

sub xbounds {
    my ($self) = @_;
    return ($self->xmin, $self->xmax);
}

sub ybounds {
    my ($self) = @_;
    return ($self->ymin, $self->ymax);
}

sub xwidth  {shift->width(@_)}
sub yheight {shift->height(@_)}

sub width {
    my ($self, $width) = @_;
    if (defined $width) {
        $self->{width} = $width;
    }
    $self->{width} //= ($self->xmax - $self->xmin);
}

sub height {
    my ($self, $height) = @_;
    if (defined $height) {
        $self->{height} = $height;
    }
    $self->{height} //= ($self->ymax - $self->ymin);
}

sub clear {
    my ($self) = @_;
    @$self{keys %$self} = ();
    # $self->{scale} = 1;
    return $self;
}

1;

