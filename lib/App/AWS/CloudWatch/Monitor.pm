package App::AWS::CloudWatch::Monitor;

use strict;
use warnings;

use App::AWS::CloudWatch::Monitor::Config;

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

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor -

=head1 SYNOPSIS

 use App::AWS::CloudWatch::Monitor;

 my $monitor = App::AWS::CloudWatch::Monitor->new();

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor>

=head1 CONSTRUCTOR

=over

=item new

Returns a new C<App::AWS::CloudWatch::Monitor> object.

=back

=head1 METHODS

=over

=item config

Returns the loaded config.

=back

=cut
