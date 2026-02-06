CLUSTER_CIDR=172.16.0.0/13
SERVICE_CIDR=172.24.0.0/13
PODMASK=20
MAXPODS=1600

INSTALL_K3S_VERSION=v1.34.2+k3s1
RANCHER_HOSTNAME='rancher.v2.miom.am'
LETSENCRYPT_EMAIL='letsencrypt@v2.miom.am'


sudo apt-get install curl
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 22/tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable


sudo ufw allow from ${CLUSTER_CIDR} to any
sudo ufw allow from ${SERVICE_CIDR} to any
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${INSTALL_K3S_VERSION} sh -s - server \
                                --cluster-cidr=${CLUSTER_CIDR} \
                                --service-cidr=${SERVICE_CIDR} \
                                --flannel-backend=none \
                                --disable-network-policy \
                                --kube-controller-manager-arg=node-cidr-mask-size-ipv4=${PODMASK} \
                                --kubelet-arg=max-pods=${MAXPODS}
export KUBECONFIG='/etc/rancher/k3s/k3s.yaml'

CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}


cilium install --version 1.18.6 --set=ipam.operator.clusterPoolIPv4PodCIDRList=${CLUSTER_CIDR} --set=ipam.operator.clusterPoolIPv4MaskSize=${PODMASK}
cilium status --wait

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod +x get_helm.sh
./get_helm.sh

export KUBECONFIG='/etc/rancher/k3s/k3s.yaml'
kubectl create namespace cert-manager || true  # Ignore if namespace already exists
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager --namespace cert-manager --set crds.enabled=true

helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
kubectl create namespace cattle-system || true  # Ignore if namespace already exists
helm install rancher rancher-stable/rancher \
   --namespace cattle-system  \
   --set hostname=${RANCHER_HOSTNAME} \
   --set ingress.tls.source=letsEncrypt \
   --set letsEncrypt.email=${LETSENCRYPT_EMAIL} \
   --set letsEncrypt.ingress.class=traefik \
   --set replicas="3"

kubectl patch svc traefik -n kube-system --type='json' -p='[{"op": "replace", "path": "/spec/externalTrafficPolicy", "value":"Local"}]'


echo -e "fs.inotify.max_user_watches = 524288\nfs.inotify.max_user_instances = 1024" | sudo tee -a /etc/sysctl.conf

reboot