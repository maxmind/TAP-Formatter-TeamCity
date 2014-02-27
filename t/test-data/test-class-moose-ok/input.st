use strict;
use warnings;

use lib 't/lib';

use TAP::Formatter::TeamCity::Test::SimpleOK;

Test::Class::Moose
    ->new(test_classes => [qw(TAP::Formatter::TeamCity::Test::SimpleOK)])
    ->runtests;

