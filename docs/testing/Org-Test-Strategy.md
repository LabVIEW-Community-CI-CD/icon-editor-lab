---
Doc-ID: IELA-TST-STR-001
Issuer: QA
Status: Draft
Issue-Date: 2025-11-10
Approvals: QA Lead; Eng Manager
Change-History:
  - { date: 2025-11-10, version: 0.1, author: QA Lead, change: "Initial draft" }
Scope: Icon-Editor-Lab — Testing
References: IELA-SRS; IELA-RTM; ISO/IEC/IEEE 29119-1; ISO/IEC/IEEE 29119-3; ISO 10007
---

# Organizational Test Strategy

**Levels:** unit → integration → system → acceptance.  
**Techniques:** property/golden, contract/round-trip, E2E user-journeys, fuzz for parsers.  
**Entry/Exit:** defined per level; prod-mode pass required for release.  
**Measures:** coverage (line/branch), pass-rate, defect trends, MTTR, flake-rate.  
**Defect Management:** severity SLA; incident template; root-cause tagging.  
**Reporting Cadence:** weekly status; completion per tag.
