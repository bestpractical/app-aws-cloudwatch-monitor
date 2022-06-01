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

package App::AWS::CloudWatch::Monitor::Check;

use strict;
use warnings;

use Capture::Tiny;

our $VERSION = '0.03';

sub new {
    my $class = shift;
    my $self  = {};

    return bless $self, $class;
}

sub run_command {
    my $self    = shift;
    my $command = shift;

    my ( $stdout, $stderr, $exit ) = Capture::Tiny::capture {
        system( @{$command} );
    };

    chomp($stderr);

    return ( $exit, [ split( /\n/, $stdout ) ], $stderr );
}

sub read_file {
    my $self     = shift;
    my $filename = shift;

    open( my $fh, '<', $filename )
        or return ( 0, "open $filename: $!" );

    my $contents = [];
    while ( my $line = <$fh> ) {
        chomp $line;
        push @{$contents}, $line;
    }
    close($fh);

    return $contents;
}

use constant UNITS => (
    BYTE => 1,
    KILO => 1024,
    MEGA => 1048576,
    GIGA => 1073741824,
);

sub constants {
    my $self = shift;

    return { UNITS() };
}

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor::Check - parent for Check modules

=head1 SYNOPSIS

 use parent 'App::AWS::CloudWatch::Monitor::Check';

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::Check> provides a contructor and methods for child modules.

This module is not meant to be initialized directly.

=head1 ADDING CHECK MODULES

To add check functionality to L<App::AWS::CloudWatch::Monitor>, additional check modules can be created as child modules to C<App::AWS::CloudWatch::Monitor::Check>.

For an example to start creating check modules, see L<App::AWS::CloudWatch::Monitor::Check::DiskSpace> or any check module released within this distribution.

=head2 CHECK MODULE REQUIREMENTS

Child modules must implement the C<check> method which gathers, formats, and returns the metrics.

The returned metrics must be an arrayref of hashrefs with keys C<MetricName>, C<Unit>, and C<RawValue>.

The returned metric hashrefs may contain a C<Dimensions> key, but its value must be an arrayref containing hashrefs with the keys C<Name> and C<Value>.

 # example MemoryUtilization check return without Dimensions data
 my $metric = [
     {   MetricName => 'MemoryUtilization',
         Unit       => 'Percent',
         RawValue   => $mem_util,
     },
 ];

 # example DiskSpaceUtilization check return with Dimensions data
 my $metric = [
     {   MetricName => 'DiskSpaceUtilization',
         Unit       => 'Percent',
         RawValue   => $disk_space_util,
         Dimensions => [
             {   Name  => 'Filesystem',
                 Value => $filesystem,
             },
             {   Name  => 'MountPath',
                 Value => $mount_path,
             },
         ],
     },
 ];

 # example Foo check return with multiple metrics
 my $metrics = [
     {   MetricName => 'FooOne',
         Unit       => 'Percent',
         RawValue   => $foo_one,
     },
     {   MetricName => 'FooTwo',
         Unit       => 'Percent',
         RawValue   => $foo_two,
     },
 ];

=head1 CONSTRUCTOR

=over

=item new

Returns the C<App::AWS::CloudWatch::Monitor::Check> object.

=back

=head1 METHODS

=over

=item run_command

Runs the specified command and returns a list with three members consisting of:

=over

=item C<exit code> returned from the system command

=item output from C<STDOUT>

=item output from C<STDERR>

=back

C<STDOUT> is split by newline and returned as an arrayref.

=item read_file

Reads the specified file and returns an arrayref of the content.

=item constants

Returns the bytes constants for use in unit conversion.

=back

=cut
