#!/bin/bash

echo "*************************************************************"
echo "* The script uses tags/labels to list and delete resources. *"
echo "* Ensure operator yaml manifests have cosistent labels set. *"
echo "* Feel free to adapt the script to your needs.              *"
echo "************************************************************"

set +e

NAMESPACE=$1
OPERATOR_NAME=$2

function approve_installplan() {
    INSTALLPLAN_NAME=$1
    DESIRED_OPERATOR=$2
    DESIRED_CSV=$3

    ORIGIN_INSTALLPLAN=/tmp/originInstallplan.json
    OWNER_REF_TRIMMED=/tmp/ownerRefInstallPlan.json
    TRIMMED_INSTALLPLAN=/tmp/trimmedInstallPlan.json

    oc get installplan.operators.coreos.com/$INSTALLPLAN_NAME -ojson > ${ORIGIN_INSTALLPLAN}
    echo "Trimming down .metadata.ownerReferences[]"
    jq --arg OPERATOR_NAME ${DESIRED_OPERATOR} \
        'del(.metadata.ownerReferences[] | select(.name | index($OPERATOR_NAME) | not))' ${ORIGIN_INSTALLPLAN} > ${OWNER_REF_TRIMMED}

    echo "Trimming down .spec.clusterServiceVersionNames[]"
    jq --arg CSV_NAME ${DESIRED_CSV} \
        'del(.spec.clusterServiceVersionNames[] | select(. | index($CSV_NAME) | not))' ${OWNER_REF_TRIMMED} > ${TRIMMED_INSTALLPLAN}

    echo "Replacing InstallPlan by trimmed version"
    oc replace -f ${TRIMMED_INSTALLPLAN}

    oc patch installplan.operators.coreos.com $INSTALLPLAN_NAME --type=json -p='[{"op":"replace","path": "/spec/approved", "value": true}]'
}

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
for subscription in $(oc get subscription.operators.coreos.com -o name | grep -i $OPERATOR_NAME)
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

            approve_installplan $installplan $OPERATOR_NAME $desiredcsv

        else
            echo "Install Plan '$installplan' already approved"
        fi
    done
done

set -e
         