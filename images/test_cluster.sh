#!/bin/bash

function kube_cmd() {
    kubectl --kubeconfig=/root/.kube/admin.config --namespace=default $@
}

#
# This function returns the IP of the master in the 
# 
function get_master_ip() {
    master_ip=$(kubectl get pods -l deployment=master --namespace=${APPNAME} -o json | jq .items[0].status.podIP | tr -d '"')
    echo ${master_ip}
}

function test_deployment() {
    kube_cmd create -f /root/test_deployment.yaml
    
    counter=0
    fail=1
    while [[ "$counter" -lt 10 ]]; do
        eip=$(kube_cmd get ep nginx -o json | jq '.subsets[0].addresses[0].ip')
        echo "ENDPOINT IP $eip"
        if [[ "$eip" == "null" ]]; then
            echo "Waiting 60seconds for endpoint to show up"
            sleep 60
            counter=$((counter+1))
            continue
        fi

        nodeport=$(kube_cmd get services nginx -o json | jq '.spec.ports[0].nodePort')
        echo "NODEPORT $nodeport"
        if [[ "$nodeport" == "null" ]]; then
            echo "Waiting 60 seconds for nodeport to show up"
            sleep 60
            counter=$((counter+1))
            continue
        fi

        server="$(get_master_ip):${nodeport}"
        code=$(curl -s -o /dev/null -w "%{http_code}" ${server})
        echo "Response from $server is $code"
        if [[ "$code" -ne 200 ]]; then
            echo "Waiting 60 seconds before retry"
            sleep 60
            counter=$((counter+1))
            continue
        fi
        fail=0
        break
    done

    kube_cmd delete -f /root/test_deployment.yaml
    if [[ "$fail" -ne 0 ]]; then
        echo "Failed test"
        exit 1
    fi
}

test_deployment
