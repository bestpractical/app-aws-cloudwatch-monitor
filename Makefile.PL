use ExtUtils::MakeMaker;

WriteMakefile(
    NAME => 'App::AWS::CloudWatch::Monitor',
    AUTHOR => 'Best Practical Solutions, LLC <modules@bestpractical.com>',
    ABSTRACT_FROM => 'lib/App/AWS/CloudWatch/Monitor.pm',
    VERSION_FROM => 'lib/App/AWS/CloudWatch/Monitor.pm',
    LICENSE => 'apache_2_0',
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            bugtracker => {
                web => 'https://github.com/bestpractical/app-aws-cloudwatch-monitor/issues',
            },
            homepage => 'https://github.com/bestpractical/app-aws-cloudwatch-monitor',
            repository => {
                type => 'git',
                url => 'https://github.com/bestpractical/app-aws-cloudwatch-monitor.git',
                web => 'https://github.com/bestpractical/app-aws-cloudwatch-monitor',
            },
        },
    },

    MIN_PERL_VERSION => '5.10.1',
    BUILD_REQUIRES => {
        'ExtUtils::MakeMaker' => '6.64',  # for TEST_REQUIRES
    },
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => '6.64',
    },
    TEST_REQUIRES => {
        'File::Find' => 0,
        'File::Spec' => 0,
        'Test::Exception' => '0.42',  # recommended by Test2
        'Test::More' => '0.98',  # for subtest()
    },
    PREREQ_PM => {
        'base' => 0,
        'Capture::Tiny' => 0,
        'Config::Tiny' => 0,
        'Compress::Zlib' => 0,
        'constant' => 0,
        'DateTime' => 0,
        'Digest::SHA' => 0,
        'Exporter' => 0,
        'File::Basename' => 0,
        'FindBin' => 0,
        'Getopt::Long' => '2.45',  # 2.36 is required for options we need, but at least 2.45 for bugfixes
        'List::Util' => 0,
        'LWP' => 6,
        'LWP::Simple' => 0,
        'Module::Loader' => 0,
        'parent' => 0,
        'Pod::Usage' => '1.67',  # rewrite in 1.62, bugfixes in 1.67
        'strict' => 0,
        'Try::Tiny' => 0,
        'URI::Escape' => 0,
        'warnings' => 0,
    },

    EXE_FILES => [
        'bin/aws-cloudwatch-monitor',
    ],

    test => {
        TESTS => 't/*.t',
    },
);
