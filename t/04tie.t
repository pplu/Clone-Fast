# $Id: 04tie.t,v 1.1 2006/07/14 03:10:13 thall Exp $
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

use Test::More tests => 4;
use Clone::Fast qw( clone );
use strict;

######################### End of black magic.

require 't/tied.pl';

my ($a, @a, %a);
tie $a, 'TIED_SCALAR';
tie %a, 'TIED_HASH';
tie @a, 'TIED_ARRAY';
$a{a} = 0;
$a{b} = 1;

my $b = [\%a, \@a, \$a]; 
my $c = clone($b);
is_deeply( $c, $b );

my $t1 = tied(%{$b->[0]});
my $t2 = tied(%{$c->[0]});
is_deeply( $t1, $t2 );

$t1 = tied(@{$b->[1]});
$t2 = tied(@{$c->[1]});
is_deeply( $t1, $t2 );

$t1 = tied(${$b->[2]});
$t2 = tied(${$c->[2]});
is_deeply( $t1, $t2 );
