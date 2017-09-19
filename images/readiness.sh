#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

num=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes \
    -l node-role.kubernetes.io/master= --no-headers \
    | grep Ready | wc -l)

echo $num

if [[ ${num} -ge 1 ]]; then
    exit 0
else
    exit 1
fi
