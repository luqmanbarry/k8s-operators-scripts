#!/bin/bash

# You need cluster-admin privileges
SA_SECRET=`oc get secret -n openshift-user-workload-monitoring | grep  prometheus-user-workload-token | head -n 1 | awk '{print $1 }'`

SA_TOKEN=`echo $(oc get secret $SECRET -n openshift-user-workload-monitoring -o json | jq -r '.data.token') | base64 -d`

THANOS_QUERIER_HOST='https://thanos-querier-openshift-monitoring.<your-domain>.com'

NAMESPACE=".*"

curl -X GET -kG "$THANOS_QUERIER_HOST/api/v1/query?" --data-urlencode "query=up{namespace=~'$NAMESPACE'}" -H "Authorization: Bearer $SA_TOKEN"