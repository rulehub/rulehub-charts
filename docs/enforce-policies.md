# Kyverno Enforce Policies Overview

The policies below use `validationFailureAction: enforce` and include short rationales for applying strict mode.

| Policy (file) | Rule(s) key idea | Rationale (why enforce) | Potential Risk of False Positives | Mitigation |
|---------------|------------------|-----------------------------|-----------------------------------|------------|
| `block-hostpath` | Deny `hostPath` volumes | hostPath gives direct node access -> risk of privilege escalation / isolation bypass | Low (rarely required in production for normal workloads) | Allowlist or disable via values for specific namespaces, or provide an override policy |
| `disallow-latest` | Deny image tags `:latest` | Ensures reproducibility and avoids version drift on pull; helps incident investigation | Medium (some dev environments rely on `:latest`) | Allow selective disabling in dev via values override |
| `no-privileged` | Deny `securityContext.privileged=true` | Privileged containers significantly increase attack surface | Low (privilege should be rare and explicitly documented) | Allow exceptions via dedicated namespaces or label-matching policies |
| `require-resources` | Require CPU/Memory requests and limits | Capacity planning, QoS stability, prevents resource hogging | Medium (older manifests may lack limits) | Gradual rollout: start with audit mode, then move to enforce after a remediation window |

## Additional comments

1. All four policies have `background: true` enabled to ensure retrospective checks of existing objects.
2. Typical hardening sequence is: audit -> enforce. This assumes auditing has already been performed and metrics show a low violation rate.
3. To mitigate operational risk, document any exceptions (allowlist namespaces) before switching to enforce.

## Recommended rationale template

```yaml
validationFailureAction: enforce  # rationale: <brief risk summary, e.g. privilege escalation / drift / resource abuse>
```

You may add an automated check that ensures a rationale comment exists for all enforce policies (see the task in Schema & Validation).
