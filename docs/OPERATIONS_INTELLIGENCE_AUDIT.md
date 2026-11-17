# THQ ERP — Operations Intelligence Comprehensive Audit & Baseline Map

**Date:** 2026-11-17  
**Branch:** `feat/gst-nongst-final-architecture`  
**Database:** `flexi-erp-dev` (`yguzrxcdvyimjrfvtcvp`)  
**Status:** Audit Completed & Baseline Verified

---

## 1. Executive Summary

This audit assesses the current state of Operations Intelligence, business analytics, risk detection, forecasting, and decision support across THQ ERP.

### Key Findings
1. **Existing Baseline Functionality:**
   - Basic operational summaries exist via `business_attention_summary_v480`, `inventory_intelligence_v480`, `customer_credit_intelligence_v480`, `supplier_payables_intelligence_v480`, and `dashboard_business_intelligence_v500`.
   - Transactional tables (`sales`, `purchases`, `location_stock_balances`, `journal_entries`, `journal_lines`, `expenses`, `customers`, `suppliers`) are robust, with authoritative GST/non-GST compliance and double-entry accounting.
2. **Current Limitations & Deficiencies:**
   - **Data Exclusions:** `inventory_intelligence_v480` joins `location_product_settings`, omitting variants that have inventory balances or sales but lack setting rows.
   - **Missing Core Engines:** There is no dedicated Financial Intelligence engine, Customer Churn/RFM engine, Supplier Quality/Risk engine, Workforce efficiency engine, or Operational velocity engine.
   - **No Automated Anomaly Detection:** Outlier discounts, void spikes, negative margin transactions, and duplicate payments are not proactively surfaced to management.
   - **No Predictive Forecasting:** Projections for demand, stockouts, reorders, and cashflow runways are currently absent or limited to naive static averages.
   - **No Scenario Simulation:** Operators cannot simulate what-if pricing adjustments, bulk purchasing economies, or credit term modifications.
   - **No Action Centre:** Insights cannot be converted into auditable, approved operational actions (PO generation, payment reminders, stock transfers) with status lifecycles.
   - **Platform Isolation:** POS Desktop, Mobile POS, and Client Mobile lack cross-platform access to intelligence insights.
   - **No Controlled AI Assistant:** No conversational, read-only AI capability exists to explain metrics or answer natural language business questions.

---

## 2. Component-by-Component Capability Audit

| Module / Capability | Classification | Current State & Evidence | Required Enhancement |
|---|---|---|---|
| **Executive Business Health** | **INCOMPLETE** | Only 1-day gross/net sales in `dashboard_business_intelligence_v500`. | Multi-period trend, composite health index, cash runway, liquidity metrics. |
| **Sales Intelligence** | **INCOMPLETE** | Top products list and hourly sales chart in v500. | Velocity, AOV, lost sales detection, peak hour heatmap, category performance. |
| **Inventory Intelligence** | **INCOMPLETE** | Reorder suggestions in v480; depends on `location_product_settings`. | Universal variant coverage, ABC Pareto analysis, Days of Inventory (DOH), dead stock capital lockup. |
| **Financial Intelligence** | **MISSING** | General ledger and reports exist, but no dedicated intelligence engine. | Gross & net margins, operating expense ratios, working capital, cash conversion cycle (CCC). |
| **Customer Credit & Intelligence** | **INCOMPLETE** | Basic aging buckets (1-30, 31-60, 61-90, 90+) in v480. | RFM customer segmentation, churn probability, credit limit velocity, advance payment reconciliation. |
| **Supplier Intelligence** | **INCOMPLETE** | `supplier_performance_v500` tracks PO vs GRN on-time %, but not integrated into main screen. | Full OTIF tracking, price variance index (PPV), defect rates, supplier concentration risk. |
| **Procurement Intelligence** | **INCOMPLETE** | Basic reorder suggestions exist. | EOQ optimization, safety stock calculations, quotation comparison matrix. |
| **Operational Efficiency** | **MISSING** | No operational velocity tracking. | Order-to-delivery cycle time, return rates, checkout speed, stock transfer transit efficiency. |
| **Workforce Intelligence** | **MISSING** | Workforce attendance exists in v630, but no operational productivity analytics. | Revenue per staff/cashier, discount concession tracking, shift throughput. |
| **Risk & Anomaly Intelligence** | **MISSING** | `audit_findings_v600` exists for transaction events, but no proactive analytics watchdog. | High discount detection, negative margin sales, abnormal stock adjustments, duplicate payment alerts. |
| **Predictive Forecasting** | **MISSING** | No time-series statistical models. | Moving averages, linear regression, seasonality indices, stockout forecasting, MAE/MAPE validation. |
| **Business Simulation** | **MISSING** | No simulation tools. | What-if pricing simulator, bulk order carrying cost simulator, credit policy simulator. |
| **Read-Only AI Assistant** | **MISSING** | No AI assistant. | Controlled, read-only API gateway for natural language questions, explanations, and summaries. |
| **Intelligence Action Centre** | **MISSING** | No insight lifecycle or action proposals. | Auditable lifecycle (`new`, `acknowledged`, `in_progress`, `resolved`), action proposal generation, human approval gates. |
| **Cross-Platform Integration** | **DISCONNECTED**| Only Client Desktop has `OperationsIntelligenceScreen`. | Shared engine in `erp_core`, reusable UI in `thq_ui`, integrations in POS and Mobile. |

---

## 3. Canonical ERP Data Lineage & Database Traceability

All intelligence calculations must derive from immutable canonical records:

| Intelligence Domain | Canonical Source Tables & Fields | Reconciliation Invariant |
|---|---|---|
| **Revenue & Sales** | `public.sales (grand_total, sale_date, status)` <br> `public.sales_returns (grand_total, refund_status)` | Net Sales = Gross Sales - Non-waived Returns. Void/cancelled sales excluded. |
| **Cost of Goods Sold (COGS)**| `public.sales (cost_total)` <br> `public.sale_items (cost_price * quantity)` | COGS matches inventory ledger depletion. |
| **Inventory Balances** | `public.location_stock_balances (quantity, average_cost)` <br> `public.stock_movements (movement_type, quantity)` | Current stock equals initial stock + inward - outward movements. |
| **Customer Receivables** | `public.sales (balance)` <br> `public.sale_payments (amount)` <br> `public.customer_advances` | Total Due matches Customer Statement (`customers_get_statement_v715`). |
| **Supplier Payables** | `public.purchases (balance)` <br> `public.purchase_invoices_v484 (balance_due)` <br> `public.purchase_payments (amount)` | Total Payable matches Supplier Statement (`suppliers_get_statement_v484`). |
| **Cash & Bank Liquidity** | `public.journal_lines (debit, credit)` for cash/bank GL accounts | Liquid funds match authoritative balance sheet. |

---

## 4. Prioritized Implementation Backlog

1. **Phase 1: Foundation Stabilization & Database Schema**
   - Migration for upgraded inventory intelligence, customer credit accuracy, and intelligence action/insight tables.
2. **Phase 2: Shared Intelligence Core (`packages/erp_core`)**
   - Standard domain models (`InsightRecord`, `ActionProposal`, `MetricSnapshot`, `FreshnessMetadata`).
   - Core orchestrator with independent collector failure handling.
3. **Phase 3: 9 Business Intelligence Engines**
   - Executive Health, Sales, Inventory, Financial, Customer, Supplier, Procurement, Operations, Workforce.
4. **Phase 4: Risk & Anomaly Intelligence Engine**
   - Automated detection of discounts, negative margins, stock loss, duplicate payments.
5. **Phase 5: Predictive Intelligence Engine**
   - Moving averages, linear regression, seasonality, stockout date projection, backtesting accuracy.
6. **Phase 6: Business Simulation & Decision Engine**
   - In-memory pricing, bulk purchasing, and credit policy simulators.
7. **Phase 7: Read-Only AI Business Assistant**
   - Controlled read-only ERP query adapter with natural language explanation capabilities.
8. **Phase 8: Intelligence Action Centre**
   - Full lifecycle management, proposal generation, human approval, idempotent execution.
9. **Phase 9: Cross-Platform UI & Application Integration**
   - Reusable UI in `thq_ui`, comprehensive workspace in `client_app`, POS and Mobile integration.
10. **Phase 10: Production Readiness & Verification**
    - Migration verification on `flexi-erp-dev`, automated tests, documentation, clean git status.
