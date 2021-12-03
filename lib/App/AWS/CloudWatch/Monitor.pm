package App::AWS::CloudWatch::Monitor;

use strict;
use warnings;

use App::AWS::CloudWatch::Monitor::Config;
use App::AWS::CloudWatch::Monitor::CloudWatchClient;
use List::Util;
use Try::Tiny;
use Module::Loader;

our $VERSION = '0.01';

my $config;

use constant CLIENT_NAME => 'App-AWS-CloudWatch-Monitor';
use constant NOW         => 0;

sub new {
    my $class = shift;
    my $self  = {};

    $config = App::AWS::CloudWatch::Monitor::Config->load();

    return bless $self, $class;
}

sub config {
    my $self = shift;
    return $config;
}

sub run {
    my $self = shift;
    my $opt  = shift;
    my $arg  = shift;

    my $instance_id = App::AWS::CloudWatch::Monitor::CloudWatchClient::get_instance_id();
    my $loader      = Module::Loader->new;

    if ( $opt->{'from-cron'} ) {
        sleep( rand(20) );
    }

    my $param = {};
    $param->{Input}{Namespace}  = 'System/Linux';
    $param->{Input}{MetricData} = [];

    my $checks = delete $opt->{check};

    foreach my $module ( List::Util::uniq @{$checks} ) {
        my $class = q{App::AWS::CloudWatch::Monitor::Check::} . $module;
        try {
            $loader->load($class);
        }
        catch {
            die "$_\n";
        };

        my $plugin = $class->new();
        my ( $metrics, $exception );
        $metrics = try {
            return $plugin->check( [ @{$arg} ] );
        }
        catch {
            chomp( $exception = $_ );
        };

        if ($exception) {
            warn "error: Check::$module: $exception\n";
            next;
        }

        my ( $ret, $msg ) = $self->_verify_metrics($metrics);
        unless ($ret) {
            warn "warning: Check::$module: $msg\n";
            next;
        }

        foreach my $metric ( @{$metrics} ) {
            push( @{ $metric->{Dimensions} }, { 'Name' => 'InstanceId', 'Value' => $instance_id } );
            $metric->{Timestamp} = App::AWS::CloudWatch::Monitor::CloudWatchClient::get_offset_time(NOW);

            push( @{ $param->{Input}{MetricData} }, $metric );
        }
    }

    unless ( scalar @{ $param->{Input}{MetricData} } ) {
        print "\nNo metrics to upload; exiting\n\n";
        exit;
    }

    $opt->{'aws-access-key-id'} = $self->config->{aws}{aws_access_key_id};
    $opt->{'aws-secret-key'}    = $self->config->{aws}{aws_secret_access_key};
    $opt->{retries}             = 2;
    $opt->{'user-agent'}        = CLIENT_NAME . "/$VERSION";

    my $response = App::AWS::CloudWatch::Monitor::CloudWatchClient::call_json( 'PutMetricData', $param, $opt );
    my $code     = $response->code;
    my $message  = $response->message;

    if ( $code == 200 && !$opt->{'from-cron'} ) {
        if ( $opt->{verify} ) {
            print "\nVerification completed successfully. No actual metrics sent to CloudWatch.\n\n";
        }
        else {
            my $request_id = $response->headers->{'x-amzn-requestid'};
            print "\nSuccessfully reported metrics to CloudWatch. Reference Id: $request_id\n\n";
        }
    }
    elsif ( $code < 100 ) {
        die "error: $message\n";
    }
    elsif ( $code != 200 ) {
        die "Failed to call CloudWatch: HTTP $code. Message: $message\n";
    }

    return;
}

sub _verify_metrics {
    my $self    = shift;
    my $metrics = shift;

    if ( !$metrics || ( ref $metrics eq 'ARRAY' && !scalar @{$metrics} ) ) {
        return ( 0, 'no metric data was returned' );
    }

    if ( ref $metrics ne 'ARRAY' ) {
        return ( 0, 'return is not in the expected format' );
    }

    foreach my $metric ( @{$metrics} ) {
        foreach my $key (qw{ MetricName Unit RawValue }) {
            unless ( defined $metric->{$key} ) {
                return ( 0, 'return does not contain the required keys' );
            }
        }
    }

    return 1;
}

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor - collect and send metrics to AWS CloudWatch

=head1 SYNOPSIS

 use App::AWS::CloudWatch::Monitor;

 my $monitor = App::AWS::CloudWatch::Monitor->new();
 $monitor->run(\%opt, \@ARGV);

 aws-cloudwatch-monitor [--check <module>]
                        [--from-cron] [--verify] [--verbose]
                        [--version] [--help]

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor> is an extensible framework for collecting and sending custom metrics to AWS CloudWatch from an AWS EC2 instance.

For the commandline interface to C<App::AWS::CloudWatch::Monitor>, see the documentation for L<aws-cloudwatch-monitor>.

For adding check modules, see the documentation for L<App::AWS::CloudWatch::Monitor::Check>.

=head1 CONSTRUCTOR

=over

=item new

Returns a new C<App::AWS::CloudWatch::Monitor> object.

=back

=head1 METHODS

=over

=item config

Returns the loaded config.

=item run

Loads and runs the specified check modules to gather metric data.

For options and arguments to C<run>, see the documentation for L<aws-cloudwatch-monitor>.

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
