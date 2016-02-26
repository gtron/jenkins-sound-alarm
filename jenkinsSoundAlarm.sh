#!/bin/bash

JENKINS_URL="http://jenkins.myjenkins.com:8080"

# ---  DEFAULT PARAMETERS  ------------------------------------

# Wait 15 minutes before playing the alarm
DEFAULT_SNOOZE_TIME=890


DEFAULT_SOUND_FAILURE="$DIR/alarm_4s.wav"
DEFAULT_SOUND_UNESTABLE=$DEFAULT_SOUND_FAILURE
DEFAULT_SOUND_BACK="$DIR/thuglive.wav"

# -------------------------------------------------------------

DIR=$(dirname $0)
LOG_FILE="$DIR/failure_${JOB}.log"
FAILURE_FILE="$DIR/failure_${JOB}.failed"
SNOOZE_FILE="$DIR/failure_${JOB}.snooze"

# -------------------------------------------------------------


function usage {

cat <<EOF

========================= Jenkins Sound Alarm  =================================

Usage: $0 [OPTIONS]...

Options :

	-j | --job : 
					Specifies the Job name we want to monitor

	-s | --snooze :	
					Seconds to wait to play the alarm from the first time the job is not in state Success

	-f | --failure-sound :
					
					Sound file or url to play when the job status is FAILURE
					
	-u | --unestable-sound :
    			
					Sound file or url to play when the job status is UNESTABLE
    
	-b | --back-sound :
    
					Sound file or url to play when the job status backs to SUCCESS
					 
	-d | --debug :
					Activate debug messages 
			 		
	-x | --explain :
					Show the Bash execution trace
					
	-h | --help :
					Show this help screen
					    				
    				
Note:
		Usually you want to run this file periodically with a cron :
		
		*/5 * * * * $0

===============================================================================

EOF

exit -1

}


while [[ $# > 0 && "$1" =~ -* ]]
do
key="$1"

case $key in
    -j|--job)
		shift
		JOB=$1
	;;
    -d|--debug)
		DEBUG=1
	;;
    -x|--explain) 
		set -x
	;;
    -s|--snooze)
    	shift
    	SNOOZE_TIME=$1
    ;;
    -h|--help)
		usage
    ;;
    -f|--failure-sound)
    	shift
    	SOUND_FAILURE=$1
    ;;
    -u|--unestable-sound)
    	shift
    	SOUND_UNESTABLE=$1
    ;;
    -b|--back-sound)
    	shift
    	SOUND_BACK=$1
    ;;
    *)
	UNKNOWN_PARAMS="$UNKNOWN_PARAMS $key"
    ;;
esac
shift 
done

[ -z $JOB ] && JOB="D_CI_100"
[ -z SNOOZE_TIME ] && SNOOZE_TIME=$DEFAULT_SNOOZE_TIME
[ -z $SOUND_FAILURE ] && SOUND_FAILURE=$DEFAULT_SOUND_FAILURE
[ -z $SOUND_UNESTABLE ] && SOUND_UNESTABLE=$DEFAULT_SOUND_UNESTABLE
[ -z $SOUND_BACK ] && SOUND_BACK=$DEFAULT_SOUND_BACK

function log {
 [ -z $DEBUG ] || echo $@
 echo -e "$@" >> $LOG_FILE
}

log " --- $(date) "

function checkSnooze {
  [ -z $SNOOZE_TIME ] && return 0
  
  if [ -f $SNOOZE_FILE ]; then
  	FILE_EPOCH=$(stat --format %Z $SNOOZE_FILE )
	#ELAPSED_TIME=$(date -u -d @$(( $( date  +%s ) - $FILE_EPOCH )) +%T )
	ELAPSED_SECONDS=$(( $( date  +%s ) - $FILE_EPOCH ))

	log "Snooze file age: $ELAPSED_SECONDS"
      
	if [ $ELAPSED_SECONDS -ge $SNOOZE_TIME ]; then
	  	log "Snooze timed out! Removing ... "
		rm $SNOOZE_FILE
		return 0
	fi
	
  else
	log "Snoze file not found ... let's create it!"
	touch $SNOOZE_FILE
  fi

  return 1
}

function playSound {

  SOUND=$1
  [ -z $SOUND ] && SOUND=$SOUND_FAILURE

  ALARM_CMD="mplayer ${SOUND}"

  if [ -z $DEBUG ]; then
	$ALARM_CMD  # >> $LOG_FILE 2>&1
  else 
	echo "PLAYING Sound:  $ALARM_CMD"
  fi
}
    
function notifyFailure {
  
  log "NotifyFailure: $1"

  checkSnooze
  SNOOZE=$?
  if [ "$SNOOZE" = "0" ]; then
       	log "Running Alarm" 
	playSound $2
  else
  	log "Job has failed ... but let's wait a little to see if it recovers!"
  fi

  [ -f $FAILURE_FILE ] || date > $FAILURE_FILE

  return 0

}

function notifySuccess {
	log "Job Status is OK ! ($JENKINS_RESULT) "

	if [ -f $FAILURE_FILE ]; then
		playSound $SOUND_BACK
	        rm $FAILURE_FILE
	fi
}

function checkBuildable {

  URL="$JENKINS_URL/job/$JOB/api/xml?tree=buildable"

  [ -z $DEBUG ] || log "Checking if buildable ($URL)"

  JENKINS_RETURN=$( wget -q -O - "$URL"  | sed -e "s/<[^>]\+>//g" )
  
  [ -z $DEBUG ] || log "Jenkins Return: $JENKINS_RETURN "

 if [ $JENKINS_RETURN = "false" ]; then
	log "Job is not buildable ! Quitting ! " 
	exit -1
  fi

}


function checkJob {

  URL="$JENKINS_URL/job/$JOB/lastBuild/api/xml?tree=building,number,result"

  [ -z $DEBUG ] || echo -n "Checking Jenkins JOB : $JOB ($URL) ... "
  
  JENKINS_RETURN=$( wget -q -O - "$URL"  | sed -e "s@</@ </@g;s/<[^>]\+>//g" )

  log "Jenkins Return: $JENKINS_RETURN "

#  JENKINS_RESULT=$( echo $JENKINS_RESULT | grep SUCCESS )
#  [ "$JENKINS_RESULT" != "" ] && JOB_STATUS=OK || JOB_STATUS=KO
  
  JENKINS_RESULT=($JENKINS_RETURN)

  IS_BUILDING=${JENKINS_RESULT[0]}
  
  [ "$IS_BUILDING" = "true" ] && log "Job is building ... " && return 10

  BUILD_NUMBER=${JENKINS_RESULT[1]}
  JOB_RESULT=${JENKINS_RESULT[2]}

  case $JOB_RESULT in

	FAILURE)
		notifyFailure $JOB_RESULT $SOUND_FAILURE
	;;

	UNSTABLE)
		notifyFailure $JOB_RESULT $SOUND_UNESTABLE
	;;
        SUCCESS)
		
		notifySuccess
       ;; 
  esac
  

}

checkBuildable

checkJob
RES=$?
COUNTER=1
MAX_RETRIES=18

#if [ "$RES" = 10 ]; then
while [[ "$RES" != 0 && $COUNTER -lt $MAX_RETRIES ]]; do
	SLEEPTIME=30

	log Waiting $SLEEPTIME seconds ...
	sleep $SLEEPTIME
	
	log "Let's try again ... "
	checkJob
	RES=$?
#fi
done
