use ExtUtils::MakeMaker;

# perl Makefile.PL -d to enable -g flag for gdb.
my $DEBUG = grep $_ eq '-d', @ARGV;

WriteMakefile(
    NAME          => 'Clone::Fast',
    VERSION_FROM  => 'lib/Clone/Fast.pm',
    PREREQ_PM     => { 'Test::More' => 0, },
    ABSTRACT_FROM => 'lib/Clone/Fast.pm',
    AUTHOR        => 'Trevor Hall <wazzuteke@cpan.org>',

    LIBS   => [''],     # e.g., '-lm'
    DEFINE => '',       # e.g., '-DHAVE_SOMETHING'
    INC    => '-I.',    # e.g., '-I. -I/usr/include/other'

    # Un-comment this if you add C files to link with later:
    OBJECT => '',       # '$(O_FILES)', # link all the C files too

    OPTIMIZE => $DEBUG ? '-g' : '-O2',
);
