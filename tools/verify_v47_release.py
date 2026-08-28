from __future__ import annotations

from pathlib import Path
import re
import sys
import yaml

ROOT = Path(__file__).resolve().parents[1]
checks: list[tuple[str, bool, str]] = []

def check(name: str, ok: bool, detail: str = '') -> None:
    checks.append((name, bool(ok), detail))

# Release cleanliness
check('no .git in release', not (ROOT / '.git').exists())
check('no node_modules in release', not (ROOT / 'node_modules').exists())
check('no supabase temp in release', not (ROOT / 'supabase/.temp').exists())

# App/package versions and YAML validity
for rel in ['apps/admin_panel/pubspec.yaml','apps/client_app/pubspec.yaml','apps/pos_app/pubspec.yaml','packages/erp_core/pubspec.yaml']:
    p = ROOT / rel
    try:
        data = yaml.safe_load(p.read_text())
        check(f'valid YAML {rel}', isinstance(data, dict))
    except Exception as exc:
        check(f'valid YAML {rel}', False, str(exc))

for app in ['admin_panel','client_app','pos_app']:
    data = yaml.safe_load((ROOT / f'apps/{app}/pubspec.yaml').read_text())
    check(f'{app} version 4.7.0+1', data.get('version') == '4.7.0+1', str(data.get('version')))
for app in ['client_app','pos_app']:
    data = yaml.safe_load((ROOT / f'apps/{app}/pubspec.yaml').read_text())
    deps = data.get('dependencies') or {}
    check(f'{app} consumes erp_core', 'erp_core' in deps)
    try:
        yaml.safe_load((ROOT / f'apps/{app}/pubspec.lock').read_text())
        check(f'{app} lock YAML valid', True)
    except Exception as exc:
        check(f'{app} lock YAML valid', False, str(exc))

# Migration order
migrations = ROOT / 'backend/migrations'
for n in range(101, 111):
    found = list(migrations.glob(f'{n}_*.sql'))
    check(f'migration {n} present exactly once', len(found) == 1, ','.join(x.name for x in found))
upgrade = ROOT / 'backend/upgrade_from_100'
upgrade_nums = sorted(int(p.name.split('_',1)[0]) for p in upgrade.glob('*.sql'))
check('upgrade_from_100 contains only 101-110', upgrade_nums == list(range(101,111)), str(upgrade_nums))
check('combined upgrade SQL exists', (ROOT/'backend/THQ_ERP_V47_UPGRADE_FROM_100.sql').stat().st_size > 1000)

# SQL structural sanity + expected v4.7 objects
for n in range(101, 111):
    p = next(migrations.glob(f'{n}_*.sql'))
    text = p.read_text()
    check(f'{p.name}: dollar quotes balanced', text.count('$$') % 2 == 0, str(text.count('$$')))
    check(f'{p.name}: transaction has begin', bool(re.search(r'(?im)^begin\s*;', text)))
    check(f'{p.name}: transaction has commit', bool(re.search(r'(?im)^commit\s*;', text)))

required_sql = {
    'release contract': ('101_v47_release_contract.sql','thq_backend_contract_v47'),
    'strict accounting': ('102_v47_accounting_integrity.sql','perform private.v4_accounting_post_document'),
    'sales idempotency': ('103_v47_idempotent_transactions.sql','sales_create_v47'),
    'operation idempotency': ('104_v47_idempotent_operations.sql','sales_add_payment_v47'),
    'installations': ('105_v47_system_installations.sql','system_claim_activation_v47'),
    'stock lock': ('106_v47_inventory_atomicity.sql','for update'),
    'health scan': ('107_v47_integrity_health.sql','system_integrity_scan_v47'),
    'fail closed': ('108_v47_security_access.sql',"coalesce((select a.enabled"),
    'release verify': ('109_v47_release_register_verify.sql','4.7.0'),
    'heartbeat sync': ('110_v47_runtime_hardening.sql','system_installations'),
}
for name,(file,needle) in required_sql.items():
    check(name, needle.lower() in (migrations/file).read_text().lower())
check('strict accounting does not swallow posting error', 'perform private.v4_accounting_post_document(new.tenant_id,new.entity_type,new.entity_id);exception when others then null' not in (migrations/'102_v47_accounting_integrity.sql').read_text().lower())

# Edge functions
activate = (ROOT/'supabase/functions/device-activate/index.ts').read_text()
login = (ROOT/'supabase/functions/username-login/index.ts').read_text()
check('activation uses atomic v47 RPC', "system_claim_activation_v47" in activate)
check('activation never sends raw secret to SQL', "p_secret_hash" in activate and "device_secret: deviceSecret" in activate)
check('login validates active installation', "from('system_installations')" in login and "installation.secret_hash" in login)

# App wiring
pos_screen = (ROOT/'apps/pos_app/lib/screens/pos_screen.dart').read_text()
check('POS holds checkout request ID across retry', '_checkoutRequestId ??= const Uuid().v4()' in pos_screen)
check('POS sends checkout request ID', 'requestId: _checkoutRequestId' in pos_screen)
for app in ['client_app','pos_app']:
    sales = (ROOT/f'apps/{app}/lib/services/sales_service.dart').read_text()
    check(f'{app} uses sales_create_v47', "'sales_create_v47'" in sales)
    compat = (ROOT/f'apps/{app}/lib/services/backend_compatibility_service.dart').read_text()
    check(f'{app} checks shared backend contract', 'ThqReleaseContract.minimumMigration' in compat)
    boot = (ROOT/f'apps/{app}/lib/screens/client_bootstrap_screen.dart').read_text()
    check(f'{app} verifies backend before business load', 'await _backendCompatibility.verify();' in boot)
check('Admin System Health screen exists', (ROOT/'apps/admin_panel/lib/screens/system_health_screen.dart').exists())
check('Admin business page exposes System Health', "label: const Text('System Health')" in (ROOT/'apps/admin_panel/lib/screens/business_details_screen.dart').read_text())

# Shared core
core = (ROOT/'packages/erp_core/lib/erp_core.dart').read_text()
check('shared core exports Money', "money.dart" in core)
check('shared core exports failure model', "erp_failure.dart" in core)
check('shared core exports release contract', "release_contract.dart" in core)

# Make sure app runtime version strings were updated where hardcoded.
for app in ['client_app','pos_app']:
    heartbeat=(ROOT/f'apps/{app}/lib/services/device_heartbeat_service.dart').read_text()
    check(f'{app} heartbeat is 4.7.0', "'p_version': '4.7.0'" in heartbeat)

failed = [c for c in checks if not c[1]]
for name,ok,detail in checks:
    print(('PASS' if ok else 'FAIL') + ' | ' + name + (f' | {detail}' if detail else ''))
print(f'\nSUMMARY: {len(checks)-len(failed)}/{len(checks)} checks passed')
if failed:
    sys.exit(1)
