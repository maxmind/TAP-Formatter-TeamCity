package TAP::Formatter::TeamCity;

use 5.010;

use strict;
use warnings;

our $VERSION = '0.005';

use TeamCity::BuildMessages qw(:all);
use TAP::Formatter::Session::TeamCity;
use TAP::Parser::Result::Test;

use base qw(TAP::Formatter::Base);

my $LastTestName;
my $LastTestResult;
my $IsLastSuiteEmpty;
my @SuiteNameStack;
my $TestOutputBuffer  = q{};
my $SuiteOutputBuffer = q{};

sub open_test {
    my ( $self, $test, $parser ) = @_;

    # last test file could have died with no test/suite finishing
    # we must report the error
    $self->_recover_from_catastrophic_death if @SuiteNameStack;

    my $session = TAP::Formatter::Session::TeamCity->new(
        {
            name       => $test,
            formatter  => $self,
            parser     => $parser,
            show_count => 0,
        }
    );

    $self->_start_suite($test);

    while ( defined( my $result = $parser->next ) ) {
        $self->_handle_event($result);
        $session->result($result);
    }

    {
        my $no_tests_message
            = 'Tests were run but no plan was declared and done_testing';
        if ( $TestOutputBuffer =~ /^$no_tests_message\(\) was not seen\.$/m )
        {
            $self->_recover_from_catastrophic_death;
        }
        else {
            if ( !$self->_test_finished && $SuiteOutputBuffer ) {
                my $suite_type = @SuiteNameStack == 1 ? 'file' : 'subtest';
                my $test_name
                    = "Test died before reaching end of $suite_type";
                my $test_result = TAP::Parser::Result::Test->new(
                    {
                        'ok'          => 'not ok',
                        'explanation' => q{},
                        'directive'   => q{},
                        'type'        => 'test',
                        'test_num'    => 1,
                        'description' => "- $test_name",
                        'raw'         => "not ok 1 - $test_name",
                    }
                );
                $self->_test_started($test_result);
                $TestOutputBuffer  = $SuiteOutputBuffer;
                $SuiteOutputBuffer = q{};
                $self->_test_finished;
            }
            {
                my @copy = @SuiteNameStack;
                $self->_finish_suite for @copy;
            }
        }
    }

    return $session;
}

sub _recover_from_catastrophic_death {
    my $self = shift;
    if ($LastTestResult) {
        my $test_num    = $LastTestResult->number;
        my $description = $LastTestResult->description;
        $LastTestResult = TAP::Parser::Result::Test->new(
            {
                'ok'          => 'not ok',
                'explanation' => q{},
                'directive'   => q{},
                'type'        => 'test',
                'test_num'    => $test_num,
                'description' => "- $description",
                'raw'         => "not ok $test_num - $description",
            }
        );
    }
    else {
        my $suite_type  = @SuiteNameStack == 1 ? 'file' : 'subtest';
        my $test_name   = "Test died before reaching end of $suite_type";
        my $test_result = TAP::Parser::Result::Test->new(
            {
                'ok'          => 'not ok',
                'explanation' => q{},
                'directive'   => q{},
                'type'        => 'test',
                'test_num'    => 1,
                'description' => "- $test_name",
                'raw'         => "not ok 1 - $test_name",
            }
        );
        $self->_test_started($test_result);
    }
    $self->_test_finished;
    {
        my @copy = @SuiteNameStack;
        $self->_finish_suite for @copy;
    }
}

#-----------------------------------------------------------------------------

sub _handle_event {
    my ( $self, $result ) = @_;
    my $type    = $result->type;
    my $handler = "_handle_$type";

    eval { $self->$handler($result); 1 }
        || die qq{Can't handle result of type=$type: $@};
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _handle_test {
    my ( $self, $result ) = @_;
    unless ( $self->_test_finished ) {
        if ( $result->directive eq 'SKIP' ) {

            # when tcm skips methods, we get 1st a Subtest message
            # then "ok $num # skip $message"
            ( my $reason ) = ( $result->raw =~ /^\s*ok \d+ # skip (.*)$/ );
            my %name = ( name => 'Skipped' );
            teamcity_emit_build_message(
                'testStarted', %name,
                captureStandardOutput => 'true'
            );
            teamcity_emit_build_message(
                'testIgnored', %name,
                message => $reason
            );
            $self->_finish_test('Skipped');
            $self->_finish_suite;
            return;
        }
    }

    my $test_name = $self->_compute_test_name($result);

    $self->_test_started($result) unless $self->_finish_suite($test_name);
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _handle_comment {
    my ( $self, $result ) = @_;
    my $comment = $result->raw;
    if ( $comment =~ /^\s*# Looks like you failed \d+/ ) {
        $self->_test_finished;
        return;
    }
    $comment =~ s/^\s*#\s?//;
    $comment =~ s/\s+$//;
    return if $comment =~ /^\s*$/;
    $TestOutputBuffer .= "$comment\n";
    $self->_print_raw($result);
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _handle_unknown {
    my ( $self, $result ) = @_;
    my $raw = $result->raw;
    if ( $raw =~ /^\s*# Subtest: (.*)$/ ) {
        $self->_test_finished;
        $self->_start_suite($1);
    }
    elsif ( $raw =~ /^\s*(not )?ok (\d+)( - (.*))?$/ ) {
        my $is_ok     = !$1;
        my $test_num  = $2;
        my $test_name = $4;
        $self->_test_finished;
        $test_name = 'NO TEST NAME' unless defined $test_name;

        my $todo;
        if ( $test_name =~ s/ # TODO (.+)$// ) {
            $todo = $1;
        }

        my $f = $self->_finish_suite($test_name);
        unless ($f) {
            my $ok = $is_ok || $todo ? 'ok' : 'not ok';
            my $actual_result = TAP::Parser::Result::Test->new(
                {
                    'ok'          => $ok,
                    'explanation' => $todo // q{},
                    'directive'   => $todo ? 'TODO' : q{},
                    'type'        => 'test',
                    'test_num'    => $test_num,
                    'description' => "- $test_name",
                    'raw'         => "$ok $test_num - $test_name",
                }
            );
            $self->_test_started($actual_result);
        }
    }
    elsif ( $raw =~ /^\s*# Looks like you failed \d+/ ) {
        $self->_test_finished;
    }
    elsif ( $raw =~ /^\s+ok \d+ # skip (.*)$/ && !$LastTestResult ) {

        # when tcm skips methods, we get 1st a Subtest message
        # then "ok $num # skip $message"
        my $reason = $1;
        my %name = ( name => 'Skipped' );
        teamcity_emit_build_message(
            'testStarted', %name,
            captureStandardOutput => 'true'
        );
        teamcity_emit_build_message(
            'testIgnored', %name,
            message => $reason
        );
        $self->_finish_test('Skipped');
        $self->_finish_suite;
    }
    elsif ( $raw =~ /^\s*#/ ) {
        ( my $clean_raw = $raw ) =~ s/^\s*#\s?//;
        $clean_raw =~ s/\s+$//;
        return if $clean_raw =~ /^\s*$/;
        $TestOutputBuffer .= "$clean_raw\n" if $LastTestResult;
        $self->_print_raw($result);
    }
    elsif ($raw =~ qr{\[checked\] .+$}
        or $raw =~ qr{Deep recursion on subroutine "B::Deparse} ) {
        print("# $raw\n") or die "Can't print to STDOUT: $!";
    }
    elsif ( $raw !~ /^\s*$/ ) {
        $SuiteOutputBuffer .= $raw;
        $self->_print_raw($result)
            unless $raw =~ /^\s*\d+\.\.\d+(?: # SKIP.*)?$/;
    }
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _handle_plan {
    my ( $self, $result ) = @_;
    unless ( $self->_test_finished ) {
        if ( $result->directive eq 'SKIP' ) {
            my %name = ( name => 'Skipped' );
            teamcity_emit_build_message(
                'testStarted', %name,
                captureStandardOutput => 'true'
            );
            teamcity_emit_build_message(
                'testIgnored', %name,
                message => $result->explanation,
            );
            $self->_finish_test('Skipped');
        }
    }
}

sub _test_started {
    my ( $self, $result ) = @_;
    my $test_name = $self->_compute_test_name($result);
    my %name = ( name => $test_name );
    teamcity_emit_build_message(
        'testStarted', %name,
        captureStandardOutput => 'true'
    );
    $LastTestName   = $test_name;
    $LastTestResult = $result;
}

sub _test_finished {
    my ($self) = @_;
    return unless $LastTestResult;
    $self->_emit_teamcity_test_results( $LastTestName, $LastTestResult );
    $self->_finish_test($LastTestName);
    return 1;
}

sub _emit_teamcity_test_results {
    my ( $self, $test_name, $result ) = @_;

    my $buffer = $TestOutputBuffer;
    $TestOutputBuffer = q{};
    chomp $buffer;

    my %name = ( name => $test_name );

    if ( $result->has_todo || $result->has_skip ) {
        teamcity_emit_build_message(
            'testIgnored', %name,
            message => $result->explanation
        );
        return;
    }

    unless ( $result->is_ok ) {
        teamcity_emit_build_message(
            'testFailed', %name,
            message => ( $result->is_ok ? 'ok' : 'not ok' ),
            details => $buffer
        );
    }
}

sub _compute_test_name {
    my ( $self, $result ) = @_;
    my $description = $result->description;
    my $test_name = $description eq q{} ? $result->explanation : $description;
    $test_name =~ s/^-\s//;
    $test_name = 'NO TEST NAME' if $test_name eq q{};
    return $test_name;
}

sub _print_raw {
    my ( $self, $result ) = @_;
    print( $result->raw . "\n" ) or die "Can't print to STDOUT: $!";
}

sub _finish_test {
    my ( undef, $test_name ) = @_;
    my %name = ( name => $test_name );
    teamcity_emit_build_message( 'testFinished', %name );
    undef $LastTestName;
    undef $LastTestResult;
    $IsLastSuiteEmpty = 0;
}

sub _start_suite {
    my ( undef, $suite_name ) = @_;
    push @SuiteNameStack, $suite_name;
    $IsLastSuiteEmpty = 1;
    teamcity_emit_build_message( 'testSuiteStarted', name => $suite_name );
}

sub _finish_suite {
    my ( $self, $name ) = @_;
    return 0 unless @SuiteNameStack;

    $name //= $SuiteNameStack[-1];

    my $result = $name eq $SuiteNameStack[-1];
    if ($result) {
        if ($IsLastSuiteEmpty) {
            my $suite_type  = @SuiteNameStack == 1 ? 'file' : 'subtest';
            my $test_name   = "Test died before reaching end of $suite_type";
            my $test_result = TAP::Parser::Result::Test->new(
                {
                    'ok'          => 'not ok',
                    'explanation' => q{},
                    'directive'   => q{},
                    'type'        => 'test',
                    'test_num'    => 1,
                    'description' => "- $test_name",
                    'raw'         => "not ok 1 - $test_name",
                }
            );
            $self->_test_started($test_result);
            $TestOutputBuffer  = $SuiteOutputBuffer;
            $SuiteOutputBuffer = q{};
            $self->_test_finished;
        }
        pop @SuiteNameStack;
        $SuiteOutputBuffer = q{};
        $IsLastSuiteEmpty  = 0;
        teamcity_emit_build_message( 'testSuiteFinished', name => $name );
    }
    return $result;
}

sub _fix_suite_name {
    my $suite_name = pop;
    for ($suite_name) {
        s{/}{.}g;
        s/::/./g;
    }
    return $suite_name;
}

1;

# ABSTRACT: Emit test results as TeamCity service messages

__END__

=pod

=head1 SYNOPSIS

   # When using prove(1):
   prove --merge --formatter TAP::Formatter::TeamCity my_test.t

   # From within a Module::Build subclass:
   sub tap_harness_args { return {formatter_class => 'TAP::Formatter::TeamCity'} }

=head1 DESCRIPTION

L<TAP::Formatter::TeamCity> is a plugin for L<TAP::Harness> that emits
TeamCity service messages to the console, rather than the usual output. The
TeamCity build server is able to process these messages in the build log and
present your test results in its web interface (along with some nice
statistics and graphs).

This is very much alpha code, and is subject to change.

=head1 SEE IT IN ACTION

If you're not familiar with continuous integration systems (in general) or
TeamCity (in particular), you're welcome to explore the TeamCity build server
we use for the L<Perl::Critic> project. Just go to
L<http://perlcritic.com:8111> and click on the "Login as a Guest" link. From
there, you can browse the build history, review test results, and examine the
artifacts (such as test coverage reports and performance profiles). All the
information you see there was generated from TAP-based tests using this module
to communicate the results to the TeamCity server.

=head1 SUGGESTED USAGE

The TeamCity service messages are generally not human-readable, so you
probably only want to use this Formatter when the tests are being run by a
TeamCity build agent and the L<TAP::Formatter::TeamCity> module is available.
I suggest using an environment variable to activate the Formatter. If you're
using a recent version of L<Module::Build> you might do something like this in
your F<Build.PL> file:

  # Regular build configuration here:
  my $builder = Module::Build->new( ... )

  # Specify this Formatter, if the environment variable is set:
  $builder->tap_harness_args( {formatter_class => 'TAP::Formatter::TeamCity'} )
    if $ENV{RUNNING_UNDER_TEAMCITY} && eval {require TAP::Formatter::TeamCity};

  # Generate build script as ususal:
  $builder->create_build_script;

And then set the C<RUNNING_UNDER_TEAMCITY> environment variable to a true
value in your TeamCity build configuration.

TODO: Figure out if/how to do this with L<ExtUtils::MakeMaker>.

=head1 LIMITATIONS

TeamCity comes from a jUnit culture, so it doesn't understand SKIP and TODO
tests in the same way that Perl testing harnesses do. Therefore, this
formatter simply instructs TeamCity to ignore tests that are marked SKIP or
TODO.

Also, I haven't yet figured out how to transmit test diagnostic messages, so
those probably won't appear in the TeamCity web interface. But I'm working on
it :)

=head1 SOME EXTRA CANDY

TeamCity, CruiseControl, and some other continuous integration systems are
oriented towards Java code. As such, they don't have native support for Perl's
customary build tools like L<Module::Build>. But they do have nice support for
running Ant. This distribution contains an Ant build script at F<build.xml>
which wraps L<Module::Build> actions in Ant targets. This makes it easier to
configure TeamCity and CruiseControl to build your Perl code. If you're using
the EPIC plug-in with Eclipse, you can also use this Ant script to build your
code from within the IDE. Feel free to copy the F<build.xml> into your own
projects.

=head1 SEE ALSO

L<TeamCity::BuildMessages>

=cut
