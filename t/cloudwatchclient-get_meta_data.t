use strict;
use warnings;

use FindBin ();
use lib "$FindBin::RealBin/../lib", "$FindBin::RealBin/lib";
use App::AWS::CloudWatch::Monitor::Test;
use Test::Warnings qw{:no_end_test};
use HTTP::Response;

my $class = 'App::AWS::CloudWatch::Monitor::CloudWatchClient';
use_ok($class);

# Disable retry delays so tests do not sleep
{
    no warnings 'once';
    $App::AWS::CloudWatch::Monitor::CloudWatchClient::imds_token_retry_initial_delay = 0;
    $App::AWS::CloudWatch::Monitor::CloudWatchClient::imds_token_retry_max_delay     = 0;
}

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

# Mock IMDSv2 token acquisition.
# $mock_put_responses is a list of HTTP::Response objects to return in order.
# When the list is exhausted, the last entry is repeated.
my $mock_token = 'fake-imds-token-12345';
my @mock_put_responses;
my $mock_put_call_count = 0;

sub _make_token_response {
    my $response = HTTP::Response->new( 200, 'OK' );
    $response->content($mock_token);
    return $response;
}

sub _make_error_response {
    my $code = shift;
    return HTTP::Response->new( $code, 'Error' );
}

App::AWS::CloudWatch::Monitor::Test::override(
    package => 'LWP::UserAgent',
    name    => 'put',
    subref  => sub {
        my $self = shift;
        my $url  = shift;

        $mock_put_call_count++;

        return HTTP::Response->new( 404, 'Not Found' )
            unless $url eq 'http://169.254.169.254/latest/api/token';

        my $idx      = $mock_put_call_count - 1;
        my $last_idx = $#mock_put_responses;
        my $response = $mock_put_responses[ $idx <= $last_idx ? $idx : $last_idx ];
        return $response;
    },
);

# Mock the default_header method on the $ua object
App::AWS::CloudWatch::Monitor::Test::override(
    package => 'LWP::Simple',
    name    => 'ua',
    subref  => sub {
        # Return a mock user agent object
        return bless {}, 'MockUserAgent';
    },
);

# Create a mock user agent class with default_header method
{
    package MockUserAgent;
    sub default_header {
        my $self = shift;
        my $header = shift;
        my $value = shift;
        # Just store the header, don't actually do anything
        $self->{headers}->{$header} = $value;
        return;
    }

    sub timeout {
        my $self = shift;
        my $timeout = shift;
        $self->{timeout} = $timeout if defined $timeout;
        return $self->{timeout};
    }
}

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

# Default: a single successful token response (used by get_meta_data tests below)
@mock_put_responses = ( _make_token_response() );

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

note('_get_imds_token: succeeds on first try');
@mock_put_responses  = ( _make_token_response() );
$mock_put_call_count = 0;
my $token_response = App::AWS::CloudWatch::Monitor::CloudWatchClient::_get_imds_token();
is( $token_response->is_success, 1,           '_get_imds_token succeeds on first try' );
is( $token_response->content,    $mock_token, '_get_imds_token returns token content' );
is( $mock_put_call_count,        1,           '_get_imds_token made exactly 1 PUT request' );

note('_get_imds_token: retries on 503, succeeds on second try');
@mock_put_responses  = ( _make_error_response(503), _make_token_response() );
$mock_put_call_count = 0;
$token_response = App::AWS::CloudWatch::Monitor::CloudWatchClient::_get_imds_token();
is( $token_response->is_success, 1,           '_get_imds_token succeeds after 503 retry' );
is( $token_response->content,    $mock_token, '_get_imds_token returns token content after retry' );
is( $mock_put_call_count,        2,           '_get_imds_token made 2 PUT requests (1 failure + 1 success)' );

note('_get_imds_token: exhausts all retries on repeated 503');
@mock_put_responses  = ( _make_error_response(503) );
$mock_put_call_count = 0;
$token_response = App::AWS::CloudWatch::Monitor::CloudWatchClient::_get_imds_token();
is( $token_response->is_success, '', '_get_imds_token fails after exhausting retries' );
my $max_retries;
{
    no warnings 'once';
    $max_retries = $App::AWS::CloudWatch::Monitor::CloudWatchClient::imds_token_max_retries;
}
is(
    $mock_put_call_count,
    $max_retries + 1,
    '_get_imds_token attempted max_retries + 1 times',
);

note('_get_imds_token: does not retry on 403 (non-retryable)');
@mock_put_responses  = ( _make_error_response(403) );
$mock_put_call_count = 0;
$token_response = App::AWS::CloudWatch::Monitor::CloudWatchClient::_get_imds_token();
is( $token_response->is_success, '', '_get_imds_token fails on 403' );
is( $mock_put_call_count,        1,  '_get_imds_token made exactly 1 PUT request on 403 (no retry)' );

note('_get_imds_token: does not retry on 404 (non-retryable)');
@mock_put_responses  = ( _make_error_response(404) );
$mock_put_call_count = 0;
$token_response = App::AWS::CloudWatch::Monitor::CloudWatchClient::_get_imds_token();
is( $token_response->is_success, '', '_get_imds_token fails on 404' );
is( $mock_put_call_count,        1,  '_get_imds_token made exactly 1 PUT request on 404 (no retry)' );

done_testing();

sub reset_vars {
    $return_expired_ttl  = 0;
    $return_empty_cache  = 0;
    $meta_data_was_written = 0;
    $return_empty_mount  = 0;
    @mock_put_responses  = ( _make_token_response() );
    $mock_put_call_count = 0;
}
