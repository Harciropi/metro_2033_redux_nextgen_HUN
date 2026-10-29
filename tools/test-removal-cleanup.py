"""Real Windows file-lock cleanup checks in isolated fixtures; installed games are read only."""
from pathlib import Path
import ctypes,json,subprocess,hashlib,uuid
ROOT=Path(__file__).resolve().parents[1]
build=json.loads((ROOT/'.private/build-package.json').read_text(encoding='utf8'))
stage=Path(build['Stage']);payload=stage/'payload';backend=stage/'Kezeles.ps1'
sdk_path=Path(json.loads((ROOT/'.private/v1.6.0/component-verification.json').read_text(encoding='utf-8-sig'))['FixtureRoot'])/'sdk-original.dll'
original=(payload/'original-content.vfx').read_bytes();sdk=sdk_path.read_bytes()
scope=ROOT/'.private/v1.6.0'/('cleanup-'+uuid.uuid4().hex);backup_name='Magyaritas_NextGen_20261022'
def fixture(name):
    p=scope/name/'steamapps/common/MetroFixture';p.mkdir(parents=True)
    assert p.resolve().is_relative_to(scope.resolve())
    (p/'content.vfx').write_bytes(original);(p/'pros.sdk.x64.dll').write_bytes(sdk)
    for n in ['metro.exe','steam_api64.dll','amd_fidelityfx_dx12.dll']:(p/n).write_text('FIXTURE ONLY')
    (p.parents[1]/'appmanifest_286690.acf').write_text('"AppState" { "appid" "286690" "StateFlags" "4" "installdir" "MetroFixture" }')
    (p/'user-note.txt').write_text('preserve');return p
def run(p,mode,selection=None,expected='INSTALLED'):
    assert p.resolve().is_relative_to(scope.resolve())
    args=['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(backend),'-GameDir',str(p),'-PayloadDir',str(payload),'-Mode',mode]
    if selection:args+=['-Components',selection]
    result=subprocess.run(args,capture_output=True,text=True,timeout=90)
    assert result.stdout.strip()==expected,(result.stdout,result.stderr)
def state(p):return json.loads((p/backup_name/'state.json').read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
k=ctypes.WinDLL('kernel32',use_last_error=True)
k.CreateFileW.argtypes=[ctypes.c_wchar_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p];k.CreateFileW.restype=ctypes.c_void_p;k.CloseHandle.argtypes=[ctypes.c_void_p]
def lock(p):
    h=k.CreateFileW(str(p),0x80000000,1,None,3,0,None);assert h not in (None,ctypes.c_void_p(-1).value);return h
p=fixture('complete');run(p,'Apply','Translation,HideAds');run(p,'Apply','Translation');backup=p/backup_name
assert list(backup.glob('sdk-original-*.dll'))
run(p,'Apply','Translation,HideAds');assert list(backup.glob('history-*.json'))
run(p,'Remove',expected='REMOVED');assert not backup.exists() and (p/'content.vfx').read_bytes()==original and (p/'pros.sdk.x64.dll').read_bytes()==sdk
p=fixture('foreign');run(p,'Apply','HideAds');backup=p/backup_name;(backup/'personal.txt').write_text('preserve')
run(p,'Remove',expected='REMOVED');assert [q.name for q in backup.iterdir()]==['personal.txt']
p=fixture('locked-original');run(p,'Apply','Translation,HideAds');backup=p/backup_name;saved=backup/state(p)['OriginalName'];h=lock(saved)
try:run(p,'Remove',expected='CLEANUP_FAILED')
finally:k.CloseHandle(h)
assert (p/'content.vfx').read_bytes()==original and (p/'pros.sdk.x64.dll').read_bytes()==sdk and saved.exists()
p=fixture('failed-restoration');run(p,'Apply','Translation,HideAds');backup=p/backup_name
before={n:sha(p/n) for n in ['content.vfx','content_hun_nextgen2.vfs0','pros.sdk.x64.dll']};state_hash=sha(backup/'state.json');h=lock(p/'pros.sdk.x64.dll')
try:run(p,'Remove',expected='OPERATION_FAILED')
finally:k.CloseHandle(h)
assert all(sha(p/n)==s for n,s in before.items()) and sha(backup/'state.json')==state_hash
assert list(backup.glob('original-*.vfx')) and list(backup.glob('sdk-original-*.dll'))
report=dict(full_removal_cleanup=True,partial_changes_keep_backups=True,foreign_files_preserved=True,locked_backup_reports_cleanup_failure_after_verified_restore=True,failed_restoration_rolls_back_and_preserves_backups=True,fixture_root=str(scope),installed_game_modified=False)
(ROOT/'.private/v1.6.0/removal-cleanup-verification.json').write_text(json.dumps(report,indent=2),encoding='utf8');print(json.dumps(report,indent=2))
