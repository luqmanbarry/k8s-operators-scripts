#!/bin/bash 

echo "*************************************************************"
echo "* The script uses tags/labels to list and delete resources. *"
echo "* Ensure operator yaml manifests have cosistent labels set. *"
echo "* Feel free to adapt the script to your needs.              *"
echo "************************************************************"

set +e

NAMESPACE=$1
OPERATOR_NAME=$2
STARTING_CSV=$3
CHART_NAMES=$4

echo "Installing Helm."
curl -L https://mirror.openshift.com/pub/openshift-v4/clients/helm/latest/helm-linux-amd64 -o /tmp/helm
chmod +x /tmp/helm
/tmp/helm version

function remove_finalizers(){
    NAME_KIND=$1
    sleep 10
    echo "Removing resources locked by finalizers if any: $NAME_KIND"
    oc patch $NAME_KIND --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' || true
    sleep 5
    oc patch $NAME_KIND --type json --patch='[ { "op": "remove", "path": "/status/finalizers" } ]' || true
    sleep 5
    oc patch $NAME_KIND --type json --patch='[ { "op": "remove", "path": "/spec/finalizers" } ]' || true
    sleep 5
}

if [ -z $NAMESPACE ] || [ -z $OPERATOR_NAME ];
then
    echo "Command Error: Namespace, Operator Reauired..."
    echo "Example: sh cleanup.sh my-namespace my-operator-name [\"my-chart1,my-chart2\"]"
    echo ""
    exit 1
elif [ "$NAMESPACE" = "-h" ];
then
    echo "Sample Call: sh cleanup.sh my-namespace my-operator-name [\"chart1,chart2\"]"
    echo ""
    exit 0
fi

echo "Working in Namespace: $NAMESPACE"
oc project $NAMESPACE

if [ -z $CHART_NAMES ];
then
    echo "No helm Charts provided."
else
    echo "Uninstalling helm Charts: $CHART_NAMES"
    for chart in $(echo $CHART_NAMES | tr ',' '  '); do echo "===> Uninstalling Chart: \"$chart\""; /tmp/helm uninstall $chart; done;
fi

sleep 10

echo "Deleting $STARTING_CSV  CSV..."
CSV_NAME=$(oc get csv -o name | grep $STARTING_CSV)
oc delete $CSV_NAME
remove_finalizers "$CSV_NAME"

echo "Deleting $OPERATOR_NAME operator Install Plans..."
for IP in $(oc get installplan.operators.coreos.com | grep $OPERATOR_NAME | cut -d' ' -f 1); 
do 
    echo "===> Deleting InstallPlan: \"$IP\""; 
    oc delete installplan.operators.coreos.com/$IP || true;
    remove_finalizers "installplan.operators.coreos.com/$IP"
done

echo "Deleting Helm Hooks Job..."
for JOB in $(oc get job -l operator=$OPERATOR_NAME | cut -d' ' -f 1); 
do 
    echo "===> Deleting Job: \"$JOB\"";
    oc delete job/$JOB || true; 
    remove_finalizers "job/$JOB"
done

echo "Deleting Helm Hooks CronJob..."
for JOB in $(oc get cronjob -l operator=$OPERATOR_NAME | cut -d' ' -f 1); 
do 
    echo "===> Deleting CronJob: \"$cronjob\""; 
    oc delete cronjob/$JOB || true;
    remove_finalizers "conjob/$JOB"
done

echo "Deleting Helm history Secrets..."
for SEC in $(oc get secret -l operator=$OPERATOR_NAME | cut -d' ' -f 1); 
do 
    echo "===> Deleting Secret: \"$SEC\""; 
    oc delete secret/$SEC || true; 
    remove_finalizers "secret/$SEC"
done

echo "Deletin ConfigMaps..."
for CM in $(oc get configmap | grep $OPERATOR_NAME | cut -d' ' -f 1); 
do 
    echo "===> Deleting Config: \"$CM\"";
    oc delete configmap/$CM || true; 
    remove_finalizers "configmap/$CM"
done

echo "Deletin Secrets..."
for SEC in $(oc get secret | grep $OPERATOR_NAME | cut -d' ' -f 1); 
do 
    echo "===> Deleting Secret: \"$SEC\""; 
    oc delete Secret/$SEC || true; 
    remove_finalizers "secret/$SEC"
done

oc delete all -l operator=$OPERATOR_NAME

sleep 10
set -e
