from pathlib import Path
import plistlib,subprocess,shutil,hashlib,tarfile
root=Path.cwd(); build=root/'build'; app=build/'AltPocket.xcarchive/Products/Applications/AltPocket.app'
assert app.is_dir(), 'Archive missing application'
info=plistlib.loads((app/'Info.plist').read_bytes())
assert info['MinimumOSVersion']=='12.0', info.get('MinimumOSVersion')
ext=app/'PlugIns/LocalTunnel.appex'
assert ext.is_dir(), 'Embedded VPN missing'
ei=plistlib.loads((ext/'Info.plist').read_bytes())
assert ei['MinimumOSVersion']=='12.0', ei.get('MinimumOSVersion')
# Some legacy Xcode targets embed an unnecessary nested Frameworks directory.
nested=app/'Frameworks/AltStoreCore.framework/Frameworks'
if nested.is_dir(): shutil.rmtree(nested)
payload=build/'Payload'; payload.mkdir(exist_ok=True)
shutil.copytree(app,payload/'AltPocket.app',dirs_exist_ok=True)
subprocess.run(['zip','-qry','AltPocket-unsigned.ipa','Payload'],cwd=build,check=True)
ipa=build/'AltPocket-unsigned.ipa'
report=['AltPocket experimental build','Commit: '+subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'Minimum iOS: '+info['MinimumOSVersion'],'VPN minimum iOS: '+ei['MinimumOSVersion'],'SHA256: '+hashlib.sha256(ipa.read_bytes()).hexdigest(),'Signing: UNSIGNED. Requires valid provisioning for app AND VPN extension.','Runtime: NOT DEVICE-TESTED. Build success does not verify Apple login/pairing/installation.']
for binary in [app/info['CFBundleExecutable'],ext/ei['CFBundleExecutable']]:
 report.append(subprocess.check_output(['xcrun','vtool','-show-build',str(binary)],text=True))
(build/'BUILD-REPORT.txt').write_text('\n'.join(report))
# Corresponding source includes the patched project and complete checked-out submodules.
with tarfile.open(build/'AltPocket-source.tar.gz','w:gz') as tar:
 def filt(i):
  parts=Path(i.name).parts
  if any(p in {'.git','target','build','.DS_Store'} for p in parts): return None
  return i
 for p in root.iterdir():
  if p.name not in {'.git','build'}: tar.add(p,arcname='AltPocket/'+p.name,filter=filt)
print('\n'.join(report))
