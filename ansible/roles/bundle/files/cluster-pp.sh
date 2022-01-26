#!/usr/bin/env bash

CLUSTER_SUFFIX=SBX
readonly CLUSTER_NAME=cluster-${CLUSTER_SUFFIX,,}

# ON PREM CONFIGS

###################################
#### SET ENVIRONMENT VARIABLES ####
###################################

readonly CONTROL_PLANE_1_ADDRESS="192.168.1.151"
readonly CONTROL_PLANE_2_ADDRESS="192.168.1.152"
readonly CONTROL_PLANE_3_ADDRESS="192.168.1.153"
readonly WORKER_1_ADDRESS="192.168.1.154"
readonly WORKER_2_ADDRESS="192.168.1.155"
readonly WORKER_3_ADDRESS="192.168.1.156"
readonly WORKER_4_ADDRESS="192.168.1.157"
readonly SSH_USER="${USER}"
readonly SSH_PRIVATE_KEY_SECRET_NAME="${CLUSTER_NAME}-ssh-key"
readonly SSH_PRIVATE_KEY="./id_rsa"
readonly SECRET_USER_OVERRIDES=${CLUSTER_NAME}-user-overrides
readonly SSH_PORT=22
readonly CONTROL_PLANE_NAME=${CLUSTER_NAME}-control-plane
readonly WORKER_NAME=${CLUSTER_NAME}-md-0
readonly CONTROL_PLANE_VIP=192.168.1.160
readonly CONTROL_PLANE_VIP_PORT=6443
readonly CONTROL_PLANE_VIP_INTERFACE=eth0
readonly DOCKER_REGISTRY_ADDRESS=http://$(hostname -I | awk '{print $1}'):5000
readonly LOAD_BALANCER_IP_RANGE="10.0.50.20-10.0.50.25"


##################################
#### CREATE BOOTSTRAP CLUSTER ####
##################################

./dkp create bootstrap --with-aws-bootstrap-credentials=false


#########################################
#### CREATE SSH AND OVERRIDE SECRETS ####
#########################################

# CREATE SSH SECRET FROM EXISTING KEY
kubectl create secret generic ${SSH_PRIVATE_KEY_SECRET_NAME} --from-file=ssh-privatekey=${SSH_PRIVATE_KEY}

kubectl label secret ${SSH_PRIVATE_KEY_SECRET_NAME} clusterctl.cluster.x-k8s.io/move=

# CREATE OVERRIDES SECRET

cat << EOF | kubectl create secret generic ${SECRET_USER_OVERRIDES} --from-file=overrides.yaml=/dev/stdin
image_registries_with_auth:
- host: ${DOCKER_REGISTRY_ADDRESS}
  username: ""
  password: ""
  auth: ""
  identityToken: ""
download_images: false
EOF

kubectl label secret ${SECRET_USER_OVERRIDES} clusterctl.cluster.x-k8s.io/move=


########################################################
#### CREATE AND APPLY PREPROVISIONED INVENTORY FILE ####
########################################################

cat <<EOF | kubectl apply -f -
---
apiVersion: infrastructure.cluster.konvoy.d2iq.io/v1alpha1
kind: PreprovisionedInventory
metadata:
  name: ${CONTROL_PLANE_NAME}
  namespace: default
  labels:
    cluster.x-k8s.io/cluster-name: ${CLUSTER_NAME}
    clusterctl.cluster.x-k8s.io/move: ""
spec:
  hosts:
    # Create as many of these as needed to match your infrastructure
    - address: ${CONTROL_PLANE_1_ADDRESS}
    - address: ${CONTROL_PLANE_2_ADDRESS}
    - address: ${CONTROL_PLANE_3_ADDRESS}
  sshConfig:
    port: ${SSH_PORT}
    # This is the username used to connect to your infrastructure. This user must be root or
    # have the ability to use sudo without a password
    user: ${SSH_USER}
    privateKeyRef:
      # This is the name of the secret you created in the previous step. It must exist in the same
      # namespace as this inventory object.
      name: ${SSH_PRIVATE_KEY_SECRET_NAME}
      namespace: default
---
apiVersion: infrastructure.cluster.konvoy.d2iq.io/v1alpha1
kind: PreprovisionedInventory
metadata:
  name: ${WORKER_NAME}
  namespace: default
  labels:
    clusterctl.cluster.x-k8s.io/move: ""
spec:
  hosts:
    - address: ${WORKER_1_ADDRESS}
    - address: ${WORKER_2_ADDRESS}
    - address: ${WORKER_3_ADDRESS}
    - address: ${WORKER_4_ADDRESS}
  sshConfig:
    port: ${SSH_PORT}
    user: ${SSH_USER}
    privateKeyRef:
      name: ${SSH_PRIVATE_KEY_SECRET_NAME}
      namespace: default
EOF


########################
#### CREATE CLUSTER ####
########################

#default CONTROL PLANE VIP Port is 6443

./dkp create cluster preprovisioned \
    --with-aws-bootstrap-credentials=false \
    --cluster-name ${CLUSTER_NAME} \
    --control-plane-endpoint-host ${CONTROL_PLANE_VIP} \
    --control-plane-endpoint-port ${CONTROL_PLANE_VIP_PORT} \
    --override-secret-name ${SECRET_USER_OVERRIDES} \
    --registry-mirror-url ${DOCKER_REGISTRY_ADDRESS} \
    --virtual-ip-interface ${CONTROL_PLANE_VIP_INTERFACE} \
    --dry-run \
    -o yaml > ${CLUSTER_NAME}.yaml

###############################
#### CREATE METALLB CONFIG ####
###############################
cat <<EOF> mlb.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: metallb-overrides
data:
  values.yaml: |
    configInline:
      address-pools:
      - name: default
        protocol: layer2
        addresses:
        - ${LOAD_BALANCER_IP_RANGE}
---
apiVersion: apps.kommander.d2iq.io/v1alpha2
kind: AppDeployment
metadata:
  name: metallb
spec:
  appRef:
    name: metallb-0.12.2
    kind: ClusterApp
  configOverrides:
    name: metallb-overrides
EOF