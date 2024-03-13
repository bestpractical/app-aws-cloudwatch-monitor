use strict;
use warnings;

use Test::More;

unless ( $ENV{TEST_RELEASE} ) {
    my $msg = 'Release test. Set $ENV{TEST_RELEASE} to a true value to run.';
    plan( skip_all => $msg );
}

eval { require ExtUtils::Manifest; };

if ($@) {
    my $msg = 'ExtUtils::Manifest required to test manifest';
    plan( skip_all => $msg );
}

my ( $missing, $extra ) = ExtUtils::Manifest::fullcheck();
ok( !scalar @{$missing}, 'no files in the manifest are missing' );
ok( !scalar @{$extra}, 'no files are missing from the manifest' );

done_testing();
