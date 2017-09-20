#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

TIMEOUT_MINUTES="${TIMEOUT_MINUTES:-10}"

function kube-main() {
  local token; token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  local namespace; namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
  local server; server="https://kubernetes.default"
  kubectl --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
      --token=${token} --namespace=${namespace} --server=${server} $@
}

function extract_secret() {
  namespace=$1
  secretname=$2

  kubectl get secret --namespace=${namespace} ${secretname} -o json | \
      jq '.["data"]["admin-config"]' | tr -d '"' | base64 -d > /tmp/admin.config
}

function wait_for_secret() {
    namespace=$1
    secretname=$2
    
    counter=0
    while [[ "${counter}" -lt "${TIMEOUT_MINUTES}" ]]; do
        found=$(kubectl get secret --namespace=${namespace} ${secretname} --ignore-not-found --no-headers | wc -l)
        if [[ "${found}" -eq "1" ]]; then
            echo 0
            return
        fi
        >&2 echo "Did not find secret ${secretname} in namespace ${namespace} in ${counter} minutes..."
        counter="$((counter+1))"
        sleep 60
     done
     echo 1
}

err=$(wait_for_secret ${APPNAME} "${CLUSTERID}-admin-conf")
if [[ "${err}" -eq "0" ]]; then
    extract_secret ${APPNAME} "${CLUSTERID}-admin-conf"
else
    echo Did not find secret in ${TIMEOUT_MINUTES} minutes
    exit 1
fi
