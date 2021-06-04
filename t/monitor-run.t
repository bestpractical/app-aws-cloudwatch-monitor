use strict;
use warnings;

use FindBin ();
use lib "$FindBin::RealBin/../lib", "$FindBin::RealBin/lib";
use App::AWS::CloudWatch::Monitor::Test;

use Capture::Tiny;

my $class = 'App::AWS::CloudWatch::Monitor';
use_ok($class);

App::AWS::CloudWatch::Monitor::Test::override(
    package => 'App::AWS::CloudWatch::Monitor::CloudWatchClient',
    name    => 'get_instance_id',
    subref  => sub { return 'i12345test' },
);

HAPPY_PATH_MOCKED: {
    note( 'happy path mocked' );

    # To allow testing the basic functionality of Monitor->run without needing to
    # run the tests on an AWS instance, this test mocks out the interactions with
    # the instance and AWS.
    # Mocking call_json skips a lot of internal functionality that we should
    # verify.  More tests should be added which run through those internals, but
    # should first check if on an AWS instance and skip if not.
    # Those tests still shouldn't connect to CloudWatch to upload metrics.

    App::AWS::CloudWatch::Monitor::Test::override(
        package => 'App::AWS::CloudWatch::Monitor::CloudWatchClient',
        name    => 'call_json',
        subref  => sub {
            return (
                HTTP::Response->new(
                    200,
                    'This is a mocked response from the test',
                    [ 'x-amzn-requestid' => '12345-67a8' ],
                )
            );
        },
    );

    my $opt = {
        check => [ qw{ TestOne TestTwo } ],
    };

    my $obj = $class->new();
    my ( $stdout, $stderr, @result ) = Capture::Tiny::capture { $obj->run($opt) };

    # Successfully reported metrics to CloudWatch. Reference Id: 12345-67a8
    like( $stdout, qr/Successfully reported metrics/, 'response contains success message' );
    like( $stdout, qr/Reference Id: \d+/, 'response contains reference id' );
}

done_testing();
