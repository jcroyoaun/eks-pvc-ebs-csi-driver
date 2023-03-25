#!/usr/bin/env bash
# Shell script optimized for Bash 4.x to create persistent storage in Amazon EKS.
# This script is a set up persistent storage in Amazon EKS using:
# Amazon Elastic Block Store (Amazon EBS) Container Storage Interface (CSI) driver
#
# Author: JuanCarlos Martinez Carrillo (jcroyoaun)
# Exit codes: 
#  150 -> no cluster name passed.
#  152 -> Unable to get AWS ID.
#  155 -> Cluster does not exist.
# 

set -e
set -u
set -o pipefail

aws_profile=""
aws_region=""
readonly CLUSTER_NAME_MISSING=150
readonly AWS_ID_NOT_FOUND=152
readonly CLUSTER_NOT_EXIST=155

usage() {
    cat <<USAGE_TEXT
Usage: ${0} [-h | --help] [-p <aws_profile> | --profile <aws_profile>] cluster_name aws_region
DESCRIPTION
    This script sets up persistent storage in Amazon EKS using the Amazon
    Elastic Block Store (Amazon EBS) Container Storage Interface (CSI) driver.

OPTIONS:
    -h, --help
        Print this help and exit.
    -p <aws_profile>, --profile <aws_profile>
        Specify the AWS profile to use when executing the script. If not provided,
        the default profile will be used.

ARGUMENTS:
    cluster_name
        The name of the Amazon EKS cluster to set up persistent storage for.
    aws_region
        The AWS region in which the Amazon EKS cluster is located.

USAGE_TEXT
}

terminate() {
    local -r msg="${1}"
    local -r code="${2:-160}"
    echo "${msg}" >&2
    exit "${code}"
}

function cluster_exists() {
  local cluster_name="${1}"
  local profile="${2}"
  local clusters

  clusters=$(aws eks list-clusters --output text ${profile} | tr '\t' '\n')
  if [[ ${clusters[*]} =~ (^|[[:space:]])"${cluster_name}"($|[[:space:]]) ]]; then
    return 0
  else
    return 1
  fi
}

# Functions for setting up persistent storage

download_example_iam_policy() {
  curl -k -o example-iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-ebs-csi-driver/v0.9.0/docs/example-iam-policy.json
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
        "Federated": "arn:aws:iam::${YOUR_AWS_ACCOUNT_ID}:oidc-provider/oidc.eks.${aws_region}.amazonaws.com/id/${oidc_id}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.${aws_region}.amazonaws.com/id/${oidc_id}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
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


# Process command line options

while getopts ":p:h-:" opt; do
  case ${opt} in
    p)
      aws_profile="--profile ${OPTARG}"
      ;;
    h | \?)
      usage
      exit 0
      ;;
    -)
      case "${OPTARG}" in
        help)
          usage
          exit 0
          ;;
        profile)
          aws_profile="--profile ${!OPTIND}"
          OPTIND=$((OPTIND + 1))
          ;;
        *)
          usage
          exit 1
          ;;
      esac
      ;;
    :)
      echo "Option -${OPTARG} requires an argument."
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

if [[ "$#" -ne 2 ]]; then
    usage
    terminate "ERROR: No Cluster name was passed as command line arguments." "${CLUSTER_NAME_MISSING}"
fi

cluster_name="${1}"
aws_region="${2}"

if ! cluster_exists "${cluster_name}" "${aws_profile}"; then
  terminate "ERROR: Cluster '${cluster_name}' does not exist." "${CLUSTER_NOT_EXIST}"
fi

if ! YOUR_AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text ${aws_profile}); then
  terminate "Unable to find/load AWS ID" "${AWS_ID_NOT_FOUND}"
fi

# Call the functions with the aws_profile variable

download_example_iam_policy
create_iam_policy "${aws_profile}"

if ! oidc_issuer_url=$(get_oidc_issuer_url "${aws_profile}"); then
  terminate "No OIDC Issuer URL found"
fi 

if ! oidc_id=$(echo "$oidc_issuer_url" | sed -e "s/^https:\/\/oidc.eks.${aws_region}.amazonaws.com\/id\///"); then
  terminate "Unable to get OIDC ID from the OIDC Issuer URL"
fi

generate_trust_policy
create_iam_role "${aws_profile}"
attach_role_policy "${aws_profile}"

echo "Finished setting up persistent storage in Amazon EKS using EBS Container Storage Interface (CSI) driver..."

exit 0
