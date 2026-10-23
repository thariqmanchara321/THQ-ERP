import subprocess
import os
import json
import sys
import time

def get_gh_env():
    p = subprocess.Popen(['git', 'credential', 'fill'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    out, _ = p.communicate('protocol=https\nhost=github.com\n\n')
    token = [l.split('=', 1)[1] for l in out.splitlines() if l.startswith('password=')][0]
    env = os.environ.copy()
    env['GH_TOKEN'] = token
    return env

def print_status(run_id="39996547495"):
    env = get_gh_env()
    res = subprocess.run([
        r'C:\Program Files\GitHub CLI\gh.exe', 'run', 'view', run_id, '--json',
        'status,conclusion,jobs,url'
    ], env=env, capture_output=True, text=True)
    
    if res.returncode != 0:
        print("Error querying run:", res.stderr, flush=True)
        return
        
    data = json.loads(res.stdout)
    status = data.get('status')
    conclusion = data.get('conclusion')
    job = data['jobs'][0] if data.get('jobs') else None

    print(f"Overall Run Status: {status}, Conclusion: {conclusion}", flush=True)
    if job:
        print(f"Job: {job['name']} ({job['status']}, conclusion: {job['conclusion']})", flush=True)
        for s in job.get('steps', []):
            status_sym = "[OK]" if s['conclusion'] == 'success' else ("[RUN]" if s['status'] == 'in_progress' else ("[FAIL]" if s['conclusion'] == 'failure' else "[WAIT]"))
            if s['status'] != 'pending':
                print(f"  {status_sym} Step {s['number']:02d}: {s['name']} -> {s['status']} ({s['conclusion'] or 'running'})", flush=True)

if __name__ == '__main__':
    run_id = sys.argv[1] if len(sys.argv) > 1 else "39996547495"
    print_status(run_id)
