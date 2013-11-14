use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    'NAME' => 'Task::Biodiverse',
    'VERSION_FROM' => 'lib/Task/Biodiverse.pm', # finds $VERSION
    ($] ge '5.005') ? (
        'AUTHOR' => 'Shawn Laffan (shawn.laffan@unsw.edu.au)',
        'ABSTRACT' => 'Task for Biodiverse dependencies',
        ) : (),
    PREREQ_PM => {
        "Task::Biodiverse::NoGUI" => "0.19",
        "Data::DumpXML" => "0",
        "Gtk2::GladeXML" => "0",
        "Gnome2::Canvas" => "0",
        "Browser::Open" => "0",
        "LWP::Simple" => "0",
    },
    BUILD_REQUIRES => {
        "ExtUtils::Depends" => "0",
        "ExtUtils::PkgConfig" => "0",
        "Glib" => "0",
        "Gtk2" => "0",
    },
);
