use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME' => 'Task::Biodiverse::NoGUI',
    'VERSION_FROM' => 'lib/Task/Biodiverse/NoGUI.pm', # finds $VERSION
    ($] ge '5.005') ? (
        'AUTHOR' => 'Shawn Laffan (shawn.laffan@unsw.edu.au)',
        'ABSTRACT' => 'Task for Biodiverse dependencies for non-GUI use',
        ) : (),
    PREREQ_PM => {
        "Data::DumpXML" => "0",
        "Math::Random::MT::Auto" => "0",
        "Devel::Symdump" => "0",
        "Text::CSV_XS" => "0.60",
        "DBD::XBase" => "0",
        "HTML::QuickTable" => "0",
        "YAML::Syck" => "0",
        "PadWalker" => "0",
        "Clone" => "0",
        "Regexp::Common" => "0",
        "lib" => "0",
        "mylib" => "0",
        "parent" => "0",
        "Readonly" => "0",
        "URI::Escape::XS" => "0",
        "Statistics::Descriptive" => "3.02",
        "Geo::Converter::dms2dd" => "0",
        "Text::Wrapper" => "0",
        "Exporter::Easy" => "0",
        "Exception::Class" => "0",
        "Math::Polygon" => "0",
        "MRO::Compat" => "0",
        "File::BOM" => "0",
        "Math::Polygon" => "0",
    }
);
