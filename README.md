# Amazon EKS Persistent Storage Setup

This script helps you set up persistent storage in Amazon EKS using the Amazon Elastic Block Store (Amazon EBS) Container Storage Interface (CSI) driver.

## Prerequisites

- Bash 4.x
- AWS CLI installed and configured
- Access to an Amazon EKS cluster

## Usage

To run the script, navigate to the directory where the script is located and execute the following command:

```sh
./<script_name> [-p aws_profile] cluster_name
```

Replace <script_name> with the name of the script file. The -p option is optional and can be used to specify a specific AWS profile. If it's not provided, the script will use the default AWS profile.


## Parameters
-p aws_profile: (Optional) The AWS profile to use for the AWS CLI commands. If not provided, the default profile will be used.
cluster_name: The name of the Amazon EKS cluster where you want to set up persistent storage.

## Exit Codes
150: No cluster name was passed as command line arguments.
152: Unable to get AWS ID.

## Example
To set up persistent storage in an Amazon EKS cluster named my-eks-cluster using the default AWS profile:

```sh
./<script_name> -p my-aws-profile my-eks-cluster
```

Replace <script_name> with the name of the script file.

