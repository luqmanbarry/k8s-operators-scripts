pipeline {
    agent {
        node {
            label 'agent-node'
        }
    }

    parameters {
        string(name: 'OCPCredentialsId', defaultValue: 'ocp-sa-token', description: 'Token used by the OpenShift CLI to authenticate.', trim: true)
        choice(name: 'Action', choices: ['PATCH_CR', 'INSTALL_OPERATOR', 'UNINSTALL_OPERATOR', 'APPROVE_INSTALLPLAN', 'ALL'], description: 'List of actions to take. \nPATCH_CR: Choose this option for simply patching the Operator custom resources.\nINSTALL_OPERATOR: Choose this option for first time installation.\nUNINSTALL_OPERATOR: Choose this option for removing the operator and all its child resources; you need cluster-admin to delete the CRDs.\nAPPROVE_INSTALLPLAN: Choose this option to approve an InstallPlan; ensure the installPlan exist in the cluster prior.\n"ALL": Chose this option to execute all the stages in the Pipeline.')
        string(name: 'TargetNamespace', defaultValue: 'my-namespace', description: 'The target namespace to deploy the monitoring resources.', trim: true)
        string(name: 'OperatorName', defaultValue: 'amq-broker-rhel8', description: 'The operator name according to docs.', trim: true)
        string(name: 'StartingCSV', defaultValue: 'amq-broker-operator.v7.10', description: 'The operator version or startingCSV.', trim: true)
        string(name: 'OperatorChartName', defaultValue: 'amq7-operator', description: 'The chart name of the Operator.', trim: true)
        string(name: 'CRsChartName', defaultValue: 'amq7-broker', description: 'The chart name of the Sync resources.', trim: true)
        string(name: 'OperatorValuesFile', defaultValue: 'operator-resources/values.yaml', description: 'The vavlues file to use. Specify values in a YAML file or a URL (can specify multiple)', trim: true)
        string(name: 'CRsValuesFile', defaultValue: 'custom-resources/values.yaml', description: 'The vavlues file to use. Specify values in a YAML file or a URL (can specify multiple)', trim: true)
    }

    options {
        timeout(time: 30, unit: 'MINUTES') 
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '20', daysToKeepStr: '30'))
        disableConcurrentBuilds()
        disableResume()
    }

    environment { 
        OCP_LOGIN                         = credentials("${params.OCPCredentialsId}")
        ACTION_TO_TAKE                    = "${params.Action}"
        NAMESPACE                         = "${params.TargetNamespace}"
        OPERATOR_NAME                     = "${params.OperatorName}"
        STARTING_CSV                      = "${params.StartingCSV}"
        OPERATOR_CHART_NAME               = "${params.OperatorChartName}"
        CR_CHART_NAME                     = "${params.CRsChartName}"
        CHART_NAMES                       = "${OPERATOR_CHART_NAME},${CR_CHART_NAME}"
        OPERATOR_VALUES_FILE              = "${params.OperatorValuesFile}"
        CR_VALUES_FILE                    = "${params.CRsValuesFile}"
    }

    stages {
        stage("Verify Tools") {
            steps {
                sh ' echo "  Verying required tools are installed  " '
                sh '  echo "Verify HELM is installed." '
                sh '''
                    if ! helm version | grep 'v3'
                    then
                        echo "Helm v3.x could not be found."
                        exit -1
                    fi
                '''
                sh ' echo "  Verify OpenShift cli is installed.    " '
                sh '''
                    if ! oc version | grep 'Client Version: 4'
                    then
                        echo "oc cli v4.x could not be found."
                        exit -1
                    fi
                '''
            }
        }
        stage("OCP Login") {
            steps {
                retry(3) {
                    sh ' echo "    Installing the helm chart...        " '
                    sh ' oc login "${OCP_LOGIN_USR}" --token "${OCP_LOGIN_PSW}" '
                    sh ' oc project ${NAMESPACE} '
                }
            }
        }
        stage("Cleanup Operator Env") {
            when {
                anyOf {
                    environment name: 'Action', value: 'UNINSTALL_OPERATOR'
                    environment name: 'Action', value: 'ALL'
                }
            }
            steps {
                sh '''
                    echo "Clean up operator and related resources."
                    echo "Uninstalling AMQ specific helm chart..."
                    # This is AMQ specific
                    sh operator-scripts/cleanup.sh $NAMESPACE $OPERATOR_NAME $STARTING_CSV "$CHART_NAMES"
                    sleep 15
                '''
            }
        }
        stage("Install Operator") {
            when {
                anyOf {
                    environment name: 'Action', value: 'INSTALL_OPERATOR'
                    environment name: 'Action', value: 'ALL'
                }
            }
            steps {
                retry(3) {
                    sh '''
                        oc delete subscription.operators.coreos.com --all
                        oc delete InstallPlan --all
                        
                        helm upgrade --install ${OPERATOR_CHART_NAME} ./operator-resources \
                            --set chart.names="${OPERATOR_CHART_NAME}\\,${CR_CHART_NAME}" \
                            -f ${OPERATOR_VALUES_FILE} \
                            -n ${NAMESPACE}
                        sleep 20
                    '''
                }
            }
        }
        stage("Approve InstallPlan"){
            when {
                anyOf {
                    environment name: 'Action', value: 'APPROVE_INSTALLPLAN'
                    environment name: 'Action', value: 'INSTALL_OPERATOR'
                    environment name: 'Action', value: 'ALL'
                }
            }
            steps {
                retry(3){
                    sh '''
                        echo "Approve operator InstallPlan."
                        sh operator-scripts/approve.sh $NAMESPACE $OPERATOR_NAME
                        sleep 30             
                    '''
                }
            }
        }
        stage("Patch Custom Resources"){
            when {
                anyOf {
                    environment name: 'Action', value: 'PATCH_CR'
                    environment name: 'Action', value: 'ALL'
                }
            }
            steps {
                retry(3) {
                    sh '''
                        helm uninstall ${CR_CHART_NAME} -n $NAMESPACE || true
                        echo "Deleting Helm history Secrets..."
                        for SEC in $(oc get secret -l helm.sh/chart=${CR_CHART_NAME} | cut -d' ' -f 1); 
                        do 
                            echo "===> Deleting Secret: \"$SEC\""; 
                            oc delete secret/$SEC || true; 
                        done
                        sleep 15
                        set +o xtrace
                        helm upgrade --install ${CR_CHART_NAME} ./custom-resources \
                            -f ${CR_VALUES_FILE} \
                            -n ${NAMESPACE}
                        set -o xtrace
                        sleep 60
                    '''
                }
            }
        }
        stage("Verify Installation") {
            when {
                anyOf {
                    environment name: 'Action', value: 'PATCH_CR'
                    environment name: 'Action', value: 'ALL'
                }
            }
            steps {
                retry(3) {
                    sh 'echo "Post installation validation..."'
                    sleep 60
                    sh '''
                        # Operator Chart
                        if ! helm history ${OPERATOR_CHART_NAME}
                        then
                            echo "Chart installation failed."
                            exit -1
                        fi
                        if [ "$(oc get po -n ${NAMESPACE} | grep Running | wc -l)" -gt "0" ];
                        then
                            echo "$$$$> Operator resources installation successful."
                        else
                            echo "&&&&> Required Operator Pods are down. Troubleshoot using the CLI and Web Console"
                            exit -1
                        fi

                        # Secret Sync Chart
                        if ! helm history ${CR_CHART_NAME}
                        then
                            echo "Chart installation failed."
                            exit -1
                        fi
                        if [ "$(oc get po -n ${NAMESPACE} | grep Running | wc -l)" -gt "0" ];
                        then
                            echo "$$$$> CRs resources installation successful."
                        else
                            echo "&&&&> Required CRs Pods are down. Troubleshoot using the CLI and Web Console"
                            exit -1
                        fi
                    '''
                    sh 'echo "====> BEGIN: Listing Installed Resources "'
                    sh 'oc get subscription,ActiveMQArtemis,ActiveMQArtemisAddress,ActiveMQArtemisScaledown,ActiveMQArtemisSecurity,all'
                    sh 'echo "====> END: Listing Installed resources "'
                }
            }
        }
    }
    post {
        always {
            echo "Terminating OCP user session..."
            sh 'oc logout &> /dev/null'
            deleteDir()
        }
    }
}