"""Refresh curated manifests from fixed model revisions, never from a mutable main branch."""
import concurrent.futures, hashlib, json, urllib.parse, urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]/'Packages/VoiceLearning/Sources/NeuralTTSBackends/Resources'
REVISIONS={'kokoro':'2568276a60ff6e7f312afce3dc9e3f07521cb48d','pocket':'c2e998e269e4d4b51f74061faddb8450cd8f9a9a'}
def get(url):
    with urllib.request.urlopen(url,timeout=90) as response: return response.read()
def tree(repo,revision,path):
    url=f'https://huggingface.co/api/models/{repo}/tree/{revision}/{path}?recursive=true&limit=1000'
    result=[]
    while url:
        with urllib.request.urlopen(url,timeout=90) as response:
            result.extend(json.load(response)); link=response.headers.get('Link','')
        next_links=[part.split('>')[0].strip(' <') for part in link.split(',') if 'rel="next"' in part]
        url=next_links[0] if next_links else None
    return [entry for entry in result if entry['type']=='file']
def build(engine,repo,entries):
    revision=REVISIONS[engine]
    def record(entry):
        path=entry['path']; sha=entry.get('lfs',{}).get('oid')
        if not sha:
            assert entry['size']<8_000_000, 'Unexpected large non-LFS asset'
            sha=hashlib.sha256(get(f'https://huggingface.co/{repo}/resolve/{revision}/{urllib.parse.quote(path)}')).hexdigest()
        return {'path':path,'sha256':sha,'size':entry['size']}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as workers:
        files=sorted(workers.map(record,entries),key=lambda f:f['path'])
    manifest={'id':engine,'repository':repo,'revision':revision,'files':files}
    if engine == 'pocket': manifest['storageFolder']='pocket-tts'
    ROOT.mkdir(parents=True,exist_ok=True)
    (ROOT/f'{engine}.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(engine,len(files),'files',sum(f['size'] for f in files),'bytes')
repo='FluidInference/kokoro-82m-coreml';rev=REVISIONS['kokoro']
ane=tree(repo,rev,'ANE')
required=['KokoroAlbert.mlmodelc','KokoroPostAlbert.mlmodelc','KokoroAlignment.mlmodelc','KokoroProsody_v2.mlmodelc','KokoroNoise_v2.mlmodelc','KokoroVocoder.mlmodelc','KokoroTail_v2.mlmodelc']
entries=[e for e in ane if any(e['path'].startswith('ANE/'+name+'/') for name in required) or e['path'] in ['ANE/af_heart.bin','ANE/vocab.json']]
for folder in ['G2PEncoder.mlmodelc','G2PDecoder.mlmodelc']: entries+=tree(repo,rev,folder)
root=tree(repo,rev,'')
entries += [e for e in root if e['path'] in ['g2p_vocab.json','us_lexicon_cache.json']]
build('kokoro',repo,entries)
repo='FluidInference/pocket-tts-coreml';rev=REVISIONS['pocket'];prefix='v2.1/english/'
entries=tree(repo,rev,'v2.1/english')
models=['cond_prefill.mlmodelc','flowlm_step.mlmodelc','flow_decoder_fused.mlmodelc','mimi_decoder.mlmodelc']
entries=[e for e in entries if any(e['path'].startswith(prefix+m+'/') for m in models) or
         (e['path'].startswith(prefix+'constants_bin/') and
          (not e['path'].endswith('.safetensors') or e['path'].endswith('/alba.safetensors')))]
build('pocket',repo,entries)
