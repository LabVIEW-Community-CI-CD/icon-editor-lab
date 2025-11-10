---
Doc-ID: IELA-TST-PLN-001
Issuer: QA
Status: Draft
Issue-Date: 2025-11-10
Approvals: QA Lead; Eng Manager
Change-History:
  - { date: 2025-11-10, version: 0.1, author: QA Lead, change: "Initial draft" }
Scope: Icon-Editor-Lab — Testing
References: IELA-SRS; IELA-RTM; ISO/IEC/IEEE 29119-1; ISO/IEC/IEEE 29119-3; ISO 10007
---

# Project Test Plan

## Context & Objectives
Scope: icon-editor-lab; in-scope features per SRS; out-of-scope listed here.

## Assumptions & Constraints
LabVIEW/VIPM available in CI; air-gapped agents supported; prod/dev mode toggles.

## Stakeholders & Communication
QA Lead (owner), Sec Lead, Core Lead, Build Lead; weekly standup; release reviews.

## Strategy (Risk-Based)
Prioritize high-exposure risks; map to cases; enforce CI gates.

## Risk Register
| ID | Description | Prob | Impact | Exposure | Mitigation | Owner |
|---|---|---|---|---|---|---|
| R-001 | Dev mode shipped in prod | M | H | H | Mode gate + E2E prod checks | QA Lead |
| R-002 | Unsafe SVG accepted | L | H | M | Sanitizer + fuzz + unit policy tests | Sec Lead |
| R-003 | Path traversal on export | L | H | M | safe_export + integration tests | Core Lead |
| R-004 | VIPM dep drift | M | M | M | lockfile + SBOM scan | Build Lead |
| R-005 | History not idempotent | M | M | M | unit/integration undo/redo tests | Core Lead |


## Test Items & Features
Parser/Serializer; History; IO export; VIPM packaging; VI diff/history reporting.

## Entry/Exit Criteria
Entry: env/data ready; dev branch green. Exit: pass-rate ≥95%, zero high-sev incidents, gates green.

## Schedule & Resources
Milestones per sprint; CI agents listed in Env Ready; staff per roles above.

## Deliverables
Status reports, completion report, execution logs, incidents, evidence artifacts.
