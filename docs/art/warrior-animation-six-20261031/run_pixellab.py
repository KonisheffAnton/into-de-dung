"""Одна отправка на клип, ограниченная очередь. Повторяются только GET."""
from pathlib import Path
import json,subprocess,time,argparse
ROOT=Path(__file__).resolve().parent
JOBS=Path('C:/Users/Aston/.codex/generated_images/warrior-animation-six-20261031')

def read(p): return json.loads(p.read_text(encoding='utf-8-sig')) if p.exists() else {}
def call(action,key):
    r=subprocess.run(['pwsh','-NoProfile','-File',str(JOBS/'invoke-pixellab.ps1'),'-Action',action,'-Variant',key],capture_output=True,text=True,encoding='utf-8',errors='replace')
    print(r.stdout.strip(),flush=True)
    return r.returncode

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--limit',type=int,default=54);parser.add_argument('--active',type=int,default=6);args=parser.parse_args()
    rows=read(ROOT/'requests.json')[:args.limit]
    while True:
        active=[];pending=[];finished=[];blocked=[]
        for row in rows:
            key=row['key'];d=JOBS/'pixellab'/key
            job=read(d/'job-latest.json');admit=read(d/'admission.json')
            if job.get('status') in ('completed','failed','cancelled'):finished.append(key)
            elif admit.get('background_job_id'):active.append(key)
            elif (d/'submit-started.json').exists():blocked.append(key)
            else:pending.append(key)
        summary={'finished':finished,'active':active,'pending':pending,'uncertain_or_rejected':blocked}
        (JOBS/'batch-status.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
        if not active and not pending:break
        for key in pending[:max(0,args.active-len(active))]:
            if call('Submit',key)!=0:
                # Неизвестный результат POST не означает отказ; повтор опасен дублем.
                print('Submission blocked; inspect saved attempt before continuing',key,flush=True)
                return
            active.append(key)
        for key in active:call('Poll',key)
        print('BATCH',len(finished),'finished;',len(active),'active;',len(pending),'pending',flush=True)
        time.sleep(20)
    print('DONE',json.dumps(summary),flush=True)

if __name__=='__main__':main()
