use strict;
use warnings;

use FindBin ();
use lib "$FindBin::RealBin/../lib", "$FindBin::RealBin/lib";
use App::AWS::CloudWatch::Monitor::Test;

my $class = 'App::AWS::CloudWatch::Monitor::Check';
use_ok($class);

HAPPY_PATH: {
    note( 'happy path' );

    my $obj = $class->new();
    my $constants = $obj->constants;

    my $expected = {
        'GIGA' => 1073741824,
        'KILO' => 1024,
        'MEGA' => 1048576,
        'BYTE' => 1
    };

    is_deeply( $constants, $expected, 'constants contains the expected keys and values' );
}

done_testing();
