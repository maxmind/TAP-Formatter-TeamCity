use strict;
use warnings;

use lib 't/lib';

use IPC::Run3 qw(run3);
use Path::Class qw(file);

use Test::More;
use Test::Differences;

{
    my @prove
        = qw( prove --lib --merge --verbose --formatter TAP::Formatter::TeamCity -j 2 );
    my @to_run = qw(
        t/test-data/basic/simple-ok/input.st
        t/test-data/basic/subtest-ok/input.st
    );

    my ( @stdout, $stderr );
    run3(
        [ @prove, @to_run ],
        \undef,
        \@stdout,
        \$stderr,
    );

    if ($stderr) {
        fail('got unexpected stderr');
        diag($stderr);
    }

    # we don't want to compare the test summary, but it has a different number
    # of lines depending on $is_ok so we chomp off the correct number of lines
    my @output;
    for my $l (@stdout) {
        last
            if $l =~ /Parse errors:/
            || $l =~ /^Files=\d+/
            || $l =~ /^Test Summary Report/
            || $l =~ /^All tests successful\./;

        push @output, $l;
    }

    my $actual = join q{}, @output;

    ## no critic (RegularExpressions::ProhibitComplexRegexes)
    like(
        $actual,
        qr{
              ^ \#\#\Qteamcity[progressMessage 'starting t/test-data/basic/simple-ok/input.st']\E $ \n
              (?:^.+$ \n)*
              ^ \#\#\Qteamcity[testSuiteStarted name='t/test-data/basic/simple-ok/input.st']\E $ \n
              ^ \#\#\Qteamcity[testStarted captureStandardOutput='true' name='simple-ok-msg']\E $ \n
              ^ \#\#\Qteamcity[testFinished name='simple-ok-msg']\E $ \n
              ^ \#\#\Qteamcity[testSuiteFinished name='t/test-data/basic/simple-ok/input.st']\E $ \n
        }xm,
        'got expected output for simple-ok/input.st'
    );

    like(
        $actual,
        qr{
              ^\#\#\Qteamcity[progressMessage 'starting t/test-data/basic/subtest-ok/input.st']\E $ \n
              (?:^.+$ \n)*
              ^\#\#\Qteamcity[testSuiteStarted name='t/test-data/basic/subtest-ok/input.st']\E $ \n
              ^\#\#\Qteamcity[testStarted captureStandardOutput='true' name='subtest-ok-msg-1']\E $ \n
              ^\#\#\Qteamcity[testFinished name='subtest-ok-msg-1']\E $ \n
              ^\#\#\Qteamcity[testSuiteStarted name='subtest-A-name']\E $ \n
              ^\#\#\Qteamcity[testStarted captureStandardOutput='true' name='subtest-ok-msg-2']\E $ \n
              ^\#\#\Qteamcity[testFinished name='subtest-ok-msg-2']\E $ \n
              ^\#\#\Qteamcity[testSuiteFinished name='subtest-A-name']\E $ \n
              ^\#\#\Qteamcity[testSuiteFinished name='t/test-data/basic/subtest-ok/input.st']\E $ \n
        }xm,
        'got expected output for subtest-ok/input.st'
    );
}

done_testing();
