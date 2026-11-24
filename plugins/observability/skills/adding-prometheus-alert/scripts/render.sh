#!/usr/bin/env bash
# Render SLO burn-rate rules, a promtool test and a runbook.
# Usage: render.sh --service S --team T --slo 99.9 [--metric http_requests_total] [--dest monitoring]
set -euo pipefail
metric=http_requests_total dest=monitoring
while [[ $# -gt 0 ]]; do
  case $1 in
    --service) svc=$2; shift 2;; --team) team=$2; shift 2;; --slo) slo=$2; shift 2;;
    --metric) metric=$2; shift 2;; --dest) dest=$2; shift 2;;
    *) echo "unknown arg $1" >&2; exit 64;;
  esac
done
: "${svc:?--service required}" "${team:?--team required}" "${slo:?--slo required}"
[[ $svc =~ ^[a-z][a-z0-9-]*$ ]] || { echo "service must be lowercase kebab-case" >&2; exit 64; }
[[ $metric =~ ^[a-zA-Z_:][a-zA-Z0-9_:]*$ ]] || { echo "invalid metric name" >&2; exit 64; }
# Below ~93% a 14.4x burn exceeds 100% errors and the page alert could never fire.
budget=$(awk -v s="$slo" 'BEGIN{ if (s<95 || s>99.999) exit 1; printf "%.6g", 1 - s/100 }') \
  || { echo "slo must be between 95 and 99.999" >&2; exit 64; }
alert=$(echo "$svc" | awk -F- '{for(i=1;i<=NF;i++) printf toupper(substr($i,1,1)) substr($i,2)}')
rules="$dest/rules/$svc-slo.rules.yaml" test="$dest/tests/$svc-slo.test.yaml" runbook="$dest/runbooks/$svc-error-budget-burn.md"
for f in "$rules" "$test" "$runbook"; do [[ -e $f ]] && { echo "refusing: $f exists" >&2; exit 65; }; done
mkdir -p "$dest/rules" "$dest/tests" "$dest/runbooks"
rec=job:${metric%_total}:error_ratio
sel="job=\"$svc\""

{
  echo "groups:"
  echo "  - name: $svc-slo"
  echo "    rules:"
  for w in 5m 30m 1h 6h; do
    cat <<YAML
      - record: ${rec}_rate$w
        expr: |
          sum by (job) (rate(${metric}{$sel,code=~"5.."}[$w]))
          /
          sum by (job) (rate(${metric}{$sel}[$w]))
YAML
  done
  cat <<YAML
      - alert: ${alert}ErrorBudgetBurnFast
        expr: |
          ${rec}_rate1h{$sel} > (14.4 * $budget)
          and
          ${rec}_rate5m{$sel} > (14.4 * $budget)
        for: 2m
        labels:
          severity: page
          team: $team
        annotations:
          summary: "$svc is burning its $slo% error budget 14x too fast"
          runbook_url: "runbooks/$svc-error-budget-burn.md"
      - alert: ${alert}ErrorBudgetBurnSlow
        expr: |
          ${rec}_rate6h{$sel} > (6 * $budget)
          and
          ${rec}_rate30m{$sel} > (6 * $budget)
        for: 15m
        labels:
          severity: ticket
          team: $team
        annotations:
          summary: "$svc is burning its $slo% error budget 6x too fast"
          runbook_url: "runbooks/$svc-error-budget-burn.md"
YAML
} > "$rules"

# Test traffic is 600 req/min. bad = 20x budget burn (above both thresholds) -> fires page + ticket;
# healthy = 0.5x budget burn -> fires nothing.
bad_err=$(awk -v b="$budget" 'BEGIN{ e = 600 * b * 20; if (e > 600) e = 600; printf "%.6g", e }')
bad_ok=$(awk -v e="$bad_err" 'BEGIN{ printf "%.6g", 600 - e }')
healthy_err=$(awk -v b="$budget" 'BEGIN{ printf "%.6g", 600 * b / 2 }')
cat > "$test" <<YAML
rule_files:
  - ../rules/$svc-slo.rules.yaml
evaluation_interval: 1m
tests:
  - name: bad burn pages and tickets
    interval: 1m
    input_series:
      - series: '${metric}{job="$svc",code="200"}'
        values: '0+${bad_ok}x120'
      - series: '${metric}{job="$svc",code="500"}'
        values: '0+${bad_err}x120'
    alert_rule_test:
      - eval_time: 70m
        alertname: ${alert}ErrorBudgetBurnFast
        exp_alerts:
          - exp_labels: {job: $svc, severity: page, team: $team}
            exp_annotations:
              summary: "$svc is burning its $slo% error budget 14x too fast"
              runbook_url: "runbooks/$svc-error-budget-burn.md"
      - eval_time: 70m
        alertname: ${alert}ErrorBudgetBurnSlow
        exp_alerts:
          - exp_labels: {job: $svc, severity: ticket, team: $team}
            exp_annotations:
              summary: "$svc is burning its $slo% error budget 6x too fast"
              runbook_url: "runbooks/$svc-error-budget-burn.md"
  - name: healthy service stays silent
    interval: 1m
    input_series:
      - series: '${metric}{job="$svc",code="200"}'
        values: '0+600x420'
      - series: '${metric}{job="$svc",code="500"}'
        values: '0+${healthy_err}x420'
    alert_rule_test:
      - eval_time: 7h
        alertname: ${alert}ErrorBudgetBurnFast
        exp_alerts: []
      - eval_time: 7h
        alertname: ${alert}ErrorBudgetBurnSlow
        exp_alerts: []
YAML

cat > "$runbook" <<MD
# $svc error budget burn

**Alerts:** \`${alert}ErrorBudgetBurnFast\` (page), \`${alert}ErrorBudgetBurnSlow\` (ticket)
**SLO:** $slo% of requests succeed (non-5xx) over 30 days. **Owner:** $team

## Impact
Users are getting 5xx responses faster than the SLO allows. Fast burn: at this rate the monthly budget is gone in ~2 days.

## Diagnosis
1. Error ratio by window: \`${rec}_rate5m{job="$svc"}\`, \`${rec}_rate1h{job="$svc"}\`.
2. Which endpoints/codes: \`sum by (code) (rate(${metric}{job="$svc",code=~"5.."}[5m]))\`.
3. Recent deploys or config changes (Argo CD history for $svc).
4. Dependencies: TODO — fill in for this service.

## Mitigation
- Recent deploy? Roll back first, investigate after.
- Dependency down? Fail over or shed load per the service's design.

## Follow-up
Write a blameless postmortem if more than 20% of the monthly budget was spent.
MD
echo "rendered $rules $test $runbook"
