use strict;
use warnings;

use FindBin ();
use lib "$FindBin::RealBin/../lib", "$FindBin::RealBin/lib";
use App::AWS::CloudWatch::Monitor::Test;

my $class = 'App::AWS::CloudWatch::Monitor';
use_ok($class);

HAPPY_PATH: {
    note( 'happy path' );

    my $obj = $class->new();
    my $config = $obj->config;

    # we already verify the config contents in the config test
    # and don't need to re-verify here.
    # just check if it's a config object and has keys.
    isa_ok( $config, 'Config::Tiny' );
    ok( keys %{$config}, 'config contains keys' );
}

done_testing();
