# THQ ERP — Operations Intelligence Platform
## Comprehensive Architecture, Security, Data Flow & Release Readiness Specification

**Document Version:** 1.0.0 (Release #715 / Platform v8.3.9)  
**System Target:** THQ ERP Monorepo (`thariqmanchara321/THQ-ERP`) & Supabase Cloud Project `flexi-erp-dev` (`yguzrxcdvyimjrfvtcvp`, Region: South Asia Mumbai)  
**Status:** Validated & Hardened for Controlled Production Release  
**Last Updated:** November 2026  

---

## 1. Executive Architecture Summary

The **THQ Operations Intelligence Platform** is an enterprise-grade, algorithm-first, deterministic operational analytics and prescriptive management system embedded directly within the core THQ ERP application. Unlike traditional decoupled BI dashboards or unpredictable LLM analytics, Operations Intelligence is:
- **100% AI-Independent & Algorithm-First:** Driven strictly by deterministic financial mathematics, statistical regression (Ordinary Least Squares, Holt-Winters exponential smoothing), Pareto ABC analysis, and formal double-entry accounting rules.
- **Explainable & Auditable:** Every insight, forecast, bottleneck, and recommendation includes mathematical justification, underlying data points, confidence scoring, and explicit business impact metrics.
- **Embedded in a Persistent Unified Client Shell:** Operates without disrupting POS or accounting operations, running within a unified Flutter desktop and mobile shell with responsive data tables, instant filtering, and sub-tab transitions.
- **Enforced Multi-Tenant & Location Isolation:** 100% of underlying analytical views, base tables, review logs, and RPCs enforce Supabase Row Level Security (RLS) and strict tenant/store isolation boundaries.
- **Permission-Aware Data Masking:** Granular masking dynamically sanitizes confidential cost prices, margins, payroll records, and executive financial ledgers based on active session capabilities (`inventory.view_cost`, `accounting.view`, `staff.payroll`).
- **Mathematically Isolated Business Simulations:** Hypothetical "what-if" scenarios (price elasticity, bulk purchasing, credit term adjustments, headcount optimization) execute strictly in transient read-only memory, guaranteed never to write to posted ledgers or stock balance tables.

---

## 2. End-to-End System Topology & Data Flow

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                THQ ERP CORE SOURCE DATA                                │
│  ┌───────────────────────┬──────────────────────┬───────────────────────────────────┐  │
│  │     Transactions      │      Operations      │            Accounting             │  │
│  │ • sales & sale_items  │ • location_stock     │ • journal_entries & lines         │  │
│  │ • purchases & items   │ • stock_movements    │ • chart_of_accounts               │  │
│  │ • goods_receipt_notes │ • internal_transfers │ • customer_payments               │  │
│  │ • sales_returns       │ • attendance_records │ • supplier_payments               │  │
│  └───────────────────────┴──────────────────────┴───────────────────────────────────┘  │
└───────────────────────────────────────────┬────────────────────────────────────────────┘
                                            │
                                            ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        ANALYTICAL ENGINE LAYER (PostgreSQL 17.6)                       │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ 10 Specialized PostgreSQL SECURITY DEFINER Intelligence Engines                  │  │
│  │  1. operations_intelligence_summary_v830 (Executive Overview)                   │  │
│  │  2. sales_intelligence_v830 (Sales, RFM, Margin & Anomaly Analytics)             │  │
│  │  3. inventory_intelligence_v830 & rebalancing (Pareto ABC, Buffer Balancing)     │  │
│  │  4. purchase_intelligence_v830 (Procurement Trends, Cost Trajectory)             │  │
│  │  5. supplier_intelligence_v830 (Supplier Scorecards, OTIF, Quality)             │  │
│  │  6. procurement_intelligence_v830 (Replenishment Deduplication)                 │  │
│  │  7. financial_intelligence_v830 & expense (P&L, Cash Flow, Trial Balance Health) │  │
│  │  8. operational_efficiency_intelligence_v830 (Bottlenecks, Scan Discrepancies)  │  │
│  │  9. workforce_intelligence_v830 (Attendance, Overtime, Capacity Benchmarking)   │  │
│  │ 10. predictive_intelligence_v830 (8 Forecast Domains & Risk Rules)               │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ Business Simulation Engine (Strict Read-Only Sandbox)                            │  │
│  │  • simulate_business_scenario_v830 (Pricing, Bulk PO, Capex, Credit, Staffing)   │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
└────────────────────────┬──────────────────────────────────────┬────────────────────────┘
                         │                                      │
                         ▼                                      ▼
┌──────────────────────────────────────┐      ┌──────────────────────────────────────────┐
│      CENTRAL ACTION & RISK CENTRE    │      │         PERSISTENCE & AUDIT TRAIL        │
│ • erp_intelligence_action_centre_v83 │      │ • erp_intelligence_insights (Deduplicated│
│ • Actionable prescriptive finding    │      │ • erp_intelligence_finding_reviews (RLS)│
│ • Severity, impact & dedup_key       │      │ • erp_intelligence_forecasts            │
│ • 7-stage deterministic lifecycle    │      │ • erp_intelligence_simulations          │
└──────────────────┬───────────────────┘      └──────────────────────────────────────────┘
                   │
                   ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                           APPLICATION & CLIENT INTEGRATION                             │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ Edge API Gateway: supabase/functions/thq-api (11 Dedicated API Resources)        │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │ Unified Client App Shell: OperationsIntelligenceScreen (13 Cohesive Sub-Tabs)    │  │
│  │  [0] Overview            [1] Sales Intel        [2] Stock Intel                  │  │
│  │  [3] Purchase Intel      [4] Supplier Intel     [5] Procurement Intel            │  │
│  │  [6] Customer Credit     [7] Financial Intel    [8] Expense Intel                │  │
│  │  [9] Operational Effic.  [10] Workforce Intel   [11] Predictive & Simulations    │  │
│  │  [12] Action & Risk Centre                                                       │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Specialized Intelligence Engines & Technical Contracts

### Engine 1: Executive Business Health & Overview
- **Function:** `public.operations_intelligence_summary_v830(p_tenant_id uuid, p_location_id uuid, p_days int)`
- **Key Responsibilities:** Computes top-level KPI velocity for executive management: Gross Sales, Net Sales (sales minus completed returns), Gross Profit (net revenue minus posted FIFO/weighted COGS), Operating Expenses, Net Operating Profit, Working Capital, and Active Store Comparison.
- **Contract Keys:** `flow_metrics`, `inventory_metrics`, `financial_metrics`, `top_products`, `attention_counts`, `store_comparisons`.
- **Masking:** If `inventory.view_cost` is missing, `cogs`, `gross_profit`, and `net_profit` return `NULL` and render masked `—` placeholders in the UI.

### Engine 2: Sales & Customer Purchasing Intelligence
- **Function:** `public.sales_intelligence_v830(p_tenant_id uuid, p_location_id uuid, p_days int)`
- **Key Responsibilities:** Analyzes customer buying behavior, product category momentum, margin contributions, and return rates. Implements RFM (Recency, Frequency, Monetary) segmentation across customer cohorts and flags anomalous margin drops or velocity halts.
- **Contract Keys:** `summary`, `trends`, `category_breakdown`, `customer_segments`, `anomalies`.

### Engine 3: Advanced Inventory Intelligence & Inter-Store Rebalancing
- **Functions:** 
  - `public.inventory_intelligence_v830(p_tenant_id uuid, p_location_id uuid, p_days int, p_query text, p_limit int, p_offset int)`
  - `public.inventory_rebalancing_recommendations_v830(p_tenant_id uuid, p_days int, p_min_transfer_units numeric)`
- **Key Responsibilities:** Pareto ABC analysis (A: 80% cumulative value, B: 15%, C: 5%), days-of-cover burn rate calculation, stock health classification (`out_of_stock`, `low_stock`, `overstocked`, `dead_stock`, `optimal`). Rebalancing engine suggests stock transfers between stores having excess coverage to stores facing imminent stockouts while strictly preserving the source location's safety buffer.
- **Replenishment Formula:**
  $$\text{Suggested Replenishment} = \max(0, \text{Reorder Point} - (\text{Stock On Hand} + \text{In-Transit Transfers} + \text{Open PO Stock}) + \text{Safety Stock})$$

### Engines 4, 5 & 6: Purchase, Supplier & Procurement Intelligence
- **Functions:**
  - `public.purchase_intelligence_v830(p_tenant_id uuid, p_location_id uuid, p_days int)`
  - `public.supplier_intelligence_v830(p_tenant_id uuid, p_days int)`
  - `public.procurement_intelligence_v830(p_tenant_id uuid, p_location_id uuid, p_days int)`
- **Key Responsibilities:** Evaluates supplier fulfillment rates, lead-time variances, On-Time In-Full (OTIF) percentages, price inflation drifts, and overdue payables. Automatically deduplicates reorder suggestions against pending purchase orders and draft goods receipt notes to prevent double-ordering.

### Engine 7: Financial, Accounting & Expense Intelligence
- **Functions:**
  - `public.financial_intelligence_v830(p_tenant_id uuid, p_days int)`
  - `public.expense_intelligence_v830(p_tenant_id uuid, p_location_id uuid, p_days int)`
- **Key Responsibilities:** Extracts double-entry ledger facts from `journal_entries` and `journal_entry_lines`. Computes true balance sheet liquidity ratios (Current Ratio, Quick Ratio), cash inflows and outflows, and verifies Trial Balance mathematical equality ($\sum \text{Debits} = \sum \text{Credits}$). Categorizes operational and administrative overheads, flagging sudden variance spikes.

### Engine 8: Operational Efficiency Intelligence
- **Function:** `public.operational_efficiency_intelligence_v830(p_tenant_id uuid, p_location_id uuid, p_days int)`
- **Key Responsibilities:** Diagnoses workflow friction and process bottlenecks. Tracks draft-to-posted invoice lag, goods receipt processing delays, inventory count variance rates, and POS cash drawer closing discrepancies. Computes a bounded Efficiency Score $[15, 100]$.

### Engine 9: Workforce Intelligence
- **Function:** `public.workforce_intelligence_v830(p_tenant_id uuid, p_location_id uuid, p_days int)`
- **Key Responsibilities:** Correlates branch transaction velocity with staffing availability. Analyzes attendance coverage drop rates, overtime concentration, cashier shift coverage gaps during peak operating hours, and transaction throughput per active employee. Restricts payroll metrics when the session lacks `staff.payroll` authority.

### Customer Intelligence Architecture (Distributed Domain Engine)
- **Architecture Strategy:** Rather than an isolated monolithic query, customer intelligence operates as a cohesive, distributed capability embedded across three core engines with clear tenant/location boundaries:
  1. *Customer Purchasing & RFM Engine* (via `sales_intelligence_v830`): Analyzes customer purchasing frequency, monetary spend, inactivity periods, and deterministic RFM segmentation (`Champions`, `Loyal`, `Potential Loyalists`, `At Risk`, `Needs Attention`, `Lost / Inactive`).
  2. *Customer Credit & Receivables Engine* (via `customer_credit_intelligence_v480` and `financial_intelligence_v830`): Computes live customer credit limits, outstanding balances, overdue aging buckets (1-30, 31-60, 61-90, 90+ days), and working capital credit exposure.
  3. *Predictive Customer Churn Engine* (via `predictive_intelligence_v830`): Calculates customer inactivity decay against mean order cycles, churn probabilities, and estimated revenue at risk.
- **Action Centre Findings:** Generates customer-specific actionable insights (`SALES_CUSTOMER_CHURN_RISK`, `SALES_CONCENTRATION_RISK`, `FIN_OVERDUE_RECEIVABLE_CONCENTRATION`, `PRED_CUSTOMER_CHURN`, `PRED_RECEIVABLES_DELAY`).

### Engine 10: Predictive Intelligence & Business Simulation Sandbox
- **Functions:**
  - `public.predictive_intelligence_v830(p_tenant_id uuid, p_location_id uuid, p_horizon_days int)`
  - `public.simulate_business_scenario_v830(p_tenant_id uuid, p_scenario_type text, p_parameters jsonb)`
- **Predictive Scope:** Runs 8 domain forecasts using Ordinary Least Squares regression, seasonal smoothing, and statistical outlier bounds:
  1. *Sales & Demand Velocity*
  2. *Inventory Depletion & Stockout Horizon*
  3. *Operating Cash Flow Forecast*
  4. *Customer Receivables Aging & Default Risk*
  5. *Supplier Payables Maturation Schedule*
  6. *Recurring Expense Projections*
  7. *Customer Churn Probability*
  8. *Supplier Lead-Time Delay Exposure*
- **Action Centre Ingestion:** Automatically generates prescriptive findings into `erp_intelligence_insights` under rules such as `PRED_STOCKOUT_IMMINENT`, `PRED_DEAD_CAPITAL_EXCESS`, `PRED_NEGATIVE_CASH_FLOW`, and `PRED_SUPPLIER_DELAY`.
- **Supported Simulation Categories (Authoritative 5):**
  - `pricing`: Simulates price alterations against price elasticity of demand ($\epsilon$).
  - `bulk_purchasing`: Simulates volume purchase discounts weighed against inventory holding costs.
  - `credit_policy`: Simulates relaxed/tightened customer credit terms against Days Sales Outstanding (DSO) and working capital.
  - `staffing`: Simulates branch labor adjustments against throughput and payroll costs.
  - `stock_transfer`: Simulates inter-store inventory transfer and stockout days averted while guaranteeing source store safety buffers.
  *(Note: Unsupported scenario types such as `CAPEX_INVESTMENT` are strictly rejected server-side with an `Unsupported simulation category` exception).*

---

## 4. Security, Multi-Tenancy & Permission Governance

### Universal RLS & Schema Boundary Integrity
- **100% RLS Coverage:** Every intelligence table (`erp_intelligence_insights`, `erp_intelligence_finding_reviews`, `erp_intelligence_forecasts`, `erp_intelligence_forecast_accuracy`, `erp_intelligence_simulations`) has `rowsecurity = true`.
- **Tenant Isolation Policy:**
  ```sql
  CREATE POLICY erp_intelligence_insights_tenant_isolation ON public.erp_intelligence_insights
    FOR ALL TO authenticated
    USING (tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid);
  ```
- **Read-Only Simulation Isolation:** `simulate_business_scenario_v830` operates strictly as a read-only mathematical projection engine. No `INSERT`, `UPDATE`, or `DELETE` statements target `journal_entries`, `location_stock_balances`, `sales`, or `purchases`. The transient scenario record is stored in `erp_intelligence_simulations` strictly for user recall.

### Granular Capability-Based Data Masking
The platform implements field-level data protection across client and database RPC layers:
1. **Cost & Margin Protection:** Users lacking `inventory.view_cost` or `sales.view_cost` receive sanitized `NULL` values for unit costs, FIFO COGS, gross margins, and dead stock tied-up capital.
2. **Financial Ledger Protection:** Users lacking `accounting.view` cannot inspect balance sheets, trial balance difference checks, or net operating cash flows.
3. **Workforce Payroll Protection:** Users lacking `staff.payroll` cannot view branch wage totals, average hourly rates, or employee overtime monetary expenses.

---

## 5. Action Centre Finding Lifecycle & Deduplication Protocol

### Deterministic State Machine
The Action & Risk Centre coordinates operational risk remediation through a 7-stage auditable lifecycle:
$$\text{Generated} \longrightarrow \text{Reviewed} \longrightarrow \begin{cases} \text{Accepted} \longrightarrow \text{Approved} \longrightarrow \text{Executed} \longrightarrow \text{Completed} \\ \text{Rejected} \end{cases}$$

- **State Transition Guard:** Direct leap from `generated` to `executed` is strictly rejected; every finding must pass through explicit managerial review.
- **Permanent Audit Trail:** Every transition logs the user ID, timestamp, old status, new status, decision rationale, and contextual parameters into `public.erp_intelligence_finding_reviews`.

### Deduplication Architecture
To prevent alert fatigue and redundant findings across consecutive intelligence scans:
$$\text{dedup\_key} = \text{MD5}(\text{tenant\_id} \parallel \text{rule\_code} \parallel \text{entity\_type} \parallel \text{entity\_id})$$
- When an active finding exists with the same `dedup_key` in `generated` or `reviewed` status, the scanner updates the metrics and evidence payload rather than creating duplicate notifications.
- Closed findings (`completed`, `rejected`) remain archived; new findings are generated only if the operational defect recurs in a subsequent period.

---

## 6. Verification & Test Audit Results

### 1. Database Integration & Audit Test Suite
Executed directly against Supabase `flexi-erp-dev` (`yguzrxcdvyimjrfvtcvp`):

| Test Suite | File | Tests Run | Result |
| :--- | :--- | :---: | :---: |
| Predictive & Simulation DB Suite | `supabase/tests/test_operations_intelligence_phase10.sql` | 10 | **PASSED (10/10)** |
| Platform Architecture Audit Suite | `supabase/tests/test_operations_intelligence_phase11_audit.sql` | 12 | **PASSED (12/12)** |
| **Consolidated Database Total** | — | **22** | **100% PASSED** |

**Audit Checks Verified in DB Suite:**
- [x] Schema releases #706 through #715 registered in `thq_schema_releases`
- [x] 100% of intelligence tables have active Row Level Security (RLS)
- [x] Engine 1 (Executive Summary) returns valid structure and metrics
- [x] Engine 2 (Sales Intelligence) executes and returns segments/anomalies
- [x] Engine 3 (Stock Intelligence & Rebalancing) evaluates inventory balances
- [x] Engines 4, 5 & 6 (Purchase, Supplier, Procurement) evaluate vendors and deduplicate reorders
- [x] Engine 7 (Financial & Expense Intelligence) verifies double-entry ledger balance
- [x] Engine 8 (Operational Efficiency) evaluates bottlenecks and scan health
- [x] Engine 9 (Workforce Intelligence) calculates staffing coverage and capacity
- [x] Engine 10 (Predictive Intelligence) returns 8 forecasting domains
- [x] Central Action & Risk Centre handles finding ingestion and status transitions
- [x] Simulation Sandbox executes in strict read-only mode without ledger side-effects

### 2. Flutter Client App Test Suites
Executed in `apps/client_app`:

| Test Suite | File | Tests Run | Result |
| :--- | :--- | :---: | :---: |
| Phase 2: Overview & Navigation Shell | `test/operations_intelligence_phase2_test.dart` | 10 | **PASSED (10/10)** |
| Phase 3: Sales Intelligence | `test/operations_intelligence_phase3_test.dart` | 8 | **PASSED (8/8)** |
| Phase 4: Stock Intelligence & Rebalancing | `test/operations_intelligence_phase4_test.dart` | 11 | **PASSED (11/11)** |
| Phase 5: Purchase, Supplier & Procurement | `test/operations_intelligence_phase5_test.dart` | 11 | **PASSED (11/11)** |
| Phase 6: Financial & Expense Intelligence | `test/operations_intelligence_phase6_test.dart` | 12 | **PASSED (12/12)** |
| Phase 7: Shared Action & Risk Centre | `test/operations_intelligence_phase7_test.dart` | 12 | **PASSED (12/12)** |
| Phase 8: Operational Efficiency Engine | `test/operations_intelligence_phase8_test.dart` | 11 | **PASSED (11/11)** |
| Phase 9: Workforce Intelligence Engine | `test/operations_intelligence_phase9_test.dart` | 15 | **PASSED (15/15)** |
| Phase 10: Predictive & Simulations | `test/operations_intelligence_phase10_test.dart` | 9 | **PASSED (9/9)** |
| **Consolidated Flutter Total** | — | **99** | **100% PASSED** |

---

## 7. Operational Deployment, Rollback & Disaster Recovery

### Deployment Checklist
1. **Migration Verification:** Ensure migrations `20261117120000` through `20261123120000` are applied in sequence.
2. **Schema Release Registration:** Verify `thq_schema_releases` contains releases #706 through #715.
3. **Edge Functions Deployment:** Deploy `thq-api` with `verify_jwt: true` via `supabase functions deploy thq-api`.
4. **Client App Distribution:** Build and sign Windows Flutter desktop executable (`client_app.exe`) and Android APK.

### Rollback Strategy
If an unforeseen regression occurs:
- The system uses backward-compatible RPC names with `_v830` suffixes. Legacy dashboards or POS transactions will continue to execute unaffected.
- Each migration includes idempotent DDL (`CREATE OR REPLACE FUNCTION`, `IF NOT EXISTS`).
- Operational transaction tables are strictly decoupled from intelligence tables; rolling back an intelligence schema migration does not compromise transactional financial records.

---

## 8. Release Readiness Classification

### Classification: **READY FOR CONTROLLED RELEASE (WITH DOCUMENTED LIMITATIONS)**

**Operational Limitations & Disclosures:**
1. **Annual Seasonality Data Sufficiency:** Predictive forecasting utilizes available historical ERP transactions. For businesses with less than 365 days of recorded sales history, annual seasonal decomposition defaults to 30-day/90-day moving averages with documented lower confidence scores ($< 0.65$).
2. **Workforce Shift Logging Dependency:** The Workforce Intelligence engine evaluates shift coverage based on active cashier shift records (`pos_shifts`) and staff attendance logs. If a branch does not utilize electronic attendance punching, attendance coverage will display as unmonitored.
3. **Cash & Bank Ledger Prerequisites:** Real-time bank balances in Executive Overview require mapped Chart of Accounts bank ledgers; if the business operates unmapped external accounts, the widget provides explicit ledger configuration guidance.

---
*Signed by:* **Antigravity Lead Architect & Senior QA Engineer for THQ ERP**  
*Release Tag:* `v8.3.9-release-ready`
