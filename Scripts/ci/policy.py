"""Small explicit CI policy. This complements linters; it is not a semantic code review."""
import copy
import re
import subprocess
from pathlib import Path
import yaml

class GithubLoader(yaml.SafeLoader):
    pass
GithubLoader.yaml_implicit_resolvers = copy.deepcopy(yaml.SafeLoader.yaml_implicit_resolvers)
for key, values in GithubLoader.yaml_implicit_resolvers.items():
    GithubLoader.yaml_implicit_resolvers[key] = [(tag, pattern) for tag, pattern in values if tag != 'tag:yaml.org,2002:bool']
GithubLoader.add_implicit_resolver('tag:yaml.org,2002:bool', re.compile(r'^(?:true|false|True|False|TRUE|FALSE)$'), list('tTfF'))

def workflow_errors(name, text):
    errors = []
    def fail(message): errors.append(f'{name}: {message}')
    try:
        workflow = yaml.load(text, Loader=GithubLoader)
    except yaml.YAMLError:
        return [f'{name}: invalid YAML']
    if not isinstance(workflow, dict): return [f'{name}: expected workflow mapping']
    events = workflow.get('on', {})
    if isinstance(events, str): events = {events: None}
    if isinstance(events, list): events = {event: None for event in events}
    if not isinstance(events, dict): return [f'{name}: invalid trigger configuration']
    if 'pull_request_target' in events: fail('pull_request_target is not allowed')
    pr = 'pull_request' in events
    if pr and re.search(r'\bsecrets\s*\.', text): fail('PR workflow must not reference secrets')
    def permissions(value):
        return isinstance(value, dict) and value.get('contents') == 'read' and all(v in ('read','none') for v in value.values())
    if not permissions(workflow.get('permissions')): fail('explicit read-only permissions with contents: read required')
    for job_name, job in workflow.get('jobs', {}).items():
        if 'permissions' in job and not permissions(job['permissions']): fail(f'{job_name}: write permissions are not allowed')
        if pr and job.get('environment'): fail(f'{job_name}: PR jobs must not use deployment environments')
        for step in job.get('steps', []):
            uses = step.get('uses', '')
            if uses and not uses.startswith('./') and not re.fullmatch(r'[^@]+@[0-9a-f]{40}', uses):
                fail(f'{job_name}: external Actions must be pinned to full commit SHA')
            if uses.startswith('actions/checkout@') and step.get('with', {}).get('persist-credentials') is not False:
                fail(f'{job_name}: checkout must disable credential persistence')
            if re.search(r'\$\{\{\s*(github\.event\.(?:pull_request|issue|comment)|inputs\.)', step.get('run','')):
                fail(f'{job_name}: pass event text through env, not inline shell expressions')
        if job.get('environment'):
            if set(events) != {'workflow_dispatch'}: fail(f'{job_name}: deployment must be manual-only')
            condition = job.get('if', '').strip()
            if condition.startswith('${{') and condition.endswith('}}'): condition = condition[3:-2].strip()
            if condition != "github.ref == 'refs/heads/main'": fail(f'{job_name}: deployment requires an explicit main-only guard')
    return errors

def tracked_errors(paths):
    errors = []
    pattern = re.compile(r'\.(?:p12|p8|mobileprovision)(?:\.|$)|\.(?:key|cer)$|(?:^|/)(?:[^/]*password[^/]*|team-id)\.txt$',re.I)
    for name in paths:
        if pattern.search(name): errors.append(f'{name}: signing material or credential file must not be tracked')
    return errors

def main():
    errors = []
    for path in sorted(Path('.github/workflows').glob('*.y*ml')):
        errors.extend(workflow_errors(str(path),path.read_text()))
    paths = subprocess.check_output(['git','-c','safe.directory=/workspace','ls-files','-z']).decode().split('\0')
    errors.extend(tracked_errors(filter(None,paths)))
    for error in errors: print(error)
    if errors: raise SystemExit(1)
    print('PASS: read-only PR permissions, pinned Actions, no PR secrets, guarded manual deployments, no signing files tracked')

if __name__ == '__main__': main()
