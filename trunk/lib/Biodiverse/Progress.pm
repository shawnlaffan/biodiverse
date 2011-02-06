package Biodiverse::Progress;
use strict;
use warnings;
use English qw { -no_match_vars };
use Carp;
use POSIX qw /fmod/;
my $NULL_STRING = q{};

our $VERSION = '0.16';

sub new {
    my $class = shift;
    my %args = @_;

    my $hash_ref = {
        gui_progress => undef,
        last_text    => $NULL_STRING,
        print_text   => 1,
        last_reported_prog    => -1,
        report_interval => 5,  #  in percent
        gui_only        => 0,  #  only feedback via GUI
        %args,  #  override if user says so
    };

    my $self = bless $hash_ref, $class;

    my $gui_progress;
    eval q{
        use Biodiverse::GUI::ProgressDialog;
        $gui_progress = Biodiverse::GUI::ProgressDialog->new;  #  should pass on relevant args
    };
    if (! $EVAL_ERROR and defined $gui_progress) {
        #  if we are in the GUI then we can use a GUI progress dialogue
        $self->{gui_progress} = $gui_progress;
    }

    return $self;
}


sub destroy {
    my $self = shift;
    
    eval {$self->{gui_progress} -> destroy};

    $self->reset();

    return;
}

sub update {
    my $self = shift;
    
    my $text     = shift;
    my $progress = shift; # fraction 0 .. 1
    my $no_update_text = shift;

    croak "No progress set\n" if not defined $progress;

    eval {$self->{gui_progress} -> update ($text, $progress)};
    if ( Biodiverse::GUI::ProgressDialog::Bounds->caught() ) {
        $EVAL_ERROR->rethrow;
    }
    elsif ( Biodiverse::GUI::ProgressDialog::Cancel->caught() ) {
        $EVAL_ERROR->rethrow;
    }

    #return if !$EVAL_ERROR;

    return if $self->{gui_only};

    if (not defined $text) {
        $text = $NULL_STRING;
    }

    croak "ERROR [Progress] progress $progress is not between 0 & 1\n"
      if ($progress < 0 || $progress > 1);

    #  do something with the text if it differs
    if ($self->{print_text}) {
        print $text . q{ };
        print q{ } x 4;
        #if (not $text =~ /[\r\n]$/) {
        #    print "\n";
        #}
    }
    $self->{print_text} = 0;

    my $prog_pct = int ($progress * 100);
    my $interval = $self->{report_interval};
    return if $prog_pct % $interval != 0 and $self->{last_reported_prog} != -1;
    return if $prog_pct == $self->{last_reported_prog};

    $self->{last_reported_prog} = $prog_pct;
    
    #  update the percent progress, use sprintf to make the string consistent length
    my $prog_text = sprintf "\b\b\b\b%3i%%", $prog_pct;
    print $prog_text;
    
    return;
}

#  need a better name?
sub close_off {
    my $self = shift;
    $self->reset;
    return;
}

#  close off this line
sub reset {
    my $self = shift;
    
    $self->{last_text}          = $NULL_STRING;
    $self->{print_text}         =  1;
    $self->{last_reported_prog} = -1,

    print "\n";

    return;
}

sub pulsate {
    my $self = shift;
    
    eval {$self->{gui_progress} -> pulsate (@_)};

    return;
}

sub pulsate_stop {
    my $self = shift;
    
    eval {$self->{gui_progress} -> pulsate_stop (@_)};
    
    return;
}

sub pulse_progress_bar {
    my $self = shift;
    
    eval {$self->{gui_progress} -> pulsate_progress_bar (@_)};
    
    return;
}

sub DESTROY {
    my $self = shift;
    $self->reset;
    if ($self->{gui_progress}) {  #  can't use an eval here as it resets $EVAL_ERROR
        $self->{gui_progress}->destroy;  #  take care of any GUI progress
    };
    delete @$self{keys %$self};             #  clean out all keys, prob not needed
}

1;


=head1 NAME

Biodiverse::Progress

=head1 SYNOPSIS

  use Biodiverse::Progress;
  my $progress = Biodiverse::Progress->new();

=head1 DESCRIPTION

Provide feedback about progress.
Uses a Biodiverse::GUI::ProgressDialog object if the GUI is running,
console text otherwise.

=head1 METHODS

=over

=item NEED TO INSERT METHODS
also valid arguments

=back

=head1 REPORTING ERRORS

Use the issue tracker at http://www.purl.org/biodiverse

=head1 COPYRIGHT

Copyright (c) 2010 Shawn Laffan. All rights reserved.  

=head1 LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

For a full copy of the license see <http://www.gnu.org/licenses/>.

=cut

1;
