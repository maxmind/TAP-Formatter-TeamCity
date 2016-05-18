use strict;
use warnings;

use Test::More;

warn "Random stderr 1\n";
ok 1, 'first test';
warn "Random stderr 2\n";

subtest(
    'subtest',
    sub {
        warn "In subtest 1\n";
        ok 1, 'starting subtest';
        warn "In subtest 2\n";
    }
);

warn "Random stderr 3\n";
ok 1, 'last test';
warn "Random stderr 4\n";

done_testing;
