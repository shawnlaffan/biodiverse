use strict;
use warnings;
use 5.010;

use lib '../../lib';
use Cwd;
use FindBin qw ( $Bin );
use Scalar::Util qw /blessed/;
use Path::Class;
use Class::Inspector;

use English qw /-no_match_vars/;

use Data::Dumper;

local $| = 1;

#  load up the user defined libs and settings
use Biodiverse::Config;

#  load Gtk
use Gtk2 qw/-init/;
use Gtk2::GladeXML;

my $max_load_count = $ARGV[0] // 10;

do {
    my $gladefile = get_gladefile();

    for my $i (1 .. $max_load_count) {
        
        my $gladexml = eval {
            Gtk2::GladeXML->new( $gladefile, 'wndProgress' );
        };
        croak $EVAL_ERROR if $EVAL_ERROR;
        my $dlg = $gladexml->get_object('wndProgress');


        if ($i == 1) {
            my $methods = Class::Inspector->methods (blessed $gladexml);
            #print join "\n", @$methods;
            my @children = $dlg->get_children;  #  there is only one
            print $children[0]->get_children;
        }

        #say Dumper $gladexml;
        $dlg->destroy;
        $gladexml->DESTROY;  #  has no effect
        $gladexml = undef;
    }
};

sub get_gladefile {
    my $gladefile = Path::Class::file( $Bin, 'progress_bar.glade' )->stringify;
    return $gladefile;
};
