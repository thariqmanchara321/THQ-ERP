# Change product tracking in the production ERP

The production database update `tracking_policy_conversion_v633` was applied on 4 October 2026. No product was converted automatically. M-SAND 1st remains batch tracked with 600 stock and average cost 17.50.

## Install the app update

Use the production source folder, usually `D:\ERP\flexi_erp`. Close running development instances. Extract `THQ_TRACKING_MAIN_UPDATE.zip` in Downloads and run its `APPLY_THQ_TRACKING_UPDATE.ps1` with `-RepoPath` pointing to your production source. The script checks the complete patch before applying it and backs up the files it changes. It preserves the current branch and other edits. If a conflict is reported, stop and send the output.

Run `tools\tracking_update\VERIFY_THQ_TRACKING_UPDATE.ps1 -RepoPath D:\ERP\flexi_erp`. It checks the shared package, Client, POS and Mobile POS, runs their tests, and builds the Windows Client and POS. Add `-BuildMobileApk` if you use Mobile POS and need its updated APK. This does not publish an installer or push Git changes.

Flutter is unavailable in the preparation workspace, so the Flutter analyzer, tests and Windows builds must be completed on your computer. SQL checks and Dart syntax checks passed during preparation. The database migration is already installed; do not paste SQL or run all old migrations.

## Change a method

1. Update every POS and Mobile POS app you use, sync pending invoices, and pause posting while you change the method.
2. Open the product's **Tracking Policy** in Inventory. Select **No serial / batch tracking**, **Serial tracking**, or **Batch tracking**.
3. Click **Change Tracking Method**. The preview lists stock at every branch and any issues that must be resolved first.
4. For serial tracking, enter one unique serial per whole base unit at every branch. Fractional stock cannot use serial tracking. For batch tracking, enter new batch numbers and quantities totalling each branch's stock. Use `BATCH=QUANTITY|YYYY-MM-DD` if an expiry is required. The quantity uses the product's base unit.
5. Give a reason, confirm devices have synced, and click **Confirm Conversion**.
6. Refresh catalogues on all devices before billing again. A stale offline invoice is held for review; it is not silently posted under a different method.

For M-SAND 1st, choose **No serial / batch tracking**, give a reason such as `Stop batch tracking for loose sand`, confirm syncing and complete the conversion. No new serial or batch allocation is needed for this choice.

Stock quantity, average cost and financial journals remain intact. Existing invoice traces and warranties stay linked to their original invoices. Returns ask for the original invoice allocation and, where necessary, the current stock allocation. You must identify the goods physically being returned; changing tracking cannot reconstruct an identity that was never recorded.

Switching to no tracking stops batch expiry checks and automatic tracking warranties for new transactions. Existing warranties continue until their own expiry or a return. Re-enabling a method is another reviewed conversion and starts a new tracking revision.

## Checks completed

Twenty-one tracking database checks passed after deployment, covering all tracking modes, multiple branches, fractional batches, conversion retry identity, stale/offline guards, returns across multiple conversions, original warranties, balanced accounting, permissions and atomic rollback. Twenty-two existing GST/invoice checks also passed. Synthetic fixture records were rolled back. New private tables use RLS and are inaccessible directly to anonymous and authenticated clients; only permission-checked public RPCs are exposed.

## Source and recovery

The patch was prepared against production checkpoint `4cde462`, on `fix/tracking-conversion-20261004`. Applying it does not switch your branch, commit, push or deploy apps. Review `git diff` after verification and commit using your normal production workflow.

The application backup folder contains copies of the touched original files and lists newly added paths. Restoring these application files does not undo the database migration or a product conversion. To change a product back, use another reviewed conversion after syncing devices; do not delete audit or trace history.
