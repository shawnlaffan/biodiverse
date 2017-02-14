#!/usr/bin/perl -w

use strict;
use warnings;

local $| = 1;

use Test::Lib;
use Test::More;
use Test::Exception;

use Biodiverse::TreeNode::BootstrapBlock;

use Devel::Symdump;
my $obj = Devel::Symdump->rnew(__PACKAGE__);
my @test_subs = grep { $_ =~ 'main::test_' } $obj->functions();

exit main();

sub main {
    foreach my $sub (@test_subs) {
        no strict 'refs';
        $sub->();
    }
    done_testing();
    return 0;
}

# testing basic set_value/get_value operations on the bootstrap block.
sub test_basic_operations {
    my $bootstrap_block = Biodiverse::TreeNode::BootstrapBlock->new();

    my %hash = ( "foo"      => "bar", 
                 "footwo"   => "bartwo", 
                 "foothree" => "barthree" );
        

    foreach my $key (keys %hash) {
        $bootstrap_block->set_value( key => $key, value => $hash{$key} );
    }

    foreach my $key (keys %hash) {
        is ( $bootstrap_block->get_value ( key => $key ),
             $hash{ $key },
             "$key maps to $hash{$key}"
            );
    }
}

sub test_decode {
    my @raw_inputs = ('"foo"="bar","footwo"="bartwo",foothree=barthree');


    my %hash = ( "foo"      => "bar", 
                 "footwo"   => "bartwo", 
                 "foothree" => "barthree", 
               );
    

    my $bootstrap_block = Biodiverse::TreeNode::BootstrapBlock->new();

    foreach my $input (@raw_inputs) {
        $bootstrap_block->decode_bootstrap_block( raw_bootstrap => $input );
        
        foreach my $key (keys %hash) {
            is ( $bootstrap_block->get_value ( key => $key ),
                 $hash{ $key },
                 "$key maps to $hash{$key}"
            );
        }
    }
}


sub test_encode {
    my %hash = ( "foo"      => "bar", 
                 "footwo"   => "bartwo", 
                 "foothree" => "barthree",
               );

    my $bootstrap_block = Biodiverse::TreeNode::BootstrapBlock->new();

    foreach my $key (keys %hash) {
        $bootstrap_block->set_value( key => $key, value => $hash{ $key } );
    }

    my $actual = $bootstrap_block->encode_bootstrap_block();

    # we don't know what order the bootstrap block will be written, so
    # just look for the pairs we know should be there.
    foreach my $key (keys %hash) {
        my $expected_string = "$key=$hash{$key}";
        ok (index($actual, $expected_string) != -1, 
            "Block contained $expected_string")
    }

    # test an encoding with exclusions
    $bootstrap_block->add_exclusion( exclusion => "foo"    );
    $bootstrap_block->add_exclusion( exclusion => "footwo" );

    ok($bootstrap_block->has_exclusion( key => "foo" ), "has_exclusion worked" );
    ok($bootstrap_block->has_exclusion( key => "footwo" ), "has_exclusion worked" );
    ok(!$bootstrap_block->has_exclusion( key => "foothree" ), "has_exclusion worked" );
    
    $actual = $bootstrap_block->encode_bootstrap_block();

    delete $hash{ "foo"    };
    delete $hash{ "footwo" };
    foreach my $key (keys %hash) {
        my $expected_string = "$key=$hash{$key}";
        ok (index($actual, $expected_string) != -1, 
            "Block contained $expected_string")
    }
    ok (index($actual, '"foo"="bar"') == -1, 
        "Block didn't contain excluded item");
    ok (index($actual, '"footwo"="bartwo"') == -1, 
        "Block didn't contain excluded item");

    # now test clearing the exclusions
    $bootstrap_block->clear_exclusions();
    $actual = $bootstrap_block->encode_bootstrap_block();

    %hash = (    "foo"      => "bar", 
                 "footwo"   => "bartwo", 
                 "foothree" => "barthree", 
        );

    
    # we don't know what order the bootstrap block will be written, so
    # just look for the pairs we know should be there.
    foreach my $key (keys %hash) {
        my $expected_string = "$key=$hash{$key}";
        ok (index($actual, $expected_string) != -1, 
            "Block contained $expected_string")
    }
}


sub test_fix_up_unquoted_bootstrap_block {
    my $bootstrap_block = Biodiverse::TreeNode::BootstrapBlock->new();
    my %test_hash = (
        '{key=value,key2=value2}' => '{"key":"value","key2":"value2"}',
        '{key=value}'             => '{"key":"value"}',
        '{"key"="value"}'         => '{"key":"value"}',
        '{"key"="value",key2=value2,"key3"="value3"}' 
                   => '{"key":"value","key2":"value2","key3":"value3"}',
    );

    foreach my $key (keys %test_hash) {
        my $result = 
            $bootstrap_block->fix_up_unquoted_bootstrap_block( block => $key);

        is ( $result,
             $test_hash{$key},
             "$key processed correctly",
            );
    }
}

# only color export should have an exclamation mark
# e.g. [&blah=blah,!color=red,blah2=blah2]
sub test_colour_specific_export {
    my %hash = ( "foo"      => "bar", 
                 "footwo"   => "bartwo", 
                 "color"    => "red",
        );

    my $bootstrap_block = Biodiverse::TreeNode::BootstrapBlock->new();

    foreach my $key (keys %hash) {
        $bootstrap_block->set_value( key => $key, value => $hash{ $key } );
    }

    my $actual = $bootstrap_block->encode_bootstrap_block();

    # we don't know what order the bootstrap block will be written, so
    # just look for the pairs we know should be there.
    ok (index($actual, "!color=red") != -1, 
        "Block contained !color=red")

    
}
