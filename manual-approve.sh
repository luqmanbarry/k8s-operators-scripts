#!/bin/bash

echo "*************************************************************"
echo "* The script uses tags/labels to list and delete resources. *"
echo "* Ensure operator yaml manifests have cosistent labels set. *"
echo "* Feel free to adapt the script to your needs.              *"
echo "************************************************************"

set +e

NAMESPACE=$1
OPERATOR_NAME=$2

if [ -z $NAMESPACE ];
then
    echo "Command Error: Namespace Reauired..."
    echo "Example: sh approve.sh my-namespace"
    echo ""
    exit 1
elif [ "$NAMESPACE" = "-h" ];
then
    echo "Sample Call: sh approve.sh my-namespace"
    echo ""
    exit 0
fi

echo "Working in Namespace: $NAMESPACE"
oc project $NAMESPACE

echo "Approving operator InstallPlans.  Waiting a few seconds to make sure the InstallPlan gets created first."
echo "Process about to sleep."
sleep 30

echo "Process about to resume."
for subscription in $(oc get subscription.operators.coreos.com -o name | grep $OPERATOR_NAME)
do 
    echo "Processing Subscription: \"$subscription\""
    desiredcsv=$(oc get $subscription -o jsonpath='{ .spec.startingCSV }')
    if [ -z "$desiredcsv" ];
    then
        desiredcsv=$(oc get $subscription -o jsonpath='{ .status.currentCSV }')
    fi
    echo "Desired CSV: \"$desiredcsv\""
    until [ "$(oc get installplan.operators.coreos.com --template="{{ range \$item := .items }}{{ range \$item.spec.clusterServiceVersionNames }}{{ if eq . \"$desiredcsv\"}}{{ printf \"%s\n\" \$item.metadata.name }}{{end}}{{end}}{{end}}")" != "" ]; do sleep 2; done
    installplans=$(oc get installplan.operators.coreos.com --template="{{ range \$item := .items }}{{ range \$item.spec.clusterServiceVersionNames }}{{ if eq . \"$desiredcsv\"}}{{ printf \"%s\n\" \$item.metadata.name }}{{end}}{{end}}{{end}}")
    for installplan in $installplans
    do
        echo "Procesing InstallPlan: \"$installplan\""
        if [ "`oc get installplan.operators.coreos.com $installplan -o jsonpath="{.spec.approved}"`" == "false" ]; then
        echo "Approving Subscription $subscription with install plan $installplan"
        oc patch installplan.operators.coreos.com $installplan --type=json -p='[{"op":"replace","path": "/spec/approved", "value": true}]'
        else
        echo "Install Plan '$installplan' already approved"
        fi
    done
done

set -e
         