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

package App::AWS::CloudWatch::Monitor::Config;

use strict;
use warnings;

use Config::Tiny;

our $VERSION = '0.06';

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

C<App::AWS::CloudWatch::Monitor::Config> loads settings for L<App::AWS::CloudWatch::Monitor>.

=head1 SUBROUTINES

=over

=item load

Load and verify the config.

=back

=head1 CONFIGURATION

To send metrics to AWS, you need to provide the access key id and secret access key for your configured AWS CloudWatch service.  You can set these in the file C<config.ini>.

An example is provided as part of this distribution.  The user running the metric script, like the user configured in cron for example, will need access to the configuration file.

To set up the configuration file, copy C<config.ini.example> into one of the following locations:

=over

=item C<$ENV{HOME}/.config/aws-cloudwatch-monitor/config.ini>

=item C</etc/aws-cloudwatch-monitor/config.ini>

=back

After creating the file, edit and update the values accordingly.

 [aws]
 aws_access_key_id = example
 aws_secret_access_key = example

B<NOTE:> If the C<$ENV{HOME}/.config/aws-cloudwatch-monitor/> directory exists, C<config.ini> will be loaded from there regardless of a config file in C</etc/aws-cloudwatch-monitor/>.

=cut
