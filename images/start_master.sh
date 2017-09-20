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

function generate_certs {
  clusterid=$1
  namespace=$2
  service_base=$3
  num_years=$4
  
  myip=$(getent hosts ${HOSTNAME} | awk '{print $1}')
  base="/etc/kubernetes/pki"
  mkdir -p ${base}
  cat > "${base}/openssl.cnf" <<EOM
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.${clusterid}.local
DNS.5 = ${clusterid}-master
DNS.6 = ${clusterid}-master.${namespace}
IP.1 = ${service_base}
IP.2 = ${myip}
EOM

  # generate cert auth
  openssl genrsa -out "${base}/ca.key" 2048
  openssl req -x509 -new -nodes -key "${base}/ca.key" -days $((num_years * 365)) -out "${base}/ca.crt" -subj "/CN=kubernetes"

  # generate apiserver cert
  openssl genrsa -out "${base}/apiserver.key" 2048
  openssl req -new -key "${base}/apiserver.key" -out "${base}/apiserver.csr" -subj "/CN=kube-apiserver" -config "${base}/openssl.cnf"
  openssl x509 -req -in "${base}/apiserver.csr" -CA "${base}/ca.crt" -CAkey "${base}/ca.key" -CAcreateserial -out "${base}/apiserver.crt" -days $((num_years * 365)) -extensions v3_req -extfile "${base}/openssl.cnf"

}

function start-master() {

  local kubeadm_token; kubeadm_token="$(cat /etc/kubernetes/clusterconfig/secret/token)"
  local cluster_id; cluster_id="$(cat /etc/kubernetes/clusterconfig/id/cluster-id)"
  local pod_cidr; pod_cidr="$(cat /etc/kubernetes/clusterconfig/pod_cidr_range/pod_cidr)"
  local namespace; namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)

  # We are generating these certs instead of letting kubeadm do it so that we can
  # add custom DNS SANs to the cert. This allows accessing the apiserver from 
  # namespaces outside the application namespace (namely the axuser namespace from which
  # test steps are executed)
  # the service base 10.96.0.1 is default for calico and the dns points to 10.96.0.10
  # generate certificate for 10 years. should be enough for a k8s cluster running inside
  # another k8s cluster :)
  generate_certs ${cluster_id} ${namespace} 10.96.0.1 10

  kubeadm init \
          --skip-preflight-checks \
          --token ${kubeadm_token} \
          --service-dns-domain "${cluster_id}.local" \
          --pod-network-cidr=${pod_cidr}

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
  update-conf "https://.*" "https://${cluster_id}-master.${namespace}:443" "${HOME}/.kube/admin-config"

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
  kubeadm join --skip-preflight-checks --token ${kubeadm_token} "${cluster_id}-master:443"
 
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
