#  Grow regions using any of the available metrics.
#  This is an extension of the clustering algorithm.

package Biodiverse::GUI::Tabs::RegionGrower;
use strict;
use warnings;

our $VERSION = '0.16';

use base qw /
    Biodiverse::GUI::Tabs::Clustering
/;


sub new {
    my $class = shift;
    #  get a Clustering object
    my $self = __PACKAGE__->SUPER::new(@_);
    
    bless $self, $class;
    
    #  now add some additional stuff
    my $xml_page = $self->{xmlPage};
    my $hbox = $xml_page->get_widget('hbox_cluster_metric');
    
    my $label_widget = Gtk2::Label->new('Objective function: ');
    my $combo_minmax = Gtk2::ComboBox->new_text();
    $combo_minmax->append_text('maximise');
    $combo_minmax->append_text('minimise');
    $combo_minmax->set_active(0);
    $hbox->pack_end($combo_minmax, 1, 1, 0);
    $hbox->pack_end($label_widget, 1, 1, 0);
    $hbox->show_all;
    
    $self->{combo_minmax} = $combo_minmax;
    
    return $self;
}

sub getType {
    return 'RegionGrower';
}

sub get_output_type {
    return 'Biodiverse::RegionGrower';
}

sub get_objective_function {
    my $self = shift;
    
    my $objective = $self->{combo_minmax}->get_active_text;
    
    return $objective eq 'minimise' ? 'get_min_value' : 'get_max_value';
}

sub onRunAnalysis {
    my $self = shift;
    
    my %analysis_args = (
        objective_function => $self->get_objective_function,
    );
    
    return $self->SUPER::onRunAnalysis (%analysis_args);
}

1;
