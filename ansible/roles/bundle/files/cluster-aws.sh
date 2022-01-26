#!/usr/bin/env bash

# Clustername
CLUSTER_SUFFIX=SBX
readonly CLUSTER_NAME=cluster-${CLUSTER_SUFFIX,,}

# AWS Region
readonly AWS_REGION=us-gov-east-1

# Existing AWS infrastructure
readonly AWS_VPC_ID=vpc-058da8b5f1fcb1369
readonly AWS_SUBNET_IDS=subnet-01e311c571e725790
readonly AWS_SECURITY_GROUPS=sg-0c343b2847fb7cd48
readonly AWS_ADDITIONAL_SECURITY_GROUPS=sg-0c343b2847fb7cd48
readonly AWS_AMI_ID=ami-08f1f6c4a711e2d2d

# Instance Profile
readonly INSTANCE_PROFILE_NAME=ag-role
readonly INSTANCE_PROFILE_SUFFIX=cluster-api-provider-aws.sigs.k8s.io
readonly INSTANCE_PROFILE=${INSTANCE_PROFILE_NAME}.${INSTANCE_PROFILE_SUFFIX}

# Registry
readonly DOCKER_REGISTRY_ADDRESS=http://$(hostname -I | awk '{print $1}'):5000

##
# Uncomment if needed
# readonly DOCKER_REGISTRY_CA=<path to the CA on the bastion>
##

# CLI execution
./dkp create bootstrap

# CLI execution
./dkp create cluster aws \
  --cluster-name=${CLUSTER_NAME} \
  --dry-run \
  -o yaml \
  --region=${AWS_REGION} \
  --vpc-id=${AWS_VPC_ID} \
  --ami=${AWS_AMI_ID} \
  --subnet-ids=${AWS_SUBNET_IDS} \
  --internal-load-balancer=true \
  --control-plane-iam-instance-profile=${INSTANCE_PROFILE} \
  --worker-iam-instance-profile=${INSTANCE_PROFILE} \
  --with-aws-bootstrap-credentials=false \
  --registry-mirror-url=${DOCKER_REGISTRY_ADDRESS} > ${CLUSTER_NAME}.yaml

sed -i '/toPort: 9100/a \
    securityGroupOverrides:\
      apiserver-lb: '"${AWS_SECURITY_GROUPS}"'\
      bastion: '"${AWS_SECURITY_GROUPS}"'\
      controlplane: '"${AWS_SECURITY_GROUPS}"'\
      lb: '"${AWS_SECURITY_GROUPS}"'\
      node: '"${AWS_SECURITY_GROUPS}"'' ${CLUSTER_NAME}.yaml