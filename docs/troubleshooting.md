# Troubleshooting

## Missing `KOPS_STATE_STORE`

### Symptoms

- KOPS commands fail because no state store is defined
- The cluster cannot be found even though it was created previously

### Resolution

Run:

```bash
source ./setup.sh
echo "${KOPS_STATE_STORE}"
```

Expected value:

```text
s3://kunal-petare-kops-state-2026
```

If you execute `./setup.sh` instead of `source ./setup.sh`, the environment variables will not persist in your current shell.

## AWS Region Errors

### Symptoms

- Resources appear in the wrong region
- EC2 or KOPS calls fail with region-related errors

### Resolution

Confirm:

```bash
echo "${AWS_REGION}"
echo "${AWS_DEFAULT_REGION}"
aws configure get region
```

This repository is designed for:

```text
ap-south-1
```

If needed:

```bash
export AWS_REGION=ap-south-1
export AWS_DEFAULT_REGION=ap-south-1
```

Then re-run:

```bash
source ./setup.sh
```

## IAM Permission Errors

### Symptoms

- `AccessDenied`
- `UnauthorizedOperation`
- S3 head-bucket failures
- VPC, EC2, or Auto Scaling creation failures

### Resolution

Verify identity:

```bash
aws sts get-caller-identity
```

Then confirm the active IAM identity has permissions for:

- EC2
- VPC
- Auto Scaling
- ELB
- S3 state store access
- IAM instance profile and related KOPS operations

If you are using an EC2 instance role, confirm the instance was launched with the correct role attached.

## Cluster Validation Failures

### Symptoms

- `kops validate cluster` times out
- Nodes never join the cluster

### Resolution

Check:

```bash
kops validate cluster --name kunal.k8s.local --state s3://kunal-petare-kops-state-2026 --wait 10m
kubectl get nodes -o wide
kubectl cluster-info
```

Common causes:

- Bootstrap still in progress
- IAM permissions missing
- Security group or routing issues
- Incorrect region or state store

If the AWS resources are still converging, wait a few more minutes and retry validation.

## Node `NotReady`

### Symptoms

- One or more nodes appear but remain `NotReady`

### Resolution

Inspect node state:

```bash
kubectl get nodes -o wide
kubectl describe node <node-name>
```

Then verify in AWS:

- The instance is running
- Security groups were created correctly
- The instance has outbound connectivity
- The node bootstrap completed successfully

For KOPS-created instances, also review the instance system logs from the EC2 console if bootstrap appears stalled.

## SSH Issues

### Symptoms

- Cannot SSH to the management EC2 instance
- SSH key files are missing on the management host

### Resolution

For management EC2 access:

- Confirm the EC2 security group allows SSH from your IP
- Confirm you are using the correct AWS key pair for the EC2 instance

For KOPS operations:

```bash
ls -la ~/.ssh/id_rsa ~/.ssh/id_rsa.pub
```

If the files do not exist, run:

```bash
./install-tools.sh
```

That script generates the local SSH key pair required for cluster creation.

## `kubectl` Connection Issues

### Symptoms

- `kubectl` cannot connect to the cluster
- API server connection refused or timeout

### Resolution

Refresh kubeconfig:

```bash
kops export kubecfg --name kunal.k8s.local --state s3://kunal-petare-kops-state-2026 --admin=18h
```

Then verify:

```bash
kubectl config current-context
kubectl cluster-info
kubectl get nodes
```

If the kubeconfig exports correctly but the cluster still cannot be reached, confirm the control plane instance is healthy and the API endpoint resources created by KOPS are available in AWS.
