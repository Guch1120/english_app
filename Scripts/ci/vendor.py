"""Check the checked-in SDK snapshot against its recorded source digests (no network)."""
import hashlib,json
from pathlib import Path
root=Path('Vendor/FluidAudio')
if root.exists():
    manifest=json.loads((root/'UPSTREAM.json').read_text())
    actual={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (root/'Sources').rglob('*') if p.is_file()}
    if actual != manifest['sourceFiles']: raise SystemExit('Vendor SDK source differs from pinned manifest; review and repin explicitly')
    if any((root/'Sources').rglob('*.tsv.zz')): raise SystemExit('Unused LuxTTS G2P resources must not be bundled')
    print('PASS: unchanged FluidAudio source snapshot; unused LuxTTS G2P data excluded')
