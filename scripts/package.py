from pathlib import Path
import plistlib,subprocess,shutil,hashlib,tarfile,struct
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
# Check every thin arm64 Mach-O, including embedded frameworks and Swift libraries.
checked=[]
for binary in app.rglob('*'):
 if not binary.is_file(): continue
 with binary.open('rb') as f: magic=f.read(4)
 if magic != b'\xcf\xfa\xed\xfe': continue
 data=binary.read_bytes(); count=struct.unpack_from('<I',data,16)[0]; offset=32
 for _ in range(count):
  command,size=struct.unpack_from('<II',data,offset)
  assert size>=8 and offset+size<=len(data), 'Malformed Mach-O'
  if command in (0x25,0x32):
   value=struct.unpack_from('<I',data,offset+(8 if command==0x25 else 12))[0]
   assert value<=12<<16, f'{binary}: minimum OS exceeds iOS 12.0'
  if command==0xc:
   string_offset=struct.unpack_from('<I',data,offset+8)[0]
   name=data[offset+string_offset:offset+size].split(b'\0')[0].decode()
   assert not any(x in name for x in ['Combine.framework','SwiftUI.framework','WidgetKit.framework','UniformTypeIdentifiers']), f'Unavailable strong dependency: {name}'
  offset+=size
 checked.append(str(binary.relative_to(app)))
payload=build/'Payload'; payload.mkdir(exist_ok=True)
shutil.copytree(app,payload/'AltPocket.app',dirs_exist_ok=True)
subprocess.run(['zip','-qry','AltPocket-unsigned.ipa','Payload'],cwd=build,check=True)
ipa=build/'AltPocket-unsigned.ipa'
report=['AltPocket experimental build','Commit: '+subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'Minimum iOS: '+info['MinimumOSVersion'],'VPN minimum iOS: '+ei['MinimumOSVersion'],'SHA256: '+hashlib.sha256(ipa.read_bytes()).hexdigest(),'Signing: UNSIGNED. Requires valid provisioning for app AND VPN extension.','Checked arm64 binaries: '+str(len(checked)), 'Runtime: NOT DEVICE-TESTED. Build success does not verify Apple login/pairing/installation.']
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
