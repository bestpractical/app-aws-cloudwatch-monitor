package App::AWS::CloudWatch::Monitor::Config;

use strict;
use warnings;

use File::HomeDir;
use Config::Tiny;

our $VERSION = '0.01';

sub load {
    my $config = _load_and_verify();

    return $config;
}

sub _load_and_verify {
    my $rc = File::HomeDir->my_home . '/.aws-cloudwatch-monitor-rc';

    unless ( -e $rc && -r $rc ) {
        die "$rc does not exist or cannot be read\n";
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

The configuration file is loaded from the running user's home directory.

An example config, C<.aws-cloudwatch-monitor-rc.example>, is provided in the project root directory.

To set up the config, copy C<.aws-cloudwatch-monitor-rc.example> into the running user's home directory, then update the values accordingly.

=cut
