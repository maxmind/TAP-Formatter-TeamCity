package TAP::Formatter::TeamCity;

use 5.010;

use strict;
use warnings;

our $VERSION = '0.050';

use TAP::Formatter::Session::TeamCity;

use base qw(TAP::Formatter::Base);

sub open_test {
    my $self      = shift;
    my $test_name = shift;
    my $parser    = shift;

    my $session = TAP::Formatter::Session::TeamCity->new(
        {
            name      => $test_name,
            formatter => $self,
            parser    => $parser,
        }
    );

    return $session;
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
