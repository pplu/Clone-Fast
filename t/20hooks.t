
use strict;
use warnings;

use Test::More qw( no_plan );
use Clone::Fast qw( clone );

use_ok( 'Clone::Fast' );

my $hooker = Hooker->new();
my $no_hooker = NoHooker->new();
ok( $hooker && $no_hooker );

ok( clone( $hooker ) );
ok( clone( $no_hooker ) );

ok( $hooker->is_ok() );
ok( ! $no_hooker->is_ok() );

package NoHooker;

{
	my $hooked;

	sub new { return bless {}, shift; }

	sub CLONEFAST_clone_x {
		$hooked++;
		return @_;
	}

	sub is_ok { return $hooked; }
}

package Hooker;

{
	my $hooked;

	sub new { return bless {}, shift; }

	sub CLONEFAST_clone {
		$hooked++;
		my ( $hook ) = @_;
		return $hook;
	}

	sub is_ok { return $hooked; }
}
