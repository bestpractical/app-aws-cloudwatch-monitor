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

package App::AWS::CloudWatch::Monitor::Check::Memory;

use strict;
use warnings;

use parent 'App::AWS::CloudWatch::Monitor::Check';

our $VERSION = '0.02';

sub check {
    my $self = shift;

    my $meminfo_filename = '/proc/meminfo';
    my ( $ret, $msg ) = $self->read_file($meminfo_filename);

    if ( !$ret && $msg ) {
        die "$msg\n";
    }

    return unless $ret;

    my %meminfo;
    foreach my $line ( @{$ret} ) {
        if ( $line =~ /^(.*?):\s+(\d+)/ ) {
            $meminfo{$1} = $2;
        }
    }

    my $mem_total   = $meminfo{MemTotal} * $self->constants->{KILO};
    my $mem_free    = $meminfo{MemFree} * $self->constants->{KILO};
    my $mem_cached  = $meminfo{Cached} * $self->constants->{KILO};
    my $mem_buffers = $meminfo{Buffers} * $self->constants->{KILO};

    # TODO: implement memory-units and mem-used-incl-cache-buff
    my $mem_avail = $mem_free;
    $mem_avail += $mem_cached + $mem_buffers;
    my $mem_used = $mem_total - $mem_avail;

    my $swap_total = $meminfo{SwapTotal} * $self->constants->{KILO};
    my $swap_free  = $meminfo{SwapFree} * $self->constants->{KILO};
    my $swap_used  = $swap_total - $swap_free;

    my $metrics = [
        {   MetricName => 'MemoryUtilization',
            Unit       => 'Percent',
            RawValue   => ( $mem_total > 0 ? 100 * $mem_used / $mem_total : 0 ),
        },
        {   MetricName => 'MemoryUsed',
            Unit       => 'Megabytes',
            RawValue   => $mem_used / $self->constants->{MEGA},
        },
        {   MetricName => 'MemoryAvailable',
            Unit       => 'Megabytes',
            RawValue   => $mem_avail / $self->constants->{MEGA},
        },
        {   MetricName => 'SwapUtilization',
            Unit       => 'Percent',
            RawValue   => ( $swap_total > 0 ? 100 * $swap_used / $swap_total : 0 ),
        },
        {   MetricName => 'SwapUsed',
            Unit       => 'Megabytes',
            RawValue   => $swap_used / $self->constants->{MEGA},
        },
    ];

    return $metrics;
}

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor::Check::Memory - gather memory metric data

=head1 SYNOPSIS

 my $plugin  = App::AWS::CloudWatch::Monitor::Check::Memory->new();
 my $metrics = $plugin->check();

 aws-cloudwatch-monitor --check Memory

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::Check::Memory> is a L<App::AWS::CloudWatch::Monitor::Check> module which gathers memory metric data.

=head1 METRICS

Data for this check is read from C</proc/meminfo>.  The following metrics are returned.

=over

=item MemoryUtilization

=item MemoryUsed

=item MemoryAvailable

=item SwapUtilization

=item SwapUsed

=back

=head1 METHODS

=over

=item check

Gathers the metric data and returns an arrayref of hashrefs with keys C<MetricName>, C<Unit>, and C<RawValue>.

=back

=cut
