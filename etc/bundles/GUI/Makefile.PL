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
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                url  => 'https://github.com/shawnlaffan/biodiverse.git',
                web  => 'http://purl.org/biodiverse',
            },
            bugtracker => {
                web => 'https://github.com/shawnlaffan/biodiverse/issues/',
            },

        },
    },
    PREREQ_PM => {
        "Task::Biodiverse::NoGUI" => "3.000",
        "Data::DumpXML" => "0",
        "Gnome2::Canvas" => "0",
        "Browser::Start" => "0",
        "LWP::Simple" => "0",
        "HTTP::Tiny" => "0",
        "IO::Socket::SSL" => "0",
    },
    BUILD_REQUIRES => {
        "ExtUtils::Depends" => "0",
        "ExtUtils::PkgConfig" => "0",
        "Glib" => "0",
        "Gtk2" => "0",
        "Pango" => "0",
    },
    TEST_REQUIRES => {
        "Test2::V0" => 0,
    },
);
