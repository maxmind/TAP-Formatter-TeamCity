use strict;
use warnings;

use lib 't/lib';

use IPC::Run3 qw(run3);
use Path::Class;
use Path::Class::Rule;

use Test::More;
use Test::Differences;

test_formatter($_) for <t/test-data/basic/*>;
test_formatter('t/test-data/basic');

done_testing;

sub test_formatter {
    my $data_dir = shift;
    my @to_run = Path::Class::Rule->new->file->name(qr/\.st/)->all($data_dir);
    my $expected = join q{},
        map { scalar $_->dir->file('expected.txt')->slurp } @to_run;

    my @prove
        = qw( prove --lib --merge --verbose --formatter TAP::Formatter::TeamCity );
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

    $_ =~ s{\n+$}{\n} for $actual, $expected;

    # These hacks exist to replace user-specific paths with some sort of fixed
    # test. Long term, it'd be better to test the formatter by feeding it TAP
    # output directly rather than running various test files with the
    # formatter in place.
    $actual =~ s{(#\s+at ).+/Moose([^\s]+) line \d+}{${1}CODE line XXX}g;
    $actual =~ s{\(\@INC contains: .+?\)}{(\@INC contains: XXX)}sg;

    # The error message for attempting to load a module that doesn't exist was
    # changed in 5.18.0.
    $expected
        =~ s{\Q(you may need to install the SomeNoneExistingModule module) }{}g
        if $] < 5.018;

    eq_or_diff_text $actual, $expected, "running tests in $data_dir";
}
