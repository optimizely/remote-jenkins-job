#!/usr/bin/env bash
###
# Trigger a Remote Jenkins Job with parameters and get console output as well as result
# Usage:
# remote-job.sh -u https://jenkins-url.com -j JOB_NAME -p "PARAM1=999" -p "PARAM2=123" -t BUILD_TOKEN
# -u: url of jenkins host
# -j: JOB_NAME on jenkins host
# -p: parameter to pass in. Send multiple parameters by passing in multiple -p flags
# -t: BUILD_TOKEN on remote machine to run job
# -i: Tell curl to ignore cert validation
###

# Number of seconds before timing out
[ -z "$BUILD_TIMEOUT_SECONDS" ] && BUILD_TIMEOUT_SECONDS=3600
# Number of seconds between polling attempts
[ -z "$POLL_INTERVAL" ] && POLL_INTERVAL=10
while getopts j:p:t:u:s:r:i opt; do
  case $opt in
    p) parameters+=("$OPTARG");;
    t) parameters+=("token=$OPTARG");;
    j) JOB_NAME=$OPTARG;;
    u) JENKINS_URL=$OPTARG;;
    s) JENKINS_USER=$OPTARG;;
    r) API_TOKEN=$OPTARG;;
    i) CURL_OPTS="-k" # tell curl to ignore cert validation
    #...
  esac
done
shift $((OPTIND -1))

[ -z "$JENKINS_URL" ] && { echo "JENKINS_URL (-u) not set"; exit 1; }
echo "[INFO] JENKINS_URL: $JENKINS_URL"
[ -z "$JOB_NAME" ] && { echo "JOB_NAME (-j) not set"; exit 1; }
echo "[INFO] JOB_NAME: $JOB_NAME"

echo "The whole list of values is '${parameters[@]}'"
for parameter in "${parameters[@]}"; do
  # If PARAMS exists, add an ampersand
  [ -n "$PARAMS" ] && PARAMS=$PARAMS\&$parameter
  # If no PARAMS exist, don't add an ampersand
  [ -z "$PARAMS" ] && PARAMS=$parameter
done
[ -z "$PARAMS" ] && { echo "[ERROR] No parameters were set!"; exit 1; }
echo "[INFO] PARAMS: $PARAMS"

# Queue up the job
# nb You must use the buildWithParameters build invocation as this
# is the only mechanism of receiving the "Queued" job id (via HTTP Location header)

REMOTE_JOB_URL="$JENKINS_URL/job/$JOB_NAME/buildWithParameters?$PARAMS"
echo "[INFO] Calling REMOTE_JOB_URL: $REMOTE_JOB_URL"

QUEUED_URL=$(curl -XPOST -sSL --user $JENKINS_USER:$API_TOKEN $CURL_OPTS -D - "$REMOTE_JOB_URL" | grep Location | awk {'print $2'})
#perl -n -e '/^Location: (.*)$/ && print "$1\n"')
[ -z "$QUEUED_URL" ] && { echo "[ERROR] No QUEUED_URL was found.  Did you remember to set a token (-t)?"; exit 1; }

# Remove extra \r at end, add /api/json path
QUEUED_URL=${QUEUED_URL%$'\r'}api/json

# Fetch the executable.url from the QUEUED url
JOB_URL=`curl -XPOST -sSL --user $JENKINS_USER:$API_TOKEN $QUEUED_URL | jq -r '.executable.url'`
[ "$JOB_URL" = "null" ] && unset JOB_URL
# Check for status of queued job, whether it is running yet
COUNTER=0
while [ -z "$JOB_URL" ]; do
  echo "[INFO] The QUEUED counter is $COUNTER"
  let COUNTER=COUNTER+$POLL_INTERVAL
  sleep $POLL_INTERVAL
  if [ "$COUNTER" -gt $BUILD_TIMEOUT_SECONDS ];
  then
    break  # Skip entire rest of loop.
  fi
  JOB_URL=`curl -XPOST -sSL --user $JENKINS_USER:$API_TOKEN $CURL_OPTS $QUEUED_URL | jq -r '.executable.url'`
  [ "$JOB_URL" = "null" ] && unset JOB_URL
done
echo "[INFO] JOB_URL: $JOB_URL"

# Job is running
IS_BUILDING="true"
COUNTER=0
OUTPUT_LINE_CURSOR=0

# Use until IS_BUILDING = false (instead of while IS_BUILDING = true)
# to avoid false positives if curl command (IS_BUILDING) fails
# while polling for status
until [ "$IS_BUILDING" = "false" ]; do
  let COUNTER=COUNTER+$POLL_INTERVAL
  sleep $POLL_INTERVAL
  if [ "$COUNTER" -gt $BUILD_TIMEOUT_SECONDS ];
  then
    echo "[ERROR] TIME-OUT: Exceeded $BUILD_TIMEOUT_SECONDS seconds"
    break  # Skip entire rest of loop.
  fi
  IS_BUILDING=`curl -XPOST -sSL --user $JENKINS_USER:$API_TOKEN $CURL_OPTS $JOB_URL/api/json | jq -r '.building'`
  # Grab total lines in console output
  NEW_LINE_CURSOR=`curl -XPOST -sSL --user $JENKINS_USER:$API_TOKEN $CURL_OPTS $JOB_URL/consoleText | wc -l`
  # subtract line count from cursor
  LINE_COUNT=`expr $NEW_LINE_CURSOR - $OUTPUT_LINE_CURSOR`
  if [ "$LINE_COUNT" -gt 0 ];
  then
    curl -XPOST -sSL --user $JENKINS_USER:$API_TOKEN $JOB_URL/consoleText | tail -$LINE_COUNT
  fi
  OUTPUT_LINE_CURSOR=$NEW_LINE_CURSOR
done

RESULT=`curl -XPOST -sSL --user $JENKINS_USER:$API_TOKEN $CURL_OPTS $JOB_URL/api/json | jq -r '.result'`
if [ "$RESULT" = 'SUCCESS' ]
then
  echo "[INFO] BUILD RESULT: $RESULT"
  exit 0
else
  echo "[ERROR] BUILD RESULT: $RESULT - Build is unsuccessful, timed out, or status could not be obtained."
  exit 1
fi
