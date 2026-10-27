"""plots.py <run>...: speaker levels, bus levels and voice counts over time (plots/<run>_*.png, .csv)."""
import sys, math, collections, os
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
import analyse, mixlib
db=analyse.db
BUS=['Music','Film','RWS stream','Player engine','Other cars','Traffic','Tyres/road/wind','Impacts/crash','Boost','UI/HUD','Props/other']
COL=['#2a78d6','#7a52c7','#8a8f98','#d6452a','#e08a1e','#c9b81a','#3f9b4b','#b0206a','#18a3a3','#555a66','#a07050']
os.makedirs('plots',exist_ok=True)
for run in sys.argv[1:]:
    T=mixlib.Trace('runs/%s/mix.txt'%run)
    for r in T.V: r['cat']=analyse.classify(r)
    nch=T.O[-1]['ch']; SP=analyse.SPK6 if nch==6 else ['L','R']
    ph=analyse.phases(run)
    import time
    d0=time.localtime(T.wall[min(T.wall)]); base=time.mktime((d0.tm_year,d0.tm_mon,d0.tm_mday,0,0,0,0,0,-1))
    w2t={int(w-base):t for t,w in T.wall.items()}
    def tof(w):
        k=min(w2t,key=lambda x:abs(x-w)); return w2t[k]
    ts=[o['t'] for o in T.O]
    fig,ax=plt.subplots(3,1,figsize=(13,11),sharex=True)
    sc=['#2a78d6','#d6452a','#3f9b4b','#111111','#7a52c7','#e08a1e']
    for c in range(nch):
        ax[0].plot(ts,[db(o['sq'][c]/o['n']) for o in T.O],color=sc[c],label=SP[c]+' RMS',lw=1.4)
        ax[0].plot(ts,[db(o['peak'][c]**2) for o in T.O],color=sc[c],lw=0.6,ls=':')
    ax[0].axhline(0,color='r',lw=0.8); ax[0].set_ylim(-70,8); ax[0].set_ylabel('dBFS (solid RMS, dotted peak before the clamp)')
    ax[0].legend(ncol=6,fontsize=8,loc='lower right'); ax[0].set_title('%s: speaker feeds, %s'%(run,'5.1' if nch==6 else 'stereo'))
    lv=collections.defaultdict(lambda:collections.Counter()); vc=collections.defaultdict(lambda:collections.Counter())
    for r in T.V:
        if max(r['spk'])>0: lv[r['cat']][r['t']]+=sum(r['spk']); vc[r['cat']][r['t']]+=1
    for b,c in zip(BUS,COL):
        if b in lv:
            ax[1].plot(ts,[db(lv[b][t]/48000) if lv[b][t]>0 else float('nan') for t in ts],color=c,label=b,lw=1.3)
    ax[1].set_ylim(-70,0); ax[1].set_ylabel('bus level, dBFS RMS (all speakers)'); ax[1].legend(ncol=6,fontsize=8,loc='lower right')
    bot=[0]*len(ts)
    for b,c in zip(BUS,COL):
        if b in vc:
            y=[vc[b][t] for t in ts]; ax[2].bar(ts,y,bottom=bot,color=c,width=1.0,label=b); bot=[a+q for a,q in zip(bot,y)]
    ax[2].set_ylabel('audible voices'); ax[2].set_xlabel('s since the APU started'); ax[2].legend(ncol=6,fontsize=8)
    for name,a,b in ph:
        for x in ax: x.axvspan(tof(a),tof(b),color='k',alpha=0.05)
        ax[0].text(tof(a)+0.5,5,name,fontsize=8,va='top')
    for x in ax: x.grid(alpha=0.25)
    fig.tight_layout(); fig.savefig('plots/%s_levels.png'%run,dpi=110); plt.close(fig)
    with open('plots/%s_speakers.csv'%run,'w') as f:
        f.write('t,'+','.join(s+'_rms_dbfs' for s in SP)+','+','.join(s+'_peak_dbfs' for s in SP)+','+','.join(s+'_over' for s in SP)+'\n')
        for o in T.O: f.write('%d,'%o['t']+','.join('%.1f'%db(o['sq'][c]/o['n']) for c in range(nch))+','+','.join('%.1f'%db(o['peak'][c]**2) for c in range(nch))+','+','.join(str(o['over'][c]) for c in range(nch))+'\n')
    with open('plots/%s_buses.csv'%run,'w') as f:
        f.write('t,bus,voices,'+','.join(s+'_dbfs' for s in SP)+'\n')
        acc=collections.defaultdict(lambda:[0,[0.0]*nch])
        for r in T.V:
            if max(r['spk'])>0:
                a=acc[(r['t'],r['cat'])]; a[0]+=1
                for c in range(nch): a[1][c]+=r['spk'][c]
        for (t,b),(n,v) in sorted(acc.items()): f.write('%d,%s,%d,'%(t,b,n)+','.join('%.1f'%db(x/48000) for x in v)+'\n')
    # speaker share matrix heat table for the main phase
    if nch==6:
        P=[p for p in ph if p[0] in('race','crash run-up','crash slow-mo + results')]
        fig,axs=plt.subplots(1,len(P),figsize=(7*len(P),4.2))
        if len(P)==1: axs=[axs]
        for axx,(name,a,b) in zip(axs,P):
            S={t for w,t in w2t.items() if a<=w<b}
            m=collections.defaultdict(lambda:[0.0]*6)
            for r in T.V:
                if r['t'] in S:
                    for c in range(6): m[r['cat']][c]+=r['spk'][c]
            rows=[k for k in BUS if k in m and sum(m[k])>0]
            Z=[[max(-40,db(m[k][c]/sum(m[k]))) for c in range(6)] for k in rows]
            im=axx.imshow(Z,cmap='viridis',vmin=-40,vmax=0,aspect='auto')
            axx.set_xticks(range(6)); axx.set_xticklabels(SP); axx.set_yticks(range(len(rows))); axx.set_yticklabels(['%s (%.0f dBFS)'%(k,db(sum(m[k])/(len(S)*48000))) for k in rows],fontsize=8)
            for i in range(len(rows)):
                for j in range(6):
                    v=db(m[rows[i]][j]/sum(m[rows[i]])); axx.text(j,i,'%.0f'%v if v>-99 else '-',ha='center',va='center',color='w' if v<-12 else 'k',fontsize=8)
            axx.set_title('%s: %s, share of each bus per speaker (dB re bus total)'%(run,name),fontsize=9)
        fig.tight_layout(); fig.savefig('plots/%s_matrix.png'%run,dpi=110); plt.close(fig)
    print('plots for',run)
