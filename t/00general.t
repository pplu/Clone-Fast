use strict;
use warnings;
use Test::More;

my @structures;

BEGIN {
    @structures = (
        1,
        '1',
        1.0,
        '1.0',
        [qw( one )],
        [qw( one two three four five )],
        { 'key' => 'value' },
        { 'key' => { 'key' => 'value' } },

        # More complex
        [   {   'key' => {
                    'arr' => [qw( some thing here )],
                    'AoH' =>
                        [ { 'a' => { 'b' => { 'c' => { 'd' => 'e' } } } } ],
                }
            },
            [   [   'key' => {
                        'arr' => [qw( some thing here )],
                        'AoH' => [
                            { 'a' => { 'b' => { 'c' => { 'd' => 'e' } } } }
                        ],
                    }
                ],
            ],
        ],
    );
    plan( tests => 1 + @structures );
}

use Clone::Fast qw( clone );
use_ok('Clone::Fast');

for (@structures) {
    is_deeply( $_, clone($_),
        join( ' ', 'A', ref($_), qw( structure was cloned appropriately ) ) );
}
