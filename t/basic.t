use strict;
use warnings;

use lib 't/lib';

use IPC::Run3 qw(run3);
use Path::Class qw(file);

use Test::More;
use Test::Differences;

test_formatter($_) for <t/test-data/basic/*>;

done_testing;

sub test_formatter {
    my $data_dir = shift;
    my $input    = file( $data_dir, 'input.st' );
    my $expected = file( $data_dir, 'expected.txt' )->slurp;

    my @prove
        = qw( prove --lib --merge --verbose --formatter TAP::Formatter::TeamCity );
    my ( @stdout, $stderr );
    run3(
        [ @prove, $input ],
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
    my $summary_index
        = $stdout[-3] =~ /Parse errors:/     ? -7
        : $stdout[-1] =~ /^Result: NOTESTS$/ ? -2
        : $? == 0                            ? -3
        :                                      -8;
    splice @stdout, $summary_index;
    my $actual = join q{}, @stdout;

    # These hacks exist to replace user-specific paths with some sort of fixed
    # test. Long term, it'd be better to test the formatter by feeding it TAP
    # output directly rather than running various test files with the
    # formatter in place.
    $actual =~ s{(#\s+at ).+/Moose([^\s]+) line \d+}{${1}CODE line XXX}g;
    $actual =~ s{\(\@INC contains: .+?\)}{(\@INC contains: XXX)}sg;

    $_ =~ s{\n+$}{\n} for $actual, $expected;

    # The error message for attempting to load a module that doesn't exist was
    # changed in 5.18.0.
    $expected
        =~ s{\Q(you may need to install the SomeNoneExistingModule module) }{}g
        if $] < 5.018;

    eq_or_diff_text $actual, $expected, "running test in $data_dir";
}

