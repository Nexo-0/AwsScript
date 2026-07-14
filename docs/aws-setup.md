# AWS Setup

## Goal

Prepare AWS so that a fresh Amazon Linux 2023 management instance can repeatedly create and destroy the KOPS lab cluster in `ap-south-1`.

## Fixed Environment Values

- Region: `ap-south-1`
- Cluster Name: `kabir.k8s.local`
- State Store: `s3://kunal-petare-kops-state-2026`

## S3 State Store

Create and keep the following bucket permanently:

```text
kunal-petare-kops-state-2026
```

Recommended bucket settings:

- Block public access enabled
- Versioning enabled
- Server-side encryption enabled
- Limited access through IAM

Example command:

```bash
aws s3 mb s3://kunal-petare-kops-state-2026 --region ap-south-1
aws s3api put-bucket-versioning \
  --bucket kunal-petare-kops-state-2026 \
  --versioning-configuration Status=Enabled
```

## IAM Guidance

The management EC2 instance needs permissions for the AWS resources that KOPS creates and manages. In practice, that usually includes access to:

- EC2
- VPC
- IAM instance profiles and role discovery
- Auto Scaling
- Elastic Load Balancing
- Route 53-related calls used internally by KOPS tooling where applicable
- S3 access to the KOPS state store

For a college lab environment, the cleanest setup is often:

1. Create an IAM role for the management EC2 instance.
2. Attach the required KOPS-compatible permissions.
3. Launch the EC2 instance with that role attached.

If you use an IAM user instead, configure it on the management machine with:

```bash
aws configure
```

Then verify:

```bash
aws sts get-caller-identity
```

## Why `kabir.k8s.local` Works

The cluster name uses the `.k8s.local` suffix, which is commonly used with KOPS for non-public DNS and lab-style clusters. This avoids the need to register a public DNS zone for repeated practice environments.

## Management EC2 Recommendations

Use a separate temporary EC2 instance as the management host for each practical.

Recommended characteristics:

- OS: Amazon Linux 2023
- Region: `ap-south-1`
- Inbound SSH from your trusted IP only
- Outbound internet access enabled
- An attached IAM role whenever possible

## AWS CLI Configuration

Amazon Linux 2023 already includes the AWS CLI, so no extra AWS CLI installation is required by this repository.

Confirm the configuration:

```bash
aws sts get-caller-identity
aws configure get region
```

If `aws configure get region` is empty, the scripts default to `ap-south-1`.

## Expected AWS Resources Created by KOPS

When `create-cluster.sh` runs, KOPS may create resources such as:

- VPC
- Subnets
- Route tables
- Internet gateway
- Security groups
- EC2 instances
- EBS volumes
- Auto Scaling Groups
- Load balancer resources used by the Kubernetes API

These cluster resources are deleted by `destroy-cluster.sh`.

The following are intentionally reused and not deleted:

- The S3 state store bucket
- IAM user or IAM role
- Management EC2 SSH key pair

## Validation Commands

Useful checks before cluster creation:

```bash
aws sts get-caller-identity
aws s3api head-bucket --bucket kunal-petare-kops-state-2026
kops version
kubectl version --client
```
