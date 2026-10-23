#!/usr/bin/env python3
"""
THQ ERP — Centralized Automated Version & Build Management Tool
Ensures atomic build number allocation across Flutter apps, Inno Setup,
release contracts, and Supabase release metadata.
"""

import argparse
import json
import os
import re
import sys
import urllib.request
import urllib.error

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

RELEASE_CONTRACT_FILE = os.path.join(PROJECT_ROOT, 'packages', 'erp_core', 'lib', 'src', 'release_contract.dart')
CLIENT_PUBSPEC = os.path.join(PROJECT_ROOT, 'apps', 'client_app', 'pubspec.yaml')
POS_PUBSPEC = os.path.join(PROJECT_ROOT, 'apps', 'pos_app', 'pubspec.yaml')
ADMIN_PUBSPEC = os.path.join(PROJECT_ROOT, 'apps', 'admin_panel', 'pubspec.yaml')
THQ_BUSINESS_ISS = os.path.join(PROJECT_ROOT, 'tools', 'windows_release', 'THQ_Business.iss')
THQ_POS_ISS = os.path.join(PROJECT_ROOT, 'tools', 'windows_release', 'THQ_POS.iss')

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://yguzrxcdvyimjrfvtcvp.supabase.co")
SUPABASE_ANON_KEY = os.environ.get("SUPABASE_ANON_KEY", "sb_publishable_NPqpotKR9BOujU4KgeDu-A_JI6sZIlJ")


def get_latest_published_release(app_key='client', platform='windows'):
    """Queries Supabase platform_app_releases for the latest version and build."""
    url = f"{SUPABASE_URL}/rest/v1/rpc/app_release_check_v820"
    payload = json.dumps({
        "p_app_key": app_key,
        "p_platform": platform,
        "p_channel": "stable",
        "p_current_version": "1.0.0",
        "p_current_build": 1,
    }).encode('utf-8')

    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "apikey": SUPABASE_ANON_KEY,
            "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
            "Content-Type": "application/json"
        },
        method="POST"
    )

    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            if isinstance(data, dict):
                latest_ver = data.get("latest_version")
                latest_build = data.get("latest_build")
                if latest_ver and latest_build is not None:
                    return str(latest_ver), int(latest_build)
    except Exception as e:
        print(f"[WARN] Failed to query latest release from Supabase RPC: {e}", file=sys.stderr)

    return None, None


def read_current_local_version(app='client'):
    """Reads current version and build number for the specified application."""
    target_pubspec = CLIENT_PUBSPEC
    if app == 'pos':
        target_pubspec = POS_PUBSPEC
    elif app == 'admin':
        target_pubspec = ADMIN_PUBSPEC

    version = "8.2.2"
    build = 19
    if os.path.exists(target_pubspec):
        with open(target_pubspec, 'r', encoding='utf-8') as f:
            content = f.read()
            m = re.search(r"^version:\s*([0-9.]+)\+([0-9]+)", content, re.MULTILINE)
            if m:
                version = m.group(1)
                build = int(m.group(2))
                return version, build

    if os.path.exists(RELEASE_CONTRACT_FILE):
        with open(RELEASE_CONTRACT_FILE, 'r', encoding='utf-8') as f:
            content = f.read()
            m_ver = re.search(r"appVersion\s*=\s*'([^']+)'", content)
            m_build = re.search(r"buildNumber\s*=\s*([0-9]+)", content)
            if m_ver:
                version = m_ver.group(1)
            if m_build:
                build = int(m_build.group(1))
    return version, build


def parse_semver(v):
    if not v:
        return (0, 0, 0)
    parts = [int(p) for p in re.findall(r'\d+', str(v))]
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])


def max_semver(v1, v2):
    if not v1:
        return v2 or "1.0.0"
    if not v2:
        return v1 or "1.0.0"
    return v1 if parse_semver(v1) >= parse_semver(v2) else v2


def compute_next_version(current_ver, current_build, bump_type='auto_build', target_ver=None, target_build=None):
    """Calculates the next version string and atomic build number."""
    if target_build is not None and target_build > 0:
        next_build = target_build
    else:
        next_build = current_build + 1

    if target_ver:
        return target_ver, next_build

    parts = [int(p) for p in re.findall(r'\d+', current_ver)]
    while len(parts) < 3:
        parts.append(0)

    major, minor, patch = parts[0], parts[1], parts[2]

    if bump_type == 'major':
        next_ver = f"{major + 1}.0.0"
    elif bump_type == 'minor':
        next_ver = f"{major}.{minor + 1}.0"
    elif bump_type == 'patch':
        next_ver = f"{major}.{minor}.{patch + 1}"
    elif bump_type == 'auto_build':
        # Default: preserve current semantic version unless build requires patch advancement
        next_ver = f"{major}.{minor}.{patch}"
    else:
        next_ver = current_ver

    return next_ver, next_build


def update_file_content(path, pattern, replacement):
    """Safely replaces regex pattern in a file."""
    if not os.path.exists(path):
        return False
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    new_content, count = re.subn(pattern, replacement, content)
    if count > 0 and new_content != content:
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(new_content)
        return True
    return False


def apply_version_to_files(app, version, build_number, release_name=None):
    """Updates all version contracts, pubspecs, and installer scripts for the target app."""
    modified = []

    # 1. release_contract.dart (core contract updated for client or all)
    if app in ('client', 'all', 'both'):
        if os.path.exists(RELEASE_CONTRACT_FILE):
            rel_name = release_name or f"THQ ERP v{version} Automated Release"
            with open(RELEASE_CONTRACT_FILE, 'r', encoding='utf-8') as f:
                c = f.read()
            c = re.sub(r"appVersion\s*=\s*'[^']+'", f"appVersion = '{version}'", c)
            c = re.sub(r"buildNumber\s*=\s*\d+", f"buildNumber = {build_number}", c)
            c = re.sub(r"releaseName\s*=\s*'[^']+'", f"releaseName = '{rel_name}'", c)
            with open(RELEASE_CONTRACT_FILE, 'w', encoding='utf-8', newline='\n') as f:
                f.write(c)
            modified.append(RELEASE_CONTRACT_FILE)

    # 2. pubspec.yaml for target app
    target_pubspecs = []
    if app in ('client', 'all', 'both'):
        target_pubspecs.append(CLIENT_PUBSPEC)
    if app in ('pos', 'all', 'both'):
        target_pubspecs.append(POS_PUBSPEC)
    if app in ('admin', 'all'):
        target_pubspecs.append(ADMIN_PUBSPEC)

    for pubspec in target_pubspecs:
        if os.path.exists(pubspec):
            if update_file_content(pubspec, r"^version:\s*[0-9.]+\+[0-9]+", f"version: {version}+{build_number}"):
                modified.append(pubspec)

    # 3. Inno Setup scripts
    if app in ('client', 'all', 'both') and os.path.exists(THQ_BUSINESS_ISS):
        with open(THQ_BUSINESS_ISS, 'r', encoding='utf-8') as f:
            c = f.read()
        c = re.sub(r'#define\s+AppVersion\s+"[^"]+"', f'#define AppVersion "{version}"', c)
        c = re.sub(r'#define\s+BuildNumber\s+"[^"]+"', f'#define BuildNumber "{build_number}"', c)
        with open(THQ_BUSINESS_ISS, 'w', encoding='utf-8', newline='\n') as f:
            f.write(c)
        modified.append(THQ_BUSINESS_ISS)

    if app in ('pos', 'all', 'both') and os.path.exists(THQ_POS_ISS):
        with open(THQ_POS_ISS, 'r', encoding='utf-8') as f:
            c = f.read()
        c = re.sub(r'#define\s+AppVersion\s+"[^"]+"', f'#define AppVersion "{version}"', c)
        c = re.sub(r'#define\s+BuildNumber\s+"[^"]+"', f'#define BuildNumber "{build_number}"', c)
        with open(THQ_POS_ISS, 'w', encoding='utf-8', newline='\n') as f:
            f.write(c)
        modified.append(THQ_POS_ISS)

    return modified


def main():
    parser = argparse.ArgumentParser(description="THQ ERP Centralized Version Management")
    parser.add_argument("--app", choices=["client", "pos", "admin", "all", "both"], default="client", help="Target application")
    parser.add_argument("--bump-type", choices=["auto_build", "patch", "minor", "major"], default="auto_build", help="Version bump type")
    parser.add_argument("--set-version", type=str, default=None, help="Explicitly specify semantic version (e.g. 8.2.3)")
    parser.add_argument("--set-build", type=int, default=0, help="Explicitly specify build number")
    parser.add_argument("--release-name", type=str, default=None, help="Custom release display name")
    parser.add_argument("--dry-run", action="store_true", help="Print changes without modifying files")
    parser.add_argument("--query-remote", action="store_true", default=True, help="Query Supabase for highest published build")

    args = parser.parse_args()

    local_ver, local_build = read_current_local_version(app=args.app)

    remote_ver, remote_build = None, None
    if args.query_remote:
        lookup_app = 'client' if args.app in ('client', 'all', 'both') else args.app
        remote_ver, remote_build = get_latest_published_release(app_key=lookup_app)

    effective_ver = max_semver(local_ver, remote_ver)
    effective_build = max(local_build, remote_build or 0)

    next_ver, next_build = compute_next_version(
        current_ver=effective_ver,
        current_build=effective_build,
        bump_type=args.bump_type,
        target_ver=args.set_version,
        target_build=args.set_build if args.set_build > 0 else None
    )

    result = {
        "app": args.app,
        "previous_version": local_ver,
        "previous_build": local_build,
        "remote_latest_version": remote_ver,
        "remote_latest_build": remote_build,
        "new_version": next_ver,
        "new_build": next_build,
        "bump_type": args.bump_type,
        "dry_run": args.dry_run
    }

    if not args.dry_run:
        modified_files = apply_version_to_files(args.app, next_ver, next_build, release_name=args.release_name)
        result["modified_files"] = [os.path.relpath(p, PROJECT_ROOT) for p in modified_files]

        if "GITHUB_OUTPUT" in os.environ:
            try:
                with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as gh_out:
                    gh_out.write(f"version={next_ver}\n")
                    gh_out.write(f"build_number={next_build}\n")
                    gh_out.write(f"previous_version={local_ver}\n")
                    gh_out.write(f"previous_build={local_build}\n")
            except Exception as e:
                print(f"[WARN] Failed to write to GITHUB_OUTPUT: {e}", file=sys.stderr)

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
