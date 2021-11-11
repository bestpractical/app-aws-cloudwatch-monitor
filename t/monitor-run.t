use strict;
use warnings;

use FindBin ();
use lib "$FindBin::RealBin/../lib", "$FindBin::RealBin/lib";
use App::AWS::CloudWatch::Monitor::Test;

use Capture::Tiny;

my $class = 'App::AWS::CloudWatch::Monitor';
use_ok($class);

# To allow testing the basic functionality of Monitor->run without needing to
# run the tests on an AWS instance, this test mocks out the interactions with
# the instance and AWS.

# TODO: CloudWatchClient allows setting an alternate meta-data location using the
# AWS_EC2CW_META_DATA ENV variable.  Instead of mocking subs in CloudWatchClient
# for tests, it would be much better to create a directory structure inside of
# t/var/ which contains meta-data for the calls to use.

App::AWS::CloudWatch::Monitor::Test::override(
    package => 'App::AWS::CloudWatch::Monitor::CloudWatchClient',
    name    => 'get_instance_id',
    subref  => sub { return 'i12345test' },
);

App::AWS::CloudWatch::Monitor::Test::override(
    package => 'App::AWS::CloudWatch::Monitor::CloudWatchClient',
    name    => 'get_avail_zone',
    subref  => sub { return 'us-east-1c' },
);

# Mocking call_json skips a lot of internal functionality that we should
# verify.  For this first happy path test, we want to run without "verify"
# but don't want to make calls to the AWS CloudWatch endpoints.

my $reference_id = '12345-67a8';
my $original_call_json = App::AWS::CloudWatch::Monitor::Test::override(
    package => 'App::AWS::CloudWatch::Monitor::CloudWatchClient',
    name    => 'call_json',
    subref  => sub {
        return (
            HTTP::Response->new(
                200,
                'This is a mocked response from the test',
                [ 'x-amzn-requestid' => $reference_id ],
            )
        );
    },
);

HAPPY_PATH_MOCKED: {
    note( 'happy path mocked' );

    my $opt = {
        check => [ qw{ TestSuccess } ],
    };

    my $arg = [];

    my $obj = $class->new();
    my ( $stdout, $stderr, @result ) = Capture::Tiny::capture { $obj->run($opt,$arg) };

    # Successfully reported metrics to CloudWatch. Reference Id: 12345-67a8
    like( $stdout, qr/Successfully reported metrics/, 'response contains success message' );
    like( $stdout, qr/Reference Id: $reference_id/, 'response contains reference id' );
}

App::AWS::CloudWatch::Monitor::Test::override(
    package => 'App::AWS::CloudWatch::Monitor::CloudWatchClient',
    name    => 'call_json',
    subref  => $original_call_json,
);

VERIFY_OPTION: {
    note( 'verify option' );

    my $opt = {
        check   => [ qw{ TestSuccess } ],
        verify  => 1,
    };

    my $arg = [ 'test', 'one', 'test', 'two' ];

    my $obj = $class->new();
    my ( $stdout, $stderr, @result ) = Capture::Tiny::capture { $obj->run($opt,$arg) };

    # Verification completed successfully. No actual metrics sent to CloudWatch.
    like( $stdout, qr/Verification completed successfully/, 'response contains success message' );
    like( $stdout, qr/No actual metrics sent to CloudWatch/, 'response indicates no metrics sent' );
}

VERBOSE_OPTION: {
    note( 'verbose option' );

    my $opt = {
        check   => [ qw{ TestSuccess } ],
        verify  => 1,
        verbose => 1,
    };

    my $arg = [];

    my $obj = $class->new();
    my ( $stdout, $stderr, @result ) = Capture::Tiny::capture { $obj->run($opt,$arg) };

    like( $stdout, qr/MetricName/, 'payload metric data is present if verbose is set' );

    $opt = {
        check  => [ qw{ TestSuccess } ],
        verify => 1,
    };

    $arg = [];

    $obj = $class->new();
    ( $stdout, $stderr, @result ) = Capture::Tiny::capture { $obj->run($opt,$arg) };

    unlike( $stdout, qr/MetricName/, 'payload metric data is not present if verbose is not set' );
}

ADDITIONAL_ARGS: {
    note( 'additional args success' );

    my $opt = {
        check   => [ qw{ TestArgs } ],
        verify  => 1,
        verbose => 1,
    };

    my $arg = [ '--test', 'one', '--test', 'two' ];

    my $obj = $class->new();
    my ( $stdout, $stderr, @result ) = Capture::Tiny::capture { $obj->run($opt,$arg) };

    # the MetricName checks below are a cheap way to verify the args are correctly passed into the check modules
    # by having the check module create metrics based on the expected values submitted.
    like( $stdout, qr/"MetricName":"one-Count"/, 'arg one is correctly passed to the test module' );
    like( $stdout, qr/"MetricName":"two-Count"/, 'arg two is correctly passed to the test module' );
    like( $stdout, qr/Verification completed successfully/, 'response contains success message' );
    like( $stdout, qr/No actual metrics sent to CloudWatch/, 'response indicates no metrics sent' );

    note( 'additional args failure' );

    $opt = {
        check   => [ qw{ TestSuccess TestArgs } ],
        verify  => 1,
        verbose => 1,
    };

    $arg = [ '--not-test', 'value' ];

    $obj = $class->new();
    ( $stdout, $stderr, @result ) = Capture::Tiny::capture { $obj->run($opt,$arg) };

    # here we need to verify TestSuccess check module still ran and succeeded, while Monitor->run catches
    # and passes back the failure from TestArgs for the missing expected "test" arg.
    like( $stderr, qr/error: Check::TestArgs: Option: test is required/, 'required option in check module throws error' );
    like( $stdout, qr/"MetricName":"TestSuccess"/, 'successful check module metric was uploaded despite failure in another check module' );

    # additionally check the output to ensure unknown args don't throw warnings.  since all additional
    # args are ultimately passed to the check modules, check module authors need to be sure
    # pass_though is enabled for Getopt::Long in their modules.  there isn't a way to enforce that for
    # check modules, so the best this is achieving is an additional self documentation of functionality.
    unlike( $stderr, qr/Unknown option/, 'unknown args do not throw errors' );

    like( $stdout, qr/Verification completed successfully/, 'response contains success message' );
    like( $stdout, qr/No actual metrics sent to CloudWatch/, 'response indicates no metrics sent' );
}

done_testing();
