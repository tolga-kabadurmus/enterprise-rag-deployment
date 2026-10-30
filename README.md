# enterprise-rag-deployment
enterprise-rag-deployment
Enterprise RAG — Kubernetes Deployment
`enterprise-rag-deployment` is the Helm-based Kubernetes/OpenShift deployment repository for the Enterprise RAG project. It deploys the document indexing job, RAG query API, RustFS S3-compatible object storage, and Qdrant vector database as a single Helm umbrella chart.
The application reads documents from S3-compatible storage, extracts and chunks content, generates embeddings, indexes vectors with source metadata in Qdrant, and answers user questions through an LLM using retrieved context and source references.
Authentication (authn) and authorization (authz) are outside the scope of this project. This chart does not implement or document either concern; deployments must address them externally when required.
For application architecture and coding conventions, see the `enterprise-rag` orchestration repository and its `AGENTS.md`. The Helm-specific requirements are maintained in the deployment specification in `AGENTS.md` when added to the project.
Repositories and components
`enterprise-rag` — top-level local development orchestration with Docker Compose and Git submodules.
`enterprise-rag-indexing` — disposable asynchronous indexing application; deployed here as a Kubernetes Job (or CronJob when scheduled execution is required).
`enterprise-rag-query` — FastAPI/Granian service for retrieval, LLM answering, and source references; deployed here as a Deployment.
`enterprise-rag-deployment` — umbrella Helm chart controlling the Kubernetes/OpenShift deployment of the complete stack.
RustFS — S3-compatible object storage for source and staging documents, with persistent storage.
Qdrant — vector storage for embeddings and source metadata, with persistent storage.
```text
enterprise-rag-deployment/              # Helm umbrella chart
├── Chart.yaml
├── values.yaml
├── values-dev.yaml                    # Example environment overrides
├── values-prod.yaml                   # Example environment overrides; no secrets
└── charts/
    ├── qdrant/                        # Persistent vector database
    ├── rustfs/                        # Persistent S3-compatible storage
    ├── enterprise-rag-indexing/       # On-demand Job / optional CronJob
    └── enterprise-rag-query/          # Long-running API Deployment
```
Each subchart contains its own `Chart.yaml`, default `values.yaml`, and `templates/` directory. Kubernetes resources should be defined in separate, purpose-named files when needed, such as `deployment.yaml`, `statefulset.yaml`, `job.yaml`, `cronjob.yaml`, `service.yaml`, `configmap.yaml`, `secret.yaml`, `pvc.yaml`, and `ingress.yaml`. Shared template helpers belong in `_helpers.tpl`. Unused resource templates should not be created.
Helm configuration
Keep rarely changing defaults in each subchart's `values.yaml`. Use the umbrella chart's `values.yaml` and environment-specific override files to configure image names and tags, replicas, resources, persistence, endpoints, networking, and runtime options.
Helm values for subcharts are normally nested under their chart names. The specific parameter keys must match the chart templates actually implemented; no complete values schema is defined at this conceptual stage.
Do not commit credentials. The deployment should be able to reference existing Kubernetes Secrets for Qdrant API keys, RustFS credentials, and embedding/LLM provider keys. ConfigMaps should contain only non-sensitive settings. Production access should use appropriate TLS and network controls; access-control design remains outside this project's scope.
PersistentVolumeClaims preserve RustFS object data and Qdrant vector data across pod restarts. Storage classes and access modes must be configured for the target cluster. The deployment does not itself guarantee backup, high availability, or disaster recovery.
Deploy the stack
Prerequisites: a reachable Kubernetes or OpenShift cluster, configured `kubectl` (or `oc`), Helm 3, a usable namespace, appropriate permissions, container images accessible to the cluster, and persistent storage provisioning.
The following commands illustrate the intended release workflow. They assume this repository has been implemented as a valid umbrella chart and that `values-dev.yaml` exists.
```bash
# From the enterprise-rag-deployment repository root
helm lint . -f values-dev.yaml

# Render and inspect all Kubernetes resources
helm template enterprise-rag . \
  --namespace enterprise-rag \
  -f values-dev.yaml

# Create the namespace if it does not exist
kubectl create namespace enterprise-rag

# Install or upgrade the release
helm upgrade --install enterprise-rag . \
  --namespace enterprise-rag \
  -f values-dev.yaml
```
`kubectl create namespace` is a one-time operation and will report an error if the namespace already exists. In automation, create it declaratively or use Helm's `--create-namespace` flag where appropriate.
Inspect the release and workloads:
```bash
helm status enterprise-rag -n enterprise-rag
kubectl get pods,deployments,statefulsets,jobs,services,pvc -n enterprise-rag
kubectl get events -n enterprise-rag --sort-by=.metadata.creationTimestamp
```
The indexing application must not run indefinitely as a Deployment. Its job receives the source bucket and optional document-key prefix as runtime configuration and terminates after processing. Job execution is subject to the implemented chart's trigger and rerun strategy; a Helm install or upgrade should not silently reprocess all documents. For example, the implementation may supply a manually created Job or a controlled Helm hook. Scheduled indexing can later use a CronJob.
The query API operates as a long-running Deployment with an internal Service and optional Ingress/Route, configured according to the target Kubernetes/OpenShift environment. Its public URL and REST paths are not yet fixed.
Validation
Always run Helm checks before deployment:
```bash
helm lint . -f values-dev.yaml
helm template enterprise-rag . -f values-dev.yaml --namespace enterprise-rag
helm template enterprise-rag . -f values-dev.yaml --namespace enterprise-rag > ../output/deployment-dev.yaml

```
When a compatible cluster and sufficient permissions are available, perform server-side validation:
```bash
helm template enterprise-rag . \
  -f values-dev.yaml \
  --namespace enterprise-rag \
  | kubectl apply --dry-run=server -f -
```
A successful `helm template` verifies rendering, not runtime correctness, permission readiness, storage compatibility, or successful application startup. Validate those separately after deployment.
Uninstall
```bash
helm uninstall enterprise-rag --namespace enterprise-rag
```
Data retention warning: Helm uninstall behavior does not guarantee either retention or removal of PersistentVolumeClaims and underlying data. Inspect reclaim policies, StatefulSet PVC behavior, and any Helm resource-retention annotations before uninstalling or deleting storage.
Project scope and status
This README describes the intended Helm deployment architecture, not an already validated cluster deployment. Specific image references, values fields, security objects, chart hooks, access URLs, resources, storage classes, and OpenShift-specific settings will be finalized during implementation.
The first target is the core Enterprise RAG workflow: source documents → indexing → Qdrant → retrieval → LLM answer with references. Hybrid search, reranking, conversation memory, evaluation pipelines, observability dashboards, and CI/CD are possible later enhancements.
Storage naming note: Earlier `enterprise-rag` documentation referred to MinIO. This deployment design follows the newer RustFS choice. The parent orchestration README, Compose configuration, and `AGENTS.md` should be synchronized if RustFS is now the canonical object-storage provider.
