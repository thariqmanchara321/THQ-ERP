# THQ ERP v4.8.6 — Offline POS Architecture

v4.8.6 makes POS checkout local-first. The POS writes the invoice and local stock/serial reservations to SQLite before attempting server synchronization. The local queue owns the exact request UUID until the server confirms it.

## Local database & Encryption at Rest

`thq_pos_offline_v486.sqlite` is stored under the operating system application-support directory. WAL mode and `synchronous=FULL` are enabled. It stores cached products, customers, available serials, metadata/printer/shift snapshots, and the offline invoice queue.

As of Phase 12.4 (`SEC-P2-02`), the local SQLite database is encrypted at rest using **SQLCipher 4.17.0 (AES-256 page-level encryption)** with keys protected by Windows DPAPI. Pre-existing plaintext databases are automatically migrated to encrypted format with zero data loss, preserving pending synchronization queues and retaining a protected recovery backup. Full architecture details are documented in [pos_offline_database_encryption.md](file:///D:/ERP/flexi_erp/docs/security/pos_offline_database_encryption.md).

## Sync lifecycle

`pending → syncing → synced` is the normal flow. Transport failures return to `pending`. Server validation issues become `conflict`. Conflicts can be retried after correction or cancelled locally if they were never posted. Successful requests use the same request UUID through `pos_offline_sale_sync_v486` and `sales_create_v483`, preserving the existing v4.7 idempotency contract.

## Conflict policy

Offline invoices are never silently repriced. Current authoritative price/tax values are compared before server posting. Stock, serial, and batch failures are surfaced as conflicts. Batch sales continue to use server FEFO when synchronized.

## Cache safety

The product cache exposes true available stock after reserved/damaged/quarantine deductions. Pending/conflicted local invoices are re-reserved after every online catalogue refresh. Available serials are paged and locally reserved by queued invoices.
