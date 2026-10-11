#!/usr/bin/env python3
"""Run DOS regressions with fresh, calibrated guest exit verdicts."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time


def guest(out, expected):
    for name in ['RESULT.TXT','OUT.TXT']:
        (out/name).unlink(missing_ok=True)
    (out/'RUN.BAT').write_bytes(b'@ECHO OFF\r\nCHECK.EXE > OUT.TXT\r\nIF ERRORLEVEL 1 GOTO BAD\r\nECHO PASS>RESULT.TXT\r\nGOTO END\r\n:BAD\r\nECHO FAIL>RESULT.TXT\r\n:END\r\n')
    (out/'run.conf').write_text('[sdl]\noutput=surface\n[cpu]\ncore=normal\ncputype=386\ncycles=fixed 20000\n[mixer]\nnosound=true\n[autoexec]\nmount c "'+str(out)+'"\nc:\nRUN.BAT\nexit\n')
    env=dict(os.environ,SDL_VIDEODRIVER='dummy',SDL_AUDIODRIVER='dummy',SDL12COMPAT_OPENGL_SCALING='0')
    verdict=None
    with (out/'dosbox.log').open('wb') as log:
        proc=subprocess.Popen(['dosbox','-conf','run.conf','-noconsole'],cwd=out,env=env,
                              stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        deadline=time.monotonic()+30
        try:
            while time.monotonic()<deadline:
                file=out/'RESULT.TXT'
                if file.exists() and file.read_text(errors='replace').strip() in ['PASS','FAIL']:
                    verdict=file.read_text().strip()
                    break
                if proc.poll() is not None: break
                time.sleep(0.1)
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid,signal.SIGTERM)
                try: proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid,signal.SIGKILL)
                    proc.wait()
    if verdict!=expected: raise RuntimeError(f'{out}: guest {verdict!r}, expected {expected}')
    return dict(verdict=verdict,expected=expected,emulator_exit=proc.returncode)


def main():
    parser=argparse.ArgumentParser()
    for name in ['compiler','rtl-root','binutils','output']:
        parser.add_argument('--'+name,required=True,type=Path)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[2]
    output=args.output.resolve()
    output.mkdir(parents=True,exist_ok=True)
    calibration=output/'exit7.pp'
    calibration.write_text('program exit7; begin halt(7); end.\n')
    compiler=args.compiler.resolve()
    binutils=args.binutils.resolve()
    env=dict(os.environ,PATH=str(binutils)+os.pathsep+os.environ['PATH'])
    rows=[]
    try:
        for model in ['Small','Large']:
            for cpu in ['80286','80386']:
                rtl=args.rtl_root.resolve()/f'rtl-msdos-{model}-{cpu}'
                if not (rtl/'system.ppu').is_file(): raise RuntimeError(f'Missing matching RTL: {rtl}')
                tests=[('exit7',calibration,'FAIL'),('tinline11',root/'tests/test/tinline11.pp','PASS'),
                       ('tw41850',root/'tests/webtbs/tw41850.pp','PASS'),
                       ('tidxpar1',root/'tests/test/cpu16/i8086/tidxpar1.pp','PASS'),
                       ('taddrprefix1',root/'tests/test/cpu16/i8086/taddrprefix1.pp','PASS')]
                # Do not count the far test's near-data skip as coverage.
                if model=='Large': tests.append(('tfarpar1',root/'tests/test/cpu16/i8086/tfarpar1.pp','PASS'))
                for abi in ['pascal','register']:
                    for name,source,expected in tests:
                        out=output/f'{model}-{cpu}-{abi}-{name}'
                        out.mkdir(exist_ok=True)
                        (out/'CHECK.EXE').unlink(missing_ok=True)
                        command=[str(compiler),'-n','-Tmsdos','-Pi8086','-Cp'+cpu,'-Wm'+model,
                                 '-O2','-Co-','-Cc'+abi,'-CX','-XX','-al','-Xm','-Fu'+str(rtl),
                                 '-FD'+str(binutils),'-FE'+str(out),'-FU'+str(out),str(source)]
                        row=dict(test=name,model=model,cpu=cpu,abi=abi,command=command)
                        rows.append(row)
                        with (out/'compile.log').open('wb') as log:
                            proc=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT)
                        row['compile_exit']=proc.returncode
                        if proc.returncode: raise RuntimeError(f'Compilation failed: {out}')
                        shutil.copy2(out/(name+'.exe'),out/'CHECK.EXE')
                        row.update(guest(out,expected))
                        print(json.dumps(row),flush=True)
    finally:
        (output/'results.json').write_text(json.dumps(rows,indent=2)+'\n')


if __name__=='__main__': main()
