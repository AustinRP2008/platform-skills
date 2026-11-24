---
name: adding-prometheus-alert
description: Add SLO-based Prometheus alerting for a service (recording rules plus multi-window multi-burn-rate page and ticket alerts), a promtool unit test that proves the alert fires on a bad burn and stays silent when healthy, and a runbook; validate and open a PR. Use when someone asks to add an alert, alerting, an SLO or monitoring for a service.
license: MIT
---

# Adding a Prometheus SLO alert

Alert on symptoms users feel (error budget burn), not causes. Background: `references/burn-rate.md`.

## 1. Collect inputs
| Input | Example | Notes |
|---|---|---|
| `service` | `checkout` | matches the `job` label |
| `team` | `payments` | routes the alert |
| `slo` | `99.9` | availability target, percent |
| `metric` | `http_requests_total` | counter with a `code` label |
| `dest` | `monitoring/` | rules, tests and runbooks are written under it |

Confirm the metric exists before rendering (ask the user, or query Prometheus if one is reachable).

## 2. Render
```bash
${CLAUDE_SKILL_DIR}/scripts/render.sh --service <s> --team <t> --slo <99.9> [--metric http_requests_total] [--dest monitoring]
```
Writes `rules/<s>-slo.rules.yaml`, `tests/<s>-slo.test.yaml` and `runbooks/<s>-error-budget-burn.md`.

## 3. Validate (the same script CI runs)
```bash
${CLAUDE_SKILL_DIR}/scripts/validate.sh <dest>
```
Runs `promtool check rules` and `promtool test rules`. The test has a firing case and a healthy case; both
must pass. If you change thresholds, change the test too — never delete the healthy (must-not-fire) case.

## 4. Open the PR
Branch `feat/alerts-<s>`, commit `feat(<s>): add error budget burn alerts`. Fill in the runbook's
"Diagnosis" section with anything the user told you about the service before opening the PR.
