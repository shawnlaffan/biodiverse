#!perl

use Test::More tests => 1;

BEGIN {
    use_ok( 'Task::Biodiverse::NoGUI' ) || print "Bail out!\n";
}

diag( "Testing Task::Biodiverse::NoGUI $Task::Biodiverse::NoGUI::VERSION, Perl $], $^X" );
