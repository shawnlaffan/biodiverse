package Biodiverse::Exception;
use strict;
use warnings;
our $VERSION = '0.17';

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
        description => 'Too few eleent lists specified',
    },
);


1;
