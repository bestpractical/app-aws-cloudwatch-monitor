# Original file:
# Copyright 2012 Amazon.com, Inc. or its affiliates. All Rights Reserved.
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

package App::AWS::CloudWatch::Monitor::AwsSignatureV4;

use strict;
use warnings;

# Package URI::Escape is implemented in Perl.
use URI::Escape qw(uri_escape_utf8);

# Package Digest::SHA is implemnted in C for performance.
use Digest::SHA qw(sha256_hex hmac_sha256 hmac_sha256_hex);

# For using PurePerl implementation of SHA functions
# use Digest::SHA::PurePerl qw(sha256_hex hmac_sha256 hmac_sha256_hex);

our $VERSION = '0.06';

# RFC3986 safe/unsafe characters
our $SAFE_CHARACTERS   = 'A-Za-z0-9\-\._~';
our $UNSAFE_CHARACTERS = '^' . $SAFE_CHARACTERS;

# Name of the signature encoding algorithm.
our $ALGORITHM_NAME = 'AWS4-HMAC-SHA256';

=head1 NAME

App::AWS::CloudWatch::Monitor::AwsSignatureV4 - methods for creating signing objects

=head1 SYNOPSIS

 use App::AWS::CloudWatch::Monitor::AwsSignatureV4;

=head1 DESCRIPTION

C<App::AWS::CloudWatch::Monitor::AwsSignatureV4> contains methods for creating signing objects for interacting with AWS.

=head1 CONSTRUCTORS

=over

=item new

Creates a new signing context object for signing an arbitrary request.

Signing context object is a hash of all request data needed to create
a valid AWS Signature V4. After the signing takes place, the context object
gets populated with intermediate signing artifacts and the actual signature.

Input:

 $opts - reference to hash that contains control options for the request
   url => endpoint of the service to call, e.g. https://monitoring.us-west-2.amazonaws.com/
       (the URL can contain path but it should not include query string, i.e. args after ?)
   aws-region => explicitly specifies AWS region (if not specified, region is extracted
       from endpoint URL; if region is not part of URL, 'us-east-1' is used by default)
   aws-service => explicitly specifies AWS service name (this is necessary when service
       name is not part of the endpoint URL, e.g. mail/ses, but usually it is)
   aws-access-key-id => Access Key Id of AWS credentials
   aws-secret-key => Secret Key of AWS credentials
   aws-security-token => Security Token in case of STS call

=cut

sub new {
    my $class = shift;
    my $self  = { opts => shift };
    $self->{'payload'} = '';
    bless $self, $class;
    return $self;
}

=item new_aws_query

Creates a new signing context object for signing AWS/Query request.

AWS/Query request can be signed for either HTTP GET method or POST method.
The recommended method is POST as it skips sorting of query string keys
and therefore performs faster.

Input:

 $params - reference to the hash that contains all (name, value) pairs of AWS/Query request
   (do not url-encode this data, it will be done as a part of signing and creating payload)
 $opts - see defition of 'new' constructor

=cut

sub new_aws_query {
    my $class = shift;
    my $self  = { params => shift, opts => shift };
    $self->{'content-type'} = 'application/x-www-form-urlencoded; charset=utf-8';
    $self->{'payload'}      = '';
    return bless $self, $class;
}

=item new_rpc_json

Creates a new signing context object for signing RPC/JSON request.
It only makes sense to sign JSON request for HTTP POST method.

Input:

 $payload - input data in RPC/JSON format
 $opts - see defition of 'new' constructor

=cut

sub new_rpc_json {
    my $class = shift;
    my $self  = { payload => shift, opts => shift };
    $self->{'content-type'} = 'application/json; charset=utf-8';
    bless $self, $class;
    return $self;
}

=item new_aws_json

Creates a new signing context object for signing AWS/JSON request.
It only makes sense to sign JSON request for HTTP POST method.

Input:

 $operation - operation name to invoke
 $payload - input data in AWS/JSON format
 $opts - see defition of 'new' constructor

=back

=cut

sub new_aws_json {
    my $class     = shift;
    my $operation = shift;
    my $payload   = shift;
    my $opts      = shift;
    my $self      = { payload => $payload, opts => $opts };

    $self->{'content-type'} = 'application/x-amz-json-1.0';

    if ( not exists $opts->{'extra-headers'} ) {
        $opts->{'extra-headers'} = {};
    }

    my $extra_headers = $opts->{'extra-headers'};
    $extra_headers->{'X-Amz-Target'} = $operation;

    bless $self, $class;
    return $self;
}

=head1 METHODS/SUBROUTINES

=over

=item sign_http_request

Signs the generic HTTP request.

Input: (all arguments optional and if specified override what is currently set)

 $method - HTTP method
 $ctype - content-type of the body
 $payload - request body data

=cut

sub sign_http_request {
    my $self    = shift;
    my $method  = shift;
    my $ctype   = shift;
    my $payload = shift;

    $self->{'http-method'}  = $method  if $method;
    $self->{'content-type'} = $ctype   if $ctype;
    $self->{'payload'}      = $payload if $payload;

    my $opts = $self->{opts};
    $opts->{'create-authz-header'} = 1;
    $self->{'request-url'}         = $opts->{'url'};

    if ( !$self->sign() ) {
        return 0;
    }

    $self->create_authz_header();
    return 1;
}

=item sign_http_post

Signs request for HTTP POST.

=cut

sub sign_http_post {
    my $self = shift;
    return $self->sign_http_request('POST');
}

=item sign_http_put

Signs request for HTTP PUT.

=cut

sub sign_http_put {
    my $self = shift;
    return $self->sign_http_request('PUT');
}

=item sign_http_get

Signs request for HTTP GET.

=cut

sub sign_http_get {
    my $self = shift;
    my $opts = $self->{opts};
    $self->{'http-method'} = 'GET';

    if ( !$self->sign() ) {
        return 0;
    }

    my $postfix      = "";
    my $query_string = $self->{'query-string'};

    if ($query_string) {
        $postfix = '?' . $query_string;
    }
    $self->{'request-url'} = $opts->{'url'} . $postfix;

    $postfix .= ( $query_string ? '&' : '?' );
    $self->{'signed-url'} = $opts->{'url'} . $postfix . 'X-Amz-Signature=' . $self->{'signature'};

    if ( $opts->{'create-authz-header'} ) {
        $self->create_authz_header();
    }

    return 1;
}

=item sign

Prepares and signs the request data.

=cut

sub sign {
    my $self = shift;

    if ( !$self->initialize() ) {
        return 0;
    }

    $self->create_basic_headers();
    $self->create_query_string();
    $self->create_signature();

    return 1;
}

=item headers

Returns reference to a hash containing all required HTTP headers.
In case of HTTP POST and PUT methods it will also include the
Authorization header that carries the signature itself.

=cut

sub headers {
    my $self = shift;
    return $self->{'headers'};
}

=item payload

In case of AWS/Query request and HTTP POST or PUT method, returns
url-encoded query string to be used as a body of HTTP POST request.

=cut

sub payload {
    my $self = shift;
    return $self->{'payload'};
}

=item signed_url

Returns complete signed URL to be used in HTTP GET request 'as is'.
You can place this value into Web browser location bar and make a call.

=cut

sub signed_url {
    my $self = shift;
    return $self->{'signed-url'};
}

=item request_url

Returns URL to be used in HTTP GET request for the case,
when the signature is passed via Authorization HTTP header.

You can not use this URL with the Web browser since it does
not contain the signature.

=cut

sub request_url {
    my $self = shift;
    return $self->{'request-url'};
}

=item error

Returns an error message if any.

=cut

sub error {
    my $self = shift;
    return $self->{'error'};
}

=item get_timestamp_daystamp

Returns both timestamp and daystamp in the format required for SigV4.

=cut

sub get_timestamp_daystamp {
    my $time = shift;
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
    my $timestamp = sprintf( "%04d%02d%02dT%02d%02d%02dZ", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
    my $daystamp  = substr( $timestamp, 0, 8 );
    return ( $timestamp, $daystamp );
}

=item extract_fqdn_from_url

Applies regex to get FQDN from URL.

=cut

sub extract_fqdn_from_url {
    my $fqdn = shift;
    $fqdn =~ s!^https?://([^/:?]*).*$!$1!;
    return $fqdn;
}

=item extract_service_from_fqdn

Applies regex to get service name from the FQDN.

=cut

sub extract_service_from_fqdn {
    my $fqdn    = shift;
    my $service = $fqdn;
    $service =~ s!^([^\.]+)\..*$!$1!;
    return $service;
}

=item extract_region_from_fqdn

Applies regex to get region from the FQDN.

=cut

sub extract_region_from_fqdn {
    my $fqdn  = shift;
    my @parts = split( /\./, $fqdn );
    return $parts[1] if $parts[1] =~ /\w{2}-\w+-\d+/;
    return 'us-east-1';
}

=item extract_path_from_url

Applies regex to get the path part of the URL.

=cut

sub extract_path_from_url {
    my $url  = shift;
    my $path = $url;
    $path =~ s!^https?://[^/]+([^\?]*).*$!$1!;
    $path = '/' if !$path;
    return $path;
}

=item create_basic_headers

Populates essential HTTP headers required for SigV4.

 CanonicalHeaders =
   CanonicalHeadersEntry0 + CanonicalHeadersEntry1 + ... + CanonicalHeadersEntryN

 CanonicalHeadersEntry =
   LOWERCASE(HeaderName) + ':' + TRIM(HeaderValue) '\n'

 SignedHeaders =
   LOWERCASE(HeaderName0) + ';' + LOWERCASE(HeaderName1) + ... + LOWERCASE(HeaderNameN)

=cut

sub create_basic_headers {
    my $self = shift;
    my $opts = $self->{opts};

    my %headers = ();
    $headers{'Host'} = $self->{'fqdn'};

    my $extra_date_specified = 0;
    my $extra_headers        = $opts->{'extra-headers'};

    if ($extra_headers) {
        foreach my $extra_name ( keys %{$extra_headers} ) {
            $headers{$extra_name} = $extra_headers->{$extra_name};
            if ( lc($extra_name) eq 'date' || lc($extra_name) eq 'x-amz-date' ) {
                $extra_date_specified = 1;
            }
        }
    }

    if ( $opts->{'aws-security-token'} ) {
        $headers{'X-Amz-Security-Token'} = $opts->{'aws-security-token'};
    }

    if ( !$extra_date_specified && $opts->{'create-authz-header'} ) {
        $headers{'X-Amz-Date'} = $self->{'timestamp'};
    }

    if ( $self->{'http-method'} ne 'GET' && $self->{'content-type'} ) {
        $headers{'Content-Type'} = $self->{'content-type'};
    }

    my %lc_headers        = ();
    my $signed_headers    = '';
    my $canonical_headers = '';

    foreach my $header_name ( keys %headers ) {
        my $header_value = $headers{$header_name};

        # trim leading and trailing whitespaces, see
        # http://perldoc.perl.org/perlfaq4.html#How-do-I-strip-blank-space-from-the-beginning%2fend-of-a-string%3f
        $header_value =~ s/^\s+//;
        $header_value =~ s/\s+$//;

        # now convert sequential spaces to a single space, but do not remove
        # extra spaces from any values that are inside quotation marks
        my @parts = split /("[^"]*")/, $header_value;
        foreach my $part (@parts) {
            unless ( $part =~ /^"/ ) {
                $part =~ s/[ ]+/ /g;
            }
        }
        $header_value = join '', @parts;
        $lc_headers{ lc($header_name) } = $header_value;
    }

    for my $lc_header ( sort keys %lc_headers ) {
        $signed_headers    .= ';' if length($signed_headers) > 0;
        $signed_headers    .= $lc_header;
        $canonical_headers .= $lc_header . ':' . $lc_headers{$lc_header} . "\n";
    }

    $self->{'signed-headers'}    = $signed_headers;
    $self->{'canonical-headers'} = $canonical_headers;
    $self->{'headers'}           = \%headers;

    return 1;
}

=item initialize

Validates input and populates essential pre-requisites.

=cut

sub initialize {
    my $self = shift;
    my $opts = $self->{opts};

    my $url = $opts->{'url'};
    if ( !$url ) {
        $self->{'error'} = 'Endpoint URL is not specified.';
        return 0;
    }
    if ( index( $url, '?' ) != -1 ) {
        $self->{'error'} = 'Endpoint URL cannot contain query string.';
        return 0;
    }

    my $akid = $opts->{'aws-access-key-id'};
    if ( !$akid ) {
        $self->{'error'} = 'AWS Access Key Id is not specified.';
        return 0;
    }
    if ( !$opts->{'aws-secret-key'} ) {
        $self->{'error'} = 'AWS Secret Key is not specified.';
        return 0;
    }

    # obtain FQDN from the endpoint url
    my $fqdn = extract_fqdn_from_url($url);
    if ( !$fqdn ) {
        $self->{'error'} = 'Failed to extract FQDN from endpoint URL.';
        return 0;
    }
    $self->{'fqdn'} = $fqdn;

    # use pre-defined region if specified, otherwise grab it from url
    my $region = $opts->{'aws-region'};
    if ( !$region ) {

        # if region is not part of url, the default region is returned
        $region = extract_region_from_fqdn($fqdn);
    }
    $self->{'region'} = $region;

    # use pre-defined service if specified, otherwise grab it from url
    # this is specifically important when url does not include service name, e.g. ses/mail
    my $service = $opts->{'aws-service'};
    if ( !$service ) {
        $service = extract_service_from_fqdn($fqdn);
        if ( !$service ) {
            $self->{'error'} = 'Failed to extract service name from endpoint URL.';
            return 0;
        }
    }
    $self->{'service'} = $service;

    # obtain uri path part from the endpoint url
    my $path = extract_path_from_url($url);
    if ( index( $path, '.' ) != -1 || index( $path, '//' ) != -1 ) {
        $self->{'error'} = 'Endpoint URL path must be normalized.';
        return 0;
    }
    $self->{'http-path'} = $path;

    # initialize time of the signature

    my ( $timestamp, $daystamp );

    if ( $opts->{'timestamp'} ) {
        $timestamp = $opts->{'timestamp'};
        $daystamp  = substr( $timestamp, 0, 8 );
    }
    else {
        my $time = time();
        $self->{'time'} = $time;
        ( $timestamp, $daystamp ) = get_timestamp_daystamp($time);
    }
    $self->{'timestamp'} = $timestamp;
    $self->{'daystamp'}  = $daystamp;

    # initialize scope & credential

    my $scope = "$daystamp/$region/$service/aws4_request";
    $self->{'scope'} = $scope;

    my $credential = "$akid/$scope";
    $self->{'credential'} = $credential;

    return 1;
}

=item create_query_string

Builds up AWS Query request as a chain of url-encoded name=value pairs separated by &.

Note that SigV4 is payload-agnostic when it comes to POST request body so there is no
need to sort arguments in the AWS Query string for the POST method.

=cut

sub create_query_string {
    my $self   = shift;
    my $opts   = $self->{opts};
    my $params = $self->{params};

    if ( !$params ) {
        $self->{'query-string'} = '';
        return 1;
    }

    my @args = ();
    my @keys = ();

    my $http_method = $self->{'http-method'};

    if ( $http_method eq 'GET' ) {
        if ( !$opts->{'create-authz-header'} ) {
            $params->{'X-Amz-Date'}          = $self->{'timestamp'};
            $params->{'X-Amz-Algorithm'}     = $ALGORITHM_NAME;
            $params->{'X-Amz-Credential'}    = $self->{'credential'};
            $params->{'X-Amz-SignedHeaders'} = $self->{'signed-headers'};
        }

        if ( $opts->{'aws-security-token'} ) {
            $params->{'X-Amz-Security-Token'} = $opts->{'aws-security-token'};
        }

        @keys = sort keys %{$params};
    }
    else    # POST
    {   @keys = keys %{$params};
    }

    foreach my $key (@keys) {
        my $value = $params->{$key};

        my ( $ekey, $evalue ) = ( uri_escape_utf8( $key, $UNSAFE_CHARACTERS ), uri_escape_utf8( $value, $UNSAFE_CHARACTERS ) );

        push @args, "$ekey=$evalue";
    }

    my $aws_query_string = join '&', @args;

    if ( $http_method eq 'GET' ) {
        $self->{'query-string'} = $aws_query_string;
        $self->{'payload'}      = '';
    }
    else    # POST
    {   $self->{'query-string'} = '';
        $self->{'payload'}      = $aws_query_string;
    }

    return 1;
}

=item create_canonical_request

 CanonicalRequest =
   Method + '\n' +
   CanonicalURI + '\n' +
   CanonicalQueryString + '\n' +
   CanonicalHeaders + '\n' +
   SignedHeaders + '\n' +
   HEX(Hash(Payload))

=cut

sub create_canonical_request {
    my $self = shift;
    my $opts = $self->{opts};

    my $canonical_request = $self->{'http-method'} . "\n";
    $canonical_request .= $self->{'http-path'} . "\n";
    $canonical_request .= $self->{'query-string'} . "\n";
    $canonical_request .= $self->{'canonical-headers'} . "\n";
    $canonical_request .= $self->{'signed-headers'} . "\n";
    $canonical_request .= sha256_hex( $self->{'payload'} );

    $self->{'canonical-request'} = $canonical_request;
    return $canonical_request;
}

=item create_string_to_sign

 StringToSign =
   Algorithm + '\n' +
   Timestamp + '\n' +
   Scope + '\n' +
   HEX(Hash(CanonicalRequest))

=cut

sub create_string_to_sign {
    my $self = shift;
    my $opts = $self->{opts};

    my $canonical_request = $self->create_canonical_request();

    my $string_to_sign = $ALGORITHM_NAME . "\n";
    $string_to_sign .= $self->{'timestamp'} . "\n";
    $string_to_sign .= $self->{'scope'} . "\n";
    $string_to_sign .= sha256_hex($canonical_request);

    $self->{'string-to-sign'} = $string_to_sign;

    return $string_to_sign;
}

=item create_signature

Performs the actual signing of the request.

=cut

sub create_signature {
    my $self = shift;
    my $opts = $self->{opts};

    my $ksecret  = $opts->{'aws-secret-key'};
    my $kdate    = hmac_sha256( $self->{'daystamp'}, 'AWS4' . $ksecret );
    my $kregion  = hmac_sha256( $self->{'region'},   $kdate );
    my $kservice = hmac_sha256( $self->{'service'},  $kregion );
    my $kcreds   = hmac_sha256( 'aws4_request',      $kservice );

    my $string_to_sign = $self->create_string_to_sign();
    my $signature      = hmac_sha256_hex( $string_to_sign, $kcreds );
    $self->{'signature'} = $signature;

    return $signature;
}

=item create_authz_header

Populates HTTP header that carries authentication data.

=back

=cut

sub create_authz_header {
    my $self = shift;
    my $opts = $self->{opts};

    my $credential     = $self->{'credential'};
    my $signed_headers = $self->{'signed-headers'};
    my $signature      = $self->{'signature'};

    my $authorization = "$ALGORITHM_NAME Credential=$credential, " . "SignedHeaders=$signed_headers, " . "Signature=$signature";

    my $headers = $self->{'headers'};
    $headers->{'Authorization'} = $authorization;

    return 1;
}

1;
