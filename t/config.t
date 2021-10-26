use strict;
use warnings;

use FindBin ();
use lib "$FindBin::RealBin/../lib", "$FindBin::RealBin/lib";
use App::AWS::CloudWatch::Monitor::Test;

my $class = 'App::AWS::CloudWatch::Monitor::Config';
use_ok($class);

HAPPY_PATH: {
    note( 'happy path' );
    lives_ok { $class->load() } 'config loads and verifies';
}

done_testing();
