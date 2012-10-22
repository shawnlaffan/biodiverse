#! perl

use strict;
use Gtk2 -init;
my $window = Gtk2::Window->new ('toplevel');
$window->signal_connect (delete_event => sub { Gtk2->main_quit });

	my $button = Gtk2::Button->new ('Action');
	$button->signal_connect (clicked => sub { 
	
  		print("Hello Gtk2-Perl\n");
		
  	});
	
$window->add ($button);
$window->show_all;
Gtk2->main;

