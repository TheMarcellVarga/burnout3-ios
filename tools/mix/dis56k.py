"""A small DSP56300 disassembler, written from Motorola's DSP56300 Family
Manual (appendix A, instruction encodings), for reading a title's GP effects
image. Only what the image uses; anything else prints as '??'."""
import sys, numpy as np

R6 = ['?00','?01','?02','?03','X0','X1','Y0','Y1','A0','B0','A2','B2','A1','B1','A','B',
      'R0','R1','R2','R3','R4','R5','R6','R7','N0','N1','N2','N3','N4','N5','N6','N7',
      'M0','M1','M2','M3','M4','M5','M6','M7','?28','?29','EP','?2B','?2C','?2D','?2E','?2F',
      'VBA','SC','?32','?33','?34','?35','?36','?37','SZ','SR','OMR','SP','SSH','SSL','LA','LC']
R5 = R6[:32]
R4 = ['?0','?1','?2','?3','X0','X1','Y0','Y1','A0','B0','A2','B2','A1','B1','A','B']
CC = ['CC','GE','NE','PL','NN','EC','LC','GT','CS','LT','EQ','MI','NR','ES','LS','LE']
JJJ = [None,'ob','X','Y','X0','Y0','X1','Y1']
QQQ = ['X0,X0','Y0,Y0','X1,X0','Y1,Y0','X0,Y1','Y0,X0','X1,Y0','Y1,X1']

def sx(v, bits):
    return v - (1 << bits) if v >> (bits - 1) else v

def ea(mmmrrr, ext):
    m, r = mmmrrr >> 3, mmmrrr & 7
    if m == 0: return '(R%d)-N%d' % (r, r), 0
    if m == 1: return '(R%d)+N%d' % (r, r), 0
    if m == 2: return '(R%d)-' % r, 0
    if m == 3: return '(R%d)+' % r, 0
    if m == 4: return '(R%d)' % r, 0
    if m == 5: return '(R%d+N%d)' % (r, r), 0
    if m == 7: return '-(R%d)' % r, 0
    if r == 0: return '$%06X' % ext, 1
    if r == 4: return '#$%06X' % ext, 1
    return '?ea', 0

def alu(op):
    d = 'B' if op & 8 else 'A'; o = 'A' if op & 8 else 'B'
    if op & 0x80:
        q = QQQ[(op >> 4) & 7]; k = '-' if op & 4 else ''
        return '%s %s%s,%s' % (['MPY','MPYR','MAC','MACR'][op & 3], k, q, d)
    hi, lo = (op >> 4) & 7, op & 7
    if hi == 0:
        return {0:'MOVE',1:'TFR %s,%s'%(o,d),2:'ADDR %s,%s'%(o,d),3:'TST '+d,4:'?alu04',5:'CMP %s,%s'%(o,d),6:'SUBR %s,%s'%(o,d),7:'CMPM %s,%s'%(o,d)}[lo]
    if hi == 1:
        return {0:'ADD %s,%s'%(o,d),1:'RND '+d,2:'ADDL %s,%s'%(o,d),3:'CLR '+d,4:'SUB %s,%s'%(o,d),5:'?alu15',6:'SUBL %s,%s'%(o,d),7:'NOT '+d}[lo]
    if hi == 2:
        return {0:'ADD X,'+d,1:'ADC X,'+d,2:'ASR '+d,3:'LSR '+d,4:'SUB X,'+d,5:'SBC X,'+d,6:'ABS '+d,7:'ROR '+d}[lo]
    if hi == 3:
        return {0:'ADD Y,'+d,1:'ADC Y,'+d,2:'ASL '+d,3:'LSL '+d,4:'SUB Y,'+d,5:'SBC Y,'+d,6:'NEG '+d,7:'ROL '+d}[lo]
    s = JJJ[hi]
    return '%s %s,%s' % (['ADD','TFR','OR','EOR','SUB','CMP','AND','CMPM'][lo], s, d)

def pmove(w, ext):
    """Parallel move field of a data ALU instruction (bits 23..8)."""
    hi = w >> 8
    n = 0
    if hi == 0x2000: return '', 0
    top = hi >> 12
    if top == 2:
        if (hi & 0xFFE0) == 0x2040:
            e, n = ea((hi & 0x1F) | 0, ext)  # U: update, mm rrr
            mm, r = (hi >> 3) & 3, hi & 7
            return ' ' + ['(R%d)-N%d','(R%d)+N%d','(R%d)-','(R%d)+'][mm].replace('%d', str(r)) , 0
        if (hi & 0xFC00) == 0x2000 and (hi >> 5) & 0x1F:
            return ' %s,%s' % (R5[(hi >> 5) & 0x1F], R5[hi & 0x1F]), 0
        if (hi & 0xFFF0) == 0x2020: return ' IF' + CC[hi & 15], 0
        if (hi & 0xFFF0) == 0x2030: return ' IF%s.U' % CC[hi & 15], 0
    if top in (2, 3):
        return ' #$%02X,%s' % (hi & 0xFF, R5[(hi >> 8) & 0x1F]), 0
    if top == 1:
        # X:R / R:Y class I
        return ' ?XR/RY(%04X)' % hi, 0
    if top in (4, 5, 6, 7):
        if (hi & 0xF400) == 0x4000:      # L:
            lll = ((hi >> 9) & 4) | ((hi >> 8) & 3)
            reg = ['A10','B10','X','Y','A','B','AB','BA'][lll]
            wr = hi & 0x80
            if hi & 0x40: e, n = ea(hi & 0x3F, ext)
            else: e = '$%02X' % (hi & 0x3F)
            return (' L:%s,%s' % (e, reg) if wr else ' %s,L:%s' % (reg, e)), n
        d = ((hi >> 9) & 0x18) | ((hi >> 8) & 7)
        sp = 'Y' if hi & 0x0800 else 'X'
        wr = hi & 0x80
        if hi & 0x40: e, n = ea(hi & 0x3F, ext)
        else: e = '$%02X' % (hi & 0x3F)
        if e.startswith('#'): return ' %s,%s' % (e, R5[d]), n
        return (' %s:%s,%s' % (sp, e, R5[d]) if wr else ' %s,%s:%s' % (R5[d], sp, e)), n
    # X: Y: dual
    wy, wx = hi & 0x4000, hi & 0x8000 and 0  # placeholder
    mmx, rx = (hi >> 3) & 3, hi & 7
    mmy, ry = (hi >> 12) & 3, ((hi >> 5) & 3)
    ry = (ry + 4) if rx < 4 else ry
    xr = ['X0','X1','A','B'][(hi >> 10) & 3]; yr = ['Y0','Y1','A','B'][(hi >> 8) & 3]
    xe = ['(R%d)+N%d','(R%d)-','(R%d)+','(R%d)'][mmx].replace('%d', str(rx))
    ye = ['(R%d)+N%d','(R%d)-','(R%d)+','(R%d)'][mmy].replace('%d', str(ry))
    xw = hi & 0x80; yw = hi & 0x4000
    a = 'X:%s,%s' % (xe, xr) if xw else '%s,X:%s' % (xr, xe)
    b = 'Y:%s,%s' % (ye, yr) if yw else '%s,Y:%s' % (yr, ye)
    return ' %s %s' % (a, b), 0

def dis(w, ext, pc):
    """-> (text, words)"""
    if w >> 20:
        m, n = pmove(w, ext)
        return alu(w & 0xFF) + m, 1 + n
    b2, b1, b0 = (w >> 16) & 0xFF, (w >> 8) & 0xFF, w & 0xFF
    if w == 0: return 'NOP', 1
    if w == 0x00000C: return 'RTS', 1
    if w == 0x000004: return 'RTI', 1
    if w == 0x00008C: return 'ENDDO', 1
    if (w & 0xFFF0C0) == 0x0000C0 or (w & 0xFF00F0) == 0x0000F0 and 0: pass
    if (w & 0xFFFFC0) == 0x0D1080: return 'BSR $%04X' % ((pc + sx(ext, 24)) & 0xFFFFFF), 2
    if (w & 0xFFFFC0) == 0x0D10C0: return 'BRA $%04X' % ((pc + sx(ext, 24)) & 0xFFFFFF), 2
    if (w & 0xFFFFF0) == 0x0D1040: return 'B%s $%04X' % (CC[w & 15], (pc + sx(ext, 24)) & 0xFFFFFF), 2
    if (w & 0xFFFFF0) == 0x0D1000: return 'BS%s $%04X' % (CC[w & 15], (pc + sx(ext, 24)) & 0xFFFFFF), 2
    if (w & 0xFF0400) == 0x050400 and 0: pass
    if b2 == 0x05 and (w & 0xC400) == 0x0400 and (b1 & 0xC0) == 0x00:
        # Bcc short: 0000 0101 CCCC 01aa aa0a aaaa
        cc = (w >> 12) & 15; a = ((w >> 1) & 0x1E0) | (w & 0x1F)
        return 'B%s $%04X' % (CC[cc], (pc + sx(a, 9)) & 0xFFFFFF), 1
    if (w & 0xFFC0FF) == 0x0BC080 or (w & 0xFFC0FF) == 0x0BF080 and 0: pass
    if b2 == 0x0B and (b1 & 0xC0) == 0xC0 and b0 == 0x80:
        e, n = ea(b1 & 0x3F, ext); return 'JSR ' + e, 1 + n
    if b2 == 0x0A and (b1 & 0xC0) == 0xC0 and b0 == 0x80:
        e, n = ea(b1 & 0x3F, ext); return 'JMP ' + e, 1 + n
    if b2 == 0x0B and (b1 & 0xC0) == 0xC0 and (b0 & 0xF0) == 0xA0:
        e, n = ea(b1 & 0x3F, ext); return 'JS%s %s' % (CC[b0 & 15], e), 1 + n
    if b2 == 0x0A and (b1 & 0xC0) == 0xC0 and (b0 & 0xF0) == 0xA0:
        e, n = ea(b1 & 0x3F, ext); return 'J%s %s' % (CC[b0 & 15], e), 1 + n
    if (w & 0xFF0000) == 0x0C0000 and (w & 0xF000) == 0x0000 and b1 < 0x10:
        return 'JMP $%03X' % (w & 0xFFF), 1
    if (w & 0xFF0000) == 0x0D0000 and b1 < 0x10:
        return 'JSR $%03X' % (w & 0xFFF), 1
    if (w & 0xFF0000) == 0x0E0000: return 'J%s $%03X' % (CC[(w >> 12) & 15], w & 0xFFF), 1
    if (w & 0xFF0000) == 0x0F0000: return 'JS%s $%03X' % (CC[(w >> 12) & 15], w & 0xFFF), 1
    # DO / DOR / REP
    if b2 == 0x06:
        if (b0 & 0xF0) == 0x80: return 'DO #$%X,$%04X' % (b1 | ((b0 & 15) << 8), ext + 0), 2
        if (b0 & 0xF0) == 0x90: return 'DOR #$%X,$%04X' % (b1 | ((b0 & 15) << 8), (pc + ext) & 0xFFFFFF), 2
        if (b0 & 0xF0) == 0xA0: return 'REP #$%X' % (b1 | ((b0 & 15) << 8)), 1
        if (b1 & 0xC0) == 0xC0 and b0 == 0x00: return 'DO %s,$%04X' % (R6[b1 & 0x3F], ext), 2
        if (b1 & 0xC0) == 0xC0 and b0 == 0x10: return 'DOR %s,$%04X' % (R6[b1 & 0x3F], (pc + ext) & 0xFFFFFF), 2
        if (b1 & 0xC0) == 0xC0 and b0 == 0x20: return 'REP %s' % R6[b1 & 0x3F], 1
        if (b1 & 0xC0) == 0x40 and (b0 & 0xBF) == 0x00:
            e, n = ea(b1 & 0x3F, ext); return 'DO %s:%s,...' % ('Y' if b0 & 0x40 else 'X', e), 2
    # bit test and branch on registers: 0000 1100 11DD DDDD 10sb bbbb  (BRCLR/BRSET), 0000 1101 11DD DDDD 10sb bbbb (BSCLR/BSSET)
    if b2 == 0x0C and (b1 & 0xC0) == 0xC0 and (b0 & 0xC0) == 0x80:
        return '%s #%d,%s,$%04X' % ('BRSET' if b0 & 0x20 else 'BRCLR', b0 & 0x1F, R6[b1 & 0x3F], (pc + sx(ext, 24)) & 0xFFFFFF), 2
    if b2 == 0x0A and (b1 & 0xC0) == 0xC0 and (b0 & 0xC0) == 0x00 and (b0 & 0x80) == 0 and 0: pass
    if b2 == 0x0A and (b1 & 0xC0) == 0xC0:
        op = {0x00:'JCLR',0x20:'JSET',0x40:'BCLR',0x60:'BSET'}.get(b0 & 0xE0)
        if op in ('BCLR', 'BSET'): return '%s #%d,%s' % (op, b0 & 0x1F, R6[b1 & 0x3F]), 1
        if op: return '%s #%d,%s,$%04X' % (op, b0 & 0x1F, R6[b1 & 0x3F], ext), 2
    if b2 == 0x0B and (b1 & 0xC0) == 0xC0:
        op = {0x40:'BCHG',0x60:'BTST'}.get(b0 & 0xE0)
        if op: return '%s #%d,%s' % (op, b0 & 0x1F, R6[b1 & 0x3F]), 1
    # bit ops on memory: 0000 101x 01MM MRRR  0S?b bbbb
    if b2 in (0x0A, 0x0B) and (b1 & 0xC0) == 0x40 and (b0 & 0x80) == 0:
        e, n = ea(b1 & 0x3F, ext)
        sp = 'Y' if b0 & 0x40 else 'X'
        op = ({0x00:'BCLR',0x20:'BSET'} if b2 == 0x0A else {0x00:'BCHG',0x20:'BTST'}).get(b0 & 0x20 | 0)
        return '%s #%d,%s:%s' % (op, b0 & 0x1F, sp, e), 1 + n
    if b2 in (0x0A, 0x0B) and (b1 & 0xC0) == 0x00:
        sp = 'Y' if b0 & 0x40 else 'X'
        if b0 & 0x80:
            op = ('JSET' if b0 & 0x20 else 'JCLR') if b2 == 0x0A else ('JSSET' if b0 & 0x20 else 'JSCLR')
            return '%s #%d,%s:$%02X,$%04X' % (op, b0 & 0x1F, sp, b1 & 0x3F, ext), 2
        op = (('BSET' if b0 & 0x20 else 'BCLR') if b2 == 0x0A else ('BTST' if b0 & 0x20 else 'BCHG'))
        return '%s #%d,%s:$%02X' % (op, b0 & 0x1F, sp, b1 & 0x3F), 1
    if b2 in (0x0A, 0x0B) and (b1 & 0xC0) == 0x80:
        sp = 'Y' if b0 & 0x40 else 'X'
        if b0 & 0x80:
            op = ('JSET' if b0 & 0x20 else 'JCLR') if b2 == 0x0A else ('JSSET' if b0 & 0x20 else 'JSCLR')
            return '%s #%d,%s:<<$%06X,$%04X' % (op, b0 & 0x1F, sp, 0xFFFFC0 | (b1 & 0x3F), ext), 2
        op = (('BSET' if b0 & 0x20 else 'BCLR') if b2 == 0x0A else ('BTST' if b0 & 0x20 else 'BCHG'))
        return '%s #%d,%s:<<$%06X' % (op, b0 & 0x1F, sp, 0xFFFFC0 | (b1 & 0x3F)), 1
    # MOVE X:(Rn+xxxx),D / S,X:(Rn+xxxx): 0000 101s 0111 0RRR 1WDD DDDD
    if b2 in (0x0A, 0x0B) and (b1 & 0xF8) == 0x70 and (b0 & 0x80):
        sp = 'Y' if b2 == 0x0B else 'X'
        r = b1 & 7; d = R6[b0 & 0x3F]
        a = '%s:(R%d+$%X)' % (sp, r, ext) if ext < 0x800000 else '%s:(R%d-$%X)' % (sp, r, 0x1000000 - ext)
        return ('MOVE %s,%s' % (a, d) if b0 & 0x40 else 'MOVE %s,%s' % (d, a)), 2
    # MOVE X:(Rn+xxx),D short: 0000 001a aaaa aRRR 1asW DDDD
    if (w & 0xFE0080) == 0x020080:
        a = (((w >> 11) & 0x3F) << 1) | ((w >> 6) & 1); a = sx(a, 7)
        sp = 'Y' if w & 0x20 else 'X'; r = (w >> 8) & 7; d = R4[w & 15]
        e = '%s:(R%d%+d)' % (sp, r, a)
        return ('MOVE %s,%s' % (e, d) if w & 0x10 else 'MOVE %s,%s' % (d, e)), 1
    # Tcc: 0000 0010 CCCC 0JJJ d... / with reg: 0000 0011 CCCC 0JJJ dttt 0TTT
    if b2 in (0x02, 0x03) and (b0 & 0x80) == 0:
        cc = CC[(w >> 12) & 15]; j = (w >> 3) & 0xF
        src = {0:'B',1:'A',8:'X0',9:'X0',10:'Y0',11:'Y0',12:'X1',13:'X1',14:'Y1',15:'Y1'}.get(j, '?')
        dst = 'B' if j & 1 else 'A'
        if j == 0: src, dst = 'B', 'A'
        if j == 1: src, dst = 'A', 'B'
        t = 'T%s %s,%s' % (cc, src, dst)
        if b2 == 0x03: t += ' R%d,R%d' % ((w >> 8) & 7, w & 7)
        return t, 1
    # immediate ALU: 0000 0001 01ii iiii 1000 dqqq (short), 0000 0001 0100 0000 1100 dqqq (long)
    if (w & 0xFFC0F0) == 0x014080 or (w & 0xFFFFF0) == 0x0140C0:
        op = ['ADD','?','OR','EOR','SUB','CMP','AND','?'][w & 7]; d = 'B' if w & 8 else 'A'
        if (w & 0xFFFFF0) == 0x0140C0: return '%s #$%06X,%s' % (op, ext, d), 2
        return '%s #$%02X,%s' % (op, (w >> 8) & 0x3F, d), 1
    # multi-bit shifts: 0000 1100 0001 1101 SiiiiiiD ASL; 1100 ASR; LSL/LSR 0C1E80.. skip
    if (w & 0xFFFF00) == 0x0C1D00: return 'ASL #%d,%s,%s' % ((w >> 1) & 0x3F, 'B' if w & 0x80 else 'A', 'B' if w & 1 else 'A'), 1
    if (w & 0xFFFF00) == 0x0C1C00: return 'ASR #%d,%s,%s' % ((w >> 1) & 0x3F, 'B' if w & 0x80 else 'A', 'B' if w & 1 else 'A'), 1
    if (w & 0xFFFFC0) == 0x0C1E80: return 'LSL #%d,%s' % ((w >> 1) & 0x1F, 'B' if w & 1 else 'A'), 1
    if (w & 0xFFFFC0) == 0x0C1EC0: return 'LSR #%d,%s' % ((w >> 1) & 0x1F, 'B' if w & 1 else 'A'), 1
    # MOVEC: 0000 0101 W1MM MRRR 0s1d dddd (ea), 0000 0100 W1ee eeee 101d dddd (reg), 0000 0101 iiii iiii 101d dddd (#xx)
    if b2 == 0x05 and (b1 & 0x40) and (b0 & 0xA0) == 0x20:
        e, n = ea(b1 & 0x3F, ext); d = R6[0x20 | (b0 & 0x1F)]; sp = 'Y' if b0 & 0x40 else 'X'
        if e.startswith('#'): return 'MOVEC %s,%s' % (e, d), 1 + n
        return ('MOVEC %s:%s,%s' % (sp, e, d) if b1 & 0x80 else 'MOVEC %s,%s:%s' % (d, sp, e)), 1 + n
    if b2 == 0x05 and (b1 & 0x40) == 0 and (b0 & 0xA0) == 0x20 and (b1 & 0x80) in (0, 0x80) and (b0 & 0x80) == 0:
        d = R6[0x20 | (b0 & 0x1F)]; sp = 'Y' if b0 & 0x40 else 'X'
        return ('MOVEC %s:$%02X,%s' % (sp, b1 & 0x3F, d) if b1 & 0x80 else 'MOVEC %s,%s:$%02X' % (d, sp, b1 & 0x3F)), 1
    if b2 == 0x04 and (b1 & 0x40) and (b0 & 0xE0) == 0xA0:
        d = R6[0x20 | (b0 & 0x1F)]; s = R6[b1 & 0x3F]
        return ('MOVEC %s,%s' % (s, d) if b1 & 0x80 else 'MOVEC %s,%s' % (d, s)), 1
    if b2 == 0x05 and (b0 & 0xE0) == 0xA0:
        return 'MOVEC #$%02X,%s' % (b1, R6[0x20 | (b0 & 0x1F)]), 1
    # LUA: 0000 0100 010M MRRR 000d dddd ; LUA (Rn+aa),D: 0000 0100 00aa aRRR aaaa dddd
    if (w & 0xFFE0E0) == 0x044000:
        mm, r = (b1 >> 3) & 3, b1 & 7
        return 'LUA %s,%s' % (['(R%d)-N%d','(R%d)+N%d','(R%d)-','(R%d)+'][mm].replace('%d', str(r)), R6[0x10 | (b0 & 0x1F)] if 0 else (('R%d' % (b0 & 7)) if not b0 & 8 else ('N%d' % (b0 & 7)))), 1
    if (w & 0xFFC000) == 0x040000:
        a = sx((((w >> 11) & 7) << 4) | ((w >> 4) & 0xF), 7); r = (w >> 8) & 7
        return 'LUA (R%d%+d),%s' % (r, a, ('R%d' % (w & 7)) if not w & 8 else ('N%d' % (w & 7))), 1
    # MOVEP: 0000 1000 sW1M MMRR R1Sp pppp (X/Y:<<pp with ea), 0000 100s W1dd dddd 00pp pppp (reg)
    if b2 in (0x08, 0x09) and (b1 & 0x40) and (b0 & 0x80):
        e, n = ea(b1 & 0x3F, ext); psp = 'Y' if b2 == 0x09 else 'X'; sp = 'Y' if b0 & 0x40 else 'X'
        pp = '%s:<<$%06X' % (psp, 0xFFFFC0 | (b0 & 0x3F))
        if e.startswith('#'): return 'MOVEP %s,%s' % (e, pp), 1 + n
        return ('MOVEP %s:%s,%s' % (sp, e, pp) if b1 & 0x80 else 'MOVEP %s,%s:%s' % (pp, sp, e)), 1 + n
    if b2 in (0x08, 0x09) and (b1 & 0x40) and (b0 & 0xC0) == 0x00:
        psp = 'Y' if b2 == 0x09 else 'X'; pp = '%s:<<$%06X' % (psp, 0xFFFFC0 | (b0 & 0x3F)); d = R6[b1 & 0x3F]
        return ('MOVEP %s,%s' % (d, pp) if b1 & 0x80 else 'MOVEP %s,%s' % (pp, d)), 1
    # MOVEM: 0000 0111 W1MM MRRR 10dd dddd
    if b2 == 0x07 and (b1 & 0x40) and (b0 & 0xC0) == 0x80:
        e, n = ea(b1 & 0x3F, ext); d = R6[b0 & 0x3F]
        return ('MOVEM P:%s,%s' % (e, d) if b1 & 0x80 else 'MOVEM %s,P:%s' % (d, e)), 1 + n
    # class II X:R / R:Y: 0000 100d 00MM MRRR  (A->X:ea, X0->A) ; 0000 100d 10MM MRRR (Y0->A, A->Y:ea)
    if b2 in (0x08, 0x09) and (b1 & 0x40) == 0:
        e, n = ea(b1 & 0x3F, ext); d = 'B' if b2 & 1 else 'A'
        if b1 & 0x80: m = ' Y0,%s %s,Y:%s' % (d, d, e)
        else: m = ' %s,X:%s X0,%s' % (d, e, d)
        return alu(b0) + m, 1 + n
    # CMP/ADD etc with 0000 0001: MPYI etc.
    if (w & 0xFFFFC0) == 0x0141C0:
        op = ['MPYI','MPYRI','MACI','MACRI'][w & 3]; k = '-' if w & 4 else ''
        return '%s %s#$%06X,%s,%s' % (op, k, ext, ['X0','Y0','X1','Y1'][(w >> 4) & 3], 'B' if w & 8 else 'A'), 2
    if (w & 0xFFF0C0) == 0x0100C0 and 0: pass
    if (w & 0xFFFFF0) == 0x0C1E60 and 0: pass
    # NORMF / MERGE / EXTRACT etc not handled
    # CMPU, DEC, INC: 0000 0000 0000 0000 0000 101d (DEC: 00000A, INC: 000008)
    if (w & 0xFFFFFE) == 0x000008: return 'INC ' + ('B' if w & 1 else 'A'), 1
    if (w & 0xFFFFFE) == 0x00000A: return 'DEC ' + ('B' if w & 1 else 'A'), 1
    if (w & 0xFFFF00) == 0x00B900 and 0: pass
    return '?? %06X' % w, 1

def listing(words, base, start, end):
    pc = start
    out = []
    while pc < end:
        w = int(words[pc - base]) & 0xFFFFFF
        ext = int(words[pc - base + 1]) & 0xFFFFFF if pc + 1 - base < len(words) else 0
        t, n = dis(w, ext, pc)
        out.append('%04X: %06X %s  %s' % (pc, w, ('%06X' % ext) if n == 2 else '      ', t))
        pc += n
    return out

if __name__ == '__main__':
    w = np.fromfile(sys.argv[1], np.uint32)
    off = int(sys.argv[2], 16); n = int(sys.argv[3], 16)
    base = int(sys.argv[4], 16) if len(sys.argv) > 4 else 0
    words = w[off // 4: off // 4 + n]
    print('\n'.join(listing(words, base, base, base + n)))
