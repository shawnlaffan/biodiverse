package Biodiverse::GUI::Canvas::Dims;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    $args{scale} //= 1;
    my $self = \%args;
    bless $self, $class;
}

{
    #  accessors
    no strict 'refs';
    my $pkg = __PACKAGE__;
    foreach my $key (qw/xmin xmax ymin ymax scale/) {
        my $method = $key;
        *{"${pkg}::${method}"} =
            do {
                sub {
                    defined $_[1] ? $_[0]->{$key} = $_[1] : $_[0]->{$key};
                };
            };
    }
}

sub xcen {
    my ($self) = @_;
    return $self->{xcen} //= ($self->{xmin} + $self->{xmax}) / 2;
}

sub ycen {
    my ($self) = @_;
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

sub xwidth  {shift->width}
sub yheight {shift->height}

sub width {
    my ($self) = @_;
    $self->xmax - $self->xmin;
}

sub height {
    my ($self) = @_;
    $self->ymax - $self->ymin;
}

sub clear {
    my ($self) = @_;
    @$self{keys %$self} = ();
}

1;

