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
`enterprise-rag-retrieval` — FastAPI/Granian service for retrieval, LLM answering, and source references; deployed here as a Deployment.
`enterprise-rag-deployment` — umbrella Helm chart controlling the Kubernetes/OpenShift deployment of the complete stack.
RustFS — S3-compatible object storage for source and staging documents, with persistent storage.
Qdrant — vector storage for embeddings and source metadata, with persistent storage.
```text
enterprise-rag-deployment/              # Helm umbrella chart
└── helm/
    ├── Chart.yaml
    ├── values.yaml                    # Safe defaults; workloads disabled
    ├── values-dev.yaml                # Development overrides
    ├── values-int.yaml                # Integration overrides
    ├── values-uat.yaml                # UAT overrides
    ├── values-prod.yaml               # Production overrides; no secrets
    └── charts/
        ├── enterprise-rag-embedding-service/ # Long-running embedding API
        ├── enterprise-rag-indexing/          # On-demand Job / CronJob
        └── enterprise-rag-retrieval/         # Long-running retrieval API
```
Each subchart contains its own `Chart.yaml`, default `values.yaml`, and `templates/` directory. Kubernetes resources should be defined in separate, purpose-named files when needed, such as `deployment.yaml`, `statefulset.yaml`, `job.yaml`, `cronjob.yaml`, `service.yaml`, `configmap.yaml`, `secret.yaml`, `pvc.yaml`, and `ingress.yaml`. Shared template helpers belong in `_helpers.tpl`. Unused resource templates should not be created.
## Configuration

Kubernetes workloads do not read the orchestration repository's local `.env` files. Helm translates environment-specific values from `helm/values-dev.yaml`, `helm/values-int.yaml`, `helm/values-uat.yaml`, or `helm/values-prod.yaml` into per-workload ConfigMaps and Secrets. Values are nested under `enterprise-rag-embedding-service`, `enterprise-rag-indexing`, and `enterprise-rag-retrieval`.

| Workload | ConfigMap environment variables | Secret environment variables |
| --- | --- | --- |
| Embedding service | `EMBEDDING_SERVICE_HOST`, `EMBEDDING_SERVICE_PORT`, `EMBEDDING_SERVICE_LOG_LEVEL`; `S3_PROVIDER`, `S3_ENDPOINT_URL`, `S3_REGION`, `S3_ADDRESSING_STYLE`, `S3_VERIFY_TLS`; `EMBEDDINGS_MODEL_NAME`, `EMBEDDINGS_REVISION`, `EMBEDDINGS_LOCAL_DIRECTORY`, `EMBEDDINGS_BUCKET`, `EMBEDDINGS_KEY_PREFIX`, `EMBEDDINGS_DIMENSION`, `EMBEDDINGS_ONNX_MODEL_FILE`, `EMBEDDINGS_TOKENIZER_FILE` | `S3_ACCESS_KEY`, `S3_SECRET_KEY` |
| Indexing job | `S3_PROVIDER`, `S3_ENDPOINT_URL`, `S3_REGION`, `S3_ADDRESSING_STYLE`, `S3_VERIFY_TLS`, `S3_MAX_CONCURRENCY`, `S3_PROCESSING_BUCKET`, `S3_CLAIM_TTL_SECONDS`, `S3_SOURCE_BUCKET`; `INDEXING_WORK_DIRECTORY`; `PDF_CHUNK_SIZE`, `PDF_CHUNK_OVERLAP`; `EMBEDDING_SERVICE_URL`, `EMBEDDING_SERVICE_API_PATH`, `EMBEDDING_SERVICE_TIMEOUT_SECONDS`, `EMBEDDING_SERVICE_EXPECTED_MODEL`, `EMBEDDING_SERVICE_EXPECTED_DIMENSION`; `VECTOR_PROVIDER`; `QDRANT_URL`, `QDRANT_COLLECTION_NAME`, `QDRANT_VECTOR_SIZE`, `QDRANT_BATCH_SIZE` | `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `QDRANT_API_KEY` |
| Retrieval API | All `QUERY_API_*`, `EMBEDDING_SERVICE_*`, non-secret `QDRANT_*`, `RAG_*`, `RERANKING_*`, and non-secret `LLM_*` variables defined by the retrieval service | `QDRANT_API_KEY`, `LLM_API_KEY` |

These lists describe the environment variables currently rendered by the chart templates; the application READMEs describe the larger runtime setting sets. Keep model identity/dimension, collection/vector names, endpoints, commands, ports, and TLS behavior aligned between Helm and the applications. Rarely changing defaults belong in each subchart's `values.yaml`; environment-specific overrides belong in the parent values files.

The retrieval subchart maps each environment variable explicitly from a snake-case `configmap` value, matching the established indexing-chart convention. It can create its Secret from `secret.qdrant_api_key` and `secret.llm_api_key` for local development or reference an externally managed Secret through `secret.existingSecret`. Do not commit real credentials. Production deployments should set `secret.create=false`, configure `secret.existingSecret`, and provision that Secret through an enterprise vault. ConfigMaps must contain only non-sensitive settings. Production access should use appropriate TLS and network controls; access-control design remains outside this project's scope.
PersistentVolumeClaims preserve RustFS object data and Qdrant vector data across pod restarts. Storage classes and access modes must be configured for the target cluster. The deployment does not itself guarantee backup, high availability, or disaster recovery.
Deploy the stack
Prerequisites: a reachable Kubernetes or OpenShift cluster, configured `kubectl` (or `oc`), Helm 3, a usable namespace, appropriate permissions, container images accessible to the cluster, and persistent storage provisioning.
The following commands illustrate the intended release workflow. They assume this repository has been implemented as a valid umbrella chart and that `values-dev.yaml` exists.
```bash
# From the enterprise-rag-deployment repository root
helm lint helm -f helm/values-dev.yaml

# Render and inspect all Kubernetes resources
helm template enterprise-rag helm \
  --namespace enterprise-rag \
  -f helm/values-dev.yaml > ./output/deployment-dev.yaml

# Create the namespace if it does not exist
kubectl create namespace enterprise-rag

# Install or upgrade the release
helm upgrade --install enterprise-rag helm \
  --namespace enterprise-rag \
  -f helm/values-dev.yaml
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
## Validation

Always run Helm checks before deployment:
```bash
for values_file in helm/values-dev.yaml helm/values-int.yaml helm/values-uat.yaml helm/values-prod.yaml; do
  helm lint helm -f "${values_file}"
  helm template enterprise-rag helm -f "${values_file}" --namespace enterprise-rag > /dev/null
done
```

Validate that every retrieval environment variable is rendered by either the retrieval ConfigMap or Secret, and that API keys do not leak into the ConfigMap:

```bash
./tests/check-retrieval-env-coverage.sh \
  ../dev-envs/enterprise-rag-retrieval.example \
  helm/values-dev.yaml
```
When a compatible cluster and sufficient permissions are available, perform server-side validation:
```bash
helm template enterprise-rag helm \
  -f helm/values-dev.yaml \
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

## Current limitations

no authenticationno authorization procesed have been covered at the project
