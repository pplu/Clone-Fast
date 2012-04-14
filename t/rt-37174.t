#!perl
use Test::More tests => 1;

use strict;
use warnings;

use Clone::Fast qw(clone);
use Data::Dumper;
use Devel::Peek;

local $Data::Dumper::Useperl = 1;

my $hashref =   {
    'foo' => [
        'Bar'
    ],
};

Dump( $hashref, 10 );
warn("Record before clone: ".Dumper($hashref));
Dump( $hashref, 10 );
my $clone = clone($hashref);
warn("Record after clone: ".Dumper($clone));


pass('Ok');
