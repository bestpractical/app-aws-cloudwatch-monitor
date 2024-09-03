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

package App::AWS::CloudWatch::Monitor::Check::Inode;

use strict;
use warnings;

use parent 'App::AWS::CloudWatch::Monitor::Check';

use Getopt::Long qw(:config pass_through);

our $VERSION = '0.06';

sub check {
    my $self = shift;
    my $arg  = shift;

    Getopt::Long::GetOptionsFromArray( $arg, \my %opt, 'disk-path=s@' );

    die "Option: disk-path is required" unless $opt{'disk-path'};

    my @df_command = (qw{ /bin/df -i -k -P });
    push @df_command, @{ $opt{'disk-path'} };

    my ( $exit, $stdout, $stderr ) = $self->run_command( \@df_command );

    if ($exit) {
        die "$stderr\n";
    }

    return unless $stdout;

    shift @{$stdout};

    my $metrics;
    foreach my $line ( @{$stdout} ) {
        my @fields = split /\s+/, $line;

        my $inode_total = $fields[1];
        my $inode_used  = $fields[2];
        my $inode_avail = $fields[3];
        my $filesystem  = $fields[0];
        my $mount_path  = $fields[5];

        push @{$metrics},
            {
            MetricName => 'InodeUtilization',
            Unit       => 'Percent',
            RawValue   => ( $inode_total > 0 ? 100 * $inode_used / $inode_total : 0 ),
            Dimensions => [
                {   Name  => 'Filesystem',
                    Value => $filesystem,
                },
                {   Name  => 'MountPath',
                    Value => $mount_path,
                },
            ],
            };
    }

    return $metrics;
}

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor::Check::Inode - gather inode metric data

=head1 SYNOPSIS

 my $plugin  = App::AWS::CloudWatch::Monitor::Check::Inode->new();
 my $metrics = $plugin->check( $args_arrayref );

 aws-cloudwatch-monitor --check Inode --disk-path /

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::Check::Inode> is a L<App::AWS::CloudWatch::Monitor::Check> module which gathers inode metric data.

=head1 METRICS

Data for this check is read from L<df(1)>.  The following metrics are returned.

=over

=item InodeUtilization

=back

=head1 METHODS

=over

=item check

Gathers the metric data and returns an arrayref of hashrefs with keys C<MetricName>, C<Unit>, C<RawValue>, and C<Dimensions>.

=back

=head1 ARGUMENTS

C<App::AWS::CloudWatch::Monitor::Check::Inode> requires the C<--disk-path> argument through the commandline.

 aws-cloudwatch-monitor --check Inode --disk-path /

Multiple C<--disk-path> arguments may be defined to gather metrics for multiple paths.

 aws-cloudwatch-monitor --check Inode --disk-path / --disk-path /mnt/data

=head1 DEPENDENCIES

C<App::AWS::CloudWatch::Monitor::Check::Inode> depends on the external program, L<df(1)>.

=cut
