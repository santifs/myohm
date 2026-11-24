#!/usr/bin/env python3
"""Run board-independent firmware checks; never flash or connect to BLE."""
from pathlib import Path
import subprocess,sys,json
root=Path(__file__).resolve().parents[1];tools=root/'firmware/nrf5340_zephyr/tools'
tests=['test_protocol_payloads.py','test_protocol_contract.py','test_hardware_contract.py','test_docs_links.py','test_python_syntax.py','test_board_validation_report.py','test_readiness_report.py','test_release_package_fixture.py']
results=[]
for test in tests:
    r=subprocess.run([sys.executable,str(tools/test)],cwd=root,text=True,capture_output=True)
    print(test+': '+('PASS' if r.returncode==0 else 'FAIL'));print(r.stdout+r.stderr,end='')
    results.append(dict(test=test,exit_code=r.returncode,output=(r.stdout+r.stderr).replace(str(root)+'/','')))
(root/'reports').mkdir(exist_ok=True)
(root/'reports/firmware-offline.json').write_text(json.dumps(results,indent=2)+'\n')
sys.exit(any(r['exit_code'] for r in results))
