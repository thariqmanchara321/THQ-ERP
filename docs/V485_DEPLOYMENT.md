# v4.8.5 deployment

1. Confirm production is on v4.8.4 / migration 146.
2. Back up the database.
3. Apply `backend/THQ_ERP_V485_UPGRADE_FROM_146.sql`.
4. Run `backend/V485_POST_UPGRADE_CHECK.sql` and confirm `ready=true`, migration 153.
5. Redeploy `thq-api` from this release.
6. Deploy Client/POS/Admin 4.8.5+13 builds.
7. Refresh application sessions/configuration.
8. Acceptance-test one untracked transfer, one serial transfer, one batch transfer, and one stock count before broad rollout.
