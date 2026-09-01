-- THQ ERP v5.2 project audit safe hardening
-- Live migration already applied to flexi-erp-dev on 2026-09-01.
--
-- Purpose:
-- 1. Complete RLS coverage for all public tables.
-- 2. Remove verified byte-for-byte duplicate indexes.
--
-- No transactional/business logic changes.

alter table public.location_document_numbers
enable row level security;

drop index if exists public.idx_expenses_tenant_date_v46;

drop index if exists public.idx_restaurant_orders_ops_v489;