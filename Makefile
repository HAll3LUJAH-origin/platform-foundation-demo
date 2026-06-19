# Local sandbox orchestration. Targets are ordered as a reviewer would run them.
# Requires: docker, kind, kubectl, helm, terraform.

CLUSTER_NAME ?= platform-foundation
REG_PORT     ?= 5001
IMAGE        ?= localhost:$(REG_PORT)/orders-api
TAG          ?= sha-local
ENV          ?= dev
NS            = orders-api-$(ENV)

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n",$$1,$$2}'

.PHONY: cluster
cluster: ## Create kind cluster + local registry
	bash scripts/kind-with-registry.sh

.PHONY: monitoring
monitoring: ## Install kube-prometheus-stack (provides CRDs + Prometheus)
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install kube-prometheus-stack \
	  prometheus-community/kube-prometheus-stack \
	  --namespace monitoring --create-namespace \
	  --set grafana.enabled=true
	kubectl label namespace monitoring kubernetes.io/metadata.name=monitoring --overwrite

.PHONY: infra
infra: ## terraform apply for $(ENV) (namespace, quotas, netpol, RBAC)
	cd infra/terraform/environments/$(ENV) && \
	  terraform init && \
	  terraform apply -auto-approve \
	    -var kube_context=kind-$(CLUSTER_NAME)

.PHONY: build
build: ## Build image and push to local registry
	docker build -t $(IMAGE):$(TAG) --build-arg VERSION=$(TAG) app
	docker push $(IMAGE):$(TAG)

.PHONY: deploy
deploy: ## helm upgrade --install into $(ENV)
	helm upgrade --install orders-api helm/orders-api \
	  --namespace $(NS) \
	  --values helm/orders-api/values-$(ENV).yaml \
	  --set image.repository=$(IMAGE) \
	  --set image.tag=$(TAG) \
	  --rollback-on-failure --timeout 5m
	kubectl -n $(NS) rollout status deploy/orders-api --timeout=180s

.PHONY: smoke
smoke: ## Port-forward and hit health/metrics
	@echo "Run in another shell: kubectl -n $(NS) port-forward svc/orders-api 8080:80"
	@echo "Then: curl localhost:8080/healthz ; curl localhost:8080/metrics"

.PHONY: drill
drill: ## (dev only) inject failures to trigger alerts
	kubectl -n $(NS) port-forward svc/orders-api 8080:80 >/dev/null 2>&1 &
	sleep 2
	curl -s "localhost:8080/debug/fail?rate=0.6&latency_ms=700" && echo
	@echo "Generating load... watch Prometheus for OrdersApiHighErrorRate."
	for i in $$(seq 1 300); do curl -s -o /dev/null localhost:8080/ || true; done

.PHONY: rollback
rollback: ## Roll back to previous release
	helm -n $(NS) rollback orders-api
	kubectl -n $(NS) rollout status deploy/orders-api --timeout=180s

.PHONY: all
all: cluster monitoring infra build deploy ## Full bring-up for $(ENV)

.PHONY: destroy
destroy: ## Tear down the kind cluster
	kind delete cluster --name $(CLUSTER_NAME)
	docker rm -f kind-registry 2>/dev/null || true
