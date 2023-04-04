# OpenShift/Kubernetes Operators Scripts

Examples of how to run the scripts. They make certain assumptions; I suggest you read the scripts to understand them, ensure they are met when installing the Operator. Helm is one recommended approach to packaging Operators and their custom resources (CRs) templates.

## Approve Operator InstallPlan

```sh
# Set Environment Variables
NAMESPACE=my-namespace
OPERATOR_NAME=amq-operator-rhel8

# Run Script
sh manual-approve.sh $NAMESPACE $OPERATOR_NAME
```

## Uninstall Operator

```sh
# Set Environment Variables
NAMESPACE=my-namespace
OPERATOR_NAME=amq-operator-rhel8
STARTING_CSV=amq-broker-operator.v7.10
CHART_NAMES="amq-operator,amq-broker"

# Run Script
sh cleanup.sh $NAMESPACE $OPERATOR_NAME $STARTING_CSV "$CHART_NAMES"
```
