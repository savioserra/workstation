# usage: python3 order-only-proof.py <old.drv> <new.drv>
# For every derivation nix-diff reports as differing between two leg
# closures: SAME-modulo-input-hashes (env equal once store hashes are
# normalized), ORDER-ONLY (same inputs, different order: a reordered list
# merge such as home.packages / environment.systemPackages) or
# CONTENT-DIFFERS. RESULT OK = no content change.
import json, re, subprocess, sys, collections
nd = subprocess.check_output(['nix','build','--no-link','--print-out-paths','nixpkgs#nix-diff'],text=True).strip()+'/bin/nix-diff'
a, b = sys.argv[1], sys.argv[2]
out = subprocess.run([nd,'--color','never',a,b],capture_output=True,text=True).stdout.splitlines()
pairs=[]
for i,l in enumerate(out):
    m=re.search(r'input derivation named `([^`]+)` differs',l)
    if m and i+2<len(out):
        pa=re.search(r'/nix/store/\S+\.drv',out[i+1]); pb=re.search(r'/nix/store/\S+\.drv',out[i+2])
        if pa and pb: pairs.append((m.group(1),pa.group(0),pb.group(0)))
def norm(d):
    j=json.loads(subprocess.check_output(['nix','derivation','show',d],text=True,stderr=subprocess.DEVNULL))
    j=j.get('derivations',j); v=list(j.values())[0]
    s=json.dumps({'env':v.get('env'),'args':v.get('args'),'structured':v.get('structuredAttrs')},sort_keys=True)
    s=re.sub(r'/nix/store/[a-z0-9]{32}-','/nix/store/H-',s)
    return s
seen=set(); bad=0
for name,pa,pb in pairs:
    if (pa,pb) in seen: continue
    seen.add((pa,pb))
    na,nb=norm(pa),norm(pb)
    if na==nb: verdict='SAME-modulo-input-hashes'
    elif collections.Counter(re.findall(r'/nix/store/H-[^"\\ ]*',na))==collections.Counter(re.findall(r'/nix/store/H-[^"\\ ]*',nb)) and sorted(na)==sorted(nb): verdict='ORDER-ONLY'
    else: verdict='CONTENT-DIFFERS'; bad+=1
    print(f'  {name}: {verdict}')
print('RESULT', 'OK' if bad==0 else f'{bad} CONTENT DIFFS')
