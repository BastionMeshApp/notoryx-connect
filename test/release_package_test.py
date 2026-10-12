"""Public policy detects accidental signing rotation and manifest changes."""
import importlib.util
import unittest
from pathlib import Path

spec=importlib.util.spec_from_file_location('gate',Path(__file__).resolve().parents[1]/'scripts/verify_release_package.py')
gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)

class ReleaseGateTest(unittest.TestCase):
 def setUp(self):
  self.policy={'package':'example.app','certificateSha256':'aa11','permissions':['android.permission.INTERNET']}
  self.apk={'package':'example.app','versionName':'1.2.3','versionCode':4,'application':{},'permissions':[{'name':'android.permission.INTERNET'}]}
  self.signature='Signer #1 certificate SHA-256 digest: aa11'
 def check(self):gate.verify(self.apk,self.signature,self.policy,('1.2.3',4))
 def test_matching_release(self):self.check()
 def test_rotated_key_rejected(self):
  self.signature='Signer #1 certificate SHA-256 digest: bb22'
  with self.assertRaisesRegex(ValueError,'certificate'):self.check()
 def test_missing_signature_rejected(self):
  self.signature='verified without certificate report'
  with self.assertRaisesRegex(ValueError,'certificate'):self.check()
 def test_extra_permission_rejected(self):
  self.apk['permissions'].append({'name':'android.permission.CAMERA'})
  with self.assertRaisesRegex(ValueError,'permissions'):self.check()
 def test_missing_permission_rejected(self):
  self.apk['permissions']=[]
  with self.assertRaisesRegex(ValueError,'permissions'):self.check()
 def test_debuggable_rejected(self):
  self.apk['application']['debuggable']=True
  with self.assertRaisesRegex(ValueError,'debuggable'):self.check()
 def test_wrong_version_rejected(self):
  self.apk['versionCode']=3
  with self.assertRaisesRegex(ValueError,'version'):self.check()
 def test_different_package_rejected(self):
  self.apk['package']='other.app'
  with self.assertRaisesRegex(ValueError,'package'):self.check()

if __name__=='__main__':unittest.main()
