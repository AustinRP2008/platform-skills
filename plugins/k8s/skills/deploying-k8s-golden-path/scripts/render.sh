#!/usr/bin/env bash
# Render golden-path manifests. Usage: render.sh --name N --image I --team T [--port P] [--dest D]
set -euo pipefail
port=8080 dest=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --name) name=$2; shift 2;; --image) image=$2; shift 2;; --team) team=$2; shift 2;;
    --port) port=$2; shift 2;; --dest) dest=$2; shift 2;;
    *) echo "unknown arg $1" >&2; exit 64;;
  esac
done
: "${name:?--name required}" "${image:?--image required}" "${team:?--team required}"
[[ $name =~ ^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$ ]] || { echo "name must be a DNS-1123 label" >&2; exit 64; }
[[ $image == *:latest || ( $image != *:* && $image != *@sha256:* ) ]] && { echo "image must pin a tag or digest (not :latest)" >&2; exit 64; }
[[ $port =~ ^[0-9]+$ ]] || { echo "port must be numeric" >&2; exit 64; }
dest=${dest:-apps/$name}
[[ -e $dest ]] && { echo "refusing: $dest already exists" >&2; exit 65; }
mkdir -p "$dest/base" "$dest/overlays/dev" "$dest/overlays/prod"

cat > "$dest/base/deployment.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $name
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: $name
  template:
    metadata:
      labels:
        app.kubernetes.io/name: $name
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: $name
          image: $image
          ports:
            - name: http
              containerPort: $port
          readinessProbe:
            httpGet: {path: /readyz, port: http}
            periodSeconds: 5
          livenessProbe:
            httpGet: {path: /healthz, port: http}
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            requests: {cpu: 50m, memory: 64Mi}
            limits: {memory: 256Mi}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
YAML
cat > "$dest/base/service.yaml" <<YAML
apiVersion: v1
kind: Service
metadata:
  name: $name
spec:
  selector:
    app.kubernetes.io/name: $name
  ports:
    - name: http
      port: 80
      targetPort: http
YAML
cat > "$dest/base/hpa.yaml" <<YAML
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: $name
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: $name}
  minReplicas: 1
  maxReplicas: 3
  metrics:
    - type: Resource
      resource: {name: cpu, target: {type: Utilization, averageUtilization: 70}}
YAML
cat > "$dest/base/pdb.yaml" <<YAML
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: $name
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: $name
YAML
cat > "$dest/base/kustomization.yaml" <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: [deployment.yaml, service.yaml, hpa.yaml, pdb.yaml]
labels:
  - pairs:
      app.kubernetes.io/part-of: $name
      app.kubernetes.io/managed-by: kustomize
      team: $team
YAML
for env in dev prod; do
  min=1 max=3; [[ $env == prod ]] && min=2 max=10
  cat > "$dest/overlays/$env/kustomization.yaml" <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: $name-$env
resources: [../../base]
labels:
  - pairs: {environment: $env}
patches:
  - target: {kind: HorizontalPodAutoscaler, name: $name}
    patch: |-
      - {op: replace, path: /spec/minReplicas, value: $min}
      - {op: replace, path: /spec/maxReplicas, value: $max}
YAML
done
echo "rendered $dest (overlays: dev prod)"
