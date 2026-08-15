## Project Overview

`kops-lab` is a reusable infrastructure automation repository for college Kubernetes practicals on AWS. It provisions and destroys a fresh KOPS-based cluster without coupling the repository to any specific workload or Kubernetes manifest.

This repository intentionally stops at cluster infrastructure. Pods, Deployments, Services, ConfigMaps, Secrets, Ingress resources, and any other practical-specific YAML should be created separately during each lab session.

Key environment defaults:

- AWS Region: `us-east-1`
- Cluster Name: `online.k8s.local`
- KOPS State Store: `s3://aarush.kops.v1`
- Management Machine OS: Amazon Linux 2023

## AWS Architecture

The cluster is built as a short-lived KOPS environment suitable for repeated lab creation and teardown. The design favors speed, clarity, and reusability over application-specific customization.

```text
                                  +-----------------------------------+
                                  | Permanent AWS Components          |
                                  |-----------------------------------|
                                  | S3 State Store                    |
                                  | aarush.kops.v1                    |
                                  +----------------+------------------+
                                                   |
                                                   |
                         +-------------------------v--------------------------+
                         | Management EC2 (Amazon Linux 2023)                |
                         |----------------------------------------------------|
                         | aws cli | kops | kubectl | ssh key pair            |
                         +-------------------------+--------------------------+
                                                   |
                                                   |
                               +-------------------v-------------------+
                               | KOPS Creates AWS Infrastructure       |
                               +-------------------+-------------------+
                                                   |
        +------------------------------------------+------------------------------------------+
        |                                                                                     |
        v                                                                                     v
+--------------------------+                                               +--------------------------------+
| VPC                      |                                               | Internet Gateway               |
| Public subnets           |<--------------------------------------------->| Public access for lab nodes    |
| Route tables             |                                               +--------------------------------+
+------------+-------------+
             |
             |
   +---------+--------------------------+
   | Security Groups + EC2 + Storage    |
   +-----------------+------------------+
                     |
      +--------------+-------------------------------+
      |                                              |
      v                                              v
+--------------------------+            +--------------------------------------+
| Control Plane            |            | Worker Nodes                         |
| 1 x c7i-flex.large       |            | 1 x c7i-flex.large                   |
| API server, etcd,        |            | Schedulable nodes for lab exercises  |
| controller manager       |            | Auto Scaling Groups                  |
+------------+-------------+            +------------------+-------------------+
             |                                               |
             v                                               v
    +---------------------+                        +---------------------+
    | EBS root volumes    |                        | EBS root volumes    |
    +---------------------+                        +---------------------+
```

## Prerequisites

Before using this repository, ensure the following are ready:

- An AWS account with permissions for EC2, IAM instance profile usage, VPC, Auto Scaling, ELB, Route management, S3 state store access, and related KOPS operations
- A permanent S3 bucket named `aarush.kops.v1`
- An IAM user or role configured for the management EC2
- An Amazon Linux 2023 management instance with outbound internet access
- Basic packages such as `curl`, `tar`, `unzip`, and `ssh-keygen`

Recommended repository layout:

```text
kops-lab/
|-- README.md
|-- install-tools.sh
|-- setup.sh
|-- create-cluster.sh
|-- destroy-cluster.sh
|-- docs/
|   |-- architecture.md
|   |-- aws-setup.md
|   `-- troubleshooting.md
|-- .gitignore
`-- LICENSE
```

## Launch Management EC2

Launch a fresh Amazon Linux 2023 EC2 instance for each practical session. This instance acts only as the administration machine and can be terminated after the lab is complete.

Recommended launch characteristics:

- Region: `us-east-1`
- OS: Amazon Linux 2023
- Instance profile or AWS credentials with KOPS-required permissions
- Security group allowing SSH from your trusted IP
- Enough outbound internet access to download `kops` and `kubectl`

Management lifecycle:

1. Launch EC2.
2. Connect through SSH.
3. Clone this repository.
4. Run the automation scripts.
5. Terminate the management EC2 after the practical.

## Configure AWS CLI

Amazon Linux 2023 already includes the AWS CLI, so this repository does not install it.

Configure credentials using one of these approaches:

1. Attach an IAM role to the management EC2 instance.
2. Or run `aws configure` with an IAM user that has the required permissions.

Verify identity before cluster work:

```bash
aws sts get-caller-identity
aws configure get region
```

If no default region is configured, the scripts will use `us-east-1`.

## Install Tools

Install `kops`, `kubectl`, and generate SSH keys if they are missing:

```bash
chmod +x install-tools.sh setup.sh create-cluster.sh destroy-cluster.sh
./install-tools.sh
```

What `install-tools.sh` does:

- Verifies required system commands are available
- Detects CPU architecture
- Downloads the latest stable `kops`
- Downloads the latest stable `kubectl`
- Installs binaries into `/usr/local/bin`
- Generates `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub` if absent

## Create Cluster

Load the environment and create the lab cluster:

```bash
source ./setup.sh
./create-cluster.sh
```

Cluster defaults:

- Cluster name: `online.k8s.local`
- State store: `s3://aarush.kops.v1`
- Region: `us-east-1`
- Control plane: `1 x c7i-flex.large`
- Worker nodes: `1 x c7i-flex.large`
- Networking: Calico

The cluster creation script:

1. Verifies AWS identity, tools, SSH keys, and S3 state store access.
2. Creates KOPS cluster configuration.
3. Applies the configuration to AWS.
4. Exports kubeconfig access.
5. Waits for validation to succeed.
6. Prints node status.

## Validate Cluster

Validation is included in the creation workflow, but you can re-run checks manually:

```bash
kops validate cluster --name online.k8s.local --state s3://aarush.kops.v1 --wait 10m
kubectl get nodes -o wide
kubectl cluster-info
```

Expected outcome:

- One control plane node is created
- One worker node is registered
- All nodes become `Ready`

## Destroy Cluster

Destroy only the KOPS cluster resources when the practical is finished:

```bash
source ./setup.sh
./destroy-cluster.sh
```

The destroy script deletes only the cluster named `online.k8s.local`.

It does not delete:

- The S3 bucket
- The IAM user or IAM role
- The SSH key pair on the management machine

## Cleanup

After cluster deletion:

1. Confirm the cluster no longer exists with `kops get cluster`.
2. Review EC2, EBS, ELB, and Auto Scaling resources for any unexpected leftovers.
3. Terminate the temporary management EC2 instance.

The permanent S3 state store bucket remains available for the next practical session.

## Future Practical Workflow

This repository is intentionally infrastructure-only. A typical lab workflow is:

1. Launch a fresh management EC2 instance.
2. Clone this repository.
3. Install tools.
4. Create the KOPS cluster.
5. Write or apply Kubernetes manifests required for that day's practical.
6. Complete the exercise.
7. Destroy the cluster.
8. Terminate the management EC2 instance.

This keeps infrastructure automation stable while allowing each practical to use different Kubernetes resources without modifying the repository structure.

## Architecture Documentation

Detailed supporting documentation is available here:

- [Architecture details](./docs/architecture.md)
- [AWS setup guidance](./docs/aws-setup.md)
- [Troubleshooting guide](./docs/troubleshooting.md)
