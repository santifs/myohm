#!/usr/bin/env python3
"""Recover embedded KiCad symbols without altering their pins or graphic definitions.
Run once on imported schematics, and again only to refresh libraries from those sources.
"""
import re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def children(text):
    depth=0; quoted=False; escape=False; start=None
    for i,c in enumerate(text):
        if quoted:
            if escape: escape=False
            elif c=='\\': escape=True
            elif c=='"': quoted=False
        elif c=='"': quoted=True
        elif c=='(':
            depth+=1
            if depth==2: start=i
        elif c==')':
            if depth==2: yield text[start:i+1]
            depth-=1
out=ROOT/'hardware/library/symbols'; out.mkdir(exist_ok=True)
rows=[]; count=0
for p in sorted((ROOT/'hardware/mainboard').glob('*.kicad_sch')):
    text=p.read_text(); lib='Myohm_'+p.stem; symbols=[]; edits=[]
    for child in children(text):
        if child.startswith('(lib_symbols'):
            embedded=[]
            for sym in children(child):
                name=re.match(r'\(symbol "([^"]+)"',sym)[1]
                local=name.split(':')[-1]
                symbols.append(sym.replace('"'+name+'"','"'+local+'"',1))
                embedded.append(sym.replace('"'+name+'"','"'+lib+':'+local+'"',1))
            edits.append((child,'(lib_symbols\n'+'\n'.join(embedded)+'\n)'))
        elif child.startswith('(symbol') and '(lib_id ' in child:
            old=re.search(r'\(lib_id "([^"]+)"\)',child)[1]
            alt=re.search(r'\(lib_name "([^"]+)"\)',child)
            local=alt[1] if alt else old.split(':')[-1]
            new=child.replace('(lib_id "'+old+'")','(lib_id "'+lib+':'+local+'")')
            new=re.sub(r'\s*\(lib_name "[^"]+"\)','',new)
            edits.append((child,new))
    if not symbols: continue
    for old,new in edits: text=text.replace(old,new,1)
    p.write_text(text)
    (out/(lib+'.kicad_sym')).write_text('(kicad_symbol_lib (version 20241209) (generator "myohm_recovery")\n'+'\n'.join(symbols)+'\n)\n')
    rows.append(f'  (lib (name "{lib}")(type "KiCad")(uri "${{KIPRJMOD}}/../library/symbols/{lib}.kicad_sym")(options "")(descr "Recovered embedded sources; see docs/licensing.md"))')
    count+=len(symbols)
(ROOT/'hardware/mainboard/sym-lib-table').write_text('(sym_lib_table\n (version 7)\n'+'\n'.join(rows)+'\n)\n')
print(f'Recovered {count} exact symbols across {len(rows)} sheets')
