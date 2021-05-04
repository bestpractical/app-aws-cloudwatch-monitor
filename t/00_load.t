use strict;
use warnings;

use FindBin;
use lib "$FindBin::RealBin/../lib", "$FindBin::RealBin/lib";
use App::AWS::CloudWatch::Monitor::Test;

use File::Find ();
use File::Spec ();

foreach my $module (find_all_perl_modules()) {
    use_ok($module) or BAIL_OUT;
}

done_testing();

sub find_all_perl_modules {
    my $base = "$FindBin::RealBin/../";

    my @modules;
    File::Find::find(
        sub {
            my $file = $File::Find::name;
            return unless $file =~ /\.pm$/;
            return if $file =~ /Test\.pm$/;

            my $rel_path = File::Spec->abs2rel( $file, $base );
            $rel_path =~ s/^[t\/]*lib\///;
            $rel_path =~ s/\//::/g;
            $rel_path =~ s/\.pm$//;

            push( @modules, $rel_path );
        },
        $base,
    );

    return @modules;
}
