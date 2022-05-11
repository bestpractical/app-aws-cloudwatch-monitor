# NAME

App::AWS::CloudWatch::Monitor - collect and send metrics to AWS CloudWatch

# SYNOPSIS

    use App::AWS::CloudWatch::Monitor;

    my $monitor = App::AWS::CloudWatch::Monitor->new();
    $monitor->run(\%opt, \@ARGV);

    aws-cloudwatch-monitor [--check <module>]
                           [--from-cron] [--verify] [--verbose]
                           [--version] [--help]

# DESCRIPTION

`App::AWS::CloudWatch::Monitor` is an extensible framework for collecting and sending custom metrics to AWS CloudWatch from an AWS EC2 instance.

For the commandline interface to `App::AWS::CloudWatch::Monitor`, see the documentation for [aws-cloudwatch-monitor](https://metacpan.org/pod/aws-cloudwatch-monitor).

For adding check modules, see the documentation for [App::AWS::CloudWatch::Monitor::Check](https://metacpan.org/pod/App::AWS::CloudWatch::Monitor::Check).

# CONSTRUCTOR

- new

    Returns a new `App::AWS::CloudWatch::Monitor` object.

# METHODS

- config

    Returns the loaded config.

- run

    Loads and runs the specified check modules to gather metric data.

    For options and arguments to `run`, see the documentation for [aws-cloudwatch-monitor](https://metacpan.org/pod/aws-cloudwatch-monitor).

# INSTALLATION

    perl Makefile.PL
    make
    make test && sudo make install

`App::AWS::CloudWatch::Monitor` can also be installed using [cpanm](https://metacpan.org/pod/cpanm).

    cpanm App::AWS::CloudWatch::Monitor

# CONFIGURATION

To send metrics to AWS, you need to provide the access key id and secret access key for your configured AWS CloudWatch service.  You can set these in the file `config.ini`.

An example is provided as part of this distribution.  The user running the metric script, like the user configured in cron for example, will need access to the configuration file.

To set up the configuration file, copy `config.ini.example` into one of the following locations:

- `$ENV{HOME}/.config/aws-cloudwatch-monitor/config.ini`
- `/etc/aws-cloudwatch-monitor/config.ini`

After creating the file, edit and update the values accordingly.

    [aws]
    aws_access_key_id = example
    aws_secret_access_key = example

**NOTE:** If the `$ENV{HOME}/.config/aws-cloudwatch-monitor/` directory exists, `config.ini` will be loaded from there regardless of a config file in `/etc/aws-cloudwatch-monitor/`.

# BUGS AND ENHANCEMENTS

Please report any bugs or feature requests at [rt.cpan.org](https://rt.cpan.org/Public/Dist/Display.html?Name=App-AWS-CloudWatch-Monitor).

Please include in the bug report:

- the operating system `aws-cloudwatch-monitor` is running on
- the output of the command `aws-cloudwatch-monitor --version`
- the command being run, error, and any additional steps to reproduce the issue
