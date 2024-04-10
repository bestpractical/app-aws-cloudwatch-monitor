package App::AWS::CloudWatch::Monitor::Test;

use strict;
use warnings;

use parent 'Test::More';

our $VERSION = '0.05';

sub import {
    my $class = shift;
    my %args  = @_;

    if ( $args{tests} ) {
        $class->builder->plan( tests => $args{tests} )
            unless $args{tests} eq 'no_declare';
    }
    elsif ( $args{skip_all} ) {
        $class->builder->plan( skip_all => $args{skip_all} );
    }

    require FindBin;
    override(
        package => 'App::AWS::CloudWatch::Monitor::Config',
        name    => '_get_conf_dir',
        subref  => sub { $FindBin::RealBin },
    );

    Test::More->export_to_level(1);

    require Test::Exception;
    Test::Exception->export_to_level(1);

    return;
}

sub override {
    my %args = (
        package => undef,
        name    => undef,
        subref  => undef,
        @_,
    );

    eval "require $args{package}";

    my $fullname = sprintf "%s::%s", $args{package}, $args{name};
    my $original = \&$fullname;

    no strict 'refs';
    no warnings 'redefine', 'prototype';
    *$fullname = $args{subref};

    return $original;
}

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor::Test - testing module for App::AWS::CloudWatch::Monitor

=head1 SYNOPSIS

 use App::AWS::CloudWatch::Monitor::Test;

 ok($got eq $expected, $test_name);

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::Test> sets up the testing environment and modules for testing within the L<App::AWS::CloudWatch::Monitor> distribution.

Methods from L<Test::More> and L<Test::Exception> are exported and available for the tests.

=head1 SUBROUTINES

=over

=item override

Overrides subroutines

ARGS are C<package>, C<name>, and C<subref>.

 my $original_sub = App::AWS::CloudWatch::Monitor::Test::override(
     package => 'Package::To::Override',
     name    => 'subtooverride',
     subref  => sub { return 'faked' },
 );

RETURNS the original, un-overridden sub.

=back

=cut
