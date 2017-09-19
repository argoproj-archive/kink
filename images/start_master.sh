#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

function fix-kube-proxy() {
  config=$1
  kubectl --kubeconfig=${config} --namespace=kube-system get ds kube-proxy -o json \
      | jq '.spec.template.spec.containers[0].command |= .+ ["--masquerade-all", "--conntrack-max=0", "--conntrack-max-per-core=0"]' \
      | kubectl --kubeconfig=${config} --namespace=kube-system apply --force -f -
  kubectl --kubeconfig=${config} --namespace=kube-system delete pod -l k8s-app=kube-proxy
}

function kube-main() {
  local token; token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  local namespace; namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
  local server; server="https://kubernetes.default"
  kubectl --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
      --token=${token} --namespace=${namespace} --server=${server} $@
}

function update-conf {
  search=$(echo $1 | sed 's./.\\/.g')
  replace=$(echo $2 | sed 's./.\\/.g')
  file=$3
  sed -i 's/'${search}'/'${replace}'/' ${file}
}

function start-master() {

  local kubeadm_token; kubeadm_token="$(cat /etc/kubernetes/clusterconfig/secret/token)"
  local cluster_id; cluster_id="$(cat /etc/kubernetes/clusterconfig/id/cluster-id)"
  local pod_cidr; pod_cidr="$(cat /etc/kubernetes/clusterconfig/pod_cidr_range/pod_cidr)"

  kubeadm init \
          --skip-preflight-checks \
          --token ${kubeadm_token} \
          --service-dns-domain "${cluster_id}.local" \
          --pod-network-cidr=${pod_cidr} \
          --apiserver-advertise-address kubernetes:443

  local config="/etc/kubernetes/admin.conf"

  # kube-proxy daemonset needs some fixup
  fix-kube-proxy ${config}

  # Configure networking
  wget http://docs.projectcalico.org/v2.4/getting-started/kubernetes/installation/hosted/kubeadm/1.6/calico.yaml
  
  # change the range in the pod ip to match that being passed above
  local pod_cidr_slash; pod_cidr_slash="$(echo ${pod_cidr} | sed 's./.\\/.g')"
  sed -i 's/192.168.0.0\/16/'${pod_cidr_slash}'/' calico.yaml
  kubectl --kubeconfig="${config}" apply -f calico.yaml

  # for some reason, the kube-dns initially has trouble communicating with api server with 10.96.0.1 ip
  # and whats even more strange is that if we delete the kube-dns pod then it works when it restarts
  sleep 30
  kubectl --kubeconfig="${config}" --namespace=kube-system delete pod -l k8s-app=kube-dns

  # copy config for easy kubectl commands
  mkdir -p ${HOME}/.kube
  cp ${config} ${HOME}/.kube/admin-config
  update-conf "https://.*" "https://${cluster_id}-master:443" "${HOME}/.kube/admin-config"

  # finally save the kube configuration to a secret so that it can be read by slaves
  kube-main delete secret "${cluster_id}-admin-conf" --ignore-not-found
  kube-main create secret generic "${cluster_id}-admin-conf" --from-file="${HOME}/.kube/admin-config"

  # just dump out everything now
  sleep 30
  kubectl --kubeconfig="${config}" get pods --all-namespaces -o wide

}

function start-minion() {
  local kubeadm_token; kubeadm_token="$(cat /etc/kubernetes/clusterconfig/secret/token)"
  local cluster_id; cluster_id="$(cat /etc/kubernetes/clusterconfig/id/cluster-id)"
  kubeadm join --skip-preflight-checks --token ${kubeadm_token} kubernetes:443
 
  # change the config so that it is not using pod ip
  update-conf "https://.*" "https://${cluster_id}-master:443" /etc/kubernetes/kubelet.conf

  # once kubeadm is done we need to restart kubelet for node to join master
  pkill -9 kubelet
}

if [[ -f "/etc/kubernetes/clusterconfig/mode/is-master" ]]; then
  start-master
else
  start-minion
fi
