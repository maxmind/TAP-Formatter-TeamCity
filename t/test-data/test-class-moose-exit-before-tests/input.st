use strict;
use warnings;

use lib 't/lib';

use TAP::Formatter::TeamCity::Test::ExitFast;

Test::Class::Moose
    ->new(test_classes => [qw(TAP::Formatter::TeamCity::Test::ExitFast)])
    ->runtests;

