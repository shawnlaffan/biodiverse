use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME' => 'Bundle::Biodiverse',
    'VERSION_FROM' => 'lib/Bundle/Biodiverse.pm', # finds $VERSION
    ($] ge '5.005') ? (
        'AUTHOR' => 'Shawn Laffan (shawn.laffan@unsw.edu.au)',
        'ABSTRACT' => 'Bundle for Biodiverse dependencies',
        ) : (),
    PREREQ_PM => {
        "Data::DumpXML" => "0",
        "Geo::ShapeFile" => "0",
        "Tree::R" => "0",
        # "ExtUtils::Depends" => "0",
        # "ExtUtils::PkgConfig" => "0",
        "Gtk2::GladeXML" => "0",
        "Browser::Open" => "0",
        # "LWP::Simple" => "0",
    }
);
