using System;
using System.Collections.Generic;

// Cycle model of the bank switching detection in CORE/vhdl/cart.vhd (S_CHECK, S_SIG_RUN,
// S_SIG_DECIDE and the Superchip scan). The cartridge RAM port A latches scan_addr on the
// falling edge, so on each rising edge ram_q_a = ram[scan_addr as set on the previous edge].
public static class CartScanSim
{
    const int BS_SIZE = 0, BS_FE = 3, BS_E0 = 4, BS_3F = 5, BS_P2 = 7, BS_CV = 9, BS_UA = 11, BS_E7 = 12;

    static ulong Win(ulong sr, byte b) { return ((sr << 8) | b) & 0xFFFFFFFFFFUL; }

    // returns (bank switching scheme, superchip detected)
    public static int[] Detect(byte[] rom)
    {
        byte[] ram = new byte[65536];
        Array.Copy(rom, ram, Math.Min(rom.Length, 65536));
        int size = rom.Length;

        // S_CHECK
        int state = 1;                // 1 = SIG_RUN, 2 = DECIDE, 3 = SC_ADDR, 4 = SC_READ1, 5 = SC_READ2, 6 = done
        int scan_addr = 0;
        ulong sig_sr = 0;
        int sig_cnt = 0;
        bool e0 = false, ua = false, fe = false, e7 = false, cv = false; int f3 = 0;
        int bs = BS_SIZE; bool sc = false;
        int scan_bank = 0, scan_banks = 0, scan_idx = 0; byte b1 = 0;
        if (size > 32768) state = 2;
        int ram_q = ram[0];           // falling edge after S_CHECK latched scan_addr = 0

        for (int cyc = 0; cyc < 200000 && state != 6; cyc++)
        {
            int n_scan_addr = scan_addr;
            switch (state)
            {
                case 1:
                {
                    ulong w = Win(sig_sr, (byte)ram_q);
                    uint w24 = (uint)(w & 0xFFFFFF); uint w16 = (uint)(w & 0xFFFF);
                    if (w24 == 0x8DE01F || w24 == 0x8DE05F || w24 == 0x8DE9FF || w24 == 0x0CE01F ||
                        w24 == 0xADE01F || w24 == 0xADE9FF || w24 == 0xADEDFF || w24 == 0xADF3BF) e0 = true;
                    if (w16 == 0x853F && f3 != 2) f3++;
                    if (w24 == 0x8D4002 || w24 == 0xAD4002 || w24 == 0xBD1F02) ua = true;
                    if (w == 0x2000D0C6C5UL || w == 0x20C3F8A582UL || w == 0xD0FB2073FEUL || w == 0x2000F084D6UL) fe = true;
                    if (w24 == 0xADE2FF || w24 == 0xADE5FF || w24 == 0xADE51F || w24 == 0xADE71F ||
                        w24 == 0x0CE71F || w24 == 0x8DE7FF || w24 == 0x8DE71F) e7 = true;
                    if (w24 == 0x9DFFF3 || w24 == 0x9900F4) cv = true;
                    sig_sr = w & 0xFFFFFFFFUL;
                    n_scan_addr = (scan_addr + 1) & 0xFFFF;
                    if (sig_cnt == size - 1) state = 2; else sig_cnt++;
                    break;
                }
                case 2:
                {
                    int sz = size;
                    if ((sz == 2048 || sz == 4096) && cv) bs = BS_CV;
                    else if (sz == 8192 && e0) bs = BS_E0;
                    else if (sz == 8192 && f3 == 2) bs = BS_3F;
                    else if (sz == 8192 && ua) bs = BS_UA;
                    else if (sz == 8192 && fe) bs = BS_FE;
                    else if (sz >= 10240 && sz <= 10495) bs = BS_P2;
                    else if (sz == 16384 && e7) bs = BS_E7;
                    else bs = BS_SIZE;
                    if (sz == 8192 || sz == 16384 || sz == 32768) { sc = true; scan_banks = sz / 4096; scan_bank = 0; scan_idx = 0; state = 3; }
                    else state = 6;
                    break;
                }
                case 3: n_scan_addr = (scan_bank << 12) | scan_idx; state = 4; break;
                case 4: b1 = (byte)ram_q; n_scan_addr = (scan_bank << 12) | 0x80 | scan_idx; state = 5; break;
                case 5:
                    if (ram_q != b1) { sc = false; state = 6; }
                    else if (scan_idx != 127) { scan_idx++; state = 3; }
                    else if (scan_bank != scan_banks - 1) { scan_idx = 0; scan_bank++; state = 3; }
                    else state = 6;
                    break;
            }
            scan_addr = n_scan_addr;
            ram_q = ram[scan_addr];   // falling edge: RAM latches the new address
        }
        return new int[] { bs, sc ? 1 : 0 };
    }

    static byte[] Rom(int size, byte fill, int seed)
    {
        var r = new Random(seed); var b = new byte[size];
        for (int i = 0; i < size; i++) b[i] = (byte)r.Next(256);
        // avoid accidental signatures: no 0x8D/0xAD/0x0C/0x85/0xBD/0x20/0xD0/0x9D/0x99 in the noise
        for (int i = 0; i < size; i++) { switch (b[i]) { case 0x8D: case 0xAD: case 0x0C: case 0x85: case 0xBD: case 0x20: case 0xD0: case 0x9D: case 0x99: b[i] = fill; break; } }
        return b;
    }
    static void Put(byte[] rom, int at, params byte[] s) { Array.Copy(s, 0, rom, at, s.Length); }

    public static string Run()
    {
        var res = new List<string>(); int fails = 0;
        Action<string, byte[], int, int> T = (name, rom, wantBs, wantSc) =>
        {
            var d = Detect(rom);
            bool ok = d[0] == wantBs && d[1] == wantSc;
            if (!ok) fails++;
            res.Add(string.Format("{0,-44} bs={1,2} sc={2}  {3}", name, d[0], d[1], ok ? "ok" : "FAIL (want bs=" + wantBs + " sc=" + wantSc + ")"));
        };

        T("8K plain (F8)",                                Rom(8192, 0x11, 1), BS_SIZE, 0);
        var e0a = Rom(8192, 0x11, 2); Put(e0a, 0, 0x8D, 0xE0, 0x1F);            T("8K E0 sig at byte 0 (STA $1FE0)", e0a, BS_E0, 0);
        var e0b = Rom(8192, 0x11, 3); Put(e0b, 8189, 0xAD, 0xF3, 0xBF);         T("8K E0 sig in last 3 bytes (LDA $BFF3)", e0b, BS_E0, 0);
        var e0c = Rom(8192, 0x11, 4); Put(e0c, 8190, 0x8D, 0xE0);               T("8K E0 sig cut off by the end (no hit)", e0c, BS_SIZE, 0);
        var f3a = Rom(8192, 0x11, 5); Put(f3a, 100, 0x85, 0x3F);                 T("8K 3F only once (no hit)", f3a, BS_SIZE, 0);
        var f3b = Rom(8192, 0x11, 6); Put(f3b, 100, 0x85, 0x3F); Put(f3b, 5000, 0x85, 0x3F); T("8K 3F twice", f3b, BS_3F, 0);
        var ua  = Rom(8192, 0x11, 7); Put(ua, 4000, 0xBD, 0x1F, 0x02);           T("8K UA (LDA $21F,X)", ua, BS_UA, 0);
        var fe  = Rom(8192, 0x11, 8); Put(fe, 300, 0x20, 0x00, 0xD0, 0xC6, 0xC5); T("8K FE (5-byte JSR $D000/DEC $C5)", fe, BS_FE, 0);
        var fe4 = Rom(8192, 0x11, 9); Put(fe4, 300, 0x20, 0x00, 0xD0, 0xC6);     T("8K FE only 4 of 5 bytes (no hit)", fe4, BS_SIZE, 0);
        var pri = Rom(8192, 0x11, 10); Put(pri, 10, 0x85, 0x3F); Put(pri, 20, 0x85, 0x3F); Put(pri, 30, 0x8D, 0xE0, 0x1F); T("8K E0 and 3F: E0 wins", pri, BS_E0, 0);
        var e7  = Rom(16384, 0x11, 11); Put(e7, 16000, 0x8D, 0xE7, 0x1F);        T("16K E7 (STA $1FE7)", e7, BS_E7, 0);
        var e78 = Rom(8192, 0x11, 12); Put(e78, 100, 0x8D, 0xE7, 0x1F);          T("8K with E7 sig (E7 only at 16K: by size)", e78, BS_SIZE, 0);
        var cv  = Rom(2048, 0x11, 13); Put(cv, 50, 0x9D, 0xFF, 0xF3);            T("2K CV (STA $F3FF,X)", cv, BS_CV, 0);
        T("2K plain",                                     Rom(2048, 0x11, 14), BS_SIZE, 0);
        T("4K plain",                                     Rom(4096, 0x11, 15), BS_SIZE, 0);
        T("10495 bytes (Pitfall II DPC)",                 Rom(10495, 0x11, 16), BS_P2, 0);
        T("12K (FA by size)",                             Rom(12288, 0x11, 17), BS_SIZE, 0);
        // Superchip: first 128 bytes == next 128 bytes in every 4K bank
        foreach (int sz in new[] { 8192, 16384, 32768 })
        {
            var s = Rom(sz, 0x11, 20 + sz / 4096); for (int bk = 0; bk < sz / 4096; bk++) for (int i = 0; i < 128; i++) s[bk * 4096 + 128 + i] = s[bk * 4096 + i];
            T(sz / 1024 + "K Superchip", s, BS_SIZE, 1);
            var s2 = (byte[])s.Clone(); s2[(sz - 4096) + 128 + 127] ^= 0xFF; T(sz / 1024 + "K Superchip pattern broken in last bank", s2, BS_SIZE, 0);
        }
        T("32K plain (F4)",                               Rom(32768, 0x11, 30), BS_SIZE, 0);
        T("64K (no scan, by size)",                       Rom(65536, 0x11, 31), BS_SIZE, 0);

        res.Insert(0, "failures: " + fails);
        return string.Join(Environment.NewLine, res);
    }
}
