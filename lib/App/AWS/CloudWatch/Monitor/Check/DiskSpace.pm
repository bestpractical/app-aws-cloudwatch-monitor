package App::AWS::CloudWatch::Monitor::Check::DiskSpace;

use strict;
use warnings;

use parent 'App::AWS::CloudWatch::Monitor::Check';

our $VERSION = '0.01';

sub check {
    my $self = shift;

    # TODO: pass in mount path
    my @df_command = (qw{ /bin/df -k -l -P / });
    my ( $exit, $stdout, $stderr ) = $self->run_command( \@df_command );

    if ($exit) {
        die "$stderr\n";
    }

    return unless $stdout;

    shift @{$stdout};
    my @fields = split /\s+/, @{$stdout}[0];

    # Result of df is reported in 1k blocks
    my $disk_total = $fields[1] * $self->constants->{KILO};
    my $disk_used  = $fields[2] * $self->constants->{KILO};
    my $disk_avail = $fields[3] * $self->constants->{KILO};
    my $filesystem = $fields[0];
    my $mount_path = $fields[5];

    my $metrics = [
        {   MetricName => 'DiskSpaceUtilization',
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
        {   MetricName => 'DiskSpaceUsed',
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
        {   MetricName => 'DiskSpaceAvailable',
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
        },
    ];

    return $metrics;
}

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor::Check::DiskSpace - gather disk metric data

=head1 SYNOPSIS

 my $plugin  = App::AWS::CloudWatch::Monitor::Check::DiskSpace->new();
 my $metrics = $plugin->check();

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::Check::DiskSpace> is a C<App::AWS::CloudWatch::Monitor::Check> module which gathers disk metric data.

=head1 METRICS

The following metrics are gathered and returned.

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

=cut
