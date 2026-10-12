"""Check a cryptographically verified APK against public release policy."""
import struct,zipfile,json,sys,re
from pathlib import Path

def manifest(path):
 b=zipfile.ZipFile(path).read('AndroidManifest.xml'); strings=[]; result={'permissions':[]}; off=8
 def u32(o): return struct.unpack_from('<I',b,o)[0]
 def u16(o): return struct.unpack_from('<H',b,o)[0]
 def string(i): return strings[i] if i != 0xffffffff else None
 while off<len(b):
  kind,header,size=struct.unpack_from('<HHI',b,off)
  if kind==1:
   count=u32(off+8); flags=u32(off+16); start=off+u32(off+20)
   for i in range(count):
    pos=start+u32(off+header+i*4)
    if flags&0x100:
     def length(p):
      v=b[p]; return (((v&127)<<8)|b[p+1],p+2) if v&128 else (v,p+1)
     _,pos=length(pos); n,pos=length(pos); strings.append(b[pos:pos+n].decode('utf8'))
    else:
     n=u16(pos);pos+=2
     if n&0x8000:n=((n&32767)<<16)|u16(pos);pos+=2
     strings.append(b[pos:pos+n*2].decode('utf-16le'))
  elif kind==0x102:
   name=string(u32(off+20)); attrs={}; start=off+16+u16(off+24); stride=u16(off+26)
   for i in range(u16(off+28)):
    p=start+i*stride; attr=string(u32(p+4)); raw=u32(p+8); typ=b[p+15]; data=u32(p+16)
    val=string(raw) if raw!=0xffffffff else (string(data) if typ==3 else (bool(data) if typ==18 else data))
    attrs[attr]=val
   if name=='manifest':result.update(attrs)
   if name in ['uses-permission','uses-permission-sdk-23']:result['permissions'].append(attrs)
   if name=='application':result['application']=attrs
  if not size:raise ValueError('Invalid XML chunk')
  off+=size
 return result
def verify(decoded, signature, policy, version):
 if decoded.get('package') != policy['package']: raise ValueError('Release package ID differs from policy')
 if decoded.get('versionName') != version[0] or decoded.get('versionCode') != version[1]: raise ValueError('Release version differs from pubspec')
 if decoded.get('application',{}).get('debuggable',False): raise ValueError('Release APK is debuggable')
 permissions=[p['name'] for p in decoded['permissions']]
 if len(set(permissions)) != len(permissions) or sorted(permissions) != sorted(policy['permissions']): raise ValueError('Merged release permissions differ from policy')
 fingerprints=re.findall(r'^(?:Signer #\d+|V\d(?:\.\d+)? Signer:) certificate SHA-256 digest: *([0-9a-fA-F:]+)$',signature,re.M)
 fingerprints={f.replace(':','').lower() for f in fingerprints}
 signer_count=re.search(r'^Number of signers: *1$',signature,re.M)
 if not signer_count or fingerprints!={policy['certificateSha256'].lower()}: raise ValueError('Release signing certificate differs from policy')

if __name__=='__main__':
 if len(sys.argv)!=3: raise SystemExit('Usage: verify_release_package.py APK APKSIGNER_SIGNATURE_REPORT')
 policy=json.loads(Path('docs/ANDROID-RELEASE-POLICY.json').read_text())
 match=re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)$',Path('pubspec.yaml').read_text(),re.M)
 if not match: raise SystemExit('Invalid pubspec version')
 decoded=manifest(sys.argv[1])
 verify(decoded,Path(sys.argv[2]).read_text(),policy,(match[1],int(match[2])))
 print('Release package, version, permission set and certificate match policy.')
