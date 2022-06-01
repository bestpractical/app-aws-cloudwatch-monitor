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

package App::AWS::CloudWatch::Monitor::Check::LoadAvg;

use strict;
use warnings;

use parent 'App::AWS::CloudWatch::Monitor::Check';

our $VERSION = '0.03';

sub check {
    my $self = shift;

    my $loadavg_filename = '/proc/loadavg';
    my ( $ret, $msg ) = $self->read_file($loadavg_filename);

    if ( !$ret && $msg ) {
        die "$msg\n";
    }

    return unless $ret;

    my @fields = split /\s+/, @{$ret}[0];

    # TODO: parse into float
    my $loadavg_1min  = $fields[0];
    my $loadavg_5min  = $fields[1];
    my $loadavg_15min = $fields[2];

    my $cpuinfo_filename = '/proc/cpuinfo';
    ( $ret, $msg ) = $self->read_file($cpuinfo_filename);

    if ( !$ret && $msg ) {
        die "$msg\n";
    }

    return unless $ret;

    my $cpu_count = grep {/processor\t:/} @{$ret};

    my $metrics = [
        {   MetricName => 'LoadAvg1Min',
            Unit       => 'Percent',
            RawValue   => $loadavg_1min,
        },
        {   MetricName => 'LoadAvg5Min',
            Unit       => 'Percent',
            RawValue   => $loadavg_5min,
        },
        {   MetricName => 'LoadAvg15Min',
            Unit       => 'Percent',
            RawValue   => $loadavg_15min,
        },
        {   MetricName => 'LoadAvgPerCPU1Min',
            Unit       => 'Percent',
            RawValue   => $loadavg_1min / $cpu_count,
        },
        {   MetricName => 'LoadAvgPerCPU5Min',
            Unit       => 'Percent',
            RawValue   => $loadavg_5min / $cpu_count,
        },
        {   MetricName => 'LoadAvgPerCPU15Min',
            Unit       => 'Percent',
            RawValue   => $loadavg_15min / $cpu_count,
        },
    ];

    return $metrics;
}

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor::Check::LoadAvg - gather load average metric data

=head1 SYNOPSIS

 my $plugin  = App::AWS::CloudWatch::Monitor::Check::LoadAvg->new();
 my $metrics = $plugin->check();

 aws-cloudwatch-monitor --check LoadAvg

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::Check::LoadAvg> is a L<App::AWS::CloudWatch::Monitor::Check> module which gathers load average metric data.

=head1 METRICS

Data for this check is read from C</proc/loadavg>.  The following metrics are returned.

=over

=item LoadAvg1Min

=item LoadAvg5Min

=item LoadAvg15Min

=item LoadAvgPerCPU1Min

=item LoadAvgPerCPU5Min

=item LoadAvgPerCPU15Min

=back

=head1 METHODS

=over

=item check

Gathers the metric data and returns an arrayref of hashrefs with keys C<MetricName>, C<Unit>, and C<RawValue>.

=back

=cut
