#!/bin/bash
set -e 

JENKINSNAMESPACE=${JENKINSNAMESPACE:-jenkins}
JENKINSK8sRC=${JENKINSK8sRC:-jenkins-builder}

function scale_down {
	echo `date` - Scaling up Jenkins Builders from $JENKINS_BUILDERSCOUNT to $JENKINS_SCALEDOWNCOUNT ...
	kubectl --namespace=$JENKINSNAMESPACE delete rc $JENKINSK8sRC

}

function scale_up {
	echo `date` - Scaling up Jenkins Builders to $JENKINS_SCALEUPCOUNT ...
	kubectl --namespace=$JENKINSNAMESPACE --replicas=$JENKINS_SCALEUPCOUNT rc/$JENKINSK8sRC
}

