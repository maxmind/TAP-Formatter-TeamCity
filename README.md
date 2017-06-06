# NAME

TAP::Formatter::TeamCity - Emit test results as TeamCity build messages

# VERSION

version 0.15

# SYNOPSIS

    # When using prove(1):
    prove --merge --formatter TAP::Formatter::TeamCity my_test.t

# DESCRIPTION

[TAP::Formatter::TeamCity](https://metacpan.org/pod/TAP::Formatter::TeamCity) is a formatter for [TAP::Harness](https://metacpan.org/pod/TAP::Harness) that emits
TeamCity build messages to the console, rather than the usual output. The
TeamCity build server is able to process these messages in the build log and
present your test results in its web interface (along with some nice
statistics and graphs).

# SUGGESTED USAGE

The TeamCity service messages are generally not human-readable, so you
probably only want to use this Formatter when the tests are being run by a
TeamCity build agent and the [TAP::Formatter::TeamCity](https://metacpan.org/pod/TAP::Formatter::TeamCity) module is available.

# LIMITATIONS

TeamCity comes from a jUnit culture, so it doesn't understand skip and TODO
tests in the same way that Perl testing harnesses do. Therefore, this
formatter simply treats skipped and TODO tests as ignored tests.

# SEE ALSO

[TeamCity::Message](https://metacpan.org/pod/TeamCity::Message)

# SUPPORT

Bugs may be submitted through [https://github.com/maxmind/TAP-Formatter-TeamCity/issues](https://github.com/maxmind/TAP-Formatter-TeamCity/issues).

# AUTHORS

- Jeffrey Ryan Thalhammer <jeff@imaginative-software.com>
- Ran Eilam <reilam@maxmind.com>

# CONTRIBUTORS

- Andy Jack <ajack@maxmind.com>
- Dave Rolsky <drolsky@maxmind.com>
- Greg Oschwald <goschwald@maxmind.com>
- Mark Fowler <mark@twoshortplanks.com>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2009 - 2017 by MaxMind, Inc.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
