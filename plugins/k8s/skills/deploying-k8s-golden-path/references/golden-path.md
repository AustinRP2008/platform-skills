# Golden path defaults and why

| Default | Protects against |
|---|---|
| `runAsNonRoot`, `readOnlyRootFilesystem`, drop ALL caps | container breakout, writable-image drift |
| requests and limits on every container | noisy neighbours, scheduler guessing |
| liveness + readiness probes | traffic to unready pods, hung processes never restarted |
| PodDisruptionBudget `minAvailable: 1` (prod: 2 replicas min) | node drains taking the service down |
| HPA on CPU 70% | manual scaling |
| `app.kubernetes.io/*` labels + `team` | unowned workloads, broken dashboards |
| image tag/digest pinned | `:latest` silently changing what runs |
