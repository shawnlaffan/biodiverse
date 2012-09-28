use strict;
use warnings;
use Test::More;

local $| = 1;
use File::Spec;


eval { require Test::Perl::Critic::Progressive };
if ($@) {
    plan skip_all => 'T::P::C::Progressive required for this test';
}

use Test::Perl::Critic::Progressive qw( progressive_critic_ok );
progressive_critic_ok();

