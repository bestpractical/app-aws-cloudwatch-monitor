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

package App::AWS::CloudWatch::Monitor::Check::Process;

use strict;
use warnings;

use parent 'App::AWS::CloudWatch::Monitor::Check';

use Getopt::Long qw(:config pass_through);

our $VERSION = '0.07';

sub check {
    my $self = shift;
    my $arg  = shift;

    Getopt::Long::GetOptionsFromArray( $arg, \my %opt, 'process=s@' );

    die "Option: process is required" unless $opt{'process'};

    # TODO: investigate ps options to allow for different systems
    my @ps_command = ( '/bin/ps', 'axco', 'command,pcpu,pmem,stat' );
    my ( $exit, $stdout, $stderr ) = $self->run_command( \@ps_command );

    if ($exit) {
        die "$stderr\n";
    }

    return unless $stdout;

    shift @{$stdout};

    my $metrics;
    foreach my $process_name ( @{ $opt{'process'} } ) {
        my $total_cnt = 0;
        my $total_cpu = 0.0;
        my $total_mem = 0.0;

        foreach my $line ( @{$stdout} ) {
            next unless $line =~ qr/^$process_name/;

            my @fields = split /\s+/, $line;

            # don't count zombie (defunct) processes towards process metrics.
            # zombie processes are finished and resources returned, so won't affect
            # memory usage on the system in a noticable way.
            # count every other process state as appropriate towards totals.

            # COMMAND                     %CPU %MEM STAT
            # zombie <defunct>             0.0  0.0 Z+

            # with defunct processes, the field index count for cpu and mem are no
            # longer accurate to count from the left.  decrement index count to check
            # the last column for zombies before reading stats for cpu and mem.
            if ( $fields[-1] !~ /^Z/ ) {
                $total_cnt += 1;
                $total_cpu += $fields[1];
                $total_mem += $fields[2];
            }
        }

        push @{$metrics},
            {
            MetricName => $process_name . '-Count',
            Unit       => 'Count',
            RawValue   => $total_cnt,
            },
            {
            MetricName => $process_name . '-CpuUtilization',
            Unit       => 'Percent',
            RawValue   => $total_cpu,
            },
            {
            MetricName => $process_name . '-MemoryUtilization',
            Unit       => 'Percent',
            RawValue   => $total_mem,
            };
    }

    return $metrics;
}

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor::Check::Process - gather process metric data

=head1 SYNOPSIS

 my $plugin  = App::AWS::CloudWatch::Monitor::Check::Process->new();
 my $metrics = $plugin->check( $args_arrayref );

 aws-cloudwatch-monitor --check Process --process apache2

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::Check::Process> is a L<App::AWS::CloudWatch::Monitor::Check> module which gathers process metric data.

=head1 METRICS

Data for this check is read from L<ps(1)>.  The following metrics are returned.

=over

=item [process-name]-Count

=item [process-name]-CpuUtilization

=item [process-name]-MemoryUtilization

=back

=head1 METHODS

=over

=item check

Gathers the metric data and returns an arrayref of hashrefs with keys C<MetricName>, C<Unit>, C<RawValue>, and C<Dimensions>.

=back

=head1 ARGUMENTS

C<App::AWS::CloudWatch::Monitor::Check::Process> requires the C<--process> argument through the commandline.

 aws-cloudwatch-monitor --check Process --process apache2

Multiple C<--process> arguments may be defined to gather metrics for multiple processes.

 aws-cloudwatch-monitor --check Process --process apache2 --process postgres

=head1 DEPENDENCIES

C<App::AWS::CloudWatch::Monitor::Check::Process> depends on the external program, L<ps(1)>.

=cut
