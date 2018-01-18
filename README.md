# remote-jenkins-job
Trigger a Remote Jenkins Job with parameters and get console output in real time, as well as result (pass/fail)

## Background
This script is intended to replace the Jenkins
[Parameterized Remote Trigger Plugin](https://wiki.jenkins.io/display/JENKINS/Parameterized+Remote+Trigger+Plugin).

At the time of writing this, the plugin appears unmaintained and the last commit was sometime in August, 2015.  Recent Jenkins updates have made this plugin extremely unstable, resulting in frequent `NullPointerError` failures.

## Requirements
jq, curl, Jenkins

## Usage

Extremely simple, use as follows:

`remote-job.sh -u https://jenkins-url.com -j JOB_NAME -p "PARAM1=999" -p "PARAM2=123" -t BUILD_TOKEN`

Where the following parameters are set:

* `-u`: url of jenkins host
* `-j`: JOB_NAME on jenkins host (eg master-build).
* `-p`: parameter(s) to pass in. Send multiple parameters by passing in multiple `-p` flags.
* `-t`: BUILD_TOKEN on remote machine to run job

You can optionally set the polling interval (`POLL_INTERVAL`, default 5) and build timeout (`BUILD_TIMEOUT_SECONDS`, default 3600) as environment variables.

The script will poll the job until completion, and output the console of the running job in near-real time as it is updated.  It does this by setting a cursor on the last line received and only outputting new lines (using a simple tail -n command).
