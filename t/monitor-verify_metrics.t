use strict;
use warnings;

use FindBin ();
use lib "$FindBin::RealBin/../lib", "$FindBin::RealBin/lib";
use App::AWS::CloudWatch::Monitor::Test;

my $class = 'App::AWS::CloudWatch::Monitor';
use_ok($class);

my $metric = {
    MetricName => 'TestVerifyMetrics',
    Unit       => 'Count',
    RawValue   => 1,
};

HAPPY_PATH: {
    note( 'happy path' );

    my $obj = $class->new();
    ok( $obj->_verify_metrics( [$metric] ), 'response is success' );

}

FAILURES: {
    my $obj = $class->new();
    my ( $res, $msg );

    note( 'failure no metric data' );

    my $expected_response = 'no metric data was returned';
    subtest 'undef metric' => sub {
        plan tests => 2;
        ( $res, $msg ) = $obj->_verify_metrics();
        isnt( $res, 1, 'response is not success' );
        like( $msg, qr/$expected_response/, "response indicates $expected_response" );
    };
    subtest 'empty arrayref metric' => sub {
        plan tests => 2;
        ( $res, $msg ) = $obj->_verify_metrics([]);
        isnt( $res, 1, 'response is not success' );
        like( $msg, qr/$expected_response/, "response indicates $expected_response" );
    };

    note( 'failure unexpected format' );

    $expected_response = 'return is not in the expected format';
    ( $res, $msg ) = $obj->_verify_metrics( $metric );
    isnt( $res, 1, 'response is not success' );
    like( $msg, qr/$expected_response/, "response indicates $expected_response" );

    note( 'failure missing keys' );

    foreach my $key ( keys %{$metric} ) {
        my $modified = $metric;
        my $value = delete $modified->{$key};

        my $expected_response = 'return does not contain the required keys';
        my ( $res, $msg ) = $obj->_verify_metrics( [$modified] );

        subtest "missing $key" => sub {
            plan tests => 2;
            isnt( $res, 1, 'response is not success' );
            like( $msg, qr/$expected_response/, "response indicates $expected_response" );
        };

        $modified->{$key} = $value;
    }
}

done_testing();
