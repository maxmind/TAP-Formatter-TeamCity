# NAME

TAP::Formatter::TeamCity - Emit test results as TeamCity service messages

# VERSION

version 0.041

# SYNOPSIS

    # When using prove(1):
    prove --merge --formatter TAP::Formatter::TeamCity my_test.t

    # From within a Module::Build subclass:
    sub tap_harness_args { return {formatter_class => 'TAP::Formatter::TeamCity'} }

# DESCRIPTION

[TAP::Formatter::TeamCity](https://metacpan.org/pod/TAP::Formatter::TeamCity) is a plugin for [TAP::Harness](https://metacpan.org/pod/TAP::Harness) that emits TeamCity
service messages to the console, rather than the usual output.  The TeamCity build
server is able to process these messages in the build log and present your test
results in its web interface (along with some nice statistics and graphs).

This is very much alpha code, and is subject to change.

# SEE IT IN ACTION

If you're not familiar with continuous integration systems (in general) or
TeamCity (in particular), you're welcome to explore the TeamCity build server
we use for the [Perl::Critic](https://metacpan.org/pod/Perl::Critic) project.  Just go to
[http://perlcritic.com:8111](http://perlcritic.com:8111) and click on the "Login as a Guest" link.  From
there, you can browse the build history, review test results, and examine the
artifacts (such as test coverage reports and performance profiles).  All the
information you see there was generated from TAP-based tests using this module
to communicate the results to the TeamCity server.

# SUGGESTED USAGE

The TeamCity service messages are generally not human-readable, so you
probably only want to use this Formatter when the tests are being run by a
TeamCity build agent and the [TAP::Formatter::TeamCity](https://metacpan.org/pod/TAP::Formatter::TeamCity) module is available.
I suggest using an environment variable to activate the Formatter.  If you're
using a recent version of [Module::Build](https://metacpan.org/pod/Module::Build) you might do something like this in
your `Build.PL` file:

    # Regular build configuration here:
    my $builder = Module::Build->new( ... )

    # Specify this Formatter, if the environment variable is set:
    $builder->tap_harness_args( {formatter_class => 'TAP::Formatter::TeamCity'} )
      if $ENV{RUNNING_UNDER_TEAMCITY} && eval {require TAP::Formatter::TeamCity};

    # Generate build script as ususal:
    $builder->create_build_script();

And then set the `RUNNING_UNDER_TEAMCITY` environment variable to a true value
in your TeamCity build configuration.

TODO: Figure out if/how to do this with [ExtUtils::MakeMaker](https://metacpan.org/pod/ExtUtils::MakeMaker).

# LIMITATIONS

TeamCity comes from a jUnit culture, so it doesn't understand SKIP and TODO 
tests in the same way that Perl testing harnesses do.  Therefore, this formatter
simply instructs TeamCity to ignore tests that are marked SKIP or TODO.

Also, I haven't yet figured out how to transmit test diagnostic messages, so
those probably won't appear in the TeamCity web interface.  But I'm working
on it :)

# SOME EXTRA CANDY

TeamCity, CruiseControl, and some other continuous integration systems are
oriented towards Java code.  As such, they don't have native support for
Perl's customary build tools like [Module::Build](https://metacpan.org/pod/Module::Build).  But they do have nice
support for running Ant.  This distribution contains an Ant build script at
`build.xml` which wraps [Module::Build](https://metacpan.org/pod/Module::Build) actions in Ant targets.  This makes
it easier to configure TeamCity and CruiseControl to build your Perl code.  If
you're using the EPIC plug-in with Eclipse, you can also use this Ant script
to build your code from within the IDE.  Feel free to copy the `build.xml`
into your own projects.

# SEE ALSO

[TeamCity::BuildMessages](https://metacpan.org/pod/TeamCity::BuildMessages)

# AUTHORS

- Jeffrey Ryan Thalhammer <jeff@imaginative-software.com>
- Ran Eilam <reilam@maxmind.com>

# CONTRIBUTORS

- Andy Jack <ajack@maxmind.com>
- Dave Rolsky <drolsky@maxmind.com>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2009 - 2015 by MaxMind, Inc..

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
