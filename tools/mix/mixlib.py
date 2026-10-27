"""mixlib.py: read a RECOMP_MIX_TRACE file and name each voice's wave (BO-114 study)."""
import os, re, struct, glob, collections
DISC=os.environ.get('BO3_DISC', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'Burnout 3 Takedown')) + '/'
def awd_waves(path):
    """RenderWare Audio wave dictionary: each wave's entry starts its format
    block with 60 2E 0F 10; +4 rate, +0xC bytes, +0x40 data offset, +0x60 name."""
    d=open(path,'rb').read()
    if len(d)<0x40: return []
    data0=struct.unpack_from('<I',d,8)[0]
    out=[]; i=0; sig=b'\x60\x2e\x0f\x10'
    if data0<=0 or data0>len(d): return []
    while True:
        i=d.find(sig,i)
        if i<0 or i+0x64>data0: break
        rate,_,ln=struct.unpack_from('<III',d,i+4)
        off=struct.unpack_from('<I',d,i+0x40)[0]
        e=d.find(b'\0',i+0x60); name=d[i+0x60:e]
        if 1<=len(name)<=28 and all(32<=c<127 for c in name) and data0+off<len(d):
            out.append(dict(file=os.path.relpath(path,DISC).lower(),name=name.decode(),off=off,len=ln,rate=rate,pos=data0+off))
        i+=4
    return out
_W=None; _D={}
def fdata(rel):
    if rel not in _D: _D[rel]=open(DISC+rel,'rb').read()
    return _D[rel]
def waves():
    global _W
    if _W is None:
        _W=[]
        for root,ds,fs in os.walk(DISC):
            for f in fs:
                if f.lower().endswith(('.awd','.hwd','.lwd')): _W+=awd_waves(os.path.join(root,f))
    return _W
_IDX=None
def match(c0,c2,o2):
    """the waves whose data starts with c0 and has c2 at +o2"""
    global _IDX
    if _IDX is None:
        _IDX=collections.defaultdict(list)
        for root,ds,fs in os.walk(DISC):
            for f in fs:
                if f.lower().endswith(('.awd','.hwd','.lwd')):
                    rel=os.path.relpath(os.path.join(root,f),DISC); d=fdata(rel)
                    for w in awd_waves(os.path.join(root,f)):
                        w['rel']=rel; _IDX[(d[w['pos']:w['pos']+16], d[w['pos']+o2:w['pos']+o2+16] if w['len']>o2+16 else b'')].append(w)
    r=_IDX.get((c0[:16],c2[:16]),[])
    if not r and len(c2)<16: r=[w for (a,b),ws in _IDX.items() if a==c0[:16] for w in ws if w['len']<=o2+16]
    return r
def kv(line):
    return dict(x.split('=',1) for x in line.split()[1:] if '=' in x)
class Trace:
    def __init__(s,path):
        s.on={}; s.buf={}; s.V=[]; s.O=[]; s.wall={}; s.onf={}
        for line in open(path,errors='replace'):
            t=line[:2]
            if t=='ON':
                k=kv(line); s.on[int(k['id'])]=k.get('stack','').split(',') if k.get('stack') else []; s.onf[int(k['id'])]=int(k['f'])
            elif t=='B ':
                k=kv(line); hx=k.get('hex',',').split(','); c0=bytes.fromhex(hx[0]); c2=bytes.fromhex(hx[1]) if len(hx)>1 else b''
                c=match(c0,c2,int(k.get('o2',1024))) if len(c0)>=16 else []
                names=sorted({w['name'] for w in c}); files=sorted({w['file'] for w in c})
                s.buf[k['pa']]=('|'.join(names) if names else '?', files, int(k['ebo']))
            elif t=='V ':
                k=kv(line)
                r=dict(t=int(k['t']),id=int(k['id']),v=int(k['v']),d3=int(k['3d']),st=int(k['st']),stream=int(k['stream']),
                       fmt=int(k['fmt'],16),fmode=int(k['fmode']),hrtf=int(k['hrtf']),rate=float(k['rate']),ea=float(k['ea']),
                       ba=k['ba'],ebo=int(k['ebo']),frames=int(k['frames']),src=float(k['src']),
                       bins=tuple(int(x) for x in k['bins'].split(',')),vols=tuple(int(x,16) for x in k['vols'].split(',')),
                       spk=[float(x) for x in k['spk'].split(',')],peak=float(k['peak']))
                s.V.append(r)
            elif t=='O ':
                k=kv(line)
                s.O.append(dict(t=int(k['t']),ch=int(k['ch']),sq=[float(x) for x in k['sq'].split(',')],
                                peak=[float(x) for x in k['peak'].split(',')],over=[int(x) for x in k['over'].split(',')],n=int(k['n'])))
            elif t=='T ':
                k=kv(line); s.wall[int(k['t'])]=int(k['wall'])
        for r in s.V:
            b=s.buf.get(r['ba'])
            r['wave']=b[0] if b else ('<stream>' if r['stream'] else '?')
            r['wfile']=','.join(b[1]) if b else ''
            r['stack']=s.on.get(r['id'],[])
