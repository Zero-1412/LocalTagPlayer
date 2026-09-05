param(
  [Parameter(Mandatory = $true)][string]$Source,
  [Parameter(Mandatory = $true)][string]$Output,
  [Parameter(Mandatory = $true)][string]$Binary,
  [Parameter(Mandatory = $true)][string]$Flutter,
  [int]$Pairs = 10
)
# 以 PowerShell 提供受 QA manifest 管理的 Windows 入口，Python 负责 SQLite backup 和进程采样。
$baselinePython = @'
"""只读 SQLite backup 创建隔离副本，重复进程冷/热启动并记录外部墙钟时延。

冷态指新进程、新 profile 缩略图缓存；不清理系统缓存，不称为 OS 磁盘冷态。
仅终止本工具启动的 PID，不接触用户应用；全部媒体路径只读使用。
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import threading
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--flutter', required=True)
    parser.add_argument('--pairs', type=int, default=10)
    args = parser.parse_args()
    source = args.source.resolve()
    output = args.output.resolve()
    if output.exists() or not (source / '.query-baseline-profile').is_file():
        raise ValueError('需要带隔离标记的 source 和全新 output 目录')
    output.mkdir(parents=True)
    results = []
    for pair in range(args.pairs):
        profile = output / f'pair-{pair + 1:02}'
        profile.mkdir()
        (profile / '.query-baseline-profile').write_text('isolated startup repeat', encoding='utf8')
        with sqlite3.connect((source / 'library.db').as_uri() + '?mode=ro', uri=True) as src:
            with sqlite3.connect(profile / 'library.db') as dst:
                src.backup(dst)
        for name in ['library_sort.json', 'window_layout.json']:
            if (source / name).exists():
                shutil.copy2(source / name, profile / name)
        for cache in ['fresh-profile', 'reused-profile']:
            label = f'{pair + 1:02}-{cache}'
            env = dict(os.environ, LOCAL_TAG_PLAYER_DATA_DIR=str(profile),
                LOCAL_TAG_PLAYER_BASELINE_STARTUP_ONLY='1',
                LOCAL_TAG_PLAYER_BASELINE_SCAN='0', LOCAL_TAG_PLAYER_BASELINE_CACHE=cache)
            observed = {}
            ready = threading.Event()
            start = time.perf_counter()
            process = subprocess.Popen([str(args.binary.resolve())], env=env,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                encoding='utf8', errors='replace')

            def read_output():
                with (output / f'{label}.log').open('w', encoding='utf8') as log:
                    for line in process.stdout:
                        log.write(line)
                        log.flush()
                        match = re.search(r'(http://127\.0\.0\.1:\d+/\S+)', line)
                        if match and 'VM service' in line:
                            observed['uri'] = match.group(1)
                            ready.set()
                        if 'LTP_BASELINE_ACTIONABLE' in line:
                            observed['processToActionableMs'] = (time.perf_counter() - start) * 1000

            reader = threading.Thread(target=read_output, daemon=True)
            reader.start()
            try:
                if not ready.wait(60):
                    raise RuntimeError(f'{label}: VM service 未就绪，见隔离日志')
                command = [args.flutter, 'drive', '--profile', '--driver=test_driver/integration_test.dart',
                    f'--use-existing-app={observed["uri"]}', '--no-keep-app-running', '-d', 'windows']
                with (output / f'{label}-driver.log').open('w', encoding='utf8') as log:
                    drive = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=120)
                report_path = profile / 'evidence/interaction-summary.json'
                report = json.loads(report_path.read_text(encoding='utf8'))
                if report.get('cacheState') != cache or 'processToActionableMs' not in observed:
                    raise RuntimeError(f'{label}: 本次证据不完整，保留现场')
                shutil.copy2(report_path, output / f'{label}.json')
                if report.get('tailTraceEnabled'):
                    # 每次启动单独封存，避免复用 profile 覆盖上一轮首次索引时序。
                    shutil.copy2(profile / 'evidence/query-tail-trace.json', output / f'{label}-trace.json')
                row = {'pair': pair + 1, 'cache': cache,
                    'completed': report['completed'] and drive.returncode == 0,
                    'processToActionableMs': observed['processToActionableMs'],
                    'dartStartupMs': report['rawSamplesMs']['startup_profile'][0],
                    'firstSearchMs': next(iter(report['rawSamplesMs'].get('search_first', [])), None)}
                if not row['completed']:
                    failure = profile / 'evidence/failure-state.json'
                    if failure.exists():
                        row['failure'] = json.loads(failure.read_text(encoding='utf8'))
                    # 失败保留在分母，不以重试成功替换；后续独立样本仍继续。
                results.append(row)
                (output / 'startup-repeats.json').write_text(json.dumps(results, indent=2), encoding='utf8')
                print(json.dumps(row), flush=True)
            finally:
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=15)
                reader.join(timeout=5)


if __name__ == '__main__':
    main()

'@
$baselinePython | python - --source $Source --output $Output --binary $Binary --flutter $Flutter --pairs $Pairs
exit $LASTEXITCODE
