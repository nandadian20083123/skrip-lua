// ============================================================================
//  nadivoice.cpp  -  Mesin "Suara Dua" untuk Perekam Nadi
//
//  Membuat suara kedua (dan ketiga) dari suara asli dengan tinggi nada berbeda
//  tetapi karakter "tenggorokan" (formant) tetap seperti aslinya.
//  Metode: TD-PSOLA (Time-Domain Pitch-Synchronous Overlap-Add)
//    1. Pelacak nada (YIN) pada sinyal yang diperkecil laju sampelnya
//    2. Penentuan titik penanda nada (pitch mark) disejajarkan dengan korelasi
//    3. Sintesis: potongan gelombang asli (2 periode, jendela Hann) disusun ulang
//       dengan jarak baru -> nada berubah, selubung spektrum (formant) tidak
//       ikut bergeser karena bentuk gelombang tiap potongan tidak diubah.
//    4. Kealamian: pergeseran nada mikro dan penundaan mikro yang berbeda
//       untuk tiap suara supaya tidak terdengar seperti salinan.
//
//  Ditulis tanpa STL, tanpa exception, tanpa RTTI -> mudah dikompilasi di
//  Termux untuk 64-bit dan 32-bit, hanya butuh libc dan libm.
//
//  Versi 11: ditambah Bass & Treble dan Ekualiser 5 band yang berjalan langsung (nvEq*), dipakai
//  pemutar langsung di FastMuxer supaya geseran penggeser terdengar seketika.
//
//  Versi 12: ditambah Pengurang Kebisingan (noise gate) langsung (nvGate*), parameternya boleh diubah saat diputar.
//
//  Versi 13: ditambah Reverb (Freeverb) dan Echo langsung (nvFx*), parameternya boleh diubah saat diputar.
//  Versi 14: ditambah AutoTune langsung (nvAt*), kunci / tangga nada / kecepatan boleh diubah saat diputar.
//  Versi 15: dulu ada Klon Suara tanpa model (mode 4); fitur itu sudah dihapus, nomor versi tetap 15.
//
//  Cara pakai dari Java (tanpa jni.h): Java mengisi variabel lingkungan
//  NADI_JOB berisi path file tugas, lalu memanggil FastMuxer.nadiJalankan().
//  Hasil ditulis ke <file tugas>.res  ("OK" atau "ERROR: ...").
// ============================================================================
#define _FILE_OFFSET_BITS 64
// Hitungan float harus sama persis dengan Java: matikan penggabungan perkalian-penjumlahan.
#if defined(__clang__)
#pragma clang fp contract(off)
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdint.h>
#include <time.h>

#define NV_VERSI 15
#define NV_PI 3.14159265358979323846

// ----------------------------------------------------------------------------
//  Tugas
// ----------------------------------------------------------------------------
struct NVJob {
    char in[1024];
    char out[1024];
    char prog[1024];
    char plabel[200];
    int sr, ch, hdr, outhdr;
    float dry, fo, nat;
    float unv;                  // volume bagian tak bersuara (desis) pada suara tambahan
    int glOn;                   // pergeseran nada bertahap pada suara pertama
    float glS0, glS1, glDur;    // semiton awal, akhir, lama (detik, 0 = sepanjang file)
    int mode, atkey, atscale;   // mode 0 = Suara Dua, 1 = AutoTune, 2 = pergeseran nada Sonic
    int64_t inoff, inlen, limit, totfr;
    float atspeed, pratio;
    char tgt[1024];             // mode 4: audio target (PCM16 mono mentah)
    float klk;                  // mode 4: kekuatan 0..1
    int klm;                    // mode 4: 0 ringan, 1 standar, 2 kuat
    char kontur[1024];          // mode 3: berkas kontur pergeseran nada (semiton per baris)
    int khop;                   // mode 3: jarak antar baris kontur (sampel)
    int use[3];
    float semi[3], level[3], delayMs[3], pan[3];
};

static void nv_salin(char* dst, size_t cap, const char* src) {
    size_t n = strlen(src);
    if (n >= cap) n = cap - 1;
    memcpy(dst, src, n);
    dst[n] = 0;
}

static int nv_baca_job(const char* path, NVJob* j) {
    FILE* f = fopen(path, "r");
    if (!f) return 0;
    memset(j, 0, sizeof(*j));
    j->sr = 44100; j->ch = 1; j->hdr = 44; j->outhdr = 44;
    j->dry = 1.0f; j->fo = 0.0f; j->nat = 0.5f; j->unv = 0.6f;
    char line[1400];
    while (fgets(line, sizeof(line), f)) {
        size_t L = strlen(line);
        while (L > 0 && (line[L - 1] == '\n' || line[L - 1] == '\r')) line[--L] = 0;
        if (!strncmp(line, "in=", 3)) { nv_salin(j->in, sizeof(j->in), line + 3); }
        else if (!strncmp(line, "out=", 4)) { nv_salin(j->out, sizeof(j->out), line + 4); }
        else if (!strncmp(line, "prog=", 5)) { nv_salin(j->prog, sizeof(j->prog), line + 5); }
        else if (!strncmp(line, "plabel=", 7)) { nv_salin(j->plabel, sizeof(j->plabel), line + 7); }
        else if (!strncmp(line, "sr=", 3)) { j->sr = atoi(line + 3); }
        else if (!strncmp(line, "ch=", 3)) { j->ch = atoi(line + 3); }
        else if (!strncmp(line, "hdr=", 4)) { j->hdr = atoi(line + 4); }
        else if (!strncmp(line, "outhdr=", 7)) { j->outhdr = atoi(line + 7); }
        else if (!strncmp(line, "dry=", 4)) { j->dry = (float)atof(line + 4); }
        else if (!strncmp(line, "fo=", 3)) { j->fo = (float)atof(line + 3); }
        else if (!strncmp(line, "nat=", 4)) { j->nat = (float)atof(line + 4); }
        else if (!strncmp(line, "unv=", 4)) { j->unv = (float)atof(line + 4); }
        else if (!strncmp(line, "kontur=", 7)) { nv_salin(j->kontur, sizeof(j->kontur), line + 7); }
        else if (!strncmp(line, "khop=", 5)) { j->khop = atoi(line + 5); }
        else if (!strncmp(line, "tgt=", 4)) { nv_salin(j->tgt, sizeof(j->tgt), line + 4); }
        else if (!strncmp(line, "klk=", 4)) { j->klk = (float)atof(line + 4); }
        else if (!strncmp(line, "klm=", 4)) { j->klm = atoi(line + 4); }
        else if (!strncmp(line, "mode=", 5)) { j->mode = atoi(line + 5); }
        else if (!strncmp(line, "inoff=", 6)) { j->inoff = (int64_t)strtoll(line + 6, 0, 10); }
        else if (!strncmp(line, "inlen=", 6)) { j->inlen = (int64_t)strtoll(line + 6, 0, 10); }
        else if (!strncmp(line, "limit=", 6)) { j->limit = (int64_t)strtoll(line + 6, 0, 10); }
        else if (!strncmp(line, "totfr=", 6)) { j->totfr = (int64_t)strtoll(line + 6, 0, 10); }
        else if (!strncmp(line, "atkey=", 6)) { j->atkey = atoi(line + 6); }
        else if (!strncmp(line, "atscale=", 8)) { j->atscale = atoi(line + 8); }
        else if (!strncmp(line, "atspeed=", 8)) { j->atspeed = strtof(line + 8, 0); }
        else if (!strncmp(line, "pratio=", 7)) { j->pratio = strtof(line + 7, 0); }
        else if (!strncmp(line, "gl=", 3)) {
            int on = 0; float a = 0, b = 0, c = 0;
            if (sscanf(line + 3, "%d,%f,%f,%f", &on, &a, &b, &c) == 4) { j->glOn = on; j->glS0 = a; j->glS1 = b; j->glDur = c; }
        }
        else if (line[0] == 'v' && line[1] >= '1' && line[1] <= '3' && line[2] == '=') {
            int idx = line[1] - '1';
            float a = 0, b = 0, c = 0, d = 0;
            if (sscanf(line + 3, "%f,%f,%f,%f", &a, &b, &c, &d) == 4) {
                j->use[idx] = 1;
                j->semi[idx] = a; j->level[idx] = b; j->delayMs[idx] = c; j->pan[idx] = d;
            }
        }
    }
    fclose(f);
    return 1;
}

// ----------------------------------------------------------------------------
//  Pelacak nada (YIN) - sinyal diperkecil ke sekitar 11 kHz
// ----------------------------------------------------------------------------
struct NVPitch {
    int hop;            // jarak antar frame dalam sampel laju penuh
    int nf;             // jumlah frame
    float* f0;          // Hz
    unsigned char* vo;  // 1 = bersuara
};

static void nv_pitch_free(NVPitch* P) {
    if (P->f0) free(P->f0);
    if (P->vo) free(P->vo);
    P->f0 = 0; P->vo = 0; P->nf = 0;
}

static int cmp_float(const void* a, const void* b) {
    float x = *(const float*)a, y = *(const float*)b;
    return (x < y) ? -1 : (x > y) ? 1 : 0;
}

static void nv_pitch_track(const float* x, int n, int sr, NVPitch* P) {
    memset(P, 0, sizeof(*P));
    int D = sr / 11025; if (D < 1) D = 1;
    int srd = sr / D;
    int nd = n / D;
    int hopD = (int)(0.005f * (float)srd); if (hopD < 1) hopD = 1;
    int W = (int)(0.035f * (float)srd);
    int tauMin = srd / 600; if (tauMin < 2) tauMin = 2;
    int tauMax = srd / 65;  if (tauMax < tauMin + 4) tauMax = tauMin + 4;
    if (W < 2 * tauMax) W = 2 * tauMax;
    int nf = nd / hopD + 1;
    if (nd < W) { // terlalu pendek
        P->hop = hopD * D; P->nf = nf > 0 ? nf : 1;
        P->f0 = (float*)calloc(P->nf, sizeof(float));
        P->vo = (unsigned char*)calloc(P->nf, 1);
        return;
    }
    int PAD = W + tauMax + 8;
    float* xp = (float*)calloc((size_t)nd + 2 * (size_t)PAD, sizeof(float));
    float* xd = xp + PAD;
    for (int i = 0; i < nd; i++) {
        float s = 0.0f;
        const float* p = x + (size_t)i * D;
        for (int k = 0; k < D; k++) s += p[k];
        xd[i] = s / (float)D;
    }
    P->hop = hopD * D;
    P->nf = nf;
    P->f0 = (float*)calloc(nf, sizeof(float));
    P->vo = (unsigned char*)calloc(nf, 1);
    float* d = (float*)malloc(sizeof(float) * (tauMax + 3));
    float* cm = (float*)malloc(sizeof(float) * (tauMax + 3));

    for (int k = 0; k < nf; k++) {
        int c = k * hopD;
        int s0 = c - W / 2;
        double e = 0.0;
        for (int j = 0; j < W; j++) { float v = xd[s0 + j]; e += (double)v * v; }
        float rms = (float)sqrt(e / (double)W);
        if (rms < 0.0025f) continue;
        for (int tau = 1; tau <= tauMax; tau++) {
            double sum = 0.0;
            const float* a = xd + s0;
            const float* b = xd + s0 + tau;
            for (int j = 0; j < W; j++) { float df = a[j] - b[j]; sum += (double)df * df; }
            d[tau] = (float)sum;
        }
        double run = 0.0;
        cm[0] = 1.0f;
        for (int tau = 1; tau <= tauMax; tau++) {
            run += d[tau];
            cm[tau] = (run > 1e-12) ? (float)((double)d[tau] * tau / run) : 1.0f;
        }
        int best = -1;
        for (int tau = tauMin; tau <= tauMax - 1; tau++) {
            if (cm[tau] < 0.15f) {
                while (tau + 1 <= tauMax - 1 && cm[tau + 1] < cm[tau]) tau++;
                best = tau;
                break;
            }
        }
        if (best < 0) {
            float mn = 10.0f;
            for (int tau = tauMin; tau <= tauMax - 1; tau++) {
                if (cm[tau] < mn) { mn = cm[tau]; best = tau; }
            }
        }
        if (best < 0 || cm[best] > 0.30f) continue;
        float tr = (float)best;
        if (best > 1 && best < tauMax) {
            float a = cm[best - 1], b = cm[best], c2 = cm[best + 1];
            float den = (a - 2.0f * b + c2);
            if (fabsf(den) > 1e-9f) tr = (float)best + 0.5f * (a - c2) / den;
        }
        if (tr < (float)tauMin) tr = (float)tauMin;
        P->f0[k] = (float)srd / tr;
        P->vo[k] = 1;
    }
    free(d); free(cm); free(xp);

    // --- perbaikan lompatan oktaf lewat median 5 frame
    float* f2 = (float*)malloc(sizeof(float) * nf);
    memcpy(f2, P->f0, sizeof(float) * nf);
    for (int k = 0; k < nf; k++) {
        if (!P->vo[k]) continue;
        float w[5]; int m = 0;
        for (int q = k - 2; q <= k + 2; q++) {
            if (q >= 0 && q < nf && P->vo[q]) w[m++] = P->f0[q];
        }
        if (m < 3) continue;
        qsort(w, m, sizeof(float), cmp_float);
        float med = w[m / 2];
        float r = P->f0[k] / med;
        if (r > 1.8f && r < 2.2f) f2[k] = P->f0[k] * 0.5f;
        else if (r > 0.45f && r < 0.55f) f2[k] = P->f0[k] * 2.0f;
        else if (r > 1.25f || r < 0.8f) f2[k] = med;
    }
    memcpy(P->f0, f2, sizeof(float) * nf);
    free(f2);

    // --- hapus segmen bersuara yang terlalu pendek (< 4 frame)
    int k = 0;
    while (k < nf) {
        if (P->vo[k]) {
            int s = k;
            while (k < nf && P->vo[k]) k++;
            if (k - s < 4) { for (int q = s; q < k; q++) P->vo[q] = 0; }
        } else k++;
    }
    // --- isi celah tak bersuara pendek (<= 3 frame) di antara dua segmen bersuara
    k = 0;
    while (k < nf) {
        if (!P->vo[k]) {
            int s = k;
            while (k < nf && !P->vo[k]) k++;
            int e = k;
            if (s > 0 && e < nf && (e - s) <= 3 && P->vo[s - 1] && P->vo[e]) {
                float fa = P->f0[s - 1], fb = P->f0[e];
                for (int q = s; q < e; q++) {
                    float t = (float)(q - s + 1) / (float)(e - s + 1);
                    P->f0[q] = fa + (fb - fa) * t;
                    P->vo[q] = 1;
                }
            }
        } else k++;
    }
}

static float nv_f0_at(const NVPitch* P, int pos) {
    int k = (pos + P->hop / 2) / P->hop;
    if (k < 0) k = 0;
    if (k >= P->nf) k = P->nf - 1;
    float f = P->f0[k];
    if (f < 40.0f) {
        // cari tetangga terdekat yang punya nada
        for (int q = 1; q < 8; q++) {
            if (k - q >= 0 && P->f0[k - q] > 40.0f) return P->f0[k - q];
            if (k + q < P->nf && P->f0[k + q] > 40.0f) return P->f0[k + q];
        }
        return 150.0f;
    }
    return f;
}

// ----------------------------------------------------------------------------
//  Titik penanda (pitch marks)
// ----------------------------------------------------------------------------
struct NVMarks {
    int n, cap;
    int* pos;
    int* T;
    unsigned char* vc;
};

static void nv_marks_init(NVMarks* M, int cap) {
    M->n = 0; M->cap = cap;
    M->pos = (int*)malloc(sizeof(int) * cap);
    M->T = (int*)malloc(sizeof(int) * cap);
    M->vc = (unsigned char*)malloc(cap);
}
static void nv_marks_free(NVMarks* M) {
    free(M->pos); free(M->T); free(M->vc);
    M->pos = 0; M->T = 0; M->vc = 0; M->n = 0;
}
static void nv_marks_push(NVMarks* M, int pos, int T, int voiced) {
    if (M->n >= M->cap) return;
    M->pos[M->n] = pos; M->T[M->n] = T; M->vc[M->n] = (unsigned char)voiced; M->n++;
}

static inline float nv_X(const float* x, int n, int i) {
    return (i >= 0 && i < n) ? x[i] : 0.0f;
}

static int nv_refine(const float* x, int n, int prev, int pred, int T) {
    int half = T / 2; if (half < 4) half = 4;
    int lo = pred - T / 4, hi = pred + T / 4;
    double refE = 1e-12;
    for (int i = -half; i < half; i++) { float v = nv_X(x, n, prev + i); refE += (double)v * v; }
    double bestScore = -1e30; int bestK = pred;
    for (int k = lo; k <= hi; k++) {
        double corr = 0.0, curE = 1e-12;
        for (int i = -half; i < half; i++) {
            float a = nv_X(x, n, prev + i), b = nv_X(x, n, k + i);
            corr += (double)a * b; curE += (double)b * b;
        }
        double ncc = corr / sqrt(refE * curE);
        // sedikit memihak ke prediksi supaya penanda tidak melompat-lompat
        double dist = fabs((double)(k - pred)) / (double)(T / 4 + 1);
        double score = ncc - 0.03 * dist;
        if (score > bestScore) { bestScore = score; bestK = k; }
    }
    return bestK;
}

static void nv_marks_build(const float* x, int n, int sr, const NVPitch* P, NVMarks* M) {
    int Tu = (int)(0.010f * (float)sr); if (Tu < 16) Tu = 16;
    int cap = n / (sr / 700 + 1) + n / Tu + 64;
    nv_marks_init(M, cap);
    int cur = 0;
    int k = 0;
    while (k < P->nf) {
        if (!P->vo[k]) { k++; continue; }
        int fs = k;
        while (k < P->nf && P->vo[k]) k++;
        int fe = k - 1;
        int s0 = fs * P->hop - P->hop / 2; if (s0 < 0) s0 = 0;
        int e0 = fe * P->hop + P->hop / 2; if (e0 > n - 1) e0 = n - 1;
        if (e0 - s0 < 2 * Tu) continue;
        // celah tak bersuara sebelum segmen ini
        for (int t = cur; t < s0 - Tu / 2; t += Tu) nv_marks_push(M, t, Tu, 0);
        float f0s = nv_f0_at(P, s0 + P->hop);
        int T0 = (int)((float)sr / f0s); if (T0 < 8) T0 = 8;
        int hiS = s0 + T0; if (hiS > e0) hiS = e0;
        int m = s0; float bestA = -1.0f;
        for (int i = s0; i <= hiS; i++) {
            float a = fabsf(x[i]);
            if (a > bestA) { bestA = a; m = i; }
        }
        int last = m;
        int lastT = T0;
        while (m <= e0) {
            float fm = nv_f0_at(P, m);
            int T = (int)((float)sr / fm); if (T < 8) T = 8;
            nv_marks_push(M, m, T, 1);
            last = m; lastT = T;
            int pred = m + T;
            if (pred > e0 + T / 2) break;
            int nm = nv_refine(x, n, m, pred, T);
            if (nm <= m + T / 2) nm = pred;
            m = nm;
        }
        cur = last + lastT;
    }
    for (int t = cur; t < n + Tu; t += Tu) nv_marks_push(M, t, Tu, 0);
}

// ----------------------------------------------------------------------------
//  Sintesis satu suara
// ----------------------------------------------------------------------------
static float nv_interp(const float* x, int n, double p) {
    int i = (int)floor(p);
    float fr = (float)(p - (double)i);
    float a = nv_X(x, n, i), b = nv_X(x, n, i + 1);
    return a + (b - a) * fr;
}

static void nv_synth(const float* x, int n, int sr, const NVMarks* M,
                     float semi, float fo, float nat, float delayMs, int seed,
                     float unvGain, int glOn, float glS0, float glS1, float glDur,
                     double baseFrame, double totalFrames,
                     float* y /* panjang n */) {
    const int PAD = 8192;
    size_t tot = (size_t)n + 2 * (size_t)PAD;
    float* acc = (float*)calloc(tot, sizeof(float));
    float* wac = (float*)calloc(tot, sizeof(float));
    double ph1 = 0.9 * (double)(seed + 1), ph2 = 2.1 * (double)(seed + 2), ph3 = 4.3 * (double)(seed + 3), ph4 = 1.7 * (double)(seed + 1);
    double fr = pow(2.0, (double)fo / 12.0);
    double baseDelay = (double)delayMs * (double)sr / 1000.0;
    const float UNV = unvGain;
    double ts = 0.0;
    int j = 0;
    while (ts < (double)n + 1.0 && M->n > 0) {
        while (j + 1 < M->n && fabs((double)M->pos[j + 1] - ts) <= fabs((double)M->pos[j] - ts)) j++;
        int T = M->T[j];
        int voiced = M->vc[j];
        double tsec = ts / (double)sr;
        double cents = (double)nat * (6.0 * sin(2.0 * NV_PI * 0.31 * tsec + ph1)
                                      + 4.0 * sin(2.0 * NV_PI * 0.83 * tsec + ph2)
                                      + 2.5 * sin(2.0 * NV_PI * 4.7 * tsec + ph3));
        double semiNow = (double)semi;
        if (glOn) {
            double tAbs = (baseFrame + ts) / (double)sr;
            double durS = (glDur > 0.0f) ? (double)glDur : (totalFrames / (double)sr);
            double u = (durS > 0.001) ? tAbs / durS : 1.0;
            if (u < 0.0) u = 0.0;
            if (u > 1.0) u = 1.0;
            semiNow = (double)glS0 + ((double)glS1 - (double)glS0) * u;
        }
        double ratio = voiced ? pow(2.0, (semiNow + cents / 100.0) / 12.0) : 1.0;
        double dly = baseDelay + (double)nat * 0.001 * (double)sr * sin(2.0 * NV_PI * 0.37 * tsec + ph4);
        float gain = voiced ? 1.0f : UNV;
        int half = T;
        double c = (double)M->pos[j];
        double dst0 = ts + dly;
        int di0 = (int)floor(dst0 + 0.5);
        for (int k = -half; k <= half; k++) {
            int di = di0 + k;
            if (di < -PAD + 1 || di >= n + PAD - 1) continue;
            float w = 0.5f * (1.0f + cosf((float)NV_PI * (float)k / (float)half));
            float s = (fr == 1.0) ? nv_X(x, n, (int)c + k) : nv_interp(x, n, c + (double)k * fr);
            acc[di + PAD] += s * w * gain;
            wac[di + PAD] += w;
        }
        ts += (double)T / ratio;
    }
    for (int i = 0; i < n; i++) {
        float w = wac[i + PAD];
        y[i] = acc[i + PAD] / (w > 0.3f ? w : 0.3f);
    }
    free(acc); free(wac);
}

// ----------------------------------------------------------------------------
//  Pembacaan / penulisan
// ----------------------------------------------------------------------------
static int nv_read_frames(FILE* f, long long hdr, long long frame0, int nfr, int ch, int16_t* buf) {
    if (nfr <= 0) return 0;
    long long off = hdr + frame0 * (long long)ch * 2;
    if (fseeko(f, (off_t)off, SEEK_SET) != 0) return 0;
    size_t want = (size_t)nfr * (size_t)ch;
    size_t got = fread(buf, 2, want, f);
    if (got < want) memset(buf + got, 0, (want - got) * 2);
    return (int)(got / (size_t)ch);
}

static float nv_pan_gain(float pan, int chIdx, int ch) {
    if (ch < 2) return 1.0f;
    if (pan > 1.0f) pan = 1.0f;
    if (pan < -1.0f) pan = -1.0f;
    if (chIdx == 0) return pan <= 0.0f ? 1.0f : 1.0f - pan;
    return pan >= 0.0f ? 1.0f : 1.0f + pan;
}

static float nv_soft(float v) {
    float a = fabsf(v);
    if (a <= 0.92f) return v;
    float o = 0.92f + 0.08f * tanhf((a - 0.92f) / 0.08f);
    return v < 0 ? -o : o;
}

static void nv_prog(const NVJob* J, int pct) {
    if (!J->prog[0]) return;
    FILE* f = fopen(J->prog, "w");
    if (f) {
        if (J->plabel[0]) fprintf(f, "%d|%s", pct, J->plabel); else fprintf(f, "%d", pct);
        fclose(f);
    }
}

static int nv_proses(const NVJob* J, char* err) {
    if (J->sr < 8000 || J->sr > 96000) { snprintf(err, 200, "laju sampel tidak didukung: %d", J->sr); return 0; }
    if (J->ch < 1 || J->ch > 2) { snprintf(err, 200, "jumlah channel tidak didukung: %d", J->ch); return 0; }
    FILE* fi = fopen(J->in, "rb");
    if (!fi) { snprintf(err, 200, "tidak bisa membuka file masukan"); return 0; }
    FILE* fo = fopen(J->out, "wb");
    if (!fo) { fclose(fi); snprintf(err, 200, "tidak bisa membuat file keluaran"); return 0; }
    fseeko(fi, 0, SEEK_END);
    long long fsz = (long long)ftello(fi);
    long long dataBytes = fsz - J->hdr; if (dataBytes < 0) dataBytes = 0;
    long long N = dataBytes >> (J->ch == 2 ? 2 : 1);   // tanpa pembagian 64-bit (aman untuk ARM 32-bit)
    if (J->outhdr > 0) {
        unsigned char z[64]; memset(z, 0, sizeof(z));
        int rem = J->outhdr;
        while (rem > 0) { int w = rem > 64 ? 64 : rem; fwrite(z, 1, w, fo); rem -= w; }
    }
    int sr = J->sr, ch = J->ch;
    int voices[3], nv = 0;
    for (int v = 0; v < 3; v++) if (J->use[v] && J->level[v] > 0.0001f) voices[nv++] = v;

    const int CHUNK = sr * 20;
    const int MARG = (int)(0.4f * (float)sr);
    const int XF = (int)(0.010f * (float)sr);
    float* tail[3] = {0, 0, 0};
    int tailValid = 0;
    for (int v = 0; v < nv; v++) tail[v] = (float*)calloc(XF + 4, sizeof(float));

    long long start = 0;
    while (start < N) {
        long long end = start + CHUNK;
        if (end >= N) end = N;
        else {
            // geser batas ke titik paling sepi (+/- 1 detik) supaya sambungan mulus
            long long a = end - sr; if (a < start + sr) a = start + sr;
            long long b = end + sr; if (b > N) b = N;
            if (b - a > 2 * XF) {
                int nfr = (int)(b - a);
                int16_t* tb = (int16_t*)malloc((size_t)nfr * ch * 2);
                nv_read_frames(fi, J->hdr, a, nfr, ch, tb);
                int blk = (int)(0.020f * (float)sr); if (blk < 16) blk = 16;
                double bestE = 1e30; long long bestPos = end;
                for (int s = 0; s + blk <= nfr; s += blk / 2) {
                    double e = 0.0;
                    for (int i = 0; i < blk; i++) {
                        double v = 0.0;
                        for (int c = 0; c < ch; c++) v += (double)tb[(size_t)(s + i) * ch + c];
                        v /= (double)ch;
                        e += v * v;
                    }
                    if (e < bestE) { bestE = e; bestPos = a + s + blk / 2; }
                }
                free(tb);
                end = bestPos;
            }
        }
        long long a = start - MARG; if (a < 0) a = 0;
        long long b = end + MARG; if (b > N) b = N;
        int n = (int)(b - a);
        int16_t* raw = (int16_t*)malloc((size_t)n * ch * 2);
        nv_read_frames(fi, J->hdr, a, n, ch, raw);
        int off = (int)(start - a);
        int len = (int)(end - start);

        float* mono = (float*)malloc(sizeof(float) * (size_t)n);
        for (int i = 0; i < n; i++) {
            float s = 0.0f;
            for (int c = 0; c < ch; c++) s += (float)raw[(size_t)i * ch + c];
            mono[i] = s / ((float)ch * 32768.0f);
        }
        float* ys[3] = {0, 0, 0};
        if (nv > 0) {
            NVPitch P; NVMarks M;
            nv_pitch_track(mono, n, sr, &P);
            nv_marks_build(mono, n, sr, &P, &M);
            for (int v = 0; v < nv; v++) {
                int id = voices[v];
                ys[v] = (float*)malloc(sizeof(float) * (size_t)n);
                nv_synth(mono, n, sr, &M, J->semi[id], J->fo, J->nat, J->delayMs[id], id,
                         J->unv, (J->glOn && id == 0) ? 1 : 0, J->glS0, J->glS1, J->glDur,
                         (double)a, (double)N, ys[v]);
            }
            nv_marks_free(&M);
            nv_pitch_free(&P);
        }
        // pencampuran + penulisan
        int16_t* ob = (int16_t*)malloc((size_t)len * ch * 2);
        for (int i = 0; i < len; i++) {
            for (int c = 0; c < ch; c++) {
                float dryV = (float)raw[(size_t)(off + i) * ch + c] / 32768.0f;
                float s = dryV * J->dry;
                for (int v = 0; v < nv; v++) {
                    int id = voices[v];
                    float yv = ys[v][off + i];
                    if (tailValid && i < XF) {
                        float t = (float)i / (float)XF;
                        yv = tail[v][i] * (1.0f - t) + yv * t;
                    }
                    s += J->level[id] * nv_pan_gain(J->pan[id], c, ch) * yv;
                }
                s = nv_soft(s);
                int q = (int)lrintf(s * 32767.0f);
                if (q > 32767) q = 32767;
                if (q < -32768) q = -32768;
                ob[(size_t)i * ch + c] = (int16_t)q;
            }
        }
        fwrite(ob, 2, (size_t)len * ch, fo);
        // simpan ekor (suara tambahan sesudah batas) untuk crossfade chunk berikutnya
        for (int v = 0; v < nv; v++) {
            for (int i = 0; i < XF; i++) {
                int idx = off + len + i;
                tail[v][i] = (idx < n) ? ys[v][idx] : 0.0f;
            }
        }
        tailValid = 1;
        for (int v = 0; v < nv; v++) if (ys[v]) free(ys[v]);
        free(ob); free(mono); free(raw);
        start = end;
        nv_prog(J, N > 0 ? (int)(((double)start * 100.0) / (double)N) : 100);
    }
    for (int v = 0; v < nv; v++) if (tail[v]) free(tail[v]);
    fclose(fi);
    fclose(fo);
    nv_prog(J, 100);
    return 1;
}

static void nv_tulis_hasil(const char* jobPath, const char* teks) {
    char p[1100];
    snprintf(p, sizeof(p), "%s.res", jobPath);
    FILE* f = fopen(p, "w");
    if (f) { fputs(teks, f); fclose(f); }
}



// ============================================================================
//  SONIC + AUTOTUNE (versi 7): pergeseran nada dan koreksi nada, dipindah dari Java.
//  Aritmetika bilangan bulat 32-bit dibuat membungkus seperti Java; konversi float ke int
//  menjenuh seperti Java. Tidak ada pembagian 64-bit (aman untuk ARM 32-bit).
// ============================================================================
static inline int32_t nv_mul32(int32_t a, int32_t b) { return (int32_t)((uint32_t)a * (uint32_t)b); }
static inline int32_t nv_add32(int32_t a, int32_t b) { return (int32_t)((uint32_t)a + (uint32_t)b); }
static inline int32_t nv_f2i(float x) {
    if (x != x) return 0;
    if (x >= 2147483647.0f) return 2147483647;
    if (x <= -2147483648.0f) return (int32_t)0x80000000;
    return (int32_t)x;
}
static inline int16_t nv_f2s(float x) { return (int16_t)(uint16_t)((uint32_t)nv_f2i(x) & 0xFFFFu); }

struct NVSonic {
    int16_t *in, *out, *pit, *ds;
    float pitch, rate, speed;
    int ch, inSize, pitSize, outSize, nIn, nOut, nPit, minP, maxP, maxReq, remCopy, sr;
};

static int16_t* nv_s16(size_t n) { return (int16_t*)calloc(n + 8, sizeof(int16_t)); }

static int nv_sonic_init(NVSonic* S, int sr, int ch) {
    memset(S, 0, sizeof(*S));
    S->pitch = 1.0f; S->rate = 1.0f; S->speed = 1.0f;
    S->sr = sr; S->ch = ch;
    S->minP = sr / 400; S->maxP = sr / 65; S->maxReq = 2 * S->maxP;
    S->inSize = S->maxReq; S->outSize = S->maxReq; S->pitSize = S->maxReq;
    size_t slack = (size_t)S->maxReq * (size_t)ch;
    S->in = nv_s16((size_t)S->maxReq * ch + slack);
    S->out = nv_s16((size_t)S->maxReq * ch + slack);
    S->pit = nv_s16((size_t)S->maxReq * ch + slack);
    S->ds = nv_s16((size_t)S->maxReq * 2 + slack);
    return S->in && S->out && S->pit && S->ds;
}
static void nv_sonic_free(NVSonic* S) { free(S->in); free(S->out); free(S->pit); free(S->ds); memset(S, 0, sizeof(*S)); }

static int nv_sonic_enlarge_out(NVSonic* S, int num) {
    if (S->nOut + num > S->outSize) {
        S->outSize += (S->outSize >> 1) + num;
        int16_t* nb = nv_s16((size_t)S->outSize * S->ch + (size_t)S->maxReq * S->ch);
        if (!nb) return 0;
        memcpy(nb, S->out, sizeof(int16_t) * (size_t)S->nOut * S->ch);
        free(S->out); S->out = nb;
    }
    return 1;
}
static int nv_sonic_enlarge_pit(NVSonic* S, int num) {
    if (S->nPit + num > S->pitSize) {
        S->pitSize += (S->pitSize >> 1) + num;
        int16_t* nb = nv_s16((size_t)S->pitSize * S->ch + (size_t)S->maxReq * S->ch);
        if (!nb) return 0;
        memcpy(nb, S->pit, sizeof(int16_t) * (size_t)S->nPit * S->ch);
        free(S->pit); S->pit = nb;
    }
    return 1;
}
static int nv_sonic_enlarge_in(NVSonic* S, int num) {
    if (S->nIn + num > S->inSize) {
        S->inSize += (S->inSize >> 1) + num;
        int16_t* nb = nv_s16((size_t)S->inSize * S->ch + (size_t)S->maxReq * S->ch);
        if (!nb) return 0;
        memcpy(nb, S->in, sizeof(int16_t) * (size_t)S->nIn * S->ch);
        free(S->in); S->in = nb;
    }
    return 1;
}

static void nv_sonic_copy_out(NVSonic* S, const int16_t* smp, int pos, int num) {
    nv_sonic_enlarge_out(S, num);
    memcpy(S->out + (size_t)S->nOut * S->ch, smp + (size_t)pos * S->ch, sizeof(int16_t) * (size_t)num * S->ch);
    S->nOut += num;
}

static void nv_sonic_down(NVSonic* S, const int16_t* smp, int position, int skip) {
    int num = S->maxReq / skip;
    int spv = S->ch * skip;
    position *= S->ch;
    for (int i = 0; i < num; i++) {
        int value = 0;
        for (int j = 0; j < spv; j++) value = nv_add32(value, smp[position + i * spv + j]);
        value /= spv;
        S->ds[i] = (int16_t)value;
    }
}

static int nv_sonic_range(const int16_t* smp, int position, int minPeriod, int maxPeriod, int channels) {
    int bestPeriod = 0, worstPeriod = 255;
    int minDiff = 1, maxDiff = 0;
    position *= channels;
    for (int period = minPeriod; period <= maxPeriod; period++) {
        int diff = 0;
        int p = position;
        int pp = position + period * channels;
        for (int i = 0; i < period; i++) {
            int sV = smp[p], pV = smp[pp];
            diff = nv_add32(diff, sV >= pV ? sV - pV : pV - sV);
            p += channels; pp += channels;
        }
        if (bestPeriod == 0 || nv_mul32(diff, bestPeriod) < nv_mul32(minDiff, period)) { minDiff = diff; bestPeriod = period; }
        if (nv_mul32(diff, worstPeriod) > nv_mul32(maxDiff, period)) { maxDiff = diff; worstPeriod = period; }
    }
    return bestPeriod;
}

static int nv_sonic_find(NVSonic* S, const int16_t* smp, int position) {
    int period, skip = 1;
    if (S->sr > 4000) skip = S->sr / 4000;
    if (S->ch == 1 && skip == 1) {
        period = nv_sonic_range(smp, position, S->minP, S->maxP, S->ch);
    } else {
        nv_sonic_down(S, smp, position, skip);
        period = nv_sonic_range(S->ds, 0, S->minP / skip, S->maxP / skip, 1);
        if (skip != 1) {
            period *= skip;
            int minP = period - (skip * 4);
            int maxP = period + (skip * 4);
            if (minP < S->minP) minP = S->minP;
            if (maxP > S->maxP) maxP = S->maxP;
            if (S->ch == 1) {
                period = nv_sonic_range(smp, position, minP, maxP, 1);
            } else {
                nv_sonic_down(S, smp, position, 1);
                period = nv_sonic_range(S->ds, 0, minP, maxP, 1);
            }
        }
    }
    return period;
}

static void nv_sonic_overlap(int num, int chn, int16_t* out, int outPos, const int16_t* in, int inPos, const int16_t* in2, int in2Pos) {
    for (int i = 0; i < chn; i++) {
        int o = outPos * chn + i, u = inPos * chn + i, d = in2Pos * chn + i;
        for (int t = 0; t < num; t++) {
            int v = nv_add32(nv_mul32(in[u], num - t), nv_mul32(in2[d], t)) / num;
            out[o] = (int16_t)v;
            o += chn; u += chn; d += chn;
        }
    }
}

static void nv_sonic_remove(NVSonic* S, int position) {
    int remaining = S->nIn - position;
    memmove(S->in, S->in + (size_t)position * S->ch, sizeof(int16_t) * (size_t)remaining * S->ch);
    S->nIn = remaining;
}

static void nv_sonic_change_speed(NVSonic* S, float speed) {
    int numSamples = S->nIn;
    int position = 0, period, newPeriod;
    if (numSamples < S->maxReq) return;
    do {
        if (S->remCopy > 0) {
            int copy = S->remCopy < numSamples - position ? S->remCopy : numSamples - position;
            nv_sonic_copy_out(S, S->in, position, copy);
            position += copy;
            S->remCopy -= copy;
        } else {
            period = nv_sonic_find(S, S->in, position);
            if (speed > 1.0f) {
                newPeriod = nv_f2i((float)period / (speed - 1.0f));
                int skip = newPeriod < numSamples - position - period ? newPeriod : numSamples - position - period;
                if (skip > period) skip = period;
                nv_sonic_enlarge_out(S, skip);
                nv_sonic_overlap(skip, S->ch, S->out, S->nOut, S->in, position, S->in, position + period);
                S->nOut += skip;
                position += skip + period;
                S->remCopy = newPeriod - skip;
            } else {
                newPeriod = nv_f2i((float)period * speed / (1.0f - speed));
                int skip = newPeriod < numSamples - position - period ? newPeriod : numSamples - position - period;
                if (skip > period) skip = period;
                nv_sonic_enlarge_out(S, period + skip);
                memcpy(S->out + (size_t)S->nOut * S->ch, S->in + (size_t)position * S->ch, sizeof(int16_t) * (size_t)period * S->ch);
                S->nOut += period;
                nv_sonic_overlap(skip, S->ch, S->out, S->nOut, S->in, position + period, S->in, position);
                S->nOut += skip;
                position += skip;
                S->remCopy = newPeriod - skip;
            }
        }
    } while (position + S->maxReq <= numSamples);
    nv_sonic_remove(S, position);
}

static void nv_sonic_adjust_rate(NVSonic* S, float rate, int origOut) {
    int newSamples, position;
    if (S->nOut == origOut) return;
    int numSamples = S->nOut - origOut;
    nv_sonic_enlarge_pit(S, numSamples);
    memcpy(S->pit + (size_t)S->nPit * S->ch, S->out + (size_t)origOut * S->ch, sizeof(int16_t) * (size_t)numSamples * S->ch);
    S->nOut = origOut;
    S->nPit += numSamples;
    position = 0;
    while (S->nPit - position >= 2) {
        newSamples = nv_f2i((float)position / rate);
        int expected = nv_f2i((float)(position + 1) / rate);
        int separation = expected - newSamples;
        if (separation > 0) {
            nv_sonic_enlarge_out(S, separation);
            for (int i = 0; i < separation; i++) {
                for (int j = 0; j < S->ch; j++) {
                    int v1 = S->pit[(position * S->ch) + j];
                    int v2 = S->pit[((position + 1) * S->ch) + j];
                    S->out[(S->nOut * S->ch) + j] = nv_f2s((float)v1 + (float)(v2 - v1) * (((float)position / rate) - (float)newSamples) / (float)separation);
                }
                S->nOut++;
            }
        }
        position++;
    }
    int remaining = S->nPit - position;
    memmove(S->pit, S->pit + (size_t)position * S->ch, sizeof(int16_t) * (size_t)remaining * S->ch);
    S->nPit = remaining;
}

static void nv_sonic_process(NVSonic* S) {
    int origOut = S->nOut;
    float s = S->speed / S->pitch;
    float r = S->rate * S->pitch;
    if (s != 1.0f) {
        nv_sonic_change_speed(S, s);
    } else {
        nv_sonic_copy_out(S, S->in, 0, S->nIn);
        S->nIn = 0;
    }
    if (r != 1.0f) nv_sonic_adjust_rate(S, r, origOut);
}

static void nv_sonic_put(NVSonic* S, const int16_t* smp, int n) {
    nv_sonic_enlarge_in(S, n);
    memcpy(S->in + (size_t)S->nIn * S->ch, smp, sizeof(int16_t) * (size_t)n * S->ch);
    S->nIn += n;
    nv_sonic_process(S);
}

static int nv_sonic_receive(NVSonic* S, int16_t* smp, int maxS) {
    int n = maxS < S->nOut ? maxS : S->nOut;
    if (n == 0) return 0;
    memcpy(smp, S->out, sizeof(int16_t) * (size_t)n * S->ch);
    int remaining = S->nOut - n;
    memmove(S->out, S->out + (size_t)n * S->ch, sizeof(int16_t) * (size_t)remaining * S->ch);
    S->nOut = remaining;
    return n;
}

static void nv_sonic_flush(NVSonic* S) {
    int remainingSamples = S->nIn;
    float s = S->speed / S->pitch;
    float r = S->rate * S->pitch;
    int expected = S->nOut + nv_f2i((((float)remainingSamples / s) + (float)S->nPit) / r + 0.5f);
    nv_sonic_enlarge_in(S, S->maxReq);
    memset(S->in + (size_t)S->nIn * S->ch, 0, sizeof(int16_t) * (size_t)S->maxReq * S->ch);
    S->nIn += S->maxReq;
    nv_sonic_process(S);
    if (S->nOut > expected) S->nOut = expected;
    S->nIn = 0; S->remCopy = 0; S->nPit = 0;
}

// ----------------------------------------------------------------------------
//  mode 3: RAPIKAN VOKAL KONTINU (versi 8)
//  Seluruh vokal diproses dalam SATU alur PSOLA dengan kontur pergeseran nada
//  (semiton per 20 md) yang halus. Tidak ada lagi pemotongan per nada, jadi
//  tidak ada sambungan kasar ("tek-tek-tek"). Setara cara kerja koreksi nada
//  (Auto-Tune): rasio nada berubah mulus, bentuk gelombang tiap periode tidak
//  diubah, sehingga karakter "tenggorokan" (formant) tetap utuh.
// ----------------------------------------------------------------------------
static float nv_kontur_at(const float* c, int nc, int hop, double posAbs) {
    if (nc <= 0) return 0.0f;
    double p = posAbs / (double)hop - 0.5;
    if (p <= 0.0) return c[0];
    if (p >= (double)(nc - 1)) return c[nc - 1];
    int i = (int)p;
    double fr = p - (double)i;
    return (float)((double)c[i] + ((double)c[i + 1] - (double)c[i]) * fr);
}

static void nv_synth_kontur(const float* x, int n, const NVMarks* M,
                            const float* kc, int nk, int khop, double baseFrame, float* y) {
    const int PAD = 8192;
    size_t tot = (size_t)n + 2 * (size_t)PAD;
    float* acc = (float*)calloc(tot, sizeof(float));
    float* wac = (float*)calloc(tot, sizeof(float));
    double ts = 0.0;
    int j = 0;
    while (ts < (double)n + 1.0 && M->n > 0) {
        while (j + 1 < M->n && fabs((double)M->pos[j + 1] - ts) <= fabs((double)M->pos[j] - ts)) j++;
        int T = M->T[j];
        int voiced = M->vc[j];
        double semi = voiced ? (double)nv_kontur_at(kc, nk, khop, baseFrame + ts) : 0.0;
        if (fabs(semi) < 0.002) semi = 0.0;
        double ratio = pow(2.0, semi / 12.0);
        int half = T;
        int c = M->pos[j];
        int di0 = (int)floor(ts + 0.5);
        for (int k = -half; k <= half; k++) {
            int di = di0 + k;
            if (di < -PAD + 1 || di >= n + PAD - 1) continue;
            float w = 0.5f * (1.0f + cosf((float)NV_PI * (float)k / (float)half));
            acc[di + PAD] += nv_X(x, n, c + k) * w;
            wac[di + PAD] += w;
        }
        ts += (double)T / ratio;
    }
    for (int i = 0; i < n; i++) {
        float w = wac[i + PAD];
        float a = acc[i + PAD];
        // bila cakupan jendela kurang dari 1, isi sisanya dari sinyal asli (tanpa lubang)
        y[i] = (w >= 1.0f) ? a / w : a + x[i] * (1.0f - w);
    }
    free(acc); free(wac);
}

static int nv_kontur(const NVJob* J, char* err) {
    if (J->sr < 8000 || J->sr > 96000) { snprintf(err, 200, "laju sampel tidak didukung: %d", J->sr); return 0; }
    if (J->ch != 1) { snprintf(err, 200, "mode kontur hanya untuk mono"); return 0; }
    int khop = J->khop > 0 ? J->khop : (J->sr / 50);
    // muat kontur (satu angka semiton per baris)
    int nk = 0, capk = 4096;
    float* kc = (float*)malloc(sizeof(float) * (size_t)capk);
    if (!kc) { snprintf(err, 200, "memori habis"); return 0; }
    {
        FILE* fk = fopen(J->kontur, "r");
        if (!fk) { free(kc); snprintf(err, 200, "tidak bisa membuka berkas kontur"); return 0; }
        char line[128];
        while (fgets(line, sizeof(line), fk)) {
            if (nk >= capk) {
                capk *= 2;
                float* nb = (float*)realloc(kc, sizeof(float) * (size_t)capk);
                if (!nb) { free(kc); fclose(fk); snprintf(err, 200, "memori habis"); return 0; }
                kc = nb;
            }
            kc[nk++] = (float)atof(line);
        }
        fclose(fk);
    }
    FILE* fi = fopen(J->in, "rb");
    if (!fi) { free(kc); snprintf(err, 200, "tidak bisa membuka file masukan"); return 0; }
    FILE* fo = fopen(J->out, "wb");
    if (!fo) { fclose(fi); free(kc); snprintf(err, 200, "tidak bisa membuat file keluaran"); return 0; }
    fseeko(fi, 0, SEEK_END);
    long long fsz = (long long)ftello(fi);
    long long dataBytes = fsz - J->hdr; if (dataBytes < 0) dataBytes = 0;
    long long N = dataBytes >> 1;
    if (J->outhdr > 0) {
        unsigned char z[64]; memset(z, 0, sizeof(z));
        int rem = J->outhdr;
        while (rem > 0) { int w = rem > 64 ? 64 : rem; fwrite(z, 1, w, fo); rem -= w; }
    }
    int sr = J->sr;
    const int CHUNK = sr * 30;
    const int MARG = (int)(0.5f * (float)sr);
    const int XF = (int)(0.015f * (float)sr);
    float* tail = (float*)calloc((size_t)XF + 4, sizeof(float));
    int tailValid = 0;
    long long start = 0;
    while (start < N) {
        long long end = start + CHUNK;
        if (end >= N) end = N;
        else {
            // batas potongan di titik paling sepi (+/- 1 detik), jauh dari nada yang sedang digeser
            long long a = end - sr; if (a < start + sr) a = start + sr;
            long long b = end + sr; if (b > N) b = N;
            if (b - a > 2 * XF) {
                int nfr = (int)(b - a);
                int16_t* tb = (int16_t*)malloc((size_t)nfr * 2);
                nv_read_frames(fi, J->hdr, a, nfr, 1, tb);
                int blk = (int)(0.020f * (float)sr); if (blk < 16) blk = 16;
                double bestE = 1e30; long long bestPos = end;
                for (int s = 0; s + blk <= nfr; s += blk / 2) {
                    double e = 0.0;
                    for (int i = 0; i < blk; i++) { double v = (double)tb[s + i]; e += v * v; }
                    // hukuman kecil bila kontur di titik itu sedang bergeser
                    double sh = fabs((double)nv_kontur_at(kc, nk, khop, (double)(a + s + blk / 2)));
                    e += sh * 1e6;
                    if (e < bestE) { bestE = e; bestPos = a + s + blk / 2; }
                }
                free(tb);
                end = bestPos;
            }
        }
        long long a = start - MARG; if (a < 0) a = 0;
        long long b = end + MARG; if (b > N) b = N;
        int n = (int)(b - a);
        int16_t* raw = (int16_t*)malloc((size_t)n * 2);
        nv_read_frames(fi, J->hdr, a, n, 1, raw);
        int off = (int)(start - a);
        int len = (int)(end - start);
        float* mono = (float*)malloc(sizeof(float) * (size_t)n);
        for (int i = 0; i < n; i++) mono[i] = (float)raw[i] / 32768.0f;
        float* ys = (float*)malloc(sizeof(float) * (size_t)n);
        // adakah pergeseran di potongan ini? bila tidak, suara asli dibiarkan utuh
        int ada = 0;
        {
            int f0 = (int)((a / khop) - 1); if (f0 < 0) f0 = 0;
            int f1 = (int)((b / khop) + 1); if (f1 > nk - 1) f1 = nk - 1;
            for (int f = f0; f <= f1; f++) if (fabsf(kc[f]) >= 0.002f) { ada = 1; break; }
        }
        if (ada) {
            NVPitch P; NVMarks M;
            nv_pitch_track(mono, n, sr, &P);
            nv_marks_build(mono, n, sr, &P, &M);
            nv_synth_kontur(mono, n, &M, kc, nk, khop, (double)a, ys);
            nv_marks_free(&M);
            nv_pitch_free(&P);
        } else {
            memcpy(ys, mono, sizeof(float) * (size_t)n);
        }
        int16_t* ob = (int16_t*)malloc((size_t)len * 2);
        for (int i = 0; i < len; i++) {
            float yv = ys[off + i];
            if (tailValid && i < XF) {
                float t = (float)i / (float)XF;
                yv = tail[i] * (1.0f - t) + yv * t;
            }
            yv = nv_soft(yv);
            int q = (int)lrintf(yv * 32767.0f);
            if (q > 32767) q = 32767;
            if (q < -32768) q = -32768;
            ob[i] = (int16_t)q;
        }
        fwrite(ob, 2, (size_t)len, fo);
        for (int i = 0; i < XF; i++) {
            int idx = off + len + i;
            tail[i] = (idx < n) ? ys[idx] : 0.0f;
        }
        tailValid = 1;
        free(ob); free(ys); free(mono); free(raw);
        start = end;
        nv_prog(J, N > 0 ? (int)(((double)start * 100.0) / (double)N) : 100);
    }
    free(tail); free(kc);
    fclose(fi);
    fclose(fo);
    nv_prog(J, 100);
    return 1;
}

// ---- AutoTune
static const unsigned char NV_MAJOR[12] = {1,0,1,0,1,1,0,1,0,1,0,1};
static const unsigned char NV_MINOR[12] = {1,0,1,1,0,1,0,1,1,0,1,0};
static int nv_nada_ok(int midi, int root, int scale) {
    if (scale == 0) return 1;
    int rel = ((midi - root) % 12 + 12) % 12;
    return scale == 1 ? NV_MAJOR[rel] : NV_MINOR[rel];
}
static int nv_nada_target(float midiF, int root, int scale, int last) {
    if (last > 0 && nv_nada_ok(last, root, scale)) {
        if (fabsf(midiF - (float)last) <= 0.62f) return last;
    }
    int base = (int)floorf(midiF + 0.5f);
    int best = base;
    float minDiff = 999.0f;
    for (int n = base - 3; n <= base + 3; n++) {
        if (nv_nada_ok(n, root, scale)) {
            float d = fabsf(midiF - (float)n);
            if (d < minDiff) { minDiff = d; best = n; }
        }
    }
    return best;
}

static float nv_yin(const float* mono, int len, int sr) {
    double energi = 0.0;
    for (int i = 0; i < len; i++) energi += (double)mono[i] * (double)mono[i];
    double rms = sqrt(energi / (double)len);
    if (rms < 160.0) return -1.0f;
    int skip = (sr >= 32000) ? 2 : 1;
    int dsLen = len / skip;
    float dsRate = (float)sr / (float)skip;
    float* ds = (float*)calloc((size_t)dsLen + 4, sizeof(float));
    if (!ds) return -1.0f;
    if (skip == 2) { for (int i = 0; i < dsLen; i++) ds[i] = 0.5f * (mono[i * 2] + mono[i * 2 + 1]); }
    else memcpy(ds, mono, sizeof(float) * (size_t)dsLen);
    int minTau = nv_f2i(dsRate / 850.0f); if (minTau < 4) minTau = 4;
    int maxTau = nv_f2i(dsRate / 75.0f); if (dsLen / 2 < maxTau) maxTau = dsLen / 2;
    int wLen = dsLen - maxTau;
    if (wLen <= minTau) { free(ds); return -1.0f; }
    float* yin = (float*)calloc((size_t)maxTau + 2, sizeof(float));
    if (!yin) { free(ds); return -1.0f; }
    yin[0] = 1.0f;
    float runningSum = 0.0f;
    for (int tau = 1; tau <= maxTau; tau++) {
        float diff = 0.0f;
        for (int j = 0; j < wLen; j++) { float delta = ds[j] - ds[j + tau]; diff += delta * delta; }
        runningSum += diff;
        yin[tau] = (runningSum > 0.0f) ? (diff * (float)tau / runningSum) : 1.0f;
    }
    int bestTau = -1;
    for (int tau = minTau; tau <= maxTau - 1; tau++) {
        if (yin[tau] < 0.22f && yin[tau] <= yin[tau - 1] && yin[tau] <= yin[tau + 1]) { bestTau = tau; break; }
    }
    if (bestTau == -1) {
        float minVal = 0.28f;
        for (int tau = minTau; tau <= maxTau - 1; tau++) { if (yin[tau] < minVal) { minVal = yin[tau]; bestTau = tau; } }
    }
    float hasil = -1.0f;
    if (bestTau > 0) {
        float s0 = yin[bestTau - 1], s1 = yin[bestTau], s2 = yin[bestTau + 1];
        float denom = 2.0f * (2.0f * s1 - s2 - s0);
        float exactTau = (float)bestTau;
        if (fabsf(denom) > 1e-6f) { float d = (s2 - s0) / denom; if (fabsf(d) < 1.0f) exactTau += d; }
        hasil = dsRate / exactTau;
    }
    free(ds); free(yin);
    return hasil;
}

static void nv_tulis_pcm(FILE* fo, const int16_t* s, int n) {
    unsigned char b[2048];
    int i = 0;
    while (i < n) {
        int m = n - i > 1024 ? 1024 : n - i;
        for (int k = 0; k < m; k++) { b[k * 2] = (unsigned char)(s[i + k] & 0xFF); b[k * 2 + 1] = (unsigned char)(((int)s[i + k] >> 8) & 0xFF); }
        fwrite(b, 1, (size_t)m * 2, fo);
        i += m;
    }
}

static float nv_semi_geser(int gl, float tetap, float g0, float g1, float gd, int64_t fSelesai, int64_t fTotal, int sr) {
    if (!gl) return tetap;
    double t = (double)fSelesai / (double)sr;
    double dur = (gd > 0.0f) ? (double)gd : ((double)fTotal / (double)sr);
    double u = (dur > 0.001) ? t / dur : 1.0;
    if (u < 0.0) u = 0.0;
    if (u > 1.0) u = 1.0;
    return (float)((double)g0 + ((double)g1 - (double)g0) * u);
}

// Menulis keluaran Sonic ke berkas (dipakai AutoTune dan pitch biasa). limit > 0: batasi jumlah byte.
static void nv_sonic_kuras(NVSonic* S, int16_t* ob, int obN, FILE* fo, int64_t* written, int64_t limit, int fs, int akhir) {
    for (;;) {
        if (akhir && limit > 0 && *written >= limit) break;
        int n = nv_sonic_receive(S, ob, obN / S->ch);
        if (n <= 0) break;
        int64_t bw = (int64_t)n * fs;
        if (limit > 0 && *written + bw > limit) bw = limit - *written;
        if (bw > 0) { nv_tulis_pcm(fo, ob, (int)(bw / 2)); *written += bw; }
    }
}

// mode 1: AutoTune. Setara AutoTune.prosesRafKeFile di Java.
static int nv_autotune(const NVJob* J, char* err) {
    int sr = J->sr, ch = J->ch;
    if (sr < 8000 || sr > 96000 || ch < 1 || ch > 2) { snprintf(err, 200, "format audio tidak didukung"); return 0; }
    FILE* fi = fopen(J->in, "rb");
    if (!fi) { snprintf(err, 200, "tidak bisa membuka file masukan"); return 0; }
    FILE* fo = fopen(J->out, "wb");
    if (!fo) { fclose(fi); snprintf(err, 200, "tidak bisa membuat file keluaran"); return 0; }
    int fs = ch * 2;
    int64_t total = J->inlen;
    if (total <= 0) { fseeko(fi, 0, SEEK_END); total = (int64_t)ftello(fi) - J->inoff; }
    int64_t valid = total & ~(int64_t)(fs - 1);
    if (J->outhdr > 0) { unsigned char z[64]; memset(z, 0, 64); int rem = J->outhdr; while (rem > 0) { int w = rem > 64 ? 64 : rem; fwrite(z, 1, (size_t)w, fo); rem -= w; } }
    if (valid <= 0) { fclose(fi); fclose(fo); return 1; }
    NVSonic S;
    if (!nv_sonic_init(&S, sr, ch)) { fclose(fi); fclose(fo); nv_sonic_free(&S); snprintf(err, 200, "memori habis"); return 0; }
    int blockFrames = sr / 40 > 256 ? sr / 40 : 256;
    int analysisFrames = sr / 25 > blockFrames ? sr / 25 : blockFrames;
    float* ring = (float*)calloc((size_t)analysisFrames + 4, sizeof(float));
    int ringFilled = 0;
    unsigned char* inB = (unsigned char*)malloc((size_t)blockFrames * fs);
    int16_t* inS = (int16_t*)calloc((size_t)blockFrames * ch + 8, sizeof(int16_t));
    int obN = blockFrames * ch * 2;
    int16_t* ob = (int16_t*)calloc((size_t)obN + 8, sizeof(int16_t));
    if (!ring || !inB || !inS || !ob) { free(ring); free(inB); free(inS); free(ob); nv_sonic_free(&S); fclose(fi); fclose(fo); snprintf(err, 200, "memori habis"); return 0; }
    float hist[3] = {0, 0, 0}; int histCount = 0, lastTarget = -1;
    float curSemi = 0.0f;
    float sp = J->atspeed; if (sp > 100.0f) sp = 100.0f; if (sp < 1.0f) sp = 1.0f;
    float alpha = (sp >= 95.0f) ? 0.94f : (0.08f + (sp / 100.0f) * 0.80f);
    fseeko(fi, (off_t)J->inoff, SEEK_SET);
    int64_t rem = valid, written = 0;
    int blockBytes = blockFrames * fs;
    while (rem > 0) {
        int toRead = rem < (int64_t)blockBytes ? (int)rem : blockBytes;
        toRead -= toRead % fs;
        if (toRead <= 0) break;
        int r = (int)fread(inB, 1, (size_t)toRead, fi);
        if (r <= 0) break;
        r -= r % fs;
        if (r <= 0) break;
        int numShorts = r / 2, framesRead = numShorts / ch;
        for (int i = 0; i < numShorts; i++) inS[i] = (int16_t)(uint16_t)(inB[i * 2] | (inB[i * 2 + 1] << 8));
        if (framesRead >= analysisFrames) {
            for (int i = 0; i < analysisFrames; i++) { float m = 0.0f; for (int c = 0; c < ch; c++) m += (float)inS[i * ch + c]; ring[i] = m / (float)ch; }
            ringFilled = analysisFrames;
        } else {
            int shift = ringFilled < analysisFrames - framesRead ? ringFilled : analysisFrames - framesRead;
            if (shift > 0 && ringFilled > shift) memmove(ring, ring + (ringFilled - shift), sizeof(float) * (size_t)shift);
            for (int i = 0; i < framesRead; i++) { float m = 0.0f; for (int c = 0; c < ch; c++) m += (float)inS[i * ch + c]; ring[shift + i] = m / (float)ch; }
            ringFilled = shift + framesRead;
        }
        float f0 = (ringFilled >= analysisFrames / 2) ? nv_yin(ring, ringFilled, sr) : -1.0f;
        if (f0 >= 75.0f && f0 <= 850.0f) {
            float midi = (float)(69.0 + 12.0 * (log((double)f0 / 440.0) / log(2.0)));
            hist[0] = hist[1]; hist[1] = hist[2]; hist[2] = midi;
            if (histCount < 3) histCount++;
            float smooth = midi;
            if (histCount == 3) {
                float a = hist[0], b = hist[1], c = hist[2];
                float mn = a < b ? a : b, mx = a > b ? a : b;
                float lo = mx < c ? mx : c;
                smooth = mn > lo ? mn : lo;
            }
            int target = nv_nada_target(smooth, J->atkey, J->atscale, lastTarget);
            lastTarget = target;
            float desired = (float)target - smooth;
            if (desired > 5.0f) desired = 5.0f; else if (desired < -5.0f) desired = -5.0f;
            curSemi = curSemi + alpha * (desired - curSemi);
        } else {
            histCount = 0;
            curSemi *= 0.5f;
            if (fabsf(curSemi) < 0.02f) curSemi = 0.0f;
        }
        float ratio = (float)pow(2.0, (double)curSemi / 12.0);
        S.pitch = ratio;
        nv_sonic_put(&S, inS, framesRead);
        nv_sonic_kuras(&S, ob, obN, fo, &written, valid, fs, 0);
        rem -= r;
    }
    nv_sonic_flush(&S);
    nv_sonic_kuras(&S, ob, obN, fo, &written, valid, fs, 1);
    free(ring); free(inB); free(inS); free(ob); nv_sonic_free(&S);
    fclose(fi); fclose(fo);
    return 1;
}

// mode 2: pergeseran nada Sonic (tetap atau bertahap). Setara blok Sonic di Java.
static int nv_sonic_pitch(const NVJob* J, char* err) {
    int sr = J->sr, ch = J->ch;
    if (sr < 8000 || sr > 96000 || ch < 1 || ch > 2) { snprintf(err, 200, "format audio tidak didukung"); return 0; }
    FILE* fi = fopen(J->in, "rb");
    if (!fi) { snprintf(err, 200, "tidak bisa membuka file masukan"); return 0; }
    FILE* fo = fopen(J->out, "wb");
    if (!fo) { fclose(fi); snprintf(err, 200, "tidak bisa membuat file keluaran"); return 0; }
    int fs = ch * 2;
    if (J->outhdr > 0) { unsigned char z[64]; memset(z, 0, 64); int rem = J->outhdr; while (rem > 0) { int w = rem > 64 ? 64 : rem; fwrite(z, 1, (size_t)w, fo); rem -= w; } }
    NVSonic S;
    if (!nv_sonic_init(&S, sr, ch)) { fclose(fi); fclose(fo); nv_sonic_free(&S); snprintf(err, 200, "memori habis"); return 0; }
    S.pitch = J->pratio;
    unsigned char* inB = (unsigned char*)malloc(8192);
    int16_t* sb = (int16_t*)calloc(4096 + 8, sizeof(int16_t));
    if (!inB || !sb) { free(inB); free(sb); nv_sonic_free(&S); fclose(fi); fclose(fo); snprintf(err, 200, "memori habis"); return 0; }
    fseeko(fi, (off_t)J->inoff, SEEK_SET);
    int64_t remRead = J->inlen > 0 ? J->inlen : -1;
    int64_t written = 0, framesDone = 0;
    int64_t limit = J->limit;
    for (;;) {
        int toRead = 8192;
        if (remRead >= 0) {
            if (remRead <= 0) break;
            if (remRead < toRead) toRead = (int)remRead;
            toRead -= toRead % fs;
            if (toRead <= 0) break;
        }
        int r = (int)fread(inB, 1, (size_t)toRead, fi);
        if (r <= 0) break;
        if (remRead >= 0) r -= r % fs;
        if (r <= 0) break;
        int numShorts = r / 2;
        for (int i = 0; i < numShorts; i++) sb[i] = (int16_t)(uint16_t)(inB[i * 2] | (inB[i * 2 + 1] << 8));
        if (J->glOn) S.pitch = (float)pow(2.0, (double)nv_semi_geser(1, J->glS0, J->glS0, J->glS1, J->glDur, framesDone, J->totfr, sr) / 12.0);
        int frames = numShorts / ch;
        nv_sonic_put(&S, sb, frames);
        framesDone += frames;
        nv_sonic_kuras(&S, sb, 4096, fo, &written, limit, fs, 0);
        if (remRead >= 0) remRead -= r;
    }
    nv_sonic_flush(&S);
    nv_sonic_kuras(&S, sb, 4096, fo, &written, limit, fs, 1);
    free(inB); free(sb); nv_sonic_free(&S);
    fclose(fi); fclose(fo);
    return 1;
}


// ============================================================================
//  VIDEO (versi 4): bagian berat pemrosesan bingkai video yang dulu berjalan di Java.
//  Hanya pekerjaan per piksel yang dipindah ke sini. Pengodean/pembongkaran video
//  tetap memakai mesin bawaan Android lewat Java.
// ============================================================================
struct NVPlane { uint8_t* p; int64_t cap; int row; int pix; };

static inline void nv_peta_putar(int rot, int vx, int vy, int srcW, int srcH, int* sx, int* sy) {
    if (rot == 90)       { *sx = vy;             *sy = srcH - 1 - vx; }
    else if (rot == 180) { *sx = srcW - 1 - vx;  *sy = srcH - 1 - vy; }
    else if (rot == 270) { *sx = srcW - 1 - vy;  *sy = vx; }
    else                 { *sx = vx;             *sy = vy; }
}

static void nv_isi_bidang(NVPlane d, int w, int h, uint8_t nilai) {
    for (int y = 0; y < h; y++) {
        int64_t base = (int64_t)y * d.row;
        if (d.pix == 1 && base >= 0 && base + w <= d.cap) { memset(d.p + base, nilai, (size_t)w); continue; }
        for (int x = 0; x < w; x++) {
            int64_t idx = base + (int64_t)x * d.pix;
            if (idx >= 0 && idx < d.cap) d.p[idx] = nilai;
        }
    }
}

// Menyalin satu bingkai YUV420 dari sumber ke tujuan: diputar sesuai srcRot, diskalakan
// (tetangga terdekat) agar muat di outW x outH, dan diberi bingkai hitam bila perlu.
// Hasilnya identik dengan versi Java. Mengembalikan 1 bila berhasil.
static int nv_bingkai_yuv(NVPlane sY, NVPlane sU, NVPlane sV, NVPlane dY, NVPlane dU, NVPlane dV,
                          int srcW, int srcH, int srcRot, int outW, int outH) {
    if (srcW <= 0 || srcH <= 0 || outW <= 0 || outH <= 0) return 0;
    int visW = (srcRot == 90 || srcRot == 270) ? srcH : srcW;
    int visH = (srcRot == 90 || srcRot == 270) ? srcW : srcH;
    float fx = (float)outW / (float)visW;
    float fy = (float)outH / (float)visH;
    float scale = fx < fy ? fx : fy;
    int drawW = ((int)floorf((float)visW * scale + 0.5f) / 2) * 2;
    int drawH = ((int)floorf((float)visH * scale + 0.5f) / 2) * 2;
    if (drawW < 2) drawW = 2;
    if (drawH < 2) drawH = 2;
    if (drawW > outW) drawW = outW;
    if (drawH > outH) drawH = outH;
    int padX = ((outW - drawW) / 4) * 2;
    int padY = ((outH - drawH) / 4) * 2;

    int* mapVX = (int*)malloc(sizeof(int) * (size_t)drawW);
    int* mapVY = (int*)malloc(sizeof(int) * (size_t)drawH);
    if (!mapVX || !mapVY) { free(mapVX); free(mapVY); return 0; }
    for (int dx = 0; dx < drawW; dx++) {
        int v = (dx * visW) / drawW;   // 32-bit (sama dengan Java); hindari pembagian 64-bit di ARM32
        if (v >= visW) v = visW - 1;
        mapVX[dx] = v;
    }
    for (int dy = 0; dy < drawH; dy++) {
        int v = (dy * visH) / drawH;
        if (v >= visH) v = visH - 1;
        mapVY[dy] = v;
    }

    if (drawW < outW || drawH < outH) {
        nv_isi_bidang(dY, outW, outH, 16);
        nv_isi_bidang(dU, outW / 2, outH / 2, 128);
        nv_isi_bidang(dV, outW / 2, outH / 2, 128);
    }

    // Bidang Y
    for (int dy = 0; dy < drawH; dy++) {
        int vy = mapVY[dy];
        int64_t dstRowOff = (int64_t)(dy + padY) * dY.row;
        for (int dx = 0; dx < drawW; dx++) {
            int sx, sy;
            nv_peta_putar(srcRot, mapVX[dx], vy, srcW, srcH, &sx, &sy);
            int64_t sIdx = (int64_t)sy * sY.row + (int64_t)sx * sY.pix;
            int64_t dIdx = dstRowOff + (int64_t)(dx + padX) * dY.pix;
            if (sIdx >= 0 && sIdx < sY.cap && dIdx >= 0 && dIdx < dY.cap) dY.p[dIdx] = sY.p[sIdx];
        }
    }
    // Bidang U dan V
    int drawW2 = drawW / 2, drawH2 = drawH / 2, padX2 = padX / 2, padY2 = padY / 2;
    for (int dy = 0; dy < drawH2; dy++) {
        int vy = mapVY[dy * 2];
        int64_t uDstRow = (int64_t)(dy + padY2) * dU.row;
        int64_t vDstRow = (int64_t)(dy + padY2) * dV.row;
        for (int dx = 0; dx < drawW2; dx++) {
            int sx, sy;
            nv_peta_putar(srcRot, mapVX[dx * 2], vy, srcW, srcH, &sx, &sy);
            int uvSX = sx / 2, uvSY = sy / 2;
            int64_t sUIdx = (int64_t)uvSY * sU.row + (int64_t)uvSX * sU.pix;
            int64_t sVIdx = (int64_t)uvSY * sV.row + (int64_t)uvSX * sV.pix;
            int64_t dUIdx = uDstRow + (int64_t)(dx + padX2) * dU.pix;
            int64_t dVIdx = vDstRow + (int64_t)(dx + padX2) * dV.pix;
            if (sUIdx >= 0 && sUIdx < sU.cap && dUIdx >= 0 && dUIdx < dU.cap) dU.p[dUIdx] = sU.p[sUIdx];
            if (sVIdx >= 0 && sVIdx < sV.cap && dVIdx >= 0 && dVIdx < dV.cap) dV.p[dVIdx] = sV.p[sVIdx];
        }
    }
    free(mapVX); free(mapVY);
    return 1;
}

// Menyalin bingkai YUV420 yang sudah ada di memori (bidang Y, U, V terpisah) ke buffer encoder.
static int nv_salin_yuv(const uint8_t* y, int64_t yLen, const uint8_t* u, int64_t uLen, const uint8_t* v, int64_t vLen,
                        int outW, int outH, NVPlane dY, NVPlane dU, NVPlane dV) {
    if (outW <= 0 || outH <= 0) return 0;
    int uvW = outW / 2, uvH = outH / 2;
    if (yLen < (int64_t)outW * outH || uLen < (int64_t)uvW * uvH || vLen < (int64_t)uvW * uvH) return 0;
    for (int yy = 0; yy < outH; yy++) {
        int64_t dstOff = (int64_t)yy * dY.row;
        if (dY.pix == 1) {
            if (dstOff >= 0 && dstOff + outW <= dY.cap) memcpy(dY.p + dstOff, y + (int64_t)yy * outW, (size_t)outW);
        } else {
            for (int x = 0; x < outW; x++) {
                int64_t idx = dstOff + (int64_t)x * dY.pix;
                if (idx >= 0 && idx < dY.cap) dY.p[idx] = y[(int64_t)yy * outW + x];
            }
        }
    }
    for (int yy = 0; yy < uvH; yy++) {
        int64_t srcRow = (int64_t)yy * uvW;
        int64_t uDst = (int64_t)yy * dU.row, vDst = (int64_t)yy * dV.row;
        for (int x = 0; x < uvW; x++) {
            int64_t uIdx = uDst + (int64_t)x * dU.pix;
            int64_t vIdx = vDst + (int64_t)x * dV.pix;
            if (uIdx >= 0 && uIdx < dU.cap) dU.p[uIdx] = u[srcRow + x];
            if (vIdx >= 0 && vIdx < dV.cap) dV.p[vIdx] = v[srcRow + x];
        }
    }
    return 1;
}

static inline uint8_t nv_klem255(int v) { return (uint8_t)(v < 0 ? 0 : (v > 255 ? 255 : v)); }

// Mengubah piksel ARGB menjadi tiga bidang YUV420 (rumus sama dengan versi Java).
static int nv_argb_ke_yuv(const int32_t* argb, int w, int h, uint8_t* y, int64_t yLen, uint8_t* u, int64_t uLen, uint8_t* v, int64_t vLen) {
    if (w <= 0 || h <= 0) return 0;
    int uvW = w / 2;
    if (yLen < (int64_t)w * h || uLen < (int64_t)uvW * (h / 2) || vLen < (int64_t)uvW * (h / 2)) return 0;
    for (int j = 0; j < h; j++) {
        int64_t rowOff = (int64_t)j * w;
        int evenRow = (j % 2 == 0);
        int64_t uvRowOff = (int64_t)(j / 2) * uvW;
        for (int i = 0; i < w; i++) {
            int32_t c = argb[rowOff + i];
            int r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF;
            int yy = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
            y[rowOff + i] = nv_klem255(yy);
            if (evenRow && (i % 2 == 0)) {
                int64_t uvIdx = uvRowOff + (i / 2);
                if (uvIdx < (int64_t)uvW * (h / 2)) {
                    int uu = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
                    int vv = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
                    u[uvIdx] = nv_klem255(uu);
                    v[uvIdx] = nv_klem255(vv);
                }
            }
        }
    }
    return 1;
}

// ---- Akses JNI tanpa jni.h: tabel fungsi JNI memakai nomor urut baku dari spesifikasi JNI.
#define NV_JNI_GetArrayLength 171
#define NV_JNI_GetPrimitiveArrayCritical 222
#define NV_JNI_ReleasePrimitiveArrayCritical 223
#define NV_JNI_GetDirectBufferAddress 230
#define NV_JNI_GetDirectBufferCapacity 231

static inline const void* nv_jni_fn(void* env, int idx) { return (*(const void* const* const*)env)[idx]; }

static int nv_jni_bidang(void* env, void* buf, int row, int pix, NVPlane* out) {
    if (!buf) return 0;
    typedef void* (*FAddr)(void*, void*);
    typedef int64_t (*FCap)(void*, void*);
    void* a = ((FAddr)nv_jni_fn(env, NV_JNI_GetDirectBufferAddress))(env, buf);
    int64_t c = ((FCap)nv_jni_fn(env, NV_JNI_GetDirectBufferCapacity))(env, buf);
    if (!a || c < 0) return 0;
    out->p = (uint8_t*)a; out->cap = c; out->row = row; out->pix = pix;
    return 1;
}

// Menyalin isi larik int Java ke larik lokal (n elemen). 1 bila berhasil.
static int nv_jni_baca_int(void* env, void* arr, int32_t* dst, int n) {
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    if (!arr) return 0;
    if (((FLen)nv_jni_fn(env, NV_JNI_GetArrayLength))(env, arr) < n) return 0;
    void* q = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, arr, 0);
    if (!q) return 0;
    memcpy(dst, q, sizeof(int32_t) * (size_t)n);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, arr, q, 2 /* JNI_ABORT */);
    return 1;
}

// ---- Pencampuran suara (versi 5): suara narasi + musik dengan volume dan fade, per potongan.
// Setara dengan perulangan per sampel di Java (racikAudioStatus). Mengembalikan 1 bila berhasil.
// Hanya memakai bilangan 32-bit untuk pembagian/konversi (aman untuk ARM 32-bit).
static int nv_campur_pcm(const uint8_t* bn, const uint8_t* bi, uint8_t* bo, int64_t lenN, int64_t lenI, int64_t lenO,
                         int nF, int ch, int64_t curF, int64_t dInstF, int64_t fInF, int64_t fOutF, int64_t totFrames,
                         float vNar, float vInst) {
    if (nF < 0 || ch < 1 || ch > 2) return 0;
    int64_t need = (int64_t)nF * ch * 2;
    if (lenN < need || lenI < need || lenO < need) return 0;
    if (fInF > 2000000000LL || fOutF > 2000000000LL) return 0;
    for (int i = 0; i < nF; i++) {
        int64_t fIdx = curF + i;
        float env = 1.0f;
        if (fInF > 0 && fIdx >= dInstF && (fIdx - dInstF) < fInF)
            env *= (float)(int32_t)(fIdx - dInstF) / (float)(int32_t)fInF;
        if (fOutF > 0 && (totFrames - fIdx) < fOutF)
            env *= (float)(int32_t)(totFrames - fIdx) / (float)(int32_t)fOutF;
        for (int c = 0; c < ch; c++) {
            size_t k = ((size_t)i * ch + c) * 2;
            int sn = (int16_t)(uint16_t)(bn[k] | (bn[k + 1] << 8));
            int si = (int16_t)(uint16_t)(bi[k] | (bi[k + 1] << 8));
            float x = ((float)sn * vNar) + ((float)si * vInst * env);
            int m = (int)floorf(x + 0.5f);
            if (m > 32767) m = 32767; else if (m < -32768) m = -32768;
            bo[k] = (uint8_t)(m & 0xFF);
            bo[k + 1] = (uint8_t)((m >> 8) & 0xFF);
        }
    }
    return 1;
}

// ============================================================================
//  RANTAI EFEK (versi 6): gate, ekualiser (tone), echo, reverb (Freeverb), dan pengganti sensor.
//  Setara dengan perulangan per sampel di Java (terapkanEfekSegmen). Parameter diturunkan oleh Java
//  (sama persis dengan yang dipakai versi Java), di sini hanya jalannya filter yang dipindah.
//  Keadaan filter disimpan di memori native sepanjang satu pekerjaan.
// ============================================================================
struct NVBiq { double b0, b1, b2, a1, a2, x1, x2, y1, y2; };
struct NVGate { float th, att, rel, env, gain; };
struct NVEcho { int delay, idx; float fb, damp, dry, wet, store; float* buf; };
struct NVComb { float* buf; int size, idx; float fb, store, d1, d2; };
struct NVAll { float* buf; int size, idx; };
struct NVFv { NVComb c[8]; NVAll a[4]; float wet, dry; };
struct NVTone { int n; NVBiq st[7]; };
struct NVSeg {
    int64_t bs, be, fade, frameLen;
    int flags, kind;
    float freq, vol, mix;
    NVGate g[2]; NVTone t[2]; NVEcho e[2]; NVFv f[2];
};
struct NVChain { int ch, sr, nseg; NVSeg* seg; };

static void nv_rantai_lepas(NVChain* C) {
    if (!C) return;
    for (int s = 0; s < C->nseg; s++) {
        NVSeg* S = &C->seg[s];
        for (int c = 0; c < 2; c++) {
            if (S->e[c].buf) free(S->e[c].buf);
            for (int i = 0; i < 8; i++) if (S->f[c].c[i].buf) free(S->f[c].c[i].buf);
            for (int i = 0; i < 4; i++) if (S->f[c].a[i].buf) free(S->f[c].a[i].buf);
        }
    }
    free(C->seg);
    free(C);
}

// Membangun rantai dari larik parameter. Mengembalikan 0 bila parameter tidak masuk akal (Java memakai cara lama).
static NVChain* nv_rantai_buat(const int64_t* L, int nL, const double* D, int nD, int ch, int sr) {
    if (ch < 1 || ch > 2 || sr < 8000 || sr > 96000 || nL < 0 || (nL % 6) != 0) return 0;
    int nseg = nL / 6;
    NVChain* C = (NVChain*)calloc(1, sizeof(NVChain));
    if (!C) return 0;
    C->ch = ch; C->sr = sr; C->nseg = nseg;
    C->seg = (NVSeg*)calloc((size_t)(nseg > 0 ? nseg : 1), sizeof(NVSeg));
    if (!C->seg) { free(C); return 0; }
    int p = 0, bad = 0;
#define NV_RD() (p < nD ? D[p++] : (bad = 1, 0.0))
    for (int s = 0; s < nseg && !bad; s++) {
        NVSeg* S = &C->seg[s];
        S->bs = L[s * 6]; S->be = L[s * 6 + 1]; S->flags = (int)L[s * 6 + 2]; S->kind = (int)L[s * 6 + 3];
        S->fade = L[s * 6 + 4]; S->frameLen = L[s * 6 + 5];
        if (S->flags & 1) for (int c = 0; c < ch; c++) {
            S->g[c].th = (float)NV_RD(); S->g[c].att = (float)NV_RD(); S->g[c].rel = (float)NV_RD();
        }
        if (S->flags & 2) for (int c = 0; c < ch; c++) {
            int n = (int)NV_RD();
            if (n < 0 || n > 7) { bad = 1; break; }
            S->t[c].n = n;
            for (int i = 0; i < n; i++) {
                S->t[c].st[i].b0 = NV_RD(); S->t[c].st[i].b1 = NV_RD(); S->t[c].st[i].b2 = NV_RD();
                S->t[c].st[i].a1 = NV_RD(); S->t[c].st[i].a2 = NV_RD();
            }
        }
        if (S->flags & 4) for (int c = 0; c < ch; c++) {
            NVEcho* E = &S->e[c];
            E->delay = (int)NV_RD(); E->fb = (float)NV_RD(); E->damp = (float)NV_RD();
            E->dry = (float)NV_RD(); E->wet = (float)NV_RD();
            if (E->delay < 1 || E->delay > sr * 2) { bad = 1; break; }
            if (E->delay > 1) { E->buf = (float*)calloc((size_t)E->delay, sizeof(float)); if (!E->buf) { bad = 1; break; } }
        }
        if (S->flags & 8) for (int c = 0; c < ch; c++) {
            NVFv* F = &S->f[c];
            int cs[8], as[4];
            for (int i = 0; i < 8; i++) cs[i] = (int)NV_RD();
            for (int i = 0; i < 4; i++) as[i] = (int)NV_RD();
            float fb = (float)NV_RD(), d1 = (float)NV_RD(), d2 = (float)NV_RD();
            F->wet = (float)NV_RD(); F->dry = (float)NV_RD();
            if (bad) break;
            for (int i = 0; i < 8; i++) {
                if (cs[i] < 1 || cs[i] > sr) { bad = 1; break; }
                F->c[i].size = cs[i]; F->c[i].fb = fb; F->c[i].d1 = d1; F->c[i].d2 = d2;
                F->c[i].buf = (float*)calloc((size_t)cs[i], sizeof(float));
                if (!F->c[i].buf) { bad = 1; break; }
            }
            for (int i = 0; i < 4 && !bad; i++) {
                if (as[i] < 1 || as[i] > sr) { bad = 1; break; }
                F->a[i].size = as[i];
                F->a[i].buf = (float*)calloc((size_t)as[i], sizeof(float));
                if (!F->a[i].buf) { bad = 1; break; }
            }
            if (bad) break;
        }
        if (S->flags & 16) { S->freq = (float)NV_RD(); S->vol = (float)NV_RD(); S->mix = (float)NV_RD(); }
    }
#undef NV_RD
    if (bad) { nv_rantai_lepas(C); return 0; }
    return C;
}

static inline int16_t nv_k16(float v) {
    if (v > 32767.0f) v = 32767.0f;
    if (v < -32768.0f) v = -32768.0f;
    return (int16_t)(int)v;
}

static inline int16_t nv_gate_p(NVGate* g, int16_t in) {
    if (g->th <= 0.0f) return in;
    float absIn = fabsf((float)in);
    if (absIn > g->env) g->env = g->att * g->env + (1.0f - g->att) * absIn;
    else g->env = g->rel * g->env + (1.0f - g->rel) * absIn;
    float tg = (g->env > g->th) ? 1.0f : 0.0f;
    if (tg > g->gain) g->gain = g->att * g->gain + (1.0f - g->att) * tg;
    else g->gain = g->rel * g->gain + (1.0f - g->rel) * tg;
    return (int16_t)(int)((float)in * g->gain);
}

static inline double nv_lembut(double v) {
    double a = fabs(v);
    if (a <= 26000.0) return v;
    double sisa = 32767.0 - 26000.0;
    double y = 26000.0 + sisa * tanh((a - 26000.0) / sisa);
    return v < 0 ? -y : y;
}

static inline int16_t nv_tone_p(NVTone* T, int16_t in) {
    double v = (double)in;
    for (int i = 0; i < T->n; i++) {
        NVBiq* q = &T->st[i];
        double y = q->b0 * v + q->b1 * q->x1 + q->b2 * q->x2 - q->a1 * q->y1 - q->a2 * q->y2;
        q->x2 = q->x1; q->x1 = v;
        q->y2 = q->y1; q->y1 = y;
        v = y;
    }
    return (int16_t)(int64_t)floor(nv_lembut(v) + 0.5);
}

static inline int16_t nv_echo_p(NVEcho* E, int16_t input) {
    if (E->delay <= 1) {
        float mixed = ((float)input * E->dry) + ((float)input * E->wet);
        return nv_k16(mixed);
    }
    float in = (float)input;
    float bufOut = E->buf[E->idx];
    E->store = (bufOut * (1.0f - E->damp)) + (E->store * E->damp);
    E->buf[E->idx] = in + (E->store * E->fb);
    E->idx++;
    if (E->idx >= E->delay) E->idx = 0;
    float mixed = (in * E->dry) + (bufOut * E->wet);
    return nv_k16(mixed);
}

static inline int16_t nv_fv_p(NVFv* F, int16_t input) {
    float in = (float)input * 0.015f;
    float out = 0.0f;
    for (int i = 0; i < 8; i++) {
        NVComb* c = &F->c[i];
        float o = c->buf[c->idx];
        c->store = (o * c->d2) + (c->store * c->d1);
        c->buf[c->idx] = in + (c->store * c->fb);
        c->idx++;
        if (c->idx >= c->size) c->idx = 0;
        out += o;
    }
    for (int i = 0; i < 4; i++) {
        NVAll* a = &F->a[i];
        float bo = a->buf[a->idx];
        float o = -out + bo;
        a->buf[a->idx] = out + (bo * 0.5f);
        a->idx++;
        if (a->idx >= a->size) a->idx = 0;
        out = o;
    }
    float mixed = (out * F->wet) + ((float)input * F->dry);
    return nv_k16(mixed);
}

static inline float nv_bunyi_sensor(int kind, float freq, int32_t rel, int ch, int sr) {
    double t = (double)rel / (double)sr;
    if (kind == 1) return (float)sin(2.0 * NV_PI * (double)freq * t);
    if (kind == 3) {
        uint64_t h = (uint64_t)(int64_t)rel * 2654435761ULL + (uint64_t)ch * 40503ULL + 12345ULL;
        h ^= (h >> 15);
        h *= 2246822519ULL;
        h ^= (h >> 13);
        h *= 3266489917ULL;
        h ^= (h >> 16);
        return (float)(((double)(h & 0xFFFFULL) / 32767.5) - 1.0);
    }
    if (kind == 4) {
        double w = 2.0 * NV_PI * (double)freq * t;
        return (float)(0.7 * sin(w) + 0.3 * sin(2.0 * w));
    }
    return 0.0f;
}

// Memproses satu potongan PCM 16-bit. base = posisi byte global potongan ini. 1 bila berhasil.
static int nv_rantai_proses(NVChain* C, const uint8_t* in, int read, uint8_t* out, int64_t base) {
    int ch = C->ch, fs = ch * 2;
    if (read < 0 || (read % fs) != 0) return 0;
    for (int s = 0; s < C->nseg; s++) {
        if ((C->seg[s].flags & 16) && (base + (int64_t)read) - C->seg[s].bs > 2000000000LL) return 0;
    }
    int frames = read / fs;
    for (int f = 0; f < frames; f++) {
        int64_t pos = base + (int64_t)f * fs;
        for (int c = 0; c < ch; c++) {
            size_t k = ((size_t)f * ch + c) * 2;
            int16_t sample = (int16_t)(uint16_t)(in[k] | (in[k + 1] << 8));
            for (int s = 0; s < C->nseg; s++) {
                NVSeg* S = &C->seg[s];
                if (!(pos >= S->bs && pos < S->be)) continue;
                if (S->flags & 1) sample = nv_gate_p(&S->g[c], sample);
                if (S->flags & 2) sample = nv_tone_p(&S->t[c], sample);
                if (S->flags & 4) sample = nv_echo_p(&S->e[c], sample);
                if (S->flags & 8) sample = nv_fv_p(&S->f[c], sample);
                if (S->flags & 16) {
                    int32_t rel = (int32_t)(pos - S->bs) / fs;
                    double env = 1.0;
                    if (S->fade > 0) {
                        double a1 = (double)rel / (double)S->fade;
                        double a2 = (double)(S->frameLen - (int64_t)rel) / (double)S->fade;
                        env = a2 < a1 ? a2 : a1;
                        if (env > 1.0) env = 1.0;
                        if (env < 0.0) env = 0.0;
                    }
                    float tahan = (float)(1.0 - env * (1.0 - (double)S->mix));
                    float bunyi = nv_bunyi_sensor(S->kind, S->freq, rel, c, C->sr) * S->vol * 30000.0f * (float)env;
                    int hasil = (int)((float)sample * tahan + bunyi);
                    if (hasil > 32767) hasil = 32767;
                    if (hasil < -32768) hasil = -32768;
                    sample = (int16_t)hasil;
                }
            }
            out[k] = (uint8_t)(sample & 0xFF);
            out[k + 1] = (uint8_t)(((int)sample >> 8) & 0xFF);
        }
    }
    return 1;
}



// ============================================================================
//  MESIN NADA LANGSUNG (versi 9)
//  Satu sesi memuat seluruh vokal (16-bit mono) ke memori, menganalisis titik
//  penanda nada SATU KALI, lalu menyusun suara keluaran blok demi blok sesuai
//  kontur pergeseran nada yang boleh diubah kapan saja saat diputar.
//  Cara sintesis sama dengan nv_synth_kontur (TD-PSOLA, formant tetap), hanya
//  dibuat mengalir: keadaan (posisi grain, penampung tumpang-tindih) disimpan
//  di antara blok sehingga tidak ada sambungan kasar.
//  Render dipanggil dari satu thread pemutar saja; Kontur boleh dari thread lain.
// ============================================================================
#define NV_LV_HALFMAX 1200
#define NV_LV_BUF 16384
#define NV_LV_BLOK_MAKS 8192
#define NV_LV_RAD 16

struct NVLive {
    int sr, n, khop, nk;
    int16_t* x;
    int mn, mcap;
    int* mpos; int* mT; unsigned char* mvc;
    volatile int prog;
    volatile int batal;
    volatile int analisisOk;
    float* target;
    float kern[2 * NV_LV_RAD + 1];
    float* acc; float* wac;
    int64_t base;
    double ts;
    double tsPrev;
    int j;
    int mulai;
    int fadeMasuk;
    void* sd;
};

static inline float nv_lv_x(const NVLive* L, int64_t i) {
    return (i >= 0 && i < (int64_t)L->n) ? (float)L->x[i] * (1.0f / 32768.0f) : 0.0f;
}

static int nv_lv_push(NVLive* L, int pos, int T, int vc) {
    if (L->mn >= L->mcap) {
        int nc = L->mcap * 2 + 1024;
        int* a = (int*)realloc(L->mpos, sizeof(int) * (size_t)nc);
        if (!a) return 0;
        L->mpos = a;
        int* b = (int*)realloc(L->mT, sizeof(int) * (size_t)nc);
        if (!b) return 0;
        L->mT = b;
        unsigned char* c = (unsigned char*)realloc(L->mvc, (size_t)nc);
        if (!c) return 0;
        L->mvc = c;
        L->mcap = nc;
    }
    L->mpos[L->mn] = pos; L->mT[L->mn] = T; L->mvc[L->mn] = (unsigned char)vc; L->mn++;
    return 1;
}

static void nv_sd_bebas(void* q);

static void nv_lv_lepas(NVLive* L) {
    if (!L) return;
    nv_sd_bebas(L->sd);
    free(L->x); free(L->mpos); free(L->mT); free(L->mvc);
    free(L->target); free(L->acc); free(L->wac);
    free(L);
}

static NVLive* nv_lv_buat(const char* path, int sr) {
    if (sr < 8000 || sr > 96000) return 0;
    FILE* f = fopen(path, "rb");
    if (!f) return 0;
    fseeko(f, 0, SEEK_END);
    long long fsz = (long long)ftello(f);
    long long n = fsz / 2;
    if (n < 2048 || n > (long long)sr * 1800LL) { fclose(f); return 0; }
    NVLive* L = (NVLive*)calloc(1, sizeof(NVLive));
    if (!L) { fclose(f); return 0; }
    L->sr = sr; L->n = (int)n; L->khop = sr / 200; if (L->khop < 1) L->khop = 1;
    L->nk = L->n / L->khop + 2;
    L->x = (int16_t*)malloc((size_t)n * 2);
    L->target = (float*)calloc((size_t)L->nk, sizeof(float));
    L->acc = (float*)calloc(NV_LV_BUF, sizeof(float));
    L->wac = (float*)calloc(NV_LV_BUF, sizeof(float));
    if (!L->x || !L->target || !L->acc || !L->wac) { fclose(f); nv_lv_lepas(L); return 0; }
    fseeko(f, 0, SEEK_SET);
    size_t got = fread(L->x, 2, (size_t)n, f);
    fclose(f);
    if (got < (size_t)n) memset(L->x + got, 0, ((size_t)n - got) * 2);
    // kernel penghalus = 16 kali rata-rata bergerak 3 titik (sama dengan rpHaluskan di Java)
    double k[2 * NV_LV_RAD + 1], t[2 * NV_LV_RAD + 1];
    for (int i = 0; i <= 2 * NV_LV_RAD; i++) k[i] = 0.0;
    k[NV_LV_RAD] = 1.0;
    for (int pass = 0; pass < NV_LV_RAD; pass++) {
        for (int i = 0; i <= 2 * NV_LV_RAD; i++) {
            double a = i > 0 ? k[i - 1] : 0.0, b = k[i], c = i < 2 * NV_LV_RAD ? k[i + 1] : 0.0;
            t[i] = (a + b + c) / 3.0;
        }
        for (int i = 0; i <= 2 * NV_LV_RAD; i++) k[i] = t[i];
    }
    for (int i = 0; i <= 2 * NV_LV_RAD; i++) L->kern[i] = (float)k[i];
    return L;
}

static int nv_lv_analisis(NVLive* L) {
    const int sr = L->sr;
    const int CHUNK = sr * 30;
    const int MARG = sr / 2;
    L->mn = 0;
    int64_t start = 0;
    while (start < L->n) {
        if (L->batal) return 0;
        int64_t end = start + CHUNK;
        if (end >= L->n) end = L->n;
        else {
            int64_t a = end - sr; if (a < start + sr) a = start + sr;
            int64_t b = end + sr; if (b > L->n) b = L->n;
            int blk = (int)(0.020f * (float)sr); if (blk < 16) blk = 16;
            double bestE = 1e30; int64_t bestPos = end;
            for (int64_t s = a; s + blk <= b; s += blk / 2) {
                double e = 0.0;
                for (int i = 0; i < blk; i++) { double v = (double)L->x[s + i]; e += v * v; }
                if (e < bestE) { bestE = e; bestPos = s + blk / 2; }
            }
            end = bestPos;
        }
        int64_t a = start - MARG; if (a < 0) a = 0;
        int64_t b = end + MARG; if (b > L->n) b = L->n;
        int len = (int)(b - a);
        float* mono = (float*)malloc(sizeof(float) * (size_t)len);
        if (!mono) return 0;
        for (int i = 0; i < len; i++) mono[i] = (float)L->x[a + i] * (1.0f / 32768.0f);
        NVPitch P; NVMarks M;
        nv_pitch_track(mono, len, sr, &P);
        nv_marks_build(mono, len, sr, &P, &M);
        for (int i = 0; i < M.n; i++) {
            int64_t ap = a + M.pos[i];
            if (ap >= start && ap < end) {
                if (!nv_lv_push(L, (int)ap, M.T[i], M.vc[i])) { nv_marks_free(&M); nv_pitch_free(&P); free(mono); return 0; }
            }
        }
        nv_marks_free(&M);
        nv_pitch_free(&P);
        free(mono);
        start = end;
        L->prog = (int)((start * 100) / L->n);
    }
    L->prog = 100;
    L->analisisOk = 1;
    return 1;
}

static float nv_lv_halus(const NVLive* L, int f) {
    float s = 0.0f;
    for (int i = -NV_LV_RAD; i <= NV_LV_RAD; i++) {
        int q = f + i;
        if (q < 0) q = 0;
        if (q > L->nk - 1) q = L->nk - 1;
        s += L->kern[i + NV_LV_RAD] * L->target[q];
    }
    return s;
}

static float nv_lv_semi_at(const NVLive* L, double posAbs) {
    double p = posAbs / (double)L->khop - 0.5;
    if (p <= 0.0) return nv_lv_halus(L, 0);
    if (p >= (double)(L->nk - 1)) return nv_lv_halus(L, L->nk - 1);
    int i = (int)p;
    double fr = p - (double)i;
    double a = (double)nv_lv_halus(L, i), b = (double)nv_lv_halus(L, i + 1);
    return (float)(a + (b - a) * fr);
}

static int nv_lv_cari_j(const NVLive* L, double ts) {
    int lo = 0, hi = L->mn - 1;
    if (hi < 0) return 0;
    while (lo < hi) {
        int mid = (lo + hi) / 2;
        if ((double)L->mpos[mid] < ts) lo = mid + 1; else hi = mid;
    }
    if (lo > 0 && fabs((double)L->mpos[lo - 1] - ts) <= fabs((double)L->mpos[lo] - ts)) lo--;
    return lo;
}

static int nv_lv_mulai(NVLive* L, int64_t pos) {
    if (!L->analisisOk) return 0;
    if (pos < 0) pos = 0;
    if (pos > L->n) pos = L->n;
    memset(L->acc, 0, sizeof(float) * NV_LV_BUF);
    memset(L->wac, 0, sizeof(float) * NV_LV_BUF);
    L->base = pos;
    L->ts = (double)pos - (double)(NV_LV_HALFMAX + 64);
    L->tsPrev = L->ts - 1.0;
    L->j = nv_lv_cari_j(L, L->ts);
    L->fadeMasuk = (int)(0.003f * (float)L->sr);
    L->mulai = 1;
    return 1;
}

// flags: 1 = mengecil sampai senyap (untuk berhenti/pindah)
static int nv_lv_render(NVLive* L, int16_t* out, int nFr, int flags) {
    if (!L->mulai || !L->analisisOk) return 0;
    if (nFr <= 0 || nFr > NV_LV_BLOK_MAKS) return -1;
    const int HM = NV_LV_HALFMAX;
    const int64_t lim = L->base + nFr;
    int guard = 0;
    while (L->mn > 0 && L->ts - (double)HM < (double)lim && L->ts < (double)L->n + 2.0 * HM && guard < 200000) {
        guard++;
        double ts = L->ts;
        int j = L->j;
        while (j + 1 < L->mn && fabs((double)L->mpos[j + 1] - ts) <= fabs((double)L->mpos[j] - ts)) j++;
        L->j = j;
        int T = L->mT[j];
        if (T > HM) T = HM;
        if (T < 8) T = 8;
        int voiced = L->mvc[j];
        double semi = voiced ? (double)nv_lv_semi_at(L, ts) : 0.0;
        if (fabs(semi) < 0.002) semi = 0.0;
        if (semi > 24.0) semi = 24.0;
        if (semi < -24.0) semi = -24.0;
        if (semi == 0.0) {
            double pj = (double)L->mpos[j];
            if (pj > L->tsPrev && fabs(pj - ts) <= (double)T) ts = pj;
        }
        double ratio = pow(2.0, semi / 12.0);
        int c = L->mpos[j];
        int64_t di0 = (int64_t)floor(ts + 0.5);
        for (int k = -T; k <= T; k++) {
            int64_t di = di0 + k;
            if (di < L->base || di >= L->base + NV_LV_BUF) continue;
            float w = 0.5f * (1.0f + cosf((float)NV_PI * (float)k / (float)T));
            int idx = (int)(di - L->base);
            L->acc[idx] += nv_lv_x(L, (int64_t)c + k) * w;
            L->wac[idx] += w;
        }
        L->tsPrev = ts;
        L->ts = ts + (double)T / ratio;
    }
    for (int i = 0; i < nFr; i++) {
        int64_t ab = L->base + i;
        float y = 0.0f;
        if (ab >= 0 && ab < (int64_t)L->n) {
            float w = L->wac[i], a = L->acc[i];
            y = (w >= 1.0f) ? a / w : a + nv_lv_x(L, ab) * (1.0f - w);
        }
        if (L->fadeMasuk > 0) {
            int tot = (int)(0.003f * (float)L->sr); if (tot < 1) tot = 1;
            y *= (float)(tot - L->fadeMasuk + 1) / (float)tot;
            L->fadeMasuk--;
        }
        if (flags & 1) y *= 1.0f - (float)(i + 1) / (float)nFr;
        y = nv_soft(y);
        int q = (int)lrintf(y * 32767.0f);
        if (q > 32767) q = 32767;
        if (q < -32768) q = -32768;
        out[i] = (int16_t)q;
    }
    memmove(L->acc, L->acc + nFr, sizeof(float) * (size_t)(NV_LV_BUF - nFr));
    memmove(L->wac, L->wac + nFr, sizeof(float) * (size_t)(NV_LV_BUF - nFr));
    memset(L->acc + (NV_LV_BUF - nFr), 0, sizeof(float) * (size_t)nFr);
    memset(L->wac + (NV_LV_BUF - nFr), 0, sizeof(float) * (size_t)nFr);
    L->base += nFr;
    return nFr;
}

// ============================================================================
//  SUARA DUA LANGSUNG (versi 10)
//  Memakai penanda nada dari sesi NVLive yang sama (analisis hanya SATU kali), lalu menyusun
//  suara asli + hingga 3 suara tambahan blok demi blok, dengan rumus yang sama dengan nv_synth
//  (TD-PSOLA, geser formant, variasi alami, penundaan, pan). Semua parameter boleh diubah
//  kapan saja saat diputar; semiton dan penundaan dihaluskan per butir supaya tidak berdetak.
//  Semua fungsi sd dipanggil dari SATU thread pemutar saja.
//  Urutan parameter p: 0 suara asli, 1 geser formant (semiton), 2 kealamian (0..1), 3 gain tak bersuara,
//  lalu 5 angka per suara (mulai indeks 4 + 5 * suara): pakai (0/1), semiton, level, pan (-1..1), tunda (md).
// ============================================================================
#define NV_SD_VOX 3
#define NV_SD_NPAR 19

struct NVSdVox {
    float* acc; float* wac;
    double ts, tsPrev, semiCur, dlyCur;
    int j, aktif, init;
};

struct NVSd {
    float p[NV_SD_NPAR];
    NVSdVox v[NV_SD_VOX];
    int64_t base;
    int mulai, fadeMasuk;
};

static void nv_sd_bebas(void* q) {
    NVSd* S = (NVSd*)q;
    if (!S) return;
    for (int v = 0; v < NV_SD_VOX; v++) { free(S->v[v].acc); free(S->v[v].wac); }
    free(S);
}

static NVSd* nv_sd_pastikan(NVLive* L) {
    if (L->sd) return (NVSd*)L->sd;
    NVSd* S = (NVSd*)calloc(1, sizeof(NVSd));
    if (!S) return 0;
    for (int v = 0; v < NV_SD_VOX; v++) {
        S->v[v].acc = (float*)calloc(NV_LV_BUF, sizeof(float));
        S->v[v].wac = (float*)calloc(NV_LV_BUF, sizeof(float));
        if (!S->v[v].acc || !S->v[v].wac) { nv_sd_bebas(S); return 0; }
    }
    S->p[0] = 1.0f; S->p[3] = 0.6f;
    L->sd = S;
    return S;
}

static int nv_sd_atur(NVLive* L, const float* p, int n) {
    NVSd* S = nv_sd_pastikan(L);
    if (!S) return 0;
    if (n > NV_SD_NPAR) n = NV_SD_NPAR;
    for (int i = 0; i < n; i++) {
        float v = p[i];
        if (v != v) v = 0.0f;
        S->p[i] = v;
    }
    return 1;
}

static int nv_sd_mulai(NVLive* L, int64_t pos) {
    if (!L->analisisOk) return 0;
    NVSd* S = nv_sd_pastikan(L);
    if (!S) return 0;
    if (pos < 0) pos = 0;
    if (pos > L->n) pos = L->n;
    S->base = pos;
    for (int v = 0; v < NV_SD_VOX; v++) S->v[v].aktif = 0;   // disiapkan ulang pada render pertama
    S->fadeMasuk = (int)(0.003f * (float)L->sr);
    S->mulai = 1;
    return 1;
}

static void nv_sd_siapkan_suara(NVLive* L, NVSd* S, int v) {
    NVSdVox* V = &S->v[v];
    const double sr = (double)L->sr;
    memset(V->acc, 0, sizeof(float) * NV_LV_BUF);
    memset(V->wac, 0, sizeof(float) * NV_LV_BUF);
    double nat = (double)S->p[2]; if (nat < 0.0) nat = 0.0; if (nat > 1.5) nat = 1.5;
    double tunda = (double)S->p[4 + v * 5 + 4]; if (tunda < 0.0) tunda = 0.0; if (tunda > 200.0) tunda = 200.0;
    double dlyMax = tunda * sr / 1000.0 + nat * 0.001 * sr + 4.0;
    V->ts = (double)S->base - (double)NV_LV_HALFMAX - 64.0 - dlyMax;
    V->tsPrev = V->ts - 1.0;
    V->j = nv_lv_cari_j(L, V->ts);
    V->dlyCur = tunda * sr / 1000.0;
    V->init = 0;
    V->aktif = 1;
}

// flags: 1 = mengecil sampai senyap. ch = 1 atau 2 (keluaran interleaved).
static int nv_sd_render(NVLive* L, int16_t* out, int nFr, int ch, int flags) {
    NVSd* S = (NVSd*)L->sd;
    if (!S || !S->mulai || !L->analisisOk) return 0;
    if (nFr <= 0 || nFr > NV_LV_BLOK_MAKS) return -1;
    if (ch < 1) ch = 1; if (ch > 2) ch = 2;
    const int HM = NV_LV_HALFMAX;
    const double sr = (double)L->sr;
    const int64_t lim = S->base + nFr;
    double fo = (double)S->p[1]; if (fo < -12.0) fo = -12.0; if (fo > 12.0) fo = 12.0;
    const double fr = pow(2.0, fo / 12.0);
    double nat = (double)S->p[2]; if (nat < 0.0) nat = 0.0; if (nat > 1.5) nat = 1.5;
    float unv = S->p[3]; if (unv < 0.0f) unv = 0.0f; if (unv > 2.0f) unv = 2.0f;
    int pakai[NV_SD_VOX];
    for (int v = 0; v < NV_SD_VOX; v++) {
        const float* q = S->p + 4 + v * 5;
        pakai[v] = (q[0] > 0.5f && q[2] > 0.0001f) ? 1 : 0;
        if (!pakai[v]) { S->v[v].aktif = 0; continue; }
        if (!S->v[v].aktif) nv_sd_siapkan_suara(L, S, v);
        NVSdVox* V = &S->v[v];
        double tgtSemi = (double)q[1]; if (tgtSemi > 24.0) tgtSemi = 24.0; if (tgtSemi < -24.0) tgtSemi = -24.0;
        double tunda = (double)q[4]; if (tunda < 0.0) tunda = 0.0; if (tunda > 200.0) tunda = 200.0;
        const double tgtDly = tunda * sr / 1000.0;
        const double ph1 = 0.9 * (double)(v + 1), ph2 = 2.1 * (double)(v + 2), ph3 = 4.3 * (double)(v + 3), ph4 = 1.7 * (double)(v + 1);
        int guard = 0;
        while (L->mn > 0 && guard < 200000) {
            guard++;
            double ts = V->ts;
            if (ts >= (double)L->n + 2.0 * HM) break;
            double tsec = ts / sr;
            double dlyBase = V->dlyCur + (tgtDly - V->dlyCur) * 0.2;
            double dly = dlyBase + nat * 0.001 * sr * sin(2.0 * NV_PI * 0.37 * tsec + ph4);
            if (!(ts + dly - (double)HM < (double)lim)) break;
            V->dlyCur = dlyBase;
            int j = V->j;
            while (j + 1 < L->mn && fabs((double)L->mpos[j + 1] - ts) <= fabs((double)L->mpos[j] - ts)) j++;
            V->j = j;
            int T = L->mT[j];
            if (T > HM) T = HM;
            if (T < 8) T = 8;
            int voiced = L->mvc[j];
            double cents = nat * (6.0 * sin(2.0 * NV_PI * 0.31 * tsec + ph1)
                                  + 4.0 * sin(2.0 * NV_PI * 0.83 * tsec + ph2)
                                  + 2.5 * sin(2.0 * NV_PI * 4.7 * tsec + ph3));
            if (!V->init) { V->semiCur = tgtSemi; V->init = 1; }
            else V->semiCur += (tgtSemi - V->semiCur) * 0.35;
            double ratio = voiced ? pow(2.0, (V->semiCur + cents / 100.0) / 12.0) : 1.0;
            float gain = voiced ? 1.0f : unv;
            double c = (double)L->mpos[j];
            int64_t di0 = (int64_t)floor(ts + dly + 0.5);
            // waktu sebelum awal berkas tidak punya suara: jangan menempatkan grain (supaya awal yang ditunda tetap senyap)
            for (int k = -T; ts >= 0.0 && k <= T; k++) {
                int64_t di = di0 + k;
                if (di < S->base || di >= S->base + NV_LV_BUF) continue;
                float w = 0.5f * (1.0f + cosf((float)NV_PI * (float)k / (float)T));
                float s;
                if (fr == 1.0) s = nv_lv_x(L, (int64_t)c + k);
                else {
                    double pp = c + (double)k * fr;
                    int64_t ip = (int64_t)floor(pp);
                    float f2 = (float)(pp - (double)ip);
                    float a = nv_lv_x(L, ip), b = nv_lv_x(L, ip + 1);
                    s = a + (b - a) * f2;
                }
                int idx = (int)(di - S->base);
                V->acc[idx] += s * w * gain;
                V->wac[idx] += w;
            }
            V->tsPrev = ts;
            V->ts = ts + (double)T / ratio;
        }
    }
    const float dryG = S->p[0];
    for (int i = 0; i < nFr; i++) {
        int64_t ab = S->base + i;
        float dryV = nv_lv_x(L, ab) * dryG;
        float yv[NV_SD_VOX];
        for (int v = 0; v < NV_SD_VOX; v++) {
            if (!pakai[v]) { yv[v] = 0.0f; continue; }
            float w = S->v[v].wac[i];
            yv[v] = S->v[v].acc[i] / (w > 0.3f ? w : 0.3f);
        }
        float env = 1.0f;
        if (S->fadeMasuk > 0) {
            int tot = (int)(0.003f * (float)L->sr); if (tot < 1) tot = 1;
            env = (float)(tot - S->fadeMasuk + 1) / (float)tot;
            S->fadeMasuk--;
        }
        if (flags & 1) env *= 1.0f - (float)(i + 1) / (float)nFr;
        for (int c = 0; c < ch; c++) {
            float s = dryV;
            for (int v = 0; v < NV_SD_VOX; v++) {
                if (!pakai[v]) continue;
                const float* q = S->p + 4 + v * 5;
                s += q[2] * nv_pan_gain(q[3], c, ch) * yv[v];
            }
            s = nv_soft(s * env);
            int qv = (int)lrintf(s * 32767.0f);
            if (qv > 32767) qv = 32767;
            if (qv < -32768) qv = -32768;
            out[(size_t)i * ch + c] = (int16_t)qv;
        }
    }
    for (int v = 0; v < NV_SD_VOX; v++) {
        if (!pakai[v]) continue;
        NVSdVox* V = &S->v[v];
        memmove(V->acc, V->acc + nFr, sizeof(float) * (size_t)(NV_LV_BUF - nFr));
        memmove(V->wac, V->wac + nFr, sizeof(float) * (size_t)(NV_LV_BUF - nFr));
        memset(V->acc + (NV_LV_BUF - nFr), 0, sizeof(float) * (size_t)nFr);
        memset(V->wac + (NV_LV_BUF - nFr), 0, sizeof(float) * (size_t)nFr);
    }
    S->base += nFr;
    return nFr;
}

// ============================================================================
//  BASS & TREBLE + EKUALISER 5 BAND LANGSUNG (versi 11)
//  Satu filter yang berjalan blok demi blok pada PCM 16-bit (mono atau stereo, sisip) dan
//  pengaturannya boleh diubah KAPAN SAJA saat sedang diputar. Rumus filter, rentang dB, dan
//  pelunakan di ujung sama dengan kelas Tone di Java (jadi yang terdengar langsung sama dengan
//  hasil simpan). Perubahan nilai tidak melompat: dB berjalan mendekati sasaran sekitar 15 md
//  per langkah blok, sehingga tidak ada bunyi klik ketika penggeser digeser.
//  Tujuh tahap tetap: 0 bass (rak rendah 120 Hz), 1..5 pita (60, 250, 1000, 4000, 12000 Hz),
//  6 treble (rak tinggi 6 kHz). Tahap yang netral dilewati, dan keadaannya dikosongkan.
//  Urutan parameter p: 0 bass %, 1 treble %, 2..6 pita 1..5 %. (50 persen = netral)
//  Semua fungsi eq dipanggil dari SATU thread pemutar saja.
// ============================================================================
#define NV_EQ_N 7
struct NVEq {
    int sr, ch, diset;
    float tgt[NV_EQ_N];        // sasaran dalam dB
    double cur[NV_EQ_N];       // nilai dB yang sedang berjalan
    int aktif[NV_EQ_N];
    NVBiq st[2][NV_EQ_N];
};

static const double NV_EQ_HZ[NV_EQ_N] = {120.0, 60.0, 250.0, 1000.0, 4000.0, 12000.0, 6000.0};

static double nv_eq_pct_db(float pct, double range) {
    if (!(pct >= 0.0f)) pct = 0.0f;          // juga menangkap NaN
    if (pct > 100.0f) pct = 100.0f;
    double db = ((double)pct - 50.0) / 50.0 * range;
    return (fabs(db) >= 0.05) ? db : 0.0;
}

// Koefisien satu tahap (RBJ cookbook), sama dengan Tone.tambahShelf / Tone.tambahPeaking di Java.
static void nv_eq_koef(int idx, double fs, double dB, NVBiq* q) {
    double maxF = 0.45 * fs;
    double f0 = NV_EQ_HZ[idx];
    double b0, b1, b2, a0, a1, a2;
    double A = pow(10.0, dB / 40.0);
    if (idx == 0 || idx == 6) {
        if (f0 > maxF) f0 = maxF;
        double w0 = 2.0 * NV_PI * f0 / fs;
        double cs = cos(w0), sn = sin(w0);
        double alpha = sn / 2.0 * sqrt(2.0);
        double t = 2.0 * sqrt(A) * alpha;
        if (idx == 0) {
            b0 = A * ((A + 1) - (A - 1) * cs + t);
            b1 = 2.0 * A * ((A - 1) - (A + 1) * cs);
            b2 = A * ((A + 1) - (A - 1) * cs - t);
            a0 = (A + 1) + (A - 1) * cs + t;
            a1 = -2.0 * ((A - 1) + (A + 1) * cs);
            a2 = (A + 1) + (A - 1) * cs - t;
        } else {
            b0 = A * ((A + 1) + (A - 1) * cs + t);
            b1 = -2.0 * A * ((A - 1) + (A + 1) * cs);
            b2 = A * ((A + 1) + (A - 1) * cs - t);
            a0 = (A + 1) - (A - 1) * cs + t;
            a1 = 2.0 * ((A - 1) - (A + 1) * cs);
            a2 = (A + 1) - (A - 1) * cs - t;
        }
    } else {
        double w0 = 2.0 * NV_PI * f0 / fs;
        double cs = cos(w0);
        double alpha = sin(w0) / (2.0 * 1.0);   // Q = 1
        b0 = 1.0 + alpha * A; b1 = -2.0 * cs; b2 = 1.0 - alpha * A;
        a0 = 1.0 + alpha / A; a1 = -2.0 * cs; a2 = 1.0 - alpha / A;
    }
    q->b0 = b0 / a0; q->b1 = b1 / a0; q->b2 = b2 / a0;
    q->a1 = a1 / a0; q->a2 = a2 / a0;
}

static NVEq* nv_eq_buat(int sr, int ch) {
    if (sr < 8000 || sr > 96000 || ch < 1 || ch > 2) return 0;
    NVEq* E = (NVEq*)calloc(1, sizeof(NVEq));
    if (!E) return 0;
    E->sr = sr; E->ch = ch;
    return E;
}

static void nv_eq_kosongkan(NVEq* E, int idx) {
    for (int c = 0; c < 2; c++) {
        NVBiq* q = &E->st[c][idx];
        q->x1 = q->x2 = q->y1 = q->y2 = 0.0;
    }
}

static void nv_eq_reset(NVEq* E) {
    for (int i = 0; i < NV_EQ_N; i++) nv_eq_kosongkan(E, i);
}

// Memasang sasaran baru. Pemasangan pertama langsung berlaku (tanpa meluncur).
static int nv_eq_atur(NVEq* E, const float* p, int n) {
    if (!E || !p || n < NV_EQ_N) return 0;
    double fs = (double)E->sr, maxF = 0.45 * fs;
    float t[NV_EQ_N];
    t[0] = (float)nv_eq_pct_db(p[0], 15.0);
    t[6] = (float)nv_eq_pct_db(p[1], 15.0);
    for (int i = 1; i <= 5; i++) {
        t[i] = (float)nv_eq_pct_db(p[1 + i], 12.0);
        if (NV_EQ_HZ[i] > maxF) t[i] = 0.0f;
    }
    for (int i = 0; i < NV_EQ_N; i++) {
        E->tgt[i] = t[i];
        if (!E->diset) {
            E->cur[i] = (double)t[i];
            E->aktif[i] = (t[i] != 0.0f);
            if (E->aktif[i]) for (int c = 0; c < E->ch; c++) nv_eq_koef(i, fs, E->cur[i], &E->st[c][i]);
        }
    }
    E->diset = 1;
    return 1;
}

// Menggeser dB berjalan mendekati sasaran untuk satu blok sepanjang nFr bingkai.
static void nv_eq_langkah(NVEq* E, int nFr) {
    double fs = (double)E->sr;
    double alpha = 1.0 - exp(-(double)nFr / (fs * 0.015));
    for (int i = 0; i < NV_EQ_N; i++) {
        double d = (double)E->tgt[i] - E->cur[i];
        if (d == 0.0) continue;
        if (fabs(d) < 0.01) E->cur[i] = (double)E->tgt[i];
        else E->cur[i] += d * alpha;
        if (E->cur[i] == 0.0) {
            E->aktif[i] = 0;
            nv_eq_kosongkan(E, i);
        } else {
            if (!E->aktif[i]) nv_eq_kosongkan(E, i);
            E->aktif[i] = 1;
            for (int c = 0; c < E->ch; c++) {
                NVBiq* q = &E->st[c][i];
                double x1 = q->x1, x2 = q->x2, y1 = q->y1, y2 = q->y2;
                nv_eq_koef(i, fs, E->cur[i], q);       // hanya koefisien yang berganti, keadaan tetap
                q->x1 = x1; q->x2 = x2; q->y1 = y1; q->y2 = y2;
            }
        }
    }
}

// Memproses nFr bingkai (sisip) di tempat. 1 bila berhasil.
static int nv_eq_proses(NVEq* E, int16_t* x, int nFr) {
    if (!E || !E->diset || !x || nFr <= 0) return 0;
    nv_eq_langkah(E, nFr);
    int ada = 0;
    for (int i = 0; i < NV_EQ_N; i++) if (E->aktif[i]) { ada = 1; break; }
    if (!ada) return 1;
    int ch = E->ch;
    for (int f = 0; f < nFr; f++) {
        for (int c = 0; c < ch; c++) {
            double v = (double)x[(size_t)f * ch + c];
            for (int i = 0; i < NV_EQ_N; i++) {
                if (!E->aktif[i]) continue;
                NVBiq* q = &E->st[c][i];
                double y = q->b0 * v + q->b1 * q->x1 + q->b2 * q->x2 - q->a1 * q->y1 - q->a2 * q->y2;
                q->x2 = q->x1; q->x1 = v;
                q->y2 = q->y1; q->y1 = y;
                v = y;
            }
            double o = floor(nv_lembut(v) + 0.5);
            if (o > 32767.0) o = 32767.0;
            if (o < -32768.0) o = -32768.0;
            x[(size_t)f * ch + c] = (int16_t)(int)o;
        }
    }
    return 1;
}

// ============================================================================
//  PENGURANG KEBISINGAN (NOISE GATE) LANGSUNG (versi 12)
//  Sama dengan kelas NoiseGate di Java dan nv_gate_p: ambang = persen/100 * 8192, koefisien attack/release
//  = exp(-1000 / (sr * md)). Pengaturan boleh diubah KAPAN SAJA saat diputar; keadaan (envelope dan gain)
//  tetap berjalan sehingga tidak ada lompatan bunyi. Urutan parameter p: 0 sensitivitas %, 1 attack md,
//  2 release md. Sensitivitas 0 = gerbang mati. Semua fungsi dipanggil dari SATU thread pemutar saja.
// ============================================================================
struct NVGateL { int sr, ch, diset; NVGate g[2]; };

static NVGateL* nv_gl_buat(int sr, int ch) {
    if (sr < 8000 || sr > 96000 || ch < 1 || ch > 2) return 0;
    NVGateL* G = (NVGateL*)calloc(1, sizeof(NVGateL));
    if (!G) return 0;
    G->sr = sr; G->ch = ch;
    for (int c = 0; c < 2; c++) { G->g[c].env = 0.0f; G->g[c].gain = 1.0f; }
    return G;
}

static void nv_gl_reset(NVGateL* G) {
    for (int c = 0; c < 2; c++) { G->g[c].env = 0.0f; G->g[c].gain = 1.0f; }
}

static int nv_gl_atur(NVGateL* G, const float* p, int n) {
    if (!G || !p || n < 3) return 0;
    float pct = p[0], att = p[1], rel = p[2];
    if (!(pct >= 0.0f)) pct = 0.0f;
    if (pct > 100.0f) pct = 100.0f;
    if (!(att > 0.1f)) att = 0.1f;
    if (!(rel > 0.1f)) rel = 0.1f;
    if (att > 10000.0f) att = 10000.0f;
    if (rel > 10000.0f) rel = 10000.0f;
    float th = (pct / 100.0f) * 8192.0f;
    float ac = (float)exp(-1000.0 / (double)((float)G->sr * att));
    float rc = (float)exp(-1000.0 / (double)((float)G->sr * rel));
    for (int c = 0; c < 2; c++) { G->g[c].th = th; G->g[c].att = ac; G->g[c].rel = rc; }
    G->diset = 1;
    return 1;
}

static int nv_gl_proses(NVGateL* G, int16_t* x, int nFr) {
    if (!G || !G->diset || !x || nFr <= 0) return 0;
    int ch = G->ch;
    for (int f = 0; f < nFr; f++)
        for (int c = 0; c < ch; c++) {
            int16_t* q = &x[(size_t)f * ch + c];
            *q = nv_gate_p(&G->g[c], *q);
        }
    return 1;
}

// ============================================================================
//  REVERB DAN ECHO LANGSUNG (versi 13)
//  Sama dengan kelas Freeverb dan Echo di Java (dan nv_fv_p / nv_echo_p di jalur simpan), mono.
//  kind 1 = reverb, p = ruangan, peredam, asli (dry), gema (wet)           (pecahan 0..1)
//  kind 2 = echo,   p = jarak md, ekor (feedback), peredam, asli, pantulan (pecahan 0..1 kecuali md)
//  Pengaturan boleh diubah KAPAN SAJA saat diputar; ekor (isi penyangga) tetap berjalan sehingga tidak
//  terpotong. Pada echo, jarak yang berubah hanya memindahkan titik baca. Reset mengosongkan ekor.
//  Semua fungsi dipanggil dari SATU thread pemutar saja.
// ============================================================================
struct NVFxL { int kind, sr, diset, ecCap; NVFv fv; NVEcho ec; };

static void nv_fx_reset(NVFxL* X) {
    if (X->kind == 1) {
        for (int i = 0; i < 8; i++) { if (X->fv.c[i].buf) memset(X->fv.c[i].buf, 0, sizeof(float) * (size_t)X->fv.c[i].size); X->fv.c[i].idx = 0; X->fv.c[i].store = 0.0f; }
        for (int i = 0; i < 4; i++) { if (X->fv.a[i].buf) memset(X->fv.a[i].buf, 0, sizeof(float) * (size_t)X->fv.a[i].size); X->fv.a[i].idx = 0; }
    } else {
        if (X->ec.buf) memset(X->ec.buf, 0, sizeof(float) * (size_t)X->ecCap);
        X->ec.idx = 0; X->ec.store = 0.0f;
    }
}

static void nv_fx_lepas(NVFxL* X) {
    if (!X) return;
    for (int i = 0; i < 8; i++) free(X->fv.c[i].buf);
    for (int i = 0; i < 4; i++) free(X->fv.a[i].buf);
    free(X->ec.buf);
    free(X);
}

static NVFxL* nv_fx_buat(int kind, int sr) {
    if ((kind != 1 && kind != 2) || sr < 8000 || sr > 96000) return 0;
    NVFxL* X = (NVFxL*)calloc(1, sizeof(NVFxL));
    if (!X) return 0;
    X->kind = kind; X->sr = sr;
    if (kind == 1) {
        float scale = (float)sr / 44100.0f;
        const int cs[8] = {1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617};
        const int as[4] = {556, 441, 341, 225};
        for (int i = 0; i < 8; i++) {
            X->fv.c[i].size = (int)((float)cs[i] * scale);
            X->fv.c[i].buf = (float*)calloc((size_t)X->fv.c[i].size, sizeof(float));
            if (!X->fv.c[i].buf) { nv_fx_lepas(X); return 0; }
        }
        for (int i = 0; i < 4; i++) {
            X->fv.a[i].size = (int)((float)as[i] * scale);
            X->fv.a[i].buf = (float*)calloc((size_t)X->fv.a[i].size, sizeof(float));
            if (!X->fv.a[i].buf) { nv_fx_lepas(X); return 0; }
        }
    } else {
        X->ecCap = sr * 2;
        X->ec.buf = (float*)calloc((size_t)X->ecCap, sizeof(float));
        if (!X->ec.buf) { nv_fx_lepas(X); return 0; }
    }
    return X;
}

static inline float nv_fx_p01(float v) {
    if (!(v >= 0.0f)) return 0.0f;
    return v > 1.0f ? 1.0f : v;
}

static int nv_fx_atur(NVFxL* X, const float* p, int n) {
    if (!X || !p) return 0;
    if (X->kind == 1) {
        if (n < 4) return 0;
        float room = nv_fx_p01(p[0]), damp = nv_fx_p01(p[1]);
        float fb = (room * 0.28f) + 0.7f;
        float d = damp * 0.4f;
        for (int i = 0; i < 8; i++) { X->fv.c[i].fb = fb; X->fv.c[i].d1 = d; X->fv.c[i].d2 = 1.0f - d; }
        X->fv.dry = nv_fx_p01(p[2]);
        X->fv.wet = nv_fx_p01(p[3]) * 3.0f;
    } else {
        if (n < 5) return 0;
        float ms = p[0];
        if (!(ms >= 0.0f)) ms = 0.0f;
        if (ms > 1000.0f) ms = 1000.0f;
        int dl = (int)((ms / 1000.0f) * (float)X->sr);
        if (dl == 0) dl = 1;
        if (dl > X->ecCap) dl = X->ecCap;
        if (dl > X->ec.delay && X->ec.delay > 0) memset(X->ec.buf + X->ec.delay, 0, sizeof(float) * (size_t)(dl - X->ec.delay));
        X->ec.delay = dl;
        if (X->ec.idx >= dl) X->ec.idx = 0;
        X->ec.fb = nv_fx_p01(p[1]);
        X->ec.damp = nv_fx_p01(p[2]);
        X->ec.dry = nv_fx_p01(p[3]);
        X->ec.wet = nv_fx_p01(p[4]);
    }
    X->diset = 1;
    return 1;
}

static int nv_fx_proses(NVFxL* X, int16_t* x, int nFr) {
    if (!X || !X->diset || !x || nFr <= 0) return 0;
    if (X->kind == 1) { for (int i = 0; i < nFr; i++) x[i] = nv_fv_p(&X->fv, x[i]); }
    else { for (int i = 0; i < nFr; i++) x[i] = nv_echo_p(&X->ec, x[i]); }
    return 1;
}

// ===================== AUTOTUNE LANGSUNG (versi 14) =====================
// Setara nv_autotune (file), tetapi berjalan per potongan kecil yang masuk dari pemutar.
// Masuk: PCM 16-bit mono. Keluar: jumlah bingkai yang sama (ada tunda sekitar 1 blok analisis).
struct NVAtL {
    int sr, blockFrames, analysisFrames, qCap, qN, pendN, ringFilled, histCount, lastTarget, key, scale, diset;
    float hist[3], curSemi, alpha;
    NVSonic S;
    float* ring;
    int16_t* pend;
    int16_t* q;
    int16_t* ob;
};

static void nv_at_kosongkan(NVAtL* X) {
    nv_sonic_free(&X->S);
    nv_sonic_init(&X->S, X->sr, 1);
    X->pendN = 0; X->ringFilled = 0; X->histCount = 0; X->lastTarget = -1;
    X->hist[0] = X->hist[1] = X->hist[2] = 0.0f;
    X->curSemi = 0.0f;
    memset(X->ring, 0, sizeof(float) * (size_t)(X->analysisFrames + 4));
    memset(X->q, 0, sizeof(int16_t) * (size_t)X->blockFrames);
    X->qN = X->blockFrames;
}

static void nv_at_lepas(NVAtL* X) {
    if (!X) return;
    nv_sonic_free(&X->S);
    free(X->ring); free(X->pend); free(X->q); free(X->ob);
    free(X);
}

static NVAtL* nv_at_buat(int sr) {
    if (sr < 8000 || sr > 96000) return nullptr;
    NVAtL* X = (NVAtL*)calloc(1, sizeof(NVAtL));
    if (!X) return nullptr;
    X->sr = sr;
    X->blockFrames = sr / 40 > 256 ? sr / 40 : 256;
    X->analysisFrames = sr / 25 > X->blockFrames ? sr / 25 : X->blockFrames;
    X->qCap = X->blockFrames * 16;
    X->ring = (float*)calloc((size_t)X->analysisFrames + 4, sizeof(float));
    X->pend = (int16_t*)calloc((size_t)X->blockFrames + 4, sizeof(int16_t));
    X->q = (int16_t*)calloc((size_t)X->qCap + 4, sizeof(int16_t));
    X->ob = (int16_t*)calloc((size_t)X->blockFrames * 2 + 8, sizeof(int16_t));
    if (!X->ring || !X->pend || !X->q || !X->ob || !nv_sonic_init(&X->S, sr, 1)) { nv_at_lepas(X); return nullptr; }
    X->key = 0; X->scale = 0; X->alpha = 0.08f + 0.80f * 0.80f; X->diset = 0;
    nv_at_kosongkan(X);
    return X;
}

// p[0] = kunci (0..11), p[1] = tangga nada (0 kromatik, 1 mayor, 2 minor), p[2] = kecepatan 1..100
static int nv_at_atur(NVAtL* X, const float* p, int n) {
    if (!X || !p || n < 3) return 0;
    int k = (int)floorf(p[0] + 0.5f); k = ((k % 12) + 12) % 12;
    int sc = (int)floorf(p[1] + 0.5f); if (sc < 0) sc = 0; if (sc > 2) sc = 2;
    float sp = p[2]; if (!(sp >= 1.0f)) sp = 1.0f; if (sp > 100.0f) sp = 100.0f;
    X->key = k; X->scale = sc;
    X->alpha = (sp >= 95.0f) ? 0.94f : (0.08f + (sp / 100.0f) * 0.80f);
    X->diset = 1;
    return 1;
}

static void nv_at_blok(NVAtL* X) {
    int framesRead = X->blockFrames, analysisFrames = X->analysisFrames;
    int shift = X->ringFilled < analysisFrames - framesRead ? X->ringFilled : analysisFrames - framesRead;
    if (shift > 0 && X->ringFilled > shift) memmove(X->ring, X->ring + (X->ringFilled - shift), sizeof(float) * (size_t)shift);
    for (int i = 0; i < framesRead; i++) X->ring[shift + i] = (float)X->pend[i];
    X->ringFilled = shift + framesRead;
    float f0 = (X->ringFilled >= analysisFrames / 2) ? nv_yin(X->ring, X->ringFilled, X->sr) : -1.0f;
    if (f0 >= 75.0f && f0 <= 850.0f) {
        float midi = (float)(69.0 + 12.0 * (log((double)f0 / 440.0) / log(2.0)));
        X->hist[0] = X->hist[1]; X->hist[1] = X->hist[2]; X->hist[2] = midi;
        if (X->histCount < 3) X->histCount++;
        float smooth = midi;
        if (X->histCount == 3) {
            float a = X->hist[0], b = X->hist[1], c = X->hist[2];
            float mn = a < b ? a : b, mx = a > b ? a : b;
            float lo = mx < c ? mx : c;
            smooth = mn > lo ? mn : lo;
        }
        int target = nv_nada_target(smooth, X->key, X->scale, X->lastTarget);
        X->lastTarget = target;
        float desired = (float)target - smooth;
        if (desired > 5.0f) desired = 5.0f; else if (desired < -5.0f) desired = -5.0f;
        X->curSemi = X->curSemi + X->alpha * (desired - X->curSemi);
    } else {
        X->histCount = 0;
        X->curSemi *= 0.5f;
        if (fabsf(X->curSemi) < 0.02f) X->curSemi = 0.0f;
    }
    X->S.pitch = (float)pow(2.0, (double)X->curSemi / 12.0);
    nv_sonic_put(&X->S, X->pend, framesRead);
    for (;;) {
        int n = nv_sonic_receive(&X->S, X->ob, X->blockFrames * 2);
        if (n <= 0) break;
        if (X->qN + n > X->qCap) {
            int buang = X->qN + n - X->qCap;
            if (buang >= X->qN) { X->qN = 0; }
            else { memmove(X->q, X->q + buang, sizeof(int16_t) * (size_t)(X->qN - buang)); X->qN -= buang; }
            if (n > X->qCap) n = X->qCap;
        }
        memcpy(X->q + X->qN, X->ob, sizeof(int16_t) * (size_t)n);
        X->qN += n;
    }
}

static int nv_at_proses(NVAtL* X, int16_t* x, int nFr) {
    if (!X || !x || nFr <= 0) return 0;
    int i = 0;
    while (i < nFr) {
        int ambil = X->blockFrames - X->pendN;
        if (ambil > nFr - i) ambil = nFr - i;
        memcpy(X->pend + X->pendN, x + i, sizeof(int16_t) * (size_t)ambil);
        X->pendN += ambil; i += ambil;
        if (X->pendN >= X->blockFrames) { nv_at_blok(X); X->pendN = 0; }
    }
    if (X->qN >= nFr) {
        memcpy(x, X->q, sizeof(int16_t) * (size_t)nFr);
        memmove(X->q, X->q + nFr, sizeof(int16_t) * (size_t)(X->qN - nFr));
        X->qN -= nFr;
    } else {
        int pad = nFr - X->qN;
        memset(x, 0, sizeof(int16_t) * (size_t)pad);
        if (X->qN > 0) memcpy(x + pad, X->q, sizeof(int16_t) * (size_t)X->qN);
        X->qN = 0;
    }
    return 1;
}

extern "C" {

__attribute__((visibility("default")))
int nv_jalankan(const char* jobPath) {
    NVJob J;
    char err[256]; err[0] = 0;
    if (!jobPath || !nv_baca_job(jobPath, &J)) {
        if (jobPath) nv_tulis_hasil(jobPath, "ERROR: file tugas tidak bisa dibaca");
        return 1;
    }
    int okJ = (J.mode == 3) ? nv_kontur(&J, err) : (J.mode == 1) ? nv_autotune(&J, err) : (J.mode == 2) ? nv_sonic_pitch(&J, err) : nv_proses(&J, err);
    if (!okJ) {
        char msg[300]; snprintf(msg, sizeof(msg), "ERROR: %s", err);
        nv_tulis_hasil(jobPath, msg);
        return 2;
    }
    nv_tulis_hasil(jobPath, "OK");
    return 0;
}

__attribute__((visibility("default")))
int nv_versi(void) { return NV_VERSI; }

// ---- Jembatan JNI (tanpa jni.h). Kelas Java: FastMuxer (paket bawaan)
__attribute__((visibility("default")))
int Java_FastMuxer_nadiVersi(void* env, void* cls) {
    (void)env; (void)cls;
    return NV_VERSI;
}

__attribute__((visibility("default")))
int Java_FastMuxer_nadiJalankan(void* env, void* cls) {
    (void)env; (void)cls;
    const char* job = getenv("NADI_JOB");
    if (!job || !job[0]) return 3;
    return nv_jalankan(job);
}

// ---- JNI video (versi 4). Semua mengembalikan 1 bila berhasil, 0 bila Java harus mengerjakan sendiri.
// p (17 bilangan bulat): srcW, srcH, srcRot, outW, outH, lalu langkah baris dan piksel
// untuk sumber Y, U, V dan tujuan Y, U, V.
__attribute__((visibility("default")))
int Java_FastMuxer_nvBingkaiYUV(void* env, void* cls, void* sY, void* sU, void* sV, void* dY, void* dU, void* dV, void* parr) {
    (void)cls;
    int32_t q[17];
    if (!nv_jni_baca_int(env, parr, q, 17)) return 0;
    NVPlane a, b, c, d, e, f;
    if (!nv_jni_bidang(env, sY, q[5], q[6], &a) || !nv_jni_bidang(env, sU, q[7], q[8], &b) ||
        !nv_jni_bidang(env, sV, q[9], q[10], &c) || !nv_jni_bidang(env, dY, q[11], q[12], &d) ||
        !nv_jni_bidang(env, dU, q[13], q[14], &e) || !nv_jni_bidang(env, dV, q[15], q[16], &f)) return 0;
    return nv_bingkai_yuv(a, b, c, d, e, f, q[0], q[1], q[2], q[3], q[4]);
}

// s (6 bilangan bulat): langkah baris dan piksel tujuan Y, U, V.
__attribute__((visibility("default")))
int Java_FastMuxer_nvSalinYUV(void* env, void* cls, void* yArr, void* uArr, void* vArr, int outW, int outH,
                              void* dY, void* dU, void* dV, void* sarr) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    int32_t s[6];
    if (!nv_jni_baca_int(env, sarr, s, 6)) return 0;
    NVPlane a, b, c;
    if (!nv_jni_bidang(env, dY, s[0], s[1], &a) || !nv_jni_bidang(env, dU, s[2], s[3], &b) ||
        !nv_jni_bidang(env, dV, s[4], s[5], &c)) return 0;
    if (!yArr || !uArr || !vArr) return 0;
    FLen len = (FLen)nv_jni_fn(env, NV_JNI_GetArrayLength);
    int64_t yl = len(env, yArr), ul = len(env, uArr), vl = len(env, vArr);
    FGet get = (FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical);
    FRel rel = (FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical);
    void* py = get(env, yArr, 0);
    void* pu = get(env, uArr, 0);
    void* pv = get(env, vArr, 0);
    int hasil = 0;
    if (py && pu && pv) hasil = nv_salin_yuv((const uint8_t*)py, yl, (const uint8_t*)pu, ul, (const uint8_t*)pv, vl, outW, outH, a, b, c);
    if (pv) rel(env, vArr, pv, 2);
    if (pu) rel(env, uArr, pu, 2);
    if (py) rel(env, yArr, py, 2);
    return hasil;
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvArgbKeYuv(void* env, void* cls, void* argb, int w, int h, void* yArr, void* uArr, void* vArr) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    if (!argb || !yArr || !uArr || !vArr) return 0;
    FLen len = (FLen)nv_jni_fn(env, NV_JNI_GetArrayLength);
    int64_t al = len(env, argb), yl = len(env, yArr), ul = len(env, uArr), vl = len(env, vArr);
    if (w <= 0 || h <= 0 || al < (int64_t)w * h) return 0;
    FGet get = (FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical);
    FRel rel = (FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical);
    void* pa = get(env, argb, 0);
    void* py = get(env, yArr, 0);
    void* pu = get(env, uArr, 0);
    void* pv = get(env, vArr, 0);
    int hasil = 0;
    if (pa && py && pu && pv) hasil = nv_argb_ke_yuv((const int32_t*)pa, w, h, (uint8_t*)py, yl, (uint8_t*)pu, ul, (uint8_t*)pv, vl);
    if (pv) rel(env, vArr, pv, 0);
    if (pu) rel(env, uArr, pu, 0);
    if (py) rel(env, yArr, py, 0);
    if (pa) rel(env, argb, pa, 2);
    return hasil;
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvCampurPCM(void* env, void* cls, void* aN, void* aI, void* aO, int nF, int ch,
                               int64_t curF, int64_t dInstF, int64_t fInF, int64_t fOutF, int64_t totFrames,
                               float vNar, float vInst) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    if (!aN || !aI || !aO) return 0;
    FLen len = (FLen)nv_jni_fn(env, NV_JNI_GetArrayLength);
    int64_t ln = len(env, aN), li = len(env, aI), lo = len(env, aO);
    FGet get = (FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical);
    FRel rel = (FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical);
    void* pn = get(env, aN, 0);
    void* pi = get(env, aI, 0);
    void* po = get(env, aO, 0);
    int hasil = 0;
    if (pn && pi && po) hasil = nv_campur_pcm((const uint8_t*)pn, (const uint8_t*)pi, (uint8_t*)po, ln, li, lo,
                                              nF, ch, curF, dInstF, fInF, fOutF, totFrames, vNar, vInst);
    if (po) rel(env, aO, po, 0);
    if (pi) rel(env, aI, pi, 2);
    if (pn) rel(env, aN, pn, 2);
    return hasil;
}

__attribute__((visibility("default")))
int64_t Java_FastMuxer_nvRantaiBuat(void* env, void* cls, void* aL, void* aD, int ch, int sr) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    if (!aL || !aD) return 0;
    FLen len = (FLen)nv_jni_fn(env, NV_JNI_GetArrayLength);
    int nL = len(env, aL), nD = len(env, aD);
    FGet get = (FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical);
    FRel rel = (FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical);
    void* pl = get(env, aL, 0);
    void* pd = get(env, aD, 0);
    NVChain* C = 0;
    if (pl && pd) C = nv_rantai_buat((const int64_t*)pl, nL, (const double*)pd, nD, ch, sr);
    if (pd) rel(env, aD, pd, 2);
    if (pl) rel(env, aL, pl, 2);
    return (int64_t)(intptr_t)C;
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvRantaiProses(void* env, void* cls, int64_t h, void* aIn, int read, void* aOut, int64_t base) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    NVChain* C = (NVChain*)(intptr_t)h;
    if (!C || !aIn || !aOut || read < 0) return 0;
    FLen len = (FLen)nv_jni_fn(env, NV_JNI_GetArrayLength);
    if (len(env, aIn) < read || len(env, aOut) < read) return 0;
    FGet get = (FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical);
    FRel rel = (FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical);
    void* pi = get(env, aIn, 0);
    void* po = get(env, aOut, 0);
    int hasil = 0;
    if (pi && po) hasil = nv_rantai_proses(C, (const uint8_t*)pi, read, (uint8_t*)po, base);
    if (po) rel(env, aOut, po, 0);
    if (pi) rel(env, aIn, pi, 2);
    return hasil;
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvRantaiLepas(void* env, void* cls, int64_t h) {
    (void)env; (void)cls;
    nv_rantai_lepas((NVChain*)(intptr_t)h);
    return 1;
}

// ---- Mesin nada langsung (versi 9). Semua lewat larik Java (tanpa jni.h).
__attribute__((visibility("default")))
int64_t Java_FastMuxer_nvLiveBuat(void* env, void* cls, void* aPath, int sr) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    if (!aPath) return 0;
    int len = ((FLen)nv_jni_fn(env, NV_JNI_GetArrayLength))(env, aPath);
    if (len <= 0 || len > 1000) return 0;
    void* p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aPath, 0);
    if (!p) return 0;
    char path[1024];
    memcpy(path, p, (size_t)len);
    path[len] = 0;
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aPath, p, 2);
    return (int64_t)(intptr_t)nv_lv_buat(path, sr);
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvLiveAnalisis(void* env, void* cls, int64_t h) {
    (void)env; (void)cls;
    NVLive* L = (NVLive*)(intptr_t)h;
    if (!L) return 0;
    return nv_lv_analisis(L);
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvLiveProgres(void* env, void* cls, int64_t h) {
    (void)env; (void)cls;
    NVLive* L = (NVLive*)(intptr_t)h;
    return L ? L->prog : 0;
}

__attribute__((visibility("default")))
void Java_FastMuxer_nvLiveBatal(void* env, void* cls, int64_t h) {
    (void)env; (void)cls;
    NVLive* L = (NVLive*)(intptr_t)h;
    if (L) L->batal = 1;
}

// apa: 0 = jumlah sampel, 1 = jarak bingkai kontur, 2 = jumlah bingkai kontur, 3 = jumlah titik penanda
__attribute__((visibility("default")))
int Java_FastMuxer_nvLiveInfo(void* env, void* cls, int64_t h, int apa) {
    (void)env; (void)cls;
    NVLive* L = (NVLive*)(intptr_t)h;
    if (!L) return -1;
    switch (apa) {
        case 0: return L->n;
        case 1: return L->khop;
        case 2: return L->nk;
        case 3: return L->mn;
        default: return -1;
    }
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvLiveKontur(void* env, void* cls, int64_t h, void* aVal, int jumlah) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    NVLive* L = (NVLive*)(intptr_t)h;
    if (!L || !aVal || jumlah <= 0) return 0;
    if (jumlah > L->nk) jumlah = L->nk;
    if (((FLen)nv_jni_fn(env, NV_JNI_GetArrayLength))(env, aVal) < jumlah) return 0;
    void* p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aVal, 0);
    if (!p) return 0;
    memcpy(L->target, p, sizeof(float) * (size_t)jumlah);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aVal, p, 2);
    return 1;
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvLiveMulai(void* env, void* cls, int64_t h, int64_t posSampel) {
    (void)env; (void)cls;
    NVLive* L = (NVLive*)(intptr_t)h;
    if (!L) return 0;
    return nv_lv_mulai(L, posSampel);
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvLiveRender(void* env, void* cls, int64_t h, void* aOut, int nFr, int flags) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    NVLive* L = (NVLive*)(intptr_t)h;
    if (!L || !aOut || nFr <= 0 || nFr > NV_LV_BLOK_MAKS) return -1;
    if (((FLen)nv_jni_fn(env, NV_JNI_GetArrayLength))(env, aOut) < nFr * 2) return -1;
    int16_t tmp[NV_LV_BLOK_MAKS];
    int r = nv_lv_render(L, tmp, nFr, flags);
    if (r <= 0) return r;
    void* p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aOut, 0);
    if (!p) return -2;
    memcpy(p, tmp, (size_t)r * 2);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aOut, p, 0);
    return r;
}

__attribute__((visibility("default")))
int64_t Java_FastMuxer_nvLivePosisi(void* env, void* cls, int64_t h) {
    (void)env; (void)cls;
    NVLive* L = (NVLive*)(intptr_t)h;
    return L ? (int64_t)L->base : -1;
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvLiveLepas(void* env, void* cls, int64_t h) {
    (void)env; (void)cls;
    nv_lv_lepas((NVLive*)(intptr_t)h);
    return 1;
}

// ---- Suara Dua langsung (versi 10). Dipanggil dari satu thread pemutar.
__attribute__((visibility("default")))
int Java_FastMuxer_nvSdAtur(void* env, void* cls, int64_t h, void* aVal, int jumlah) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    NVLive* L = (NVLive*)(intptr_t)h;
    if (!L || !aVal || jumlah <= 0) return 0;
    if (jumlah > NV_SD_NPAR) jumlah = NV_SD_NPAR;
    if (((FLen)nv_jni_fn(env, NV_JNI_GetArrayLength))(env, aVal) < jumlah) return 0;
    void* p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aVal, 0);
    if (!p) return 0;
    float tmp[NV_SD_NPAR];
    memcpy(tmp, p, sizeof(float) * (size_t)jumlah);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aVal, p, 2);
    return nv_sd_atur(L, tmp, jumlah);
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvSdMulai(void* env, void* cls, int64_t h, int64_t posSampel) {
    (void)env; (void)cls;
    NVLive* L = (NVLive*)(intptr_t)h;
    if (!L) return 0;
    return nv_sd_mulai(L, posSampel);
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvSdRender(void* env, void* cls, int64_t h, void* aOut, int nFr, int ch, int flags) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    NVLive* L = (NVLive*)(intptr_t)h;
    if (!L || !aOut || nFr <= 0 || nFr > NV_LV_BLOK_MAKS || ch < 1 || ch > 2) return -1;
    if (((FLen)nv_jni_fn(env, NV_JNI_GetArrayLength))(env, aOut) < nFr * ch * 2) return -1;
    int16_t tmp[NV_LV_BLOK_MAKS * 2];
    int r = nv_sd_render(L, tmp, nFr, ch, flags);
    if (r <= 0) return r;
    void* p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aOut, 0);
    if (!p) return -2;
    memcpy(p, tmp, (size_t)r * (size_t)ch * 2);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aOut, p, 0);
    return r;
}

// ---- Bass & Treble + Ekualiser langsung (versi 11). Dipanggil dari satu thread pemutar.
// nvEqBuat(sr, ch) -> pegangan (0 bila gagal); nvEqAtur(h, p, n) dengan p = bass, treble, pita 1..5 (persen);
// nvEqProses(h, buf, nBingkai) memproses PCM 16-bit sisip di tempat (buf adalah byte[]); nvEqReset(h) mengosongkan
// keadaan filter (dipanggil setelah pindah posisi); nvEqLepas(h) melepas memori.
__attribute__((visibility("default")))
int64_t Java_FastMuxer_nvEqBuat(void* env, void* cls, int sr, int ch) {
    (void)env; (void)cls;
    return (int64_t)(intptr_t)nv_eq_buat(sr, ch);
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvEqAtur(void* env, void* cls, int64_t h, void* aVal, int jumlah) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    NVEq* E = (NVEq*)(intptr_t)h;
    if (!E || !aVal || jumlah < NV_EQ_N) return 0;
    if (((FLen)nv_jni_fn(env, NV_JNI_GetArrayLength))(env, aVal) < NV_EQ_N) return 0;
    void* p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aVal, 0);
    if (!p) return 0;
    float tmp[NV_EQ_N];
    memcpy(tmp, p, sizeof(float) * NV_EQ_N);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aVal, p, 2);
    return nv_eq_atur(E, tmp, NV_EQ_N);
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvEqReset(void* env, void* cls, int64_t h) {
    (void)env; (void)cls;
    NVEq* E = (NVEq*)(intptr_t)h;
    if (!E) return 0;
    nv_eq_reset(E);
    return 1;
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvEqProses(void* env, void* cls, int64_t h, void* aBuf, int nFr) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    NVEq* E = (NVEq*)(intptr_t)h;
    if (!E || !aBuf || nFr <= 0 || nFr > NV_LV_BLOK_MAKS) return -1;
    if (((FLen)nv_jni_fn(env, NV_JNI_GetArrayLength))(env, aBuf) < nFr * E->ch * 2) return -1;
    int16_t tmp[NV_LV_BLOK_MAKS * 2];
    void* p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aBuf, 0);
    if (!p) return -2;
    memcpy(tmp, p, (size_t)nFr * (size_t)E->ch * 2);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aBuf, p, 2);   // 2 = buang (tidak ditulis balik)
    int ok = nv_eq_proses(E, tmp, nFr);
    if (ok != 1) return ok;
    p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aBuf, 0);
    if (!p) return -2;
    memcpy(p, tmp, (size_t)nFr * (size_t)E->ch * 2);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aBuf, p, 0);
    return 1;
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvEqLepas(void* env, void* cls, int64_t h) {
    (void)env; (void)cls;
    free((NVEq*)(intptr_t)h);
    return 1;
}

// ---- Noise gate langsung (versi 12). Dipanggil dari satu thread pemutar.
// nvGateBuat(sr, ch); nvGateAtur(h, p, n) dengan p = sensitivitas %, attack md, release md;
// nvGateProses(h, buf, nBingkai) di tempat pada PCM 16-bit sisip (byte[]); nvGateReset; nvGateLepas.
__attribute__((visibility("default")))
int64_t Java_FastMuxer_nvGateBuat(void* env, void* cls, int sr, int ch) {
    (void)env; (void)cls;
    return (int64_t)(intptr_t)nv_gl_buat(sr, ch);
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvGateAtur(void* env, void* cls, int64_t h, void* aVal, int jumlah) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    NVGateL* G = (NVGateL*)(intptr_t)h;
    if (!G || !aVal || jumlah < 3) return 0;
    if (((FLen)nv_jni_fn(env, NV_JNI_GetArrayLength))(env, aVal) < 3) return 0;
    void* p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aVal, 0);
    if (!p) return 0;
    float tmp[3];
    memcpy(tmp, p, sizeof(float) * 3);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aVal, p, 2);
    return nv_gl_atur(G, tmp, 3);
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvGateReset(void* env, void* cls, int64_t h) {
    (void)env; (void)cls;
    NVGateL* G = (NVGateL*)(intptr_t)h;
    if (!G) return 0;
    nv_gl_reset(G);
    return 1;
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvGateProses(void* env, void* cls, int64_t h, void* aBuf, int nFr) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    NVGateL* G = (NVGateL*)(intptr_t)h;
    if (!G || !aBuf || nFr <= 0 || nFr > NV_LV_BLOK_MAKS) return -1;
    if (((FLen)nv_jni_fn(env, NV_JNI_GetArrayLength))(env, aBuf) < nFr * G->ch * 2) return -1;
    int16_t tmp[NV_LV_BLOK_MAKS * 2];
    void* p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aBuf, 0);
    if (!p) return -2;
    memcpy(tmp, p, (size_t)nFr * (size_t)G->ch * 2);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aBuf, p, 2);
    int ok = nv_gl_proses(G, tmp, nFr);
    if (ok != 1) return ok;
    p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aBuf, 0);
    if (!p) return -2;
    memcpy(p, tmp, (size_t)nFr * (size_t)G->ch * 2);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aBuf, p, 0);
    return 1;
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvGateLepas(void* env, void* cls, int64_t h) {
    (void)env; (void)cls;
    free((NVGateL*)(intptr_t)h);
    return 1;
}

// ---- Reverb dan Echo langsung (versi 13), mono. kind 1 = reverb, 2 = echo.
// nvFxBuat(kind, sr); nvFxAtur(h, p, n) (urutan p di atas); nvFxProses(h, buf, nBingkai) di tempat pada PCM 16-bit mono (byte[]);
// nvFxReset mengosongkan ekor; nvFxLepas melepas memori.
__attribute__((visibility("default")))
int64_t Java_FastMuxer_nvFxBuat(void* env, void* cls, int kind, int sr) {
    (void)env; (void)cls;
    return (int64_t)(intptr_t)nv_fx_buat(kind, sr);
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvFxAtur(void* env, void* cls, int64_t h, void* aVal, int jumlah) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    NVFxL* X = (NVFxL*)(intptr_t)h;
    if (!X || !aVal || jumlah < 4 || jumlah > 8) return 0;
    if (((FLen)nv_jni_fn(env, NV_JNI_GetArrayLength))(env, aVal) < jumlah) return 0;
    void* p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aVal, 0);
    if (!p) return 0;
    float tmp[8];
    memcpy(tmp, p, sizeof(float) * (size_t)jumlah);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aVal, p, 2);
    return nv_fx_atur(X, tmp, jumlah);
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvFxReset(void* env, void* cls, int64_t h) {
    (void)env; (void)cls;
    NVFxL* X = (NVFxL*)(intptr_t)h;
    if (!X) return 0;
    nv_fx_reset(X);
    return 1;
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvFxProses(void* env, void* cls, int64_t h, void* aBuf, int nFr) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    NVFxL* X = (NVFxL*)(intptr_t)h;
    if (!X || !aBuf || nFr <= 0 || nFr > NV_LV_BLOK_MAKS) return -1;
    if (((FLen)nv_jni_fn(env, NV_JNI_GetArrayLength))(env, aBuf) < nFr * 2) return -1;
    int16_t tmp[NV_LV_BLOK_MAKS];
    void* p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aBuf, 0);
    if (!p) return -2;
    memcpy(tmp, p, (size_t)nFr * 2);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aBuf, p, 2);
    int ok = nv_fx_proses(X, tmp, nFr);
    if (ok != 1) return ok;
    p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aBuf, 0);
    if (!p) return -2;
    memcpy(p, tmp, (size_t)nFr * 2);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aBuf, p, 0);
    return 1;
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvFxLepas(void* env, void* cls, int64_t h) {
    (void)env; (void)cls;
    nv_fx_lepas((NVFxL*)(intptr_t)h);
    return 1;
}

// ---- AutoTune langsung (versi 14)
// nvAtBuat(sr); nvAtAtur(h, p, 3) p = {kunci 0..11, tangga nada 0..2, kecepatan 1..100};
// nvAtProses(h, buf, nBingkai) di tempat pada PCM 16-bit mono (byte[]); nvAtReset; nvAtLepas.
__attribute__((visibility("default")))
int64_t Java_FastMuxer_nvAtBuat(void* env, void* cls, int sr) {
    (void)env; (void)cls;
    return (int64_t)(intptr_t)nv_at_buat(sr);
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvAtAtur(void* env, void* cls, int64_t h, void* aVal, int jumlah) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    NVAtL* X = (NVAtL*)(intptr_t)h;
    if (!X || !aVal || jumlah < 3 || jumlah > 8) return 0;
    if (((FLen)nv_jni_fn(env, NV_JNI_GetArrayLength))(env, aVal) < jumlah) return 0;
    void* p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aVal, 0);
    if (!p) return 0;
    float tmp[8];
    memcpy(tmp, p, sizeof(float) * (size_t)jumlah);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aVal, p, 2);
    return nv_at_atur(X, tmp, jumlah);
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvAtReset(void* env, void* cls, int64_t h) {
    (void)env; (void)cls;
    NVAtL* X = (NVAtL*)(intptr_t)h;
    if (!X) return 0;
    nv_at_kosongkan(X);
    return 1;
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvAtProses(void* env, void* cls, int64_t h, void* aBuf, int nFr) {
    (void)cls;
    typedef int32_t (*FLen)(void*, void*);
    typedef void* (*FGet)(void*, void*, unsigned char*);
    typedef void (*FRel)(void*, void*, void*, int32_t);
    NVAtL* X = (NVAtL*)(intptr_t)h;
    if (!X || !aBuf || nFr <= 0 || nFr > NV_LV_BLOK_MAKS) return -1;
    if (((FLen)nv_jni_fn(env, NV_JNI_GetArrayLength))(env, aBuf) < nFr * 2) return -1;
    int16_t tmp[NV_LV_BLOK_MAKS];
    void* p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aBuf, 0);
    if (!p) return -2;
    memcpy(tmp, p, (size_t)nFr * 2);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aBuf, p, 2);
    int ok = nv_at_proses(X, tmp, nFr);
    if (ok != 1) return ok;
    p = ((FGet)nv_jni_fn(env, NV_JNI_GetPrimitiveArrayCritical))(env, aBuf, 0);
    if (!p) return -2;
    memcpy(p, tmp, (size_t)nFr * 2);
    ((FRel)nv_jni_fn(env, NV_JNI_ReleasePrimitiveArrayCritical))(env, aBuf, p, 0);
    return 1;
}

__attribute__((visibility("default")))
int Java_FastMuxer_nvAtLepas(void* env, void* cls, int64_t h) {
    (void)env; (void)cls;
    nv_at_lepas((NVAtL*)(intptr_t)h);
    return 1;
}

} // extern "C"

// ============================================================================
//  Uji mandiri (hanya dikompilasi bila -DNV_SELFTEST): dipakai skrip Termux
//  untuk memastikan hasil kompilasi benar-benar berjalan di HP.
// ============================================================================
#ifdef NV_SELFTEST
static double nv_periode(const float* x, int n, int lo, int hi) {
    double best = -1e30; int bk = lo;
    for (int k = lo; k <= hi; k++) {
        double c = 0.0, e1 = 1e-12, e2 = 1e-12;
        for (int i = 0; i + k < n; i += 2) { c += (double)x[i] * x[i + k]; e1 += (double)x[i] * x[i]; e2 += (double)x[i + k] * x[i + k]; }
        double r = c / sqrt(e1 * e2);
        if (r > best) { best = r; bk = k; }
    }
    return (double)bk;
}

static int nv_uji_campur() {
    uint8_t n[8], i2[8], o[8];
    int16_t a[4] = {1000, -1000, 30000, -30000}, b[4] = {2000, 2000, 30000, -30000};
    memcpy(n, a, 8); memcpy(i2, b, 8);
    if (nv_campur_pcm(n, i2, o, 8, 8, 8, 2, 2, 0, 0, 0, 0, 1000, 0.5f, 1.0f) != 1) return 1;
    int16_t r[4]; memcpy(r, o, 8);
    if (r[0] != 2500 || r[1] != 1500 || r[2] != 32767 || r[3] != -32768) return 2;
    // fade-in separuh jalan: frame 1 dari 4 -> env 0.25
    if (nv_campur_pcm(n, i2, o, 8, 8, 8, 2, 2, 0, 0, 4, 0, 1000, 0.0f, 1.0f) != 1) return 3;
    memcpy(r, o, 8);
    if (r[0] != 0 || r[1] != 0 || r[2] != 7500 || r[3] != -7500) return 4;
    return 0;
}

static int nv_uji_rantai() {
    int64_t L[6] = {0, 2000, 4, 0, 0, 1000};
    double D[5] = {3, 0, 0, 1, 1};
    NVChain* C = nv_rantai_buat(L, 6, D, 5, 1, 44100);
    if (!C) return 1;
    uint8_t in[16], out[16]; memset(in, 0, 16);
    int16_t x[8] = {1000, 0, 0, 0, 0, 0, 0, 0}; memcpy(in, x, 16);
    if (nv_rantai_proses(C, in, 16, out, 0) != 1) return 2;
    int16_t r[8]; memcpy(r, out, 16);
    if (r[0] != 1000 || r[1] != 0 || r[2] != 0 || r[3] != 1000 || r[6] != 0) return 3;
    nv_rantai_lepas(C);
    int64_t L2[6] = {0, 2000, 8, 0, 0, 1000};
    double D2[17] = {10, 11, 12, 13, 14, 15, 16, 17, 5, 6, 7, 8, 0.84, 0.2, 0.8, 0.5, 0.7};
    C = nv_rantai_buat(L2, 6, D2, 17, 1, 44100);
    if (!C) return 4;
    if (nv_rantai_proses(C, in, 16, out, 0) != 1) return 5;
    memcpy(r, out, 16);
    if (r[0] != 700) return 6;
    nv_rantai_lepas(C);
    return 0;
}

// Uji video: putar, salin, dan ubah warna bingkai kecil lalu periksa hasilnya.
static int nv_uji_video() {
    const int W = 8, H = 6;
    uint8_t sy[W * H], su[(W / 2) * (H / 2)], sv[(W / 2) * (H / 2)];
    uint8_t dy[W * H], du[(W / 2) * (H / 2)], dv[(W / 2) * (H / 2)];
    for (int i = 0; i < W * H; i++) sy[i] = (uint8_t)(i * 3 + 7);
    for (int i = 0; i < (W / 2) * (H / 2); i++) { su[i] = (uint8_t)(i + 100); sv[i] = (uint8_t)(200 - i); }
    NVPlane a = {sy, W * H, W, 1}, b = {su, (W / 2) * (H / 2), W / 2, 1}, c = {sv, (W / 2) * (H / 2), W / 2, 1};
    NVPlane d = {dy, W * H, W, 1}, e = {du, (W / 2) * (H / 2), W / 2, 1}, f = {dv, (W / 2) * (H / 2), W / 2, 1};
    memset(dy, 0, sizeof(dy)); memset(du, 0, sizeof(du)); memset(dv, 0, sizeof(dv));
    if (nv_bingkai_yuv(a, b, c, d, e, f, W, H, 0, W, H) != 1) return 1;
    if (memcmp(sy, dy, sizeof(sy)) || memcmp(su, du, sizeof(su)) || memcmp(sv, dv, sizeof(sv))) return 2;
    memset(dy, 0, sizeof(dy)); memset(du, 0, sizeof(du)); memset(dv, 0, sizeof(dv));
    if (nv_bingkai_yuv(a, b, c, d, e, f, W, H, 180, W, H) != 1) return 3;
    for (int i = 0; i < W * H; i++) if (dy[i] != sy[W * H - 1 - i]) return 4;
    memset(dy, 0, sizeof(dy)); memset(du, 0, sizeof(du)); memset(dv, 0, sizeof(dv));
    NVPlane d2 = {dy, W * H, H, 1};
    if (nv_bingkai_yuv(a, b, c, d2, e, f, W, H, 90, H, W) != 1) return 5;
    // putar 90: titik hasil (x, y) berasal dari sumber (sx, sy) = (y, H - 1 - x)
    for (int y = 0; y < W; y++) for (int x = 0; x < H; x++) {
        if (dy[y * H + x] != sy[(H - 1 - x) * W + y]) return 6;
    }
    int32_t px[4] = {(int32_t)0xFFFFFFFF, (int32_t)0xFF000000, (int32_t)0xFFFF0000, (int32_t)0xFF0000FF};
    uint8_t yy[4], uu[1], vv[1];
    if (nv_argb_ke_yuv(px, 2, 2, yy, 4, uu, 1, vv, 1) != 1) return 7;
    if (yy[0] != 235 || yy[1] != 16) return 8;
    if (uu[0] != 128 || vv[0] != 128) return 9;
    return 0;
}

static int nv_uji_sonic(const char* dir, const float* x, int n, int sr) {
    char pin[600], pout[600], pjob[600];
    snprintf(pin, sizeof(pin), "%s/nv_uji_s_in.raw", dir);
    snprintf(pout, sizeof(pout), "%s/nv_uji_s_out.raw", dir);
    snprintf(pjob, sizeof(pjob), "%s/nv_uji_s_job.txt", dir);
    FILE* f = fopen(pin, "wb");
    if (!f) return 1;
    for (int i = 0; i < n; i++) { int16_t s = (int16_t)lrintf(x[i] * 32767.0f); fwrite(&s, 2, 1, f); }
    fclose(f);
    int rc = 0;
    for (int m = 2; m >= 1 && !rc; m--) {
        f = fopen(pjob, "w");
        if (m == 2) fprintf(f, "in=%s\nout=%s\nsr=%d\nch=1\nmode=2\nouthdr=0\npratio=%.9g\n", pin, pout, sr, pow(2.0, 4.0 / 12.0));
        else fprintf(f, "in=%s\nout=%s\nsr=%d\nch=1\nmode=1\nouthdr=0\natkey=0\natscale=0\natspeed=80\n", pin, pout, sr);
        fclose(f);
        if (nv_jalankan(pjob) != 0) { rc = 2; break; }
        f = fopen(pout, "rb");
        if (!f) { rc = 3; break; }
        float* o = (float*)calloc(n, sizeof(float));
        int cnt = 0;
        for (; cnt < n; cnt++) { int16_t s; if (fread(&s, 2, 1, f) != 1) break; o[cnt] = (float)s / 32768.0f; }
        fclose(f);
        if (cnt < n / 2) rc = 4;
        else if (m == 2) {
            double Tin = nv_periode(x + sr / 2, sr, 150, 600), Tout = nv_periode(o + sr / 2, sr, 150, 600);
            double ratio = Tin / Tout, target = pow(2.0, 4.0 / 12.0);
            printf("Sonic: rasio nada %.3f (target %.3f)\n", ratio, target);
            if (fabs(ratio - target) / target > 0.06) rc = 5;
        }
        free(o);
    }
    remove(pin); remove(pout); remove(pjob);
    char pres[700]; snprintf(pres, sizeof(pres), "%s.res", pjob); remove(pres);
    return rc;
}

static int nv_uji_live(const char* dir, const float* x, int n, int sr) {
    char pin[600];
    snprintf(pin, sizeof(pin), "%s/nv_uji_live.raw", dir);
    FILE* f = fopen(pin, "wb");
    if (!f) return 1;
    for (int i = 0; i < n; i++) { int16_t s = (int16_t)lrintf(x[i] * 32767.0f); fwrite(&s, 2, 1, f); }
    fclose(f);
    NVLive* L = nv_lv_buat(pin, sr);
    int rc = 0;
    int16_t* o = (int16_t*)malloc((size_t)n * 2);
    float* of = (float*)malloc(sizeof(float) * (size_t)n);
    if (!L || !o || !of) rc = 2;
    if (!rc && !nv_lv_analisis(L)) rc = 3;
    if (!rc) {
        nv_lv_mulai(L, 0);
        int done = 0;
        while (done < n) { int N = 512; if (n - done < N) N = n - done; nv_lv_render(L, o + done, N, 0); done += N; }
        double maxd = 0;
        for (int i = 4000; i < n - 4000; i++) { double d = fabs((double)o[i] / 32768.0 - (double)x[i]); if (d > maxd) maxd = d; }
        printf("Live: tanpa geser, selisih maks %.5f\n", maxd);
        if (maxd > 0.01) rc = 4;
    }
    if (!rc) {
        for (int i = 0; i < L->nk; i++) L->target[i] = 0.0f;
        nv_lv_mulai(L, 0);
        int done = 0, blk = 0;
        while (done < n) {
            if (blk == 40) for (int i = 0; i < L->nk; i++) L->target[i] = 4.0f;
            int N = 512; if (n - done < N) N = n - done;
            nv_lv_render(L, o + done, N, 0); done += N; blk++;
        }
        for (int i = 0; i < n; i++) of[i] = (float)o[i] / 32768.0f;
        double Tin = nv_periode(x + sr, sr, 150, 600), Tout = nv_periode(of + sr, sr, 150, 600);
        double ratio = Tin / Tout, target = pow(2.0, 4.0 / 12.0);
        double mj = 0, mj0 = 0;
        for (int i = 1; i < n; i++) {
            double d = fabs((double)of[i] - (double)of[i - 1]); if (d > mj) mj = d;
            double d0 = fabs((double)x[i] - (double)x[i - 1]); if (d0 > mj0) mj0 = d0;
        }
        printf("Live: geser langsung, rasio nada %.3f (target %.3f), lonjakan %.4f (asli %.4f)\n", ratio, target, mj, mj0);
        if (fabs(ratio - target) / target > 0.04) rc = 5;
        else if (mj > mj0 * 1.6 + 0.05) rc = 6;
    }
    nv_lv_lepas(L); free(o); free(of);
    remove(pin);
    return rc;
}


static double nv_sd_korelasi(const float* a, const float* b, int n, int lag) {
    double c = 0.0, ea = 1e-12, eb = 1e-12;
    for (int i = 4000; i < n - 4000 - 3000; i++) {
        double u = a[i + lag], v = b[i];
        c += u * v; ea += u * u; eb += v * v;
    }
    return c / sqrt(ea * eb);
}

static int nv_uji_sd(const char* dir, const float* x, int n, int sr) {
    char pin[600];
    snprintf(pin, sizeof(pin), "%s/nv_uji_sd.raw", dir);
    FILE* f = fopen(pin, "wb");
    if (!f) return 1;
    for (int i = 0; i < n; i++) { int16_t s = (int16_t)lrintf(x[i] * 32767.0f); fwrite(&s, 2, 1, f); }
    fclose(f);
    NVLive* L = nv_lv_buat(pin, sr);
    int rc = 0;
    int16_t* o = (int16_t*)malloc((size_t)n * 4);
    float* of = (float*)malloc(sizeof(float) * (size_t)n);
    float* orr = (float*)malloc(sizeof(float) * (size_t)n);
    if (!L || !o || !of || !orr) rc = 2;
    if (!rc && !nv_lv_analisis(L)) rc = 3;
    float p[NV_SD_NPAR];
    #define SD_RENDER_MONO(BLOKGANTI) { nv_sd_mulai(L, 0); int done = 0, blk = 0; \
        while (done < n) { BLOKGANTI; int N = 512; if (n - done < N) N = n - done; nv_sd_render(L, o + done, N, 1, 0); done += N; blk++; } \
        for (int i = 0; i < n; i++) of[i] = (float)o[i] / 32768.0f; }
    // 1) suara dua +4 semiton, suara asli mati: nada harus naik tepat 4 semiton, lalu berubah ke 0 di tengah
    if (!rc) {
        memset(p, 0, sizeof(p)); p[0] = 0.0f; p[3] = 0.6f;
        p[4] = 1; p[5] = 4.0f; p[6] = 1.0f; p[7] = 0.0f; p[8] = 0.0f;
        nv_sd_atur(L, p, NV_SD_NPAR);
        SD_RENDER_MONO((void)0);
        double Tin = nv_periode(x + sr, sr, 150, 600), Tout = nv_periode(of + sr, sr, 150, 600);
        double ratio = Tin / Tout, target = pow(2.0, 4.0 / 12.0);
        printf("SD: +4 semiton, rasio nada %.3f (target %.3f)\n", ratio, target);
        if (fabs(ratio - target) / target > 0.04) rc = 4;
    }
    // 2) ubah semiton saat diputar: bagian akhir harus menjadi +7, tanpa lonjakan besar
    if (!rc) {
        memset(p, 0, sizeof(p)); p[3] = 0.6f;
        p[4] = 1; p[5] = 4.0f; p[6] = 1.0f;
        nv_sd_atur(L, p, NV_SD_NPAR);
        nv_sd_mulai(L, 0);
        int done = 0, blk = 0;
        while (done < n) {
            if (blk == 150) { p[5] = 7.0f; nv_sd_atur(L, p, NV_SD_NPAR); }
            int N = 512; if (n - done < N) N = n - done;
            nv_sd_render(L, o + done, N, 1, 0); done += N; blk++;
        }
        for (int i = 0; i < n; i++) of[i] = (float)o[i] / 32768.0f;
        double Tin = nv_periode(x + 2 * sr + sr / 2, sr / 4, 150, 600), Tout = nv_periode(of + 2 * sr + sr / 2, sr / 4, 150, 600);
        double ratio = Tin / Tout, target = pow(2.0, 7.0 / 12.0);
        double mj = 0, mj0 = 0;
        for (int i = 1; i < n; i++) {
            double d = fabs((double)of[i] - (double)of[i - 1]); if (d > mj) mj = d;
            double d0 = fabs((double)x[i] - (double)x[i - 1]); if (d0 > mj0) mj0 = d0;
        }
        printf("SD: ubah langsung ke +7, rasio nada %.3f (target %.3f), lonjakan %.4f (asli %.4f)\n", ratio, target, mj, mj0);
        if (fabs(ratio - target) / target > 0.05) rc = 5;
        else if (mj > mj0 * 1.6 + 0.05) rc = 6;
    }
    // 3) hanya suara asli: harus sama dengan masukan
    if (!rc) {
        memset(p, 0, sizeof(p)); p[0] = 1.0f; p[3] = 0.6f;
        nv_sd_atur(L, p, NV_SD_NPAR);
        SD_RENDER_MONO((void)0);
        double maxd = 0;
        for (int i = 4000; i < n - 4000; i++) { double d = fabs((double)of[i] - (double)x[i]); if (d > maxd) maxd = d; }
        printf("SD: hanya suara asli, selisih maks %.5f\n", maxd);
        if (maxd > 0.001) rc = 7;
    }
    // 4) penundaan 50 md pada nada yang sama: awal suara harus mundur sekitar 2205 sampel (+/- satu periode)
    if (!rc) {
        int awal[2] = {0, 0};
        float tunda[2] = {0.0f, 50.0f};
        for (int u = 0; u < 2 && !rc; u++) {
            memset(p, 0, sizeof(p)); p[0] = 0.0f; p[3] = 0.6f;
            p[4] = 1; p[5] = 0.0f; p[6] = 1.0f; p[7] = 0.0f; p[8] = tunda[u];
            nv_sd_atur(L, p, NV_SD_NPAR);
            SD_RENDER_MONO((void)0);
            int k = 0; while (k < n && fabsf(of[k]) < 0.05f) k++;
            awal[u] = k;
        }
        int selisih = awal[1] - awal[0], target = (int)(0.050 * sr + 0.5);
        printf("SD: penundaan 50 md, awal suara %d lalu %d, selisih %d sampel (target %d)\n", awal[0], awal[1], selisih, target);
        if (abs(selisih - target) > 450) rc = 8;
    }
    // 5) geser formant +3 tidak boleh mengubah nada
    if (!rc) {
        memset(p, 0, sizeof(p)); p[0] = 0.0f; p[1] = 3.0f; p[3] = 0.6f;
        p[4] = 1; p[5] = 0.0f; p[6] = 1.0f;
        nv_sd_atur(L, p, NV_SD_NPAR);
        SD_RENDER_MONO((void)0);
        double Tin = nv_periode(x + sr, sr, 150, 600), Tout = nv_periode(of + sr, sr, 150, 600);
        printf("SD: geser formant +3, periode %.1f (asli %.1f)\n", Tout, Tin);
        if (fabs(Tin - Tout) / Tin > 0.03) rc = 9;
    }
    // 6) stereo dengan pan penuh ke kiri: kanan harus senyap; suara ketiga hidup-mati saat diputar
    if (!rc) {
        memset(p, 0, sizeof(p)); p[0] = 0.0f; p[3] = 0.6f;
        p[4] = 1; p[5] = 4.0f; p[6] = 1.0f; p[7] = -1.0f;
        nv_sd_atur(L, p, NV_SD_NPAR);
        int16_t* st = (int16_t*)malloc((size_t)n * 4);
        nv_sd_mulai(L, 0);
        int done = 0, blk = 0; double eL = 0, eR = 0, e3 = 0;
        while (done < n) {
            if (blk == 100) { p[9] = 1; p[10] = -5.0f; p[11] = 1.0f; p[12] = 1.0f; nv_sd_atur(L, p, NV_SD_NPAR); }
            int N = 512; if (n - done < N) N = n - done;
            nv_sd_render(L, st + (size_t)done * 2, N, 2, 0); done += N; blk++;
        }
        for (int i = 4000; i < n - 4000; i++) { double l = st[2 * i] / 32768.0, r = st[2 * i + 1] / 32768.0; eL += l * l; eR += r * r; if (i > 100 * 512) e3 += r * r; }
        printf("SD: pan kiri, energi kiri %.2f kanan %.2f; suara ketiga (kanan) setelah dihidupkan %.2f\n", eL, eR, e3);
        free(st);
        if (eL < 1.0) rc = 10;
        else if (e3 < 1.0) rc = 11;
    }
    nv_lv_lepas(L); free(o); free(of); free(orr);
    remove(pin);
    return rc;
}

// Uji Bass & Treble + Ekualiser langsung: penguatan rak, netral = tidak berubah, peralihan mulus, stereo.
static double nv_eq_puncak(const int16_t* x, int n, int ch, int c, int dari) {
    double m = 0.0;
    for (int i = dari; i < n; i++) { double v = fabs((double)x[(size_t)i * ch + c]); if (v > m) m = v; }
    return m;
}

static int nv_uji_eq() {
    const int sr = 44100, blk = 512, n = (sr / blk) * blk;   // n = kelipatan blok, supaya seluruhnya diproses
    int16_t* a = (int16_t*)calloc((size_t)n * 2, sizeof(int16_t));
    int16_t* b = (int16_t*)calloc((size_t)n * 2, sizeof(int16_t));
    if (!a || !b) return 1;
    float p[NV_EQ_N];
    int rc = 0;
    // 1) netral: keluaran persis sama dengan masukan
    for (int i = 0; i < n; i++) a[i] = (int16_t)lrint(8000.0 * sin(2.0 * NV_PI * 440.0 * i / sr));
    memcpy(b, a, (size_t)n * 2);
    NVEq* E = nv_eq_buat(sr, 1);
    if (!E) { free(a); free(b); return 2; }
    for (int i = 0; i < NV_EQ_N; i++) p[i] = 50.0f;
    nv_eq_atur(E, p, NV_EQ_N);
    for (int o = 0; o + blk <= n; o += blk) nv_eq_proses(E, b + o, blk);
    if (memcmp(a, b, (size_t)n * 2) != 0) rc = 3;
    nv_eq_reset(E);
    free(E);
    if (rc) { free(a); free(b); return rc; }
    // 2) Bass 100% (+15 dB rak rendah) pada 30 Hz: sekitar x5.6 ; Treble 0% (-15 dB) pada 15 kHz: sekitar x0.18
    for (int k = 0; k < 2 && !rc; k++) {
        double f = (k == 0) ? 30.0 : 15000.0;
        for (int i = 0; i < n; i++) a[i] = (int16_t)lrint(2000.0 * sin(2.0 * NV_PI * f * i / sr));
        memcpy(b, a, (size_t)n * 2);
        E = nv_eq_buat(sr, 1);
        for (int i = 0; i < NV_EQ_N; i++) p[i] = 50.0f;
        if (k == 0) p[0] = 100.0f; else p[1] = 0.0f;
        nv_eq_atur(E, p, NV_EQ_N);
        for (int o = 0; o + blk <= n; o += blk) nv_eq_proses(E, b + o, blk);
        double r = nv_eq_puncak(b, n, 1, 0, sr / 2) / nv_eq_puncak(a, n, 1, 0, sr / 2);
        printf("EQ: %s hasil %.3f kali\n", k == 0 ? "bass 100% pada 30 Hz" : "treble 0% pada 15 kHz", r);
        if (k == 0 && (r < 4.8 || r > 6.0)) rc = 4;
        if (k == 1 && (r < 0.14 || r > 0.23)) rc = 5;
        free(E);
    }
    // 3) peralihan mulus: dari netral ke bass 100% di tengah jalan; tidak ada lompatan besar antar sampel
    if (!rc) {
        for (int i = 0; i < n; i++) a[i] = (int16_t)lrint(3000.0 * sin(2.0 * NV_PI * 80.0 * i / sr));
        memcpy(b, a, (size_t)n * 2);
        E = nv_eq_buat(sr, 1);
        for (int i = 0; i < NV_EQ_N; i++) p[i] = 50.0f;
        nv_eq_atur(E, p, NV_EQ_N);
        double lompat = 0.0, awal = 0.0, akhir = 0.0;
        for (int o = 0, bi = 0; o + blk <= n; o += blk, bi++) {
            if (bi == 20) { p[0] = 100.0f; p[4] = 100.0f; nv_eq_atur(E, p, NV_EQ_N); }
            nv_eq_proses(E, b + o, blk);
        }
        for (int i = 1; i < n; i++) {
            double d = fabs((double)b[i] - (double)b[i - 1]);
            if (d > lompat) lompat = d;
        }
        awal = nv_eq_puncak(b, 20 * blk, 1, 0, 0);
        akhir = nv_eq_puncak(b, n, 1, 0, n - 4000);
        printf("EQ: peralihan mulus, puncak awal %.0f akhir %.0f, lompatan terbesar %.0f\n", awal, akhir, lompat);
        if (fabs(awal - 3000.0) > 40.0) rc = 6;
        else if (akhir < 3000.0 * 3.0) rc = 7;
        else if (lompat > 3000.0 * 2.0 * NV_PI * 80.0 / sr * 6.0 * 5.6 + 50.0) rc = 8;
        free(E);
    }
    // 4) stereo: dua kanal diproses sendiri-sendiri; kanal kiri diberi sinyal, kanal kanan hening
    if (!rc) {
        int16_t* st = (int16_t*)calloc((size_t)n * 2, sizeof(int16_t));
        for (int i = 0; i < n; i++) st[2 * i] = (int16_t)lrint(2000.0 * sin(2.0 * NV_PI * 1000.0 * i / sr));
        E = nv_eq_buat(sr, 2);
        for (int i = 0; i < NV_EQ_N; i++) p[i] = 50.0f;
        p[4] = 100.0f; // pita 1 kHz +12 dB
        nv_eq_atur(E, p, NV_EQ_N);
        for (int o = 0; o + blk <= n; o += blk) nv_eq_proses(E, st + (size_t)o * 2, blk);
        double kiri = nv_eq_puncak(st, n, 2, 0, sr / 2), kanan = nv_eq_puncak(st, n, 2, 1, 0);
        printf("EQ: stereo, kiri %.0f (diharapkan sekitar 8000), kanan %.0f\n", kiri, kanan);
        if (kiri < 7000.0 || kiri > 9000.0) rc = 9;
        else if (kanan != 0.0) rc = 10;
        free(E); free(st);
    }
    // 5) parameter tidak masuk akal tidak membuat galat
    if (!rc) {
        E = nv_eq_buat(sr, 1);
        float q[NV_EQ_N] = {-5.0f, 1e9f, 50.0f, 50.0f, 50.0f, 50.0f, 50.0f};
        if (nv_eq_atur(E, q, NV_EQ_N) != 1) rc = 11;
        free(E);
        if (nv_eq_buat(100, 1) || nv_eq_buat(44100, 3)) rc = 12;
    }
    free(a); free(b);
    return rc;
}

// Uji noise gate langsung: sinyal kecil ditutup, sinyal besar lolos, ambang bisa diubah, sensitivitas 0 = mati.
static int nv_uji_gate() {
    const int sr = 44100, blk = 512, n = (sr / blk) * blk;
    int16_t* a = (int16_t*)calloc((size_t)n, 2);
    int16_t* b = (int16_t*)calloc((size_t)n, 2);
    int rc = 0;
    float p[3] = {20.0f, 5.0f, 100.0f};    // ambang 20% = 1638
    NVGateL* G = nv_gl_buat(sr, 1);
    if (!G) return 1;
    nv_gl_atur(G, p, 3);
    for (int i = 0; i < n; i++) a[i] = (int16_t)lrint(300.0 * sin(2.0 * NV_PI * 300.0 * i / sr));     // derau kecil
    memcpy(b, a, (size_t)n * 2);
    for (int o = 0; o + blk <= n; o += blk) nv_gl_proses(G, b + o, blk);
    double pk = 0; for (int i = n / 2; i < n; i++) if (fabs((double)b[i]) > pk) pk = fabs((double)b[i]);
    printf("Gate: derau 300 ditutup, puncak %.0f\n", pk);
    if (pk > 3.0) rc = 2;
    if (!rc) {                                   // sinyal 6000 melewati gerbang
        for (int i = 0; i < n; i++) a[i] = (int16_t)lrint(6000.0 * sin(2.0 * NV_PI * 300.0 * i / sr));
        memcpy(b, a, (size_t)n * 2);
        for (int o = 0; o + blk <= n; o += blk) nv_gl_proses(G, b + o, blk);
        pk = 0; for (int i = n / 2; i < n; i++) if (fabs((double)b[i]) > pk) pk = fabs((double)b[i]);
        printf("Gate: sinyal 6000 lolos, puncak %.0f\n", pk);
        if (pk < 5900.0) rc = 3;
    }
    if (!rc) {                                   // ambang diubah di tengah jalan menjadi 0 (mati): derau lolos lagi
        float q[3] = {0.0f, 5.0f, 100.0f};
        nv_gl_atur(G, q, 3);
        nv_gl_reset(G);
        for (int i = 0; i < n; i++) a[i] = (int16_t)lrint(300.0 * sin(2.0 * NV_PI * 300.0 * i / sr));
        memcpy(b, a, (size_t)n * 2);
        for (int o = 0; o + blk <= n; o += blk) nv_gl_proses(G, b + o, blk);
        if (memcmp(a, b, (size_t)n * 2) != 0) rc = 4;
    }
    if (!rc) {                                   // kecocokan dengan nv_gate_p (jalur simpan) pada sinyal campuran
        NVGate ref; ref.th = (20.0f / 100.0f) * 8192.0f;
        ref.att = (float)exp(-1000.0 / (double)((float)sr * 5.0f)); ref.rel = (float)exp(-1000.0 / (double)((float)sr * 100.0f));
        ref.env = 0; ref.gain = 1;
        nv_gl_atur(G, p, 3); nv_gl_reset(G);
        for (int i = 0; i < n; i++) { double amp = ((i / 8000) % 2) ? 5000.0 : 400.0; a[i] = (int16_t)lrint(amp * sin(2.0 * NV_PI * 200.0 * i / sr)); }
        memcpy(b, a, (size_t)n * 2);
        for (int o = 0; o + blk <= n; o += blk) nv_gl_proses(G, b + o, blk);
        for (int i = 0; i < n; i++) if (nv_gate_p(&ref, a[i]) != b[i]) { rc = 5; break; }
    }
    free(G); free(a); free(b);
    return rc;
}

// Uji reverb dan echo langsung: kecocokan dengan jalur simpan (nv_fv_p / nv_echo_p), ekor, dan perubahan di tengah jalan.
static int nv_uji_fx() {
    const int sr = 44100, blk = 512, n = (sr / blk) * blk;
    int16_t* a = (int16_t*)calloc((size_t)n, 2);
    int16_t* b = (int16_t*)calloc((size_t)n, 2);
    int rc = 0;
    for (int i = 0; i < n; i++) a[i] = (i < 4000) ? (int16_t)lrint(7000.0 * sin(2.0 * NV_PI * 300.0 * i / sr)) : 0;
    // 1) echo 300 md, ekor 30%, peredam 50%, asli 100%, pantulan 30%: sama dengan nv_echo_p
    {
        NVFxL* X = nv_fx_buat(2, sr);
        if (!X) return 1;
        float p[5] = {300.0f, 0.3f, 0.5f, 1.0f, 0.3f};
        nv_fx_atur(X, p, 5);
        memcpy(b, a, (size_t)n * 2);
        for (int o = 0; o + blk <= n; o += blk) nv_fx_proses(X, b + o, blk);
        NVEcho E; memset(&E, 0, sizeof E);
        E.delay = (int)((300.0f / 1000.0f) * (float)sr); E.fb = 0.3f; E.damp = 0.5f; E.dry = 1.0f; E.wet = 0.3f;
        E.buf = (float*)calloc((size_t)E.delay, sizeof(float));
        for (int i = 0; i < n; i++) if (nv_echo_p(&E, a[i]) != b[i]) { rc = 2; break; }
        free(E.buf);
        // gema harus muncul 300 md setelah suara: energi di sekitar sampel 13230..17230
        double e = 0; for (int i = 13230 + 100; i < 13230 + 3800; i++) e += fabs((double)b[i]);
        printf("Echo: energi pantulan pertama %.0f\n", e);
        if (!rc && e < 1000.0) rc = 3;
        nv_fx_lepas(X);
    }
    // 2) reverb: ruangan 50%, peredam 50%, asli 70%, gema 30%: sama dengan nv_fv_p, dan ada ekor setelah suara berhenti
    if (!rc) {
        NVFxL* X = nv_fx_buat(1, sr);
        float p[4] = {0.5f, 0.5f, 0.7f, 0.3f};
        nv_fx_atur(X, p, 4);
        memcpy(b, a, (size_t)n * 2);
        for (int o = 0; o + blk <= n; o += blk) nv_fx_proses(X, b + o, blk);
        NVFv F; memset(&F, 0, sizeof F);
        float scale = (float)sr / 44100.0f;
        const int cs[8] = {1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617}, as[4] = {556, 441, 341, 225};
        for (int i = 0; i < 8; i++) { F.c[i].size = (int)((float)cs[i] * scale); F.c[i].buf = (float*)calloc((size_t)F.c[i].size, sizeof(float)); F.c[i].fb = 0.5f * 0.28f + 0.7f; F.c[i].d1 = 0.5f * 0.4f; F.c[i].d2 = 1.0f - 0.5f * 0.4f; }
        for (int i = 0; i < 4; i++) { F.a[i].size = (int)((float)as[i] * scale); F.a[i].buf = (float*)calloc((size_t)F.a[i].size, sizeof(float)); }
        F.dry = 0.7f; F.wet = 0.3f * 3.0f;
        for (int i = 0; i < n; i++) if (nv_fv_p(&F, a[i]) != b[i]) { rc = 4; break; }
        for (int i = 0; i < 8; i++) free(F.c[i].buf);
        for (int i = 0; i < 4; i++) free(F.a[i].buf);
        double e = 0; for (int i = 8000; i < 12000; i++) e += fabs((double)b[i]);
        printf("Reverb: energi ekor setelah suara berhenti %.0f\n", e);
        if (!rc && e < 1000.0) rc = 5;
        // 3) ubah di tengah jalan: gema 0 => ekor baru tidak ditambah; reset => hening
        float q[4] = {0.5f, 0.5f, 1.0f, 0.0f};
        nv_fx_atur(X, q, 4);
        nv_fx_reset(X);
        memset(b, 0, (size_t)blk * 2);
        nv_fx_proses(X, b, blk);
        for (int i = 0; i < blk; i++) if (b[i] != 0) { rc = 6; break; }
        nv_fx_lepas(X);
    }
    // 4) echo: jarak diubah di tengah jalan tidak membuat galat atau nilai liar
    if (!rc) {
        NVFxL* X = nv_fx_buat(2, sr);
        float p[5] = {500.0f, 0.5f, 0.2f, 1.0f, 0.5f};
        nv_fx_atur(X, p, 5);
        memcpy(b, a, (size_t)n * 2);
        for (int o = 0, bi = 0; o + blk <= n; o += blk, bi++) {
            if (bi == 30) { p[0] = 100.0f; nv_fx_atur(X, p, 5); }
            if (bi == 60) { p[0] = 1000.0f; nv_fx_atur(X, p, 5); }
            nv_fx_proses(X, b + o, blk);
        }
        float q[5] = {-3.0f, 9.0f, NAN, 1.0f, 1.0f};
        if (nv_fx_atur(X, q, 5) != 1) rc = 7;
        nv_fx_lepas(X);
        if (nv_fx_buat(3, sr) || nv_fx_buat(1, 100)) rc = 8;
    }
    free(a); free(b);
    return rc;
}

int main(int argc, char** argv) {
    const char* dir = (argc > 1) ? argv[1] : ".";
    char pin[600], pout[600], pjob[600];
    snprintf(pin, sizeof(pin), "%s/nv_uji_in.raw", dir);
    snprintf(pout, sizeof(pout), "%s/nv_uji_out.raw", dir);
    snprintf(pjob, sizeof(pjob), "%s/nv_uji_job.txt", dir);
    const int sr = 44100, n = sr * 3;
    float* x = (float*)calloc(n, sizeof(float));
    double y1 = 0, y2 = 0;
    const double f0 = 130.0, r = 0.9985, th = 2.0 * NV_PI * 700.0 / sr;
    double next = 0.0;
    for (int i = 0; i < n; i++) {
        double ex = 0.0;
        if ((double)i >= next) { ex = 1.0; next += (double)sr / f0; }
        double y = ex + 2.0 * r * cos(th) * y1 - r * r * y2;
        y2 = y1; y1 = y;
        x[i] = (float)y;
    }
    float mx = 0; for (int i = 0; i < n; i++) if (fabsf(x[i]) > mx) mx = fabsf(x[i]);
    for (int i = 0; i < n; i++) x[i] = x[i] / mx * 0.5f;
    FILE* f = fopen(pin, "wb");
    if (!f) { printf("UJI GAGAL: tidak bisa menulis %s\n", pin); return 1; }
    unsigned char z[44]; memset(z, 0, 44); fwrite(z, 1, 44, f);
    for (int i = 0; i < n; i++) { int16_t s = (int16_t)lrintf(x[i] * 32767.0f); fwrite(&s, 2, 1, f); }
    fclose(f);
    f = fopen(pjob, "w");
    fprintf(f, "in=%s\nout=%s\nsr=%d\nch=1\nhdr=44\nouthdr=44\ndry=0\nfo=0\nnat=0\nv1=4,1.0,0,0\n", pin, pout, sr);
    fclose(f);
    clock_t t0 = clock();
    int rc = nv_jalankan(pjob);
    double detik = (double)(clock() - t0) / (double)CLOCKS_PER_SEC;
    if (rc != 0) { printf("UJI GAGAL: kode %d\n", rc); return 2; }
    printf("Kecepatan: audio 3 detik diproses dalam %.3f detik (RTF %.3f; makin kecil makin cepat, di bawah 1.0 berarti lebih cepat dari waktu nyata)\n", detik, detik / 3.0);
    f = fopen(pout, "rb");
    if (!f) { printf("UJI GAGAL: keluaran tidak ada\n"); return 3; }
    fseek(f, 44, SEEK_SET);
    float* o = (float*)calloc(n, sizeof(float));
    int cnt = 0;
    for (; cnt < n; cnt++) { int16_t s; if (fread(&s, 2, 1, f) != 1) break; o[cnt] = (float)s / 32768.0f; }
    fclose(f);
    if (cnt != n) { printf("UJI GAGAL: panjang keluaran %d, seharusnya %d\n", cnt, n); return 4; }
    double Tin = nv_periode(x + sr / 2, sr, 150, 600);
    double Tout = nv_periode(o + sr / 2, sr, 150, 600);
    double ratio = Tin / Tout;
    double target = pow(2.0, 4.0 / 12.0);
    printf("Periode masukan %.1f sampel, keluaran %.1f sampel\n", Tin, Tout);
    printf("Rasio nada terukur %.3f (target %.3f untuk +4 semiton)\n", ratio, target);
    remove(pin); remove(pout); remove(pjob);
    char pres[700]; snprintf(pres, sizeof(pres), "%s.res", pjob); remove(pres);
    int rcs = nv_uji_sonic(dir, x, n, sr);
    if (rcs != 0) { printf("UJI SONIC: GAGAL (%d)\n", rcs); return 9; }
    printf("UJI SONIC DAN AUTOTUNE: BERHASIL\n");
    { int rcl = nv_uji_live(dir, x, n, sr); if (rcl != 0) { printf("UJI LIVE: GAGAL (%d)\n", rcl); return 10; } printf("UJI LIVE: BERHASIL\n"); }
    { int rcs2 = nv_uji_sd(dir, x, n, sr); if (rcs2 != 0) { printf("UJI SUARA DUA LANGSUNG: GAGAL (%d)\n", rcs2); return 11; } printf("UJI SUARA DUA LANGSUNG: BERHASIL\n"); }
    { int rce = nv_uji_eq(); if (rce != 0) { printf("UJI EKUALISER LANGSUNG: GAGAL (%d)\n", rce); return 12; } printf("UJI EKUALISER LANGSUNG: BERHASIL\n"); }
    { int rcg = nv_uji_gate(); if (rcg != 0) { printf("UJI NOISE GATE LANGSUNG: GAGAL (%d)\n", rcg); return 13; } printf("UJI NOISE GATE LANGSUNG: BERHASIL\n"); }
    { int rcx = nv_uji_fx(); if (rcx != 0) { printf("UJI REVERB DAN ECHO LANGSUNG: GAGAL (%d)\n", rcx); return 14; } printf("UJI REVERB DAN ECHO LANGSUNG: BERHASIL\n"); }
    if (fabs(ratio - target) / target < 0.03) {
        if (nv_uji_video() != 0) { printf("UJI VIDEO: GAGAL\n"); return 6; }
        { int rc2 = nv_uji_campur(); if (rc2 != 0) { printf("UJI CAMPUR: GAGAL (%d)\n", rc2); return 7; } printf("UJI CAMPUR: BERHASIL\n"); }
        { int rc3 = nv_uji_rantai(); if (rc3 != 0) { printf("UJI RANTAI: GAGAL (%d)\n", rc3); return 8; } printf("UJI RANTAI: BERHASIL\n"); }
        printf("UJI VIDEO: BERHASIL\n");
        printf("UJI MANDIRI: BERHASIL\n");
        return 0;
    }
    printf("UJI MANDIRI: GAGAL (nada tidak sesuai)\n");
    return 5;
}
#endif
