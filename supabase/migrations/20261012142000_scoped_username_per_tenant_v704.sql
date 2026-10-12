-- Migration: 20261012142000_scoped_username_per_tenant_v704.sql
-- Scope user login names per tenant so different businesses can have users with the same username.

-- 1. Add tenant_id column to user_login_names if not exists
ALTER TABLE public.user_login_names 
  ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES public.tenants(id) ON DELETE CASCADE;

-- 2. Populate tenant_id for existing rows from tenant_memberships
UPDATE public.user_login_names u
SET tenant_id = m.tenant_id
FROM (
  SELECT user_id, tenant_id 
  FROM public.tenant_memberships 
  WHERE status = 'active'
) m
WHERE u.user_id = m.user_id AND u.tenant_id IS NULL;

-- 3. Drop global unique constraint on username if exists
ALTER TABLE public.user_login_names 
  DROP CONSTRAINT IF EXISTS user_login_names_username_key;

-- 4. Create unique index on (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(username))
CREATE UNIQUE INDEX IF NOT EXISTS user_login_names_tenant_username_idx 
  ON public.user_login_names (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(username));
