package App::AWS::CloudWatch::Monitor::Check::Inode;

use strict;
use warnings;

use parent 'App::AWS::CloudWatch::Monitor::Check';

our $VERSION = '0.01';

sub check {
    my $self = shift;

    # TODO: pass in mount path
    my @df_command = (qw{ /bin/df -i -k -P / });
    my ( $exit, $stdout, $stderr ) = $self->run_command( \@df_command );

    if ($exit) {
        die "$stderr\n";
    }

    return unless $stdout;

    shift @{$stdout};
    my @fields = split /\s+/, @{$stdout}[0];

    my $inode_total = $fields[1];
    my $inode_used  = $fields[2];
    my $inode_avail = $fields[3];
    my $filesystem  = $fields[0];
    my $mount_path  = $fields[5];

    my $metrics = [
        {   MetricName => 'InodeUtilization',
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
        },
    ];

    return $metrics;
}

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor::Check::Inode - gather inode metric data

=head1 SYNOPSIS

 my $plugin  = App::AWS::CloudWatch::Monitor::Check::Inode->new();
 my $metrics = $plugin->check();

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::Check::Inode> is a C<App::AWS::CloudWatch::Monitor::Check> module which gathers inode metric data.

=head1 METRICS

The following metrics are gathered and returned.

=over

=item InodeUtilization

=back

=head1 METHODS

=over

=item check

Gathers the metric data and returns an arrayref of hashrefs with keys C<MetricName>, C<Unit>, C<RawValue>, and C<Dimensions>.

=back

=cut
