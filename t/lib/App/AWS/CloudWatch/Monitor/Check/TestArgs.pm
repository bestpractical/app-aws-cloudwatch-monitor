package App::AWS::CloudWatch::Monitor::Check::TestArgs;

use strict;
use warnings;

use parent 'App::AWS::CloudWatch::Monitor::Check';

use Getopt::Long qw(:config pass_through);

our $VERSION = '0.07';

sub check {
    my $self = shift;
    my $arg  = shift;

    Getopt::Long::GetOptionsFromArray( $arg, \my %opt, 'test=s@' );

    die "Option: test is required" unless $opt{'test'};

    my $metrics;
    foreach my $value ( @{ $opt{'test'} } ) {
        push @{$metrics},
            {
            MetricName => $value . '-Count',
            Unit       => 'Count',
            RawValue   => 1,
            };
    }

    return $metrics;
}

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor::Check::TestArgs - test metric for tests

=head1 SYNOPSIS

 my $plugin  = App::AWS::CloudWatch::Monitor::Check::TestArgs->new();
 my $metrics = $plugin->check( [ @{$arg} ] );

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::Check::TestArgs> is a L<App::AWS::CloudWatch::Monitor::Check> module to use in tests.

This test check module verifies the presence of the C<--test> arg and dies on failure, or returns a metric for each C<--test>.

=head1 METHODS

=over

=item check

Gathers the metric data and returns an arrayref of hashrefs with keys C<MetricName>, C<Unit>, and C<RawValue>.

=back

=cut
