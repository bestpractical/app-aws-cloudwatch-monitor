package App::AWS::CloudWatch::Monitor::Config;

use strict;
use warnings;

use Config::Tiny;

our $VERSION = '0.01';

sub load {
    my $config = _load_and_verify();

    return $config;
}

sub _get_conf_dir {
    my $name = 'aws-cloudwatch-monitor';

    my $dir;
    if ( $ENV{HOME} && -d "$ENV{HOME}/.config/$name" ) {
        $dir = "$ENV{HOME}/.config";
    }
    elsif ( -d "/etc/$name" ) {
        $dir = '/etc';
    }
    else {
        die "error: unable to find config directory\n";
    }

    return "$dir/$name";
}

sub _load_and_verify {
    my $rc = _get_conf_dir() . '/config.ini';

    unless ( -e $rc && -r $rc ) {
        die "error: $rc does not exist or cannot be read\n";
    }

    my $config = Config::Tiny->read($rc);

    foreach my $required (qw{ aws }) {
        unless ( defined $config->{$required} ) {
            die "$required section in $rc is not defined\n";
        }
    }

    foreach my $required (qw{ aws_access_key_id aws_secret_access_key }) {
        unless ( defined $config->{aws}{$required} ) {
            die "$required key for aws section in $rc is not defined\n";
        }
    }

    return $config;
}

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor::Config - load and verify the config

=head1 SYNOPSIS

 use App::AWS::CloudWatch::Monitor::Config;

 my $config = App::AWS::CloudWatch::Monitor::Config->load();

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::Config> loads settings for C<App::AWS::CloudWatch::Monitor>.

=head1 SUBROUTINES

=over

=item load

Load and verify the config.

=back

=head1 CONFIGURATION

An example configuration file, C<config.ini.example>, is provided in the project root directory.

To set up the configuration file, copy the example into one of the following locations:

=over

=item C<$ENV{HOME}/.config/aws-cloudwatch-monitor/config.ini>

=item C</etc/aws-cloudwatch-monitor/config.ini>

=back

After creating the file, edit and update the values accordingly.

B<NOTE:> If the C<$ENV{HOME}/.config/aws-cloudwatch-monitor/> directory exists, C<config.ini> will be loaded from there regardless of a config file in C</etc/aws-cloudwatch-monitor/>.

=cut
