#!/usr/bin/env bash
###
# Trigger a Remote Jenkins Job with parameters and get console output as well as result
# Usage:
# remote-job.sh -u https://jenkins-url.com -j JOB_NAME -p "PARAM1=999" -p "PARAM2=123" -t BUILD_TOKEN
# -u: url of jenkins host
# -j: JOB_NAME on jenkins host
# -p: parameter to pass in. Send multiple parameters by passing in multiple -p flags
# -t: BUILD_TOKEN on remote machine to run job
###

# Number of seconds before timing out
[ -z "$BUILD_TIMEOUT_SECONDS" ] && BUILD_TIMEOUT_SECONDS=3600
# Number of seconds between polling attempts
[ -z "$POLL_INTERVAL" ] && POLL_INTERVAL=5

while getopts j:p:t:u: opt; do
  case $opt in
    p) parameters+=("$OPTARG");;
    t) parameters+=("token=$OPTARG");;
    j) JOB_NAME=$OPTARG;;
    u) JENKINS_URL=$OPTARG;;
    #...
  esac
done
shift $((OPTIND -1))

[ -z "$JENKINS_URL" ] && { echo "JENKINS_URL (-u) not set"; exit 1; }
echo "JENKINS_URL: $JENKINS_URL"
[ -z "$JOB_NAME" ] && { echo "JOB_NAME (-j) not set"; exit 1; }
echo "JOB_NAME: $JOB_NAME"

echo "The whole list of values is '${parameters[@]}'"
for parameter in "${parameters[@]}"; do
  # If PARAMS exists, add an ampersand
  [ -n "$PARAMS" ] && PARAMS=$PARAMS\&$parameter
  # If no PARAMS exist, don't add an ampersand
  [ -z "$PARAMS" ] && PARAMS=$parameter
done
[ -z "$PARAMS" ] && { echo "No parameters were set!"; exit 1; }
echo "PARAMS: $PARAMS"

# Queue up the job
# nb You must use the buildWithParameters build invocation as this
# is the only mechanism of receiving the "Queued" job id (via HTTP Location header)

REMOTE_JOB_URL="$JENKINS_URL/job/$JOB_NAME/buildWithParameters?$PARAMS"
echo "Calling REMOTE_JOB_URL: $REMOTE_JOB_URL"

QUEUED_URL=$(curl -sSL -D - $REMOTE_JOB_URL |\
perl -n -e '/^Location: (.*)$/ && print "$1\n"')
[ -z "$QUEUED_URL" ] && { echo "No QUEUED_URL was found.  Did you remember to set a token (-t)?"; exit 1; }

# Remove extra \r at end, add /api/json path
QUEUED_URL=${QUEUED_URL%$'\r'}api/json

# Fetch the executable.url from the QUEUED url
JOB_URL=`curl -sSL $QUEUED_URL | jq -r '.executable.url'`

# Check for status of queued job, whether it is running yet
COUNTER=0
while [ -z "$JOB_URL" ]; do
  echo "The QUEUED counter is $COUNTER"
  let COUNTER=COUNTER+$POLL_INTERVAL
  sleep $POLL_INTERVAL
  if [ "$COUNTER" -gt $BUILD_TIMEOUT_SECONDS ];
  then
    break  # Skip entire rest of loop.
  fi
  JOB_URL=`curl -sSL $QUEUED_URL | jq -r '.executable.url'`
done
echo "JOB_URL: $JOB_URL"

# Job is running
IS_BUILDING="true"
COUNTER=0
OUTPUT_LINE_CURSOR=0
while [ "$IS_BUILDING" = "true" ]; do
  let COUNTER=COUNTER+$POLL_INTERVAL
  sleep $POLL_INTERVAL
  if [ "$COUNTER" -gt $BUILD_TIMEOUT_SECONDS ];
  then
    break  # Skip entire rest of loop.
  fi
  IS_BUILDING=`curl -sSL $JOB_URL/api/json | jq -r '.building'`
  NEW_LINE_CURSOR=`curl -sSL $JOB_URL/consoleText | wc -l`
  LINE_COUNT=`expr $NEW_LINE_CURSOR - $OUTPUT_LINE_CURSOR`
  if [ "$LINE_COUNT" -gt 0 ];
  then
    curl -sSL $JOB_URL/consoleText | tail -$LINE_COUNT
  fi
  OUTPUT_LINE_CURSOR=$NEW_LINE_CURSOR
done

echo $JOB_URL
RESULT=`curl -sSL $JOB_URL/api/json | jq -r '.result'`
if [ "$RESULT" = 'SUCCESS' ]
then
  echo 'BUILD RESULT: $RESULT'
  exit 0
else
  echo "BUILD RESULT: $RESULT - Build is unsuccessful, timed out, or status could not be obtained."
  exit 1
fi
