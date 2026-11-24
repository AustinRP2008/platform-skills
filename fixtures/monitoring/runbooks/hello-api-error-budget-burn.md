# hello-api error budget burn

**Alerts:** `HelloApiErrorBudgetBurnFast` (page), `HelloApiErrorBudgetBurnSlow` (ticket)
**SLO:** 99.9% of requests succeed (non-5xx) over 30 days. **Owner:** platform

## Impact
Users are getting 5xx responses faster than the SLO allows. Fast burn: at this rate the monthly budget is gone in ~2 days.

## Diagnosis
1. Error ratio by window: `job:http_requests:error_ratio_rate5m{job="hello-api"}`, `job:http_requests:error_ratio_rate1h{job="hello-api"}`.
2. Which endpoints/codes: `sum by (code) (rate(http_requests_total{job="hello-api",code=~"5.."}[5m]))`.
3. Recent deploys or config changes (Argo CD history for hello-api).
4. Dependencies: TODO — fill in for this service.

## Mitigation
- Recent deploy? Roll back first, investigate after.
- Dependency down? Fail over or shed load per the service's design.

## Follow-up
Write a blameless postmortem if more than 20% of the monthly budget was spent.
