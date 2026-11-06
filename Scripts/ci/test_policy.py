import unittest
from policy import tracked_errors, workflow_errors
SHA = 'a'*40
SAFE = f'''name: Check
on: [pull_request]
permissions: {{contents: read}}
jobs:
  check:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@{SHA}
        with: {{persist-credentials: false}}
'''
class PolicyTests(unittest.TestCase):
    def test_on_is_an_event_key(self):
        self.assertEqual(workflow_errors('fixture', SAFE), [])
    def test_secret_reference_in_pr_fails(self):
        self.assertTrue(workflow_errors('fixture', SAFE+'      - run: echo ${{ secrets.DUMMY }}\n'))
    def test_mutable_action_and_write_permission_fail(self):
        self.assertTrue(workflow_errors('fixture', SAFE.replace(SHA,'v4')))
        self.assertTrue(workflow_errors('fixture', SAFE.replace('contents: read','contents: write')))
    def test_unsafe_event_and_inline_event_text_fail(self):
        self.assertTrue(workflow_errors('fixture', SAFE.replace('pull_request','pull_request_target')))
        self.assertTrue(workflow_errors('fixture', SAFE+'      - run: echo "${{ github.event.pull_request.title }}"\n'))
    def test_deployment_requires_manual_or_main_push_and_main_guard(self):
        deploy = SAFE.replace('[pull_request]','[workflow_dispatch]').replace('    runs-on:', '    environment: ios-testflight\n    runs-on:')
        self.assertTrue(workflow_errors('fixture', deploy))
        self.assertEqual(workflow_errors('fixture', deploy.replace('    environment:', "    if: github.ref == 'refs/heads/main'\n    environment:")), [])
        automatic = deploy.replace('on: [workflow_dispatch]', 'on:\n  push:\n    branches: [main]\n  workflow_dispatch:')
        automatic = automatic.replace('    runs-on:', "    if: github.ref == 'refs/heads/main'\n    runs-on:")
        self.assertEqual(workflow_errors('fixture', automatic), [])
        self.assertTrue(workflow_errors('fixture', automatic.replace('branches: [main]', 'branches: [main, release]')))
    def test_signing_files_including_encoded_files_fail(self):
        self.assertEqual(len(tracked_errors(['cert.p12','cert.p12.base64','key.p8','a.mobileprovision','p12-password.txt'])),5)
        self.assertEqual(tracked_errors(['Docs/TestFlight.md','Scripts/testflight.sh']),[])

from changes import requires_build
class ChangeSelectionTests(unittest.TestCase):
    def test_docs_and_usb_scripts_skip_macos_build(self):
        self.assertFalse(requires_build(['Docs/TestFlight.md','README.md','Scripts/iphone.sh']))
    def test_app_package_and_build_pipeline_require_build(self):
        for path in ['Apps/EnglishTrainer/Info.plist','Packages/VoiceLearning/Package.swift','Scripts/testflight.sh','.github/workflows/validate.yml','.github/workflows/testflight.yml']:
            self.assertTrue(requires_build([path]))

if __name__ == '__main__': unittest.main()
