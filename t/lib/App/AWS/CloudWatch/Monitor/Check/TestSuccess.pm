package App::AWS::CloudWatch::Monitor::Check::TestSuccess;

use strict;
use warnings;

use parent 'App::AWS::CloudWatch::Monitor::Check';

our $VERSION = '0.02';

sub check {
    my $self = shift;

    my $metric = {
        MetricName => 'TestSuccess',
        Unit       => 'Count',
        RawValue   => 1,
    };

    return [ $metric ];
}

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor::Check::TestSuccess - test metric for tests

=head1 SYNOPSIS

 my $plugin  = App::AWS::CloudWatch::Monitor::Check::TestSuccess->new();
 my $metrics = $plugin->check();

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::Check::TestSuccess> is a L<App::AWS::CloudWatch::Monitor::Check> module to use in tests.

This test check module doesn't verify args or run anything on the system, but only returns metric data in the expected format.

=head1 METHODS

=over

=item check

Gathers the metric data and returns an arrayref of hashrefs with keys C<MetricName>, C<Unit>, and C<RawValue>.

=back

=cut
