package Biodiverse::Exception;
use strict;
use warnings;
our $VERSION = '4.99_003';

use Config;
my ($bit_size, $prng_init_descr, $other_bit_size);

BEGIN {
    $bit_size = $Config{archname} =~ /x(?:86_)?64/ ? 64 : 32;  #  will 128 bits ever be needed for this work?
    $other_bit_size = $bit_size == 64 ? 32 : 64;
    $prng_init_descr = <<"PRNG_INIT_DESCR"
PRNG initialisation has been passed a state vector for the wrong architecture.
This is a $bit_size bit perl but one or more analyses were
built on a $other_bit_size bit architecture.
Rebuilding each analysis on this architecture 
(including randomisations) is unfortunately the only solution.
PRNG_INIT_DESCR
  ;
}

#  Exceptions for the Biodiverse system,
#  both GUI and non-GUI
#  GUI should go into their own package, though

use Exception::Class (
    'Biodiverse::Cluster::MatrixExists' => {
        description => 'A matrix of this name is already in the BaseData object',
        fields      => [ 'name', 'object' ],
    },
    'Biodiverse::MissingBasedataRef' => {
        description => 'Caller object is missing the basedata ref',
    },
    'Biodiverse::MissingArgument' => {
        description => 'Call to method is missing required argument',
        fields => [qw /method argument/],
    },
    'Biodiverse::NoMethod' => {
        description => 'Cannot call method via autoloader',
        fields => [qw /method in_autoloader/],
    },
    'Biodiverse::Args::ElPropInputCols' => {
        description => 'Input columns argument is incorrect',
    },
    'Biodiverse::Tree::NodeAlreadyExists' => {
        description => 'Node already exists in the tree',
        fields      => [ 'name' ],
    },
    'Biodiverse::ReadNexus::IncorrectFormat' => {
        description => 'Not in valid format',
        fields      => [ 'type' ],
    },    
    'Biodiverse::NoSubElementHash' => {
        description => 'Element does not exist or does not have a SUBELEMENT hash',
    },
    'Biodiverse::GUI::ProgressDialog::Cancel' => {
        description => 'User closed the progress dialog',
        #message     => 'Progress bar closed, operation cancelled',
    },
    'Biodiverse::GUI::ProgressDialog::Bounds' => {
        description => 'Progress value is out of bounds',
    },
    'Biodiverse::GUI::ProgressDialog::NotInGUI' => {
        description => 'Not running under the GUI',
    },
    'Biodiverse::Indices::MissingRequiredArguments' => {
        description => 'Missing one or more required arguments',
    },
    'Biodiverse::Indices::InsufficientElementLists' => {
        description => 'Too few element lists specified',
    },
    'Biodiverse::Indices::FailedPreCondition' => {
        description => 'Failed a precondition',
    },
    'Biodiverse::Tree::NotExistsNode' => {
        description => 'Specified node does not exist',
    },
    'Biodiverse::PRNG::InvalidStateVector' => {
        description => $prng_init_descr,
    },
    'Biodiverse::BaseStruct::ListDoesNotExist' => {
        description => 'The requested list does not exist for this element',
    },
    'Biodiverse::CannotOpenFile' => {
        description =>
              'Unable to open the given file'
            . "Check file read permissions."
            . "If the file name contains unicode characters then please rename the file so its name does not contain them.\n"
            . 'See https://github.com/shawnlaffan/biodiverse/issues/272'
    }
);


1;
