#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

// All the behaviroal definitions begin and end here.  For more
// infomration on these definitions, please review the POD
// #define TRACE_LOG
#define MINDFUL_REFS
//#define MINDFUL_CIR
#define ALLOW_HOOKS

// Define some logging functions
#ifdef TRACE_LOG
#define xT()          printf( "%s:%d: ", __FUNCTION__, __LINE__ )
#define xPNL()        printf( "\n" )
#define TRACE(m)      xT() && printf m
#define SV_TRACE(s,c) xT() && printf( "$src = %d(0x%x); $cln = %c(0x%x)", SvREFCNT( s ), s, SvREFCNT( c ), c  ) && xPNL()
#else
#define TRACE(m)
#define SV_TRACE(s,c)
#endif

// The SV_(TRIAGE|STORE)? macros are used inline to determine if/when/how
// we should store the current { source => clone } in order to sustain
// circular and internal structure references
#ifdef MINDFUL_REFS
#define SV_STORE(s,c) do {\
	if ( ! hv_store( sv_cache, (char*)s, PTRSIZE, SvREFCNT_inc( c ), 0 ) )\
		warn( "Warning: Invalid assignment of value to HASH key!" );\
} while( 0 )\

#define SV_TRIAGE(s,c) do{\
	if ( KEEP_REF() && SvREFCNT( s ) > 1 )\
		SV_STORE( s, c );\
} while( 0 )\

#else
#define SV_STORE(s,c)
#define SV_TRIAGE(s,c)
#endif

// This macro will be for the hooking of Clone-type objects that are
// being cloned.  Using configuration variables defined in the Perl
// package, we can turn this macro on and/or off programatically.
// see POD for more details
bool    watch_hooks;
#ifdef  ALLOW_HOOKS
#define SV_HOOK_OBJECT(s,c) do{\
	sv_bless( c, SvSTASH( SvRV( s ) ) );\
	if ( watch_hooks ) {\
		GV * clone_hook = gv_fetchmethod_autoload( 	SvSTASH( SvRV( source ) ), "CLONEFAST_clone", FALSE );\
		if ( clone_hook ) {\
			dSP;\
			int count;\
			ENTER;\
			SAVETMPS;\
			PUSHMARK(SP);\
			XPUSHs( sv_2mortal( c ) );\
			XPUSHs( sv_2mortal( s ) );\
			PUTBACK;\
			count = perl_call_sv( (SV*)clone_hook, G_SCALAR );\
			TRACE( ( "Return of %d returned from hook\n", count ) );\
			SPAGAIN;\
			TRACE( ( "HookING $source=0x%x, $clone=0x%x\n", s, c ) );\
			if ( SvTRUE( ERRSV ) ) {\
				STRLEN n_a;\
				printf ("Something went impossibly wrong: %s\n", SvPV(ERRSV, n_a));\
				POPs;\
			}\
			else if ( count ){\
				c = SvREFCNT_inc( POPs );\
				s = SvREFCNT_inc( s );\
			}\
			else\
				croak( "CLONEFAST_store did not return anticipated value; expected 1 return, got %d\n", count );\
			if ( ! SvROK( c ) )\
				croak( "CLONEFAST_store expected reference as return, got %d\n", SvTYPE( c ) );\
			TRACE( ( "HookED $source=0x%x, $clone=0x%x\n", s, c ) );\
			PUTBACK;\
			FREETMPS;\
			LEAVE;\
		}\
	}\
} while( 0 )\

#else
#define SV_HOOK_OBJECT(s,c) do{\
	sv_bless( c, SvSTASH( SvRV( s ) ) );\
} while( 0 )\

#endif

// Used for the manipulaton of internal referencing
bool break_refs;
#define KEEP_REF()     ( ! break_refs ) 

// Used for the toggling of circular reference checks
bool ignore_circular;
#define CHECK_CIRCLE() ( ! ignore_circular )

// General constants we can use
#define MAGIC_QR      'r'
#define MAGIC_TAINT   't'
#define MAGIC_BACKREF '<'
#define MAGIC_USERDEF '~'
#define MAGIC_ARYLEN  '@'

// Primary and recursive cloning functions
static SV * sv_clone( SV *         );
static SV * hv_clone( HV *, HV *   );
static SV * av_clone( AV *, AV *   );
static SV * mg_clone( SV *         );
static SV * sv_seen ( SV *         );

// Generalized and listed cloning functions
static SV * clone_sv( SV * );
static SV * clone_rv( SV * );
static SV * clone_av( SV * );
static SV * clone_hv( SV * );
static SV * no_clone( SV * );

// Dynamic dispatching table, mapping the particular
// data type to the enumerated-ish cloning function
typedef SV * ( * sv_clone_t )( SV * source );
static sv_clone_t sv_clone_table[] = {
	(sv_clone_t)clone_sv,   // SVt_NULL
#if PERL_VERSION >= 9
	(sv_clone_t)no_clone,   // SVt_BIND
#endif
	(sv_clone_t)clone_sv,   // SVt_IV
	(sv_clone_t)clone_sv,   // SVt_NV
	(sv_clone_t)clone_rv,   // SVt_RV
	(sv_clone_t)clone_sv,   // SVt_PV
	(sv_clone_t)clone_sv,   // SVt_PVIV
	(sv_clone_t)clone_sv,   // SVt_PVNV
	(sv_clone_t)clone_sv,   // SVt_PVMG
#if PERL_VERSION <= 8
	(sv_clone_t)no_clone,   // SVt_PVBM
#endif
#if PERL_VERSION >= 9
	(sv_clone_t)no_clone,   // SVt_GV
#endif
	(sv_clone_t)no_clone,   // SVt_PVLV
	(sv_clone_t)clone_av,   // SVt_PVAV
	(sv_clone_t)clone_hv,   // SVt_PVHV
	(sv_clone_t)no_clone,   // SVt_CV
#if PERL_VERSION <= 8
	(sv_clone_t)no_clone,   // SVt_GV	
#endif
	(sv_clone_t)no_clone,   // SVt_FM
	(sv_clone_t)no_clone,   // SVt_IO
};

// Simple accessor into the sv_clone[] table //
#define SV_CLONE(x) (*sv_clone_table[x])

// Used to determine internal structure references
HV * sv_cache;

// Used to better track circular references
static bool sv_is_circular   ( SV * );
static bool sv_deeply_circular( SV * );
HV * sv_circle;
I32  sv_depth;

// Used to programatically determine what the heck to do
// with circular references
static SV * build_circular_return( SV *, I32 );

static SV * sv_clone( SV * source ) {
	SV * clone;

	if ( SvREFCNT( source ) > 1 ) {
#ifdef MINDFUL_CIR
		if ( CHECK_CIRCLE() && sv_is_circular( source ) )
			 return build_circular_return( source, (I32)SvIVX(perl_get_sv( "Clone::Fast::CIRCULAR_ACTION", TRUE ) ) );
#endif
#ifdef MINDFUL_REFS
		if ( KEEP_REF() && ( clone = sv_seen( source ) ) )
			return clone;
#endif
	}
	
	// Will make a single call to an indexed list of possible
	// cloning functions.  This should allow for a much more
	// liniar performance implications
	clone = ( ( SvMAGICAL( source ) ) ? mg_clone( source ) : SV_CLONE( SvTYPE( source ) )( source ) );
	sv_depth++;
	
	SV_TRACE( source, clone );
	return clone;
}

static SV * build_circular_return( SV * source, I32 action ) {
	SV * clone;

	TRACE( ( "Cir => 0x%x; Act = %d\n", source, action ) );

	// Currently supported options.
	// 0b000  ( 0 ) => Will continue the circular reference (default)
	// 0b001  ( 1 ) => Will return an incremented version of the source
	// 0b010  ( 2 ) => Will undef the value
	// 0b100  ( 4 ) => Will warn about the circular reference, acting as 0b000
	switch( action ) {
		case 0:
			if ( ( clone = sv_seen( source ) ) )
				return clone;
			return build_circular_return( source, 1 );
			break;
		case 1:
			return SvREFCNT_inc( source );
			break;
		case 2:
			return &PL_sv_undef;
			break;
		case 4:
			warn( "Warning: Circular reference detected at 0x%x", source );
			return build_circular_return( source, 0 );
			break;
		default:
			warn( "Invalid CIRCULAR_ACTION, using default\n" );
			return build_circular_return( source, 0 );
			break;
	}

	// Should NEVER get here with the switch(){default:};
	croak( "Unexpected behavior when building circular return" );
}

static SV * clone_hv( SV * source ) {
	HV * clone = newHV();
	
	// We can store off the new clone pointer now that we have it
	SV_TRIAGE( source, (SV*)clone );
		
	// Clone away
	return hv_clone( (HV*)source, clone );
}

static SV * clone_av( SV * source ) {
	AV * clone = newAV();

	// We can store off the new clone pointer now that we have it
	SV_TRIAGE( source, (SV*)clone );
	
	// Clone away
	return av_clone( (AV*)source, clone );
}

static SV * no_clone( SV * source ) {
	SV * clone = SvREFCNT_inc( source );
	
	TRACE( ( "Returning incrementned source\n" ) );
	
	// We can store off the new clone pointer now that we have it
	SV_TRIAGE( source, clone );
	
	return clone;
}

static SV * clone_rv( SV * source ) {
	SV *  clone;
	
	TRACE( ( "Ripping reference from source\n" ) );

	if ( ! SvROK( source ) ) {
		clone = SvREFCNT_inc( source );
		SV_TRIAGE( source, clone );
		return clone;
	}
	else {
		clone = newSV(0);
		SvUPGRADE( clone, SVt_RV );
		SV_TRIAGE( source, clone );
	}

	SvROK_on( clone );
	SvRV( clone ) = sv_clone( SvRV( source ) );
	
	if ( sv_isobject( source ) )
		SV_HOOK_OBJECT( source, clone );
	
	return clone;
}

static SV * clone_sv( SV * source ) {
	SV * clone;
	TRACE( ( "Cloning SVsv\n" ) );
	
	if ( SvROK( source ) )
		clone = clone_rv( source );
	else {
		clone = newSVsv( source );
		SV_TRIAGE( source, clone );
	}
	
	return clone;
}

static SV * hv_clone( HV * source, HV * clone ) {
	HE * iter = NULL;	

	TRACE( ( "Cloning HASH\n" ) );

	hv_iterinit( source );
	while ( iter = hv_iternext( source ) ) {
		SV * key = hv_iterkeysv( iter );
		hv_store_ent( clone, key, sv_clone( hv_iterval( source, iter ) ), 0 );
	}

	return (SV*)clone;
}

static SV * av_clone ( AV * source, AV * clone ) {
	int i;
	SV ** t_svp;

	TRACE( ( "Cloning ARRAY\n" ) );
	
	/* 
	 * Need to make sure the clone length is the same
	 * size as the source length; let Perl handle it
	 */
	if ( av_len( clone ) < av_len( source ) )
		av_extend( clone, av_len( source ) );

	for ( i = 0; i <= av_len( source ); i++ ) {
		t_svp = av_fetch( source, i, 0 );
		if ( t_svp )
			av_store( clone, i, sv_clone( *t_svp ) );
	}

	return (SV*)clone;
}

static SV * mg_clone( SV * source ) {
	SV    * clone;
	MAGIC * mg;
	bool    mg_flg = FALSE;

	//
	// This is a little different than the normal dispatching
	// algorithms, however is pretty close to the same to.
	//
	// TBD: This needs some serious clean up work.  Two case
	//      blocks and a conditional tree make for some slow
	//      copying of magic crap.  Though it seems to work ;)
	//
	switch( SvTYPE( source ) ) {
		case SVt_RV:
			clone = newSV(0);
			sv_upgrade( clone, 3 );
		case SVt_PVAV:
			clone = (SV*)newAV();
			break;
		case SVt_PVHV: 
			clone = (SV*)newHV();
			break;
		default:
			clone = source;
	}
	clone = SvREFCNT_inc( clone ); // Boink!

	for ( mg = SvMAGIC( source ); mg; mg = mg->mg_moremagic ) {
		SV    * obj = Nullsv;
		
		// How magic is it?	
		switch (mg->mg_type) {
			case MAGIC_QR:
				obj = mg->mg_obj;
				break;
			case MAGIC_TAINT:
				continue;
				break;
			case MAGIC_BACKREF:
				continue;
				break;
			case MAGIC_USERDEF:
			case MAGIC_ARYLEN:
				obj = mg->mg_obj;
				break;
			default:
				// TBD: Do we need to store this now, or will sv_clone() take
				//      care of it??
				if ( mg->mg_obj ) {
					obj = sv_clone( mg->mg_obj );
				}
		}
		mg_flg = TRUE;

		// Magicasize it!
		sv_magic( clone, obj, mg->mg_type, mg->mg_ptr, mg->mg_len );
	}

	if ( mg = mg_find( clone, MAGIC_QR ) )
		mg->mg_virtual = (MGVTBL*)NULL;

	// Now we can watch for the monitor flag
	if ( ! mg_flg ) {
		if ( SvTYPE( source ) == SVt_PVHV )
			clone = hv_clone( (HV*)source, (HV*)clone );
		else if ( SvTYPE( source ) == SVt_PVAV )
			clone = av_clone( (AV*)source, (AV*)clone );
		else if ( SvROK( source ) ) {
			SvROK_on( clone );
			SvRV( clone ) = sv_clone( SvRV( source ) );
			if ( sv_isobject( source ) )
				SV_HOOK_OBJECT( source, clone );
		}
	}
	
	return clone;
}

static SV * sv_seen ( SV * source ) {
	SV ** seen;

	SV_TRACE( source, source );
	
	if ( seen = hv_fetch( sv_cache, (char*)source, PTRSIZE, 0 ) )
		return SvREFCNT_inc( *seen ); 

	return NULL;
}

static bool sv_is_circular( SV * source ) {
	SV ** sv_monitor;
	SV ** sv_elem;
	AV *  av_monitor;
	int i;
	
	TRACE( ( "Testing for circularity at source 0x%x\n", source ) );

	// If the source hasn't been here yet, then initiate the HV key with the source
	if ( ! hv_exists( sv_circle, (char*)source, PTRSIZE ) ) {
		TRACE( ( "Source, 0x%x, not yet watched\n", source ) );
		av_monitor = newAV();
		av_push( av_monitor, SvREFCNT_inc( source ) );
		hv_store( sv_circle, (char*)source, PTRSIZE, (SV*)av_monitor, 0 );
		return FALSE;
	}
	else if ( ( sv_monitor = hv_fetch( sv_circle, (char*)source, PTRSIZE, 0 ) ) ) {
		TRACE( ( "Source, 0x%x, being watched...\n", source ) );
		av_monitor = (AV*)*sv_monitor;
		for ( i = 0; i <= av_len( av_monitor ); i++ ) {
			TRACE( ( "Source, 0x%x, against 0x%x\n", source, *sv_elem ) );
			sv_elem = av_fetch( av_monitor, i, 0 );
			if ( ( source == *sv_elem ) )
				return TRUE;
		}
		TRACE( ( "Source, 0x%x, not within ones self; continuing\n", source ) );
		av_push( av_monitor, SvREFCNT_inc( source ) );
		return FALSE;
	}
	else
		croak( "Circular integrity engine failed critically!\n" );
}

static bool sv_deeply_circular( SV * source ) {
	int i;
	SV   ** av_elem;
	HE   *  hv_iter;
	SV   *  hv_val;

	TRACE( ( "0x%x => %d (depth = %d)\n", source, SvTYPE( source ), sv_depth ) );
	
	if ( sv_is_circular( source ) )
		return TRUE;

	switch( SvTYPE( source ) ) {
		case  SVt_RV:
			return sv_deeply_circular( SvRV( source ) );
			break;
		case SVt_PVAV:
			for ( i = 0; i <= av_len( (AV*)source ); i++ ) {
				av_elem = av_fetch( (AV*)source, i, 0 );
				if ( av_elem && sv_deeply_circular( *av_elem ) )
					return TRUE;	
			}
			break;
		case SVt_PVHV:
			hv_iterinit( (HV*)source );
			while ( hv_iter = hv_iternext( (HV*)source ) ) {
				hv_val = hv_iterval( (HV*)source, hv_iter );	
				if ( hv_val && sv_deeply_circular( hv_val ) )
					return TRUE;
			}
			break;
		default:
			break;
	};

	sv_depth++;
	return FALSE;
}

MODULE = Clone::Fast		PACKAGE = Clone::Fast

PROTOTYPES: ENABLE

BOOT:
sv_cache   = newHV();
sv_circle  = newHV();

void clone( source )
	SV * source

	PREINIT:
	SV * clone = &PL_sv_undef;

	PPCODE:
#ifdef MINDFUL_REFS
	break_refs      = ( SvTRUE( perl_get_sv( "Clone::Fast::BREAK_REFS",      TRUE ) ) );
#endif
#ifdef MINDFUL_CIR
	ignore_circular = ( SvTRUE( perl_get_sv( "Clone::Fast::IGNORE_CIRCULAR", TRUE ) ) );
#endif
#ifdef ALLOW_HOOKS
	watch_hooks     = ( SvTRUE( perl_get_sv( "Clone::Fast::ALLOW_HOOKS", TRUE ) ) );
#endif
	clone = sv_clone( source );
	hv_clear( sv_cache );
#ifdef MINDFUL_CIR
	hv_clear( sv_circle );
	sv_depth = 0;
#endif
	EXTEND( SP, 1 );
	PUSHs ( sv_2mortal( clone ) );
