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
    my @raw_inputs = ('["foo":"bar","footwo":"bartwo","foothree":"barthree"]');


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
        my $expected_string = "\"$key\":\"$hash{$key}\"";
        ok (index($actual, $expected_string) != -1, 
            "Block contained $expected_string")
    }

    # also test an encoding with exclusions
    my @exclusions = ("foo");
   $actual = 
       $bootstrap_block->encode_bootstrap_block(exclusions => \@exclusions);

    delete $hash{"foo"};
    foreach my $key (keys %hash) {
        my $expected_string = "\"$key\":\"$hash{$key}\"";
        ok (index($actual, $expected_string) != -1, 
            "Block contained $expected_string")
    }
    ok (index($actual, '"foo":"bar"') == -1, 
        "Block didn't contain excluded item")


}

