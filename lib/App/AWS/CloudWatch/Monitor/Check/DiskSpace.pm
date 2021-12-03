package App::AWS::CloudWatch::Monitor::Check::DiskSpace;

use strict;
use warnings;

use parent 'App::AWS::CloudWatch::Monitor::Check';

use Getopt::Long qw(:config pass_through);

our $VERSION = '0.01';

sub check {
    my $self = shift;
    my $arg  = shift;

    Getopt::Long::GetOptionsFromArray( $arg, \my %opt, 'disk-path=s@' );

    die "Option: disk-path is required" unless $opt{'disk-path'};

    my @df_command = (qw{ /bin/df -k -l -P });
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

        my $disk_total = $fields[1] * $self->constants->{KILO};
        my $disk_used  = $fields[2] * $self->constants->{KILO};
        my $disk_avail = $fields[3] * $self->constants->{KILO};
        my $filesystem = $fields[0];
        my $mount_path = $fields[5];

        push @{$metrics},
            {
            MetricName => 'DiskSpaceUtilization',
            Unit       => 'Percent',
            RawValue   => ( $disk_total > 0 ? 100 * $disk_used / $disk_total : 0 ),
            Dimensions => [
                {   Name  => 'Filesystem',
                    Value => $filesystem,
                },
                {   Name  => 'MountPath',
                    Value => $mount_path,
                },
            ],
            },
            {
            MetricName => 'DiskSpaceUsed',
            Unit       => 'Gigabytes',
            RawValue   => $disk_used / $self->constants->{GIGA},
            Dimensions => [
                {   Name  => 'Filesystem',
                    Value => $filesystem,
                },
                {   Name  => 'MountPath',
                    Value => $mount_path,
                },
            ],
            },
            {
            MetricName => 'DiskSpaceAvailable',
            Unit       => 'Gigabytes',
            RawValue   => $disk_avail / $self->constants->{GIGA},
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

App::AWS::CloudWatch::Monitor::Check::DiskSpace - gather disk metric data

=head1 SYNOPSIS

 my $plugin  = App::AWS::CloudWatch::Monitor::Check::DiskSpace->new();
 my $metrics = $plugin->check( $args_arrayref );

 aws-cloudwatch-monitor --check DiskSpace --disk-path /

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::Check::DiskSpace> is a L<App::AWS::CloudWatch::Monitor::Check> module which gathers disk metric data.

=head1 METRICS

Data for this check is read from L<df(1)>.  The following metrics are returned.

=over

=item DiskSpaceUtilization

=item DiskSpaceUsed

=item DiskSpaceAvailable

=back

=head1 METHODS

=over

=item check

Gathers the metric data and returns an arrayref of hashrefs with keys C<MetricName>, C<Unit>, C<RawValue>, and C<Dimensions>.

=back

=head1 ARGUMENTS

C<App::AWS::CloudWatch::Monitor::Check::DiskSpace> requires the C<--disk-path> argument through the commandline.

 aws-cloudwatch-monitor --check DiskSpace --disk-path /

Multiple C<--disk-path> arguments may be defined to gather metrics for multiple paths.

 aws-cloudwatch-monitor --check DiskSpace --disk-path / --disk-path /mnt/data

=head1 DEPENDENCIES

C<App::AWS::CloudWatch::Monitor::Check::DiskSpace> depends on the external program, L<df(1)>.

=cut
