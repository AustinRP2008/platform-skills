# Multi-window, multi-burn-rate alerts

From the Google SRE Workbook, "Alerting on SLOs". Error budget = 1 - SLO. Burn rate = observed error ratio / budget.

| Severity | Burn rate | Long window | Short window | Budget spent at trigger |
|---|---|---|---|---|
| page | 14.4 | 1h | 5m | 2% of a 30-day budget |
| ticket | 6 | 6h | 30m | 5% |

The short window makes the alert reset quickly once the problem stops. Generators such as Sloth or Pyrra
produce the same structure; this skill keeps it hand-readable for learning.
