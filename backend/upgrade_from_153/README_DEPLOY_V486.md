# THQ ERP v4.8.6 database upgrade (153 → 160)

1. Confirm the current database is THQ ERP v4.8.5 / migration 153.
2. Back up the database.
3. Run `THQ_ERP_V486_UPGRADE_FROM_153.sql` once.
4. Deploy both `thq-api` Edge Function copies using your normal Supabase deployment process.
5. Run `V486_POST_UPGRADE_CHECK.sql`. The release verifier must report `ready: true`, schema `4.8.6`, migration `160`.

Do not replay migrations 001–153 on an existing v4.8.5 database.
