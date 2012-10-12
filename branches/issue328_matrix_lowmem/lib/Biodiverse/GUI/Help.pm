package Biodiverse::GUI::Help;

use strict;
use warnings;
use Carp;

use Gtk2;

use Data::Dumper;
use Browser::Open qw( open_browser );
#use Path::Class;

use English qw { -no_match_vars };
use LWP::Simple;

use Biodiverse::GUI::YesNoCancel;

our $VERSION = '0.18003';

##############################################
#  Web links.  


my $bandaid_text = '(This is a bandaid solution until we get hyperlinks working).';


#################
#  Build the URL accessor subs from a hash
#  process borrowed from Statistics::Descriptive v3

my $base_url = 'http://code.google.com/p/biodiverse/wiki/';

my %subs_and_urls = (
    help_show_link_to_web_help         => $base_url . 'HelpOverview',
    help_show_calculations_and_indices => $base_url . 'Indices',
    help_show_spatial_conditions       => $base_url . 'SpatialConditions',
    help_show_release_notes            => $base_url . 'ReleaseNotes',
    help_show_citation                 => $base_url . 'PublicationsList',
    help_show_mailing_list             => 'http://groups.google.com/group/biodiverse-users',
);

sub _make_url_accessors {
    my ($pkg, $methods) = @_;

    no strict 'refs';
    while (my ($sub, $url) = each %$methods) {
        *{$pkg. '::' .$sub} =
            do {
                sub {
                    my $gui = shift;
                    my $link = $url;
                    open_browser_and_show_url ($gui, $url);
                    return;
                };
            };
    }

    return;
}

#  make the URL accessors
__PACKAGE__->_make_url_accessors(\%subs_and_urls);



sub open_browser_and_show_url {
    my $gui  = shift;
    my $link = shift;

    #  open using default browser,
    #  but have to handle a bug in Browser::Open
    #  which doesn't find correct command on windows
    if ($OSNAME eq 'MSWin32') {
        system ('start', $link);
    }
    else {
        my $check_open = open_browser ($link);
    }

    my $text =<<"END_LINK_TEXT"
Your browser should have opened and displayed the URL below.
If it has not then please copy and paste the URL into your web browser.

<span foreground="blue">
$link
</span>

Note that you need to be connected to the web for this to work.

END_LINK_TEXT
;

    #my $window = Gtk2::Window->new;
    #$window->set_title ('Help link');
    #$window->set_modal (1);
    #
    #my $label = Gtk2::Label->new();
    #$window->add ($label);
    #
    #$label->set_use_markup (1);
    #$label->set_markup ($text);
    #$label->set_padding (10, 10);
    #$label->set_selectable (1);
    #$label->select_region (1, 5);
    #
    #$window->show_all;
    
    my $dlg = Gtk2::Dialog->new(
        'Help link',
        $gui->getWidget('wndMain'),
        'modal',
        'gtk-ok'     => 'ok',
    );
    my $text_widget = Gtk2::Label ->new();
    $text_widget->set_use_markup(1);
    $text_widget->set_alignment (0, 1);
    $text_widget->set_markup ($text);
    $text_widget->set_selectable (1);
    $dlg->vbox->pack_start ($text_widget, 0, 0, 0);
    
    $dlg->show_all;
    $dlg->run;
    $dlg->destroy;

    return;
}

#  do we have a new version available?
sub help_show_check_for_updates {
    my $gui = shift;
    
    my $download_url = 'http://code.google.com/p/biodiverse/downloads/list';
    
    my $url = 'http://biodiverse.googlecode.com/svn/trunk/etc/versions.txt';
    my $content = get($url);

    my ($release, $devel);
    if (defined $content) {
        $content =~ s/[\r\n]//g;
        if ($content =~ m/\[release\](.+?)\[/xmso) {
            $release = $1;
        }
        if ($content =~ m/\[development\](.+)\z/xmso) {
            $devel = $1;
        }
    }
    else {
        die "Unable to connect to update server: $url\n";
    }

    my $dlg = Gtk2::Dialog->new(
        'Check for updates',
        $gui->getWidget('wndMain'),
        'modal',
        'gtk-ok'     => 'ok',
    );
    my $text_widget = Gtk2::Label->new();
    $text_widget->set_use_markup(1);
    $text_widget->set_alignment (0, 1);
    $dlg->vbox->pack_start ($text_widget, 0, 0, 0);
    
    $dlg->show_all;

    my $expl_text = "Release version is $release.\n"
                  . "Development version is $devel.";
    my $text;
    
    if ($VERSION == $release) {
        $text = "\n\nYou are using the current release version.\n\n";
    }
    elsif ($VERSION == $devel) {
        $text = "\n\nYou are using the current development version.\n\n";
    }
    elsif ($VERSION < $release) {
        $dlg->add_button ('Get Update' => '1',);
        $text = "\n\n"
                . "A new release is available.  "
                . 'Go to '
                #. '<span foreground="blue">'
                . $download_url
                #. '</span>'
                . " to download it.\n\n";
    }
    elsif ($VERSION > $devel) {
        $text = "\n\nYou seem to be ahead of the development cycle (version is $VERSION).\n\n";
    }
    elsif ($VERSION < $devel) {
        $text= "\n\nYou seem to be on a development version that is one version behind (version is $VERSION).\n\n";
    }
    else {
        $text = "Muh? Check your version ($VERSION) as it does not fit expectations.";
    }
    $text_widget->set_text ($text . $expl_text);
    my $response = $dlg->run;
    if ($response eq 1) {
        open_browser_and_show_url ($gui, $download_url);
    }
    $dlg->destroy;

    return;
}


1;
