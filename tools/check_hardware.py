#!/usr/bin/env python3
"""Rebuild review evidence and fail on unresolved KiCad errors/warnings."""
from pathlib import Path
import os,shutil,subprocess,json,sys,collections
root=Path(__file__).resolve().parents[1]
cli=os.environ.get('KICAD_CLI') or shutil.which('kicad-cli')
if not cli:
    mac='/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli'
    if Path(mac).exists(): cli=mac
if not cli: raise SystemExit('Install KiCad 10 and set KICAD_CLI or PATH')
report=root/'reports';report.mkdir(exist_ok=True)
board=root/'hardware/mainboard/AllInOne'
commands={
 'erc':['sch','erc','--format','json','--severity-all','-o',str(report/'erc.json'),str(board)+'.kicad_sch'],
 'drc':['pcb','drc','--format','json','--severity-all','--schematic-parity','--refill-zones','-o',str(report/'drc.json'),str(board)+'.kicad_pcb'],
 'netlist':['sch','export','netlist','--format','kicadxml','-o',str(report/'netlist-final.xml'),str(board)+'.kicad_sch'],
 'pdf':['sch','export','pdf','-o',str(report/'schematic.pdf'),str(board)+'.kicad_sch']}
for name,args in commands.items():
    with (report/(name+'-stderr.log')).open('w') as err:
        subprocess.run([cli]+args,cwd=root,stderr=err,check=True)
netlist=report/'netlist-final.xml'
netlist.write_text(netlist.read_text().replace(str(root)+'/',''))  # keep reports machine-independent
summary={}
for name in ('erc','drc'):
    d=json.loads((report/(name+'.json')).read_text())
    if name=='erc': v=[v for s in d['sheets'] for v in s['violations']]
    else: v=sum((d.get(k,[]) for k in ('violations','unconnected_items','schematic_parity')),[])
    summary[name]=dict(collections.Counter(x['severity'] for x in v))
    summary[name+'_ignored_checks']=d.get('ignored_checks',[])
    if name == 'erc':
        rows = ['# ERC triage', '',
                'Generated from the current KiCad JSON report. No new electrical checks suppressed.', '',
                '| Sheet | Severity | Type | Evidence |',
                '| --- | --- | --- | --- |']
        for sheet in d['sheets']:
            for violation in sheet['violations']:
                evidence = violation['description'] + ': ' + '; '.join(
                    item['description'] for item in violation.get('items', []))
                cells = [sheet['path'], violation['severity'], violation['type'], evidence]
                rows.append('| ' + ' | '.join(c.replace('|', '\\|').replace('\n', ' ') for c in cells) + ' |')
        (report/'erc-triage.md').write_text('\n'.join(rows)+'\n')
(report/'checks.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
raise SystemExit(1 if any(summary[n].get(s,0) for n in ('erc','drc') for s in ('error','warning')) else 0)
