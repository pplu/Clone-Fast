# Test script from RT #32567

# The following script demonstrates the problem. # -- Petr Pajas #

use warnings; 
use strict; 

use Test::More tests => 3; 
use Scalar::Util qw(isweak weaken); 

use Clone::Fast; 
use Clone; 

my $root = { name => 'ROOT' }; 
my $node = { name => 'CHILD', parent => $root }; 

$root->{child}=$node; 

weaken($node->{parent}); 
my $fast = Clone::Fast::clone($root); 


ok(isweak($root->{child}{parent}), 'original is weak'); 

my $clone = Clone::clone($root); 
ok(isweak($clone->{child}{parent}), 'Clone::clone is weak'); 

TODO: {
   local $TODO = "Doesn't support weak refs yet";
   ok(isweak($fast->{child}{parent}), 'Fast::Clone::clone is weak'); 
}
