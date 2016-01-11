package TAP::Formatter::Session::TeamCity;

use strict;
use warnings;

our $VERSION = '0.10';

use TAP::Parser::Result::Test;
use Time::HiRes qw( time );

use base qw(TAP::Formatter::Session);

{
    my @accessors = map { '_tc_' . $_ } qw(
        last_test_name
        last_test_result
        is_last_suite_empty
        suite_name_stack
        test_output_buffer
        suite_output_buffer
        buffered_output
        output_handle
    );
    __PACKAGE__->mk_methods(@accessors);
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _initialize {
    my $self = shift;

    $self->SUPER::_initialize(@_);

    $self->_tc_suite_name_stack( [] );
    $self->_tc_test_output_buffer(q{});
    $self->_tc_suite_output_buffer(q{});

    my $buffered = q{};
    $self->_tc_buffered_output( \$buffered );

    if ( $self->_is_parallel ) {
        $self->_tc_message(
            'progressMessage',
            'starting ' . $self->name,
            1,
        );

        ## no critic (InputOutput::RequireCheckedOpen, InputOutput::RequireCheckedSyscalls)
        open my $fh, '>', \$buffered;
        $self->_tc_output_handle($fh);
    }
    else {
        $self->_tc_output_handle( \*STDOUT );
    }

    $self->_start_suite( $self->name );

    return $self;
}
## use critic

sub _is_parallel {
    return $_[0]->formatter->jobs > 1;
}

sub result {
    my $self   = shift;
    my $result = shift;

    my $type    = $result->type;
    my $handler = "_handle_$type";

    die qq{Can't handle result of type=$type}
        unless $self->can($handler);

    $self->$handler($result);
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _handle_test {
    my $self   = shift;
    my $result = shift;

    unless ( $self->_test_finished ) {
        if ( $result->directive eq 'SKIP' ) {

            # when tcm skips methods, we get 1st a Subtest message
            # then "ok $num # skip $message"
            ( my $reason ) = ( $result->raw =~ /^\s*ok \d+ # skip (.*)$/ );

            $self->_tc_message(
                'testStarted',
                {
                    name                  => 'Skipped',
                    captureStandardOutput => 'true'
                }
            );
            $self->_tc_message(
                'testIgnored',
                {
                    name    => 'Skipped',
                    message => $reason
                },
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
    my $self   = shift;
    my $result = shift;

    my $comment = $result->raw;
    if ( $comment =~ /^\s*# Looks like you failed \d+/ ) {
        $self->_test_finished;
        return;
    }
    $comment =~ s/^\s*#\s?//;
    $comment =~ s/\s+$//;
    return if $comment =~ /^\s*$/;
    $self->_tc_test_output_buffer(
        $self->_tc_test_output_buffer . "$comment\n" );
    $self->_maybe_print_raw( $result->raw );
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines, Subroutines::ProhibitExcessComplexity)
sub _handle_unknown {
    my $self   = shift;
    my $result = shift;

    my $raw = $result->raw;
    if ( $raw =~ /^\s*# Subtest: (.*)$/ ) {
        $self->_test_finished;
        $self->_start_suite($1);

        # We want progress messages for each top-level subtest, but not for
        # any subtests they might contain.
        if ( $self->_is_parallel && @{ $self->_tc_suite_name_stack } == 2 ) {
            my $name = join q{ - }, @{ $self->_tc_suite_name_stack };
            $self->_tc_message(
                'progressMessage',
                "starting $name",
                1,
            );
        }
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
    elsif ( $raw =~ /^\s+ok \d+ # skip (.*)$/
        && !$self->_tc_last_test_result ) {

        # when tcm skips methods, we get 1st a Subtest message
        # then "ok $num # skip $message"
        my $reason = $1;
        $self->_tc_message(
            'testStarted',
            {
                name                  => 'Skipped',
                captureStandardOutput => 'true'
            },
        );
        $self->_tc_message(
            'testIgnored',
            {
                name    => 'Skipped',
                message => $reason,
            },
        );
        $self->_finish_test('Skipped');
        $self->_finish_suite;
    }
    elsif ( $raw =~ /^\s*#/ ) {
        ( my $clean_raw = $raw ) =~ s/^\s*#\s?//;
        $clean_raw =~ s/\s+$//;
        return if $clean_raw =~ /^\s*$/;
        $self->_tc_test_output_buffer(
            $self->_tc_test_output_buffer . "$clean_raw\n" )
            if $self->_tc_last_test_result;
        $self->_maybe_print_raw( $result->raw );
    }
    elsif ($raw =~ qr{\[checked\] .+$}
        or $raw =~ qr{Deep recursion on subroutine "B::Deparse} ) {
        $self->_maybe_print_raw("# $raw\n");
    }
    elsif ( $raw !~ /^\s*$/ ) {
        $self->_tc_suite_output_buffer(
            $self->_tc_suite_output_buffer . $raw );
        $self->_maybe_print_raw( $result->raw )
            unless $raw =~ /^\s*\d+\.\.\d+(?: # SKIP.*)?$/;
    }
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _handle_plan {
    my $self   = shift;
    my $result = shift;

    unless ( $self->_test_finished ) {
        if ( $result->directive eq 'SKIP' ) {
            $self->_tc_message(
                'testStarted',
                {
                    name                  => 'Skipped',
                    captureStandardOutput => 'true',
                },
            );
            $self->_tc_message(
                'testIgnored',
                {
                    name    => 'Skipped',
                    message => $result->explanation,
                },
            );
            $self->_finish_test('Skipped');
        }
    }
}

sub _test_started {
    my $self   = shift;
    my $result = shift;

    my $test_name = $self->_compute_test_name($result);
    $self->_tc_message(
        'testStarted',
        {
            name                  => $test_name,
            captureStandardOutput => 'true',
        },
    );
    $self->_tc_last_test_name($test_name);
    $self->_tc_last_test_result($result);
}

sub _test_finished {
    my $self = shift;

    return unless $self->_tc_last_test_result;
    $self->_emit_teamcity_test_results(
        $self->_tc_last_test_name,
        $self->_tc_last_test_result
    );
    $self->_finish_test( $self->_tc_last_test_name );
    return 1;
}

sub _emit_teamcity_test_results {
    my $self      = shift;
    my $test_name = shift;
    my $result    = shift;

    my $buffer = $self->_tc_test_output_buffer;
    $self->_tc_test_output_buffer(q{});
    chomp $buffer;

    if ( $result->has_todo || $result->has_skip ) {
        $self->_tc_message(
            'testIgnored',
            {
                name    => $test_name,
                message => $result->explanation,
            },
        );
        return;
    }

    unless ( $result->is_ok ) {
        $self->_tc_message(
            'testFailed',
            {
                name => $test_name,
                message => ( $result->is_ok ? 'ok' : 'not ok' ),
                ( $buffer ? ( details => $buffer ) : () ),
            },
        );
    }
}

sub _compute_test_name {
    my $self   = shift;
    my $result = shift;

    my $description = $result->description;
    my $test_name = $description eq q{} ? $result->explanation : $description;
    $test_name =~ s/^-\s//;
    $test_name = 'NO TEST NAME' if $test_name eq q{};
    return $test_name;
}

sub _maybe_print_raw {
    my $self = shift;
    my $raw  = shift;

    if ( $self->_is_parallel ) {
        $self->_tc_test_output_buffer(
            $self->_tc_test_output_buffer . "$raw\n" );
    }
    else {
        print "$raw\n" or die "Can't print to STDOUT: $!";
    }
}

sub _finish_test {
    my $self      = shift;
    my $test_name = shift;

    $self->_tc_message( 'testFinished', { name => $test_name } );
    $self->_tc_last_test_name(undef);
    $self->_tc_last_test_result(undef);
    $self->_tc_is_last_suite_empty(0);
}

sub _start_suite {
    my $self       = shift;
    my $suite_name = shift;

    push @{ $self->_tc_suite_name_stack }, $suite_name;
    $self->_tc_is_last_suite_empty(1);
    $self->_tc_message( 'testSuiteStarted', { name => $suite_name } );
}

sub close_test {
    my $self = shift;

    my $no_tests_message
        = 'Tests were run but no plan was declared and done_testing';
    if ( $self->_tc_test_output_buffer
        =~ /^$no_tests_message\(\) was not seen\.$/m ) {
        $self->_recover_from_catastrophic_death;
    }
    else {
        if ( !$self->_test_finished && $self->_tc_suite_output_buffer ) {
            my $suite_type
                = @{ $self->_tc_suite_name_stack } == 1
                ? 'file'
                : 'subtest';
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
            $self->_tc_test_output_buffer( $self->_tc_suite_output_buffer );
            $self->_tc_suite_output_buffer(q{});
            $self->_test_finished;
        }
        {
            my @copy = @{ $self->_tc_suite_name_stack };
            $self->_finish_suite for @copy;
        }
    }

    if ( $self->_is_parallel ) {
        print ${ $self->_tc_buffered_output }
            or die $!;
    }
}

sub _recover_from_catastrophic_death {
    my $self = shift;

    if ( $self->_tc_last_test_result ) {
        my $test_num    = $self->_tc_last_test_result->number;
        my $description = $self->_tc_last_test_result->description;
        $self->_tc_last_test_result(
            TAP::Parser::Result::Test->new(
                {
                    'ok'          => 'not ok',
                    'explanation' => q{},
                    'directive'   => q{},
                    'type'        => 'test',
                    'test_num'    => $test_num,
                    'description' => "- $description",
                    'raw'         => "not ok $test_num - $description",
                }
            )
        );
    }
    else {
        my $suite_type
            = @{ $self->_tc_suite_name_stack } == 1 ? 'file' : 'subtest';
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
        my @copy = @{ $self->_tc_suite_name_stack };
        $self->_finish_suite for @copy;
    }
}

sub _finish_suite {
    my $self = shift;
    my $name = shift;

    return 0 unless @{ $self->_tc_suite_name_stack };

    $name //= $self->_tc_suite_name_stack->[-1];

    my $result = $name eq $self->_tc_suite_name_stack->[-1];
    if ($result) {
        if ( $self->_tc_is_last_suite_empty ) {
            my $suite_type
                = @{ $self->_tc_suite_name_stack } == 1 ? 'file' : 'subtest';
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
            $self->_tc_test_output_buffer( $self->_tc_suite_output_buffer );
            $self->_tc_suite_output_buffer(q{});
            $self->_test_finished;
        }
        pop @{ $self->_tc_suite_name_stack };
        $self->_tc_suite_output_buffer(q{});
        $self->_tc_is_last_suite_empty(0);
        $self->_tc_message( 'testSuiteFinished', { name => $name } );
    }
    return $result;
}

sub _tc_message {
    my $self         = shift;
    my $message      = shift;
    my $values       = shift;
    my $force_stdout = shift;

    my $handle = $force_stdout ? \*STDOUT : $self->_tc_output_handle;

    my $tc_msg = "##teamcity[$message";

    if ( ref $values ) {
        for my $name ( sort keys %{$values} ) {
            my $value = $values->{$name};
            $tc_msg .= qq{ $name='} . _tc_escape($value) . q{'};
        }

        $tc_msg .= $self->_tc_message_timestamp
            unless ref $values && $values->{timestamp};
        $tc_msg .= $self->_tc_message_flow_id
            unless ref $values && $values->{flowId};
    }
    else {
        $tc_msg .= q{ '} . _tc_escape($values) . q{'} or die $!;
    }

    $tc_msg .= "]\n";

    print {$handle} $tc_msg or die $!;

    return;
}

sub _tc_message_timestamp {
    my $now = time;

    my ( $s, $mi, $h, $d, $mo, $y ) = ( gmtime($now) )[ 0 .. 5 ];

    my $float = ( $now - int($now) );
    return sprintf(
        q{ timestamp='%4d-%02d-%02dT%02d:%02d:%02d.%03d'},
        $y + 1900, $mo + 1, $d,
        $h, $mi, $s,

        # We only need 3 places of precision so if we multiply it be 1,000 we
        # can just treat it as an integer.
        $float * 1000,
    );
}

sub _tc_message_flow_id {
    my $self = shift;
    return q{ flowId='} . _tc_escape( $self->name ) . q{'};
}

sub _tc_escape {
    my $str = shift;

    ( my $esc = $str ) =~ s{(['|\]])}{|$1}g;
    $esc =~ s{\n}{|n}g;
    $esc =~ s{\r}{|r}g;

    return $esc;
}

1;

__END__

=pod

=head1 DESCRIPTION

This module provides the core internals for turning TAP into TeamCity
messages. There are no user-serviceable parts in here.

=cut
