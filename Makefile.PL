use strict;
use warnings;
use 5.036;
use ExtUtils::MakeMaker;

#  these are from the cpanfile
#  need to look at https://metacpan.org/pod/ExtUtils::MakeMaker::CPANfile
my %common_reqs = (
    "Class::Inspector"      => 0,
    "Clone"                 => "0.35",
    "Cpanel::JSON::XS"      => "3",
    "Data::Structure::Util" => 0,
    "Data::Compare"         => 0,
    "Exception::Class"      => 0,
    "Exporter::Easy"        => 0,
    #"Faster::Maths"         => 0,
    "File::BOM" => 0,
    "File::Find::Rule" => 0,
    "Geo::Converter::dms2dd" => "0.05",
    "Geo::GDAL::FFI" => "0.09",  #  this will pick up the aliens
    "Geo::ShapeFile" => "3.00",
    "Getopt::Long::Descriptive" => 0,
    "HTML::QuickTable" => 0,
    "JSON::MaybeXS" => "1.003",
    "JSON::PP" => 0,
    "List::MoreUtils" => "0.425",
    "List::Unique::DeterministicOrder" => "0.003",
    "List::Util" => "1.54",
    "Math::Polygon" => 0,
    "Math::Random::MT::Auto" => "6.21",
    "Readonly" => 0,
    "Ref::Util" => 0,
    "Ref::Util::XS" => 0,
    "Regexp::Common" => 0,
    "Sereal" => "3",
    "Sort::Key" => 0,
    "Spreadsheet::ParseExcel" => 0,
    "Spreadsheet::ParseXLSX" => 0,
    "Spreadsheet::ParseODS" => 0,
    "Spreadsheet::Read" => "0.82",
    "Spreadsheet::ReadSXC" => "0.28",
    "Statistics::Descriptive" => "3.0608",
    "Statistics::Sampler::Multinomial" => '1.02',
    "Text::CSV_XS" => "1.52",
    "Text::Fuzzy" => 0,
    "Text::Wrapper" => 0,
    "Tree::R" => 0,
    "URI::Escape" => 0,
    "URI::Escape::XS" => 0,
    "YAML::Syck" => "1.29",
    "autovivification" => "0.18",
    "parent" => 0,
    "rlib" => 0,
    "Statistics::Descriptive::PDL" => "0.15",
    "Excel::ValueReader::XLSX" => 0,
    ($^O eq 'MSWin32' ? ("Win32::LongPath" => 0) : ()),
);

my %test_reqs = (
    "Test::Lib" => 0,
    "Test::TempDir::Tiny" => 0,
    "Test2::Suite" => 0,
    #$^O ne 'MSWin32' ? (suggests "Test2::Harness") : ();
    "Data::Section::Simple" => 0,
    "Perl::Tidy" => 0,
    "Devel::Symdump" => 0,
    "File::Compare" => 0,
    "Scalar::Util::Numeric" => 0,
    "Test::TempDir::Tiny" => 0,
    'Test::Deep::NoTest' => 0,
    'Alien::Build::Plugin::Fetch::Cache' => 0,
);

my %WriteMakefileArgs = (
    "ABSTRACT" => "Biodiverse - a tool for the spatial analysis of biological and other diversity",
    "AUTHOR"   => 'Shawn Laffan <shawnlaffan@gmail.com>',
    "NAME"     => "Biodiverse",
    "VERSION_FROM" => "lib/App/Biodiverse.pm",
    MIN_PERL_VERSION => '5.036',
    "CONFIGURE_REQUIRES" => {
        %common_reqs,
    },
    "BUILD_REQUIRES" => {
        %common_reqs,
    },
    "TEST_REQUIRES" => {
        %test_reqs,
    },
    "PREREQ_PM" => {
        %common_reqs,
    },
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                url  => 'https://github.com/shawnlaffan/biodiverse',
            },
            bugtracker => {
                web => 'https://github.com/shawnlaffan/biodiverse/issues/',
            },
        },
        #prereqs => {
        #    build => {
        #        suggests => {  #  gtk stuff
        #            "Alien::spatialite" => '1.07',
        #        },
        #    },
        #},
    },
    "DISTNAME" => "Biodiverse",
    "LICENSE"  => "perl",
);

WriteMakefile(%WriteMakefileArgs);

