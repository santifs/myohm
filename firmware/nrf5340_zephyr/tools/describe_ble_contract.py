#!/usr/bin/env python3
"""Describe Myohm firmware coverage; the teaching web client supports a subset."""
from pathlib import Path
import argparse,json,re
import test_protocol_contract as contract
WEB=contract.REPO_ROOT/'web/src/ble/index.ts'
def uuid_rows():
    fw=contract.read(contract.FIRMWARE_BLE).lower();web=contract.read(WEB).lower()
    return [dict(name=name,uuid=value,firmware=contract.uuid16(value) in fw,web_supported=value in web) for name,value in contract.UUIDS.items()]
def command_rows():
    fw=contract.read(contract.FIRMWARE_BLE)
    found={m[1]:int(m[2],0) for m in re.finditer(r'#define\s+COMMAND_([A-Z0-9_]+)\s+(0x[0-9a-fA-F]+|\d+)',fw)}
    return [dict(name=name,opcode=code,opcode_hex=f'0x{code:02x}',firmware=found.get(name)==code,web_supported=code in (1,2,6)) for name,code in contract.COMMANDS.items()]
def all_rows_ok(rows):return all(row['firmware'] for row in rows)
def write_markdown(path,uuids,commands):
    lines=['# Myohm BLE contract','', 'Source checks only. Web support is a subset; no Android/iOS validation is claimed.','', '| Name | UUID/opcode | Firmware | Web support |','| --- | --- | --- | --- |']
    for row in uuids+commands:lines.append(f"| {row['name']} | {row.get('uuid',row.get('opcode_hex'))} | {row['firmware']} | {row['web_supported']} |")
    path.parent.mkdir(parents=True,exist_ok=True);path.write_text('\n'.join(lines)+'\n')
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--json',type=Path);parser.add_argument('--markdown',type=Path);args=parser.parse_args()
    contract.assert_web_contract();uuids=uuid_rows();commands=command_rows()
    summary=dict(ok=all_rows_ok(uuids+commands),device_name='BioMess (default; overrides supported)',uuid_count=len(uuids),command_count=len(commands),uuid_rows=uuids,command_rows=commands)
    if args.json:args.json.parent.mkdir(parents=True,exist_ok=True);args.json.write_text(json.dumps(summary,indent=2)+'\n')
    if args.markdown:write_markdown(args.markdown,uuids,commands)
    print('ble_contract_ok='+str(summary['ok']).lower())
    if not summary['ok']:raise SystemExit(1)
if __name__=='__main__':main()
