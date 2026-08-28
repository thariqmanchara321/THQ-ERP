# THQ ERP v4.7.1 Migration Order

Prerequisite: database already at migration **110**.

Apply exactly:

1. `111_v471_system_admin_fixes.sql`
2. `112_v471_customer_receivables.sql`
3. `113_v471_pos_operations.sql`
4. `114_v471_release_hardening.sql`

Alternatively run `backend/THQ_ERP_V471_UPGRADE_FROM_110.sql` once.

Afterwards run `backend/V471_POST_UPGRADE_CHECK.sql`. Expected backend contract: `schema_version=4.7.1`, `migration_no=114`, `minimum_app_version=4.7.1`.

Do not replay migrations 001–110 on a database that is already at 110.
