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

def watch_run(run_id="39954608057", poll_seconds=15, max_minutes=25):
    env = get_gh_env()
    start_time = time.time()
    last_completed = set()

    print(f"Tracking GitHub Actions Run: https://github.com/thariqmanchara321/THQ-ERP/actions/runs/{run_id}")
    
    while True:
        res = subprocess.run([
            r'C:\Program Files\GitHub CLI\gh.exe', 'run', 'view', run_id, '--json',
            'status,conclusion,jobs,url'
        ], env=env, capture_output=True, text=True)
        
        if res.returncode != 0:
            print("Error querying run:", res.stderr)
            time.sleep(poll_seconds)
            continue
            
        data = json.loads(res.stdout)
        status = data.get('status')
        conclusion = data.get('conclusion')
        job = data['jobs'][0] if data.get('jobs') else None

        if job:
            for s in job.get('steps', []):
                step_key = f"{s['number']}_{s['status']}_{s['conclusion']}"
                if step_key not in last_completed:
                    status_sym = "[OK]" if s['conclusion'] == 'success' else ("[RUN]" if s['status'] == 'in_progress' else ("[FAIL]" if s['conclusion'] == 'failure' else "[WAIT]"))
                    print(f"[{time.strftime('%H:%M:%S')}] {status_sym} Step {s['number']:02d}: {s['name']} -> {s['status']} ({s['conclusion'] or 'running'})")
                    last_completed.add(step_key)

        if status == 'completed':
            print(f"\n[{time.strftime('%H:%M:%S')}] FINAL RESULT: {conclusion.upper()}")
            break

        if (time.time() - start_time) > (max_minutes * 60):
            print("\nMax monitor time reached.")
            break

        time.sleep(poll_seconds)

if __name__ == '__main__':
    run_id = sys.argv[1] if len(sys.argv) > 1 else "39954608057"
    watch_run(run_id)
