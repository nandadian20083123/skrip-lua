import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaFormat;
import android.media.MediaMuxer;
import android.media.MediaExtractor;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.ShortBuffer;
import android.content.Context;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.speech.tts.Voice;
import java.util.HashMap;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

public class FastMuxer {

private static float racikRadioEnv(long fIdx, int sRate, long introF, long narEnd, float vInst, float holdSec, float fadeSecEff) {
if (fIdx < introF) return 1.0f;
if (fIdx < narEnd) {
if (introF <= 0) return vInst;
long duckF = (long) (0.5f * sRate);
long k = fIdx - introF;
if (k >= duckF) return vInst;
float x = (float) k / (float) duckF;
float sm = x * x * (3f - 2f * x);
return 1.0f + (vInst - 1.0f) * sm;
}
float tSec = (float) (fIdx - narEnd) / (float) sRate;
float peak = holdSec > 0f ? Math.max(1.0f, vInst) : vInst;
float swell = holdSec > 0f ? Math.min(0.6f, holdSec * 0.5f) : 0f;
if (tSec < swell) {
float x = tSec / swell;
float sm = x * x * (3f - 2f * x);
return vInst + (peak - vInst) * sm;
} else if (tSec < holdSec) {
return peak;
}
float x = (tSec - Math.max(holdSec, 0f)) / fadeSecEff;
if (x >= 1f) return 0f;
return peak * (0.5f * (1f + (float) Math.cos(Math.PI * x)));
}

public static String racikAudioStatus(String narPath, String instPath, String outPath, int fmt, int sRate, int ch, int bit, float vNar, float vInst, int offsetSec, int durTargetSec, int fadeInSec, int fadeOutSec, String rvbCfg, String toneCfg) {
return racikAudioStatus(narPath, instPath, outPath, fmt, sRate, ch, bit, vNar, vInst, offsetSec, durTargetSec, fadeInSec, fadeOutSec, rvbCfg, toneCfg, 0, 0L, 0f, 0f);
}

public static String racikAudioStatus(String narPath, String instPath, String outPath, int fmt, int sRate, int ch, int bit, float vNar, float vInst, int offsetSec, int durTargetSec, int fadeInSec, int fadeOutSec, String rvbCfg, String toneCfg, int radioMode, long musStartMs, float radioHoldSec, float radioFadeSec) {
tahap("Menyusun suara status");
File dir = new File(outPath).getParentFile();
if (dir != null && !dir.exists()) dir.mkdirs();
File rNar = new File(dir, "_st_nar.raw");
File rInst = new File(dir, "_st_inst.raw");
File wFx = new File(dir, "_st_fx.wav");
File rMix = new File(dir, "_st_mix.raw");
try {
rNar.delete(); rInst.delete(); wFx.delete(); rMix.delete();
if (narPath != null && !narPath.isEmpty() && new File(narPath).exists()) {
String d1 = decodeToPCM(narPath, rNar.getAbsolutePath(), sRate, ch, 0);
if (!"SUKSES".equals(d1)) return d1;
boolean useRvb = rvbCfg != null && rvbCfg.startsWith("1,");
boolean useTone = toneCfg != null && toneCfg.startsWith("1,");
if (useRvb || useTone) {
String rS = useRvb ? rvbCfg : "0,0.5,0.5,0.7,0.3";
String tS = useTone ? toneCfg : "0,50,50,50,50,50,50,50";
String cfg = "0|999999999|0,20,5,150|0,0|" + rS + "|0,300,0.3,0.5,1.0,0.3|" + tS + "|0,0,0,80";
String fxRes = terapkanEfekSegmen(rNar.getAbsolutePath(), cfg, wFx.getAbsolutePath(), 1, sRate, ch, bit, 0f, 0f);
if ("SUKSES".equals(fxRes) && wFx.length() > 44) {
FileInputStream fis = new FileInputStream(wFx);
fis.skip(44);
FileOutputStream fos = new FileOutputStream(rNar);
byte[] b = new byte[16384];
int r;
while ((r = fis.read(b)) > 0) fos.write(b, 0, r);
fis.close(); fos.close();
}
wFx.delete();
}
}
int fSize = ch * 2;
long narFrames = rNar.exists() ? (rNar.length() / fSize) : 0;
long dNarF = offsetSec > 0 ? ((long) offsetSec * sRate) : 0;
long dInstF = offsetSec < 0 ? ((long) (-offsetSec) * sRate) : 0;
long totFrames = durTargetSec > 0 ? ((long) durTargetSec * sRate) : (dNarF + narFrames);
boolean instAdaFile = (instPath != null && !instPath.isEmpty() && new File(instPath).exists());
boolean radio = (radioMode == 1) && instAdaFile;
long introF = 0L;
long narEndF = 0L;
float holdSecEff = 0f;
float fadeSecEff = Math.max(radioFadeSec, 0.05f);
if (radio) {
introF = Math.max(0L, musStartMs) * sRate / 1000L;
dNarF = introF;
dInstF = 0L;
narEndF = introF + narFrames;
long fadeF = (long) (fadeSecEff * sRate);
if (durTargetSec > 0) {
totFrames = (long) durTargetSec * sRate;
holdSecEff = Math.max(0f, (float) (totFrames - narEndF - fadeF) / (float) sRate);
} else {
holdSecEff = Math.max(radioHoldSec, 0f);
totFrames = narEndF + (long) (holdSecEff * sRate) + fadeF;
}
}
if (totFrames < sRate) totFrames = sRate;
boolean adaInst = false;
if (instPath != null && !instPath.isEmpty() && new File(instPath).exists()) {
long butuhDetik = ((totFrames - dInstF) + sRate - 1) / sRate + 2;
int limInst = (int) Math.max(1L, Math.min(86400L, butuhDetik));
String dI = decodeToPCM(instPath, rInst.getAbsolutePath(), sRate, ch, limInst);
if (!"SUKSES".equals(dI)) return "ERROR: gagal membaca instrumen: " + dI;
adaInst = rInst.length() > 0;
}
long fInF = (long) fadeInSec * sRate;
long fOutF = (long) fadeOutSec * sRate;
RandomAccessFile rafN = rNar.exists() ? new RandomAccessFile(rNar, "r") : null;
RandomAccessFile rafI = adaInst ? new RandomAccessFile(rInst, "r") : null;
FileOutputStream fosM = new FileOutputStream(rMix);
fosM.write(new byte[44]);
int chunkF = 4096;
byte[] bN = new byte[chunkF * fSize];
byte[] bI = new byte[chunkF * fSize];
byte[] bO = new byte[chunkF * fSize];
long curF = 0;
while (curF < totFrames) {
int nF = (int) Math.min((long) chunkF, totFrames - curF);
int nBytes = nF * fSize;
java.util.Arrays.fill(bN, 0, nBytes, (byte) 0);
java.util.Arrays.fill(bI, 0, nBytes, (byte) 0);
if (rafN != null && curF + nF > dNarF && curF < dNarF + narFrames) {
int skipF = (curF < dNarF) ? (int) (dNarF - curF) : 0;
rafN.read(bN, skipF * fSize, (nF - skipF) * fSize);
}
if (rafI != null && curF + nF > dInstF) {
int skipF = (curF < dInstF) ? (int) (dInstF - curF) : 0;
int offB = skipF * fSize;
int remB = nBytes - offB;
while (remB > 0) {
int r = rafI.read(bI, offB, remB);
if (r <= 0) { rafI.seek(0); r = rafI.read(bI, offB, remB); if (r <= 0) break; }
offB += r; remB -= r;
}
}
boolean campurNative = false;
if (!radio && campurNativeSiap()) {
try {
campurNative = nvCampurPCM(bN, bI, bO, nF, ch, curF, dInstF, fInF, fOutF, totFrames, vNar, vInst) == 1;
} catch (Throwable t) { campurNativeState = -1; }
}
if (!campurNative) {
ByteBuffer bbN = ByteBuffer.wrap(bN, 0, nBytes).order(ByteOrder.LITTLE_ENDIAN);
ByteBuffer bbI = ByteBuffer.wrap(bI, 0, nBytes).order(ByteOrder.LITTLE_ENDIAN);
ByteBuffer bbO = ByteBuffer.wrap(bO, 0, nBytes).order(ByteOrder.LITTLE_ENDIAN);
for (int i = 0; i < nF; i++) {
long fIdx = curF + i;
float env = 1.0f;
if (radio) {
env = racikRadioEnv(fIdx, sRate, introF, narEndF, vInst, holdSecEff, fadeSecEff);
} else {
if (fInF > 0 && fIdx >= dInstF && (fIdx - dInstF) < fInF) env *= (float) (fIdx - dInstF) / (float) fInF;
if (fOutF > 0 && (totFrames - fIdx) < fOutF) env *= (float) (totFrames - fIdx) / (float) fOutF;
}
for (int c = 0; c < ch; c++) {
int m = Math.round((bbN.getShort() * vNar) + (bbI.getShort() * (radio ? 1.0f : vInst) * env));
if (m > 32767) m = 32767; else if (m < -32768) m = -32768;
bbO.putShort((short) m);
}
}
}
fosM.write(bO, 0, nBytes);
curF += nF;
}
if (rafN != null) rafN.close();
if (rafI != null) rafI.close();
fosM.close();
rNar.delete(); rInst.delete();
String res = prosesAudio(rMix.getAbsolutePath(), "", outPath, fmt, sRate, ch, bit, 1.0f, 1.0f);
rMix.delete();
return res;
} catch (Exception e) {
rNar.delete(); rInst.delete(); wFx.delete(); rMix.delete();
return "ERROR: " + e.getMessage();
}
}

public static String renderVideoStatus(String audioM4aPath, String imgPath, String teksCerita, String teksCreator, boolean devWm, int modeLatar, String outPath, int reqW, int reqH) {
tahap("Membuat video status");
File dir = new File(outPath).getParentFile();
if (dir != null && !dir.exists()) dir.mkdirs();
File fBmp = new File(dir, "_st_canvas.png");
try {
int w = reqW - (reqW % 2);
int h = reqH - (reqH % 2);
android.graphics.Bitmap bmp = android.graphics.Bitmap.createBitmap(w, h, android.graphics.Bitmap.Config.ARGB_8888);
android.graphics.Canvas cv = new android.graphics.Canvas(bmp);
android.graphics.Paint p = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
boolean drawnImg = false;
if (modeLatar == 1 && imgPath != null && !imgPath.isEmpty() && new File(imgPath).exists()) {
android.graphics.Bitmap src = android.graphics.BitmapFactory.decodeFile(imgPath);
if (src != null) {
float sc = Math.max((float) w / src.getWidth(), (float) h / src.getHeight());
int nw = Math.round(src.getWidth() * sc), nh = Math.round(src.getHeight() * sc);
android.graphics.Bitmap scaled = android.graphics.Bitmap.createScaledBitmap(src, nw, nh, true);
cv.drawBitmap(scaled, (w - nw) / 2f, (h - nh) / 2f, p);
p.setColor(0x78000000);
cv.drawRect(0, 0, w, h, p);
drawnImg = true;
}
}
if (!drawnImg) {
int cTop = (modeLatar == 2) ? 0xFF0F2027 : 0xFF0B1021;
int cBot = (modeLatar == 2) ? 0xFF2C5364 : 0xFF1E1B4B;
p.setShader(new android.graphics.LinearGradient(0, 0, w, h, cTop, cBot, android.graphics.Shader.TileMode.CLAMP));
cv.drawRect(0, 0, w, h, p);
p.setShader(null);
if (modeLatar == 2) {
p.setColor(0x4438BDF8);
float bw = (w * 0.7f) / 24f, sx = w * 0.15f;
for (int i = 0; i < 24; i++) {
float bh = (float) (Math.sin(i * 0.7) * 0.5 + 0.6) * (h * 0.06f);
cv.drawRect(sx + i * bw, h * 0.80f - bh, sx + i * bw + bw * 0.6f, h * 0.80f + bh, p);
}
}
}
float padX = w * 0.08f, padY = h * 0.18f;
p.setColor(0x66000000);
cv.drawRoundRect(new android.graphics.RectF(padX, padY, w - padX, h - padY), 28f, 28f, p);
p.setStyle(android.graphics.Paint.Style.STROKE);
p.setStrokeWidth(3f);
p.setColor(0x5590CAF9);
cv.drawRoundRect(new android.graphics.RectF(padX, padY, w - padX, h - padY), 28f, 28f, p);
p.setStyle(android.graphics.Paint.Style.FILL);
String isi = (teksCerita != null && !teksCerita.trim().isEmpty()) ? teksCerita.trim() : "Status Cerita";
if (isi.length() > 280) isi = isi.substring(0, 280) + "...";
p.setColor(0xFFFFFFFF);
p.setTypeface(android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD));
p.setTextAlign(android.graphics.Paint.Align.CENTER);
float tSize = Math.max(22f, Math.min(w, h) * 0.042f);
p.setTextSize(tSize);
p.setShadowLayer(6f, 0f, 3f, 0xFF000000);
float maxW = w - (padX * 2.6f);
String[] words = isi.split("\\s+");
java.util.List<String> lines = new java.util.ArrayList<String>();
String curL = "";
for (String wd : words) {
String test = curL.isEmpty() ? wd : (curL + " " + wd);
if (p.measureText(test) <= maxW) curL = test;
else { if (!curL.isEmpty()) lines.add(curL); curL = wd; }
}
if (!curL.isEmpty()) lines.add(curL);
float lineH = tSize * 1.4f;
float startY = (h / 2f) - ((lines.size() - 1) * lineH / 2f);
for (int i = 0; i < lines.size(); i++) cv.drawText(lines.get(i), w / 2f, startY + (i * lineH), p);
if (teksCreator != null && !teksCreator.trim().isEmpty()) {
p.setColor(0xFFFFD54F);
p.setTextSize(Math.max(18f, Math.min(w, h) * 0.032f));
p.setTextAlign(android.graphics.Paint.Align.CENTER);
cv.drawText("Karya: " + teksCreator.trim(), w / 2f, h - (h * 0.10f), p);
}
if (devWm) {
p.setColor(0xB8FFFFFF);
p.setTextSize(Math.max(16f, Math.min(w, h) * 0.028f));
p.setTextAlign(android.graphics.Paint.Align.RIGHT);
cv.drawText("Nadi Editor", w - (w * 0.05f), h * 0.06f, p);
}
FileOutputStream fos = new FileOutputStream(fBmp);
bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 95, fos);
fos.close();
bmp.recycle();
String res = audioKeVideo(audioM4aPath, fBmp.getAbsolutePath(), "", outPath, w, h);
fBmp.delete();
return res;
} catch (Exception e) {
fBmp.delete();
return "ERROR: " + e.getMessage();
}
}

private static void aplikasiFadePotong(byte[] b, int len, int frameSize, int channels, long segPos, long segLen, long fadeInB, long fadeOutB) {
int frames = len / frameSize;
for (int fr = 0; fr < frames; fr++) {
long posB = segPos + (long) fr * frameSize;
double g = 1.0;
if (fadeInB > 0 && posB < fadeInB) g = Math.min(g, (double) posB / (double) fadeInB);
long sisa = segLen - posB;
if (fadeOutB > 0 && sisa <= fadeOutB) g = Math.min(g, (double) sisa / (double) fadeOutB);
if (g >= 1.0) continue;
if (g < 0.0) g = 0.0;
for (int c = 0; c < channels; c++) {
int o = fr * frameSize + c * 2;
int sm = (short) ((b[o] & 0xFF) | (b[o + 1] << 8));
sm = (int) Math.round(sm * g);
b[o] = (byte) (sm & 0xFF);
b[o + 1] = (byte) ((sm >> 8) & 0xFF);
}
}
}

public static String potongAudio(String inputPath, String outputPath, int format, int sampleRate, int channels, int bitrate, int mode, float msAwal, float msAkhir) {
tahap("Memotong audio");
RandomAccessFile raf = null;
try {
File inFile = new File(inputPath);
if (!inFile.exists()) return "ERROR: File tidak ditemukan.";
int frameSize = channels * 2;
raf = new RandomAccessFile(inFile, "r");
long headerOffset = 0;
if (inFile.length() >= 44) {
byte[] magic = new byte[4];
raf.read(magic);
if (magic[0] == 'R' && magic[1] == 'I' && magic[2] == 'F' && magic[3] == 'F') {
headerOffset = 44;
}
}
long totalAudioBytes = inFile.length() - headerOffset;
totalAudioBytes -= (totalAudioBytes % frameSize);
if (totalAudioBytes <= 0) {
raf.close();
return "ERROR: File kosong.";
}
double bytesPerMs = ((double) sampleRate * frameSize) / 1000.0;
long byteA = Math.round(msAwal * bytesPerMs);
byteA -= (byteA % frameSize);
long byteB = Math.round(msAkhir * bytesPerMs);
byteB -= (byteB % frameSize);
if (byteA < 0) byteA = 0;
if (byteB > totalAudioBytes) byteB = totalAudioBytes;
if (byteA >= byteB) {
raf.close();
return "ERROR: Titik awal harus lebih kecil dari titik akhir.";
}
long[] readLimits;
long[] seekPoints;
byte[][] memData;
long[] fadeInB;
long[] fadeOutB;
long fadeB = (long) Math.max(1, sampleRate * 8 / 1000) * frameSize;
long xfB = (long) Math.max(1, sampleRate * 15 / 1000) * frameSize;
if (mode == 1) {
seekPoints = new long[]{headerOffset + byteA};
readLimits = new long[]{byteB - byteA};
memData = new byte[1][];
fadeInB = new long[]{byteA > 0 ? fadeB : 0};
fadeOutB = new long[]{byteB < totalAudioBytes ? fadeB : 0};
} else if (byteA >= xfB && byteB >= xfB) {
byte[] xa = new byte[(int) xfB];
byte[] xf = new byte[(int) xfB];
raf.seek(headerOffset + byteA - xfB);
raf.readFully(xa);
raf.seek(headerOffset + byteB - xfB);
raf.readFully(xf);
int nFr = (int) (xfB / frameSize);
for (int fr = 0; fr < nFr; fr++) {
double tt = (nFr <= 1) ? 1.0 : (double) fr / (nFr - 1);
double gOut = Math.cos(tt * Math.PI / 2.0);
double gIn = Math.sin(tt * Math.PI / 2.0);
for (int c = 0; c < channels; c++) {
int o = fr * frameSize + c * 2;
int s1 = (short) ((xa[o] & 0xFF) | (xa[o + 1] << 8));
int s2 = (short) ((xf[o] & 0xFF) | (xf[o + 1] << 8));
int m = (int) Math.round(s1 * gOut + s2 * gIn);
if (m > 32767) m = 32767; else if (m < -32768) m = -32768;
xf[o] = (byte) (m & 0xFF);
xf[o + 1] = (byte) ((m >> 8) & 0xFF);
}
}
seekPoints = new long[]{headerOffset, headerOffset, headerOffset + byteB};
readLimits = new long[]{byteA - xfB, xfB, totalAudioBytes - byteB};
memData = new byte[3][];
memData[1] = xf;
fadeInB = new long[]{0, 0, 0};
fadeOutB = new long[]{0, 0, 0};
} else {
seekPoints = new long[]{headerOffset, headerOffset + byteB};
readLimits = new long[]{byteA, totalAudioBytes - byteB};
memData = new byte[2][];
fadeInB = new long[]{0, fadeB};
fadeOutB = new long[]{fadeB, 0};
}
long totalTargetBytes = 0;
for (long lim : readLimits) totalTargetBytes += lim;
if (totalTargetBytes <= 0) {
raf.close();
return "ERROR: Hasil pemotongan kosong.";
}
boolean isM4a = (format == 2);
FileOutputStream fosWav = null;
MediaCodec encoder = null;
MediaMuxer muxer = null;
int trackIdx = -1;
boolean muxStarted = false;
long ptsUs = 0;
long totalBytesWritten = 0;
int lastProgress = 0;
String progFile = outputPath + ".prog";
if (!isM4a) {
fosWav = new FileOutputStream(outputPath);
fosWav.write(new byte[44]);
} else {
MediaFormat f = MediaFormat.createAudioFormat("audio/mp4a-latm", sampleRate, channels);
f.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC);
f.setInteger(MediaFormat.KEY_BIT_RATE, bitrate);
f.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 524288);
encoder = MediaCodec.createEncoderByType("audio/mp4a-latm");
encoder.configure(f, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
encoder.start();
muxer = new MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
}
int bufSize = 32768;
byte[] buffer = new byte[bufSize];
MediaCodec.BufferInfo info = isM4a ? new MediaCodec.BufferInfo() : null;
for (int i = 0; i < seekPoints.length; i++) {
if (readLimits[i] <= 0) continue;
raf.seek(seekPoints[i]);
long bytesRemaining = readLimits[i];
long segDone = 0;
int memPos = 0;
while (bytesRemaining > 0) {
int toRead = (int) Math.min((long) bufSize, bytesRemaining);
toRead -= (toRead % frameSize);
if (toRead <= 0) break;
int read;
if (memData[i] != null) {
read = (int) Math.min((long) toRead, (long) memData[i].length - memPos);
if (read > 0) { System.arraycopy(memData[i], memPos, buffer, 0, read); memPos += read; }
} else {
read = raf.read(buffer, 0, toRead);
}
if (read <= 0) break;
read -= (read % frameSize);
if (read <= 0) break;
if (fadeInB[i] > 0 || fadeOutB[i] > 0) aplikasiFadePotong(buffer, read, frameSize, channels, segDone, readLimits[i], fadeInB[i], fadeOutB[i]);
if (!isM4a) {
fosWav.write(buffer, 0, read);
} else {
int inIdx = -1;
while (inIdx < 0) {
inIdx = encoder.dequeueInputBuffer(10000);
if (inIdx >= 0) {
ByteBuffer inBuf = encoder.getInputBuffer(inIdx);
inBuf.clear();
inBuf.put(buffer, 0, read);
encoder.queueInputBuffer(inIdx, 0, read, ptsUs, 0);
ptsUs += (long) read * 1000000L / (sampleRate * frameSize);
}
while (true) {
int outIdx = encoder.dequeueOutputBuffer(info, 10000);
if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
trackIdx = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (outIdx >= 0) {
ByteBuffer outBuf = encoder.getOutputBuffer(outIdx);
if (info.size > 0 && muxStarted) {
outBuf.position(info.offset);
outBuf.limit(info.offset + info.size);
muxer.writeSampleData(trackIdx, outBuf, info);
}
encoder.releaseOutputBuffer(outIdx, false);
} else {
break;
}
}
}
}
totalBytesWritten += read;
segDone += read;
bytesRemaining -= read;
int currentProgress = (int) ((totalBytesWritten * 100L) / totalTargetBytes);
if (currentProgress > lastProgress && currentProgress <= 100) {
lastProgress = currentProgress;
try {
FileOutputStream pfos = new FileOutputStream(progFile);
pfos.write(String.valueOf(currentProgress).getBytes()); laporUmum((int) (currentProgress));
pfos.close();
} catch (Exception ignored) {}
}
}
}
raf.close();
raf = null;
if (!isM4a) {
fosWav.close();
RandomAccessFile rafWav = new RandomAccessFile(outputPath, "rw");
rafWav.seek(0);
ByteBuffer head = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
head.put("RIFF".getBytes()); head.putInt((int)totalBytesWritten + 36);
head.put("WAVE".getBytes()); head.put("fmt ".getBytes());
head.putInt(16); head.putShort((short)1); head.putShort((short)channels);
head.putInt(sampleRate); head.putInt(sampleRate * frameSize);
head.putShort((short)frameSize); head.putShort((short)16);
head.put("data".getBytes()); head.putInt((int)totalBytesWritten);
rafWav.write(head.array());
rafWav.close();
} else {
int inIdx = -1;
while (inIdx < 0) {
inIdx = encoder.dequeueInputBuffer(10000);
if (inIdx >= 0) {
encoder.queueInputBuffer(inIdx, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
} else {
while (true) {
int outIdx = encoder.dequeueOutputBuffer(info, 10000);
if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
trackIdx = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (outIdx >= 0) {
ByteBuffer outBuf = encoder.getOutputBuffer(outIdx);
if (info.size > 0 && muxStarted) {
outBuf.position(info.offset);
outBuf.limit(info.offset + info.size);
muxer.writeSampleData(trackIdx, outBuf, info);
}
encoder.releaseOutputBuffer(outIdx, false);
} else {
break;
}
}
}
}
while (true) {
int outIdx = encoder.dequeueOutputBuffer(info, 10000);
if (outIdx >= 0) {
ByteBuffer outBuf = encoder.getOutputBuffer(outIdx);
if (info.size > 0 && muxStarted) {
outBuf.position(info.offset);
outBuf.limit(info.offset + info.size);
muxer.writeSampleData(trackIdx, outBuf, info);
}
encoder.releaseOutputBuffer(outIdx, false);
if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break;
} else if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
trackIdx = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) {
break;
}
}
encoder.stop(); encoder.release();
if (muxStarted) { muxer.stop(); muxer.release(); }
}
new File(progFile).delete();
return "SUKSES";
} catch (Exception e) {
if (raf != null) try { raf.close(); } catch (Exception ignored) {}
return "ERROR: " + e.getMessage();
}
}

public static String potongVideo(String videoPath, String cutAudioPath, String outPath, int mode, float msAwal, float msAkhir) {
tahap("Memotong video");
MediaExtractor vEx = null;
MediaExtractor aEx = null;
MediaMuxer muxer = null;
try {
File vFile = new File(videoPath);
if (!vFile.exists()) return "ERROR: File video tidak ditemukan.";
vEx = new MediaExtractor();
vEx.setDataSource(videoPath);
int vTrack = -1;
MediaFormat vFormat = null;
for (int i = 0; i < vEx.getTrackCount(); i++) {
MediaFormat fmt = vEx.getTrackFormat(i);
String mime = fmt.getString(MediaFormat.KEY_MIME);
if (mime != null && mime.startsWith("video/")) {
vTrack = i;
vFormat = fmt;
break;
}
}
if (vTrack == -1 || vFormat == null) {
vEx.release();
return "ERROR: Tidak ada trek video di dalam file.";
}
vEx.selectTrack(vTrack);
long totalVideoUs = vFormat.containsKey(MediaFormat.KEY_DURATION) ? vFormat.getLong(MediaFormat.KEY_DURATION) : Long.MAX_VALUE;
long usA = Math.round(msAwal * 1000.0);
long usB = Math.round(msAkhir * 1000.0);
if (usA < 0) usA = 0;
if (totalVideoUs != Long.MAX_VALUE && usB > totalVideoUs) usB = totalVideoUs;
if (usA >= usB) {
vEx.release();
return "ERROR: Titik awal harus lebih kecil dari titik akhir.";
}
long[] segStarts;
long[] segEnds;
if (mode == 1) {
segStarts = new long[]{usA};
segEnds = new long[]{usB};
} else {
segStarts = new long[]{0L, usB};
segEnds = new long[]{usA, totalVideoUs};
}
long totalTargetUs = 0;
for (int i = 0; i < segStarts.length; i++) {
if (segEnds[i] > segStarts[i]) {
totalTargetUs += (segEnds[i] - segStarts[i]);
}
}
if (totalTargetUs <= 0) {
vEx.release();
return "ERROR: Durasi hasil potongan kosong.";
}
muxer = new MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
if (vFormat.containsKey(MediaFormat.KEY_ROTATION)) {
try {
muxer.setOrientationHint(vFormat.getInteger(MediaFormat.KEY_ROTATION));
} catch (Exception ignored) {}
}
int mVTrack = muxer.addTrack(vFormat);
int mATrack = -1;
if (cutAudioPath != null && !cutAudioPath.isEmpty()) {
File aFile = new File(cutAudioPath);
if (aFile.exists() && aFile.length() > 0) {
aEx = new MediaExtractor();
aEx.setDataSource(cutAudioPath);
for (int i = 0; i < aEx.getTrackCount(); i++) {
MediaFormat af = aEx.getTrackFormat(i);
String amime = af.getString(MediaFormat.KEY_MIME);
if (amime != null && amime.startsWith("audio/")) {
aEx.selectTrack(i);
mATrack = muxer.addTrack(af);
break;
}
}
}
}
muxer.start();
ByteBuffer buf = ByteBuffer.allocate(2097152);
MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
String progFile = outPath + ".prog";
int lastProgress = 80;
long outBaseUs = 0;
long lastVideoPtsUs = -1;
long writtenSpanUs = 0;
for (int i = 0; i < segStarts.length; i++) {
long sStart = segStarts[i];
long sEnd = segEnds[i];
if (sEnd <= sStart) continue;
vEx.seekTo(sStart, MediaExtractor.SEEK_TO_PREVIOUS_SYNC);
while (true) {
info.offset = 0;
info.size = vEx.readSampleData(buf, 0);
if (info.size < 0) break;
long sampleTime = vEx.getSampleTime();
if (sampleTime < 0 || sampleTime > sEnd) break;
long pts;
if (sampleTime < sStart) {
pts = (lastVideoPtsUs < outBaseUs) ? outBaseUs : (lastVideoPtsUs + 500L);
} else {
pts = outBaseUs + (sampleTime - sStart);
if (pts <= lastVideoPtsUs) {
pts = lastVideoPtsUs + 500L;
}
}
lastVideoPtsUs = pts;
info.presentationTimeUs = pts;
info.flags = vEx.getSampleFlags();
muxer.writeSampleData(mVTrack, buf, info);
if (sampleTime >= sStart && totalTargetUs > 0 && totalTargetUs != Long.MAX_VALUE) {
long curSpan = writtenSpanUs + (sampleTime - sStart);
int prog = 80 + (int) ((curSpan * 20L) / totalTargetUs);
if (prog > lastProgress && prog <= 100) {
lastProgress = prog;
try {
FileOutputStream pfos = new FileOutputStream(progFile);
pfos.write(String.valueOf(prog).getBytes()); laporUmum((int) (prog));
pfos.close();
} catch (Exception ignored) {}
}
}
vEx.advance();
}
writtenSpanUs += (sEnd - sStart);
outBaseUs += (sEnd - sStart);
if (lastVideoPtsUs >= outBaseUs) {
outBaseUs = lastVideoPtsUs + 500L;
}
}
if (aEx != null && mATrack != -1) {
long lastAudioPtsUs = -1;
while (true) {
info.offset = 0;
info.size = aEx.readSampleData(buf, 0);
if (info.size < 0) break;
long aPts = aEx.getSampleTime();
if (aPts < 0) break;
if (aPts <= lastAudioPtsUs) aPts = lastAudioPtsUs + 100L;
lastAudioPtsUs = aPts;
info.presentationTimeUs = aPts;
info.flags = aEx.getSampleFlags();
muxer.writeSampleData(mATrack, buf, info);
aEx.advance();
}
aEx.release();
aEx = null;
}
vEx.release();
vEx = null;
muxer.stop();
muxer.release();
muxer = null;
new File(progFile).delete();
return "SUKSES";
} catch (Exception e) {
if (vEx != null) try { vEx.release(); } catch (Exception ignored) {}
if (aEx != null) try { aEx.release(); } catch (Exception ignored) {}
if (muxer != null) try { muxer.stop(); muxer.release(); } catch (Exception ignored) {}
return "ERROR: " + e.getMessage();
}
}

private static void tulisBingkaiYUV(android.media.Image srcImg, int srcW, int srcH, int srcRot, android.media.Image dstImg, int outW, int outH) {
android.media.Image.Plane[] srcPlanes = srcImg.getPlanes();
android.media.Image.Plane[] dstPlanes = dstImg.getPlanes();
ByteBuffer srcY = srcPlanes[0].getBuffer();
ByteBuffer srcU = srcPlanes[1].getBuffer();
ByteBuffer srcV = srcPlanes[2].getBuffer();
int srcYRow = srcPlanes[0].getRowStride();
int srcYPix = srcPlanes[0].getPixelStride();
int srcURow = srcPlanes[1].getRowStride();
int srcUPix = srcPlanes[1].getPixelStride();
int srcVRow = srcPlanes[2].getRowStride();
int srcVPix = srcPlanes[2].getPixelStride();
ByteBuffer dstY = dstPlanes[0].getBuffer();
ByteBuffer dstU = dstPlanes[1].getBuffer();
ByteBuffer dstV = dstPlanes[2].getBuffer();
int dstYRow = dstPlanes[0].getRowStride();
int dstYPix = dstPlanes[0].getPixelStride();
int dstURow = dstPlanes[1].getRowStride();
int dstUPix = dstPlanes[1].getPixelStride();
int dstVRow = dstPlanes[2].getRowStride();
int dstVPix = dstPlanes[2].getPixelStride();
if (videoNativeSiap()) {
try {
int[] pr = {srcW, srcH, srcRot, outW, outH, srcYRow, srcYPix, srcURow, srcUPix, srcVRow, srcVPix, dstYRow, dstYPix, dstURow, dstUPix, dstVRow, dstVPix};
if (nvBingkaiYUV(srcY, srcU, srcV, dstY, dstU, dstV, pr) == 1) return;
} catch (Throwable t) { videoNativeState = -1; }
}
int visW = (srcRot == 90 || srcRot == 270) ? srcH : srcW;
int visH = (srcRot == 90 || srcRot == 270) ? srcW : srcH;
float scale = Math.min((float) outW / visW, (float) outH / visH);
int drawW = Math.max(2, ((int) Math.round(visW * scale) / 2) * 2);
int drawH = Math.max(2, ((int) Math.round(visH * scale) / 2) * 2);
if (drawW > outW) drawW = outW;
if (drawH > outH) drawH = outH;
int padX = ((outW - drawW) / 4) * 2;
int padY = ((outH - drawH) / 4) * 2;
if (drawW < outW || drawH < outH) {
int dstYCap = dstY.capacity();
for (int y = 0; y < outH; y++) {
int rowStart = y * dstYRow;
for (int x = 0; x < outW; x++) {
int idx = rowStart + x * dstYPix;
if (idx >= 0 && idx < dstYCap) dstY.put(idx, (byte) 16);
}
}
int uvH = outH / 2;
int uvW = outW / 2;
int dstUCap = dstU.capacity();
int dstVCap = dstV.capacity();
for (int y = 0; y < uvH; y++) {
int uRow = y * dstURow;
int vRow = y * dstVRow;
for (int x = 0; x < uvW; x++) {
int uIdx = uRow + x * dstUPix;
int vIdx = vRow + x * dstVPix;
if (uIdx >= 0 && uIdx < dstUCap) dstU.put(uIdx, (byte) 128);
if (vIdx >= 0 && vIdx < dstVCap) dstV.put(vIdx, (byte) 128);
}
}
}
int[] mapVX = new int[drawW];
for (int dx = 0; dx < drawW; dx++) {
int v = (dx * visW) / drawW;
if (v >= visW) v = visW - 1;
mapVX[dx] = v;
}
int[] mapVY = new int[drawH];
for (int dy = 0; dy < drawH; dy++) {
int v = (dy * visH) / drawH;
if (v >= visH) v = visH - 1;
mapVY[dy] = v;
}
int srcYCap = srcY.capacity();
int dstYCap = dstY.capacity();
for (int dy = 0; dy < drawH; dy++) {
int vy = mapVY[dy];
int dstRowOff = (dy + padY) * dstYRow;
for (int dx = 0; dx < drawW; dx++) {
int vx = mapVX[dx];
int sx, sy;
if (srcRot == 90) {
sx = vy;
sy = srcH - 1 - vx;
} else if (srcRot == 180) {
sx = srcW - 1 - vx;
sy = srcH - 1 - vy;
} else if (srcRot == 270) {
sx = srcW - 1 - vy;
sy = vx;
} else {
sx = vx;
sy = vy;
}
int sIdx = sy * srcYRow + sx * srcYPix;
int dIdx = dstRowOff + (dx + padX) * dstYPix;
if (sIdx >= 0 && sIdx < srcYCap && dIdx >= 0 && dIdx < dstYCap) {
dstY.put(dIdx, srcY.get(sIdx));
}
}
}
int drawW2 = drawW / 2;
int drawH2 = drawH / 2;
int padX2 = padX / 2;
int padY2 = padY / 2;
int srcUCap = srcU.capacity();
int srcVCap = srcV.capacity();
int dstUCap = dstU.capacity();
int dstVCap = dstV.capacity();
for (int dy = 0; dy < drawH2; dy++) {
int vy = mapVY[dy * 2];
int uDstRow = (dy + padY2) * dstURow;
int vDstRow = (dy + padY2) * dstVRow;
for (int dx = 0; dx < drawW2; dx++) {
int vx = mapVX[dx * 2];
int sx, sy;
if (srcRot == 90) {
sx = vy;
sy = srcH - 1 - vx;
} else if (srcRot == 180) {
sx = srcW - 1 - vx;
sy = srcH - 1 - vy;
} else if (srcRot == 270) {
sx = srcW - 1 - vy;
sy = vx;
} else {
sx = vx;
sy = vy;
}
int uvSX = sx / 2;
int uvSY = sy / 2;
int sUIdx = uvSY * srcURow + uvSX * srcUPix;
int sVIdx = uvSY * srcVRow + uvSX * srcVPix;
int dUIdx = uDstRow + (dx + padX2) * dstUPix;
int dVIdx = vDstRow + (dx + padX2) * dstVPix;
if (sUIdx >= 0 && sUIdx < srcUCap && dUIdx >= 0 && dUIdx < dstUCap) {
dstU.put(dUIdx, srcU.get(sUIdx));
}
if (sVIdx >= 0 && sVIdx < srcVCap && dVIdx >= 0 && dVIdx < dstVCap) {
dstV.put(dVIdx, srcV.get(sVIdx));
}
}
}
}

public static String gabungVideo(String listVideoData, String mergedAudioPath, String outPath, int targetRes) {
tahap("Menggabungkan video");
MediaMuxer muxer = null;
MediaCodec encoder = null;
MediaExtractor aEx = null;
try {
String[] paths = listVideoData.trim().split("\n");
int n = paths.length;
if (n == 0) return "ERROR: Daftar video kosong.";
int[] widths = new int[n];
int[] heights = new int[n];
int[] rots = new int[n];
long[] durs = new long[n];
String[] mimes = new String[n];
byte[][] csd0s = new byte[n][];
MediaFormat firstFormat = null;
long totalAllVideoUs = 0;
for (int i = 0; i < n; i++) {
paths[i] = paths[i].trim();
File vf = new File(paths[i]);
if (!vf.exists()) return "ERROR: File tidak ditemukan: " + paths[i];
MediaExtractor ex = new MediaExtractor();
ex.setDataSource(paths[i]);
MediaFormat vFmt = null;
for (int t = 0; t < ex.getTrackCount(); t++) {
MediaFormat fmt = ex.getTrackFormat(t);
String m = fmt.getString(MediaFormat.KEY_MIME);
if (m != null && m.startsWith("video/")) {
vFmt = fmt;
break;
}
}
ex.release();
if (vFmt == null) return "ERROR: Tidak ada trek video pada " + vf.getName();
if (i == 0) firstFormat = vFmt;
mimes[i] = vFmt.getString(MediaFormat.KEY_MIME);
widths[i] = vFmt.getInteger(MediaFormat.KEY_WIDTH);
heights[i] = vFmt.getInteger(MediaFormat.KEY_HEIGHT);
rots[i] = vFmt.containsKey(MediaFormat.KEY_ROTATION) ? vFmt.getInteger(MediaFormat.KEY_ROTATION) : 0;
durs[i] = vFmt.containsKey(MediaFormat.KEY_DURATION) ? vFmt.getLong(MediaFormat.KEY_DURATION) : 10000000L;
totalAllVideoUs += Math.max(1000L, durs[i]);
if (vFmt.containsKey("csd-0")) {
ByteBuffer b = vFmt.getByteBuffer("csd-0");
if (b != null) {
byte[] arr = new byte[b.remaining()];
b.duplicate().get(arr);
csd0s[i] = arr;
}
}
}
boolean bisaSalinKilat = (targetRes == 0);
if (bisaSalinKilat) {
for (int i = 1; i < n; i++) {
if (!mimes[0].equals(mimes[i]) || widths[0] != widths[i] || heights[0] != heights[i] || rots[0] != rots[i]) {
bisaSalinKilat = false;
break;
}
if (csd0s[0] != null && csd0s[i] != null && !java.util.Arrays.equals(csd0s[0], csd0s[i])) {
bisaSalinKilat = false;
break;
}
}
}
String progFile = outPath + ".prog";
int lastProgress = 0;
if (bisaSalinKilat && firstFormat != null) {
muxer = new MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
if (rots[0] != 0) {
try { muxer.setOrientationHint(rots[0]); } catch (Exception ignored) {}
}
int mVTrack = muxer.addTrack(firstFormat);
int mATrack = -1;
if (mergedAudioPath != null && !mergedAudioPath.isEmpty()) {
File af = new File(mergedAudioPath);
if (af.exists() && af.length() > 0) {
aEx = new MediaExtractor();
aEx.setDataSource(mergedAudioPath);
for (int t = 0; t < aEx.getTrackCount(); t++) {
MediaFormat fmt = aEx.getTrackFormat(t);
String am = fmt.getString(MediaFormat.KEY_MIME);
if (am != null && am.startsWith("audio/")) {
aEx.selectTrack(t);
mATrack = muxer.addTrack(fmt);
break;
}
}
}
}
muxer.start();
ByteBuffer buf = ByteBuffer.allocate(2097152);
MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
long basePtsUs = 0;
long lastGlobalPtsUs = -1;
for (int i = 0; i < n; i++) {
MediaExtractor vEx = new MediaExtractor();
vEx.setDataSource(paths[i]);
for (int t = 0; t < vEx.getTrackCount(); t++) {
String m = vEx.getTrackFormat(t).getString(MediaFormat.KEY_MIME);
if (m != null && m.startsWith("video/")) {
vEx.selectTrack(t);
break;
}
}
long maxLocalPts = 0;
while (true) {
info.offset = 0;
info.size = vEx.readSampleData(buf, 0);
if (info.size < 0) break;
long st = vEx.getSampleTime();
if (st < 0) break;
if (st > maxLocalPts) maxLocalPts = st;
long pts = basePtsUs + st;
if (pts <= lastGlobalPtsUs) pts = lastGlobalPtsUs + 500L;
lastGlobalPtsUs = pts;
info.presentationTimeUs = pts;
info.flags = vEx.getSampleFlags();
muxer.writeSampleData(mVTrack, buf, info);
if (totalAllVideoUs > 0) {
int prog = (int) ((pts * 100L) / totalAllVideoUs);
if (prog > lastProgress && prog <= 100) {
lastProgress = prog;
try {
FileOutputStream pfos = new FileOutputStream(progFile);
pfos.write(String.valueOf(prog).getBytes()); laporUmum((int) (prog));
pfos.close();
} catch (Exception ignored) {}
}
}
vEx.advance();
}
vEx.release();
long clipDur = Math.max(durs[i], maxLocalPts + 33333L);
basePtsUs += clipDur;
if (lastGlobalPtsUs >= basePtsUs) basePtsUs = lastGlobalPtsUs + 500L;
}
if (aEx != null && mATrack != -1) {
long lastAudioPts = -1;
while (true) {
info.offset = 0;
info.size = aEx.readSampleData(buf, 0);
if (info.size < 0) break;
long aPts = aEx.getSampleTime();
if (aPts < 0) break;
if (aPts <= lastAudioPts) aPts = lastAudioPts + 100L;
lastAudioPts = aPts;
info.presentationTimeUs = aPts;
info.flags = aEx.getSampleFlags();
muxer.writeSampleData(mATrack, buf, info);
aEx.advance();
}
aEx.release();
aEx = null;
}
muxer.stop();
muxer.release();
muxer = null;
new File(progFile).delete();
return "SUKSES";
}
int dispW1 = (rots[0] == 90 || rots[0] == 270) ? heights[0] : widths[0];
int dispH1 = (rots[0] == 90 || rots[0] == 270) ? widths[0] : heights[0];
int outW = dispW1;
int outH = dispH1;
if (targetRes > 0) {
if (dispW1 <= dispH1) {
outW = targetRes;
outH = Math.round((float) dispH1 * targetRes / dispW1);
} else {
outH = targetRes;
outW = Math.round((float) dispW1 * targetRes / dispH1);
}
}
outW = Math.max(160, (outW / 16) * 16);
outH = Math.max(160, (outH / 16) * 16);
int videoBitrate = 3500000;
int maxDim = Math.max(outW, outH);
if (maxDim >= 1920) videoBitrate = 6000000;
else if (maxDim <= 864) videoBitrate = 2000000;
MediaFormat encFmt = MediaFormat.createVideoFormat("video/avc", outW, outH);
encFmt.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible);
encFmt.setInteger(MediaFormat.KEY_BIT_RATE, videoBitrate);
encFmt.setInteger(MediaFormat.KEY_FRAME_RATE, 30);
encFmt.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);
encoder = MediaCodec.createEncoderByType("video/avc");
encoder.configure(encFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
encoder.start();
muxer = new MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
int mVTrack = -1;
int mATrack = -1;
boolean muxStarted = false;
if (mergedAudioPath != null && !mergedAudioPath.isEmpty()) {
File af = new File(mergedAudioPath);
if (af.exists() && af.length() > 0) {
aEx = new MediaExtractor();
aEx.setDataSource(mergedAudioPath);
for (int t = 0; t < aEx.getTrackCount(); t++) {
MediaFormat fmt = aEx.getTrackFormat(t);
String am = fmt.getString(MediaFormat.KEY_MIME);
if (am != null && am.startsWith("audio/")) {
aEx.selectTrack(t);
mATrack = muxer.addTrack(fmt);
break;
}
}
}
}
MediaCodec.BufferInfo decInfo = new MediaCodec.BufferInfo();
MediaCodec.BufferInfo encInfo = new MediaCodec.BufferInfo();
long basePtsUs = 0;
long lastGlobalPtsUs = -1;
for (int i = 0; i < n; i++) {
MediaExtractor vEx = new MediaExtractor();
vEx.setDataSource(paths[i]);
MediaFormat inFmt = null;
for (int t = 0; t < vEx.getTrackCount(); t++) {
MediaFormat fmt = vEx.getTrackFormat(t);
String m = fmt.getString(MediaFormat.KEY_MIME);
if (m != null && m.startsWith("video/")) {
vEx.selectTrack(t);
inFmt = fmt;
break;
}
}
if (inFmt == null) {
vEx.release();
continue;
}
inFmt.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible);
MediaCodec decoder = MediaCodec.createDecoderByType(mimes[i]);
decoder.configure(inFmt, null, null, 0);
decoder.start();
boolean inEOS = false;
boolean outEOS = false;
long maxLocalPts = 0;
while (!outEOS) {
if (!inEOS) {
int inIdx = decoder.dequeueInputBuffer(10000);
if (inIdx >= 0) {
ByteBuffer inBuf = decoder.getInputBuffer(inIdx);
int sz = vEx.readSampleData(inBuf, 0);
if (sz < 0) {
decoder.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
inEOS = true;
} else {
long st = vEx.getSampleTime();
decoder.queueInputBuffer(inIdx, 0, sz, st, 0);
vEx.advance();
}
}
}
int outIdx = decoder.dequeueOutputBuffer(decInfo, 10000);
if (outIdx >= 0) {
boolean isEnd = (decInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
if (decInfo.size > 0) {
android.media.Image srcImg = decoder.getOutputImage(outIdx);
if (srcImg != null) {
int encInIdx = -1;
while (encInIdx < 0) {
encInIdx = encoder.dequeueInputBuffer(10000);
if (encInIdx < 0) {
while (true) {
int eOut = encoder.dequeueOutputBuffer(encInfo, 10000);
if (eOut == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
mVTrack = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (eOut >= 0) {
ByteBuffer eBuf = encoder.getOutputBuffer(eOut);
if (encInfo.size > 0 && muxStarted) {
eBuf.position(encInfo.offset);
eBuf.limit(encInfo.offset + encInfo.size);
muxer.writeSampleData(mVTrack, eBuf, encInfo);
}
encoder.releaseOutputBuffer(eOut, false);
} else {
break;
}
}
}
}
android.media.Image dstImg = encoder.getInputImage(encInIdx);
if (dstImg != null) {
tulisBingkaiYUV(srcImg, widths[i], heights[i], rots[i], dstImg, outW, outH);
dstImg.close();
}
srcImg.close();
long st = Math.max(0L, decInfo.presentationTimeUs);
if (st > maxLocalPts) maxLocalPts = st;
long pts = basePtsUs + st;
if (pts <= lastGlobalPtsUs) pts = lastGlobalPtsUs + 33333L;
lastGlobalPtsUs = pts;
ByteBuffer rawEncIn = encoder.getInputBuffer(encInIdx);
int queueSz = (rawEncIn != null && rawEncIn.capacity() > 0) ? rawEncIn.capacity() : (outW * outH * 3 / 2);
encoder.queueInputBuffer(encInIdx, 0, queueSz, pts, 0);
if (totalAllVideoUs > 0) {
int prog = (int) ((pts * 100L) / totalAllVideoUs);
if (prog > lastProgress && prog <= 100) {
lastProgress = prog;
try {
FileOutputStream pfos = new FileOutputStream(progFile);
pfos.write(String.valueOf(prog).getBytes()); laporUmum((int) (prog));
pfos.close();
} catch (Exception ignored) {}
}
}
}
}
decoder.releaseOutputBuffer(outIdx, false);
if (isEnd) outEOS = true;
}
while (true) {
int eOut = encoder.dequeueOutputBuffer(encInfo, 0);
if (eOut == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
mVTrack = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (eOut >= 0) {
ByteBuffer eBuf = encoder.getOutputBuffer(eOut);
if (encInfo.size > 0 && muxStarted) {
eBuf.position(encInfo.offset);
eBuf.limit(encInfo.offset + encInfo.size);
muxer.writeSampleData(mVTrack, eBuf, encInfo);
}
encoder.releaseOutputBuffer(eOut, false);
} else {
break;
}
}
}
decoder.stop();
decoder.release();
vEx.release();
long clipDur = Math.max(durs[i], maxLocalPts + 33333L);
basePtsUs += clipDur;
if (lastGlobalPtsUs >= basePtsUs) basePtsUs = lastGlobalPtsUs + 33333L;
}
int eosIdx = -1;
while (eosIdx < 0) {
eosIdx = encoder.dequeueInputBuffer(10000);
if (eosIdx >= 0) {
encoder.queueInputBuffer(eosIdx, 0, 0, Math.max(0L, lastGlobalPtsUs + 33333L), MediaCodec.BUFFER_FLAG_END_OF_STREAM);
} else {
while (true) {
int eOut = encoder.dequeueOutputBuffer(encInfo, 10000);
if (eOut == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
mVTrack = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (eOut >= 0) {
ByteBuffer eBuf = encoder.getOutputBuffer(eOut);
if (encInfo.size > 0 && muxStarted) {
eBuf.position(encInfo.offset);
eBuf.limit(encInfo.offset + encInfo.size);
muxer.writeSampleData(mVTrack, eBuf, encInfo);
}
encoder.releaseOutputBuffer(eOut, false);
} else {
break;
}
}
}
}
while (true) {
int eOut = encoder.dequeueOutputBuffer(encInfo, 10000);
if (eOut == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
mVTrack = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (eOut >= 0) {
ByteBuffer eBuf = encoder.getOutputBuffer(eOut);
if (encInfo.size > 0 && muxStarted) {
eBuf.position(encInfo.offset);
eBuf.limit(encInfo.offset + encInfo.size);
muxer.writeSampleData(mVTrack, eBuf, encInfo);
}
encoder.releaseOutputBuffer(eOut, false);
if ((encInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break;
} else if (eOut == MediaCodec.INFO_TRY_AGAIN_LATER) {
break;
}
}
encoder.stop();
encoder.release();
encoder = null;
if (aEx != null && mATrack != -1 && muxStarted) {
ByteBuffer aBuf = ByteBuffer.allocate(1048576);
MediaCodec.BufferInfo aInfo = new MediaCodec.BufferInfo();
long lastAudioPts = -1;
while (true) {
aInfo.offset = 0;
aInfo.size = aEx.readSampleData(aBuf, 0);
if (aInfo.size < 0) break;
long aPts = aEx.getSampleTime();
if (aPts < 0) break;
if (aPts <= lastAudioPts) aPts = lastAudioPts + 100L;
lastAudioPts = aPts;
aInfo.presentationTimeUs = aPts;
aInfo.flags = aEx.getSampleFlags();
muxer.writeSampleData(mATrack, aBuf, aInfo);
aEx.advance();
}
aEx.release();
aEx = null;
}
if (muxStarted) {
muxer.stop();
muxer.release();
muxer = null;
}
new File(progFile).delete();
return "SUKSES";
} catch (Exception e) {
if (encoder != null) try { encoder.stop(); encoder.release(); } catch (Exception ignored) {}
if (aEx != null) try { aEx.release(); } catch (Exception ignored) {}
if (muxer != null) try { muxer.stop(); muxer.release(); } catch (Exception ignored) {}
return "ERROR: " + e.getMessage();
}
}

private static android.graphics.Bitmap buatKanvasAudioKeVideo(int outW, int outH, String imagePath, String titleText) {
android.graphics.Bitmap canvasBmp = android.graphics.Bitmap.createBitmap(outW, outH, android.graphics.Bitmap.Config.ARGB_8888);
android.graphics.Canvas canvas = new android.graphics.Canvas(canvasBmp);
canvas.drawColor(0xFF12161F);
boolean gambarBerhasil = false;
if (imagePath != null && !imagePath.trim().isEmpty()) {
File imgFile = new File(imagePath.trim());
if (imgFile.exists() && imgFile.length() > 0) {
try {
android.graphics.BitmapFactory.Options opts = new android.graphics.BitmapFactory.Options();
opts.inJustDecodeBounds = true;
android.graphics.BitmapFactory.decodeFile(imgFile.getAbsolutePath(), opts);
int sampleSize = 1;
int maxReq = Math.max(outW, outH);
while ((opts.outWidth / sampleSize) > maxReq * 2 || (opts.outHeight / sampleSize) > maxReq * 2) {
sampleSize *= 2;
}
opts.inJustDecodeBounds = false;
opts.inSampleSize = sampleSize;
android.graphics.Bitmap srcBmp = android.graphics.BitmapFactory.decodeFile(imgFile.getAbsolutePath(), opts);
if (srcBmp != null) {
int bw = srcBmp.getWidth();
int bh = srcBmp.getHeight();
float scale = Math.min((float) outW / bw, (float) outH / bh);
float dw = bw * scale;
float dh = bh * scale;
float left = (outW - dw) / 2.0f;
float top = (outH - dh) / 2.0f;
android.graphics.Paint pBmp = new android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG);
canvas.drawBitmap(srcBmp, null, new android.graphics.RectF(left, top, left + dw, top + dh), pBmp);
srcBmp.recycle();
gambarBerhasil = true;
}
} catch (Exception ignored) {}
}
}
if (!gambarBerhasil) {
android.graphics.Paint pBox = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
pBox.setStyle(android.graphics.Paint.Style.STROKE);
pBox.setStrokeWidth(Math.max(2f, Math.min(outW, outH) * 0.006f));
pBox.setColor(0xFF2196F3);
float margin = Math.min(outW, outH) * 0.08f;
canvas.drawRect(margin, margin, outW - margin, outH - margin, pBox);
String judul = (titleText != null && !titleText.trim().isEmpty()) ? titleText.trim() : "Audio Nadi";
if (judul.length() > 60) judul = judul.substring(0, 57) + "...";
android.graphics.Paint pText = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
pText.setColor(0xFFFFFFFF);
pText.setTextAlign(android.graphics.Paint.Align.CENTER);
float baseTextSize = Math.max(18f, Math.min(outW, outH) * 0.055f);
pText.setTextSize(baseTextSize);
canvas.drawText(judul, outW / 2.0f, (outH / 2.0f) - (baseTextSize * 0.3f), pText);
pText.setColor(0xFF90CAF9);
pText.setTextSize(baseTextSize * 0.65f);
canvas.drawText("Perekam Nadi", outW / 2.0f, (outH / 2.0f) + (baseTextSize * 1.1f), pText);
}
return canvasBmp;
}

private static void salinCacheYUVKeImage(byte[] yArr, byte[] uArr, byte[] vArr, int outW, int outH, android.media.Image dstImg) {
android.media.Image.Plane[] planes = dstImg.getPlanes();
ByteBuffer dstY = planes[0].getBuffer();
ByteBuffer dstU = planes[1].getBuffer();
ByteBuffer dstV = planes[2].getBuffer();
int yRowStride = planes[0].getRowStride();
int yPixStride = planes[0].getPixelStride();
int uRowStride = planes[1].getRowStride();
int uPixStride = planes[1].getPixelStride();
int vRowStride = planes[2].getRowStride();
int vPixStride = planes[2].getPixelStride();
if (videoNativeSiap()) {
try {
int[] st = {yRowStride, yPixStride, uRowStride, uPixStride, vRowStride, vPixStride};
if (nvSalinYUV(yArr, uArr, vArr, outW, outH, dstY, dstU, dstV, st) == 1) return;
} catch (Throwable t) { videoNativeState = -1; }
}
int yCap = dstY.capacity();
if (yPixStride == 1) {
for (int y = 0; y < outH; y++) {
int dstOff = y * yRowStride;
if (dstOff + outW <= yCap) {
dstY.position(dstOff);
dstY.put(yArr, y * outW, outW);
}
}
} else {
for (int y = 0; y < outH; y++) {
int srcRow = y * outW;
int dstRow = y * yRowStride;
for (int x = 0; x < outW; x++) {
int idx = dstRow + x * yPixStride;
if (idx >= 0 && idx < yCap) dstY.put(idx, yArr[srcRow + x]);
}
}
}
int uvW = outW / 2;
int uvH = outH / 2;
int uCap = dstU.capacity();
int vCap = dstV.capacity();
for (int y = 0; y < uvH; y++) {
int srcRow = y * uvW;
int uDstRow = y * uRowStride;
int vDstRow = y * vRowStride;
for (int x = 0; x < uvW; x++) {
int uIdx = uDstRow + x * uPixStride;
int vIdx = vDstRow + x * vPixStride;
byte uVal = uArr[srcRow + x];
byte vVal = vArr[srcRow + x];
if (uIdx >= 0 && uIdx < uCap) dstU.put(uIdx, uVal);
if (vIdx >= 0 && vIdx < vCap) dstV.put(vIdx, vVal);
}
}
}

public static String audioKeVideo(String m4aAudioPath, String imagePath, String titleText, String outPath, int reqW, int reqH) {
tahap("Membuat video dari suara");
MediaExtractor aEx = null;
MediaCodec encoder = null;
MediaMuxer muxer = null;
try {
File aFile = new File(m4aAudioPath);
if (!aFile.exists() || aFile.length() <= 0) return "ERROR: File audio sumber tidak ditemukan.";
aEx = new MediaExtractor();
aEx.setDataSource(m4aAudioPath);
int aTrack = -1;
MediaFormat aFmt = null;
for (int i = 0; i < aEx.getTrackCount(); i++) {
MediaFormat fmt = aEx.getTrackFormat(i);
String mime = fmt.getString(MediaFormat.KEY_MIME);
if (mime != null && mime.startsWith("audio/")) {
aTrack = i;
aFmt = fmt;
break;
}
}
if (aTrack == -1 || aFmt == null) {
aEx.release();
return "ERROR: Tidak ada trek suara di dalam file.";
}
aEx.selectTrack(aTrack);
long durationUs = aFmt.containsKey(MediaFormat.KEY_DURATION) ? aFmt.getLong(MediaFormat.KEY_DURATION) : 0L;
if (durationUs <= 0) {
long maxSt = 0;
ByteBuffer tmpBuf = ByteBuffer.allocate(262144);
while (aEx.readSampleData(tmpBuf, 0) >= 0) {
long st = aEx.getSampleTime();
if (st > maxSt) maxSt = st;
aEx.advance();
}
durationUs = Math.max(1000000L, maxSt + 50000L);
aEx.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC);
}
int outW = Math.max(160, (reqW / 16) * 16);
int outH = Math.max(160, (reqH / 16) * 16);
android.graphics.Bitmap bmp = buatKanvasAudioKeVideo(outW, outH, imagePath, titleText);
int[] argb = new int[outW * outH];
bmp.getPixels(argb, 0, outW, 0, 0, outW, outH);
bmp.recycle();
byte[] yArr = new byte[outW * outH];
byte[] uArr = new byte[(outW / 2) * (outH / 2)];
byte[] vArr = new byte[(outW / 2) * (outH / 2)];
argbKeYuv(argb, outW, outH, yArr, uArr, vArr);
argb = null;
int maxDim = Math.max(outW, outH);
int videoBitrate = 1500000;
if (maxDim >= 1920) videoBitrate = 2500000;
else if (maxDim <= 640) videoBitrate = 800000;
MediaFormat encFmt = MediaFormat.createVideoFormat("video/avc", outW, outH);
encFmt.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible);
encFmt.setInteger(MediaFormat.KEY_BIT_RATE, videoBitrate);
encFmt.setInteger(MediaFormat.KEY_FRAME_RATE, 15);
encFmt.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2);
encoder = MediaCodec.createEncoderByType("video/avc");
encoder.configure(encFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
encoder.start();
muxer = new MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
int mATrack = muxer.addTrack(aFmt);
int mVTrack = -1;
boolean muxStarted = false;
long stepUs = 200000L;
long totalFrames = Math.max(2L, (durationUs / stepUs) + 1L);
long frameIdx = 0;
boolean inEOS = false;
boolean outEOS = false;
MediaCodec.BufferInfo encInfo = new MediaCodec.BufferInfo();
String progFile = outPath + ".prog";
int lastProgress = 0;
while (!outEOS) {
if (!inEOS) {
int inIdx = encoder.dequeueInputBuffer(10000);
if (inIdx >= 0) {
if (frameIdx >= totalFrames) {
encoder.queueInputBuffer(inIdx, 0, 0, durationUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
inEOS = true;
} else {
android.media.Image dstImg = encoder.getInputImage(inIdx);
if (dstImg != null) {
salinCacheYUVKeImage(yArr, uArr, vArr, outW, outH, dstImg);
dstImg.close();
}
long ptsUs = Math.min(durationUs, frameIdx * stepUs);
ByteBuffer rawIn = encoder.getInputBuffer(inIdx);
int queueSz = (rawIn != null && rawIn.capacity() > 0) ? rawIn.capacity() : (outW * outH * 3 / 2);
encoder.queueInputBuffer(inIdx, 0, queueSz, ptsUs, 0);
frameIdx++;
int prog = (int) ((frameIdx * 90L) / totalFrames);
if (prog > lastProgress && prog <= 90) {
lastProgress = prog;
try {
FileOutputStream pfos = new FileOutputStream(progFile);
pfos.write(String.valueOf(prog).getBytes()); laporUmum((int) (prog));
pfos.close();
} catch (Exception ignored) {}
}
}
}
}
while (true) {
int outIdx = encoder.dequeueOutputBuffer(encInfo, 10000);
if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
mVTrack = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (outIdx >= 0) {
ByteBuffer outBuf = encoder.getOutputBuffer(outIdx);
if (encInfo.size > 0 && muxStarted) {
outBuf.position(encInfo.offset);
outBuf.limit(encInfo.offset + encInfo.size);
muxer.writeSampleData(mVTrack, outBuf, encInfo);
}
encoder.releaseOutputBuffer(outIdx, false);
if ((encInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
outEOS = true;
break;
}
} else {
break;
}
}
}
encoder.stop();
encoder.release();
encoder = null;
if (muxStarted && mATrack != -1) {
ByteBuffer aBuf = ByteBuffer.allocate(1048576);
MediaCodec.BufferInfo aInfo = new MediaCodec.BufferInfo();
long lastAudioPts = -1;
while (true) {
aInfo.offset = 0;
aInfo.size = aEx.readSampleData(aBuf, 0);
if (aInfo.size < 0) break;
long aPts = aEx.getSampleTime();
if (aPts < 0) break;
if (aPts <= lastAudioPts) aPts = lastAudioPts + 100L;
lastAudioPts = aPts;
aInfo.presentationTimeUs = aPts;
aInfo.flags = aEx.getSampleFlags();
muxer.writeSampleData(mATrack, aBuf, aInfo);
aEx.advance();
}
}
aEx.release();
aEx = null;
if (muxStarted) {
muxer.stop();
muxer.release();
muxer = null;
}
new File(progFile).delete();
return "SUKSES";
} catch (Exception e) {
if (encoder != null) try { encoder.stop(); encoder.release(); } catch (Exception ignored) {}
if (aEx != null) try { aEx.release(); } catch (Exception ignored) {}
if (muxer != null) try { muxer.stop(); muxer.release(); } catch (Exception ignored) {}
return "ERROR: " + e.getMessage();
}
}

private static class SegmenEfek {
long byteStart;
long byteEnd;
boolean hasPitch;
float pitchSemitone;
boolean pitchLanjut;
boolean pitchGl;
float pitchG0, pitchG1, pitchGd;
boolean hasAutoTune;
boolean hasSuaraDua;
SuaraDuaCfg sdCfg;
boolean hasSensor;
int snKind;
float snFreq;
float snVol;
float snMix;
long snFadeFrames;
int atKey;
int atScale;
float atSpeed;
NoiseGate[] gates;
Tone[] tones;
Echo[] echos;
Freeverb[] fvs;
}

// =====================================================================
//  SUARA DUA  (mesin C++ libnadivoice, dimuat lewat System.load)
//  Konfigurasi satu baris: aktif,s2,l2,d2,p2,on3,s3,l3,d3,p3,dry,fo,nat
//    s = interval nada (semiton), l = volume 0..1, d = tunda (ms), p = posisi -1..1
// =====================================================================
// Laporan kemajuan umum: satu berkas bersama yang dibaca tampilan ("persen|nama tahap")
private static String tahapProg = "Memproses";
private static void tahap(String nama) {
    tahapProg = nama;
    laporUmum(0);
}
private static void laporUmum(int persen) {
    try {
        String f = System.getProperty("nadi.prog.file");
        if (f == null || f.isEmpty()) return;
        if (persen < 0) persen = 0;
        if (persen > 100) persen = 100;
        FileOutputStream o = new FileOutputStream(f);
        o.write((persen + "|" + tahapProg).getBytes("UTF-8"));
        o.close();
    } catch (Exception ignored) {}
}

// Bunyi pengganti sensor pada posisi frameRel (hasil -1..1), dihitung langsung dari rumus gelombang
private static float bunyiSensor(int kind, float freq, long frameRel, int chIdx, int sampleRate) {
    double t = (double) frameRel / (double) sampleRate;
    switch (kind) {
        case 1: // beep: gelombang sinus murni
            return (float) Math.sin(2.0 * Math.PI * (double) freq * t);
        case 3: { // derau putih (acak semu yang selalu sama untuk posisi yang sama)
            long h = frameRel * 2654435761L + (long) chIdx * 40503L + 12345L;
            h ^= (h >>> 15);
            h *= 2246822519L;
            h ^= (h >>> 13);
            h *= 3266489917L;
            h ^= (h >>> 16);
            return (float) (((double) (h & 0xFFFFL) / 32767.5) - 1.0);
        }
        case 4: { // dengung: nada rendah dengan satu nada tambahan di atasnya
            double w = 2.0 * Math.PI * (double) freq * t;
            return (float) (0.7 * Math.sin(w) + 0.3 * Math.sin(2.0 * w));
        }
        default: // 2 = sunyi
            return 0f;
    }
}

// Nada (semiton) pada waktu tertentu untuk pergeseran bertahap
private static float semitonGeser(boolean gl, float tetap, float g0, float g1, float gd, long frameSelesai, long frameTotal, int sampleRate) {
    if (!gl) return tetap;
    double t = (double) frameSelesai / (double) sampleRate;
    double dur = (gd > 0f) ? (double) gd : ((double) frameTotal / (double) sampleRate);
    double u = (dur > 0.001) ? t / dur : 1.0;
    if (u < 0.0) u = 0.0;
    if (u > 1.0) u = 1.0;
    return (float) ((double) g0 + ((double) g1 - (double) g0) * u);
}

private static native int nadiVersi();
private static native int nadiJalankan();
// Mesin video C++ (nadivoice versi 4 ke atas): pekerjaan per piksel pada bingkai video.
// Semuanya mengembalikan 1 bila berhasil. Bila 0 atau terjadi galat, Java mengerjakan sendiri.
private static native int nvBingkaiYUV(ByteBuffer sY, ByteBuffer sU, ByteBuffer sV, ByteBuffer dY, ByteBuffer dU, ByteBuffer dV, int[] p);
private static native int nvSalinYUV(byte[] y, byte[] u, byte[] v, int outW, int outH, ByteBuffer dY, ByteBuffer dU, ByteBuffer dV, int[] s);
private static native int nvArgbKeYuv(int[] argb, int w, int h, byte[] y, byte[] u, byte[] v);
private static native int nvCampurPCM(byte[] bN, byte[] bI, byte[] bO, int nF, int ch, long curF, long dInstF, long fInF, long fOutF, long totFrames, float vNar, float vInst);
private static native long nvRantaiBuat(long[] segL, double[] segD, int channels, int sampleRate);
private static native int nvRantaiProses(long handle, byte[] in, int read, byte[] out, long basePos);
private static native int nvRantaiLepas(long handle);
// Mesin nada langsung (nadivoice versi 9 ke atas): suara digeser nadanya blok demi blok saat diputar
private static native long nvLiveBuat(byte[] jalur, int sampleRate);
private static native int nvLiveAnalisis(long h);
private static native int nvLiveProgres(long h);
private static native void nvLiveBatal(long h);
private static native int nvLiveInfo(long h, int apa);
private static native int nvLiveKontur(long h, float[] v, int jumlah);
private static native int nvLiveMulai(long h, long posSampel);
private static native int nvLiveRender(long h, byte[] out, int nSampel, int flags);
private static native long nvLivePosisi(long h);
private static native int nvLiveLepas(long h);
// Suara Dua langsung (nadivoice versi 10 ke atas)
private static native int nvSdAtur(long h, float[] p, int n);
private static native int nvSdMulai(long h, long posSampel);
private static native int nvSdRender(long h, byte[] out, int nSampel, int ch, int flags);
// Bass & Treble dan Ekualiser langsung (nadivoice versi 11 ke atas): filter berjalan blok demi blok saat diputar
private static native long nvEqBuat(int sampleRate, int ch);
private static native int nvEqAtur(long h, float[] p, int n);
private static native int nvEqReset(long h);
private static native int nvEqProses(long h, byte[] pcm, int nBingkai);
private static native int nvEqLepas(long h);
// Pengurang Kebisingan (noise gate) langsung (nadivoice versi 12 ke atas)
private static native long nvGateBuat(int sampleRate, int ch);
private static native int nvGateAtur(long h, float[] p, int n);
private static native int nvGateReset(long h);
private static native int nvGateProses(long h, byte[] pcm, int nBingkai);
private static native int nvGateLepas(long h);
// Reverb dan Echo langsung (nadivoice versi 13 ke atas), mono. kind 1 = reverb, 2 = echo
private static native long nvFxBuat(int kind, int sampleRate);
private static native int nvFxAtur(long h, float[] p, int n);
private static native int nvFxReset(long h);
private static native int nvFxProses(long h, byte[] pcm, int nBingkai);
private static native int nvFxLepas(long h);
// AutoTune langsung (nadivoice versi 14 ke atas), mono. p = {kunci 0..11, tangga nada 0..2, kecepatan 1..100}
private static native long nvAtBuat(int sampleRate);
private static native int nvAtAtur(long h, float[] p, int n);
private static native int nvAtReset(long h);
private static native int nvAtProses(long h, byte[] pcm, int nBingkai);
private static native int nvAtLepas(long h);
private static int rantaiNativeState = 0; // 0 belum dicek, 1 dipakai, -1 Java
private static int campurNativeState = 0; // 0 belum dicek, 1 dipakai, -1 Java
private static int videoNativeState = 0; // 0 belum dicek, 1 dipakai, -1 tidak dipakai (Java)
private static boolean nadiSiap = false;
private static int nadiVer = 0;
private static String nadiPesan = "";

private static class SuaraDuaCfg {
    boolean ada = false;
    boolean[] use = new boolean[3];
    float[] semi = new float[3];
    float[] level = new float[3];
    float[] delay = new float[3];
    float[] pan = new float[3];
    float dry = 1.0f, fo = 0.0f, nat = 0.5f;
    float unv = 0.6f;
    boolean glOn = false;
    float glS0 = 0f, glS1 = 0f, glDur = 0f;

    // Konfigurasi untuk Mode Nada Tingkat Lanjut: suara asli diganti oleh versi yang digeser nadanya
    static SuaraDuaCfg untukPitch(float semi, boolean gl, float g0, float g1, float gd) {
        SuaraDuaCfg c = new SuaraDuaCfg();
        c.ada = true;
        c.use[0] = true;
        c.semi[0] = semi;
        c.level[0] = 1.0f;
        c.delay[0] = 0f;
        c.pan[0] = 0f;
        c.dry = 0f;
        c.fo = 0f;
        c.nat = 0f;
        c.unv = 1.0f;
        c.glOn = gl;
        c.glS0 = g0;
        c.glS1 = g1;
        c.glDur = gd;
        return c;
    }

    static SuaraDuaCfg parse(String line) {
        SuaraDuaCfg c = new SuaraDuaCfg();
        try {
            if (line == null) return c;
            String[] p = line.trim().split(",");
            if (p.length < 13) return c;
            if (Integer.parseInt(p[0].trim()) != 1) return c;
            c.use[0] = true;
            c.semi[0] = Float.parseFloat(p[1].trim());
            c.level[0] = Float.parseFloat(p[2].trim());
            c.delay[0] = Float.parseFloat(p[3].trim());
            c.pan[0] = Float.parseFloat(p[4].trim());
            if (Integer.parseInt(p[5].trim()) == 1) {
                c.use[1] = true;
                c.semi[1] = Float.parseFloat(p[6].trim());
                c.level[1] = Float.parseFloat(p[7].trim());
                c.delay[1] = Float.parseFloat(p[8].trim());
                c.pan[1] = Float.parseFloat(p[9].trim());
            }
            c.dry = Float.parseFloat(p[10].trim());
            c.fo = Float.parseFloat(p[11].trim());
            c.nat = Float.parseFloat(p[12].trim());
            c.ada = true;
        } catch (Exception e) {
            c.ada = false;
        }
        return c;
    }
}

private static synchronized boolean muatNativeSuaraDua() {
    if (nadiSiap) return true;
    try {
        String so = System.getProperty("nadi.so.file");
        String cache = System.getProperty("nadi.so.cache");
        if (so == null || so.trim().isEmpty()) {
            nadiPesan = "Mesin pengubah suara belum siap";
            android.util.Log.w("NadiMesin", "properti nadi.so.file belum diatur");
            return false;
        }
        File src = new File(so);
        if (!src.exists()) {
            nadiPesan = "Mesin pengubah suara belum siap";
            android.util.Log.w("NadiMesin", "berkas tidak ditemukan: " + so);
            return false;
        }
        File dir = new File((cache != null && !cache.isEmpty()) ? cache : System.getProperty("java.io.tmpdir"));
        dir.mkdirs();
        long now = System.currentTimeMillis();
        File[] lama = dir.listFiles();
        if (lama != null) {
            for (File f : lama) {
                String nm = f.getName();
                if (nm.startsWith("nadivoice_") && nm.endsWith(".so") && now - f.lastModified() > 120000L) {
                    f.delete();
                }
            }
        }
        // Salinan unik per pemuatan: Android menolak memuat jalur yang sama di dua ClassLoader berbeda
        File dst = new File(dir, "nadivoice_" + System.nanoTime() + ".so");
        FileInputStream in = new FileInputStream(src);
        FileOutputStream out = new FileOutputStream(dst);
        byte[] buf = new byte[65536];
        int r;
        while ((r = in.read(buf)) > 0) out.write(buf, 0, r);
        out.close();
        in.close();
        try { dst.setReadOnly(); } catch (Exception ignored) {}
        System.load(dst.getAbsolutePath());
        int v = nadiVersi();
        if (v < 1) {
            nadiPesan = "Mesin pengubah suara belum siap";
            android.util.Log.w("NadiMesin", "versi tidak cocok: " + v);
            return false;
        }
        nadiSiap = true;
        nadiVer = v;
        nadiPesan = "";
        return true;
    } catch (Throwable t) {
        nadiPesan = "Mesin pengubah suara belum siap";
        android.util.Log.w("NadiMesin", "gagal memuat: " + t);
        return false;
    }
}

private static synchronized boolean videoNativeSiap() {
    if (videoNativeState != 0) return videoNativeState == 1;
    boolean ok = false;
    try { ok = muatNativeSuaraDua() && nadiVer >= 4; } catch (Throwable t) { ok = false; }
    videoNativeState = ok ? 1 : -1;
    if (!ok) android.util.Log.w("NadiMesin", "mesin video C++ tidak dipakai, memakai Java");
    return ok;
}

private static synchronized boolean rantaiNativeSiap() {
    if (rantaiNativeState != 0) return rantaiNativeState == 1;
    boolean ok = false;
    try { ok = muatNativeSuaraDua() && nadiVer >= 6; } catch (Throwable t) { ok = false; }
    rantaiNativeState = ok ? 1 : -1;
    return ok;
}

// Menyerahkan parameter efek (yang sudah dihitung Java) ke mesin C++. Mengembalikan 0 bila tidak bisa.
private static long buatRantaiNative(SegmenEfek[] segs, int channels, int sampleRate, int frameSize) {
    int n = segs.length;
    long[] sl = new long[n * 6];
    double[] d = new double[n * 130 + 8];
    int p = 0;
    for (int s = 0; s < n; s++) {
        SegmenEfek sg = segs[s];
        int fl = 0;
        if (sg.gates != null) fl |= 1;
        if (sg.tones != null) fl |= 2;
        if (sg.echos != null) fl |= 4;
        if (sg.fvs != null) fl |= 8;
        if (sg.hasSensor) fl |= 16;
        sl[s * 6] = sg.byteStart;
        sl[s * 6 + 1] = sg.byteEnd;
        sl[s * 6 + 2] = fl;
        sl[s * 6 + 3] = sg.snKind;
        sl[s * 6 + 4] = sg.snFadeFrames;
        sl[s * 6 + 5] = (sg.byteEnd - sg.byteStart) / frameSize;
        if (sg.gates != null) {
            for (int c = 0; c < channels; c++) {
                NoiseGate g = sg.gates[c];
                d[p++] = g.threshold; d[p++] = g.attackCoef; d[p++] = g.releaseCoef;
            }
        }
        if (sg.tones != null) {
            for (int c = 0; c < channels; c++) {
                Tone t = sg.tones[c];
                d[p++] = t.count;
                for (int i = 0; i < t.count; i++) {
                    Tone.Biquad q = t.stages[i];
                    d[p++] = q.b0; d[p++] = q.b1; d[p++] = q.b2; d[p++] = q.a1; d[p++] = q.a2;
                }
            }
        }
        if (sg.echos != null) {
            for (int c = 0; c < channels; c++) {
                Echo e = sg.echos[c];
                d[p++] = e.delaySamples; d[p++] = e.feedback; d[p++] = e.damping; d[p++] = e.dry; d[p++] = e.wet;
            }
        }
        if (sg.fvs != null) {
            for (int c = 0; c < channels; c++) {
                Freeverb f = sg.fvs[c];
                for (int i = 0; i < 8; i++) d[p++] = f.combs[i].buffer.length;
                for (int i = 0; i < 4; i++) d[p++] = f.allpasses[i].buffer.length;
                d[p++] = f.combs[0].feedback; d[p++] = f.combs[0].damp1; d[p++] = f.combs[0].damp2;
                d[p++] = f.wet; d[p++] = f.dry;
            }
        }
        if (sg.hasSensor) {
            d[p++] = sg.snFreq; d[p++] = sg.snVol; d[p++] = sg.snMix;
        }
    }
    return nvRantaiBuat(sl, d, channels, sampleRate);
}

private static int sonicNativeState = 0; // 0 belum dicek, 1 dipakai, -1 Java
private static synchronized boolean sonicNativeSiap() {
    if (sonicNativeState != 0) return sonicNativeState == 1;
    boolean ok = false;
    try { ok = muatNativeSuaraDua() && nadiVer >= 7; } catch (Throwable t) { ok = false; }
    sonicNativeState = ok ? 1 : -1;
    return ok;
}

// Menjalankan satu tugas teks di mesin C++. Mengembalikan true bila hasilnya "OK".
private static boolean jalankanJobMentah(String isi) {
    File job = null;
    File res = null;
    try {
        String cache = System.getProperty("nadi.so.cache");
        File dir = new File((cache != null && !cache.isEmpty()) ? cache : System.getProperty("java.io.tmpdir"));
        dir.mkdirs();
        job = new File(dir, "nadi_job_" + System.nanoTime() + ".txt");
        res = new File(job.getAbsolutePath() + ".res");
        FileOutputStream fos = new FileOutputStream(job);
        fos.write(isi.getBytes("UTF-8"));
        fos.close();
        int rc;
        synchronized (Runtime.getRuntime()) {
            android.system.Os.setenv("NADI_JOB", job.getAbsolutePath(), true);
            rc = nadiJalankan();
        }
        String hasil = "";
        if (res.exists()) {
            BufferedReader br = new BufferedReader(new FileReader(res));
            String l = br.readLine();
            br.close();
            if (l != null) hasil = l.trim();
        }
        return rc == 0 && "OK".equals(hasil);
    } catch (Throwable t) {
        return false;
    } finally {
        if (job != null) job.delete();
        if (res != null) res.delete();
    }
}

// AutoTune di C++ (setara AutoTune.prosesRafKeFile). inLen <= 0 berarti sampai akhir berkas.
private static boolean autoTuneNative(String inPath, long inOff, long inLen, File out, int outHdr, int sr, int ch, int key, int scale, float speed) {
    StringBuilder sb = new StringBuilder();
    sb.append("mode=1\n");
    sb.append("in=").append(inPath).append("\n");
    sb.append("out=").append(out.getAbsolutePath()).append("\n");
    sb.append("sr=").append(sr).append("\n");
    sb.append("ch=").append(ch).append("\n");
    sb.append("inoff=").append(inOff).append("\n");
    sb.append("inlen=").append(inLen).append("\n");
    sb.append("outhdr=").append(outHdr).append("\n");
    sb.append("atkey=").append(key).append("\n");
    sb.append("atscale=").append(scale).append("\n");
    sb.append("atspeed=").append(Float.toString(speed)).append("\n");
    boolean ok = jalankanJobMentah(sb.toString());
    if (!ok) { try { out.delete(); } catch (Throwable ignored) {} }
    return ok;
}

// Pergeseran nada Sonic di C++ (tetap atau bertahap). limit > 0 membatasi jumlah byte keluaran.
private static boolean sonicNative(String inPath, long inOff, long inLen, File out, int outHdr, int sr, int ch, float ratio, boolean gl, float g0, float g1, float gd, long totFrames, long limit) {
    StringBuilder sb = new StringBuilder();
    sb.append("mode=2\n");
    sb.append("in=").append(inPath).append("\n");
    sb.append("out=").append(out.getAbsolutePath()).append("\n");
    sb.append("sr=").append(sr).append("\n");
    sb.append("ch=").append(ch).append("\n");
    sb.append("inoff=").append(inOff).append("\n");
    sb.append("inlen=").append(inLen).append("\n");
    sb.append("outhdr=").append(outHdr).append("\n");
    sb.append("limit=").append(limit).append("\n");
    sb.append("totfr=").append(totFrames).append("\n");
    sb.append("pratio=").append(Float.toString(ratio)).append("\n");
    if (gl) sb.append("gl=1,").append(Float.toString(g0)).append(",").append(Float.toString(g1)).append(",").append(Float.toString(gd)).append("\n");
    boolean ok = jalankanJobMentah(sb.toString());
    if (!ok) { try { out.delete(); } catch (Throwable ignored) {} }
    return ok;
}

private static synchronized boolean campurNativeSiap() {
    if (campurNativeState != 0) return campurNativeState == 1;
    boolean ok = false;
    try { ok = muatNativeSuaraDua() && nadiVer >= 5; } catch (Throwable t) { ok = false; }
    campurNativeState = ok ? 1 : -1;
    return ok;
}

// Dipanggil Lua: apakah mesin cukup baru untuk pemrosesan video di C++ (versi 4 ke atas)?
public static String mesinVideoSiap() {
    if (!muatNativeSuaraDua()) return nadiPesan.isEmpty() ? "Mesin pengubah suara belum siap" : nadiPesan;
    if (nadiVer < 4) return "Mesin pengubah suara perlu diperbarui";
    return "SIAP";
}

// Mengubah piksel ARGB menjadi bidang Y, U, V (YUV420). Memakai C++ bila siap, bila tidak memakai Java.
private static void argbKeYuv(int[] argb, int outW, int outH, byte[] yArr, byte[] uArr, byte[] vArr) {
    if (videoNativeSiap()) {
        try {
            if (nvArgbKeYuv(argb, outW, outH, yArr, uArr, vArr) == 1) return;
        } catch (Throwable t) { videoNativeState = -1; }
    }
    int uvW = outW / 2;
    for (int j = 0; j < outH; j++) {
        int rowOff = j * outW;
        boolean evenRow = (j % 2 == 0);
        int uvRowOff = (j / 2) * uvW;
        for (int i = 0; i < outW; i++) {
            int c = argb[rowOff + i];
            int r = (c >> 16) & 0xFF;
            int g = (c >> 8) & 0xFF;
            int b = c & 0xFF;
            int y = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
            yArr[rowOff + i] = (byte) (y < 0 ? 0 : (y > 255 ? 255 : y));
            if (evenRow && (i % 2 == 0)) {
                int u = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
                int v = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
                int uvIdx = uvRowOff + (i / 2);
                uArr[uvIdx] = (byte) (u < 0 ? 0 : (u > 255 ? 255 : u));
                vArr[uvIdx] = (byte) (v < 0 ? 0 : (v > 255 ? 255 : v));
            }
        }
    }
}

// Dipanggil Lua untuk memeriksa apakah mesin Suara Dua siap. Hasil: "SIAP" atau pesan galat.
public static String suaraDuaSiap() {
    if (muatNativeSuaraDua()) return "SIAP";
    return nadiPesan.isEmpty() ? "Mesin pengubah suara belum siap" : nadiPesan;
}

// Dipanggil Lua: apakah mesin cukup baru untuk Mode Nada Tingkat Lanjut (versi 2 ke atas)?
public static String pitchLanjutSiap() {
    if (!muatNativeSuaraDua()) return nadiPesan.isEmpty() ? "Mesin pengubah suara belum siap" : nadiPesan;
    if (nadiVer < 2) return "Mesin pengubah suara perlu diperbarui";
    return "SIAP";
}

private static String jalankanSuaraDua(String inPath, String outPath, int hdr, int outHdr, int sampleRate, int channels, SuaraDuaCfg sd, String progPath) {
    if (!muatNativeSuaraDua()) return "ERROR: " + nadiPesan;
    File job = null;
    File res = null;
    try {
        String cache = System.getProperty("nadi.so.cache");
        File dir = new File((cache != null && !cache.isEmpty()) ? cache : System.getProperty("java.io.tmpdir"));
        dir.mkdirs();
        job = new File(dir, "nadi_job_" + System.nanoTime() + ".txt");
        res = new File(job.getAbsolutePath() + ".res");
        StringBuilder sb = new StringBuilder();
        sb.append("in=").append(inPath).append("\n");
        sb.append("out=").append(outPath).append("\n");
        String progUmum = System.getProperty("nadi.prog.file");
        if (progPath != null && !progPath.isEmpty()) sb.append("prog=").append(progPath).append("\n");
        else if (progUmum != null && !progUmum.isEmpty()) {
            sb.append("prog=").append(progUmum).append("\n");
            sb.append("plabel=").append(tahapProg).append("\n");
        }
        sb.append("sr=").append(sampleRate).append("\n");
        sb.append("ch=").append(channels).append("\n");
        sb.append("hdr=").append(hdr).append("\n");
        sb.append("outhdr=").append(outHdr).append("\n");
        sb.append("dry=").append(String.format(java.util.Locale.US, "%.4f", sd.dry)).append("\n");
        sb.append("fo=").append(String.format(java.util.Locale.US, "%.4f", sd.fo)).append("\n");
        sb.append("nat=").append(String.format(java.util.Locale.US, "%.4f", sd.nat)).append("\n");
        sb.append("unv=").append(String.format(java.util.Locale.US, "%.4f", sd.unv)).append("\n");
        if (sd.glOn) {
            sb.append("gl=1,").append(String.format(java.util.Locale.US, "%.4f,%.4f,%.4f", sd.glS0, sd.glS1, sd.glDur)).append("\n");
        }
        for (int i = 0; i < 3; i++) {
            if (!sd.use[i]) continue;
            sb.append("v").append(i + 1).append("=")
              .append(String.format(java.util.Locale.US, "%.4f,%.4f,%.4f,%.4f", sd.semi[i], sd.level[i], sd.delay[i], sd.pan[i]))
              .append("\n");
        }
        FileOutputStream fos = new FileOutputStream(job);
        fos.write(sb.toString().getBytes("UTF-8"));
        fos.close();
        int rc;
        synchronized (Runtime.getRuntime()) {
            android.system.Os.setenv("NADI_JOB", job.getAbsolutePath(), true);
            rc = nadiJalankan();
        }
        String hasil = "";
        if (res.exists()) {
            BufferedReader br = new BufferedReader(new FileReader(res));
            String l = br.readLine();
            br.close();
            if (l != null) hasil = l.trim();
        }
        if (rc == 0 && "OK".equals(hasil)) return "OK";
        return hasil.isEmpty() ? ("ERROR: kode " + rc) : hasil;
    } catch (Throwable t) {
        return "ERROR: " + t.getMessage();
    } finally {
        if (job != null) job.delete();
        if (res != null) res.delete();
    }
}

// Memproses sebuah rentang byte (tanpa header) di dalam RandomAccessFile; hasilnya ditulis kembali di tempat yang sama.
private static boolean suaraDuaRentangDiTempat(RandomAccessFile raf, long off, long len, String tmpBase, int sampleRate, int channels, SuaraDuaCfg sd) {
    File tin = new File(tmpBase + ".sdin.raw");
    File tout = new File(tmpBase + ".sdout.raw");
    try {
        raf.seek(off);
        FileOutputStream fo = new FileOutputStream(tin);
        byte[] buf = new byte[32768];
        long rem = len;
        while (rem > 0) {
            int tr = (int) Math.min((long) buf.length, rem);
            int r = raf.read(buf, 0, tr);
            if (r <= 0) break;
            fo.write(buf, 0, r);
            rem -= r;
        }
        fo.close();
        String r = jalankanSuaraDua(tin.getAbsolutePath(), tout.getAbsolutePath(), 0, 0, sampleRate, channels, sd, null);
        if (!"OK".equals(r) || tout.length() < len) return false;
        raf.seek(off);
        FileInputStream fi = new FileInputStream(tout);
        long back = len;
        while (back > 0) {
            int tr = (int) Math.min((long) buf.length, back);
            int rr = fi.read(buf, 0, tr);
            if (rr <= 0) break;
            raf.write(buf, 0, rr);
            back -= rr;
        }
        fi.close();
        return true;
    } catch (Throwable t) {
        return false;
    } finally {
        tin.delete();
        tout.delete();
    }
}

public static String terapkanEfekSegmen(String rawPcmPath, String configData, String outPath, int format, int sampleRate, int channels, int bitrate, float clipStartMs, float clipEndMs) {
tahap("Menerapkan efek suara");
RandomAccessFile rafIn = null;
File workFile = null;
MediaCodec encoder = null;
MediaMuxer muxer = null;
try {
File inFile = new File(rawPcmPath);
if (!inFile.exists()) return "ERROR: File PCM sumber tidak ditemukan.";
int frameSize = channels * 2;
long bytesPerSec = (long) sampleRate * frameSize;
double bytesPerMs = (double) bytesPerSec / 1000.0;
rafIn = new RandomAccessFile(inFile, "r");
long headerOffset = 0;
if (inFile.length() >= 44) {
byte[] magic = new byte[4];
rafIn.read(magic);
if (magic[0] == 'R' && magic[1] == 'I' && magic[2] == 'F' && magic[3] == 'F') {
headerOffset = 44;
}
}
long totalAudioBytes = inFile.length() - headerOffset;
totalAudioBytes -= (totalAudioBytes % frameSize);
if (totalAudioBytes <= 0) {
rafIn.close();
return "ERROR: File audio kosong.";
}
long sliceStartByte = 0;
long sliceEndByte = totalAudioBytes;
if (clipEndMs > clipStartMs && clipEndMs > 0f) {
sliceStartByte = Math.round(clipStartMs * bytesPerMs);
sliceStartByte -= (sliceStartByte % frameSize);
sliceEndByte = Math.round(clipEndMs * bytesPerMs);
sliceEndByte -= (sliceEndByte % frameSize);
if (sliceStartByte < 0) sliceStartByte = 0;
if (sliceEndByte > totalAudioBytes) sliceEndByte = totalAudioBytes;
if (sliceStartByte >= sliceEndByte) {
sliceStartByte = 0;
sliceEndByte = Math.min(totalAudioBytes, bytesPerSec * 5);
}
}
String[] lines = (configData != null && !configData.trim().isEmpty()) ? configData.trim().split("\n") : new String[0];
java.util.ArrayList<SegmenEfek> segList = new java.util.ArrayList<SegmenEfek>();
boolean butuhPitchKerja = false;
for (int l = 0; l < lines.length; l++) {
String line = lines[l].trim();
if (line.isEmpty()) continue;
String[] cols = line.split("\\|");
if (cols.length < 7) continue;
float sMs = Float.parseFloat(cols[0].trim());
float eMs = Float.parseFloat(cols[1].trim());
long bStart = Math.round(sMs * bytesPerMs);
bStart -= (bStart % frameSize);
long bEnd = (eMs <= 0f) ? totalAudioBytes : Math.round(eMs * bytesPerMs);
bEnd -= (bEnd % frameSize);
if (bStart < 0) bStart = 0;
if (bEnd > totalAudioBytes) bEnd = totalAudioBytes;
if (bStart >= bEnd) continue;
SegmenEfek seg = new SegmenEfek();
seg.byteStart = bStart;
seg.byteEnd = bEnd;
String[] gParts = cols[2].trim().split(",");
if (gParts.length >= 4 && Integer.parseInt(gParts[0].trim()) == 1) {
float gTh = Float.parseFloat(gParts[1].trim());
float gAtt = Float.parseFloat(gParts[2].trim());
float gRel = Float.parseFloat(gParts[3].trim());
if (gTh > 0f) {
seg.gates = new NoiseGate[channels];
for (int c = 0; c < channels; c++) seg.gates[c] = new NoiseGate(sampleRate, gTh, gAtt, gRel);
}
}
String[] pParts = cols[3].trim().split(",");
if (pParts.length >= 2 && Integer.parseInt(pParts[0].trim()) == 1) {
float semi = Float.parseFloat(pParts[1].trim());
boolean segExt = (pParts.length >= 7);
boolean segLanjut = segExt && "1".equals(pParts[2].trim());
boolean segGl = segExt && "1".equals(pParts[3].trim());
if (Math.abs(semi) >= 0.05f || segGl) {
seg.hasPitch = true;
seg.pitchSemitone = semi;
if (segExt) {
seg.pitchLanjut = segLanjut;
seg.pitchGl = segGl;
seg.pitchG0 = Float.parseFloat(pParts[4].trim());
seg.pitchG1 = Float.parseFloat(pParts[5].trim());
seg.pitchGd = Float.parseFloat(pParts[6].trim());
}
if (seg.byteEnd > sliceStartByte && seg.byteStart < sliceEndByte) {
butuhPitchKerja = true;
}
}
}
String[] rParts = cols[4].trim().split(",");
if (rParts.length >= 5 && Integer.parseInt(rParts[0].trim()) == 1) {
float rRoom = Float.parseFloat(rParts[1].trim());
float rDamp = Float.parseFloat(rParts[2].trim());
float rDry = Float.parseFloat(rParts[3].trim());
float rWet = Float.parseFloat(rParts[4].trim());
float rStereo = 0f;
if (rParts.length >= 6) rStereo = Math.max(0f, Math.min(1f, Float.parseFloat(rParts[5].trim())));
seg.fvs = new Freeverb[channels];
for (int c = 0; c < channels; c++) {
int spreadSeg = (channels >= 2 && c == 1) ? (int) (rStereo * 120f * ((float) sampleRate / 44100.0f)) : 0;
seg.fvs[c] = new Freeverb(sampleRate, spreadSeg);
seg.fvs[c].setRoomSize(rRoom);
seg.fvs[c].setDamp(rDamp);
seg.fvs[c].setDry(rDry);
seg.fvs[c].setWet(rWet);
}
}
String[] eParts = cols[5].trim().split(",");
if (eParts.length >= 6 && Integer.parseInt(eParts[0].trim()) == 1) {
float eDly = Float.parseFloat(eParts[1].trim());
float eFb = Float.parseFloat(eParts[2].trim());
float eDamp = Float.parseFloat(eParts[3].trim());
float eDry = Float.parseFloat(eParts[4].trim());
float eWet = Float.parseFloat(eParts[5].trim());
float eStereo = 0f;
if (eParts.length >= 7) eStereo = Math.max(0f, Math.min(1f, Float.parseFloat(eParts[6].trim())));
seg.echos = new Echo[channels];
for (int c = 0; c < channels; c++) {
seg.echos[c] = new Echo(sampleRate);
float dlySeg = (channels >= 2 && c == 1) ? eDly * (1.0f + 0.5f * eStereo) : eDly;
seg.echos[c].setParameters(dlySeg, eFb, eDamp, eDry, eWet);
}
}
String[] tParts = cols[6].trim().split(",");
if (tParts.length >= 8 && Integer.parseInt(tParts[0].trim()) == 1) {
float tBass = Float.parseFloat(tParts[1].trim());
float tTreble = Float.parseFloat(tParts[2].trim());
float[] tBands = new float[5];
for (int b = 0; b < 5; b++) tBands[b] = Float.parseFloat(tParts[3 + b].trim());
Tone[] cand = new Tone[channels];
for (int c = 0; c < channels; c++) cand[c] = new Tone(sampleRate, tBass, tTreble, tBands);
if (cand[0].aktif()) seg.tones = cand;
}
if (cols.length >= 8) {
String[] atParts = cols[7].trim().split(",");
if (atParts.length >= 4 && Integer.parseInt(atParts[0].trim()) == 1) {
seg.hasAutoTune = true;
seg.atKey = Math.round(Float.parseFloat(atParts[1].trim()));
seg.atScale = Math.round(Float.parseFloat(atParts[2].trim()));
seg.atSpeed = Float.parseFloat(atParts[3].trim());
if (seg.byteEnd > sliceStartByte && seg.byteStart < sliceEndByte) {
butuhPitchKerja = true;
}
}
}
if (cols.length >= 9) {
SuaraDuaCfg sdc = SuaraDuaCfg.parse(cols[8]);
if (sdc.ada) {
seg.hasSuaraDua = true;
seg.sdCfg = sdc;
if (seg.byteEnd > sliceStartByte && seg.byteStart < sliceEndByte) {
butuhPitchKerja = true;
}
}
}
if (cols.length >= 10) {
try {
String[] sp = cols[9].trim().split(",");
if (sp.length >= 6 && Math.round(Float.parseFloat(sp[0].trim())) == 1) {
int snK = Math.round(Float.parseFloat(sp[1].trim()));
if (snK < 1 || snK > 4) snK = 1;
seg.hasSensor = true;
seg.snKind = snK;
seg.snFreq = Math.max(20f, Math.min(20000f, Float.parseFloat(sp[2].trim())));
seg.snVol = Math.max(0f, Math.min(1f, Float.parseFloat(sp[3].trim())));
seg.snMix = Math.max(0f, Math.min(1f, Float.parseFloat(sp[4].trim())));
long snFr = (long) Math.round(Float.parseFloat(sp[5].trim()) * (float) sampleRate / 1000f);
long snSegFr = (seg.byteEnd - seg.byteStart) / frameSize;
seg.snFadeFrames = Math.max(0L, Math.min(snFr, snSegFr / 2));
}
} catch (Exception ignoredSn) {
android.util.Log.w("NadiSensor", "Pengaturan sensor tidak terbaca: " + cols[9]);
seg.hasSensor = false;
}
}
segList.add(seg);
}
long sliceByteLen = sliceEndByte - sliceStartByte;
long readBaseOffset = headerOffset + sliceStartByte;
if (butuhPitchKerja) {
workFile = new File(outPath + ".work.raw");
FileOutputStream wFos = new FileOutputStream(workFile);
rafIn.seek(headerOffset + sliceStartByte);
byte[] cpBuf = new byte[32768];
long remCopy = sliceByteLen;
while (remCopy > 0) {
int tr = (int) Math.min((long) cpBuf.length, remCopy);
int r = rafIn.read(cpBuf, 0, tr);
if (r <= 0) break;
wFos.write(cpBuf, 0, r);
remCopy -= r;
}
wFos.close();
rafIn.close();
rafIn = new RandomAccessFile(workFile, "rw");
readBaseOffset = 0;
for (int sIdx = 0; sIdx < segList.size(); sIdx++) {
SegmenEfek seg = segList.get(sIdx);
if (!seg.hasPitch) continue;
long ovStartGlobal = Math.max(seg.byteStart, sliceStartByte);
long ovEndGlobal = Math.min(seg.byteEnd, sliceEndByte);
if (ovEndGlobal <= ovStartGlobal) continue;
long localOff = ovStartGlobal - sliceStartByte;
long localLen = ovEndGlobal - ovStartGlobal;
localLen -= (localLen % frameSize);
if (localLen <= 0) continue;
if (seg.pitchLanjut && muatNativeSuaraDua() && nadiVer >= 2) {
SuaraDuaCfg pcSeg = SuaraDuaCfg.untukPitch(seg.pitchSemitone, seg.pitchGl, seg.pitchG0, seg.pitchG1, seg.pitchGd);
if (suaraDuaRentangDiTempat(rafIn, localOff, localLen, outPath, sampleRate, channels, pcSeg)) continue;
}
if (Math.abs(seg.pitchSemitone) < 0.05f && !seg.pitchGl) continue;
File pitchTmp = new File(outPath + ".pseg.raw");
float pitchRatio = (float) Math.pow(2.0, semitonGeser(seg.pitchGl, seg.pitchSemitone, seg.pitchG0, seg.pitchG1, seg.pitchGd, 0L, 1L, sampleRate) / 12.0);
boolean pitchNat = false;
if (sonicNativeSiap()) {
try {
pitchNat = sonicNative(workFile.getAbsolutePath(), localOff, localLen, pitchTmp, 0, sampleRate, channels, pitchRatio, seg.pitchGl, seg.pitchG0, seg.pitchG1, seg.pitchGd, localLen / frameSize, localLen);
} catch (Throwable t) { pitchNat = false; }
}
if (!pitchNat) {
FileOutputStream pFos = new FileOutputStream(pitchTmp);
Sonic sonic = new Sonic(sampleRate, channels);
sonic.setPitch(pitchRatio);
rafIn.seek(localOff);
byte[] inBuf = new byte[8192];
short[] shortBuf = new short[4096];
byte[] outBuf = new byte[8192];
long remPitchRead = localLen;
long writtenPitchBytes = 0;
while (remPitchRead > 0) {
int tr = (int) Math.min((long) inBuf.length, remPitchRead);
tr -= (tr % frameSize);
if (tr <= 0) break;
int r = rafIn.read(inBuf, 0, tr);
if (r <= 0) break;
int numShorts = r / 2;
ByteBuffer.wrap(inBuf, 0, r).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(shortBuf, 0, numShorts);
if (seg.pitchGl) sonic.setPitch((float) Math.pow(2.0, semitonGeser(seg.pitchGl, seg.pitchSemitone, seg.pitchG0, seg.pitchG1, seg.pitchGd, (localLen - remPitchRead) / frameSize, localLen / frameSize, sampleRate) / 12.0));
sonic.putSamples(shortBuf, numShorts / channels);
while (true) {
int samplesOut = sonic.receiveSamples(shortBuf, shortBuf.length / channels);
if (samplesOut <= 0) break;
int bw = samplesOut * frameSize;
if (writtenPitchBytes + bw > localLen) {
bw = (int) (localLen - writtenPitchBytes);
}
if (bw > 0) {
ByteBuffer bb = ByteBuffer.wrap(outBuf, 0, bw).order(ByteOrder.LITTLE_ENDIAN);
for (int k = 0; k < bw / 2; k++) bb.putShort(shortBuf[k]);
pFos.write(outBuf, 0, bw);
writtenPitchBytes += bw;
}
}
remPitchRead -= r;
}
sonic.flush();
while (writtenPitchBytes < localLen) {
int samplesOut = sonic.receiveSamples(shortBuf, shortBuf.length / channels);
if (samplesOut <= 0) break;
int bw = samplesOut * frameSize;
if (writtenPitchBytes + bw > localLen) {
bw = (int) (localLen - writtenPitchBytes);
}
if (bw > 0) {
ByteBuffer bb = ByteBuffer.wrap(outBuf, 0, bw).order(ByteOrder.LITTLE_ENDIAN);
for (int k = 0; k < bw / 2; k++) bb.putShort(shortBuf[k]);
pFos.write(outBuf, 0, bw);
writtenPitchBytes += bw;
}
}
pFos.close();
}
rafIn.seek(localOff);
FileInputStream pFis = new FileInputStream(pitchTmp);
byte[] pBackBuf = new byte[8192];
long remBack = Math.min(localLen, pitchTmp.length());
while (remBack > 0) {
int tr = (int) Math.min((long) pBackBuf.length, remBack);
int r = pFis.read(pBackBuf, 0, tr);
if (r <= 0) break;
rafIn.write(pBackBuf, 0, r);
remBack -= r;
}
pFis.close();
pitchTmp.delete();
}
for (int sIdx = 0; sIdx < segList.size(); sIdx++) {
SegmenEfek seg = segList.get(sIdx);
if (!seg.hasAutoTune) continue;
long ovStartGlobal = Math.max(seg.byteStart, sliceStartByte);
long ovEndGlobal = Math.min(seg.byteEnd, sliceEndByte);
if (ovEndGlobal <= ovStartGlobal) continue;
long localOff = ovStartGlobal - sliceStartByte;
long localLen = ovEndGlobal - ovStartGlobal;
localLen -= (localLen % frameSize);
if (localLen <= 0) continue;
File atTmp = new File(outPath + ".atseg.raw");
boolean atNat = false;
if (sonicNativeSiap()) {
try { atNat = autoTuneNative(workFile.getAbsolutePath(), localOff, localLen, atTmp, 0, sampleRate, channels, seg.atKey, seg.atScale, seg.atSpeed); } catch (Throwable t) { atNat = false; }
}
if (!atNat) AutoTune.prosesRafKeFile(rafIn, localOff, localLen, atTmp, false, sampleRate, channels, seg.atKey, seg.atScale, seg.atSpeed);
rafIn.seek(localOff);
FileInputStream atFis = new FileInputStream(atTmp);
byte[] atBuf = new byte[8192];
long remBack = Math.min(localLen, atTmp.length());
while (remBack > 0) {
int tr = (int) Math.min((long) atBuf.length, remBack);
int r = atFis.read(atBuf, 0, tr);
if (r <= 0) break;
rafIn.write(atBuf, 0, r);
remBack -= r;
}
atFis.close();
atTmp.delete();
}
for (int sIdx = 0; sIdx < segList.size(); sIdx++) {
SegmenEfek seg = segList.get(sIdx);
if (!seg.hasSuaraDua) continue;
long ovStartGlobal = Math.max(seg.byteStart, sliceStartByte);
long ovEndGlobal = Math.min(seg.byteEnd, sliceEndByte);
if (ovEndGlobal <= ovStartGlobal) continue;
long localOff = ovStartGlobal - sliceStartByte;
long localLen = ovEndGlobal - ovStartGlobal;
localLen -= (localLen % frameSize);
if (localLen <= 0) continue;
suaraDuaRentangDiTempat(rafIn, localOff, localLen, outPath, sampleRate, channels, seg.sdCfg);
}
}
rafIn.seek(readBaseOffset);
boolean isM4a = (format == 2);
FileOutputStream fosWav = null;
int trackIdx = -1;
boolean muxStarted = false;
long ptsUs = 0;
long totalBytesWritten = 0;
int lastProgress = 0;
String progFile = outPath + ".prog";
if (!isM4a) {
fosWav = new FileOutputStream(outPath);
fosWav.write(new byte[44]);
} else {
MediaFormat f = MediaFormat.createAudioFormat("audio/mp4a-latm", sampleRate, channels);
f.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC);
f.setInteger(MediaFormat.KEY_BIT_RATE, bitrate);
f.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 524288);
encoder = MediaCodec.createEncoderByType("audio/mp4a-latm");
encoder.configure(f, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
encoder.start();
muxer = new MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
}
int bufSize = 32768;
byte[] bIn = new byte[bufSize];
ByteBuffer bbOut = ByteBuffer.allocate(bufSize).order(ByteOrder.LITTLE_ENDIAN);
MediaCodec.BufferInfo info = isM4a ? new MediaCodec.BufferInfo() : null;
int numSegs = segList.size();
SegmenEfek[] segArr = segList.toArray(new SegmenEfek[numSegs]);
long rantaiH = 0;
if (numSegs > 0 && rantaiNativeSiap()) {
try { rantaiH = buatRantaiNative(segArr, channels, sampleRate, frameSize); } catch (Throwable t) { rantaiH = 0; }
}
long currentReadBytes = 0;
while (currentReadBytes < sliceByteLen) {
int toRead = (int) Math.min((long) bufSize, sliceByteLen - currentReadBytes);
toRead -= (toRead % frameSize);
if (toRead <= 0) break;
int read = rafIn.read(bIn, 0, toRead);
if (read <= 0) break;
read -= (read % frameSize);
if (read <= 0) break;
int numShorts = read / 2;
bbOut.clear();
boolean rantaiOk = false;
if (rantaiH != 0) {
try {
rantaiOk = nvRantaiProses(rantaiH, bIn, read, bbOut.array(), sliceStartByte + currentReadBytes) == 1;
} catch (Throwable t) { rantaiOk = false; }
}
if (!rantaiOk) {
ByteBuffer bbIn = ByteBuffer.wrap(bIn, 0, read).order(ByteOrder.LITTLE_ENDIAN);
for (int i = 0; i < numShorts; i++) {
short sample = bbIn.getShort();
int chIdx = i % channels;
int frameIdx = i / channels;
long globalBytePos = sliceStartByte + currentReadBytes + ((long) frameIdx * frameSize);
for (int s = 0; s < numSegs; s++) {
SegmenEfek seg = segArr[s];
if (globalBytePos >= seg.byteStart && globalBytePos < seg.byteEnd) {
if (seg.gates != null) sample = seg.gates[chIdx].process(sample);
if (seg.tones != null) sample = seg.tones[chIdx].process(sample);
if (seg.echos != null) sample = seg.echos[chIdx].process(sample);
if (seg.fvs != null) sample = seg.fvs[chIdx].process(sample);
if (seg.hasSensor) {
long frameRelSn = (globalBytePos - seg.byteStart) / frameSize;
long frameLenSn = (seg.byteEnd - seg.byteStart) / frameSize;
double envSn = 1.0;
if (seg.snFadeFrames > 0) {
double a1 = (double) frameRelSn / (double) seg.snFadeFrames;
double a2 = (double) (frameLenSn - frameRelSn) / (double) seg.snFadeFrames;
envSn = Math.min(1.0, Math.min(a1, a2));
if (envSn < 0.0) envSn = 0.0;
}
float tahanSn = (float) (1.0 - envSn * (1.0 - (double) seg.snMix));
float bunyiSn = bunyiSensor(seg.snKind, seg.snFreq, frameRelSn, chIdx, sampleRate) * seg.snVol * 30000f * (float) envSn;
int hasilSn = (int) ((float) sample * tahanSn + bunyiSn);
if (hasilSn > 32767) hasilSn = 32767;
if (hasilSn < -32768) hasilSn = -32768;
sample = (short) hasilSn;
}
}
}
bbOut.putShort(sample);
}
}
currentReadBytes += read;
totalBytesWritten += read;
if (sliceByteLen > 0) {
int prog = (int) ((currentReadBytes * 100L) / sliceByteLen);
if (prog > lastProgress && prog <= 100) {
lastProgress = prog;
try {
FileOutputStream pfos = new FileOutputStream(progFile);
pfos.write(String.valueOf(prog).getBytes()); laporUmum((int) (prog));
pfos.close();
} catch (Exception ignored) {}
}
}
if (!isM4a) {
fosWav.write(bbOut.array(), 0, read);
} else {
int inIdx = -1;
while (inIdx < 0) {
inIdx = encoder.dequeueInputBuffer(10000);
if (inIdx >= 0) {
ByteBuffer inBuf = encoder.getInputBuffer(inIdx);
inBuf.clear();
inBuf.put(bbOut.array(), 0, read);
encoder.queueInputBuffer(inIdx, 0, read, ptsUs, 0);
ptsUs += (long) read * 1000000L / bytesPerSec;
}
while (true) {
int outIdx = encoder.dequeueOutputBuffer(info, 10000);
if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
trackIdx = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (outIdx >= 0) {
ByteBuffer outBuf = encoder.getOutputBuffer(outIdx);
if (info.size > 0 && muxStarted) {
outBuf.position(info.offset);
outBuf.limit(info.offset + info.size);
muxer.writeSampleData(trackIdx, outBuf, info);
}
encoder.releaseOutputBuffer(outIdx, false);
} else {
break;
}
}
}
}
}
if (rantaiH != 0) { try { nvRantaiLepas(rantaiH); } catch (Throwable t) {} rantaiH = 0; }
rafIn.close();
rafIn = null;
if (workFile != null && workFile.exists()) workFile.delete();
if (!isM4a) {
fosWav.close();
RandomAccessFile rafWav = new RandomAccessFile(outPath, "rw");
rafWav.seek(0);
ByteBuffer head = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
head.put("RIFF".getBytes()); head.putInt((int) totalBytesWritten + 36);
head.put("WAVE".getBytes()); head.put("fmt ".getBytes());
head.putInt(16); head.putShort((short) 1); head.putShort((short) channels);
head.putInt(sampleRate); head.putInt((int) bytesPerSec);
head.putShort((short) frameSize); head.putShort((short) 16);
head.put("data".getBytes()); head.putInt((int) totalBytesWritten);
rafWav.write(head.array());
rafWav.close();
} else {
int inIdx = -1;
while (inIdx < 0) {
inIdx = encoder.dequeueInputBuffer(10000);
if (inIdx >= 0) {
encoder.queueInputBuffer(inIdx, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
} else {
while (true) {
int outIdx = encoder.dequeueOutputBuffer(info, 10000);
if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
trackIdx = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (outIdx >= 0) {
ByteBuffer outBuf = encoder.getOutputBuffer(outIdx);
if (info.size > 0 && muxStarted) {
outBuf.position(info.offset);
outBuf.limit(info.offset + info.size);
muxer.writeSampleData(trackIdx, outBuf, info);
}
encoder.releaseOutputBuffer(outIdx, false);
} else {
break;
}
}
}
}
while (true) {
int outIdx = encoder.dequeueOutputBuffer(info, 10000);
if (outIdx >= 0) {
ByteBuffer outBuf = encoder.getOutputBuffer(outIdx);
if (info.size > 0 && muxStarted) {
outBuf.position(info.offset);
outBuf.limit(info.offset + info.size);
muxer.writeSampleData(trackIdx, outBuf, info);
}
encoder.releaseOutputBuffer(outIdx, false);
if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break;
} else if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
trackIdx = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) {
break;
}
}
encoder.stop();
encoder.release();
encoder = null;
if (muxStarted) {
muxer.stop();
muxer.release();
muxer = null;
}
}
new File(progFile).delete();
return "SUKSES";
} catch (Exception e) {
if (rafIn != null) try { rafIn.close(); } catch (Exception ignored) {}
if (workFile != null && workFile.exists()) try { workFile.delete(); } catch (Exception ignored) {}
if (encoder != null) try { encoder.stop(); encoder.release(); } catch (Exception ignored) {}
if (muxer != null) try { muxer.stop(); muxer.release(); } catch (Exception ignored) {}
return "ERROR: " + e.getMessage();
}
}

public static String gabungVideoPenutup(String videoPath, String audioPath, String outPath, boolean tampilWatermark, String teksWatermark) {
    return gabungVideoPenutup(videoPath, audioPath, outPath, tampilWatermark, teksWatermark, 0L);
}

// Menulis frame layar hitam (opsional bertuliskan watermark) dari ptsStartUs sampai ptsEndUs ke track video muxer
private static boolean tulisFrameLayarPenutup(MediaMuxer muxer, int track, String mime, int codedW, int codedH, int rot, String teks, long ptsStartUs, long ptsEndUs) {
    if (ptsEndUs - ptsStartUs < 100000L) return true;
    MediaCodec encoder = null;
    try {
        int encW = codedW - (codedW % 2);
        int encH = codedH - (codedH % 2);
        boolean tukar = (rot == 90 || rot == 270);
        int dispW = tukar ? encH : encW;
        int dispH = tukar ? encW : encH;

        android.graphics.Bitmap disp = android.graphics.Bitmap.createBitmap(dispW, dispH, android.graphics.Bitmap.Config.ARGB_8888);
        android.graphics.Canvas cv = new android.graphics.Canvas(disp);
        cv.drawColor(0xFF000000);
        if (teks != null && !teks.isEmpty()) {
            android.graphics.Paint pt = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
            pt.setColor(0xFFEDEDED);
            pt.setTextAlign(android.graphics.Paint.Align.CENTER);
            pt.setTypeface(android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD));
            float tSize = Math.max(24f, Math.min(dispW, dispH) * 0.07f);
            pt.setTextSize(tSize);
            while (pt.measureText(teks) > dispW * 0.85f && tSize > 12f) {
                tSize -= 2f;
                pt.setTextSize(tSize);
            }
            float cy = dispH / 2f - (pt.ascent() + pt.descent()) / 2f;
            cv.drawText(teks, dispW / 2f, cy, pt);
            float lineW = Math.min(pt.measureText(teks), dispW * 0.5f) * 0.6f;
            pt.setColor(0x66FFFFFF);
            pt.setStrokeWidth(Math.max(2f, Math.min(dispW, dispH) * 0.004f));
            float ly = cy + tSize * 0.45f;
            cv.drawLine(dispW / 2f - lineW / 2f, ly, dispW / 2f + lineW / 2f, ly, pt);
        }
        android.graphics.Bitmap coded = disp;
        if (rot != 0) {
            android.graphics.Matrix mx = new android.graphics.Matrix();
            mx.postRotate((360 - rot) % 360);
            coded = android.graphics.Bitmap.createBitmap(disp, 0, 0, dispW, dispH, mx, true);
        }
        if (coded.getWidth() != encW || coded.getHeight() != encH) {
            coded = android.graphics.Bitmap.createScaledBitmap(coded, encW, encH, true);
        }
        int[] argb = new int[encW * encH];
        coded.getPixels(argb, 0, encW, 0, 0, encW, encH);
        byte[] yArr = new byte[encW * encH];
        byte[] uArr = new byte[(encW / 2) * (encH / 2)];
        byte[] vArr = new byte[(encW / 2) * (encH / 2)];
        argbKeYuv(argb, encW, encH, yArr, uArr, vArr);
        argb = null;

        MediaFormat encFmt = MediaFormat.createVideoFormat(mime, encW, encH);
        encFmt.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible);
        encFmt.setInteger(MediaFormat.KEY_BIT_RATE, 800000);
        encFmt.setInteger(MediaFormat.KEY_FRAME_RATE, 5);
        encFmt.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);
        try { encFmt.setInteger("prepend-sps-pps-to-idr-frames", 1); } catch (Exception ignored) {}
        encoder = MediaCodec.createEncoderByType(mime);
        encoder.configure(encFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
        encoder.start();

        long stepUs = 200000L;
        long ptsNext = ptsStartUs;
        long ptsAkhir = ptsEndUs - 33000L;
        boolean frameAkhirTerkirim = false;
        boolean inEOS = false;
        boolean outEOS = false;
        int spinEOS = 0;
        MediaCodec.BufferInfo encInfo = new MediaCodec.BufferInfo();
        while (!outEOS) {
            if (!inEOS) {
                int inIdx = encoder.dequeueInputBuffer(10000);
                if (inIdx >= 0) {
                    long ptsFrame;
                    boolean kirimEOS = false;
                    if (ptsNext < ptsAkhir - 50000L) {
                        ptsFrame = ptsNext;
                        ptsNext += stepUs;
                    } else if (!frameAkhirTerkirim) {
                        ptsFrame = ptsAkhir;
                        frameAkhirTerkirim = true;
                    } else {
                        ptsFrame = ptsEndUs;
                        kirimEOS = true;
                    }
                    if (kirimEOS) {
                        encoder.queueInputBuffer(inIdx, 0, 0, ptsFrame, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                        inEOS = true;
                    } else {
                        android.media.Image dstImg = encoder.getInputImage(inIdx);
                        if (dstImg != null) {
                            salinCacheYUVKeImage(yArr, uArr, vArr, encW, encH, dstImg);
                            dstImg.close();
                        }
                        ByteBuffer rawIn = encoder.getInputBuffer(inIdx);
                        int qSz = (rawIn != null && rawIn.capacity() > 0) ? rawIn.capacity() : (encW * encH * 3 / 2);
                        encoder.queueInputBuffer(inIdx, 0, qSz, ptsFrame, 0);
                    }
                }
            } else {
                spinEOS++;
                if (spinEOS > 3000) break;
            }
            while (true) {
                int outIdx = encoder.dequeueOutputBuffer(encInfo, 10000);
                if (outIdx >= 0) {
                    ByteBuffer ob = encoder.getOutputBuffer(outIdx);
                    boolean config = (encInfo.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0;
                    if (encInfo.size > 0 && !config && ob != null) {
                        ob.position(encInfo.offset);
                        ob.limit(encInfo.offset + encInfo.size);
                        muxer.writeSampleData(track, ob, encInfo);
                    }
                    encoder.releaseOutputBuffer(outIdx, false);
                    if ((encInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        outEOS = true;
                        break;
                    }
                } else if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    // format video sudah dipakai dari file asli, abaikan
                } else {
                    break;
                }
            }
        }
        encoder.stop();
        encoder.release();
        encoder = null;
        return true;
    } catch (Exception e) {
        if (encoder != null) {
            try { encoder.stop(); } catch (Exception ignored) {}
            try { encoder.release(); } catch (Exception ignored) {}
        }
        return false;
    }
}

// introMs > 0: video dimulai setelah introMs (layar hitam selama musik pembuka), lalu ekor musik di akhir
public static String gabungVideoPenutup(String videoPath, String audioPath, String outPath, boolean tampilWatermark, String teksWatermark, long introMs) {
tahap("Menyusun video");
    MediaExtractor vEx = null;
    MediaExtractor aEx = null;
    MediaMuxer muxer = null;
    boolean muxStarted = false;
    try {
        vEx = new MediaExtractor();
        vEx.setDataSource(videoPath);
        int vTrack = -1;
        MediaFormat vFmt = null;
        for (int i = 0; i < vEx.getTrackCount(); i++) {
            MediaFormat f = vEx.getTrackFormat(i);
            String mime = f.getString(MediaFormat.KEY_MIME);
            if (mime != null && mime.startsWith("video/")) { vTrack = i; vFmt = f; break; }
        }
        aEx = new MediaExtractor();
        aEx.setDataSource(audioPath);
        int aTrack = -1;
        MediaFormat aFmt = null;
        for (int i = 0; i < aEx.getTrackCount(); i++) {
            MediaFormat f = aEx.getTrackFormat(i);
            String mime = f.getString(MediaFormat.KEY_MIME);
            if (mime != null && mime.startsWith("audio/")) { aTrack = i; aFmt = f; break; }
        }
        if (vTrack == -1 || vFmt == null || aTrack == -1 || aFmt == null) {
            vEx.release(); vEx = null;
            aEx.release(); aEx = null;
            return gabung(videoPath, audioPath, outPath);
        }
        vEx.selectTrack(vTrack);
        aEx.selectTrack(aTrack);

        long audioDurUs = aFmt.containsKey(MediaFormat.KEY_DURATION) ? aFmt.getLong(MediaFormat.KEY_DURATION) : 0L;
        if (audioDurUs <= 0) {
            long maxSt = 0;
            ByteBuffer tmp = ByteBuffer.allocate(262144);
            while (aEx.readSampleData(tmp, 0) >= 0) {
                long st = aEx.getSampleTime();
                if (st > maxSt) maxSt = st;
                aEx.advance();
            }
            audioDurUs = maxSt + 30000L;
            aEx.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC);
        }

        muxer = new MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
        int rot = 0;
        if (vFmt.containsKey(MediaFormat.KEY_ROTATION)) rot = vFmt.getInteger(MediaFormat.KEY_ROTATION);
        rot = ((rot % 360) + 360) % 360;
        try { muxer.setOrientationHint(rot); } catch (Exception ignored) {}
        int mVTrack = muxer.addTrack(vFmt);
        int mATrack = muxer.addTrack(aFmt);
        muxer.start();
        muxStarted = true;

        String vMime = vFmt.getString(MediaFormat.KEY_MIME);
        boolean bisaEncode = vMime != null && (vMime.equals("video/avc") || vMime.equals("video/hevc"));
        int codedW = vFmt.getInteger(MediaFormat.KEY_WIDTH);
        int codedH = vFmt.getInteger(MediaFormat.KEY_HEIGHT);
        String teksLayar = tampilWatermark ? ((teksWatermark != null && !teksWatermark.trim().isEmpty()) ? teksWatermark.trim() : "Nadi Editor") : null;

        long introUs = Math.max(introMs, 0L) * 1000L;
        if (introUs > 0 && bisaEncode && introUs >= 300000L) {
            tulisFrameLayarPenutup(muxer, mVTrack, vMime, codedW, codedH, rot, teksLayar, 0L, introUs);
        }

        int vBufSize = 2097152;
        if (vFmt.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) vBufSize = Math.max(vBufSize, vFmt.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE));
        ByteBuffer buf = ByteBuffer.allocate(vBufSize);
        MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
        long firstPts = -1;
        long maxPts = 0;
        int count = 0;
        while (true) {
            info.offset = 0;
            info.size = vEx.readSampleData(buf, 0);
            if (info.size < 0) break;
            long ptsAsli = vEx.getSampleTime();
            info.presentationTimeUs = ptsAsli + introUs;
            info.flags = vEx.getSampleFlags();
            muxer.writeSampleData(mVTrack, buf, info);
            if (firstPts < 0) firstPts = ptsAsli;
if (ptsAsli > maxPts) maxPts = ptsAsli;
count++;
if ((count % 15) == 0) laporUmum((int) Math.min(60L, ptsAsli * 60L / Math.max(1L, audioDurUs)));
            vEx.advance();
        }

        long frameDurUs = 33333L;
        if (count > 1 && maxPts > firstPts) frameDurUs = (maxPts - firstPts) / (count - 1);
        if (frameDurUs < 1000L || frameDurUs > 200000L) frameDurUs = 33333L;
        long videoEndUs = maxPts + introUs + frameDurUs;

        laporUmum(65);
if (tampilWatermark && bisaEncode && count > 0 && audioDurUs > videoEndUs + 300000L) {
tulisFrameLayarPenutup(muxer, mVTrack, vMime, codedW, codedH, rot, teksLayar, videoEndUs, audioDurUs);
        }

        ByteBuffer aBuf = ByteBuffer.allocate(1048576);
        MediaCodec.BufferInfo aInfo = new MediaCodec.BufferInfo();
        while (true) {
            aInfo.offset = 0;
            aInfo.size = aEx.readSampleData(aBuf, 0);
            if (aInfo.size < 0) break;
            aInfo.presentationTimeUs = aEx.getSampleTime();
aInfo.flags = aEx.getSampleFlags();
muxer.writeSampleData(mATrack, aBuf, aInfo);
if ((aInfo.presentationTimeUs % 500000L) < 25000L) laporUmum(80 + (int) Math.min(19L, aInfo.presentationTimeUs * 19L / Math.max(1L, audioDurUs)));
aEx.advance();
}
laporUmum(100);
vEx.release(); vEx = null;
aEx.release(); aEx = null;
muxer.stop();
muxer.release();
muxer = null;
return "SUKSES";
    } catch (Exception e) {
        if (vEx != null) { try { vEx.release(); } catch (Exception ignored) {} }
        if (aEx != null) { try { aEx.release(); } catch (Exception ignored) {} }
        if (muxer != null) {
            if (muxStarted) { try { muxer.stop(); } catch (Exception ignored) {} }
            try { muxer.release(); } catch (Exception ignored) {}
        }
        return "ERROR: " + e.getMessage();
    }
}

public static String gabung(String videoPath, String audioPath, String outPath) {
tahap("Menggabungkan gambar dan suara");
try {
MediaMuxer muxer = new MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
MediaExtractor vEx = new MediaExtractor();
vEx.setDataSource(videoPath);
int vTrack = -1;
for (int i = 0; i < vEx.getTrackCount(); i++) {
if (vEx.getTrackFormat(i).getString(MediaFormat.KEY_MIME).startsWith("video/")) {
vTrack = i; break;
}
}
int mVTrack = -1;
if (vTrack != -1) {
vEx.selectTrack(vTrack);
MediaFormat vFmt = vEx.getTrackFormat(vTrack);
if (vFmt.containsKey(MediaFormat.KEY_ROTATION)) {
try {
muxer.setOrientationHint(vFmt.getInteger(MediaFormat.KEY_ROTATION));
} catch (Exception ignored) {}
}
mVTrack = muxer.addTrack(vFmt);
}
MediaExtractor aEx = new MediaExtractor();
aEx.setDataSource(audioPath);
int aTrack = -1;
for (int i = 0; i < aEx.getTrackCount(); i++) {
if (aEx.getTrackFormat(i).getString(MediaFormat.KEY_MIME).startsWith("audio/")) {
aTrack = i; break;
}
}
int mATrack = -1;
if (aTrack != -1) {
aEx.selectTrack(aTrack);
mATrack = muxer.addTrack(aEx.getTrackFormat(aTrack));
}
muxer.start();
ByteBuffer buf = ByteBuffer.allocate(2097152);
MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
long durGab = 1L;
try {
if (vTrack != -1 && vEx.getTrackFormat(vTrack).containsKey(MediaFormat.KEY_DURATION)) durGab = Math.max(durGab, vEx.getTrackFormat(vTrack).getLong(MediaFormat.KEY_DURATION));
if (aTrack != -1 && aEx.getTrackFormat(aTrack).containsKey(MediaFormat.KEY_DURATION)) durGab = Math.max(durGab, aEx.getTrackFormat(aTrack).getLong(MediaFormat.KEY_DURATION));
} catch (Exception ignoredDur) {}
int pctGabTerakhir = -1;
if (vTrack != -1) {
while (true) {
info.size = vEx.readSampleData(buf, 0);
if (info.size < 0) break;
info.presentationTimeUs = vEx.getSampleTime();
info.flags = vEx.getSampleFlags();
info.offset = 0;
muxer.writeSampleData(mVTrack, buf, info);
int pcG = (int) Math.min(50L, (info.presentationTimeUs * 50L) / durGab);
if (pcG != pctGabTerakhir) { pctGabTerakhir = pcG; laporUmum(pcG); }
vEx.advance();
}
}
if (aTrack != -1) {
while (true) {
info.size = aEx.readSampleData(buf, 0);
if (info.size < 0) break;
info.presentationTimeUs = aEx.getSampleTime();
info.flags = aEx.getSampleFlags();
info.offset = 0;
muxer.writeSampleData(mATrack, buf, info);
int pcG2 = 50 + (int) Math.min(50L, (info.presentationTimeUs * 50L) / durGab);
if (pcG2 != pctGabTerakhir) { pctGabTerakhir = pcG2; laporUmum(pcG2); }
aEx.advance();
}
}
laporUmum(100);
vEx.release(); aEx.release();
muxer.stop(); muxer.release();
return "SUKSES";
} catch (Exception e) {
return "ERROR: " + e.getMessage();
}
}

public static String decodeToPCM(String inputPath, String outputPath, int targetSampleRate, int targetChannels, int limitSec) {
tahap("Membaca suara");
MediaExtractor extractor = null;
MediaCodec decoder = null;
FileOutputStream fos = null;
FileInputStream fisSumber = null;
try {
extractor = new MediaExtractor();
try {
extractor.setDataSource(inputPath);
} catch (Exception e1) {
try { extractor.release(); } catch (Exception ig) {}
extractor = new MediaExtractor();
fisSumber = new FileInputStream(inputPath);
extractor.setDataSource(fisSumber.getFD());
}
int trackIndex = -1;
for (int i = 0; i < extractor.getTrackCount(); i++) {
String mt = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME);
if (mt != null && mt.startsWith("audio/")) { trackIndex = i; break; }
}
if (trackIndex == -1) return "ERROR: Tidak ada trek audio pada " + inputPath;
extractor.selectTrack(trackIndex);
MediaFormat format = extractor.getTrackFormat(trackIndex);
String mime = format.getString(MediaFormat.KEY_MIME);
int outRate = format.containsKey(MediaFormat.KEY_SAMPLE_RATE) ? format.getInteger(MediaFormat.KEY_SAMPLE_RATE) : targetSampleRate;
int outCh = format.containsKey(MediaFormat.KEY_CHANNEL_COUNT) ? format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) : targetChannels;
int outEnc = 2;
decoder = MediaCodec.createDecoderByType(mime);
decoder.configure(format, null, null, 0);
decoder.start();
MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
fos = new FileOutputStream(outputPath);
long limitUs = (limitSec > 0) ? (long) limitSec * 1000000L : Long.MAX_VALUE;
long durMaksUs = format.containsKey(MediaFormat.KEY_DURATION) ? format.getLong(MediaFormat.KEY_DURATION) : 0L;
if (limitUs < durMaksUs) durMaksUs = limitUs;
int pctDecTerakhir = -1;
boolean inputDone = false;
boolean outputDone = false;
int diam = 0;
long totalTertulis = 0L;
double rpos = 0.0;
short[] prev = null;
while (!outputDone) {
if (!inputDone) {
int inIndex = decoder.dequeueInputBuffer(10000);
if (inIndex >= 0) {
ByteBuffer ib = decoder.getInputBuffer(inIndex);
int sampleSize = extractor.readSampleData(ib, 0);
if (sampleSize < 0) {
decoder.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
inputDone = true;
} else {
long tUs = extractor.getSampleTime();
if (durMaksUs > 0) {
int pcDec = (int) Math.max(0L, Math.min(100L, (tUs * 100L) / durMaksUs));
if (pcDec != pctDecTerakhir) { pctDecTerakhir = pcDec; laporUmum(pcDec); }
}
decoder.queueInputBuffer(inIndex, 0, sampleSize, tUs, 0);
extractor.advance();
}
}
}
int outIndex = decoder.dequeueOutputBuffer(info, 10000);
if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
MediaFormat of = decoder.getOutputFormat();
if (of.containsKey(MediaFormat.KEY_SAMPLE_RATE)) outRate = of.getInteger(MediaFormat.KEY_SAMPLE_RATE);
if (of.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) outCh = of.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
outEnc = of.containsKey("pcm-encoding") ? of.getInteger("pcm-encoding") : 2;
rpos = 0.0;
prev = null;
diam = 0;
} else if (outIndex >= 0) {
diam = 0;
ByteBuffer ob = decoder.getOutputBuffer(outIndex);
if (info.size > 0 && (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
if (info.presentationTimeUs > limitUs) {
outputDone = true;
} else {
ob.position(info.offset);
ob.limit(info.offset + info.size);
ob.order(ByteOrder.LITTLE_ENDIAN);
short[] inPCM;
if (outEnc == 4) {
java.nio.FloatBuffer fb = ob.asFloatBuffer();
int nf = fb.remaining();
inPCM = new short[nf];
for (int i = 0; i < nf; i++) {
float v = fb.get();
if (v > 1f) v = 1f; else if (v < -1f) v = -1f;
inPCM[i] = (short) Math.round(v * 32767f);
}
} else if (outEnc == 3) {
int nb = ob.remaining();
inPCM = new short[nb];
for (int i = 0; i < nb; i++) inPCM[i] = (short) (((ob.get() & 0xFF) - 128) << 8);
} else {
ShortBuffer sb = ob.asShortBuffer();
int ns = sb.remaining();
inPCM = new short[ns];
sb.get(inPCM);
}
int ic = Math.max(1, outCh);
int frames = inPCM.length / ic;
int tc = Math.max(1, targetChannels);
short[] cf = new short[frames * tc];
for (int f = 0; f < frames; f++) {
if (tc == 1) {
if (ic == 1) {
cf[f] = inPCM[f];
} else {
int sum = 0;
for (int c = 0; c < ic; c++) sum += inPCM[f * ic + c];
cf[f] = (short) (sum / ic);
}
} else {
for (int c = 0; c < tc; c++) cf[f * tc + c] = (ic == 1) ? inPCM[f] : inPCM[f * ic + Math.min(c, ic - 1)];
}
}
short[] hasil = cf;
int nHasil = frames * tc;
if (outRate != targetSampleRate && outRate > 0 && frames > 0) {
double step = (double) outRate / (double) targetSampleRate;
int total = frames + (prev != null ? 1 : 0);
short[] comb;
if (prev != null) {
comb = new short[total * tc];
System.arraycopy(prev, 0, comb, 0, tc);
System.arraycopy(cf, 0, comb, tc, frames * tc);
} else {
comb = cf;
}
int maxOut = Math.max(0, (int) ((total - 1 - rpos) / step) + 2);
short[] ro = new short[maxOut * tc];
int no = 0;
while (rpos < total - 1 && no < maxOut) {
int i0 = (int) rpos;
double fr = rpos - i0;
for (int c = 0; c < tc; c++) {
int s1 = comb[i0 * tc + c];
int s2 = comb[(i0 + 1) * tc + c];
ro[no * tc + c] = (short) Math.round(s1 + fr * (s2 - s1));
}
no++;
rpos += step;
}
rpos -= (total - 1);
if (rpos < 0) rpos = 0;
prev = new short[tc];
System.arraycopy(comb, (total - 1) * tc, prev, 0, tc);
hasil = ro;
nHasil = no * tc;
}
if (nHasil > 0) {
ByteBuffer writeBuf = ByteBuffer.allocate(nHasil * 2).order(ByteOrder.LITTLE_ENDIAN);
writeBuf.asShortBuffer().put(hasil, 0, nHasil);
fos.write(writeBuf.array());
totalTertulis += nHasil * 2L;
}
}
}
decoder.releaseOutputBuffer(outIndex, false);
if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) outputDone = true;
} else if (outIndex == MediaCodec.INFO_TRY_AGAIN_LATER && inputDone) {
diam++;
if (diam > 500) outputDone = true;
}
}
if (totalTertulis <= 0L) return "ERROR: Tidak ada data suara yang bisa dibaca dari file ini (" + mime + ")";
return "SUKSES";
} catch (Throwable e) {
return "ERROR: " + (e.getMessage() == null ? e.toString() : e.getMessage());
} finally {
try { if (fos != null) fos.close(); } catch (Exception ig) {}
try { if (decoder != null) { try { decoder.stop(); } catch (Exception ig) {} decoder.release(); } } catch (Exception ig) {}
try { if (extractor != null) extractor.release(); } catch (Exception ig) {}
try { if (fisSumber != null) fisSumber.close(); } catch (Exception ig) {}
}
}

private static void readTrackData(RandomAccessFile raf, byte[] buf, int length, boolean loop, long validLen) throws IOException {
int offset = 0;
while (offset < length) {
if (raf == null || validLen <= 0) {
for (int i = offset; i < length; i++) buf[i] = 0;
break;
}
long pos = raf.getFilePointer();
long rem = validLen - pos;
if (rem <= 0) {
if (loop) {
raf.seek(0);
rem = validLen;
} else {
for (int i = offset; i < length; i++) buf[i] = 0;
break;
}
}
int toRead = (int) Math.min((long)(length - offset), rem);
int read = raf.read(buf, offset, toRead);
if (read > 0) {
offset += read;
} else {
if (loop) {
raf.seek(0);
} else {
for (int i = offset; i < length; i++) buf[i] = 0;
break;
}
}
}
}

public static String campurAudio(String configData, String outPath, int format, int sampleRate, int channels, int bitrate, int previewSec) {
tahap("Mencampur audio");
RandomAccessFile[] rafs = null;
try {
String[] lines = configData.trim().split("\n");
int numTracks = lines.length;
if (numTracks == 0) return "ERROR: Daftar audio kosong";
String[] paths = new String[numTracks];
float[] vols = new float[numTracks];
boolean[] loops = new boolean[numTracks];
int[] fadeModes = new int[numTracks];
float[] fadeSecs = new float[numTracks];
long[] validLens = new long[numTracks];
rafs = new RandomAccessFile[numTracks];
int frameSize = channels * 2;
long bytesPerSec = (long) sampleRate * frameSize;
for (int i = 0; i < numTracks; i++) {
String[] parts = lines[i].trim().split("\\|");
paths[i] = parts[0].trim();
vols[i] = (parts.length > 1) ? Float.parseFloat(parts[1].trim()) : 1.0f;
loops[i] = (parts.length > 2) && (Integer.parseInt(parts[2].trim()) == 1);
fadeModes[i] = (parts.length > 3) ? Integer.parseInt(parts[3].trim()) : 0;
fadeSecs[i] = (parts.length > 4) ? Float.parseFloat(parts[4].trim()) : 0f;
File f = new File(paths[i]);
if (f.exists() && f.length() >= frameSize) {
validLens[i] = f.length() - (f.length() % frameSize);
rafs[i] = new RandomAccessFile(f, "r");
} else {
validLens[i] = 0;
rafs[i] = null;
}
}
if (validLens[0] <= 0) return "ERROR: Audio Utama kosong atau rusak";
long mainBytes = validLens[0];
long[] fadeBytesArr = new long[numTracks];
long maxExtraBytes = 0;
if (previewSec > 0) {
long prevLimit = (long) previewSec * bytesPerSec;
prevLimit = prevLimit - (prevLimit % frameSize);
if (mainBytes > prevLimit) mainBytes = prevLimit;
} else {
for (int i = 1; i < numTracks; i++) {
long reqFade = (long) (fadeSecs[i] * bytesPerSec);
reqFade = reqFade - (reqFade % frameSize);
if (fadeModes[i] == 1) {
fadeBytesArr[i] = Math.min(reqFade, mainBytes);
} else if (fadeModes[i] == 2 && reqFade > 0) {
long availTail = loops[i] ? reqFade : Math.max(0L, Math.min(validLens[i] - mainBytes, reqFade));
fadeBytesArr[i] = availTail;
if (availTail > maxExtraBytes) maxExtraBytes = availTail;
}
}
}
long totalOutputBytes = mainBytes + maxExtraBytes;
boolean isM4a = (format == 2);
FileOutputStream fosWav = null;
MediaCodec encoder = null;
MediaMuxer muxer = null;
int trackIdx = -1;
boolean muxStarted = false;
long ptsUs = 0;
long totalBytesWritten = 0;
int lastProgress = 0;
String progFile = outPath + ".prog";
if (!isM4a) {
fosWav = new FileOutputStream(outPath);
fosWav.write(new byte[44]);
} else {
MediaFormat f = MediaFormat.createAudioFormat("audio/mp4a-latm", sampleRate, channels);
f.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC);
f.setInteger(MediaFormat.KEY_BIT_RATE, bitrate);
f.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 524288);
encoder = MediaCodec.createEncoderByType("audio/mp4a-latm");
encoder.configure(f, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
encoder.start();
muxer = new MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
}
int bufSize = 32768;
byte[][] trackBufs = new byte[numTracks][bufSize];
ShortBuffer[] shortBufs = new ShortBuffer[numTracks];
ByteBuffer bbOut = ByteBuffer.allocate(bufSize).order(ByteOrder.LITTLE_ENDIAN);
MediaCodec.BufferInfo info = isM4a ? new MediaCodec.BufferInfo() : null;
long currentBytePos = 0;
while (currentBytePos < totalOutputBytes) {
int chunkBytes = (int) Math.min((long) bufSize, totalOutputBytes - currentBytePos);
chunkBytes = chunkBytes - (chunkBytes % frameSize);
if (chunkBytes <= 0) break;
int numShorts = chunkBytes / 2;
if (currentBytePos < mainBytes) {
int mainToRead = (int) Math.min((long) chunkBytes, mainBytes - currentBytePos);
readTrackData(rafs[0], trackBufs[0], mainToRead, false, validLens[0]);
if (mainToRead < chunkBytes) {
for (int b = mainToRead; b < chunkBytes; b++) trackBufs[0][b] = 0;
}
} else {
for (int b = 0; b < chunkBytes; b++) trackBufs[0][b] = 0;
}
shortBufs[0] = ByteBuffer.wrap(trackBufs[0], 0, chunkBytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer();
for (int t = 1; t < numTracks; t++) {
readTrackData(rafs[t], trackBufs[t], chunkBytes, loops[t], validLens[t]);
shortBufs[t] = ByteBuffer.wrap(trackBufs[t], 0, chunkBytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer();
}
bbOut.clear();
for (int s = 0; s < numShorts; s++) {
int frameIdx = s / channels;
long sampleBytePos = currentBytePos + ((long) frameIdx * frameSize);
float mixed = 0f;
short sMain = shortBufs[0].get(s);
if (sampleBytePos < mainBytes) {
mixed += sMain * vols[0];
}
for (int t = 1; t < numTracks; t++) {
short sComp = shortBufs[t].get(s);
if (sComp == 0) continue;
float fadeMul = 1.0f;
if (previewSec == 0) {
if (fadeModes[t] == 0) {
if (sampleBytePos >= mainBytes) fadeMul = 0f;
} else if (fadeModes[t] == 1) {
long fBytes = fadeBytesArr[t];
if (sampleBytePos >= mainBytes) {
fadeMul = 0f;
} else if (fBytes > 0 && sampleBytePos >= (mainBytes - fBytes)) {
fadeMul = (float)(mainBytes - sampleBytePos) / (float)fBytes;
}
} else if (fadeModes[t] == 2) {
long fBytes = fadeBytesArr[t];
if (fBytes <= 0) {
if (sampleBytePos >= mainBytes) fadeMul = 0f;
} else if (sampleBytePos >= (mainBytes + fBytes)) {
fadeMul = 0f;
} else if (sampleBytePos >= mainBytes) {
fadeMul = (float)((mainBytes + fBytes) - sampleBytePos) / (float)fBytes;
}
}
}
if (fadeMul > 0f) {
mixed += sComp * vols[t] * fadeMul;
}
}
int finalSample = Math.round(mixed);
if (finalSample > 32767) finalSample = 32767;
else if (finalSample < -32768) finalSample = -32768;
bbOut.putShort((short) finalSample);
}
currentBytePos += chunkBytes;
if (totalOutputBytes > 0) {
int currentProgress = (int) ((currentBytePos * 100L) / totalOutputBytes);
if (currentProgress > lastProgress && currentProgress <= 100) {
lastProgress = currentProgress;
try {
FileOutputStream pfos = new FileOutputStream(progFile);
pfos.write(String.valueOf(currentProgress).getBytes()); laporUmum((int) (currentProgress));
pfos.close();
} catch (Exception ignored) {}
}
}
if (!isM4a) {
fosWav.write(bbOut.array(), 0, chunkBytes);
totalBytesWritten += chunkBytes;
} else {
int inIdx = -1;
while (inIdx < 0) {
inIdx = encoder.dequeueInputBuffer(10000);
if (inIdx >= 0) {
ByteBuffer inBuf = encoder.getInputBuffer(inIdx);
inBuf.clear();
inBuf.put(bbOut.array(), 0, chunkBytes);
encoder.queueInputBuffer(inIdx, 0, chunkBytes, ptsUs, 0);
ptsUs += (long) chunkBytes * 1000000L / bytesPerSec;
}
while (true) {
int outIdx = encoder.dequeueOutputBuffer(info, 10000);
if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
trackIdx = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (outIdx >= 0) {
ByteBuffer outBuf = encoder.getOutputBuffer(outIdx);
if (info.size > 0 && muxStarted) {
outBuf.position(info.offset);
outBuf.limit(info.offset + info.size);
muxer.writeSampleData(trackIdx, outBuf, info);
}
encoder.releaseOutputBuffer(outIdx, false);
} else {
break;
}
}
}
}
}
for (int i = 0; i < numTracks; i++) {
if (rafs[i] != null) try { rafs[i].close(); } catch (Exception ignored) {}
}
if (!isM4a) {
fosWav.close();
RandomAccessFile rafWav = new RandomAccessFile(outPath, "rw");
rafWav.seek(0);
ByteBuffer head = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
head.put("RIFF".getBytes()); head.putInt((int)totalBytesWritten + 36);
head.put("WAVE".getBytes()); head.put("fmt ".getBytes());
head.putInt(16); head.putShort((short)1); head.putShort((short)channels);
head.putInt(sampleRate); head.putInt((int)bytesPerSec);
head.putShort((short)frameSize); head.putShort((short)16);
head.put("data".getBytes()); head.putInt((int)totalBytesWritten);
rafWav.write(head.array());
rafWav.close();
} else {
int inIdx = -1;
while (inIdx < 0) {
inIdx = encoder.dequeueInputBuffer(10000);
if (inIdx >= 0) {
encoder.queueInputBuffer(inIdx, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
} else {
while (true) {
int outIdx = encoder.dequeueOutputBuffer(info, 10000);
if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
trackIdx = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (outIdx >= 0) {
ByteBuffer outBuf = encoder.getOutputBuffer(outIdx);
if (info.size > 0 && muxStarted) {
outBuf.position(info.offset);
outBuf.limit(info.offset + info.size);
muxer.writeSampleData(trackIdx, outBuf, info);
}
encoder.releaseOutputBuffer(outIdx, false);
} else {
break;
}
}
}
}
while (true) {
int outIdx = encoder.dequeueOutputBuffer(info, 10000);
if (outIdx >= 0) {
ByteBuffer outBuf = encoder.getOutputBuffer(outIdx);
if (info.size > 0 && muxStarted) {
outBuf.position(info.offset);
outBuf.limit(info.offset + info.size);
muxer.writeSampleData(trackIdx, outBuf, info);
}
encoder.releaseOutputBuffer(outIdx, false);
if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break;
} else if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
trackIdx = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) {
break;
}
}
encoder.stop(); encoder.release();
if (muxStarted) { muxer.stop(); muxer.release(); }
}
new File(progFile).delete();
return "SUKSES";
} catch (Exception e) {
if (rafs != null) {
for (RandomAccessFile r : rafs) {
if (r != null) try { r.close(); } catch (Exception ignored) {}
}
}
return "ERROR: " + e.getMessage();
}
}

public static String prosesAudio(String micPath, String intPath, String outPath, int format, int sampleRate, int channels, int bitrate, float volM, float volI) {
tahap("Menerapkan efek suara");
try {
File fMic = new File(micPath);
File fInt = new File(intPath);
boolean hasMic = fMic.exists() && fMic.length() > 44;
boolean hasInt = fInt.exists() && fInt.length() > 44;
if (!hasMic && !hasInt) return "SUKSES_KOSONG";
String originalMicPath = micPath;
long micSkip = 44;
long intSkip = 44;
if (hasMic && hasInt) {
long micTime = 0;
long intTime = 0;
try {
BufferedReader brM = new BufferedReader(new FileReader(originalMicPath + ".time"));
micTime = Long.parseLong(brM.readLine().trim());
brM.close();
} catch (Exception ignored) {}
try {
BufferedReader brI = new BufferedReader(new FileReader(intPath + ".time"));
intTime = Long.parseLong(brI.readLine().trim());
brI.close();
} catch (Exception ignored) {}
if (micTime > 0 && intTime > 0) {
long delta = Math.abs(micTime - intTime);
long skipBytes = (delta * sampleRate * channels * 2) / 1000;
skipBytes = skipBytes - (skipBytes % (channels * 2));
if (micTime < intTime) {
micSkip += skipBytes;
} else if (intTime < micTime) {
intSkip += skipBytes;
}
}
}
float pitchSemitone = 0f;
boolean pitchLanjut = false, pitchGl = false;
float pitchG0 = 0f, pitchG1 = 0f, pitchGd = 0f;
File fDir = new File(outPath).getParentFile();
try {
File pFile = new File(fDir, "_pitch.cfg");
if (pFile.exists()) {
BufferedReader br = new BufferedReader(new FileReader(pFile));
pitchSemitone = Float.parseFloat(br.readLine().trim());
String lnP2 = br.readLine();
if (lnP2 != null && (lnP2.trim().startsWith("LANJUT") || lnP2.trim().startsWith("STD"))) {
String[] qp = lnP2.trim().split(",");
if (qp.length >= 5) {
pitchLanjut = lnP2.trim().startsWith("LANJUT");
pitchGl = "1".equals(qp[1].trim());
pitchG0 = Float.parseFloat(qp[2].trim());
pitchG1 = Float.parseFloat(qp[3].trim());
pitchGd = Float.parseFloat(qp[4].trim());
}
}
br.close();
pFile.delete();
}
} catch (Exception ignored) {}
boolean pitchLanjutSelesai = false;
if (pitchLanjut && hasMic && (pitchSemitone != 0 || pitchGl)) {
try {
if (muatNativeSuaraDua() && nadiVer >= 2) {
SuaraDuaCfg pcfg = SuaraDuaCfg.untukPitch(pitchSemitone, pitchGl, pitchG0, pitchG1, pitchGd);
File fOutPl = new File(micPath + ".pitchlj.raw");
String rPl = jalankanSuaraDua(fMic.getAbsolutePath(), fOutPl.getAbsolutePath(), (int) micSkip, 44, sampleRate, channels, pcfg, null);
if ("OK".equals(rPl) && fOutPl.exists() && fOutPl.length() > 44) {
if (!fMic.getAbsolutePath().equals(originalMicPath)) fMic.delete();
fMic = fOutPl;
micPath = fOutPl.getAbsolutePath();
micSkip = 44;
pitchLanjutSelesai = true;
}
}
} catch (Throwable ignoredPl) {}
}
if ((pitchSemitone != 0 || pitchGl) && hasMic && !pitchLanjutSelesai) {
float pitchRatio = (float) Math.pow(2.0, semitonGeser(pitchGl, pitchSemitone, pitchG0, pitchG1, pitchGd, 0L, 1L, sampleRate) / 12.0);
long pitchFramesTotal = (fMic.length() - micSkip) / (2L * channels);
long pitchFramesDone = 0L;
File fMicPitch = new File(micPath + ".pitch.raw");
boolean pitchNatB = false;
if (sonicNativeSiap()) {
try {
pitchNatB = sonicNative(fMic.getAbsolutePath(), (long) micSkip, 0L, fMicPitch, 44, sampleRate, channels, pitchRatio, pitchGl, pitchG0, pitchG1, pitchGd, pitchFramesTotal, 0L);
} catch (Throwable t) { pitchNatB = false; }
}
if (!pitchNatB) {
Sonic sonic = new Sonic(sampleRate, channels);
sonic.setPitch(pitchRatio);
RandomAccessFile inRaf = new RandomAccessFile(fMic, "r");
FileOutputStream outFos = new FileOutputStream(fMicPitch);
inRaf.seek(micSkip);
outFos.write(new byte[44]);
byte[] inBuffer = new byte[8192];
short[] shortBuffer = new short[4096];
byte[] outBuffer = new byte[8192];
while(true) {
int read = inRaf.read(inBuffer);
if (read <= 0) break;
int numShorts = read / 2;
ByteBuffer.wrap(inBuffer, 0, read).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(shortBuffer, 0, numShorts);
if (pitchGl) sonic.setPitch((float) Math.pow(2.0, semitonGeser(pitchGl, pitchSemitone, pitchG0, pitchG1, pitchGd, pitchFramesDone, pitchFramesTotal, sampleRate) / 12.0));
sonic.putSamples(shortBuffer, numShorts / channels);
pitchFramesDone += numShorts / channels;
while(true) {
int samplesRead = sonic.receiveSamples(shortBuffer, shortBuffer.length / channels);
if (samplesRead <= 0) break;
int bytesToWrite = samplesRead * channels * 2;
ByteBuffer bb = ByteBuffer.wrap(outBuffer, 0, bytesToWrite).order(ByteOrder.LITTLE_ENDIAN);
for (int i=0; i<samplesRead * channels; i++) bb.putShort(shortBuffer[i]);
outFos.write(outBuffer, 0, bytesToWrite);
}
}
sonic.flush();
while(true) {
int samplesRead = sonic.receiveSamples(shortBuffer, shortBuffer.length / channels);
if (samplesRead <= 0) break;
int bytesToWrite = samplesRead * channels * 2;
ByteBuffer bb = ByteBuffer.wrap(outBuffer, 0, bytesToWrite).order(ByteOrder.LITTLE_ENDIAN);
for (int i=0; i<samplesRead * channels; i++) bb.putShort(shortBuffer[i]);
outFos.write(outBuffer, 0, bytesToWrite);
}
inRaf.close();
outFos.close();
}
fMic = fMicPitch;
micPath = fMicPitch.getAbsolutePath();
micSkip = 44;
}
int atAktif = 0, atKey = 0, atScale = 0;
float atSpeed = 80f;
try {
File atFile = new File(fDir, "_autotune.cfg");
if (atFile.exists()) {
BufferedReader brAt = new BufferedReader(new FileReader(atFile));
String[] atParts = brAt.readLine().trim().split(",");
brAt.close();
atFile.delete();
if (atParts.length >= 4) {
atAktif = Integer.parseInt(atParts[0].trim());
atKey = Math.round(Float.parseFloat(atParts[1].trim()));
atScale = Math.round(Float.parseFloat(atParts[2].trim()));
atSpeed = Float.parseFloat(atParts[3].trim());
}
}
} catch (Exception ignored) {}
if (atAktif == 1 && hasMic) {
File fMicAt = new File(originalMicPath + ".autotune.raw");
RandomAccessFile atRaf = new RandomAccessFile(fMic, "r");
long availAtBytes = fMic.length() - micSkip;
availAtBytes -= (availAtBytes % (channels * 2));
if (availAtBytes > 0) {
boolean atNatB = false;
if (sonicNativeSiap()) {
try { atNatB = autoTuneNative(fMic.getAbsolutePath(), (long) micSkip, availAtBytes, fMicAt, 44, sampleRate, channels, atKey, atScale, atSpeed); } catch (Throwable t) { atNatB = false; }
}
if (!atNatB) AutoTune.prosesRafKeFile(atRaf, micSkip, availAtBytes, fMicAt, true, sampleRate, channels, atKey, atScale, atSpeed);
}
atRaf.close();
if (pitchSemitone != 0 && !fMic.getAbsolutePath().equals(originalMicPath)) {
fMic.delete();
}
if (fMicAt.exists() && fMicAt.length() > 44) {
fMic = fMicAt;
micPath = fMicAt.getAbsolutePath();
micSkip = 44;
}
}
File fMicSuaraDua = null;
try {
File sdFile = new File(fDir, "_suaradua.cfg");
if (sdFile.exists()) {
BufferedReader brSd = new BufferedReader(new FileReader(sdFile));
String lineSd = brSd.readLine();
brSd.close();
sdFile.delete();
SuaraDuaCfg sdc = SuaraDuaCfg.parse(lineSd);
if (sdc.ada && hasMic) {
File fOutSd = new File(originalMicPath + ".suaradua.raw");
String rSd = jalankanSuaraDua(fMic.getAbsolutePath(), fOutSd.getAbsolutePath(), (int) micSkip, 44, sampleRate, channels, sdc, null);
if ("OK".equals(rSd) && fOutSd.exists() && fOutSd.length() > 44) {
if (!fMic.getAbsolutePath().equals(originalMicPath)) fMic.delete();
fMic = fOutSd;
micPath = fOutSd.getAbsolutePath();
micSkip = 44;
fMicSuaraDua = fOutSd;
}
}
}
} catch (Throwable ignoredSd) {}
int gateTarget = 0;
float gateThresh = 0f, gateAtt = 5f, gateRel = 100f;
try {
File gFile = new File(fDir, "_gate.cfg");
if (gFile.exists()) {
BufferedReader br = new BufferedReader(new FileReader(gFile));
String[] parts = br.readLine().trim().split(",");
br.close();
gFile.delete();
if(parts.length >= 4) {
gateTarget = Integer.parseInt(parts[0].trim());
gateThresh = Float.parseFloat(parts[1].trim());
gateAtt = Float.parseFloat(parts[2].trim());
gateRel = Float.parseFloat(parts[3].trim());
}
}
} catch (Exception ignored) {}
NoiseGate[] gates = null;
if (gateTarget > 0 && gateThresh > 0f) {
gates = new NoiseGate[channels];
for(int i=0; i<channels; i++) {
gates[i] = new NoiseGate(sampleRate, gateThresh, gateAtt, gateRel);
}
}
int echoTarget = 0;
float echoDelayMs = 0f, echoFeedback = 0f, echoDamp = 0f, echoDry = 0f, echoWet = 0f, echoStereo = 0f;
try {
File eFile = new File(fDir, "_echo.cfg");
if (eFile.exists()) {
BufferedReader br = new BufferedReader(new FileReader(eFile));
String[] parts = br.readLine().trim().split(",");
br.close();
eFile.delete();
if(parts.length >= 6) {
echoTarget = Integer.parseInt(parts[0].trim());
echoDelayMs = Float.parseFloat(parts[1].trim());
echoFeedback = Float.parseFloat(parts[2].trim());
echoDamp = Float.parseFloat(parts[3].trim());
echoDry = Float.parseFloat(parts[4].trim());
echoWet = Float.parseFloat(parts[5].trim());
if (parts.length >= 7) echoStereo = Math.max(0f, Math.min(1f, Float.parseFloat(parts[6].trim())));
}
}
} catch (Exception ignored) {}
Echo[] echos = null;
if (echoTarget > 0) {
echos = new Echo[channels];
for(int i=0; i<channels; i++) {
echos[i] = new Echo(sampleRate);
float dlyKanal = (channels >= 2 && i == 1) ? echoDelayMs * (1.0f + 0.5f * echoStereo) : echoDelayMs;
echos[i].setParameters(dlyKanal, echoFeedback, echoDamp, echoDry, echoWet);
}
}
int rvbTarget = 0;
float rvbRoom = 0f, rvbDamp = 0f, rvbDry = 0f, rvbWet = 0f, rvbStereo = 0f;
try {
File rFile = new File(fDir, "_reverb.cfg");
if (rFile.exists()) {
BufferedReader br = new BufferedReader(new FileReader(rFile));
String[] parts = br.readLine().trim().split(",");
br.close();
rFile.delete();
if(parts.length >= 5) {
rvbTarget = Integer.parseInt(parts[0].trim());
rvbRoom = Float.parseFloat(parts[1].trim());
rvbDamp = Float.parseFloat(parts[2].trim());
rvbDry = Float.parseFloat(parts[3].trim());
rvbWet = Float.parseFloat(parts[4].trim());
if (parts.length >= 6) rvbStereo = Math.max(0f, Math.min(1f, Float.parseFloat(parts[5].trim())));
}
}
} catch (Exception ignored) {}
Freeverb[] fvs = null;
if (rvbTarget > 0) {
fvs = new Freeverb[channels];
for(int i=0; i<channels; i++) {
int spreadKanal = (channels >= 2 && i == 1) ? (int) (rvbStereo * 120f * ((float) sampleRate / 44100.0f)) : 0;
fvs[i] = new Freeverb(sampleRate, spreadKanal);
fvs[i].setRoomSize(rvbRoom);
fvs[i].setDamp(rvbDamp);
fvs[i].setDry(rvbDry);
fvs[i].setWet(rvbWet);
}
}
int toneTarget = 0;
float toneBass = 50f, toneTreble = 50f;
float[] toneBand = {50f, 50f, 50f, 50f, 50f};
try {
File tFile = new File(fDir, "_tone.cfg");
if (tFile.exists()) {
BufferedReader br = new BufferedReader(new FileReader(tFile));
String[] parts = br.readLine().trim().split(",");
br.close();
tFile.delete();
if (parts.length >= 8) {
toneTarget = Integer.parseInt(parts[0].trim());
toneBass = Float.parseFloat(parts[1].trim());
toneTreble = Float.parseFloat(parts[2].trim());
for (int i = 0; i < 5; i++) toneBand[i] = Float.parseFloat(parts[3 + i].trim());
}
}
} catch (Exception ignored) { toneTarget = 0; }
Tone[] tones = null;
if (toneTarget > 0) {
Tone[] cand = new Tone[channels];
for (int i = 0; i < channels; i++) cand[i] = new Tone(sampleRate, toneBass, toneTreble, toneBand);
if (cand[0].aktif()) tones = cand;
}
RandomAccessFile rafMic = hasMic ? new RandomAccessFile(fMic, "r") : null;
RandomAccessFile rafInt = hasInt ? new RandomAccessFile(fInt, "r") : null;
if (rafMic != null) rafMic.seek(micSkip);
if (rafInt != null) rafInt.seek(intSkip);
FileOutputStream fosWav = null;
MediaCodec encoder = null;
MediaMuxer muxer = null;
int trackIdx = -1;
boolean muxStarted = false;
long ptsUs = 0;
long totalBytes = 0;
boolean isM4a = (format == 2);
long totalFileLen = Math.max((fMic != null && fMic.exists() ? fMic.length() : 0), (fInt != null && fInt.exists() ? fInt.length() : 0));
long currentReadLen = 0;
int lastProgress = 0;
String progFile = outPath + ".prog";
if (!isM4a) {
fosWav = new FileOutputStream(outPath);
fosWav.write(new byte[44]);
} else {
MediaFormat f = MediaFormat.createAudioFormat("audio/mp4a-latm", sampleRate, channels);
f.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC);
f.setInteger(MediaFormat.KEY_BIT_RATE, bitrate);
f.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 524288);
encoder = MediaCodec.createEncoderByType("audio/mp4a-latm");
encoder.configure(f, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
encoder.start();
muxer = new MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
}
int bufSize = 32768;
byte[] bM = new byte[bufSize];
byte[] bI = new byte[bufSize];
ByteBuffer bbOut = ByteBuffer.allocate(bufSize).order(ByteOrder.LITTLE_ENDIAN);
MediaCodec.BufferInfo info = isM4a ? new MediaCodec.BufferInfo() : null;
boolean readEOF = false;
while (!readEOF) {
int rM = (rafMic != null) ? rafMic.read(bM) : -1;
int rI = (rafInt != null) ? rafInt.read(bI) : -1;
if (rM <= 0 && rI <= 0) {
readEOF = true;
}
int lenM = Math.max(rM, 0);
int lenI = Math.max(rI, 0);
int maxLen = Math.max(lenM, lenI);
int maxShorts = maxLen / 2;
currentReadLen += maxLen;
if (totalFileLen > 0) {
int currentProgress = (int) ((currentReadLen * 100) / totalFileLen);
if (currentProgress > lastProgress && currentProgress <= 100) {
lastProgress = currentProgress;
try {
FileOutputStream pfos = new FileOutputStream(progFile);
pfos.write(String.valueOf(currentProgress).getBytes()); laporUmum((int) (currentProgress));
pfos.close();
} catch(Exception ignored) {}
}
}
if (maxShorts > 0) {
bbOut.clear();
ByteBuffer bbMic = ByteBuffer.wrap(bM, 0, lenM).order(ByteOrder.LITTLE_ENDIAN);
ByteBuffer bbInt = ByteBuffer.wrap(bI, 0, lenI).order(ByteOrder.LITTLE_ENDIAN);
for (int i = 0; i < maxShorts; i++) {
short sM = bbMic.hasRemaining() ? bbMic.getShort() : 0;
short sI = bbInt.hasRemaining() ? bbInt.getShort() : 0;
int chIdx = i % channels;
if (gates != null) {
if (gateTarget == 1) sM = gates[chIdx].process(sM);
else if (gateTarget == 2) sI = gates[chIdx].process(sI);
}
if (tones != null) {
if (toneTarget == 1) sM = tones[chIdx].process(sM);
else if (toneTarget == 2) sI = tones[chIdx].process(sI);
}
if (echos != null) {
if (echoTarget == 1) sM = echos[chIdx].process(sM);
else if (echoTarget == 2) sI = echos[chIdx].process(sI);
}
if (fvs != null) {
if (rvbTarget == 1) sM = fvs[chIdx].process(sM);
else if (rvbTarget == 2) sI = fvs[chIdx].process(sI);
}
int mixed = (int)((sM * volM) + (sI * volI));
if (mixed > 32767) mixed = 32767;
else if (mixed < -32768) mixed = -32768;
if (gates != null && gateTarget == 3) {
mixed = (int) gates[chIdx].process((short)mixed);
}
if (echos != null && echoTarget == 3) {
mixed = (int) echos[chIdx].process((short)mixed);
}
if (fvs != null && rvbTarget == 3) {
mixed = (int) fvs[chIdx].process((short)mixed);
}
if (tones != null && toneTarget == 3) {
mixed = (int) tones[chIdx].process((short)mixed);
}
bbOut.putShort((short)mixed);
}
int bytesToWrite = maxShorts * 2;
if (!isM4a) {
fosWav.write(bbOut.array(), 0, bytesToWrite);
totalBytes += bytesToWrite;
} else {
int inIdx = -1;
while (inIdx < 0) {
inIdx = encoder.dequeueInputBuffer(10000);
if (inIdx >= 0) {
ByteBuffer inBuf = encoder.getInputBuffer(inIdx);
inBuf.clear();
inBuf.put(bbOut.array(), 0, bytesToWrite);
encoder.queueInputBuffer(inIdx, 0, bytesToWrite, ptsUs, 0);
ptsUs += (long) bytesToWrite * 1000000L / (sampleRate * channels * 2);
}
while (true) {
int outIdx = encoder.dequeueOutputBuffer(info, 10000);
if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
trackIdx = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (outIdx >= 0) {
ByteBuffer outBuf = encoder.getOutputBuffer(outIdx);
if (info.size > 0 && muxStarted) {
outBuf.position(info.offset);
outBuf.limit(info.offset + info.size);
muxer.writeSampleData(trackIdx, outBuf, info);
}
encoder.releaseOutputBuffer(outIdx, false);
} else {
break;
}
}
}
}
}
}
if (rafMic != null) rafMic.close();
if (fMicSuaraDua != null) fMicSuaraDua.delete();
if (rafInt != null) rafInt.close();
if ((pitchSemitone != 0 || atAktif == 1) && hasMic && !micPath.equals(originalMicPath)) {
new File(micPath).delete();
}
if (!isM4a) {
fosWav.close();
RandomAccessFile rafWav = new RandomAccessFile(outPath, "rw");
rafWav.seek(0);
ByteBuffer head = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
head.put("RIFF".getBytes()); head.putInt((int)totalBytes + 36);
head.put("WAVE".getBytes()); head.put("fmt ".getBytes());
head.putInt(16); head.putShort((short)1); head.putShort((short)channels);
head.putInt(sampleRate); head.putInt(sampleRate * channels * 2);
head.putShort((short)(channels * 2)); head.putShort((short)16);
head.put("data".getBytes()); head.putInt((int)totalBytes);
rafWav.write(head.array());
rafWav.close();
} else {
int inIdx = -1;
while (inIdx < 0) {
inIdx = encoder.dequeueInputBuffer(10000);
if (inIdx >= 0) {
encoder.queueInputBuffer(inIdx, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
} else {
while (true) {
int outIdx = encoder.dequeueOutputBuffer(info, 10000);
if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
trackIdx = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (outIdx >= 0) {
ByteBuffer outBuf = encoder.getOutputBuffer(outIdx);
if (info.size > 0 && muxStarted) {
outBuf.position(info.offset);
outBuf.limit(info.offset + info.size);
muxer.writeSampleData(trackIdx, outBuf, info);
}
encoder.releaseOutputBuffer(outIdx, false);
} else {
break;
}
}
}
}
while (true) {
int outIdx = encoder.dequeueOutputBuffer(info, 10000);
if (outIdx >= 0) {
ByteBuffer outBuf = encoder.getOutputBuffer(outIdx);
if (info.size > 0 && muxStarted) {
outBuf.position(info.offset);
outBuf.limit(info.offset + info.size);
muxer.writeSampleData(trackIdx, outBuf, info);
}
encoder.releaseOutputBuffer(outIdx, false);
if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break;
} else if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
trackIdx = muxer.addTrack(encoder.getOutputFormat());
muxer.start();
muxStarted = true;
} else if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) {
break;
}
}
encoder.stop(); encoder.release();
if (muxStarted) { muxer.stop(); muxer.release(); }
}
new File(progFile).delete();
return "SUKSES";
} catch (Exception e) {
return "ERROR: " + e.getMessage();
}
}

private static class NoiseGate {
private float threshold;
private float attackCoef;
private float releaseCoef;
private float envelope = 0f;
private float gain = 1f;
public NoiseGate(int sampleRate, float thresholdPct, float attackMs, float releaseMs) {
this.threshold = (thresholdPct / 100f) * 8192f;
if (attackMs <= 0.1f) attackMs = 0.1f;
if (releaseMs <= 0.1f) releaseMs = 0.1f;
this.attackCoef = (float) Math.exp(-1000.0 / (sampleRate * attackMs));
this.releaseCoef = (float) Math.exp(-1000.0 / (sampleRate * releaseMs));
}
// Mengganti pengaturan tanpa mengosongkan envelope dan gain (untuk pemutar langsung).
public void atur(int sampleRate, float thresholdPct, float attackMs, float releaseMs) {
this.threshold = (thresholdPct / 100f) * 8192f;
if (attackMs <= 0.1f) attackMs = 0.1f;
if (releaseMs <= 0.1f) releaseMs = 0.1f;
this.attackCoef = (float) Math.exp(-1000.0 / (sampleRate * attackMs));
this.releaseCoef = (float) Math.exp(-1000.0 / (sampleRate * releaseMs));
}
public void kosongkan() { envelope = 0f; gain = 1f; }
public short process(short input) {
if (threshold <= 0f) return input;
float absIn = Math.abs((float)input);
if (absIn > envelope) {
envelope = attackCoef * envelope + (1.0f - attackCoef) * absIn;
} else {
envelope = releaseCoef * envelope + (1.0f - releaseCoef) * absIn;
}
float targetGain = (envelope > threshold) ? 1.0f : 0.0f;
if (targetGain > gain) {
gain = attackCoef * gain + (1.0f - attackCoef) * targetGain;
} else {
gain = releaseCoef * gain + (1.0f - releaseCoef) * targetGain;
}
return (short)(input * gain);
}
}

private static class Echo {
private float[] buffer;
private int bufIdx = 0;
private int delaySamples = 0;
private float feedback = 0f;
private float damping = 0f;
private float dry = 1.0f;
private float wet = 0f;
private float filterStore = 0f;
public Echo(int sampleRate) {
buffer = new float[sampleRate * 2];
}
public void setParameters(float delayMs, float feedback, float damping, float dry, float wet) {
this.delaySamples = (int)((delayMs / 1000.0f) * (buffer.length / 2));
if (this.delaySamples == 0) this.delaySamples = 1;
if (this.delaySamples > buffer.length) this.delaySamples = buffer.length;
this.feedback = feedback;
this.damping = damping;
this.dry = dry;
this.wet = wet;
this.bufIdx = 0;
this.filterStore = 0f;
for(int i=0; i<buffer.length; i++) buffer[i] = 0f;
}
public short process(short input) {
if (delaySamples <= 1) {
float mixed = (input * dry) + (input * wet);
if (mixed > 32767.0f) mixed = 32767.0f;
if (mixed < -32768.0f) mixed = -32768.0f;
return (short)mixed;
}
float in = (float)input;
float bufOut = buffer[bufIdx];
filterStore = (bufOut * (1.0f - damping)) + (filterStore * damping);
buffer[bufIdx] = in + (filterStore * feedback);
bufIdx++;
if (bufIdx >= delaySamples) bufIdx = 0;
float mixed = (in * dry) + (bufOut * wet);
if (mixed > 32767.0f) mixed = 32767.0f;
if (mixed < -32768.0f) mixed = -32768.0f;
return (short)mixed;
}
}

private static class Tone {
static final double BASS_HZ = 120.0;
static final double TREBLE_HZ = 6000.0;
static final double[] BAND_HZ = {60.0, 250.0, 1000.0, 4000.0, 12000.0};
static final double RANGE_SHELF_DB = 15.0;
static final double RANGE_BAND_DB = 12.0;
static final double BAND_Q = 1.0;
static final double AMBANG_LEMBUT = 26000.0;
private static class Biquad {
double b0, b1, b2, a1, a2;
double x1, x2, y1, y2;
double process(double x) {
double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
x2 = x1; x1 = x;
y2 = y1; y1 = y;
return y;
}
}
private final Biquad[] stages = new Biquad[7];
private int count = 0;
private final double fs;
public Tone(int sampleRate, float bassPct, float treblePct, float[] bandPct) {
this.fs = sampleRate;
double maxF = 0.45 * fs;
double dbBass = pctKeDb(bassPct, RANGE_SHELF_DB);
if (Math.abs(dbBass) >= 0.05) tambahShelf(true, Math.min(BASS_HZ, maxF), dbBass);
for (int i = 0; i < 5; i++) {
double db = pctKeDb(bandPct[i], RANGE_BAND_DB);
if (Math.abs(db) >= 0.05 && BAND_HZ[i] <= maxF) tambahPeaking(BAND_HZ[i], db);
}
double dbTreble = pctKeDb(treblePct, RANGE_SHELF_DB);
if (Math.abs(dbTreble) >= 0.05) tambahShelf(false, Math.min(TREBLE_HZ, maxF), dbTreble);
}
public boolean aktif() { return count > 0; }
static double pctKeDb(float pct, double range) {
if (pct < 0f) pct = 0f;
if (pct > 100f) pct = 100f;
return ((pct - 50.0) / 50.0) * range;
}
private void simpan(double b0, double b1, double b2, double a0, double a1, double a2) {
Biquad q = new Biquad();
q.b0 = b0 / a0; q.b1 = b1 / a0; q.b2 = b2 / a0;
q.a1 = a1 / a0; q.a2 = a2 / a0;
stages[count++] = q;
}
private void tambahShelf(boolean rendah, double f0, double dB) {
double A = Math.pow(10.0, dB / 40.0);
double w0 = 2.0 * Math.PI * f0 / fs;
double cs = Math.cos(w0);
double sn = Math.sin(w0);
double alpha = sn / 2.0 * Math.sqrt(2.0);
double t = 2.0 * Math.sqrt(A) * alpha;
if (rendah) {
simpan(A * ((A + 1) - (A - 1) * cs + t),
2.0 * A * ((A - 1) - (A + 1) * cs),
A * ((A + 1) - (A - 1) * cs - t),
(A + 1) + (A - 1) * cs + t,
-2.0 * ((A - 1) + (A + 1) * cs),
(A + 1) + (A - 1) * cs - t);
} else {
simpan(A * ((A + 1) + (A - 1) * cs + t),
-2.0 * A * ((A - 1) + (A + 1) * cs),
A * ((A + 1) + (A - 1) * cs - t),
(A + 1) - (A - 1) * cs + t,
2.0 * ((A - 1) - (A + 1) * cs),
(A + 1) - (A - 1) * cs - t);
}
}
private void tambahPeaking(double f0, double dB) {
double A = Math.pow(10.0, dB / 40.0);
double w0 = 2.0 * Math.PI * f0 / fs;
double cs = Math.cos(w0);
double alpha = Math.sin(w0) / (2.0 * BAND_Q);
simpan(1.0 + alpha * A, -2.0 * cs, 1.0 - alpha * A,
1.0 + alpha / A, -2.0 * cs, 1.0 - alpha / A);
}
private static double lembut(double v) {
double a = Math.abs(v);
if (a <= AMBANG_LEMBUT) return v;
double sisa = 32767.0 - AMBANG_LEMBUT;
double y = AMBANG_LEMBUT + sisa * Math.tanh((a - AMBANG_LEMBUT) / sisa);
return v < 0 ? -y : y;
}
public short process(short input) {
double v = input;
for (int i = 0; i < count; i++) v = stages[i].process(v);
return (short) Math.round(lembut(v));
}
}

// Bass & Treble + Ekualiser 5 band yang pengaturannya boleh diubah kapan saja saat memutar (real time).
// Urutan p: bass %, treble %, pita 60 Hz, 250 Hz, 1 kHz, 4 kHz, 12 kHz (50 = netral).
// Memakai mesin C++ (nadivoice versi 11 ke atas, peralihan nilai dibuat mulus). Bila mesin belum ada atau
// lebih lama, dipakai cadangan Java (kelas Tone yang sama dengan hasil simpan; filter dibangun ulang tiap
// perubahan). Hanya boleh dipakai dari SATU thread pemutar.
private interface PcmFx {
    void atur(float[] p);
    void reset();
    void proses(byte[] buf, int nBingkai);
    void lepas();
}

private static final class ToneLive implements PcmFx {
    private final int sr, ch;
    private long h = 0L;
    private Tone[] jv = null;
    private float[] terakhir = {50f, 50f, 50f, 50f, 50f, 50f, 50f};
    private boolean sudahAtur = false;

    ToneLive(int sr, int ch) {
        this.sr = sr;
        this.ch = Math.max(1, Math.min(2, ch));
        try {
            if (muatNativeSuaraDua() && nadiVer >= 11) h = nvEqBuat(sr, this.ch);
        } catch (Throwable t) {
            h = 0L;
        }
    }

    boolean mesinCpp() { return h != 0L; }

    private void bangunJava() {
        Tone[] cand = new Tone[ch];
        float[] pita = {terakhir[2], terakhir[3], terakhir[4], terakhir[5], terakhir[6]};
        for (int c = 0; c < ch; c++) cand[c] = new Tone(sr, terakhir[0], terakhir[1], pita);
        jv = cand[0].aktif() ? cand : null;
    }

    public void atur(float[] p) {
        if (p == null || p.length < 7) return;
        float[] q = new float[7];
        for (int i = 0; i < 7; i++) {
            float v = p[i];
            if (!(v >= 0f)) v = 0f;
            if (v > 100f) v = 100f;
            q[i] = v;
        }
        terakhir = q;
        if (h != 0L) {
            try {
                if (nvEqAtur(h, q, 7) == 1) { sudahAtur = true; return; }
            } catch (Throwable t) {
                android.util.Log.w("NadiMesin", "ekualiser C++ gagal, memakai Java: " + t);
            }
            h = 0L;
        }
        bangunJava();
        sudahAtur = true;
    }

    // Mengosongkan keadaan filter (setelah pindah posisi) supaya sisa gelombang lama tidak ikut terdengar.
    public void reset() {
        if (h != 0L) {
            try { nvEqReset(h); } catch (Throwable ignored) {}
        } else if (sudahAtur) {
            bangunJava();
        }
    }

    // Memproses nBingkai bingkai PCM 16-bit sisip (byte little-endian) di tempat.
    public void proses(byte[] buf, int nBingkai) {
        if (!sudahAtur || nBingkai <= 0) return;
        if (h != 0L) {
            try {
                if (nvEqProses(h, buf, nBingkai) == 1) return;
            } catch (Throwable t) {
                android.util.Log.w("NadiMesin", "ekualiser C++ gagal, memakai Java: " + t);
            }
            h = 0L;
            bangunJava();
        }
        if (jv == null) return;
        for (int f = 0; f < nBingkai; f++) {
            for (int c = 0; c < ch; c++) {
                int k = (f * ch + c) * 2;
                short v = (short) ((buf[k] & 0xFF) | (buf[k + 1] << 8));
                v = jv[c].process(v);
                buf[k] = (byte) (v & 0xFF);
                buf[k + 1] = (byte) ((v >> 8) & 0xFF);
            }
        }
    }

    public void lepas() {
        long x = h;
        h = 0L;
        if (x != 0L) {
            try { nvEqLepas(x); } catch (Throwable ignored) {}
        }
    }
}

// Pengurang Kebisingan (noise gate) yang pengaturannya boleh diubah kapan saja saat memutar (real time).
// Urutan p: sensitivitas %, attack md, release md. Memakai mesin C++ (nadivoice versi 12 ke atas); bila belum
// ada, dipakai kelas NoiseGate Java yang sama dengan hasil simpan. Hanya dari SATU thread pemutar.
private static final class GateLive implements PcmFx {
    private final int sr, ch;
    private long h = 0L;
    private NoiseGate[] jv = null;
    private float[] terakhir = {0f, 5f, 150f};
    private boolean sudahAtur = false;

    GateLive(int sr, int ch) {
        this.sr = sr;
        this.ch = Math.max(1, Math.min(2, ch));
        try {
            if (muatNativeSuaraDua() && nadiVer >= 12) h = nvGateBuat(sr, this.ch);
        } catch (Throwable t) {
            h = 0L;
        }
    }

    private void aturJava() {
        if (jv == null) {
            jv = new NoiseGate[ch];
            for (int c = 0; c < ch; c++) jv[c] = new NoiseGate(sr, terakhir[0], terakhir[1], terakhir[2]);
        } else {
            for (int c = 0; c < ch; c++) jv[c].atur(sr, terakhir[0], terakhir[1], terakhir[2]);
        }
    }

    public void atur(float[] p) {
        if (p == null || p.length < 3) return;
        float pct = p[0];
        if (!(pct >= 0f)) pct = 0f;
        if (pct > 100f) pct = 100f;
        terakhir = new float[]{pct, p[1], p[2]};
        if (h != 0L) {
            try {
                if (nvGateAtur(h, terakhir, 3) == 1) { sudahAtur = true; return; }
            } catch (Throwable t) {
                android.util.Log.w("NadiMesin", "noise gate C++ gagal, memakai Java: " + t);
            }
            h = 0L;
        }
        aturJava();
        sudahAtur = true;
    }

    public void reset() {
        if (h != 0L) {
            try { nvGateReset(h); } catch (Throwable ignored) {}
        } else if (jv != null) {
            for (int c = 0; c < ch; c++) jv[c].kosongkan();
        }
    }

    public void proses(byte[] buf, int nBingkai) {
        if (!sudahAtur || nBingkai <= 0) return;
        if (h != 0L) {
            try {
                if (nvGateProses(h, buf, nBingkai) == 1) return;
            } catch (Throwable t) {
                android.util.Log.w("NadiMesin", "noise gate C++ gagal, memakai Java: " + t);
            }
            h = 0L;
            aturJava();
        }
        if (jv == null) return;
        for (int f = 0; f < nBingkai; f++) {
            for (int c = 0; c < ch; c++) {
                int k = (f * ch + c) * 2;
                short v = (short) ((buf[k] & 0xFF) | (buf[k + 1] << 8));
                v = jv[c].process(v);
                buf[k] = (byte) (v & 0xFF);
                buf[k + 1] = (byte) ((v >> 8) & 0xFF);
            }
        }
    }

    public void lepas() {
        long x = h;
        h = 0L;
        if (x != 0L) {
            try { nvGateLepas(x); } catch (Throwable ignored) {}
        }
    }
}

// Reverb (Freeverb) dan Echo yang pengaturannya boleh diubah kapan saja saat memutar (real time), mono.
// kind 1 = reverb, p = ruangan, peredam, asli (dry), gema (wet), semuanya pecahan 0..1
// kind 2 = echo,   p = jarak (md), ekor (feedback), peredam, asli (dry), pantulan (wet), selain md pecahan 0..1
// Memakai mesin C++ (nadivoice versi 13 ke atas). Bila belum ada, dipakai kelas Freeverb / Echo Java yang
// sama dengan hasil simpan. Hanya dari SATU thread pemutar.
private static final class FxLive implements PcmFx {
    private final int kind, sr;
    private long h = 0L;
    private Freeverb jvR = null;
    private Echo jvE = null;
    private float[] terakhir = null;
    private boolean sudahAtur = false;

    FxLive(int kind, int sr) {
        this.kind = (kind == 2) ? 2 : 1;
        this.sr = sr;
        try {
            if (muatNativeSuaraDua() && nadiVer >= 13) h = nvFxBuat(this.kind, sr);
        } catch (Throwable t) {
            h = 0L;
        }
    }

    private void aturJava() {
        float[] p = terakhir;
        if (kind == 1) {
            if (jvR == null) jvR = new Freeverb(sr, 0);
            jvR.setRoomSize(p[0]);
            jvR.setDamp(p[1]);
            jvR.setDry(p[2]);
            jvR.setWet(p[3]);
        } else {
            if (jvE == null) jvE = new Echo(sr);
            jvE.setParameters(p[0], p[1], p[2], p[3], p[4]);   // kelas Echo mengosongkan penyangga saat diatur
        }
    }

    public void atur(float[] p) {
        int perlu = (kind == 1) ? 4 : 5;
        if (p == null || p.length < perlu) return;
        float[] q = new float[perlu];
        for (int i = 0; i < perlu; i++) {
            float v = p[i];
            if (!(v >= 0f)) v = 0f;
            float maks = (kind == 2 && i == 0) ? 1000f : 1f;
            if (v > maks) v = maks;
            q[i] = v;
        }
        terakhir = q;
        if (h != 0L) {
            try {
                if (nvFxAtur(h, q, perlu) == 1) { sudahAtur = true; return; }
            } catch (Throwable t) {
                android.util.Log.w("NadiMesin", "reverb/echo C++ gagal, memakai Java: " + t);
            }
            h = 0L;
        }
        aturJava();
        sudahAtur = true;
    }

    public void reset() {
        if (h != 0L) {
            try { nvFxReset(h); } catch (Throwable ignored) {}
        } else if (sudahAtur) {
            jvR = null;
            jvE = null;
            aturJava();
        }
    }

    public void proses(byte[] buf, int nBingkai) {
        if (!sudahAtur || nBingkai <= 0) return;
        if (h != 0L) {
            try {
                if (nvFxProses(h, buf, nBingkai) == 1) return;
            } catch (Throwable t) {
                android.util.Log.w("NadiMesin", "reverb/echo C++ gagal, memakai Java: " + t);
            }
            h = 0L;
            aturJava();
        }
        for (int f = 0; f < nBingkai; f++) {
            int k = f * 2;
            short v = (short) ((buf[k] & 0xFF) | (buf[k + 1] << 8));
            v = (kind == 1) ? jvR.process(v) : jvE.process(v);
            buf[k] = (byte) (v & 0xFF);
            buf[k + 1] = (byte) ((v >> 8) & 0xFF);
        }
    }

    public void lepas() {
        long x = h;
        h = 0L;
        if (x != 0L) {
            try { nvFxLepas(x); } catch (Throwable ignored) {}
        }
    }
}

private static final class AutoTuneLive implements PcmFx {
    private final int sr;
    private long h = 0L;
    private boolean sudahAtur = false;
    private int key = 0, scale = 0;
    private float alpha = 0.72f;
    // cadangan Java (bila mesin C++ belum versi 14)
    private Sonic sonic = null;
    private int blockFrames, analysisFrames, ringFilled, pendN, histCount, lastTarget, qN;
    private float[] ring, hist;
    private short[] pend, q, ob;
    private float curSemi;

    AutoTuneLive(int sr) {
        this.sr = sr;
        try {
            if (muatNativeSuaraDua() && nadiVer >= 14) h = nvAtBuat(sr);
        } catch (Throwable t) {
            h = 0L;
        }
    }

    private void siapJava() {
        blockFrames = Math.max(256, sr / 40);
        analysisFrames = Math.max(blockFrames, sr / 25);
        ring = new float[analysisFrames + 4];
        hist = new float[3];
        pend = new short[blockFrames + 4];
        q = new short[blockFrames * 16 + 4];
        ob = new short[blockFrames * 2 + 8];
        sonic = new Sonic(sr, 1);
        ringFilled = 0; pendN = 0; histCount = 0; lastTarget = -1; curSemi = 0f;
        qN = blockFrames;   // tunda awal satu blok (diam)
    }

    public void atur(float[] p) {
        if (p == null || p.length < 3) return;
        float[] q3 = new float[]{p[0], p[1], p[2]};
        if (h != 0L) {
            try {
                if (nvAtAtur(h, q3, 3) == 1) { sudahAtur = true; return; }
            } catch (Throwable t) {
                android.util.Log.w("NadiMesin", "autotune C++ gagal, memakai Java: " + t);
            }
            try { nvAtLepas(h); } catch (Throwable ignored) {}
            h = 0L;
        }
        int k = Math.round(q3[0]); key = ((k % 12) + 12) % 12;
        int sc = Math.round(q3[1]); scale = Math.max(0, Math.min(2, sc));
        float sp = Math.max(1f, Math.min(100f, q3[2]));
        alpha = (sp >= 95f) ? 0.94f : (0.08f + (sp / 100f) * 0.80f);
        if (sonic == null) siapJava();
        sudahAtur = true;
    }

    public void reset() {
        if (h != 0L) {
            try { nvAtReset(h); } catch (Throwable ignored) {}
        } else if (sudahAtur) {
            siapJava();
        }
    }

    private void blokJava() {
        int framesRead = blockFrames;
        int shift = Math.min(ringFilled, analysisFrames - framesRead);
        if (shift > 0 && ringFilled > shift) System.arraycopy(ring, ringFilled - shift, ring, 0, shift);
        for (int i = 0; i < framesRead; i++) ring[shift + i] = pend[i];
        ringFilled = shift + framesRead;
        float f0 = (ringFilled >= analysisFrames / 2) ? AutoTune.deteksiFrekuensiYIN(ring, ringFilled, sr) : -1.0f;
        if (f0 >= 75.0f && f0 <= 850.0f) {
            float midi = (float) (69.0 + 12.0 * (Math.log(f0 / 440.0) / Math.log(2.0)));
            hist[0] = hist[1]; hist[1] = hist[2]; hist[2] = midi;
            if (histCount < 3) histCount++;
            float smooth = midi;
            if (histCount == 3) {
                float a = hist[0], b = hist[1], c = hist[2];
                smooth = Math.max(Math.min(a, b), Math.min(Math.max(a, b), c));
            }
            int target = AutoTune.cariNadaTarget(smooth, key, scale, lastTarget);
            lastTarget = target;
            float desired = target - smooth;
            if (desired > 5.0f) desired = 5.0f; else if (desired < -5.0f) desired = -5.0f;
            curSemi = curSemi + alpha * (desired - curSemi);
        } else {
            histCount = 0;
            curSemi *= 0.5f;
            if (Math.abs(curSemi) < 0.02f) curSemi = 0.0f;
        }
        sonic.setPitch((float) Math.pow(2.0, curSemi / 12.0));
        sonic.putSamples(pend, framesRead);
        while (true) {
            int n = sonic.receiveSamples(ob, ob.length);
            if (n <= 0) break;
            if (qN + n > q.length) {
                int buang = qN + n - q.length;
                if (buang >= qN) qN = 0;
                else { System.arraycopy(q, buang, q, 0, qN - buang); qN -= buang; }
                if (n > q.length) n = q.length;
            }
            System.arraycopy(ob, 0, q, qN, n);
            qN += n;
        }
    }

    public void proses(byte[] buf, int nBingkai) {
        if (!sudahAtur || nBingkai <= 0) return;
        if (h != 0L) {
            try {
                if (nvAtProses(h, buf, nBingkai) == 1) return;
            } catch (Throwable t) {
                android.util.Log.w("NadiMesin", "autotune C++ gagal, memakai Java: " + t);
            }
            try { nvAtLepas(h); } catch (Throwable ignored) {}
            h = 0L;
            siapJava();
        }
        int i = 0;
        while (i < nBingkai) {
            int ambil = Math.min(blockFrames - pendN, nBingkai - i);
            for (int k = 0; k < ambil; k++) pend[pendN + k] = (short) ((buf[(i + k) * 2] & 0xFF) | (buf[(i + k) * 2 + 1] << 8));
            pendN += ambil;
            i += ambil;
            if (pendN >= blockFrames) { blokJava(); pendN = 0; }
        }
        int pad = 0;
        int ambilQ = nBingkai;
        if (qN < nBingkai) { pad = nBingkai - qN; ambilQ = qN; }
        for (int k = 0; k < pad; k++) { buf[k * 2] = 0; buf[k * 2 + 1] = 0; }
        for (int k = 0; k < ambilQ; k++) {
            short v = q[k];
            buf[(pad + k) * 2] = (byte) (v & 0xFF);
            buf[(pad + k) * 2 + 1] = (byte) ((v >> 8) & 0xFF);
        }
        System.arraycopy(q, ambilQ, q, 0, qN - ambilQ);
        qN -= ambilQ;
    }

    public void lepas() {
        long x = h;
        h = 0L;
        if (x != 0L) {
            try { nvAtLepas(x); } catch (Throwable ignored) {}
        }
    }
}

private static class Freeverb {
private static final int numCombs = 8;
private static final int numAllpasses = 4;
private static final float fixedGain = 0.015f;
private static final float scaleWet = 3.0f;
private static final float scaleDamp = 0.4f;
private static final float scaleRoom = 0.28f;
private static final float offsetRoom = 0.7f;
private Comb[] combs;
private Allpass[] allpasses;
private float roomSize, damp, wet, dry;
public Freeverb(int sampleRate) { this(sampleRate, 0); }
public Freeverb(int sampleRate, int spread) {
float scale = (float) sampleRate / 44100.0f;
combs = new Comb[numCombs];
combs[0] = new Comb((int)(1116 * scale) + spread);
combs[1] = new Comb((int)(1188 * scale) + spread);
combs[2] = new Comb((int)(1277 * scale) + spread);
combs[3] = new Comb((int)(1356 * scale) + spread);
combs[4] = new Comb((int)(1422 * scale) + spread);
combs[5] = new Comb((int)(1491 * scale) + spread);
combs[6] = new Comb((int)(1557 * scale) + spread);
combs[7] = new Comb((int)(1617 * scale) + spread);
allpasses = new Allpass[numAllpasses];
allpasses[0] = new Allpass((int)(556 * scale) + spread);
allpasses[1] = new Allpass((int)(441 * scale) + spread);
allpasses[2] = new Allpass((int)(341 * scale) + spread);
allpasses[3] = new Allpass((int)(225 * scale) + spread);
setRoomSize(0.5f); setDamp(0.5f); setWet(0.33f); setDry(0.7f);
}
public void setRoomSize(float value) {
roomSize = (value * scaleRoom) + offsetRoom;
for (Comb c : combs) c.setFeedback(roomSize);
}
public void setDamp(float value) {
damp = value * scaleDamp;
for (Comb c : combs) c.setDamp(damp);
}
public void setWet(float value) { wet = value * scaleWet; }
public void setDry(float value) { dry = value; }
public short process(short input) {
float in = (float)input * fixedGain;
float out = 0.0f;
for (int i = 0; i < numCombs; i++) out += combs[i].process(in);
for (int i = 0; i < numAllpasses; i++) out = allpasses[i].process(out);
float mixed = (out * wet) + (input * dry);
if (mixed > 32767.0f) mixed = 32767.0f;
if (mixed < -32768.0f) mixed = -32768.0f;
return (short)mixed;
}
private class Comb {
float[] buffer; int bufIdx;
float feedback, filterStore, damp1, damp2;
public Comb(int size) { buffer = new float[size]; bufIdx = 0; }
public void setFeedback(float fb) { feedback = fb; }
public void setDamp(float d) { damp1 = d; damp2 = 1.0f - d; }
public float process(float input) {
float output = buffer[bufIdx];
filterStore = (output * damp2) + (filterStore * damp1);
buffer[bufIdx] = input + (filterStore * feedback);
bufIdx++;
if (bufIdx >= buffer.length) bufIdx = 0;
return output;
}
}
private class Allpass {
float[] buffer; int bufIdx;
public Allpass(int size) { buffer = new float[size]; bufIdx = 0; }
public float process(float input) {
float bufOut = buffer[bufIdx];
float output = -input + bufOut;
buffer[bufIdx] = input + (bufOut * 0.5f);
bufIdx++;
if (bufIdx >= buffer.length) bufIdx = 0;
return output;
}
}
}

private static class Sonic {
private static final int SONIC_MIN_PITCH = 65;
private static final int SONIC_MAX_PITCH = 400;
private static final int SONIC_AMDF_FREQ = 4000;
private short[] inputBuffer;
private short[] outputBuffer;
private short[] pitchBuffer;
private short[] downSampleBuffer;
private float pitch = 1.0f;
private float rate = 1.0f;
private float speed = 1.0f;
private int numChannels;
private int inputBufferSize;
private int pitchBufferSize;
private int outputBufferSize;
private int numInputSamples = 0;
private int numOutputSamples = 0;
private int numPitchSamples = 0;
private int minPeriod;
private int maxPeriod;
private int maxRequired;
private int remainingInputToCopy = 0;
private int sampleRate;
public Sonic(int sampleRate, int numChannels) {
this.sampleRate = sampleRate;
this.numChannels = numChannels;
minPeriod = sampleRate / SONIC_MAX_PITCH;
maxPeriod = sampleRate / SONIC_MIN_PITCH;
maxRequired = 2 * maxPeriod;
inputBufferSize = maxRequired;
inputBuffer = new short[maxRequired * numChannels];
outputBufferSize = maxRequired;
outputBuffer = new short[maxRequired * numChannels];
pitchBufferSize = maxRequired;
pitchBuffer = new short[maxRequired * numChannels];
downSampleBuffer = new short[maxRequired];
}
public void setPitch(float pitch) { this.pitch = pitch; }
private void enlargeOutputBufferIfNeeded(int numSamples) {
if (numOutputSamples + numSamples > outputBufferSize) {
outputBufferSize += (outputBufferSize >> 1) + numSamples;
short[] newBuffer = new short[outputBufferSize * numChannels];
System.arraycopy(outputBuffer, 0, newBuffer, 0, numOutputSamples * numChannels);
outputBuffer = newBuffer;
}
}
private void enlargePitchBufferIfNeeded(int numSamples) {
if (numPitchSamples + numSamples > pitchBufferSize) {
pitchBufferSize += (pitchBufferSize >> 1) + numSamples;
short[] newBuffer = new short[pitchBufferSize * numChannels];
System.arraycopy(pitchBuffer, 0, newBuffer, 0, numPitchSamples * numChannels);
pitchBuffer = newBuffer;
}
}
public void putSamples(short[] samples, int samplesToWrite) {
if (numInputSamples + samplesToWrite > inputBufferSize) {
inputBufferSize += (inputBufferSize >> 1) + samplesToWrite;
short[] newBuffer = new short[inputBufferSize * numChannels];
System.arraycopy(inputBuffer, 0, newBuffer, 0, numInputSamples * numChannels);
inputBuffer = newBuffer;
}
System.arraycopy(samples, 0, inputBuffer, numInputSamples * numChannels, samplesToWrite * numChannels);
numInputSamples += samplesToWrite;
processStreamInput();
}
public int receiveSamples(short[] samples, int maxSamples) {
int samplesToRead = Math.min(maxSamples, numOutputSamples);
if (samplesToRead == 0) return 0;
System.arraycopy(outputBuffer, 0, samples, 0, samplesToRead * numChannels);
int remaining = numOutputSamples - samplesToRead;
System.arraycopy(outputBuffer, samplesToRead * numChannels, outputBuffer, 0, remaining * numChannels);
numOutputSamples = remaining;
return samplesToRead;
}
public void flush() {
int remainingSamples = numInputSamples;
float s = speed / pitch;
float r = rate * pitch;
int expectedOutputSamples = numOutputSamples + (int)((remainingSamples / s + numPitchSamples) / r + 0.5f);
if (numInputSamples + maxRequired > inputBufferSize) {
inputBufferSize += (inputBufferSize >> 1) + maxRequired;
short[] newBuffer = new short[inputBufferSize * numChannels];
System.arraycopy(inputBuffer, 0, newBuffer, 0, numInputSamples * numChannels);
inputBuffer = newBuffer;
}
for (int i = 0; i < maxRequired * numChannels; i++) {
inputBuffer[numInputSamples * numChannels + i] = 0;
}
numInputSamples += maxRequired;
processStreamInput();
if (numOutputSamples > expectedOutputSamples) numOutputSamples = expectedOutputSamples;
numInputSamples = 0;
remainingInputToCopy = 0;
numPitchSamples = 0;
}
private void copyToOutput(short[] samples, int position, int numSamples) {
enlargeOutputBufferIfNeeded(numSamples);
System.arraycopy(samples, position * numChannels, outputBuffer, numOutputSamples * numChannels, numSamples * numChannels);
numOutputSamples += numSamples;
}
private int findPitchPeriod(short[] samples, int position) {
int period, skip = 1;
if (sampleRate > SONIC_AMDF_FREQ) skip = sampleRate / SONIC_AMDF_FREQ;
if (numChannels == 1 && skip == 1) {
period = findPitchPeriodInRange(samples, position, minPeriod, maxPeriod, numChannels);
} else {
downSampleInput(samples, position, skip);
period = findPitchPeriodInRange(downSampleBuffer, 0, minPeriod / skip, maxPeriod / skip, 1);
if (skip != 1) {
period *= skip;
int minP = period - (skip * 4);
int maxP = period + (skip * 4);
if (minP < minPeriod) minP = minPeriod;
if (maxP > maxPeriod) maxP = maxPeriod;
if (numChannels == 1) {
period = findPitchPeriodInRange(samples, position, minP, maxP, 1);
} else {
downSampleInput(samples, position, 1);
period = findPitchPeriodInRange(downSampleBuffer, 0, minP, maxP, 1);
}
}
}
return period;
}
private void downSampleInput(short[] samples, int position, int skip) {
int numSamples = maxRequired / skip;
int samplesPerValue = numChannels * skip;
position *= numChannels;
for (int i = 0; i < numSamples; i++) {
int value = 0;
for (int j = 0; j < samplesPerValue; j++) {
value += samples[position + i * samplesPerValue + j];
}
value /= samplesPerValue;
downSampleBuffer[i] = (short)value;
}
}
private int findPitchPeriodInRange(short[] samples, int position, int minPeriod, int maxPeriod, int channels) {
int bestPeriod = 0, worstPeriod = 255;
int minDiff = 1, maxDiff = 0;
position *= channels;
for (int period = minPeriod; period <= maxPeriod; period++) {
int diff = 0;
int p = position;
int pPeriod = position + period * channels;
for (int i = 0; i < period; i++) {
short sV = samples[p];
short pV = samples[pPeriod];
diff += sV >= pV ? sV - pV : pV - sV;
p += channels;
pPeriod += channels;
}
if (bestPeriod == 0 || diff * bestPeriod < minDiff * period) {
minDiff = diff;
bestPeriod = period;
}
if (diff * worstPeriod > maxDiff * period) {
maxDiff = diff;
worstPeriod = period;
}
}
return bestPeriod;
}
private void overlapAdd(int numSamples, int numChannels, short[] out, int outPos, short[] in, int inPos, short[] in2, int in2Pos) {
for (int i = 0; i < numChannels; i++) {
int o = outPos * numChannels + i;
int u = inPos * numChannels + i;
int d = in2Pos * numChannels + i;
for (int t = 0; t < numSamples; t++) {
out[o] = (short)((in[u] * (numSamples - t) + in2[d] * t) / numSamples);
o += numChannels;
u += numChannels;
d += numChannels;
}
}
}
private void changeSpeed(float speed) {
int numSamples = numInputSamples;
int position = 0, period, newPeriod;
if (numSamples < maxRequired) return;
do {
if (remainingInputToCopy > 0) {
int copy = Math.min(remainingInputToCopy, numSamples - position);
copyToOutput(inputBuffer, position, copy);
position += copy;
remainingInputToCopy -= copy;
} else {
period = findPitchPeriod(inputBuffer, position);
if (speed > 1.0) {
newPeriod = (int)(period / (speed - 1.0f));
int skip = Math.min(newPeriod, numSamples - position - period);
if (skip > period) skip = period;
enlargeOutputBufferIfNeeded(skip);
overlapAdd(skip, numChannels, outputBuffer, numOutputSamples, inputBuffer, position, inputBuffer, position + period);
numOutputSamples += skip;
position += skip + period;
remainingInputToCopy = newPeriod - skip;
} else {
newPeriod = (int)(period * speed / (1.0f - speed));
int skip = Math.min(newPeriod, numSamples - position - period);
if (skip > period) skip = period;
enlargeOutputBufferIfNeeded(period + skip);
System.arraycopy(inputBuffer, position * numChannels, outputBuffer, numOutputSamples * numChannels, period * numChannels);
numOutputSamples += period;
overlapAdd(skip, numChannels, outputBuffer, numOutputSamples, inputBuffer, position + period, inputBuffer, position);
numOutputSamples += skip;
position += skip;
remainingInputToCopy = newPeriod - skip;
}
}
} while (position + maxRequired <= numSamples);
removeInputSamples(position);
}
private void removeInputSamples(int position) {
int remaining = numInputSamples - position;
System.arraycopy(inputBuffer, position * numChannels, inputBuffer, 0, remaining * numChannels);
numInputSamples = remaining;
}
private void adjustRate(float rate, int originalNumOutputSamples) {
int newSamples, position;
if (numOutputSamples == originalNumOutputSamples) return;
int numSamples = numOutputSamples - originalNumOutputSamples;
enlargePitchBufferIfNeeded(numSamples);
System.arraycopy(outputBuffer, originalNumOutputSamples * numChannels, pitchBuffer, numPitchSamples * numChannels, numSamples * numChannels);
numOutputSamples = originalNumOutputSamples;
numPitchSamples += numSamples;
position = 0;
while (numPitchSamples - position >= 2) {
newSamples = (int)(position / rate);
int expectedSamples = (int)((position + 1) / rate);
int separation = expectedSamples - newSamples;
if (separation > 0) {
enlargeOutputBufferIfNeeded(separation);
for (int i = 0; i < separation; i++) {
for (int j = 0; j < numChannels; j++) {
int v1 = pitchBuffer[(position * numChannels) + j];
int v2 = pitchBuffer[((position + 1) * numChannels) + j];
outputBuffer[(numOutputSamples * numChannels) + j] = (short)(v1 + (v2 - v1) * ((position / rate) - newSamples) / separation);
}
numOutputSamples++;
}
}
position++;
}
int remaining = numPitchSamples - position;
System.arraycopy(pitchBuffer, position * numChannels, pitchBuffer, 0, remaining * numChannels);
numPitchSamples = remaining;
}
private void processStreamInput() {
int originalNumOutputSamples = numOutputSamples;
float s = speed / pitch;
float r = rate * pitch;
if (s != 1.0f) {
changeSpeed(s);
} else {
copyToOutput(inputBuffer, 0, numInputSamples);
numInputSamples = 0;
}
if (r != 1.0f) {
adjustRate(r, originalNumOutputSamples);
}
}
}

private static class AutoTune {
private static final boolean[] MASK_MAJOR = {true, false, true, false, true, true, false, true, false, true, false, true};
private static final boolean[] MASK_MINOR = {true, false, true, true, false, true, false, true, true, false, true, false};
private static boolean nadaDiizinkan(int midiNote, int rootKey, int scaleType) {
if (scaleType == 0) return true;
int rel = ((midiNote - rootKey) % 12 + 12) % 12;
return (scaleType == 1) ? MASK_MAJOR[rel] : MASK_MINOR[rel];
}
private static int cariNadaTarget(float midiFloat, int rootKey, int scaleType, int lastTarget) {
if (lastTarget > 0 && nadaDiizinkan(lastTarget, rootKey, scaleType)) {
if (Math.abs(midiFloat - lastTarget) <= 0.62f) return lastTarget;
}
int base = Math.round(midiFloat);
int bestNote = base;
float minDiff = 999f;
for (int n = base - 3; n <= base + 3; n++) {
if (nadaDiizinkan(n, rootKey, scaleType)) {
float d = Math.abs(midiFloat - n);
if (d < minDiff) { minDiff = d; bestNote = n; }
}
}
return bestNote;
}
private static float deteksiFrekuensiYIN(float[] monoBuf, int len, int sampleRate) {
double energi = 0.0;
for (int i = 0; i < len; i++) energi += (double) monoBuf[i] * monoBuf[i];
double rms = Math.sqrt(energi / len);
if (rms < 160.0) return -1.0f;
int skip = (sampleRate >= 32000) ? 2 : 1;
int dsLen = len / skip;
float dsRate = (float) sampleRate / skip;
float[] ds = new float[dsLen];
if (skip == 2) {
for (int i = 0; i < dsLen; i++) ds[i] = 0.5f * (monoBuf[i * 2] + monoBuf[i * 2 + 1]);
} else {
System.arraycopy(monoBuf, 0, ds, 0, dsLen);
}
int minTau = Math.max(4, (int) (dsRate / 850.0f));
int maxTau = Math.min(dsLen / 2, (int) (dsRate / 75.0f));
int wLen = dsLen - maxTau;
if (wLen <= minTau) return -1.0f;
float[] yin = new float[maxTau + 1];
yin[0] = 1.0f;
float runningSum = 0.0f;
for (int tau = 1; tau <= maxTau; tau++) {
float diff = 0.0f;
for (int j = 0; j < wLen; j++) {
float delta = ds[j] - ds[j + tau];
diff += delta * delta;
}
runningSum += diff;
yin[tau] = (runningSum > 0.0f) ? (diff * tau / runningSum) : 1.0f;
}
int bestTau = -1;
for (int tau = minTau; tau <= maxTau - 1; tau++) {
if (yin[tau] < 0.22f && yin[tau] <= yin[tau - 1] && yin[tau] <= yin[tau + 1]) {
bestTau = tau;
break;
}
}
if (bestTau == -1) {
float minVal = 0.28f;
for (int tau = minTau; tau <= maxTau - 1; tau++) {
if (yin[tau] < minVal) { minVal = yin[tau]; bestTau = tau; }
}
}
if (bestTau <= 0) return -1.0f;
float s0 = yin[bestTau - 1], s1 = yin[bestTau], s2 = yin[bestTau + 1];
float denom = 2.0f * (2.0f * s1 - s2 - s0);
float exactTau = (float) bestTau;
if (Math.abs(denom) > 1e-6f) {
float d = (s2 - s0) / denom;
if (Math.abs(d) < 1.0f) exactTau += d;
}
return dsRate / exactTau;
}
public static void prosesRafKeFile(RandomAccessFile rafIn, long startOffset, long totalBytes, File outFile, boolean tulisHeaderKosong, int sampleRate, int channels, int rootKey, int scaleType, float speedPct) throws Exception {
int frameSize = channels * 2;
long validBytes = totalBytes - (totalBytes % frameSize);
FileOutputStream fos = new FileOutputStream(outFile);
if (tulisHeaderKosong) fos.write(new byte[44]);
if (validBytes <= 0) { fos.close(); return; }
Sonic sonic = new Sonic(sampleRate, channels);
int blockFrames = Math.max(256, sampleRate / 40);
int analysisFrames = Math.max(blockFrames, sampleRate / 25);
float[] analysisRing = new float[analysisFrames];
int ringFilled = 0;
byte[] inBytes = new byte[blockFrames * frameSize];
short[] inShorts = new short[blockFrames * channels];
short[] outShorts = new short[blockFrames * channels * 2];
byte[] outBytes = new byte[outShorts.length * 2];
float[] histMidi = new float[3];
int histCount = 0;
int lastTargetNote = -1;
float currentSemiShift = 0.0f;
float clampedSpeed = Math.max(1.0f, Math.min(100.0f, speedPct));
float alpha = (clampedSpeed >= 95.0f) ? 0.94f : (0.08f + (clampedSpeed / 100.0f) * 0.80f);
rafIn.seek(startOffset);
long remRead = validBytes;
long writtenBytes = 0;
while (remRead > 0) {
int toRead = (int) Math.min((long) inBytes.length, remRead);
toRead -= (toRead % frameSize);
if (toRead <= 0) break;
int r = rafIn.read(inBytes, 0, toRead);
if (r <= 0) break;
r -= (r % frameSize);
if (r <= 0) break;
int numShorts = r / 2;
int framesRead = numShorts / channels;
ByteBuffer.wrap(inBytes, 0, r).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(inShorts, 0, numShorts);
if (framesRead >= analysisFrames) {
for (int i = 0; i < analysisFrames; i++) {
float m = 0f;
for (int c = 0; c < channels; c++) m += inShorts[i * channels + c];
analysisRing[i] = m / channels;
}
ringFilled = analysisFrames;
} else {
int shift = Math.min(ringFilled, analysisFrames - framesRead);
if (shift > 0 && ringFilled > shift) {
System.arraycopy(analysisRing, ringFilled - shift, analysisRing, 0, shift);
}
for (int i = 0; i < framesRead; i++) {
float m = 0f;
for (int c = 0; c < channels; c++) m += inShorts[i * channels + c];
analysisRing[shift + i] = m / channels;
}
ringFilled = shift + framesRead;
}
float f0 = (ringFilled >= analysisFrames / 2) ? deteksiFrekuensiYIN(analysisRing, ringFilled, sampleRate) : -1.0f;
if (f0 >= 75.0f && f0 <= 850.0f) {
float midi = (float) (69.0 + 12.0 * (Math.log(f0 / 440.0) / Math.log(2.0)));
histMidi[0] = histMidi[1]; histMidi[1] = histMidi[2]; histMidi[2] = midi;
if (histCount < 3) histCount++;
float smoothMidi = midi;
if (histCount == 3) {
float a = histMidi[0], b = histMidi[1], c = histMidi[2];
smoothMidi = Math.max(Math.min(a, b), Math.min(Math.max(a, b), c));
}
int targetNote = cariNadaTarget(smoothMidi, rootKey, scaleType, lastTargetNote);
lastTargetNote = targetNote;
float desiredSemi = targetNote - smoothMidi;
if (desiredSemi > 5.0f) desiredSemi = 5.0f;
else if (desiredSemi < -5.0f) desiredSemi = -5.0f;
currentSemiShift = currentSemiShift + alpha * (desiredSemi - currentSemiShift);
} else {
histCount = 0;
currentSemiShift *= 0.5f;
if (Math.abs(currentSemiShift) < 0.02f) currentSemiShift = 0.0f;
}
float ratio = (float) Math.pow(2.0, currentSemiShift / 12.0);
sonic.setPitch(ratio);
sonic.putSamples(inShorts, framesRead);
while (true) {
int samplesOut = sonic.receiveSamples(outShorts, outShorts.length / channels);
if (samplesOut <= 0) break;
int bw = samplesOut * frameSize;
if (writtenBytes + bw > validBytes) bw = (int) (validBytes - writtenBytes);
if (bw > 0) {
ByteBuffer bb = ByteBuffer.wrap(outBytes, 0, bw).order(ByteOrder.LITTLE_ENDIAN);
for (int k = 0; k < bw / 2; k++) bb.putShort(outShorts[k]);
fos.write(outBytes, 0, bw);
writtenBytes += bw;
}
}
remRead -= r;
}
sonic.flush();
while (writtenBytes < validBytes) {
int samplesOut = sonic.receiveSamples(outShorts, outShorts.length / channels);
if (samplesOut <= 0) break;
int bw = samplesOut * frameSize;
if (writtenBytes + bw > validBytes) bw = (int) (validBytes - writtenBytes);
if (bw > 0) {
ByteBuffer bb = ByteBuffer.wrap(outBytes, 0, bw).order(ByteOrder.LITTLE_ENDIAN);
for (int k = 0; k < bw / 2; k++) bb.putShort(outShorts[k]);
fos.write(outBytes, 0, bw);
writtenBytes += bw;
}
}
fos.close();
}
}
// ==========================================================
// KONTROL TTS (SEMUA DIJALANKAN DI JAVA, LUA HANYA TAMPILAN)
// Mendukung Android lama (API < 21) dan Android baru (API >= 21)
// Pintu masuk dari Lua: ttsPerintah(Context, aksi, data)
// Data dipisah dengan karakter ASCII 31.
// ==========================================================
private static final String TTS_SEP = String.valueOf((char) 31);
private static final Object TTS_LOCK = new Object();
private static TextToSpeech ttsEng = null;
private static int ttsState = 0; // 0 kosong, 1 menyiapkan, 2 siap, 3 gagal
private static String ttsPaket = "";
private static String ttsGalat = "";
private static int ttsGen = 0;
private static long ttsIdleStamp = 0;
private static String ttsAntrianTeks = null;
private static boolean ttsAntrianFlush = true;
private static String ttsCfgSuara = "";
private static String ttsCfgBahasa = "";
private static float ttsCfgKec = 50f;
private static float ttsCfgNada = 50f;
private static String ttsCachePaket = null;
private static final java.util.ArrayList<Object> ttsDaftarSuara = new java.util.ArrayList<Object>();
private static final java.util.ArrayList<java.util.Locale> ttsDaftarLocale = new java.util.ArrayList<java.util.Locale>();
private static final java.util.concurrent.ExecutorService ttsExec = java.util.concurrent.Executors.newSingleThreadExecutor();
private static final android.os.Handler ttsMain = new android.os.Handler(android.os.Looper.getMainLooper());

private static String ttsPar(String[] p, int i) {
return (p != null && i < p.length && p[i] != null) ? p[i] : "";
}

private static float ttsAngka(String s, float def) {
try { return Float.parseFloat(s.trim()); } catch (Throwable e) { return def; }
}

private static java.util.Locale ttsLocaleDariKunci(String key) {
String[] a = key.split("_", -1);
String l = a.length > 0 ? a[0] : "";
String c = a.length > 1 ? a[1] : "";
String v = a.length > 2 ? a[2] : "";
return new java.util.Locale(l, c, v);
}

private static void ttsShutdownAsync(final TextToSpeech t) {
if (t == null) return;
ttsMain.post(new Runnable() {
@Override
public void run() {
try { t.stop(); } catch (Throwable e) {}
try { t.shutdown(); } catch (Throwable e) {}
}
});
}

private static void ttsLepas() {
TextToSpeech t;
synchronized (TTS_LOCK) {
ttsGen++;
ttsIdleStamp++;
t = ttsEng;
ttsEng = null;
ttsState = 0;
ttsAntrianTeks = null;
ttsGalat = "";
}
ttsShutdownAsync(t);
}

private static String ttsStatusTeks() {
synchronized (TTS_LOCK) {
if (ttsState == 2) return "SIAP";
if (ttsState == 1) return "MENYIAPKAN";
if (ttsState == 3) return "GAGAL: " + ttsGalat;
return "KOSONG";
}
}

private static void ttsTandaiGagal(String alasan) {
synchronized (TTS_LOCK) {
ttsState = 3;
ttsGalat = alasan;
}
}

private static void ttsJadwalIdle() {
final long stamp;
synchronized (TTS_LOCK) {
ttsIdleStamp++;
stamp = ttsIdleStamp;
}
ttsMain.postDelayed(new Runnable() {
@Override
public void run() {
ttsExec.execute(new Runnable() {
@Override
public void run() {
TextToSpeech t;
synchronized (TTS_LOCK) {
if (stamp != ttsIdleStamp) return;
t = ttsEng;
}
boolean sedangBicara = false;
try { sedangBicara = (t != null && t.isSpeaking()); } catch (Throwable e) {}
if (sedangBicara) ttsJadwalIdle(); else ttsLepas();
}
});
}
}, 90000);
}

private static void ttsBuatMesin(final Context ctx, String paketBaru) {
final String paket = (paketBaru == null) ? "" : paketBaru.trim();
final int gen;
TextToSpeech lama;
synchronized (TTS_LOCK) {
lama = ttsEng;
ttsEng = null;
ttsGen++;
gen = ttsGen;
ttsIdleStamp++;
ttsState = 1;
ttsGalat = "";
if (ttsCachePaket != null && !ttsCachePaket.equals(paket)) {
ttsDaftarSuara.clear();
ttsDaftarLocale.clear();
}
ttsPaket = paket;
}
ttsShutdownAsync(lama);
ttsMain.post(new Runnable() {
@Override
public void run() {
TextToSpeech t = null;
try {
TextToSpeech.OnInitListener l = new TextToSpeech.OnInitListener() {
@Override
public void onInit(final int status) {
ttsExec.execute(new Runnable() {
@Override
public void run() { ttsSetelahInit(gen, status); }
});
}
};
if (paket.length() > 0) t = new TextToSpeech(ctx, l, paket);
else t = new TextToSpeech(ctx, l);
} catch (Throwable e) {
synchronized (TTS_LOCK) {
if (gen == ttsGen) { ttsState = 3; ttsGalat = "Tidak bisa membuat mesin TTS: " + e.getMessage(); }
}
return;
}
boolean batal = false;
synchronized (TTS_LOCK) {
if (gen == ttsGen) ttsEng = t; else batal = true;
}
if (batal) { try { t.shutdown(); } catch (Throwable e) {} }
}
});
ttsMain.postDelayed(new Runnable() {
@Override
public void run() {
synchronized (TTS_LOCK) {
if (gen == ttsGen && ttsState == 1) { ttsState = 3; ttsGalat = "Mesin TTS tidak merespons"; }
}
}
}, 20000);
}

private static void ttsKumpulkanDaftar(TextToSpeech t) {
java.util.ArrayList<Object> vs = new java.util.ArrayList<Object>();
java.util.ArrayList<java.util.Locale> ls = new java.util.ArrayList<java.util.Locale>();
try {
if (android.os.Build.VERSION.SDK_INT >= 21) {
Set<Voice> set = t.getVoices();
if (set != null) {
for (Voice v : set) vs.add(v);
}
}
} catch (Throwable e) {}
try {
if (android.os.Build.VERSION.SDK_INT < 21 || vs.isEmpty()) {
for (java.util.Locale lc : java.util.Locale.getAvailableLocales()) {
String lang = lc.getLanguage();
if (lang == null || lang.length() < 2 || lang.length() > 3) continue;
if (t.isLanguageAvailable(lc) >= TextToSpeech.LANG_AVAILABLE) ls.add(lc);
}
}
} catch (Throwable e) {}
synchronized (TTS_LOCK) {
ttsDaftarSuara.clear();
ttsDaftarSuara.addAll(vs);
ttsDaftarLocale.clear();
ttsDaftarLocale.addAll(ls);
}
}

private static void ttsTerapkanCfg(TextToSpeech t) {
String suara, bahasa;
float kec, nada;
Object[] arr;
synchronized (TTS_LOCK) {
suara = ttsCfgSuara;
bahasa = ttsCfgBahasa;
kec = ttsCfgKec;
nada = ttsCfgNada;
arr = ttsDaftarSuara.toArray();
}
try { t.setSpeechRate(0.1f + (kec / 100f) * 3.9f); } catch (Throwable e) {}
try { t.setPitch(0.1f + (nada / 100f) * 2.9f); } catch (Throwable e) {}
boolean suaraDipasang = false;
if (android.os.Build.VERSION.SDK_INT >= 21 && suara.length() > 0) {
try {
for (Object o : arr) {
Voice v = (Voice) o;
if (suara.equals(v.getName())) {
t.setVoice(v);
suaraDipasang = true;
break;
}
}
} catch (Throwable e) {}
}
if (!suaraDipasang && bahasa.length() > 0) {
try { t.setLanguage(ttsLocaleDariKunci(bahasa)); } catch (Throwable e) {}
}
}

private static void ttsSimpanCfg(String suara, String kec, String nad, String bahasa) {
synchronized (TTS_LOCK) {
ttsCfgSuara = suara == null ? "" : suara;
ttsCfgKec = ttsAngka(kec, 50f);
ttsCfgNada = ttsAngka(nad, 50f);
ttsCfgBahasa = bahasa == null ? "" : bahasa;
}
}

private static int ttsBatasPanjang() {
int max = 3500;
try {
if (android.os.Build.VERSION.SDK_INT >= 18) max = Math.min(3500, TextToSpeech.getMaxSpeechInputLength() - 100);
} catch (Throwable e) {}
if (max < 200) max = 200;
return max;
}

private static java.util.List<String> ttsPecahTeks(String teks, int max) {
java.util.ArrayList<String> out = new java.util.ArrayList<String>();
String s = (teks == null) ? "" : teks.trim();
while (s.length() > max) {
int cut = -1;
for (int i = max; i > max / 2; i--) {
char c = s.charAt(i - 1);
if (c == '.' || c == '!' || c == '?' || c == '\n') { cut = i; break; }
}
if (cut < 0) {
for (int i = max; i > max / 2; i--) {
char c = s.charAt(i - 1);
if (c == ';' || c == ',' || c == ':') { cut = i; break; }
}
}
if (cut < 0) {
int sp = s.lastIndexOf(' ', max);
cut = (sp > max / 2) ? sp + 1 : max;
}
String bagian = s.substring(0, cut).trim();
if (bagian.length() > 0) out.add(bagian);
s = s.substring(cut).trim();
}
if (s.length() > 0) out.add(s);
return out;
}

private static String ttsBicaraInternal(TextToSpeech t, String teks, boolean flush) {
java.util.List<String> bagian = ttsPecahTeks(teks, ttsBatasPanjang());
if (bagian.isEmpty()) return "GAGAL: Teks kosong";
for (int i = 0; i < bagian.size(); i++) {
int mode = (i == 0 && flush) ? TextToSpeech.QUEUE_FLUSH : TextToSpeech.QUEUE_ADD;
String id = "NADI_BICARA_" + System.nanoTime() + "_" + i;
int r;
try {
if (android.os.Build.VERSION.SDK_INT >= 21) {
r = t.speak(bagian.get(i), mode, (android.os.Bundle) null, id);
} else {
HashMap<String, String> hp = new HashMap<String, String>();
hp.put(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, id);
r = t.speak(bagian.get(i), mode, hp);
}
} catch (Throwable e) {
return "GAGAL: " + e.getMessage();
}
if (r != TextToSpeech.SUCCESS) return "GAGAL: Mesin TTS menolak membacakan teks";
}
return "OK";
}

private static void ttsSetelahInit(int gen, int status) {
TextToSpeech t = null;
for (int i = 0; i < 20; i++) {
synchronized (TTS_LOCK) {
if (gen != ttsGen) return;
t = ttsEng;
}
if (t != null) break;
try { Thread.sleep(50); } catch (InterruptedException e) {}
}
if (t == null || status != TextToSpeech.SUCCESS) {
synchronized (TTS_LOCK) {
if (gen == ttsGen) {
ttsState = 3;
ttsGalat = "Mesin TTS gagal dimulai" + (ttsPaket.length() > 0 ? " (" + ttsPaket + ")" : "");
}
}
return;
}
ttsKumpulkanDaftar(t);
String teks;
boolean flush;
synchronized (TTS_LOCK) {
if (gen != ttsGen) return;
ttsCachePaket = ttsPaket;
ttsState = 2;
teks = ttsAntrianTeks;
flush = ttsAntrianFlush;
ttsAntrianTeks = null;
}
ttsTerapkanCfg(t);
if (teks != null) {
String r = ttsBicaraInternal(t, teks, flush);
if (!"OK".equals(r)) ttsTandaiGagal(r.startsWith("GAGAL: ") ? r.substring(7) : r);
}
ttsJadwalIdle();
}

private static String ttsDaftarMesin(Context ctx) {
StringBuilder sb = new StringBuilder();
TextToSpeech t = null;
synchronized (TTS_LOCK) {
if (ttsState == 2) t = ttsEng;
}
try {
if (t != null) {
java.util.List<TextToSpeech.EngineInfo> es = t.getEngines();
if (es != null) {
for (TextToSpeech.EngineInfo e : es) {
sb.append(e.name).append('\t').append(e.label).append('\n');
}
}
}
} catch (Throwable e) {}
if (sb.length() == 0) {
try {
android.content.pm.PackageManager pm = ctx.getPackageManager();
android.content.Intent it = new android.content.Intent("android.intent.action.TTS_SERVICE");
java.util.List<android.content.pm.ResolveInfo> hasil = pm.queryIntentServices(it, 0);
if (hasil != null) {
for (android.content.pm.ResolveInfo ri : hasil) {
if (ri.serviceInfo == null) continue;
CharSequence lb = ri.loadLabel(pm);
sb.append(ri.serviceInfo.packageName).append('\t').append(lb == null ? ri.serviceInfo.packageName : lb.toString()).append('\n');
}
}
} catch (Throwable e) {}
}
return sb.toString();
}

private static String ttsMesinBawaan(Context ctx) {
String d = "";
try { d = android.provider.Settings.Secure.getString(ctx.getContentResolver(), "tts_default_synth"); } catch (Throwable e) {}
if (d == null || d.length() == 0) {
TextToSpeech t = null;
synchronized (TTS_LOCK) {
if (ttsState == 2) t = ttsEng;
}
try { if (t != null) d = t.getDefaultEngine(); } catch (Throwable e) {}
}
return d == null ? "" : d;
}

private static String ttsDaftarBahasa() {
Object[] vs;
java.util.ArrayList<java.util.Locale> ls;
synchronized (TTS_LOCK) {
vs = ttsDaftarSuara.toArray();
ls = new java.util.ArrayList<java.util.Locale>(ttsDaftarLocale);
}
java.util.HashMap<String, String> unik = new java.util.HashMap<String, String>();
try {
for (Object o : vs) {
java.util.Locale lc = ((Voice) o).getLocale();
if (lc == null) continue;
String n = lc.getDisplayName();
if (n == null || n.length() == 0) continue;
if (!unik.containsKey(n)) unik.put(n, lc.toString());
}
} catch (Throwable e) {}
for (java.util.Locale lc : ls) {
String n = lc.getDisplayName();
if (n == null || n.length() == 0) continue;
if (!unik.containsKey(n)) unik.put(n, lc.toString());
}
java.util.ArrayList<String> nama = new java.util.ArrayList<String>(unik.keySet());
java.util.Collections.sort(nama, String.CASE_INSENSITIVE_ORDER);
StringBuilder sb = new StringBuilder();
for (String n : nama) sb.append(unik.get(n)).append('\t').append(n).append('\n');
return sb.toString();
}

private static String ttsDaftarSuaraTeks(String kunciBahasa) {
Object[] vs;
synchronized (TTS_LOCK) {
vs = ttsDaftarSuara.toArray();
}
java.util.TreeMap<String, String> urut = new java.util.TreeMap<String, String>(String.CASE_INSENSITIVE_ORDER);
try {
for (Object o : vs) {
Voice v = (Voice) o;
java.util.Locale lc = v.getLocale();
if (lc == null) continue;
if (kunciBahasa != null && kunciBahasa.length() > 0 && !lc.toString().equals(kunciBahasa)) continue;
urut.put(v.getName(), v.isNetworkConnectionRequired() ? "1" : "0");
}
} catch (Throwable e) {}
StringBuilder sb = new StringBuilder();
for (java.util.Map.Entry<String, String> en : urut.entrySet()) {
sb.append(en.getKey()).append('\t').append(en.getValue()).append('\n');
}
return sb.toString();
}

public static String ttsPerintah(Context ctx, String aksi, String data) {
tahap("Membuat suara dari teks");
try {
String[] p = (data == null ? "" : data).split(java.util.regex.Pattern.quote(TTS_SEP), -1);
if ("siapkan".equals(aksi)) {
String paket = ttsPar(p, 0).trim();
boolean sudah;
synchronized (TTS_LOCK) {
sudah = (ttsState == 1 || ttsState == 2) && ttsPaket.equals(paket);
}
if (!sudah) ttsBuatMesin(ctx, paket);
return "OK";
}
if ("status".equals(aksi)) return ttsStatusTeks();
if ("mesinBawaan".equals(aksi)) return ttsMesinBawaan(ctx);
if ("daftarMesin".equals(aksi)) return ttsDaftarMesin(ctx);
if ("daftarBahasa".equals(aksi)) return ttsDaftarBahasa();
if ("daftarSuara".equals(aksi)) return ttsDaftarSuaraTeks(ttsPar(p, 0));
if ("terapkan".equals(aksi)) {
ttsSimpanCfg(ttsPar(p, 0), ttsPar(p, 1), ttsPar(p, 2), ttsPar(p, 3));
final TextToSpeech t;
synchronized (TTS_LOCK) {
t = (ttsState == 2) ? ttsEng : null;
}
if (t != null) {
ttsExec.execute(new Runnable() {
@Override
public void run() { ttsTerapkanCfg(t); }
});
}
return "OK";
}
if ("bicara".equals(aksi)) {
final String teks = ttsPar(p, 0);
final boolean flush = !"0".equals(ttsPar(p, 1));
final String paket = ttsPar(p, 2).trim();
if (teks.trim().length() == 0) return "GAGAL: Teks kosong";
ttsSimpanCfg(ttsPar(p, 3), ttsPar(p, 4), ttsPar(p, 5), ttsPar(p, 6));
TextToSpeech siap = null;
boolean perluInit;
synchronized (TTS_LOCK) {
if (ttsState == 2 && ttsEng != null && ttsPaket.equals(paket)) {
siap = ttsEng;
perluInit = false;
} else {
ttsAntrianTeks = teks;
ttsAntrianFlush = flush;
perluInit = !(ttsState == 1 && ttsPaket.equals(paket));
}
}
if (siap != null) {
final TextToSpeech t = siap;
ttsExec.execute(new Runnable() {
@Override
public void run() {
ttsTerapkanCfg(t);
String r = ttsBicaraInternal(t, teks, flush);
if (!"OK".equals(r)) ttsTandaiGagal(r.startsWith("GAGAL: ") ? r.substring(7) : r);
ttsJadwalIdle();
}
});
return "OK";
}
if (perluInit) ttsBuatMesin(ctx, paket);
return "OK";
}
if ("henti".equals(aksi)) {
final TextToSpeech t;
synchronized (TTS_LOCK) {
ttsAntrianTeks = null;
t = ttsEng;
}
if (t != null) {
ttsExec.execute(new Runnable() {
@Override
public void run() { try { t.stop(); } catch (Throwable e) {} }
});
}
return "OK";
}
if ("lepas".equals(aksi)) {
ttsLepas();
return "OK";
}
if ("sintesis".equals(aksi)) {
return ttsSintesisKeFile(ctx, ttsPar(p, 0), ttsPar(p, 1), ttsPar(p, 2), ttsPar(p, 3),
ttsAngka(ttsPar(p, 4), 50f), ttsAngka(ttsPar(p, 5), 50f), ttsPar(p, 6));
}
return "GAGAL: Perintah TTS tidak dikenal: " + aksi;
} catch (Throwable e) {
return "GAGAL: " + e;
}
}

// ==========================================================
// SINTESIS TEKS KE FILE WAV (BLOKING, JALAN DI THREAD LATAR)
// ==========================================================
private static byte[] ttsHeaderWav(long dataLen, int sr, int ch, int bits) {
ByteBuffer bb = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
bb.put(new byte[] {'R', 'I', 'F', 'F'});
bb.putInt((int) (36 + dataLen));
bb.put(new byte[] {'W', 'A', 'V', 'E'});
bb.put(new byte[] {'f', 'm', 't', ' '});
bb.putInt(16);
bb.putShort((short) 1);
bb.putShort((short) ch);
bb.putInt(sr);
bb.putInt(sr * ch * bits / 8);
bb.putShort((short) (ch * bits / 8));
bb.putShort((short) bits);
bb.put(new byte[] {'d', 'a', 't', 'a'});
bb.putInt((int) dataLen);
return bb.array();
}

private static long[] ttsInfoWav(File f) throws IOException {
RandomAccessFile raf = new RandomAccessFile(f, "r");
try {
long len = raf.length();
if (len < 44) return null;
byte[] hd = new byte[12];
raf.readFully(hd);
if (hd[0] != 'R' || hd[1] != 'I' || hd[2] != 'F' || hd[3] != 'F') return null;
long pos = 12;
long sr = 0, ch = 0, bits = 0;
while (pos + 8 <= len) {
raf.seek(pos);
byte[] ck = new byte[8];
raf.readFully(ck);
String id = new String(ck, 0, 4, "US-ASCII");
long size = (ck[4] & 0xFFL) | ((ck[5] & 0xFFL) << 8) | ((ck[6] & 0xFFL) << 16) | ((ck[7] & 0xFFL) << 24);
if (id.equals("fmt ")) {
byte[] fm = new byte[16];
raf.readFully(fm);
ch = (fm[2] & 0xFF) | ((fm[3] & 0xFF) << 8);
sr = (fm[4] & 0xFFL) | ((fm[5] & 0xFFL) << 8) | ((fm[6] & 0xFFL) << 16) | ((fm[7] & 0xFFL) << 24);
bits = (fm[14] & 0xFF) | ((fm[15] & 0xFF) << 8);
} else if (id.equals("data")) {
long off = pos + 8;
long avail = len - off;
long dl = size;
if (dl <= 0 || dl > avail) dl = avail;
if (sr == 0 || ch == 0 || bits == 0) return null;
return new long[] {off, dl, sr, ch, bits};
}
pos += 8 + size + (size & 1);
}
return null;
} finally {
raf.close();
}
}

private static String ttsGabungWav(java.util.List<File> bagian, File out) {
FileOutputStream fos = null;
try {
long total = 0;
int sr = 0, ch = 0, bits = 0;
fos = new FileOutputStream(out);
fos.write(new byte[44]);
byte[] buf = new byte[16384];
for (File f : bagian) {
long[] info = ttsInfoWav(f);
if (info == null) return "ERROR: Format WAV hasil TTS tidak dikenali";
if (sr == 0) { sr = (int) info[2]; ch = (int) info[3]; bits = (int) info[4]; }
RandomAccessFile raf = new RandomAccessFile(f, "r");
try {
raf.seek(info[0]);
long sisa = info[1];
while (sisa > 0) {
int r = raf.read(buf, 0, (int) Math.min((long) buf.length, sisa));
if (r <= 0) break;
fos.write(buf, 0, r);
sisa -= r;
total += r;
}
} finally {
raf.close();
}
}
fos.close();
fos = null;
RandomAccessFile h = new RandomAccessFile(out, "rw");
try {
h.seek(0);
h.write(ttsHeaderWav(total, sr, ch, bits));
} finally {
h.close();
}
return "OK";
} catch (Exception e) {
return "ERROR: Gagal menggabung potongan suara TTS: " + e.getMessage();
} finally {
if (fos != null) { try { fos.close(); } catch (Exception e) {} }
}
}

private static String ttsSintesisKeFile(final Context ctx, String teks, String outPath, String paket, String suara, float kecepatan, float nada, String bahasa) {
if (teks == null || teks.trim().length() == 0) return "ERROR: Teks kosong";
if (outPath == null || outPath.length() == 0) return "ERROR: Jalur file keluaran kosong";
ttsLepas();
final File fOut = new File(outPath);
File dir = fOut.getParentFile();
if (dir != null && !dir.exists()) dir.mkdirs();
if (fOut.exists()) fOut.delete();
final String paketN = (paket == null) ? "" : paket.trim();
final CountDownLatch initLatch = new CountDownLatch(1);
final int[] initStatus = {-999};
final TextToSpeech[] holder = new TextToSpeech[1];
ttsMain.post(new Runnable() {
@Override
public void run() {
try {
TextToSpeech.OnInitListener l = new TextToSpeech.OnInitListener() {
@Override
public void onInit(int status) {
initStatus[0] = status;
initLatch.countDown();
}
};
if (paketN.length() > 0) holder[0] = new TextToSpeech(ctx, l, paketN);
else holder[0] = new TextToSpeech(ctx, l);
} catch (Throwable e) {
initStatus[0] = -998;
initLatch.countDown();
}
}
});
TextToSpeech tts = null;
java.util.ArrayList<File> potong = new java.util.ArrayList<File>();
try {
if (!initLatch.await(20, TimeUnit.SECONDS)) {
ttsMain.postDelayed(new Runnable() {
@Override
public void run() { if (holder[0] != null) { try { holder[0].shutdown(); } catch (Throwable e) {} } }
}, 30000);
return "ERROR: Mesin TTS tidak merespons saat disiapkan" + (paketN.length() > 0 ? " (" + paketN + ")" : "");
}
tts = holder[0];
if (initStatus[0] != TextToSpeech.SUCCESS || tts == null) {
return "ERROR: Mesin TTS gagal dimulai" + (paketN.length() > 0 ? " (" + paketN + ")" : "");
}
try { tts.setSpeechRate(0.1f + (kecepatan / 100f) * 3.9f); } catch (Throwable e) {}
try { tts.setPitch(0.1f + (nada / 100f) * 2.9f); } catch (Throwable e) {}
boolean suaraOk = false;
if (android.os.Build.VERSION.SDK_INT >= 21 && suara != null && suara.trim().length() > 0) {
try {
Set<Voice> vs = tts.getVoices();
if (vs != null) {
for (Voice v : vs) {
if (suara.equals(v.getName())) { tts.setVoice(v); suaraOk = true; break; }
}
}
} catch (Throwable e) {}
}
if (!suaraOk && bahasa != null && bahasa.trim().length() > 0) {
try { tts.setLanguage(ttsLocaleDariKunci(bahasa.trim())); } catch (Throwable e) {}
}

java.util.List<String> bagian = ttsPecahTeks(teks, ttsBatasPanjang());
if (bagian.isEmpty()) return "ERROR: Teks kosong";

final String[] idSekarang = {""};
final String[] hasilBagian = {""};
final CountDownLatch[] latchBagian = new CountDownLatch[1];
tts.setOnUtteranceProgressListener(new UtteranceProgressListener() {
@Override
public void onStart(String utteranceId) {}
@Override
public void onDone(String utteranceId) {
if (utteranceId != null && utteranceId.equals(idSekarang[0])) {
hasilBagian[0] = "OK";
CountDownLatch lt = latchBagian[0];
if (lt != null) lt.countDown();
}
}
@Override
public void onError(String utteranceId) {
if (utteranceId != null && utteranceId.equals(idSekarang[0])) {
hasilBagian[0] = "ERROR: Mesin TTS menolak memproses teks ini";
CountDownLatch lt = latchBagian[0];
if (lt != null) lt.countDown();
}
}
public void onError(String utteranceId, int errorCode) {
if (utteranceId != null && utteranceId.equals(idSekarang[0])) {
hasilBagian[0] = "ERROR: Mesin TTS menolak memproses teks ini (kode " + errorCode + ")";
CountDownLatch lt = latchBagian[0];
if (lt != null) lt.countDown();
}
}
public void onStop(String utteranceId, boolean interrupted) {
if (utteranceId != null && utteranceId.equals(idSekarang[0])) {
hasilBagian[0] = "ERROR: Sintesis TTS dihentikan sebelum selesai";
CountDownLatch lt = latchBagian[0];
if (lt != null) lt.countDown();
}
}
});

for (int i = 0; i < bagian.size(); i++) {
File fp = (bagian.size() == 1) ? fOut : new File(outPath + ".bagian" + i + ".tmp");
if (fp.exists()) fp.delete();
String id = "NADI_SYNTH_" + System.nanoTime() + "_" + i;
CountDownLatch lt = new CountDownLatch(1);
hasilBagian[0] = "";
idSekarang[0] = id;
latchBagian[0] = lt;
int rc;
if (android.os.Build.VERSION.SDK_INT >= 21) {
rc = tts.synthesizeToFile(bagian.get(i), (android.os.Bundle) null, fp, id);
} else {
HashMap<String, String> hp = new HashMap<String, String>();
hp.put(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, id);
rc = tts.synthesizeToFile(bagian.get(i), hp, fp.getAbsolutePath());
}
if (rc != TextToSpeech.SUCCESS) return "ERROR: Gagal memanggil fungsi sintesis dari TTS";
if (!lt.await(180, TimeUnit.SECONDS)) return "ERROR: Timeout sintesis. Mesin TTS mogok atau macet.";
if (!"OK".equals(hasilBagian[0])) return hasilBagian[0].length() > 0 ? hasilBagian[0] : "ERROR: Sintesis TTS gagal";
try { Thread.sleep(80); } catch (InterruptedException e) {}
if (!fp.exists() || fp.length() <= 44) return "ERROR: File output TTS kosong";
potong.add(fp);
}

if (potong.size() > 1) {
String g = ttsGabungWav(potong, fOut);
if (!"OK".equals(g)) return g;
}
if (!fOut.exists() || fOut.length() <= 44) return "ERROR: File output TTS kosong";
return "SUKSES";
} catch (Throwable e) {
return "ERROR: " + e.getMessage();
} finally {
ttsShutdownAsync(tts);
for (File f : potong) {
if (!f.equals(fOut) && f.exists()) f.delete();
}
}
}

// Dipertahankan agar pemanggil lama tetap jalan
public static String sintesisTTSLatarBelakang(Context context, String teks, String outPath, String namaMesin, String namaSuara, float kecepatan, float nada) {
tahap("Membuat suara dari teks");
return ttsSintesisKeFile(context, teks, outPath, namaMesin, namaSuara, kecepatan, nada, "");
}

// ==========================================================
// KELAS DAN FUNGSI UNTUK AUTO-DUCKING (VOICE OVER)
// ==========================================================
private static class SidechainDucker {
    private float threshold;
    private float depth;
    private float attackCoef;
    private float releaseCoef;
    private float envelope = 0f;
    private float gain = 1f;

    public SidechainDucker(int sampleRate, float thresholdPct, float depthPct, float attackMs, float releaseMs) {
        this.threshold = (thresholdPct / 100f) * 32768f; 
        this.depth = depthPct / 100f; 
        if (attackMs <= 0.1f) attackMs = 0.1f;
        if (releaseMs <= 0.1f) releaseMs = 0.1f;
        this.attackCoef = (float) Math.exp(-1000.0 / (sampleRate * attackMs));
        this.releaseCoef = (float) Math.exp(-1000.0 / (sampleRate * releaseMs));
    }

    public short process(short triggerSample, short targetSample) {
        float absIn = Math.abs((float) triggerSample);
        if (absIn > envelope) {
            envelope = attackCoef * envelope + (1.0f - attackCoef) * absIn;
        } else {
            envelope = releaseCoef * envelope + (1.0f - releaseCoef) * absIn;
        }

        float targetGain = (envelope > threshold) ? depth : 1.0f;

        if (targetGain < gain) {
            gain = attackCoef * gain + (1.0f - attackCoef) * targetGain;
        } else {
            gain = releaseCoef * gain + (1.0f - releaseCoef) * targetGain;
        }

        float ducked = targetSample * gain;
        if (ducked > 32767f) ducked = 32767f;
        if (ducked < -32768f) ducked = -32768f;
        return (short) ducked;
    }
}

// Pemanggil lama (16 argumen) tetap jalan: otomatis mode ducking biasa
public static String prosesVoiceOverDinamis(String micPath, String intPath, String musPath, String outPath, int format, int sampleRate, int channels, int bitrate, float volM, float volI, float volMus, int triggerMode, float thresholdPct, float depthPct, float attackMs, float releaseMs) {
    return prosesVoiceOverDinamis(micPath, intPath, musPath, outPath, format, sampleRate, channels, bitrate, volM, volI, volMus, triggerMode, thresholdPct, depthPct, attackMs, releaseMs, false, 0L, 0f, 0f);
}

public static String prosesVoiceOverDinamis(String micPath, String intPath, String musPath, String outPath, int format, int sampleRate, int channels, int bitrate, float volM, float volI, float volMus, int triggerMode, float thresholdPct, float depthPct, float attackMs, float releaseMs, boolean isBroadcast, long musStartMs, float outroHoldSec, float outroFadeSec) {
tahap("Menerapkan Voice Over");
    try {
        File fMic = new File(micPath == null ? "" : micPath);
        File fInt = new File(intPath == null ? "" : intPath);
        File fMus = new File(musPath == null ? "" : musPath);

        boolean hasMic = fMic.exists() && fMic.length() > 44;
        boolean hasInt = fInt.exists() && fInt.length() > 44;
        boolean hasMus = fMus.exists() && fMus.length() > 0;

        if (!hasMic && !hasInt && !hasMus) return "SUKSES_KOSONG";

        long micSkip = 44;
        long intSkip = 44;
        long musSkip = 0;
        long musLoopStart = 0;
        long musBase = 0;
        long introBytesTotal = 0;

        if (hasMus && fMus.length() >= 44) {
            RandomAccessFile tRaf = new RandomAccessFile(fMus, "r");
            byte[] magic = new byte[4];
            tRaf.read(magic);
            if (magic[0] == 'R' && magic[1] == 'I' && magic[2] == 'F' && magic[3] == 'F') {
                musSkip = 44;
            }
            tRaf.close();
            
            if (isBroadcast && musStartMs > 0) {
                long offsetBytes = (musStartMs * sampleRate * channels * 2) / 1000L;
                offsetBytes -= (offsetBytes % (channels * 2));
                if (musSkip + offsetBytes + 4096 < fMus.length()) introBytesTotal = offsetBytes;
            }
        }

        musBase = musSkip;
        musLoopStart = musSkip;

        if (hasMic && hasInt) {
            long micTime = 0, intTime = 0;
            try {
                BufferedReader brM = new BufferedReader(new FileReader(micPath + ".time"));
                micTime = Long.parseLong(brM.readLine().trim());
                brM.close();
            } catch (Exception ignored) {}
            try {
                BufferedReader brI = new BufferedReader(new FileReader(intPath + ".time"));
                intTime = Long.parseLong(brI.readLine().trim());
                brI.close();
            } catch (Exception ignored) {}
            if (micTime > 0 && intTime > 0) {
                long delta = Math.abs(micTime - intTime);
                long skipBytes = (delta * sampleRate * channels * 2) / 1000;
                skipBytes = skipBytes - (skipBytes % (channels * 2));
                if (micTime < intTime) micSkip += skipBytes;
                else if (intTime < micTime) intSkip += skipBytes;
            }
        }

        SidechainDucker[] duckers = null;
        if (!isBroadcast) {
            duckers = new SidechainDucker[channels];
            for (int i = 0; i < channels; i++) {
                duckers[i] = new SidechainDucker(sampleRate, thresholdPct, depthPct, attackMs, releaseMs);
            }
        }

        RandomAccessFile rafMic = hasMic ? new RandomAccessFile(fMic, "r") : null;
        RandomAccessFile rafInt = hasInt ? new RandomAccessFile(fInt, "r") : null;
        RandomAccessFile rafMus = hasMus ? new RandomAccessFile(fMus, "r") : null;

        if (rafMic != null) rafMic.seek(micSkip);
        if (rafInt != null) rafInt.seek(intSkip);
        if (rafMus != null) rafMus.seek(musSkip);

        boolean isM4a = (format == 2);
        FileOutputStream fosWav = null;
        MediaCodec encoder = null;
        MediaMuxer muxer = null;
        int trackIdx = -1;
        boolean muxStarted = false;
        long ptsUs = 0;
        long totalBytes = 0;

        long lenM = hasMic ? (fMic.length() - micSkip) : 0;
        long lenI = hasInt ? (fInt.length() - intSkip) : 0;
        long mainAudioLen = Math.max(lenM, lenI);
        
        long outroHoldBytes = isBroadcast ? (long)(outroHoldSec * sampleRate * channels * 2) : 0;
        long outroFadeBytes = isBroadcast ? (long)(outroFadeSec * sampleRate * channels * 2) : 0;
        outroHoldBytes -= (outroHoldBytes % (channels * 2));
        outroFadeBytes -= (outroFadeBytes % (channels * 2));
        
        long totalFileLen = (hasMic || hasInt) ? (mainAudioLen + outroHoldBytes + outroFadeBytes + introBytesTotal) : (hasMus ? (fMus.length() - musSkip) : 0);
        long currentReadLen = 0;
        int lastProgress = 0;
        String progFile = outPath + ".prog";

        if (!isM4a) {
            fosWav = new FileOutputStream(outPath);
            fosWav.write(new byte[44]);
        } else {
            MediaFormat f = MediaFormat.createAudioFormat("audio/mp4a-latm", sampleRate, channels);
            f.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC);
            f.setInteger(MediaFormat.KEY_BIT_RATE, bitrate);
            f.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 524288);
            encoder = MediaCodec.createEncoderByType("audio/mp4a-latm");
            encoder.configure(f, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
            encoder.start();
            muxer = new MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
        }

        int bufSize = 32768;
        byte[] bM = new byte[bufSize];
        byte[] bI = new byte[bufSize];
        byte[] bMus = new byte[bufSize];
        ByteBuffer bbOut = ByteBuffer.allocate(bufSize).order(ByteOrder.LITTLE_ENDIAN);
        MediaCodec.BufferInfo info = isM4a ? new MediaCodec.BufferInfo() : null;
        
        boolean readEOF = false;
        long introRemain = introBytesTotal;
        long mainShortsDone = 0;
        long duckRampFrames = (long) (0.5f * sampleRate);
        boolean inOutroPhase = false;
        long currentOutroBytes = 0;
        float currentMusicVol = volMus;
        float outroFadeEff = Math.max(outroFadeSec, 0.05f);
        float outroSwellSec = outroHoldSec > 0f ? Math.min(0.6f, outroHoldSec * 0.5f) : 0f;
        float outroPeakVol = outroHoldSec > 0f ? Math.max(1.0f, volMus) : volMus;
        long outroTotalFrames = (long) ((Math.max(outroHoldSec, 0f) + outroFadeEff) * sampleRate);

        while (!readEOF) {
            int rM = -1, rI = -1;
            boolean inIntro = isBroadcast && !inOutroPhase && introRemain > 0;
            if (!inOutroPhase && !inIntro) {
                if (rafMic != null) rM = rafMic.read(bM);
                if (rafInt != null) rI = rafInt.read(bI);
                
                if (rM <= 0 && rI <= 0) {
                    if (isBroadcast && hasMus && (outroHoldSec > 0 || outroFadeSec > 0)) {
                        inOutroPhase = true;
                    } else {
                        readEOF = true;
                        break;
                    }
                }
            }

            int rMus = -1;
            if (rafMus != null) {
                rMus = 0;
                int guardLoop = 0;
                while (rMus < bufSize && guardLoop < 256) {
                    int nRead = rafMus.read(bMus, rMus, bufSize - rMus);
                    if (nRead <= 0) {
                        rafMus.seek(musLoopStart);
                        guardLoop++;
                    } else {
                        rMus += nRead;
                    }
                }
                if (rMus > 0) rMus -= (rMus % (2 * channels));
            }

            if (inOutroPhase && rMus <= 0) {
                readEOF = true;
                break;
            }

            int lM = Math.max(rM, 0);
            int lI = Math.max(rI, 0);
            int lMus = Math.max(rMus, 0);
            int maxLen = inOutroPhase ? lMus : ((hasMic || hasInt) ? Math.max(lM, lI) : lMus);
            if (inIntro) {
                maxLen = (int) Math.min((long) lMus, introRemain);
                maxLen -= (maxLen % (2 * channels));
                introRemain -= maxLen;
                if (maxLen <= 0) introRemain = 0;
            }
            int maxShorts = maxLen / 2;
            int outShorts = maxShorts;
            if (isBroadcast && !inOutroPhase && rafMus != null && rMus > maxLen) {
                long rewPos = rafMus.getFilePointer() - (rMus - maxLen);
                if (rewPos < musBase) rewPos = musBase;
                rafMus.seek(rewPos);
            }
            currentReadLen += maxLen;

            if (totalFileLen > 0) {
                int currentProgress = (int) ((currentReadLen * 100) / totalFileLen);
                if (currentProgress > lastProgress && currentProgress <= 100) {
                    lastProgress = currentProgress;
                    try {
                        FileOutputStream pfos = new FileOutputStream(progFile);
                        pfos.write(String.valueOf(currentProgress).getBytes()); laporUmum((int) (currentProgress));
                        pfos.close();
                    } catch(Exception ignored) {}
                }
            }

            if (maxShorts > 0) {
                bbOut.clear();
                ByteBuffer bbMic = ByteBuffer.wrap(bM, 0, lM).order(ByteOrder.LITTLE_ENDIAN);
                ByteBuffer bbInt = ByteBuffer.wrap(bI, 0, lI).order(ByteOrder.LITTLE_ENDIAN);
                ByteBuffer bbMus = ByteBuffer.wrap(bMus, 0, lMus).order(ByteOrder.LITTLE_ENDIAN);

                for (int i = 0; i < maxShorts; i++) {
                    short sM = (!inOutroPhase && bbMic.hasRemaining()) ? bbMic.getShort() : 0;
                    short sI = (!inOutroPhase && bbInt.hasRemaining()) ? bbInt.getShort() : 0;
                    short sMus = bbMus.hasRemaining() ? bbMus.getShort() : 0;
                    
                    int mixed = 0;

                    if (isBroadcast) {
                        if (inOutroPhase) {
                            long frIdx = currentOutroBytes / (2L * channels);
                            if (frIdx >= outroTotalFrames) {
                                readEOF = true;
                                outShorts = i;
                                break;
                            }
                            float tSec = (float) frIdx / (float) sampleRate;
                            float vol;
                            if (tSec < outroSwellSec) {
                                float x = tSec / outroSwellSec;
                                float sm = x * x * (3f - 2f * x);
                                vol = volMus + (outroPeakVol - volMus) * sm;
                            } else if (tSec < outroHoldSec) {
                                vol = outroPeakVol;
                            } else {
                                float x = (tSec - Math.max(outroHoldSec, 0f)) / outroFadeEff;
                                if (x > 1f) x = 1f;
                                vol = outroPeakVol * (0.5f * (1f + (float) Math.cos(Math.PI * x)));
                            }
                            mixed = (int) (sMus * vol);
                            currentOutroBytes += 2;
                        } else if (inIntro) {
                            mixed = (int) (sMus * 1.0f);
                        } else {
                            float volNow = volMus;
                            if (introBytesTotal > 0) {
                                long frMain = mainShortsDone / channels;
                                if (frMain < duckRampFrames) {
                                    float x = (float) frMain / (float) duckRampFrames;
                                    float sm = x * x * (3f - 2f * x);
                                    volNow = 1.0f + (volMus - 1.0f) * sm;
                                }
                            }
                            mainShortsDone++;
                            mixed = (int) ((sM * volM) + (sI * volI) + (sMus * volNow));
                        }
                    } else {
                        int chIdx = i % channels;
                        short pemicu = 0;
                        if (triggerMode == 1) pemicu = sM;
                        else if (triggerMode == 2) pemicu = sI;
                        else if (triggerMode == 3) {
                            int p = sM + sI;
                            pemicu = (short) Math.max(-32768, Math.min(32767, p));
                        }
                        float sMusMute = (float) sMus * volMus;
                        short duckedMus = duckers[chIdx].process(pemicu, (short) Math.max(-32768, Math.min(32767, sMusMute)));
                        mixed = (int) ((sM * volM) + (sI * volI) + duckedMus);
                    }

                    if (mixed > 32767) mixed = 32767;
                    else if (mixed < -32768) mixed = -32768;

                    bbOut.putShort((short) mixed);
                }

                if (outShorts <= 0) continue;
                int bytesToWrite = outShorts * 2;
                if (!isM4a) {
                    fosWav.write(bbOut.array(), 0, bytesToWrite);
                    totalBytes += bytesToWrite;
                } else {
                    int inIdx = -1;
                    while (inIdx < 0) {
                        inIdx = encoder.dequeueInputBuffer(10000);
                        if (inIdx >= 0) {
                            ByteBuffer inBuf = encoder.getInputBuffer(inIdx);
                            inBuf.clear();
                            inBuf.put(bbOut.array(), 0, bytesToWrite);
                            encoder.queueInputBuffer(inIdx, 0, bytesToWrite, ptsUs, 0);
                            ptsUs += (long) bytesToWrite * 1000000L / (sampleRate * channels * 2);
                        }
                        while (true) {
                            int outIdx = encoder.dequeueOutputBuffer(info, 10000);
                            if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                                trackIdx = muxer.addTrack(encoder.getOutputFormat());
                                muxer.start();
                                muxStarted = true;
                            } else if (outIdx >= 0) {
                                ByteBuffer outBuf = encoder.getOutputBuffer(outIdx);
                                if (info.size > 0 && muxStarted) {
                                    outBuf.position(info.offset);
                                    outBuf.limit(info.offset + info.size);
                                    muxer.writeSampleData(trackIdx, outBuf, info);
                                }
                                encoder.releaseOutputBuffer(outIdx, false);
                            } else {
                                break;
                            }
                        }
                    }
                }
            }
        }

        if (rafMic != null) rafMic.close();
        if (rafInt != null) rafInt.close();
        if (rafMus != null) rafMus.close();

        if (!isM4a) {
            fosWav.close();
            RandomAccessFile rafWav = new RandomAccessFile(outPath, "rw");
            rafWav.seek(0);
            ByteBuffer head = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
            head.put("RIFF".getBytes()); head.putInt((int) totalBytes + 36);
            head.put("WAVE".getBytes()); head.put("fmt ".getBytes());
            head.putInt(16); head.putShort((short) 1); head.putShort((short) channels);
            head.putInt(sampleRate); head.putInt(sampleRate * channels * 2);
            head.putShort((short) (channels * 2)); head.putShort((short) 16);
            head.put("data".getBytes()); head.putInt((int) totalBytes);
            rafWav.write(head.array());
            rafWav.close();
        } else {
            int inIdx = -1;
            while (inIdx < 0) {
                inIdx = encoder.dequeueInputBuffer(10000);
                if (inIdx >= 0) {
                    encoder.queueInputBuffer(inIdx, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                } else {
                    while (true) {
                        int outIdx = encoder.dequeueOutputBuffer(info, 10000);
                        if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                            trackIdx = muxer.addTrack(encoder.getOutputFormat());
                            muxer.start();
                            muxStarted = true;
                        } else if (outIdx >= 0) {
                            ByteBuffer outBuf = encoder.getOutputBuffer(outIdx);
                            if (info.size > 0 && muxStarted) {
                                outBuf.position(info.offset);
                                outBuf.limit(info.offset + info.size);
                                muxer.writeSampleData(trackIdx, outBuf, info);
                            }
                            encoder.releaseOutputBuffer(outIdx, false);
                        } else {
                            break;
                        }
                    }
                }
            }
            while (true) {
                int outIdx = encoder.dequeueOutputBuffer(info, 10000);
                if (outIdx >= 0) {
                    ByteBuffer outBuf = encoder.getOutputBuffer(outIdx);
                    if (info.size > 0 && muxStarted) {
                        outBuf.position(info.offset);
                        outBuf.limit(info.offset + info.size);
                        muxer.writeSampleData(trackIdx, outBuf, info);
                    }
                    encoder.releaseOutputBuffer(outIdx, false);
                    if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break;
                } else if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    trackIdx = muxer.addTrack(encoder.getOutputFormat());
                    muxer.start();
                    muxStarted = true;
                } else if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    break;
                }
            }
            encoder.stop(); encoder.release();
            if (muxStarted) { muxer.stop(); muxer.release(); }
        }

        new File(progFile).delete();
        return "SUKSES";
    } catch (Exception e) {
        return "ERROR: " + e.getMessage();
    }
}

// =====================================================================
//  KONVERSI AUDIO  (mesin konversi dimuat satu ClassLoader dengan FastMuxer)
//  Semua pemanggilan ke mesin konversi memakai refleksi, sehingga FastMuxer
//  tetap bisa dikompilasi tanpa berkas mesin konversi, dan fitur lain tidak terganggu.
// =====================================================================
private static final String FF_PAKET = "com.arthenica.ffmpegkit.";

private static Class<?> ffKelas(String nama) throws Exception {
    return Class.forName(FF_PAKET + nama, true, FastMuxer.class.getClassLoader());
}

private static String ffRingkasGalat(Throwable t) {
    StringBuilder sb = new StringBuilder();
    int n = 0;
    while (t != null && n < 4) {
        if (n > 0) sb.append(" <- ");
        sb.append(t.getClass().getSimpleName());
        String m = t.getMessage();
        if (m != null && !m.isEmpty()) {
            if (m.length() > 300) m = m.substring(0, 300);
            sb.append(": ").append(m);
        }
        t = t.getCause();
        n++;
    }
    return sb.toString();
}

// Memastikan mesin konversi benar-benar termuat. Hasil: "SUKSES|versi" atau "GAGAL: alasan"
public static String konversiSiap() {
    try {
        Class<?> cfg = ffKelas("FFmpegKitConfig");
        Object v = cfg.getMethod("getFFmpegVersion").invoke(null);
        return "SUKSES|" + String.valueOf(v);
    } catch (Throwable t) {
        return "GAGAL: " + ffRingkasGalat(t);
    }
}

private static int ffTerdekat(int nilai, int[] himpunan) {
    int terbaik = himpunan[0];
    int selisih = Math.abs(nilai - terbaik);
    for (int i = 1; i < himpunan.length; i++) {
        int s = Math.abs(nilai - himpunan[i]);
        if (s < selisih) { selisih = s; terbaik = himpunan[i]; }
    }
    return terbaik;
}

// Menyesuaikan sample rate dengan yang didukung format. 0 = biarkan seperti aslinya.
private static int ffSampleRate(String fmt, int sr) {
    if (fmt.equals("amr")) return 8000;
    if (fmt.equals("awb")) return 16000;
    if (sr <= 0) return 0;
    if (fmt.equals("mp3")) return ffTerdekat(sr, new int[]{8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000});
    if (fmt.equals("opus")) return ffTerdekat(sr, new int[]{8000, 12000, 16000, 24000, 48000});
    if (fmt.equals("ac3")) return ffTerdekat(sr, new int[]{32000, 44100, 48000});
    if (fmt.equals("mp2")) return ffTerdekat(sr, new int[]{16000, 22050, 24000, 32000, 44100, 48000});
    if (fmt.equals("wma")) return Math.min(sr, 48000);
    if (fmt.equals("m4a") || fmt.equals("aac")) return ffTerdekat(sr, new int[]{8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000, 64000, 88200, 96000});
    return sr;
}

// Menyesuaikan bitrate dengan yang didukung format. 0 = bawaan format. Mengembalikan 0 bila format tanpa bitrate.
private static int ffBitrate(String fmt, int br, int srAkhir) {
    if (fmt.equals("wav") || fmt.equals("flac") || fmt.equals("alac") || fmt.equals("aiff")) return 0;
    if (fmt.equals("amr")) {
        int[] h = {4750, 5150, 5900, 6700, 7400, 7950, 10200, 12200};
        return br <= 0 ? 12200 : ffTerdekat(br, h);
    }
    if (fmt.equals("awb")) {
        int[] h = {6600, 8850, 12650, 14250, 15850, 18250, 19850, 23050, 23850};
        return br <= 0 ? 23850 : ffTerdekat(br, h);
    }
    if (br <= 0) return 0;
    if (fmt.equals("ac3")) return ffTerdekat(br, new int[]{32000, 40000, 48000, 56000, 64000, 80000, 96000, 112000, 128000, 160000, 192000, 224000, 256000, 320000, 384000, 448000, 512000, 576000, 640000});
    if (fmt.equals("mp2")) {
        if (srAkhir > 0 && srAkhir <= 24000) return ffTerdekat(br, new int[]{8000, 16000, 24000, 32000, 40000, 48000, 56000, 64000, 80000, 96000, 112000, 128000, 144000, 160000});
        return ffTerdekat(br, new int[]{32000, 48000, 56000, 64000, 80000, 96000, 112000, 128000, 160000, 192000, 224000, 256000, 320000, 384000});
    }
    if (fmt.equals("mp3")) {
        int[] h = {8000, 16000, 24000, 32000, 40000, 48000, 56000, 64000, 80000, 96000, 112000, 128000, 160000, 192000, 224000, 256000, 320000};
        int hasil = ffTerdekat(br, h);
        if (srAkhir > 0 && srAkhir <= 24000 && hasil > 160000) hasil = 160000;
        if (srAkhir >= 32000 && hasil < 32000) hasil = 32000;
        return hasil;
    }
    if (fmt.equals("opus")) return Math.max(6000, Math.min(br, 510000));
    if (fmt.equals("ogg")) return Math.max(32000, br);
    if (fmt.equals("wma")) return Math.max(32000, Math.min(br, 320000));
    return br;
}

// Membangun daftar argumen untuk mesin konversi
private static java.util.ArrayList<String> ffArgumen(String masuk, String keluar, String fmt, int sr, int ch, int br) {
    java.util.ArrayList<String> a = new java.util.ArrayList<String>();
    String codec;
    String muxer;
    if (fmt.equals("mp3")) { codec = "libmp3lame"; muxer = "mp3"; }
    else if (fmt.equals("m4a")) { codec = "aac"; muxer = "ipod"; }
    else if (fmt.equals("aac")) { codec = "aac"; muxer = "adts"; }
    else if (fmt.equals("ogg")) { codec = "libvorbis"; muxer = "ogg"; }
    else if (fmt.equals("opus")) { codec = "libopus"; muxer = "opus"; }
    else if (fmt.equals("wav")) { codec = "pcm_s16le"; muxer = "wav"; }
    else if (fmt.equals("flac")) { codec = "flac"; muxer = "flac"; }
    else if (fmt.equals("alac")) { codec = "alac"; muxer = "ipod"; }
    else if (fmt.equals("wma")) { codec = "wmav2"; muxer = "asf"; }
    else if (fmt.equals("amr")) { codec = "libopencore_amrnb"; muxer = "amr"; }
    else if (fmt.equals("awb")) { codec = "libvo_amrwbenc"; muxer = "amr"; }
    else if (fmt.equals("ac3")) { codec = "ac3"; muxer = "ac3"; }
    else if (fmt.equals("mp2")) { codec = "mp2"; muxer = "mp2"; }
    else if (fmt.equals("aiff")) { codec = "pcm_s16be"; muxer = "aiff"; }
    else return null;

    int srAkhir = ffSampleRate(fmt, sr);
    int brAkhir = ffBitrate(fmt, br, srAkhir);
    int chAkhir = ch;
    if (fmt.equals("amr") || fmt.equals("awb")) chAkhir = 1;
    if (fmt.equals("mp3") && chAkhir > 2) chAkhir = 2;

    a.add("-y");
    a.add("-i"); a.add(masuk);
    a.add("-vn");
    a.add("-map"); a.add("0:a:0");
    a.add("-map_metadata"); a.add("0");
    a.add("-c:a"); a.add(codec);
    if (brAkhir > 0) { a.add("-b:a"); a.add(String.valueOf(brAkhir)); }
    if (srAkhir > 0) { a.add("-ar"); a.add(String.valueOf(srAkhir)); }
    if (chAkhir > 0) { a.add("-ac"); a.add(String.valueOf(chAkhir)); }
    if (fmt.equals("mp3")) { a.add("-id3v2_version"); a.add("3"); }
    a.add("-f"); a.add(muxer);
    a.add(keluar);
    return a;
}

private static long ffDurasiMs(String jalur) {
    android.media.MediaMetadataRetriever mmr = null;
    try {
        mmr = new android.media.MediaMetadataRetriever();
        mmr.setDataSource(jalur);
        String d = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION);
        if (d != null) return Long.parseLong(d.trim());
    } catch (Throwable ignored) {
    } finally {
        try { if (mmr != null) mmr.release(); } catch (Throwable ignored) {}
    }
    return 0L;
}

// Mengonversi satu audio. idx/total dipakai untuk persen keseluruhan saat banyak file.
// Hasil: "SUKSES" atau "GAGAL: alasan"
public static String konversiAudio(String masuk, String keluar, String fmt, int sr, int ch, int br, int idx, int total) {
    final int fIdx = Math.max(1, idx);
    final int fTotal = Math.max(1, total);
    File sementara = null;
    Object cbObj = null;
    Class<?> kelasCfg = null;
    Class<?> kelasCb = null;
    try {
        if (masuk == null || masuk.isEmpty() || keluar == null || keluar.isEmpty()) return "GAGAL: jalur berkas kosong";
        if (!masuk.startsWith("/")) masuk = "/" + masuk;
        if (!keluar.startsWith("/")) keluar = "/" + keluar;
        File fMasuk = new File(masuk);
        if (!fMasuk.exists()) return "GAGAL: berkas sumber tidak ditemukan";
        File dirKeluar = new File(keluar).getParentFile();
        if (dirKeluar != null && !dirKeluar.exists()) dirKeluar.mkdirs();

        String nama = fMasuk.getName();
        tahap("Mengonversi audio " + fIdx + " dari " + fTotal);
        laporUmum(((fIdx - 1) * 100) / fTotal);

        sementara = new File(keluar + ".part");
        if (sementara.exists()) sementara.delete();
        java.util.ArrayList<String> args = ffArgumen(masuk, sementara.getAbsolutePath(), fmt, sr, ch, br);
        if (args == null) return "GAGAL: format tujuan tidak dikenal";
        String[] arr = args.toArray(new String[0]);

        final long durMs = ffDurasiMs(masuk);

        kelasCfg = ffKelas("FFmpegKitConfig");
        kelasCb = ffKelas("StatisticsCallback");
        final Class<?> kelasStat = ffKelas("Statistics");
        cbObj = java.lang.reflect.Proxy.newProxyInstance(kelasCb.getClassLoader(), new Class<?>[]{kelasCb},
            new java.lang.reflect.InvocationHandler() {
                public Object invoke(Object proxy, java.lang.reflect.Method m, Object[] a) throws Throwable {
                    String n = m.getName();
                    if (m.getDeclaringClass() == Object.class) {
                        if (n.equals("hashCode")) return Integer.valueOf(System.identityHashCode(proxy));
                        if (n.equals("equals")) return Boolean.valueOf(a != null && a.length > 0 && proxy == a[0]);
                        return "NadiProgres";
                    }
                    try {
                        if (n.equals("apply") && a != null && a.length == 1 && a[0] != null && durMs > 0) {
                            double t = ((Number) kelasStat.getMethod("getTime").invoke(a[0])).doubleValue();
                            double f = t / (double) durMs;
                            if (f < 0.0) f = 0.0;
                            if (f > 1.0) f = 1.0;
                            int persen = (int) (((double) (fIdx - 1) + f) * 100.0 / (double) fTotal);
                            laporUmum(persen);
                        }
                    } catch (Throwable ignored) {}
                    return null;
                }
            });
        kelasCfg.getMethod("enableStatisticsCallback", kelasCb).invoke(null, cbObj);

        Object sesi = ffKelas("FFmpegKit").getMethod("executeWithArguments", String[].class).invoke(null, (Object) arr);

        Class<?> kelasSesi = ffKelas("Session");
        Class<?> kelasKode = ffKelas("ReturnCode");
        Object kode = kelasSesi.getMethod("getReturnCode").invoke(sesi);
        boolean sukses = ((Boolean) kelasKode.getMethod("isSuccess", kelasKode).invoke(null, kode)).booleanValue();
        if (!sukses) {
            boolean batal = ((Boolean) kelasKode.getMethod("isCancel", kelasKode).invoke(null, kode)).booleanValue();
            String log = "";
            try {
                Object l = kelasSesi.getMethod("getAllLogsAsString", int.class).invoke(sesi, Integer.valueOf(2000));
                if (l != null) log = String.valueOf(l).trim();
            } catch (Throwable ignored) {}
            if (log.length() > 700) log = log.substring(log.length() - 700);
            if (sementara.exists()) sementara.delete();
            return "GAGAL: " + (batal ? "dibatalkan" : "konversi " + nama + " tidak berhasil (kode " + String.valueOf(kode) + ")") + (log.isEmpty() ? "" : "\n" + log);
        }
        File fHasil = new File(keluar);
        if (fHasil.exists()) fHasil.delete();
        if (!sementara.renameTo(fHasil)) {
            return "GAGAL: tidak bisa menyimpan hasil ke " + keluar;
        }
        laporUmum((fIdx * 100) / fTotal);
        return "SUKSES";
    } catch (Throwable t) {
        try { if (sementara != null && sementara.exists()) sementara.delete(); } catch (Throwable ignored) {}
        return "GAGAL: " + ffRingkasGalat(t);
    } finally {
        try {
            if (kelasCfg != null && kelasCb != null) kelasCfg.getMethod("enableStatisticsCallback", kelasCb).invoke(null, new Object[]{null});
        } catch (Throwable ignored) {}
    }
}

// =====================================================================
//  KOMPRES VIDEO dan INFO MESIN KONVERSI (memakai pembantu refleksi di atas)
// =====================================================================

// Menjalankan satu perintah dan memantau persen. Hasil: "SUKSES" atau "GAGAL: ..."
private static String ffEksekusi(String[] arr, final long durMs, final int fIdx, final int fTotal) {
    Class<?> kelasCfg = null;
    Class<?> kelasCb = null;
    try {
        kelasCfg = ffKelas("FFmpegKitConfig");
        kelasCb = ffKelas("StatisticsCallback");
        final Class<?> kelasStat = ffKelas("Statistics");
        Object cbObj = java.lang.reflect.Proxy.newProxyInstance(kelasCb.getClassLoader(), new Class<?>[]{kelasCb},
            new java.lang.reflect.InvocationHandler() {
                public Object invoke(Object proxy, java.lang.reflect.Method m, Object[] a) throws Throwable {
                    String n = m.getName();
                    if (m.getDeclaringClass() == Object.class) {
                        if (n.equals("hashCode")) return Integer.valueOf(System.identityHashCode(proxy));
                        if (n.equals("equals")) return Boolean.valueOf(a != null && a.length > 0 && proxy == a[0]);
                        return "NadiProgres";
                    }
                    try {
                        if (n.equals("apply") && a != null && a.length == 1 && a[0] != null && durMs > 0) {
                            double t = ((Number) kelasStat.getMethod("getTime").invoke(a[0])).doubleValue();
                            double f = t / (double) durMs;
                            if (f < 0.0) f = 0.0;
                            if (f > 1.0) f = 1.0;
                            laporUmum((int) (((double) (fIdx - 1) + f) * 100.0 / (double) fTotal));
                        }
                    } catch (Throwable ignored) {}
                    return null;
                }
            });
        kelasCfg.getMethod("enableStatisticsCallback", kelasCb).invoke(null, cbObj);
        Object sesi = ffKelas("FFmpegKit").getMethod("executeWithArguments", String[].class).invoke(null, (Object) arr);
        Class<?> kelasSesi = ffKelas("Session");
        Class<?> kelasKode = ffKelas("ReturnCode");
        Object kode = kelasSesi.getMethod("getReturnCode").invoke(sesi);
        boolean sukses = ((Boolean) kelasKode.getMethod("isSuccess", kelasKode).invoke(null, kode)).booleanValue();
        if (sukses) return "SUKSES";
        String log = "";
        try {
            Object l = kelasSesi.getMethod("getAllLogsAsString", int.class).invoke(sesi, Integer.valueOf(2000));
            if (l != null) log = String.valueOf(l).trim();
        } catch (Throwable ignored) {}
        if (log.length() > 600) log = log.substring(log.length() - 600);
        return "GAGAL: kode " + String.valueOf(kode) + (log.isEmpty() ? "" : "\n" + log);
    } catch (Throwable t) {
        return "GAGAL: " + ffRingkasGalat(t);
    } finally {
        try {
            if (kelasCfg != null && kelasCb != null) kelasCfg.getMethod("enableStatisticsCallback", kelasCb).invoke(null, new Object[]{null});
        } catch (Throwable ignored) {}
    }
}

private static int ffGenap(double nilai) {
    int n = (int) Math.round(nilai / 2.0) * 2;
    return n < 2 ? 2 : n;
}

// Mengompres satu video. tinggiMax = sisi terpendek maksimum (0 = tetap), vBitrate/aBitrate dalam bit per detik.
// Mencoba encoder perangkat keras lebih dulu, lalu cadangan perangkat lunak.
public static String kompresVideo(String masuk, String keluar, String fmt, int tinggiMax, int vBitrate, int aBitrate, int idx, int total) {
    final int fIdx = Math.max(1, idx);
    final int fTotal = Math.max(1, total);
    File sementara = null;
    try {
        if (masuk == null || masuk.isEmpty() || keluar == null || keluar.isEmpty()) return "GAGAL: jalur berkas kosong";
        if (!masuk.startsWith("/")) masuk = "/" + masuk;
        if (!keluar.startsWith("/")) keluar = "/" + keluar;
        File fMasuk = new File(masuk);
        if (!fMasuk.exists()) return "GAGAL: berkas sumber tidak ditemukan";
        File dirKeluar = new File(keluar).getParentFile();
        if (dirKeluar != null && !dirKeluar.exists()) dirKeluar.mkdirs();
        tahap("Mengompres video " + fIdx + " dari " + fTotal);
        laporUmum(((fIdx - 1) * 100) / fTotal);

        long durMs = 0L;
        int lebar = 0, tinggi = 0, rotasi = 0;
        long bitrateSumber = 0L;
        android.media.MediaMetadataRetriever mmr = null;
        try {
            mmr = new android.media.MediaMetadataRetriever();
            mmr.setDataSource(masuk);
            String d = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION);
            String w = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH);
            String h = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT);
            String r = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION);
            String b = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_BITRATE);
            if (d != null) durMs = Long.parseLong(d.trim());
            if (w != null) lebar = Integer.parseInt(w.trim());
            if (h != null) tinggi = Integer.parseInt(h.trim());
            if (r != null) rotasi = Integer.parseInt(r.trim());
            if (b != null) bitrateSumber = Long.parseLong(b.trim());
        } catch (Throwable ignored) {
        } finally {
            try { if (mmr != null) mmr.release(); } catch (Throwable ignored) {}
        }
        if (rotasi == 90 || rotasi == 270) { int tmp = lebar; lebar = tinggi; tinggi = tmp; }

        String filter = null;
        if (tinggiMax > 0 && lebar > 0 && tinggi > 0) {
            int pendek = Math.min(lebar, tinggi);
            if (pendek > tinggiMax) {
                double faktor = (double) tinggiMax / (double) pendek;
                filter = "scale=" + ffGenap(lebar * faktor) + ":" + ffGenap(tinggi * faktor);
            }
        }
        int vb = vBitrate;
        if (bitrateSumber > 0 && vb > (int) (bitrateSumber * 0.8)) vb = (int) (bitrateSumber * 0.8);
        if (vb < 150000) vb = 150000;

        sementara = new File(keluar + ".part");
        String[] daftarEncoder = new String[]{"h264_mediacodec", "libopenh264", "mpeg4"};
        String hasil = "GAGAL: tidak ada pengubah video yang bisa dipakai";
        for (int e = 0; e < daftarEncoder.length; e++) {
            if (sementara.exists()) sementara.delete();
            java.util.ArrayList<String> a = new java.util.ArrayList<String>();
            a.add("-y");
            a.add("-i"); a.add(masuk);
            a.add("-map"); a.add("0:v:0");
            a.add("-map"); a.add("0:a:0?");
            a.add("-map_metadata"); a.add("0");
            if (filter != null) { a.add("-vf"); a.add(filter); }
            a.add("-c:v"); a.add(daftarEncoder[e]);
            a.add("-b:v"); a.add(String.valueOf(vb));
            a.add("-pix_fmt"); a.add("yuv420p");
            a.add("-c:a"); a.add("aac");
            a.add("-b:a"); a.add(String.valueOf(aBitrate > 0 ? aBitrate : 96000));
            a.add("-movflags"); a.add("+faststart");
            a.add("-f"); a.add("mp4");
            a.add(sementara.getAbsolutePath());
            hasil = ffEksekusi(a.toArray(new String[0]), durMs, fIdx, fTotal);
            if (hasil.equals("SUKSES") && sementara.exists() && sementara.length() > 0) break;
            if (hasil.equals("SUKSES")) hasil = "GAGAL: hasil kosong";
        }
        if (!hasil.equals("SUKSES")) {
            if (sementara.exists()) sementara.delete();
            return hasil;
        }
        File fHasil = new File(keluar);
        if (fHasil.exists()) fHasil.delete();
        if (!sementara.renameTo(fHasil)) return "GAGAL: tidak bisa menyimpan hasil ke " + keluar;
        laporUmum((fIdx * 100) / fTotal);
        return "SUKSES";
    } catch (Throwable t) {
        try { if (sementara != null && sementara.exists()) sementara.delete(); } catch (Throwable ignored) {}
        return "GAGAL: " + ffRingkasGalat(t);
    }
}

// Menyimpan daftar kemampuan mesin ke berkas teks. jenis: encoders, decoders, muxers, demuxers, filters, codecs
public static String konversiInfo(String jenis, String keluar, String fmt, int a, int b, int c, int idx, int total) {
    try {
        if (jenis == null || !jenis.matches("[a-z]+")) return "GAGAL: jenis daftar tidak valid";
        if (!keluar.startsWith("/")) keluar = "/" + keluar;
        Class<?> kelasSesi = ffKelas("Session");
        Object sesi = ffKelas("FFmpegKit").getMethod("executeWithArguments", String[].class).invoke(null, (Object) new String[]{"-hide_banner", "-" + jenis});
        Object teks = kelasSesi.getMethod("getAllLogsAsString", int.class).invoke(sesi, Integer.valueOf(5000));
        String isi = teks == null ? "" : String.valueOf(teks);
        if (isi.trim().isEmpty()) return "GAGAL: daftar kosong";
        File f = new File(keluar);
        File dir = f.getParentFile();
        if (dir != null && !dir.exists()) dir.mkdirs();
        java.io.FileOutputStream fos = new java.io.FileOutputStream(f);
        try {
            fos.write(isi.getBytes("UTF-8"));
        } finally {
            fos.close();
        }
        return "SUKSES";
    } catch (Throwable t) {
        return "GAGAL: " + ffRingkasGalat(t);
    }
}

// =============================================================================
//  RAPIKAN SUARA VOKAL
//  Memecah vokal menjadi nada-nada, lalu menggeser nada satu per satu dengan
//  mesin pengubah suara (PSOLA, karakter suara tetap alami).
//  Satu pintu masuk dari Lua: rapikanPerintah(perintah, a, b, c, d) -> teks.
//    siapkan  : a = jalur audio, b = folder kerja   -> "SUKSES:jumlahNada:durMs"
//    pratinjau: a = folder kerja, b = "awalMs,akhirMs,sen", c = wav keluaran
//    render   : a = folder kerja, b = berkas daftar nada, c = wav keluaran,
//               d = "1" untuk melewati bagian kosong yang panjang
// =============================================================================
private static final int RP_SR = 44100;
private static final int RP_HOP = RP_SR / 50;      // 20 milidetik
private static final int RP_DS = 4;                // pengecilan laju untuk pelacak nada
private static final int RP_MS_KOSONG_MIN = 300;   // jeda sependek ini tidak dilewati
private static final int RP_MS_SISA = 80;          // sisa di tiap tepi jeda yang dilewati
private static final int RP_KHOP = RP_SR / 200;     // kontur pergeseran nada per 5 md (lebih rapat dari 20 md supaya batas nada presisi)
private static final int RP_HALUS_LULUS = 16;      // 16 kali rata-rata 3 titik pada 5 md: peralihan sekitar 40 md
private static final int RP_MIN_NADA = 60;         // panjang nada minimum (md) setelah batas dihaluskan

// ============================================================================
//  GEMINI TTS
//  Perintah (lewat rapikanPerintah, awalan "gm_"):
//    gm_buat      : a = JSON permintaan -> "SUKSES|model dipakai|dari cadangan|jumlah bagian|kunci ke-"
//    gm_progres   : "persen|keterangan"
//    gm_model     : a = daftar kunci (satu per baris) -> "SUKSES" lalu satu model per baris
//    gm_model_teks: a = daftar kunci -> "SUKSES" lalu satu model per baris (HANYA Flash dan Flash-Lite, bukan TTS)
//    gm_transkrip : a = JSON {wav, kunci[], model[], tag[], dua} -> "SUKSES\n{transkrip, gaya, teks, model}"
//    gm_saran     : a = JSON {teks, kunci[], model[], tag[], dua} -> "SUKSES\n{gaya, teks, model}"
//    gm_suara     : a = daftar kunci, b = kata cari, c = kode bahasa -> "SUKSES" lalu satu suara per baris
//    gm_sambung   : a = JSON (menyambung rekaman dan hasil Gemini, mengubah sample rate dan channel)
//    gm_cache_info / gm_cache_hapus : a = folder cadangan
//    gm_desain    : a = JSON (kunci, model, nama, gender, bahasa, deskripsi, out, prog) -> "SUKSES|id|nama" (Voice design; contoh suara ditulis ke out)
//    gm_replika   : a = JSON (kunci, model, nama, sumber, persetujuan, simpan, tmp, prog) -> "SUKSES|id atau kunci|nama|id atau kunci" (Voice replication)
//    gm_suara_saya: a = daftar kunci -> "SUKSES" lalu satu suara buatan sendiri per baris (id, nama, bahasa, jenis, model dipisah tab)
//    gm_suara_contoh: a = daftar kunci, b = id suara, c = jalur WAV hasil -> "SUKSES" (hanya suara rancangan yang punya contoh)
//    gm_suara_hapus : a = daftar kunci, b = id suara -> "SUKSES"
//  Suara buatan sendiri (voice_... atau voicekey_...) hanya jalan di model 3.8 ke atas (Interactions API).
//  Model baru (3.8 ke atas) memakai Interactions API; model lama memakai generateContent.
//  Hasil tiap bagian teks disimpan sebagai cadangan supaya teks dan suara yang sama tidak meminta ke Google lagi.
// ============================================================================
private static final String GM_BASE = "https://generativelanguage.googleapis.com/v1beta";
private static final int GM_SR = 24000;
private static final String[] GM_SUARA_BAWAAN = {"Zephyr", "Puck", "Charon", "Kore", "Fenrir", "Leda", "Orus", "Aoede",
    "Callirrhoe", "Autonoe", "Enceladus", "Iapetus", "Umbriel", "Algieba", "Despina", "Erinome", "Algenib", "Rasalgethi",
    "Laomedeia", "Achernar", "Alnilam", "Schedar", "Gacrux", "Pulcherrima", "Achird", "Zubenelgenubi", "Vindemiatrix",
    "Sadachbia", "Sadaltager", "Sulafat"};
private static volatile int gmPersen = 0;
private static volatile String gmInfo = "";
private static volatile String gmProgJalur = "";

private static void gmLapor() {
    String p = gmProgJalur;
    if (p == null || p.length() == 0) return;
    try {
        FileOutputStream fo = new FileOutputStream(p);
        fo.write((gmPersen + "|" + gmInfo).getBytes("UTF-8"));
        fo.close();
    } catch (Throwable t) {
    }
}

// Satu permintaan ke Google tidak punya laporan kemajuan, jadi selama menunggu persen dihitung sebagai PERKIRAAN
// (naik pelan mendekati batas bagiannya, tidak pernah mencapai batas sebelum benar-benar selesai).
private static volatile int gmTickGen = 0;

private static void gmStopTick() { gmTickGen++; }

private static void gmMulaiTick(final int base, final int span, final int chars, final String info) {
    final int gen = ++gmTickGen;
    final long t0 = System.currentTimeMillis();
    Thread th = new Thread(new Runnable() {
        public void run() {
            double tau = 3.0 + chars / 40.0;
            while (gen == gmTickGen) {
                double el = (System.currentTimeMillis() - t0) / 1000.0;
                int pp = base + (int) (span * 0.92 * (1.0 - Math.exp(-el / tau)));
                if (gen != gmTickGen) return;
                if (pp > gmPersen) gmPersen = pp;
                gmInfo = info + " - menunggu Google " + (int) el + " detik";
                gmLapor();
                try { Thread.sleep(500); } catch (InterruptedException ie) { return; }
            }
        }
    });
    th.setDaemon(true);
    th.start();
}

private static final class GmGiliran {
    int s;
    String t;
    GmGiliran(int s, String t) { this.s = s; this.t = t; }
}

private static final class GmCfg {
    boolean dua;
    String v1 = "Kore", v2 = "Puck", st1 = "", st2 = "";
}

private static final class GmWav {
    int sr = GM_SR, ch = 1;
    short[] d = new short[0];
}

private static final class GmHasil {
    int kode;
    String isi;
}

private static String gmDispatch(String cmd, String a, String b, String c, String d) {
    try {
        if ("gm_buat".equals(cmd)) return gmBuat(a);
        if ("gm_transkrip".equals(cmd)) return gmTranskrip(a);
        if ("gm_progres".equals(cmd)) return gmPersen + "|" + gmInfo;
        if ("gm_model".equals(cmd)) return gmDaftarModel(a);
        if ("gm_model_teks".equals(cmd)) return gmDaftarModelTeks(a);
        if ("gm_saran".equals(cmd)) return gmSaran(a);
        if ("gm_suara".equals(cmd)) return gmDaftarSuara(a, b, c, d);
        if ("gm_sambung".equals(cmd)) return gmSambung(a);
        if ("gm_cache_info".equals(cmd)) return gmCacheInfo(a);
        if ("gm_cache_hapus".equals(cmd)) return gmCacheHapus(a);
        if ("gm_desain".equals(cmd)) return gmDesain(a);
        if ("gm_replika".equals(cmd)) return gmReplika(a);
        if ("gm_suara_saya".equals(cmd)) return gmSuaraSaya(a);
        if ("gm_suara_contoh".equals(cmd)) return gmSuaraContoh(a, b, c);
        if ("gm_suara_hapus".equals(cmd)) return gmSuaraHapus(a, b);
        return "GAGAL: perintah Gemini tidak dikenal";
    } catch (Throwable t) {
        return "GAGAL: " + (t.getMessage() == null ? t.toString() : t.getMessage());
    }
}

private static boolean gmModelBaru(String m) {
    java.util.regex.Matcher x = java.util.regex.Pattern.compile("gemini-(\\d+)(?:\\.(\\d+))?").matcher(m);
    if (!x.find()) return false;
    int maj = Integer.parseInt(x.group(1));
    int min = x.group(2) == null ? 0 : Integer.parseInt(x.group(2));
    return maj > 3 || (maj == 3 && min >= 8);
}

private static boolean gmSuaraBawaan(String v) {
    for (int i = 0; i < GM_SUARA_BAWAAN.length; i++) if (GM_SUARA_BAWAAN[i].equals(v)) return true;
    return false;
}

private static boolean gmDalamTag(String s, int cut) {
    int lt = s.lastIndexOf('<', cut - 1);
    if (lt < 0) return false;
    int gt = s.indexOf('>', lt);
    return gt < 0 || gt >= cut;
}

private static java.util.ArrayList<String> gmPecah(String teks, int maks) {
    java.util.ArrayList<String> out = new java.util.ArrayList<String>();
    String s = teks.trim();
    while (s.length() > maks) {
        int cut = -1;
        for (int i = maks; i > maks / 2; i--) {
            char ch = s.charAt(i - 1);
            if ((ch == '.' || ch == '!' || ch == '?' || ch == '\n' || ch == ';') && !gmDalamTag(s, i)) { cut = i; break; }
        }
        if (cut < 0) {
            for (int i = maks; i > maks / 2; i--) {
                char ch = s.charAt(i - 1);
                if ((ch == ',' || ch == ' ') && !gmDalamTag(s, i)) { cut = i; break; }
            }
        }
        if (cut < 0) cut = maks;
        String bag = s.substring(0, cut).trim();
        if (bag.length() > 0) out.add(bag);
        s = s.substring(cut).trim();
    }
    if (s.length() > 0) out.add(s);
    return out;
}

// ----------------------------------------------------------------------------
//  SUARA JADI TEKS (transkripsi lewat Gemini generateContent, audio inline, maksimal 20 MB per permintaan)
//  Masukan JSON: {wav (WAV PCM16 mono), kunci [..], model [..] (dicoba berurutan), prompt (opsional)}
//  Hasil: "SUKSES\n<teks>" atau "GAGAL: ..."
// ----------------------------------------------------------------------------
private static String gmAmbilTeks(String isi) {
    try {
        org.json.JSONObject o = new org.json.JSONObject(isi);
        org.json.JSONArray cs = o.optJSONArray("candidates");
        if (cs == null || cs.length() == 0) return "";
        org.json.JSONObject c0 = cs.optJSONObject(0);
        if (c0 == null) return "";
        org.json.JSONObject ct = c0.optJSONObject("content");
        if (ct == null) return "";
        org.json.JSONArray ps = ct.optJSONArray("parts");
        if (ps == null) return "";
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < ps.length(); i++) {
            org.json.JSONObject p = ps.optJSONObject(i);
            if (p == null || p.optBoolean("thought", false)) continue;
            sb.append(p.optString("text", ""));
        }
        return sb.toString().trim();
    } catch (Throwable t) {
        return "";
    }
}

private static final String GM_TAG_BAWAAN = "<laugh>, <chuckle>, <sigh>, <breath>, <gasp>, <sob>, <cry>, <whimper>, <cough>, <yawn>, <cheer>, <shout>, <whispers>, <short pause>, <long pause>";

private static java.util.ArrayList<String> gmModelDari(org.json.JSONObject j, String bawaan) {
    java.util.ArrayList<String> model = new java.util.ArrayList<String>();
    org.json.JSONArray am = j.optJSONArray("model");
    if (am != null) {
        for (int i = 0; i < am.length(); i++) {
            String m = am.optString(i, "").trim();
            if (m.length() > 0 && !model.contains(m)) model.add(m);
        }
    }
    if (model.isEmpty()) model.add(bawaan);
    return model;
}

private static String gmTagDari(org.json.JSONObject j) {
    org.json.JSONArray a = j.optJSONArray("tag");
    StringBuilder sb = new StringBuilder();
    if (a != null) {
        for (int i = 0; i < a.length(); i++) {
            String t = a.optString(i, "").trim();
            if (t.startsWith("<") && t.endsWith(">") && t.length() < 32) {
                if (sb.length() > 0) sb.append(", ");
                sb.append(t);
            }
        }
    }
    return sb.length() == 0 ? GM_TAG_BAWAAN : sb.toString();
}

private static String gmPromptSaran(String tag, boolean dua, boolean dariSuara) {
    StringBuilder p = new StringBuilder();
    p.append("You are a voice-direction assistant for a Gemini text-to-speech app. ");
    if (dariSuara) {
        p.append("Listen to the speech in the attached audio and return ONE JSON object with exactly these three string fields.\n");
        p.append("1. \"transkrip\": a verbatim transcription in the language(s) actually spoken (Indonesian, Javanese, English, etc.). ");
        p.append("Use proper punctuation. Do NOT translate, summarize, correct or add tags, labels, timestamps or comments. Use an empty string if there is no speech.\n");
    } else {
        p.append("Read the text provided below and return ONE JSON object with exactly these two string fields.\n");
    }
    int n = dariSuara ? 2 : 1;
    p.append(n).append(". \"gaya\": a short voice-direction prompt in English (one sentence, at most 25 words) describing HOW the text should be read aloud so it sounds natural: ");
    p.append("emotion, tone, pace and delivery that match the mood and context of the content ");
    p.append("(example: \"Warm, soft storyteller, slow pace, voice growing shaky and sad near the end\").\n");
    n++;
    p.append(n).append(". \"teks_ekspresi\": the SAME words as the text, in the same language, enriched with expression tags placed where they naturally fit the context. ");
    p.append("Allowed tags (use only these, exactly as written): ").append(tag).append(". ");
    p.append("Rules: never change, delete, translate or reorder the spoken words; only insert tags between words or sentences; ");
    p.append("be sparing (at most about one tag per one or two sentences, only where the emotion really calls for it); ");
    p.append("use <short pause> or <long pause> for pauses, <sob> for sobbing, <sigh> for sighing, <laugh> for laughter, and so on; ");
    p.append("you may write a word in CAPITAL LETTERS to stress it.\n");
    if (dua) {
        p.append("The content may be a dialogue between two speakers. If so, put each speaker's lines on separate lines starting with \"1:\" or \"2:\" ");
        p.append("in every text field, and let \"gaya\" describe both voices briefly.\n");
    }
    p.append("Return only the JSON object, with no markdown fences and no commentary.");
    return p.toString();
}

private static org.json.JSONObject gmBentukSaran(boolean dariSuara) throws Exception {
    org.json.JSONObject props = new org.json.JSONObject();
    org.json.JSONArray req = new org.json.JSONArray();
    if (dariSuara) {
        props.put("transkrip", new org.json.JSONObject().put("type", "STRING"));
        req.put("transkrip");
    }
    props.put("gaya", new org.json.JSONObject().put("type", "STRING"));
    props.put("teks_ekspresi", new org.json.JSONObject().put("type", "STRING"));
    req.put("gaya");
    req.put("teks_ekspresi");
    org.json.JSONObject schema = new org.json.JSONObject();
    schema.put("type", "OBJECT");
    schema.put("properties", props);
    schema.put("required", req);
    org.json.JSONObject gc = new org.json.JSONObject();
    gc.put("responseMimeType", "application/json");
    gc.put("responseSchema", schema);
    return gc;
}

private static org.json.JSONObject gmParseJsonModel(String t) {
    if (t == null) return null;
    String s = t.trim();
    if (s.startsWith("```")) {
        int nl = s.indexOf('\n');
        if (nl > 0) s = s.substring(nl + 1);
        int akhirF = s.lastIndexOf("```");
        if (akhirF >= 0) s = s.substring(0, akhirF);
    }
    int a = s.indexOf('{');
    int b = s.lastIndexOf('}');
    if (a < 0 || b <= a) return null;
    try {
        return new org.json.JSONObject(s.substring(a, b + 1));
    } catch (Throwable e) {
        return null;
    }
}

// Urutan: per model, semua kunci dicoba dulu; kunci yang jatahnya habis (429) dilewati ke kunci berikutnya,
// kalau semua kunci habis pindah ke model berikutnya. 401/403 = kunci dilewati untuk semua model.
// 404/400 = langsung model berikutnya. 5xx/jaringan = diulang sekali.
// Hasil: teks jawaban, atau null kalau semua gagal (galat[0] = alasan). galat[1] = model yang dipakai.
private static String gmGenerasi(java.util.ArrayList<String> kunci, java.util.ArrayList<String> model, String body, String[] galat) {
    boolean[] kunciMati = new boolean[kunci.size()];
    String pesanAkhir = "";
    boolean adaJatahHabis = false;
    for (int mi = 0; mi < model.size(); mi++) {
        boolean modelTidakCocok = false;
        for (int ki = 0; ki < kunci.size() && !modelTidakCocok; ki++) {
            if (kunciMati[ki]) continue;
            GmHasil r = null;
            for (int p = 0; p < 2; p++) {
                try {
                    r = gmHttp("POST", GM_BASE + "/models/" + model.get(mi) + ":generateContent", kunci.get(ki), body, 120000);
                } catch (IOException e) {
                    r = null;
                    pesanAkhir = e.getMessage() == null ? e.toString() : e.getMessage();
                    try { Thread.sleep(1200); } catch (InterruptedException ie) { }
                    continue;
                }
                if (r.kode >= 500) {
                    pesanAkhir = "Server Google sedang sibuk (" + r.kode + ")";
                    r = null;
                    try { Thread.sleep(1500); } catch (InterruptedException ie) { }
                    continue;
                }
                break;
            }
            if (r == null) continue;
            if (r.kode == 200) {
                galat[1] = model.get(mi);
                return gmAmbilTeks(r.isi);
            }
            String m = gmPesanGalat(r.isi);
            pesanAkhir = m;
            String ml = m.toLowerCase();
            if (r.kode == 429) {
                adaJatahHabis = true;
                pesanAkhir = "Jatah model " + model.get(mi) + " habis untuk kunci ke-" + (ki + 1);
            } else if (r.kode == 401 || r.kode == 403 || ml.indexOf("api key") >= 0) {
                kunciMati[ki] = true;
            } else if (r.kode == 404 || r.kode == 400) {
                modelTidakCocok = true;
            }
        }
    }
    boolean semuaMati = kunci.size() > 0;
    for (int i = 0; i < kunciMati.length; i++) if (!kunciMati[i]) semuaMati = false;
    if (semuaMati) {
        galat[0] = "Semua kunci API ditolak Google. Periksa kuncinya di Pengaturan Gemini TTS. " + pesanAkhir;
    } else if (adaJatahHabis) {
        galat[0] = "Jatah semua kunci dan model sudah habis. Coba lagi nanti atau tambah kunci/model. " + pesanAkhir;
    } else {
        galat[0] = pesanAkhir.length() == 0 ? "tidak bisa menghubungi Gemini" : pesanAkhir;
    }
    return null;
}

private static String gmSaranKeluar(String t, boolean dariSuara, String modelPakai, String teksAsal) throws Exception {
    org.json.JSONObject o = gmParseJsonModel(t);
    org.json.JSONObject out = new org.json.JSONObject();
    if (o == null) {
        out.put("transkrip", dariSuara ? (t == null ? "" : t.trim()) : "");
        out.put("gaya", "");
        out.put("teks", teksAsal == null ? "" : teksAsal);
    } else {
        if (dariSuara) out.put("transkrip", o.optString("transkrip", "").trim());
        out.put("gaya", o.optString("gaya", "").trim());
        out.put("teks", o.optString("teks_ekspresi", "").trim());
    }
    out.put("model", modelPakai == null ? "" : modelPakai);
    return "SUKSES\n" + out.toString();
}

private static String gmTranskrip(String json) throws Exception {
    org.json.JSONObject j = new org.json.JSONObject(json);
    java.util.ArrayList<String> kunci = gmKunciDari(j);
    java.util.ArrayList<String> model = gmModelDari(j, "gemini-2.5-flash");
    if (kunci.isEmpty()) return "GAGAL: Kunci API Gemini belum diisi. Isi dulu di Pengaturan Gemini TTS.";
    File f = new File(j.optString("wav", ""));
    if (!f.exists() || f.length() < 8000) return "GAGAL: Rekaman terlalu pendek.";
    if (f.length() > 14L * 1024L * 1024L) return "GAGAL: Rekaman terlalu panjang (maksimal sekitar 7 menit).";
    String b64 = android.util.Base64.encodeToString(gmBacaSemua(f), android.util.Base64.NO_WRAP);
    String prompt = gmPromptSaran(gmTagDari(j), j.optBoolean("dua", false), true);
    org.json.JSONObject dataIn = new org.json.JSONObject();
    dataIn.put("mime_type", "audio/wav");
    dataIn.put("data", b64);
    org.json.JSONObject pAudio = new org.json.JSONObject();
    pAudio.put("inline_data", dataIn);
    org.json.JSONObject pTeks = new org.json.JSONObject();
    pTeks.put("text", prompt);
    org.json.JSONArray parts = new org.json.JSONArray();
    parts.put(pTeks);
    parts.put(pAudio);
    org.json.JSONObject konten = new org.json.JSONObject();
    konten.put("parts", parts);
    org.json.JSONArray kontenList = new org.json.JSONArray();
    kontenList.put(konten);
    org.json.JSONObject root = new org.json.JSONObject();
    root.put("contents", kontenList);
    root.put("generationConfig", gmBentukSaran(true));
    String[] galat = new String[]{"", ""};
    String t = gmGenerasi(kunci, model, root.toString(), galat);
    if (t == null) return "GAGAL: " + galat[0];
    if (t.length() == 0) return "GAGAL: Tidak ada ucapan yang terdengar. Coba bicara lebih dekat ke mikrofon.";
    String hasil = gmSaranKeluar(t, true, galat[1], "");
    org.json.JSONObject cek = new org.json.JSONObject(hasil.substring(7));
    if (cek.optString("transkrip", "").length() == 0) return "GAGAL: Tidak ada ucapan yang terdengar. Coba bicara lebih dekat ke mikrofon.";
    return hasil;
}

private static String gmSaran(String json) throws Exception {
    org.json.JSONObject j = new org.json.JSONObject(json);
    java.util.ArrayList<String> kunci = gmKunciDari(j);
    java.util.ArrayList<String> model = gmModelDari(j, "gemini-2.5-flash");
    if (kunci.isEmpty()) return "GAGAL: Kunci API Gemini belum diisi. Isi dulu di Pengaturan Gemini TTS.";
    String teks = j.optString("teks", "").trim();
    if (teks.length() < 2) return "GAGAL: Teksnya masih kosong.";
    if (teks.length() > 8000) teks = teks.substring(0, 8000);
    String prompt = gmPromptSaran(gmTagDari(j), j.optBoolean("dua", false), false) + "\n\nTEXT:\n" + teks;
    org.json.JSONObject pTeks = new org.json.JSONObject();
    pTeks.put("text", prompt);
    org.json.JSONArray parts = new org.json.JSONArray();
    parts.put(pTeks);
    org.json.JSONObject konten = new org.json.JSONObject();
    konten.put("parts", parts);
    org.json.JSONArray kontenList = new org.json.JSONArray();
    kontenList.put(konten);
    org.json.JSONObject root = new org.json.JSONObject();
    root.put("contents", kontenList);
    root.put("generationConfig", gmBentukSaran(false));
    String[] galat = new String[]{"", ""};
    String t = gmGenerasi(kunci, model, root.toString(), galat);
    if (t == null) return "GAGAL: " + galat[0];
    if (t.length() == 0) return "GAGAL: Gemini tidak memberi saran. Coba model lain.";
    return gmSaranKeluar(t, false, galat[1], teks);
}

private static String gmSha(String s) throws Exception {
    java.security.MessageDigest md = java.security.MessageDigest.getInstance("SHA-256");
    byte[] h = md.digest(s.getBytes("UTF-8"));
    StringBuilder sb = new StringBuilder();
    for (int i = 0; i < 16; i++) sb.append(String.format("%02x", h[i] & 0xFF));
    return sb.toString();
}

private static int gmLe16(byte[] b, int p) { return (b[p] & 0xFF) | ((b[p + 1] & 0xFF) << 8); }
private static int gmLe32(byte[] b, int p) { return gmLe16(b, p) | (gmLe16(b, p + 2) << 16); }

// Membaca WAV (mencari potongan fmt dan data). Bila bukan WAV, dianggap PCM 16 bit mono dengan laju dari mime.
private static GmWav gmParse(byte[] b, String mime) {
    GmWav w = new GmWav();
    int off = 0, len = b.length;
    if (b.length > 44 && b[0] == 'R' && b[1] == 'I' && b[2] == 'F' && b[3] == 'F') {
        int p = 12;
        off = -1;
        while (p + 8 <= b.length) {
            int sz = gmLe32(b, p + 4);
            String id = new String(b, p, 4);
            if ("fmt ".equals(id) && p + 20 <= b.length) {
                w.ch = Math.max(1, gmLe16(b, p + 10));
                w.sr = gmLe32(b, p + 12);
            } else if ("data".equals(id)) {
                off = p + 8;
                len = (sz <= 0 || off + (long) sz > b.length) ? b.length - off : sz;
                break;
            }
            if (sz < 0) break;
            p += 8 + sz + (sz & 1);
        }
        if (off < 0) { off = 44; len = Math.max(0, b.length - 44); }
    } else {
        w.sr = GM_SR;
        if (mime != null) {
            java.util.regex.Matcher x = java.util.regex.Pattern.compile("rate=(\\d+)").matcher(mime);
            if (x.find()) w.sr = Integer.parseInt(x.group(1));
        }
    }
    int n = len / 2;
    w.d = new short[n];
    for (int i = 0; i < n; i++) w.d[i] = (short) gmLe16(b, off + i * 2);
    return w;
}

private static GmWav gmBacaWav(String path) throws IOException {
    File f = new File(path);
    byte[] b = new byte[(int) f.length()];
    DataInputStream in = new DataInputStream(new FileInputStream(f));
    try { in.readFully(b); } finally { in.close(); }
    return gmParse(b, null);
}

// Mengubah ke satu channel pada laju tujuan (interpolasi linear), lalu menggandakan ke chOut channel.
private static short[] gmUbah(short[] in, int chIn, int srIn, int chOut, int srOut) {
    if (chIn < 1) chIn = 1;
    int frames = in.length / chIn;
    short[] mono = new short[frames];
    for (int i = 0; i < frames; i++) {
        int sum = 0;
        for (int c = 0; c < chIn; c++) sum += in[i * chIn + c];
        mono[i] = (short) (sum / chIn);
    }
    short[] rs = mono;
    if (srIn != srOut && frames > 1) {
        int nOut = (int) ((long) frames * srOut / srIn);
        rs = new short[nOut];
        double step = (double) srIn / srOut;
        for (int i = 0; i < nOut; i++) {
            double pos = i * step;
            int i0 = (int) pos;
            if (i0 >= frames - 1) { rs[i] = mono[frames - 1]; continue; }
            double fr = pos - i0;
            rs[i] = (short) Math.round(mono[i0] * (1.0 - fr) + mono[i0 + 1] * fr);
        }
    }
    if (chOut <= 1) return rs;
    short[] out = new short[rs.length * chOut];
    for (int i = 0; i < rs.length; i++) for (int c = 0; c < chOut; c++) out[i * chOut + c] = rs[i];
    return out;
}

private static void gmTulisWav(String path, short[] pcm, int sr) throws IOException {
    File tmp = new File(path + ".tmp");
    OutputStream os = new BufferedOutputStream(new FileOutputStream(tmp), 1 << 16);
    try {
        int bytes = pcm.length * 2;
        ByteBuffer h = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
        h.put("RIFF".getBytes()).putInt(36 + bytes).put("WAVE".getBytes()).put("fmt ".getBytes()).putInt(16)
            .putShort((short) 1).putShort((short) 1).putInt(sr).putInt(sr * 2).putShort((short) 2).putShort((short) 16)
            .put("data".getBytes()).putInt(bytes);
        os.write(h.array());
        byte[] buf = new byte[1 << 16];
        int bi = 0;
        for (int i = 0; i < pcm.length; i++) {
            buf[bi++] = (byte) (pcm[i] & 0xFF);
            buf[bi++] = (byte) ((pcm[i] >> 8) & 0xFF);
            if (bi == buf.length) { os.write(buf, 0, bi); bi = 0; }
        }
        if (bi > 0) os.write(buf, 0, bi);
    } finally {
        os.close();
    }
    File dst = new File(path);
    if (dst.exists()) dst.delete();
    if (!tmp.renameTo(dst)) throw new IOException("tidak bisa menyimpan hasil suara");
}

private static GmHasil gmHttp(String metode, String url, String kunci, String body, int bacaMs) throws IOException {
    java.net.HttpURLConnection h = (java.net.HttpURLConnection) new java.net.URL(url).openConnection();
    try {
        h.setRequestMethod(metode);
        h.setConnectTimeout(20000);
        h.setReadTimeout(bacaMs);
        h.setRequestProperty("x-goog-api-key", kunci);
        if (body != null) {
            h.setRequestProperty("Content-Type", "application/json");
            h.setDoOutput(true);
            byte[] bt = body.getBytes("UTF-8");
            h.setFixedLengthStreamingMode(bt.length);
            OutputStream o = h.getOutputStream();
            o.write(bt);
            o.close();
        }
        int kode = h.getResponseCode();
        InputStream in = kode >= 400 ? h.getErrorStream() : h.getInputStream();
        ByteArrayOutputStream bo = new ByteArrayOutputStream();
        if (in != null) {
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
            in.close();
        }
        GmHasil r = new GmHasil();
        r.kode = kode;
        r.isi = bo.toString("UTF-8");
        return r;
    } finally {
        h.disconnect();
    }
}

private static String gmPesanGalat(String isi) {
    try {
        org.json.JSONObject o = new org.json.JSONObject(isi);
        org.json.JSONObject e = o.optJSONObject("error");
        String m = e != null ? e.optString("message", "") : o.optString("message", "");
        if (m.length() > 0) return m.length() > 160 ? m.substring(0, 160) : m;
    } catch (Throwable t) {
    }
    String s = isi == null ? "" : isi.trim();
    return s.length() > 160 ? s.substring(0, 160) : s;
}

private static void gmCari(Object n, String[] best) {
    if (n instanceof org.json.JSONObject) {
        org.json.JSONObject o = (org.json.JSONObject) n;
        String dt = o.optString("data", "");
        if (dt.length() > 200) {
            best[0] = dt;
            best[1] = o.optString("mime_type", o.optString("mimeType", ""));
        }
        java.util.Iterator<String> it = o.keys();
        while (it.hasNext()) {
            Object ch = o.opt(it.next());
            if (ch instanceof org.json.JSONObject || ch instanceof org.json.JSONArray) gmCari(ch, best);
        }
    } else if (n instanceof org.json.JSONArray) {
        org.json.JSONArray ja = (org.json.JSONArray) n;
        for (int i = 0; i < ja.length(); i++) {
            Object ch = ja.opt(i);
            if (ch instanceof org.json.JSONObject || ch instanceof org.json.JSONArray) gmCari(ch, best);
        }
    }
}

private static String gmBodyBaru(String model, GmCfg c, java.util.ArrayList<GmGiliran> turns) throws Exception {
    org.json.JSONObject root = new org.json.JSONObject();
    root.put("model", model);
    root.put("store", false);   // teks yang dibacakan tidak perlu disimpan di server Google
    org.json.JSONArray content = new org.json.JSONArray();
    for (int i = 0; i < turns.size(); i++) {
        GmGiliran g = turns.get(i);
        org.json.JSONObject it = new org.json.JSONObject();
        it.put("type", "text");
        it.put("text", g.t);
        String st = (c.dua && g.s == 2) ? c.st2 : c.st1;
        if (c.dua || st.length() > 0) {
            org.json.JSONObject an = new org.json.JSONObject();
            an.put("type", "speech_metadata");
            if (c.dua) an.put("speaker", g.s == 2 ? "Speaker2" : "Speaker1");
            if (st.length() > 0) an.put("style", st);
            org.json.JSONArray ans = new org.json.JSONArray();
            ans.put(an);
            it.put("annotations", ans);
        }
        content.put(it);
    }
    org.json.JSONObject ui = new org.json.JSONObject();
    ui.put("type", "user_input");
    ui.put("content", content);
    org.json.JSONArray input = new org.json.JSONArray();
    input.put(ui);
    root.put("input", input);
    org.json.JSONObject rf = new org.json.JSONObject();
    rf.put("type", "audio");
    root.put("response_format", rf);
    org.json.JSONObject gc = new org.json.JSONObject();
    if (c.dua) {
        org.json.JSONArray sp = new org.json.JSONArray();
        org.json.JSONObject s1 = new org.json.JSONObject();
        s1.put("speaker", "Speaker1");
        s1.put("voice", c.v1);
        org.json.JSONObject s2 = new org.json.JSONObject();
        s2.put("speaker", "Speaker2");
        s2.put("voice", c.v2);
        sp.put(s1);
        sp.put(s2);
        org.json.JSONObject sc = new org.json.JSONObject();
        sc.put("speakers", sp);
        gc.put("speech_config", sc);
    } else {
        org.json.JSONArray sc = new org.json.JSONArray();
        org.json.JSONObject v = new org.json.JSONObject();
        v.put("voice", c.v1);
        sc.put(v);
        gc.put("speech_config", sc);
    }
    root.put("generation_config", gc);
    return root.toString();
}

private static String gmTagLama(String t, String model) {
    if (model.indexOf("3.1") >= 0) return t.replaceAll("<([a-zA-Z\\- ]+)>", "[$1]");
    return t.replaceAll("<(short|long) pause>", "...").replaceAll("<[a-zA-Z\\- ]+>", "");
}

private static org.json.JSONObject gmSuaraLama(String voice) throws Exception {
    org.json.JSONObject pre = new org.json.JSONObject();
    pre.put("voiceName", voice);
    org.json.JSONObject vc = new org.json.JSONObject();
    vc.put("prebuiltVoiceConfig", pre);
    return vc;
}

private static String gmBodyLama(String model, GmCfg c, java.util.ArrayList<GmGiliran> turns) throws Exception {
    String v1 = gmSuaraBawaan(c.v1) ? c.v1 : "Kore";
    String v2 = gmSuaraBawaan(c.v2) ? c.v2 : "Puck";
    StringBuilder sb = new StringBuilder();
    if (c.dua) {
        sb.append("SYSTEM INSTRUCTION: Generate a podcast dialogue.\n");
        sb.append("Speaker 1 (").append(v1).append(") tone MUST be: ").append(c.st1).append("\n");
        sb.append("Speaker 2 (").append(v2).append(") tone MUST be: ").append(c.st2).append("\n\nDIALOGUE:\n");
        for (int i = 0; i < turns.size(); i++) {
            GmGiliran g = turns.get(i);
            sb.append(g.s == 2 ? "Speaker2: " : "Speaker1: ").append(gmTagLama(g.t, model)).append("\n");
        }
    } else {
        String isi = gmTagLama(turns.get(0).t, model);
        if (c.st1.length() > 0) sb.append("SYSTEM: Perform with this tone: ").append(c.st1).append("\n\nTEXT:\n");
        sb.append(isi);
    }
    org.json.JSONObject root = new org.json.JSONObject();
    org.json.JSONObject part = new org.json.JSONObject();
    part.put("text", sb.toString());
    org.json.JSONArray parts = new org.json.JSONArray();
    parts.put(part);
    org.json.JSONObject cont = new org.json.JSONObject();
    cont.put("parts", parts);
    org.json.JSONArray contents = new org.json.JSONArray();
    contents.put(cont);
    root.put("contents", contents);
    org.json.JSONObject gc = new org.json.JSONObject();
    org.json.JSONArray mod = new org.json.JSONArray();
    mod.put("AUDIO");
    gc.put("responseModalities", mod);
    org.json.JSONObject sc = new org.json.JSONObject();
    if (c.dua) {
        org.json.JSONArray lst = new org.json.JSONArray();
        org.json.JSONObject a1 = new org.json.JSONObject();
        a1.put("speaker", "Speaker1");
        a1.put("voiceConfig", gmSuaraLama(v1));
        org.json.JSONObject a2 = new org.json.JSONObject();
        a2.put("speaker", "Speaker2");
        a2.put("voiceConfig", gmSuaraLama(v2));
        lst.put(a1);
        lst.put(a2);
        org.json.JSONObject ms = new org.json.JSONObject();
        ms.put("speakerVoiceConfigs", lst);
        sc.put("multiSpeakerVoiceConfig", ms);
    } else {
        sc.put("voiceConfig", gmSuaraLama(v1));
    }
    gc.put("speechConfig", sc);
    root.put("generationConfig", gc);
    return root.toString();
}

// Satu permintaan ke satu model dengan satu kunci. galat[0] = kuota | kunci | model | lain | jaringan, galat[1] = pesan.
private static short[] gmCoba(String model, String kunci, GmCfg c, java.util.ArrayList<GmGiliran> turns, String[] galat) {
    try {
        String url, body;
        if (gmModelBaru(model)) {
            url = GM_BASE + "/interactions";
            body = gmBodyBaru(model, c, turns);
        } else {
            url = GM_BASE + "/models/" + model + ":generateContent";
            body = gmBodyLama(model, c, turns);
        }
        GmHasil r = null;
        for (int p = 0; p < 3; p++) {
            try {
                r = gmHttp("POST", url, kunci, body, 240000);
            } catch (IOException e) {
                r = null;
                galat[0] = "jaringan";
                galat[1] = e.getMessage() == null ? e.toString() : e.getMessage();
                try { Thread.sleep(1500); } catch (InterruptedException ie) { }
                continue;
            }
            if (r.kode >= 500) {
                galat[0] = "lain";
                galat[1] = "Server Google sedang sibuk (" + r.kode + ")";
                try { Thread.sleep(2000); } catch (InterruptedException ie) { }
                r = null;
                continue;
            }
            break;
        }
        if (r == null) return null;
        String pesan = gmPesanGalat(r.isi);
        if (r.kode == 429) { galat[0] = "kuota"; galat[1] = pesan; return null; }
        if (r.kode == 401 || r.kode == 403 || (r.kode == 400 && (r.isi.indexOf("API key") >= 0 || r.isi.indexOf("API_KEY") >= 0))) {
            galat[0] = "kunci"; galat[1] = pesan; return null;
        }
        boolean pakaiKustom = gmKustom(c.v1) || (c.dua && gmKustom(c.v2));
        if (pakaiKustom && (r.kode == 404 || (r.kode == 400 && r.isi.toLowerCase().indexOf("voice") >= 0))) {
            galat[0] = "suara"; galat[1] = pesan; return null;
        }
        if (r.kode == 404) { galat[0] = "model"; galat[1] = pesan; return null; }
        if (r.kode >= 400) { galat[0] = "lain"; galat[1] = pesan; return null; }
        String[] best = new String[2];
        gmCari(new org.json.JSONObject(r.isi), best);
        if (best[0] == null) { galat[0] = "lain"; galat[1] = "Google tidak mengirim suara (teks mungkin ditolak)"; return null; }
        byte[] raw = android.util.Base64.decode(best[0], android.util.Base64.DEFAULT);
        GmWav w = gmParse(raw, best[1]);
        return gmUbah(w.d, w.ch, w.sr, 1, GM_SR);
    } catch (Throwable t) {
        galat[0] = "lain";
        galat[1] = t.getMessage() == null ? t.toString() : t.getMessage();
        return null;
    }
}

private static String gmBuat(String json) throws Exception {
    org.json.JSONObject j = new org.json.JSONObject(json);
    java.util.ArrayList<String> kunci = new java.util.ArrayList<String>();
    org.json.JSONArray ak = j.optJSONArray("kunci");
    if (ak != null) for (int i = 0; i < ak.length(); i++) { String k = ak.optString(i, "").trim(); if (k.length() > 0) kunci.add(k); }
    java.util.ArrayList<String> model = new java.util.ArrayList<String>();
    org.json.JSONArray am = j.optJSONArray("model");
    if (am != null) for (int i = 0; i < am.length(); i++) { String m = am.optString(i, "").trim(); if (m.length() > 0) model.add(m); }
    if (kunci.isEmpty()) return "GAGAL: Belum ada kunci API Gemini. Isi dulu di pengaturan TTS Gemini.";
    if (model.isEmpty()) return "GAGAL: Belum ada model yang dipilih.";
    GmCfg c = new GmCfg();
    c.dua = j.optBoolean("dua", false);
    c.v1 = j.optString("suara1", "Kore");
    c.v2 = j.optString("suara2", "Puck");
    if (gmKustom(c.v1) || (c.dua && gmKustom(c.v2))) {
        java.util.ArrayList<String> baru = new java.util.ArrayList<String>();
        for (int i = 0; i < model.size(); i++) if (gmModelBaru(model.get(i))) baru.add(model.get(i));
        if (baru.isEmpty()) return "GAGAL: Suara buatan sendiri hanya bisa dipakai model Gemini 3.8 ke atas. Pilih model Gemini 3.8 Flash TTS atau Flash-Lite TTS.";
        model = baru;
    }
    c.st1 = j.optString("gaya1", "").trim();
    c.st2 = j.optString("gaya2", "").trim();
    // Dokumentasi resmi: satu permintaan dua pembicara hanya untuk suara bawaan. Kalau salah satu suara buatan sendiri
    // (voice_ / voicekey_), tiap giliran dibuat sendiri-sendiri sebagai satu pembicara lalu disambung.
    boolean pisah = c.dua && (gmKustom(c.v1) || gmKustom(c.v2));
    String out = j.optString("out", "");
    String cacheDir = j.optString("cache", "");
    boolean pakaiCache = j.optBoolean("pakaiCache", true);
    int maks = Math.max(300, j.optInt("maks", 1200));
    if (out.length() == 0) return "GAGAL: jalur hasil kosong";

    java.util.ArrayList<GmGiliran> semua = new java.util.ArrayList<GmGiliran>();
    org.json.JSONArray at = j.optJSONArray("giliran");
    if (at != null) {
        for (int i = 0; i < at.length(); i++) {
            org.json.JSONObject o = at.optJSONObject(i);
            if (o == null) continue;
            String t = o.optString("t", "").trim();
            if (t.length() == 0) continue;
            int s = (c.dua && o.optInt("s", 1) == 2) ? 2 : 1;
            java.util.ArrayList<String> ps = gmPecah(t, maks);
            for (int k = 0; k < ps.size(); k++) semua.add(new GmGiliran(s, ps.get(k)));
        }
    }
    if (semua.isEmpty()) return "GAGAL: Teksnya masih kosong.";

    java.util.ArrayList<java.util.ArrayList<GmGiliran>> bagian = new java.util.ArrayList<java.util.ArrayList<GmGiliran>>();
    java.util.ArrayList<GmGiliran> now = new java.util.ArrayList<GmGiliran>();
    int jml = 0;
    for (int i = 0; i < semua.size(); i++) {
        GmGiliran g = semua.get(i);
        if (!now.isEmpty() && (!c.dua || pisah || jml + g.t.length() > maks)) {
            bagian.add(now);
            now = new java.util.ArrayList<GmGiliran>();
            jml = 0;
        }
        now.add(g);
        jml += g.t.length();
    }
    if (!now.isEmpty()) bagian.add(now);

    File cd = null;
    if (cacheDir.length() > 0) { cd = new File(cacheDir); if (!cd.exists()) cd.mkdirs(); }
    gmProgJalur = j.optString("prog", "");
    gmPersen = 0;
    gmInfo = "Menyiapkan";
    gmLapor();
    java.util.HashSet<String> habis = new java.util.HashSet<String>();
    java.util.HashSet<Integer> kunciRusak = new java.util.HashSet<Integer>();
    java.util.HashSet<String> modelRusak = new java.util.HashSet<String>();
    java.util.LinkedHashSet<String> dipakai = new java.util.LinkedHashSet<String>();
    java.util.ArrayList<short[]> hasil = new java.util.ArrayList<short[]>();
    int dariCache = 0, kunciMaks = 0, adaKuota = 0;
    boolean suaraTak = false;
    String pesanLain = "";
    int total = bagian.size();
    for (int bi = 0; bi < total; bi++) {
        java.util.ArrayList<GmGiliran> turns = bagian.get(bi);
        GmCfg cp = c;
        if (pisah) {
            cp = new GmCfg();
            cp.dua = false;
            boolean dua2 = turns.get(0).s == 2;
            cp.v1 = dua2 ? c.v2 : c.v1;
            cp.st1 = dua2 ? c.st2 : c.st1;
        }
        gmInfo = "Bagian " + (bi + 1) + " dari " + total;
        gmPersen = (bi * 100 + 5) / total;
        gmLapor();
        StringBuilder kb = new StringBuilder();
        kb.append("v2|").append(cp.dua ? "2" : "1").append("|").append(cp.v1).append("|").append(cp.dua ? cp.v2 : "").append("|")
            .append(cp.st1).append("|").append(cp.dua ? cp.st2 : "").append("|");
        for (int i = 0; i < turns.size(); i++) kb.append(turns.get(i).s).append(":").append(turns.get(i).t).append("\n");
        File cf = cd == null ? null : new File(cd, "gm_" + gmSha(kb.toString()) + ".wav");
        short[] pcm = null;
        if (pakaiCache && cf != null && cf.exists() && cf.length() > 1000) {
            try { pcm = gmUbah(gmBacaWav(cf.getAbsolutePath()).d, 1, GM_SR, 1, GM_SR); dariCache++; } catch (Throwable t) { pcm = null; }
        }
        if (pcm == null) {
            int chTurn = 0;
            for (int zz = 0; zz < turns.size(); zz++) chTurn += turns.get(zz).t.length();
            gmMulaiTick((bi * 100) / total, 100 / total, chTurn, "Bagian " + (bi + 1) + " dari " + total);
            for (int mi = 0; mi < model.size() && pcm == null; mi++) {
                String m = model.get(mi);
                if (modelRusak.contains(m)) continue;
                for (int ki = 0; ki < kunci.size(); ki++) {
                    if (kunciRusak.contains(ki) || habis.contains(m + "|" + ki)) continue;
                    String[] g = new String[2];
                    short[] p = gmCoba(m, kunci.get(ki), cp, turns, g);
                    if (p != null) {
                        pcm = p;
                        dipakai.add(m);
                        if (ki > kunciMaks) kunciMaks = ki;
                        break;
                    }
                    if ("kuota".equals(g[0])) { habis.add(m + "|" + ki); adaKuota++; }
                    else if ("kunci".equals(g[0])) { kunciRusak.add(ki); pesanLain = g[1]; }
                    else if ("suara".equals(g[0])) { kunciRusak.add(ki); suaraTak = true; pesanLain = g[1]; }
                    else if ("model".equals(g[0])) { modelRusak.add(m); pesanLain = g[1]; break; }
                    else { pesanLain = g[1] == null ? "" : g[1]; break; }
                }
            }
            gmStopTick();
            if (pcm == null) {
                if (suaraTak && kunciRusak.size() >= kunci.size())
                    return "GAGAL: Suara buatan sendiri tidak ditemukan di kunci API yang dipakai. Suara hanya milik proyek Google tempat dia dibuat, dan suara tanpa simpan (voicekey) kedaluwarsa 7 hari. Buat ulang atau pakai kunci yang sama. " + pesanLain;
                if (kunciRusak.size() >= kunci.size())
                    return "GAGAL: Semua kunci API ditolak Google. Periksa kuncinya di pengaturan TTS Gemini. " + pesanLain;
                if (adaKuota > 0)
                    return "GAGAL: Jatah semua kunci dan model sudah habis. Jatah harian direset tengah malam waktu Pasifik (sekitar jam 3 sore WIB). Kamu bisa menambah kunci dari proyek Google lain. Bagian yang sudah jadi tersimpan, jadi tidak diulang saat dicoba lagi. " + pesanLain;
                return "GAGAL: Google menolak permintaan. " + pesanLain;
            }
            if (cf != null) { try { gmTulisWav(cf.getAbsolutePath(), pcm, GM_SR); } catch (Throwable t) { } }
        }
        hasil.add(pcm);
        gmPersen = ((bi + 1) * 100) / total;
        gmLapor();
    }
    int n = 0;
    for (int i = 0; i < hasil.size(); i++) n += hasil.get(i).length;
    short[] semuaPcm = new short[n];
    int pos = 0;
    for (int i = 0; i < hasil.size(); i++) { System.arraycopy(hasil.get(i), 0, semuaPcm, pos, hasil.get(i).length); pos += hasil.get(i).length; }
    gmTulisWav(out, semuaPcm, GM_SR);
    gmInfo = "Selesai";
    gmPersen = 100;
    gmLapor();
    StringBuilder dm = new StringBuilder();
    for (String m : dipakai) { if (dm.length() > 0) dm.append(","); dm.append(m); }
    return "SUKSES|" + dm + "|" + dariCache + "|" + total + "|" + (kunciMaks + 1);
}

private static boolean gmKustom(String v) {
    return v != null && (v.startsWith("voice_") || v.startsWith("voicekey_"));
}

private static java.util.ArrayList<String> gmKunciDari(org.json.JSONObject j) {
    java.util.ArrayList<String> kunci = new java.util.ArrayList<String>();
    org.json.JSONArray ak = j.optJSONArray("kunci");
    if (ak != null) for (int i = 0; i < ak.length(); i++) { String k = ak.optString(i, "").trim(); if (k.length() > 0) kunci.add(k); }
    return kunci;
}

private static byte[] gmBacaSemua(File f) throws IOException {
    byte[] b = new byte[(int) f.length()];
    FileInputStream fi = new FileInputStream(f);
    try {
        int got = 0;
        while (got < b.length) { int k = fi.read(b, got, b.length - got); if (k <= 0) break; got += k; }
    } finally { fi.close(); }
    return b;
}

// Mengubah berkas suara apa pun (mp3, m4a, wav, dan lain-lain) menjadi WAV 24 kHz mono 16-bit berkode base64.
// minDetik: rekaman yang lebih pendek ditolak sebelum dikirim, supaya tidak memakai jatah Google.
private static String gmWavBase64(String path, int batasDetik, int minDetik, String tmpDir) throws Exception {
    File d = new File(tmpDir);
    if (!d.exists()) d.mkdirs();
    long id = System.nanoTime();
    File raw = new File(d, "_gm_tmp_" + id + ".raw");
    File wav = new File(d, "_gm_tmp_" + id + ".wav");
    try {
        String r = decodeToPCM(path, raw.getAbsolutePath(), GM_SR, 1, batasDetik);
        if (r == null || !r.startsWith("SUKSES")) throw new IOException("Berkas suara tidak bisa dibaca. " + r);
        long n = raw.length() / 2;
        if (n < (long) GM_SR * minDetik) throw new IOException("Rekaman terlalu pendek. Minimal " + minDetik + " detik suara bicara.");
        byte[] bt = gmBacaSemua(raw);
        short[] pcm = new short[bt.length / 2];
        ByteBuffer.wrap(bt, 0, pcm.length * 2).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(pcm);
        gmTulisWav(wav.getAbsolutePath(), pcm, GM_SR);
        return android.util.Base64.encodeToString(gmBacaSemua(wav), android.util.Base64.NO_WRAP);
    } finally {
        raw.delete();
        wav.delete();
    }
}

// Mengirim permintaan pembuatan suara (POST /v1beta/voices), dicoba ke tiap kunci sampai ada yang berhasil.
private static org.json.JSONObject gmBuatSuara(java.util.ArrayList<String> kunci, String body, String[] galat) throws Exception {
    if (kunci.isEmpty()) { galat[0] = "Belum ada kunci API Gemini. Isi dulu di pengaturan TTS Gemini."; return null; }
    String pesan = "";
    for (int ki = 0; ki < kunci.size(); ki++) {
        GmHasil r;
        try {
            r = gmHttp("POST", GM_BASE + "/voices", kunci.get(ki), body, 240000);
        } catch (IOException e) {
            pesan = "Jaringan bermasalah: " + (e.getMessage() == null ? e.toString() : e.getMessage());
            continue;
        }
        if (r.kode == 200 || r.kode == 201) {
            org.json.JSONObject o = new org.json.JSONObject(r.isi);
            if (o.optString("id", "").length() == 0 && o.optString("key", "").length() == 0 && o.optJSONObject("voice") != null) o = o.optJSONObject("voice");
            return o;
        }
        pesan = gmPesanGalat(r.isi);
        if (r.kode == 429 || r.kode == 401 || r.kode == 403 || r.kode >= 500) continue;
        break;   // 400: rekaman ditolak, kunci lain tidak akan beda
    }
    galat[0] = pesan.length() == 0 ? "Google menolak permintaan" : pesan;
    return null;
}

private static void gmTulisContoh(org.json.JSONObject o, String out) {
    if (out == null || out.length() == 0) return;
    org.json.JSONObject sa = o.optJSONObject("sample_audio");
    if (sa == null) sa = o.optJSONObject("sampleAudio");
    if (sa == null) return;
    String dt = sa.optString("data", "");
    if (dt.length() < 100) return;
    try {
        byte[] raw = android.util.Base64.decode(dt, android.util.Base64.DEFAULT);
        FileOutputStream fo = new FileOutputStream(out);
        try { fo.write(raw); } finally { fo.close(); }
    } catch (Throwable t) { }
}

private static String gmDesain(String json) throws Exception {
    org.json.JSONObject j = new org.json.JSONObject(json);
    java.util.ArrayList<String> kunci = gmKunciDari(j);
    String model = j.optString("model", "gemini-3.8-flash-tts").trim();
    if (!gmModelBaru(model)) model = "gemini-3.8-flash-tts";
    String nama = j.optString("nama", "").trim();
    String deskripsi = j.optString("deskripsi", "").trim();
    String gender = j.optString("gender", "").trim();
    String bahasa = j.optString("bahasa", "").trim();
    String out = j.optString("out", "");
    if (deskripsi.length() < 10) return "GAGAL: Deskripsi suaranya terlalu pendek. Ceritakan umur, nada, dan aksennya dalam satu atau dua kalimat.";
    if (nama.length() == 0) nama = "Suara rancangan";
    org.json.JSONObject v = new org.json.JSONObject();
    v.put("model", model);
    v.put("type", "prompted");
    v.put("display_name", nama);
    if (gender.length() > 0) v.put("gender", gender);
    if (bahasa.length() > 0) v.put("language_code", bahasa);
    org.json.JSONObject pr = new org.json.JSONObject();
    pr.put("input", deskripsi);
    v.put("prompted", pr);
    org.json.JSONObject root = new org.json.JSONObject();
    root.put("store", true);
    root.put("voice", v);
    gmProgJalur = j.optString("prog", "");
    gmPersen = 10; gmInfo = "Merancang suara"; gmLapor();
    String[] galat = new String[1];
    org.json.JSONObject o;
    gmMulaiTick(10, 85, 600, "Merancang suara");
    try { o = gmBuatSuara(kunci, root.toString(), galat); } finally { gmStopTick(); }
    if (o == null) return "GAGAL: " + galat[0];
    String id = o.optString("id", "");
    if (id.length() == 0) return "GAGAL: Google tidak mengirim nomor suara";
    gmTulisContoh(o, out);
    gmPersen = 100; gmInfo = "Selesai"; gmLapor();
    return "SUKSES|" + gmBersih(id).replace("|", " ") + "|" + gmBersih(o.optString("display_name", nama)).replace("|", " ");
}

// Voice replication. Google memeriksa sendiri bahwa suara contoh dan suara persetujuan berasal dari orang yang sama.
private static String gmReplika(String json) throws Exception {
    org.json.JSONObject j = new org.json.JSONObject(json);
    java.util.ArrayList<String> kunci = gmKunciDari(j);
    String model = j.optString("model", "gemini-3.8-flash-tts").trim();
    if (!gmModelBaru(model)) model = "gemini-3.8-flash-tts";
    String nama = j.optString("nama", "").trim();
    String sumber = j.optString("sumber", "");
    String setuju = j.optString("persetujuan", "");
    String tmp = j.optString("tmp", "");
    boolean simpan = j.optBoolean("simpan", true);
    if (sumber.length() == 0 || !new File(sumber).exists()) return "GAGAL: Rekaman contoh suara belum dipilih.";
    if (setuju.length() == 0 || !new File(setuju).exists()) return "GAGAL: Rekaman persetujuan belum dipilih.";
    if (tmp.length() == 0) return "GAGAL: folder sementara kosong";
    if (nama.length() == 0) nama = "Suara tiruan";
    gmProgJalur = j.optString("prog", "");
    gmPersen = 5; gmInfo = "Menyiapkan rekaman contoh"; gmLapor();
    String src = gmWavBase64(sumber, 30, 10, tmp);       // 10 sampai 30 detik
    gmPersen = 25; gmInfo = "Menyiapkan rekaman persetujuan"; gmLapor();
    String con = gmWavBase64(setuju, 20, 2, tmp);
    org.json.JSONObject sa = new org.json.JSONObject();
    sa.put("mime_type", "audio/wav");
    sa.put("data", src);
    org.json.JSONObject ca = new org.json.JSONObject();
    ca.put("mime_type", "audio/wav");
    ca.put("data", con);
    org.json.JSONObject rp = new org.json.JSONObject();
    rp.put("source_audio", sa);
    rp.put("consent_audio", ca);
    org.json.JSONObject v = new org.json.JSONObject();
    v.put("model", model);
    v.put("type", "replicated");
    if (simpan) v.put("display_name", nama);
    v.put("replicated", rp);
    org.json.JSONObject root = new org.json.JSONObject();
    root.put("store", simpan);
    root.put("voice", v);
    gmPersen = 45; gmInfo = "Mengirim ke Google dan memeriksa suara"; gmLapor();
    String[] galat = new String[1];
    org.json.JSONObject o;
    gmMulaiTick(45, 50, 400, "Memeriksa suara di Google");
    try { o = gmBuatSuara(kunci, root.toString(), galat); } finally { gmStopTick(); }
    if (o == null) return "GAGAL: " + galat[0];
    String id = o.optString("id", "");
    String key = o.optString("key", "");
    gmPersen = 100; gmInfo = "Selesai"; gmLapor();
    String nm = gmBersih(nama).replace("|", " ");
    if (simpan && id.length() > 0) return "SUKSES|" + gmBersih(id).replace("|", " ") + "|" + nm + "|id";
    if (key.length() > 0) return "SUKSES|" + gmBersih(key).replace("|", " ") + "|" + nm + "|kunci";
    if (id.length() > 0) return "SUKSES|" + gmBersih(id).replace("|", " ") + "|" + nm + "|id";
    return "GAGAL: Google tidak mengirim nomor suara";
}

private static String gmSuaraSaya(String kuncis) throws Exception {
    String[] ks = kuncis.split("\n");
    java.util.LinkedHashMap<String, String> baris = new java.util.LinkedHashMap<String, String>();
    String pesan = "";
    boolean adaOk = false;
    for (int i = 0; i < ks.length; i++) {
        String k = ks[i].trim();
        if (k.length() == 0) continue;
        String token = "";
        for (int hal = 0; hal < 6; hal++) {
            String url = GM_BASE + "/voices?page_size=1000&type=prompted&type=replicated";
            if (token.length() > 0) url += "&page_token=" + java.net.URLEncoder.encode(token, "UTF-8");
            GmHasil r;
            try { r = gmHttp("GET", url, k, null, 30000); } catch (IOException e) { pesan = e.getMessage() == null ? e.toString() : e.getMessage(); break; }
            if (r.kode != 200) { pesan = gmPesanGalat(r.isi); break; }
            adaOk = true;
            org.json.JSONObject o = new org.json.JSONObject(r.isi);
            org.json.JSONArray vs = o.optJSONArray("voices");
            if (vs != null) {
                for (int q = 0; q < vs.length(); q++) {
                    org.json.JSONObject v = vs.optJSONObject(q);
                    if (v == null) continue;
                    String id = v.optString("id", "");
                    if (!id.startsWith("voice_") || baris.containsKey(id)) continue;
                    String tp = v.optString("type", "");
                    if (!"prompted".equals(tp) && !"replicated".equals(tp)) continue;
                    baris.put(id, gmBersih(id) + "\t" + gmBersih(v.optString("display_name", id)) + "\t" + gmBersih(v.optString("language_code", v.optString("languageCode", ""))) + "\t" + ("prompted".equals(tp) ? "rancangan" : "tiruan") + "\t" + gmBersih(v.optString("model", "")));
                }
            }
            token = o.optString("next_page_token", o.optString("nextPageToken", ""));
            if (token.length() == 0) break;
        }
    }
    if (!adaOk) return "GAGAL: Daftar suara saya tidak bisa diambil. " + pesan;
    StringBuilder sb = new StringBuilder("SUKSES");
    for (String l : baris.values()) sb.append("\n").append(l);
    return sb.toString();
}

// Mengambil contoh suara (sample_audio) dari suara rancangan yang sudah tersimpan. Daftar suara sengaja tanpa contoh, jadi diambil lewat GET satu suara.
private static String gmSuaraContoh(String kuncis, String id, String out) throws Exception {
    if (id == null || !id.startsWith("voice_")) return "GAGAL: nomor suara tidak sah";
    if (out == null || out.length() == 0) return "GAGAL: jalur hasil kosong";
    String[] ks = kuncis.split("\n");
    String pesan = "";
    for (int i = 0; i < ks.length; i++) {
        String k = ks[i].trim();
        if (k.length() == 0) continue;
        try {
            GmHasil r = gmHttp("GET", GM_BASE + "/voices/" + java.net.URLEncoder.encode(id, "UTF-8"), k, null, 60000);
            if (r.kode == 200) {
                File f = new File(out);
                if (f.exists()) f.delete();
                gmTulisContoh(new org.json.JSONObject(r.isi), out);
                if (f.exists() && f.length() > 100) return "SUKSES";
                return "GAGAL: Suara ini tidak punya contoh suara. Contoh hanya ada untuk suara rancangan.";
            }
            pesan = gmPesanGalat(r.isi);
        } catch (IOException e) {
            pesan = e.getMessage() == null ? e.toString() : e.getMessage();
        }
    }
    return "GAGAL: Contoh suara tidak bisa diambil. " + pesan;
}

private static String gmSuaraHapus(String kuncis, String id) throws Exception {
    if (id == null || !id.startsWith("voice_")) return "GAGAL: nomor suara tidak sah";
    String[] ks = kuncis.split("\n");
    String pesan = "";
    for (int i = 0; i < ks.length; i++) {
        String k = ks[i].trim();
        if (k.length() == 0) continue;
        try {
            GmHasil r = gmHttp("DELETE", GM_BASE + "/voices/" + java.net.URLEncoder.encode(id, "UTF-8"), k, null, 30000);
            if (r.kode >= 200 && r.kode < 300) return "SUKSES";
            pesan = gmPesanGalat(r.isi);
        } catch (IOException e) {
            pesan = e.getMessage() == null ? e.toString() : e.getMessage();
        }
    }
    return "GAGAL: Suara tidak bisa dihapus dari Google. " + pesan;
}

private static int gmVersiModel(String m) {
    java.util.regex.Matcher x = java.util.regex.Pattern.compile("gemini-(\\d+)(?:\\.(\\d+))?").matcher(m);
    if (!x.find()) return 0;
    int maj = Integer.parseInt(x.group(1));
    int min = x.group(2) == null ? 0 : Integer.parseInt(x.group(2));
    return maj * 100 + min;
}

// Hanya Flash dan Flash-Lite yang bisa menerima audio dan menjawab teks. TTS, image, live, audio-native, embedding, Pro dibuang.
private static boolean gmModelTeksOk(String nm, org.json.JSONArray metode) {
    String l = nm.toLowerCase();
    if (!l.startsWith("gemini-") || l.indexOf("flash") < 0) return false;
    String[] buang = {"tts", "image", "live", "audio", "embed", "imagen", "veo", "robot", "computer", "native", "dialog", "learnlm"};
    for (int i = 0; i < buang.length; i++) if (l.indexOf(buang[i]) >= 0) return false;
    if (metode != null && metode.length() > 0) {
        boolean bisa = false;
        for (int w = 0; w < metode.length(); w++) if ("generateContent".equals(metode.optString(w, ""))) { bisa = true; break; }
        if (!bisa) return false;
    }
    return true;
}

private static String gmDaftarModelTeks(String kuncis) throws Exception {
    String[] ks = kuncis.split("\n");
    String pesan = "";
    for (int i = 0; i < ks.length; i++) {
        String k = ks[i].trim();
        if (k.length() == 0) continue;
        java.util.LinkedHashSet<String> ids = new java.util.LinkedHashSet<String>();
        String token = "";
        boolean ok = true;
        for (int hal = 0; hal < 6; hal++) {
            String url = GM_BASE + "/models?pageSize=1000" + (token.length() > 0 ? "&pageToken=" + java.net.URLEncoder.encode(token, "UTF-8") : "");
            GmHasil r = gmHttp("GET", url, k, null, 30000);
            if (r.kode != 200) { ok = false; pesan = gmPesanGalat(r.isi); break; }
            org.json.JSONObject o = new org.json.JSONObject(r.isi);
            org.json.JSONArray ms = o.optJSONArray("models");
            if (ms != null) {
                for (int q = 0; q < ms.length(); q++) {
                    org.json.JSONObject mo = ms.optJSONObject(q);
                    if (mo == null) continue;
                    String nm = mo.optString("name", "");
                    if (nm.startsWith("models/")) nm = nm.substring(7);
                    if (gmModelTeksOk(nm, mo.optJSONArray("supportedGenerationMethods"))) ids.add(nm);
                }
            }
            token = o.optString("nextPageToken", "");
            if (token.length() == 0) break;
        }
        if (ok) {
            if (ids.isEmpty()) { pesan = "Tidak ada model Flash atau Flash-Lite yang tersedia untuk kunci API ini."; continue; }
            java.util.ArrayList<String> urut = new java.util.ArrayList<String>(ids);
            java.util.Collections.sort(urut, new java.util.Comparator<String>() {
                public int compare(String a, String b) {
                    int va = gmVersiModel(a), vb = gmVersiModel(b);
                    if (va != vb) return vb - va;
                    boolean la = a.toLowerCase().indexOf("lite") >= 0, lb = b.toLowerCase().indexOf("lite") >= 0;
                    if (la != lb) return la ? 1 : -1;
                    return a.compareTo(b);
                }
            });
            StringBuilder sb = new StringBuilder("SUKSES");
            for (int u = 0; u < urut.size(); u++) sb.append("\n").append(urut.get(u));
            return sb.toString();
        }
    }
    return "GAGAL: Daftar model tidak bisa diambil. " + pesan;
}

private static String gmDaftarModel(String kuncis) throws Exception {
    String[] ks = kuncis.split("\n");
    String pesan = "";
    for (int i = 0; i < ks.length; i++) {
        String k = ks[i].trim();
        if (k.length() == 0) continue;
        java.util.LinkedHashSet<String> ids = new java.util.LinkedHashSet<String>();
        String token = "";
        boolean ok = true;
        for (int hal = 0; hal < 6; hal++) {
            String url = GM_BASE + "/models?pageSize=1000" + (token.length() > 0 ? "&pageToken=" + java.net.URLEncoder.encode(token, "UTF-8") : "");
            GmHasil r = gmHttp("GET", url, k, null, 30000);
            if (r.kode != 200) { ok = false; pesan = gmPesanGalat(r.isi); break; }
            org.json.JSONObject o = new org.json.JSONObject(r.isi);
            org.json.JSONArray ms = o.optJSONArray("models");
            if (ms != null) {
                for (int q = 0; q < ms.length(); q++) {
                    org.json.JSONObject mo = ms.optJSONObject(q);
                    if (mo == null) continue;
                    String nm = mo.optString("name", "");
                    if (nm.startsWith("models/")) nm = nm.substring(7);
                    if (nm.toLowerCase().indexOf("tts") < 0) continue;
                    // Hanya model yang memang bisa menghasilkan suara. Model Gemini 3.8 ke atas dipanggil lewat Interactions,
                    // jadi tidak dicoret hanya karena daftar metodenya tidak memuat generateContent.
                    org.json.JSONArray gmm = mo.optJSONArray("supportedGenerationMethods");
                    boolean bisa = gmm == null || gmm.length() == 0 || gmModelBaru(nm);
                    if (!bisa) {
                        for (int w = 0; w < gmm.length(); w++) {
                            String mt = gmm.optString(w, "");
                            if ("generateContent".equals(mt) || "streamGenerateContent".equals(mt)) { bisa = true; break; }
                        }
                    }
                    if (bisa) ids.add(nm);
                }
            }
            token = o.optString("nextPageToken", "");
            if (token.length() == 0) break;
        }
        if (ok) {
            if (ids.isEmpty()) { pesan = "Tidak ada model TTS yang tersedia untuk kunci API ini."; continue; }
            java.util.ArrayList<String> urut = new java.util.ArrayList<String>(ids);
            java.util.Collections.sort(urut);
            StringBuilder sb = new StringBuilder("SUKSES");
            for (int u = 0; u < urut.size(); u++) sb.append("\n").append(urut.get(u));
            return sb.toString();
        }
    }
    return "GAGAL: Daftar model tidak bisa diambil. " + pesan;
}

private static String gmBersih(String s) {
    return s == null ? "" : s.replace('\t', ' ').replace('\n', ' ').trim();
}

private static String gmDaftarSuara(String kuncis, String cari, String bahasa, String ekstra) throws Exception {
    String[] ks = kuncis.split("\n");
    String pesan = "";
    for (int i = 0; i < ks.length; i++) {
        String k = ks[i].trim();
        if (k.length() == 0) continue;
        StringBuilder sb = new StringBuilder("SUKSES");
        String token = "";
        boolean ok = true;
        int jumlah = 0;
        for (int hal = 0; hal < 400; hal++) {
            String url = GM_BASE + "/voices?page_size=1000";
            if (cari != null && cari.trim().length() > 0) url += "&search=" + java.net.URLEncoder.encode(cari.trim(), "UTF-8");
            if (bahasa != null && bahasa.trim().length() > 0) url += "&language_code=" + java.net.URLEncoder.encode(bahasa.trim(), "UTF-8");
            // Filter resmi ListVoices: gender, pitch, type, accent, region_code, persona, context (bentuk: kunci=nilai&kunci=nilai).
            if (ekstra != null && ekstra.trim().length() > 0) {
                String[] ps = ekstra.split("&");
                for (int e = 0; e < ps.length; e++) {
                    int eq = ps[e].indexOf('=');
                    if (eq <= 0) continue;
                    String kk = ps[e].substring(0, eq).trim();
                    String vv = ps[e].substring(eq + 1).trim();
                    if (vv.length() == 0) continue;
                    if (kk.equals("gender") || kk.equals("pitch") || kk.equals("type") || kk.equals("accent")
                        || kk.equals("region_code") || kk.equals("persona") || kk.equals("context"))
                        url += "&" + kk + "=" + java.net.URLEncoder.encode(vv, "UTF-8");
                }
            }
            if (token.length() > 0) url += "&page_token=" + java.net.URLEncoder.encode(token, "UTF-8");
            GmHasil r = gmHttp("GET", url, k, null, 30000);
            if (r.kode != 200) { ok = false; pesan = gmPesanGalat(r.isi); break; }
            org.json.JSONObject o = new org.json.JSONObject(r.isi);
            org.json.JSONArray vs = o.optJSONArray("voices");
            if (vs != null) {
                for (int q = 0; q < vs.length(); q++) {
                    org.json.JSONObject v = vs.optJSONObject(q);
                    if (v == null) continue;
                    String id = v.optString("id", v.optString("name", ""));
                    if (id.length() == 0) continue;
                    String nm = v.optString("display_name", v.optString("displayName", id));
                    String bh = v.optString("language_code", v.optString("languageCode", ""));
                    String gd = v.optString("gender", "");
                    String ds = v.optString("description", "");
                    sb.append("\n").append(gmBersih(id)).append("\t").append(gmBersih(nm)).append("\t").append(gmBersih(bh))
                        .append("\t").append(gmBersih(gd)).append("\t").append(gmBersih(ds))
                        .append("\t").append(gmBersih(v.optString("type", ""))).append("\t").append(gmBersih(v.optString("accent", "")))
                        .append("\t").append(gmBersih(v.optString("pitch", ""))).append("\t").append(gmBersih(v.optString("persona", "")))
                        .append("\t").append(gmBersih(v.optString("context", ""))).append("\t").append(gmBersih(v.optString("region_code", v.optString("regionCode", ""))));
                    jumlah++;
                }
            }
            token = o.optString("next_page_token", o.optString("nextPageToken", ""));
            if (token.length() == 0) break;
        }
        if (ok) return sb.toString();
    }
    return "GAGAL: Daftar suara tidak bisa diambil. " + pesan;
}

// Menyambung potongan (rekaman mentah dan hasil Gemini) ke satu berkas pada sample rate dan channel tujuan.
private static String gmSambung(String json) throws Exception {
    org.json.JSONObject j = new org.json.JSONObject(json);
    String out = j.optString("out", "");
    String fmt = j.optString("fmt", "raw");
    int sr = j.optInt("sr", 44100);
    int ch = Math.max(1, j.optInt("ch", 1));
    org.json.JSONArray parts = j.optJSONArray("bagian");
    if (out.length() == 0 || parts == null) return "GAGAL: data penyambungan tidak lengkap";
    boolean wav = "wav".equals(fmt);
    File tmp = new File(out + ".tmp");
    long bytes = 0;
    long awalMs = 0;
    boolean sudahRaw = false;
    OutputStream os = new BufferedOutputStream(new FileOutputStream(tmp), 1 << 16);
    try {
        if (wav) os.write(new byte[44]);
        for (int i = 0; i < parts.length(); i++) {
            org.json.JSONObject p = parts.optJSONObject(i);
            if (p == null) continue;
            String path = p.optString("p", "");
            if ("raw".equals(p.optString("t", ""))) {
                File f = new File(path);
                if (!f.exists()) continue;
                InputStream in = new FileInputStream(f);
                try {
                    byte[] buf = new byte[1 << 16];
                    int n;
                    while ((n = in.read(buf)) > 0) { os.write(buf, 0, n); bytes += n; }
                } finally {
                    in.close();
                }
                sudahRaw = true;
            } else {
                GmWav w = gmBacaWav(path);
                short[] s = gmUbah(w.d, w.ch, w.sr, ch, sr);
                byte[] buf = new byte[s.length * 2];
                for (int q = 0; q < s.length; q++) { buf[q * 2] = (byte) (s[q] & 0xFF); buf[q * 2 + 1] = (byte) ((s[q] >> 8) & 0xFF); }
                os.write(buf);
                bytes += buf.length;
                if (!sudahRaw) awalMs += (long) (s.length / ch) * 1000L / sr;
            }
        }
    } finally {
        os.close();
    }
    if (wav) {
        RandomAccessFile raf = new RandomAccessFile(tmp, "rw");
        try {
            ByteBuffer h = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
            h.put("RIFF".getBytes()).putInt((int) (36 + bytes)).put("WAVE".getBytes()).put("fmt ".getBytes()).putInt(16)
                .putShort((short) 1).putShort((short) ch).putInt(sr).putInt(sr * ch * 2).putShort((short) (ch * 2)).putShort((short) 16)
                .put("data".getBytes()).putInt((int) bytes);
            raf.seek(0);
            raf.write(h.array());
        } finally {
            raf.close();
        }
    }
    File dst = new File(out);
    if (dst.exists()) dst.delete();
    if (!tmp.renameTo(dst)) return "GAGAL: tidak bisa menyimpan hasil sambungan";
    return "SUKSES|" + awalMs;
}

private static String gmCacheInfo(String dir) {
    File d = new File(dir);
    File[] fs = d.listFiles();
    long b = 0;
    int n = 0;
    if (fs != null) {
        for (int i = 0; i < fs.length; i++) {
            if (fs[i].getName().startsWith("gm_") && fs[i].getName().endsWith(".wav")) { n++; b += fs[i].length(); }
        }
    }
    return "SUKSES|" + n + "|" + b;
}

private static String gmCacheHapus(String dir) {
    File d = new File(dir);
    File[] fs = d.listFiles();
    int n = 0;
    if (fs != null) {
        for (int i = 0; i < fs.length; i++) {
            if (fs[i].getName().startsWith("gm_") && fs[i].getName().endsWith(".wav") && fs[i].delete()) n++;
        }
    }
    return "SUKSES|" + n;
}


public static String rapikanPerintah(String cmd, String a, String b, String c, String d) {
    try {
        if ("siapkan".equals(cmd)) return rapikanSiapkan(a, b);
        if ("pratinjau".equals(cmd)) return rapikanPratinjau(a, b, c);
        if ("render".equals(cmd)) return rapikanRender(a, b, c, "1".equals(d));
        if (cmd != null && cmd.startsWith("gm_")) return gmDispatch(cmd, a, b, c, d);
        if (cmd != null && cmd.startsWith("live_")) return liveDispatch(cmd, a, b, c, d);
        if (cmd != null && cmd.startsWith("mt_")) return mtDispatch(cmd, a, b, c, d);
        if (cmd != null && cmd.startsWith("pt_")) return ptDispatch(cmd, a, b, c, d);
        return "GAGAL: perintah tidak dikenal";
    } catch (Throwable t) {
        return "GAGAL: " + (t.getMessage() == null ? t.toString() : t.getMessage());
    }
}

private static float rpMedian(java.util.ArrayList<Float> v) {
    if (v.isEmpty()) return 0f;
    float[] t = new float[v.size()];
    for (int i = 0; i < t.length; i++) t[i] = v.get(i).floatValue();
    java.util.Arrays.sort(t);
    return t[t.length / 2];
}

// Pelacak nada YIN pada satu bingkai (sinyal sudah diperkecil lajunya). Mengembalikan Hz, atau -1.
private static float rpYin(float[] x, int pos, int w, int tauMin, int tauMax, float sr, float[] cm) {
    float run = 0f;
    cm[0] = 1f;
    for (int tau = 1; tau <= tauMax; tau++) {
        float dsum = 0f;
        for (int j = 0; j < w; j++) {
            float df = x[pos + j] - x[pos + j + tau];
            dsum += df * df;
        }
        run += dsum;
        cm[tau] = run > 0f ? dsum * tau / run : 1f;
    }
    int best = -1;
    for (int tau = tauMin; tau <= tauMax; tau++) {
        if (cm[tau] < 0.15f) {
            while (tau + 1 <= tauMax && cm[tau + 1] < cm[tau]) tau++;
            best = tau;
            break;
        }
    }
    if (best < 0) {
        float mn = 1e9f;
        for (int tau = tauMin; tau <= tauMax; tau++) if (cm[tau] < mn) { mn = cm[tau]; best = tau; }
        if (best < 0 || mn > 0.25f) return -1f;
    }
    float tf = best;
    if (best > 1 && best < tauMax) {
        float s0 = cm[best - 1], s1 = cm[best], s2 = cm[best + 1];
        float den = s0 - 2f * s1 + s2;
        if (Math.abs(den) > 1e-9f) tf = best + (s0 - s2) / (2f * den);
    }
    if (tf <= 0f) return -1f;
    return sr / tf;
}

private static void rpTambahSeg(java.util.ArrayList<int[]> seg, java.util.ArrayList<Float> midi, int tipe, int s, int e, float m) {
    if (e <= s) return;
    seg.add(new int[]{tipe, s, e});
    midi.add(Float.valueOf(m));
}

private static String rapikanSiapkan(String audio, String kerja) throws Exception {
    if (audio != null && !audio.startsWith("/")) audio = "/" + audio;
    File dir = new File(kerja);
    dir.mkdirs();
    File raw = new File(dir, "vokal.raw");
    if (raw.exists()) raw.delete();
    String r = decodeToPCM(audio, raw.getAbsolutePath(), RP_SR, 1, 0);
    if (!"SUKSES".equals(r)) return "GAGAL: " + r;
    long nBytes = raw.length();
    if (nBytes < (long) RP_SR * 2L) return "GAGAL: audio terlalu pendek (kurang dari 1 detik)";
    if (nBytes > (long) RP_SR * 2L * 900L) return "GAGAL: audio lebih panjang dari 15 menit";
    int n = (int) (nBytes / 2L);
    short[] x = new short[n];
    FileInputStream fi = new FileInputStream(raw);
    byte[] buf = new byte[65536];
    int pos = 0;
    int carry = -1;
    while (pos < n) {
        int rd = fi.read(buf, 0, buf.length);
        if (rd <= 0) break;
        int i = 0;
        if (carry >= 0 && rd > 0) { x[pos++] = (short) (carry | (buf[0] << 8)); carry = -1; i = 1; }
        for (; i + 1 < rd && pos < n; i += 2) x[pos++] = (short) ((buf[i] & 0xFF) | (buf[i + 1] << 8));
        if (i < rd && pos < n) carry = buf[i] & 0xFF;
    }
    fi.close();

    StringBuilder sb = new StringBuilder();
    int jumlahNada = rpPecahNada(x, n, sb);
    FileOutputStream fo = new FileOutputStream(new File(dir, "nada.txt"));
    fo.write(sb.toString().getBytes("UTF-8"));
    fo.close();
    long durMs = (long) n * 1000L / RP_SR;
    return "SUKSES:" + jumlahNada + ":" + durMs;
}

// Memecah vokal menjadi nada. Hasil (tipe;awalMs;akhirMs;midi;sen) ditulis ke sb, mengembalikan jumlah nada.
// Batas nada dicari kasar per 20 md, lalu dihaluskan sampai ketelitian milidetik (rpRapikanBatas).
private static int rpPecahNada(short[] x, int n, StringBuilder sb) {
    // Pengecilan laju (rata-rata RP_DS cuplikan)
    int nd = n / RP_DS;
    float[] xd = new float[nd];
    for (int i = 0; i < nd; i++) {
        int s = 0;
        for (int k = 0; k < RP_DS; k++) s += x[i * RP_DS + k];
        xd[i] = s / (float) (RP_DS * 32768);
    }
    final float srd = (float) RP_SR / RP_DS;
    final int W = 384;
    final int tauMin = Math.max(2, (int) (srd / 900f));
    final int tauMax = (int) (srd / 75f);
    final int span = W + tauMax + 1;
    float[] cm = new float[tauMax + 2];

    int nF = n / RP_HOP;
    float[] rms = new float[nF];
    for (int f = 0; f < nF; f++) {
        double s = 0.0;
        int a0 = f * RP_HOP;
        for (int i = 0; i < RP_HOP; i++) { double v = x[a0 + i] / 32768.0; s += v * v; }
        rms[f] = (float) Math.sqrt(s / RP_HOP);
    }
    float[] urut = rms.clone();
    java.util.Arrays.sort(urut);
    float lantai = urut[Math.max(0, Math.min(nF - 1, nF / 10))];
    float ambang = Math.max(0.005f, lantai * 3f);

    float[] midi = new float[nF];
    boolean[] suara = new boolean[nF];
    for (int f = 0; f < nF; f++) {
        if (rms[f] < ambang) continue;
        int tengahDs = (f * RP_HOP + RP_HOP / 2) / RP_DS;
        int p0 = tengahDs - span / 2;
        if (p0 < 0 || p0 + span + 1 >= nd) continue;
        float f0 = rpYin(xd, p0, W, tauMin, tauMax, srd, cm);
        if (f0 < 75f || f0 > 900f) continue;
        midi[f] = (float) (69.0 + 12.0 * Math.log(f0 / 440.0) / Math.log(2.0));
        suara[f] = true;
    }
    // Isi celah pendek (1-2 bingkai) di antara bingkai bersuara
    for (int f = 1; f < nF - 1; f++) {
        if (suara[f]) continue;
        int j = f;
        while (j < nF && !suara[j]) j++;
        if (j < nF && (j - f) <= 2 && suara[f - 1]) {
            for (int k = f; k < j; k++) { midi[k] = midi[f - 1]; suara[k] = true; }
        }
        f = j;
    }
    // Penghalus median 5 bingkai pada nilai nada
    float[] halus = midi.clone();
    for (int f = 0; f < nF; f++) {
        if (!suara[f]) continue;
        java.util.ArrayList<Float> w = new java.util.ArrayList<Float>();
        for (int k = f - 2; k <= f + 2; k++) if (k >= 0 && k < nF && suara[k]) w.add(Float.valueOf(midi[k]));
        halus[f] = rpMedian(w);
    }
    midi = halus;

    // Pemecahan menjadi nada
    java.util.ArrayList<int[]> seg = new java.util.ArrayList<int[]>();
    java.util.ArrayList<Float> segMidi = new java.util.ArrayList<Float>();
    int f = 0;
    while (f < nF) {
        if (!suara[f]) {
            int j = f;
            while (j < nF && !suara[j]) j++;
            rpTambahSeg(seg, segMidi, 0, f, j, 0f);
            f = j;
        } else {
            int j = f;
            while (j < nF && suara[j]) j++;
            int awal = f;
            java.util.ArrayList<Float> cur = new java.util.ArrayList<Float>();
            int pend = 0;
            for (int g = f; g < j; g++) {
                float m = midi[g];
                boolean beda = cur.size() >= 3 && Math.abs(m - rpMedian(cur)) > 0.8f;
                if (beda) {
                    pend++;
                    if (pend >= 3) {
                        int potong = g - pend + 1;
                        rpTambahSeg(seg, segMidi, 1, awal, potong, rpMedian(cur));
                        awal = potong;
                        cur.clear();
                        for (int k = potong; k <= g; k++) cur.add(Float.valueOf(midi[k]));
                        pend = 0;
                    }
                } else {
                    if (pend > 0) { for (int k = g - pend; k < g; k++) cur.add(Float.valueOf(midi[k])); pend = 0; }
                    cur.add(Float.valueOf(m));
                }
            }
            if (pend > 0) { for (int k = j - pend; k < j; k++) cur.add(Float.valueOf(midi[k])); }
            rpTambahSeg(seg, segMidi, 1, awal, j, rpMedian(cur));
            f = j;
        }
    }
    // Gabungkan nada yang terlalu pendek (kurang dari 4 bingkai = 80 md) ke tetangganya
    for (int i = 0; i < seg.size(); i++) {
        int[] s = seg.get(i);
        if (s[0] != 1 || (s[2] - s[1]) >= 4) continue;
        if (i > 0 && seg.get(i - 1)[0] == 1 && seg.get(i - 1)[2] == s[1]) {
            seg.get(i - 1)[2] = s[2];
            seg.remove(i); segMidi.remove(i);
            i--;
        } else if (i + 1 < seg.size() && seg.get(i + 1)[0] == 1 && seg.get(i + 1)[1] == s[2]) {
            seg.get(i + 1)[1] = s[1];
            seg.remove(i); segMidi.remove(i);
            i--;
        }
    }

    // Ubah ke milidetik, lalu haluskan batas-batasnya
    java.util.ArrayList<int[]> segMs = new java.util.ArrayList<int[]>();
    for (int i = 0; i < seg.size(); i++) {
        int[] s = seg.get(i);
        segMs.add(new int[]{s[0], s[1] * 20, s[2] * 20});
    }
    // segmen terakhir dipanjangkan sampai ujung audio, supaya seluruh durasi asli tercakup
    if (!segMs.isEmpty()) {
        int durMs = (int) ((long) n * 1000L / RP_SR);
        int[] last = segMs.get(segMs.size() - 1);
        if (durMs > last[2]) last[2] = durMs;
    }
    rpRapikanBatas(segMs, segMidi, x, xd, srd, ambang);

    int jumlahNada = 0;
    for (int i = 0; i < segMs.size(); i++) {
        int[] s = segMs.get(i);
        if (s[0] == 1) jumlahNada++;
        sb.append(s[0]).append(';').append(s[1]).append(';').append(s[2]).append(';')
          .append(String.format(java.util.Locale.US, "%.2f", segMidi.get(i).floatValue())).append(";0\n");
    }
    return jumlahNada;
}


// ---------------------------------------------------------------------------
// Penghalusan batas nada sampai ketelitian milidetik.
//  - awal nada : titik pertama tempat sinyal sudah cukup keras DAN periodik (menghadap ke depan)
//  - akhir nada: titik terakhir tempat sinyal masih cukup keras DAN periodik (menghadap ke belakang)
//  - pergantian nada: titik yang paling cocok memisahkan dua nada berdasarkan jejak nada per 5 md
// Jendela analisis memakai periode nada yang sudah diketahui (sekitar 2 periode),
// jauh lebih pendek daripada jendela kasar, sehingga batasnya tidak ikut melebar.
// ---------------------------------------------------------------------------
private static int rpMs(int ms) {
    return (int) ((long) ms * RP_SR / 1000L);
}

private static float rpRms(short[] x, int a, int b) {
    if (a < 0) a = 0;
    if (b > x.length) b = x.length;
    if (b <= a) return 0f;
    double s = 0.0;
    for (int i = a; i < b; i++) { double v = x[i] / 32768.0; s += v * v; }
    return (float) Math.sqrt(s / (b - a));
}

// Nilai terendah dari fungsi selisih ternormalisasi (YIN) pada rentang tau. Kecil = periodik. 9 = di luar data.
private static float rpPeriodik(float[] x, int p0, int w, int tauMin, int tauMax, float[] cm) {
    if (p0 < 0 || p0 + w + tauMax + 1 > x.length) return 9f;
    float run = 0f;
    float mn = 9f;
    cm[0] = 1f;
    for (int tau = 1; tau <= tauMax; tau++) {
        float dsum = 0f;
        for (int j = 0; j < w; j++) {
            float df = x[p0 + j] - x[p0 + j + tau];
            dsum += df * df;
        }
        run += dsum;
        cm[tau] = run > 0f ? dsum * tau / run : 1f;
        if (tau >= tauMin && cm[tau] < mn) mn = cm[tau];
    }
    return mn;
}

// {tauMin, tauMax, lebarJendela} dari nada (MIDI), pada laju sampel yang sudah diperkecil
private static int[] rpParamTau(float midi, float srd) {
    double f0 = 440.0 * Math.pow(2.0, (midi - 69.0) / 12.0);
    double per = srd / f0;
    int tauMin = Math.max(2, (int) Math.floor(per * 0.7));
    int tauMax = Math.min((int) (srd / 75f), (int) Math.ceil(per * 1.4) + 1);
    if (tauMax < tauMin + 3) tauMax = tauMin + 3;
    int w = Math.max(48, (int) Math.ceil(per * 2.0));
    return new int[]{tauMin, tauMax, w};
}

private static boolean rpOkMaju(short[] x, float[] xd, int t, int[] pt, float thrE, float[] cm) {
    int s = rpMs(t);
    if (rpRms(x, s, s + rpMs(5)) < thrE) return false;
    return rpPeriodik(xd, s / RP_DS, pt[2], pt[0], pt[1], cm) < 0.35f;
}

private static boolean rpOkMundur(short[] x, float[] xd, int t, int[] pt, float thrE, float[] cm) {
    int s = rpMs(t);
    if (rpRms(x, s - rpMs(5), s) < thrE) return false;
    return rpPeriodik(xd, s / RP_DS - (pt[2] + pt[1] + 1), pt[2], pt[0], pt[1], cm) < 0.35f;
}

private static float rpMidiHalus(float[] xd, int tengahDs, int w, int tauMin, int tauMax, float srd, float[] cm) {
    int span = w + tauMax + 1;
    int p0 = tengahDs - span / 2;
    if (p0 < 0 || p0 + span + 1 >= xd.length) return -1f;
    float f0 = rpYin(xd, p0, w, tauMin, tauMax, srd, cm);
    if (f0 < 75f || f0 > 900f) return -1f;
    return (float) (69.0 + 12.0 * Math.log(f0 / 440.0) / Math.log(2.0));
}

private static int rpHalusAwal(int[] a, int[] b, float midi, short[] x, float[] xd, float srd, float ambang, float[] cm) {
    int tb = b[1];
    int[] pt = rpParamTau(midi, srd);
    int lo = Math.max(a[1] + 5, tb - 50);
    int hi = Math.min(tb + 50, b[2] - RP_MIN_NADA);
    if (hi < lo) return tb;
    int refA = rpMs(tb + 10);
    int refB = rpMs(Math.min(b[2], tb + 60));
    if (refB - refA < rpMs(10)) refB = refA + rpMs(10);
    float rmsRef = rpRms(x, refA, refB);
    float thrE = Math.max(ambang * 0.6f, rmsRef * 0.2f);
    int run = 0;
    for (int t = lo; t <= hi; t += 2) {
        if (rpOkMaju(x, xd, t, pt, thrE, cm)) {
            run++;
            if (run >= 3) return t - 4;
        } else {
            run = 0;
        }
    }
    return tb;
}

private static int rpHalusAkhir(int[] a, int[] b, float midi, short[] x, float[] xd, float srd, float ambang, float[] cm) {
    int tb = a[2];
    int[] pt = rpParamTau(midi, srd);
    int lo = Math.max(a[1] + RP_MIN_NADA, tb - 50);
    int hi = Math.min(tb + 50, b[2] - 5);
    if (hi < lo) return tb;
    int refA = rpMs(Math.max(a[1], tb - 60));
    int refB = rpMs(tb - 10);
    if (refB - refA < rpMs(10)) refB = refA + rpMs(10);
    float rmsRef = rpRms(x, refA, refB);
    float thrE = Math.max(ambang * 0.6f, rmsRef * 0.2f);
    int run = 0;
    for (int t = hi; t >= lo; t -= 2) {
        if (rpOkMundur(x, xd, t, pt, thrE, cm)) {
            run++;
            if (run >= 3) return t + 4;
        } else {
            run = 0;
        }
    }
    return tb;
}

private static float rpBeda(float m, float ref) {
    if (m < 0f) return 0.5f;
    return Math.min(Math.abs(m - ref), 2f);
}

private static int rpHalusBelah(int[] a, int[] b, float mL, float mR, float[] xd, float srd, float[] cm) {
    int tb = b[1];
    int lo = Math.max(a[1] + RP_MIN_NADA, tb - 50);
    int hi = Math.min(b[2] - RP_MIN_NADA, tb + 50);
    if (hi <= lo) return tb;
    double fA = 440.0 * Math.pow(2.0, (Math.min(mL, mR) - 69.0) / 12.0) / 1.15;
    double fB = 440.0 * Math.pow(2.0, (Math.max(mL, mR) - 69.0) / 12.0) * 1.15;
    int tauMin = Math.max(2, (int) (srd / fB));
    int tauMax = Math.min((int) (srd / 75f), (int) Math.ceil(srd / fA) + 1);
    if (tauMax < tauMin + 3) tauMax = tauMin + 3;
    int w = Math.max(64, tauMax * 2);
    int nk = (hi - lo) / 5 + 1;
    float[] mk = new float[nk];
    for (int k = 0; k < nk; k++) mk[k] = rpMidiHalus(xd, rpMs(lo + k * 5) / RP_DS, w, tauMin, tauMax, srd, cm);
    double terbaik = 1e18;
    int tBaik = tb;
    for (int c = 0; c <= nk; c++) {
        double biaya = 0.0;
        for (int k = 0; k < c; k++) biaya += rpBeda(mk[k], mL);
        for (int k = c; k < nk; k++) biaya += rpBeda(mk[k], mR);
        int t = lo + c * 5 - 2;
        if (t < lo) t = lo;
        if (t > hi) t = hi;
        biaya += 1e-4 * Math.abs(t - tb);
        if (biaya < terbaik) { terbaik = biaya; tBaik = t; }
    }
    return tBaik;
}

private static void rpRapikanBatas(java.util.ArrayList<int[]> seg, java.util.ArrayList<Float> midi, short[] x, float[] xd, float srd, float ambang) {
    float[] cm = new float[(int) (srd / 75f) + 4];
    for (int i = 1; i < seg.size(); i++) {
        int[] a = seg.get(i - 1);
        int[] b = seg.get(i);
        int t = b[1];
        if (a[0] == 0 && b[0] == 1) t = rpHalusAwal(a, b, midi.get(i).floatValue(), x, xd, srd, ambang, cm);
        else if (a[0] == 1 && b[0] == 0) t = rpHalusAkhir(a, b, midi.get(i - 1).floatValue(), x, xd, srd, ambang, cm);
        else if (a[0] == 1 && b[0] == 1) t = rpHalusBelah(a, b, midi.get(i - 1).floatValue(), midi.get(i).floatValue(), xd, srd, cm);
        a[2] = t;
        b[1] = t;
    }
}

private static void rpTulisWav(File out, byte[] pcm, int len) throws Exception {
    FileOutputStream fo = new FileOutputStream(out);
    rpTulisHeader(fo, len);
    fo.write(pcm, 0, len);
    fo.close();
}

private static void rpTulisHeader(FileOutputStream fo, long dataLen) throws Exception {
    byte[] h = new byte[44];
    long rate = RP_SR;
    long byteRate = rate * 2L;
    h[0] = 'R'; h[1] = 'I'; h[2] = 'F'; h[3] = 'F';
    long riff = 36L + dataLen;
    h[4] = (byte) (riff & 0xFF); h[5] = (byte) ((riff >> 8) & 0xFF); h[6] = (byte) ((riff >> 16) & 0xFF); h[7] = (byte) ((riff >> 24) & 0xFF);
    h[8] = 'W'; h[9] = 'A'; h[10] = 'V'; h[11] = 'E';
    h[12] = 'f'; h[13] = 'm'; h[14] = 't'; h[15] = ' ';
    h[16] = 16; h[17] = 0; h[18] = 0; h[19] = 0;
    h[20] = 1; h[21] = 0;
    h[22] = 1; h[23] = 0;
    h[24] = (byte) (rate & 0xFF); h[25] = (byte) ((rate >> 8) & 0xFF); h[26] = (byte) ((rate >> 16) & 0xFF); h[27] = (byte) ((rate >> 24) & 0xFF);
    h[28] = (byte) (byteRate & 0xFF); h[29] = (byte) ((byteRate >> 8) & 0xFF); h[30] = (byte) ((byteRate >> 16) & 0xFF); h[31] = (byte) ((byteRate >> 24) & 0xFF);
    h[32] = 2; h[33] = 0;
    h[34] = 16; h[35] = 0;
    h[36] = 'd'; h[37] = 'a'; h[38] = 't'; h[39] = 'a';
    h[40] = (byte) (dataLen & 0xFF); h[41] = (byte) ((dataLen >> 8) & 0xFF); h[42] = (byte) ((dataLen >> 16) & 0xFF); h[43] = (byte) ((dataLen >> 24) & 0xFF);
    fo.write(h);
}

private static String rapikanPratinjau(String kerja, String spek, String keluar) throws Exception {
    String[] p = spek.split(",");
    long awalMs = Long.parseLong(p[0].trim());
    long akhirMs = Long.parseLong(p[1].trim());
    float sen = Float.parseFloat(p[2].trim());
    File raw = new File(kerja, "vokal.raw");
    long aB = (awalMs * RP_SR / 1000L) * 2L;
    long bB = (akhirMs * RP_SR / 1000L) * 2L;
    if (bB > raw.length()) bB = raw.length() - (raw.length() & 1L);
    int len = (int) (bB - aB);
    if (len < 200) return "GAGAL: potongan terlalu pendek";
    byte[] data = new byte[len];
    RandomAccessFile rin = new RandomAccessFile(raw, "r");
    rin.seek(aB);
    rin.readFully(data);
    rin.close();
    boolean selesai = false;
    if (Math.abs(sen) >= 0.5f && muatNativeSuaraDua() && nadiVer >= 8) {
        // Jalur kontinu: sertakan 300 md suara di kiri-kanan sebagai konteks, kontur digeser mulus
        long ctxB = (RP_SR * 300L / 1000L) * 2L;
        long tot = raw.length() - (raw.length() & 1L);
        long aE = Math.max(0L, aB - ctxB); aE -= (aE & 1L);
        long bE = Math.min(tot, bB + ctxB); bE -= (bE & 1L);
        int lenE = (int) (bE - aE);
        byte[] ext = new byte[lenE];
        RandomAccessFile r2 = new RandomAccessFile(raw, "r");
        r2.seek(aE);
        r2.readFully(ext);
        r2.close();
        File tin = new File(kerja, "pr_in.raw");
        File tout = new File(kerja, "pr_out.raw");
        try {
            FileOutputStream fo = new FileOutputStream(tin);
            fo.write(ext);
            fo.close();
            int nS = lenE / 2;
            int oS = (int) ((aB - aE) / 2L);
            float[] kv = new float[nS / RP_KHOP + 2];
            for (int f = 0; f < kv.length; f++) {
                double c = (f + 0.5) * RP_KHOP;
                if (c >= oS && c < oS + len / 2) kv[f] = sen / 100f;
            }
            rpHaluskan(kv, RP_HALUS_LULUS);
            String r = rpJalankanKontur(tin.getAbsolutePath(), tout.getAbsolutePath(), kv, new File(kerja, "pr").getAbsolutePath());
            if (!"OK".equals(r) || tout.length() < lenE) return "GAGAL: " + r;
            byte[] sh = new byte[lenE];
            FileInputStream fi = new FileInputStream(tout);
            int got = 0;
            while (got < lenE) {
                int rd = fi.read(sh, got, lenE - got);
                if (rd <= 0) break;
                got += rd;
            }
            fi.close();
            System.arraycopy(sh, (int) (aB - aE), data, 0, len);
            selesai = true;
        } finally {
            tin.delete();
            tout.delete();
        }
    }
    if (!selesai && Math.abs(sen) >= 0.5f) {
        if (!muatNativeSuaraDua()) return "GAGAL: mesin pengubah suara belum siap. " + nadiPesan;
        File tin = new File(kerja, "pr_in.raw");
        File tout = new File(kerja, "pr_out.raw");
        try {
            FileOutputStream fo = new FileOutputStream(tin);
            fo.write(data);
            fo.close();
            String r = jalankanSuaraDua(tin.getAbsolutePath(), tout.getAbsolutePath(), 0, 0, RP_SR, 1,
                SuaraDuaCfg.untukPitch(sen / 100f, false, 0f, 0f, 0f), null);
            if (!"OK".equals(r) || tout.length() < len) return "GAGAL: " + r;
            FileInputStream fi = new FileInputStream(tout);
            int got = 0;
            while (got < len) {
                int rd = fi.read(data, got, len - got);
                if (rd <= 0) break;
                got += rd;
            }
            fi.close();
        } finally {
            tin.delete();
            tout.delete();
        }
    }
    // gelombang masuk/keluar 5 md supaya tidak berdetak
    int n = len / 2;
    int fade = Math.min(RP_SR / 200, n / 2);
    for (int i = 0; i < fade; i++) {
        float w = (i + 0.5f) / fade;
        int i0 = i * 2;
        int i1 = (n - 1 - i) * 2;
        short s0 = (short) ((data[i0] & 0xFF) | (data[i0 + 1] << 8));
        short s1 = (short) ((data[i1] & 0xFF) | (data[i1 + 1] << 8));
        s0 = (short) Math.round(s0 * w);
        s1 = (short) Math.round(s1 * w);
        data[i0] = (byte) (s0 & 0xFF); data[i0 + 1] = (byte) ((s0 >> 8) & 0xFF);
        data[i1] = (byte) (s1 & 0xFF); data[i1 + 1] = (byte) ((s1 >> 8) & 0xFF);
    }
    rpTulisWav(new File(keluar), data, len);
    return "SUKSES";
}

// Penghalus kontur: rata-rata bergerak 3 titik, sebanyak 'lulus' kali (pada 5 md, 16 kali = peralihan sekitar 40 md)
private static void rpHaluskan(float[] v, int lulus) {
    int n = v.length;
    if (n < 3) return;
    float[] t = new float[n];
    for (int pass = 0; pass < lulus; pass++) {
        for (int i = 0; i < n; i++) {
            float a = v[i > 0 ? i - 1 : 0], b = v[i], c = v[i < n - 1 ? i + 1 : n - 1];
            t[i] = (a + b + c) / 3f;
        }
        System.arraycopy(t, 0, v, 0, n);
    }
}

// Kontur pergeseran nada (semiton per 5 md) dari daftar nada {tipe, awalMs, akhirMs, sen}.
// Bagian tanpa nada menahan nilai nada terdekat supaya tepi nada tidak tertarik ke nol.
private static void rpKonturMentah(java.util.ArrayList<long[]> nada, int nF, float[] v, boolean[] ada, int[] kiri, int[] kanan, float[] h) {
    java.util.Arrays.fill(v, 0, nF, 0f);
    java.util.Arrays.fill(ada, 0, nF, false);
    for (int i = 0; i < nada.size(); i++) {
        long[] s = nada.get(i);
        if (s[0] != 1) continue;
        // bingkai f berpusat di (f + 0.5) * RP_KHOP cuplikan; milik nada bila pusatnya jatuh di [awal, akhir)
        int a = (int) Math.ceil(s[1] * (double) RP_SR / 1000.0 / RP_KHOP - 0.5);
        int b = (int) Math.ceil(s[2] * (double) RP_SR / 1000.0 / RP_KHOP - 0.5);
        for (int f = Math.max(0, a); f < b && f < nF; f++) { v[f] = s[3] / 100f; ada[f] = true; }
    }
    int last = -1;
    for (int f = 0; f < nF; f++) { if (ada[f]) last = f; kiri[f] = last; }
    last = -1;
    for (int f = nF - 1; f >= 0; f--) { if (ada[f]) last = f; kanan[f] = last; }
    for (int f = 0; f < nF; f++) {
        if (ada[f]) { h[f] = v[f]; continue; }
        int l = kiri[f], r = kanan[f];
        if (l < 0 && r < 0) h[f] = 0f;
        else if (l < 0) h[f] = v[r];
        else if (r < 0) h[f] = v[l];
        else h[f] = (f - l <= r - f) ? v[l] : v[r];
    }
}

private static float[] rpBuatKontur(java.util.ArrayList<long[]> nada, int nF) {
    float[] h = new float[nF];
    rpKonturMentah(nada, nF, new float[nF], new boolean[nF], new int[nF], new int[nF], h);
    rpHaluskan(h, RP_HALUS_LULUS);
    return h;
}

// Menjalankan mesin C++ mode 3 (satu alur kontinu). Mengembalikan "OK" atau pesan galat.
private static String rpJalankanKontur(String inPath, String outPath, float[] kontur, String dasar) {
    if (!muatNativeSuaraDua()) return "ERROR: " + nadiPesan;
    File job = null, res = null;
    File kf = new File(dasar + ".kontur.txt");
    try {
        StringBuilder ks = new StringBuilder();
        for (int i = 0; i < kontur.length; i++) ks.append(String.format(java.util.Locale.US, "%.5f", kontur[i])).append("\n");
        FileOutputStream fk = new FileOutputStream(kf);
        fk.write(ks.toString().getBytes("UTF-8"));
        fk.close();
        String cache = System.getProperty("nadi.so.cache");
        File dir = new File((cache != null && !cache.isEmpty()) ? cache : System.getProperty("java.io.tmpdir"));
        dir.mkdirs();
        job = new File(dir, "nadi_job_" + System.nanoTime() + ".txt");
        res = new File(job.getAbsolutePath() + ".res");
        StringBuilder sb = new StringBuilder();
        sb.append("in=").append(inPath).append("\n");
        sb.append("out=").append(outPath).append("\n");
        String progUmum = System.getProperty("nadi.prog.file");
        if (progUmum != null && !progUmum.isEmpty()) {
            sb.append("prog=").append(progUmum).append("\n");
            sb.append("plabel=").append(tahapProg).append("\n");
        }
        sb.append("sr=").append(RP_SR).append("\nch=1\nhdr=0\nouthdr=0\nmode=3\n");
        sb.append("kontur=").append(kf.getAbsolutePath()).append("\n");
        sb.append("khop=").append(RP_KHOP).append("\n");
        FileOutputStream fos = new FileOutputStream(job);
        fos.write(sb.toString().getBytes("UTF-8"));
        fos.close();
        int rc;
        synchronized (Runtime.getRuntime()) {
            android.system.Os.setenv("NADI_JOB", job.getAbsolutePath(), true);
            rc = nadiJalankan();
        }
        String hasil = "";
        if (res.exists()) {
            BufferedReader br = new BufferedReader(new FileReader(res));
            String l = br.readLine();
            br.close();
            if (l != null) hasil = l.trim();
        }
        if (rc == 0 && "OK".equals(hasil)) return "OK";
        return hasil.isEmpty() ? ("ERROR: kode " + rc) : hasil;
    } catch (Throwable t) {
        return "ERROR: " + t.getMessage();
    } finally {
        if (job != null) job.delete();
        if (res != null) res.delete();
        kf.delete();
    }
}

private static boolean rpGeserRentang(RandomAccessFile rin, RandomAccessFile rout, long offB, long lenB, long totalB, String dasar, float semi) throws Exception {
    long xfB = (RP_SR / 100) * 2L;   // 10 md
    long a = Math.max(0L, offB - xfB);
    a -= (a & 1L);
    long b = Math.min(totalB, offB + lenB + xfB);
    b -= (b & 1L);
    int len = (int) (b - a);
    if (len < 400) return false;
    byte[] pri = new byte[len];
    rin.seek(a);
    rin.readFully(pri);
    File tin = new File(dasar + ".rpin.raw");
    File tout = new File(dasar + ".rpout.raw");
    try {
        FileOutputStream fo = new FileOutputStream(tin);
        fo.write(pri);
        fo.close();
        String r = jalankanSuaraDua(tin.getAbsolutePath(), tout.getAbsolutePath(), 0, 0, RP_SR, 1,
            SuaraDuaCfg.untukPitch(semi, false, 0f, 0f, 0f), null);
        if (!"OK".equals(r) || tout.length() < len) return false;
        byte[] sh = new byte[len];
        FileInputStream fi = new FileInputStream(tout);
        int got = 0;
        while (got < len) {
            int rd = fi.read(sh, got, len - got);
            if (rd <= 0) break;
            got += rd;
        }
        fi.close();
        byte[] dsr = new byte[len];
        rout.seek(a);
        rout.readFully(dsr);
        int n = len / 2;
        int mAwal = (int) ((offB - a) / 2L);
        int mAkhir = (int) ((b - (offB + lenB)) / 2L);
        for (int i = 0; i < n; i++) {
            float w = 1f;
            if (mAwal > 0 && i < mAwal) w = (i + 0.5f) / mAwal;
            int dariAkhir = n - 1 - i;
            if (mAkhir > 0 && dariAkhir < mAkhir) w = Math.min(w, (dariAkhir + 0.5f) / mAkhir);
            int i0 = i * 2;
            short sb = (short) ((dsr[i0] & 0xFF) | (dsr[i0 + 1] << 8));
            short ss = (short) ((sh[i0] & 0xFF) | (sh[i0 + 1] << 8));
            int v = Math.round(sb * (1f - w) + ss * w);
            if (v > 32767) v = 32767;
            if (v < -32768) v = -32768;
            dsr[i0] = (byte) (v & 0xFF);
            dsr[i0 + 1] = (byte) ((v >> 8) & 0xFF);
        }
        rout.seek(a);
        rout.write(dsr);
        return true;
    } finally {
        tin.delete();
        tout.delete();
    }
}

private static String rapikanRender(String kerja, String berkasNada, String keluar, boolean lewatiKosong) throws Exception {
    File raw = new File(kerja, "vokal.raw");
    if (!raw.exists()) return "GAGAL: data vokal tidak ditemukan";
    java.util.ArrayList<long[]> nada = new java.util.ArrayList<long[]>();   // {tipe, awalMs, akhirMs, sen}
    BufferedReader br = new BufferedReader(new InputStreamReader(new FileInputStream(berkasNada), "UTF-8"));
    String ln;
    while ((ln = br.readLine()) != null) {
        ln = ln.trim();
        if (ln.isEmpty()) continue;
        String[] p = ln.split(";");
        if (p.length < 5) continue;
        nada.add(new long[]{Long.parseLong(p[0]), Long.parseLong(p[1]), Long.parseLong(p[2]), Math.round(Double.parseDouble(p[4]))});
    }
    br.close();
    long totalB = raw.length() - (raw.length() & 1L);
    File hasil = new File(kerja, "keluar.raw");
    if (hasil.exists()) hasil.delete();
    FileInputStream fi = new FileInputStream(raw);
    FileOutputStream fo = new FileOutputStream(hasil);
    byte[] buf = new byte[65536];
    int rd;
    while ((rd = fi.read(buf)) > 0) fo.write(buf, 0, rd);
    fi.close();
    fo.close();

    boolean adaGeser = false;
    for (long[] s : nada) if (s[0] == 1 && s[3] != 0) { adaGeser = true; break; }
    if (adaGeser) {
        if (!muatNativeSuaraDua()) return "GAGAL: mesin pengubah suara belum siap. " + nadiPesan;
        if (nadiVer >= 8) {
            // Satu alur kontinu untuk seluruh vokal: tidak ada potongan per nada, jadi tidak ada sambungan kasar
            tahap("Merapikan vokal");
            int nF = (int) (totalB / 2L / RP_KHOP) + 2;
            float[] kontur = rpBuatKontur(nada, nF);
            File keluarRaw = new File(kerja, "keluar_k.raw");
            String r = rpJalankanKontur(raw.getAbsolutePath(), keluarRaw.getAbsolutePath(), kontur, new File(kerja, "rk").getAbsolutePath());
            if (!"OK".equals(r) || keluarRaw.length() < totalB) { keluarRaw.delete(); return "GAGAL: " + r; }
            hasil.delete();
            if (!keluarRaw.renameTo(hasil)) return "GAGAL: tidak bisa menyimpan hasil";
            adaGeser = false;
        }
    }
    if (adaGeser) {
        RandomAccessFile rin = new RandomAccessFile(raw, "r");
        RandomAccessFile rout = new RandomAccessFile(hasil, "rw");
        try {
            int total = 0, ke = 0;
            for (long[] s : nada) if (s[0] == 1 && s[3] != 0) total++;
            for (long[] s : nada) {
                if (s[0] != 1 || s[3] == 0) continue;
                ke++;
                tahap("Merapikan nada " + ke + " dari " + total);
                laporUmum((ke - 1) * 100 / Math.max(1, total));
                long offB = (s[1] * RP_SR / 1000L) * 2L;
                long lenB = ((s[2] - s[1]) * RP_SR / 1000L) * 2L;
                if (offB + lenB > totalB) lenB = totalB - offB;
                rpGeserRentang(rin, rout, offB, lenB, totalB, hasil.getAbsolutePath(), s[3] / 100f);
            }
        } finally {
            rin.close();
            rout.close();
        }
    }
    // Susun keluaran: seluruhnya, atau tanpa jeda panjang
    java.util.ArrayList<long[]> rentang = new java.util.ArrayList<long[]>();
    if (!lewatiKosong) {
        rentang.add(new long[]{0L, totalB});
    } else {
        long sisaB = ((long) RP_MS_SISA * RP_SR / 1000L) * 2L;
        for (int i = 0; i < nada.size(); i++) {
            long[] s = nada.get(i);
            long aB = (s[1] * RP_SR / 1000L) * 2L;
            long bB = (i == nada.size() - 1) ? totalB : (s[2] * RP_SR / 1000L) * 2L;
            if (bB > totalB) bB = totalB;
            if (bB <= aB) continue;
            long durMs = s[2] - s[1];
            if (s[0] == 0 && durMs >= RP_MS_KOSONG_MIN && (bB - aB) > 2L * sisaB) {
                rentang.add(new long[]{aB, aB + sisaB});
                rentang.add(new long[]{bB - sisaB, bB});
            } else {
                rentang.add(new long[]{aB, bB});
            }
        }
    }
    long dataLen = 0L;
    for (long[] r : rentang) dataLen += (r[1] - r[0]);
    RandomAccessFile src = new RandomAccessFile(hasil, "r");
    FileOutputStream wav = new FileOutputStream(new File(keluar));
    rpTulisHeader(wav, dataLen);
    for (long[] r : rentang) {
        src.seek(r[0]);
        long sisa = r[1] - r[0];
        while (sisa > 0) {
            int tr = (int) Math.min((long) buf.length, sisa);
            int got = src.read(buf, 0, tr);
            if (got <= 0) break;
            wav.write(buf, 0, got);
            sisa -= got;
        }
    }
    wav.close();
    src.close();
    hasil.delete();
    return "SUKSES";
}

// =============================================================================
//  MESIN NADA LANGSUNG (REAL TIME) untuk Rapikan Suara Vokal
//  Seluruh vokal dimuat sekali ke mesin pengubah suara dan dianalisis sekali. Saat
//  diputar, mesin menyusun suara blok demi blok (sekitar 11 md) dengan nada sesuai
//  kontur yang BOLEH DIUBAH KAPAN SAJA, sehingga perubahan nada terdengar seketika
//  tanpa menunggu render, dan warna suara (formant) tetap alami.
//
//  Perintah dari Lua (lewat rapikanPerintah, semuanya kembali seketika):
//    live_siap  : a = folder kerja                -> "SUKSES:status" atau "GAGAL: ..."
//    live_nada  : a = berkas daftar nada          -> "SUKSES" (memuat ulang semua nada)
//    live_geser : a = nomor baris (mulai 0), b = sen -> "SUKSES" (nada berubah seketika)
//    live_main  : a = awal md, b = akhir md (<=0 = sampai habis) -> "SUKSES" / "TUNGGU:persen"
//    live_cari  : a = posisi md (pindah posisi saat diputar)
//    live_henti : berhenti dengan memudar
//    live_status: -> "status|persen|posisiMd|jalan|pesan"
//    live_lepas : melepas sesi dan memori
//  Seluruh keadaan bersifat statis di kelas ini, jadi Lua harus memanggil lewat
//  SATU pemuat kelas yang sama (rapikanJava), bukan rapikanAsync.
// =============================================================================
private static final int LV_BLOK = 512;
private static final Object liveKunci = new Object();
private static LiveSesi liveSesi = null;

private static final class LiveSesi {
    final String kerja;
    final String kunciBerkas;
    long h = 0;
    volatile String state = "analisis";   // analisis, siap, galat
    volatile String galat = "";
    boolean batal = false;
    boolean analisisJalan = false;
    int mainHidup = 0;
    LiveMain main = null;
    int n = 0, nk = 0, khop = 0;
    java.util.ArrayList<long[]> nada = new java.util.ArrayList<long[]>();   // {tipe, awalMs, akhirMs, sen}
    float[] kontur, sV, sH;
    boolean[] sAda;
    int[] sKiri, sKanan;
    volatile long rAwalMs = 0, rAkhirMs = 0;
    LiveSesi(String kerja, String kunciBerkas) { this.kerja = kerja; this.kunciBerkas = kunciBerkas; }
}

private static final class LiveMain implements Runnable {
    final LiveSesi s;
    final LiveMain sebelum;
    Thread th;
    volatile boolean hidup = true;
    volatile boolean henti = false;
    volatile boolean ganti = false;
    volatile long posMs = 0;
    volatile String galat = "";
    LiveMain(LiveSesi s, LiveMain sebelum) { this.s = s; this.sebelum = sebelum; }
    public void run() { livePutar(this); }
}

// Dipanggil di dalam liveKunci. Melepas memori native hanya bila tidak ada thread yang memakainya.
private static void liveLepasJikaPerlu(LiveSesi s) {
    if (s.batal && !s.analisisJalan && s.mainHidup == 0 && s.h != 0) {
        long h = s.h;
        s.h = 0;
        try { nvLiveLepas(h); } catch (Throwable ignored) {}
    }
}

private static void liveLepasSesi() {
    synchronized (liveKunci) {
        LiveSesi s = liveSesi;
        liveSesi = null;
        if (s == null) return;
        s.batal = true;
        if (s.main != null) s.main.henti = true;
        if (s.h != 0 && s.analisisJalan) { try { nvLiveBatal(s.h); } catch (Throwable ignored) {} }
        liveLepasJikaPerlu(s);
    }
}

private static String liveDispatch(String cmd, String a, String b, String c, String d) {
    try {
        if ("live_siap".equals(cmd)) return liveSiap(a);
        if ("live_nada".equals(cmd)) return liveMuatNada(a);
        if ("live_geser".equals(cmd)) return liveGeser(Integer.parseInt(a.trim()), Math.round(Float.parseFloat(b.trim())));
        if ("live_main".equals(cmd)) return liveMain(Long.parseLong(a.trim()), Long.parseLong(b.trim()));
        if ("live_cari".equals(cmd)) return liveCari(Long.parseLong(a.trim()));
        if ("live_henti".equals(cmd)) return liveHenti();
        if ("live_status".equals(cmd)) return liveStatus();
        if ("live_lepas".equals(cmd)) { liveLepasSesi(); return "SUKSES"; }
        return "GAGAL: perintah tidak dikenal";
    } catch (Throwable t) {
        return "GAGAL: " + (t.getMessage() == null ? t.toString() : t.getMessage());
    }
}

private static String liveSiap(String kerja) {
    File raw = new File(kerja, "vokal.raw");
    if (!raw.exists()) return "GAGAL: data vokal tidak ditemukan";
    if (!muatNativeSuaraDua()) return "GAGAL: mesin pengubah suara belum siap";
    if (nadiVer < 9) return "GAGAL: mesin pengubah suara belum mendukung pemutaran langsung";
    String kunci = raw.length() + ":" + raw.lastModified();
    synchronized (liveKunci) {
        LiveSesi lama = liveSesi;
        if (lama != null && !lama.batal && lama.kerja.equals(kerja) && lama.kunciBerkas.equals(kunci) && !"galat".equals(lama.state)) {
            return "SUKSES:" + lama.state;
        }
    }
    liveLepasSesi();
    final LiveSesi s = new LiveSesi(kerja, kunci);
    synchronized (liveKunci) {
        liveSesi = s;
        s.analisisJalan = true;
    }
    Thread t = new Thread(new Runnable() {
        public void run() { liveAnalisisKerja(s); }
    }, "NadiLiveAnalisis");
    t.setDaemon(true);
    t.start();
    return "SUKSES:analisis";
}

private static void liveAnalisisKerja(LiveSesi s) {
    try {
        byte[] jp = new File(s.kerja, "vokal.raw").getAbsolutePath().getBytes("UTF-8");
        long h = nvLiveBuat(jp, RP_SR);
        synchronized (liveKunci) {
            if (h == 0) { s.galat = "vokal tidak bisa dimuat ke mesin"; s.state = "galat"; return; }
            s.h = h;
            if (s.batal) return;
        }
        int ok = nvLiveAnalisis(h);
        synchronized (liveKunci) {
            if (s.batal) return;
            if (ok != 1) { s.galat = "analisis nada gagal"; s.state = "galat"; return; }
            s.n = nvLiveInfo(h, 0);
            s.khop = nvLiveInfo(h, 1);
            s.nk = nvLiveInfo(h, 2);
            if (s.n <= 0 || s.nk <= 0 || s.khop != RP_KHOP) { s.galat = "mesin tidak cocok"; s.state = "galat"; return; }
            s.kontur = new float[s.nk];
            s.sV = new float[s.nk];
            s.sH = new float[s.nk];
            s.sAda = new boolean[s.nk];
            s.sKiri = new int[s.nk];
            s.sKanan = new int[s.nk];
            s.state = "siap";
            liveDorongKontur(s);
        }
    } catch (Throwable t) {
        s.galat = "" + (t.getMessage() == null ? t.toString() : t.getMessage());
        s.state = "galat";
    } finally {
        synchronized (liveKunci) {
            s.analisisJalan = false;
            liveLepasJikaPerlu(s);
        }
    }
}

// Dipanggil di dalam liveKunci, sesi siap. Menghitung kontur dari daftar nada dan menyerahkannya ke mesin.
private static void liveDorongKontur(LiveSesi s) {
    if (s.batal || s.h == 0 || !"siap".equals(s.state) || s.kontur == null) return;
    rpKonturMentah(s.nada, s.nk, s.sV, s.sAda, s.sKiri, s.sKanan, s.kontur);
    nvLiveKontur(s.h, s.kontur, s.nk);
}

private static String liveMuatNada(String berkas) throws Exception {
    java.util.ArrayList<long[]> daftar = new java.util.ArrayList<long[]>();
    BufferedReader br = new BufferedReader(new InputStreamReader(new FileInputStream(berkas), "UTF-8"));
    try {
        String ln;
        while ((ln = br.readLine()) != null) {
            ln = ln.trim();
            if (ln.isEmpty()) continue;
            String[] p = ln.split(";");
            if (p.length < 5) continue;
            daftar.add(new long[]{Long.parseLong(p[0]), Long.parseLong(p[1]), Long.parseLong(p[2]), Math.round(Double.parseDouble(p[4]))});
        }
    } finally {
        br.close();
    }
    synchronized (liveKunci) {
        LiveSesi s = liveSesi;
        if (s == null) return "GAGAL: sesi belum disiapkan";
        s.nada = daftar;
        liveDorongKontur(s);
    }
    return "SUKSES";
}

private static String liveGeser(int idx, int sen) {
    synchronized (liveKunci) {
        LiveSesi s = liveSesi;
        if (s == null) return "GAGAL: sesi belum disiapkan";
        if (idx < 0 || idx >= s.nada.size()) return "GAGAL: nada tidak ada";
        long[] n = s.nada.get(idx);
        if (n[0] != 1) return "GAGAL: bukan nada";
        n[3] = sen;
        liveDorongKontur(s);
    }
    return "SUKSES";
}

private static String liveMain(long awalMs, long akhirMs) {
    synchronized (liveKunci) {
        LiveSesi s = liveSesi;
        if (s == null || s.batal) return "GAGAL: sesi belum disiapkan";
        if ("analisis".equals(s.state)) return "TUNGGU:" + liveProgresLocked(s);
        if (!"siap".equals(s.state) || s.h == 0) return "GAGAL: " + s.galat;
        long durMs = (long) s.n * 1000L / RP_SR;
        if (awalMs < 0) awalMs = 0;
        if (akhirMs <= 0 || akhirMs > durMs) akhirMs = durMs;
        if (awalMs > akhirMs - 30) awalMs = Math.max(0L, akhirMs - 30);
        if (akhirMs - awalMs < 20) return "GAGAL: rentang terlalu pendek";
        s.rAwalMs = awalMs;
        s.rAkhirMs = akhirMs;
        LiveMain m = s.main;
        if (m != null && m.hidup && !m.henti) {
            m.ganti = true;         // pemutar yang sedang jalan pindah ke rentang baru
            return "SUKSES";
        }
        LiveMain baru = new LiveMain(s, (m != null && m.hidup) ? m : null);
        baru.posMs = awalMs;
        s.main = baru;
        s.mainHidup++;
        baru.th = new Thread(baru, "NadiLivePutar");
        baru.th.setDaemon(true);
        baru.th.start();
    }
    return "SUKSES";
}

private static String liveCari(long posMs) {
    LiveSesi s;
    long akhir;
    synchronized (liveKunci) {
        s = liveSesi;
        if (s == null) return "GAGAL: sesi belum disiapkan";
        akhir = s.rAkhirMs;
    }
    return liveMain(posMs, akhir);
}

private static String liveHenti() {
    synchronized (liveKunci) {
        LiveSesi s = liveSesi;
        if (s == null) return "SUKSES";
        if (s.main != null) s.main.henti = true;
    }
    return "SUKSES";
}

private static int liveProgresLocked(LiveSesi s) {
    if ("siap".equals(s.state)) return 100;
    if (s.h == 0 || s.batal) return 0;
    try { return nvLiveProgres(s.h); } catch (Throwable t) { return 0; }
}

private static String liveStatus() {
    synchronized (liveKunci) {
        LiveSesi s = liveSesi;
        if (s == null) return "kosong|0|0|0|";
        LiveMain m = s.main;
        int jalan = (m != null && m.hidup && !m.henti) ? 1 : 0;
        long pos = (m != null) ? m.posMs : 0L;
        String pesan = s.galat;
        if (m != null && m.galat != null && !m.galat.isEmpty()) pesan = m.galat;
        return s.state + "|" + liveProgresLocked(s) + "|" + pos + "|" + jalan + "|" + pesan.replace('|', ' ');
    }
}

private static long liveHead(android.media.AudioTrack at) {
    return ((long) at.getPlaybackHeadPosition()) & 0xFFFFFFFFL;
}

private static void liveTungguHabis(LiveMain m, android.media.AudioTrack at, long headDasar, long ditulis, long batasMd) {
    long mulai = System.currentTimeMillis();
    while (System.currentTimeMillis() - mulai < batasMd) {
        if (m.s.batal || m.ganti) return;
        long dimainkan = liveHead(at) - headDasar;
        if (dimainkan >= ditulis) return;
        try { Thread.sleep(3); } catch (InterruptedException e) { return; }
    }
}

// Satu thread pemutar: AudioTrack mengalir, mesin C++ mengisi blok demi blok.
private static void livePutar(LiveMain m) {
    final LiveSesi s = m.s;
    android.media.AudioTrack at = null;
    try {
        try { android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO); } catch (Throwable ignored) {}
        if (m.sebelum != null && m.sebelum.th != null) {
            try { m.sebelum.th.join(1500); } catch (InterruptedException ignored) {}
        }
        synchronized (liveKunci) { if (s.batal || m.henti) return; }
        int minBuf = android.media.AudioTrack.getMinBufferSize(RP_SR, 4 /* CHANNEL_OUT_MONO */, 2 /* PCM 16 */);
        int bufBytes = Math.max(minBuf, LV_BLOK * 2 * 3);
        at = new android.media.AudioTrack(3 /* STREAM_MUSIC */, RP_SR, 4, 2, bufBytes, android.media.AudioTrack.MODE_STREAM);
        if (at.getState() != android.media.AudioTrack.STATE_INITIALIZED) throw new Exception("pemutar suara tidak bisa dibuka");
        byte[] buf = new byte[LV_BLOK * 2];
        boolean pertama = true;
        boolean berhenti = false;
        while (!berhenti) {
            long awalMs, akhirMs;
            synchronized (liveKunci) {
                if (s.batal || m.henti || s.h == 0) break;
                awalMs = s.rAwalMs;
                akhirMs = s.rAkhirMs;
                m.ganti = false;
            }
            final long awalS = awalMs * RP_SR / 1000L;
            long akhirS = akhirMs * RP_SR / 1000L;
            if (akhirS > s.n) akhirS = s.n;
            if (nvLiveMulai(s.h, awalS) != 1) throw new Exception("mesin gagal dimulai");
            m.posMs = awalMs;
            if (!pertama) {
                try { at.pause(); } catch (Throwable ignored) {}
                at.flush();
            }
            long headDasar = liveHead(at);
            at.play();
            pertama = false;
            long rendered = awalS;
            long ditulis = 0;
            boolean akhirRentang = false;
            while (true) {
                if (s.batal) { berhenti = true; break; }
                if (m.henti || m.ganti) {
                    // memudar supaya tidak berdetak, lalu tunggu sebentar sampai habis terdengar
                    int r = nvLiveRender(s.h, buf, LV_BLOK, 1);
                    if (r > 0) { at.write(buf, 0, r * 2); ditulis += r; }
                    at.stop();
                    liveTungguHabis(m, at, headDasar, ditulis, 150);
                    if (m.henti) berhenti = true;
                    break;
                }
                long sisa = akhirS - rendered;
                if (sisa <= 0) { akhirRentang = true; break; }
                int N = (int) Math.min((long) LV_BLOK, sisa);
                boolean terakhir = (sisa <= LV_BLOK) && (akhirS < s.n);
                int r = nvLiveRender(s.h, buf, N, terakhir ? 1 : 0);
                if (r <= 0) throw new Exception("mesin gagal membuat suara (" + r + ")");
                at.write(buf, 0, r * 2);
                rendered += r;
                ditulis += r;
                long dimainkan = liveHead(at) - headDasar;
                if (dimainkan < 0) dimainkan = 0;
                if (dimainkan > ditulis) dimainkan = ditulis;
                m.posMs = (awalS + dimainkan) * 1000L / RP_SR;
            }
            if (akhirRentang) {
                at.stop();
                long tunggu = (ditulis - (liveHead(at) - headDasar)) * 1000L / RP_SR + 300L;
                liveTungguHabis(m, at, headDasar, ditulis, Math.max(300L, tunggu));
                // memeriksa permintaan baru dan menandai selesai harus sekaligus, supaya perintah yang
                // datang tepat di ujung tidak hilang (liveMain memeriksa m.hidup di kunci yang sama)
                synchronized (liveKunci) {
                    if (!m.ganti) { m.posMs = akhirMs; m.hidup = false; berhenti = true; }
                }
            }
        }
    } catch (Throwable t) {
        m.galat = (t.getMessage() == null ? t.toString() : t.getMessage());
        android.util.Log.w("NadiMesin", "pemutar langsung berhenti: " + t);
    } finally {
        if (at != null) {
            try { at.stop(); } catch (Throwable ignored) {}
            try { at.release(); } catch (Throwable ignored) {}
        }
        synchronized (liveKunci) {
            m.hidup = false;
            s.mainHidup--;
            liveLepasJikaPerlu(s);
        }
    }
}

// =============================================================================
//  PEMUTAR MULTI-TRACK REAL TIME (gaya DAW)
//  Setiap track sudah dirender sekali (efek + segmen) menjadi PCM 16-bit stereo di cache.
//  Saat diputar, pencampuran dilakukan per blok kecil langsung ke AudioTrack, sehingga:
//    - tombol putar langsung berbunyi (tanpa menyatukan seluruh lagu dulu)
//    - volume, geser waktu, dan solo berubah seketika saat sedang diputar
//    - pindah posisi (cari) tidak perlu render ulang
//  Rumus campur dan pemotongan di ujung track utama sama dengan campurAudio, jadi
//  yang terdengar di sini sama dengan hasil simpan.
//  Perintah (lewat rapikanPerintah, seluruh keadaan statis, pakai SATU pemuat kelas):
//    mt_muat   : a = berkas manifes (baris: pathPcm|volPersen|geserMs)  -> "SUKSES"
//    mt_atur   : a = "vol|geser;vol|geser;..." (jumlah harus sama)       -> "SUKSES"
//    mt_vol    : a = nomor track (mulai 0), b = persen                    -> "SUKSES"
//    mt_geser  : a = nomor track (mulai 0), b = milidetik                 -> "SUKSES"
//    mt_solo   : a = nomor track, -1 = semua                              -> "SUKSES"
//    mt_main   : a = awal md (<0 = lanjut dari posisi terakhir), b = solo -> "SUKSES"
//    mt_cari   : a = posisi md
//    mt_henti  : berhenti dengan memudar (posisi diingat)
//    mt_status : -> "jalan|posMd|durMd|pesan"
//    mt_lepas  : melepas sesi
// =============================================================================
private static final int MT_SR = 44100;
private static final int MT_BLOK = 1024;
private static final Object mtKunci = new Object();
private static MtSesi mtSesi = null;

private static final class MtTrack {
    String path;
    volatile float vol = 1f;
    volatile long offFr = 0;
    long lenFr = 0;
    RandomAccessFile raf = null;
}

private static final class MtSesi {
    volatile MtTrack[] tr = new MtTrack[0];
    final Object kunciBaca = new Object();
    volatile int solo = -1;
    volatile boolean henti = false;
    volatile boolean hidup = false;
    volatile long posFr = 0;
    volatile long seekFr = -1;
    volatile String galat = "";
    boolean batal = false;
    Thread th = null;
    float[] gain = new float[0];
}

private static long mtDurFr(MtSesi s) {
    MtTrack[] t = s.tr;
    if (t.length == 0) return 0;
    // sama dengan campurAudio: track pertama adalah track utama, yang lain terpotong di ujungnya.
    // Mode solo meniru pratinjau "track ini saja": track itu menjadi track utama.
    int sl = s.solo;
    MtTrack u = (sl >= 0 && sl < t.length) ? t[sl] : t[0];
    long d = u.lenFr + u.offFr;
    return d < 0 ? 0 : d;
}

private static void mtTutupRaf(MtTrack[] t) {
    if (t == null) return;
    for (int i = 0; i < t.length; i++) {
        if (t[i] != null && t[i].raf != null) { try { t[i].raf.close(); } catch (Throwable ignored) {} t[i].raf = null; }
    }
}

private static String mtDispatch(String cmd, String a, String b, String c, String d) {
    try {
        if ("mt_muat".equals(cmd)) return mtMuat(a);
        if ("mt_atur".equals(cmd)) return mtAtur(a);
        if ("mt_vol".equals(cmd)) {
            MtSesi s = mtSesi; if (s == null) return "GAGAL: belum dimuat";
            MtTrack[] t = s.tr; int i = Integer.parseInt(a.trim());
            if (i < 0 || i >= t.length) return "GAGAL: track tidak ada";
            t[i].vol = Math.max(0f, Math.min(2f, Float.parseFloat(b.trim()) / 100f));
            return "SUKSES";
        }
        if ("mt_geser".equals(cmd)) {
            MtSesi s = mtSesi; if (s == null) return "GAGAL: belum dimuat";
            MtTrack[] t = s.tr; int i = Integer.parseInt(a.trim());
            if (i < 0 || i >= t.length) return "GAGAL: track tidak ada";
            t[i].offFr = Math.round(Double.parseDouble(b.trim()) * MT_SR / 1000.0);
            return "SUKSES";
        }
        if ("mt_solo".equals(cmd)) {
            MtSesi s = mtSesi; if (s == null) return "GAGAL: belum dimuat";
            s.solo = Integer.parseInt(a.trim());
            return "SUKSES";
        }
        if ("mt_main".equals(cmd)) return mtMain(Long.parseLong(a.trim()), (b == null || b.trim().isEmpty()) ? -1 : Integer.parseInt(b.trim()));
        if ("mt_cari".equals(cmd)) {
            MtSesi s = mtSesi; if (s == null) return "GAGAL: belum dimuat";
            long fr = Math.max(0L, Long.parseLong(a.trim()) * MT_SR / 1000L);
            fr = Math.min(fr, mtDurFr(s));
            if (s.hidup && !s.henti) s.seekFr = fr; else s.posFr = fr;
            return "SUKSES";
        }
        if ("mt_henti".equals(cmd)) {
            MtSesi s = mtSesi; if (s != null) s.henti = true;
            return "SUKSES";
        }
        if ("mt_status".equals(cmd)) {
            MtSesi s = mtSesi;
            if (s == null) return "0|0|0|";
            String p = s.galat == null ? "" : s.galat.replace('|', ' ');
            return ((s.hidup && !s.henti) ? "1" : "0") + "|" + (s.posFr * 1000L / MT_SR) + "|" + (mtDurFr(s) * 1000L / MT_SR) + "|" + p;
        }
        if ("mt_lepas".equals(cmd)) { mtLepas(); return "SUKSES"; }
        return "GAGAL: perintah tidak dikenal";
    } catch (Throwable t) {
        return "GAGAL: " + (t.getMessage() == null ? t.toString() : t.getMessage());
    }
}

private static void mtLepas() {
    MtSesi s;
    synchronized (mtKunci) { s = mtSesi; mtSesi = null; }
    if (s == null) return;
    s.batal = true;
    s.henti = true;
    Thread th = s.th;
    if (th != null) { try { th.join(800); } catch (InterruptedException ignored) {} }
    synchronized (s.kunciBaca) { mtTutupRaf(s.tr); s.tr = new MtTrack[0]; }
}

private static String mtMuat(String berkas) throws Exception {
    java.util.ArrayList<String[]> baris = new java.util.ArrayList<String[]>();
    BufferedReader br = new BufferedReader(new InputStreamReader(new FileInputStream(berkas), "UTF-8"));
    try {
        String ln;
        while ((ln = br.readLine()) != null) {
            ln = ln.trim();
            if (ln.isEmpty()) continue;
            String[] p = ln.split("\\|");
            baris.add(p);
        }
    } finally { br.close(); }
    if (baris.isEmpty()) return "GAGAL: daftar track kosong";
    MtTrack[] baru = new MtTrack[baris.size()];
    for (int i = 0; i < baru.length; i++) {
        String[] p = baris.get(i);
        MtTrack t = new MtTrack();
        t.path = p[0].trim();
        t.vol = (p.length > 1) ? Math.max(0f, Math.min(2f, Float.parseFloat(p[1].trim()) / 100f)) : 1f;
        t.offFr = (p.length > 2) ? Math.round(Double.parseDouble(p[2].trim()) * MT_SR / 1000.0) : 0L;
        File f = new File(t.path);
        long len = f.exists() ? f.length() : 0L;
        len -= len % 4;
        t.lenFr = len / 4;
        if (t.lenFr > 0) t.raf = new RandomAccessFile(f, "r");
        baru[i] = t;
    }
    if (baru[0].lenFr <= 0) { mtTutupRaf(baru); return "GAGAL: track utama kosong atau rusak"; }
    MtSesi s;
    synchronized (mtKunci) {
        if (mtSesi == null || mtSesi.batal) mtSesi = new MtSesi();
        s = mtSesi;
    }
    MtTrack[] lama;
    synchronized (s.kunciBaca) {
        lama = s.tr;
        s.tr = baru;
        if (s.gain.length != baru.length) {
            s.gain = new float[baru.length];
            for (int i = 0; i < baru.length; i++) s.gain[i] = baru[i].vol;
        }
        if (s.solo >= baru.length) s.solo = -1;
        s.galat = "";
        long dur = mtDurFr(s);
        if (s.posFr > dur) s.posFr = dur;
        mtTutupRaf(lama);
    }
    return "SUKSES";
}

// Memakai nilai volume dan geser terbaru tanpa memuat ulang berkas.
private static String mtAtur(String teks) {
    MtSesi s = mtSesi;
    if (s == null) return "GAGAL: belum dimuat";
    MtTrack[] t = s.tr;
    String[] bag = teks.split(";");
    if (bag.length != t.length) return "GAGAL: jumlah track berbeda";
    for (int i = 0; i < t.length; i++) {
        String[] p = bag[i].split("\\|");
        t[i].vol = Math.max(0f, Math.min(2f, Float.parseFloat(p[0].trim()) / 100f));
        t[i].offFr = Math.round(Double.parseDouble(p[1].trim()) * MT_SR / 1000.0);
    }
    return "SUKSES";
}

private static String mtMain(long awalMs, int solo) {
    MtSesi s = mtSesi;
    if (s == null || s.tr.length == 0) return "GAGAL: belum dimuat";
    s.solo = solo;
    long dur = mtDurFr(s);
    long fr = (awalMs < 0) ? s.posFr : awalMs * MT_SR / 1000L;
    if (fr >= dur) fr = 0;      // sudah di ujung: mulai dari awal
    synchronized (mtKunci) {
        if (s.hidup && !s.henti) { s.seekFr = fr; return "SUKSES"; }
        Thread lama = s.th;
        s.henti = false;
        s.seekFr = fr;
        s.posFr = fr;
        s.galat = "";
        s.hidup = true;
        final MtSesi ss = s;
        final Thread tunggu = lama;
        s.th = new Thread(new Runnable() {
            public void run() {
                if (tunggu != null && tunggu.isAlive()) { try { tunggu.join(1200); } catch (InterruptedException ignored) {} }
                mtPutar(ss);
            }
        }, "NadiMtPutar");
        s.th.setDaemon(true);
        s.th.start();
    }
    return "SUKSES";
}

// Mencampur satu blok mulai frame 'mulai' sebanyak n frame ke out (stereo, short).
private static void mtCampurBlok(MtSesi s, long mulai, int n, short[] out, byte[] tmp, float[] acc) {
    java.util.Arrays.fill(acc, 0, n * 2, 0f);
    synchronized (s.kunciBaca) {
        MtTrack[] tr = s.tr;
        long dur = mtDurFr(s);
        if (s.gain.length != tr.length) s.gain = new float[tr.length];
        int solo = s.solo;
        for (int k = 0; k < tr.length; k++) {
            MtTrack t = tr[k];
            float tujuan = (solo < 0 || solo == k) ? t.vol : 0f;
            float g0 = s.gain[k];
            s.gain[k] = tujuan;
            if (t.raf == null || t.lenFr <= 0) continue;
            if (g0 == 0f && tujuan == 0f) continue;
            long src = mulai - t.offFr;
            int i0 = (int) Math.max(0L, -src);
            int i1 = (int) Math.min((long) n, t.lenFr - src);
            if (solo < 0 && k > 0) i1 = (int) Math.min((long) i1, dur - mulai);   // dipotong di ujung track utama
            if (i1 <= i0) continue;
            int cnt = i1 - i0;
            try {
                t.raf.seek((src + i0) * 4L);
                t.raf.readFully(tmp, 0, cnt * 4);
            } catch (IOException e) { continue; }
            float step = (tujuan - g0) / (float) n;
            for (int i = 0; i < cnt; i++) {
                int fi = i0 + i;
                float g = g0 + step * fi;
                int bi = i * 4;
                short l = (short) ((tmp[bi] & 0xFF) | (tmp[bi + 1] << 8));
                short r = (short) ((tmp[bi + 2] & 0xFF) | (tmp[bi + 3] << 8));
                acc[fi * 2] += l * g;
                acc[fi * 2 + 1] += r * g;
            }
        }
    }
    for (int i = 0; i < n * 2; i++) {
        int v = Math.round(acc[i]);
        if (v > 32767) v = 32767; else if (v < -32768) v = -32768;
        out[i] = (short) v;
    }
}

private static void mtPutar(MtSesi s) {
    android.media.AudioTrack at = null;
    try {
        try { android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO); } catch (Throwable ignored) {}
        int minBuf = android.media.AudioTrack.getMinBufferSize(MT_SR, 12 /* STEREO */, 2);
        int bufBytes = Math.max(minBuf, MT_BLOK * 4 * 3);
        at = new android.media.AudioTrack(3, MT_SR, 12, 2, bufBytes, android.media.AudioTrack.MODE_STREAM);
        if (at.getState() != android.media.AudioTrack.STATE_INITIALIZED) throw new Exception("pemutar suara tidak bisa dibuka");
        short[] out = new short[MT_BLOK * 2];
        byte[] tmp = new byte[MT_BLOK * 4];
        float[] acc = new float[MT_BLOK * 2];
        long pos = s.posFr;
        long basePos = pos;
        long headDasar = 0;
        boolean mulaiBaru = true;
        boolean selesai = false;
        long ditulis = 0;
        while (!s.batal) {
            long sk = s.seekFr;
            if (sk >= 0) {
                s.seekFr = -1;
                pos = Math.min(sk, mtDurFr(s));
                basePos = pos;
                if (!mulaiBaru) { try { at.pause(); } catch (Throwable ignored) {} at.flush(); }
                headDasar = liveHead(at);
                ditulis = 0;
                at.play();
                mulaiBaru = false;
            }
            long dur = mtDurFr(s);
            if (s.henti) {
                // memudar 256 frame supaya tidak berdetak
                int n = (int) Math.max(1L, Math.min(256L, dur - pos));
                if (pos < dur) {
                    mtCampurBlok(s, pos, n, out, tmp, acc);
                    for (int i = 0; i < n; i++) {
                        float f = 1f - (i / (float) n);
                        out[i * 2] = (short) (out[i * 2] * f);
                        out[i * 2 + 1] = (short) (out[i * 2 + 1] * f);
                    }
                    at.write(out, 0, n * 2);
                    pos += n; ditulis += n;
                }
                break;
            }
            if (pos >= dur) { selesai = true; break; }
            int n = (int) Math.min((long) MT_BLOK, dur - pos);
            mtCampurBlok(s, pos, n, out, tmp, acc);
            at.write(out, 0, n * 2);
            pos += n;
            ditulis += n;
            long dimain = liveHead(at) - headDasar;
            if (dimain < 0) dimain = 0;
            if (dimain > ditulis) dimain = ditulis;
            s.posFr = basePos + dimain;
        }
        if (selesai) {
            at.stop();
            long mulaiTunggu = System.currentTimeMillis();
            long batas = (ditulis - (liveHead(at) - headDasar)) * 1000L / MT_SR + 400L;
            while (System.currentTimeMillis() - mulaiTunggu < batas && !s.batal && s.seekFr < 0) {
                if (liveHead(at) - headDasar >= ditulis) break;
                try { Thread.sleep(5); } catch (InterruptedException e) { break; }
            }
            if (s.seekFr < 0) s.posFr = mtDurFr(s);
        } else {
            try { at.stop(); } catch (Throwable ignored) {}
            long mulaiTunggu = System.currentTimeMillis();
            while (System.currentTimeMillis() - mulaiTunggu < 150 && liveHead(at) - headDasar < ditulis) {
                try { Thread.sleep(3); } catch (InterruptedException e) { break; }
            }
            s.posFr = Math.min(pos, mtDurFr(s));
        }
    } catch (Throwable t) {
        s.galat = (t.getMessage() == null ? t.toString() : t.getMessage());
        android.util.Log.w("NadiMesin", "pemutar multi-track berhenti: " + t);
    } finally {
        if (at != null) {
            try { at.stop(); } catch (Throwable ignored) {}
            try { at.release(); } catch (Throwable ignored) {}
        }
        s.hidup = false;
    }
}

// =============================================================================
//  PEMUTAR NADA REAL TIME (Naikkan / Turunkan Nada)
//  Audio dimuat sekali, lalu diputar blok demi blok (sekitar 12 md) langsung ke AudioTrack.
//  Tingkat nada, pergeseran bertahap, mode biasa/tingkat lanjut, dan ulangi boleh diubah
//  KAPAN SAJA saat sedang diputar, dan perubahan langsung terdengar (tanpa render ulang).
//    - Mode biasa         : Sonic, mengalir (langsung berbunyi, tanpa persiapan).
//    - Mode tingkat lanjut: mesin nada langsung (formant terjaga). Analisis dilakukan SATU kali
//                           di latar belakang dengan persen. Selama analisis berjalan, suara tetap
//                           diputar dengan mode biasa, lalu berpindah sendiri bila sudah siap.
//  Perintah (lewat rapikanPerintah, seluruh keadaan statis, pakai SATU pemuat kelas):
//    pt_siapkan     : a = berkas audio, b = folder kerja, c = "awalMd,akhirMd" (boleh kosong)  -> "SUKSES:durMd"
//    pt_siapkan_raw : a = berkas PCM 16-bit mentah, b = folder kerja, c = sample rate, d = channel -> "SUKSES:durMd"
//    pt_buka        : a = folder kerja, b = "sd" untuk mode Suara Dua (boleh kosong), c = "1" bila stereo -> "SUKSES:durMd"
//    pt_atur_sd     : a = "ulang|dry|formant|alami|tidakBersuara|[pakai|semiton|level|pan|tundaMd] x 3" (mode sd) -> "SUKSES"
//    pt_buka        : ... b = "tone" untuk mode Bass & Treble / Ekualiser langsung (tanpa analisis, tanpa mesin nada)
//    pt_atur_tone   : a = "ulang|bass|treble|pita1|pita2|pita3|pita4|pita5" (persen 0..100, 50 = netral) -> "SUKSES"
//                     (mode tone: berubah seketika saat diputar; filter berjalan di C++ bila nadivoice >= 11, kalau tidak di Java)
//    pt_buka        : ... b = "gate" untuk mode Pengurang Kebisingan langsung
//    pt_atur_gate   : a = "ulang|sensitivitas%|attackMd|releaseMd" -> "SUKSES" (berubah seketika; C++ bila nadivoice >= 12, kalau tidak Java)
//    pt_buka        : ... b = "autotune" untuk mode AutoTune langsung (mono)
//    pt_atur_autotune : a = "ulang|kunci 0..11|tangga nada 0..2|kecepatan 1..100" -> "SUKSES" (C++ bila nadivoice >= 14, kalau tidak Java)
//    pt_buka        : ... b = "reverb" atau "echo" untuk mode Reverb / Echo langsung (mono)
//    pt_atur_fx     : a = "ulang|p1|p2|..." reverb: ruangan|peredam|asli|gema (pecahan 0..1);
//                     echo: jarakMd|ekor|peredam|asli|pantulan (pecahan 0..1) -> "SUKSES" (C++ bila nadivoice >= 13, kalau tidak Java)
//    pt_atur        : a = "lanjut|ulang|bertahap|nada|awal|akhir|lama"  (1/0, angka titik)     -> "SUKSES"
//    pt_main        : a = awal md (<0 = lanjut dari posisi terakhir)                          -> "SUKSES"
//    pt_cari        : a = posisi md                                                           -> "SUKSES"
//    pt_henti       : berhenti dengan memudar (posisi diingat)
//    pt_status      : -> "lanjut|persen|posMd|jalan|durMd|mesin|selesai|pesan"
//    pt_lepas       : melepas sesi dan memori
//  pt_siapkan dan pt_siapkan_raw tidak memakai keadaan statis (boleh lewat rapikanAsync).
// =============================================================================
private static final int PT_BLOK = 512;
private static final Object ptKunci = new Object();
private static PtSesi ptSesi = null;

private static final class PtSesi {
    final String raw;
    final long totalFr;
    volatile boolean batal = false;
    volatile boolean lanjut = false;
    volatile boolean ulang = false;
    volatile boolean glOn = false;
    volatile float val = 0f, g0 = 0f, g1 = 0f, gd = 0f;
    volatile boolean hidup = false;
    volatile boolean henti = false;
    volatile boolean selesai = false;
    volatile long posFr = 0;
    volatile long seekFr = -1;
    volatile int mesin = 0;               // 0 = biasa, 1 = tingkat lanjut (yang sedang dipakai)
    volatile String galat = "";
    Thread th = null;
    long h = 0;                           // pegangan mesin nada langsung
    volatile String lj = "mati";          // mati, analisis, siap, galat
    volatile String ljPesan = "";
    boolean analisisJalan = false;
    int mainHidup = 0;
    int nk = 0, khop = 0;
    float[] kontur = null;
    volatile boolean konturKotor = true;
    volatile boolean sd = false;          // mode Suara Dua (bukan nada)
    volatile boolean stereo = false;      // keluaran stereo (hanya mode sd)
    volatile float[] sdp = new float[19];
    volatile boolean sdKotor = true;
    volatile boolean tone = false;        // mode Bass & Treble / Ekualiser langsung (bukan nada, bukan sd)
    volatile float[] toneP = {50f, 50f, 50f, 50f, 50f, 50f, 50f};   // bass, treble, pita 1..5 (persen)
    volatile boolean toneKotor = true;
    volatile boolean gate = false;        // mode Pengurang Kebisingan langsung
    volatile float[] gateP = {0f, 5f, 150f};   // sensitivitas %, attack md, release md
    volatile int fxJenis = 0;                  // 0 bukan, 1 reverb langsung, 2 echo langsung
    volatile float[] fxP = {0.5f, 0.5f, 0.7f, 0.3f, 0f};
    volatile boolean atLive = false;           // mode AutoTune langsung
    volatile float[] atP = {0f, 0f, 80f};      // kunci 0..11, tangga nada 0..2, kecepatan %
    PtSesi(String raw, long totalFr) { this.raw = raw; this.totalFr = totalFr; }
}

// Dipanggil di dalam ptKunci. Melepas memori mesin hanya bila tidak ada thread yang memakainya.
private static void ptLepasJikaPerlu(PtSesi s) {
    if (s.batal && !s.analisisJalan && s.mainHidup == 0 && s.h != 0) {
        long h = s.h;
        s.h = 0;
        try { nvLiveLepas(h); } catch (Throwable ignored) {}
    }
}

private static void ptLepas() {
    synchronized (ptKunci) {
        PtSesi s = ptSesi;
        ptSesi = null;
        if (s == null) return;
        s.batal = true;
        s.henti = true;
        if (s.h != 0 && s.analisisJalan) { try { nvLiveBatal(s.h); } catch (Throwable ignored) {} }
        ptLepasJikaPerlu(s);
    }
}

private static String ptDispatch(String cmd, String a, String b, String c, String d) {
    try {
        if ("pt_siapkan".equals(cmd)) return ptSiapkan(a, b, c);
        if ("pt_siapkan_raw".equals(cmd)) return ptSiapkanRaw(a, b, c, d);
        if ("pt_buka".equals(cmd)) return ptBuka(a, b, c);
        if ("pt_atur_sd".equals(cmd)) return ptAturSd(a);
        if ("pt_atur_tone".equals(cmd)) return ptAturTone(a);
        if ("pt_atur_gate".equals(cmd)) return ptAturGate(a);
        if ("pt_atur_autotune".equals(cmd)) return ptAturAutotune(a);
        if ("pt_atur_fx".equals(cmd)) return ptAturFx(a);
        if ("pt_atur".equals(cmd)) return ptAtur(a);
        if ("pt_main".equals(cmd)) return ptMain((long) Double.parseDouble(a.trim()));
        if ("pt_cari".equals(cmd)) return ptCari((long) Double.parseDouble(a.trim()));
        if ("pt_henti".equals(cmd)) {
            synchronized (ptKunci) { PtSesi s = ptSesi; if (s != null) s.henti = true; }
            return "SUKSES";
        }
        if ("pt_status".equals(cmd)) return ptStatus();
        if ("pt_lepas".equals(cmd)) { ptLepas(); return "SUKSES"; }
        return "GAGAL: perintah tidak dikenal";
    } catch (Throwable t) {
        return "GAGAL: " + (t.getMessage() == null ? t.toString() : t.getMessage());
    }
}

private static String ptSiapkan(String audio, String kerja, String klip) throws Exception {
    if (audio != null && !audio.startsWith("/")) audio = "/" + audio;
    File dir = new File(kerja);
    dir.mkdirs();
    File raw = new File(dir, "nada_pt.raw");
    if (raw.exists()) raw.delete();
    String r = decodeToPCM(audio, raw.getAbsolutePath(), RP_SR, 1, 0);
    if (!"SUKSES".equals(r)) return "GAGAL: " + r;
    return ptPangkas(raw, klip);
}

// Memangkas berkas mono 44100 ke rentang "awalMd,akhirMd" (akhir <= 0 = sampai habis).
private static String ptPangkas(File raw, String klip) throws Exception {
    long awalMs = 0L, akhirMs = 0L;
    if (klip != null && klip.indexOf(',') > 0) {
        String[] q = klip.split(",");
        awalMs = (long) Double.parseDouble(q[0].trim());
        akhirMs = (long) Double.parseDouble(q[1].trim());
    }
    long totalFr = raw.length() / 2L;
    long a = Math.max(0L, awalMs * RP_SR / 1000L);
    long e = (akhirMs > 0L) ? Math.min(totalFr, akhirMs * RP_SR / 1000L) : totalFr;
    if (a > 0L || e < totalFr) {
        if (e - a < 4096L) return "GAGAL: bagian audio terlalu pendek";
        File tmp = new File(raw.getAbsolutePath() + ".pangkas");
        RandomAccessFile in = new RandomAccessFile(raw, "r");
        FileOutputStream out = new FileOutputStream(tmp);
        try {
            in.seek(a * 2L);
            byte[] buf = new byte[65536];
            long sisa = (e - a) * 2L;
            while (sisa > 0L) {
                int rd = in.read(buf, 0, (int) Math.min((long) buf.length, sisa));
                if (rd <= 0) break;
                out.write(buf, 0, rd);
                sisa -= rd;
            }
        } finally {
            try { in.close(); } catch (Throwable ignored) {}
            try { out.close(); } catch (Throwable ignored) {}
        }
        raw.delete();
        if (!tmp.renameTo(raw)) return "GAGAL: gagal memangkas audio";
    }
    long n = raw.length() / 2L;
    if (n < 4096L) return "GAGAL: audio terlalu pendek";
    return "SUKSES:" + (n * 1000L / RP_SR);
}

// Mengubah PCM 16-bit mentah (sample rate dan channel apa saja) menjadi mono 44100.
private static String ptSiapkanRaw(String rawIn, String kerja, String srS, String chS) throws Exception {
    int sr = Integer.parseInt(srS.trim());
    int ch = Math.max(1, Integer.parseInt(chS.trim()));
    File fin = new File(rawIn);
    if (!fin.exists()) return "GAGAL: rekaman contoh tidak ada";
    if (sr < 4000) return "GAGAL: sample rate tidak dikenal";
    File dir = new File(kerja);
    dir.mkdirs();
    File raw = new File(dir, "nada_pt.raw");
    if (raw.exists()) raw.delete();
    long frIn = fin.length() / (2L * ch);
    if (frIn < 2L) return "GAGAL: rekaman contoh kosong";
    double langkah = (double) sr / (double) RP_SR;          // bingkai masukan per bingkai keluaran
    long totalOut = (long) Math.floor((double) (frIn - 1L) / langkah) + 1L;
    FileInputStream fi = new FileInputStream(fin);
    BufferedOutputStream fo = new BufferedOutputStream(new FileOutputStream(raw), 65536);
    try {
        final int CH_FR = 32768;
        byte[] bb = new byte[CH_FR * 2 * ch];
        short[] ext = new short[CH_FR + 1];
        long g0 = 0L;                                       // indeks bingkai pertama pada potongan ini
        long next = 0L;                                     // indeks keluaran berikutnya
        short carry = 0;
        while (g0 < frIn) {
            int want = (int) Math.min((long) CH_FR, frIn - g0);
            int need = want * 2 * ch;
            int got = 0;
            while (got < need) {
                int rd = fi.read(bb, got, need - got);
                if (rd <= 0) break;
                got += rd;
            }
            int m = got / (2 * ch);
            if (m <= 0) break;
            ext[0] = carry;
            for (int i = 0; i < m; i++) {
                int sum = 0;
                for (int c = 0; c < ch; c++) {
                    int p = (i * ch + c) * 2;
                    sum += (short) ((bb[p] & 0xFF) | (bb[p + 1] << 8));
                }
                ext[i + 1] = (short) (sum / ch);
            }
            long akhirBingkai = g0 + m - 1L;
            while (next < totalOut) {
                double src = (double) next * langkah;
                long idx = (long) Math.floor(src);
                if (idx + 1L > akhirBingkai) break;
                double fr = src - (double) idx;
                double v0 = ext[(int) (idx - g0 + 1L)];
                double v1 = ext[(int) (idx - g0 + 2L)];
                int v = (int) Math.round(v0 + (v1 - v0) * fr);
                if (v > 32767) v = 32767; else if (v < -32768) v = -32768;
                fo.write(v & 0xFF);
                fo.write((v >> 8) & 0xFF);
                next++;
            }
            carry = ext[m];
            g0 += m;
            if (m < want) break;
        }
        while (next < totalOut) {                           // sisa di ujung: ulangi sampel terakhir
            int v = carry;
            fo.write(v & 0xFF);
            fo.write((v >> 8) & 0xFF);
            next++;
        }
    } finally {
        try { fi.close(); } catch (Throwable ignored) {}
        try { fo.close(); } catch (Throwable ignored) {}
    }
    long n = raw.length() / 2L;
    if (n < 4096L) return "GAGAL: rekaman contoh terlalu pendek";
    return "SUKSES:" + (n * 1000L / RP_SR);
}

private static String ptBuka(String kerja, String mode, String stereo) {
    File raw = new File(kerja, "nada_pt.raw");
    if (!raw.exists()) return "GAGAL: audio belum disiapkan";
    long n = raw.length() / 2L;
    if (n < 4096L) return "GAGAL: audio terlalu pendek";
    ptLepas();
    PtSesi s = new PtSesi(raw.getAbsolutePath(), n);
    s.sd = "sd".equals(mode == null ? "" : mode.trim());
    s.stereo = s.sd && "1".equals(stereo == null ? "" : stereo.trim());
    s.tone = "tone".equals(mode == null ? "" : mode.trim());
    s.gate = "gate".equals(mode == null ? "" : mode.trim());
    s.atLive = "autotune".equals(mode == null ? "" : mode.trim());
    s.fxJenis = "reverb".equals(mode == null ? "" : mode.trim()) ? 1 : ("echo".equals(mode == null ? "" : mode.trim()) ? 2 : 0);
    s.sdp[0] = 1f;
    s.sdp[3] = 0.6f;
    synchronized (ptKunci) { ptSesi = s; }
    return "SUKSES:" + (n * 1000L / RP_SR);
}

private static float ptAngka(String t) {
    try { return Float.parseFloat(t.trim().replace(',', '.')); } catch (Throwable e) { return 0f; }
}

private static String ptAtur(String a) {
    String[] q = (a == null ? "" : a).split("\\|");
    if (q.length < 7) return "GAGAL: pengaturan tidak lengkap";
    synchronized (ptKunci) {
        PtSesi s = ptSesi;
        if (s == null || s.batal) return "GAGAL: belum dibuka";
        s.val = ptAngka(q[3]);
        s.g0 = ptAngka(q[4]);
        s.g1 = ptAngka(q[5]);
        s.gd = ptAngka(q[6]);
        s.glOn = "1".equals(q[2].trim());
        s.ulang = "1".equals(q[1].trim());
        s.konturKotor = true;
        boolean lanjutBaru = "1".equals(q[0].trim());
        s.lanjut = lanjutBaru;
        if (lanjutBaru) ptMulaiAnalisis(s);
    }
    return "SUKSES";
}

private static String ptAturSd(String a) {
    String[] q = (a == null ? "" : a).split("\\|");
    if (q.length < 20) return "GAGAL: pengaturan tidak lengkap";
    synchronized (ptKunci) {
        PtSesi s = ptSesi;
        if (s == null || s.batal || !s.sd) return "GAGAL: belum dibuka";
        float[] p = new float[19];
        for (int i = 0; i < 19; i++) p[i] = ptAngka(q[i + 1]);
        s.sdp = p;
        s.ulang = "1".equals(q[0].trim());
        s.sdKotor = true;
        ptMulaiAnalisis(s);
    }
    return "SUKSES";
}

private static String ptAturFx(String a) {
    String[] q = (a == null ? "" : a).split("\\|");
    synchronized (ptKunci) {
        PtSesi s = ptSesi;
        if (s == null || s.batal || s.fxJenis == 0) return "GAGAL: belum dibuka";
        int perlu = (s.fxJenis == 1) ? 4 : 5;
        if (q.length < perlu + 1) return "GAGAL: pengaturan tidak lengkap";
        float[] p = new float[5];
        for (int i = 0; i < perlu; i++) p[i] = ptAngka(q[i + 1]);
        s.fxP = p;
        s.ulang = "1".equals(q[0].trim());
        s.toneKotor = true;
    }
    return "SUKSES";
}

private static String ptAturAutotune(String a) {
    String[] q = (a == null ? "" : a).split("\\|");
    if (q.length < 4) return "GAGAL: pengaturan tidak lengkap";
    synchronized (ptKunci) {
        PtSesi s = ptSesi;
        if (s == null || s.batal || !s.atLive) return "GAGAL: belum dibuka";
        float k = ptAngka(q[1]);
        float sc = ptAngka(q[2]);
        float sp = ptAngka(q[3]);
        if (sc < 0f) sc = 0f; else if (sc > 2f) sc = 2f;
        if (sp < 1f) sp = 1f; else if (sp > 100f) sp = 100f;
        s.atP = new float[]{k, sc, sp};
        s.ulang = "1".equals(q[0].trim());
        s.toneKotor = true;
    }
    return "SUKSES";
}

private static String ptAturGate(String a) {
    String[] q = (a == null ? "" : a).split("\\|");
    if (q.length < 4) return "GAGAL: pengaturan tidak lengkap";
    synchronized (ptKunci) {
        PtSesi s = ptSesi;
        if (s == null || s.batal || !s.gate) return "GAGAL: belum dibuka";
        float pct = ptAngka(q[1]);
        if (pct < 0f) pct = 0f; else if (pct > 100f) pct = 100f;
        s.gateP = new float[]{pct, ptAngka(q[2]), ptAngka(q[3])};
        s.ulang = "1".equals(q[0].trim());
        s.toneKotor = true;
    }
    return "SUKSES";
}

private static String ptAturTone(String a) {
    String[] q = (a == null ? "" : a).split("\\|");
    if (q.length < 8) return "GAGAL: pengaturan tidak lengkap";
    synchronized (ptKunci) {
        PtSesi s = ptSesi;
        if (s == null || s.batal || !s.tone) return "GAGAL: belum dibuka";
        float[] p = new float[7];
        for (int i = 0; i < 7; i++) {
            float v = ptAngka(q[i + 1]);
            if (v < 0f) v = 0f; else if (v > 100f) v = 100f;
            p[i] = v;
        }
        s.toneP = p;
        s.ulang = "1".equals(q[0].trim());
        s.toneKotor = true;
    }
    return "SUKSES";
}

// Dipanggil di dalam ptKunci.
private static void ptMulaiAnalisis(final PtSesi s) {
    if (!"mati".equals(s.lj)) return;
    if (s.totalFr > (long) RP_SR * 900L) {
        s.lj = "galat";
        s.ljPesan = "Audio lebih panjang dari 15 menit";
        return;
    }
    boolean siapMesin = false;
    boolean mesinAda = false;
    try { mesinAda = muatNativeSuaraDua(); siapMesin = mesinAda && nadiVer >= (s.sd ? 10 : 9); } catch (Throwable ignored) { siapMesin = false; }
    if (!siapMesin) {
        s.lj = "galat";
        s.ljPesan = (mesinAda && s.sd) ? "Mesin pengubah suara perlu diperbarui ke versi 10" : "Mesin pengubah suara belum siap";
        return;
    }
    s.lj = "analisis";
    s.analisisJalan = true;
    Thread t = new Thread(new Runnable() {
        public void run() { ptAnalisisKerja(s); }
    }, "NadiPtAnalisis");
    t.setDaemon(true);
    t.start();
}

private static void ptAnalisisKerja(PtSesi s) {
    try {
        byte[] jp = s.raw.getBytes("UTF-8");
        long h = nvLiveBuat(jp, RP_SR);
        synchronized (ptKunci) {
            if (h == 0L) { s.ljPesan = "Audio tidak bisa dimuat ke mesin"; s.lj = "galat"; return; }
            s.h = h;
            if (s.batal) return;
        }
        int ok = nvLiveAnalisis(h);
        synchronized (ptKunci) {
            if (s.batal) return;
            if (ok != 1) { s.ljPesan = "Analisis nada gagal"; s.lj = "galat"; return; }
            int n = nvLiveInfo(h, 0);
            s.khop = nvLiveInfo(h, 1);
            s.nk = nvLiveInfo(h, 2);
            if (n <= 0 || s.nk <= 0 || s.khop != RP_KHOP) { s.ljPesan = "Mesin tidak cocok"; s.lj = "galat"; return; }
            s.kontur = new float[s.nk];
            s.konturKotor = true;
            s.lj = "siap";
        }
    } catch (Throwable t) {
        s.ljPesan = "" + (t.getMessage() == null ? t.toString() : t.getMessage());
        s.lj = "galat";
    } finally {
        synchronized (ptKunci) {
            s.analisisJalan = false;
            ptLepasJikaPerlu(s);
        }
    }
}

private static int ptProgres(PtSesi s) {
    if ("siap".equals(s.lj)) return 100;
    if (!"analisis".equals(s.lj)) return 0;
    if (s.h == 0L || s.batal) return 0;
    try { return nvLiveProgres(s.h); } catch (Throwable t) { return 0; }
}

private static long ptMsKeFr(long ms, PtSesi s) {
    long fr = ms * RP_SR / 1000L;
    if (fr < 0L) fr = 0L;
    if (fr > s.totalFr - 1L) fr = s.totalFr - 1L;
    return fr;
}

private static String ptMain(long awalMs) {
    PtSesi s;
    Thread lama;
    synchronized (ptKunci) {
        s = ptSesi;
        if (s == null || s.batal) return "GAGAL: belum dibuka";
        lama = s.th;
    }
    if (lama != null && lama.isAlive() && s.henti) {
        try { lama.join(800); } catch (InterruptedException ignored) {}
    }
    final PtSesi sf = s;
    synchronized (ptKunci) {
        if (ptSesi != sf || sf.batal) return "GAGAL: sesi sudah ditutup";
        if (sf.hidup && !sf.henti) {
            if (awalMs >= 0L) sf.seekFr = ptMsKeFr(awalMs, sf);
            return "SUKSES";
        }
        if (sf.hidup) return "GAGAL: pemutar masih berhenti, coba lagi";
        long fr = (awalMs < 0L) ? sf.posFr : ptMsKeFr(awalMs, sf);
        if (fr >= sf.totalFr - 2048L) fr = 0L;
        sf.posFr = fr;
        sf.seekFr = -1L;
        sf.henti = false;
        sf.selesai = false;
        sf.galat = "";
        sf.hidup = true;
        sf.mainHidup++;
        Thread t = new Thread(new Runnable() {
            public void run() { ptPutar(sf); }
        }, "NadiPtPutar");
        sf.th = t;
        t.setDaemon(true);
        t.start();
    }
    return "SUKSES";
}

private static String ptCari(long posMs) {
    synchronized (ptKunci) {
        PtSesi s = ptSesi;
        if (s == null || s.batal) return "GAGAL: belum dibuka";
        long fr = ptMsKeFr(posMs, s);
        if (s.hidup && !s.henti) s.seekFr = fr; else s.posFr = fr;
    }
    return "SUKSES";
}

private static String ptStatus() {
    synchronized (ptKunci) {
        PtSesi s = ptSesi;
        if (s == null) return "mati|0|0|0|0|0|0|";
        String pesan = (s.galat != null && !s.galat.isEmpty()) ? s.galat : s.ljPesan;
        if (pesan == null) pesan = "";
        return s.lj + "|" + ptProgres(s) + "|" + (s.posFr * 1000L / RP_SR) + "|" + ((s.hidup && !s.henti) ? 1 : 0)
            + "|" + (s.totalFr * 1000L / RP_SR) + "|" + s.mesin + "|" + (s.selesai ? 1 : 0) + "|" + pesan.replace('|', ' ');
    }
}

// Mengisi kontur (semiton per bingkai) dari pengaturan nada. Dipanggil di thread pemutar.
private static void ptIsiKontur(PtSesi s) {
    float[] k = s.kontur;
    if (k == null || s.h == 0L) return;
    final boolean gl = s.glOn;
    final float v = s.val, g0 = s.g0, g1 = s.g1, gd = s.gd;
    for (int f = 0; f < s.nk; f++) {
        long fr = (long) f * (long) s.khop;
        k[f] = semitonGeser(gl, v, g0, g1, gd, fr, s.totalFr, RP_SR);
    }
    nvLiveKontur(s.h, k, s.nk);
}

private static void ptPudar(short[] b, int n, int dari, int total) {
    // dari = jumlah bingkai fade-in yang sudah dilewati sebelum blok ini; total = panjang fade-in
    for (int i = 0; i < n; i++) {
        int pos = dari + i;
        if (pos >= total) break;
        b[i] = (short) (b[i] * ((pos + 1) / (float) total));
    }
}

// Satu thread pemutar untuk semua mesin. AudioTrack mengalir, ditulis blok demi blok.
//   mode nada : mesin 0 = Sonic, mesin 1 = mesin nada langsung (tingkat lanjut)
//   mode sd   : mesin 0 = suara asli saja (selama analisis), mesin 1 = mesin Suara Dua langsung
private static void ptPutar(final PtSesi s) {
    android.media.AudioTrack at = null;
    RandomAccessFile raf = null;
    PcmFx tl = null;                    // hanya mode tone / gate: efek langsung pada suara asli
    try {
        try { android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO); } catch (Throwable ignored) {}
        final boolean sdMode = s.sd;
        final boolean toneMode = (s.tone || s.gate || s.fxJenis != 0 || s.atLive) && !s.sd;   // mode efek langsung (Bass & Treble / Ekualiser / Noise Gate)
        final int CHO = (sdMode && s.stereo) ? 2 : 1;
        int minBuf = android.media.AudioTrack.getMinBufferSize(RP_SR, CHO == 2 ? 12 : 4, 2 /* PCM 16 */);
        int bufBytes = Math.max(minBuf, PT_BLOK * 2 * CHO * 3);
        at = new android.media.AudioTrack(3 /* STREAM_MUSIC */, RP_SR, CHO == 2 ? 12 : 4, 2, bufBytes, android.media.AudioTrack.MODE_STREAM);
        if (at.getState() != android.media.AudioTrack.STATE_INITIALIZED) throw new Exception("pemutar suara tidak bisa dibuka");
        raf = new RandomAccessFile(s.raw, "r");
        final long total = s.totalFr;
        final int FADE = 256;
        byte[] inB = new byte[PT_BLOK * 2];
        short[] inS = new short[PT_BLOK];
        short[] blk = new short[PT_BLOK * 4];
        byte[] ljB = new byte[PT_BLOK * 2 * 2];
        Sonic sonic = null;
        if (toneMode) tl = s.atLive ? new AutoTuneLive(RP_SR) : (s.gate ? new GateLive(RP_SR, 1) : (s.fxJenis != 0 ? new FxLive(s.fxJenis, RP_SR) : new ToneLive(RP_SR, 1)));
        long pos = s.posFr;
        long basePos = pos;
        long ditulis = 0L;
        long headDasar = liveHead(at);
        int mesin = -1;
        int fadeSudah = 0;          // bingkai fade-in yang sudah lewat (FADE = tidak sedang fade-in)
        boolean selesaiFile = false;
        at.play();
        while (true) {
            if (s.batal || s.henti) break;
            long sk = s.seekFr;
            if (sk >= 0L) {
                s.seekFr = -1L;
                pos = Math.max(0L, Math.min(sk, total - 1L));
                basePos = pos;
                mesin = -1;
                try { at.pause(); } catch (Throwable ignored) {}
                at.flush();
                headDasar = liveHead(at);
                ditulis = 0L;
                at.play();
                fadeSudah = 0;
            }
            if (pos >= total) {
                if (s.ulang) {
                    pos = 0L;
                    basePos = 0L;
                    mesin = -1;
                    fadeSudah = 0;
                    ditulis = 0L;
                    try { at.pause(); } catch (Throwable ignored) {}
                    at.flush();
                    headDasar = liveHead(at);
                    at.play();
                } else {
                    selesaiFile = true;
                    break;
                }
            }
            // Memilih mesin: mesin langsung hanya bila analisis sudah selesai (mode nada: DAN diminta tingkat lanjut).
            int mau = (!toneMode && (sdMode || s.lanjut) && "siap".equals(s.lj) && s.h != 0L) ? 1 : 0;
            if (mau != mesin) {
                if (mau == 1) {
                    int ok = sdMode ? nvSdMulai(s.h, pos) : nvLiveMulai(s.h, pos);
                    if (ok != 1) {
                        mau = 0;
                        s.ljPesan = sdMode ? "Mesin Suara Dua gagal dimulai" : "Mesin tingkat lanjut gagal dimulai";
                        s.lj = "galat";
                    } else if (sdMode) {
                        s.sdKotor = true;
                    }
                }
                if (mau == 0) {
                    if (!sdMode && !toneMode) sonic = new Sonic(RP_SR, 1);
                    raf.seek(pos * 2L);
                    if (toneMode) tl.reset();      // posisi baru: buang sisa keadaan filter
                }
                mesin = mau;
                s.mesin = mau;
                fadeSudah = 0;
            }
            if (mesin == 1 && sdMode) {
                if (s.sdKotor) { s.sdKotor = false; nvSdAtur(s.h, s.sdp, 19); }
                int N = (int) Math.min((long) PT_BLOK, total - pos);
                int r = nvSdRender(s.h, ljB, N, CHO, 0);
                if (r <= 0) throw new Exception("mesin gagal membuat suara (" + r + ")");
                at.write(ljB, 0, r * CHO * 2);
                pos += r;
                ditulis += r;
                fadeSudah = FADE;
            } else if (mesin == 1) {
                if (s.konturKotor) { s.konturKotor = false; ptIsiKontur(s); }
                int N = (int) Math.min((long) PT_BLOK, total - pos);
                int r = nvLiveRender(s.h, ljB, N, 0);
                if (r <= 0) throw new Exception("mesin gagal membuat suara (" + r + ")");
                for (int i = 0; i < r; i++) blk[i] = (short) ((ljB[i * 2] & 0xFF) | (ljB[i * 2 + 1] << 8));
                pos += r;
                if (fadeSudah < FADE) { ptPudar(blk, r, fadeSudah, FADE); fadeSudah += r; }
                at.write(blk, 0, r);
                ditulis += r;
            } else if (toneMode) {
                // Bass & Treble / Ekualiser langsung: bacaan mentah, lalu filter. Nilai baru dipasang tiap blok.
                if (s.toneKotor) { s.toneKotor = false; tl.atur(s.atLive ? s.atP : (s.gate ? s.gateP : (s.fxJenis != 0 ? s.fxP : s.toneP))); }
                int N = (int) Math.min((long) PT_BLOK, total - pos);
                raf.readFully(inB, 0, N * 2);
                tl.proses(inB, N);
                for (int i = 0; i < N; i++) inS[i] = (short) ((inB[i * 2] & 0xFF) | (inB[i * 2 + 1] << 8));
                if (fadeSudah < FADE) { ptPudar(inS, N, fadeSudah, FADE); fadeSudah += N; }
                at.write(inS, 0, N);
                pos += N;
                ditulis += N;
            } else if (sdMode) {
                // analisis belum selesai (atau gagal): suara asli saja, dengan volume suara asli
                int N = (int) Math.min((long) PT_BLOK, total - pos);
                raf.readFully(inB, 0, N * 2);
                float g = s.sdp[0];
                for (int i = 0; i < N; i++) {
                    int v = Math.round(((short) ((inB[i * 2] & 0xFF) | (inB[i * 2 + 1] << 8))) * g);
                    inS[i] = (short) (v > 32767 ? 32767 : (v < -32768 ? -32768 : v));
                }
                if (fadeSudah < FADE) { ptPudar(inS, N, fadeSudah, FADE); fadeSudah += N; }
                for (int i = 0; i < N; i++) { blk[i * CHO] = inS[i]; if (CHO == 2) blk[i * 2 + 1] = inS[i]; }
                at.write(blk, 0, N * CHO);
                pos += N;
                ditulis += N;
            } else {
                float semi = semitonGeser(s.glOn, s.val, s.g0, s.g1, s.gd, pos, total, RP_SR);
                if (semi > 12f) semi = 12f; else if (semi < -12f) semi = -12f;
                sonic.setPitch((float) Math.pow(2.0, semi / 12.0));
                int N = (int) Math.min((long) PT_BLOK, total - pos);
                raf.readFully(inB, 0, N * 2);
                for (int i = 0; i < N; i++) inS[i] = (short) ((inB[i * 2] & 0xFF) | (inB[i * 2 + 1] << 8));
                sonic.putSamples(inS, N);
                pos += N;
                if (pos >= total && !s.ulang) sonic.flush();
                int got;
                while ((got = sonic.receiveSamples(blk, blk.length)) > 0) {
                    if (fadeSudah < FADE) { ptPudar(blk, got, fadeSudah, FADE); fadeSudah += got; }
                    at.write(blk, 0, got);
                    ditulis += got;
                }
            }
            long dimain = liveHead(at) - headDasar;
            if (dimain < 0L) dimain = 0L;
            if (dimain > ditulis) dimain = ditulis;
            long p = basePos + dimain;
            s.posFr = Math.min(p, total);
        }
        if (selesaiFile) {
            at.stop();
            long mulaiTunggu = System.currentTimeMillis();
            long batas = (ditulis - (liveHead(at) - headDasar)) * 1000L / RP_SR + 400L;
            while (System.currentTimeMillis() - mulaiTunggu < batas && !s.batal && s.seekFr < 0L) {
                if (liveHead(at) - headDasar >= ditulis) break;
                try { Thread.sleep(5); } catch (InterruptedException e) { break; }
            }
            if (!s.batal) { s.posFr = total; s.selesai = true; }
        } else {
            // berhenti dengan memudar supaya tidak berdetak
            try {
                if (mesin == 1 && s.h != 0L && !s.batal) {
                    if (sdMode) {
                        int r = nvSdRender(s.h, ljB, PT_BLOK, CHO, 1);
                        if (r > 0) at.write(ljB, 0, r * CHO * 2);
                    } else {
                        int r = nvLiveRender(s.h, ljB, PT_BLOK, 1);
                        if (r > 0) at.write(ljB, 0, r * 2);
                    }
                } else if (toneMode) {
                    int N = (int) Math.min((long) PT_BLOK, total - pos);
                    if (N > 0) {
                        raf.readFully(inB, 0, N * 2);
                        tl.proses(inB, N);
                        for (int i = 0; i < N; i++) {
                            int v = Math.round(((short) ((inB[i * 2] & 0xFF) | (inB[i * 2 + 1] << 8))) * (1f - (i + 1) / (float) N));
                            blk[i] = (short) v;
                        }
                        at.write(blk, 0, N);
                        ditulis += N;
                    }
                } else if (sdMode) {
                    int N = (int) Math.min((long) PT_BLOK, total - pos);
                    if (N > 0) {
                        raf.readFully(inB, 0, N * 2);
                        float g = s.sdp[0];
                        for (int i = 0; i < N; i++) {
                            int v = Math.round(((short) ((inB[i * 2] & 0xFF) | (inB[i * 2 + 1] << 8))) * g * (1f - (i + 1) / (float) N));
                            short sv = (short) (v > 32767 ? 32767 : (v < -32768 ? -32768 : v));
                            blk[i * CHO] = sv;
                            if (CHO == 2) blk[i * 2 + 1] = sv;
                        }
                        at.write(blk, 0, N * CHO);
                        ditulis += N;
                    }
                } else if (sonic != null) {
                    int N = (int) Math.min((long) PT_BLOK, total - pos);
                    if (N > 0) {
                        raf.readFully(inB, 0, N * 2);
                        for (int i = 0; i < N; i++) inS[i] = (short) ((inB[i * 2] & 0xFF) | (inB[i * 2 + 1] << 8));
                        sonic.putSamples(inS, N);
                        int got = sonic.receiveSamples(blk, blk.length);
                        if (got > 0) {
                            for (int i = 0; i < got; i++) blk[i] = (short) (blk[i] * (1f - (i + 1) / (float) got));
                            at.write(blk, 0, got);
                            ditulis += got;
                        }
                    }
                }
            } catch (Throwable ignored) {}
            try { at.stop(); } catch (Throwable ignored) {}
            long mulaiTunggu = System.currentTimeMillis();
            while (System.currentTimeMillis() - mulaiTunggu < 150L && liveHead(at) - headDasar < ditulis) {
                try { Thread.sleep(3); } catch (InterruptedException e) { break; }
            }
        }
    } catch (Throwable t) {
        s.galat = (t.getMessage() == null ? t.toString() : t.getMessage());
        android.util.Log.w("NadiMesin", "pemutar nada real time berhenti: " + t);
    } finally {
        if (at != null) {
            try { at.stop(); } catch (Throwable ignored) {}
            try { at.release(); } catch (Throwable ignored) {}
        }
        if (raf != null) { try { raf.close(); } catch (Throwable ignored) {} }
        if (tl != null) tl.lepas();
        synchronized (ptKunci) {
            s.hidup = false;
            s.mainHidup--;
            ptLepasJikaPerlu(s);
        }
    }
}


}
