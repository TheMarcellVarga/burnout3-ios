"""RE helpers over the regen's analysis: string -> referencing functions, callers."""
import json, re, bisect, sys, struct
import os
B=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..') + '/'
A=json.load(open(B+'build/xr/analysis.json'))
SECS=[(int(s['virtual_addr'],16), s['virtual_size'], int(s['raw_addr'],16), s['raw_size'], s['name']) for s in A['sections']]
XBE=open(B+'Burnout 3 Takedown/default.xbe','rb').read()
FN=sorted((int(f['start'],16), int(f['end'],16), f) for f in json.load(open(B+'build/xr/disasm/functions.json')))
ST=[f[0] for f in FN]
def off2va(o):
    for va,vs,ra,rs,n in SECS:
        if ra<=o<ra+rs: return va+o-ra
def va2off(v):
    for va,vs,ra,rs,n in SECS:
        if va<=v<va+min(vs,rs): return ra+v-va
def rd(v,n): o=va2off(v); return XBE[o:o+n] if o is not None else b''
def u32(v): return struct.unpack('<I',rd(v,4))[0]
def f32(v): return struct.unpack('<f',rd(v,4))[0]
def cstr(v):
    o=va2off(v); e=XBE.index(b'\0',o); return XBE[o:e].decode('latin1')
def func_of(a):
    i=bisect.bisect_right(ST,a)-1
    if i>=0 and FN[i][0]<=a<FN[i][1]: return FN[i][2]
def sec_of(a):
    for va,vs,ra,rs,n in SECS:
        if va<=a<va+vs: return n
def strings(rx):
    out=[]
    for m in re.finditer(rb'[\x20-\x7e]{4,}\0', XBE):
        s=m.group()[:-1].decode()
        if re.search(rx,s,re.I):
            va=off2va(m.start())
            if va: out.append((va,s))
    return out
def refs(va):
    """code locations holding imm32 == va"""
    pat=struct.pack('<I',va); out=[]; i=0
    while True:
        i=XBE.find(pat,i)
        if i<0: break
        a=off2va(i)
        if a: out.append(a)
        i+=1
    return out
if __name__=='__main__':
    for va,s in strings(sys.argv[1]):
        rs=refs(va)
        fs=sorted({(func_of(r) or {}).get('name','data@%08X'%r) for r in rs})
        print('%08X %-50s %s'%(va,s,' '.join(fs)))
