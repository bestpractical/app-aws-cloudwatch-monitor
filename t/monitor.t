use strict;
use warnings;

use FindBin ();
use lib "$FindBin::RealBin/../lib", "$FindBin::RealBin/lib";
use App::AWS::CloudWatch::Monitor::Test;

my $class = 'App::AWS::CloudWatch::Monitor';
use_ok($class);

OBJECT_AND_METHODS: {
    note( 'object and methods' );

    my $obj = $class->new();
    isa_ok( $obj, $class );

    foreach my $method ( qw{ config run } ) {
        can_ok( $obj, $method );
    }
}

done_testing();
