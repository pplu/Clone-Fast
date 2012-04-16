package Clone::Fast;

use strict;

our $VERSION = '0.97';

# Configuration variables
our $BREAK_REFS      = 0;
our $IGNORE_CIRCULAR = 0;
our $CIRCULAR_ACTION = 0;
our $ALLOW_HOOKS     = 1;

use Exporter;
*import = \&Exporter::import;
our @EXPORT_OK = qw( clone );

use XSLoader;
XSLoader::load( 'Clone::Fast', $VERSION );

2 != 42;
__END__

=head1 NAME

Clone::Fast - Natively copying Perl data structures

=head1 SYNOPSIS

	use strict;
	use warnings;

	use Clone::Fast qw( clone );
	use Data::Dumper;

	# Though that may be the easiest thing to do, there
	# are also other options:
	#
	# use Clone::Fast; # While using Clone::Fast::clone
	# {
	#   no strict 'refs';
	#   *clone = \&Clone::Fast::clone;
	# }
	#
	# eval( "sub clone { Clone::Fast::clone }" );

	my $original = bless( { 'a' => [ qw( a b c d ) ] }, 'main' );
	my $copy     = clone( $original );

	# Notice the original and copy are no longer the same,
	# although they look exactly the same
	print "Different memory segments\n" if ( $original ne $copy );
	print "Same structure\n" if ( Dumper( $original ) eq Dumper( $copy ) );

=head1 DESCRIPTION

Essentially, this module is a very optimized version of L<Clone::More>.  By taking
advantage of one of L<Clone::More>'s 'OPTIMIZATION_HACKS' as well as removing all
the Pure Perl from the C<More.pm>, I was able to gain a lot of speed out of the module.
Essentially, though, the core of the module is exactly as that of L<Clone::More>.

You will see that by useing L<Benchmark::cmpthese>, I ran a simple comparison between
L<Storable::dclone>, L<Clone::More::clone>, and L<Clone::Fast::clone>.  You will (should)
begin to see the reason why I loaded this module along side of L<Clone::More>.

				   Rate    Storable Clone::More Clone::Fast
	Storable     7552/s          --        -39%        -59%
	Clone::More 12400/s         64%          --        -33%
	Clone::Fast 18442/s        144%         49%          --

For more information relative to the DESCRIPTION of this module, I recommend peeking into
the POD written for L<Clone::More> (I took more time with it ;) )

=head2 HISTORY

As noted in L<Clone::More>, this module started as a patch for L<Clone> with repsect to a
large memory leak a team I was working closely with at the time fell across once implemented
the cloning into a Perl application.  The unfortunate part is that I wasn't able to patch the
L<Clone> module without a complete re-factor (I still have no idea where the leak is in Clone),
and have not been able to get ahold of Ray Finch, the current author and supporter of L<Clone>.
Every thing considered, I loaded up this and it's counter part L<Clone::More> - both a little
different from one another, and both a little different from L<Clone> still.

=head2 EXPORT

=head3 clone

Clone is the primary function from within the provided module.  By passing a scalar reference to this
routine, you will expect to get a returned scalar reference that will no longer have any reference to
the originating reference.  However, references deeper into the structure will still uphold the references
within the structure.

Example being:

	use Clone::Fast qw( clone );

	my $foo = { 'a' => 'b' };
	my $bar = { 'a' => $foo, 'b' => $foo };

	my $baz = clone( $bar );

	print "\$foo and \$bar are different references\n" if ( $foo ne $bar );
	print "\$foo->{'a'} and \$bar->{'a'} are different references\n" if ( $foo->{'a'} ne $bar->{'a'} );
	print "\$foo->{'a'} and \$foo->{'b'} are the same, however\n" if ( $foo->{'a'} eq $bar->{'b'} );

This makes sense, although this can be modified as well.  By using the internal variable, BREAK_REFS, you
are also allowed to break internal references (may break up circular references, although won't fix
the circular reference in the originating reference).

=head1 PROGRAMATIC HOOKS

Much like the Perl Storable module (available in all current Perl distributions), C<Clone::Fast> allows for
hooks that will be accessed when cloning any object that has a hook defined.  This can be very handy where
Inside Out objects would not normally be cloned.  WHHAAATT????  What I mean is, only the reference of an
object will be cloned, not the internal stash of the object.  Therefore, accessors that are defined within
an inside out object will not be cloned.  There is no real safe way to do this, with the exception of cloning
the entire class stash, breaking more things than it will fix.  Again, the reference of the object will be
fully cloned, and the object it's self will be a new reference, although it will be an empty object.  Subsiquently,
such as most inside out objects, the blessed reference is of a scalar type; an integer indicating the object id.
When cloning this, you would end up with two objects of the same type with the same object id.  The hooks
have been added in an attempt to prevent this from happening.

=head2 CLONEFAST_clone

Again, much like L<Storable> (though a little better, I hope), the function will be called *AFTER* the clone
operation has completed on the object being cloned.  The routine will have two scalar references passed
via the stack, representing both the cloned object as well as the source of the clone.  This *should* allow
for the programatic manipulation of the object before it gets returned to the caller, or placed into the
refering structure.

As an example, I will use the following object to define a 'hooked' object:

	package Hookable;

	use strict;
	use warnings;

	use Clone::Fast qw( clone );
	
	sub new { bless {}, shift }

	sub CLONEFAST_clone {

		# Where clone is the cloned object from the source, where source
		# was the originating reference
		my ( $clone, $source ) = @_;

		# I am going to pretend the source has a list of defined methods,
		# of which I want to clone and transfer to the clone; outside
		# of the blessed hash-refrence that is the source of the object
		$clone->$_( clone( $source->$_() ) ) for ( qw( get_method_1 get_method_2 get_method_3 ) );

		# At this point, the cloned object will also have a set of cloned
		# fields from the source.  If, by chance, any of the values of the
		# defined attribtes are other 'Hookable' objects, the same routine
		# will be called on that object as well.
		
		# The API requires me to return the new $clone, this will be returned to
		# the caller
		return $clone;
	}

Using the package from above, I will now use an example of a script where I will demonstrate how
the whole thing comes together:

	#!/usr/bin/perl -w
	
	use strict;

	use Clone::Fast qw( clone );

	my $hookable  = Hookable->new();
	$hookable->{'hash_stuff'} = 'some value';
	
	my $structure = {
		'hookable' => $hookable,
		'new'      => Hookable->new(),
		'deeply'   => {
			'hookable' => $hookable,
			'new'      => Hookable->new();
		},
	};

	my $cloned = clone( $sturcture );

This script will demonstrate a number of things.  1.) C<Clone::Fast::clone> will, automagically call the hook
on all instances of the Hookable.  Though the hash_stuff key will automatically be cloned before the hook is ever
called.  Subsiquently, the hashes in both values of hookable in the hash will be references of one another, though
not references to the originating object.  The Hookable->new() object, on the other hand, will not be referenced
to anything of the similar like.

As a secondary note, it was originally thought to allow for hooks to show up before and after the cloning of the
object.  Though, that would allow for the full change of the cloning type; this would be very bad.  Also, given
that it is somewhat reasonable to believe hooks will only be used with inside out objects, we can also assume the
cloning of a simple referent will be so lightweight that there will still be the benifit of having clone hook into
the object.  If anyone has beef with this paradigm, let me know and I'll change it.

=head1 CONFIGURATION VARIABLES 

=over

=item $Clone::Fast::ALLOW_HOOKS

The C<ALLOW_HOOKS> variable will allow for the toggling behavior, telling C<Clone::Fast> to check for
hooks when cloning objects.  (See C<PRGRAMATIC HOOKS> for more details).  The varialble will default
to 'on', where C<Clone::Fast> will always check each object for hooks defined within the object.

	use Clone::Fast qw( clone );
	
	$Clone::Fast::ALLOW_HOOKS = 1; # No need, this is default

	my $object = HasHooks->new();

	package HasHooks;

	use strict;
	use warnings;

	sub new { bless {}, shift }

	sub CLONEFAST_clone {
		my ( $clone, $source ) = @_;

		# Re-assigning the reference will now return the reference from the
		# C<Clone::Fast::clone> when cloning a HasHooks object, rather than
		# a cloned reference to the object.
		$clone = { 'object' => $clone };
		return $clone;
	}

=item $Clone::Fast::BREAK_REFS

	use Clone::Fast qw( clone );
	$Clone::Fast::BREAK_REFS = 1;

	my $foo = { 'a' => 'b' };
	my $bar = { 'a' => $foo, 'b' => $foo };

	my $baz = clone( $bar );

	print "\$foo and \$bar are different references\n" if ( $foo ne $bar );
	print "\$foo->{'a'} and \$bar->{'a'} are different references\n" if ( $foo->{'a'} ne $bar->{'a'} );
	print "\$foo->{'a'} and \$foo->{'b'} are no longer the same\n" if ( $foo->{'a'} ne $bar->{'b'} );

You will see that by adding the BREAK_REFS flag, you will change the overall behavior of the routine.
The BREAK_REFS flag must, simply, have truthfullness (as far as Perl is concerned) in order to be 'on'.

Whereas:

	$Clone::Fast::BREAK_REFS = 1;

	# Will do the same thing as:
	
	$Clone::Fast::BREAK_REFS = 'yes';

	# Will do the same thing as:
	
	$Clone::Fast::BREAK_REFS = ( 2 != 1 );

Albeit handy, this feature may also slow down the module by some degree.  Therefore, there is some flexibility
into whether or not you need to use this, and the functionality can be compiled out of the object; speeding up
the cloning ability.  Therefore, Re-compiling the mdule without MINDFUL_REFS will increase the speed of the
module by a degree of 3x!  If you KNOW you will never use the $Clone::Fast::BREAK_REFS and are confident
with manually installing Perl modules from source, it is recommended you do so.  There are comments in the XS source
that will detail how to do this.

This configuration only applies to the C<Clone::Fast::clone> routine.


=back

=head1 EXAMPLES

=over

=item Using Clone::Fast::clone

C<Clone::Fast::clone> is an exported routine.  You can either use it as such, or simply call it
directly on the package.

Example w/ export:

	use Clone::Fast qw( clone );

	my $source = { 'a' => 'b' };
	my $clone  = clone( $source );

Example w/o export

	use Clone::Fast;

	my $source = { 'a' => 'b' };
	my $clone  = Clone::Fast::clone( $source );

=item Using Clone::Fast::(is_)?circular

The C<Clone::Fast::(is_)?circular> routines will allow you to test whether or not a structure
contains a ciruclar reference or not.

=back

=head1 GOTCHAS/WARNINGS

=over

=item bless()'ed references (Perl objects)

This module works great for blessed references, how ever the paradigm changes when trying to clone
inside out objects (or Conway's 'flywaight' style of object creation).  Clone does not, nor will not,
clone the stash of an object's class; this would break more than anything.  Given this, HOOKS have
been provided in order to programatically handle wierd stuff like this.  I am hoping applications,
developers and all of the like whom are using inside out objects will know what the heck it is I'm
talking about here.  There is a lot more information about this in the PROGRAMATIC HOOKS section.

=back

=over

=item ithreads

I really have no idea how this will work in a treadded environment.  It should be OK, but there is no
development that has taken this into account.

=back

=over

=item Hooks

Hooks are pretty new, and may have some problems within them. Please, if you find anything you don't expect;
feel free to bug it and I will try to patch it up
ASAP.

=back

=head1 SEE ALSO

=over

=item L<Storable>

This will, essentially, do the exact same thing as what this module does.  The difference being that Storable will
freeze the chunk of memory you are trying to clone, and thaw that binary chunk to another piece of memory.  This works
well, yet is very slow.  Subsiquently, Storable, as of Perl 5.8, is CORE; and may be more trusted than this :)

=item L<Clone>

The 'basis' of C<Clone::Fast>, where L<Clone> is simply a very optimized version of C<Clone::Fast>.  Where hooks, some
exported routines and advanced functionality have been removed.

=item L<Clone::More>

The counter-part and un-optimized version of L<Clone::Fast>

=back

=head1 AUTHOR

Trevor Hall, E<lt>wazzuteke@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Trevor Hall

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
