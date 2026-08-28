# THQ ERP v4.7 Migration Order

Starting state: live backend is already at migration **100**.

| Order | Migration | Purpose |
|---|---|---|
| 101 | `101_v47_release_contract.sql` | Schema/release contract |
| 102 | `102_v47_accounting_integrity.sql` | Accounting provisioning + strict posting |
| 103 | `103_v47_idempotent_transactions.sql` | Request ledger + retry-safe sale/purchase |
| 104 | `104_v47_idempotent_operations.sql` | Retry-safe payments/returns/expenses/stock/shifts |
| 105 | `105_v47_system_installations.sql` | Logical system vs physical installation + atomic activation |
| 106 | `106_v47_inventory_atomicity.sql` | Row-locked available-stock enforcement |
| 107 | `107_v47_integrity_health.sql` | Integrity scanner/System Health backend |
| 108 | `108_v47_security_access.sql` | Fail-closed app access |
| 109 | `109_v47_release_register_verify.sql` | Release registration + object verification |
| 110 | `110_v47_runtime_hardening.sql` | Heartbeat/install history synchronization |

Use the individual files when you want precise migration tracking. `backend/THQ_ERP_V47_UPGRADE_FROM_100.sql` is provided for controlled manual execution as a convenience.
