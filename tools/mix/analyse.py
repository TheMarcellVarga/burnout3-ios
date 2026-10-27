"""analyse.py <run>: BO-114 mix study report for one traced run (runs/<run>/mix.txt)."""
import sys, re, math, time, collections, json
import mixlib
SPK6=['FL','FR','C','LFE','SL','SR']
def db(x): return 10*math.log10(x) if x>0 else -99.9
RULES=[ # (bus, regex on wave name)   -- positional/2D SFX named by their wave
 ('Player engine', r'^(eng|ex)_\d+$'),          # refined below: bin 17/18 = player, panned = other cars
 ('Boost',         r'^boost(in|out|loop|sml|big)$|^flash$'),
 ('Traffic',       r'^(buseng|trkeng|traff_horn|truck_horn|staticpass|bstps[ls]|p1horn|airbrake|Tram|gvl)'),
 ('Tyres/road/wind', r'^(tar|cartar|const|wood|smltrafskd|lrgtrafskd|kurbbounce)'),
 ('Impacts/crash', r'^(impact|carpart|glass|carscrap|airram|exp$|fire$|steam|caralarm|shunt|slam|crashescap|gear_)'),
 ('UI/HUD',        r'^(Select|Back|back|Vertical|vertical|kbmove|count|cash|cbreak|timer|swoosh|staticlp|ident|Beep|Menu|GSweep|GTurn|Globe|Zoom|Resolve|Icon|Text|p_|ding|trophy|take|paint|new_car|RoadShow)'),
]
def classify(r):
    b=r['bins']; stk=r['stack']
    if r['stream'] or (b[:6] in ((0,1,4,5,2,3),(0,1,2,3,4,5)) and r['st']):
        if r['stream']:
            if '00152FB2' in stk: return 'Music'
            if '0001507D' in stk or '0008731B' in stk: return 'Film'
            return 'Stream ?'
        if '0020BD49' in stk: return 'RWS stream'
        return 'Direct ?'
    w=r['wave'].split('|')[0]
    two_d = b[5] in (17,18) and b[0]==0
    if b[:2]==(0,1) and not two_d and w=='?': return 'RWS stream' if '0020BD49' in stk else 'Unknown'
    stereo_sfx = b[:2]==(0,1) and not two_d   # the title's stereo mode: positioned SFX straight to L/R
    for bus,rx in RULES:
        if re.search(rx,w):
            if bus=='Player engine' and not two_d: return 'Other cars'
            return bus
    if w=='?' : return 'Unknown'
    return 'Props/other' # track sound.awd waves etc
def phases(run):
    L=[l.split(' ',1) for l in open('runs/%s/scene.txt'%run).read().splitlines()]
    def ts(s):
        h,m,x=map(int,s.split(':')); return h*3600+m*60+x
    ev=[(ts(a),b) for a,b in L]
    def at(rx,n=0):
        m=[t for t,b in ev if re.search(rx,b)]; return m[n] if m else None
    P=[]
    if 'race' in run:
        P=[('front end',at('PHASE menu'),at('PHASE loading')),('race',at('PHASE race'),at('PHASE pause')),('pause menu',at('PHASE pause')+1,at('PHASE resumed'))]
    else:
        P=[('front end',at('main menu'),at('car select')),('film (crash training)',at('Crash Training')+3,at('junction streamed')-3),
           ('crash run-up',at('captions'),at('impact')),('crash slow-mo + results',at('impact'),at('at Crash Results'))]
    return P
def main(run):
    T=mixlib.Trace('runs/%s/mix.txt'%run)
    day0=time.localtime(T.wall[min(T.wall)])
    base=time.mktime((day0.tm_year,day0.tm_mon,day0.tm_mday,0,0,0,0,0,-1))
    tw={t:int(w-base) for t,w in T.wall.items()}
    nch=T.O[-1]['ch']; SP=SPK6 if nch==6 else ['L','R']
    out={'run':run,'layout':nch,'phases':{}}
    for r in T.V: r['cat']=classify(r)
    print('=== %s (%s) ==='%(run,'5.1' if nch==6 else 'stereo'))
    for name,a,b in phases(run):
        secs=[t for t,w in tw.items() if a<=w<b]
        if not secs: continue
        n=len(secs)*48000.0; S=set(secs)
        V=[r for r in T.V if r['t'] in S]; O=[o for o in T.O if o['t'] in S]
        print('\n-- %s: %d s (t=%d..%d)'%(name,len(secs),min(secs),max(secs)))
        osq=[sum(o['sq'][c] for o in O) for c in range(nch)]
        print('   output RMS dBFS  '+'  '.join('%s %6.1f'%(SP[c],db(osq[c]/n)) for c in range(nch)))
        print('   output peak dBFS '+'  '.join('%s %6.1f'%(SP[c],db(max(o['peak'][c] for o in O)**2)) for c in range(nch)))
        print('   samples over full scale before the clamp: '+' '.join('%s %d'%(SP[c],sum(o['over'][c] for o in O)) for c in range(nch))+'  of %d'%n)
        cat=collections.defaultdict(lambda:[0.0]*nch); cnt=collections.Counter(); act=collections.Counter(); pk=collections.Counter()
        for r in V:
            act[r['cat']]+=1
            if max(r['spk'])>0:
                cnt[r['cat']]+=1
                for c in range(nch): cat[r['cat']][c]+=r['spk'][c]
                pk[r['cat']]=max(pk[r['cat']],r['peak'])
        print('   %-18s %6s %6s %6s | share of the bus on each speaker, dB re its total (%s)'%('bus','dBFS','peak','voices','  '.join(SP)))
        ph={}
        for k,v in sorted(cat.items(),key=lambda x:-sum(x[1])):
            tot=sum(v)
            print('   %-18s %6.1f %6.1f %6.1f | '%(k,db(tot/n),db(pk[k]**2),cnt[k]/len(secs))+' '.join('%6.1f'%(db(x/tot) if tot else -99.9) for x in v))
            ph[k]=dict(dbfs=db(tot/n),share=[db(x/tot) for x in v],voices=cnt[k]/len(secs))
        tsum=[sum(v[c] for v in cat.values()) for c in range(nch)]
        print('   sum of buses (power) vs output, dB: '+' '.join('%s %+.1f'%(SP[c],db(tsum[c])-db(osq[c])) for c in range(nch) if osq[c]>0))
        print('   active voices/s (audible + silent): '+', '.join('%s %.0f+%.0f'%(k,cnt[k]/len(secs),(act[k]-cnt[k])/len(secs)) for k in sorted(act)))
        un=collections.Counter(r['wave'] for r in V if r['cat'] in('Props/other','Unknown') and max(r['spk'])>0)
        if un: print('   Props/other waves:',dict(un.most_common(12)))
        out['phases'][name]=ph
    json.dump(dict(out=out,tw=tw),open('runs/%s/report.json'%run,'w'))
    return T,tw
if __name__=='__main__':
    for run in sys.argv[1:]: main(run)
