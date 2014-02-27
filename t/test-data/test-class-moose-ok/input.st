use strict;
use warnings;

use lib 't/lib';

use TAP::Formatter::TeamCity::Test::SimpleOK;

use Test::Class::Moose;

Test::Class::Moose
    ->new(test_classes => [qw(TAP::Formatter::TeamCity::Test::SimpleOK)])
    ->runtests;

