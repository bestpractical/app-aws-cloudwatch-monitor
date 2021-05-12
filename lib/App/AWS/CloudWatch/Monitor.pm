package App::AWS::CloudWatch::Monitor;

use strict;
use warnings;

use App::AWS::CloudWatch::Monitor::Config;
use App::AWS::CloudWatch::Monitor::CloudWatchClient;
use Try::Tiny;
use Module::Loader;

our $VERSION = '0.01';

my $config;

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

    my $instance_id = App::AWS::CloudWatch::Monitor::CloudWatchClient::get_instance_id();
    my $loader      = Module::Loader->new;

    my @metrics;
    foreach my $module ( @{ $opt->{check} } ) {
        my $class = q{App::AWS::CloudWatch::Monitor::Check::} . $module;
        try {
            $loader->load($class);
        }
        catch {
            my $exception = $_;
            die "$exception\n";
        };

        my $plugin = $class->new();
        my $metric = $plugin->check();

        push @{ $metric->{Dimensions} }, { Name => 'InstanceId', Value => $instance_id };
        push @metrics, $metric;
    }

    return;
}

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor - collect and send metrics to AWS CloudWatch

=head1 SYNOPSIS

 use App::AWS::CloudWatch::Monitor;

 my $monitor = App::AWS::CloudWatch::Monitor->new();

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor> collects and sends custom metrics to AWS CloudWatch from an AWS EC2 instance.

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

=back

=cut
