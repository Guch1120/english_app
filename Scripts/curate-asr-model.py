"""Create the allowlisted Parakeet TDT-CTC 110M file manifest at an immutable revision."""
import concurrent.futures
import hashlib
import json
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "Packages/VoiceLearning/Sources/NeuralASRBackends/Resources"
REPO = "FluidInference/parakeet-tdt-ctc-110m-coreml"
REVISION = "9bc92ead6e8f17eca92a869fd578ae76842b82ba"
PREFIXES = ("Preprocessor.mlmodelc/", "Decoder.mlmodelc/", "JointDecision.mlmodelc/")

def get(url):
    with urllib.request.urlopen(url, timeout=90) as response:
        return response.read()

url = f"https://huggingface.co/api/models/{REPO}/tree/{REVISION}?recursive=true&limit=1000"
with urllib.request.urlopen(url, timeout=90) as response:
    entries = json.load(response)
entries = [entry for entry in entries if entry.get("type") == "file" and
          (entry["path"].startswith(PREFIXES) or entry["path"] == "parakeet_vocab.json")]

def record(entry):
    path = entry["path"]
    digest = (entry.get("lfs") or {}).get("oid")
    if not digest:
        if entry["size"] > 8_000_000:
            raise ValueError(f"Unexpected large non-LFS asset: {path}")
        digest = hashlib.sha256(get(f"https://huggingface.co/{REPO}/resolve/{REVISION}/{urllib.parse.quote(path)}")).hexdigest()
    return {"path": path, "sha256": digest, "size": entry["size"]}

with concurrent.futures.ThreadPoolExecutor(max_workers=6) as workers:
    files = sorted(workers.map(record, entries), key=lambda item: item["path"])
manifest = {"id": "parakeet-tdt-ctc-110m", "repository": REPO, "revision": REVISION,
            "storageFolder": "parakeet-tdt-ctc-110m-coreml", "files": files}
ROOT.mkdir(parents=True, exist_ok=True)
(ROOT / "parakeet.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"{len(files)} files; {sum(item['size'] for item in files)} bytes")
