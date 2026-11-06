"""Emit whether Swift/iOS validation is needed; all other changes still get quality checks."""
import os
from pathlib import Path
import subprocess

def requires_build(paths):
    return any(p.startswith(('Apps/','Packages/','EnglishTrainer.xcodeproj/','.github/workflows/')) or p in
        ('Dockerfile','Scripts/test.sh','Scripts/testflight.sh','.github/workflows/validate.yml','Scripts/ci/changes.py') for p in paths)

def main():
    base, head = os.environ.get('BASE_SHA'), os.environ.get('HEAD_SHA')
    paths = subprocess.check_output(['git','diff','--name-only','-z',base,head]).decode().split('\0') if base and head else []
    needed = requires_build(paths) if base and head else True
    output = f"build={'true' if needed else 'false'}\n"
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'],'a') as stream: stream.write(output)
    print(output.strip())
if __name__ == '__main__': main()
