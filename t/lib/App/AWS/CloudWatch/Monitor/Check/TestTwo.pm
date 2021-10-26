package App::AWS::CloudWatch::Monitor::Check::TestTwo;

use strict;
use warnings;

use parent 'App::AWS::CloudWatch::Monitor::Check';

our $VERSION = '0.01';

sub check {
    my $self = shift;

    my @echo_testing_command = (qw{ /bin/echo testtwo });
    ( my $exit, my $stdout, my $stderr ) = $self->run_command( \@echo_testing_command );

    my $value = ( $stdout ? 1 : 0 );

    my $metric = {
        MetricName => 'TestTwo',
        Unit       => 'Count',
        RawValue   => $value,
    };

    return $metric;
}

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor::Check::TestTwo - test metric for tests

=head1 SYNOPSIS

 my $plugin = App::AWS::CloudWatch::Monitor::Check::TestTwo->new();
 my $metric = $plugin->check();

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::Check::TestTwo> is a C<App::AWS::CloudWatch::Monitor::Check> module to use in tests.

=head1 METHODS

=over

=item check

Gathers the metric data and returns a hashref with keys C<MetricName>, C<Unit>, and C<RawValue>.

=back

=cut
