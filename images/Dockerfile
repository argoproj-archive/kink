FROM ubuntu:xenial

LABEL maintainer="abhinav@applatix.com"
 
# Install Docker
RUN apt-get update  && \
    apt-get install -y \
        apt-transport-https ca-certificates curl wget vim supervisor software-properties-common jq && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \
    add-apt-repository \
            "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
            $(lsb_release -cs) \
            stable" && \
    apt-get update  && \
    apt-get install -y docker-ce
    
RUN mkdir -p /var/log/supervisor && \ 
    mkdir -p /var/log/docker

RUN wget https://dl.k8s.io/v1.7.6/kubernetes-server-linux-amd64.tar.gz && \
    tar -xvzf kubernetes-server-linux-amd64.tar.gz && \
    cp kubernetes/server/bin/kubelet /usr/local/bin && \
    cp kubernetes/server/bin/kubeadm /usr/local/bin && \
    cp kubernetes/server/bin/kube-proxy /usr/local/bin && \
    cp kubernetes/server/bin/kubectl /usr/local/bin && \
    rm -rf kubernetes && \
    rm kubernetes-server-linux-amd64.tar.gz

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY start_master.sh /usr/local/bin
COPY readiness.sh /usr/local/bin

# Start supervisord when running the container
CMD /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
