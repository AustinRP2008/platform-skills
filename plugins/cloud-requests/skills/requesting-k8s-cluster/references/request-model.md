# Cluster request model

Request file -> policy -> cost -> approval tier -> plan -> PR. Modelled on account vending (AWS AFT) and
cluster-as-a-service flows in internal developer portals: a typed request in git, a thin module behind it,
humans approve by tier.

## Sizes
| Size | GKE standard | EKS managed | Use for |
|---|---|---|---|
| S | e2-standard-2, 1-3 nodes | t3.large, 1-3 nodes | dev, demos |
| M | e2-standard-4, 2-6 nodes | m6i.large, 2-6 nodes | staging, small prod |
| L | e2-standard-8, 3-12 nodes | m6i.xlarge, 3-12 nodes | prod |

Autopilot / Auto Mode bill per pod or per node the cloud picks; the size then only sets the budget class.

## Approval tiers
| Tier | When | Who |
|---|---|---|
| `auto` | dev, size S or M, ttl <= 72h | merges when CI is green |
| `platform` | staging, or dev beyond the auto limits | one platform reviewer |
| `platform-2` | prod, or size L anywhere | two platform reviewers |

## TTL
Dev and staging clusters must carry a TTL (max 168h). A scheduled job opens a destroy PR when it expires;
extending it is a new PR. Prod clusters never carry a TTL and always have deletion protection.

## Cost
`assets/prices.json` is an illustrative price table for practice, not a quote. Replace it with
Infracost in a real setup.
