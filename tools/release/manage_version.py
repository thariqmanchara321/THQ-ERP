#!/usr/bin/env python3
"""
THQ ERP — Centralized Automated Version & Build Management Tool
Ensures atomic build number allocation across Flutter apps, Inno Setup,
release contracts, Git release tags, and Supabase release metadata.
Guarantees unique (app_key, platform, version) releases without registry collisions.
"""

import argparse
import json
import os
import re
import subprocess
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


def get_service_role_key():
    """Retrieves service-role key from environment without exposing or printing it."""
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    return key if key else None


def get_git_release_tags(project_root=PROJECT_ROOT):
    """Discovers all local git release tags matching vX.Y.Z+B."""
    tags = []
    try:
        proc = subprocess.run(
            ["git", "-C", project_root, "tag", "-l", "v*"],
            capture_output=True, text=True, check=True
        )
        for line in proc.stdout.splitlines():
            line = line.strip()
            m = re.match(r"^v(\d+\.\d+\.\d+)\+(\d+)$", line)
            if m:
                tags.append({
                    "tag": line,
                    "version": m.group(1),
                    "build_number": int(m.group(2))
                })
    except Exception as e:
        print(f"[WARN] Failed to query local git tags: {e}", file=sys.stderr)
    return tags


def get_remote_git_tags(project_root=PROJECT_ROOT):
    """Discovers remote git release tags from origin without fetching."""
    tags = []
    try:
        proc = subprocess.run(
            ["git", "-C", project_root, "ls-remote", "--tags", "origin", "refs/tags/v*"],
            capture_output=True, text=True, timeout=10
        )
        if proc.returncode == 0:
            for line in proc.stdout.splitlines():
                parts = line.split()
                if len(parts) >= 2:
                    ref = parts[1].replace("refs/tags/", "").replace("^{}", "")
                    m = re.match(r"^v(\d+\.\d+\.\d+)\+(\d+)$", ref)
                    if m:
                        tags.append({
                            "tag": ref,
                            "version": m.group(1),
                            "build_number": int(m.group(2))
                        })
    except Exception as e:
        print(f"[WARN] Failed to query remote git tags: {e}", file=sys.stderr)
    return tags


def get_all_known_tags(project_root=PROJECT_ROOT, query_remote=True):
    """Combines local and remote git release tags into a deduplicated dictionary."""
    tags_by_name = {}
    for t in get_git_release_tags(project_root):
        tags_by_name[t["tag"]] = t
    if query_remote:
        for t in get_remote_git_tags(project_root):
            if t["tag"] not in tags_by_name:
                tags_by_name[t["tag"]] = t
    return list(tags_by_name.values())


def get_all_registry_releases(app_key='client', platform='windows', service_role_key=None,
                              page_size=100, max_pages=100):
    """
    Queries public.platform_app_releases using an authenticated PostgREST query
    when an authorized service-role credential is available in a trusted environment.
    Discovers all historical records across multiple pages using PostgREST pagination.
    Validates completeness, Content-Range headers, count consistency, and duplicate prevention.

    Returns:
        tuple: (records_list, is_complete, error_summary)
        records_list: list of dicts:
            {'version': normalized_ver, 'build_number': int_build, 'status': status, 'id': id}
    """
    key = service_role_key or get_service_role_key()
    if not key:
        return [], False, "No service-role credential available in environment"

    seen_ids = set()
    records = []
    offset = 0
    page = 0
    total_count = None

    while page < max_pages:
        url = (
            f"{SUPABASE_URL}/rest/v1/platform_app_releases"
            f"?app_key=eq.{app_key}&platform=eq.{platform}"
            f"&select=id,version,build_number,status,channel"
            f"&order=released_at.asc,id.asc"
            f"&limit={page_size}&offset={offset}"
        )
        req = urllib.request.Request(
            url,
            headers={
                "apikey": key,
                "Authorization": f"Bearer {key}",
                "Accept": "application/json",
                "Prefer": "count=exact",
                "Range-Unit": "items"
            },
            method="GET"
        )

        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                content_range = resp.headers.get("Content-Range", "")
                if content_range and "/" in content_range:
                    total_part = content_range.split("/")[-1].strip()
                    if total_part != "*":
                        try:
                            total_count = int(total_part)
                        except ValueError:
                            pass

                raw_body = resp.read().decode('utf-8')
                page_data = json.loads(raw_body)
                if not isinstance(page_data, list):
                    return [], False, f"Unexpected response format on page {page}: {type(page_data)}"

                if not page_data:
                    break

                for row in page_data:
                    row_id = str(row.get("id", "")).strip()
                    if not row_id:
                        return [], False, f"Registry record missing required primary key id on page {page}"

                    if row_id in seen_ids:
                        return [], False, f"Duplicate record ID {row_id} detected during pagination on page {page}. Inconsistent scan."
                    seen_ids.add(row_id)

                    raw_ver = str(row.get("version", "")).strip()
                    m_v = re.match(r"^v?(\d+\.\d+\.\d+)", raw_ver)
                    norm_ver = m_v.group(1) if m_v else raw_ver

                    try:
                        raw_build = row.get("build_number")
                        norm_build = int(raw_build) if raw_build is not None else 0
                    except (ValueError, TypeError):
                        norm_build = 0

                    records.append({
                        "id": row_id,
                        "version": norm_ver,
                        "build_number": norm_build,
                        "status": str(row.get("status", "")).strip().lower(),
                        "channel": str(row.get("channel", "")).strip().lower()
                    })

                offset += len(page_data)
                page += 1

                if total_count is not None and offset >= total_count:
                    break

                if len(page_data) < page_size:
                    break

        except urllib.error.HTTPError as e:
            return [], False, f"PostgREST query failed on page {page} (offset {offset}): HTTP {e.code}"
        except Exception as e:
            return [], False, f"Exception querying registry page {page}: {type(e).__name__}: {str(e)}"

    if total_count is not None and len(records) != total_count:
        return [], False, f"Registry count mismatch: Content-Range indicated {total_count} records, but retrieved {len(records)} records across {page} pages."

    return records, True, None


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


def compute_next_version(current_ver, current_build, bump_type='auto_build',
                         target_ver=None, target_build=None,
                         known_versions=None, known_tags=None):
    """
    Calculates the next version string and atomic build number.
    Ensures that (app_key, platform, version) remains unique and does not collide
    with any existing Git tag or Supabase release record.
    """
    known_versions = set(known_versions or [])
    known_tags = set(known_tags or [])

    if target_build is not None and target_build > 0:
        next_build = target_build
    else:
        next_build = current_build + 1

    if target_ver:
        # Explicit target version: check for collisions
        if target_ver in known_versions:
            raise ValueError(
                f"Version collision: Proposed version '{target_ver}' has already been published/registered. "
                f"The platform_app_releases table has a unique constraint on (app_key, platform, version)."
            )
        target_tag = f"v{target_ver}+{next_build}"
        if target_tag in known_tags:
            raise ValueError(
                f"Tag collision: Git release tag '{target_tag}' already exists."
            )
        return target_ver, next_build

    parts = list(parse_semver(current_ver))
    major, minor, patch = parts[0], parts[1], parts[2]

    if bump_type == 'major':
        candidate_ver = f"{major + 1}.0.0"
    elif bump_type == 'minor':
        candidate_ver = f"{major}.{minor + 1}.0"
    elif bump_type == 'patch':
        candidate_ver = f"{major}.{minor}.{patch + 1}"
    elif bump_type == 'auto_build':
        # If current_ver has ALREADY been used/published in the registry or git tags,
        # we MUST advance patch because (app_key, platform, version) must be globally unique!
        if current_ver in known_versions:
            candidate_ver = f"{major}.{minor}.{patch + 1}"
        else:
            candidate_ver = f"{major}.{minor}.{patch}"
    else:
        candidate_ver = current_ver

    # Loop-advance patch if candidate_ver still collides with known published versions
    while candidate_ver in known_versions:
        c_parts = list(parse_semver(candidate_ver))
        c_parts[2] += 1
        candidate_ver = f"{c_parts[0]}.{c_parts[1]}.{c_parts[2]}"

    # Loop-advance build number if the tag candidate v<ver>+<build> already exists
    while f"v{candidate_ver}+{next_build}" in known_tags:
        next_build += 1

    return candidate_ver, next_build


def update_file_content(path, pattern, replacement, flags=0):
    """Safely replaces regex pattern in a file."""
    if not os.path.exists(path):
        return False
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    new_content, count = re.subn(pattern, replacement, content, flags=flags)
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

    # 2. pubspec.yaml for target app (multiline regex to match line 19)
    target_pubspecs = []
    if app in ('client', 'all', 'both'):
        target_pubspecs.append(CLIENT_PUBSPEC)
    if app in ('pos', 'all', 'both'):
        target_pubspecs.append(POS_PUBSPEC)
    if app in ('admin', 'all'):
        target_pubspecs.append(ADMIN_PUBSPEC)

    for pubspec in target_pubspecs:
        if os.path.exists(pubspec):
            if update_file_content(
                pubspec,
                r"^version:\s*['\"]?[0-9.]+[\+][0-9]+['\"]?.*$",
                f"version: {version}+{build_number}",
                flags=re.MULTILINE
            ):
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
    parser.add_argument("--set-version", type=str, default=None, help="Explicitly specify semantic version (e.g. 8.2.4)")
    parser.add_argument("--set-build", type=int, default=0, help="Explicitly specify build number")
    parser.add_argument("--release-name", type=str, default=None, help="Custom release display name")
    parser.add_argument("--dry-run", action="store_true", help="Print changes without modifying files")
    parser.add_argument("--check", action="store_true", help="Perform preflight release check without modifying files")
    parser.add_argument("--enforce-complete-registry", action="store_true", help="Fail closed if complete authenticated registry cannot be queried")
    parser.add_argument("--query-remote", action="store_true", default=True, help="Query Supabase for highest published build")
    parser.add_argument("--no-query-remote", action="store_false", dest="query_remote", help="Skip remote queries")

    args = parser.parse_args()

    local_ver, local_build = read_current_local_version(app=args.app)

    # 1. Inspect Git release tags
    all_tags = get_all_known_tags(project_root=PROJECT_ROOT, query_remote=args.query_remote)
    known_tag_strings = {t["tag"] for t in all_tags}
    known_versions = {t["version"] for t in all_tags}
    git_max_build = max([t["build_number"] for t in all_tags], default=0)
    git_max_ver = "0.0.0"
    for t in all_tags:
        git_max_ver = max_semver(git_max_ver, t["version"])

    # 2. Inspect Supabase release registry
    remote_ver, remote_build = None, None
    registry_records = []
    registry_is_complete = False
    registry_notice = None
    sources_checked = {
        "local_git_tags": len(get_git_release_tags(project_root=PROJECT_ROOT)),
        "remote_git_tags": len(get_remote_git_tags(project_root=PROJECT_ROOT)) if args.query_remote else 0,
        "registry_rpc": False,
        "registry_table_authenticated": False,
        "complete_registry_verified": False,
        "registry_records_inspected": 0
    }

    if args.query_remote:
        lookup_app = 'client' if args.app in ('client', 'all', 'both') else args.app
        lookup_platform = 'windows'

        # A. Attempt authenticated full table query if service-role key is provided
        sr_key = get_service_role_key()
        if sr_key:
            records, is_complete, reg_err = get_all_registry_releases(
                app_key=lookup_app, platform=lookup_platform, service_role_key=sr_key
            )
            if is_complete:
                registry_is_complete = True
                sources_checked["registry_table_authenticated"] = True
                sources_checked["complete_registry_verified"] = True
                sources_checked["registry_records_inspected"] = len(records)
                for r in records:
                    v = r["version"]
                    b = r["build_number"]
                    if v:
                        known_versions.add(v)
                    if v and b > 0:
                        known_tag_strings.add(f"v{v}+{b}")
                    remote_build = max(remote_build or 0, b)
                    if r["status"] in ("published", "stable", "beta"):
                        remote_ver = max_semver(remote_ver, v)
            else:
                registry_notice = reg_err
        else:
            registry_notice = "Service-role credential not provided in local environment"

        # B. Query latest active release via public RPC (works with anon key)
        rpc_ver, rpc_build = get_latest_published_release(app_key=lookup_app, platform=lookup_platform)
        if rpc_ver:
            sources_checked["registry_rpc"] = True
            known_versions.add(rpc_ver)
            remote_ver = max_semver(remote_ver, rpc_ver)
            remote_build = max(remote_build or 0, rpc_build or 0)

    # 3. Baseline version and build
    baseline_ver = max_semver(remote_ver, git_max_ver if git_max_ver != "0.0.0" else None)
    baseline_build = max(remote_build or 0, git_max_build)

    # 4. Detect branch-version divergence & tag/registry discrepancies
    branch_in_sync = True
    branch_divergence_diagnostic = None
    if baseline_build > 0 or (baseline_ver and baseline_ver != "0.0.0"):
        local_sv = parse_semver(local_ver)
        base_sv = parse_semver(baseline_ver)
        if local_sv < base_sv or (local_sv == base_sv and local_build < baseline_build):
            branch_in_sync = False
            branch_divergence_diagnostic = (
                f"Local workspace version ({local_ver}+{local_build}) is behind release baseline ({baseline_ver}+{baseline_build}). "
                f"Working tree files reflect older branch state."
            )

    discrepancy = None
    if remote_build and git_max_build and remote_build != git_max_build:
        discrepancy = (
            f"Discrepancy detected: Supabase registry highest build is {remote_build}, "
            f"while Git release tags reach build {git_max_build}."
        )
    elif not branch_in_sync:
        discrepancy = branch_divergence_diagnostic

    # 5. Effective baseline version and build
    effective_ver = max_semver(local_ver, baseline_ver)
    effective_build = max(local_build, baseline_build)

    # 6. Compute next version and build
    collision_detected = False
    error_msg = None
    next_ver, next_build = None, None

    if args.enforce_complete_registry and not registry_is_complete:
        collision_detected = True
        error_msg = f"FAIL-CLOSED POLICY: Complete registry collision check could not be performed ({registry_notice}). Publication halted."
    else:
        try:
            next_ver, next_build = compute_next_version(
                current_ver=effective_ver,
                current_build=effective_build,
                bump_type=args.bump_type,
                target_ver=args.set_version,
                target_build=args.set_build if args.set_build > 0 else None,
                known_versions=known_versions,
                known_tags=known_tag_strings
            )
        except ValueError as e:
            collision_detected = True
            error_msg = str(e)

    # Distinguish valid proposed version from verified publication readiness
    candidate_valid = (not collision_detected) and (next_ver is not None) and (next_build is not None)
    provisional_calculation = not registry_is_complete
    publication_ready = candidate_valid and registry_is_complete and (not collision_detected)
    can_rel = publication_ready

    result = {
        "app": args.app,
        "candidate_valid": candidate_valid,
        "publication_ready": publication_ready,
        "can_release": can_rel,
        "provisional_calculation": provisional_calculation,
        "branch_in_sync": branch_in_sync,
        "branch_divergence_diagnostic": branch_divergence_diagnostic,
        "local_version": local_ver,
        "local_build": local_build,
        "remote_latest_version": remote_ver,
        "remote_latest_build": remote_build,
        "git_latest_version": git_max_ver if git_max_ver != "0.0.0" else None,
        "git_latest_build": git_max_build,
        "proposed_version": next_ver,
        "proposed_build": next_build,
        "proposed_tag": f"v{next_ver}+{next_build}" if next_ver and next_build else None,
        "bump_type": args.bump_type,
        "discrepancy": discrepancy,
        "collision_detected": collision_detected,
        "complete_registry_verified": registry_is_complete,
        "sources_checked": sources_checked,
        "registry_error": registry_notice if not registry_is_complete else None,
        "error": error_msg,
        "dry_run": args.dry_run or args.check
    }

    if args.check:
        print(json.dumps(result, indent=2))
        sys.exit(0 if not collision_detected else 1)

    if not args.dry_run and not collision_detected:
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
    if collision_detected:
        sys.exit(1)


if __name__ == "__main__":
    main()

