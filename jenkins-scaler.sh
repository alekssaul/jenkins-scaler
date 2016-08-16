#!/bin/bash
set -e 

JENKINSNAMESPACE=${JENKINSNAMESPACE:-jenkins}
JENKINSK8sRC=${JENKINSK8sRC:-jenkins-builder}
JENKINSEXTRABUILDERS=${JENKINSEXTRABUILDERS:-1}
JENKINSURL=${JENKINSURL:-http://jenkins:8080}
JENKINSMINNUMBUILDERS=${JENKINSMINNUMBUILDERS:-2}

function auto_scale_down {	
	kubectl --namespace=$JENKINSNAMESPACE get rc $JENKINSK8sRC -o yaml > /tmp/jenkins-builders-rc.yaml
	kubectl --namespace=$JENKINSNAMESPACE delete rc $JENKINSK8sRC --cascade=false

	# detect and delete idle pods
	JENKINSPODSTOKILL=($(curl -s -k -m 10  $JENKINSURL/computer/api/json | jq '.computer[] | select (.numExecutors | contains (1)) | select(.idle == true) | .displayName'))
	JENKINSPODSTOKILLCOUNT=$(curl -s -k -m 10  $JENKINSURL/computer/api/json | jq '.computer[] | select (.numExecutors | contains (1)) | select(.idle == true) | .displayName' | grep -c '')
	JENKINSWORKERCOUNT=$(curl -s -k -m 10  $JENKINSURL/computer/api/json | jq '.computer[] | select (.numExecutors | contains (1)) | select(.idle == false) | .displayName' | grep -c '')

	if [ $(expr $JENKINS_BUILDERSCOUNT - $JENKINSPODSTOKILLCOUNT) -lt $(expr $JENKINSWORKERCOUNT + $JENKINSEXTRABUILDERS ) ]; then
		# don't kill them all		
		killlimit=$(expr $JENKINS_BUILDERSCOUNT - $JENKINSWORKERCOUNT - $JENKINSEXTRABUILDERS )
	else 
		killlimit=$JENKINSPODSTOKILLCOUNT
	fi


	echo `date` - Will kill $killlimit idle pods 
	killcounter=0
	for pod in "${JENKINSPODSTOKILL[@]}"; do
		realpod=$(echo $pod | sed 's/.\(.*\)/\1/' | sed 's/\(.*\)./\1/'	)			
		realpodname=$(curl -s -k -m 10 -d "script=println InetAddress.localHost.hostName" $JENKINSURL/computer/$realpod/scriptText)								
		if [ $killcounter -lt $killlimit ]; then														
			kubectl --namespace=$JENKINSNAMESPACE delete pod $realpodname --now
		fi
		killcounter=$(($killcounter + 1))	
	done 

	newscale=$(expr $JENKINS_BUILDERSCOUNT - $killlimit)
	echo `date` - Scaling down Jenkins Builders from $JENKINS_BUILDERSCOUNT to $newscale ...
	sed -i 's@replicas: '$JENKINS_BUILDERSCOUNT'@replicas: '$newscale'@g' /tmp/jenkins-builders-rc.yaml	

	kubectl --namespace=$JENKINSNAMESPACE create -f /tmp/jenkins-builders-rc.yaml 
}

function scale_up () {
	echo `date` - Scaling up Jenkins Builders from $JENKINS_BUILDERSCOUNT to $1 ...
	kubectl --namespace=$JENKINSNAMESPACE scale rc $JENKINSK8sRC --replicas=$1
}

function query_jenkins {
	export JENKINS_BUILDERSCOUNT=$(kubectl --namespace=$JENKINSNAMESPACE get rc $JENKINSK8sRC --output=jsonpath={.spec.replicas})
	echo `date` - JENKINS_BUILDERSCOUNT=$JENKINS_BUILDERSCOUNT
	{ 
		JENKINSCURRENTQUEUECOUNT=$(curl -s -k -m 10  $JENKINSURL/queue/api/json | jq '.items[].id' | grep -c '') 
	} || { 
		JENKINSCURRENTQUEUECOUNT="0"
	}
	
	echo `date` - Jenkins Queue has $JENKINSCURRENTQUEUECOUNT items
	{
		JENKINSIDLENODESCOUNT=($(curl -s -k -m 10  $JENKINSURL/computer/api/json | jq '.computer[] | select (.numExecutors | contains (1)) | select(.idle == true) | .displayName' | grep -c ''))
	} || {
		JENKINSIDLENODESCOUNT="0"
	}

	
	if [ "$JENKINSCURRENTQUEUECOUNT" -ne "0" ]; then
		if [ "$JENKINS_BUILDERSCOUNT" -ge "$JENKINSMINNUMBUILDERS" ]; then 			
			newscale=$(expr $JENKINS_BUILDERSCOUNT + $JENKINSCURRENTQUEUECOUNT + JENKINSEXTRABUILDERS )
			scale_up $newscale
		fi
	else
		if [ "$JENKINS_BUILDERSCOUNT" -lt "$JENKINSMINNUMBUILDERS" ]; then
			echo `date` - Jenkins Builders does not meet minimum: $JENKINSMINNUMBUILDERS builders, scaling up
			scale_up $JENKINSMINNUMBUILDERS
		elif [ "$JENKINSIDLENODESCOUNT" -eq "0" ]; then
			echo `date` - No idle nodes, spinning one
			newscale=$(expr $JENKINS_BUILDERSCOUNT + 1)
			scale_up $newscale
		elif [ "$JENKINS_BUILDERSCOUNT" -eq "$JENKINSMINNUMBUILDERS" ]; then 
			echo `date` - No action needed			
		elif [ "$JENKINSIDLENODESCOUNT" -eq "$JENKINSEXTRABUILDERS" ]; then
			echo `date` - No action needed
		else 
			auto_scale_down
		fi
	fi
}

function sanity_check {
	kubectl --namespace=$JENKINSNAMESPACE get rc $JENKINSK8sRC  2> /dev/stdout 1> /dev/null || exit 
	pendingpods=$(kubectl --namespace=$JENKINSNAMESPACE get pods --selector=role=agent --output=json | jq '.items[].status | select(.phase=="Pending")')
	while [[ $pendingpods ]]; do 
		pendingpods=$(kubectl --namespace=$JENKINSNAMESPACE get pods --selector=role=agent --output=json | jq '.items[].status | select(.phase=="Pending")')
		if [[ $pendingpods ]]; then 
			echo `date` - Most likely ran out of resources 
			sleep 30
		fi
	done
}


echo `date` - Started Jenkins auto scaler 
echo `date` - JENKINSNAMESPACE=$JENKINSNAMESPACE
echo `date` - JENKINSK8sRC=$JENKINSK8sRC
echo `date` - JENKINSEXTRABUILDERS=$JENKINSEXTRABUILDERS
echo `date` - JENKINSURL=$JENKINSURL
echo `date` - JENKINSMINNUMBUILDERS=$JENKINSMINNUMBUILDERS
echo `date` -----------------------------


while :
do
	sanity_check
	query_jenkins
	sleep 30
done
