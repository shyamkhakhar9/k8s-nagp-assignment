# Assignment 1 — Kubernetes Multi-Tier Application

## Table of Contents

1. [Requirement Understanding](#1-requirement-understanding)
2. [Assumptions](#2-assumptions)
3. [Solution Overview](#3-solution-overview)
4. [Justification for the Resources Utilized](#4-justification-for-the-resources-utilized)
5. [Appendix: Deployment & Verification](#appendix-deployment--verification)

---

## 1. Requirement Understanding

The assignment requires designing, containerizing, and deploying a **multi-tier architecture** on Kubernetes consisting of:

- **One microservice (Service API tier)** that exposes an HTTP API and fetches data from a database on each request.
- **One database tier** that stores persistent data and is reachable only inside the cluster.

### 1.1 Service API Tier Requirements

| Requirement | Interpretation |
|-------------|----------------|
| Expose an API/Application endpoint | HTTP REST API with at least one data-fetching endpoint (`GET /api/products`) |
| Fetch data from DB on invocation | API queries PostgreSQL at request time via a connection pool |
| Any language/framework | Python **FastAPI** with **Uvicorn** ASGI server |
| Best practices (pooling, config separation) | `psycopg2` connection pool; DB settings from ConfigMap; password from Secret |
| Rolling updates | `Deployment` with `RollingUpdate` strategy |
| Externally accessible | Public **AWS ALB** via **Ingress** (AWS Load Balancer Controller) |
| Self-healing | Kubernetes `Deployment` controller recreates failed/deleted pods |
| HPA on Service API | `HorizontalPodAutoscaler` scaling on CPU utilization |

### 1.2 Database Tier Requirements

| Requirement | Interpretation |
|-------------|----------------|
| One table with 5–10 records | `products` table seeded with **8 records** via init SQL |
| Data persistence | `StatefulSet` + `PersistentVolumeClaim` (1 Gi) |
| Cluster-internal only | `ClusterIP` headless Service; no Ingress or LoadBalancer for DB |
| Auto-recover after pod deletion | `StatefulSet` recreates `postgres-0` and re-attaches existing PVC |

### 1.3 Kubernetes Feature Matrix

| Feature | Service API Tier | Database Tier |
|---------|------------------|---------------|
| Exposed outside cluster | **Yes** (ALB Ingress) | **No** |
| Number of pods | **4** (HPA min) | **1** |
| Rolling updates | **Yes** | **No** (StatefulSet; single replica) |
| Persistent storage | **No** | **Yes** (PVC) |
| ConfigMap | **Yes** (DB connection config) | **Yes** (init SQL script) |
| Secrets | **Yes** (DB password) | **Yes** (Postgres credentials) |

### 1.4 Cross-Cutting Requirements

| Requirement | How It Is Addressed |
|-------------|---------------------|
| DB config outside pod YAML and app code | `api-config` ConfigMap injected as environment variables |
| DB password not visible in YAML | Secrets created via `scripts/create-secrets.sh` using `kubectl create secret` |
| Data survives DB pod re-deploy | PVC `postgres-data-postgres-0` persists independently of the pod |
| No pod IPs for inter-tier communication | API connects to `postgres-service.k8s-demo.svc.cluster.local` (Kubernetes DNS) |
| External exposure via Ingress | `assignment-api-ingress` with `ingressClassName: alb` |

---

## 2. Assumptions

### 2.1 Infrastructure Assumptions

| # | Assumption |
|---|------------|
| 1 | The target platform is **Amazon EKS** in **us-east-2** (AWS account `730335193392`). |
| 2 | **AWS Load Balancer Controller** is already installed in the `kube-system` namespace. |
| 3 | EKS worker nodes have IAM permissions to pull images from **Amazon ECR**. |
| 4 | A default **StorageClass** exists for dynamic PVC provisioning (e.g. EBS `gp2`/`gp3`). |
| 5 | **metrics-server** is installed on the cluster (required for HPA CPU metrics). |
| 6 | VPC subnets are tagged appropriately for ALB provisioning (`kubernetes.io/role/elb=1` on public subnets). |
| 7 | A network policy engine (e.g. **Calico** or **Cilium**) may be required for `NetworkPolicy` enforcement; the default AWS VPC CNI alone does not enforce policies. |

### 2.2 Operational Assumptions

| # | Assumption |
|---|------------|
| 8 | AWS CLI is configured with profile **`devsaas`** for ECR login, EKS access, and deployments. |
| 9 | `kubectl` context points to the correct EKS cluster before running deploy scripts. |
| 10 | ECR repository name is **`k8s-demo`** in registry `730335193392.dkr.ecr.us-east-2.amazonaws.com`. |
| 11 | All application resources are deployed in namespace **`k8s-demo`**. |
| 12 | PostgreSQL init scripts run **only on first boot** when the data directory is empty; re-deploying the pod does not re-seed data. |
| 13 | HTTP (port 80) on the public ALB is sufficient for the assignment; TLS/HTTPS is not configured. |
| 14 | Single-AZ or default EBS volume placement is acceptable for this demo workload (not multi-AZ HA database). |

### 2.3 Security Assumptions

| # | Assumption |
|---|------------|
| 15 | Secrets are created interactively at deploy time and are not committed to source control. |
| 16 | The API container runs as a **non-root** user (UID 1000) following container security best practices. |
| 17 | Database credentials for the API and Postgres container are shared via separate Secret objects created from the same password input. |

---

## 3. Solution Overview

### 3.1 Architecture

```
                    Internet
                        │
                        ▼
              ┌─────────────────────┐
              │  AWS ALB (public)   │  ← Ingress (ALB Controller)
              └──────────┬──────────┘
                         │ HTTP :80
                         ▼
              ┌─────────────────────┐
              │ assignment-api-svc  │  ClusterIP :80 → :8000
              └──────────┬──────────┘
                         │
         ┌───────────────┼───────────────┬───────────────┐
         ▼               ▼               ▼               ▼
    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
    │ API Pod │    │ API Pod │    │ API Pod │    │ API Pod │  Deployment (4 replicas, HPA 4–8)
    │  :8000  │    │  :8000  │    │  :8000  │    │  :8000  │
    └────┬────┘    └────┬────┘    └────┬────┘    └────┬────┘
         │               │               │               │
         └───────────────┴───────┬───────┴───────────────┘
                                 │ TCP :5432 (DNS: postgres-service)
                                 ▼
                    ┌────────────────────────┐
                    │   postgres-service     │  Headless ClusterIP (internal only)
                    └────────────┬───────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │     postgres-0         │  StatefulSet (1 replica)
                    │     PostgreSQL 16      │
                    └────────────┬───────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │  PVC (1 Gi, RWO)       │  PersistentVolume (EBS)
                    │  postgres-data-postgres-0
                    └────────────────────────┘

    NetworkPolicy: only pods labeled app=assignment-api → postgres:5432
```

### 3.2 Application Tier (FastAPI Microservice)

**Technology:** Python 3.12, FastAPI, Uvicorn, psycopg2

**Endpoints:**

| Endpoint | Purpose |
|----------|---------|
| `GET /` | Service metadata |
| `GET /health` | Liveness/readiness probe; verifies DB connectivity |
| `GET /api/products` | Returns all rows from `products` table |

**Key implementation details:**

- **Connection pooling:** `ThreadedConnectionPool` (min 1, max 10 connections) initialized at startup via FastAPI lifespan handler.
- **Configuration separation:** Non-sensitive DB settings (`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`) from ConfigMap; password read from mounted Secret file at `/secrets/db-password`.
- **Container security:** Non-root user (`app`, UID/GID 1000) in Dockerfile; `securityContext` enforced in Deployment.

**Image registry:** `730335193392.dkr.ecr.us-east-2.amazonaws.com/k8s-demo:latest`

### 3.3 Database Tier (PostgreSQL)

**Technology:** PostgreSQL 16 Alpine (official image)

**Schema:** Single `products` table with columns `id`, `name`, `category`, `price`, `stock`, `created_at`.

**Seed data:** 8 product records inserted via `01-init.sql` mounted from `postgres-init` ConfigMap into `/docker-entrypoint-initdb.d/`.

**Persistence:** `volumeClaimTemplates` provisions `postgres-data-postgres-0` (1 Gi, ReadWriteOnce). Data directory: `/var/lib/postgresql/data/pgdata`.

**Recovery behavior:** Deleting pod `postgres-0` triggers StatefulSet to recreate it with the same name and re-attach the existing PVC. Init scripts do not re-run; data is preserved.

### 3.4 Kubernetes Resources Summary

| Resource | Name | Namespace |
|----------|------|-----------|
| Namespace | `k8s-demo` | — |
| Deployment | `assignment-api` | k8s-demo |
| StatefulSet | `postgres` | k8s-demo |
| Service | `assignment-api-service` | k8s-demo |
| Service | `postgres-service` | k8s-demo |
| Ingress | `assignment-api-ingress` | k8s-demo |
| HPA | `assignment-api-hpa` | k8s-demo |
| ConfigMap | `api-config` | k8s-demo |
| ConfigMap | `postgres-init` | k8s-demo |
| Secret | `postgres-secret` | k8s-demo |
| Secret | `api-db-secret` | k8s-demo |
| NetworkPolicy | `postgres-network-policy` | k8s-demo |
| PVC | `postgres-data-postgres-0` | k8s-demo |

### 3.5 Automation Scripts

| Script | Purpose |
|--------|---------|
| `scripts/build-push.sh` | ECR login, Docker build, push to ECR |
| `scripts/create-secrets.sh` | Create namespace and Kubernetes Secrets interactively |
| `scripts/deploy.sh` | Apply all manifests; wait for Postgres and ALB |
| `scripts/destroy.sh` | Tear down all resources including PVCs and ALB |
| `scripts/demo-self-healing.sh` | Delete an API pod and observe recreation |
| `scripts/demo-rolling-update.sh` | Trigger rolling image update |
| `scripts/demo-hpa.sh` | Load test to demonstrate autoscaling |

### 3.6 Requirement Demonstration Map

| Assignment Demo | Command / Action |
|-----------------|------------------|
| Rolling update | `./scripts/demo-rolling-update.sh` or `kubectl set image deployment/assignment-api ...` |
| Self-healing (API) | `./scripts/demo-self-healing.sh` or `kubectl delete pod <api-pod>` |
| Self-healing (DB) | `kubectl delete pod postgres-0 -n k8s-demo` → data persists |
| HPA | `./scripts/demo-hpa.sh` with `HOST=<alb-dns>` |
| External access | `curl http://<alb-dns>/api/products` |
| DB not externally exposed | No Ingress/LoadBalancer on `postgres-service`; ClusterIP only |
| ConfigMap config | `kubectl describe configmap api-config -n k8s-demo` |
| Secrets (not in YAML) | `kubectl get secret api-db-secret -n k8s-demo` (values base64-encoded) |
| Service DNS (not pod IP) | `DB_HOST=postgres-service.k8s-demo.svc.cluster.local` in ConfigMap |

---

## 4. Justification for the Resources Utilized

### 4.1 Workload Controllers

#### Deployment (API) vs StatefulSet (Database)

| Choice | Justification |
|--------|---------------|
| **Deployment** for API | API pods are stateless and interchangeable. A Deployment supports **rolling updates**, easy **horizontal scaling** (4 replicas + HPA), and **self-healing** when pods fail or are deleted. Pod names and stable identity are not required. |
| **StatefulSet** for PostgreSQL | Databases require **stable network identity** (`postgres-0`) and **persistent storage** per pod. StatefulSet provides ordered deployment, stable hostname, and `volumeClaimTemplates` for automatic PVC binding. A Deployment would not provide the same persistence guarantees for a single-replica database. |

### 4.2 Services

#### `assignment-api-service` (ClusterIP)

- Provides a **stable cluster-internal DNS name** and load-balances traffic across 4 API pod endpoints.
- Port 80 → 8000 decouples Ingress/service port from container port.
- ClusterIP is sufficient because external access is handled by Ingress/ALB.

#### `postgres-service` (Headless ClusterIP)

- **Headless** (`clusterIP: None`) gives stable DNS for StatefulSet pods (`postgres-0.postgres-service.k8s-demo.svc.cluster.local`).
- **ClusterIP only** ensures the database is **not reachable from outside the cluster**, satisfying the assignment requirement.
- API uses the service short name `postgres-service` resolved via Kubernetes DNS — **no pod IPs** are used.

### 4.3 Ingress (AWS ALB)

| Decision | Justification |
|----------|---------------|
| `ingressClassName: alb` | Leverages the pre-installed **AWS Load Balancer Controller** on EKS; native integration with VPC, subnets, and security groups. |
| `scheme: internet-facing` | Creates a **public** Application Load Balancer for external API access. |
| `target-type: ip` | Routes traffic directly to pod IPs (required for Fargate; best practice on EKS for lower latency and simpler path). |
| Health check on `/health` | ALB only routes to healthy pods that can reach the database. |
| HTTP port 80 | Sufficient for assignment demo; avoids ACM certificate setup complexity. |

**Alternatives considered:** NGINX Ingress (not used — cluster has ALB Controller); `LoadBalancer` Service type (bypasses Ingress requirement).

### 4.4 HorizontalPodAutoscaler

| Setting | Value | Justification |
|---------|-------|---------------|
| `minReplicas` | 4 | Matches assignment requirement of **4 API pods** as baseline. |
| `maxReplicas` | 8 | Allows visible scale-out under load without unbounded cost. |
| Metric | CPU 70% | Standard, well-supported metric via metrics-server; easy to demonstrate with load script. |

HPA is applied **only to the API tier** because the database is a single-replica StatefulSet that does not support horizontal scaling in this design.

### 4.5 ConfigMaps

#### `api-config`

Stores non-sensitive database connection parameters (`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD_FILE`). This satisfies the requirement that configuration be **external to the pod definition and application source code** — changes can be made with `kubectl edit configmap` without rebuilding the image.

#### `postgres-init`

Stores the SQL init script. Mounted into the Postgres container's `/docker-entrypoint-initdb.d/` directory, which is the standard PostgreSQL Docker entrypoint pattern for first-time schema and data seeding.

### 4.6 Secrets

| Secret | Keys | Justification |
|--------|------|---------------|
| `postgres-secret` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` | Official Postgres image reads these env vars at startup. |
| `api-db-secret` | `db-password` | Mounted as a file for the API; keeps password out of ConfigMap and Deployment YAML. |

Secrets are created via `kubectl create secret` in a script — **passwords never appear in plain text in Git-tracked YAML files**.

### 4.7 PersistentVolumeClaim

| Attribute | Value | Justification |
|-----------|-------|---------------|
| Size | 1 Gi | Sufficient for 8 demo records; minimal EBS cost. |
| Access mode | ReadWriteOnce | Standard for single-node PostgreSQL; one pod mounts one volume. |
| Provisioned via | `volumeClaimTemplates` in StatefulSet | PVC lifecycle tied to StatefulSet; automatically created as `postgres-data-postgres-0`. |

Without PVC, deleting the Postgres pod would lose all data — violating the persistence requirement.

### 4.8 NetworkPolicy

Restricts ingress to Postgres pods (`app: postgres`) to **only** pods labeled `app: assignment-api` on port **5432**.

| Justification |
|---------------|
| Defense-in-depth: even inside the cluster, arbitrary pods cannot connect to the database. |
| Complements ClusterIP (network reachability) with explicit **identity-based** access control. |
| Aligns with production best practices for multi-tier architectures. |

### 4.9 Probes and Resource Limits

#### API probes

| Probe | Path | Justification |
|-------|------|---------------|
| Readiness | `/health` | Pod receives traffic only when DB is reachable. |
| Liveness | `/health` | Unhealthy pods are restarted automatically (self-healing). |

#### Postgres probes

| Probe | Command | Justification |
|-------|---------|---------------|
| Readiness / Liveness | `pg_isready` | Standard Postgres health check; runs in-container (not affected by NetworkPolicy). |

#### Resource requests/limits

| Tier | CPU Request/Limit | Memory Request/Limit | Justification |
|------|-------------------|------------------------|---------------|
| API | 100m / 500m | 128Mi / 256Mi | Light HTTP workload; limits prevent noisy neighbor; requests enable scheduling and HPA. |
| Postgres | 100m / 500m | 256Mi / 512Mi | Slightly higher memory for DB buffer cache on a small dataset. |

### 4.10 Container Image Choices

| Component | Image | Justification |
|-----------|-------|---------------|
| API | Custom image on ECR | Assignment requires build and push to container registry; ECR integrates natively with EKS. |
| Database | `postgres:16-alpine` | Official, well-maintained, small footprint; supports init scripts and env-based configuration. |
| Non-root API container | UID 1000 | Reduces attack surface; aligns with Pod Security Standards. |

### 4.11 Namespace

All resources are isolated in `k8s-demo` for:

- Clear resource boundaries for the assignment
- Simplified cleanup via `destroy.sh`
- RBAC and network policy scoping

---

## Appendix: Deployment & Verification

### Prerequisites

```bash
# Configure AWS and cluster access
export AWS_PROFILE=devsaas
aws eks update-kubeconfig --region us-east-2 --name <cluster-name>
```

### Deploy

```bash
cd Assignment-1
./scripts/build-push.sh              # Build and push API image to ECR
./scripts/create-secrets.sh          # Create secrets (interactive)
./scripts/deploy.sh                  # Deploy full stack
```

### Verify

```bash
# Check all resources
kubectl get all,ingress,hpa,pvc,networkpolicy -n k8s-demo

# Get public ALB URL
kubectl get ingress assignment-api-ingress -n k8s-demo

# Test API
curl http://<alb-dns>/health
curl http://<alb-dns>/api/products
```

### Destroy

```bash
./scripts/destroy.sh
```

---

*Document version: 1.0 — Assignment 1, Kubernetes DevOps FinOps 2026*
