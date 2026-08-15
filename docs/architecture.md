# Architecture

## Purpose

This repository provisions only the Kubernetes infrastructure needed for repeated AWS KOPS lab exercises. It is designed for short-lived environments where the management instance and Kubernetes cluster are temporary, but the KOPS state store remains permanent.

## Environment Summary

- AWS Region: `us-east-1`
- Cluster Name: `online.k8s.local`
- State Store: `s3://aarush.kops.v1`
- Management Machine: Amazon Linux 2023
- Control Plane: `1 x c7i-flex.large`
- Worker Nodes: `1 x c7i-flex.large`
- Networking: Calico
- Topology: Public

## High-Level Architecture

```text
                              +----------------------------------+
                              | Management EC2                   |
                              | Amazon Linux 2023                |
                              |----------------------------------|
                              | aws cli                          |
                              | kops                             |
                              | kubectl                          |
                              | SSH key pair                     |
                              +----------------+-----------------+
                                               |
                                               v
                              +----------------------------------+
                              | S3 KOPS State Store              |
                              | aarush.kops.v1                    |
                              +----------------+-----------------+
                                               |
                                               v
                              +----------------------------------+
                              | KOPS Cluster Definition          |
                              | online.k8s.local                 |
                              +----------------+-----------------+
                                               |
        +--------------------------------------+--------------------------------------+
        |                                                                             |
        v                                                                             v
+---------------------------+                                          +---------------------------+
| AWS Networking            |                                          | AWS Compute               |
|---------------------------|                                          |---------------------------|
| VPC                       |                                          | 1 Control Plane Instance  |
| Public Subnets            |                                          | 1 Worker Node Instance    |
| Route Tables              |                                          | Auto Scaling Groups       |
| Internet Gateway          |                                          | EBS Root Volumes          |
| Security Groups           |                                          | Load Balancer components  |
+---------------------------+                                          +---------------------------+
```

## Component Breakdown

### VPC

KOPS creates a dedicated VPC for the cluster unless instructed to use an existing one. This VPC isolates the lab network from unrelated AWS resources and allows the entire environment to be removed cleanly after each practical.

### Subnets

The cluster is configured in availability zone `us-east-1a`. KOPS uses this zone to create subnets for the control plane and worker node instance groups.

For this lab-oriented design, the cluster uses a public topology. That keeps provisioning simpler and avoids the added cost and complexity of NAT gateways for short-lived practical sessions.

### Route Tables

KOPS creates route tables and associates them with the generated subnets. These route tables allow instances to reach required AWS and internet endpoints during bootstrap and cluster operation.

### Internet Gateway

Because the cluster uses public topology, an internet gateway is attached to the VPC so instances can pull packages, container images, and cluster dependencies during provisioning.

### Security Groups

KOPS creates and manages security groups for:

- Control plane communication
- Node-to-node traffic
- Kubernetes API access
- SSH connectivity, depending on the cluster settings and your surrounding network controls

These security groups are part of the automatically managed infrastructure and are removed when the cluster is deleted.

### Control Plane

The repository provisions one control plane instance of type `c7i-flex.large`. This node runs core Kubernetes control plane components such as:

- API server
- Controller manager
- Scheduler
- etcd

For college lab use, a single control plane is a practical tradeoff between cost and functionality.

### Worker Nodes

The repository provisions one worker node of type `c7i-flex.large`. This node is where practical-specific Kubernetes resources run after the cluster is created.

Keeping the worker node separate from the control plane gives you a more realistic Kubernetes environment for exercises involving scheduling, services, networking, and troubleshooting.

### EBS

Each EC2 instance uses EBS-backed root storage. These volumes are created as part of the cluster lifecycle and should be removed when KOPS successfully deletes the cluster. If cluster deletion is interrupted, EBS volumes are one of the first resources to verify manually.

### Auto Scaling Groups

KOPS uses Auto Scaling Groups to manage instance groups. Even though the cluster is fixed at one control plane and one worker by default, AWS still tracks those node groups using scaling constructs so instances can be recreated if needed.

### KOPS State Store

The S3 bucket `aarush.kops.v1` stores cluster state, configuration, and metadata used by KOPS. This bucket is intentionally permanent and reused across many practical sessions.

Important distinction:

- The bucket remains.
- The cluster definitions and runtime infrastructure can be recreated and removed repeatedly.

## Lifecycle Model

```text
1. Launch fresh management EC2
2. Clone repository
3. Install kops and kubectl
4. Export KOPS_STATE_STORE and verify AWS identity
5. Create KOPS cluster
6. Run practical-specific Kubernetes work
7. Delete KOPS cluster
8. Terminate management EC2
9. Reuse the same S3 state store next time
```

## Why No Kubernetes Manifests Are Included

The repository is intentionally infrastructure-only. Different practical sessions may require:

- Pods
- Deployments
- Services
- ConfigMaps
- Secrets
- Ingress

Keeping manifests out of this repository prevents application-specific coupling and keeps the automation reusable for any Kubernetes exercise.
