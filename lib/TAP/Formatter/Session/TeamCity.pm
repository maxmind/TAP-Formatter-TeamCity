package TAP::Formatter::Session::TeamCity;

use strict;
use warnings;

our $VERSION = '0.005';

use base qw(TAP::Formatter::Session);

1;

__END__

=pod

=head1 DESCRIPTION

L<TAP::Formatter::Session::TeamCity> is the Session delegate used by
L<TAP::Formatter::TeamCity>.  Since TeamCity takes care of tabulating and
summarizing test results for you, there is no particular session-level
reporting that is required.  So this is basically just the minimal
L<TAP::Formatter::Session>.

=cut
