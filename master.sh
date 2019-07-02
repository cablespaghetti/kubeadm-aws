#!/bin/bash -ve

# Disable pointless daemons
systemctl stop snapd snapd.socket lxcfs snap.amazon-ssm-agent.amazon-ssm-agent
systemctl disable snapd snapd.socket lxcfs snap.amazon-ssm-agent.amazon-ssm-agent

# Disable swap to make K8S happy
swapoff -a
sed -i '/swap/d' /etc/fstab

# Install K8S, kubeadm and Docker
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y kubelet=${k8sversion}-00 kubeadm=${k8sversion}-00 kubectl=${k8sversion}-00 awscli jq docker.io
apt-mark hold kubelet kubeadm kubectl docker.io

# Install etcdctl for the version of etcd we're running
ETCD_VERSION=$(kubeadm config images list | grep etcd | cut -d':' -f2)
wget "https://github.com/coreos/etcd/releases/download/v$${ETCD_VERSION}/etcd-v$${ETCD_VERSION}-linux-amd64.tar.gz"
tar xvf "etcd-v$${ETCD_VERSION}-linux-amd64.tar.gz"
mv "etcd-v$${ETCD_VERSION}-linux-amd64/etcdctl" /usr/local/bin/
rm -rf etcd*

# Point Docker at big ephemeral drive and turn on log rotation
systemctl stop docker
mkdir /mnt/docker
chmod 711 /mnt/docker
cat <<EOF > /etc/docker/daemon.json
{
    "data-root": "/mnt/docker",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "5"
    }
}
EOF
systemctl start docker
systemctl enable docker

# Set default AWS region
REGION=$(ec2metadata --availability-zone | rev | cut -c 2- | rev)
export AWS_DEFAULT_REGION=$REGION
echo "AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION" >> /etc/environment

# Work around the fact spot requests can't tag their instances
INSTANCE_ID=$(ec2metadata --instance-id)
aws ec2 create-tags --resources $INSTANCE_ID --tags "Key=Name,Value=${clustername}-master" "Key=Environment,Value=${clustername}" "Key=kubernetes.io/cluster/${clustername},Value=owned"

# Point kubelet at big ephemeral drive
mkdir /mnt/kubelet
echo 'KUBELET_EXTRA_ARGS="--root-dir=/mnt/kubelet --cloud-provider=aws"' > /etc/default/kubelet

cat >init-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1alpha3
kind: InitConfiguration
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: "${k8stoken}"
  ttl: "0"
nodeRegistration:
  name: "$(hostname -f)"
  taints: []
---
apiVersion: kubeadm.k8s.io/v1alpha3
kind: ClusterConfiguration
apiServerExtraArgs:
  cloud-provider: aws
controllerManagerExtraArgs:
  cloud-provider: aws
networking:
  podSubnet: 10.244.0.0/16
EOF

echo "Checking s3://${s3bucket}/etcd-snapshot.db.xz"
aws s3 cp s3://${s3bucket}/etcd-snapshot.db.xz etcd-snapshot.db.xz || echo "Snapshot not found."

if [ -f etcd-snapshot.db.xz ]; then
  echo "Found etcd snapshot"
  unxz etcd-snapshot.db.xz

  echo "Restoring etcd snapshot"
  ETCDCTL_API=3 etcdctl snapshot restore etcd-snapshot.db --data-dir /var/lib/etcd

  echo "Downloading Kubernetes pki data"
  aws s3 cp s3://${s3bucket}/pki.tar.xz - | tar xJv -C /etc/kubernetes/

  echo "Running kubeadm init"
  kubeadm init --ignore-preflight-errors="DirAvailable--var-lib-etcd,NumCPU" --config=init-config.yaml
else
  echo "Running kubeadm init"
  kubeadm init --config=init-config.yaml --ignore-preflight-errors=NumCPU
  touch /tmp/fresh-cluster

  if [[ "${backupenabled}" == "1" ]]; then
    echo "Backing up Kubernetes pki data"
    tar cJv -C /etc/kubernetes/ pki | aws s3 cp --metadata instanceid=$INSTANCE_ID - s3://${s3bucket}/pki.tar.xz
  fi
fi

# Pass bridged IPv4 traffic to iptables chains (required by Flannel like the above cidr setting)
echo "net.bridge.bridge-nf-call-iptables = 1" > /etc/sysctl.d/60-flannel.conf
service procps start

# Set up kubectl for the ubuntu user
mkdir -p /home/ubuntu/.kube && cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config && chown -R ubuntu. /home/ubuntu/.kube
echo 'source <(kubectl completion bash)' >> /home/ubuntu/.bashrc

# Install helm
wget https://storage.googleapis.com/kubernetes-helm/helm-v2.12.0-linux-amd64.tar.gz
tar xvf helm-v2.12.0-linux-amd64.tar.gz
mv linux-amd64/helm /usr/local/bin/
rm -rf linux-amd64 helm-*

if [ -f /tmp/fresh-cluster ]; then
  su -c 'kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/13a990bb716c82a118b8e825b78189dcfbfb2f1e/Documentation/kube-flannel.yml' ubuntu

  # Set up helm
  su -c 'kubectl create serviceaccount tiller --namespace=kube-system' ubuntu
  su -c 'kubectl create clusterrolebinding tiller-admin --serviceaccount=kube-system:tiller --clusterrole=cluster-admin' ubuntu
  su -c 'helm init --service-account=tiller' ubuntu

  # Install cert-manager
  if [[ "${certmanagerenabled}" == "1" ]]; then
    sleep 60 # Give Tiller a minute to start up
    su -c 'helm install --name cert-manager --namespace cert-manager --version 0.5.2 stable/cert-manager --set createCustomResource=false && helm upgrade --install --namespace cert-manager --version 0.5.2 cert-manager stable/cert-manager --set createCustomResource=true' ubuntu
  fi

  # Install all the YAML we've put on S3
  mkdir /tmp/manifests
  aws s3 sync s3://${s3bucket}/manifests/ /tmp/manifests
  su -c 'kubectl apply -f /tmp/manifests/' ubuntu
fi

# Set up backups if they have been enabled
# This section is indented with tabs to make the EOF heredocs work
if [[ "${backupenabled}" == "1" ]]; then
	# Back up etcd to s3 every 15 minutes. A lifecycle rule will delete previous versions after 7 days.
	cat <<-EOF > /usr/local/bin/backup-etcd.sh
	#!/bin/bash
	ETCDCTL_API=3 /usr/local/bin/etcdctl --cacert='/etc/kubernetes/pki/etcd/ca.crt' --cert='/etc/kubernetes/pki/etcd/peer.crt' --key='/etc/kubernetes/pki/etcd/peer.key' snapshot save etcd-snapshot.db
	xz -f -9 etcd-snapshot.db
	aws s3 cp --metadata instanceid=$INSTANCE_ID etcd-snapshot.db.xz s3://${s3bucket}/etcd-snapshot.db.xz
	EOF

	echo "${backupcron} root bash /usr/local/bin/backup-etcd.sh" > /etc/cron.d/backup-etcd

	# Poll the spot instance termination URL and backup immediately if it returns a 200 response.
	cat <<-'EOF' > /usr/local/bin/check-termination.sh
	#!/bin/bash
	# Mostly borrowed from https://github.com/kube-aws/kube-spot-termination-notice-handler/blob/master/entrypoint.sh

	POLL_INTERVAL=10
	NOTICE_URL="http://169.254.169.254/latest/meta-data/spot/termination-time"

	echo "Polling $${NOTICE_URL} every $${POLL_INTERVAL} second(s)"

	# To whom it may concern: http://superuser.com/questions/590099/can-i-make-curl-fail-with-an-exitcode-different-than-0-if-the-http-status-code-i
	while http_status=$(curl -o /dev/null -w '%{http_code}' -sL $${NOTICE_URL}); [ $${http_status} -ne 200 ]; do
	  echo "Polled termination notice URL. HTTP Status was $${http_status}."
	  sleep $${POLL_INTERVAL}
	done

	echo "Polled termination notice URL. HTTP Status was $${http_status}. Triggering backup."
	/bin/bash /usr/local/bin/backup-etcd.sh
	sleep 300 # Sleep for 5 minutes, by which time the machine will have terminated.
	EOF

	cat <<-'EOF' > /etc/systemd/system/check-termination.service
	[Unit]
	Description=Spot Termination Checker
	After=network.target
	[Service]
	Type=simple
	Restart=always
	RestartSec=10
	User=root
	ExecStart=/bin/bash /usr/local/bin/check-termination.sh

	[Install]
	WantedBy=multi-user.target
	EOF

	systemctl start check-termination
	systemctl enable check-termination
fi
