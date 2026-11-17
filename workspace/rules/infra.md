---
paths:
  - "**/*.{tf,tfvars,hcl}"
---

# infra.md

## Scope

- All infrastructure as code with Terraform. NEVER create or change cloud resources manually.
- Every delivery that needs infra, except the exemptions in `rules/rules.md` "Workspace layout", MUST include one root module, on the cloud and in the tenant the custom layer names (`rules/rules.md` "Custom layer"). None named: ask. NEVER add a module for another cloud.
- The module is sized per "Sizing".
- Read-only cloud access by default: NEVER let a cloud CLI install an extension or plugin on its own, because the human authorizes reading only.

## Sizing

Start with the smallest infra that runs the delivery, built so that it scales when the load grows.

- Never ask the human for volume, availability, latency or a budget, and never invent those numbers. A number the request gives (a volume, a deadline, an availability target, a budget ceiling) is a requirement: size for it and say so.
- Smallest: the lowest tier or SKU that runs the function; a consumption or scale-to-zero plan where the service has one; one region and one instance; no redundancy beyond what the platform gives by default; a serverless or shared database tier before a provisioned one.
- Scalable: nothing in the design blocks growth. Stateless compute, with state only in managed services; tiers that can be raised in place, with no resource recreated and no data migrated; autoscale rules declared from the start, with a low ceiling; every limit (tier, instance count, storage) a Terraform variable, so scaling is a value change, never a redesign.
- Never provision for a load nobody measured.
- Say when to scale. `docs/` records the initial size and its monthly cost, the signal that it is time to grow (a metric and a threshold, e.g. CPU above 70% for 10 minutes, queue age, p95 latency), and the next step with its cost.
- Before the first apply that creates a billable resource: tell the human the monthly estimate of the initial size.
- What is stored and for how long, and how personal data is shown, are not sizing: they come from the request.

## Cost estimate (in `docs/`)

- MUST state: monthly estimate (USD; BRL if budget is in BRL), region, pricing date, method, assumptions (usage volume, hours, storage, egress).
- Method MUST be reproducible: official pricing calculator or pricing API, or a cost-estimation tool run against the Terraform plan. Name it and keep the inputs.
- Include free tier only when it applies to the stated volume; list it separately.
- MUST compare the viable options of the cloud for the initial size and end with the cheapest and why; add the cost of the next step up ("Sizing").

## Terraform quality

- Pin Terraform and provider versions; commit `.terraform.lock.hcl`.
- `terraform fmt -check` and `terraform validate` MUST pass.
- Run an IaC security scanner in CI; fix or justify every high finding.
- Remote state with encryption and locking. Mark secret values `sensitive`; PREFER ephemeral resources / write-only arguments so secrets never reach state.
- Least privilege for every role and identity (see `rules/security.md`).
- Inputs via typed, validated variables with descriptions; no hard-coded environment values.
- Tag/label every resource with project, environment, owner, cost center.
