# Original file:
# Copyright 2015 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You may not
# use this file except in compliance with the License. A copy of the License
# is located at
#
#        http://aws.amazon.com/apache2.0/
#
# or in the "LICENSE" file accompanying this file. This file is distributed
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied. See the License for the specific language governing
# permissions and limitations under the License.

# Additional development:
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

package App::AWS::CloudWatch::Monitor::CloudWatchClient;

use v5.10;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT = qw();
use File::Basename;
use App::AWS::CloudWatch::Monitor::AwsSignatureV4;
use Time::Piece;
use Digest::SHA qw(hmac_sha256_base64);
use URI::Escape qw(uri_escape_utf8);
use Compress::Zlib;
use LWP 6;

use LWP::Simple qw($ua get);
$ua->timeout(2);    # timeout for meta-data calls

our $VERSION = '0.06';

our %version_prefix_map = ( '2010-08-01' => [ 'GraniteServiceVersion20100801', 'com.amazonaws.cloudwatch.v2010_08_01#' ] );

our %supported_actions = (
    'DescribeTags'        => 1,
    'PutMetricData'       => 1,
    'GetMetricStatistics' => 1,
    'ListMetrics'         => 1
);

our %numeric_parameters = (
    'Timestamp' => 'Timestamp',
    'RawValue'  => 'Value',
    'StartTime' => 'StartTime',
    'EndTime'   => 'EndTime',
    'Period'    => 'Period'
);

our %region_suffix_map = (
    'cn-north-1'     => '.cn',
    'cn-northwest-1' => '.cn'
);

use constant {
    DO_NOT_CACHE => 0,
    USE_CACHE    => 1,
};

use constant {
    OK    => 1,
    ERROR => 0,
};

our $client_version           = '1.2.0';
our $service_version          = '2010-08-01';
our $compress_threshold_bytes = 2048;
our $imds_token_ttl           = 900;            # 15 minutes
our $meta_data_short_ttl      = 21600;          # 6 hours
our $meta_data_long_ttl       = 86400;          # 1 day
our $http_request_timeout     = 5;              # seconds

# RFC3986 unsafe characters
our $unsafe_characters = "^A-Za-z0-9\-\._~";

our $region;
our $avail_zone;
our $instance_id;
our $instance_type;
our $image_id;
our $as_group_name;
our $meta_data_loc = '/var/tmp/aws-mon';

=head1 NAME

App::AWS::CloudWatch::Monitor::CloudWatchClient - subroutines for interacting with AWS

=head1 SYNOPSIS

 use App::AWS::CloudWatch::Monitor::CloudWatchClient;

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::CloudWatchClient> contains subroutines for interacting with AWS EC2 instance meta data and CloudWatch.

=head1 SUBROUTINES

=over

=item get_meta_data

Queries meta data for the current EC2 instance.

=cut

sub get_meta_data {
    my $resource  = shift;
    my $use_cache = shift;
    my ( $cache_data, $ttl_expired ) = read_meta_data( $resource, $meta_data_short_ttl );

    if ( $ttl_expired || !$cache_data ) {
        state $token_expiration_ts = 0;

        if ( $token_expiration_ts <= time() ) {
            my $user_agent = LWP::UserAgent->new( timeout => 2 );

            # Be conservative so that in borderline cases we should
            # err on the side of getting a new token a bit early
            # rather than trying to use a token for a bit too long.
            $token_expiration_ts = time() + $imds_token_ttl - 1;

            my $response = $user_agent->put(
                'http://169.254.169.254/latest/api/token',
                'X-aws-ec2-metadata-token-ttl-seconds' => $imds_token_ttl,
            );

            if ( !$response->is_success or !$response->content ) {
                warn "unable to obtain IMDSv2 token";
                return;
            }

            $ua->default_header(
                'X-aws-ec2-metadata-token' => $response->content,
            );
        }

        my $base_uri   = 'http://169.254.169.254/latest/meta-data';
        my $mount_data = get $base_uri . $resource;

        if ($mount_data) {
            $cache_data = $mount_data;

            if ($use_cache) {
                write_meta_data( $resource, $mount_data );
            }
        }

        # although the likelihood is low, there may be circumstances where the TTL of the cache
        # has expired and the meta-data mount returned no data.  in that case, use the expired
        # cache data, but warn that expired data is being used.  once the meta-data mount starts
        # to return data again, the cache will be updated and TTL countdown started over.
        else {
            if ( $ttl_expired && $cache_data ) {
                warn "meta-data resource $resource cache TTL is expired and the meta-data mount failed to return data.\n"
                    . "expired data from the cache will continue to be used and will persist in the cache until the meta-data mount starts returning data again.\n";
            }
        }
    }

    unless ($cache_data) {
        warn "meta-data resource $resource returned empty\n";
    }

    return $cache_data;
}

=item read_meta_data

Reads meta-data from the local filesystem.

Returns a list containing the cache data value and a truthy value indicating the ttl has expired.

 my ( $cache_data, $ttl_expired ) = read_meta_data( $resource, $meta_data_short_ttl );

=cut

sub read_meta_data {
    my $resource    = shift;
    my $default_ttl = shift;

    my $location = $ENV{'AWS_EC2CW_META_DATA'};
    if ( !$location ) {
        $location = $meta_data_loc if ($meta_data_loc);
    }
    my $meta_data_ttl = $ENV{'AWS_EC2CW_META_DATA_TTL'};
    $meta_data_ttl = $default_ttl if ( !defined($meta_data_ttl) );

    my $data_value;
    my $ttl_expired = 0;
    if ($location) {
        my $filename = $location . $resource;
        if ( -d $filename ) {
            $data_value = `/bin/ls $filename`;
        }
        elsif ( -e $filename ) {
            my $ret = open( my $file_fh, '<', $filename );
            unless ($ret) {
                warn "open: unable to read meta data from filesystem: $!\n";
                return;
            }
            while ( my $line = <$file_fh> ) {
                $data_value .= $line;
            }
            close $file_fh;

            my $updated  = ( stat($filename) )[9];
            my $file_age = time() - $updated;
            if ( $file_age >= $meta_data_ttl ) {
                $ttl_expired = 1;
            }
        }
    }

    chomp($data_value) if $data_value;
    return ( $data_value, $ttl_expired );
}

=item write_meta_data

Writes meta-data to the local filesystem.

=cut

sub write_meta_data {
    my $resource   = shift;
    my $data_value = shift;

    if ( $resource && $data_value ) {
        my $location = $ENV{'AWS_EC2CW_META_DATA'};
        if ( !$location ) {
            $location = $meta_data_loc if ($meta_data_loc);
        }

        if ($location) {
            my $filename  = $location . $resource;
            my $directory = File::Basename::dirname($filename);
            system( qw{ /bin/mkdir -p }, $directory ) unless -d $directory;

            open( my $file_fh, '>', $filename )
                or warn "open: unable to write meta data from filesystem: $!\n";
            print $file_fh $data_value;
            close $file_fh;
        }
    }

    return;
}

=item get_ec2_endpoint

Builds up ec2 endpoint URL for this region.

=cut

sub get_ec2_endpoint {
    my $reg      = get_region();
    my $endpoint = "https://ec2.amazonaws.com";

    if ($reg) {
        $endpoint = "https://ec2.$reg.amazonaws.com";
        if ( exists $region_suffix_map{$reg} ) {
            $endpoint .= $region_suffix_map{$reg};
        }
    }

    return $endpoint;
}

=item get_auto_scaling_group

Obtains Auto Scaling group name by making EC2 API call.

=cut

sub get_auto_scaling_group {
    if ($as_group_name) {
        return ( 200, $as_group_name );
    }

    # Try to get AS group name from the local cache and avoid calling EC2 API for
    # at least several hours. AS group name is not something that may changes but
    # just in case it may change at some point, refresh the value from the tag.

    my $resource = '/as-group-name';
    my $ttl_expired;
    ( $as_group_name, $ttl_expired ) = read_meta_data( $resource, $meta_data_short_ttl );
    if ( $as_group_name && !$ttl_expired ) {
        return ( 200, $as_group_name );
    }

    my $opts = shift;

    my %ec2_opts = ();
    $ec2_opts{'aws-credential-file'} = $opts->{'aws-credential-file'};
    $ec2_opts{'aws-access-key-id'}   = $opts->{'aws-access-key-id'};
    $ec2_opts{'aws-secret-key'}      = $opts->{'aws-secret-key'};
    $ec2_opts{'short-response'}      = 0;
    $ec2_opts{'retries'}             = 1;
    $ec2_opts{'verbose'}             = $opts->{'verbose'};
    $ec2_opts{'verify'}              = $opts->{'verify'};
    $ec2_opts{'user-agent'}          = $opts->{'user-agent'};
    $ec2_opts{'version'}             = '2011-12-15';
    $ec2_opts{'url'}                 = get_ec2_endpoint();
    $ec2_opts{'aws-iam-role'}        = $opts->{'aws-iam-role'};

    my %ec2_params = ();
    $ec2_params{'Filter.1.Name'}    = 'resource-id';
    $ec2_params{'Filter.1.Value.1'} = get_instance_id();
    $ec2_params{'Filter.2.Name'}    = 'key';
    $ec2_params{'Filter.2.Value.1'} = 'aws:autoscaling:groupName';

    my $response = call_query( 'DescribeTags', \%ec2_params, \%ec2_opts );

    my $pattern;
    if ( $response->code == 200 ) {
        $pattern = "<value>(.*?)<\/value>";
        if ( $response->content =~ /$pattern/s ) {
            $as_group_name = $1;
            write_meta_data( $resource, $as_group_name );
            return ( 200, $as_group_name );
        }
        $response->message(undef);
    }

    # In case when EC2 API call fails for whatever reason, keep using the older
    # value if it is present. Only ofter one day, assume this value is obsolete.
    # AS group name is not something that is changing on the fly anyway.

    if ( !$as_group_name ) {

        # EC2 call failed, so try using older value for AS group name
        ( $as_group_name, $ttl_expired ) = read_meta_data( $resource, $meta_data_long_ttl );
        if ($as_group_name) {
            return ( 200, $as_group_name );
        }
    }

    # Unable to obtain AutoScaling group name.
    # Return the response code and error message
    return ( $response->code, $response->message );
}

=item get_instance_id

Obtains EC2 instance id from meta data.

=cut

sub get_instance_id {
    if ( !$instance_id ) {
        $instance_id = get_meta_data( '/instance-id', USE_CACHE );
    }
    return $instance_id;
}

=item get_instance_type

Obtains EC2 instance type from meta data.

=cut

sub get_instance_type {
    if ( !$instance_type ) {
        $instance_type = get_meta_data( '/instance-type', USE_CACHE );
    }
    return $instance_type;
}

=item get_image_id

Obtains EC2 image id from meta data.

=cut

sub get_image_id {
    if ( !$image_id ) {
        $image_id = get_meta_data( '/ami-id', USE_CACHE );
    }
    return $image_id;
}

=item get_avail_zone

Obtains EC2 avilability zone from meta data.

=cut

sub get_avail_zone {
    if ( !$avail_zone ) {
        $avail_zone = get_meta_data( '/placement/availability-zone', USE_CACHE );
    }
    return $avail_zone;
}

=item get_region

Extracts region from avilability zone.

=cut

sub get_region {
    if ( !$region ) {
        my $azone = get_avail_zone();
        if ($azone) {
            $region = substr( $azone, 0, -1 );
        }
    }
    return $region;
}

=item get_endpoint

Builds up the endpoint based on the provided region.

=cut

sub get_endpoint {
    my $reg      = get_region();
    my $endpoint = "https://monitoring.amazonaws.com";

    if ($reg) {
        $endpoint = "https://monitoring.$reg.amazonaws.com";
        if ( exists $region_suffix_map{$reg} ) {
            $endpoint .= $region_suffix_map{$reg};
        }
    }

    return $endpoint;
}

=item prepare_iam_role

Read credentials from the IAM Role Metadata.

=cut

sub prepare_iam_role {
    my $opts     = shift;
    my $response = {};
    my $verbose  = $opts->{'verbose'};
    my $outfile  = $opts->{'output-file'};
    my $iam_role = $opts->{'aws-iam-role'};
    my $iam_dir  = "/iam/security-credentials/";

    # if am_role is not explicitly specified
    if ( !defined($iam_role) ) {
        my $roles       = get_meta_data( $iam_dir, DO_NOT_CACHE );
        my $nr_of_roles = $roles =~ tr/\n//;

        print_out( "No credential methods are specified. Trying default IAM role.", $outfile ) if $verbose;
        if ( $roles eq "" ) {
            return $response = { "code" => ERROR, "error" => "No IAM role is associated with this EC2 instance." };
        }
        elsif ( $nr_of_roles == 0 ) {

            # if only one role
            $iam_role = $roles;
        }
        else {
            $roles =~ s/\n/, /g;    # puts all the roles on one line
            $roles =~ s/, $//;      # deletes the comma at the end
            return { "code" => ERROR, "error" => "More than one IAM roles are associated with this EC2 instance: $roles." };
        }
    }

    my $role_content = get_meta_data( ( $iam_dir . $iam_role ), DO_NOT_CACHE );

    # Could not find the IAM role metadata
    if ( !$role_content ) {
        my $roles = get_meta_data( $iam_dir, DO_NOT_CACHE );
        my $roles_message;
        if ($roles) {
            $roles =~ s/\n/, /g;    # puts all the roles on one line
            $roles =~ s/, $//;      # deletes the comma at the end
            $roles_message = "Available roles: " . $roles;
        }
        else {
            $roles_message = "This EC2 instance does not have an IAM role associated with it.";
        }
        return { "code" => ERROR, "error" => "Failed to obtain credentials for IAM role $iam_role. $roles_message" };
    }

    print_out( "Using IAM role <$iam_role>", $outfile ) if $verbose;
    my $id;
    my $key;
    my $token;
    while ( $role_content =~ /(.*)\n/g ) {
        my $line = $1;
        if ( $line =~ /"AccessKeyId"[ \t]*:[ \t]*"(.+)"/ ) {
            $id = $1;
            next;
        }
        if ( $line =~ /"SecretAccessKey"[ \t]*:[ \t]*"(.+)"/ ) {
            $key = $1;
            next;
        }
        if ( $line =~ /"Token"[ \t]*:[ \t]*"(.+)"/ ) {
            $token = $1;
            next;
        }
    }

    my $role_statement = "from IAM role <$iam_role>";
    if ( !defined($id) && !defined($key) ) {
        return { "code" => ERROR, "error" => "Failed to parse AWS access key id and secret key $role_statement." };
    }
    elsif ( !defined($id) ) {
        return { "code" => ERROR, "error" => "Failed to parse AWS access key id $role_statement." };
    }
    elsif ( !defined($key) ) {
        return { "code" => ERROR, "error" => "Failed to parse AWS secret key $role_statement." };
    }

    $opts->{'aws-access-key-id'}  = $id;
    $opts->{'aws-secret-key'}     = $key;
    $opts->{'aws-security-token'} = $token;

    return { "code" => OK };
}

=item prepare_credentials

Checks if credential set is present. If not, reads credentials from file.

=cut

sub prepare_credentials {
    my $opts                = shift;
    my $verbose             = $opts->{'verbose'};
    my $outfile             = $opts->{'output-file'};
    my $aws_access_key_id   = $opts->{'aws-access-key-id'};
    my $aws_secret_key      = $opts->{'aws-secret-key'};
    my $aws_credential_file = $opts->{'aws-credential-file'};

    if ( defined($aws_access_key_id) && !$aws_access_key_id ) {
        return { "code" => ERROR, "error" => "Provided empty AWS access key id." };
    }
    if ( defined($aws_secret_key) && !$aws_secret_key ) {
        return { "code" => ERROR, "error" => "Provided empty AWS secret key." };
    }
    if ( $aws_access_key_id && $aws_secret_key ) {
        return { "code" => OK };
    }

    if ( !$aws_credential_file ) {
        my $env_creds_file = $ENV{'AWS_CREDENTIAL_FILE'};
        if ( defined($env_creds_file) && length($env_creds_file) > 0 ) {
            $aws_credential_file = $env_creds_file;
        }
    }

    if ( !$aws_credential_file ) {
        my $conf_file = File::Basename::dirname($0) . '/awscreds.conf';
        if ( -e $conf_file ) {
            $aws_credential_file = $conf_file;
        }
    }

    if ($aws_credential_file) {
        print_out( "Using AWS credentials file <$aws_credential_file>", $outfile ) if $verbose;
        my $file = $aws_credential_file;
        open( my $file_fh, '<:encoding(UTF-8)', $file )
            or return { "code" => ERROR, "error" => "Failed to open AWS credentials file <$file>" };

        while ( my $line = <$file_fh> ) {
            $line =~ /^$/   and next;    # skip empty lines
            $line =~ /^#.*/ and next;    # skip commented lines
            $line =~ /^\s*(.*?)=(.*?)\s*$/
                or return { "code" => ERROR, "error" => "Failed to parse AWS credential entry '$line' in <$file>." };
            my ( $key, $value ) = ( $1, $2 );
            if ( $key eq 'AWSAccessKeyId' ) {
                $opts->{'aws-access-key-id'} = $value;
            }
            elsif ( $key eq 'AWSSecretKey' ) {
                $opts->{'aws-secret-key'} = $value;
            }
        }
        close($file_fh);
    }

    $aws_access_key_id = $opts->{'aws-access-key-id'};
    $aws_secret_key    = $opts->{'aws-secret-key'};

    if ( !$aws_access_key_id || !$aws_secret_key ) {

        # if all the credential methods failed, try iam_role
        # either the default or user specified IAM role
        return prepare_iam_role($opts);
    }

    return { "code" => OK };
}

=item get_timestamp

Retrieves the local timestamp.

=cut

sub get_timestamp {
    my $t         = localtime;
    my $timestamp = $t->epoch;
    return $timestamp;
}

=item print_out

Prints out diagnostic message to a file or standard output.

=cut

sub print_out {
    my $text     = shift;
    my $filename = shift;

    if ($filename) {
        open( my $file_fh, '>>', $filename )
            or warn "open: unable to write to $filename: $!\n";
        print $file_fh "$text\n";
        close $file_fh;
    }
    else {
        print "$text\n";
    }

    return;
}

=item get_interface_version_and_type

Retrieves the interface and type prefixes for the version and action supplied.

 e.g. 2010-08-01 => [GraniteService20100801, com.amazonaws.cloudwatch.v2010_08_01#]

=cut

sub get_interface_version_and_type {
    my $params  = shift;
    my $version = $params->{'Version'};

    if ( !( defined($version) ) ) {
        $version = $service_version;
    }
    if ( !( exists $version_prefix_map{$version} ) ) {
        return { "code" => ERROR, "error" => 'Unsupported version' };
    }

    return { "code" => OK, "version" => $version_prefix_map{$version}[0], "type" => $version_prefix_map{$version}[1] };
}

=item add_simple_parameter

Creates a key-value pair string to get added to the JSON payload.

=cut

sub add_simple_parameter {
    my $param_name = shift;
    my $value      = shift;

    my $json_data = '';
    if ( exists $numeric_parameters{$param_name} ) {
        my $key = $numeric_parameters{$param_name};
        $json_data = qq("$key":$value,);
    }
    else {
        $json_data = qq("$param_name":"$value",);
    }

    return $json_data;
}

=item add_hash

Iterates through hash entries and adds them to the JSON payload.

=cut

sub add_hash {
    my $param_name = shift;
    my $hash_ref   = shift;

    my $json_data = ( ( $param_name eq '' ) ? $param_name : qq("$param_name":) ) . "{";
    while ( my ( $key, $value ) = each %{$hash_ref} ) {
        if ( ref $value eq 'ARRAY' ) {
            $json_data .= add_array( $key, $value ) . ",";
        }
        else {
            $json_data .= add_simple_parameter( $key, $value );
        }
    }
    chop($json_data) unless ( ( keys %{$hash_ref} ) == 0 );
    $json_data .= "}";

    return $json_data;
}

=item add_array

Iterates through array entries and adds them to the JSON payload.

=cut

sub add_array {
    my $param_name = shift;
    my $array_ref  = shift;

    my $json_data = ( ( $param_name eq '' ) ? $param_name : qq("$param_name":) ) . "[";
    for my $array_val ( @{$array_ref} ) {
        if ( ref $array_val eq 'HASH' ) {
            $json_data .= add_hash( '', $array_val ) . ",";
        }
        else {
            $json_data .= qq("$array_val",);
        }
    }
    chop($json_data) unless ( scalar @{$array_ref} == 0 );
    $json_data .= "]";

    return $json_data;
}

=item construct_payload

Builds a JSON payload from the request parameters.

=cut

sub construct_payload {
    my $params    = shift;
    my $json_data = add_hash( "", $params->{'Input'} );
    return $json_data;
}

=item get_json_payload_and_headers

Prepares SigV4 request headers and JSON payload for the HTTP request.

=cut

sub get_json_payload_and_headers {
    my $params = shift;
    my $opts   = shift;

    my $operation = $params->{'Operation'};
    my $json_data = construct_payload($params);

    my $sigv4 = App::AWS::CloudWatch::Monitor::AwsSignatureV4->new_aws_json( $operation, $json_data, $opts );
    if ( !( $sigv4->sign_http_post() ) ) {
        return { "code" => ERROR, "error" => $sigv4->error };
    }

    return { "code" => OK, "payload" => $json_data, "headers" => $sigv4->headers };
}

=item call_setup

Shared call setup used for both AWS/JSON and AWS/Query HTTP requests.

=cut

sub call_setup {
    my $params = shift;
    my $opts   = shift;
    my $validation_contents;

    $opts->{'http-method'} = 'POST';

    if ( !defined( $opts->{'url'} ) ) {
        $opts->{'url'} = get_endpoint();
    }

    if ( !defined( $opts->{'version'} ) ) {
        $opts->{'version'} = $service_version;
    }
    $params->{'Version'} = $opts->{'version'};

    if ( !defined( $opts->{'user-agent'} ) ) {
        $opts->{'user-agent'} = "CloudWatch-Scripting/$client_version";
    }

    return prepare_credentials($opts);
}

=item call

Helper method used by both call_json and call_query.

Configures and sends the HTTP request and passes result back to caller.

=cut

sub call {
    my $payload         = shift;
    my $headers         = shift;
    my $opts            = shift;
    my $failure_pattern = shift;

    my $user_agent = LWP::UserAgent->new( agent => $opts->{'user-agent}'} );
    $user_agent->timeout($http_request_timeout);

    my $http_headers = HTTP::Headers->new( %{$headers} );
    my $request      = HTTP::Request->new( $opts->{'http-method'}, $opts->{'url'}, $http_headers, $payload );

    if ( defined( $opts->{'enable-compression'} ) && length($payload) > $compress_threshold_bytes ) {
        $request->encode('gzip');
    }

    my $response;
    my $keep_trying   = 1;
    my $call_attempts = 1;
    my $endpoint      = $opts->{'url'};
    my $verbose       = $opts->{'verbose'};
    my $outfile       = $opts->{'output-file'};

    print_out( "Endpoint: $endpoint", $outfile ) if $verbose;
    print_out( "Payload: $payload",   $outfile ) if $verbose;

    # initial and max delay in seconds between retries
    my $delay     = $opts->{'initial-delay'} || 4;
    my $max_delay = $opts->{'max-delay'} || 16;

    if ( defined( $opts->{'retries'} ) ) {
        $call_attempts += $opts->{'retries'};
    }

    my $response_code = 0;

    if ( $opts->{'verify'} ) {
        return ( HTTP::Response->new( 200, 'This is a verification run, not an actual response.' ) );
    }

    for ( my $i = 0; $i < $call_attempts && $keep_trying; ++$i ) {
        my $attempt = $i + 1;
        $response      = $user_agent->request($request);
        $response_code = $response->code;
        if ($verbose) {
            print_out( "Received HTTP status $response_code on attempt $attempt", $outfile );
            if ( $response_code != 200 ) {
                print_out( $response->content, $outfile );
            }
        }
        $keep_trying = 0;
        if ( $response_code >= 500 ) {
            $keep_trying = 1;
        }
        elsif ( $response_code == 400 ) {

            # special case to handle throttling fault
            my $pattern = "Throttling";
            if ( $response->content =~ m/$pattern/ ) {
                print_out( "Request throttled.", $outfile ) if $verbose;
                $keep_trying = 1;
            }
        }
        if ( $keep_trying && $attempt < $call_attempts ) {
            print_out( "Waiting $delay seconds before next retry.", $outfile ) if $verbose;
            sleep($delay);
            my $incdelay = $delay * 2;
            $delay = $incdelay > $max_delay ? $max_delay : $incdelay;
        }
    }

    print_out( $response->content, $outfile ) if ( $verbose && $response_code == 200 );

    if ( !$response->is_success ) {
        if ( $response->content =~ /$failure_pattern/s ) {
            $response->message($1);
        }
        elsif ( $response->content =~ m/__type.*?#(.*?)"}/ ) {
            $response->message($1);
        }
        else {
            $response->message( $response->content );
        }
    }

    return $response;
}

=item call_query

Makes a remote invocation to the CloudWatch service using the AWS/Query format.

Returns request ID, if successful, or error message if unsuccessful.

=cut

sub call_query {
    my $operation = shift;
    my $params    = shift;
    my $opts      = shift;
    my $validation_contents;
    my $payload;
    my $headers         = {};
    my $failure_pattern = "<Message>(.*?)<\/Message>";
    $params->{'Action'} = $operation;

    $validation_contents = call_setup( $params, $opts );

    if ( $validation_contents->{"code"} == ERROR ) {
        return ( HTTP::Response->new( $validation_contents->{"code"}, $validation_contents->{"error"} ) );
    }

    my $sigv4 = App::AWS::CloudWatch::Monitor::AwsSignatureV4->new_aws_query( $params, $opts );

    if ( !$sigv4->sign_http_post() ) {
        return ( HTTP::Response->new( 400, $sigv4->{'error'} ) );
    }

    $payload = $sigv4->{'payload'};
    $headers = $sigv4->{'headers'};

    return call( $payload, $headers, $opts, $failure_pattern );
}

=item call_json

Makes a remote invocation to the CloudWatch service using the AWS/JSON format.

Returns the full response if successful, or error message if unsuccessful.

=back

=cut

sub call_json {
    my $operation = shift;
    my $params    = shift;
    my $opts      = shift;
    my $validation_contents;
    my $payload;
    my $headers         = {};
    my $failure_pattern = "\"message\":\"(.*?)\"";

    $validation_contents = call_setup( $params, $opts );

    if ( $validation_contents->{"code"} == ERROR ) {
        return ( HTTP::Response->new( $validation_contents->{"code"}, $validation_contents->{"error"} ) );
    }

    if ( !( exists $supported_actions{$operation} ) ) {
        return ( HTTP::Response->new( ERROR, 'Unsupported Operation' ) );
    }

    $validation_contents = get_interface_version_and_type($params);

    if ( $validation_contents->{"code"} == ERROR ) {
        return ( HTTP::Response->new( $validation_contents->{"code"}, $validation_contents->{"error"} ) );
    }

    $params->{'Operation'} = $validation_contents->{"version"} . "." . $operation;
    $params->{'Input'}->{'__type'} = $validation_contents->{"type"} . $operation . "Input";

    $validation_contents = get_json_payload_and_headers( $params, $opts );

    if ( $validation_contents->{"code"} == ERROR ) {
        return ( HTTP::Response->new( $validation_contents->{"code"}, $validation_contents->{"error"} ) );
    }

    $payload = $validation_contents->{"payload"};
    $headers = $validation_contents->{"headers"};

    return call( $payload, $headers, $opts, $failure_pattern );
}

1;
