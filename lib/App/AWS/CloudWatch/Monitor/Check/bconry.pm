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

package App::AWS::CloudWatch::Monitor::Check::bconry;

use strict;
use warnings;

use parent 'App::AWS::CloudWatch::Monitor::Check';

use Getopt::Long qw(:config pass_through);

our $VERSION = '0.01';

our $PMAP_CONFIG = '/home/admin/tmp/pmaprc';
our $TOP_CONFIG = '/home/admin/tmp/';

our %UNITS_BY_CATEGORY = (
    ps_cpu => 'Seconds',
    ps_age => 'Seconds',
    ps_rss        => 'Kilobytes',
    ps_size       => 'Kilobytes',
    pmap_rss      => 'Kilobytes',
    pmap_pss      => 'Kilobytes',
    pmap_rsan     => 'Kilobytes',
    pmap_killsize => 'Kilobytes',
    top_rss       => 'Kilobytes',
    top_rsan      => 'Kilobytes',
);

sub check {
    my $self = shift;
    my $arg  = shift;

    Getopt::Long::GetOptionsFromArray( $arg, \my %opt, 'user=s@' );

    die "Option: user is required" unless $opt{'user'};

    my $match = '^(' . join( '|', @{$opt{'user'}} ) . ')';
    $match = qr/$match/;

    my $metrics;

    # use ps to get process list and some information
    my @ps_command = ( '/bin/ps', 'axco', 'user,pid,stat,rss,size,cputime,etime,command' );
    my ( $exit, $stdout, $stderr ) = $self->run_command( \@ps_command );

    if ($exit) {
        die "$stderr\n";
    }

    return unless $stdout;

    # remove header, but make sure it's what we expect
    # if it isn't then we're probably not going to process the data properly
    my $header = shift @$stdout;
    die "unexpected header" unless $header =~ /^ USER \s+ PID \s+ STAT \s+ RSS \s+ SIZE \s+ TIME \s+ ELAPSED \s+ COMMAND/x;

    my %data_by_user_and_pid;
    my %summary;

    # for each pid, gather additional information
    foreach my $line ( @{$stdout} ) {
        next unless $line =~ $match;

        my( $uname, $pid, $status, $ps_rss, $mem_size, $cpu_time, $elapsed_time, $command ) = split /\s+/, $line;

        # ignore zombie processes
        next if $status =~ /^Z/;

        foreach my $time ($cpu_time, $elapsed_time) {
            if ($time =~ /^(?:(?<days>\d+)-)?(?:(?<hours>\d+):)?(?:(?<minutes>\d+):)(?<seconds>\d+)/) {
                $time = ((($+{days} // 0) * 24 + ($+{hours} // 0)) * 60 + ($+{minutes} // 0)) * 60 + $+{seconds};
            }
            else {
                # die?  warn?
                # setting a negative value that will be ignored later
                $time = -1;
            }
        }

        # store what we have so far
        my $summary_key = "$uname/$command";
        my $summary_record = $summary{$summary_key} //= {
            ps_rss => [],
            ps_size => [],
            ps_cpu => [],
            ps_age => [],
            pmap_rss => [],
            pmap_pss => [],
            pmap_rsan => [],
        };

        push @{$summary_record->{ps_rss}}, $ps_rss;
        push @{$summary_record->{ps_size}}, $mem_size;
        push @{$summary_record->{ps_cpu}}, $cpu_time;
        push @{$summary_record->{ps_age}}, $elapsed_time;

        # gather more data from pmap
        my @pmap_command = ( '/usr/bin/sudo', '/usr/bin/pmap', '-C', $PMAP_CONFIG, '-p', $pid );
        my ( $pmap_exit, $pmap_stdout, $pmap_stderr ) = $self->run_command( \@pmap_command );

        if (!$pmap_exit and $pmap_stdout) {
            # first line is the full command line
            my $pmap_command = @$pmap_stdout;

            # second line is the headers
            my $pmap_header = shift @pmap_$sdtout;

            # next are detail lines
            if ($pmap_header eq =~ /^ \s+ Address \s+ Rss \s+ Pss \s+ Anonymous $/x) {
                my $kill_size = 0;

                while (my $detail = shift @$stdout) {
                    # then a line of lines ('=' characters)
                    last if $detail =~ /==/;

                    my ($addr, $pmap_rss, $pss, $pmap_rsan) = split /\s+/, $detail;

                    if( $pmap_rsan ) {
                        $kill_size += $pmap_rsan;
                    }
                    elsif ($pmap_rss == $pss) {
                        $kill_size += $pss;
                    }
                }

                # then a summary line
                my ($pmap_sum_rss, $pmap_sum_pss, $pmap_sum_rsan) = split ' ', shift @$stdout;

                push @{$summary_record->{pmap_rss}}, $pmap_sum_rss;
                push @{$summary_record->{pmap_pss}}, $pmap_sum_pss;
                push @{$summary_record->{pmap_rsan}}, $pmap_sum_rsan;
                push @{$summary_record->{pmap_killsize}}, $pmap_killsize;
            }

        }

        # gather more data from top
        {
            local $ENV{'XDG_CONFIG_HOME'} = $TOP_CONFIG;
            my @top_command = ( '/usr/bin/top', '-b', '-n', '1', '-E', 'k', '-H', '-p', $pid );
            my ( $top_exit, $top_stdout, $top_stderr ) = $self->run_command( \@top_command );

            if (!$top_exit and $top_stdout) {
                # first is a blank line (all summary lines are turned off)
                my $top_blank = shift @$top_stdout;
                # next is the header line
                my $top_header = shift @$top_stdout;

                if ($top_blank eq '' and $top_header =~ /^ \s+ RES \s+ RSan \s+ COMMAND$/x) {
                    # last is the line of data
                    my $data = shift @$top_stdout;
                    my ($top_rss, $top_rsan, $top_command) = split ' ', shift @$stdout;

                    push @{$summary_record->{top_rss}}, $top_rss;
                    push @{$summary_record->{top_rsan}}, $top_rsan;
                }
            }
        }
    }

    # summarize by command
    foreach my $summary_key (keys %summary) {
        my $summary_record = $summary{$summary_key};

        # the number of ps_cpu entries is our count
        {
            MetricName => $summary_key . '-Count',
            Unit       => 'Count',
            RawValue   => scalar @{$summary_record->{ps_cpu}},
        },

        foreach my $category (qw(ps_rss ps_size ps_cpu ps_age pmap_rss pmap_pss pmap_rsan pmap_killsize top_rss top_rsan)) {
            my $entries = $summary_record->{$category};

            my %values;

            foreach my $value (@$entries) {
                $values{$value}++;
            }

            my @unique_values = sort { $a <=> $b } keys %values;

            my @counts = @values{@unique_values};

            push @$metrics, {
                MetricName => "$summary_key-$category",
                Unit       => $UNITS_BY_CATEGORY{$category},
                Values     => \@unique_values,
                Counts     => \@counts,
            };
        }
    }

    return $metrics;
}

1;

__END__

=pod

=head1 NAME

App::AWS::CloudWatch::Monitor::Check::bconry - gather process metric data by user and process

=head1 SYNOPSIS

 my $plugin  = App::AWS::CloudWatch::Monitor::Check::bconry->new();
 my $metrics = $plugin->check( $args_arrayref );

 aws-cloudwatch-monitor --check bconry --user www-data
 aws-cloudwatch-monitor --check bconry --user postfix
 aws-cloudwatch-monitor --check bconry --user postgres

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::Check::bconry> is a L<App::AWS::CloudWatch::Monitor::Check> module which gathers process metric data.

=head1 METRICS

Data for this check is read from L<ps(1)>.  The following metrics are returned.

=over

=item tbd

=item tbd

=item tbd

=back

=head1 METHODS

=over

=item check

Gathers the metric data and returns an arrayref of hashrefs with keys C<MetricName>, C<Unit>, C<RawValue>, and C<Dimensions>.

=back

=head1 ARGUMENTS

C<App::AWS::CloudWatch::Monitor::Check::bconry> requires the C<--user> argument through the commandline.

 aws-cloudwatch-monitor --check bconry --user www-data

Multiple C<--user> arguments may be defined to gather metrics for multiple users.

 aws-cloudwatch-monitor --check bconry --user www-data --user postgres

=head1 DEPENDENCIES

C<App::AWS::CloudWatch::Monitor::Check::bconry> depends on the external program, L<ps(1)>.

=cut
