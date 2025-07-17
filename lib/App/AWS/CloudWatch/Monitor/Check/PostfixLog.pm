# Copyright 2021 Best Practical Solutions, LLC <sales@bestpractical.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

package App::AWS::CloudWatch::Monitor::Check::PostfixLog;

use strict;
use warnings;

use parent 'App::AWS::CloudWatch::Monitor::Check';

use Getopt::Long qw(:config pass_through);

our $VERSION = '0.06';

sub check {
    my $self = shift;
    my $arg  = shift;

    my $metrics;
    my $lookup_failures = 0;

    eval "require Mail::Log::Parse::Postfix";
    die "Install the module Mail::Log::Parse to use this check: $@" if $@;

    Getopt::Long::GetOptionsFromArray( $arg, \my %opt, 'log=s', 'lines=i', 'duration=i' );

    my $log = $opt{'log'} // '/var/log/mail.log';
    my $lines = $opt{'lines'} // 500;
    my $duration = $opt{'duration'} // 5;

    my $log_obj = Mail::Log::Parse::Postfix->new({ log_file => $log });

    # Jump to the end, then back up 'lines' lines to get past 'duration' minutes ago
    $log_obj->go_to_end();
    $log_obj->go_backward($lines);

    my $timestart = time;
    $timestart = $timestart - ($duration * 60); # Go back 5 minutes

    while ( my $line_info = $log_obj->next() ) {
        next unless $line_info->{'timestamp'} >= $timestart;

        my @text = split / /, $line_info->{text};

        # The info in text doesn't seem to be standard, but the error condition we
        # are looking for has 'reject:' and code 451 in the positions below.
        next unless $text[0] eq 'reject:';

        if ( $text[4] eq '451' ) {
            $lookup_failures++;
        }
    }

    push @{$metrics},
        {
        MetricName => 'PostfixLogLookupError',
        Unit       => 'Count',
        RawValue   => $lookup_failures,
        };

    return $metrics;
}

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor::Check::PostfixLog - find errors in Postfix logs

=head1 SYNOPSIS

    aws-cloudwatch-monitor --check PostfixLog --log /var/log/mail.log --lines 100 --duration 1

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::Check::PostfixLog> is a L<App::AWS::CloudWatch::Monitor::Check> module which gathers
postfix log error metric data.

=head1 METRICS

This check scans the Postfix log file identified by C<log>, starting at C<lines>
lines from the end, and checking log entries for the last C<duration>
minutes. This is similar to a Linux C<tail> with an extra time component
added.

It specifically looks for reject messages with a 451 code, which indicates
Postfix cannot load it's aliases information. It reports the number of
these errors found.

=head1 ARGUMENTS

The following argument are accepted.

=over

=item log

The full path and filename of the Postfix log file to process.

Defaults to C</var/log/mail.log>.

=item lines

The number of lines from the end of the file to process. Try to set this to
a value that will find lines older than C<duration>.

Defaults to 500.

=item duration

How many past minutes of log entries to process from now. Align this with your
C<lines> setting and your frequency of running the check job.

Defaults to 5.

=back

=head1 DEPENDENCIES

C<App::AWS::CloudWatch::Monitor::Check::PostfixLog> requires the module L<Mail::Log::Parse>
to be installed.

=cut
