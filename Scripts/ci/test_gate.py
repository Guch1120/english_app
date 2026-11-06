"""Exercise the real workflow gate, including expected skipped-build and failure paths."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml
from policy import GithubLoader

class ReviewGateTests(unittest.TestCase):
    def test_real_gate_accepts_only_complete_applicable_checks(self):
        workflow = yaml.load(Path('.github/workflows/validate.yml').read_text(), Loader=GithubLoader)
        script = workflow['jobs']['review-gate']['steps'][0]['run']
        cases = [
            ('success','true','success','success',True),
            ('success','false','skipped','skipped',True),
            ('success','true','failure','skipped',False),
            ('success','true','success','cancelled',False),
            ('failure','','skipped','skipped',False),
            ('success','','skipped','skipped',False),
            ('success','false','success','skipped',False),
        ]
        for quality, build, core, ios, expected in cases:
            with self.subTest(quality=quality, build=build, core=core, ios=ios), tempfile.TemporaryDirectory() as folder:
                env = dict(os.environ, QUALITY=quality, BUILD_REQUIRED=build, CORE=core, IOS=ios,
                           GITHUB_STEP_SUMMARY=str(Path(folder)/'summary.md'))
                result = subprocess.run(['bash','-e','-c',script],env=env,capture_output=True,text=True)
                self.assertEqual(result.returncode == 0,expected)
                self.assertIn('Automated PR checks',(Path(folder)/'summary.md').read_text())
if __name__ == '__main__': unittest.main()
