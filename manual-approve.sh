#!/bin/bash

echo "*************************************************************"
echo "* The script uses tags/labels to list and delete resources. *"
echo "* Ensure operator yaml manifests have cosistent labels set. *"
echo "* Feel free to adapt the script to your needs.              *"
echo "*************************************************************"

approve_installplan () {
    INSTALLPLAN_NAME=$1
    DESIRED_OPERATOR=$2
    DESIRED_CSV=$3

    ORIGIN_INSTALLPLAN=/tmp/originInstallplan.json
    OWNER_REF_TRIMMED=/tmp/ownerRefInstallPlan.json
    TRIMMED_INSTALLPLAN=/tmp/trimmedInstallPlan.json
    DESIRED_CSV_OUTPUT=/tmp/desiredCSVOutput.json


    oc get installplan.operators.coreos.com/$INSTALLPLAN_NAME -ojson > ${ORIGIN_INSTALLPLAN}
    echo "Trimming down .metadata.ownerReferences[]"
    jq --arg OPERATOR_NAME ${DESIRED_OPERATOR} \
        'del(.metadata.ownerReferences[] | select(.name | index($OPERATOR_NAME) | not))' ${ORIGIN_INSTALLPLAN} > ${OWNER_REF_TRIMMED}

    echo "Trimming down .spec.clusterServiceVersionNames[]"
    jq --arg CSV_NAME ${DESIRED_CSV} \
        'del(.spec.clusterServiceVersionNames[] | select(. | index($CSV_NAME) | not))' ${OWNER_REF_TRIMMED} > ${TRIMMED_INSTALLPLAN}

    echo "Replacing InstallPlan by trimmed version"
    oc apply -f ${TRIMMED_INSTALLPLAN}

    if [ $? != 0 ];
    then
        echo "##### Failed to patch installplan: $INSTALLPLAN_NAME"
        exit 1
    fi

    oc patch installplan.operators.coreos.com $INSTALLPLAN_NAME --type=json -p='[{"op":"replace","path": "/spec/approved", "value": true}]'
    
    START_TIME=$(date +%s)
    MAX_WAIT_SECS=300
    while [ true ];
    do
        sleep 15
        OPERATOR_INSTALLED="$( oc get clusterserviceversion.operators.coreos.com/$DESIRED_CSV -ojson | jq '.status.phase' | xargs )"
        echo "Awaiting Operator Installation to succeed..."
        echo "CSV PHASE: $OPERATOR_INSTALLED"
        if [ $OPERATOR_INSTALLED = "Succeeded" ];
        then
            echo ">>> Operator installation successful. >>>"
            oc delete installplan.operators.coreos.com $INSTALLPLAN_NAME
            break;
        elif [ $OPERATOR_INSTALLED = "Installing" ] || [ $OPERATOR_INSTALLED = "InstallReady" ];
        then
            echo ">>> Operator installation 'in progress'.>>>"
        elif [ $OPERATOR_INSTALLED = "Pending" ];
        then
            echo ">>> Operator installation 'Pending'.>>>"
            sleep 15
            TIME_ELAPSED=$($(date +%s)-$START_TIME)
            if [ $TIME_ELAPSED >= $MAX_WAIT_SECS ];
            then
                echo ">>> Operator stuck in 'Pending' for the last $MAX_WAIT_SECS seconds. May be failing to install.>>>"
                exit 1
            fi
        else
            echo ">>> Operator installation failed. >>>"
            exit 1
        fi
    done

    rm -v ${ORIGIN_INSTALLPLAN}
    rm -v ${OWNER_REF_TRIMMED}
    rm -v ${TRIMMED_INSTALLPLAN}
}

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
        IP_APPROVED="$(oc get installplan.operators.coreos.com $installplan -o jsonpath='{.spec.approved}')"
        echo "Install Plan Approve? $IP_APPROVED"
        
        if [ !$IP_APPROVED  ]; then
            echo "Approving Subscription $subscription with install plan $installplan"

            approve_installplan $installplan $OPERATOR_NAME $desiredcsv

        else
            echo "Install Plan '$installplan' already approved"
        fi
    done
done

set -e