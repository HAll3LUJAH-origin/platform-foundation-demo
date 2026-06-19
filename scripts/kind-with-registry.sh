#!/usr/bin/env bash
# Creates a local kind cluster wired to a local container registry, plus the
# namespace labels Prometheus/NetworkPolicies rely on. Idempotent.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-platform-foundation}"
REG_NAME="${REG_NAME:-kind-registry}"
REG_PORT="${REG_PORT:-5001}"

# 1. Local registry container.
if [ "$(docker inspect -f '{{.State.Running}}' "${REG_NAME}" 2>/dev/null || true)" != 'true' ]; then
  docker run -d --restart=always -p "127.0.0.1:${REG_PORT}:5000" \
    --network bridge --name "${REG_NAME}" registry:2
fi

# 2. kind cluster that trusts the local registry.
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${REG_PORT}"]
      endpoint = ["http://${REG_NAME}:5000"]
EOF
fi

# 3. Connect registry to the kind network.
if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${REG_NAME}")" = 'null' ]; then
  docker network connect "kind" "${REG_NAME}" || true
fi

# 4. Label kube-system so NetworkPolicy DNS egress selector matches.
kubectl label namespace kube-system kubernetes.io/metadata.name=kube-system --overwrite >/dev/null

echo "kind cluster '${CLUSTER_NAME}' ready. Context: kind-${CLUSTER_NAME}"
echo "Local registry: localhost:${REG_PORT}"
