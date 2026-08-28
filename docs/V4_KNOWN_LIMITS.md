# Flexi ERP V4 Known Limits / Honest Boundaries

V4 is intentionally broad, but it does not claim every item in the long-term roadmap is production complete.

1. **Offline:** POS is still primarily an online transaction system. A complete durable offline transaction queue/conflict resolver is not included.
2. **Backup restore:** V4 exports a comprehensive JSON business backup. Automatic destructive restore is not provided yet; restoration should be a controlled support/admin process after validation.
3. **Attachments:** attachment metadata is supported, but the complete Supabase Storage upload/download UI is not wired into every entity yet.
4. **Approvals:** approval rule/request infrastructure exists, but every Sales/Purchase/Expense/Discount operation is not yet automatically paused by arbitrary configurable approval rules.
5. **Custom fields:** definitions and values APIs exist; definitions are manageable in Client, but every entity editor/industry screen does not yet dynamically render all custom fields.
6. **Healthcare:** Pharmacy/Clinic/Hospital/Lab are not presented as production-ready clinical systems. Sensitive medical workflows need a dedicated security/compliance phase.
7. **Restaurant Phase 2:** the proven basic Restaurant/KOT flow remains; modifier/waiter/table-event backend foundations are added, but all advanced table split/merge/KDS UI is not complete.
8. **Workshop:** V4 adds useful vehicles/job-card operations. Full inspection -> estimate -> customer approval -> technician labour -> invoice automation remains a later refinement.
9. **Production Phase 2:** BOM/reservation foundations are added; full MRP/work-center/batch costing UI remains future.
10. **External integrations:** WhatsApp, payment gateways, e-commerce, Tally, weighing scales, ANPR and AI features remain separate integrations.
11. **Direct silent thermal printing:** V4 uses explicit system print/PDF workflows. Silent hardware-specific printer control should be a separate printer integration layer.
12. **Automated updater:** app/device version tracking exists, but V4 does not silently self-update deployed EXE/APK installs.

These boundaries are deliberate. Financial, stock, tenant and audit integrity take priority over claiming a feature is complete before its complete workflow is proven.
