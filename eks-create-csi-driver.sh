#!/usr/bin/env bash
# Shell script optimized for Bash 4.x to create persistent storage in Amazon EKS.
# This script is a set up persistent storage in Amazon EKS using:
# Amazon Elastic Block Store (Amazon EBS) Container Storage Interface (CSI) driver
#
# Author: JuanCarlos Martinez Carrillo (jcroyoaun)
# Exit codes: 
#  150 -> no cluster name passed.
#  152 -> Unable to get AWS ID.
# 

set -e
set -u
set -o pipefail
aws_profile=""
readonly CLUSTER_NAME_MISSING=150
readonly AWS_ID_NOT_FOUND=152

while getopts ":p:" opt; do
  case ${opt} in
    p)
      aws_profile="--profile ${OPTARG}"
      ;;
    \?)
      echo "Usage: ${0} [-p aws_profile] cluster_name"
      exit 1
      ;;
    :)
      echo "Option -${OPTARG} requires an argument."
      exit 1
      ;;
  esac
done

shift $((OPTIND - 1))

terminate() {
    local -r msg="${1}"
    local -r code="${2:-160}"
    echo "$0 - Error: ${msg}" >&2
    exit "${code}"
}

if [[ "$#" -ne 1 ]]; then
    terminate "No Cluster name was passed as command line arguments." "${CLUSTER_NAME_MISSING}"
    exit 150
fi
cluster_name="${1}"

if ! YOUR_AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text ${aws_profile}); then
  terminate "Unable to find/load AWS ID" "${AWS_ID_NOT_FOUND}"
fi

echo "${YOUR_AWS_ACCOUNT_ID}"

download_example_iam_policy() {
  curl -o example-iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-ebs-csi-driver/v0.9.0/docs/example-iam-policy.json
}

create_iam_policy() {
  local -r profile="${1}"
  aws iam create-policy --policy-name AmazonEKS_EBS_CSI_Driver_Policy --policy-document file://example-iam-policy.json ${profile}
}

get_oidc_issuer_url() {
  local -r profile="${1}"
  aws eks describe-cluster --name "${cluster_name}" --query "cluster.identity.oidc.issuer" --output text ${profile}
}

generate_trust_policy() {
  cat <<EOF > trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${YOUR_AWS_ACCOUNT_ID}:oidc-provider/oidc.eks.${YOUR_AWS_REGION}.amazonaws.com/id/${oidc_id}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.${YOUR_AWS_REGION}.amazonaws.com/id/${oidc_id}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF

  echo "Generated trust-policy.json:"
  cat trust-policy.json
}

create_iam_role() {
  local -r profile="${1}"
  aws iam create-role \
    --role-name AmazonEKS_EBS_CSI_DriverRole \
    --assume-role-policy-document file://trust-policy.json ${profile}
}

attach_role_policy() {
  local -r profile="${1}"
  aws iam attach-role-policy \
    --policy-arn "arn:aws:iam::${YOUR_AWS_ACCOUNT_ID}:policy/AmazonEKS_EBS_CSI_Driver_Policy" \
    --role-name AmazonEKS_EBS_CSI_DriverRole ${profile}
}

# Call the functions with the aws_profile variable
download_example_iam_policy
create_iam_policy "${aws_profile}"

if ! oidc_issuer_url=$(get_oidc_issuer_url "${aws_profile}"); then
  terminate "No OIDC Issuer URL found"
fi 

if ! oidc_id=$(echo "$oidc_issuer_url" | sed -e "s/^https:\/\/oidc.eks.${YOUR_AWS_REGION}.amazonaws.com\/id\///"); then
  terminate "Unable to get OIDC ID from teh OIDC Issuer URL"
fi

generate_trust_policy
create_iam_role "${aws_profile}"
attach_role_policy "${aws_profile}"

