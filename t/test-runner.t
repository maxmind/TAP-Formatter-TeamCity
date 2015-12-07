use strict;
use warnings;

use lib 't/lib';

use File::Temp qw(tempdir);
use Path::Class qw(dir file);

use Test::More;
use Test::Differences;

test_formatter($_) for <t/test-data/*>;

done_testing;

sub test_formatter {
    my $data_dir  = shift;
    my $input     = file( $data_dir, 'input.st' );
    my $expected  = file( $data_dir, 'expected.txt' )->slurp;
    my $tmp_dir   = dir( tempdir( CLEANUP => 1 ) );
    my $out_file  = $tmp_dir->file('actual.txt');
    my $prove     = 'prove --lib --merge --verbose';
    my $formatter = '--formatter TAP::Formatter::TeamCity';

    my $is_ok = !system("$prove $formatter $input > $out_file");

    # we don't want to compare the test summary, but it is
    # different number of lines depending on $is_ok
    # so we chomp off the correct number of lines

    my @actual = $out_file->slurp;
    my $pop
        = $actual[-3] =~ /Parse errors:/     ? 7
        : $actual[-1] =~ /^Result: NOTESTS$/ ? 2
        : $is_ok                             ? 3
        :                                      8;
    pop @actual for 1 .. $pop;
    my $actual = join q{}, @actual;

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

    eq_or_diff_text $actual, $expected, "running test in $data_dir";
}

