# argocd-apps layout and rules

```
bootstrap/root.yaml          app of apps: syncs bootstrap/*project.yaml, addons/*.yaml, apps/*.yaml
bootstrap/project.yaml       AppProject platform-addons: chart repos and namespaces add-ons may use
bootstrap/apps-project.yaml  AppProject platform-apps: team repos and namespaces, namespaced resources only
addons/<name>.yaml           ApplicationSet addon-<name>: clusters labelled addon/<name>: "true"
addons/values/<name>/        default.yaml for every cluster, <env>.yaml per env label (optional)
apps/<name>.yaml             ApplicationSet app-<name> (clusters by env label) or Application app-<name> (one cluster)
```

## Application or ApplicationSet
An **Application** is one source synced to one destination cluster and namespace. An **ApplicationSet** is a
template plus a generator; here the cluster generator stamps out one Application per matching cluster, named
`<name>-<cluster>`. Use an Application for something that only ever runs in one place (a hub-only tool, a
one-off chart); use an ApplicationSet for anything that should follow clusters as they are added.

| Rule | Protects against |
|---|---|
| exact chart version | a chart release changing what runs without a PR |
| repo and namespace on the AppProject allow-list | an app pulling from anywhere or writing into any namespace |
| apps project allows only Namespace at cluster scope | a team app installing CRDs, ClusterRoles or webhooks |
| no workloads in kube-system, argocd, default | a workload clobbering platform components |
| `prune` + `selfHeal` | drift: git stays the source of truth |
| `CreateNamespace=true` | a first sync failing on a missing namespace |
| ApplicationSet: `goTemplateOptions: missingkey=error` | a missing cluster label silently rendering an empty value |
| ApplicationSet: name includes `{{.name}}` | two clusters' apps colliding on one name |
| Application: one named destination, resources finalizer | an app with no target; deleting it from git orphaning what it deployed |
| projects at sync-wave -1 | an app rendering before its project exists |
