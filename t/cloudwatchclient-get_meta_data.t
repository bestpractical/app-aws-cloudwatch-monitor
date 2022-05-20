use strict;
use warnings;

use FindBin ();
use lib "$FindBin::RealBin/../lib", "$FindBin::RealBin/lib";
use App::AWS::CloudWatch::Monitor::Test;
use Test::Warnings qw{:no_end_test};

my $class = 'App::AWS::CloudWatch::Monitor::CloudWatchClient';
use_ok($class);

use constant {
    DO_NOT_CACHE => 0,
    USE_CACHE    => 1,
};

my %meta_data_cache = (
    '/instance-id' => 'i12345testcache',
);

my %meta_data_mount = (
    '/instance-id' => 'i12345testmount',
);

my $return_expired_ttl = 0;
my $return_empty_cache = 0;
App::AWS::CloudWatch::Monitor::Test::override(
    package => 'App::AWS::CloudWatch::Monitor::CloudWatchClient',
    name    => 'read_meta_data',
    subref  => sub {
        my $resource    = shift;
        my $default_ttl = shift;
        my $meta_data;
        unless ($return_empty_cache) {
            $meta_data = $meta_data_cache{$resource};
        }
        return ( $meta_data, $return_expired_ttl );
    },
);

my $meta_data_was_written = 0;
App::AWS::CloudWatch::Monitor::Test::override(
    package => 'App::AWS::CloudWatch::Monitor::CloudWatchClient',
    name    => 'write_meta_data',
    subref  => sub {
        my $resource   = shift;
        my $data_value = shift;
        $meta_data_was_written = 1;
        return;
    },
);

my $return_empty_mount = 0;
App::AWS::CloudWatch::Monitor::Test::override(
    package => 'App::AWS::CloudWatch::Monitor::CloudWatchClient',
    name    => 'get',  # get is imported from LWP::Simple
    subref  => sub {
        my $uri = shift;
        my $resource;
        if ( $uri =~ /.latest\/meta-data(\/.+)/ ) {
            $resource = $1;
        }
        my $meta_data;
        unless ($return_empty_mount) {
            $meta_data = $meta_data_mount{$resource};
        }
        return $meta_data;
    },
);

note('get meta_data from cache');
my $instance_id = App::AWS::CloudWatch::Monitor::CloudWatchClient::get_meta_data( '/instance-id', USE_CACHE );
is( $instance_id, $meta_data_cache{'/instance-id'}, 'instance-id from cache returned expected' );
is( $meta_data_was_written, 0, 'meta_data was not written' );
reset_vars();

note('get meta_data from mount');
$return_empty_cache = 1;
note("don't write the cache");
$instance_id = App::AWS::CloudWatch::Monitor::CloudWatchClient::get_meta_data( '/instance-id', DO_NOT_CACHE );
is( $instance_id, $meta_data_mount{'/instance-id'}, 'instance-id from mount returned expected' );
is( $meta_data_was_written, 0, 'meta_data was not written' );
note("write the cache");
$instance_id = App::AWS::CloudWatch::Monitor::CloudWatchClient::get_meta_data( '/instance-id', USE_CACHE );
is( $instance_id, $meta_data_mount{'/instance-id'}, 'instance-id from mount returned expected' );
is( $meta_data_was_written, 1, 'meta_data was written' );
reset_vars();

note("return empty from cache and mount");
$return_empty_cache = 1;
$return_empty_mount = 1;
$instance_id = App::AWS::CloudWatch::Monitor::CloudWatchClient::get_meta_data( '/instance-id', USE_CACHE );
is( $instance_id, undef, 'instance-id from mount returned empty' );
is( $meta_data_was_written, 0, 'meta_data was not written' );
my $warning = Test::Warnings::warning { App::AWS::CloudWatch::Monitor::CloudWatchClient::get_meta_data( '/instance-id', USE_CACHE ) };
like(
    $warning,
    qr/^meta-data resource \/instance-id returned empty/,
    'warning is generated if cache and mount return no meta-data',
);
reset_vars();

note("return expired from cache and empty mount");
$return_expired_ttl = 1;
$return_empty_mount = 1;
$instance_id = App::AWS::CloudWatch::Monitor::CloudWatchClient::get_meta_data( '/instance-id', USE_CACHE );
is( $instance_id, $meta_data_cache{'/instance-id'}, 'instance-id from cache returned expected' );
is( $meta_data_was_written, 0, 'meta_data was not written' );
$warning = Test::Warnings::warning { App::AWS::CloudWatch::Monitor::CloudWatchClient::get_meta_data( '/instance-id', USE_CACHE ) };
like(
    $warning,
    qr/^meta-data resource \/instance-id cache TTL is expired and the meta-data mount failed to return data\.\nexpired data from the cache will continue to be used and will persist in the cache until the meta-data mount starts returning data again\./,
    'warning is generated if cache is expired and mount return no meta-data',
);
reset_vars();

done_testing();

sub reset_vars {
    $return_expired_ttl = 0;
    $return_empty_cache = 0;
    $meta_data_was_written = 0;
    $return_empty_mount = 0;
}
