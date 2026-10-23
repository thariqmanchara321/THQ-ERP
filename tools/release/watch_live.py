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

def watch_live(run_id="39996547495", poll_seconds=20, max_minutes=30):
    env = get_gh_env()
    start_time = time.time()
    seen_steps = {}

    print(f"Tracking run {run_id}: https://github.com/thariqmanchara321/THQ-ERP/actions/runs/{run_id}", flush=True)

    while True:
        try:
            res = subprocess.run([
                r'C:\Program Files\GitHub CLI\gh.exe', 'run', 'view', run_id, '--json',
                'status,conclusion,jobs'
            ], env=env, capture_output=True, text=True)
            
            if res.returncode == 0:
                data = json.loads(res.stdout)
                status = data.get('status')
                conclusion = data.get('conclusion')
                job = data['jobs'][0] if data.get('jobs') else None

                if job:
                    for s in job.get('steps', []):
                        num = s['number']
                        st = s['status']
                        con = s['conclusion']
                        prev = seen_steps.get(num)
                        current = (st, con)
                        if prev != current:
                            seen_steps[num] = current
                            sym = "[OK]" if con == 'success' else ("[RUN]" if st == 'in_progress' else ("[FAIL]" if con == 'failure' else "[WAIT]"))
                            print(f"[{time.strftime('%H:%M:%S')}] {sym} Step {num:02d}: {s['name']} -> {st} ({con or 'in_progress'})", flush=True)

                if status == 'completed':
                    print(f"\n[{time.strftime('%H:%M:%S')}] RUN COMPLETED: {conclusion.upper()}", flush=True)
                    break
            else:
                print(f"Warning: {res.stderr.strip()}", flush=True)
        except Exception as e:
            print(f"Exception while polling: {e}", flush=True)

        if (time.time() - start_time) > (max_minutes * 60):
            print("Max timeout reached.", flush=True)
            break

        time.sleep(poll_seconds)

if __name__ == '__main__':
    run_id = sys.argv[1] if len(sys.argv) > 1 else "39996547495"
    watch_live(run_id)
