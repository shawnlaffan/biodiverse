use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

require 5.010;

WriteMakefile(
    'NAME' => 'Task::Biodiverse::NoGUI',
    'VERSION_FROM' => 'lib/Task/Biodiverse/NoGUI.pm', # finds $VERSION
    ($] ge '5.005') ? (
        'AUTHOR' => 'Shawn Laffan (shawn.laffan@unsw.edu.au)',
        'ABSTRACT' => 'Task for Biodiverse dependencies for non-GUI use',
        )
    : (),
    PREREQ_PM => {
        "Data::DumpXML" => "0",
        "Math::Random::MT::Auto" => "6.21",
        #"Devel::Symdump" => "0",  #  redundant from 0.18003
        "Text::CSV_XS" => "0.60",
        "DBD::XBase" => "0",
        "HTML::QuickTable" => "0",
        "YAML::Syck" => "0",
        #"PadWalker" => "0",  #  redundant from 0.18_007
        "Clone" => "0.35",
        "Regexp::Common" => "0",
        "rlib" => "0",
        #"mylib" => "0",
        "parent" => "0",
        "Readonly" => "0",
        "URI::Escape::XS" => "0",
        "Statistics::Descriptive" => "3.06",
        "Geo::Converter::dms2dd" => "0",
        "Text::Wrapper" => "0",
        "Exporter::Easy" => "0",
        "Exception::Class" => "0",
        "Math::Polygon" => "0",
        #"MRO::Compat" => "0",  #  redundant from 0.18003
        "File::BOM" => "0",
        "Math::Polygon" => "0",
        "Path::Class" => "0",
        "Tree::R" => "0",
        "Geo::ShapeFile" => "0",
        "List::MoreUtils" => "0",
        "List::Util" => "1.32",
        "Class::Inspector" => "0",
        "autovivification" => "0.11",
    },
    BUILD_REQUIRES => {
        "Data::Section::Simple" => "0",
        "Test::Deep" => "0",
        "Test::NoWarnings" => "0",
        "Perl::Tidy" => 0,
    },
);
