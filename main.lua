require "import"
local cjson = require "cjson"
local luajava = require("luajava")
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"
import "java.net.URL"
import "java.io.InputStreamReader"
import "java.io.BufferedReader"
import "java.util.zip.ZipOutputStream"
import "java.util.zip.ZipInputStream"
import "java.util.zip.ZipEntry"
import "java.util.ArrayList"
import "android.widget.LinearLayout"
import "android.widget.EditText"
import "android.widget.ListView"
import "android.widget.Button"
import "android.widget.ArrayAdapter"
import "android.widget.TextView"
import "android.widget.CheckBox"
import "android.text.TextWatcher"
import "com.androlua.LuaDialog"
import "com.androlua.LuaAdapter"
import "android.os.Handler"
import "android.os.Looper"
import "java.lang.Thread"
import "java.lang.Runnable"
import "android.view.accessibility.AccessibilityNodeInfo"
import "android.graphics.Rect"
import "android.media.MediaPlayer"
import "android.view.KeyEvent"
import "android.preference.PreferenceManager"
import "android.content.Intent"
import "android.content.IntentFilter"
import "android.content.BroadcastReceiver"
import "android.app.PendingIntent"
import "android.os.Build"
import "android.net.Uri"
import "android.content.Context"
import "android.content.ClipboardManager"
import "android.content.ClipData"
import "android.speech.tts.TextToSpeech"
import "android.speech.tts.UtteranceProgressListener"
import "android.widget.SeekBar"
import "android.widget.Spinner"
import "android.widget.ScrollView"
import "java.util.HashSet"
import "android.provider.Settings"
import "android.util.Base64"
import "java.io.ByteArrayOutputStream"

local pref = service.getSharedPreferences("Nadi Voice Team", 0)

local function getAlarmHours()
local arr = {}
pcall(function()
local stringSet = PreferenceManager.getDefaultSharedPreferences(service).getStringSet("alarm_hours", nil)
if stringSet then
local iter = stringSet.iterator()
while iter.hasNext() do table.insert(arr, tonumber(tostring(iter.next()))) end
end
end)
return arr
end

local function setAlarmHours(arr)
pcall(function()
local stringSet = HashSet()
for i = 1, #arr do stringSet.add(tostring(arr[i])) end
PreferenceManager.getDefaultSharedPreferences(service).edit().putStringSet("alarm_hours", stringSet).apply()
end)
end
local editor = pref.edit()

local function dapatkanString(key, defaultVal)
return pref.getString(key, defaultVal)
end

local function simpanString(key, val)
if val == "" then editor.remove(key) else editor.putString(key, val) end
editor.commit()
end

local function bacaJson(path)
local f = io.open(path, "r")
if not f then return {} end
local content = f:read("*all")
f:close()
if not content or content == "" then return {} end
local ok, data = pcall(function() return cjson.decode(content) end)
if ok and type(data) == "table" then return data else return {} end
end

local function simpanJson(path, data)
local ok, jsonStr = pcall(function() return cjson.encode(data) end)
if ok and jsonStr then
local f = io.open(path, "w")
if f then f:write(jsonStr) f:close() return true end
end
return false
end

local function DapatkanNamaUnik(folderPath, fileName)
local targetFile = File(folderPath .. "/" .. fileName)
if not targetFile.exists() then return fileName end
local name, ext = string.match(fileName, "^(.+)(%..+)$")
if not name then name = fileName; ext = "" end
local i = 1
while true do
local newName = name .. tostring(i) .. ext
if not File(folderPath .. "/" .. newName).exists() then return newName end
i = i + 1
end
end

local pathAdminJson = tostring(service.getExternalFilesDir(nil).getAbsolutePath()) .. "/daftar_admin.json"

local function simpanAdminJsonLokal(data)
local ok, jsonStr = pcall(function() return cjson.encode(data) end)
if ok and jsonStr then
local f = io.open(pathAdminJson, "w")
if f then f:write(jsonStr) f:close() return true end
end
return false
end

local function bacaAdminJsonLokal()
local f = io.open(pathAdminJson, "r")
if not f then
local dataBawaan = {
versi_tanggal = "",
admin_utama = {
["0fef1416c68c6769"] = "Nanda",
["0c3454d593fb8a16"] = "Dian Resya Putri"
},
admin_kedua = {
["2cae55449afe4e0a"] = "Tegar"
},
admin_ketiga = {},
daftar_ampunan = {}
}
simpanAdminJsonLokal(dataBawaan)
return dataBawaan
end
local content = f:read("*all")
f:close()
local ok, data = pcall(function() return cjson.decode(content) end)
if ok and type(data) == "table" then
data.admin_utama = data.admin_utama or {}
data.admin_kedua = data.admin_kedua or {}
data.admin_ketiga = data.admin_ketiga or {}
data.daftar_ampunan = data.daftar_ampunan or {}
return data
else
return {admin_utama={}, admin_kedua={}, admin_ketiga={}, daftar_ampunan={}}
end
end

local DataAdminGlobal = bacaAdminJsonLokal()

local function SalinFile(srcPath, dstPath)
pcall(function()
local fis = FileInputStream(srcPath)
local fos = FileOutputStream(dstPath)
local buffer = byte[8192]
local length = fis.read(buffer)
while length > 0 do
pcall(function() java.lang.Thread.sleep(2) end)
fos.write(buffer, 0, length)
length = fis.read(buffer)
end
fis.close()
fos.close()
end)
end

local function EkstrakSPK(zipPath, destDir)
pcall(function()
local fis = FileInputStream(zipPath)
local zis = ZipInputStream(fis)
local entry = zis.getNextEntry()
local buffer = byte[8192]
while entry do
local fileName = entry.getName()
local newFile = File(destDir, fileName)
-- Keamanan: lewati entry yang keluar dari folder tujuan (zip-slip, mis. ../)
local entryAman = false
pcall(function()
local basePathAman = tostring(File(destDir).getCanonicalPath())
local targetAman = tostring(newFile.getCanonicalPath())
entryAman = (targetAman == basePathAman) or (targetAman:sub(1, #basePathAman + 1) == basePathAman .. "/")
end)
if not entryAman then
-- entry berbahaya dilewati
elseif entry.isDirectory() then
newFile.mkdirs()
else
newFile.getParentFile().mkdirs()
local fos = FileOutputStream(newFile)
local length = zis.read(buffer)
while length > 0 do
pcall(function() java.lang.Thread.sleep(2) end)
fos.write(buffer, 0, length)
length = zis.read(buffer)
end
fos.close()
end
zis.closeEntry()
entry = zis.getNextEntry()
end
zis.close()
fis.close()
end)
end

local function ZipRekursif(sourceFile, basePathZip, zos, buffer)
if sourceFile.isDirectory() then
local files = sourceFile.listFiles()
if files then
for i = 0, #files - 1 do
local zipName = basePathZip == "" and files[i].getName() or (basePathZip .. "/" .. files[i].getName())
ZipRekursif(files[i], zipName, zos, buffer)
end
end
else
zos.putNextEntry(ZipEntry(basePathZip))
local fis = FileInputStream(sourceFile)
local length = fis.read(buffer)
while length > 0 do
pcall(function() java.lang.Thread.sleep(2) end)
zos.write(buffer, 0, length)
length = fis.read(buffer)
end
fis.close()
zos.closeEntry()
end
end

local function UI_Layout(...)
local layout = {LinearLayout, orientation="vertical", layout_width="fill", layout_height="fill", padding="12dp"}
local args = {...}
for i=1, #args do table.insert(layout, args[i]) end
return layout
end

local function UI_Tombol(idStr, txtStr)
return {Button, id=idStr, text=txtStr, layout_width="fill", layout_marginBottom="8dp"}
end

local function UI_Tombol_H(idStr, txtStr)
return {Button, id=idStr, text=txtStr, layout_weight=1, layout_marginLeft="4dp", layout_marginRight="4dp"}
end

local function UI_Input(idStr, txtStr)
return {EditText, id=idStr, hint=txtStr, layout_width="fill", layout_marginBottom="8dp"}
end

local function UI_Daftar(idStr)
return {ListView, id=idStr, layout_width="fill", layout_weight=1}
end

local function UI_ItemBaris(idCekbox, idTeks)
return {
LinearLayout, layout_width="fill", orientation="horizontal", padding="10dp", gravity="center_vertical",
{CheckBox, id=idCekbox, focusable=false, clickable=false},
{TextView, id=idTeks, textSize="16sp", layout_marginLeft="10dp"}
}
end

local function UI_Teks(txtStr, rataTengah)
local t = {TextView, text=txtStr, textSize="16sp", layout_marginBottom="16dp"}
if rataTengah then
t.gravity = "center"
t.layout_width = "fill"
end
return t
end

local function UI_Dialog(judul)
if AksiDex and AksiDex.tangkap then return AksiDex.dialogPalsu() end
local d = LuaDialog(service)
if judul then d.setTitle(judul) end
return d
end

local folderJieshuo = string.char(232, 167, 163, 232, 175, 180)
local jieshuoPath = "/storage/emulated/0/" .. folderJieshuo
local folderSuara = dapatkanString("nama_folder_suara", "Suara")
local basePath = jieshuoPath .. "/" .. folderSuara
local backupPath = "/storage/emulated/0/.cadangan"

-- Nama kunci sidik jari BARU. Nama lama (symbiotic_key, is_banned, .sys_core_lock)
-- sengaja ditinggalkan supaya semua pengguna yang sebelumnya terkunci otomatis terbuka.
-- Ganti angka v2 menjadi v3 kalau suatu saat perlu membuka semua kunci lagi.
SIDIK = { KUNCI = "sidik_jari_v2", BLOKIR = "status_blokir_v2", BERKAS = ".sys_core_lock_v2" }

local BASE = package.searchpath("main", package.path):match(".*/")
local langDir = BASE .. "bahasa/"
File(langDir).mkdirs()

local currentLang = dapatkanString("app_language", "indonesia")
local langData = bacaJson(langDir .. currentLang .. ".json")

local PetaAudioAktif = {}
local dataEventPath = BASE .. "data_iven.json"
local mappingTema = bacaJson(dataEventPath)

local function simpanDataEvent()
simpanJson(dataEventPath, mappingTema)
end

local function T(key, defaultText)
return langData[key] or defaultText
end

-- ==========================================================================
-- KLAIM JATAH (hadiah premium sementara untuk pengguna free yang sudah mendaftar nama)
-- Tabel global agar tidak menambah jumlah variabel lokal pada skrip utama.
-- ==========================================================================
JATAH = {
-- Token TIDAK disimpan di sini. Pengguna memakai token komunitas yang sama dengan upload tema suara
-- (diambil dari token_komunitas.json), admin memakai token admin. Token itu harus punya akses
-- "Contents: Read and write" ke repo REPO di bawah. Ubah AKTIF jadi false untuk mematikan fitur ini.
AKTIF = true,
OWNER = "nandadian20083123",
REPO = "daftar-pengguna",
JEDA_HARI = 6,
PELUANG_FULL = 3,          -- persen; peluang premium penuh 3 hari
HARI_PILIHAN = {1, 3},     -- lama hadiah fitur acak
MAKS_FITUR = 3,            -- hadiah fitur acak: 1 sampai sekian fitur
KUNCI_HADIAH = "hadiah_jatah_v1",
KUNCI_NAMA = "nama_terdaftar_v1",
KUNCI_ANTRI = "nama_antri_upload_v1",
KUNCI_TANYA = "nama_ditanya_v1",
KOLAM = { "demo_instan", "edit_hapus_tak_terdaftar", "edit_hilangkan_format", "edit_nama_event", "edit_nama_kastem", "tts_jam", "pulih_otomatis", "efek_nada", "efek_echo", "efek_reverb", "upload_komunitas" },
-- Tidak pernah ikut hadiah, termasuk saat premium penuh. (Tema private sebenarnya hanya dijaga
-- pengecekan Admin Utama, jadi hadiah memang tidak menyentuhnya.)
DILARANG = { tema_private = true },
LABEL = {
demo_instan = {"label_demo_instan", "Buat Demo Instan"},
edit_hapus_tak_terdaftar = {"label_hapus_tak_terdaftar", "Hapus File Tak Terdaftar"},
edit_hilangkan_format = {"label_hilangkan_format", "Hilangkan Format"},
edit_nama_event = {"label_nama_event", "Ubah Nama Event"},
edit_nama_kastem = {"label_nama_kastem", "Ubah Nama Kastem"},
tts_jam = {"label_tts_jam", "Suara Jam (TTS)"},
pulih_otomatis = {"label_pulih_otomatis", "Pulih Otomatis"},
efek_nada = {"label_efek_nada", "Efek Naik Turun Nada"},
efek_echo = {"label_efek_echo", "Efek Echo"},
efek_reverb = {"label_efek_reverb", "Efek Reverb"},
upload_komunitas = {"label_upload_komunitas", "Upload Tema Komunitas (Publik)"}
}
}

function JATAH.label(k)
local l = JATAH.LABEL[k]
if l then return T(l[1], l[2]) end
return tostring(k)
end

function JATAH.ambil()
local s = dapatkanString(JATAH.KUNCI_HADIAH, "")
if s == "" then return nil end
local ok, d = pcall(function() return cjson.decode(s) end)
if ok and type(d) == "table" then return d end
return nil
end

function JATAH.simpan(g)
local ok, s = pcall(function() return cjson.encode(g) end)
simpanString(JATAH.KUNCI_HADIAH, (g and ok and s) or "")
end

-- Sisa detik hadiah yang masih berlaku (0 kalau tidak ada / sudah habis / jam HP diundur)
function JATAH.sisaDetik()
local g = JATAH.ambil()
if not g then return 0 end
local sekarang = os.time()
local lihat = tonumber(g.lihat) or 0
if sekarang + 3600 < lihat then
JATAH.simpan(nil)
return 0
end
local sisa = (tonumber(g.selesai) or 0) - sekarang
if sisa <= 0 then return 0 end
if sekarang - lihat > 60 then
g.lihat = sekarang
JATAH.simpan(g)
end
return sisa
end

-- Dipanggil di pemeriksaan kuota/premium: true kalau fitur ini sedang dibuka oleh hadiah
function JATAH.aktif(tipe)
if JATAH.DILARANG[tipe] then return false end
if JATAH.sisaDetik() <= 0 then return false end
local g = JATAH.ambil()
if not g then return false end
if g.tipe == "full" then return true end
for _, f in ipairs(g.fitur or {}) do
if f == tipe then return true end
end
return false
end

function JATAH.perluTombol()
if not JATAH.AKTIF then return false end
local myId = DapatkanAndroidID()
if ADMIN_IDS[myId] or ADMIN_KEDUA_IDS[myId] or ADMIN_KETIGA_IDS[myId] then return false end
return true
end

local uiHandler = Handler(Looper.getMainLooper())
local bagikanBanyakFile
do
-- ===== Bagikan Native (ganti service.shareFile agar bisa banyak file sekaligus) =====
local FileProviderClass = nil
pcall(function()
import "androidx.core.content.FileProvider"
FileProviderClass = FileProvider
end)
if not FileProviderClass then
pcall(function()
import "android.support.v4.content.FileProvider"
FileProviderClass = FileProvider
end)
end

-- CATATAN PENTING: authority di bawah ini mengikuti konvensi umum "<packageName>.fileprovider".
-- Ini WAJIB sama persis dengan authority <provider> FileProvider yang didaftarkan di AndroidManifest.xml
-- (biasanya sudah ada karena dipakai juga oleh service.shareFile bawaan). Jika nama authority berbeda,
-- sesuaikan baris fileProviderAuthority di bawah ini.
local fileProviderAuthority = service.getPackageName() .. ".fileprovider"

local function dapatkanUriBagikan(file)
local uri = nil
-- 1) Cara paling aman: helper bawaan Jieshuo/CSR (memakai FileProvider milik CSR sendiri,
--    authority com.nirenr.talkman.fileprovider, jalur sdcard_root sudah mencakup /storage/emulated/0).
pcall(function() uri = service.getUriForFile(file) end)
-- 2) FileProvider milik CSR (nama class di manifest: android.content.FileProvider,
--    metode statis hasil obfuscate: g(Context, String, File) = getUriForFile).
if not uri then
pcall(function()
import "android.content.FileProvider"
uri = FileProvider.g(service, fileProviderAuthority, file)
end)
end
-- 3) FileProvider AndroidX / support (cadangan).
if not uri and FileProviderClass then
pcall(function()
uri = FileProviderClass.getUriForFile(service, fileProviderAuthority, file)
end)
end
-- 4) Terakhir: file:// (WhatsApp biasanya menolak ini).
if not uri then
pcall(function() uri = Uri.fromFile(file) end)
end
return uri
end

local mimeZip = "application/zip"

local function buatIntentKirimSatuFile(path)
local shareIntent = Intent(Intent.ACTION_SEND)
shareIntent.setType(mimeZip)
local uri = dapatkanUriBagikan(File(path))
if uri then shareIntent.putExtra(Intent.EXTRA_STREAM, uri) end
shareIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
return shareIntent
end

-- Kirim satu file LANGSUNG ke komponen (aplikasi) tertentu, tanpa memunculkan
-- chooser lagi. Dipakai untuk melanjutkan file ke-2 dst setelah pengguna memilih
-- aplikasi tujuan sekali di awal.
local function kirimLangsungKeKomponen(komponen, path)
local shareIntent = buatIntentKirimSatuFile(path)
shareIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
shareIntent.setComponent(komponen)
pcall(function() service.startActivity(shareIntent) end)
end

local function kirimBerurutanKeKomponen(komponen, daftarPath, index)
if index > #daftarPath then return end
kirimLangsungKeKomponen(komponen, daftarPath[index])
if index < #daftarPath then
uiHandler.postDelayed(Runnable({
run = function() kirimBerurutanKeKomponen(komponen, daftarPath, index + 1) end
}), 1200)
end
end

-- Membagikan satu atau banyak file, bukan lewat service.shareFile satu-satu dan
-- bukan lewat zip gabungan besar. MIME dipaksa "application/zip" karena
-- PPK/XPK/SPK sebenarnya berformat zip, supaya aplikasi penerima (WhatsApp, dll)
-- mau menerimanya sebagai dokumen biasa.
--
-- CATATAN: WhatsApp dan banyak aplikasi lain TIDAK menerima beberapa dokumen
-- sekaligus lewat ACTION_SEND_MULTIPLE (cuma mau satu per satu) - beda dengan
-- foto/video. File manager terlihat "bisa langsung banyak" karena di baliknya dia
-- juga mengirim satu-satu. Di sini: untuk banyak file, pengguna cukup memilih
-- aplikasi tujuan SEKALI lewat kotak dialog bagikan; sisanya otomatis terkirim
-- satu-satu ke aplikasi yang sama tanpa ditanya ulang.
local function bagikanBerurutan(daftarPath)
if not daftarPath or #daftarPath == 0 then return end

if #daftarPath == 1 then
local shareIntent = buatIntentKirimSatuFile(daftarPath[1])
local chooser = Intent.createChooser(shareIntent, "Bagikan File")
chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
pcall(function() service.startActivity(chooser) end)
return
end

local shareIntentPertama = buatIntentKirimSatuFile(daftarPath[1])

local AKSI_PILIHAN = service.getPackageName() .. ".CSR_SHARE_CHOSEN"
local receiverIntent = Intent(AKSI_PILIHAN)
receiverIntent.setPackage(service.getPackageName())

local flagPending = PendingIntent.FLAG_UPDATE_CURRENT
local sdkInt = Build.VERSION.SDK_INT
if sdkInt >= 31 then
flagPending = flagPending + PendingIntent.FLAG_MUTABLE
end

local berhasilSiapkanPi, pi = pcall(function()
return PendingIntent.getBroadcast(service, 0, receiverIntent, flagPending)
end)

if not berhasilSiapkanPi or not pi then
-- Gagal siapkan mekanisme lanjut-otomatis (misal versi Android lama yang aneh):
-- tetap jalan dengan cara aman, tanya chooser tiap file.
local function kirimSatuDenganChooser(i)
if i > #daftarPath then return end
local shareIntent = buatIntentKirimSatuFile(daftarPath[i])
local chooser = Intent.createChooser(shareIntent, "Bagikan File (" .. i .. "/" .. #daftarPath .. ")")
chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
pcall(function() service.startActivity(chooser) end)
if i < #daftarPath then
uiHandler.postDelayed(Runnable({ run = function() kirimSatuDenganChooser(i + 1) end }), 1200)
end
end
kirimSatuDenganChooser(1)
return
end

local receiver = nil
receiver = BroadcastReceiver({
onReceive = function(ctx, intent)
pcall(function() service.unregisterReceiver(receiver) end)
local berhasilBaca, komponen = pcall(function()
return intent.getParcelableExtra(Intent.EXTRA_CHOSEN_COMPONENT)
end)
if berhasilBaca and komponen then
uiHandler.postDelayed(Runnable({
run = function() kirimBerurutanKeKomponen(komponen, daftarPath, 2) end
}), 500)
end
end
})

local berhasilDaftar = false
if sdkInt >= 33 then
berhasilDaftar = pcall(function()
service.registerReceiver(receiver, IntentFilter(AKSI_PILIHAN), Context.RECEIVER_NOT_EXPORTED)
end)
else
berhasilDaftar = pcall(function()
service.registerReceiver(receiver, IntentFilter(AKSI_PILIHAN))
end)
end

local chooser = Intent.createChooser(shareIntentPertama, "Bagikan " .. #daftarPath .. " File", pi.getIntentSender())
chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
pcall(function() service.startActivity(chooser) end)

if not berhasilDaftar then
-- Kalau gagal daftar penerima siaran, minimal file pertama tetap terkirim;
-- sisanya tidak bisa otomatis lanjut tanpa mekanisme ini.
end
end

-- ===== BAGIKAN BANYAK FILE SEKALIGUS (ACTION_SEND_MULTIPLE) =====
-- Cara yang sama dipakai file manager: SATU intent membawa SEMUA file (ArrayList<Uri>),
-- sehingga WhatsApp cukup ditanya kontak SEKALI lalu semua dokumen terkirim bersamaan.
-- Kunci supaya WhatsApp mau menerima:
--   1. Setiap URI harus content:// dari FileProvider (bukan file://).
--   2. URI dimasukkan ke EXTRA_STREAM (ArrayList) DAN ke ClipData, plus
--      FLAG_GRANT_READ_URI_PERMISSION, supaya izin baca ikut diberikan ke aplikasi penerima
--      untuk SEMUA URI (bukan cuma yang pertama).
--   3. MIME tipe harus cocok dengan filter penerima. Jika "application/zip" ditolak oleh
--      aplikasi tertentu, ubah MIME_BANYAK menjadi "*/*".
local MIME_BANYAK = "application/zip"

bagikanBanyakFile = function(daftarPath)
if not daftarPath or #daftarPath == 0 then return end

if #daftarPath == 1 then
local shareIntent = buatIntentKirimSatuFile(daftarPath[1])
local chooser = Intent.createChooser(shareIntent, "Bagikan File")
chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
pcall(function() service.startActivity(chooser) end)
return
end

local daftarUri = ArrayList()
local uriPertama = nil
for _, path in ipairs(daftarPath) do
local uri = dapatkanUriBagikan(File(path))
if uri then
daftarUri.add(uri)
if not uriPertama then uriPertama = uri end
end
end

if daftarUri.size() == 0 then
service.asyncSpeak("Gagal menyiapkan file untuk dibagikan.")
return
end

local ok = pcall(function()
local shareIntent = Intent(Intent.ACTION_SEND_MULTIPLE)
shareIntent.setType(MIME_BANYAK)
shareIntent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, daftarUri)

-- ClipData berisi semua URI -> izin baca diberikan untuk semuanya.
local clip = ClipData.newRawUri("berkas", uriPertama)
for i = 1, daftarUri.size() - 1 do
clip.addItem(ClipData.Item(daftarUri.get(i)))
end
shareIntent.setClipData(clip)
shareIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

local chooser = Intent.createChooser(shareIntent, "Bagikan " .. daftarUri.size() .. " File")
chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
service.startActivity(chooser)
end)

-- Cadangan: kalau SEND_MULTIPLE gagal dibuat, pakai cara lama (berurutan).
if not ok then
bagikanBerurutan(daftarPath)
end
end
-- ===== Akhir Bagikan Native =====
end

local globalMediaPlayer = nil
local debounceHandler = Handler(Looper.getMainLooper())
local debounceRunnable = nil
local radarHandler = Handler(Looper.getMainLooper())
local radarRunnable = nil
local isRadarRunning = false
local lastFocusedText = ""
local lastFocusedBounds = nil

local dialogUtama, showEventList, showAudioList, tampilkanMenuEdit, tampilkanMenuPengaturan, tampilkanPemilihTemaSuara, tampilkanPemilihVolume, tampilkanPemilihIntensitas, toggleSuara, muatUlangBahasaDanMenu, prosesAntreanBagikan, showDemoInstan, tampilkanMenuDemo, showPickerDemo, tampilkanDaftarKodeSuara, showPickerSPK, tampilkanMenuPencadangan
local isShortcutMenu = false

local function jalankanDenganLoading(pesan, taskBg, taskUi)
-- Saat layar progres jam aktif, semua tahap memakai satu layar yang sama (tanpa dialog baru).
if ProgresJam and ProgresJam.aktif then
ProgresJam.setPesan(pesan)
Thread(Runnable({
run = function()
local ok, res = pcall(function() return taskBg() end)
uiHandler.post(Runnable({ run = function() if taskUi then taskUi(res) end end }))
end
})).start()
return
end
local loading = UI_Dialog(T("mohon_tunggu", "Mohon Tunggu"))
loading.setMessage(pesan or T("sedang_memproses", "Sedang memproses..."))
loading.setCancelable(false)
loading.show()

uiHandler.postDelayed(Runnable({
run = function()
Thread(Runnable({
run = function()
local ok, res = pcall(function() return taskBg() end)
uiHandler.post(Runnable({
run = function()
if loading then pcall(function() loading.dismiss() end) end
if taskUi then taskUi(res) end
end
}))
end
})).start()
end
}), 60)
end

-- ===== TASK (Lua state terpisah) untuk pembuatan zip SPK =====
-- Mengikuti pola skrip referensi: task(fungsi_kerja, argumen, fungsi_hasil).
-- Fungsi kerja TIDAK boleh menyentuh variabel/UI di luar: semua data lewat argumen (JSON),
-- hasil dikembalikan lewat return (JSON). Thread & UI utama tidak berat.
local function kerjaZipSpk(jsonItems)
require "import"
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"
import "java.util.zip.ZipOutputStream"
import "java.util.zip.ZipEntry"
local cjson = require "cjson"
local items = cjson.decode(jsonItems)
local function zipRek(src, namaZip, zos, buffer)
if src.isDirectory() then
local anak = src.listFiles()
if anak then
for i = 0, #anak - 1 do
local nm = namaZip == "" and anak[i].getName() or (namaZip .. "/" .. anak[i].getName())
zipRek(anak[i], nm, zos, buffer)
end
end
else
zos.putNextEntry(ZipEntry(namaZip))
local fis = FileInputStream(src)
local len = fis.read(buffer)
while len > 0 do
zos.write(buffer, 0, len)
len = fis.read(buffer)
end
fis.close()
zos.closeEntry()
end
end
local berhasil = {}
for n = 1, #items do
local ok = pcall(function()
local fos = FileOutputStream(items[n].out)
local zos = ZipOutputStream(fos)
local buffer = byte[8192]
local files = File(items[n].src).listFiles()
if files then
for i = 0, #files - 1 do zipRek(files[i], files[i].getName(), zos, buffer) end
end
zos.close()
fos.close()
end)
if ok then table.insert(berhasil, items[n].out) end
end
return cjson.encode(berhasil)
end

-- items = { {src = folderTema, out = fileSpkKeluaran}, ... }; onSelesai(daftarPathBerhasil)
local function jalankanZipTask(pesan, items, onSelesai)
local loading = UI_Dialog(T("mohon_tunggu", "Mohon Tunggu"))
loading.setMessage(pesan or T("sedang_memproses", "Sedang memproses..."))
loading.setCancelable(false)
loading.show()
task(kerjaZipSpk, cjson.encode(items), function(json)
pcall(function() loading.dismiss() end)
local hasil = {}
pcall(function() hasil = cjson.decode(tostring(json)) end)
if onSelesai then onSelesai(hasil) end
end)
end

-- ===== TASK umum (Lua state terpisah) untuk demo, upload, dan unduh =====
local function kerjaSalinTema(jsonArgs)
require "import"
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"
local cjson = require "cjson"
local a = cjson.decode(jsonArgs)
local function hapusRek(f)
if f.isDirectory() then
local anak = f.listFiles()
if anak then for i = 0, #anak - 1 do hapusRek(anak[i]) end end
end
f.delete()
end
local function namaUnik(folder, nama)
if not File(folder .. "/" .. nama).exists() then return nama end
local nm, ext = string.match(nama, "^(.+)(%..+)$")
if not nm then nm = nama; ext = "" end
local i = 1
while true do
local baru = nm .. tostring(i) .. ext
if not File(folder .. "/" .. baru).exists() then return baru end
i = i + 1
end
end
local dest = File(a.dest)
if a.hapusDulu and dest.exists() then hapusRek(dest) end
dest.mkdirs()
local config = {}
for k, path in pairs(a.files) do
local asal = File(path)
if asal.exists() then
local nama = namaUnik(a.dest, asal.getName())
pcall(function()
local fis = FileInputStream(path)
local fos = FileOutputStream(a.dest .. "/" .. nama)
local buffer = byte[8192]
local len = fis.read(buffer)
while len > 0 do
fos.write(buffer, 0, len)
len = fis.read(buffer)
end
fis.close()
fos.close()
end)
config[k] = nama
end
end
local f = io.open(a.dest .. "/config", "w")
if f then f:write(cjson.encode(config)) f:close() end
return cjson.encode(config)
end

local function kerjaHapusPath(jsonList)
require "import"
local luajava = require("luajava")
import "java.io.File"
local cjson = require "cjson"
local daftar = cjson.decode(jsonList)
local function hapusRek(f)
if f.isDirectory() then
local anak = f.listFiles()
if anak then for i = 0, #anak - 1 do hapusRek(anak[i]) end end
end
f.delete()
end
for i = 1, #daftar do
local f = File(daftar[i])
if f.exists() then hapusRek(f) end
end
return "ok"
end

-- Dialog loading + task; onSelesai(hasilTabel) dipanggil di UI utama.
local function jalankanTaskLoading(pesan, fungsiKerja, argJson, onSelesai)
if ProgresJam and ProgresJam.aktif then
if pesan then ProgresJam.setPesan(pesan) end
task(fungsiKerja, argJson, function(json)
local hasil = {}
pcall(function() hasil = cjson.decode(tostring(json)) end)
if onSelesai then onSelesai(hasil) end
end)
return
end
local loading = UI_Dialog(T("mohon_tunggu", "Mohon Tunggu"))
loading.setMessage(pesan or T("sedang_memproses", "Sedang memproses..."))
loading.setCancelable(false)
loading.show()
task(fungsiKerja, argJson, function(json)
pcall(function() loading.dismiss() end)
local hasil = {}
pcall(function() hasil = cjson.decode(tostring(json)) end)
if onSelesai then onSelesai(hasil) end
end)
end

-- Progres dari sisi task lewat System property "nadi_prog_teks" (dibaca ringan tiap 0,7 detik).
local function mulaiPollerProgres(target)
local System = luajava.bindClass("java.lang.System")
System.setProperty("nadi_prog_teks", "")
local aktif = true
local terakhir = ""
local function poll()
if not aktif then return end
local t = tostring(System.getProperty("nadi_prog_teks"))
if t ~= "" and t ~= "null" and t ~= terakhir then
terakhir = t
if type(target) == "function" then pcall(function() target(t) end)
else pcall(function() target.setMessage(t) end) end
end
uiHandler.postDelayed(Runnable({ run = poll }), 700)
end
uiHandler.postDelayed(Runnable({ run = poll }), 700)
return function() aktif = false end
end

-- ==========================================================================
-- PROGRES JAM: satu layar progres dengan persen untuk seluruh pembuatan jam bicara.
-- Tahap (siap, tts, efek, sisip, konversi, pindah) punya bobot; persen dihitung dari bobot
-- tahap yang benar-benar dipakai. Fungsi di sini aman dipanggil dari thread mana pun.
-- Pengumuman suara diatur pref "prog_umum": item (bawaan), persen, atau mati.
-- ==========================================================================
ProgresJam = { aktif = false, tahapList = {}, total = 1, idx = 0, pecahan = 0, persen = 0, tonggak = 25, pesan = "" }

ProgresJam.mode = function()
return pref.getString("prog_umum", "item")
end

ProgresJam.atur = function(daftarTahap)
ProgresJam.tahapList = daftarTahap
local total = 0
for _, t in ipairs(daftarTahap) do total = total + t.b end
ProgresJam.total = (total > 0) and total or 1
end

ProgresJam.teks = function()
return tostring(ProgresJam.persen) .. " " .. T("prog_persen", "persen") .. "\n" .. tostring(ProgresJam.pesan)
end

ProgresJam.tampil = function()
if ProgresJam.dialog then pcall(function() ProgresJam.dialog.dismiss() end) end
local d = UI_Dialog(T("mohon_tunggu", "Mohon Tunggu"))
-- Tombol Batal dipasang di dalam tampilan sendiri (bukan tombol dialog) supaya layar tidak ikut tertutup.
local lay = LinearLayout(service)
lay.setOrientation(1)
lay.setPadding(48, 32, 48, 16)
local tv = TextView(service)
tv.setText(ProgresJam.teks())
tv.setTextSize(16)
lay.addView(tv)
local btn = Button(service)
btn.setText(T("batal", "Batal"))
btn.onClick = function() ProgresJam.tanyaBatal() end
lay.addView(btn)
d.setView(lay)
d.setCancelable(false)
d.show()
ProgresJam.dialog = d
ProgresJam.tv = tv
ProgresJam.btn = btn
end

ProgresJam.sembunyi = function()
if ProgresJam.dialog then
pcall(function() ProgresJam.dialog.dismiss() end)
ProgresJam.dialog = nil
end
ProgresJam.tv = nil
ProgresJam.btn = nil
end

ProgresJam.selesai = function()
ProgresJam.aktif = false
ProgresJam.sembunyi()
end

ProgresJam.mulai = function(daftarTahap, pesanAwal)
ProgresJam.selesai()
ProgresJam.dibatalkan = false
ProgresJam.sudahKeluar = false
ProgresJam.padaBatal = nil
ProgresJam.pesanBatal = nil
pcall(function() luajava.bindClass("java.lang.System").setProperty("nadi_batal", "") end)
ProgresJam.atur(daftarTahap)
ProgresJam.idx = 0
ProgresJam.pecahan = 0
ProgresJam.persen = 0
ProgresJam.tonggak = 25
ProgresJam.pesan = pesanAwal or T("sedang_memproses", "Sedang memproses...")
ProgresJam.aktif = true
ProgresJam.tampil()
end

ProgresJam.ucap = function(teks)
uiHandler.post(Runnable({ run = function() pcall(function() service.speak(teks) end) end }))
end

ProgresJam.segarkan = function()
local teks = ProgresJam.teks()
uiHandler.post(Runnable({
run = function()
pcall(function() if ProgresJam.tv then ProgresJam.tv.setText(teks) end end)
end
}))
end

ProgresJam.hitungPersen = function()
local tl = ProgresJam.tahapList
local dasar = 0
for i = 1, ProgresJam.idx - 1 do
if tl[i] then dasar = dasar + tl[i].b end
end
local bobot = (tl[ProgresJam.idx] and tl[ProgresJam.idx].b) or 0
local p = math.floor((dasar + bobot * ProgresJam.pecahan) * 100 / ProgresJam.total)
if p > 100 then p = 100 end
if p < ProgresJam.persen then p = ProgresJam.persen end
ProgresJam.persen = p
end

ProgresJam.cekTonggak = function()
if ProgresJam.mode() ~= "persen" then return end
if ProgresJam.tonggak <= 75 and ProgresJam.persen >= ProgresJam.tonggak then
ProgresJam.ucap(tostring(ProgresJam.persen) .. " " .. T("prog_persen", "persen"))
while ProgresJam.tonggak <= ProgresJam.persen do ProgresJam.tonggak = ProgresJam.tonggak + 25 end
end
end

-- Hanya mengganti tulisan (persen tidak berubah).
ProgresJam.setPesan = function(pesan)
if not ProgresJam.aktif or not pesan then return end
ProgresJam.pesan = pesan
ProgresJam.segarkan()
end

-- Pindah ke tahap berikutnya. Pada mode "item", nama tahap diumumkan beserta persen.
ProgresJam.tahap = function(kunci, pesan)
if not ProgresJam.aktif then return end
for i, t in ipairs(ProgresJam.tahapList) do
if t.k == kunci then ProgresJam.idx = i; break end
end
ProgresJam.padaBatal = nil
ProgresJam.pecahan = 0
if pesan then ProgresJam.pesan = pesan end
ProgresJam.hitungPersen()
ProgresJam.segarkan()
if pesan and ProgresJam.mode() == "item" then
ProgresJam.ucap(tostring(pesan) .. ", " .. ProgresJam.persen .. " " .. T("prog_persen", "persen"))
end
ProgresJam.cekTonggak()
end

-- Kemajuan di dalam tahap (pecahan 0 sampai 1). umumkan = true: sebut nama berkas (mode "item").
ProgresJam.maju = function(pecahan, pesan, umumkan)
if not ProgresJam.aktif then return end
if pecahan < 0 then pecahan = 0 elseif pecahan > 1 then pecahan = 1 end
ProgresJam.pecahan = pecahan
if pesan then ProgresJam.pesan = pesan end
ProgresJam.hitungPersen()
ProgresJam.segarkan()
if umumkan and pesan and ProgresJam.mode() == "item" then
ProgresJam.ucap(tostring(pesan) .. ", " .. ProgresJam.persen .. " " .. T("prog_persen", "persen"))
end
ProgresJam.cekTonggak()
end

-- Pembatalan. Tombol Batal bertanya dulu; bila "Ya", proses dihentikan di titik aman terdekat:
-- tahap TTS dihentikan langsung (padaBatal), tahap task berhenti di antara dua berkas lewat
-- System property "nadi_batal", lalu tiap tahap memeriksa ProgresJam.dibatalkan sebelum lanjut.
ProgresJam.tanyaBatal = function()
if not ProgresJam.aktif or ProgresJam.dibatalkan then return end
local d = UI_Dialog(T("prog_batal_judul", "Batalkan Pembuatan Jam?"))
d.setMessage(ProgresJam.pesanBatal or T("prog_batal_dasar", "Proses akan dihentikan."))
d.setButton(T("prog_batal_ya", "Ya, Batalkan"), function() ProgresJam.batal() end)
d.setButton2(T("prog_batal_tidak", "Lanjutkan"), function() end)
d.show()
end

ProgresJam.batal = function()
if not ProgresJam.aktif or ProgresJam.dibatalkan then return end
ProgresJam.dibatalkan = true
pcall(function() luajava.bindClass("java.lang.System").setProperty("nadi_batal", "1") end)
ProgresJam.matikanBatal()
ProgresJam.setPesan(T("prog_membatalkan", "Membatalkan, mohon tunggu..."))
ProgresJam.ucap(T("prog_membatalkan", "Membatalkan, mohon tunggu..."))
if ProgresJam.padaBatal then
local f = ProgresJam.padaBatal
ProgresJam.padaBatal = nil
pcall(f)
end
end

ProgresJam.matikanBatal = function()
pcall(function() if ProgresJam.btn then ProgresJam.btn.setEnabled(false) end end)
end

-- Keluar setelah dibatalkan. pathHapus (boleh nil): folder setengah jadi yang dibuang.
ProgresJam.keluarBatal = function(pathHapus, ucap)
if ProgresJam.sudahKeluar then return end
ProgresJam.sudahKeluar = true
ProgresJam.selesai()
if pathHapus then
pcall(function() task(kerjaHapusPath, cjson.encode({ pathHapus }), function() end) end)
end
service.speak(ucap or T("prog_dibatalkan", "Pembuatan jam dibatalkan."))
muatUlangBahasaDanMenu()
end

-- Memantau kemajuan dari fungsi kerja yang berjalan di task (Lua state terpisah) lewat System property.
-- onBaca(teks) dipanggil di thread utama tiap 0,4 detik bila isinya berubah. Mengembalikan fungsi berhenti.
ProgresJam.pantau = function(kunci, onBaca)
local System = luajava.bindClass("java.lang.System")
System.setProperty(kunci, "")
local aktif = true
local terakhir = ""
local function poll()
if not aktif then return end
local t = tostring(System.getProperty(kunci))
if t ~= "" and t ~= "null" and t ~= terakhir then
terakhir = t
pcall(function() onBaca(t) end)
end
uiHandler.postDelayed(Runnable({ run = poll }), 400)
end
uiHandler.postDelayed(Runnable({ run = poll }), 400)
return function() aktif = false end
end

-- Nama yang enak diucapkan untuk satu berkas jam (dari nama folder dan nama berkas).
ProgresJam.labelSub = function(sub, angka)
if sub == "hour" then
return T("prog_lbl_jam", "jam ") .. tostring(angka == 0 and 24 or angka)
elseif sub == "hourly" then
local jam = math.floor(angka / 100)
if jam == 0 then jam = 24 end
return T("prog_lbl_jam_tepat", "jam tepat ") .. tostring(jam)
elseif sub == "minute" then
return T("prog_lbl_menit", "menit ") .. tostring(angka)
end
return tostring(angka)
end

ProgresJam.labelBerkas = function(path)
local sub, nama = string.match(tostring(path), "/([^/]+)/([^/]+)$")
if not sub then return tostring(path) end
local angka = tonumber(string.match(nama, "^(%d+)"))
if not angka then return nama end
return ProgresJam.labelSub(sub, angka)
end

-- id ucapan TTS: h13 (jam), hl1300 (jam tepat), m5 (menit)
ProgresJam.labelId = function(uid)
local awalan, angka = string.match(tostring(uid), "^(%a+)(%d+)$")
if not awalan then return tostring(uid) end
local sub = (awalan == "h" and "hour") or (awalan == "hl" and "hourly") or (awalan == "m" and "minute") or ""
return ProgresJam.labelSub(sub, tonumber(angka))
end

-- Menu pilihan pengumuman suara progres.
ProgresJam.tampilkanPengaturan = function()
local d = UI_Dialog(T("prog_umum_menu", "Pengumuman Progres Pembuatan Jam"))
local lv = ListView(service)
local nilai = { "item", "persen", "mati" }
local label = ArrayList()
label.add(T("prog_umum_item", "Setiap tahap dan berkas (misalnya: Membuat jam 13, 40 persen)"))
label.add(T("prog_umum_persen", "Hanya setiap 25 persen"))
label.add(T("prog_umum_mati", "Mati (hanya tampil di layar)"))
lv.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, label))
d.setView(lv)
lv.onItemClick = function(l, v, p, id)
pcall(function() pref.edit().putString("prog_umum", nilai[p + 1]).apply() end)
d.dismiss()
service.speak(tostring(label.get(p)))
end
d.setButton(T("tutup", "Tutup"), function() d.dismiss() end)
d.show()
end
-- ==========================================================================

local function kerjaUnduhSpk(jsonArgs)
require "import"
local luajava = require("luajava")
import "java.io.File"
import "java.io.FileOutputStream"
import "java.net.URL"
local cjson = require "cjson"
local System = luajava.bindClass("java.lang.System")
local a = cjson.decode(jsonArgs)
local files = {}
local galat = "" -- pesan galat asli unduhan pertama yang gagal, ditampilkan ke pengguna
for i = 1, #a.items do
local item = a.items[i]
System.setProperty("nadi_prog_teks", a.lbl .. i .. "/" .. #a.items .. "\n" .. item.cleanName)
-- buang karakter terlarang di nama berkas lokal (terutama "/" yang dianggap subfolder)
local aman = string.gsub(item.cleanName, "[/\\:*?\"<>|]", "_")
local target = a.folder .. "/" .. aman .. ".spk"
local ok, err = pcall(function()
local conn = URL(item.url).openConnection()
if item.api and (a.token or "") ~= "" then
conn.setRequestProperty("Authorization", "token " .. a.token)
conn.setRequestProperty("Accept", "application/vnd.github.raw")
end
conn.setConnectTimeout(10000)
conn.setReadTimeout(15000)
local is = conn.getInputStream()
local fos = FileOutputStream(target)
local buffer = byte[8192]
local len = is.read(buffer)
while len ~= -1 do
fos.write(buffer, 0, len)
len = is.read(buffer)
end
fos.flush()
fos.close()
is.close()
end)
if ok then table.insert(files, target)
elseif galat == "" then galat = item.cleanName .. ": " .. tostring(err) end
end
return cjson.encode({ files = files, galat = galat })
end

local function kerjaUploadSpk(jsonArgs)
require "import"
local luajava = require("luajava")
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.ByteArrayOutputStream"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.net.URL"
local cjson = require "cjson"
local System = luajava.bindClass("java.lang.System")
local a = cjson.decode(jsonArgs)
local repoPakai = a.repo or "nandadian20083123/skrip-lua"
local token = ""
if a.isAdmin then
token = a.token or ""
if token == "" then return cjson.encode({ status = "token_kosong" }) end
elseif a.repo then
-- Repo khusus (Tema Admin): wajib token repo itu, tidak pernah memakai token komunitas
token = a.tokenTema or ""
if token == "" then return cjson.encode({ status = "token_kosong" }) end
else
local ok, dataToken = pcall(function()
local conn = URL("https://raw.githubusercontent.com/nandadian20083123/skrip-lua/main/token_komunitas.json").openConnection()
conn.setRequestProperty("Cache-Control", "no-cache")
conn.setConnectTimeout(5000)
local br = BufferedReader(InputStreamReader(conn.getInputStream()))
local content = ""
local line = br.readLine()
while line do content = content .. line; line = br.readLine() end
br.close()
return cjson.decode(content)
end)
local tokenBaca = nil
if ok and type(dataToken) == "table" then
if dataToken.k then
local okD, hasilD = pcall(function()
local B64 = luajava.bindClass("android.util.Base64")
local JStr = luajava.bindClass("java.lang.String")
local terbalik = tostring(JStr(B64.decode(tostring(dataToken.k), 0), "UTF-8"))
return string.reverse(terbalik)
end)
if okD and type(hasilD) == "string" and hasilD ~= "" then tokenBaca = hasilD end
elseif dataToken.token_komunitas then
tokenBaca = dataToken.token_komunitas
end
end
if tokenBaca then
token = tokenBaca
else
return cjson.encode({ status = "gagal_token" })
end
end
local total = #a.items
local sukses = 0
local errorMsg = ""
local Base64 = luajava.bindClass("android.util.Base64")
for index = 1, total do
local item = a.items[index]
System.setProperty("nadi_prog_teks", a.lbl .. index .. "/" .. total .. "\n" .. item.name)
local function bacaGalat(conn)
local okB, teksB = pcall(function()
local es = conn.getErrorStream()
if not es then return "" end
local brE = BufferedReader(InputStreamReader(es))
local t, l = "", brE.readLine()
while l do t = t .. l; l = brE.readLine() end
brE.close()
local okJ, d = pcall(function() return cjson.decode(t) end)
if okJ and type(d) == "table" and d.message then return tostring(d.message) end
return t
end)
return okB and teksB or ""
end
local success, hasilOk, pesanDalam = pcall(function()
local f = File(item.path)
if tonumber(f.length()) > 26214400 then return false, "File terlalu besar (>25MB)" end
local fis = FileInputStream(f)
local baos = ByteArrayOutputStream()
local buffer = byte[4096]
local read = fis.read(buffer)
while read ~= -1 do
baos.write(buffer, 0, read)
read = fis.read(buffer)
end
local base64Data = Base64.encodeToString(baos.toByteArray(), 2)
fis.close()
baos.close()
local repoPath = a.folder .. "/" .. string.gsub(item.name, " ", "%%20")
local sha = nil
local connGet = URL("https://api.github.com/repos/" .. repoPakai .. "/contents/" .. repoPath).openConnection()
connGet.setRequestMethod("GET")
connGet.setRequestProperty("Authorization", "token " .. token)
connGet.setRequestProperty("Accept", "application/vnd.github.v3+json")
if connGet.getResponseCode() == 200 then
local br = BufferedReader(InputStreamReader(connGet.getInputStream()))
local jsonText, line = "", br.readLine()
while line do jsonText = jsonText .. line; line = br.readLine() end
br.close()
sha = cjson.decode(jsonText).sha
end
local connPut = URL("https://api.github.com/repos/" .. repoPakai .. "/contents/" .. repoPath).openConnection()
connPut.setRequestMethod("PUT")
connPut.setRequestProperty("Authorization", "token " .. token)
connPut.setRequestProperty("Accept", "application/vnd.github.v3+json")
connPut.setRequestProperty("Content-Type", "application/json")
connPut.setDoOutput(true)
local OutputStreamWriter = luajava.bindClass("java.io.OutputStreamWriter")
local osw = OutputStreamWriter(connPut.getOutputStream(), "UTF-8")
osw.write('{"message":"Upload Tema Komunitas: ')
osw.write(item.name)
osw.write('","content":"')
osw.write(base64Data)
osw.write('"')
if sha then
osw.write(',"sha":"')
osw.write(sha)
osw.write('"')
end
osw.write('}')
osw.flush()
osw.close()
local code = connPut.getResponseCode()
base64Data = nil
collectgarbage("collect")
if code == 200 or code == 201 then return true end
local detail = bacaGalat(connPut)
return false, "Error Code: " .. tostring(code) .. (detail ~= "" and ("\nGitHub: " .. detail) or "")
end)
if success and hasilOk ~= false then
sukses = sukses + 1
else
if success then errorMsg = tostring(pesanDalam or hasilOk) else errorMsg = "Galat: " .. tostring(hasilOk) end
end
end
token = ""
return cjson.encode({ status = "selesai", sukses = sukses, total = total, err = errorMsg })
end

local function kerjaHapusSpk(folderPath)
require "import"
import "java.io.File"
local dir = File(folderPath)
if dir.exists() and dir.isDirectory() then
local files = dir.listFiles()
if files then
for i = 0, #files - 1 do
local f = files[i]
if f.isFile() and string.match(string.lower(f.getName()), "%.spk$") then f.delete() end
end
end
end
return "ok"
end

local function kerjaSedotAdmin(jsonArgs)
require "import"
local luajava = require("luajava")
local cjson = require "cjson"
local a = cjson.decode(jsonArgs)
local ok, content = pcall(function()
local url = luajava.bindClass("java.net.URL")("https://raw.githubusercontent.com/nandadian20083123/skrip-lua/main/daftar_admin.json")
local conn = url.openConnection()
conn.setRequestProperty("Cache-Control", "no-cache")
conn.setConnectTimeout(3000)
local is = conn.getInputStream()
local isi = ""
local br = luajava.bindClass("java.io.BufferedReader")(luajava.bindClass("java.io.InputStreamReader")(is))
local line = br.readLine()
while line do isi = isi .. line; line = br.readLine() end
br.close()
local parsed = cjson.decode(isi)
if type(parsed) == "table" then
local f = io.open(a.pathAdminJson, "w")
if f then f:write(isi); f:close() end
return isi
end
return nil
end)
if ok and content then return content end
return ""
end

local function kerjaUnduhOta(jsonList)
require "import"
import "java.io.File"
import "java.io.FileOutputStream"
import "java.net.URL"
local cjson = require "cjson"
local daftar = cjson.decode(jsonList)
local sukses = true
for i = 1, #daftar do
local tempPath = daftar[i].path .. ".temp"
local ok = pcall(function()
local conn = URL(daftar[i].url).openConnection()
conn.setConnectTimeout(10000)
conn.setReadTimeout(15000)
local is = conn.getInputStream()
local fos = FileOutputStream(tempPath)
local buffer = byte[8192]
local len = is.read(buffer)
while len > 0 do
fos.write(buffer, 0, len)
len = is.read(buffer)
end
fos.close()
is.close()
end)
if not ok then sukses = false break end
end
return cjson.encode({ success = sukses })
end

local function kerjaUploadGithub(jsonArgs)
require "import"
local luajava = require("luajava")
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.ByteArrayOutputStream"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.net.URL"
import "java.lang.String"
local cjson = require "cjson"
local System = luajava.bindClass("java.lang.System")
local Base64 = luajava.bindClass("android.util.Base64")
local a = cjson.decode(jsonArgs)
local function bacaGalat(conn)
local okB, teksB = pcall(function()
local es = conn.getErrorStream()
if not es then return "" end
local brE = BufferedReader(InputStreamReader(es))
local t, l = "", brE.readLine()
while l do t = t .. l; l = brE.readLine() end
brE.close()
local okJ, d = pcall(function() return cjson.decode(t) end)
if okJ and type(d) == "table" and d.message then return tostring(d.message) end
return t
end)
return okB and teksB or ""
end
local success, hasilOk, pesanDalam = pcall(function()
local f = File(a.localFilePath)
if not f.exists() then return false, "File lokal tidak ditemukan" end
local fis = FileInputStream(f)
local bos = ByteArrayOutputStream()
local buf = byte[8192]
local len = fis.read(buf)
while len > 0 do
bos.write(buf, 0, len)
len = fis.read(buf)
end
fis.close()
local base64Data = Base64.encodeToString(bos.toByteArray(), Base64.NO_WRAP)
bos.close()
System.setProperty("nadi_prog_teks", "Mengambil data " .. a.repoPath .. " dari server...")
local alamat = "https://api.github.com/repos/" .. a.owner .. "/" .. a.repo .. "/contents/" .. a.repoPath
local sha = nil
local connGet = URL(alamat).openConnection()
connGet.setRequestMethod("GET")
connGet.setRequestProperty("Authorization", "token " .. a.token)
connGet.setRequestProperty("Accept", "application/vnd.github.v3+json")
if connGet.getResponseCode() == 200 then
local br = BufferedReader(InputStreamReader(connGet.getInputStream()))
local jsonText, line = "", br.readLine()
while line do jsonText = jsonText .. line; line = br.readLine() end
br.close()
sha = cjson.decode(jsonText).sha
end
System.setProperty("nadi_prog_teks", "Mengunggah " .. a.repoPath .. " ke GitHub...")
local bodyTable = { message = a.commitMsg, content = base64Data }
if sha then bodyTable.sha = sha end
local bodyJson = cjson.encode(bodyTable)
local connPut = URL(alamat).openConnection()
connPut.setRequestMethod("PUT")
connPut.setRequestProperty("Authorization", "token " .. a.token)
connPut.setRequestProperty("Accept", "application/vnd.github.v3+json")
connPut.setRequestProperty("Content-Type", "application/json")
connPut.setDoOutput(true)
local os = connPut.getOutputStream()
os.write(String(bodyJson).getBytes("UTF-8"))
os.close()
local code = connPut.getResponseCode()
if code == 200 or code == 201 then return true, "Berhasil" end
local detail = bacaGalat(connPut)
return false, "Error Code: " .. tostring(code) .. (detail ~= "" and ("\nGitHub: " .. detail) or "")
end)
local berhasil = (success and hasilOk ~= false)
local pesanAkhir
if success then pesanAkhir = tostring(pesanDalam or hasilOk) else pesanAkhir = "Galat: " .. tostring(hasilOk) end
return cjson.encode({ ok = berhasil and true or false, msg = pesanAkhir })
end

local function kerjaAmbilManifestKustom(jsonArgs)
require "import"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.net.URL"
import "java.lang.String"
local luajava = require("luajava")
local cjson = require "cjson"
local Base64 = luajava.bindClass("android.util.Base64")
local a = cjson.decode(jsonArgs)
local ok, hasil = pcall(function()
local conn = URL("https://api.github.com/repos/nandadian20083123/skrip-lua/contents/file_kustom.json").openConnection()
conn.setConnectTimeout(8000) conn.setReadTimeout(8000)
conn.setRequestProperty("Cache-Control", "no-cache")
conn.setRequestProperty("Authorization", "token " .. a.token)
conn.setRequestProperty("Accept", "application/vnd.github.v3+json")
local code = conn.getResponseCode()
if code == 404 then return { ok = true, daftar = {} } end
if code ~= 200 then return { ok = false } end
local br = BufferedReader(InputStreamReader(conn.getInputStream()))
local teks, baris = "", br.readLine()
while baris do teks = teks .. baris; baris = br.readLine() end
br.close()
local isi = (tostring(cjson.decode(teks).content or ""):gsub("%s", ""))
local daftar = cjson.decode(tostring(String(Base64.decode(isi, 0), "UTF-8")))
return { ok = true, daftar = daftar }
end)
if ok and hasil then return cjson.encode(hasil) end
return cjson.encode({ ok = false })
end

local function kerjaCekOta(jsonArgs)
require "import"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.net.URL"
local cjson = require "cjson"
local a = cjson.decode(jsonArgs)
local ok, hasil = pcall(function()
local urlTree = URL("https://api.github.com/repos/nandadian20083123/skrip-lua/git/trees/main?recursive=1")
local connTree = urlTree.openConnection()
connTree.setConnectTimeout(5000) connTree.setReadTimeout(5000) connTree.setRequestProperty("Cache-Control", "no-cache")
if a.token ~= "" then connTree.setRequestProperty("Authorization", "token " .. a.token) end
local brTree = BufferedReader(InputStreamReader(connTree.getInputStream()))
local jsonTextTree, lineTree = "", brTree.readLine()
while lineTree do jsonTextTree = jsonTextTree .. lineTree; lineTree = brTree.readLine() end
brTree.close()
local jsonTree = cjson.decode(jsonTextTree)
local kustom = {}
local adaManifest = false
for i = 1, #jsonTree.tree do
if jsonTree.tree[i].path == "file_kustom.json" then adaManifest = true end
end
if adaManifest then
pcall(function()
local luajava = require("luajava")
local connM = URL("https://api.github.com/repos/nandadian20083123/skrip-lua/contents/file_kustom.json").openConnection()
connM.setConnectTimeout(5000) connM.setReadTimeout(5000) connM.setRequestProperty("Cache-Control", "no-cache")
if a.token ~= "" then connM.setRequestProperty("Authorization", "token " .. a.token) end
local brM = BufferedReader(InputStreamReader(connM.getInputStream()))
local tM, lM = "", brM.readLine()
while lM do tM = tM .. lM; lM = brM.readLine() end
brM.close()
local Base64 = luajava.bindClass("android.util.Base64")
local JString = luajava.bindClass("java.lang.String")
local isi = (tostring(cjson.decode(tM).content or ""):gsub("%s", ""))
local daftarM = cjson.decode(tostring(JString(Base64.decode(isi, 0), "UTF-8")))
for k = 1, #daftarM do
local e = daftarM[k]
if type(e) == "table" and type(e.nama) == "string" and e.nama:match("^[%w_%-][%w%._%-]*%.%w+$") and not e.nama:find("%.%.") then
kustom[#kustom + 1] = { nama = e.nama, folder = (e.folder == "bahasa") and "bahasa" or "luar" }
end
end
end)
end
local kunci = {}
for i = 1, #a.keys do kunci[a.keys[i]] = true end
for i = 1, #kustom do kunci[((kustom[i].folder == "bahasa") and "bahasa/" or "") .. kustom[i].nama] = true end
if adaManifest then kunci["file_kustom.json"] = true end
local combinedSha = ""
for i = 1, #jsonTree.tree do
local item = jsonTree.tree[i]
if kunci[item.path] then combinedSha = combinedSha .. item.sha end
end
local urlCommit = URL("https://api.github.com/repos/nandadian20083123/skrip-lua/commits/main")
local connCommit = urlCommit.openConnection()
connCommit.setConnectTimeout(5000) connCommit.setReadTimeout(5000) connCommit.setRequestProperty("Cache-Control", "no-cache")
if a.token ~= "" then connCommit.setRequestProperty("Authorization", "token " .. a.token) end
local brCommit = BufferedReader(InputStreamReader(connCommit.getInputStream()))
local jsonTextCommit, lineCommit = "", brCommit.readLine()
while lineCommit do jsonTextCommit = jsonTextCommit .. lineCommit; lineCommit = brCommit.readLine() end
brCommit.close()
local jsonCommit = cjson.decode(jsonTextCommit)
return { ok = true, date = jsonCommit.commit.committer.date, message = jsonCommit.commit.message, shaCommit = jsonCommit.sha, coreSha = combinedSha, kustom = kustom }
end)
if ok and hasil then return cjson.encode(hasil) end
return cjson.encode({ ok = false })
end

local function kerjaCekToken(jsonArgs)
require "import"
import "java.net.URL"
local cjson = require "cjson"
local a = cjson.decode(jsonArgs)
local ok, status = pcall(function()
local conn = URL("https://api.github.com/repos/nandadian20083123/skrip-lua").openConnection()
conn.setConnectTimeout(5000)
conn.setReadTimeout(5000)
conn.setRequestProperty("Authorization", "token " .. a.token)
return conn.getResponseCode() == 200
end)
return cjson.encode({ valid = (ok and status) and true or false })
end

-- items: { {src=folder, dst=folder, hapusDulu=bool}, ... } salin file datar (tanpa sub-folder)
-- atau { {srcFile=berkas, dstFile=berkas} }.
local function kerjaSalinFlat(jsonList)
require "import"
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"
local cjson = require "cjson"
local daftar = cjson.decode(jsonList)
local function hapusRek(f)
if f.isDirectory() then
local anak = f.listFiles()
if anak then for i = 0, #anak - 1 do hapusRek(anak[i]) end end
end
f.delete()
end
local function salin(srcPath, dstPath)
pcall(function()
local fis = FileInputStream(srcPath)
local fos = FileOutputStream(dstPath)
local buffer = byte[8192]
local len = fis.read(buffer)
while len > 0 do
fos.write(buffer, 0, len)
len = fis.read(buffer)
end
fis.close()
fos.close()
end)
end
for n = 1, #daftar do
local it = daftar[n]
if it.srcFile then
local dstF = File(it.dstFile)
if not dstF.getParentFile().exists() then dstF.getParentFile().mkdirs() end
salin(it.srcFile, it.dstFile)
else
local dst = File(it.dst)
if it.hapusDulu and dst.exists() then hapusRek(dst) end
dst.mkdirs()
local f = File(it.src).listFiles()
if f then
for j = 0, #f - 1 do
salin(f[j].getAbsolutePath(), it.dst .. "/" .. f[j].getName())
end
end
end
end
return "ok"
end

local function kerjaAmbilDaftarKomunitas(jsonArgs)
require "import"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.net.URL"
local cjson = require "cjson"
local a = cjson.decode(jsonArgs)
local ok, hasil = pcall(function()
local repoPakai = a.repo or "nandadian20083123/skrip-lua"
local conn = URL("https://api.github.com/repos/" .. repoPakai .. "/git/trees/" .. (a.repo and "HEAD" or "main") .. "?recursive=1").openConnection()
conn.setRequestProperty("Cache-Control", "no-cache")
if (a.token or "") ~= "" then conn.setRequestProperty("Authorization", "token " .. a.token) end
conn.setRequestProperty("Accept", "application/vnd.github.v3+json")
if conn.getResponseCode() ~= 200 then return nil end
local br = BufferedReader(InputStreamReader(conn.getInputStream()))
local jsonText, line = "", br.readLine()
while line do jsonText = jsonText .. line; line = br.readLine() end
br.close()
local jsonData = cjson.decode(jsonText)
local daftar = {}
for i = 1, #jsonData.tree do
local item = jsonData.tree[i]
-- cek awalan folder secara polos (bukan pola) supaya nama folder berisi "-" atau "." tidak merusak pencocokan
local awalan = a.folderTarget .. "/"
if item.type == "blob" and string.sub(item.path, 1, #awalan) == awalan and string.sub(item.path, -4) == ".spk" then
local rawFileName = string.sub(item.path, #awalan + 1)
rawFileName = string.gsub(rawFileName, "%%20", " ")
-- Folder induk (mis. tema_suara_admin) ikut memuat berkas di subfolder slot admin lain.
-- Pisahkan nama berkas dari nama slot, supaya cleanName tidak berisi "/" (itu yang bikin unduhan gagal).
local slot, namaBerkas = string.match(rawFileName, "^(.*)/([^/]+)$")
if not namaBerkas then namaBerkas = rawFileName end
local cleanName, uploader = string.match(namaBerkas, "^(.*)_%d+_(.-)%.spk$")
if not cleanName then cleanName = string.gsub(namaBerkas, "%.spk$", ""); uploader = a.lblTakDiketahui end
if slot then uploader = uploader .. " [" .. slot .. "]" end
table.insert(daftar, {
path = item.path,
sha = item.sha,
fileName = rawFileName,
cleanName = cleanName,
uploader = uploader,
repo = repoPakai,
api = a.repo and true or nil,
-- repo khusus diunduh lewat API + token; repo publik lewat raw seperti biasa
url = a.repo and ("https://api.github.com/repos/" .. repoPakai .. "/contents/" .. string.gsub(item.path, " ", "%%20"))
or ("https://raw.githubusercontent.com/nandadian20083123/skrip-lua/main/" .. string.gsub(item.path, " ", "%%20"))
})
end
end
table.sort(daftar, function(x, y) return string.lower(x.cleanName) < string.lower(y.cleanName) end)
return daftar
end)
if ok and hasil then return cjson.encode({ ok = true, data = hasil }) end
return cjson.encode({ ok = false })
end

local function kerjaHapusServer(jsonArgs)
require "import"
local luajava = require("luajava")
import "java.net.URL"
local cjson = require "cjson"
local a = cjson.decode(jsonArgs)
local ok, hasil = pcall(function()
local bodyJson = cjson.encode({ message = "Hapus Tema Komunitas: " .. a.fileName, sha = a.sha })
local connPut = URL("https://api.github.com/repos/" .. (a.repo or "nandadian20083123/skrip-lua") .. "/contents/" .. string.gsub(a.path, " ", "%%20")).openConnection()
connPut.setRequestMethod("DELETE")
connPut.setRequestProperty("Authorization", "token " .. a.token)
connPut.setRequestProperty("Accept", "application/vnd.github.v3+json")
connPut.setRequestProperty("Content-Type", "application/json")
connPut.setDoOutput(true)
local os = connPut.getOutputStream()
os.write(luajava.bindClass("java.lang.String")(bodyJson).getBytes("UTF-8"))
os.close()
return connPut.getResponseCode() == 200
end)
return cjson.encode({ sukses = (ok and hasil) and true or false })
end

-- daftar: { {src=pathLama, dst=pathBaru}, ... }
local function kerjaRenamePath(jsonList)
require "import"
import "java.io.File"
local cjson = require "cjson"
local daftar = cjson.decode(jsonList)
for i = 1, #daftar do
local f = File(daftar[i].src)
if f.exists() then f.renameTo(File(daftar[i].dst)) end
end
return "ok"
end

-- args: { jamAsli=path, items={ {src=,dst=} }, hapus={path,...} }
local function kerjaSelesaiJam(jsonArgs)
require "import"
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"
local cjson = require "cjson"
local a = cjson.decode(jsonArgs)
local function hapusRek(f)
if f.isDirectory() then
local anak = f.listFiles()
if anak then for i = 0, #anak - 1 do hapusRek(anak[i]) end end
end
f.delete()
end
local function salin(srcPath, dstPath)
pcall(function()
local fis = FileInputStream(srcPath)
local fos = FileOutputStream(dstPath)
local buffer = byte[8192]
local len = fis.read(buffer)
while len > 0 do
fos.write(buffer, 0, len)
len = fis.read(buffer)
end
fis.close()
fos.close()
end)
end
local jamAsli = File(a.jamAsli)
if jamAsli.exists() then hapusRek(jamAsli) end
jamAsli.mkdirs()
for n = 1, #a.items do
local dst = File(a.items[n].dst)
if not dst.exists() then dst.mkdirs() end
local files = File(a.items[n].src).listFiles()
if files then
for i = 0, #files - 1 do
salin(files[i].getAbsolutePath(), a.items[n].dst .. "/" .. files[i].getName())
end
end
end
for i = 1, #a.hapus do
local f = File(a.hapus[i])
if f.exists() then hapusRek(f) end
end
return "ok"
end

-- args: { path=, isInternal=bool, tipeKomponen=string|nil }
local function kerjaDaftarFolderTema(jsonArgs)
require "import"
import "java.io.File"
local cjson = require "cjson"
local a = cjson.decode(jsonArgs)
local function apakahFolderTemaKetat(dir)
local configF = File(dir.getAbsolutePath() .. "/config")
if not configF.exists() or not configF.isFile() then return false end
local anak = dir.listFiles()
if anak then
for i = 0, #anak - 1 do
if anak[i].isDirectory() then
local namaFolder = string.lower(anak[i].getName())
if namaFolder ~= "clock" and namaFolder ~= "effect" then return false end
end
end
end
return true
end
local isInternal = a.isInternal
local tempItems = {}
local d = File(a.path)
if d.exists() and d.isDirectory() then
local files = d.listFiles()
if files then
for i = 0, #files - 1 do
local f = files[i]
if f.isDirectory() and not string.match(f.getName(), "^%.") then
local isT = isInternal and File(f.getAbsolutePath() .. "/config").exists() or apakahFolderTemaKetat(f)
local masuk = true
if a.tipeKomponen then
masuk = (not isT) or File(f.getAbsolutePath() .. "/" .. a.tipeKomponen).exists()
end
if masuk then
table.insert(tempItems, { name = f.getName(), path = f.getAbsolutePath(), isTheme = isT })
end
end
end
end
end
table.sort(tempItems, function(x, y) return string.lower(x.name) < string.lower(y.name) end)
return cjson.encode(tempItems)
end

-- args: { spk=pathSpk, target=folderTujuan, hapusDulu=bool }
local function kerjaImporSpk(jsonArgs)
require "import"
local luajava = require("luajava")
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"
import "java.util.zip.ZipInputStream"
local cjson = require "cjson"
local a = cjson.decode(jsonArgs)
local function hapusRek(f)
if f.isDirectory() then
local anak = f.listFiles()
if anak then for i = 0, #anak - 1 do hapusRek(anak[i]) end end
end
f.delete()
end
local function ekstrak(zipPath, destDir)
pcall(function()
local fis = FileInputStream(zipPath)
local zis = ZipInputStream(fis)
local entry = zis.getNextEntry()
local buffer = byte[8192]
while entry do
local fileName = entry.getName()
local newFile = File(destDir, fileName)
-- Keamanan: lewati entry yang keluar dari folder tujuan (zip-slip, mis. ../)
local entryAman = false
pcall(function()
local basePathAman = tostring(File(destDir).getCanonicalPath())
local targetAman = tostring(newFile.getCanonicalPath())
entryAman = (targetAman == basePathAman) or (targetAman:sub(1, #basePathAman + 1) == basePathAman .. "/")
end)
if not entryAman then
-- entry berbahaya dilewati
elseif entry.isDirectory() then
newFile.mkdirs()
else
newFile.getParentFile().mkdirs()
local fos = FileOutputStream(newFile)
local length = zis.read(buffer)
while length > 0 do
fos.write(buffer, 0, length)
length = zis.read(buffer)
end
fos.close()
end
zis.closeEntry()
entry = zis.getNextEntry()
end
zis.close()
fis.close()
end)
end
local function rapikan(folderPath)
local targetDir = File(folderPath)
if not targetDir.exists() or not targetDir.isDirectory() then return end
if File(folderPath .. "/config").exists() then return end
local files = targetDir.listFiles()
if not files then return end
local jumlahFolder = 0
local folderAnak = nil
for i = 0, #files - 1 do
if files[i].isDirectory() then
jumlahFolder = jumlahFolder + 1
folderAnak = files[i]
end
end
if jumlahFolder == 1 and folderAnak then
if File(folderAnak.getAbsolutePath() .. "/config").exists() then
local isiAnak = folderAnak.listFiles()
if isiAnak then
for j = 0, #isiAnak - 1 do
isiAnak[j].renameTo(File(folderPath .. "/" .. isiAnak[j].getName()))
end
end
folderAnak.delete()
end
end
end
local target = File(a.target)
if a.hapusDulu and target.exists() then hapusRek(target) end
target.mkdirs()
ekstrak(a.spk, a.target)
rapikan(a.target)
return "ok"
end

local BukaMenuPremiumGaib = nil

local function AmbilDataBrankas()
local f = io.open("/storage/emulated/0/.cadangan/.sys_cache_record", "r")
if not f then return {} end
local c = f:read("*all")
f:close()
local ok, d = pcall(function() return require("cjson").decode(c) end)
return (ok and type(d) == "table") and d or {}
end

local function SimpanDataBrankas(data)
local ok, j = pcall(function() return require("cjson").encode(data) end)
if ok and j then
luajava.bindClass("java.io.File")("/storage/emulated/0/.cadangan").mkdirs()
local f = io.open("/storage/emulated/0/.cadangan/.sys_cache_record", "w")
if f then f:write(j); f:close() end
end
end

local BATAS_JATAH_FREE = 3
local JEDA_RESET_DETIK = 24 * 60 * 60

-- Jendela jatah: 24 jam dihitung dari pemakaian PERTAMA. Setelah 24 jam itu lewat, hitungan kembali 0
-- dan pemakaian berikutnya memulai jendela baru. Mengembalikan true bila baru saja diriset.
local function ResetLimitJikaSudahLewat(brankas, myId, tipeFitur)
local data = brankas[myId]
if not data then return false end
local pakai = tonumber(data[tipeFitur]) or 0
if pakai <= 0 then return false end
local kunciMulai = "waktu_mulai_" .. tipeFitur
local kunciLama = "waktu_limit_" .. tipeFitur
local sekarang = os.time()
local mulai = tonumber(data[kunciMulai])
local berubah = false
if not mulai then
-- Data versi lama: pakai catatan waktu limit lama bila ada, kalau tidak mulai hitung dari sekarang
mulai = tonumber(data[kunciLama]) or sekarang
data[kunciMulai] = mulai
data[kunciLama] = nil
berubah = true
end
-- Jam HP diundur jauh ke belakang: mulai hitung dari sekarang
if mulai > sekarang + JEDA_RESET_DETIK then
mulai = sekarang
data[kunciMulai] = mulai
berubah = true
end
if sekarang >= mulai + JEDA_RESET_DETIK then
data[tipeFitur] = 0
data[kunciMulai] = nil
data[kunciLama] = nil
SimpanDataBrankas(brankas)
return true
end
if berubah then SimpanDataBrankas(brankas) end
return false
end

local function CekKuotaFreemium(tipeFitur, onDiizinkan)
local myId = DapatkanAndroidID()
if ADMIN_IDS[myId] or ADMIN_KEDUA_IDS[myId] or ADMIN_KETIGA_IDS[myId] or JATAH.aktif(tipeFitur) then onDiizinkan(); return end
local brankas = AmbilDataBrankas()
if not brankas[myId] then brankas[myId] = {} end
ResetLimitJikaSudahLewat(brankas, myId, tipeFitur)
local pakai = tonumber(brankas[myId][tipeFitur]) or 0
if pakai >= BATAS_JATAH_FREE then
local dLimit = UI_Dialog(T("jatah_habis", "Batas Harian Tercapai"))
dLimit.setMessage(T("teks_habis_kuota", "Jatah harian Anda untuk fitur ini sudah habis. Jatah akan pulih 24 jam setelah pemakaian pertama, atau tingkatkan ke Premium untuk menggunakan fitur ini tanpa batas."))
dLimit.setButton(T("tingkatkan_premium", "Tingkatkan ke Premium"), function() 
dLimit.dismiss()
if BukaMenuPremiumGaib then BukaMenuPremiumGaib() else service.speak(T("buka_menu_utama", "Silakan buka menu Tingkatkan ke Premium di Menu Utama.")) end
end)
dLimit.setButton2(T("tutup", "Tutup"), function() dLimit.dismiss() end)
dLimit.setCancelable(false)
dLimit.show()
else
onDiizinkan()
end
end

local function CatatPemakaianFreemium(tipeFitur, isSilent)
local myId = DapatkanAndroidID()
if ADMIN_IDS[myId] or ADMIN_KEDUA_IDS[myId] or ADMIN_KETIGA_IDS[myId] or JATAH.aktif(tipeFitur) then return end
local brankas = AmbilDataBrankas()
if not brankas[myId] then brankas[myId] = {} end
ResetLimitJikaSudahLewat(brankas, myId, tipeFitur)
local jatahSekarang = tonumber(brankas[myId][tipeFitur]) or 0
-- Jatah sudah penuh: jangan menambah dan jangan menyentuh waktu mulai (agar kunci tidak diperpanjang)
if jatahSekarang < BATAS_JATAH_FREE then
if jatahSekarang == 0 or not brankas[myId]["waktu_mulai_" .. tipeFitur] then
brankas[myId]["waktu_mulai_" .. tipeFitur] = os.time()
end
jatahSekarang = jatahSekarang + 1
brankas[myId][tipeFitur] = jatahSekarang
SimpanDataBrankas(brankas)
end

if not isSilent then
local dInfo = UI_Dialog(T("informasi", "Informasi"))
if jatahSekarang == 1 then dInfo.setMessage(T("jatah_1_dari_3", "Anda telah menggunakan jatah sebanyak satu dari tiga."))
elseif jatahSekarang == 2 then dInfo.setMessage(T("jatah_2_dari_3", "Anda telah menggunakan jatah sebanyak dua dari tiga."))
else dInfo.setMessage(T("jatah_3_dari_3", "Anda telah menggunakan jatah sebanyak tiga dari tiga. Limit Anda untuk perintah tersebut telah selesai. Jatah pulih 24 jam setelah pemakaian pertama, atau berlangganan ke premium.")) end
dInfo.setButton(T("tombol_oke", "Oke"), function() dInfo.dismiss() end)
dInfo.setCancelable(false)
dInfo.show()
end
return jatahSekarang
end

local function CekSisaKuotaTTS()
local myId = DapatkanAndroidID()
if ADMIN_IDS[myId] or ADMIN_KEDUA_IDS[myId] or ADMIN_KETIGA_IDS[myId] or JATAH.aktif("tts_jam") then return true end
local brankas = AmbilDataBrankas()
ResetLimitJikaSudahLewat(brankas, myId, "tts_jam")
local pakai = (brankas[myId] and tonumber(brankas[myId]["tts_jam"])) or 0
return pakai < BATAS_JATAH_FREE
end

local function showInputDialog(title, hint, defaultText, onSave, onCancel, allowSpecialChars)
local inputDialog = UI_Dialog(title)
local layout = UI_Layout(
{EditText, id="dialogInputEt", layout_width="fill", layout_marginBottom="8dp"},
{LinearLayout, orientation="horizontal", layout_width="fill",
UI_Tombol_H("dialogBtnBatal", T("batal", "Batal")),
UI_Tombol_H("dialogBtnSimpan", T("simpan", "Simpan"))
}
)
inputDialog.setView(loadlayout(layout))

if hint and hint ~= "" then dialogInputEt.setHint(hint) end
if defaultText and defaultText ~= "" then dialogInputEt.setText(defaultText) end

dialogBtnSimpan.onClick = function()
local txt = tostring(dialogInputEt.getText()):match("^%s*(.-)%s*$") or ""
if txt == "" then
service.speak(T("tidak_boleh_kosong", "Kotak teks tidak boleh kosong!"))
return
end
if not allowSpecialChars and txt:match('[/\\:*?"<>|]') then
service.speak(T("karakter_terlarang", "Nama tidak boleh mengandung karakter khusus seperti garis miring, titik dua, atau bintang."))
return
end
local result = onSave(txt, inputDialog)
if result ~= false then
inputDialog.dismiss()
end
end

dialogBtnBatal.onClick = function()
inputDialog.dismiss()
if onCancel then onCancel() end
end

inputDialog.setOnCancelListener(function() if onCancel then onCancel() end end)
inputDialog.show()
end

local function showConfirmDialog(title, message, onOk, onCancel)
local confirmDialog = UI_Dialog(title)
confirmDialog.setMessage(message)
confirmDialog.setButton(T("konfirmasi", "Konfirmasi"), onOk)
confirmDialog.setButton2(T("batal", "Batal"), function() if onCancel then onCancel() end end)
confirmDialog.setOnCancelListener(function() if onCancel then onCancel() end end)
confirmDialog.show()
end

local function hentikanAudioGlobal()
if globalMediaPlayer then
pcall(function()
if globalMediaPlayer.isPlaying() then globalMediaPlayer.stop() end
end)
end
end

-- ==========================================================================
-- MENU "AKSI" PEMBACA LAYAR UNTUK BARIS DAFTAR (AksiDex)
-- Kelas Java kecil ada di berkas aksi.dex (folder utama atau folder bahasa).
-- Aksi diambil langsung dari menu ketuk tahan yang sudah ada (ditangkap, tidak ditampilkan),
-- ditambah satu aksi untuk fungsi ketuk. Tabel global agar tidak menambah variabel lokal.
-- ==========================================================================
AksiDex = {}
AksiDex.NAMA_BERKAS = "aksi.dex"
AksiDex.NAMA_KELAS = "AksiDex"
AksiDex.tangkap = nil
AksiDex.RESERVED = {"main.lua", "data.dat", "data_iven.json", "daftar_admin.json", "terenkripsi.lua", "file_kustom.json"}

-- Dialog palsu: dipakai saat menangkap isi menu ketuk tahan. Tidak tampil, hanya mencatat.
AksiDex.dialogPalsu = function()
local t = AksiDex.tangkap
local f = {}
setmetatable(f, { __index = function(_, k) return function() end end })
f.setItems = function(o) t.opsi = o end
f.setOnItemClickListener = function(fn) t.klik = fn end
return f
end

AksiDex.muat = function()
if AksiDex._kelas ~= nil then return AksiDex._kelas or nil end
AksiDex._kelas = false
local ok, err = pcall(function()
local asli = nil
local dirCari = {BASE, langDir}
for i = 1, #dirCari do
local f = File(dirCari[i] .. AksiDex.NAMA_BERKAS)
if f.exists() then asli = f; break end
end
if not asli then error("aksi.dex tidak ditemukan") end

-- Kelas disimpan di sisi Java (tahan dari tutup dan jalankan ulang skrip), karena tabel
-- Lua ikut hilang saat skrip ditutup tapi pembaca layar tetap hidup. Tanpa ini, muat ulang
-- berkas dex yang sama di proses yang sama bisa gagal.
local kunci = "aksi_dex_kelas:" .. asli.getAbsolutePath() .. ":" .. tostring(asli.lastModified()) .. ":" .. tostring(asli.length())
local props = luajava.bindClass("java.lang.System").getProperties()
local tersimpan = nil
pcall(function() tersimpan = props.get(kunci) end)
if tersimpan ~= nil then
AksiDex._kelas = tersimpan
return
end

local dirDex = File(service.getCacheDir(), "aksi_dex")
dirDex.mkdirs()
local dirOpt = File(service.getCacheDir(), "aksi_odex")
dirOpt.mkdirs()
-- bersihkan salinan lama (yang sudah termuat tetap aman di memori)
local function bersihkan(dir)
pcall(function()
local daftar = dir.listFiles()
if daftar then
for i = 0, #daftar - 1 do
local x = daftar[i]
x.setWritable(true)
x.delete()
end
end
end)
end
bersihkan(dirDex)
bersihkan(dirOpt)

-- nama salinan unik tiap muat, supaya tidak bentrok dengan dex lama yang masih termuat
local salinan = File(dirDex, "aksi_" .. tostring(os.time()) .. ".dex")
SalinFile(asli.getAbsolutePath(), salinan.getAbsolutePath())
salinan.setReadOnly()
local cL = luajava.bindClass("dalvik.system.DexClassLoader")(salinan.getAbsolutePath(), dirOpt.getAbsolutePath(), nil, service.getClassLoader())
local kelas = cL.loadClass(AksiDex.NAMA_KELAS)
AksiDex._kelas = kelas
pcall(function() props.put(kunci, kelas) end)
end)
if not ok then
AksiDex.galat = tostring(err)
pcall(function() service.speak("Aksi gagal dimuat: " .. AksiDex.galat:sub(1, 150)) end)
end
return AksiDex._kelas or nil
end

-- Susun daftar aksi untuk baris ke-p: aksi ketuk (kalau ada) lalu isi menu ketuk tahan.
AksiDex.daftarUntuk = function(lv, p, opsi)
local hasil = {}
if opsi.modePilih and opsi.modePilih() then return hasil end
local labelKlik = opsi.labelKlik
if type(labelKlik) == "function" then labelKlik = labelKlik(p) end
-- listener tidak bisa dibaca lewat lv.onItemClick, pakai getter Android
local klik = nil
pcall(function() klik = lv.getOnItemClickListener() end)
if labelKlik and klik then
hasil[#hasil + 1] = { label = labelKlik, kode = function() klik.onItemClick(lv, nil, p, 0) end }
end
local tahan = nil
pcall(function() tahan = lv.getOnItemLongClickListener() end)
if tahan then
local t = { opsi = nil, klik = nil }
AksiDex.tangkap = t
pcall(function() tahan.onItemLongClick(lv, nil, p, 0) end)
AksiDex.tangkap = nil
if t.opsi and t.klik then
local tutup = T("tutup", "Tutup")
for i = 1, #t.opsi do
local lbl = tostring(t.opsi[i])
if lbl ~= tutup then
local idx = i
hasil[#hasil + 1] = { label = lbl, kode = function() t.klik(nil, nil, idx - 1, 0) end }
end
end
end
end
return hasil
end

-- opsi = { labelKlik = "teks" atau function(p), modePilih = function() return true/false end }
AksiDex.pasang = function(lv, opsi)
pcall(function()
if tostring(lv.getTag()) == "aksi_dex" then return end
lv.setTag("aksi_dex")
local function pasangPadaBaris(anak)
pcall(function()
local kelas = AksiDex.muat()
if not kelas then return end
local cur = anak.getAccessibilityDelegate()
if cur ~= nil and kelas.isInstance(cur) then return end
local d = kelas.newInstance()
d.sambungKeInduk(anak)
d.bisaDifokuskan()
d.penyegar(luajava.createProxy("java.lang.Runnable", { run = function()
d.kosongkan()
local p = lv.getPositionForView(anak)
if p < 0 then return end
local daftar = AksiDex.daftarUntuk(lv, p, opsi)
for n = 1, #daftar do
local nomor = n
d.aksi(tostring(daftar[n].label), luajava.createProxy("java.lang.Runnable", { run = function()
local pos = lv.getPositionForView(anak)
if pos < 0 then return end
local lagi = AksiDex.daftarUntuk(lv, pos, opsi)
if lagi[nomor] then lagi[nomor].kode() end
end }))
end
end }))
anak.setAccessibilityDelegate(d)
end)
end
lv.setOnHierarchyChangeListener(luajava.createProxy("android.view.ViewGroup$OnHierarchyChangeListener", {
onChildViewAdded = function(induk, anak) pasangPadaBaris(anak) end,
onChildViewRemoved = function(induk, anak) end
}))
-- ListView melepas delegate saat baris didaur ulang: cek ulang tiap selesai tata letak
-- DAN tiap daftar bergulir. Baris daur ulang dipasang kembali tanpa tata letak ulang dan
-- tanpa kabar onChildViewAdded, jadi tanpa pemeriksaan saat gulir, baris itu kehilangan aksi.
local function periksaSemuaBaris()
pcall(function()
for i = 0, lv.getChildCount() - 1 do pasangPadaBaris(lv.getChildAt(i)) end
end)
end
pcall(function()
lv.getViewTreeObserver().addOnGlobalLayoutListener(luajava.createProxy("android.view.ViewTreeObserver$OnGlobalLayoutListener", {
onGlobalLayout = periksaSemuaBaris
}))
end)
pcall(function()
lv.getViewTreeObserver().addOnScrollChangedListener(luajava.createProxy("android.view.ViewTreeObserver$OnScrollChangedListener", {
onScrollChanged = periksaSemuaBaris
}))
end)
end)
end

-- ----- Upload berkas kustom ke GitHub (misalnya aksi.dex) -----
AksiDex.namaValid = function(nama)
if type(nama) ~= "string" then return false end
if #nama < 3 or #nama > 60 then return false end
if nama:find("%.%.") then return false end
if not nama:match("^[%w_%-][%w%._%-]*%.%w+$") then return false end
local kecil = nama:lower()
for i = 1, #AksiDex.RESERVED do
if kecil == AksiDex.RESERVED[i] then return false end
end
return true
end

-- Kotak isian: nama berkas + format, dan pilihan lokasi. Kalau salah, kotak tidak ditutup.
AksiDex.dialogTambahKustom = function(onTambah)
local d = UI_Dialog("Tambah File Kustom")
local lay = UI_Layout(
UI_Input("etNamaKustom", "Nama file lengkap dengan format, contoh: aksi.dex"),
UI_Tombol("btnLokasiKustom", "Lokasi: Folder utama (sama dengan main.lua)"),
{LinearLayout, orientation="horizontal", layout_width="fill",
UI_Tombol_H("btnBatalKustom", "Batal"),
UI_Tombol_H("btnTambahKustomOk", "Tambah")
}
)
d.setView(loadlayout(lay))
local folder = "luar"
btnLokasiKustom.onClick = function()
if folder == "luar" then
folder = "bahasa"
btnLokasiKustom.setText("Lokasi: Folder bahasa")
else
folder = "luar"
btnLokasiKustom.setText("Lokasi: Folder utama (sama dengan main.lua)")
end
end
btnBatalKustom.onClick = function() d.dismiss() end
btnTambahKustomOk.onClick = function()
local nama = tostring(etNamaKustom.getText()):match("^%s*(.-)%s*$") or ""
if not AksiDex.namaValid(nama) then
service.speak("Nama file tidak valid. Tulis nama lengkap dengan format, tanpa spasi atau garis miring, misalnya aksi.dex.")
return
end
local dir = (folder == "bahasa") and langDir or BASE
local namaFolder = (folder == "bahasa") and "folder bahasa" or "folder utama"
if not File(dir .. nama).exists() then
service.speak("File " .. nama .. " tidak ditemukan di " .. namaFolder .. ". Periksa nama dan lokasinya.")
return
end
d.dismiss()
onTambah({
name = nama .. " (kustom, " .. namaFolder .. ")",
localPath = dir .. nama,
repoPath = ((folder == "bahasa") and "bahasa/" or "") .. nama,
kustom = true, nama = nama, folder = folder
})
end
d.show()
end

-- Sebelum upload: gabungkan daftar kustom dari server dengan yang baru, lalu ikut diunggah
-- sebagai file_kustom.json supaya pengguna tahu berkas apa saja yang harus diunduh dan ke mana.
AksiDex.siapkanManifest = function(token, terpilih, selesai)
local kustom = {}
for i = 1, #terpilih do
if terpilih[i].kustom then kustom[#kustom + 1] = terpilih[i] end
end
if #kustom == 0 then selesai(true); return end
task(kerjaAmbilManifestKustom, cjson.encode({ token = token }), function(json)
local r = {}
pcall(function() r = cjson.decode(tostring(json)) end)
if r.ok ~= true then selesai(false, "Gagal membaca daftar file kustom dari server."); return end
local daftar = r.daftar or {}
for i = 1, #kustom do
local ada = false
for j = 1, #daftar do
if daftar[j].nama == kustom[i].nama and daftar[j].folder == kustom[i].folder then ada = true end
end
if not ada then daftar[#daftar + 1] = { nama = kustom[i].nama, folder = kustom[i].folder } end
end
local f = io.open(BASE .. "file_kustom.json", "w")
if not f then selesai(false, "Gagal menulis file_kustom.json di folder utama."); return end
f:write(cjson.encode(daftar))
f:close()
table.insert(terpilih, { name = "file_kustom.json (daftar file kustom)", localPath = BASE .. "file_kustom.json", repoPath = "file_kustom.json" })
selesai(true)
end)
end

-- ==========================================================================
-- EFEK SUARA JAM (Reverb, Echo, Naik Turun Nada) untuk Pembuat Jam Bicara
-- Mesin: FastMuxer.dex + libnadivoice64.so / libnadivoice32.so di folder skrip ini.
-- Tabel global agar tidak menambah jumlah variabel lokal pada skrip utama.
-- ==========================================================================
EfekJam = {}
EfekJam.KUNCI_EFEK = { nada = "efek_nada", echo = "efek_echo", reverb = "efek_reverb" }
EfekJam.URUTAN = { "nada", "echo", "reverb" }

EfekJam.adalahAdmin = function()
local myId = DapatkanAndroidID()
return (ADMIN_IDS[myId] or ADMIN_KEDUA_IDS[myId] or ADMIN_KETIGA_IDS[myId]) and true or false
end

-- Jatah dihitung PER EFEK: tiap efek (nada, echo, reverb) punya jatah 3 kali sendiri-sendiri per hari.
-- True kalau efek ini boleh dipakai (admin, hadiah Klaim Jatah, atau jatah hariannya belum habis).
EfekJam.punyaJatah = function(nama)
if EfekJam.adalahAdmin() then return true end
local kunci = EfekJam.KUNCI_EFEK[nama]
if JATAH.aktif(kunci) then return true end
local myId = DapatkanAndroidID()
local brankas = AmbilDataBrankas()
if not brankas[myId] then brankas[myId] = {} end
ResetLimitJikaSudahLewat(brankas, myId, kunci)
return (tonumber(brankas[myId][kunci]) or 0) < BATAS_JATAH_FREE
end

-- Daftar nama efek yang ada di konfigurasi (urut: nada, echo, reverb)
EfekJam.efekDalamCfg = function(cfg)
local ada, daftar = {}, {}
if not cfg then return daftar end
for baris in string.gmatch(cfg, "[^\n]+") do
local nm = string.match(baris, "^(%a+)=")
if nm then ada[nm] = true end
end
for _, nama in ipairs(EfekJam.URUTAN) do
if ada[nama] then table.insert(daftar, nama) end
end
return daftar
end

EfekJam.labelEfek = function(nama)
return JATAH.label(EfekJam.KUNCI_EFEK[nama])
end

-- Membaca nilai angka dari pengaturan (disimpan sebagai Float)
EfekJam.ambilAngka = function(kunci, awal)
local ok, v = pcall(function() return pref.getFloat(kunci, awal) end)
if ok and v then return tonumber(v) or awal end
return awal
end

EfekJam.simpanAngka = function(kunci, nilai)
pcall(function() pref.edit().putFloat(kunci, nilai).apply() end)
end

EfekJam.simpanBool = function(kunci, nilai)
pcall(function() pref.edit().putBoolean(kunci, nilai).apply() end)
end

EfekJam.fmtAngka = function(v)
if v == math.floor(v) then return string.format("%d", v) end
local s = string.format("%.3f", v)
s = string.gsub(s, "0+$", "")
return s
end

-- Menyusun konfigurasi untuk mesin (satu baris per efek). Mengembalikan nil bila tidak ada efek aktif.
-- abaikanSaklar = true dipakai oleh pratinjau supaya efek bisa dicoba walau saklar utama mati.
-- Efek yang jatah hariannya habis dibuang dari hasil, kecuali tanpaFilter = true.
EfekJam.ambilCfg = function(abaikanSaklar, tanpaFilter)
if not abaikanSaklar and not pref.getBoolean("efek_aktif", false) then return nil end
local baris = {}
if pref.getBoolean("efek_nada_on", false) and (abaikanSaklar or tanpaFilter or EfekJam.punyaJatah("nada")) then
local lanjut = pref.getBoolean("efek_nada_lanjut", false) and 1 or 0
table.insert(baris, string.format("nada=1,%s,%d,%d,%s,%s,%s", EfekJam.fmtAngka(EfekJam.ambilAngka("efek_nada_semi", 0)), lanjut,
pref.getBoolean("efek_nada_gl", false) and 1 or 0,
EfekJam.fmtAngka(EfekJam.ambilAngka("efek_nada_g0", 0)), EfekJam.fmtAngka(EfekJam.ambilAngka("efek_nada_g1", 4)), EfekJam.fmtAngka(EfekJam.ambilAngka("efek_nada_gd", 0))))
end
local adaGema = false
if pref.getBoolean("efek_ec_on", false) and (abaikanSaklar or tanpaFilter or EfekJam.punyaJatah("echo")) then
adaGema = true
table.insert(baris, string.format("echo=1,%s,%s,%s,%s,%s,%s",
EfekJam.fmtAngka(EfekJam.ambilAngka("efek_ec_dly", 300)),
EfekJam.fmtAngka(EfekJam.ambilAngka("efek_ec_fb", 30) / 100),
EfekJam.fmtAngka(EfekJam.ambilAngka("efek_ec_damp", 50) / 100),
EfekJam.fmtAngka(EfekJam.ambilAngka("efek_ec_dry", 100) / 100),
EfekJam.fmtAngka(EfekJam.ambilAngka("efek_ec_wet", 30) / 100),
EfekJam.fmtAngka(EfekJam.ambilAngka("efek_ec_st", 50) / 100)))
end
if pref.getBoolean("efek_rv_on", false) and (abaikanSaklar or tanpaFilter or EfekJam.punyaJatah("reverb")) then
adaGema = true
table.insert(baris, string.format("reverb=1,%s,%s,%s,%s,%s",
EfekJam.fmtAngka(EfekJam.ambilAngka("efek_rv_room", 50) / 100),
EfekJam.fmtAngka(EfekJam.ambilAngka("efek_rv_damp", 50) / 100),
EfekJam.fmtAngka(EfekJam.ambilAngka("efek_rv_dry", 70) / 100),
EfekJam.fmtAngka(EfekJam.ambilAngka("efek_rv_wet", 30) / 100),
EfekJam.fmtAngka(EfekJam.ambilAngka("efek_rv_st", 50) / 100)))
end
if #baris == 0 then return nil end
if adaGema then
table.insert(baris, "ekor=" .. EfekJam.fmtAngka(EfekJam.ambilAngka("efek_ekor_ms", 500)))
end
return table.concat(baris, "\n")
end

-- Memuat mesin (dex + so) sekali saja. Mengembalikan true, atau false beserta alasannya.
EfekJam.muatMesin = function()
if EfekJam._metode then return true end
local dexAsli = BASE .. "FastMuxer.dex"
if not File(dexAsli).exists() then
return false, T("efekjam_mesin_tidak_ada", "File mesin efek (FastMuxer.dex) tidak ditemukan di folder skrip.")
end
local okMuat, galat = pcall(function()
local Sys = luajava.bindClass("java.lang.System")
local is64 = true
pcall(function() is64 = luajava.bindClass("android.os.Process").is64Bit() end)
Sys.setProperty("nadi.so.file", BASE .. (is64 and "libnadivoice64.so" or "libnadivoice32.so"))
Sys.setProperty("nadi.so.cache", service.getCacheDir().getAbsolutePath())
local dirDex = File(service.getCacheDir(), "efek_dex")
dirDex.mkdirs()
local salinan = File(dirDex, "FastMuxer.dex")
if salinan.exists() then salinan.setWritable(true); salinan.delete() end
SalinFile(dexAsli, salinan.getAbsolutePath())
salinan.setReadOnly()
local dirOpt = File(service.getCacheDir(), "efek_odex")
dirOpt.mkdirs()
local cL = luajava.bindClass("dalvik.system.DexClassLoader")(salinan.getAbsolutePath(), dirOpt.getAbsolutePath(), nil, service.getClassLoader())
local kls = cL.loadClass("FastMuxer")
local tipeString = luajava.bindClass("java.lang.String")
local tipe = luajava.newArray(luajava.bindClass("java.lang.Class"), 3)
tipe[0] = tipeString
tipe[1] = tipeString
tipe[2] = tipeString
EfekJam._metode = kls.getMethod("terapkanEfekJam", tipe)
local tipe5 = luajava.newArray(luajava.bindClass("java.lang.Class"), 5)
for i = 0, 4 do tipe5[i] = tipeString end
EfekJam._metodeLive = nil
pcall(function() EfekJam._metodeLive = kls.getMethod("jamPerintah", tipe5) end)
end)
if not okMuat then
EfekJam._metode = nil
return false, T("efekjam_mesin_gagal", "Mesin efek gagal dimuat: ") .. tostring(galat)
end
return true
end

-- Menerapkan efek pada satu berkas. Hasil ditulis ke berkas lain (outPath).
EfekJam.terapkan = function(inPath, outPath, cfg)
local ok, pesan = EfekJam.muatMesin()
if not ok then return false, pesan end
local hasil = ""
local okPanggil, galat = pcall(function()
local arg = luajava.newArray(luajava.bindClass("java.lang.Object"), 3)
arg[0] = inPath
arg[1] = outPath
arg[2] = cfg
hasil = tostring(EfekJam._metode.invoke(nil, arg))
end)
if not okPanggil then return false, tostring(galat) end
if hasil ~= "SUKSES" then return false, hasil end
return true
end

EfekJam.namaKeluaran = function(path)
return (string.gsub(path, "(%.%w+)$", ".fx%1"))
end

-- Daftar berkas berekstensi tertentu di folder hour, minute, hourly.
EfekJam.kumpulFile = function(folder, ekstensi)
local daftar = {}
local subFolder = { "hour", "minute", "hourly" }
for _, nama in ipairs(subFolder) do
local files = File(folder .. "/" .. nama).listFiles()
if files then
for i = 0, #files - 1 do
local n = files[i].getName()
if string.sub(n, -#ekstensi) == ekstensi then table.insert(daftar, files[i].getAbsolutePath()) end
end
end
end
return daftar
end

-- Menerapkan efek pada banyak berkas sekaligus (semua berhasil atau tidak ada yang diubah).
-- onSelesai(sukses, pesan) dipanggil di thread utama.
-- Fungsi kerja untuk task (Lua state terpisah). Mesin efek sudah dimuat di Lua state utama; objek Method-nya
-- dibagikan lewat System.getProperties() supaya mesin dan library native-nya hanya dimuat satu kali.
-- Kemajuan dilaporkan lewat System property "nadi_prog_efek" berformat "<selesai>\t<path>".
EfekJam.kerja = function(jsonArgs)
require "import"
local luajava = require("luajava")
import "java.io.File"
local cjson = require "cjson"
local System = luajava.bindClass("java.lang.System")
local a = cjson.decode(jsonArgs)
local metode = System.getProperties().get("nadi.efek.metode")
if not metode then
return cjson.encode({ ok = false, pesan = "Mesin efek belum dimuat" })
end
local keluaran = {}
local galat = nil
local batal = false
for i, p in ipairs(a.tugas) do
if tostring(System.getProperty("nadi_batal")) == "1" then batal = true; break end
System.setProperty("nadi_prog_efek", tostring(i - 1) .. "\t" .. tostring(p))
local out = (string.gsub(p, "(%.%w+)$", ".fx%1"))
File(out).delete()
local hasil = ""
local okP, g = pcall(function()
local arg = luajava.newArray(luajava.bindClass("java.lang.Object"), 3)
arg[0] = p
arg[1] = out
arg[2] = a.cfg
hasil = tostring(metode.invoke(nil, arg))
end)
if not okP then galat = tostring(g); break end
if hasil ~= "SUKSES" or not File(out).exists() then galat = hasil; break end
table.insert(keluaran, out)
end
if galat or batal then
for _, o in ipairs(keluaran) do File(o).delete() end
return cjson.encode({ ok = false, batal = batal, pesan = galat or "__batal__" })
end
for i, p in ipairs(a.tugas) do
local src = File(p)
src.delete()
File(keluaran[i]).renameTo(src)
end
System.setProperty("nadi_prog_efek", "")
return cjson.encode({ ok = true })
end

-- Menerapkan efek pada banyak berkas sekaligus (semua berhasil atau tidak ada yang diubah).
-- Pekerjaan berat berjalan di task. onSelesai(sukses, pesan) dipanggil di thread utama.
EfekJam.terapkanDaftar = function(daftar, cfg, onSelesai)
local ada = {}
for _, p in ipairs(daftar) do
local f = File(p)
if f.exists() and f.length() > 44 then table.insert(ada, p) end
end
if #ada == 0 then
onSelesai(false, T("efekjam_tidak_ada_berkas", "Tidak ada berkas suara yang bisa diberi efek."))
return
end
local okMesin, pesanMesin = EfekJam.muatMesin()
if not okMesin then
onSelesai(false, pesanMesin)
return
end
pcall(function() luajava.bindClass("java.lang.System").getProperties().put("nadi.efek.metode", EfekJam._metode) end)

local milik = not ProgresJam.aktif
if milik then ProgresJam.mulai({ { k = "efek", b = 1 } }, T("efekjam_menerapkan", "Menerapkan efek suara, mohon tunggu...")) end
ProgresJam.tahap("efek", T("efekjam_menerapkan", "Menerapkan efek suara, mohon tunggu..."))
local total = #ada
local berhenti = ProgresJam.pantau("nadi_prog_efek", function(teks)
local selesai, path = string.match(teks, "^(%d+)\t(.*)$")
if not selesai then return end
ProgresJam.maju(tonumber(selesai) / total, T("prog_efek", "Menerapkan efek: ") .. ProgresJam.labelBerkas(path), false)
end)
local argumen = cjson.encode({ tugas = ada, cfg = cfg })
uiHandler.postDelayed(Runnable({
run = function()
task(EfekJam.kerja, argumen, function(json)
berhenti()
local r = {}
local okD = pcall(function() r = cjson.decode(tostring(json)) end)
if milik then ProgresJam.selesai() end
if okD and type(r) == "table" and r.ok then
onSelesai(true)
else
onSelesai(false, (okD and type(r) == "table" and r.pesan) or tostring(json))
end
end)
end
}), 80)
end

-- Mencatat satu pemakaian jatah harian efek (pengguna gratis). Mengembalikan teks info untuk diucapkan.
EfekJam.catatInfo = function(cfg)
local info = {}
for _, nama in ipairs(EfekJam.efekDalamCfg(cfg)) do
local n = CatatPemakaianFreemium(EfekJam.KUNCI_EFEK[nama], true)
if n then
local t = T("efekjam_jatah_efek", "Jatah [E] hari ini terpakai [N] dari 3.")
t = string.gsub(t, "%[E%]", EfekJam.labelEfek(nama))
t = string.gsub(t, "%[N%]", tostring(n))
table.insert(info, t)
end
end
if #info == 0 then return "" end
return " " .. table.concat(info, " ")
end

-- Menentukan apakah sesi pembuatan jam ini memakai efek. onLanjut(true/false), onBatal().
EfekJam.siapkanSesi = function(onLanjut, onBatal)
local cfg = EfekJam.ambilCfg(false, true)
if not cfg then onLanjut(false); return end
local okMesin, pesanMesin = EfekJam.muatMesin()
if not okMesin then
local dM = UI_Dialog(T("efekjam_judul", "Pengaturan Efek Suara"))
dM.setMessage(tostring(pesanMesin) .. "\n\n" .. T("efekjam_lanjut_tanpa_tanya", "Lanjutkan membuat jam tanpa efek?"))
dM.setButton(T("efekjam_lanjut_tanpa", "Lanjut Tanpa Efek"), function() onLanjut(false) end)
dM.setButton2(T("batal", "Batal"), function() onBatal() end)
dM.setOnCancelListener(function() onBatal() end)
dM.show()
return
end
if EfekJam.adalahAdmin() then onLanjut(true); return end
local cfgBoleh = EfekJam.ambilCfg(false)
if cfgBoleh then
if cfgBoleh == cfg then onLanjut(true); return end
-- Sebagian efek jatahnya habis: efek itu dilewati, sisanya tetap dipakai
local habis = {}
local masihBoleh = {}
for _, nama in ipairs(EfekJam.efekDalamCfg(cfgBoleh)) do masihBoleh[nama] = true end
for _, nama in ipairs(EfekJam.efekDalamCfg(cfg)) do
if not masihBoleh[nama] then table.insert(habis, EfekJam.labelEfek(nama)) end
end
local dS = UI_Dialog(T("efekjam_sebagian_judul", "Jatah Sebagian Efek Habis"))
dS.setMessage(T("efekjam_sebagian_teks", "Jatah harian efek berikut sudah habis dan akan dilewati:\n- ") .. table.concat(habis, "\n- ") .. T("efekjam_sebagian_lanjut", "\n\nEfek lainnya tetap dipakai. Lanjutkan?"))
dS.setButton(T("lanjut", "Lanjut"), function() onLanjut(true) end)
dS.setButton2(T("batal", "Batal"), function() onBatal() end)
dS.setOnCancelListener(function() onBatal() end)
dS.show()
return
end
local dL = UI_Dialog(T("efekjam_habis_judul", "Jatah Efek Harian Habis"))
dL.setMessage(T("efekjam_habis_teks", "Jatah efek suara Anda hari ini sudah habis dan akan pulih 24 jam setelah pemakaian pertama. Anda bisa melanjutkan membuat jam tanpa efek, atau tingkatkan ke Premium."))
dL.setButton(T("efekjam_lanjut_tanpa", "Lanjut Tanpa Efek"), function() onLanjut(false) end)
dL.setButton2(T("tingkatkan_premium", "Tingkatkan ke Premium"), function()
if BukaMenuPremiumGaib then BukaMenuPremiumGaib() else service.speak(T("buka_menu_utama", "Silakan buka menu Tingkatkan ke Premium di Menu Utama.")) end
onBatal()
end)
dL.setButton3(T("batal", "Batal"), function() onBatal() end)
dL.setOnCancelListener(function() onBatal() end)
dL.show()
end

-- Peringatan saat keluar di tengah perekaman suara sendiri: sesi tetap dihitung satu pemakaian.
-- simpanDraf() menyimpan draf; onKeluar() lanjut keluar; onLanjut() kembali merekam.
EfekJam.peringatanKeluar = function(draf, simpanDraf, onKeluar, onLanjut)
if (not draf) or (not draf.efek_cfg) or draf.efek_dihitung or EfekJam.adalahAdmin() then
onKeluar()
return
end
local d = UI_Dialog(T("efekjam_keluar_judul", "Keluar dari Rekaman?"))
d.setMessage(T("efekjam_keluar_teks", "Jika Anda keluar sekarang, sesi pembuatan jam dengan efek ini tetap dihitung satu kali pemakaian hari ini. Tetap keluar?"))
d.setButton(T("efekjam_keluar_ya", "Keluar"), function()
EfekJam.catatInfo(draf.efek_cfg)
draf.efek_dihitung = true
pcall(simpanDraf)
onKeluar()
end)
d.setButton2(T("efekjam_keluar_lanjut", "Lanjut Merekam"), function() onLanjut() end)
d.setOnCancelListener(function() onLanjut() end)
d.setCancelable(false)
d.show()
end

-- ===== Kontrol angka (Kurangi, Tambah, Langkah) seperti di main_1.lua =====
EfekJam.pasangKlik = function(view, aksi)
view.onClick = function() aksi() end
end

-- Satu baris pengaturan angka. d = {k, label, min, max, langkah = {..}, satuan, ucap, awal}
-- Mengembalikan fungsi untuk menyegarkan tampilan setelah nilai diubah dari luar (preset).
EfekJam.barisAngka = function(lay, st, d, onUbah)
local tv = TextView(service)
tv.setTextSize(16)
tv.setPadding(0, 24, 0, 0)
local iLangkah = 1
local function tampil()
tv.setText(d.label .. ": " .. EfekJam.fmtAngka(st[d.k]) .. (d.satuan or ""))
end
local function terapkan(v)
local batas = nil
if v < d.min then v = d.min; batas = T("efekjam_batas_bawah", "Batas bawah tercapai.") end
if v > d.max then v = d.max; batas = T("efekjam_batas_atas", "Batas atas tercapai.") end
st[d.k] = v
tampil()
local ucapan = EfekJam.fmtAngka(v) .. (d.ucap or "")
if batas then ucapan = batas .. " " .. ucapan end
service.speak(ucapan)
if onUbah then onUbah() end
end
tampil()
EfekJam.pasangKlik(tv, function()
showInputDialog(d.label .. " (" .. EfekJam.fmtAngka(d.min) .. " - " .. EfekJam.fmtAngka(d.max) .. ")", "", EfekJam.fmtAngka(st[d.k]), function(txt)
local v = tonumber((string.gsub(txt, ",", ".")))
if not v then service.speak(T("efekjam_bukan_angka", "Isi dengan angka.")); return false end
terapkan(v)
return true
end, nil, true)
end)
lay.addView(tv)
local baris = LinearLayout(service)
baris.setOrientation(0)
local function tombol(teks, aksi)
local b = Button(service)
b.setText(teks)
b.onClick = function() aksi() end
baris.addView(b, LinearLayout.LayoutParams(0, -2, 1))
return b
end
tombol(T("efekjam_kurangi", "Kurangi"), function() terapkan(st[d.k] - d.langkah[iLangkah]) end)
tombol(T("efekjam_tambah", "Tambah"), function() terapkan(st[d.k] + d.langkah[iLangkah]) end)
local btnL
btnL = tombol(T("efekjam_langkah", "Langkah") .. " " .. EfekJam.fmtAngka(d.langkah[1]), function()
iLangkah = iLangkah % #d.langkah + 1
btnL.setText(T("efekjam_langkah", "Langkah") .. " " .. EfekJam.fmtAngka(d.langkah[iLangkah]))
service.speak(T("efekjam_langkah_sekarang", "Langkah") .. " " .. EfekJam.fmtAngka(d.langkah[iLangkah]))
end)
lay.addView(baris)
return tampil
end

-- ===== Preset (Pilih, Simpan, Hapus) =====
EfekJam.muatPreset = function(kunci)
local ok, hasil = pcall(function() return cjson.decode(pref.getString(kunci, "[]")) end)
if ok and type(hasil) == "table" then return hasil end
return {}
end

EfekJam.simpanPreset = function(kunci, daftar)
pcall(function() pref.edit().putString(kunci, cjson.encode(daftar)).apply() end)
end

EfekJam.dialogDaftarPreset = function(judul, daftar, onPilih)
local nama = {}
for _, p in ipairs(daftar) do table.insert(nama, tostring(p.nama)) end
local d = UI_Dialog(judul)
d.setItems(nama)
d.setOnItemClickListener(function(al, av, ap, ai)
d.dismiss()
onPilih(ap + 1)
end)
d.setButton(T("batal", "Batal"), function() end)
d.show()
end

-- kunciPreset: nama pengaturan penyimpan daftar; daftarKunci: kunci nilai yang ikut disimpan; segarkan(): menyegarkan tampilan
EfekJam.barisPreset = function(lay, kunciPreset, daftarKunci, st, segarkan, onUbah)
local judul = TextView(service)
judul.setText(T("efekjam_preset", "Preset"))
judul.setTextSize(16)
judul.setPadding(0, 32, 0, 0)
lay.addView(judul)
local function tombol(teks, aksi)
local b = Button(service)
b.setText(teks)
b.onClick = function() aksi() end
lay.addView(b)
end
tombol(T("efekjam_pilih_preset", "Pilih Preset"), function()
local daftar = EfekJam.muatPreset(kunciPreset)
if #daftar == 0 then service.speak(T("efekjam_belum_ada_preset", "Belum ada preset. Atur dulu lalu simpan.")); return end
EfekJam.dialogDaftarPreset(T("efekjam_pilih_preset", "Pilih Preset"), daftar, function(i)
local p = daftar[i]
if p and type(p.nilai) == "table" then
for _, k in ipairs(daftarKunci) do
if p.nilai[k] ~= nil then st[k] = p.nilai[k] end
end
segarkan()
if onUbah then onUbah() end
service.speak(T("efekjam_preset_diterapkan", "Preset diterapkan."))
end
end)
end)
tombol(T("efekjam_simpan_preset", "Simpan Preset"), function()
showInputDialog(T("efekjam_nama_preset", "Nama preset"), "", "", function(nama)
local daftar = EfekJam.muatPreset(kunciPreset)
local nilai = {}
for _, k in ipairs(daftarKunci) do nilai[k] = st[k] end
table.insert(daftar, { nama = nama, nilai = nilai })
EfekJam.simpanPreset(kunciPreset, daftar)
service.speak(T("efekjam_preset_disimpan", "Preset disimpan."))
return true
end, nil, true)
end)
tombol(T("efekjam_hapus_preset", "Hapus Preset"), function()
local daftar = EfekJam.muatPreset(kunciPreset)
if #daftar == 0 then service.speak(T("efekjam_belum_ada_preset_hapus", "Belum ada preset.")); return end
EfekJam.dialogDaftarPreset(T("efekjam_hapus_preset", "Hapus Preset"), daftar, function(i)
showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("efekjam_hapus_preset_tanya", "Hapus preset ini?") .. " " .. tostring(daftar[i].nama), function()
table.remove(daftar, i)
EfekJam.simpanPreset(kunciPreset, daftar)
service.speak(T("efekjam_preset_dihapus", "Preset dihapus."))
end)
end)
end)
end

-- ===== Contoh suara dan pemanggil mesin pratinjau langsung =====
EfekJam.panggilLive = function(cmd, a, b, c, d)
local ok, pesan = EfekJam.muatMesin()
if not ok then return "GAGAL: " .. tostring(pesan) end
if not EfekJam._metodeLive then
return "GAGAL: " .. T("efekjam_live_tidak_ada", "Mesin pratinjau langsung tidak ada di FastMuxer.dex. Pakai FastMuxer versi terbaru.")
end
local hasil = "GAGAL: ?"
local okp, e = pcall(function()
local arg = luajava.newArray(luajava.bindClass("java.lang.Object"), 5)
arg[0] = cmd
arg[1] = a or ""
arg[2] = b or ""
arg[3] = c or ""
arg[4] = d or ""
hasil = tostring(EfekJam._metodeLive.invoke(nil, arg))
end)
if not okp then return "GAGAL: " .. tostring(e) end
return hasil
end

-- Membuat contoh suara dengan TTS (disimpan sementara). onSukses(pathWav) atau onGagal(pesan).
EfekJam.siapkanContoh = function(onSukses, onGagal)
local cache = service.getCacheDir().getAbsolutePath()
local wav = cache .. "/efek_contoh.wav"
local engine = pref.getString("tts_engine", "")
local voiceName = pref.getString("tts_voice", "")
local kunci = engine .. "|" .. voiceName .. "|" .. tostring(pref.getFloat("tts_pitch", 1.0)) .. "|" .. tostring(pref.getFloat("tts_rate", 1.0))
local f = File(wav)
if f.exists() and f.length() > 4000 and EfekJam._kunciContoh == kunci then
onSukses(wav)
return
end
f.delete()
local dL = UI_Dialog(T("mohon_tunggu", "Mohon Tunggu"))
dL.setMessage(T("efekjam_menyiapkan_contoh", "Menyiapkan contoh suara..."))
dL.setCancelable(false)
dL.show()
local selesai = false
local tts
local function akhir(ok, pesan)
if selesai then return end
selesai = true
uiHandler.post(Runnable({ run = function()
pcall(function() dL.dismiss() end)
pcall(function() tts.shutdown() end)
if ok then
EfekJam._kunciContoh = kunci
onSukses(wav)
else
onGagal(pesan)
end
end }))
end
tts = TextToSpeech(service, function(status)
if status == TextToSpeech.SUCCESS then
if engine ~= "" then pcall(function() tts.setEngineByPackageName(engine) end) end
if voiceName ~= "" then
pcall(function()
local voices = tts.getVoices()
if voices then
local iter = voices.iterator()
while iter.hasNext() do
local v = iter.next()
if v.getName() == voiceName then tts.setVoice(v); break end
end
end
end)
end
pcall(function() tts.setPitch(pref.getFloat("tts_pitch", 1.0)) end)
pcall(function() tts.setSpeechRate(pref.getFloat("tts_rate", 1.0)) end)
pcall(function()
tts.setOnUtteranceProgressListener(UtteranceProgressListener{
onStart = function(uId) end,
onDone = function(uId) akhir(true) end,
onError = function(uId) akhir(false, T("efekjam_gagal_contoh", "Gagal membuat contoh suara.")) end
})
end)
local paramMap = luajava.bindClass("java.util.HashMap")()
paramMap.put(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, "efek_contoh")
local r = tts.synthesizeToFile(T("efekjam_teks_contoh", "Waktu saat ini menunjukkan pukul sepuluh lewat lima menit"), paramMap, wav)
if r == TextToSpeech.ERROR then akhir(false, T("efekjam_gagal_contoh", "Gagal membuat contoh suara.")) end
else
akhir(false, T("gagal_mesin_tts", "Gagal memulai mesin TTS"))
end
end, engine == "" and nil or engine)
end

-- ===== Pratinjau Real Time di dalam dialog efek =====
-- mode: "nada", "reverb", atau "echo". kirim(ulang) mengembalikan perintah dan argumen pengaturan saat ini.
EfekJam.bangunLive = function(lay, mode, kirim)
local ctrl = { siap = false, memutar = false, tutup = false, menyiapkan = false }
local kerja = service.getCacheDir().getAbsolutePath() .. "/efek_live"
File(kerja).mkdirs()

local judul = TextView(service)
judul.setText(T("efekjam_pratinjau_rt", "Pratinjau Real Time"))
judul.setTextSize(16)
judul.setPadding(0, 32, 0, 0)
lay.addView(judul)
local tvInfo = TextView(service)
tvInfo.setText(T("efekjam_rt_info", "Putar contoh suara lalu ubah angkanya, efek langsung terdengar. Pratinjau tidak memakai jatah harian."))
tvInfo.setTextSize(13)
lay.addView(tvInfo)
local btnMain = Button(service)
btnMain.setText(T("efekjam_putar_langsung", "Putar Langsung"))
lay.addView(btnMain)
local tvStatus = TextView(service)
tvStatus.setText(T("efekjam_belum_diputar", "Belum diputar."))
tvStatus.setTextSize(14)
lay.addView(tvStatus)
local baris = LinearLayout(service)
baris.setOrientation(0)
local btnMundur = Button(service)
btnMundur.setText(T("efekjam_mundur_10", "Mundur 10 Detik"))
local btnMaju = Button(service)
btnMaju.setText(T("efekjam_maju_10", "Maju 10 Detik"))
baris.addView(btnMundur, LinearLayout.LayoutParams(0, -2, 1))
baris.addView(btnMaju, LinearLayout.LayoutParams(0, -2, 1))
lay.addView(baris)
local cbUlang = CheckBox(service)
cbUlang.setText(T("efekjam_ulangi", "Ulangi dari awal bila selesai"))
lay.addView(cbUlang)

local function pecah(s)
local f = {}
for x in (s .. "|"):gmatch("([^|]*)|") do table.insert(f, x) end
return f
end
local function mdtk(ms)
local d = math.floor((tonumber(ms) or 0) / 1000)
return string.format("%d:%02d", math.floor(d / 60), d % 60)
end
local function kirimCfg()
local cmd, arg = kirim(cbUlang.isChecked() and "1" or "0")
return EfekJam.panggilLive(cmd, arg)
end
local poll
poll = function()
if ctrl.tutup then return end
local f = pecah(EfekJam.panggilLive("pt_status"))
local lj = f[1] or "mati"
local aktif = (f[4] == "1")
if lj == "analisis" then
tvStatus.setText(T("efekjam_menganalisis", "Menganalisis nada: ") .. tostring(f[2]) .. "%")
elseif lj == "galat" then
tvStatus.setText(T("efekjam_mesin_lanjut_galat", "Mesin lanjutan belum bisa dipakai, memakai mesin biasa: ") .. tostring(f[8] or ""))
else
tvStatus.setText((aktif and T("efekjam_memutar", "Memutar ") or T("efekjam_berhenti", "Berhenti ")) .. mdtk(f[3]) .. " / " .. mdtk(f[5]) .. (f[6] == "1" and (" - " .. T("efekjam_mesin_lanjut_aktif", "mesin lanjutan")) or ""))
end
if f[7] == "1" and not aktif then
ctrl.memutar = false
btnMain.setText(T("efekjam_putar_langsung", "Putar Langsung"))
service.speak(T("efekjam_selesai", "Selesai."))
return
end
if not aktif and ctrl.memutar and lj ~= "analisis" then
ctrl.memutar = false
btnMain.setText(T("efekjam_putar_langsung", "Putar Langsung"))
return
end
uiHandler.postDelayed(Runnable({ run = function() poll() end }), 500)
end
local function mulaiMemutar()
local r = EfekJam.panggilLive("pt_main", "-1")
if string.sub(r, 1, 6) ~= "SUKSES" then
tvStatus.setText(r)
service.speak(r)
return
end
ctrl.memutar = true
btnMain.setText(T("efekjam_hentikan", "Hentikan"))
service.speak(T("efekjam_memutar_ucap", "Memutar"))
poll()
end
local function siapkanLalu()
ctrl.menyiapkan = true
btnMain.setText(T("efekjam_menyiapkan_tombol", "Menyiapkan..."))
tvStatus.setText(T("efekjam_menyiapkan_contoh", "Menyiapkan contoh suara..."))
EfekJam.siapkanContoh(function(wav)
Thread(Runnable({ run = function()
EfekJam.panggilLive("pt_lepas")
local r = EfekJam.panggilLive("pt_siapkan_berkas", wav, kerja)
if string.sub(r, 1, 6) == "SUKSES" then r = EfekJam.panggilLive("pt_buka", kerja, mode) end
uiHandler.post(Runnable({ run = function()
ctrl.menyiapkan = false
if ctrl.tutup then return end
if string.sub(r, 1, 6) ~= "SUKSES" then
btnMain.setText(T("efekjam_putar_langsung", "Putar Langsung"))
tvStatus.setText(r)
service.speak(r)
return
end
ctrl.siap = true
kirimCfg()
mulaiMemutar()
end }))
end })).start()
end, function(pesan)
ctrl.menyiapkan = false
btnMain.setText(T("efekjam_putar_langsung", "Putar Langsung"))
tvStatus.setText(tostring(pesan))
service.speak(tostring(pesan))
end)
end
btnMain.onClick = function()
if ctrl.menyiapkan then service.speak(T("efekjam_masih_menyiapkan", "Masih menyiapkan contoh suara.")); return end
if ctrl.memutar then
EfekJam.panggilLive("pt_henti")
ctrl.memutar = false
btnMain.setText(T("efekjam_putar_langsung", "Putar Langsung"))
service.speak(T("efekjam_dihentikan", "Dihentikan."))
return
end
if ctrl.siap then
kirimCfg()
mulaiMemutar()
else
siapkanLalu()
end
end
local function lompat(delta)
if not ctrl.siap then service.speak(T("efekjam_putar_dulu", "Putar contoh suaranya dulu.")); return end
local f = pecah(EfekJam.panggilLive("pt_status"))
local baru = (tonumber(f[3]) or 0) + delta
if baru < 0 then baru = 0 end
EfekJam.panggilLive("pt_cari", tostring(math.floor(baru)))
service.speak(T("efekjam_posisi", "Posisi") .. " " .. mdtk(baru))
end
btnMundur.onClick = function() lompat(-10000) end
btnMaju.onClick = function() lompat(10000) end

-- Dipanggil setiap kali angka berubah supaya efek langsung terdengar
ctrl.ubah = function()
if ctrl.siap and not ctrl.tutup then kirimCfg() end
end
ctrl.lepas = function()
ctrl.tutup = true
pcall(function() EfekJam.panggilLive("pt_henti") end)
pcall(function() EfekJam.panggilLive("pt_lepas") end)
end
return ctrl
end

-- ===== Kerangka dialog efek =====
EfekJam.kerangkaDialog = function(judul)
local d = UI_Dialog(judul)
local scroll = ScrollView(service)
local lay = LinearLayout(service)
lay.setOrientation(1)
lay.setPadding(32, 24, 32, 24)
scroll.addView(lay)
d.setView(scroll)
return d, lay
end

EfekJam.pasangLepas = function(d, ctrl)
d.setOnDismissListener(luajava.createProxy("android.content.DialogInterface$OnDismissListener", {
onDismiss = function(x) if ctrl then ctrl.lepas() end end
}))
end

-- Dialog Reverb dan Echo (parameter sama seperti di main_1.lua)
EfekJam.spec = function(jenis)
if jenis == "reverb" then
return {
judul = T("efekjam_reverb", "Efek Ruangan (Reverb)"), aktif = "efek_rv_on", labelAktif = T("efekjam_aktifkan_reverb", "Aktifkan reverb"),
preset = "efek_rv_presets", mode = "reverb",
param = {
{ k = "efek_rv_room", label = T("efekjam_p_ruangan", "Luas Ruangan"), min = 0, max = 100, langkah = { 1, 5, 10 }, satuan = "%", ucap = " persen", awal = 50 },
{ k = "efek_rv_damp", label = T("efekjam_p_peredam_gema", "Peredam Gema"), min = 0, max = 100, langkah = { 1, 5, 10 }, satuan = "%", ucap = " persen", awal = 50 },
{ k = "efek_rv_dry", label = T("efekjam_p_asli", "Volume Suara Asli"), min = 0, max = 100, langkah = { 1, 5, 10 }, satuan = "%", ucap = " persen", awal = 70 },
{ k = "efek_rv_wet", label = T("efekjam_p_gema", "Kekuatan Suara Efek Gema"), min = 0, max = 100, langkah = { 1, 5, 10 }, satuan = "%", ucap = " persen", awal = 30 },
{ k = "efek_rv_st", label = T("efekjam_p_stereo", "Tingkat Stereo Ruangan (berlaku bila hasil Stereo)"), min = 0, max = 100, langkah = { 1, 5, 10 }, satuan = "%", ucap = " persen", awal = 50 }
}
}
end
return {
judul = T("efekjam_echo", "Efek Pantulan (Echo)"), aktif = "efek_ec_on", labelAktif = T("efekjam_aktifkan_echo", "Aktifkan echo"),
preset = "efek_ec_presets", mode = "echo",
param = {
{ k = "efek_ec_dly", label = T("efekjam_p_jarak", "Jarak Waktu Pantulan"), min = 0, max = 1000, langkah = { 10, 50, 100 }, satuan = " ms", ucap = " milidetik", awal = 300 },
{ k = "efek_ec_fb", label = T("efekjam_p_ulang", "Banyaknya Ekor Pantulan"), min = 0, max = 100, langkah = { 1, 5, 10 }, satuan = "%", ucap = " persen", awal = 30 },
{ k = "efek_ec_damp", label = T("efekjam_p_peredam_pantulan", "Peredam Pantulan"), min = 0, max = 100, langkah = { 1, 5, 10 }, satuan = "%", ucap = " persen", awal = 50 },
{ k = "efek_ec_dry", label = T("efekjam_p_asli", "Volume Suara Asli"), min = 0, max = 100, langkah = { 1, 5, 10 }, satuan = "%", ucap = " persen", awal = 100 },
{ k = "efek_ec_wet", label = T("efekjam_p_pantulan", "Kekuatan Suara Efek Pantulan"), min = 0, max = 100, langkah = { 1, 5, 10 }, satuan = "%", ucap = " persen", awal = 30 },
{ k = "efek_ec_st", label = T("efekjam_p_stereo_echo", "Tingkat Stereo Pantulan (berlaku bila hasil Stereo)"), min = 0, max = 100, langkah = { 1, 5, 10 }, satuan = "%", ucap = " persen", awal = 50 }
}
}
end

EfekJam.dialogEfek = function(jenis)
local sp = EfekJam.spec(jenis)
local d, lay = EfekJam.kerangkaDialog(sp.judul)
local st = {}
local daftarKunci = {}
for _, p in ipairs(sp.param) do
st[p.k] = EfekJam.ambilAngka(p.k, p.awal)
table.insert(daftarKunci, p.k)
end
local cbAktif = CheckBox(service)
cbAktif.setText(sp.labelAktif)
cbAktif.setChecked(pref.getBoolean(sp.aktif, false))
lay.addView(cbAktif)
local ctrl
local function ubah() if ctrl then ctrl.ubah() end end
local segarkan = {}
for _, p in ipairs(sp.param) do
table.insert(segarkan, EfekJam.barisAngka(lay, st, p, ubah))
end
local function segarkanSemua() for _, f in ipairs(segarkan) do f() end end
EfekJam.barisPreset(lay, sp.preset, daftarKunci, st, segarkanSemua, ubah)
-- Argumen pratinjau langsung (pecahan 0..1, jarak echo dalam milidetik)
local function kirim(ulang)
if jenis == "reverb" then
return "pt_atur_fx", string.format("%s|%s|%s|%s|%s", ulang, EfekJam.fmtAngka(st.efek_rv_room / 100), EfekJam.fmtAngka(st.efek_rv_damp / 100), EfekJam.fmtAngka(st.efek_rv_dry / 100), EfekJam.fmtAngka(st.efek_rv_wet / 100))
end
return "pt_atur_fx", string.format("%s|%s|%s|%s|%s|%s", ulang, EfekJam.fmtAngka(st.efek_ec_dly), EfekJam.fmtAngka(st.efek_ec_fb / 100), EfekJam.fmtAngka(st.efek_ec_damp / 100), EfekJam.fmtAngka(st.efek_ec_dry / 100), EfekJam.fmtAngka(st.efek_ec_wet / 100))
end
ctrl = EfekJam.bangunLive(lay, sp.mode, kirim)
EfekJam.pasangLepas(d, ctrl)
d.setButton(T("simpan", "Simpan"), function()
EfekJam.simpanBool(sp.aktif, cbAktif.isChecked())
for _, p in ipairs(sp.param) do EfekJam.simpanAngka(p.k, st[p.k]) end
service.speak(T("efekjam_tersimpan", "Pengaturan efek tersimpan."))
end)
d.setButton2(T("batal", "Batal"), function() end)
d.show()
end

EfekJam.dialogReverb = function() EfekJam.dialogEfek("reverb") end
EfekJam.dialogEcho = function() EfekJam.dialogEfek("echo") end

-- Dialog Naik/Turunkan Nada: Model Biasa atau Lanjut, nada tetap dengan langkah, atau pergeseran bertahap
EfekJam.dialogNada = function()
local d, lay = EfekJam.kerangkaDialog(T("efekjam_nada", "Naik/Turunkan Nada Suara (Pitch)"))
local st = {
efek_nada_semi = EfekJam.ambilAngka("efek_nada_semi", 0),
efek_nada_g0 = EfekJam.ambilAngka("efek_nada_g0", 0),
efek_nada_g1 = EfekJam.ambilAngka("efek_nada_g1", 4),
efek_nada_gd = EfekJam.ambilAngka("efek_nada_gd", 0),
efek_nada_lanjut = pref.getBoolean("efek_nada_lanjut", false),
efek_nada_gl = pref.getBoolean("efek_nada_gl", false)
}
local ctrl
local function ubah() if ctrl then ctrl.ubah() end end

local cbAktif = CheckBox(service)
cbAktif.setText(T("efekjam_aktifkan_nada", "Aktifkan perubahan nada"))
cbAktif.setChecked(pref.getBoolean("efek_nada_on", false))
lay.addView(cbAktif)

local cbLanjut = CheckBox(service)
cbLanjut.setText(T("efekjam_nada_lanjut", "Mode Nada Tingkat Lanjut (warna suara lebih terjaga)"))
cbLanjut.setChecked(st.efek_nada_lanjut)
cbLanjut.onClick = function()
st.efek_nada_lanjut = cbLanjut.isChecked()
service.speak(st.efek_nada_lanjut and T("efekjam_nada_lanjut_aktif", "Mode nada tingkat lanjut aktif") or T("efekjam_nada_lanjut_mati", "Mode nada biasa"))
ubah()
end
lay.addView(cbLanjut)

-- Nada tetap
local wadahTetap = LinearLayout(service)
wadahTetap.setOrientation(1)
lay.addView(wadahTetap)
local tvSemi = TextView(service)
tvSemi.setTextSize(16)
tvSemi.setPadding(0, 24, 0, 0)
wadahTetap.addView(tvSemi)
local langkahPilihan = { 0.5, 1, 2, 12 }
local namaLangkah = {
T("efekjam_langkah_setengah", "Setengah nada"), T("efekjam_langkah_satu", "Satu nada"),
T("efekjam_langkah_dua", "Dua nada"), T("efekjam_langkah_oktaf", "Satu oktaf") }
local iL = 2
local function tampilSemi()
local v = st.efek_nada_semi
tvSemi.setText(T("efekjam_nada_sekarang", "Nada: ") .. (v > 0 and "+" or "") .. EfekJam.fmtAngka(v) .. " " .. T("efekjam_satuan_nada", "nada"))
end
local function setSemi(v)
local batas = nil
if v < -12 then v = -12; batas = T("efekjam_batas_bawah", "Batas bawah tercapai.") end
if v > 12 then v = 12; batas = T("efekjam_batas_atas", "Batas atas tercapai.") end
st.efek_nada_semi = v
tampilSemi()
local ucap = (v > 0 and "plus " or (v < 0 and "minus " or "")) .. EfekJam.fmtAngka(math.abs(v)) .. " " .. T("efekjam_satuan_nada", "nada")
if batas then ucap = batas .. " " .. ucap end
service.speak(ucap)
ubah()
end
local function tombolDi(induk, teks, aksi)
local b = Button(service)
b.setText(teks)
b.onClick = function() aksi() end
induk.addView(b)
return b
end
EfekJam.pasangKlik(tvSemi, function()
showInputDialog(T("efekjam_nada", "Naik/Turunkan Nada Suara (Pitch)") .. " (-12 - 12)", "", EfekJam.fmtAngka(st.efek_nada_semi), function(txt)
local v = tonumber((string.gsub(txt, ",", ".")))
if not v then service.speak(T("efekjam_bukan_angka", "Isi dengan angka.")); return false end
setSemi(v)
return true
end, nil, true)
end)
local barisSemi = LinearLayout(service)
barisSemi.setOrientation(0)
local function tombolBaris(teks, aksi)
local b = Button(service)
b.setText(teks)
b.onClick = function() aksi() end
barisSemi.addView(b, LinearLayout.LayoutParams(0, -2, 1))
return b
end
tombolBaris(T("efekjam_turunkan", "Turunkan"), function() setSemi(st.efek_nada_semi - langkahPilihan[iL]) end)
tombolBaris(T("efekjam_naikkan", "Naikkan"), function() setSemi(st.efek_nada_semi + langkahPilihan[iL]) end)
wadahTetap.addView(barisSemi)
local btnLangkah
btnLangkah = Button(service)
btnLangkah.setText(T("efekjam_langkah_tombol", "Langkah Tombol: ") .. namaLangkah[iL])
btnLangkah.onClick = function()
iL = iL % #langkahPilihan + 1
btnLangkah.setText(T("efekjam_langkah_tombol", "Langkah Tombol: ") .. namaLangkah[iL])
service.speak(namaLangkah[iL])
end
wadahTetap.addView(btnLangkah)
tombolDi(wadahTetap, T("efekjam_kembali_nol", "Kembalikan ke 0"), function() setSemi(0) end)

-- Pergeseran bertahap
local cbGl = CheckBox(service)
cbGl.setText(T("efekjam_bertahap", "Pergeseran Bertahap (naik atau turun pelan-pelan)"))
cbGl.setChecked(st.efek_nada_gl)
lay.addView(cbGl)
local wadahGl = LinearLayout(service)
wadahGl.setOrientation(1)
lay.addView(wadahGl)
local segarGl = {}
table.insert(segarGl, EfekJam.barisAngka(wadahGl, st, { k = "efek_nada_g0", label = T("efekjam_nada_awal", "Nada Awal"), min = -12, max = 12, langkah = { 0.5, 1, 2 }, satuan = "", ucap = " nada", awal = 0 }, ubah))
table.insert(segarGl, EfekJam.barisAngka(wadahGl, st, { k = "efek_nada_g1", label = T("efekjam_nada_akhir", "Nada Akhir"), min = -12, max = 12, langkah = { 0.5, 1, 2 }, satuan = "", ucap = " nada", awal = 4 }, ubah))
table.insert(segarGl, EfekJam.barisAngka(wadahGl, st, { k = "efek_nada_gd", label = T("efekjam_lama_peralihan", "Lama Peralihan (0 = sepanjang suara)"), min = 0, max = 120, langkah = { 1, 5, 10 }, satuan = " detik", ucap = " detik", awal = 0 }, ubah))
local function segarkanGl() for _, f in ipairs(segarGl) do f() end end
tombolDi(wadahGl, T("efekjam_naik_pelan", "Naik Pelan-Pelan"), function()
st.efek_nada_g0 = 0; st.efek_nada_g1 = 4; segarkanGl(); service.speak(T("efekjam_naik_pelan_ucap", "Dari 0 naik ke plus 4 nada")); ubah()
end)
tombolDi(wadahGl, T("efekjam_turun_pelan", "Turun Pelan-Pelan"), function()
st.efek_nada_g0 = 0; st.efek_nada_g1 = -4; segarkanGl(); service.speak(T("efekjam_turun_pelan_ucap", "Dari 0 turun ke minus 4 nada")); ubah()
end)
local function atur()
wadahTetap.setVisibility(cbGl.isChecked() and 8 or 0)
wadahGl.setVisibility(cbGl.isChecked() and 0 or 8)
end
cbGl.onClick = function()
st.efek_nada_gl = cbGl.isChecked()
atur()
service.speak(st.efek_nada_gl and T("efekjam_bertahap_aktif", "Pergeseran bertahap aktif") or T("efekjam_bertahap_mati", "Pergeseran bertahap mati, nada tetap"))
ubah()
end
tampilSemi()
atur()

-- Preset menyimpan model, nada tetap, dan pergeseran bertahap
local kunciPreset = { "efek_nada_semi", "efek_nada_g0", "efek_nada_g1", "efek_nada_gd", "efek_nada_lanjut", "efek_nada_gl" }
EfekJam.barisPreset(lay, "efek_nada_presets", kunciPreset, st, function()
cbLanjut.setChecked(st.efek_nada_lanjut and true or false)
cbGl.setChecked(st.efek_nada_gl and true or false)
tampilSemi()
segarkanGl()
atur()
end, ubah)

local function kirim(ulang)
local val = st.efek_nada_semi
return "pt_atur", string.format("%d|%s|%d|%s|%s|%s|%s", st.efek_nada_lanjut and 1 or 0, ulang, st.efek_nada_gl and 1 or 0,
EfekJam.fmtAngka(val), EfekJam.fmtAngka(st.efek_nada_g0), EfekJam.fmtAngka(st.efek_nada_g1), EfekJam.fmtAngka(st.efek_nada_gd))
end
ctrl = EfekJam.bangunLive(lay, "nada", kirim)
EfekJam.pasangLepas(d, ctrl)
d.setButton(T("simpan", "Simpan"), function()
EfekJam.simpanBool("efek_nada_on", cbAktif.isChecked())
EfekJam.simpanBool("efek_nada_lanjut", st.efek_nada_lanjut and true or false)
EfekJam.simpanBool("efek_nada_gl", st.efek_nada_gl and true or false)
EfekJam.simpanAngka("efek_nada_semi", st.efek_nada_semi)
EfekJam.simpanAngka("efek_nada_g0", st.efek_nada_g0)
EfekJam.simpanAngka("efek_nada_g1", st.efek_nada_g1)
EfekJam.simpanAngka("efek_nada_gd", st.efek_nada_gd)
service.speak(T("efekjam_tersimpan", "Pengaturan efek tersimpan."))
end)
d.setButton2(T("batal", "Batal"), function() end)
d.show()
end

EfekJam.dialogEkor = function()
local d, lay = EfekJam.kerangkaDialog(T("efekjam_ekor", "Ekor Gema"))
local info = TextView(service)
info.setText(T("efekjam_ekor_info", "Tambahan hening di akhir tiap suara supaya gema tidak terpotong"))
info.setTextSize(14)
lay.addView(info)
local st = { efek_ekor_ms = EfekJam.ambilAngka("efek_ekor_ms", 500) }
EfekJam.barisAngka(lay, st, { k = "efek_ekor_ms", label = T("efekjam_p_ekor", "Panjang ekor"), min = 0, max = 2000, langkah = { 50, 100, 500 }, satuan = " ms", ucap = " milidetik", awal = 500 }, nil)
d.setButton(T("simpan", "Simpan"), function()
EfekJam.simpanAngka("efek_ekor_ms", st.efek_ekor_ms)
service.speak(T("efekjam_tersimpan", "Pengaturan efek tersimpan."))
end)
d.setButton2(T("batal", "Batal"), function() end)
d.show()
end


-- Pratinjau: memberi contoh suara (TTS) semua efek yang aktif lalu memutarnya. Tidak memakai jatah.
EfekJam.pratinjau = function()
local cfg = EfekJam.ambilCfg(true)
if not cfg then
service.speak(T("efekjam_pratinjau_kosong", "Aktifkan minimal satu efek terlebih dahulu."))
return
end
local okMesin, pesanMesin = EfekJam.muatMesin()
if not okMesin then service.speak(tostring(pesanMesin)); return end
EfekJam.siapkanContoh(function(wav)
local keluar = EfekJam.namaKeluaran(wav)
File(keluar).delete()
jalankanDenganLoading(T("efekjam_menerapkan", "Menerapkan efek suara, mohon tunggu..."), function()
local ok, pesan = EfekJam.terapkan(wav, keluar, cfg)
return { ok = ok, pesan = pesan }
end, function(res)
if not (type(res) == "table" and res.ok) then
service.speak(T("efekjam_gagal_diterapkan", "Efek gagal diterapkan: ") .. tostring(type(res) == "table" and res.pesan or res))
return
end
pcall(function() hentikanAudioGlobal() end)
pcall(function()
local mp = luajava.bindClass("android.media.MediaPlayer")()
mp.setDataSource(keluar)
mp.prepare()
mp.setOnCompletionListener(function(m) pcall(function() m.release() end) end)
mp.start()
end)
end)
end, function(pesan)
service.speak(tostring(pesan))
end)
end

-- Layar utama Pengaturan Efek Suara
EfekJam.tampilkanPengaturan = function()
local d = UI_Dialog(T("efekjam_judul", "Pengaturan Efek Suara"))
local scroll = ScrollView(service)
local lay = LinearLayout(service)
lay.setOrientation(1)
lay.setPadding(32, 24, 32, 24)
scroll.addView(lay)

local cbUtama = CheckBox(service)
cbUtama.setText(T("efekjam_aktifkan", "Aktifkan efek suara"))
cbUtama.setChecked(pref.getBoolean("efek_aktif", false))
lay.addView(cbUtama)

local info = TextView(service)
info.setText(T("efekjam_info_limit", "Efek dipasang saat membuat jam bicara (TTS atau suara sendiri). Pengguna gratis dibatasi 3 kali per 24 jam sejak pemakaian pertama. Pratinjau tidak memakai jatah."))
info.setTextSize(14)
info.setPadding(0, 16, 0, 16)
lay.addView(info)

local isi = LinearLayout(service)
isi.setOrientation(1)
lay.addView(isi)

local function tombol(teks, aksi)
local b = Button(service)
b.setText(teks)
b.onClick = function() aksi() end
isi.addView(b)
return b
end

tombol(T("efekjam_reverb", "Reverb (Gema Ruangan)"), EfekJam.dialogReverb)
tombol(T("efekjam_echo", "Echo (Pantulan)"), EfekJam.dialogEcho)
tombol(T("efekjam_nada", "Naik Turun Nada"), EfekJam.dialogNada)
tombol(T("efekjam_ekor", "Ekor Gema"), EfekJam.dialogEkor)
tombol(T("efekjam_pratinjau", "Pratinjau Efek"), EfekJam.pratinjau)

local function atur()
isi.setVisibility(cbUtama.isChecked() and 0 or 8)
end
atur()
cbUtama.onClick = function()
EfekJam.simpanBool("efek_aktif", cbUtama.isChecked())
atur()
end

d.setView(scroll)
d.setButton(T("tutup", "Tutup"), function() d.dismiss() end)
d.show()
end
-- ==========================================================================

-- ==========================================================================
-- AUDIO SISIPAN JAM (awalan, tengah, akhiran) untuk Pembuat Jam Bicara
-- Mesin: SisipanJam.dex (kelas SisipanJam) di folder skrip ini.
-- Tabel global agar tidak menambah jumlah variabel lokal pada skrip utama.
-- ==========================================================================
SisipanJam = {}
SisipanJam.SLOT = { "awal", "tengah", "akhir" }
SisipanJam.EKSTENSI = { mp3 = true, wav = true, m4a = true, ogg = true, aac = true, flac = true, opus = true, amr = true, mp4 = true }
SisipanJam.KUNCI_SUB = { hour = "sisip_jam", minute = "sisip_menit", hourly = "sisip_hourly" }

SisipanJam.simpanBool = function(kunci, nilai)
pcall(function() pref.edit().putBoolean(kunci, nilai).apply() end)
end

SisipanJam.simpanTeks = function(kunci, nilai)
pcall(function() pref.edit().putString(kunci, nilai).apply() end)
end

-- Menyusun konfigurasi untuk satu berkas jam. Folder induknya (hour, minute, hourly) menentukan
-- apakah sisipan berlaku dan audio mana yang dipakai untuk tempat itu.
-- Mengembalikan nil bila tidak ada yang perlu disisipkan.
SisipanJam.ambilCfg = function(path)
if not pref.getBoolean("sisip_aktif", false) then return nil end
local sub = string.match(path, "/([^/]+)/[^/]+$")
local kunciSub = SisipanJam.KUNCI_SUB[sub or ""]
if not kunciSub or not pref.getBoolean(kunciSub, true) then return nil end
local baris = {}
for _, s in ipairs(SisipanJam.SLOT) do
local p = pref.getString("sisip_" .. s .. "_" .. sub .. "_path", "")
if pref.getBoolean("sisip_" .. s .. "_on", false) and p ~= "" and File(p).exists() then
table.insert(baris, s .. "=" .. p)
table.insert(baris, s .. "_vol=" .. EfekJam.fmtAngka(EfekJam.ambilAngka("sisip_" .. s .. "_vol", 100)))
end
end
if #baris == 0 then return nil end
if pref.getBoolean("sisip_tengah_potong", false) then table.insert(baris, "tengah_potong=1") end
return table.concat(baris, "\n")
end

SisipanJam.muatMesin = function()
if SisipanJam._metode then return true end
local dexAsli = BASE .. "SisipanJam.dex"
if not File(dexAsli).exists() then
return false, T("sisip_mesin_tidak_ada", "File mesin sisipan (SisipanJam.dex) tidak ditemukan di folder skrip.")
end
local okMuat, galat = pcall(function()
local dirDex = File(service.getCacheDir(), "sisip_dex")
dirDex.mkdirs()
local salinan = File(dirDex, "SisipanJam.dex")
if salinan.exists() then salinan.setWritable(true); salinan.delete() end
SalinFile(dexAsli, salinan.getAbsolutePath())
salinan.setReadOnly()
local dirOpt = File(service.getCacheDir(), "sisip_odex")
dirOpt.mkdirs()
local cL = luajava.bindClass("dalvik.system.DexClassLoader")(salinan.getAbsolutePath(), dirOpt.getAbsolutePath(), nil, service.getClassLoader())
local kls = cL.loadClass("SisipanJam")
local tipeString = luajava.bindClass("java.lang.String")
local tipe = luajava.newArray(luajava.bindClass("java.lang.Class"), 3)
tipe[0] = tipeString
tipe[1] = tipeString
tipe[2] = tipeString
SisipanJam._metode = kls.getMethod("terapkan", tipe)
end)
if not okMuat then
SisipanJam._metode = nil
return false, T("sisip_mesin_gagal", "Mesin sisipan gagal dimuat: ") .. tostring(galat)
end
return true
end

SisipanJam.terapkan = function(inPath, outPath, cfg)
local ok, pesan = SisipanJam.muatMesin()
if not ok then return false, pesan end
local hasil = ""
local okPanggil, galat = pcall(function()
local arg = luajava.newArray(luajava.bindClass("java.lang.Object"), 3)
arg[0] = inPath
arg[1] = outPath
arg[2] = cfg
hasil = tostring(SisipanJam._metode.invoke(nil, arg))
end)
if not okPanggil then return false, tostring(galat) end
if hasil ~= "SUKSES" then return false, hasil end
return true
end

-- Apakah ada berkas dalam daftar yang akan mendapat sisipan (tanpa memeriksa isi berkasnya).
SisipanJam.adaSisipan = function(daftar)
for _, p in ipairs(daftar) do
if SisipanJam.ambilCfg(p) then return true end
end
return false
end

-- Fungsi kerja untuk task (Lua state terpisah, tidak boleh menyentuh variabel atau UI di luar).
-- Semua data lewat argumen JSON. Memuat SisipanJam.dex sendiri, lalu memproses berkas satu per satu.
-- a.mode = "sisip" (menyisipkan audio) atau "konversi" (WAV ke M4A atau OGG).
-- Kemajuan dilaporkan lewat System property "nadi_prog_sisip" berformat "<selesai>\t<path>".
-- Pembatalan: System property "nadi_batal" = "1" menghentikan proses di antara dua berkas.
SisipanJam.kerja = function(jsonArgs)
require "import"
local luajava = require("luajava")
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"
local cjson = require "cjson"
local System = luajava.bindClass("java.lang.System")
local a = cjson.decode(jsonArgs)
local konversi = (a.mode == "konversi")
local function dibatalkan() return tostring(System.getProperty("nadi_batal")) == "1" end

local okMuat, metode = pcall(function()
local dirDex = File(a.cacheDir, "sisip_dex_task")
dirDex.mkdirs()
local salinan = File(dirDex, "SisipanJam.dex")
if salinan.exists() then salinan.setWritable(true); salinan.delete() end
local fis = FileInputStream(a.dex)
local fos = FileOutputStream(salinan)
local buffer = byte[8192]
local n = fis.read(buffer)
while n > 0 do
fos.write(buffer, 0, n)
n = fis.read(buffer)
end
fis.close()
fos.close()
salinan.setReadOnly()
local dirOpt = File(a.cacheDir, "sisip_odex_task")
dirOpt.mkdirs()
local DCL = luajava.bindClass("dalvik.system.DexClassLoader")
local CL = luajava.bindClass("java.lang.ClassLoader")
local cL = DCL(salinan.getAbsolutePath(), dirOpt.getAbsolutePath(), nil, CL.getSystemClassLoader())
local kls = cL.loadClass("SisipanJam")
local tipeString = luajava.bindClass("java.lang.String")
local tipe = luajava.newArray(luajava.bindClass("java.lang.Class"), 3)
tipe[0] = tipeString
tipe[1] = tipeString
tipe[2] = tipeString
return kls.getMethod(konversi and "konversi" or "terapkan", tipe)
end)
if not okMuat then
return cjson.encode({ ok = false, pesan = "Mesin sisipan gagal dimuat: " .. tostring(metode) })
end

if konversi then
local sr = 0
local isErr = false
local batal = false
for i, t in ipairs(a.tugas) do
if dibatalkan() then batal = true; break end
System.setProperty("nadi_prog_sisip", tostring(i - 1) .. "\t" .. tostring(t.path))
local hasil = ""
local okP = pcall(function()
local arg = luajava.newArray(luajava.bindClass("java.lang.Object"), 3)
arg[0] = t.path
arg[1] = a.format
arg[2] = tostring(a.br)
hasil = tostring(metode.invoke(nil, arg))
end)
if okP and string.sub(hasil, 1, 7) == "SUKSES:" then
if sr == 0 then sr = tonumber(string.sub(hasil, 8)) or 0 end
elseif a.format == "OGG" then
isErr = true
break
end
end
System.setProperty("nadi_prog_sisip", "")
return cjson.encode({ ok = (not isErr) and (not batal), isErr = isErr, sr = sr, batal = batal })
end

local keluaran = {}
local galat = nil
local batal = false
for i, t in ipairs(a.tugas) do
if dibatalkan() then batal = true; break end
System.setProperty("nadi_prog_sisip", tostring(i - 1) .. "\t" .. tostring(t.path))
local out = (string.gsub(t.path, "(%.%w+)$", ".sp%1"))
File(out).delete()
local hasil = ""
local okP, g = pcall(function()
local arg = luajava.newArray(luajava.bindClass("java.lang.Object"), 3)
arg[0] = t.path
arg[1] = out
arg[2] = t.cfg
hasil = tostring(metode.invoke(nil, arg))
end)
if not okP then galat = tostring(g); break end
if hasil ~= "SUKSES" or not File(out).exists() then galat = hasil; break end
table.insert(keluaran, out)
end
if galat or batal then
for _, o in ipairs(keluaran) do File(o).delete() end
return cjson.encode({ ok = false, batal = batal, pesan = galat or "__batal__" })
end
for i, t in ipairs(a.tugas) do
local src = File(t.path)
src.delete()
File(keluaran[i]).renameTo(src)
end
System.setProperty("nadi_prog_sisip", "")
return cjson.encode({ ok = true })
end

-- Apakah ada berkas dalam daftar yang akan mendapat sisipan (tanpa memeriksa isi berkasnya).
SisipanJam.adaSisipan = function(daftar)
for _, p in ipairs(daftar) do
if SisipanJam.ambilCfg(p) then return true end
end
return false
end

-- Memasang sisipan pada banyak berkas (semua berhasil atau tidak ada yang diubah).
-- Pekerjaan berat berjalan di task, jadi layar tidak tertahan. onSelesai() dipanggil di thread utama.
-- Bila gagal, jam tetap dibuat tanpa sisipan. Layar progres jam dipakai; bila belum aktif, dibuat sendiri.
SisipanJam.terapkanSesi = function(daftar, onSelesai, bitrate)
local tugas = {}
for _, p in ipairs(daftar) do
local f = File(p)
if f.exists() and f.length() > 44 then
local cfg = SisipanJam.ambilCfg(p)
if cfg then table.insert(tugas, { path = p, cfg = cfg .. "\nbitrate=" .. tostring(bitrate or 128000) }) end
end
end
if #tugas == 0 then onSelesai(); return end

local dexAsli = BASE .. "SisipanJam.dex"
if not File(dexAsli).exists() then
service.speak(T("sisip_mesin_tidak_ada", "File mesin sisipan (SisipanJam.dex) tidak ditemukan di folder skrip."))
onSelesai()
return
end

local total = #tugas
local milik = not ProgresJam.aktif
if milik then ProgresJam.mulai({ { k = "sisip", b = 1 } }, T("prog_sisip_tahap", "Menyisipkan audio...")) end
ProgresJam.tahap("sisip", T("prog_sisip_tahap", "Menyisipkan audio..."))
local berhenti = ProgresJam.pantau("nadi_prog_sisip", function(teks)
local selesai, path = string.match(teks, "^(%d+)\t(.*)$")
if not selesai then return end
ProgresJam.maju(tonumber(selesai) / total, T("prog_sisip", "Menyisipkan audio: ") .. ProgresJam.labelBerkas(path), false)
end)
local argumen = cjson.encode({
mode = "sisip",
dex = dexAsli,
cacheDir = tostring(service.getCacheDir().getAbsolutePath()),
tugas = tugas
})
-- Task dimulai sesudah layar progres sempat tergambar.
uiHandler.postDelayed(Runnable({
run = function()
task(SisipanJam.kerja, argumen, function(json)
berhenti()
local r = {}
local okD = pcall(function() r = cjson.decode(tostring(json)) end)
if milik then ProgresJam.selesai() end
if okD and type(r) == "table" and r.ok then
if milik then service.speak(T("sisip_berhasil", "Audio sisipan berhasil dipasang.")) end
elseif ProgresJam.dibatalkan or (okD and type(r) == "table" and r.batal) then
-- dibatalkan: pemanggil yang menangani
else
local alasan = (okD and type(r) == "table" and r.pesan) or tostring(json)
service.speak(T("sisip_gagal", "Audio sisipan gagal dipasang: ") .. tostring(alasan))
end
onSelesai()
end)
end
}), 80)
end

-- Mengonversi daftar WAV menjadi M4A atau OGG lewat mesin Java di task.
-- onSelesai({ isErr, sr, batal, tanpaMesin }) dipanggil di thread utama.
SisipanJam.konversiSesi = function(daftar, fSel, brTarget, onSelesai)
local dexAsli = BASE .. "SisipanJam.dex"
if not File(dexAsli).exists() then
service.speak(T("sisip_mesin_tidak_ada", "File mesin sisipan (SisipanJam.dex) tidak ditemukan di folder skrip."))
onSelesai({ isErr = true, sr = 0, tanpaMesin = true })
return
end
local tugas = {}
for _, p in ipairs(daftar) do table.insert(tugas, { path = p }) end
local total = #tugas
local pesanTahap = T("mengonversi_ke", "Mengonversi ke ") .. fSel .. "..."
local berhenti = ProgresJam.pantau("nadi_prog_sisip", function(teks)
local selesai, path = string.match(teks, "^(%d+)\t(.*)$")
if not selesai then return end
ProgresJam.maju(tonumber(selesai) / total, T("prog_konversi", "Mengonversi ke ") .. fSel .. ": " .. ProgresJam.labelBerkas(path), false)
end)
local argumen = cjson.encode({
mode = "konversi",
dex = dexAsli,
cacheDir = tostring(service.getCacheDir().getAbsolutePath()),
format = fSel,
br = brTarget,
tugas = tugas
})
uiHandler.postDelayed(Runnable({
run = function()
task(SisipanJam.kerja, argumen, function(json)
berhenti()
local r = {}
local okD = pcall(function() r = cjson.decode(tostring(json)) end)
if not okD or type(r) ~= "table" then r = { isErr = true, sr = 0, pesan = tostring(json) } end
onSelesai(r)
end)
end
}), 80)
end

-- (Pemilih audio dan layar pengaturan SisipanJam dipasang setelah BukaPickerKustom, lihat di bawah.)
-- ==========================================================================

local function putarDenganDebounce(path)
if debounceRunnable then debounceHandler.removeCallbacks(debounceRunnable) end
debounceRunnable = Runnable({
run = function()
pcall(function()
local f = File(path)
if f.exists() and f.isFile() then
if not globalMediaPlayer then
globalMediaPlayer = MediaPlayer()
globalMediaPlayer.setOnErrorListener(function(mp, what, extra)
pcall(function() mp.release() end)
if globalMediaPlayer == mp then globalMediaPlayer = nil end
return true
end)
else
pcall(function()
if globalMediaPlayer.isPlaying() then globalMediaPlayer.stop() end
globalMediaPlayer.reset()
end)
end
globalMediaPlayer.setDataSource(path)
globalMediaPlayer.prepare()
globalMediaPlayer.start()
end
end)
end
})
debounceHandler.postDelayed(debounceRunnable, 15)
end

local function dapatkanTeksDariNode(node)
if not node then return "" end
local text = ""
if node.getText() then text = text .. tostring(node.getText()) .. " " end
if node.getContentDescription() then text = text .. tostring(node.getContentDescription()) .. " " end
for i = 0, node.getChildCount() - 1 do
local child = node.getChild(i)
if child then text = text .. dapatkanTeksDariNode(child) end
end
return text
end

local function deleteRecursive(fileOrDir)
if fileOrDir.isDirectory() then
local children = fileOrDir.listFiles()
if children then
for i = 0, #children - 1 do deleteRecursive(children[i]) end
end
end
fileOrDir.delete()
end

local function cleanSpkTrash()
task(kerjaHapusSpk, jieshuoPath, function() end)
end

local function isAudioFile(fileObj)
if not fileObj.isFile() or string.lower(fileObj.getName()) == "config" then return false end

local name = string.lower(fileObj.getName())

local ext = string.match(name, "%.([^%.]+)$")
local audioExts = {
mp3=true, ogg=true, wav=true, m4a=true, flac=true, amr=true,
mid=true, midi=true, aac=true, wma=true, opus=true, aiff=true,
mka=true, m4r=true, au=true, awb=true, snd=true, mp2=true,
ra=true, rm=true, dts=true, ac3=true
}
if ext and audioExts[ext] then return true end

local ok, res = pcall(function()
local fis = FileInputStream(fileObj)
local b = byte[8]
local count = fis.read(b)
fis.close()
if count < 4 then return false end

local function unsign(v) if v < 0 then return v + 256 else return v end end
local b0, b1, b2, b3 = unsign(b[0]), unsign(b[1]), unsign(b[2]), unsign(b[3])

if b0 == 0x4F and b1 == 0x67 and b2 == 0x67 and b3 == 0x53 then return true end
if b0 == 0x52 and b1 == 0x49 and b2 == 0x46 and b3 == 0x46 then return true end
if b0 == 0x49 and b1 == 0x44 and b2 == 0x33 then return true end
if b0 == 0xFF and (b1 >= 0xE0) then return true end
if b0 == 0x66 and b1 == 0x4C and b2 == 0x61 and b3 == 0x43 then return true end
if b0 == 0x23 and b1 == 0x21 and b2 == 0x41 and b3 == 0x4D then return true end
if b0 == 0x4D and b1 == 0x54 and b2 == 0x68 and b3 == 0x64 then return true end
if b0 == 0x30 and b1 == 0x26 and b2 == 0xB2 and b3 == 0x75 then return true end
if b0 == 0x2E and b1 == 0x73 and b2 == 0x6E and b3 == 0x64 then return true end

if count >= 8 then
local b4, b5, b6, b7 = unsign(b[4]), unsign(b[5]), unsign(b[6]), unsign(b[7])
if b4 == 0x66 and b5 == 0x74 and b6 == 0x79 and b7 == 0x70 then return true end
end
return false
end)
return ok and res
end

local function mulaiRadarFokus()
if isRadarRunning then return end
isRadarRunning, lastFocusedText, lastFocusedBounds = true, "", nil
local tabelPencarian = {}
for namaUi, pathLengkap in pairs(PetaAudioAktif) do table.insert(tabelPencarian, {nama = namaUi, path = pathLengkap}) end

radarRunnable = Runnable({
run = function()
if isRadarRunning then
pcall(function()
local rootNode = service.getRootInActiveWindow()
if rootNode then
local focusNode = rootNode.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)
if focusNode then
local teksFokusAsli = dapatkanTeksDariNode(focusNode)
local barisPertama = teksFokusAsli:match("^(.-)\n") or teksFokusAsli
local teksPencarian = (barisPertama:match("^%s*(.-)%s*$") or barisPertama):lower()

local currentBounds = Rect()
focusNode.getBoundsInScreen(currentBounds)
local boundsChanged = not (lastFocusedBounds and currentBounds.equals(lastFocusedBounds))

if teksPencarian ~= "" and (teksPencarian ~= lastFocusedText or boundsChanged) then
lastFocusedText, lastFocusedBounds = teksPencarian, Rect(currentBounds)
local foundPath = nil
for i = 1, #tabelPencarian do
if teksPencarian == tabelPencarian[i].nama:lower() then
foundPath = tabelPencarian[i].path
break
end
end
if foundPath then putarDenganDebounce(foundPath) else hentikanAudioGlobal() end
end
end
end
end)
radarHandler.postDelayed(radarRunnable, 300)
end
end
})
radarHandler.post(radarRunnable)
end

local function hentikanRadarFokus()
isRadarRunning, PetaAudioAktif, lastFocusedText, lastFocusedBounds = false, {}, "", nil
if radarRunnable then radarHandler.removeCallbacks(radarRunnable) end
end

local function BukaPickerKustom(opsi)
local currentPath = opsi.pathAwal or "/storage/emulated/0"
local selectedFiles = {}

local savedPetaAudioAktif = {}
for k,v in pairs(PetaAudioAktif) do savedPetaAudioAktif[k] = v end
local function restoreRadar()
hentikanRadarFokus()
if opsi.hentikanAudioGlobal then hentikanAudioGlobal() end
PetaAudioAktif = savedPetaAudioAktif
mulaiRadarFokus()
end

local pickerDialog = UI_Dialog(opsi.judul)

local elemenTombolBawah = {LinearLayout, orientation="horizontal", layout_width="fill", layout_marginBottom="8dp"}
if opsi.modeMulti then
if opsi.teksTombol1 then table.insert(elemenTombolBawah, UI_Tombol_H("btnAksi1", opsi.teksTombol1 .. " (0)")) end
if opsi.teksTombol2 then table.insert(elemenTombolBawah, UI_Tombol_H("btnAksi2", opsi.teksTombol2 .. " (0)")) end
else
elemenTombolBawah = {LinearLayout, visibility=8}
end

local elemenPilihSemua = {LinearLayout, orientation="horizontal", layout_width="fill", layout_marginBottom="8dp"}
if opsi.modeMulti then
table.insert(elemenPilihSemua, UI_Tombol_H("btnPilihSemua", T("pilih_semua", "Pilih Semua")))
table.insert(elemenPilihSemua, UI_Tombol_H("btnBatalPilih", T("batalkan_pemilihan", "Batalkan Pemilihan")))
else
elemenPilihSemua = {LinearLayout, visibility=8}
end

local layoutPicker = UI_Layout(
{TextView, id="tvPath", text=currentPath, padding="10dp", layout_marginBottom="8dp"},
UI_Input("etCari", T("cari_file", "Cari file atau folder...")),
elemenPilihSemua,
UI_Daftar("lvPicker"),
elemenTombolBawah,
UI_Tombol("btnBatal", T("tutup", "Tutup"))
)
pickerDialog.setView(loadlayout(layoutPicker))

local itemLayout = UI_ItemBaris("cbItem", "tvName")
local pickerData, adapterPicker = {}, nil
local allFolders, allFiles = {}, {}

local function updateBtnCount()
local c = 0
for k,v in pairs(selectedFiles) do c = c + 1 end
if opsi.teksTombol1 then btnAksi1.setText(opsi.teksTombol1 .. " (" .. c .. ")") end
if opsi.teksTombol2 then btnAksi2.setText(opsi.teksTombol2 .. " (" .. c .. ")") end
end

local function refreshPicker(query)
for i = #pickerData, 1, -1 do table.remove(pickerData, i) end
local q = tostring(query):lower()
for i=1, #allFolders do
if q == "" or string.find(allFolders[i].getName():lower(), q, 1, true) then
table.insert(pickerData, { cbItem = {visibility = 8}, tvName = allFolders[i].getName(), _path = allFolders[i].getAbsolutePath(), _isDir = true })
end
end
for i=1, #allFiles do
if q == "" or string.find(allFiles[i].getName():lower(), q, 1, true) then
table.insert(pickerData, { cbItem = {visibility = opsi.modeMulti and 0 or 8, checked = (selectedFiles[allFiles[i].getAbsolutePath()] == true)}, tvName = allFiles[i].getName(), _path = allFiles[i].getAbsolutePath(), _isDir = false })
end
end
if not adapterPicker then
adapterPicker = LuaAdapter(service, pickerData, itemLayout)
lvPicker.setAdapter(adapterPicker)
else
adapterPicker.notifyDataSetChanged()
end
end

local function loadPath(path)
currentPath = path
tvPath.setText(path)
etCari.setText("")
hentikanRadarFokus()
if opsi.petakanAudioAktif then PetaAudioAktif = {} end
allFolders, allFiles = {}, {}

jalankanDenganLoading(T("memuat_file", "Memuat daftar file..."), function()
local tempFolders, tempFiles = {}, {}
local d = File(path)
if d.exists() and d.isDirectory() then
local f = d.listFiles()
if f then
for i=0, #f-1 do
if not string.match(f[i].getName(), "^%.") then
if f[i].isDirectory() then table.insert(tempFolders, f[i])
elseif opsi.filterFile(f[i]) then table.insert(tempFiles, f[i]) end
end
end
end
table.sort(tempFolders, function(a,b) return string.lower(a.getName()) < string.lower(b.getName()) end)
table.sort(tempFiles, function(a,b) return string.lower(a.getName()) < string.lower(b.getName()) end)
end
return {tempFolders, tempFiles}
end, function(res)
allFolders = res[1]
allFiles = res[2]
if opsi.petakanAudioAktif then
for i=1, #allFiles do PetaAudioAktif[allFiles[i].getName()] = allFiles[i].getAbsolutePath() end
end
refreshPicker("")
if opsi.petakanAudioAktif then mulaiRadarFokus() end
end)
end
loadPath(currentPath)

etCari.addTextChangedListener(TextWatcher{ onTextChanged = function(c) refreshPicker(tostring(c)) end })

if opsi.modeMulti then
btnPilihSemua.onClick = function()
for i = 1, #pickerData do
if not pickerData[i]._isDir then
selectedFiles[pickerData[i]._path] = true
pickerData[i].cbItem.checked = true
end
end
adapterPicker.notifyDataSetChanged()
updateBtnCount()
end

btnBatalPilih.onClick = function()
selectedFiles = {}
for i = 1, #pickerData do
if not pickerData[i]._isDir then pickerData[i].cbItem.checked = false end
end
adapterPicker.notifyDataSetChanged()
updateBtnCount()
end

if opsi.teksTombol1 then
btnAksi1.onClick = function()
local toProcess = {}
for k,v in pairs(selectedFiles) do table.insert(toProcess, k) end
if #toProcess > 0 then opsi.onAksi1(toProcess, pickerDialog, restoreRadar) end
end
end

if opsi.teksTombol2 then
btnAksi2.onClick = function()
local toProcess = {}
for k,v in pairs(selectedFiles) do table.insert(toProcess, k) end
if #toProcess > 0 then opsi.onAksi2(toProcess, pickerDialog, restoreRadar) end
end
end
end

lvPicker.onItemClick = function(l, v, p, id)
local item = pickerData[p+1]
if item._isDir then loadPath(item._path)
else
if opsi.modeMulti then
if selectedFiles[item._path] then
selectedFiles[item._path] = nil
item.cbItem.checked = false
else
selectedFiles[item._path] = true
item.cbItem.checked = true
end
adapterPicker.notifyDataSetChanged()
updateBtnCount()
else
opsi.onPilihSingle(item._path, item.tvName, pickerDialog, restoreRadar)
end
end
end

pickerDialog.setOnKeyListener(function(dialog, keyCode, event)
if keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
if currentPath ~= "/storage/emulated/0" and currentPath ~= "/" then
local parent = File(currentPath).getParent()
if parent then loadPath(parent); return true end
else
restoreRadar()
pickerDialog.dismiss()
if opsi.onBatal then opsi.onBatal() end
return true
end
end
return false
end)

btnBatal.onClick = function() restoreRadar(); pickerDialog.dismiss(); if opsi.onBatal then opsi.onBatal() end end
pickerDialog.setOnCancelListener(function() restoreRadar(); if opsi.onBatal then opsi.onBatal() end end)
pickerDialog.show()
end

-- ==========================================================================
-- SisipanJam: pemilih audio dan layar pengaturan.
-- Dipasang di sini karena memakai BukaPickerKustom dan isAudioFile yang didefinisikan di atas.
-- ==========================================================================
SisipanJam.JUDUL_SLOT = function()
return {
awal = T("sisip_awal", "Audio Awalan"),
tengah = T("sisip_tengah", "Audio Tengah (bersamaan dengan ucapan)"),
akhir = T("sisip_akhir", "Audio Akhiran")
}
end

SisipanJam.DAFTAR_SUB = function()
return {
{ sub = "hour", kunci = "sisip_jam", label = T("sisip_sub_jam", "Jam (hour)"), pendek = T("sisip_sub_jam_p", "Jam") },
{ sub = "minute", kunci = "sisip_menit", label = T("sisip_sub_menit", "Menit (minute)"), pendek = T("sisip_sub_menit_p", "Menit") },
{ sub = "hourly", kunci = "sisip_hourly", label = T("sisip_sub_hourly", "Hourly (tepat per jam)"), pendek = T("sisip_sub_hourly_p", "Hourly") }
}
end

SisipanJam.subAktif = function()
local hasil = {}
for _, x in ipairs(SisipanJam.DAFTAR_SUB()) do
if pref.getBoolean(x.kunci, true) then table.insert(hasil, x) end
end
return hasil
end

SisipanJam.namaBerkas = function(p)
if p == "" then return T("sisip_belum", "belum dipilih") end
return tostring(File(p).getName())
end

SisipanJam.ringkasTempat = function()
local nama = {}
for _, x in ipairs(SisipanJam.subAktif()) do table.insert(nama, x.label) end
if #nama == 0 then return T("sisip_belum", "belum dipilih") end
return table.concat(nama, ", ")
end

SisipanJam.ringkasSlot = function(s)
if not pref.getBoolean("sisip_" .. s .. "_on", false) then return T("sisip_mati", "mati") end
local tempat = {}
for _, x in ipairs(SisipanJam.subAktif()) do
if pref.getString("sisip_" .. s .. "_" .. x.sub .. "_path", "") ~= "" then table.insert(tempat, x.pendek) end
end
if #tempat == 0 then return T("sisip_belum_audio", "belum ada audio") end
return T("sisip_aktif_di", "aktif di") .. " " .. table.concat(tempat, ", ") .. ", " .. T("sisip_volume", "Volume") .. " " .. EfekJam.fmtAngka(EfekJam.ambilAngka("sisip_" .. s .. "_vol", 100)) .. "%"
end

-- Pemilih audio: memakai pemilih berkas bawaan aplikasi, sama seperti Impor Audio dan Buat Demo Instan.
-- Fokus atau sentuh berkas memutar contoh suaranya, ketuk untuk memilih.
SisipanJam.pilihBerkas = function(judul, dirAwal, onPilih)
BukaPickerKustom({
judul = judul,
pathAwal = dirAwal or "/storage/emulated/0",
modeMulti = false,
hentikanAudioGlobal = true,
petakanAudioAktif = true,
filterFile = function(f) return isAudioFile(f) end,
onPilihSingle = function(pathDipilih, namaFile, pickerDialog, restoreRadar)
restoreRadar()
pickerDialog.dismiss()
onPilih(tostring(pathDipilih))
end
})
end

-- Dialog "Terapkan pada": tiga kotak centang (jam, menit, hourly).
SisipanJam.dialogTempat = function(onTutup)
local d = UI_Dialog(T("sisip_terapkan_pada", "Terapkan pada:"))
local lay = LinearLayout(service)
lay.setOrientation(1)
lay.setPadding(32, 16, 32, 16)
for _, x in ipairs(SisipanJam.DAFTAR_SUB()) do
local cb = CheckBox(service)
cb.setText(x.label)
cb.setChecked(pref.getBoolean(x.kunci, true))
cb.onClick = function() SisipanJam.simpanBool(x.kunci, cb.isChecked()) end
lay.addView(cb)
end
d.setView(lay)
d.setButton(T("sisip_selesai", "Selesai"), function() d.dismiss() end)
d.setOnDismissListener(function() if onTutup then onTutup() end end)
d.show()
end

-- Dialog satu jenis audio (awalan, tengah, atau akhiran): centang pakai, pilih audio per tempat, volume.
SisipanJam.dialogSlot = function(s, onTutup)
local judulSlot = SisipanJam.JUDUL_SLOT()
local aktifSub = SisipanJam.subAktif()
local d = UI_Dialog(judulSlot[s])
local scroll = ScrollView(service)
local lay = LinearLayout(service)
lay.setOrientation(1)
lay.setPadding(32, 16, 32, 16)
scroll.addView(lay)

local kunciOn = "sisip_" .. s .. "_on"
local cb = CheckBox(service)
cb.setText(T("sisip_pakai", "Pakai ") .. judulSlot[s])
cb.setChecked(pref.getBoolean(kunciOn, false))
lay.addView(cb)

if #aktifSub == 0 then
local tvKosong = TextView(service)
tvKosong.setText(T("sisip_pilih_tempat", "Centang minimal satu tempat penerapan."))
lay.addView(tvKosong)
end

if #aktifSub > 1 then
local tvPetunjuk = TextView(service)
tvPetunjuk.setText(T("sisip_petunjuk_tempat", "Tempat yang dibiarkan belum dipilih tidak diberi audio ini. Tombol Hapus mengosongkan pilihan."))
tvPetunjuk.setTextSize(13)
tvPetunjuk.setPadding(0, 8, 0, 8)
lay.addView(tvPetunjuk)
end

local LP = luajava.bindClass("android.widget.LinearLayout$LayoutParams")
for _, x in ipairs(aktifSub) do
local kunciPath = "sisip_" .. s .. "_" .. x.sub .. "_path"
local baris = LinearLayout(service)
baris.setOrientation(0)
local btn = Button(service)
local btnHapus = Button(service)
btnHapus.setText(T("sisip_hapus", "Hapus"))
local function segarkan()
local lbl = T("sisip_pilih_audio", "Pilih audio")
if #aktifSub > 1 then lbl = x.label end
local isiPath = pref.getString(kunciPath, "")
btn.setText(lbl .. ": " .. SisipanJam.namaBerkas(isiPath))
btnHapus.setEnabled(isiPath ~= "")
end
segarkan()
btn.onClick = function()
local lama = pref.getString(kunciPath, "")
local dirAwal = "/storage/emulated/0"
if lama ~= "" then dirAwal = tostring(File(lama).getParent() or dirAwal) end
SisipanJam.pilihBerkas(judulSlot[s], dirAwal, function(path)
SisipanJam.simpanTeks(kunciPath, path)
SisipanJam.simpanBool(kunciOn, true)
cb.setChecked(true)
segarkan()
service.speak(SisipanJam.namaBerkas(path))
end)
end
btnHapus.onClick = function()
SisipanJam.simpanTeks(kunciPath, "")
segarkan()
service.speak(T("sisip_dihapus", "Pilihan dihapus"))
end
baris.addView(btn, LP(0, -2, 1))
baris.addView(btnHapus, LP(-2, -2))
lay.addView(baris)
end

cb.onClick = function()
if cb.isChecked() then
local ada = false
for _, x in ipairs(aktifSub) do
if pref.getString("sisip_" .. s .. "_" .. x.sub .. "_path", "") ~= "" then ada = true end
end
if not ada then
cb.setChecked(false)
service.speak(T("sisip_pilih_dulu", "Pilih berkas audionya dulu lewat tombol di bawahnya."))
return
end
end
SisipanJam.simpanBool(kunciOn, cb.isChecked())
end

local kunciVol = "sisip_" .. s .. "_vol"
local st = { v = EfekJam.ambilAngka(kunciVol, 100) }
EfekJam.barisAngka(lay, st, {
k = "v", label = T("sisip_volume", "Volume"),
min = 0, max = 200, langkah = { 5, 1, 10 }, satuan = "%", ucap = " " .. T("sisip_persen", "persen")
}, function() EfekJam.simpanAngka(kunciVol, st.v) end)

if s == "tengah" then
local cbPotong = CheckBox(service)
cbPotong.setText(T("sisip_potong", "Potong audio tengah sesuai durasi ucapan"))
cbPotong.setChecked(pref.getBoolean("sisip_tengah_potong", false))
cbPotong.onClick = function() SisipanJam.simpanBool("sisip_tengah_potong", cbPotong.isChecked()) end
lay.addView(cbPotong)
end

d.setView(scroll)
d.setButton(T("tutup", "Tutup"), function() d.dismiss() end)
d.setOnDismissListener(function() if onTutup then onTutup() end end)
d.show()
end

-- Layar utama: satu sakelar dan empat tombol ringkas. Rincian ada di dialog masing-masing.
SisipanJam.tampilkanPengaturan = function()
local d = UI_Dialog(T("sisip_judul", "Pengaturan Audio Sisipan"))
local lay = LinearLayout(service)
lay.setOrientation(1)
lay.setPadding(32, 16, 32, 16)

local cbUtama = CheckBox(service)
cbUtama.setText(T("sisip_aktifkan", "Aktifkan audio sisipan"))
cbUtama.setChecked(pref.getBoolean("sisip_aktif", false))
lay.addView(cbUtama)

local isi = LinearLayout(service)
isi.setOrientation(1)
lay.addView(isi)

local judulPendek = {
awal = T("sisip_awal", "Audio Awalan"),
tengah = T("sisip_tengah_p", "Audio Tengah"),
akhir = T("sisip_akhir", "Audio Akhiran")
}
local btnTempat = Button(service)
isi.addView(btnTempat)
local tombolSlot = {}
local function segarkan()
btnTempat.setText(T("sisip_terapkan_pada", "Terapkan pada:") .. " " .. SisipanJam.ringkasTempat())
for _, s in ipairs(SisipanJam.SLOT) do
tombolSlot[s].setText(judulPendek[s] .. ": " .. SisipanJam.ringkasSlot(s))
end
end
btnTempat.onClick = function() SisipanJam.dialogTempat(segarkan) end
for _, s in ipairs(SisipanJam.SLOT) do
local b = Button(service)
tombolSlot[s] = b
b.onClick = function() SisipanJam.dialogSlot(s, segarkan) end
isi.addView(b)
end
segarkan()

local function atur()
isi.setVisibility(cbUtama.isChecked() and 0 or 8)
end
atur()
cbUtama.onClick = function()
SisipanJam.simpanBool("sisip_aktif", cbUtama.isChecked())
atur()
end

d.setView(lay)
d.setButton(T("tutup", "Tutup"), function() d.dismiss() end)
d.show()
end
-- ==========================================================================

local function prosesAntreanImporAudio(queue, index, themeName, overrideAction, importedNames, onComplete)
if index > #queue then
onComplete(importedNames)
return
end

local srcFile = File(queue[index])
local targetName = srcFile.getName()
local targetFile = File(basePath .. "/" .. themeName .. "/" .. targetName)

local function eksekusiTindakan(action, newOverride)
local daftarSalin = {}
local namaMasuk = nil
if action == "timpa" then
daftarSalin = { { srcFile = srcFile.getAbsolutePath(), dstFile = targetFile.getAbsolutePath() } }
namaMasuk = targetName
elseif action == "ganti_nama" then
local safeName = DapatkanNamaUnik(basePath .. "/" .. themeName, targetName)
daftarSalin = { { srcFile = srcFile.getAbsolutePath(), dstFile = basePath .. "/" .. themeName .. "/" .. safeName } }
namaMasuk = safeName
end
local function lanjutAntrean()
if namaMasuk then table.insert(importedNames, namaMasuk) end
prosesAntreanImporAudio(queue, index + 1, themeName, newOverride, importedNames, onComplete)
end
if namaMasuk then
jalankanTaskLoading(nil, kerjaSalinFlat, cjson.encode(daftarSalin), lanjutAntrean)
else
lanjutAntrean()
end
end

if targetFile.exists() then
if overrideAction then
eksekusiTindakan(overrideAction, overrideAction)
else
uiHandler.post(Runnable({
run = function()
local dKonflik = UI_Dialog(T("konfirmasi", "Konfirmasi"))
dKonflik.setMessage(targetName .. " " .. T("file_sudah_ada", "sudah ada. Apa yang ingin Anda lakukan?"))
local barisKonflik = UI_ItemBaris("cbSemuaKonflikAudio", "tvSemuaKonflikAudio")
barisKonflik.id = "llSemuaKonflikAudio"
local layoutKonflik = UI_Layout(barisKonflik)
dKonflik.setView(loadlayout(layoutKonflik))
tvSemuaKonflikAudio.setText(T("terapkan_ke_semua", "Terapkan ke semua konflik"))
llSemuaKonflikAudio.onClick = function() cbSemuaKonflikAudio.setChecked(not cbSemuaKonflikAudio.isChecked()) end
dKonflik.setButton(T("timpa", "Timpa"), function() eksekusiTindakan("timpa", cbSemuaKonflikAudio.isChecked() and "timpa" or nil) end)
dKonflik.setButton2(T("ganti_nama", "Ganti Nama"), function() eksekusiTindakan("ganti_nama", cbSemuaKonflikAudio.isChecked() and "ganti_nama" or nil) end)
dKonflik.setButton3(T("lewati", "Lewati"), function() eksekusiTindakan("lewati", cbSemuaKonflikAudio.isChecked() and "lewati" or nil) end)
dKonflik.setCancelable(false)
dKonflik.show()
end
}))
end
else
eksekusiTindakan("timpa", overrideAction)
end
end

local function rapikanFolderStruktur(folderPath)
local targetDir = File(folderPath)
if not targetDir.exists() or not targetDir.isDirectory() then return end
local configAsli = File(folderPath .. "/config")
if configAsli.exists() then return end
local files = targetDir.listFiles()
if not files then return end
local jumlahFolder = 0
local folderAnak = nil
for i = 0, #files - 1 do
if files[i].isDirectory() then
jumlahFolder = jumlahFolder + 1
folderAnak = files[i]
end
end
if jumlahFolder == 1 and folderAnak then
local configAnak = File(folderAnak.getAbsolutePath() .. "/config")
if configAnak.exists() then
local isiAnak = folderAnak.listFiles()
if isiAnak then
for j = 0, #isiAnak - 1 do
isiAnak[j].renameTo(File(folderPath .. "/" .. isiAnak[j].getName()))
end
end
folderAnak.delete()
end
end
end

local function prosesAntreanSPK(queue, index, overrideAction, importedThemes, onComplete)
if index > #queue then
onComplete(importedThemes)
return
end

local spkFile = File(queue[index])
local rawName = string.match(spkFile.getName(), "^(.+)%.spk$") or spkFile.getName()
rawName = string.gsub(rawName, "_clock_effect$", "")
rawName = string.gsub(rawName, "_clock$", "")
rawName = string.gsub(rawName, "_effect$", "")
rawName = string.gsub(rawName, "_%d%d%d%d%d%d%d%d%d%d%d%d%d%d$", "")
rawName = string.gsub(rawName, "%s+$", "")
local targetFolder = File(basePath .. "/" .. rawName)

local function eksekusiTindakan(action, newOverride)
local argsImpor = nil
local namaMasuk = nil
if action == "timpa" then
argsImpor = { spk = spkFile.getAbsolutePath(), target = targetFolder.getAbsolutePath(), hapusDulu = true }
namaMasuk = rawName
elseif action == "ganti_nama" then
local safeName = DapatkanNamaUnik(basePath, rawName)
argsImpor = { spk = spkFile.getAbsolutePath(), target = basePath .. "/" .. safeName, hapusDulu = false }
namaMasuk = safeName
end
local function lanjutAntrean()
if namaMasuk then table.insert(importedThemes, namaMasuk) end
prosesAntreanSPK(queue, index + 1, newOverride, importedThemes, onComplete)
end
if argsImpor then
jalankanTaskLoading(nil, kerjaImporSpk, cjson.encode(argsImpor), lanjutAntrean)
else
lanjutAntrean()
end
end

if targetFolder.exists() then
if overrideAction then
eksekusiTindakan(overrideAction, overrideAction)
else
uiHandler.post(Runnable({
run = function()
local dKonflik = UI_Dialog(T("konfirmasi", "Konfirmasi"))
dKonflik.setMessage(rawName .. " " .. T("file_sudah_ada", "sudah ada. Apa yang ingin Anda lakukan?"))
local barisKonflik = UI_ItemBaris("cbSemuaKonflikSPK", "tvSemuaKonflikSPK")
barisKonflik.id = "llSemuaKonflikSPK"
local layoutKonflik = UI_Layout(barisKonflik)
dKonflik.setView(loadlayout(layoutKonflik))
tvSemuaKonflikSPK.setText(T("terapkan_ke_semua", "Terapkan ke semua konflik"))
llSemuaKonflikSPK.onClick = function() cbSemuaKonflikSPK.setChecked(not cbSemuaKonflikSPK.isChecked()) end
dKonflik.setButton(T("timpa", "Timpa"), function() eksekusiTindakan("timpa", cbSemuaKonflikSPK.isChecked() and "timpa" or nil) end)
dKonflik.setButton2(T("ganti_nama", "Ganti Nama"), function() eksekusiTindakan("ganti_nama", cbSemuaKonflikSPK.isChecked() and "ganti_nama" or nil) end)
dKonflik.setButton3(T("lewati", "Lewati"), function() eksekusiTindakan("lewati", cbSemuaKonflikSPK.isChecked() and "lewati" or nil) end)
dKonflik.setCancelable(false)
dKonflik.show()
end
}))
end
else
eksekusiTindakan("timpa", overrideAction)
end
end

showAudioList = function(themeName, eventName, jsonKey)
local dir = File(basePath .. "/" .. themeName)
local dialogAudio = UI_Dialog(eventName)

local layoutAudioList = UI_Layout(
UI_Tombol("btnModePemilihan", T("mode_pilih", "Aktifkan Mode Pemilihan")),
{Button, id="btnPilihSemua", text=T("pilih_semua", "Pilih Semua"), layout_width="fill", layout_marginBottom="8dp", visibility=8},
{Button, id="btnHapusTerpilih", text=T("hapus", "Hapus"), layout_width="fill", layout_marginBottom="8dp", visibility=8},
UI_Daftar("lvAudio"),
UI_Tombol("btnBatalAudio", T("tutup", "Tutup"))
)
dialogAudio.setView(loadlayout(layoutAudioList))

local itemLayout = UI_ItemBaris("cbItem", "tvName")
local tempFiles = {}
if dir.exists() and dir.isDirectory() then
local files = dir.listFiles()
if files then
for i = 0, #files - 1 do
if isAudioFile(files[i]) then table.insert(tempFiles, tostring(files[i].getName())) end
end
table.sort(tempFiles, function(a, b) return string.lower(a) < string.lower(b) end)
end
end

hentikanRadarFokus()
PetaAudioAktif = {}
for i = 1, #tempFiles do
PetaAudioAktif[tempFiles[i]] = basePath .. "/" .. themeName .. "/" .. tempFiles[i]
end

local isSelectionMode = false
local isAllSelected = false
local selectedAudios = {}
local audioData = {}
local adapterAudio = nil

local function getAudioData()
local data = {}
if not isSelectionMode then
table.insert(data, { cbItem = {visibility = 8, checked = false}, tvName = T("standar", "Standar"), _isBawaan = true })
table.insert(data, { cbItem = {visibility = 8, checked = false}, tvName = T("tidak_ada", "Tidak ada"), _isBawaan = true })
end
for i = 1, #tempFiles do
table.insert(data, { cbItem = {visibility = isSelectionMode and 0 or 8, checked = selectedAudios[tempFiles[i]] == true}, tvName = tempFiles[i], _isBawaan = false })
end
return data
end

audioData = getAudioData()
adapterAudio = LuaAdapter(service, audioData, itemLayout)
lvAudio.setAdapter(adapterAudio)
mulaiRadarFokus()

local function updateListUI()
audioData = getAudioData()
adapterAudio = LuaAdapter(service, audioData, itemLayout)
lvAudio.setAdapter(adapterAudio)
end

local function updateBtnHapusAudio()
local count = 0
for k, v in pairs(selectedAudios) do count = count + 1 end
if count > 0 then
btnHapusTerpilih.setVisibility(0)
btnHapusTerpilih.setText(T("hapus", "Hapus") .. " (" .. count .. ")")
else
btnHapusTerpilih.setVisibility(8)
end
end

btnModePemilihan.onClick = function()
isSelectionMode = not isSelectionMode
if isSelectionMode then
dialogAudio.setTitle(T("pilih_audio", "Pilih Audio"))
btnModePemilihan.setText(T("batal_mode_pilih", "Batal Mode Pemilihan"))
btnPilihSemua.setVisibility(0)
updateBtnHapusAudio()
else
dialogAudio.setTitle(eventName)
btnModePemilihan.setText(T("mode_pilih", "Aktifkan Mode Pemilihan"))
btnPilihSemua.setVisibility(8)
btnHapusTerpilih.setVisibility(8)
selectedAudios = {}
isAllSelected = false
btnPilihSemua.setText(T("pilih_semua", "Pilih Semua"))
end
updateListUI()
end

btnPilihSemua.onClick = function()
isAllSelected = not isAllSelected
selectedAudios = {}
btnPilihSemua.setText(isAllSelected and T("batal_pilih_semua", "Batal Pilih Semua") or T("pilih_semua", "Pilih Semua"))
for i = 1, #audioData do
if not audioData[i]._isBawaan then
if isAllSelected then
selectedAudios[audioData[i].tvName] = true
audioData[i].cbItem.checked = true
else
audioData[i].cbItem.checked = false
end
end
end
adapterAudio.notifyDataSetChanged()
updateBtnHapusAudio()
end

local function refreshAudioListUI()
hentikanRadarFokus()
dialogAudio.dismiss()
showAudioList(themeName, eventName, jsonKey)
end

btnHapusTerpilih.onClick = function()
local toDelete = {}
for k, v in pairs(selectedAudios) do table.insert(toDelete, k) end
if #toDelete == 0 then return end
showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("hapus", "Hapus") .. " " .. #toDelete .. " audio?", function()
jalankanDenganLoading(nil, function()
for i=1, #toDelete do
local f = File(basePath .. "/" .. themeName .. "/" .. toDelete[i])
if f.exists() then f.delete() end
end
end, function()
refreshAudioListUI()
end)
end)
end

lvAudio.onItemClick = function(l, v, p, id)
local item = audioData[p+1]
if isSelectionMode then
if not item._isBawaan then
if selectedAudios[item.tvName] then
selectedAudios[item.tvName] = nil
item.cbItem.checked = false
else
selectedAudios[item.tvName] = true
item.cbItem.checked = true
end
adapterAudio.notifyDataSetChanged()
local allSelected = true
for i=1, #tempFiles do
if not selectedAudios[tempFiles[i]] then allSelected = false break end
end
isAllSelected = allSelected
btnPilihSemua.setText(isAllSelected and T("batal_pilih_semua", "Batal Pilih Semua") or T("pilih_semua", "Pilih Semua"))
updateBtnHapusAudio()
end
else
hentikanRadarFokus()
hentikanAudioGlobal()
local selectedAudioName = item.tvName
local jsonValue = selectedAudioName
if selectedAudioName == T("standar", "Standar") then jsonValue = "value_default"
elseif selectedAudioName == T("tidak_ada", "Tidak ada") then jsonValue = "value_none" end

local configPath = basePath .. "/" .. themeName .. "/config"
local themeDataObj = bacaJson(configPath)
themeDataObj[jsonKey] = jsonValue
simpanJson(configPath, themeDataObj)

local prefs = PreferenceManager.getDefaultSharedPreferences(service)
if prefs.getString("sound_package", "") == themeName then
service.loadSoundPackage(themeName)
end

dialogAudio.dismiss()
showEventList(themeName)
end
end

lvAudio.onItemLongClick = function(l, v, p, id)
if isSelectionMode then return true end
local item = audioData[p+1]
if item._isBawaan then return true end
local selectedAudioName = item.tvName
local targetAudioFile = File(basePath .. "/" .. themeName .. "/" .. selectedAudioName)
local optDialog = UI_Dialog(selectedAudioName)
local opsis = {T("ganti_nama", "Ganti Nama"), T("hapus", "Hapus"), T("tutup", "Tutup")}
optDialog.setItems(opsis)
optDialog.setOnItemClickListener(function(al, av, ap, ai)
local action = opsis[ap + 1]
optDialog.dismiss()
if action == T("ganti_nama", "Ganti Nama") then
showInputDialog(T("ganti_nama", "Ganti Nama"), nil, selectedAudioName, function(newName)
if newName ~= "" and newName ~= selectedAudioName then
local targetBaru = File(basePath .. "/" .. themeName .. "/" .. newName)
if targetBaru.exists() then
service.speak(T("nama_telah_digunakan", "Nama tersebut sudah digunakan, silakan pilih nama lain."))
return false
else
jalankanTaskLoading(nil, kerjaRenamePath, cjson.encode({ { src = targetAudioFile.getAbsolutePath(), dst = targetBaru.getAbsolutePath() } }), function()
refreshAudioListUI()
end)
return true
end
end
return true
end)
elseif action == T("hapus", "Hapus") then
showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("hapus", "Hapus") .. " " .. selectedAudioName .. "?", function()
jalankanTaskLoading(nil, kerjaHapusPath, cjson.encode({ targetAudioFile.getAbsolutePath() }), function()
refreshAudioListUI()
end)
end)
end
end)
optDialog.show()
return true
end

AksiDex.pasang(lvAudio, {
labelKlik = function(p) if audioData[p+1] then return T("aksi_pilih_audio", "Pilih audio ini") end end,
modePilih = function() return isSelectionMode end
})

btnBatalAudio.onClick = function() hentikanRadarFokus(); hentikanAudioGlobal(); dialogAudio.dismiss(); showEventList(themeName) end
dialogAudio.setOnCancelListener(function() hentikanRadarFokus(); hentikanAudioGlobal(); showEventList(themeName) end)
dialogAudio.show()
end

local function jalankanOtomatisasi(tasks, themeName)
jalankanDenganLoading(nil, function()
local configPath = basePath .. "/" .. themeName .. "/config"
local themeDataObj = bacaJson(configPath)
for i = 1, #tasks do
local task = tasks[i]
local jsonKey = mappingTema[task.index][2]
themeDataObj[jsonKey] = task.audioName
end
simpanJson(configPath, themeDataObj)
end, function()
local prefs = PreferenceManager.getDefaultSharedPreferences(service)
if prefs.getString("sound_package", "") == themeName then
service.loadSoundPackage(themeName)
end
showEventList(themeName)
end)
end

local function mulaiProsesTerapkan(audioList, index, tasks, themeName)
if index > #audioList then
if #tasks > 0 then
table.sort(tasks, function(a, b) return a.index < b.index end)
jalankanOtomatisasi(tasks, themeName)
else
showEventList(themeName)
end
return
end

local currentAudioName = audioList[index]
local audioPath = basePath .. "/" .. themeName .. "/" .. currentAudioName

local dialogTerapkan = UI_Dialog(T("terapkan", "Terapkan") .. ": " .. currentAudioName)
local layoutTerapkan = UI_Layout(
UI_Tombol("btnPutar", T("putar_audio", "Putar Audio")),
UI_Daftar("lvTerapkan"),
{LinearLayout, orientation="horizontal", layout_width="fill",
UI_Tombol_H("btnTutupTerapkan", T("batal", "Batal")),
UI_Tombol_H("btnTerapkanLanjut", T("terapkan", "Terapkan"))
}
)
dialogTerapkan.setView(loadlayout(layoutTerapkan))

local configPath = basePath .. "/" .. themeName .. "/config"
local themeDataObj = bacaJson(configPath)

local mapData = {}
for i = 1, #mappingTema do
local jsonKey = mappingTema[i][2]
local uiName = dapatkanString("str_event_" .. jsonKey, mappingTema[i][1])
local oldAudio = themeDataObj[jsonKey]
local subText = ""
if oldAudio and oldAudio ~= "value_default" and oldAudio ~= "value_none" and oldAudio ~= "" then
subText = "\n(" .. oldAudio .. ")"
end
table.insert(mapData, {
cbAksi = {visibility = 0, checked = false},
tvAksiName = uiName .. subText,
_uiName = uiName,
_oldAudio = oldAudio,
_index = i
})
end

local itemLayoutMap = UI_ItemBaris("cbAksi", "tvAksiName")
local adapterTerapkan = LuaAdapter(service, mapData, itemLayoutMap)
lvTerapkan.setAdapter(adapterTerapkan)

local isPlaying = false
btnPutar.onClick = function()
if isPlaying then
hentikanAudioGlobal()
btnPutar.setText(T("putar_audio", "Putar Audio"))
isPlaying = false
mulaiRadarFokus() -- Ide sampean: Radar nyala lagi saat dihentikan manual
else
hentikanRadarFokus() -- Ide sampean: Radar dimatikan sesaat sebelum diputar
hentikanAudioGlobal()
pcall(function()
globalMediaPlayer = MediaPlayer()
globalMediaPlayer.setDataSource(audioPath)
globalMediaPlayer.prepare()
globalMediaPlayer.start()
btnPutar.setText(T("hentikan_audio", "Hentikan Audio"))
isPlaying = true
globalMediaPlayer.setOnCompletionListener(function(mp)
uiHandler.post(Runnable({
run = function()
btnPutar.setText(T("putar_audio", "Putar Audio"))
isPlaying = false
mulaiRadarFokus() -- Ide sampean: Radar nyala otomatis saat audio usai
end
}))
end)
end)
end
end

lvTerapkan.onItemClick = function(l, v, p, id)
local item = mapData[p+1]
if not item.cbAksi.checked and item._oldAudio and item._oldAudio ~= "value_default" and item._oldAudio ~= "value_none" and item._oldAudio ~= "" then
local dTimpa = UI_Dialog(T("konfirmasi", "Konfirmasi"))
dTimpa.setMessage("Event '" .. item._uiName .. "' sudah terisi audio:\n" .. item._oldAudio .. "\n\nApakah Anda yakin ingin menimpanya?")

-- Fungsi kecil untuk menyegarkan "mata" radar agar tidak buta setelah dialog ditutup
local function segarkanRadar()
local PetaAudioSementara = {}
for k, val in pairs(PetaAudioAktif) do PetaAudioSementara[k] = val end
hentikanRadarFokus()
PetaAudioAktif = PetaAudioSementara
mulaiRadarFokus()
end

dTimpa.setButton(T("timpa", "Timpa"), function()
item.cbAksi.checked = true
adapterTerapkan.notifyDataSetChanged()
segarkanRadar()
end)
dTimpa.setButton2(T("batal", "Batal"), function()
segarkanRadar()
end)
dTimpa.setOnCancelListener(function()
segarkanRadar()
end)
dTimpa.show()
else
item.cbAksi.checked = not item.cbAksi.checked
adapterTerapkan.notifyDataSetChanged()
end
end

btnTerapkanLanjut.onClick = function()
hentikanAudioGlobal()
for i=1, #mapData do
if mapData[i].cbAksi.checked then
table.insert(tasks, { audioName = currentAudioName, eventName = mapData[i]._uiName, index = mapData[i]._index })
end
end
dialogTerapkan.dismiss()
uiHandler.postDelayed(Runnable({ run = function() mulaiProsesTerapkan(audioList, index + 1, tasks, themeName) end }), 300)
end

btnTutupTerapkan.onClick = function()
hentikanAudioGlobal()
dialogTerapkan.dismiss()
uiHandler.postDelayed(Runnable({ run = function() mulaiProsesTerapkan(audioList, index + 1, tasks, themeName) end }), 300)
end

dialogTerapkan.setOnCancelListener(function()
hentikanAudioGlobal()
mulaiProsesTerapkan(audioList, index + 1, tasks, themeName)
end)

dialogTerapkan.show()
end

showEventList = function(themeName)
hentikanRadarFokus()
local configPath = basePath .. "/" .. themeName .. "/config"
local themeData = bacaJson(configPath)
local listArr = ArrayList()
PetaAudioAktif = {}

for i = 1, #mappingTema do
local jsonKey = mappingTema[i][2]
local uiName = dapatkanString("str_event_" .. jsonKey, mappingTema[i][1])
local rawVal, subText = themeData[jsonKey], ""
if rawVal == "value_default" then subText = T("standar", "Standar")
elseif rawVal == "value_none" then subText = T("tidak_ada", "Tidak ada")
elseif type(rawVal) == "string" and rawVal ~= "" then
subText = rawVal
PetaAudioAktif[uiName] = basePath .. "/" .. themeName .. "/" .. rawVal
end
listArr.add(subText ~= "" and (uiName .. "\n" .. subText) or uiName)
end

local dialogSet = UI_Dialog(themeName)
local layoutSet = UI_Layout(
UI_Tombol("btnImporBaru", T("impor_audio", "Impor Audio")),
UI_Daftar("lvSet"),
UI_Tombol("btnTutupSet", T("tutup", "Tutup"))
)
dialogSet.setView(loadlayout(layoutSet))
lvSet.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, listArr))

lvSet.onItemClick = function(pl, pv, pp, pid)
hentikanRadarFokus()
hentikanAudioGlobal()
dialogSet.dismiss()
local jsonKey = mappingTema[pp + 1][2]
local targetUiName = dapatkanString("str_event_" .. jsonKey, mappingTema[pp + 1][1])
showAudioList(themeName, targetUiName, jsonKey)
end

-- Ketuk tahan pada event: hapus pengaturannya (penerapan di config + file audio), event kembali seperti belum diatur
local function hapusPenerapanEvent(jsonKey, uiName)
local obj = bacaJson(configPath)
local v = obj[jsonKey]
if v == nil then
service.speak((string.gsub(T("hapus_penerapan_kosong", "Event [E] belum diatur, tidak ada yang dihapus."), "%[E%]", uiName)))
return
end
local namaAudio = nil
if type(v) == "string" and v ~= "value_default" and v ~= "value_none" and v ~= "" then namaAudio = v end
obj[jsonKey] = nil -- kunci dibuang = event kembali ke kondisi paling awal
local fileTerhapus, fileDibiarkan = false, false
if namaAudio then
hentikanAudioGlobal()
-- File yang masih dipakai event lain jangan ikut terhapus
local masihDipakai = false
for _, val in pairs(obj) do
if type(val) == "string" and string.lower(val) == string.lower(namaAudio) then masihDipakai = true; break end
end
-- Tolak nama berisi "..", "/" atau "\" supaya config tidak bisa menghapus file di luar folder tema
local aman = not (string.find(namaAudio, "..", 1, true) or string.find(namaAudio, "/", 1, true) or string.find(namaAudio, "\\", 1, true))
if aman and not masihDipakai then
local f = File(basePath .. "/" .. themeName .. "/" .. namaAudio)
if f.exists() and f.isFile() and f.delete() then fileTerhapus = true end
elseif masihDipakai then
fileDibiarkan = true
end
end
simpanJson(configPath, obj)
local prefs = PreferenceManager.getDefaultSharedPreferences(service)
if prefs.getString("sound_package", "") == themeName then pcall(function() service.loadSoundPackage(themeName) end) end
local pesan
if fileTerhapus then
pesan = T("hapus_penerapan_selesai_file", "Pengaturan event [E] dihapus dan file audio [V] ikut dihapus.")
elseif fileDibiarkan then
pesan = T("hapus_penerapan_selesai_tetap", "Pengaturan event [E] dihapus. File audio [V] dibiarkan karena masih dipakai event lain.")
else
pesan = T("hapus_penerapan_selesai", "Pengaturan event [E] dihapus.")
end
pesan = string.gsub(pesan, "%[E%]", uiName)
pesan = string.gsub(pesan, "%[V%]", tostring(namaAudio or ""))
service.speak(pesan)
dialogSet.dismiss()
showEventList(themeName)
end

lvSet.onItemLongClick = function(pl, pv, pp, pid)
local jsonKey = mappingTema[pp + 1][2]
local uiName = dapatkanString("str_event_" .. jsonKey, mappingTema[pp + 1][1])
local v = bacaJson(configPath)[jsonKey]
local labelHapus = T("aksi_hapus_pengaturan", "Hapus Pengaturan Event")
local function tanya()
local tampil = tostring(v)
if v == "value_default" then tampil = T("standar", "Standar") elseif v == "value_none" then tampil = T("tidak_ada", "Tidak ada") end
local pesan
if type(v) == "string" and v ~= "value_default" and v ~= "value_none" and v ~= "" then
pesan = T("hapus_penerapan_tanya_audio", "Hapus pengaturan event [E] ([V])? Penerapan di config dihapus dan file audionya ikut dihapus, sehingga event kembali seperti belum diatur. Ini tidak bisa dibatalkan.")
else
pesan = T("hapus_penerapan_tanya", "Hapus pengaturan event [E] ([V])? Event kembali seperti belum diatur.")
end
pesan = string.gsub(pesan, "%[E%]", uiName)
pesan = string.gsub(pesan, "%[V%]", tampil)
showConfirmDialog(labelHapus, pesan, function() hapusPenerapanEvent(jsonKey, uiName) end)
end
if AksiDex and AksiDex.tangkap then
-- Menu Aksi pembaca layar: cukup daftarkan aksinya (hanya kalau event sudah diatur), jangan tampilkan dialog sekarang
if v ~= nil then
AksiDex.tangkap.opsi = { labelHapus }
AksiDex.tangkap.klik = function() tanya() end
end
return true
end
if v == nil then
service.speak((string.gsub(T("hapus_penerapan_kosong", "Event [E] belum diatur, tidak ada yang dihapus."), "%[E%]", uiName)))
return true
end
tanya()
return true
end
AksiDex.pasang(lvSet, { labelKlik = T("aksi_pilih_audio_event", "Pilih audio untuk event ini") })

btnTutupSet.onClick = function()
hentikanRadarFokus()
hentikanAudioGlobal()
dialogSet.dismiss()
if isShortcutMenu then isShortcutMenu = false muatUlangBahasaDanMenu() else tampilkanMenuEdit() end
end

btnImporBaru.onClick = function()
dialogSet.dismiss()
BukaPickerKustom({
judul = T("impor_audio", "Impor Audio"),
modeMulti = true,
hentikanAudioGlobal = false,
petakanAudioAktif = true,
teksTombol1 = T("impor", "Impor"),
teksTombol2 = T("impor_terapkan", "Impor & Terapkan"),
filterFile = function(f) return isAudioFile(f) end,
onAksi1 = function(toImport, pickerDialog, restoreRadar)
restoreRadar()
pickerDialog.dismiss()
prosesAntreanImporAudio(toImport, 1, themeName, nil, {}, function(importedNames)
showEventList(themeName)
end)
end,
onAksi2 = function(toImport, pickerDialog, restoreRadar)
restoreRadar()
pickerDialog.dismiss()
prosesAntreanImporAudio(toImport, 1, themeName, nil, {}, function(importedNames)
mulaiProsesTerapkan(importedNames, 1, {}, themeName)
end)
end,
onBatal = function()
showEventList(themeName)
end
})
end

dialogSet.setOnCancelListener(function() hentikanRadarFokus(); hentikanAudioGlobal(); if isShortcutMenu then isShortcutMenu = false muatUlangBahasaDanMenu() else tampilkanMenuEdit() end end)
dialogSet.show()
mulaiRadarFokus()
end

prosesAntreanBagikan = function(daftarTema)
if not daftarTema or #daftarTema == 0 then return end
local useFmt = PreferenceManager.getDefaultSharedPreferences(service).getBoolean("use_jieshuo_export_format", false)
local itemsZip = {}
for idx = 1, #daftarTema do
local selectedTheme = daftarTema[idx]
local targetFolder = File(basePath .. "/" .. selectedTheme)
if targetFolder.exists() then
local suffixExt = ""
local adaClock = File(targetFolder.getAbsolutePath() .. "/clock").exists()
local adaEfek = File(targetFolder.getAbsolutePath() .. "/effect").exists()
if adaClock and adaEfek then suffixExt = "_clock_effect"
elseif adaClock then suffixExt = "_clock"
elseif adaEfek then suffixExt = "_effect" end
local middleFmt = ""
if useFmt then middleFmt = "_" .. os.date("%Y%m%d%H%M%S") end
table.insert(itemsZip, {src = targetFolder.getAbsolutePath(), out = jieshuoPath .. "/" .. selectedTheme .. middleFmt .. suffixExt .. ".spk"})
end
end
if #itemsZip == 0 then
service.speak(T("gagal_bagikan", "Gagal menyiapkan file untuk dibagikan."))
return
end
service.speak(T("membagikan", "Membagikan tema ") .. #itemsZip)
jalankanZipTask(T("membagikan", "Membagikan tema ") .. #itemsZip, itemsZip, function(hasil)
if hasil and #hasil > 0 then
pcall(function() bagikanBanyakFile(hasil) end)
else
service.speak(T("gagal_bagikan", "Gagal menyiapkan file untuk dibagikan."))
end
end)
end

local function getListPref(key)
local prefs = PreferenceManager.getDefaultSharedPreferences(service)
local str = prefs.getString(key, "[]")
local status, res = pcall(cjson.decode, str)
if status and type(res) == "table" then return res else return {} end
end
local function setListPref(key, tbl)
local prefs = PreferenceManager.getDefaultSharedPreferences(service)
prefs.edit().putString(key, cjson.encode(tbl)).apply()
end
local function isInList(key, val)
local lst = getListPref(key)
for i, v in ipairs(lst) do if v == val then return true, i end end
return false, -1
end
local function toggleListPref(key, val)
local lst = getListPref(key)
local exists, idx = isInList(key, val)
if exists then table.remove(lst, idx) else table.insert(lst, val) end
setListPref(key, lst)
end
local function updateNameInPref(key, oldName, newName)
local lst = getListPref(key)
local exists, idx = isInList(key, oldName)
if exists then
lst[idx] = newName
setListPref(key, lst)
end
end

local function autoRestoreCadangan(onComplete)
local dirCad = File(backupPath)
if not dirCad.exists() then
dirCad.mkdirs()
if onComplete then onComplete() end
return
end
local butuhRestore = false
local files = dirCad.listFiles()
if files then
for i = 0, #files - 1 do
if files[i].isDirectory() then
local targetFolder = File(basePath .. "/" .. files[i].getName())
if not targetFolder.exists() then
butuhRestore = true
break
end
end
end
end
if not butuhRestore then
if onComplete then onComplete() end
return
end

local myId = DapatkanAndroidID()
local isAdminPulih = (ADMIN_IDS[myId] or ADMIN_KEDUA_IDS[myId] or ADMIN_KETIGA_IDS[myId] or JATAH.aktif("pulih_otomatis")) and true or false
local sisaPulih = true
if not isAdminPulih then
local brankasP = AmbilDataBrankas()
ResetLimitJikaSudahLewat(brankasP, myId, "pulih_otomatis")
sisaPulih = ((brankasP[myId] and tonumber(brankasP[myId]["pulih_otomatis"])) or 0) < BATAS_JATAH_FREE
end
if sisaPulih then
jalankanDenganLoading(T("memulihkan_cadangan", "Memulihkan data cadangan..."), function()
if files then
for i = 0, #files - 1 do
if files[i].isDirectory() then
local namaTema = files[i].getName()
local targetFolder = File(basePath .. "/" .. namaTema)
if not targetFolder.exists() then
targetFolder.mkdirs()
local isiCadangan = files[i].listFiles()
if isiCadangan then
for j = 0, #isiCadangan - 1 do
SalinFile(isiCadangan[j].getAbsolutePath(), targetFolder.getAbsolutePath() .. "/" .. isiCadangan[j].getName())
end
end
end
end
end
end
end, function()
if not isAdminPulih then
local nPulih = CatatPemakaianFreemium("pulih_otomatis", true)
if nPulih then
local ucapPulih = string.gsub(T("jatah_pulih_terpakai", "Jatah pemulihan otomatis terpakai [N] dari 3."), "%[N%]", tostring(nPulih))
service.speak(ucapPulih)
end
end
if onComplete then onComplete() end
end)
else
local dPremium = UI_Dialog(T("informasi", "Informasi"))
dPremium.setMessage(T("info_pulih_premium", "Jatah pemulihan otomatis sudah habis (3 kali per 24 jam sejak pemakaian pertama). Silakan masuk ke menu pencadangan, atau tingkatkan ke Premium."))
dPremium.setButton(T("tombol_oke", "Oke"), function()
dPremium.dismiss()
if onComplete then onComplete() end
end)
dPremium.setCancelable(false)
dPremium.show()
end
end

local function cekStatusCadangan(nama)
local fU = File(basePath .. "/" .. nama)
local fCad = File(backupPath .. "/" .. nama)
if not fCad.exists() or not fCad.isDirectory() then return 0 end
local cList = fCad.listFiles()
local uList = fU.listFiles()
local cFiles, uFiles = {}, {}
if cList then for j=0, #cList-1 do if cList[j].isFile() then table.insert(cFiles, cList[j].getName()) end end end
if uList then for j=0, #uList-1 do if uList[j].isFile() then table.insert(uFiles, uList[j].getName()) end end end
if #cFiles ~= #uFiles then return 2 end
local mapC = {}
for j=1, #cFiles do mapC[cFiles[j]] = true end
for j=1, #uFiles do if not mapC[uFiles[j]] then return 2 end end
local jsonC = bacaJson(fCad.getAbsolutePath().."/config")
local jsonU = bacaJson(fU.getAbsolutePath().."/config")
local function deepCompare(t1, t2)
if type(t1) ~= type(t2) then return false end
if type(t1) ~= "table" then return t1 == t2 end
for k, v in pairs(t1) do if not deepCompare(v, t2[k]) then return false end end
for k, v in pairs(t2) do if t1[k] == nil then return false end end
return true
end
if not deepCompare(jsonC, jsonU) then return 2 end
return 1
end

tampilkanMenuEdit = function()
folderSuara = dapatkanString("nama_folder_suara", "Suara")
basePath = jieshuoPath .. "/" .. folderSuara
backupPath = "/storage/emulated/0/.cadangan"
autoRestoreCadangan(function()

local function HelperHilangkanFormat(tema)
local targetFolder = File(basePath .. "/" .. tema)
local configPath = basePath .. "/" .. tema .. "/config"
local themeDataObj = bacaJson(configPath)
local renamedMap = {}
local function hapusFormatFolder(dir)
local files = dir.listFiles()
if files then
for i = 0, #files - 1 do
local f = files[i]
if f.isDirectory() then hapusFormatFolder(f) elseif isAudioFile(f) then
local oldName = f.getName()
local newName = string.match(oldName, "^(.+)%..+$")
if newName and newName ~= "" then
if f.renameTo(File(dir.getAbsolutePath() .. "/" .. newName)) then renamedMap[oldName] = newName end
end end end end end
hapusFormatFolder(targetFolder)
local hasChanges = false
for k, v in pairs(themeDataObj) do
if type(v) == "string" and renamedMap[v] then themeDataObj[k] = renamedMap[v]; hasChanges = true end
end
if hasChanges then simpanJson(configPath, themeDataObj) end
end

local function HelperNamaEventFormat(tema, withFormat)
local targetFolder = File(basePath .. "/" .. tema)
local configPath = basePath .. "/" .. tema .. "/config"
local themeDataObj = bacaJson(configPath)
local newThemeDataObj = {}
local filesToProcess = {}
local tempDir = File(basePath .. "/.temp_snapshot_" .. tema)
if tempDir.exists() then deleteRecursive(tempDir) end
tempDir.mkdirs()
local filesToDelete = {}
for i = 1, #mappingTema do
local uiName = dapatkanString("str_event_" .. mappingTema[i][2], mappingTema[i][1])
local safeUiName = string.gsub(uiName, '[\\/:%*%?"<>|]', "_")
local jsonKey = mappingTema[i][2]
local oldFileName = themeDataObj[jsonKey]
if oldFileName and oldFileName ~= "value_default" and oldFileName ~= "value_none" and oldFileName ~= "" then
local oldFile = File(basePath .. "/" .. tema .. "/" .. oldFileName)
if oldFile.exists() and oldFile.isFile() then
local ext = ""
if withFormat then ext = string.match(oldFileName, "^.+(%..+)$") or "" end
local newFileName = safeUiName .. ext
newThemeDataObj[jsonKey] = newFileName
if oldFileName ~= newFileName then
local tempPath = tempDir.getAbsolutePath() .. "/temp_" .. tostring(i)
SalinFile(oldFile.getAbsolutePath(), tempPath)
table.insert(filesToProcess, { src = tempPath, dst = basePath .. "/" .. tema .. "/" .. newFileName })
filesToDelete[oldFile.getAbsolutePath()] = true
end else newThemeDataObj[jsonKey] = oldFileName end
elseif oldFileName then newThemeDataObj[jsonKey] = oldFileName end
end
for k, v in pairs(themeDataObj) do if not newThemeDataObj[k] then newThemeDataObj[k] = v end end
for k, v in pairs(newThemeDataObj) do
if type(v) == "string" and v ~= "value_default" and v ~= "value_none" and v ~= "" then filesToDelete[basePath .. "/" .. tema .. "/" .. v] = nil end
end
for path, _ in pairs(filesToDelete) do local fDel = File(path); if fDel.exists() then fDel.delete() end end
for i = 1, #filesToProcess do SalinFile(filesToProcess[i].src, filesToProcess[i].dst) end
deleteRecursive(tempDir)
simpanJson(configPath, newThemeDataObj)
end

local Kastem = {}

function Kastem.trim(s)
return (tostring(s):match("^%s*(.-)%s*$")) or ""
end

function Kastem.jumlah(s)
local n = 0
for _ in pairs(s) do n = n + 1 end
return n
end

-- Daftar event yang punya file audio di salah satu tema yang diproses (urut sesuai mappingTema)
function Kastem.daftarEvent(temaList)
local ada = {}
for t = 1, #temaList do
local obj = bacaJson(basePath .. "/" .. temaList[t] .. "/config")
for i = 1, #mappingTema do
local key = mappingTema[i][2]
local v = obj[key]
if not ada[key] and type(v) == "string" and v ~= "value_default" and v ~= "value_none" and v ~= "" then
local f = File(basePath .. "/" .. temaList[t] .. "/" .. v)
if f.exists() and f.isFile() then ada[key] = true end
end
end
end
local hasil = {}
for i = 1, #mappingTema do
local key = mappingTema[i][2]
if ada[key] then
table.insert(hasil, { key = key, label = dapatkanString("str_event_" .. key, mappingTema[i][1]) })
end
end
return hasil
end

-- Terapkan rencana penamaan ke satu tema. plan.roundOf[key] = urutan nama kastem, plan.eventKeys[key] = pakai nama event
function Kastem.terapkan(tema, withFormat, plan)
local configPath = basePath .. "/" .. tema .. "/config"
local themeDataObj = bacaJson(configPath)
local newThemeDataObj = {}
local filesToProcess = {}
local tempDir = File(basePath .. "/.temp_snapshot_" .. tema)
if tempDir.exists() then deleteRecursive(tempDir) end
tempDir.mkdirs()
local filesToDelete = {}
local counters, used = {}, {}
for i = 1, #mappingTema do
local jsonKey = mappingTema[i][2]
local oldFileName = themeDataObj[jsonKey]
if oldFileName and oldFileName ~= "value_default" and oldFileName ~= "value_none" and oldFileName ~= "" then
local oldFile = File(basePath .. "/" .. tema .. "/" .. oldFileName)
local rIdx = plan.roundOf[jsonKey]
if oldFile.exists() and oldFile.isFile() and (rIdx or plan.eventKeys[jsonKey]) then
local ext = ""
if withFormat then ext = string.match(oldFileName, "^.+(%..+)$") or "" end
local base
if rIdx then
local n = counters[rIdx] or 0
repeat
n = n + 1
base = plan.rounds[rIdx].nama .. tostring(n)
until not used[string.lower(base .. ext)]
counters[rIdx] = n
else
local uiName = dapatkanString("str_event_" .. jsonKey, mappingTema[i][1])
base = string.gsub(uiName, '[\\/:%*%?"<>|]', "_")
if used[string.lower(base .. ext)] then base = base .. "_" .. tostring(i) end
end
local newFileName = base .. ext
used[string.lower(newFileName)] = true
newThemeDataObj[jsonKey] = newFileName
if oldFileName ~= newFileName then
local tempPath = tempDir.getAbsolutePath() .. "/temp_" .. tostring(i)
SalinFile(oldFile.getAbsolutePath(), tempPath)
table.insert(filesToProcess, { src = tempPath, dst = basePath .. "/" .. tema .. "/" .. newFileName })
filesToDelete[oldFile.getAbsolutePath()] = true
end
else newThemeDataObj[jsonKey] = oldFileName end
elseif oldFileName then newThemeDataObj[jsonKey] = oldFileName end
end
for k, v in pairs(themeDataObj) do if not newThemeDataObj[k] then newThemeDataObj[k] = v end end
for k, v in pairs(newThemeDataObj) do
if type(v) == "string" and v ~= "value_default" and v ~= "value_none" and v ~= "" then filesToDelete[basePath .. "/" .. tema .. "/" .. v] = nil end
end
for path, _ in pairs(filesToDelete) do local fDel = File(path); if fDel.exists() then fDel.delete() end end
for i = 1, #filesToProcess do SalinFile(filesToProcess[i].src, filesToProcess[i].dst) end
deleteRecursive(tempDir)
simpanJson(configPath, newThemeDataObj)
end

function Kastem.namaValid(ctx, nama)
if nama == "" then
service.speak(T("tidak_boleh_kosong", "Kotak teks tidak boleh kosong!"))
return false
end
if nama:match('[/\\:*?"<>|]') then
service.speak(T("karakter_terlarang", "Nama tidak boleh mengandung karakter khusus seperti garis miring, titik dua, atau bintang."))
return false
end
for i = 1, #ctx.plan.rounds do
if string.lower(ctx.plan.rounds[i].nama) == string.lower(nama) then
service.speak(T("kastem_nama_kembar", "Nama ini sudah dipakai pada langkah sebelumnya, masukkan nama lain."))
return false
end
end
return true
end

-- Dialog daftar centang event. Tidak boleh memilih semua event yang tersisa.
function Kastem.cek(ctx)
local st = ctx.st
local data = {}
for i = 1, #ctx.sisa do
local e = ctx.sisa[i]
table.insert(data, { cbItem = { checked = (st.pilihan[e.key] == true) }, tvName = e.label, key = e.key })
end
local dl = UI_Dialog(T("kastem_pilih_judul", "Pilih Nama Event"))
local lay = UI_Layout(
UI_Teks(T("kastem_pilih_info", "Centang event yang akan memakai namamu. Dilarang memilih semua; jika ingin semua, pilih Semua Event Suara pada penerapan.")),
UI_Daftar("lvKastemEvent")
)
dl.setView(loadlayout(lay))
local lv = lvKastemEvent
local adapter = LuaAdapter(service, data, UI_ItemBaris("cbItem", "tvName"))
lv.setAdapter(adapter)
lv.onItemClick = function(l, v, p, id)
local it = data[p + 1]
if it then
it.cbItem.checked = not it.cbItem.checked
adapter.notifyDataSetChanged()
end
end
dl.setButton(T("terapkan", "Terapkan"), function()
local pilih, n = {}, 0
for i = 1, #data do
if data[i].cbItem.checked then pilih[data[i].key] = true; n = n + 1 end
end
st.pilihan = pilih
if n == 0 then
service.speak(T("kastem_pilih_dulu", "Pilih dulu minimal satu event yang akan memakai namamu."))
Kastem.cek(ctx)
return
end
if n >= #ctx.sisa then
service.speak(T("kastem_dilarang_semua", "Dilarang memilih semua event. Kalau ingin semua, lebih baik pilih Semua Event Suara pada penerapan."))
Kastem.cek(ctx)
return
end
if st.sisaMode == 0 then
if Kastem.namaValid(ctx, st.nama) then Kastem.lanjut(ctx) else Kastem.dialog(ctx) end
else
Kastem.dialog(ctx)
end
end)
dl.setButton2(T("batal", "Batal"), function() Kastem.dialog(ctx) end)
dl.setOnCancelListener(function() Kastem.dialog(ctx) end)
dl.setCancelable(false)
dl.show()
end

-- Catat nama saat ini sebagai satu putaran, lalu lanjut ke nama berikutnya (sisa = nama kastem) atau selesai (sisa = nama event)
function Kastem.lanjut(ctx)
local st = ctx.st
local nomor = #ctx.plan.rounds + 1
ctx.plan.rounds[nomor] = { nama = st.nama }
local sisaBaru = {}
for i = 1, #ctx.sisa do
local e = ctx.sisa[i]
if st.pilihan[e.key] then ctx.plan.roundOf[e.key] = nomor else table.insert(sisaBaru, e) end
end
if st.sisaMode == 0 then
Kastem.dialog({
withFormat = ctx.withFormat, urutan = ctx.urutan + 1, sisa = sisaBaru, plan = ctx.plan,
selesai = ctx.selesai, batal = ctx.batal,
st = { nama = "", scope = 0, sisaMode = 0, pilihan = {} }
})
else
for i = 1, #sisaBaru do ctx.plan.eventKeys[sisaBaru[i].key] = true end
ctx.selesai(ctx.plan)
end
end

function Kastem.dialog(ctx)
local st = ctx.st
local judul = ctx.withFormat and T("nama_kastem_dengan_format", "Nama Kastem Dengan Format") or T("nama_kastem_tanpa_format", "Nama Kastem Tanpa Format")
local dlg = UI_Dialog(judul)
local petunjuk = T("kastem_petunjuk", "Masukkan namamu di bawah ini untuk dijadikan nama tema suara.")
if ctx.urutan > 1 then
local info = string.gsub(T("kastem_nama_ke", "Ini nama ke-[N]. Event yang tersisa: [M]."), "%[N%]", tostring(ctx.urutan))
info = string.gsub(info, "%[M%]", tostring(#ctx.sisa))
petunjuk = petunjuk .. " " .. info
end
local lay = UI_Layout(
UI_Teks(petunjuk),
{EditText, id="etKastemNama", hint=T("kastem_hint", "Masukkan namamu"), layout_width="fill", layout_marginBottom="8dp"},
UI_Teks(T("kastem_terapkan_di", "Terapkan di mana:")),
{Spinner, id="spKastemScope"},
{TextView, id="tvKastemSisa", text=T("kastem_sisa_label", "Untuk sisa event yang tidak ditandai:"), textSize="16sp", layout_marginTop="12dp", layout_marginBottom="4dp", visibility=8},
{Spinner, id="spKastemSisa", visibility=8},
{Button, id="btnKastemPilih", text="", layout_width="fill", layout_marginTop="12dp", visibility=8}
)
local scroll = ScrollView(service)
scroll.addView(loadlayout(lay))
dlg.setView(scroll)
local et, sp1, sp2, tvSisa, btnPilih = etKastemNama, spKastemScope, spKastemSisa, tvKastemSisa, btnKastemPilih

local bisaSebagian = #ctx.sisa >= 2
local d1 = ArrayList()
d1.add(T("kastem_semua", "Semua Event Suara"))
if bisaSebagian then d1.add(T("kastem_sebagian", "Sebagian Event Suara")) end
sp1.setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_item, d1))
local d2 = ArrayList()
d2.add(T("kastem_sisa_kastem", "Nama Kastem"))
d2.add(T("kastem_sisa_event", "Nama Event"))
sp2.setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_item, d2))
et.setText(st.nama)
sp1.setSelection((bisaSebagian and st.scope == 1) and 1 or 0)
sp2.setSelection(st.sisaMode == 1 and 1 or 0)

local function labelPilih()
local t = T("kastem_tombol_pilih", "Pilih Nama Event yang Kamu Jadikan Namamu")
local n = Kastem.jumlah(st.pilihan)
if n > 0 then t = t .. " (" .. tostring(n) .. ")" end
return t
end
btnPilih.setText(labelPilih())

local function perbarui()
local v = (sp1.getSelectedItemPosition() == 1) and 0 or 8
tvSisa.setVisibility(v)
sp2.setVisibility(v)
btnPilih.setVisibility(v)
end
local okListener = pcall(function()
sp1.setOnItemSelectedListener(luajava.createProxy("android.widget.AdapterView$OnItemSelectedListener", {
onItemSelected = function(parent, view, pos, id) perbarui() end,
onNothingSelected = function(parent) end
}))
end)
if okListener then
perbarui()
elseif bisaSebagian then
-- Cadangan bila pendengar dropdown tidak tersedia: tampilkan semua kontrol
tvSisa.setVisibility(0); sp2.setVisibility(0); btnPilih.setVisibility(0)
end

local function simpan()
st.nama = Kastem.trim(et.getText())
st.scope = sp1.getSelectedItemPosition()
st.sisaMode = sp2.getSelectedItemPosition()
end

btnPilih.onClick = function()
simpan()
dlg.dismiss()
Kastem.cek(ctx)
end

dlg.setButton(T("ubah_nama", "Ubah Nama"), function()
simpan()
if not Kastem.namaValid(ctx, st.nama) then Kastem.dialog(ctx); return end
if st.scope == 0 or not bisaSebagian then
local n = #ctx.plan.rounds + 1
ctx.plan.rounds[n] = { nama = st.nama }
for i = 1, #ctx.sisa do ctx.plan.roundOf[ctx.sisa[i].key] = n end
ctx.selesai(ctx.plan)
elseif Kastem.jumlah(st.pilihan) == 0 then
service.speak(T("kastem_pilih_dulu", "Pilih dulu minimal satu event yang akan memakai namamu."))
Kastem.dialog(ctx)
else
Kastem.lanjut(ctx)
end
end)
dlg.setButton2(T("batal", "Batal"), function() ctx.batal() end)
dlg.setOnCancelListener(function() ctx.batal() end)
dlg.setCancelable(false)
dlg.show()
end

function Kastem.mulai(temaList, withFormat, onSelesai, onBatal)
local sisa = Kastem.daftarEvent(temaList)
if #sisa == 0 then
service.speak(T("kastem_tidak_ada_event", "Tidak ada event yang memiliki file audio."))
onBatal()
return
end
Kastem.dialog({
withFormat = withFormat, urutan = 1, sisa = sisa,
plan = { rounds = {}, roundOf = {}, eventKeys = {} },
selesai = onSelesai, batal = onBatal,
st = { nama = "", scope = 0, sisaMode = 0, pilihan = {} }
})
end

local mainDialog = UI_Dialog(T("edit_tema", "Edit Tema Suara"))

local layoutEdit = UI_Layout(
{LinearLayout, id="layoutSearchEdit", orientation="horizontal", layout_width="fill", layout_marginBottom="8dp", gravity="center_vertical",
{EditText, id="searchBarEdit", hint=T("cari_tema", "Cari tema..."), layout_weight=1},
{Button, id="btnBuatEdit", text=T("buat", "Buat"), layout_marginLeft="8dp"}
},
UI_Tombol("btnDaftarFavorit", T("daftar_favorit", "Daftar Tema Favorit")),
UI_Tombol("btnModePemilihanEdit", T("mode_pilih", "Aktifkan Mode Pemilihan")),
{Button, id="btnPilihSemuaEdit", text=T("pilih_semua", "Pilih Semua"), layout_width="fill", layout_marginBottom="8dp", visibility=8},
{LinearLayout, id="layoutAksiEdit", orientation="horizontal", layout_width="fill", layout_marginBottom="8dp", visibility=8,
UI_Tombol_H("btnHapusTerpilihEdit", T("hapus", "Hapus")),
UI_Tombol_H("btnAksiMassal", T("aksi_massal", "Aksi Lainnya..."))
},
UI_Daftar("themeListView"),
UI_Tombol("closeBtnEdit", T("tutup", "Tutup"))
)
mainDialog.setView(loadlayout(layoutEdit))

local itemLayoutTheme = UI_ItemBaris("cbItem", "tvName")

local themeList, filteredList = {}, {}
local themeData = {}
local isSelectionModeEdit = false
local isAllSelectedEdit = false
local selectedThemes = {}
local adapterEdit = nil

-- Hasil pemeriksaan cadangan per tema, disimpan sebentar. Menu Aksi pembaca layar memanggil
-- penangan ketuk tahan tiap kali baris disentuh/digeser, dan pemeriksaan cadangan itu berat
-- (membuka dua folder tema + membaca dua berkas config), jadi tanpa cache daftar jadi lag.
local cacheCadangan = {}

local function getThemeData()
local pinnedList = {}
local normalList = {}
local semat = {}
for _, v in ipairs(getListPref("pinned_themes")) do semat[v] = true end
for i = 1, #filteredList do
local fName = filteredList[i]
local itemData = {
cbItem = {visibility = isSelectionModeEdit and 0 or 8, checked = selectedThemes[fName] == true},
realName = fName
}
if semat[fName] then
itemData.tvName = fName .. T("label_semat", " [Semat]")
table.insert(pinnedList, itemData)
else
itemData.tvName = fName
table.insert(normalList, itemData)
end
end
local data = {}
for i=1, #pinnedList do table.insert(data, pinnedList[i]) end
for i=1, #normalList do table.insert(data, normalList[i]) end
return data
end

local function updateListUI()
themeData = getThemeData()
adapterEdit = LuaAdapter(service, themeData, itemLayoutTheme)
themeListView.setAdapter(adapterEdit)
end

local function refreshData(query)
cacheCadangan = {}
themeList = {}
filteredList = {}
local dir = File(basePath)
if dir.exists() and dir.isDirectory() then
local files = dir.listFiles()
if files then
for i = 0, #files - 1 do
if files[i].isDirectory() and File(files[i].getAbsolutePath() .. "/config").exists() then
table.insert(themeList, tostring(files[i].getName()))
end
end
end
end
table.sort(themeList, function(a, b) return string.lower(a) < string.lower(b) end)
for i = 1, #themeList do
if not query or query == "" or string.find(string.lower(themeList[i]), string.lower(query), 1, true) then
table.insert(filteredList, themeList[i])
end
end
updateListUI()
end
refreshData("")

local function updateAksiEdit()
local count = 0
for k, v in pairs(selectedThemes) do count = count + 1 end
if count > 0 then
layoutAksiEdit.setVisibility(0)
btnHapusTerpilihEdit.setText(T("hapus", "Hapus") .. " (" .. count .. ")")
btnAksiMassal.setText(T("aksi_massal", "Aksi Lainnya...") .. " (" .. count .. ")")
else
layoutAksiEdit.setVisibility(8)
end
end

btnModePemilihanEdit.onClick = function()
isSelectionModeEdit = not isSelectionModeEdit
if isSelectionModeEdit then
mainDialog.setTitle(T("edit_tema", "Edit Tema Suara"))
layoutSearchEdit.setVisibility(8)
btnModePemilihanEdit.setText(T("batal_mode_pilih", "Batal Mode Pemilihan"))
btnPilihSemuaEdit.setVisibility(0)
updateAksiEdit()
else
mainDialog.setTitle(T("edit_tema", "Edit Tema Suara"))
layoutSearchEdit.setVisibility(0)
btnModePemilihanEdit.setText(T("mode_pilih", "Aktifkan Mode Pemilihan"))
btnPilihSemuaEdit.setVisibility(8)
layoutAksiEdit.setVisibility(8)
selectedThemes = {}
isAllSelectedEdit = false
btnPilihSemuaEdit.setText(T("pilih_semua", "Pilih Semua"))
end
updateListUI()
end

btnPilihSemuaEdit.onClick = function()
isAllSelectedEdit = not isAllSelectedEdit
selectedThemes = {}
btnPilihSemuaEdit.setText(isAllSelectedEdit and T("batal_pilih_semua", "Batal Pilih Semua") or T("pilih_semua", "Pilih Semua"))
for i = 1, #themeData do
if isAllSelectedEdit then
selectedThemes[themeData[i].realName or themeData[i].tvName] = true
themeData[i].cbItem.checked = true
else
themeData[i].cbItem.checked = false
end
end
adapterEdit.notifyDataSetChanged()
updateAksiEdit()
end

btnAksiMassal.onClick = function()
local toProcess = {}
local countA, countB, countC = 0, 0, 0
local listA, listB, listC = {}, {}, {}
for k, v in pairs(selectedThemes) do
table.insert(toProcess, k)
local status = cekStatusCadangan(k)
if status == 0 then countA = countA + 1; table.insert(listA, k)
elseif status == 1 then countB = countB + 1; table.insert(listB, k)
elseif status == 2 then countC = countC + 1; table.insert(listC, k) end
end
if #toProcess == 0 then return end
local options = {T("bagikan", "Bagikan"), T("tambah_favorit", "Tambahkan ke Favorit"), T("hapus_favorit", "Hapus dari Favorit")}
if countA > 0 then table.insert(options, T("cadangkan", "Cadangkan") .. " (" .. countA .. ")") end
if countC > 0 then table.insert(options, T("cadangkan_ulang", "Cadangkan Ulang") .. " (" .. countC .. ")") end
if (countB + countC) > 0 then table.insert(options, T("hapus_cadangan", "Hapus dari Cadangan") .. " (" .. (countB + countC) .. ")") end
table.insert(options, T("cadangkan_spk", "Cadangkan Jadi SPK"))
table.insert(options, T("hilangkan_format", "Hilangkan Format Audio"))
table.insert(options, T("nama_tanpa_format", "Nama Event Tanpa Format"))
table.insert(options, T("nama_dengan_format", "Nama Event Dengan Format"))
table.insert(options, T("hapus_tak_terdaftar", "Hapus Audio Tak Terdaftar"))
table.insert(options, T("nama_kastem_tanpa_format", "Nama Kastem Tanpa Format"))
table.insert(options, T("nama_kastem_dengan_format", "Nama Kastem Dengan Format"))
table.insert(options, T("tutup", "Tutup"))
local optDialog = UI_Dialog(T("aksi_massal", "Aksi Lainnya...") .. " (" .. #toProcess .. ")")
optDialog.setItems(options)
optDialog.setOnItemClickListener(function(al, av, ap, ai)
local action = options[ap + 1]

-- Gerbang premium telah dipindahkan ke sistem Kuota Gaib

optDialog.dismiss()

if action == T("tambah_favorit", "Tambahkan ke Favorit") then
for pt=1, #toProcess do
if not isInList("favorite_themes", toProcess[pt]) then toggleListPref("favorite_themes", toProcess[pt]) end
end
refreshData(tostring(searchBarEdit.getText()))
elseif action == T("hapus_favorit", "Hapus dari Favorit") then
for pt=1, #toProcess do
if isInList("favorite_themes", toProcess[pt]) then toggleListPref("favorite_themes", toProcess[pt]) end
end
refreshData(tostring(searchBarEdit.getText()))
elseif action == T("bagikan", "Bagikan") then
mainDialog.dismiss()
prosesAntreanBagikan(toProcess)
elseif action == T("cadangkan_spk", "Cadangkan Jadi SPK") then
mainDialog.dismiss()
local itemsZip = {}
local spkDir = File("/storage/emulated/0/nadi cadangan SPK")
if not spkDir.exists() then spkDir.mkdirs() end
for pt=1, #toProcess do
local selectedTheme = toProcess[pt]
local targetFolder = File(basePath .. "/" .. selectedTheme)
local suffixExt = ""
local adaClock = File(targetFolder.getAbsolutePath() .. "/clock").exists()
local adaEfek = File(targetFolder.getAbsolutePath() .. "/effect").exists()
if adaClock and adaEfek then suffixExt = "_clock_effect"
elseif adaClock then suffixExt = "_clock"
elseif adaEfek then suffixExt = "_effect" end
local middleFmt = ""
if PreferenceManager.getDefaultSharedPreferences(service).getBoolean("use_jieshuo_export_format", false) then
middleFmt = "_" .. os.date("%Y%m%d%H%M%S")
end
local baseSpkName = selectedTheme .. middleFmt .. suffixExt .. ".spk"
local finalSpkName = baseSpkName
if middleFmt == "" then finalSpkName = DapatkanNamaUnik(spkDir.getAbsolutePath(), baseSpkName) end
local zipFilePath = spkDir.getAbsolutePath() .. "/" .. finalSpkName
table.insert(itemsZip, {src = targetFolder.getAbsolutePath(), out = zipFilePath})
end
jalankanZipTask("Mencadangkan " .. #toProcess .. " tema ke SPK...", itemsZip, function() service.speak("Semua tema berhasil dicadangkan ke SPK."); tampilkanMenuEdit() end)
elseif action == T("cadangkan", "Cadangkan") .. " (" .. countA .. ")" or action == T("cadangkan_ulang", "Cadangkan Ulang") .. " (" .. countC .. ")" then
mainDialog.dismiss()
local targetList = (action == T("cadangkan", "Cadangkan") .. " (" .. countA .. ")") and listA or listC
jalankanDenganLoading(nil, function()
File(backupPath).mkdirs()
for pt=1, #targetList do
local selectedTheme = targetList[pt]
local targetFolder = File(basePath .. "/" .. selectedTheme)
local cadFolder = File(backupPath .. "/" .. selectedTheme)
if cadFolder.exists() then deleteRecursive(cadFolder) end
cadFolder.mkdirs()
local files = targetFolder.listFiles()
if files then
for i=0, #files-1 do SalinFile(files[i].getAbsolutePath(), cadFolder.getAbsolutePath() .. "/" .. files[i].getName()) end
end
end
end, function() tampilkanMenuEdit() end)
elseif action == T("hapus_cadangan", "Hapus dari Cadangan") .. " (" .. (countB + countC) .. ")" then
mainDialog.dismiss()
jalankanDenganLoading(nil, function()
for pt=1, #toProcess do
local status = cekStatusCadangan(toProcess[pt])
if status == 1 or status == 2 then
local cadFolder = File(backupPath .. "/" .. toProcess[pt])
if cadFolder.exists() then deleteRecursive(cadFolder) end
end
end
end, function() tampilkanMenuEdit() end)
elseif action == T("hilangkan_format", "Hilangkan Format Audio") then
mainDialog.dismiss()
CekKuotaFreemium("edit_hilangkan_format", function()
jalankanDenganLoading(nil, function()
for pt=1, #toProcess do HelperHilangkanFormat(toProcess[pt]) end
end, function() tampilkanMenuEdit(); CatatPemakaianFreemium("edit_hilangkan_format", false) end)
end)
elseif action == T("nama_tanpa_format", "Nama Event Tanpa Format") or action == T("nama_dengan_format", "Nama Event Dengan Format") then
mainDialog.dismiss()
CekKuotaFreemium("edit_nama_event", function()
local withFormat = (action == T("nama_dengan_format", "Nama Event Dengan Format"))
jalankanDenganLoading(nil, function()
for pt=1, #toProcess do HelperNamaEventFormat(toProcess[pt], withFormat) end
end, function() tampilkanMenuEdit(); CatatPemakaianFreemium("edit_nama_event", false) end)
end)
elseif action == T("nama_kastem_tanpa_format", "Nama Kastem Tanpa Format") or action == T("nama_kastem_dengan_format", "Nama Kastem Dengan Format") then
mainDialog.dismiss()
local withFormat = (action == T("nama_kastem_dengan_format", "Nama Kastem Dengan Format"))
CekKuotaFreemium("edit_nama_kastem", function()
Kastem.mulai(toProcess, withFormat, function(plan)
jalankanDenganLoading(nil, function()
for pt=1, #toProcess do Kastem.terapkan(toProcess[pt], withFormat, plan) end
end, function() tampilkanMenuEdit(); CatatPemakaianFreemium("edit_nama_kastem", false) end)
end, function() tampilkanMenuEdit() end)
end)
elseif action == T("hapus_tak_terdaftar", "Hapus Audio Tak Terdaftar") then
CekKuotaFreemium("edit_hapus_tak_terdaftar", function()
jalankanDenganLoading(nil, function()
local allTrash = {}
for pt=1, #toProcess do
local selectedTheme = toProcess[pt]
local targetFolder = File(basePath .. "/" .. selectedTheme)
local configPath = basePath .. "/" .. selectedTheme .. "/config"
local themeDataObj = bacaJson(configPath)
local usedFiles = {}
for k, v in pairs(themeDataObj) do
if type(v) == "string" and v ~= "value_default" and v ~= "value_none" and v ~= "" then usedFiles[string.lower(v)] = true end
end
local files = targetFolder.listFiles()
if files then
for i = 0, #files - 1 do
local f = files[i]
if isAudioFile(f) then
if not usedFiles[string.lower(f.getName())] then table.insert(allTrash, f.getAbsolutePath()) end
end
end
end
end
return allTrash
end, function(allTrash)
if allTrash and #allTrash > 0 then
mainDialog.dismiss()
showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("hapus", "Hapus") .. " " .. #allTrash .. " audio?", function()
jalankanTaskLoading(nil, kerjaHapusPath, cjson.encode(allTrash), function()
tampilkanMenuEdit()
CatatPemakaianFreemium("edit_hapus_tak_terdaftar", false)
end)
end, function() tampilkanMenuEdit() end)
end
end)
end)
end
end)
optDialog.show()
end

btnHapusTerpilihEdit.onClick = function()
local toDelete = {}
for k, v in pairs(selectedThemes) do table.insert(toDelete, k) end
if #toDelete == 0 then return end
showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("hapus", "Hapus") .. " " .. #toDelete .. " tema?", function()
local daftarHapus = {}
for i=1, #toDelete do
table.insert(daftarHapus, basePath .. "/" .. toDelete[i])
table.insert(daftarHapus, backupPath .. "/" .. toDelete[i])
end
jalankanTaskLoading(nil, kerjaHapusPath, cjson.encode(daftarHapus), function()
isSelectionModeEdit = false
mainDialog.setTitle(T("edit_tema", "Edit Tema Suara"))
layoutSearchEdit.setVisibility(0)
btnModePemilihanEdit.setText(T("mode_pilih", "Aktifkan Mode Pemilihan"))
btnPilihSemuaEdit.setVisibility(8)
layoutAksiEdit.setVisibility(8)
selectedThemes = {}
isAllSelectedEdit = false
btnPilihSemuaEdit.setText(T("pilih_semua", "Pilih Semua"))
refreshData(tostring(searchBarEdit.getText()))
end)
end)
end

searchBarEdit.addTextChangedListener(TextWatcher{ onTextChanged = function(c, start, before, count) refreshData(tostring(c)) end })

btnBuatEdit.onClick = function(v)
showInputDialog(T("buat_tema", "Buat Tema Baru"), nil, nil, function(newName)
if newName ~= "" then
local newFolder = File(basePath .. "/" .. newName)
if newFolder.exists() then
service.speak(T("nama_telah_digunakan", "Nama tersebut sudah digunakan, silakan pilih nama lain."))
return false
else
newFolder.mkdirs()
File(newFolder.getAbsolutePath() .. "/config").createNewFile()
uiHandler.post(Runnable({ run = function() refreshData(tostring(searchBarEdit.getText())) end }))
return true
end
end
return true
end)
end

closeBtnEdit.onClick = function(v) mainDialog.dismiss(); muatUlangBahasaDanMenu() end

themeListView.onItemClick = function(l, v, p, id)
local item = themeData[p+1]
local selectedTheme = item.realName or item.tvName
if isSelectionModeEdit then
if selectedThemes[selectedTheme] then
selectedThemes[selectedTheme] = nil
item.cbItem.checked = false
else
selectedThemes[selectedTheme] = true
item.cbItem.checked = true
end
adapterEdit.notifyDataSetChanged()
local allSelected = true
for i=1, #filteredList do
if not selectedThemes[filteredList[i]] then allSelected = false break end
end
isAllSelectedEdit = allSelected
btnPilihSemuaEdit.setText(isAllSelectedEdit and T("batal_pilih_semua", "Batal Pilih Semua") or T("pilih_semua", "Pilih Semua"))
updateAksiEdit()
else
mainDialog.dismiss()
showEventList(selectedTheme)
end
end

themeListView.onItemLongClick = function(l, v, p, id)
if isSelectionModeEdit then return true end
local selectedTheme = themeData[p+1].realName or themeData[p+1].tvName
local cadF = File(backupPath .. "/" .. selectedTheme)
local statusCad
local ck = cacheCadangan[selectedTheme]
if AksiDex.tangkap and ck and (os.time() - ck.t) < 10 then
-- dipanggil menu Aksi pembaca layar: pakai hasil beberapa detik lalu
statusCad = ck.v
else
statusCad = cekStatusCadangan(selectedTheme)
cacheCadangan[selectedTheme] = { v = statusCad, t = os.time() }
end

local txtSemat = isInList("pinned_themes", selectedTheme) and T("lepas_sematan", "Lepas Sematan") or T("sematkan", "Sematkan")
local txtFav = isInList("favorite_themes", selectedTheme) and T("hapus_favorit", "Hapus dari Favorit") or T("tambah_favorit", "Tambahkan ke Favorit")

local options = {T("ganti_nama", "Ganti Nama"), T("hapus", "Hapus"), txtSemat, txtFav}
if statusCad == 0 then table.insert(options, T("cadangkan", "Cadangkan"))
elseif statusCad == 1 then table.insert(options, T("hapus_cadangan", "Hapus dari Cadangan"))
elseif statusCad == 2 then
table.insert(options, T("cadangkan_ulang", "Cadangkan Ulang"))
table.insert(options, T("hapus_cadangan", "Hapus dari Cadangan"))
end
table.insert(options, T("bagikan", "Bagikan"))
table.insert(options, T("cadangkan_spk", "Cadangkan Jadi SPK"))
table.insert(options, T("hilangkan_format", "Hilangkan Format Audio"))
table.insert(options, T("nama_tanpa_format", "Nama Event Tanpa Format"))
table.insert(options, T("nama_dengan_format", "Nama Event Dengan Format"))
table.insert(options, T("hapus_tak_terdaftar", "Hapus Audio Tak Terdaftar"))
table.insert(options, T("nama_kastem_tanpa_format", "Nama Kastem Tanpa Format"))
table.insert(options, T("nama_kastem_dengan_format", "Nama Kastem Dengan Format"))
table.insert(options, T("tutup", "Tutup"))
local optDialog = UI_Dialog(selectedTheme)
optDialog.setItems(options)
optDialog.setOnItemClickListener(function(al, av, ap, ai)
local action = options[ap + 1]

-- Gerbang premium telah dipindahkan ke sistem Kuota Gaib

optDialog.dismiss()
local targetFolder = File(basePath .. "/" .. selectedTheme)

if action == T("ganti_nama", "Ganti Nama") then
showInputDialog(T("ganti_nama", "Ganti Nama"), nil, selectedTheme, function(newName)
if newName ~= "" and newName ~= selectedTheme then
local cekDir = File(basePath .. "/" .. newName)
if cekDir.exists() then
service.speak(T("nama_telah_digunakan", "Nama tersebut sudah digunakan, silakan pilih nama lain."))
return false
else
local daftarRename = { { src = targetFolder.getAbsolutePath(), dst = cekDir.getAbsolutePath() } }
if cadF.exists() then table.insert(daftarRename, { src = cadF.getAbsolutePath(), dst = backupPath .. "/" .. newName }) end
jalankanTaskLoading(nil, kerjaRenamePath, cjson.encode(daftarRename), function()
updateNameInPref("pinned_themes", selectedTheme, newName)
updateNameInPref("favorite_themes", selectedTheme, newName)
refreshData(tostring(searchBarEdit.getText()))
end)
return true
end
end
return true
end)
elseif action == T("cadangkan", "Cadangkan") or action == T("cadangkan_ulang", "Cadangkan Ulang") then
jalankanTaskLoading(nil, kerjaSalinFlat, cjson.encode({ { src = targetFolder.getAbsolutePath(), dst = cadF.getAbsolutePath(), hapusDulu = true } }), function() end)
elseif action == T("hapus_cadangan", "Hapus dari Cadangan") then
jalankanTaskLoading(nil, kerjaHapusPath, cjson.encode({ cadF.getAbsolutePath() }), function() end)
elseif action == txtSemat then
toggleListPref("pinned_themes", selectedTheme)
refreshData(tostring(searchBarEdit.getText()))
elseif action == txtFav then
toggleListPref("favorite_themes", selectedTheme)
refreshData(tostring(searchBarEdit.getText()))
elseif action == T("hapus", "Hapus") then
showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("hapus", "Hapus") .. " " .. selectedTheme .. "?", function()
jalankanTaskLoading(nil, kerjaHapusPath, cjson.encode({ targetFolder.getAbsolutePath(), cadF.getAbsolutePath() }), function()
refreshData(tostring(searchBarEdit.getText()))
end)
end)
elseif action == T("bagikan", "Bagikan") then
mainDialog.dismiss()
local suffixExt = ""
local adaClock = File(targetFolder.getAbsolutePath() .. "/clock").exists()
local adaEfek = File(targetFolder.getAbsolutePath() .. "/effect").exists()
if adaClock and adaEfek then suffixExt = "_clock_effect"
elseif adaClock then suffixExt = "_clock"
elseif adaEfek then suffixExt = "_effect" end

local middleFmt = ""
if PreferenceManager.getDefaultSharedPreferences(service).getBoolean("use_jieshuo_export_format", false) then
middleFmt = "_" .. os.date("%Y%m%d%H%M%S")
end

local zipFilePath = jieshuoPath .. "/" .. selectedTheme .. middleFmt .. suffixExt .. ".spk"
jalankanZipTask(nil, {{src = targetFolder.getAbsolutePath(), out = zipFilePath}}, function(hasil)
if hasil and #hasil > 0 then pcall(function() bagikanBanyakFile(hasil) end) end
end)
elseif action == T("cadangkan_spk", "Cadangkan Jadi SPK") then
mainDialog.dismiss()
local spkDir = File("/storage/emulated/0/nadi cadangan SPK")
if not spkDir.exists() then spkDir.mkdirs() end
local suffixExt = ""
local adaClock = File(targetFolder.getAbsolutePath() .. "/clock").exists()
local adaEfek = File(targetFolder.getAbsolutePath() .. "/effect").exists()
if adaClock and adaEfek then suffixExt = "_clock_effect"
elseif adaClock then suffixExt = "_clock"
elseif adaEfek then suffixExt = "_effect" end
local middleFmt = ""
if PreferenceManager.getDefaultSharedPreferences(service).getBoolean("use_jieshuo_export_format", false) then
middleFmt = "_" .. os.date("%Y%m%d%H%M%S")
end
local baseSpkName = selectedTheme .. middleFmt .. suffixExt .. ".spk"
local finalSpkName = baseSpkName
if middleFmt == "" then finalSpkName = DapatkanNamaUnik(spkDir.getAbsolutePath(), baseSpkName) end
local zipFilePath = spkDir.getAbsolutePath() .. "/" .. finalSpkName
jalankanZipTask(T("sedang_memproses", "Sedang memproses..."), {{src = targetFolder.getAbsolutePath(), out = zipFilePath}}, function()
service.speak("Berhasil dicadangkan ke " .. finalSpkName)
tampilkanMenuEdit()
end)
elseif action == T("hilangkan_format", "Hilangkan Format Audio") then
mainDialog.dismiss()
CekKuotaFreemium("edit_hilangkan_format", function()
jalankanDenganLoading(nil, function()
HelperHilangkanFormat(selectedTheme)
end, function() showEventList(selectedTheme); CatatPemakaianFreemium("edit_hilangkan_format", false) end)
end)
elseif action == T("nama_tanpa_format", "Nama Event Tanpa Format") or action == T("nama_dengan_format", "Nama Event Dengan Format") then
mainDialog.dismiss()
CekKuotaFreemium("edit_nama_event", function()
local withFormat = (action == T("nama_dengan_format", "Nama Event Dengan Format"))
jalankanDenganLoading(nil, function()
HelperNamaEventFormat(selectedTheme, withFormat)
end, function() showEventList(selectedTheme); CatatPemakaianFreemium("edit_nama_event", false) end)
end)
elseif action == T("nama_kastem_tanpa_format", "Nama Kastem Tanpa Format") or action == T("nama_kastem_dengan_format", "Nama Kastem Dengan Format") then
mainDialog.dismiss()
local withFormat = (action == T("nama_kastem_dengan_format", "Nama Kastem Dengan Format"))
CekKuotaFreemium("edit_nama_kastem", function()
Kastem.mulai({selectedTheme}, withFormat, function(plan)
jalankanDenganLoading(nil, function()
Kastem.terapkan(selectedTheme, withFormat, plan)
end, function() showEventList(selectedTheme); CatatPemakaianFreemium("edit_nama_kastem", false) end)
end, function() showEventList(selectedTheme) end)
end)
elseif action == T("hapus_tak_terdaftar", "Hapus Audio Tak Terdaftar") then
CekKuotaFreemium("edit_hapus_tak_terdaftar", function()
jalankanDenganLoading(nil, function()
local configPath = basePath .. "/" .. selectedTheme .. "/config"
local themeDataObj = bacaJson(configPath)
local usedFiles = {}
for k, v in pairs(themeDataObj) do
if type(v) == "string" and v ~= "value_default" and v ~= "value_none" and v ~= "" then usedFiles[string.lower(v)] = true end
end
local files = targetFolder.listFiles()
local trashFiles = {}
if files then
for i = 0, #files - 1 do
local f = files[i]
if isAudioFile(f) then
if not usedFiles[string.lower(f.getName())] then table.insert(trashFiles, f.getAbsolutePath()) end
end
end
end
return trashFiles
end, function(trashFiles)
if trashFiles and #trashFiles > 0 then
showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("hapus", "Hapus") .. " " .. #trashFiles .. " audio?", function()
jalankanTaskLoading(nil, kerjaHapusPath, cjson.encode(trashFiles), function() CatatPemakaianFreemium("edit_hapus_tak_terdaftar", false) end)
end)
end
end)
end)
end
end)
optDialog.show()
return true
end

AksiDex.pasang(themeListView, {
labelKlik = T("aksi_buka_tema_suara", "Buka tema suara"),
modePilih = function() return isSelectionModeEdit end
})

btnDaftarFavorit.onClick = function()
local favList = getListPref("favorite_themes")
if #favList == 0 then
service.speak(T("favorit_kosong", "Daftar favorit masih kosong"))
return
end
local dFav = UI_Dialog(T("daftar_favorit", "Daftar Tema Favorit"))
dFav.setItems(favList)
dFav.setOnItemClickListener(function(l, v, p, id)
local namaTemaFav = favList[p+1]
dFav.dismiss()
service.loadSoundPackage(namaTemaFav)
service.speak(namaTemaFav .. " " .. T("status_aktif", "Aktif"))
end)
dFav.setOnItemLongClickListener(function(l, v, p, id)
local fakeList = {}
for i=1, #favList do table.insert(fakeList, {tvName = favList[i], realName = favList[i]}) end
local oldData = themeData
themeData = fakeList
themeListView.onItemLongClick(l, v, p, id)
themeData = oldData
dFav.dismiss()
return true
end)
dFav.show()
end

mainDialog.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
mainDialog.show()
end)
end

local function showHelperPanelKompresi(judul, teksSimpan, defFmt, defBr, onSimpan, onBatal)
local dKonv = UI_Dialog(judul)
local layKonv = UI_Layout(
UI_Teks(T("pilih_format", "Pilih Format:")), {Spinner, id="spFormat"},
UI_Teks(T("pilih_bitrate", "Pilih Bitrate:")), {Spinner, id="spBR"}
)
local scrollK = ScrollView(service)
scrollK.addView(loadlayout(layKonv))
dKonv.setView(scrollK)

local fData = ArrayList()
fData.add("M4A")
fData.add("OGG")
spFormat.setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_item, fData))
spFormat.setSelection(defFmt == "OGG" and 1 or 0)

local bData = ArrayList()
bData.add("32 kbps")
bData.add("64 kbps")
bData.add("128 kbps")
bData.add("192 kbps")
bData.add("256 kbps")
spBR.setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_item, bData))
if defBr == 32000 then spBR.setSelection(0) elseif defBr == 64000 then spBR.setSelection(1) elseif defBr == 128000 then spBR.setSelection(2) elseif defBr == 192000 then spBR.setSelection(3) elseif defBr == 256000 then spBR.setSelection(4) else spBR.setSelection(2) end

dKonv.setButton(teksSimpan, function()
local fSel = tostring(spFormat.getSelectedItem())
local bSelStr = tostring(spBR.getSelectedItem())
local brTarget = 128000
if bSelStr == "32 kbps" then brTarget = 32000 elseif bSelStr == "64 kbps" then brTarget = 64000 elseif bSelStr == "128 kbps" then brTarget = 128000 elseif bSelStr == "192 kbps" then brTarget = 192000 elseif bSelStr == "256 kbps" then brTarget = 256000 end
local srTarget = 0
onSimpan(fSel, srTarget, brTarget)
end)
dKonv.setButton2(T("batal", "Batal"), function() if onBatal then onBatal() end end)
dKonv.setOnCancelListener(function() if onBatal then onBatal() end end)
dKonv.setCancelable(false)
dKonv.show()
end

local function showHelperPanelAudio(judul, teksSimpan, defMic, defSr, defBr, defCh, onSimpan, onBatal)
local dSetMic = UI_Dialog(judul)
local layMic = UI_Layout(
UI_Teks(T("jenis_mikrofon", "Jenis Mikrofon:")), {Spinner, id="spMic"},
UI_Teks(T("pilih_sample_rate", "Pilih Sample Rate:")), {Spinner, id="spSR"},
UI_Teks(T("pilih_bitrate", "Pilih Bitrate:")), {Spinner, id="spBR"},
UI_Teks(T("pilih_channel", "Pilih Channel (Saluran):")), {Spinner, id="spCh"}
)
local scrollM = ScrollView(service)
scrollM.addView(loadlayout(layMic))
dSetMic.setView(scrollM)

local micData = ArrayList()
micData.add(T("mic_default", "Bawaan (Default)"))
micData.add(T("mic_utama", "Mikrofon Utama"))
micData.add(T("mic_komunikasi", "Komunikasi Suara (Anti-Bising)"))
micData.add(T("mic_kamera", "Mikrofon Kamera"))
micData.add(T("mic_pengenalan", "Pengenalan Suara"))
micData.add(T("mic_mentah", "Mentah (Unprocessed)"))
spMic.setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_item, micData))
if defMic == 0 then spMic.setSelection(0) elseif defMic == 1 then spMic.setSelection(1) elseif defMic == 7 then spMic.setSelection(2) elseif defMic == 5 then spMic.setSelection(3) elseif defMic == 6 then spMic.setSelection(4) elseif defMic == 9 then spMic.setSelection(5) else spMic.setSelection(1) end

local sData = ArrayList()
sData.add("8000 Hz")
sData.add("16000 Hz")
sData.add("22050 Hz")
sData.add("44100 Hz")
sData.add("48000 Hz")
spSR.setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_item, sData))
if defSr == 8000 then spSR.setSelection(0) elseif defSr == 16000 then spSR.setSelection(1) elseif defSr == 22050 then spSR.setSelection(2) elseif defSr == 48000 then spSR.setSelection(4) else spSR.setSelection(3) end

local bData = ArrayList()
bData.add("32 kbps")
bData.add("64 kbps")
bData.add("96 kbps")
bData.add("128 kbps")
bData.add("192 kbps")
bData.add("256 kbps")
spBR.setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_item, bData))
if defBr == 32000 then spBR.setSelection(0) elseif defBr == 64000 then spBR.setSelection(1) elseif defBr == 96000 then spBR.setSelection(2) elseif defBr == 192000 then spBR.setSelection(4) elseif defBr == 256000 then spBR.setSelection(5) else spBR.setSelection(3) end

local chData = ArrayList()
chData.add(T("ch_mono", "Mono (1 Saluran)"))
chData.add(T("ch_stereo", "Stereo (2 Saluran)"))
spCh.setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_item, chData))
spCh.setSelection(defCh == 2 and 1 or 0)

dSetMic.setButton(teksSimpan, function()
local selMic = 1
local mStr = tostring(spMic.getSelectedItem())
if mStr == T("mic_default", "Bawaan (Default)") then selMic = 0 elseif mStr == T("mic_utama", "Mikrofon Utama") then selMic = 1 elseif mStr == T("mic_komunikasi", "Komunikasi Suara (Anti-Bising)") then selMic = 7 elseif mStr == T("mic_kamera", "Mikrofon Kamera") then selMic = 5 elseif mStr == T("mic_pengenalan", "Pengenalan Suara") then selMic = 6 elseif mStr == T("mic_mentah", "Mentah (Unprocessed)") then selMic = 9 end

local selSr = 44100
local sStr = tostring(spSR.getSelectedItem())
if sStr == "8000 Hz" then selSr = 8000 elseif sStr == "16000 Hz" then selSr = 16000 elseif sStr == "22050 Hz" then selSr = 22050 elseif sStr == "48000 Hz" then selSr = 48000 end

local selBr = 128000
local bStr = tostring(spBR.getSelectedItem())
if bStr == "32 kbps" then selBr = 32000 elseif bStr == "64 kbps" then selBr = 64000 elseif bStr == "96 kbps" then selBr = 96000 elseif bStr == "192 kbps" then selBr = 192000 elseif bStr == "256 kbps" then selBr = 256000 end

local selCh = 1
local cStr = tostring(spCh.getSelectedItem())
if cStr == T("ch_stereo", "Stereo (2 Saluran)") then selCh = 2 end

onSimpan(selMic, selSr, selBr, selCh)
end)
dSetMic.setButton2(T("batal", "Batal"), function() if onBatal then onBatal() end end)
dSetMic.setOnCancelListener(function() if onBatal then onBatal() end end)
dSetMic.show()
end

tampilkanMenuPengaturan = function()
local dialogPengaturan = UI_Dialog(T("pengaturan", "Pengaturan"))
local lvMenu = ListView(service)
local menuData = {}
local menuList = ArrayList()
local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, menuList)
lvMenu.setAdapter(adapter)

local ttsPkgs = {}
local ttsLabels = {}
pcall(function()
local onInit = luajava.createProxy("android.speech.tts.TextToSpeech$OnInitListener", {
onInit = function(status) end
})
local tts = TextToSpeech(service, onInit)
local engs = tts.getEngines()
if engs then
for i = 0, engs.size() - 1 do
local eng = engs.get(i)
table.insert(ttsPkgs, eng.name)
table.insert(ttsLabels, eng.label)
end
end
tts.shutdown()
end)

local function refreshList()
local prefs = PreferenceManager.getDefaultSharedPreferences(service)

local isSoundOn = prefs.getBoolean("use_sound", true)
local statusSuara = isSoundOn and T("status_aktif", "Aktif") or T("status_mati", "Mati")
local isAlarmOn = prefs.getBoolean("use_alarm", false)
local statusAlarm = isAlarmOn and T("status_aktif", "Aktif") or T("status_mati", "Mati")
local isKlip = prefs.getBoolean("use_jieshuo_clip", false)
local statusKlip = isKlip and T("status_aktif", "Aktif") or T("status_mati", "Mati")
local isExportFmt = prefs.getBoolean("use_jieshuo_export_format", false)
local statusExportFmt = isExportFmt and T("status_aktif", "Aktif") or T("status_mati", "Mati")

menuData = {}

-- Toggle volume aksesibilitas (pref sama persis dengan yang dipakai main.lua CSR)
local isAksVol = prefs.getBoolean("use_accessibility_volume", false)
local statusAksVol = isAksVol and T("status_aktif", "Aktif") or T("status_mati", "Mati")
table.insert(menuData, { id = "vol_aks", text = T("pengaturan_volume_aksesibilitas", "Aktifkan atau matikan volume aksesibilitas. Status saat ini: ") .. statusAksVol })

table.insert(menuData, { id = "suara", text = T("pengaturan_suara", "Aktifkan atau matikan tema suara. Status saat ini: ") .. statusSuara })
if isSoundOn then
table.insert(menuData, { id = "suara_set", text = T("menu_suara_set", "Pengaturan Volume dan Suara Tema") })
end

local isVibrateOn = prefs.getBoolean("vibrate", true)
local statusGetaran = isVibrateOn and T("status_aktif", "Aktif") or T("status_mati", "Mati")
local currentVibrateVal = prefs.getString("vibrate_intensity", "32")
local currentVibrateText = T("getar_kecil", "Kecil")

if currentVibrateVal == "12" then currentVibrateText = T("getar_paling_kecil", "Paling kecil")
elseif currentVibrateVal == "32" then currentVibrateText = T("getar_kecil", "Kecil")
elseif currentVibrateVal == "48" then currentVibrateText = T("getar_besar", "Besar")
elseif currentVibrateVal == "64" then currentVibrateText = T("getar_paling_besar", "Paling besar") end

table.insert(menuData, { id = "getaran", text = T("pengaturan_getaran", "Aktifkan atau matikan getaran. Status saat ini: ") .. statusGetaran })
if isVibrateOn then
table.insert(menuData, { id = "intensitas_getaran", text = T("intensitas_getaran", "Intensitas getaran saat ini: ") .. currentVibrateText })
end

table.insert(menuData, { id = "jam", text = T("status_jam_bicara", "Aktifkan atau matikan jam bicara. Status saat ini: ") .. statusAlarm })
if isAlarmOn then
table.insert(menuData, { id = "jam_set", text = T("menu_jam_set", "Pengaturan Jam Bicara") })
end

local isAutoComp = pref.getBoolean("auto_compress", false)
local statusAutoComp = isAutoComp and T("status_aktif", "Aktif") or T("status_mati", "Mati")
table.insert(menuData, { id = "autocomp", text = T("konversi_audio_otomatis", "Konversi Audio Otomatis: ") .. statusAutoComp })
if isAutoComp then
table.insert(menuData, { id = "autocompset_menu", text = T("menu_autocomp_set", "Pengaturan Konversi Audio") })
end

local isAutoRec = pref.getBoolean("auto_record_quality", false)
local statusAutoRec = isAutoRec and T("status_aktif", "Aktif") or T("status_mati", "Mati")
table.insert(menuData, { id = "auto_rekam", text = T("kualitas_rekaman_otomatis", "Kualitas Rekaman Otomatis: ") .. statusAutoRec })
if isAutoRec then
table.insert(menuData, { id = "auto_rekam_menu", text = T("menu_autorekam_set", "Pengaturan Kualitas Rekaman") })
end

table.insert(menuData, { id = "jam_dapur", text = T("pengaturan_jam_dapur", "Pengaturan Pembuatan Jam Bicara") })
table.insert(menuData, { id = "folder", text = T("pengaturan_folder", "Pengaturan Folder") })
table.insert(menuData, { id = "event", text = T("pengaturan_event", "Pengaturan Nama Event") })
table.insert(menuData, { id = "tambah", text = T("tambah_event", "Tambah Event Suara Baru") })
table.insert(menuData, { id = "klip", text = T("pengaturan_klip", "Gunakan Papan Klip Jieshuo: ") .. statusKlip })
table.insert(menuData, { id = "ekspor_fmt", text = T("pengaturan_format_ekspor", "Gunakan Angka Jieshuo Saat Ekspor: ") .. statusExportFmt })
table.insert(menuData, { id = "komunitas_csr", text = T("csr_pengaturan_menu", "Pengaturan Komunitas Tema Suara CSR") })
table.insert(menuData, { id = "salin_user_csr", text = T("salin_nama_pengguna_csr", "Salin Nama Pengguna") })
table.insert(menuData, { id = "salin_sandi_csr", text = T("salin_kata_sandi_csr", "Salin Kata Sandi") })
table.insert(menuData, { id = "reset_pengaturan", text = T("reset_pengaturan", "Reset Pengaturan Skrip (Bawaan Pabrik)") })

menuList.clear()

for i = 1, #menuData do
menuList.add(menuData[i].text)
end
adapter.notifyDataSetChanged()
end

refreshList()
dialogPengaturan.setView(lvMenu)

lvMenu.onItemClick = function(l, v, p, id)
local selectedId = menuData[p + 1].id
local prefs = PreferenceManager.getDefaultSharedPreferences(service)

if selectedId == "vol_aks" then
local statusBaru = not prefs.getBoolean("use_accessibility_volume", false)
prefs.edit().putBoolean("use_accessibility_volume", statusBaru).apply()
prefs.edit().putBoolean("accessibility_volume", statusBaru).apply()
pcall(function() service.reCreate() end) -- wajib, biar CSR baca ulang pref volume
if statusBaru then service.asyncSpeak(T("volume_aks_aktif", "Volume aksesibilitas diaktifkan")) else service.asyncSpeak(T("volume_aks_mati", "Volume aksesibilitas dinonaktifkan")) end
pcall(refreshList)
elseif selectedId == "suara" then
local isSoundOn = prefs.getBoolean("use_sound", true)
local statusBaru = not isSoundOn
prefs.edit().putBoolean("use_sound", statusBaru).apply()
pcall(function() service.setSound(statusBaru) end)
if statusBaru then service.asyncSpeak(T("ucapan_aktif", "Saat ini aktif")) else service.asyncSpeak(T("ucapan_mati", "Saat ini mati")) end
refreshList()
elseif selectedId == "getaran" then
local isVibrateOn = prefs.getBoolean("vibrate", true)
local statusBaru = not isVibrateOn
prefs.edit().putBoolean("vibrate", statusBaru).apply()
pcall(function() service.setVibrate(statusBaru) end)
if statusBaru then service.asyncSpeak(T("ucapan_aktif", "Saat ini aktif")) else service.asyncSpeak(T("ucapan_mati", "Saat ini mati")) end
refreshList()
elseif selectedId == "intensitas_getaran" then
dialogPengaturan.dismiss()
tampilkanPemilihIntensitas()

elseif selectedId == "suara_set" then
dialogPengaturan.dismiss()

-- Bungkus dialog dalam sebuah fungsi lokal agar bisa dipanggil ulang
local function bukaMenuSuaraSet()
local dSuaraSet = UI_Dialog(T("menu_suara_set", "Pengaturan Volume dan Suara Tema"))
local lvSSet = ListView(service)
local sSetData = ArrayList()
local currentVol = prefs.getString("sound_volume", "100")
local currentTheme = prefs.getString("sound_package", "")
if currentTheme == "" then currentTheme = T("standar", "Standar") end
sSetData.add(T("volume_saat_ini", "Volume saat ini: ") .. currentVol .. "%")
sSetData.add(T("tema_saat_ini", "Tema suara saat ini: ") .. currentTheme)
lvSSet.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, sSetData))
dSuaraSet.setView(lvSSet)
lvSSet.onItemClick = function(l, v, p, id)
dSuaraSet.dismiss()
-- Kirim fungsi ini ke picker agar mereka bisa kembali ke sini
if p == 0 then tampilkanPemilihVolume(bukaMenuSuaraSet) else tampilkanPemilihTemaSuara(bukaMenuSuaraSet) end
end
dSuaraSet.setButton(T("tutup", "Tutup"), function() dSuaraSet.dismiss(); tampilkanMenuPengaturan() end)
dSuaraSet.setOnCancelListener(function() tampilkanMenuPengaturan() end)
dSuaraSet.show()
end
bukaMenuSuaraSet()

elseif selectedId == "jam" then
local isAlarmOn = prefs.getBoolean("use_alarm", false)
local newAlarmStatus = not isAlarmOn
prefs.edit().putBoolean("use_alarm", newAlarmStatus).apply()
pcall(function() service.setUseAlarm(newAlarmStatus) end)
if newAlarmStatus then service.asyncSpeak(T("ucapan_aktif", "Saat ini aktif")) else service.asyncSpeak(T("ucapan_mati", "Saat ini mati")) end
refreshList()

elseif selectedId == "jam_set" then
dialogPengaturan.dismiss()

local function bukaMenuJamSet()
local dJamSet = UI_Dialog(T("menu_jam_set", "Pengaturan Jam Bicara"))
local lvJSet = ListView(service)
local jSetList = ArrayList()
local jSetIds = {}

local currentInterval = prefs.getString("alarm_interval", "15")
local selectedHours = getAlarmHours()
local textWaktu = ""
if #selectedHours == 0 then textWaktu = T("tidak_ada", "Tidak ada")
elseif #selectedHours == 24 then textWaktu = T("semua_waktu", "Semua waktu (24 Jam)")
else table.sort(selectedHours); textWaktu = table.concat(selectedHours, ", ") end

jSetList.add(T("interval_jam", "Interval Jam Bicara: ") .. currentInterval .. " " .. T("menit", "Menit"))
table.insert(jSetIds, "interval")
jSetList.add(T("waktu_berbunyi", "Berbunyi pada waktu: ") .. textWaktu)
table.insert(jSetIds, "waktu")

local currEnginePkg = prefs.getString("timer_tts_engine", "")
local currEngineLabel = currEnginePkg
for i = 1, #ttsPkgs do if ttsPkgs[i] == currEnginePkg then currEngineLabel = ttsLabels[i]; break end end
if currEngineLabel == "" then currEngineLabel = T("tts_bawaan", "Bawaan sistem") end

jSetList.add(T("set_tts_engine", "Mesin TTS: ") .. currEngineLabel)
table.insert(jSetIds, "tts_engine")
jSetList.add(T("set_tts_scale", "Kecepatan teks ke suara: ") .. prefs.getString("timer_tts_scale", "1"))
table.insert(jSetIds, "tts_scale")
jSetList.add(T("set_tts_speed", "Kecepatan teks ke ucapan: ") .. prefs.getString("timer_tts_speed", "50"))
table.insert(jSetIds, "tts_speed")
jSetList.add(T("set_tts_volume", "Volume teks ke ucapan: ") .. prefs.getString("timer_tts_volume", "150"))
table.insert(jSetIds, "tts_volume")
jSetList.add(T("set_tts_pitch", "Nada teks ke ucapan: ") .. prefs.getString("timer_tts_pitch", "50"))
table.insert(jSetIds, "tts_pitch")

lvJSet.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, jSetList))
dJamSet.setView(lvJSet)

lvJSet.onItemClick = function(l, v, p, id)
local sId = jSetIds[p + 1]
dJamSet.dismiss()

if sId == "interval" then
local dInterval = UI_Dialog(T("interval_jam", "Interval Jam Bicara"))
local lvInterval = ListView(service)
local intervals = ArrayList()
local opsiInt = {"5", "10", "15", "30", "60"}
for i = 1, #opsiInt do intervals.add(opsiInt[i]) end
lvInterval.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, intervals))
dInterval.setView(lvInterval)
lvInterval.onItemClick = function(l2, v2, p2, id2)
prefs.edit().putString("alarm_interval", tostring(intervals.get(p2))).apply()
pcall(function() service.reCreate() end)
dInterval.dismiss()
bukaMenuJamSet()
end
dInterval.setButton(T("tutup", "Tutup"), function() dInterval.dismiss(); bukaMenuJamSet() end)
dInterval.setOnCancelListener(function() bukaMenuJamSet() end)
dInterval.show()

elseif sId == "waktu" then
local judulBersih = T("waktu_berbunyi", "Berbunyi pada waktu: "):gsub(": %s*$", "")
local dWaktu = UI_Dialog(judulBersih)
local layoutWaktu = UI_Layout(UI_Daftar("lvWaktu"))
dWaktu.setView(loadlayout(layoutWaktu))
local itemLayout = UI_ItemBaris("cbJam", "tvJam")
local hoursMap = {}
local currentH = getAlarmHours()
for _, h in ipairs(currentH) do hoursMap[tonumber(h)] = true end
local listData = {}
for i = 0, 23 do
local numStr = tostring(i)
if i < 10 then numStr = "0" .. numStr end
table.insert(listData, { cbJam = {checked = (hoursMap[i] == true)}, tvJam = T("teks_jam", "Jam ") .. numStr .. ":00", _jam = i })
end
local adapterWaktu = LuaAdapter(service, listData, itemLayout)
lvWaktu.setAdapter(adapterWaktu)
lvWaktu.onItemClick = function(lW, vW, pW, idW)
local item = listData[pW + 1]
item.cbJam.checked = not item.cbJam.checked
adapterWaktu.notifyDataSetChanged()
end
dWaktu.setButton(T("simpan", "Simpan"), function()
local newArr = {}
for i = 1, #listData do
if listData[i].cbJam.checked then table.insert(newArr, listData[i]._jam) end
end
setAlarmHours(newArr)
pcall(function() service.reCreate() end)
service.speak(T("simpan", "Simpan"))
dWaktu.dismiss()
bukaMenuJamSet()
end)
dWaktu.setButton2(T("batal", "Batal"), function() dWaktu.dismiss(); bukaMenuJamSet() end)
dWaktu.setOnCancelListener(function() bukaMenuJamSet() end)
dWaktu.show()

elseif sId == "tts_engine" then
local dE = UI_Dialog(T("set_tts_engine", "Mesin TTS") .. ":")
local lvE = ListView(service)
local arrE = ArrayList()
for i = 1, #ttsLabels do arrE.add(ttsLabels[i]) end
lvE.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, arrE))
dE.setView(lvE)
lvE.onItemClick = function(lE, vE, pE, idE)
prefs.edit().putString("timer_tts_engine", ttsPkgs[pE + 1]).apply()
pcall(function() service.reCreate() end)
service.asyncSpeak(T("simpan", "Simpan"))
dE.dismiss()
bukaMenuJamSet()
end
dE.setButton(T("batal", "Batal"), function() dE.dismiss(); bukaMenuJamSet() end)
dE.setOnCancelListener(function() bukaMenuJamSet() end)
dE.show()

elseif sId == "tts_scale" then
local dS = UI_Dialog(T("set_tts_scale", "Kecepatan teks ke suara") .. ":")
local lvS = ListView(service)
local arrS = ArrayList()
for i = 10, 100 do
local val = i / 10
if math.floor(val) == val then arrS.add(tostring(math.floor(val))) else arrS.add(tostring(val)) end
end
lvS.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, arrS))
dS.setView(lvS)
lvS.onItemClick = function(lS, vS, pS, idS)
prefs.edit().putString("timer_tts_scale", tostring(arrS.get(pS))).apply()
pcall(function() service.reCreate() end)
service.asyncSpeak(T("simpan", "Simpan"))
dS.dismiss()
bukaMenuJamSet()
end
dS.setButton(T("batal", "Batal"), function() dS.dismiss(); bukaMenuJamSet() end)
dS.setOnCancelListener(function() bukaMenuJamSet() end)
dS.show()

elseif sId == "tts_speed" then
local dSp = UI_Dialog(T("set_tts_speed", "Kecepatan teks ke ucapan") .. ":")
local lvSp = ListView(service)
local arrSp = ArrayList()
for i = 0, 100 do arrSp.add(tostring(i)) end
lvSp.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, arrSp))
dSp.setView(lvSp)
lvSp.onItemClick = function(lSp, vSp, pSp, idSp)
prefs.edit().putString("timer_tts_speed", tostring(arrSp.get(pSp))).apply()
pcall(function() service.reCreate() end)
service.asyncSpeak(T("simpan", "Simpan"))
dSp.dismiss()
bukaMenuJamSet()
end
dSp.setButton(T("batal", "Batal"), function() dSp.dismiss(); bukaMenuJamSet() end)
dSp.setOnCancelListener(function() bukaMenuJamSet() end)
dSp.show()

elseif sId == "tts_volume" then
local dV = UI_Dialog(T("set_tts_volume", "Volume teks ke ucapan") .. ":")
local lvV = ListView(service)
local arrV = ArrayList()
for i = 0, 100 do arrV.add(tostring(i)) end
for i = 110, 1000, 10 do arrV.add(tostring(i)) end
lvV.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, arrV))
dV.setView(lvV)
lvV.onItemClick = function(lV, vV, pV, idV)
prefs.edit().putString("timer_tts_volume", tostring(arrV.get(pV))).apply()
pcall(function() service.reCreate() end)
service.asyncSpeak(T("simpan", "Simpan"))
dV.dismiss()
bukaMenuJamSet()
end
dV.setButton(T("batal", "Batal"), function() dV.dismiss(); bukaMenuJamSet() end)
dV.setOnCancelListener(function() bukaMenuJamSet() end)
dV.show()

elseif sId == "tts_pitch" then
local dP = UI_Dialog(T("set_tts_pitch", "Nada teks ke ucapan") .. ":")
local lvP = ListView(service)
local arrP = ArrayList()
for i = 0, 100 do arrP.add(tostring(i)) end
lvP.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, arrP))
dP.setView(lvP)
lvP.onItemClick = function(lP, vP, pP, idP)
prefs.edit().putString("timer_tts_pitch", tostring(arrP.get(pP))).apply()
pcall(function() service.reCreate() end)
service.asyncSpeak(T("simpan", "Simpan"))
dP.dismiss()
bukaMenuJamSet()
end
dP.setButton(T("batal", "Batal"), function() dP.dismiss(); bukaMenuJamSet() end)
dP.setOnCancelListener(function() bukaMenuJamSet() end)
dP.show()
end
end
dJamSet.setButton(T("tutup", "Tutup"), function() dJamSet.dismiss(); tampilkanMenuPengaturan() end)
dJamSet.setOnCancelListener(function() tampilkanMenuPengaturan() end)
dJamSet.show()
end
bukaMenuJamSet()

elseif selectedId == "autocomp" then
local isAutoComp = pref.getBoolean("auto_compress", false)
local statusBaru = not isAutoComp
editor.putBoolean("auto_compress", statusBaru)
editor.commit()
if statusBaru then service.asyncSpeak(T("ucapan_aktif", "Saat ini aktif")) else service.asyncSpeak(T("ucapan_mati", "Saat ini mati")) end
refreshList()

elseif selectedId == "auto_rekam" then
local isAutoRec = pref.getBoolean("auto_record_quality", false)
local statusBaru = not isAutoRec
editor.putBoolean("auto_record_quality", statusBaru)
editor.commit()
if statusBaru then service.asyncSpeak(T("ucapan_aktif", "Saat ini aktif")) else service.asyncSpeak(T("ucapan_mati", "Saat ini mati")) end
refreshList()

elseif selectedId == "autocompset_menu" then
dialogPengaturan.dismiss()
local svFmt = pref.getString("auto_comp_format", "M4A")
local svBr = pref.getInt("auto_comp_br", 128000)
showHelperPanelKompresi(T("menu_autocomp_set", "Pengaturan Konversi Audio"), T("simpan", "Simpan"), svFmt, svBr, function(fSel, srTarget, brTarget)
editor.putString("auto_comp_format", fSel)
editor.putInt("auto_comp_br", brTarget)
editor.commit()
tampilkanMenuPengaturan()
end, function()
tampilkanMenuPengaturan()
end)

elseif selectedId == "auto_rekam_menu" then
dialogPengaturan.dismiss()
local svMic = pref.getInt("auto_rec_mic", 1)
local svSr = pref.getInt("auto_rec_sr", 44100)
local svBr = pref.getInt("auto_rec_br", 128000)
local svCh = pref.getInt("auto_rec_ch", 1)
showHelperPanelAudio(T("menu_autorekam_set", "Pengaturan Kualitas Rekaman"), T("simpan", "Simpan"), svMic, svSr, svBr, svCh, function(selMic, selSr, selBr, selCh)
editor.putInt("auto_rec_mic", selMic)
editor.putInt("auto_rec_sr", selSr)
editor.putInt("auto_rec_br", selBr)
editor.putInt("auto_rec_ch", selCh)
editor.commit()
tampilkanMenuPengaturan()
end, function()
tampilkanMenuPengaturan()
end)

elseif selectedId == "komunitas_csr" then
dialogPengaturan.dismiss()
CSRO.Pengaturan(function() tampilkanMenuPengaturan() end)

elseif selectedId == "salin_user_csr" then
local u = CSRO.akunCsr()
if u == "" then service.speak(T("akun_csr_kosong", "Belum ada akun CSR yang tersimpan."))
else
CSRO.salinAman("csr_user", u)
service.speak(T("csr_pengguna_tersalin", "Nama pengguna tersalin."))
end
elseif selectedId == "salin_sandi_csr" then
local _, p = CSRO.akunCsr()
if p == "" then service.speak(T("akun_csr_kosong", "Belum ada akun CSR yang tersimpan."))
else
CSRO.salinAman("csr_pass", p)
service.speak(T("csr_sandi_tersalin", "Kata sandi tersalin. Clipboard dibersihkan otomatis dalam 30 detik."))
end

elseif selectedId == "folder" then

dialogPengaturan.dismiss()
showInputDialog(T("pengaturan_folder", "Pengaturan Folder"), nil, dapatkanString("nama_folder_suara", "Suara"), function(txt)
simpanString("nama_folder_suara", txt)
tampilkanMenuPengaturan()
end, function() tampilkanMenuPengaturan() end)
elseif selectedId == "event" then
dialogPengaturan.dismiss()
local dEvent = UI_Dialog(T("pengaturan_event", "Pengaturan Nama Event"))
local lv = ListView(service)
local data = ArrayList()
for i=1, #mappingTema do data.add(mappingTema[i][1]) end
lv.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, data))
dEvent.setView(lv)
lv.onItemClick = function(l2, v2, p2, id2)
local defaultName = mappingTema[p2+1][1]
local key = "str_event_" .. mappingTema[p2+1][2]
showInputDialog(T("ganti_nama", "Ganti Nama"), nil, dapatkanString(key, defaultName), function(txt)
simpanString(key, txt)
end)
end
dEvent.setButton(T("tutup", "Tutup"), function() dEvent.dismiss(); tampilkanMenuPengaturan() end)
dEvent.setOnCancelListener(function() tampilkanMenuPengaturan() end)
dEvent.show()
elseif selectedId == "tambah" then
dialogPengaturan.dismiss()
local dTambah = UI_Dialog(T("tambah_event", "Tambah Event Suara Baru"))
local layoutTambah = UI_Layout(
UI_Input("etUiName", T("nama_tampilan_ui", "Nama Tampilan UI")),
UI_Input("etJsonKey", T("kode_json_jieshuo", "Kode JSON Jieshuo")),
UI_Tombol("btnPosisi", T("penempatan_default", "Penempatan (Default: Bawah)")),
{LinearLayout, orientation="horizontal", layout_width="fill",
UI_Tombol_H("btnBatalTambah", T("batal", "Batal")),
UI_Tombol_H("btnSimpanTambah", T("simpan", "Simpan"))
}
)
dTambah.setView(loadlayout(layoutTambah))

local targetIndex = -1
local positionType = "bawah"

btnPosisi.onClick = function()
local dPos = UI_Dialog(T("pilih_penempatan", "Pilih Penempatan"))
local lvPos = ListView(service)
local dataPos = ArrayList()
for i=1, #mappingTema do dataPos.add(mappingTema[i][1]) end
lvPos.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, dataPos))
dPos.setView(lvPos)
lvPos.onItemClick = function(l3, v3, p3, id3)
dPos.dismiss()
local dArah = UI_Dialog(T("di_sebelah_mana", "Di sebelah mana?"))
local lvArah = ListView(service)
lvArah.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, {T("kiri_sebelum", "Kiri (Sebelum ") .. mappingTema[p3+1][1] .. ")", T("kanan_sesudah", "Kanan (Sesudah ") .. mappingTema[p3+1][1] .. ")"}))
dArah.setView(lvArah)
lvArah.onItemClick = function(l4, v4, p4, id4)
dArah.dismiss()
targetIndex = p3 + 1
positionType = (p4 == 0) and "kiri" or "kanan"
btnPosisi.setText((p4 == 0) and (T("sebelum", "Sebelum: ") .. mappingTema[targetIndex][1]) or (T("sesudah", "Sesudah: ") .. mappingTema[targetIndex][1]))
end
dArah.show()
end
dPos.setButton(T("paling_bawah", "Paling Bawah"), function() targetIndex = -1 positionType = "bawah" btnPosisi.setText(T("paling_bawah", "Paling Bawah")) end)
dPos.show()
end

btnSimpanTambah.onClick = function()
local uiName = tostring(etUiName.getText()):match("^%s*(.-)%s*$") or ""
local jsonKey = tostring(etJsonKey.getText()):match("^%s*(.-)%s*$") or ""
if uiName == "" or jsonKey == "" then
service.speak(T("tidak_boleh_kosong", "Kotak teks tidak boleh kosong!"))
return
end
if uiName:match('[/\\:*?"<>|]') or jsonKey:match('[/\\:*?"<>|]') then
service.speak(T("karakter_terlarang", "Nama tidak boleh mengandung karakter khusus seperti garis miring, titik dua, atau bintang."))
return
end
local newItem = {uiName, jsonKey}
if targetIndex == -1 then
table.insert(mappingTema, newItem)
else
if positionType == "kiri" then table.insert(mappingTema, targetIndex, newItem)
else table.insert(mappingTema, targetIndex + 1, newItem) end
end
simpanDataEvent()
dTambah.dismiss()
tampilkanMenuPengaturan()
end
btnBatalTambah.onClick = function() dTambah.dismiss(); tampilkanMenuPengaturan() end
dTambah.setOnCancelListener(function() tampilkanMenuPengaturan() end)
dTambah.show()

-- ==========================================
-- TAMBAHAN: Handler untuk Jam Dapur & Sakelar
-- ==========================================
elseif selectedId == "jam_dapur" then
dialogPengaturan.dismiss()
local dDapur = UI_Dialog(T("pengaturan_jam_dapur", "Pengaturan Pembuatan Jam Bicara"))
local lvDapur = ListView(service)
local optDapur = {
T("dapur_tts", "Pengaturan Suara TTS"),
T("dapur_24", "Format Teks 24 Jam"),
T("dapur_12", "Format Teks 12 Jam"),
T("dapur_menit", "Format Teks Menit"),
T("efekjam_menu", "Pengaturan Efek Suara"),
T("sisip_menu", "Pengaturan Audio Sisipan"),
T("prog_umum_menu", "Pengumuman Progres Pembuatan Jam")
}
lvDapur.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, optDapur))
dDapur.setView(lvDapur)

lvDapur.onItemClick = function(lD, vD, pD, idD)
if pD == 0 then
local function keList(tabel)
local arr = ArrayList()
for i=1, #tabel do arr.add(tabel[i]) end
return arr
end

local laySet = UI_Layout(
UI_Teks(T("dapur_tts_mesin", "Pilih Mesin TTS:")),
{Spinner, id="spMesin"},
UI_Teks(T("dapur_tts_bahasa", "Pilih Bahasa:")),
{Spinner, id="spBhs"},
UI_Teks(T("dapur_tts_suara", "Pilih Suara:")),
{Spinner, id="spSua"},
UI_Teks(T("nada_pitch", "Nada (Pitch):")),
{SeekBar, id="skP", max=20},
UI_Teks(T("kecepatan_rate", "Kecepatan (Rate):")),
{SeekBar, id="skR", max=20},
UI_Tombol("btnTest", T("tes_suara", "Tes Suara"))
)

local scrollLay = ScrollView(service)
scrollLay.addView(loadlayout(laySet))

local dTTS = UI_Dialog(T("dapur_tts", "Pengaturan Suara TTS"))
dTTS.setView(scrollLay)

local ttsTmp = TextToSpeech(service, nil)
local engs = ttsTmp.getEngines()
local pkgs, labels = {}, {}
if engs then
for i=0, engs.size()-1 do
table.insert(pkgs, engs.get(i).name)
table.insert(labels, engs.get(i).label)
end
end
ttsTmp.shutdown()

spMesin.setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_item, keList(labels)))
local svM = pref.getString("tts_engine", "")
local foundEng = false
for i, p in ipairs(pkgs) do if p == svM then spMesin.setSelection(i - 1); foundEng = true; break end end
if not foundEng and #pkgs > 0 then svM = pkgs[1] end

local tempTts = nil
local bahasaNames, bahasaLocales = {}, {}
local suaraNames, suaraObjs = {}, {}

local function perbaruiSuara(selLoc)
suaraNames = {}; suaraObjs = {}
if tempTts and selLoc then
local vl = tempTts.getVoices()
if vl then
local it = vl.iterator()
while it.hasNext() do
local vc = it.next()
if vc.getLocale().equals(selLoc) then
table.insert(suaraNames, vc.getName() .. (vc.isNetworkConnectionRequired() and T("online", " [Online]") or T("offline", " [Offline]")))
table.insert(suaraObjs, vc)
end
end
end
end
spSua.setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_item, keList(suaraNames)))
local sVoice = pref.getString("tts_voice", "")
for i, vObj in ipairs(suaraObjs) do
if vObj.getName() == sVoice then spSua.setSelection(i - 1); break end
end
end

local function perbaruiBahasa()
bahasaNames = {}; bahasaLocales = {}
local unik, temp = {}, {}
if tempTts then
local vl = tempTts.getVoices()
if vl then
local it = vl.iterator()
while it.hasNext() do
local vc = it.next()
local loc = vc.getLocale()
if loc then
local n = loc.getDisplayName()
if n ~= "" and not unik[n] then
table.insert(temp, {n=n, l=loc})
unik[n] = true
end
end
end
end
end
table.sort(temp, function(a, b) return a.n:lower() < b.n:lower() end)
for _, v in ipairs(temp) do table.insert(bahasaNames, v.n); table.insert(bahasaLocales, v.l) end
spBhs.setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_item, keList(bahasaNames)))
local sBhs = pref.getString("tts_lang", "")
local fnd = false
for i, v in ipairs(bahasaNames) do if v == sBhs then spBhs.setSelection(i - 1); fnd = true; break end end
if not fnd and #bahasaNames > 0 then spBhs.setSelection(0) end
end

local function initTempTts(pkg)
if tempTts then pcall(function() tempTts.shutdown() end); tempTts = nil end
local onInit = luajava.createProxy("android.speech.tts.TextToSpeech$OnInitListener", {
onInit = function(status)
if status == TextToSpeech.SUCCESS then
uiHandler.post(Runnable({run = function() perbaruiBahasa() end}))
end
end
})
tempTts = (pkg and pkg ~= "") and TextToSpeech(service, onInit, pkg) or TextToSpeech(service, onInit)
end

initTempTts(svM)

spMesin.onItemSelected = function(l, v, p, id)
local sp = pkgs[p+1]
if sp ~= svM then svM = sp; initTempTts(sp) end
end

spBhs.onItemSelected = function(l, v, p, id)
if #bahasaLocales > 0 then perbaruiSuara(bahasaLocales[p+1]) end
end

skP.setProgress(pref.getFloat("tts_pitch", 1.0) * 10)
skR.setProgress(pref.getFloat("tts_rate", 1.0) * 10)

btnTest.onClick = function()
if tempTts then
local selSuaIdx = spSua.getSelectedItemPosition()
if selSuaIdx >= 0 and #suaraObjs > 0 then pcall(function() tempTts.setVoice(suaraObjs[selSuaIdx + 1]) end) end
tempTts.setPitch(skP.getProgress() / 10.0)
tempTts.setSpeechRate(skR.getProgress() / 10.0)
tempTts.speak(T("teks_tes_suara", "Halo, ini adalah tes suara."), TextToSpeech.QUEUE_FLUSH, nil)
end
end

dTTS.setButton(T("simpan", "Simpan"), function()
editor.putString("tts_engine", svM)
if spBhs.getSelectedItemPosition() >= 0 and #bahasaNames > 0 then editor.putString("tts_lang", bahasaNames[spBhs.getSelectedItemPosition() + 1]) end
if spSua.getSelectedItemPosition() >= 0 and #suaraObjs > 0 then editor.putString("tts_voice", suaraObjs[spSua.getSelectedItemPosition() + 1].getName()) end
editor.putFloat("tts_pitch", skP.getProgress() / 10.0)
editor.putFloat("tts_rate", skR.getProgress() / 10.0)
editor.commit()
if tempTts then pcall(function() tempTts.shutdown() end) end
end)
dTTS.setButton2(T("batal", "Batal"), function() if tempTts then pcall(function() tempTts.shutdown() end) end end)
dTTS.setOnCancelListener(function() if tempTts then pcall(function() tempTts.shutdown() end) end end)
dTTS.show()

elseif pD == 1 then
local lay24 = UI_Layout(
UI_Teks(T("teks_24_jam", "Teks 24 Jam:")),
UI_Input("e24b", "waktu saat ini menunjukan pukul: [ANGKA]"),
UI_Teks(T("teks_24_jam_tepat", "Teks 24 Jam Tepat:")),
UI_Input("e24t", "waktu saat ini menunjukan pukul: [ANGKA] ,tepat...")
)
local d24 = UI_Dialog(T("dapur_24", "Format Teks 24 Jam"))
d24.setView(loadlayout(lay24))
e24b.setText(pref.getString("txt_24", "waktu saat ini menunjukkan pukul: [ANGKA]"))
e24t.setText(pref.getString("txt_24_tepat", "waktu saat ini menunjukkan pukul: [ANGKA], tepat..."))
d24.setButton(T("simpan", "Simpan"), function()
editor.putString("txt_24", tostring(e24b.getText()))
editor.putString("txt_24_tepat", tostring(e24t.getText()))
editor.commit()
end)
d24.setButton2(T("batal", "Batal"), nil)
d24.show()

elseif pD == 2 then
local scroll = ScrollView(service)
local lay12 = UI_Layout(
UI_Teks(T("dini_hari", "Dini Hari (Biasa / Tepat):")),
UI_Input("e12_1b", "pukul [ANGKA] dini hari"), UI_Input("e12_1t", "tepat pukul [ANGKA] dini hari"),
UI_Teks(T("pagi_hari", "Pagi (Biasa / Tepat):")),
UI_Input("e12_2b", "pukul [ANGKA] pagi"), UI_Input("e12_2t", "tepat pukul [ANGKA] pagi"),
UI_Teks(T("siang_hari", "Siang (Biasa / Tepat):")),
UI_Input("e12_3b", "pukul [ANGKA] siang"), UI_Input("e12_3t", "tepat pukul [ANGKA] siang"),
UI_Teks(T("sore_hari", "Sore (Biasa / Tepat):")),
UI_Input("e12_4b", "pukul [ANGKA] sore"), UI_Input("e12_4t", "tepat pukul [ANGKA] sore"),
UI_Teks(T("malam_hari", "Malam (Biasa / Tepat):")),
UI_Input("e12_5b", "pukul [ANGKA] malam"), UI_Input("e12_5t", "tepat pukul [ANGKA] malam")
)
scroll.addView(loadlayout(lay12))
local d12 = UI_Dialog(T("dapur_12", "Format Teks 12 Jam"))
d12.setView(scroll)
e12_1b.setText(pref.getString("txt_12_1", "waktu saat ini menunjukkan pukul [ANGKA] dini hari"))
e12_1t.setText(pref.getString("txt_12_1_tepat", "waktu saat ini tepat pukul [ANGKA] dini hari..."))
e12_2b.setText(pref.getString("txt_12_2", "waktu saat ini menunjukkan pukul [ANGKA] pagi"))
e12_2t.setText(pref.getString("txt_12_2_tepat", "waktu saat ini tepat pukul [ANGKA] pagi..."))
e12_3b.setText(pref.getString("txt_12_3", "waktu saat ini menunjukkan pukul [ANGKA] siang"))
e12_3t.setText(pref.getString("txt_12_3_tepat", "waktu saat ini tepat pukul [ANGKA] siang..."))
e12_4b.setText(pref.getString("txt_12_4", "waktu saat ini menunjukkan pukul [ANGKA] sore"))
e12_4t.setText(pref.getString("txt_12_4_tepat", "waktu saat ini tepat pukul [ANGKA] sore"))
e12_5b.setText(pref.getString("txt_12_5", "waktu saat ini menunjukkan pukul [ANGKA] malam"))
e12_5t.setText(pref.getString("txt_12_5_tepat", "waktu saat ini tepat pukul [ANGKA] malam"))

d12.setButton(T("simpan", "Simpan"), function()
editor.putString("txt_12_1", tostring(e12_1b.getText()))
editor.putString("txt_12_1_tepat", tostring(e12_1t.getText()))
editor.putString("txt_12_2", tostring(e12_2b.getText()))
editor.putString("txt_12_2_tepat", tostring(e12_2t.getText()))
editor.putString("txt_12_3", tostring(e12_3b.getText()))
editor.putString("txt_12_3_tepat", tostring(e12_3t.getText()))
editor.putString("txt_12_4", tostring(e12_4b.getText()))
editor.putString("txt_12_4_tepat", tostring(e12_4t.getText()))
editor.putString("txt_12_5", tostring(e12_5b.getText()))
editor.putString("txt_12_5_tepat", tostring(e12_5t.getText()))
editor.commit()
end)
d12.setButton2(T("batal", "Batal"), nil)
d12.show()

elseif pD == 3 then
local layMin = UI_Layout(
UI_Teks(T("teks_menit_0", "Teks Menit 0 (Tepat):")),
UI_Input("emin0", ",Tepat"),
UI_Teks(T("teks_menit_lewat", "Teks Menit Lewat (Kelipatan 5):")),
UI_Input("eminx", "Lewat: [ANGKA] menit...")
)
local dMin = UI_Dialog(T("dapur_menit", "Format Teks Menit"))
dMin.setView(loadlayout(layMin))
emin0.setText(pref.getString("txt_min_0", ",Tepat"))
eminx.setText(pref.getString("txt_min_x", "Lewat: [ANGKA] menit..."))
dMin.setButton(T("simpan", "Simpan"), function()
editor.putString("txt_min_0", tostring(emin0.getText()))
editor.putString("txt_min_x", tostring(eminx.getText()))
editor.commit()
end)
dMin.setButton2(T("batal", "Batal"), nil)
dMin.show()
elseif pD == 4 then
EfekJam.tampilkanPengaturan()
elseif pD == 5 then
SisipanJam.tampilkanPengaturan()
elseif pD == 6 then
ProgresJam.tampilkanPengaturan()
end
end
dDapur.setButton(T("tutup", "Tutup"), function() dDapur.dismiss(); tampilkanMenuPengaturan() end)
dDapur.setOnCancelListener(function() tampilkanMenuPengaturan() end)
dDapur.show()

elseif selectedId == "klip" then
local isKlip = prefs.getBoolean("use_jieshuo_clip", false)
prefs.edit().putBoolean("use_jieshuo_clip", not isKlip).apply()
if not isKlip then service.asyncSpeak(T("ucapan_aktif", "Saat ini aktif")) else service.asyncSpeak(T("ucapan_mati", "Saat ini mati")) end
refreshList()

elseif selectedId == "ekspor_fmt" then
local isExportFmt = prefs.getBoolean("use_jieshuo_export_format", false)
prefs.edit().putBoolean("use_jieshuo_export_format", not isExportFmt).apply()
if not isExportFmt then service.asyncSpeak(T("ucapan_aktif", "Saat ini aktif")) else service.asyncSpeak(T("ucapan_mati", "Saat ini mati")) end
refreshList()

elseif selectedId == "reset_pengaturan" then
dialogPengaturan.dismiss()
showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("pesan_reset_pengaturan", "Yakin ingin mereset semua pengaturan khusus skrip ini (seperti format jam, kualitas rekaman, nama event, dll) kembali ke bawaan pabrik? \n\nTenang saja, tema dan file audio Anda tidak akan terhapus."), function()
pref.edit().clear().commit()
service.speak(T("reset_sukses", "Pengaturan skrip berhasil direset."))
muatUlangBahasaDanMenu()
end, function()
tampilkanMenuPengaturan()
end)

end
end
dialogPengaturan.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dialogPengaturan.setButton(T("tutup", "Tutup"), function() dialogPengaturan.dismiss(); muatUlangBahasaDanMenu() end)
dialogPengaturan.show()
end


tampilkanPemilihTemaSuara = function(onBack)
autoRestoreCadangan(function()
local prefs = PreferenceManager.getDefaultSharedPreferences(service)
local dTema = UI_Dialog(T("ganti_tema", "Ganti Tema Suara"))
local layoutTema = UI_Layout(
UI_Input("cariTema", T("cari_tema", "Cari tema...")),
UI_Daftar("lvTema"),
UI_Tombol("btnTutupTema", T("tutup", "Tutup"))
)
dTema.setView(loadlayout(layoutTema))

local temaGlobal = {}
local filterList = ArrayList()

local dir = File(basePath)
if dir.exists() and dir.isDirectory() then
local files = dir.listFiles()
if files then
for i = 0, #files - 1 do
if files[i].isDirectory() and File(files[i].getAbsolutePath() .. "/config").exists() then
table.insert(temaGlobal, tostring(files[i].getName()))
end
end
end
end
table.sort(temaGlobal, function(a, b) return string.lower(a) < string.lower(b) end)

for i = 1, #temaGlobal do filterList.add(temaGlobal[i]) end
local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, filterList)
lvTema.setAdapter(adapter)

cariTema.addTextChangedListener(TextWatcher{
onTextChanged = function(text, start, before, count)
local query = tostring(text):lower()
filterList.clear()
for _, tema in ipairs(temaGlobal) do
if tostring(tema):lower():find(query, 1, true) then filterList.add(tema) end
end
adapter.notifyDataSetChanged()
end
})

lvTema.onItemClick = function(l, v, p, id)
local tema = tostring(filterList.get(p))
prefs.edit().putString("sound_package", tema).apply()
service.loadSoundPackage(tema)
dTema.dismiss()
if onBack then onBack() else tampilkanMenuPengaturan() end
end

btnTutupTema.onClick = function() dTema.dismiss(); if onBack then onBack() else tampilkanMenuPengaturan() end end
dTema.setOnCancelListener(function() if onBack then onBack() else tampilkanMenuPengaturan() end end)
dTema.show()

end)
end

tampilkanPemilihIntensitas = function()
local prefs = PreferenceManager.getDefaultSharedPreferences(service)
local dInt = UI_Dialog(T("atur_intensitas", "Atur Intensitas Getaran"))
local lvInt = ListView(service)

local optionsList = ArrayList()
optionsList.add(T("getar_paling_kecil", "Paling kecil"))
optionsList.add(T("getar_kecil", "Kecil"))
optionsList.add(T("getar_besar", "Besar"))
optionsList.add(T("getar_paling_besar", "Paling besar"))

local valuesList = {"12", "32", "48", "64"}

lvInt.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, optionsList))
dInt.setView(lvInt)

lvInt.onItemClick = function(l, v, p, id)
local intensity = valuesList[p + 1]
prefs.edit().putString("vibrate_intensity", intensity).apply()

-- Trik yang benar: Muat ulang engine Jieshuo agar membaca intensitas baru
pcall(function() service.reCreate() end)

service.asyncSpeak(T("simpan", "Simpan"))
dInt.dismiss()
tampilkanMenuPengaturan()
end

dInt.setButton(T("tutup", "Tutup"), function() dInt.dismiss(); tampilkanMenuPengaturan() end)
dInt.setOnCancelListener(function() tampilkanMenuPengaturan() end)
dInt.show()
end

tampilkanPemilihVolume = function(onBack)
local prefs = PreferenceManager.getDefaultSharedPreferences(service)
local dVol = UI_Dialog(T("atur_volume", "Atur Volume"))
local lvVol = ListView(service)
local volumes = ArrayList()
for i = 1, 100 do volumes.add(tostring(i)) end
lvVol.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, volumes))
dVol.setView(lvVol)
lvVol.onItemClick = function(l, v, p, id)
local volume = p + 1
service.setSoundVolume(volume)
prefs.edit().putString("sound_volume", tostring(volume)).apply()
service.reCreate()
dVol.dismiss()
if onBack then onBack() else tampilkanMenuPengaturan() end
end
dVol.setButton(T("tutup", "Tutup"), function() dVol.dismiss(); if onBack then onBack() else tampilkanMenuPengaturan() end end)
dVol.setOnCancelListener(function() if onBack then onBack() else tampilkanMenuPengaturan() end end)
dVol.show()

end

toggleSuara = function()
local prefs = PreferenceManager.getDefaultSharedPreferences(service)
local statusSaatIni = prefs.getBoolean("use_sound", true)
local statusBaru = not statusSaatIni
prefs.edit().putBoolean("use_sound", statusBaru).apply()
service.setSound(statusBaru)
if statusBaru then
service.asyncSpeak(T("ucapan_aktif", "Saat ini aktif"))
else
service.asyncSpeak(T("ucapan_mati", "Saat ini mati"))
end
end

demoSesiDihitung = false
function CatatDemoInstan()
if demoSesiDihitung then return end
demoSesiDihitung = true
CatatPemakaianFreemium("demo_instan", false)
end

local function HelperGunakanDemo()
hentikanAudioGlobal()
local folderDemo = File(basePath .. "/[Tema Demo]")
local dDataGunakan = bacaJson(BASE .. "draft_demo.json")
jalankanTaskLoading(nil, kerjaSalinTema, cjson.encode({ dest = folderDemo.getAbsolutePath(), hapusDulu = true, files = dDataGunakan }), function()
PreferenceManager.getDefaultSharedPreferences(service).edit().putString("sound_package", "[Tema Demo]").apply()

service.loadSoundPackage("[Tema Demo]")
service.speak(T("demo_aktif", "Tema Demo aktif!"))
CatatDemoInstan()
end)
end

local function HelperJadikanAsli(dialogToDismiss)
hentikanAudioGlobal()
local dData = bacaJson(BASE .. "draft_demo.json")
local adaIsi = false
for k, v in pairs(dData) do
if v and v ~= "" and File(v).exists() then adaIsi = true break end
end

if not adaIsi then
service.speak(T("demo_kosong", "Belum ada audio demo yang dipilih."))
return
end

showInputDialog(T("jadikan_asli", "Jadikan Tema Suara Asli"), T("masukkan_nama_tema_baru", "Masukkan nama tema baru..."), "", function(namaBaru)
if namaBaru ~= "" then
local folderBaru = File(basePath .. "/" .. namaBaru)
if folderBaru.exists() then
service.speak(T("nama_telah_digunakan", "Nama tersebut sudah digunakan, silakan pilih nama lain."))
return false
else
jalankanTaskLoading(nil, kerjaSalinTema, cjson.encode({ dest = folderBaru.getAbsolutePath(), hapusDulu = false, files = dData }), function()
PreferenceManager.getDefaultSharedPreferences(service).edit().putString("sound_package", namaBaru).apply()
service.loadSoundPackage(namaBaru)
service.speak(T("demo_tersimpan", "Berhasil disimpan sebagai tema ") .. namaBaru)

task(kerjaHapusPath, cjson.encode({ basePath .. "/[Tema Demo]", BASE .. "draft_demo.json" }), function() end)

if dialogToDismiss then dialogToDismiss.dismiss() end
muatUlangBahasaDanMenu()
CatatDemoInstan()
end)
return true
end
end
return true
end)
end

local function HelperHapusDemo(dialogToDismiss, onSuccess)
hentikanAudioGlobal()
local dData = bacaJson(BASE .. "draft_demo.json")
local adaIsi = false
for k, v in pairs(dData) do if v and v ~= "" and File(v).exists() then adaIsi = true break end end
local folderDemo = File(basePath .. "/[Tema Demo]")

if not adaIsi and not folderDemo.exists() then
service.speak(T("demo_kosong", "Belum ada audio demo yang dipilih."))
return
end

showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("hapus_demo", "Hapus Demo") .. "?", function()
jalankanTaskLoading(nil, kerjaHapusPath, cjson.encode({ folderDemo.getAbsolutePath(), BASE .. "draft_demo.json" }), function()
service.speak(T("demo_berhasil_dihapus", "Tema demo berhasil dihapus."))
if onSuccess then onSuccess() else if dialogToDismiss then dialogToDismiss.dismiss() end muatUlangBahasaDanMenu() end
end)
end)
end

showDemoInstan = function(initPath)
BukaPickerKustom({
judul = T("buat_demo_instan", "Buat Demo Instan"),
pathAwal = initPath or "/storage/emulated/0",
modeMulti = false,
hentikanAudioGlobal = true,
petakanAudioAktif = true,
filterFile = function(f) return isAudioFile(f) end,
onPilihSingle = function(pathDipilih, namaFile, pickerDialog, restoreRadar)
hentikanRadarFokus()
pickerDialog.dismiss()

local eventDialog = UI_Dialog(T("terapkan", "Terapkan") .. ": " .. namaFile)

local layoutEvent = UI_Layout(
UI_Daftar("lvEvent"),
UI_Tombol("btnBatalInstan", T("batal", "Batal"))
)
eventDialog.setView(loadlayout(layoutEvent))
eventDialog.setCancelable(false)

btnBatalInstan.onClick = function()
hentikanRadarFokus()
hentikanAudioGlobal()
eventDialog.dismiss()
local curParent = File(pathDipilih).getParent()
showDemoInstan(curParent and tostring(curParent) or "/storage/emulated/0")
end

local eventData = ArrayList()
local draftData = bacaJson(BASE .. "draft_demo.json")
local rawMaps = {}
PetaAudioAktif = {}

for i = 1, #mappingTema do
local jsonKey = mappingTema[i][2]
local uiName = dapatkanString("str_event_" .. jsonKey, mappingTema[i][1])
local oldPath = draftData[jsonKey]
local subText = ""
local oldAudioName = nil
if oldPath and File(oldPath).exists() then
oldAudioName = File(oldPath).getName()
subText = "\n(" .. oldAudioName .. ")"
PetaAudioAktif[uiName] = oldPath
end
eventData.add(uiName .. subText)
table.insert(rawMaps, { key = jsonKey, uiName = uiName, oldAudio = oldAudioName })
end
lvEvent.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, eventData))

lvEvent.onItemClick = function(el, ev, ep, eid)
hentikanRadarFokus()
hentikanAudioGlobal()
local mapObj = rawMaps[ep + 1]
local function simpanKeDraft()
eventDialog.dismiss()
draftData[mapObj.key] = pathDipilih
simpanJson(BASE .. "draft_demo.json", draftData)
local curParent = File(pathDipilih).getParent()

-- MEMUNCULKAN DIALOG OPSI SETELAH TERAPKAN --
local dOpsi = UI_Dialog(T("terapkan", "Terapkan") .. " " .. T("sukses", "Berhasil!"))
local layOpsi = UI_Layout(
UI_Tombol("btnLanjut", T("lanjut_edit", "Lanjut Mengedit Tema")),
UI_Tombol("btnGunakan", T("gunakan_demo", "Gunakan Tema Suara Demo")),
UI_Tombol("btnJadikan", T("jadikan_asli", "Jadikan Tema Suara Asli")),
UI_Tombol("btnHapus", T("hapus_demo", "Hapus Demo")),
UI_Tombol("btnKeluar", T("tutup", "Tutup / Keluar"))
)
dOpsi.setView(loadlayout(layOpsi))
dOpsi.setCancelable(false)

btnLanjut.onClick = function() dOpsi.dismiss(); showDemoInstan(curParent and tostring(curParent) or "/storage/emulated/0") end
btnGunakan.onClick = function() dOpsi.dismiss(); HelperGunakanDemo() end
btnJadikan.onClick = function() HelperJadikanAsli(dOpsi) end
btnHapus.onClick = function() HelperHapusDemo(dOpsi, function() dOpsi.dismiss(); muatUlangBahasaDanMenu() end) end
btnKeluar.onClick = function() dOpsi.dismiss(); muatUlangBahasaDanMenu() end
dOpsi.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dOpsi.show()
----------------------------------------------
end

if mapObj.oldAudio then
local dTimpa = UI_Dialog(T("konfirmasi", "Konfirmasi"))
dTimpa.setMessage("Event '" .. mapObj.uiName .. "' sudah terisi audio:\n" .. mapObj.oldAudio .. "\n\nApakah Anda yakin ingin menimpanya?")
dTimpa.setButton(T("timpa", "Timpa"), function() simpanKeDraft() end)
dTimpa.setButton2(T("batal", "Batal"), function() mulaiRadarFokus() end)
dTimpa.show()
else
simpanKeDraft()
end
end

eventDialog.setOnCancelListener(function()
hentikanRadarFokus()
hentikanAudioGlobal()
local curParent = File(pathDipilih).getParent()
showDemoInstan(curParent and tostring(curParent) or "/storage/emulated/0")
end)
eventDialog.show()
mulaiRadarFokus()
end,
onBatal = function()
muatUlangBahasaDanMenu()
end
})
end

showPickerDemo = function(jsonKey, targetUiName)
BukaPickerKustom({
judul = T("pilih_audio", "Pilih Audio") .. ": " .. targetUiName,
modeMulti = false,
hentikanAudioGlobal = true,
petakanAudioAktif = true,
filterFile = function(f) return isAudioFile(f) end,
onPilihSingle = function(pathDipilih, namaFile, pickerDialog, restoreRadar)
local draftData = bacaJson(BASE .. "draft_demo.json")
draftData[jsonKey] = pathDipilih
simpanJson(BASE .. "draft_demo.json", draftData)
restoreRadar()
pickerDialog.dismiss()
tampilkanMenuDemo()
end,
onBatal = function()
tampilkanMenuDemo()
end
})
end

tampilkanMenuDemo = function()
hentikanRadarFokus()
local mainDialog = UI_Dialog(T("buat_demo", "Buat Tema Suara Demo"))

local layoutDemo = UI_Layout(
UI_Tombol("btnGunakanDemo", T("gunakan_demo", "Gunakan Tema Suara Demo")),
UI_Tombol("btnJadikanAsli", T("jadikan_asli", "Jadikan Tema Suara Asli")),
UI_Tombol("btnHapusDemo", T("hapus_demo", "Hapus Demo")),
UI_Daftar("lvDemo"),
UI_Tombol("closeBtn", T("tutup", "Tutup"))
)
mainDialog.setView(loadlayout(layoutDemo))

btnGunakanDemo.onClick = function() HelperGunakanDemo() end
btnJadikanAsli.onClick = function() HelperJadikanAsli(mainDialog) end
btnHapusDemo.onClick = function() HelperHapusDemo(mainDialog, function() mainDialog.dismiss(); tampilkanMenuDemo() end) end

local itemLayout = UI_ItemBaris("cbItem", "tvName")
local draftData = bacaJson(BASE .. "draft_demo.json")
local listData = {}
PetaAudioAktif = {}

for i = 1, #mappingTema do
local jsonKey = mappingTema[i][2]
local uiName = dapatkanString("str_event_" .. jsonKey, mappingTema[i][1])
local pathTersimpan = draftData[jsonKey]
local subText = T("belum_diatur", "Belum diatur")

if pathTersimpan and File(pathTersimpan).exists() then
subText = File(pathTersimpan).getName()
PetaAudioAktif[uiName] = pathTersimpan
end

table.insert(listData, {
cbItem = {visibility = 8},
tvName = uiName .. "\n" .. subText,
_jsonKey = jsonKey,
_uiName = uiName
})
end

local adapter = LuaAdapter(service, listData, itemLayout)
lvDemo.setAdapter(adapter)

lvDemo.onItemClick = function(l, v, p, id)
hentikanRadarFokus()
hentikanAudioGlobal()
local item = listData[p+1]
mainDialog.dismiss()
showPickerDemo(item._jsonKey, item._uiName)
end

closeBtn.onClick = function() hentikanRadarFokus(); hentikanAudioGlobal(); mainDialog.dismiss(); muatUlangBahasaDanMenu() end
mainDialog.setOnCancelListener(function() hentikanRadarFokus(); hentikanAudioGlobal(); muatUlangBahasaDanMenu() end)
mainDialog.show()
mulaiRadarFokus()
end

tampilkanDaftarKodeSuara = function()
local dialogKode = UI_Dialog(T("daftar_kode_suara", "Daftar Kode Suara Tema"))
local layoutKode = UI_Layout(
UI_Daftar("lvKode"),
UI_Tombol("btnCloseKode", T("tutup", "Tutup"))
)
dialogKode.setView(loadlayout(layoutKode))

local listData = ArrayList()
local rawData = {}

local templateAjaib = 'pcall(function() local pr=luajava.bindClass("android.preference.PreferenceManager").getDefaultSharedPreferences(service); local tm=pr.getString("sound_package",""); if tm~="" and tm~="Standar" then local d=luajava.bindClass("java.io.File")("/storage/emulated/0/瑙ｈ").listFiles(); local p=nil; if d then for i=0,#d-1 do if d[i].isDirectory() and luajava.bindClass("java.io.File")(d[i].getAbsolutePath().."/"..tm).exists() then p=d[i].getAbsolutePath().."/"..tm; break end end end if p then local js=require("cjson").decode(io.open(p.."/config"):read("*a")); local fn=js["%s"]; if fn and fn~="value_default" and fn~="value_none" and fn~="" then local mp=luajava.bindClass("android.media.MediaPlayer")(); mp.setOnCompletionListener(function(m) m.release() end); mp.setDataSource(p.."/"..fn); mp.prepare(); mp.start(); return end end end service.play("%s") end)'

for i = 1, #mappingTema do
local jsonKey = mappingTema[i][2]
local uiName = dapatkanString("str_event_" .. jsonKey, mappingTema[i][1])
local kodeScript = string.format(templateAjaib, jsonKey, jsonKey)
local teksTampilan = 'service.play("' .. jsonKey .. '")'
listData.add(uiName .. "\n" .. teksTampilan)
table.insert(rawData, {nama = uiName, kode = kodeScript, key = jsonKey})
end

lvKode.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, listData))

lvKode.onItemClick = function(l, v, p, id)
local item = rawData[p+1]
local isKlipJieshuo = PreferenceManager.getDefaultSharedPreferences(service).getBoolean("use_jieshuo_clip", false)

if isKlipJieshuo then
service.copy(item.kode)
else
local clipboard = service.getSystemService(Context.CLIPBOARD_SERVICE)
local clipData = ClipData.newPlainText("KodeJieshuo", item.kode)
clipboard.setPrimaryClip(clipData)
end
service.speak(T("berhasil_disalin", "Berhasil disalin: ") .. 'service.play("' .. item.key .. '")')
end

lvKode.onItemLongClick = function(l, v, p, id)
local item = rawData[p+1]
service.speak(T("tes_suara", "Memutar: ") .. item.nama)

Thread(Runnable({
run = function()
import "java.lang.Thread"
Thread.sleep(150)
while service.isSpeaking() do
Thread.sleep(50)
end
pcall(function() loadstring(item.kode)() end)
end
})).start()

return true
end

btnCloseKode.onClick = function() dialogKode.dismiss(); muatUlangBahasaDanMenu() end
dialogKode.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dialogKode.show()
end

showPickerSPK = function()
local function jalankanImporSPK(toImport, gunakanTema)
prosesAntreanSPK(toImport, 1, nil, {}, function(importedThemes)
if #importedThemes > 0 then
if gunakanTema then
if #importedThemes == 1 then
PreferenceManager.getDefaultSharedPreferences(service).edit().putString("sound_package", importedThemes[1]).apply()
service.loadSoundPackage(importedThemes[1])
service.speak(T("berhasil_impor_spk", "Berhasil mengimpor: ") .. importedThemes[1])
muatUlangBahasaDanMenu()
else
local dPilih = UI_Dialog(T("pilih_tema_diterapkan", "Pilih Tema untuk Diterapkan"))
local lvPilih = ListView(service)
local listPilih = ArrayList()
for i = 1, #importedThemes do listPilih.add(importedThemes[i]) end
lvPilih.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, listPilih))
dPilih.setView(lvPilih)
lvPilih.onItemClick = function(lP, vP, pP, idP)
local tDipilih = importedThemes[pP + 1]
PreferenceManager.getDefaultSharedPreferences(service).edit().putString("sound_package", tDipilih).apply()
service.loadSoundPackage(tDipilih)
dPilih.dismiss()
muatUlangBahasaDanMenu()
end
dPilih.setButton(T("tutup", "Tutup"), function() dPilih.dismiss(); muatUlangBahasaDanMenu() end)
dPilih.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dPilih.show()
end
else
service.speak(T("berhasil_impor_spk", "Berhasil mengimpor: ") .. #importedThemes .. " SPK")
muatUlangBahasaDanMenu()
end
else
muatUlangBahasaDanMenu()
end
end)
end

BukaPickerKustom({
judul = T("pilih_spk", "Pilih File SPK"),
modeMulti = true,
hentikanAudioGlobal = false,
petakanAudioAktif = false,
teksTombol1 = T("impor", "Impor"),
teksTombol2 = T("impor_terapkan", "Impor & Gunakan"),
filterFile = function(f) return string.match(string.lower(f.getName()), "%.spk$") ~= nil end,
onAksi1 = function(listFile, pickerDialog, restoreRadar)
pickerDialog.dismiss()
jalankanImporSPK(listFile, false)
end,
onAksi2 = function(listFile, pickerDialog, restoreRadar)
pickerDialog.dismiss()
jalankanImporSPK(listFile, true)
end,
onBatal = function()
muatUlangBahasaDanMenu()
end
})
end

tampilkanMenuPencadangan = function()
local dCadang = UI_Dialog(T("menu_pencadangan", "Menu Pencadangan"))
local lvMenu = ListView(service)
local opsiMenu = {T("cadang_data", "Cadangkan Data Tema Suara"), T("pulih_data", "Pulihkan Data Tema Suara"), T("cek_integritas", "Periksa Integritas Data")}
lvMenu.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, opsiMenu))
dCadang.setView(lvMenu)
lvMenu.onItemClick = function(l, v, p, id)
dCadang.dismiss()
if p == 0 then
local pCadang = UI_Dialog(T("cadang_data", "Cadangkan Data Tema Suara"))
local layoutC = UI_Layout(
UI_Daftar("lvC"),
{LinearLayout, orientation="horizontal", layout_width="fill",
UI_Tombol_H("btnTutupC", T("tutup", "Tutup")),
UI_Tombol_H("btnSimpanC", T("cadangkan", "Cadangkan"))
}
)
pCadang.setView(loadlayout(layoutC))
local listT, itemLayout = {}, UI_ItemBaris("cbItem", "tvName")
local d = File(basePath)
if d.exists() then
local f = d.listFiles()
if f then for i=0,#f-1 do if f[i].isDirectory() and File(f[i].getAbsolutePath().."/config").exists() then table.insert(listT, {cbItem={checked=false}, tvName=f[i].getName()}) end end end
end
table.sort(listT, function(a,b) return a.tvName:lower() < b.tvName:lower() end)
local adapter = LuaAdapter(service, listT, itemLayout)
lvC.setAdapter(adapter)
lvC.onItemClick = function(ll,vv,pp,iid) listT[pp+1].cbItem.checked = not listT[pp+1].cbItem.checked; adapter.notifyDataSetChanged() end
btnSimpanC.onClick = function()
local diproses = {}
for i=1,#listT do if listT[i].cbItem.checked then table.insert(diproses, listT[i].tvName) end end
if #diproses>0 then
local itemsSalin = {}
for i=1,#diproses do table.insert(itemsSalin, { src = basePath.."/"..diproses[i], dst = backupPath.."/"..diproses[i], hapusDulu = true }) end
jalankanTaskLoading(nil, kerjaSalinFlat, cjson.encode(itemsSalin), function() tampilkanMenuPencadangan() end)
end
end
btnTutupC.onClick = function() pCadang.dismiss(); tampilkanMenuPencadangan() end
pCadang.setOnCancelListener(function() tampilkanMenuPencadangan() end)
pCadang.show()
elseif p == 1 then
local pPulih = UI_Dialog(T("pulih_data", "Pulihkan Data Tema Suara"))
local layoutP = UI_Layout(
UI_Daftar("lvP"),
{LinearLayout, orientation="horizontal", layout_width="fill",
UI_Tombol_H("btnTutupP", T("tutup", "Tutup")),
UI_Tombol_H("btnSimpanP", T("pulihkan", "Pulihkan"))
}
)
pPulih.setView(loadlayout(layoutP))
local listT, itemLayout = {}, UI_ItemBaris("cbItem", "tvName")
local d = File(backupPath)
if d.exists() then
local f = d.listFiles()
if f then for i=0,#f-1 do if f[i].isDirectory() then table.insert(listT, {cbItem={checked=false}, tvName=f[i].getName()}) end end end
end
table.sort(listT, function(a,b) return a.tvName:lower() < b.tvName:lower() end)
local adapter = LuaAdapter(service, listT, itemLayout)
lvP.setAdapter(adapter)
lvP.onItemClick = function(ll,vv,pp,iid) listT[pp+1].cbItem.checked = not listT[pp+1].cbItem.checked; adapter.notifyDataSetChanged() end
btnSimpanP.onClick = function()
local diproses = {}
for i=1,#listT do if listT[i].cbItem.checked then table.insert(diproses, listT[i].tvName) end end
if #diproses>0 then
local itemsSalin = {}
for i=1,#diproses do table.insert(itemsSalin, { src = backupPath.."/"..diproses[i], dst = basePath.."/"..diproses[i], hapusDulu = true }) end
jalankanTaskLoading(nil, kerjaSalinFlat, cjson.encode(itemsSalin), function() tampilkanMenuPencadangan() end)
end
end
btnTutupP.onClick = function() pPulih.dismiss(); tampilkanMenuPencadangan() end
pPulih.setOnCancelListener(function() tampilkanMenuPencadangan() end)
pPulih.show()
elseif p == 2 then
jalankanDenganLoading(nil, function()
local dUtama = File(basePath)
local dCad = File(backupPath)
local modif = {}
if dCad.exists() and dUtama.exists() then
local fCad = dCad.listFiles()
if fCad then
for i=0,#fCad-1 do
if fCad[i].isDirectory() then
local nama = fCad[i].getName()
local fU = File(basePath.."/"..nama)
if fU.exists() and fU.isDirectory() then
local cList = fCad[i].listFiles()
local uList = fU.listFiles()
local cFiles, uFiles = {}, {}
if cList then for j=0, #cList-1 do if cList[j].isFile() then table.insert(cFiles, cList[j].getName()) end end end
if uList then for j=0, #uList-1 do if uList[j].isFile() then table.insert(uFiles, uList[j].getName()) end end end
local beda = false
if #cFiles ~= #uFiles then beda = true else
local mapC = {}
for j=1, #cFiles do mapC[cFiles[j]] = true end
for j=1, #uFiles do if not mapC[uFiles[j]] then beda = true break end end
end
if not beda then
local jsonC = bacaJson(fCad[i].getAbsolutePath().."/config")
local jsonU = bacaJson(fU.getAbsolutePath().."/config")
local function deepCompare(t1, t2)
if type(t1) ~= type(t2) then return false end
if type(t1) ~= "table" then return t1 == t2 end
for k, v in pairs(t1) do if not deepCompare(v, t2[k]) then return false end end
for k, v in pairs(t2) do if t1[k] == nil then return false end end
return true
end
if not deepCompare(jsonC, jsonU) then beda = true end
end
if beda then table.insert(modif, nama) end
end
end
end
end
end
return modif
end, function(modif)
if #modif == 0 then
tampilkanMenuPencadangan()
uiHandler.postDelayed(Runnable({
run = function()
service.speak(T("aman", "Integritas Data Aman"))
end
}), 500)
else
local pSync = UI_Dialog(T("cek_integritas", "Periksa Integritas Data"))
local layoutS = UI_Layout({TextView, text=T("data_termodifikasi", "Termodifikasi (Ketuk untuk menyinkronkan):"), layout_marginBottom="8dp"}, UI_Daftar("lvS"), UI_Tombol("btnSinkronSemua", T("sinkron_semua", "Sinkronkan Semua")), UI_Tombol("btnTutupS", T("tutup", "Tutup")))
pSync.setView(loadlayout(layoutS))

local listModif = ArrayList()
for k=1, #modif do listModif.add(modif[k]) end
local adapterSync = ArrayAdapter(service, android.R.layout.simple_list_item_1, listModif)
lvS.setAdapter(adapterSync)

lvS.onItemClick = function(ll,vv,pp,iid)
local item = tostring(listModif.get(pp))
jalankanTaskLoading(nil, kerjaSalinFlat, cjson.encode({ { src = basePath.."/"..item, dst = backupPath.."/"..item, hapusDulu = true } }), function()
service.speak(T("disinkronkan", "Disinkronkan: ") .. item)
listModif.remove(pp)
adapterSync.notifyDataSetChanged()
if listModif.size() == 0 then
pSync.dismiss()
tampilkanMenuPencadangan()
end
end)
end

btnSinkronSemua.onClick = function()
pSync.dismiss()
local itemsSalin = {}
for k=0, listModif.size()-1 do
local item = tostring(listModif.get(k))
table.insert(itemsSalin, { src = basePath.."/"..item, dst = backupPath.."/"..item, hapusDulu = true })
end
jalankanTaskLoading(nil, kerjaSalinFlat, cjson.encode(itemsSalin), function() tampilkanMenuPencadangan() end)
end
btnTutupS.onClick = function() pSync.dismiss(); tampilkanMenuPencadangan() end
pSync.setOnCancelListener(function() tampilkanMenuPencadangan() end)
pSync.show()
end
end)
end
end
dCadang.setButton(T("tutup", "Tutup"), function() dCadang.dismiss(); muatUlangBahasaDanMenu() end)
dCadang.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dCadang.show()
end

local tampilkanMenuBuatEfek
local function prosesAntreanEfek(queue, index, temaTujuan)
if index > #queue then
service.speak(T("selesai", "Semua efek selesai diproses"))
muatUlangBahasaDanMenu()
return
end
local srcFile = File(queue[index])
local oldFullName = srcFile.getName()
local nameOnly, ext = string.match(oldFullName, "^(.+)(%..+)$")
if not nameOnly then nameOnly = oldFullName; ext = "" end
local dName = UI_Dialog(T("ganti_nama_efek", "Ganti Nama Efek (") .. index .. "/" .. #queue .. ")")
local input = EditText(service)
input.setText(nameOnly)
dName.setView(input)
local function lanjut(namaBaruFinal)
jalankanTaskLoading(nil, kerjaSalinFlat, cjson.encode({ { srcFile = srcFile.getAbsolutePath(), dstFile = basePath .. "/" .. temaTujuan .. "/effect/" .. namaBaruFinal } }), function()
prosesAntreanEfek(queue, index + 1, temaTujuan)
end)
end
dName.setButton(T("simpan", "Simpan"), function()
local teksName = tostring(input.getText())
if teksName == "" then teksName = nameOnly end
local finalName = teksName .. ext
local targetFile = File(basePath .. "/" .. temaTujuan .. "/effect/" .. finalName)
if targetFile.exists() then
local dKonflik = UI_Dialog(T("konfirmasi", "Konfirmasi"))
dKonflik.setMessage(finalName .. " " .. T("file_sudah_ada", "sudah ada. Apa yang ingin Anda lakukan?"))
dKonflik.setButton(T("timpa", "Timpa"), function() lanjut(finalName) end)
dKonflik.setButton2(T("ganti_nama", "Ganti Nama"), function()
local safeName = DapatkanNamaUnik(basePath .. "/" .. temaTujuan .. "/effect", finalName)
lanjut(safeName)
end)
dKonflik.setButton3(T("lewati", "Lewati"), function() prosesAntreanEfek(queue, index + 1, temaTujuan) end)
dKonflik.setCancelable(false)
dKonflik.show()
else
lanjut(finalName)
end
end)
dName.setButton2(T("lewati", "Batal / Lewati"), function()
prosesAntreanEfek(queue, index + 1, temaTujuan)
end)
dName.setCancelable(false)
dName.show()
end

tampilkanMenuBuatEfek = function()
local dTemaObj = UI_Dialog(T("pilih_tema_tujuan_efek", "Pilih Tema Tujuan (Efek)"))
local lvTemaObj = ListView(service)
local listTema = ArrayList()
local dir = File(basePath)
local allT = {}
if dir.exists() then
local files = dir.listFiles()
if files then
for i = 0, #files - 1 do
if files[i].isDirectory() and File(files[i].getAbsolutePath() .. "/config").exists() then
table.insert(allT, files[i].getName())
end
end
end
end
table.sort(allT, function(a, b) return string.lower(a) < string.lower(b) end)
for i=1, #allT do listTema.add(allT[i]) end
lvTemaObj.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, listTema))
dTemaObj.setView(lvTemaObj)
lvTemaObj.onItemClick = function(lT, vT, pT, idT)
local temaTujuan = tostring(listTema.get(pT))
dTemaObj.dismiss()
BukaPickerKustom({
judul = T("pilih_audio_efek", "Pilih Audio untuk Efek"),
modeMulti = true,
hentikanAudioGlobal = true,
petakanAudioAktif = true,
teksTombol1 = T("proses_efek", "Proses Efek"),
filterFile = function(f) return isAudioFile(f) end,
onAksi1 = function(toProcess, pickerDialog, restoreRadar)
restoreRadar()
pickerDialog.dismiss()
prosesAntreanEfek(toProcess, 1, temaTujuan)
end,
onBatal = function()
tampilkanMenuBuatEfek()
end
})
end
dTemaObj.setButton(T("tutup", "Tutup"), function() dTemaObj.dismiss(); muatUlangBahasaDanMenu() end)
dTemaObj.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dTemaObj.show()
end

local tampilkanTemaEksternal
tampilkanTemaEksternal = function(currentPath)
currentPath = currentPath or "/storage/emulated/0"

local dialogEks = UI_Dialog(T("kelola_tema_eksternal", "Manajer Tema Eksternal"))

local layoutEks = UI_Layout(
{TextView, id="tvPathEks", text=currentPath, padding="10dp", layout_marginBottom="8dp", textColor="0xFF4CAF50"},
UI_Input("etCariEks", T("cari_folder", "Cari folder atau tema...")),
UI_Tombol("btnModePemilihanEks", T("mode_pilih", "Aktifkan Mode Pemilihan")),
{Button, id="btnPilihSemuaEks", text=T("pilih_semua", "Pilih Semua"), layout_width="fill", layout_marginBottom="8dp", visibility=8},
{LinearLayout, id="layoutAksiEks", orientation="horizontal", layout_width="fill", layout_marginBottom="8dp", visibility=8,
UI_Tombol_H("btnHapusEks", T("hapus", "Hapus")),
UI_Tombol_H("btnEksporEks", T("bagikan", "Ekspor")),
UI_Tombol_H("btnCadangSpkEks", T("cadangkan_spk", "Cadang SPK"))
},
UI_Daftar("lvEks"),
UI_Tombol("btnTutupEks", T("tutup", "Tutup"))
)
dialogEks.setView(loadlayout(layoutEks))

local itemLayout = UI_ItemBaris("cbItem", "tvName")
local allItems = {}
local listData = {}
local isSelectionMode = false
local isAllSelected = false
local selectedItems = {}
local adapter = nil

local function updateAksiEks()
local count = 0
for k, v in pairs(selectedItems) do count = count + 1 end
if count > 0 then
layoutAksiEks.setVisibility(0)
btnHapusEks.setText(T("hapus", "Hapus") .. " (" .. count .. ")")
btnEksporEks.setText(T("bagikan", "Ekspor") .. " (" .. count .. ")")
btnCadangSpkEks.setText(T("cadangkan_spk", "Cadang SPK") .. " (" .. count .. ")")
else
layoutAksiEks.setVisibility(8)
end
end

-- LOGIKA BARU: Pengetatan validasi folder tema suara
local function apakahFolderTema(dir)
local configF = File(dir.getAbsolutePath() .. "/config")
if not configF.exists() or not configF.isFile() then return false end

local anak = dir.listFiles()
if anak then
for i = 0, #anak - 1 do
if anak[i].isDirectory() then
local namaFolder = string.lower(anak[i].getName())
-- Jika ada folder SELAIN clock atau effect, fix BUKAN folder tema
if namaFolder ~= "clock" and namaFolder ~= "effect" then
return false
end
end
end
end
return true
end

local function refreshList(query)
-- PERBAIKAN BUG LUAADAPTER: Jangan gunakan listData = {}, gunakan table.remove agar referensi memori tidak putus
for i = #listData, 1, -1 do table.remove(listData, i) end

local q = tostring(query):lower()
for i = 1, #allItems do
local itemName = allItems[i].name
if q == "" or string.find(itemName:lower(), q, 1, true) then
local label = itemName
if allItems[i].isTheme then label = label .. " " .. T("label_tema", "[TEMA SUARA]") end

table.insert(listData, {
cbItem = {visibility = isSelectionMode and 0 or 8, checked = (selectedItems[allItems[i].path] == true)},
tvName = label,
_path = allItems[i].path,
_isTheme = allItems[i].isTheme,
_name = itemName
})
end
end
if not adapter then
adapter = LuaAdapter(service, listData, itemLayout)
lvEks.setAdapter(adapter)
else
adapter.notifyDataSetChanged()
end
end

local function loadDir(pathTarget)
currentPath = pathTarget
tvPathEks.setText(currentPath)
etCariEks.setText("")
allItems = {}

jalankanTaskLoading(T("memuat_file", "Memuat daftar folder..."), kerjaDaftarFolderTema, cjson.encode({ path = currentPath, isInternal = false }), function(res)
allItems = res
selectedItems = {}
refreshList("")
updateAksiEks()
end)
end

loadDir(currentPath)

etCariEks.addTextChangedListener(TextWatcher{ onTextChanged = function(c) refreshList(tostring(c)) end })

btnModePemilihanEks.onClick = function()
isSelectionMode = not isSelectionMode
if isSelectionMode then
btnModePemilihanEks.setText(T("batal_mode_pilih", "Batal Mode Pemilihan"))
btnPilihSemuaEks.setVisibility(0)
else
btnModePemilihanEks.setText(T("mode_pilih", "Aktifkan Mode Pemilihan"))
btnPilihSemuaEks.setVisibility(8)
selectedItems = {}
isAllSelected = false
btnPilihSemuaEks.setText(T("pilih_semua", "Pilih Semua"))
end
refreshList(tostring(etCariEks.getText()))
updateAksiEks()
end

btnPilihSemuaEks.onClick = function()
isAllSelected = not isAllSelected
selectedItems = {}
btnPilihSemuaEks.setText(isAllSelected and T("batal_pilih_semua", "Batal Pilih Semua") or T("pilih_semua", "Pilih Semua"))
for i = 1, #listData do
if listData[i]._isTheme then
if isAllSelected then
selectedItems[listData[i]._path] = true
listData[i].cbItem.checked = true
else
listData[i].cbItem.checked = false
end
end
end
adapter.notifyDataSetChanged()
updateAksiEks()
end

lvEks.onItemClick = function(l, v, p, id)
local item = listData[p+1]
if not item then return end -- Guard antisipasi crash

if isSelectionMode then
if not item._isTheme then
service.speak(T("hanya_tema_yang_bisa_dipilih", "Hanya folder tema yang bisa dipilih."))
return
end
if selectedItems[item._path] then
selectedItems[item._path] = nil
item.cbItem.checked = false
else
selectedItems[item._path] = true
item.cbItem.checked = true
end
adapter.notifyDataSetChanged()
updateAksiEks()
else
if item._isTheme then
local dImpor = UI_Dialog(item._name)
dImpor.setMessage(T("impor_tema_ini", "Apakah Anda ingin mengimpor tema ini ke dalam direktori Jieshuo?"))

dImpor.setButton(T("impor", "Impor"), function()
jalankanTaskLoading(nil, kerjaSalinFlat, cjson.encode({ { src = item._path, dst = basePath .. "/" .. item._name, hapusDulu = false } }), function() service.speak(T("sukses", "Berhasil diimpor!")) end)
end)

dImpor.setButton2(T("impor_terapkan", "Impor & Terapkan"), function()
jalankanTaskLoading(nil, kerjaSalinFlat, cjson.encode({ { src = item._path, dst = basePath .. "/" .. item._name, hapusDulu = false } }), function()
PreferenceManager.getDefaultSharedPreferences(service).edit().putString("sound_package", item._name).apply()
service.loadSoundPackage(item._name)
service.speak(item._name .. " " .. T("status_aktif", "Aktif"))
end)
end)

dImpor.setButton3(T("batal", "Batal"), nil)
dImpor.show()
else
-- Buka folder biasa dengan aman
loadDir(item._path)
end
end
end

lvEks.onItemLongClick = function(l, v, p, id)
if isSelectionMode then return true end
local item = listData[p+1]

if not item or not item._isTheme then return true end

local optDialog = UI_Dialog(item._name)
local options = {T("bagikan", "Bagikan (Ekspor SPK)"), T("cadangkan_spk", "Cadangkan Jadi SPK"), T("ganti_nama", "Ganti Nama"), T("hapus", "Hapus"), T("tutup", "Tutup")}
optDialog.setItems(options)

optDialog.setOnItemClickListener(function(al, av, ap, ai)
local action = options[ap + 1]
optDialog.dismiss()

if action == T("bagikan", "Bagikan (Ekspor SPK)") then
dialogEks.dismiss()
jalankanZipTask(T("membagikan", "Mengekspor tema..."), {{src = File(item._path).getAbsolutePath(), out = currentPath .. "/" .. item._name .. ".spk"}}, function(hasil)
if hasil and #hasil > 0 then pcall(function() bagikanBanyakFile(hasil) end) end
end)

elseif action == T("cadangkan_spk", "Cadangkan Jadi SPK") then
dialogEks.dismiss()
local spkDir = File("/storage/emulated/0/nadi cadangan SPK")
if not spkDir.exists() then spkDir.mkdirs() end
local srcFolder = File(item._path)
local suffixExt = ""
local adaClock = File(srcFolder.getAbsolutePath() .. "/clock").exists()
local adaEfek = File(srcFolder.getAbsolutePath() .. "/effect").exists()
if adaClock and adaEfek then suffixExt = "_clock_effect"
elseif adaClock then suffixExt = "_clock"
elseif adaEfek then suffixExt = "_effect" end
local middleFmt = ""
if PreferenceManager.getDefaultSharedPreferences(service).getBoolean("use_jieshuo_export_format", false) then
middleFmt = "_" .. os.date("%Y%m%d%H%M%S")
end
local baseSpkName = item._name .. middleFmt .. suffixExt .. ".spk"
local finalSpkName = baseSpkName
if middleFmt == "" then finalSpkName = DapatkanNamaUnik(spkDir.getAbsolutePath(), baseSpkName) end
local zipFilePath = spkDir.getAbsolutePath() .. "/" .. finalSpkName

jalankanZipTask(T("sedang_memproses", "Sedang memproses..."), {{src = srcFolder.getAbsolutePath(), out = zipFilePath}}, function()
service.speak("Berhasil dicadangkan ke " .. finalSpkName)
muatUlangBahasaDanMenu()
end)

elseif action == T("ganti_nama", "Ganti Nama") then
showInputDialog(T("ganti_nama", "Ganti Nama"), nil, item._name, function(newName)
if newName ~= "" and newName ~= item._name then
local targetBaru = File(currentPath .. "/" .. newName)
if targetBaru.exists() then
service.speak(T("nama_telah_digunakan", "Nama tersebut sudah digunakan."))
return false
else
jalankanTaskLoading(nil, kerjaRenamePath, cjson.encode({ { src = item._path, dst = targetBaru.getAbsolutePath() } }), function()
loadDir(currentPath)
end)
return true
end
end
return true
end)

elseif action == T("hapus", "Hapus") then
showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("hapus", "Hapus") .. " " .. item._name .. "?", function()
jalankanTaskLoading(nil, kerjaHapusPath, cjson.encode({ File(item._path).getAbsolutePath() }), function() loadDir(currentPath) end)
end)
end
end)
optDialog.show()
return true
end

AksiDex.pasang(lvEks, {
labelKlik = function(p)
local it = listData[p+1]
if not it then return nil end
return it._isTheme and T("aksi_impor_tema", "Impor tema") or T("aksi_buka_folder", "Buka folder")
end,
modePilih = function() return isSelectionMode end
})

btnEksporEks.onClick = function()
local toProcess = {}
for k, v in pairs(selectedItems) do table.insert(toProcess, k) end

dialogEks.dismiss()
local itemsZip = {}
for i = 1, #toProcess do
local srcFolder = File(toProcess[i])
table.insert(itemsZip, {src = srcFolder.getAbsolutePath(), out = currentPath .. "/" .. srcFolder.getName() .. ".spk"})
end
jalankanZipTask("Mengekspor " .. #toProcess .. " tema...", itemsZip, function()
service.speak("Berhasil diekspor menjadi SPK di folder ini.")
muatUlangBahasaDanMenu()
end)
end

btnCadangSpkEks.onClick = function()
local toProcess = {}
for k, v in pairs(selectedItems) do table.insert(toProcess, k) end

dialogEks.dismiss()
local itemsZip = {}
local spkDir = File("/storage/emulated/0/nadi cadangan SPK")
if not spkDir.exists() then spkDir.mkdirs() end
for i = 1, #toProcess do
local srcFolder = File(toProcess[i])
local suffixExt = ""
local adaClock = File(srcFolder.getAbsolutePath() .. "/clock").exists()
local adaEfek = File(srcFolder.getAbsolutePath() .. "/effect").exists()
if adaClock and adaEfek then suffixExt = "_clock_effect"
elseif adaClock then suffixExt = "_clock"
elseif adaEfek then suffixExt = "_effect" end
local middleFmt = ""
if PreferenceManager.getDefaultSharedPreferences(service).getBoolean("use_jieshuo_export_format", false) then
middleFmt = "_" .. os.date("%Y%m%d%H%M%S")
end
local baseSpkName = srcFolder.getName() .. middleFmt .. suffixExt .. ".spk"
local finalSpkName = baseSpkName
if middleFmt == "" then finalSpkName = DapatkanNamaUnik(spkDir.getAbsolutePath(), baseSpkName) end
local zipFilePath = spkDir.getAbsolutePath() .. "/" .. finalSpkName
table.insert(itemsZip, {src = srcFolder.getAbsolutePath(), out = zipFilePath})
end
jalankanZipTask("Mencadangkan " .. #toProcess .. " tema ke SPK...", itemsZip, function()
service.speak("Semua tema berhasil dicadangkan ke SPK.")
muatUlangBahasaDanMenu()
end)
end

btnHapusEks.onClick = function()
local toProcess = {}
for k, v in pairs(selectedItems) do table.insert(toProcess, k) end

showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("hapus", "Hapus") .. " " .. #toProcess .. " tema?", function()
jalankanTaskLoading(nil, kerjaHapusPath, cjson.encode(toProcess), function()
isSelectionMode = false
btnModePemilihanEks.setText(T("mode_pilih", "Aktifkan Mode Pemilihan"))
btnPilihSemuaEks.setVisibility(8)
selectedItems = {}
loadDir(currentPath)
end)
end)
end

dialogEks.setOnKeyListener(function(dialog, keyCode, event)
if keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
if currentPath ~= "/storage/emulated/0" and currentPath ~= "/" then
local parent = File(currentPath).getParent()
if parent then loadDir(parent); return true end
else
dialogEks.dismiss()
muatUlangBahasaDanMenu()
return true
end
end
return false
end)

btnTutupEks.onClick = function() dialogEks.dismiss(); muatUlangBahasaDanMenu() end
dialogEks.setOnCancelListener(function() muatUlangBahasaDanMenu() end)

dialogEks.show()
end

local function BukaMenuHapusKomponen()
local dKomp = UI_Dialog(T("pilih_komponen_dihapus", "Pilih Komponen yang Dihapus"))
local layKomp = UI_Layout(
UI_Tombol("btnHapusKompClock", T("folder_jam_clock", "Folder Jam (Clock)")),
UI_Tombol("btnHapusKompEfek", T("folder_efek_effect", "Folder Efek (Effect)")),
UI_Tombol("btnBatalKomp", T("kembali", "Kembali"))
)
dKomp.setView(loadlayout(layKomp))

local function BukaPemilihSumberHapus(tipeKomponen)
local dSumber = UI_Dialog(T("pilih_sumber_tema", "Pilih Sumber Tema"))
local laySumber = UI_Layout(
UI_Tombol("btnSumberInternalHK", T("sumber_internal", "Dari Tema Jieshuo (Internal)")),
UI_Tombol("btnSumberEksternalHK", T("sumber_eksternal", "Dari Folder Eksternal")),
UI_Tombol("btnBatalSumberHK", T("kembali", "Kembali"))
)
dSumber.setView(loadlayout(laySumber))

local function TampilkanPickerHapus(isInternal)
local currentPath = isInternal and basePath or "/storage/emulated/0"
local namaKompUI = (tipeKomponen == "clock") and T("komp_clock", "Jam (Clock)") or T("komp_effect", "Efek (Effect)")
local judul = T("hapus_komp_massal", "Hapus Massal") .. " - " .. namaKompUI
local dPicker = UI_Dialog(judul)

local layPicker = UI_Layout(
not isInternal and {TextView, id="tvPathHK", text=currentPath, padding="10dp", layout_marginBottom="8dp", textColor="0xFF4CAF50"} or {LinearLayout, visibility=8},
UI_Input("etCariHK", T("cari_tema", "Cari tema...")),
{LinearLayout, orientation="horizontal", layout_width="fill", layout_marginBottom="8dp",
UI_Tombol_H("btnPilihSemuaHK", T("pilih_semua", "Pilih Semua")),
UI_Tombol_H("btnBatalPilihHK", T("batal_pilih", "Batal Pilih"))
},
UI_Daftar("lvHK"),
{LinearLayout, orientation="horizontal", layout_width="fill",
UI_Tombol_H("btnTutupHK", T("kembali", "Kembali")),
UI_Tombol_H("btnLanjutHapus", T("hapus_terpilih", "Hapus Terpilih (0)"))
}
)
dPicker.setView(loadlayout(layPicker))

local itemLayout = UI_ItemBaris("cbItem", "tvName")
local allItems, listData, selectedItems = {}, {}, {}
local adapter = nil

local function apakahFolderTemaKetat(dir)
local configF = File(dir.getAbsolutePath() .. "/config")
if not configF.exists() or not configF.isFile() then return false end
local anak = dir.listFiles()
if anak then
for i = 0, #anak - 1 do
if anak[i].isDirectory() then
local namaFolder = string.lower(anak[i].getName())
if namaFolder ~= "clock" and namaFolder ~= "effect" then return false end
end
end
end
return true
end

local function updateBtnHapus()
local count = 0
for k, v in pairs(selectedItems) do count = count + 1 end
btnLanjutHapus.setText(T("hapus_terpilih", "Hapus Terpilih") .. " (" .. count .. ")")
end

local function refreshList(query)
for i = #listData, 1, -1 do table.remove(listData, i) end
local q = tostring(query):lower()
for i = 1, #allItems do
local itemName = allItems[i].name
if q == "" or string.find(itemName:lower(), q, 1, true) then
local label = itemName
if not isInternal and allItems[i].isTheme then label = label .. " " .. T("label_tema", "[TEMA SUARA]") end
table.insert(listData, {
cbItem = {visibility = allItems[i].isTheme and 0 or 8, checked = (selectedItems[allItems[i].path] == true)},
tvName = label, _path = allItems[i].path, _isTheme = allItems[i].isTheme, _name = itemName
})
end
end
if not adapter then adapter = LuaAdapter(service, listData, itemLayout) lvHK.setAdapter(adapter)
else adapter.notifyDataSetChanged() end
end

local function loadDir(pathTarget)
currentPath = pathTarget
if tvPathHK then tvPathHK.setText(currentPath) end
etCariHK.setText("")
allItems = {}

jalankanTaskLoading(T("memuat_file", "Memuat daftar folder..."), kerjaDaftarFolderTema, cjson.encode({ path = currentPath, isInternal = (isInternal and true or false), tipeKomponen = tipeKomponen }), function(res)
allItems = res
selectedItems = {}
refreshList("")
updateBtnHapus()
end)
end

loadDir(currentPath)
etCariHK.addTextChangedListener(TextWatcher{ onTextChanged = function(c) refreshList(tostring(c)) end })

btnPilihSemuaHK.onClick = function()
for i = 1, #listData do
if listData[i]._isTheme then
selectedItems[listData[i]._path] = true
listData[i].cbItem.checked = true
end
end
adapter.notifyDataSetChanged()
updateBtnHapus()
end

btnBatalPilihHK.onClick = function()
selectedItems = {}
for i = 1, #listData do listData[i].cbItem.checked = false end
adapter.notifyDataSetChanged()
updateBtnHapus()
end

lvHK.onItemClick = function(l, v, p, id)
local item = listData[p+1]
if not item then return end
if item._isTheme then
if selectedItems[item._path] then selectedItems[item._path] = nil item.cbItem.checked = false
else selectedItems[item._path] = true item.cbItem.checked = true end
adapter.notifyDataSetChanged()
updateBtnHapus()
else
loadDir(item._path)
end
end

dPicker.setOnKeyListener(function(dialog, keyCode, event)
if not isInternal and keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
if currentPath ~= "/storage/emulated/0" and currentPath ~= "/" then
local parent = File(currentPath).getParent()
if parent then loadDir(parent); return true end
else
dPicker.dismiss() BukaPemilihSumberHapus(tipeKomponen) return true
end
end
return false
end)

btnTutupHK.onClick = function() dPicker.dismiss() BukaPemilihSumberHapus(tipeKomponen) end
dPicker.setOnCancelListener(function() BukaPemilihSumberHapus(tipeKomponen) end)

btnLanjutHapus.onClick = function()
local toProcess = {}
for k, v in pairs(selectedItems) do table.insert(toProcess, k) end
if #toProcess == 0 then service.speak(T("pilih_minimal_satu", "Pilih minimal satu tema!")); return end

showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("yakin_hapus_komponen", "Yakin ingin menghapus komponen ini dari ") .. #toProcess .. " " .. T("tema_tanya", "tema?"), function()
local daftarKomponen = {}
for i = 1, #toProcess do table.insert(daftarKomponen, toProcess[i] .. "/" .. tipeKomponen) end
jalankanTaskLoading(nil, kerjaHapusPath, cjson.encode(daftarKomponen), function()
service.speak(T("berhasil_dihapus", "Berhasil dihapus."))
selectedItems = {}
loadDir(currentPath)
end)
end)
end

dPicker.show()
end

btnSumberInternalHK.onClick = function() dSumber.dismiss() TampilkanPickerHapus(true) end
btnSumberEksternalHK.onClick = function() dSumber.dismiss() TampilkanPickerHapus(false) end
btnBatalSumberHK.onClick = function() dSumber.dismiss() BukaMenuHapusKomponen() end
dSumber.setOnCancelListener(function() BukaMenuHapusKomponen() end)
dSumber.show()
end

btnHapusKompClock.onClick = function() dKomp.dismiss() BukaPemilihSumberHapus("clock") end
btnHapusKompEfek.onClick = function() dKomp.dismiss() BukaPemilihSumberHapus("effect") end
btnBatalKomp.onClick = function() dKomp.dismiss() muatUlangBahasaDanMenu() end
dKomp.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dKomp.show()
end

-- ==========================================================================
-- HAPUS EVENT SUARA TERTENTU
-- Alur: pilih event (centang banyak) -> pilih tema (centang banyak / semua) -> konfirmasi -> hapus.
-- Hasilnya event kembali ke kondisi paling awal: kunci event dibuang dari config (tanpa keterangan
-- aksi), dan file audio-nya ikut dihapus apa pun formatnya. Tidak ada batas limit.
-- Tabel global supaya tidak menambah jumlah variabel lokal pada skrip utama.
-- ==========================================================================
HapusEvent = {}

-- Dialog 1: daftar centang event
function HapusEvent.dialogEvent(st)
local data = {}
local jumlahCentang = 0
for i = 1, #mappingTema do
local key = mappingTema[i][2]
local on = (st.event[key] == true)
if on then jumlahCentang = jumlahCentang + 1 end
table.insert(data, { cbItem = { checked = on }, tvName = dapatkanString("str_event_" .. key, mappingTema[i][1]), key = key })
end
local dl = UI_Dialog(T("hapus_event_judul", "Hapus Event Suara Tertentu"))
local lay = UI_Layout(
UI_Teks(T("hapus_event_info", "Centang event yang audionya ingin dihapus. Nama dan format file audio ikut terhapus.")),
UI_Tombol("btnSemuaHE", (jumlahCentang == #data) and T("batal_pilih_semua", "Batal Pilih Semua") or T("pilih_semua", "Pilih Semua")),
UI_Daftar("lvEventHE")
)
dl.setView(loadlayout(lay))
local lv, btnSemua = lvEventHE, btnSemuaHE
local adapter = LuaAdapter(service, data, UI_ItemBaris("cbItem", "tvName"))
lv.setAdapter(adapter)

-- Hanya membalik centang lalu memberi tahu adapter, jadi daftar tidak loncat ke atas
lv.onItemClick = function(l, v, p, id)
local it = data[p + 1]
if it then
it.cbItem.checked = not it.cbItem.checked
adapter.notifyDataSetChanged()
end
end

btnSemua.onClick = function()
local semua = true
for i = 1, #data do if not data[i].cbItem.checked then semua = false; break end end
for i = 1, #data do data[i].cbItem.checked = not semua end
btnSemua.setText(semua and T("pilih_semua", "Pilih Semua") or T("batal_pilih_semua", "Batal Pilih Semua"))
adapter.notifyDataSetChanged()
end

dl.setButton(T("hapus_event_lanjut", "Lanjut"), function()
local pilih, n = {}, 0
for i = 1, #data do
if data[i].cbItem.checked then pilih[data[i].key] = true; n = n + 1 end
end
st.event = pilih
if n == 0 then
service.speak(T("hapus_event_kosong_event", "Pilih dulu minimal satu event."))
HapusEvent.dialogEvent(st)
return
end
HapusEvent.dialogTema(st)
end)
dl.setButton2(T("batal", "Batal"), function() muatUlangBahasaDanMenu() end)
dl.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dl.setCancelable(false)
dl.show()
end

-- Dialog 2: daftar centang tema (ada pencarian dan Pilih Semua)
function HapusEvent.dialogTema(st)
local semuaTema = {}
local dir = File(basePath)
if dir.exists() and dir.isDirectory() then
local fs = dir.listFiles()
if fs then
for i = 0, #fs - 1 do
if fs[i].isDirectory() and File(fs[i].getAbsolutePath() .. "/config").exists() then
table.insert(semuaTema, tostring(fs[i].getName()))
end
end
end
end
table.sort(semuaTema, function(a, b) return string.lower(a) < string.lower(b) end)
if #semuaTema == 0 then
service.speak(T("hapus_event_tidak_ada_tema", "Belum ada tema suara."))
muatUlangBahasaDanMenu()
return
end

local dl = UI_Dialog(T("hapus_event_pilih_tema", "Pilih Tema Suara"))
local lay = UI_Layout(
UI_Input("etCariHT", T("cari_tema", "Cari tema...")),
UI_Tombol("btnSemuaHT", T("pilih_semua", "Pilih Semua")),
UI_Daftar("lvTemaHE")
)
dl.setView(loadlayout(lay))
local lv, btnSemua, etCari = lvTemaHE, btnSemuaHT, etCariHT
local data, adapter = {}, nil

local function perbaruiLabel()
local semua = (#data > 0)
for i = 1, #data do if not data[i].cbItem.checked then semua = false; break end end
btnSemua.setText(semua and T("batal_pilih_semua", "Batal Pilih Semua") or T("pilih_semua", "Pilih Semua"))
end

local function bangun(q)
q = string.lower(q or "")
data = {}
for i = 1, #semuaTema do
local nm = semuaTema[i]
if q == "" or string.find(string.lower(nm), q, 1, true) then
table.insert(data, { cbItem = { checked = (st.tema[nm] == true) }, tvName = nm, nama = nm })
end
end
adapter = LuaAdapter(service, data, UI_ItemBaris("cbItem", "tvName"))
lv.setAdapter(adapter)
perbaruiLabel()
end
bangun("")

lv.onItemClick = function(l, v, p, id)
local it = data[p + 1]
if it then
it.cbItem.checked = not it.cbItem.checked
st.tema[it.nama] = it.cbItem.checked and true or nil
adapter.notifyDataSetChanged()
perbaruiLabel()
end
end

-- Pilih Semua berlaku untuk tema yang sedang tampil (sesuai pencarian)
btnSemua.onClick = function()
local semua = (#data > 0)
for i = 1, #data do if not data[i].cbItem.checked then semua = false; break end end
for i = 1, #data do
data[i].cbItem.checked = not semua
st.tema[data[i].nama] = (not semua) and true or nil
end
adapter.notifyDataSetChanged()
perbaruiLabel()
end

etCari.addTextChangedListener(TextWatcher{ onTextChanged = function(c, start, before, count) bangun(tostring(c)) end })

dl.setButton(T("hapus", "Hapus"), function()
local n = 0
for _ in pairs(st.tema) do n = n + 1 end
if n == 0 then
service.speak(T("hapus_event_kosong_tema", "Pilih dulu minimal satu tema."))
HapusEvent.dialogTema(st)
return
end
local ne = 0
for _ in pairs(st.event) do ne = ne + 1 end
local pesan = T("hapus_event_tanya", "Hapus [E] event beserta file audionya dari [T] tema? Event akan kembali seperti belum diatur. Ini tidak bisa dibatalkan.")
pesan = string.gsub(pesan, "%[E%]", tostring(ne))
pesan = string.gsub(pesan, "%[T%]", tostring(n))
showConfirmDialog(T("konfirmasi", "Konfirmasi"), pesan, function()
HapusEvent.jalankan(st)
end, function()
HapusEvent.dialogTema(st)
end)
end)
dl.setButton2(T("kembali", "Kembali"), function() HapusEvent.dialogEvent(st) end)
dl.setOnCancelListener(function() HapusEvent.dialogEvent(st) end)
dl.setCancelable(false)
dl.show()
end

-- Proses hapus di thread terpisah
function HapusEvent.jalankan(st)
local daftarKey, daftarTema = {}, {}
for k in pairs(st.event) do table.insert(daftarKey, k) end
for k in pairs(st.tema) do table.insert(daftarTema, k) end
local base = basePath
jalankanDenganLoading(nil, function()
local totalEvent, totalFile = 0, 0
for t = 1, #daftarTema do
local tema = daftarTema[t]
local cfg = base .. "/" .. tema .. "/config"
local obj = bacaJson(cfg)
local kandidat, berubah = {}, false
for i = 1, #daftarKey do
local key = daftarKey[i]
local v = obj[key]
if v ~= nil then
if type(v) == "string" and v ~= "value_default" and v ~= "value_none" and v ~= "" then kandidat[v] = true end
obj[key] = nil -- kunci dibuang = event kembali ke kondisi paling awal
berubah = true
totalEvent = totalEvent + 1
end
end
if berubah then
-- File yang masih dipakai event lain (tidak ikut dipilih) jangan ikut terhapus
local masihDipakai = {}
for _, v in pairs(obj) do
if type(v) == "string" then masihDipakai[string.lower(v)] = true end
end
for nama in pairs(kandidat) do
-- Tolak nama berisi "..", "/" atau "\" supaya config tema orang lain tidak bisa menghapus file di luar folder tema
local aman = not (string.find(nama, "..", 1, true) or string.find(nama, "/", 1, true) or string.find(nama, "\\", 1, true))
if aman and not masihDipakai[string.lower(nama)] then
local f = File(base .. "/" .. tema .. "/" .. nama)
if f.exists() and f.isFile() and f.delete() then totalFile = totalFile + 1 end
end
end
simpanJson(cfg, obj)
end
end
return { event = totalEvent, file = totalFile }
end, function(hasil)
local prefs = PreferenceManager.getDefaultSharedPreferences(service)
local aktif = prefs.getString("sound_package", "")
for t = 1, #daftarTema do
if daftarTema[t] == aktif then pcall(function() service.loadSoundPackage(aktif) end) end
end
if type(hasil) == "table" then
local pesan = T("hapus_event_selesai", "Selesai. [E] event dihapus dari [T] tema, [F] file audio ikut dihapus.")
pesan = string.gsub(pesan, "%[E%]", tostring(hasil.event))
pesan = string.gsub(pesan, "%[T%]", tostring(#daftarTema))
pesan = string.gsub(pesan, "%[F%]", tostring(hasil.file))
service.speak(pesan)
else
service.speak(T("hapus_event_gagal", "Gagal menghapus event."))
end
muatUlangBahasaDanMenu()
end)
end

function HapusEvent.mulai()
folderSuara = dapatkanString("nama_folder_suara", "Suara")
basePath = jieshuoPath .. "/" .. folderSuara
HapusEvent.dialogEvent({ event = {}, tema = {} })
end

-- ==========================================================================
-- TAMBAH AUDIO DI BEBERAPA TEMA SUARA
-- Alur: pilih audio (ketuk = langsung terpilih, bukan centang) -> pilih tema (centang banyak)
--       -> pilih event (centang banyak) -> "Terapkan dan Tutup" atau "Cari Audio Lagi".
-- Audio disalin ke tiap tema terpilih dengan nama yang sama, lalu event terpilih di config
-- tiap tema diarahkan ke nama audio itu. Tidak ada batas limit.
-- Tabel global supaya tidak menambah jumlah variabel lokal pada skrip utama.
-- ==========================================================================
TambahAudio = {}

-- Langkah 1: pemilih audio bawaan (ada pencarian, fokus/sentuh memutar contoh), mode satu pilihan
function TambahAudio.pilihAudio(st)
BukaPickerKustom({
judul = T("tambah_audio_pilih", "Pilih Audio"),
pathAwal = st.pathAwal or "/storage/emulated/0",
modeMulti = false,
hentikanAudioGlobal = true,
petakanAudioAktif = true,
filterFile = function(f) return isAudioFile(f) end,
onPilihSingle = function(pathDipilih, namaFile, pickerDialog, restoreRadar)
restoreRadar()
pickerDialog.dismiss()
local fp = File(tostring(pathDipilih))
st.pathAwal = tostring(fp.getParent() or "/storage/emulated/0")
st.cur = { path = tostring(pathDipilih), nama = tostring(fp.getName()), tema = {}, event = {} }
TambahAudio.dialogTema(st)
end,
onBatal = function()
if #st.tugas > 0 then TambahAudio.dialogAkhir(st) else muatUlangBahasaDanMenu() end
end
})
end

-- Langkah 2: daftar centang tema (ada pencarian dan Pilih Semua)
function TambahAudio.dialogTema(st)
local semuaTema = {}
local dir = File(basePath)
if dir.exists() and dir.isDirectory() then
local fs = dir.listFiles()
if fs then
for i = 0, #fs - 1 do
if fs[i].isDirectory() and File(fs[i].getAbsolutePath() .. "/config").exists() then
table.insert(semuaTema, tostring(fs[i].getName()))
end
end
end
end
table.sort(semuaTema, function(a, b) return string.lower(a) < string.lower(b) end)
if #semuaTema == 0 then
service.speak(T("tambah_audio_tidak_ada_tema", "Belum ada tema suara."))
muatUlangBahasaDanMenu()
return
end

local dl = UI_Dialog(T("tambah_audio_pilih_tema", "Pilih Tema Suara") .. " - " .. st.cur.nama)
local lay = UI_Layout(
UI_Input("etCariTA", T("cari_tema", "Cari tema...")),
UI_Tombol("btnSemuaTA", T("pilih_semua", "Pilih Semua")),
UI_Daftar("lvTemaTA")
)
dl.setView(loadlayout(lay))
local lv, btnSemua, etCari = lvTemaTA, btnSemuaTA, etCariTA
local data, adapter = {}, nil

local function perbaruiLabel()
local semua = (#data > 0)
for i = 1, #data do if not data[i].cbItem.checked then semua = false; break end end
btnSemua.setText(semua and T("batal_pilih_semua", "Batal Pilih Semua") or T("pilih_semua", "Pilih Semua"))
end

local function bangun(q)
q = string.lower(q or "")
data = {}
for i = 1, #semuaTema do
local nm = semuaTema[i]
if q == "" or string.find(string.lower(nm), q, 1, true) then
table.insert(data, { cbItem = { checked = (st.cur.tema[nm] == true) }, tvName = nm, nama = nm })
end
end
adapter = LuaAdapter(service, data, UI_ItemBaris("cbItem", "tvName"))
lv.setAdapter(adapter)
perbaruiLabel()
end
bangun("")

lv.onItemClick = function(l, v, p, id)
local it = data[p + 1]
if it then
it.cbItem.checked = not it.cbItem.checked
st.cur.tema[it.nama] = it.cbItem.checked and true or nil
adapter.notifyDataSetChanged()
perbaruiLabel()
end
end

-- Pilih Semua berlaku untuk tema yang sedang tampil (sesuai pencarian)
btnSemua.onClick = function()
local semua = (#data > 0)
for i = 1, #data do if not data[i].cbItem.checked then semua = false; break end end
for i = 1, #data do
data[i].cbItem.checked = not semua
st.cur.tema[data[i].nama] = (not semua) and true or nil
end
adapter.notifyDataSetChanged()
perbaruiLabel()
end

etCari.addTextChangedListener(TextWatcher{ onTextChanged = function(c, start, before, count) bangun(tostring(c)) end })

dl.setButton(T("tambah_audio_lanjut", "Lanjut"), function()
local n = 0
for _ in pairs(st.cur.tema) do n = n + 1 end
if n == 0 then
service.speak(T("tambah_audio_kosong_tema", "Pilih dulu minimal satu tema."))
TambahAudio.dialogTema(st)
return
end
TambahAudio.dialogEvent(st)
end)
dl.setButton2(T("kembali", "Kembali"), function() TambahAudio.pilihAudio(st) end)
dl.setOnCancelListener(function() TambahAudio.pilihAudio(st) end)
dl.setCancelable(false)
dl.show()
end

-- Langkah 3: daftar centang event (audio ini dipakai di event mana saja)
function TambahAudio.dialogEvent(st)
local data = {}
local jumlahCentang = 0
for i = 1, #mappingTema do
local key = mappingTema[i][2]
local on = (st.cur.event[key] == true)
if on then jumlahCentang = jumlahCentang + 1 end
table.insert(data, { cbItem = { checked = on }, tvName = dapatkanString("str_event_" .. key, mappingTema[i][1]), key = key })
end
local dl = UI_Dialog(T("tambah_audio_pilih_event", "Pilih Event") .. " - " .. st.cur.nama)
local lay = UI_Layout(
UI_Teks(T("tambah_audio_info_event", "Centang event yang akan memakai audio ini. Audio disalin ke tema yang dipilih dengan nama yang sama.")),
UI_Tombol("btnSemuaTE", (jumlahCentang == #data) and T("batal_pilih_semua", "Batal Pilih Semua") or T("pilih_semua", "Pilih Semua")),
UI_Daftar("lvEventTA")
)
dl.setView(loadlayout(lay))
local lv, btnSemua = lvEventTA, btnSemuaTE
local adapter = LuaAdapter(service, data, UI_ItemBaris("cbItem", "tvName"))
lv.setAdapter(adapter)

lv.onItemClick = function(l, v, p, id)
local it = data[p + 1]
if it then
it.cbItem.checked = not it.cbItem.checked
adapter.notifyDataSetChanged()
end
end

btnSemua.onClick = function()
local semua = true
for i = 1, #data do if not data[i].cbItem.checked then semua = false; break end end
for i = 1, #data do data[i].cbItem.checked = not semua end
btnSemua.setText(semua and T("pilih_semua", "Pilih Semua") or T("batal_pilih_semua", "Batal Pilih Semua"))
adapter.notifyDataSetChanged()
end

dl.setButton(T("tambah_audio_lanjut", "Lanjut"), function()
local pilih, n = {}, 0
for i = 1, #data do
if data[i].cbItem.checked then pilih[data[i].key] = true; n = n + 1 end
end
st.cur.event = pilih
if n == 0 then
service.speak(T("tambah_audio_kosong_event", "Pilih dulu minimal satu event."))
TambahAudio.dialogEvent(st)
return
end
-- pasangan audio + tema + event ini masuk antrean, belum ditulis ke tema sebelum "Terapkan"
table.insert(st.tugas, st.cur)
st.cur = nil
TambahAudio.dialogAkhir(st)
end)
dl.setButton2(T("kembali", "Kembali"), function() TambahAudio.dialogTema(st) end)
dl.setOnCancelListener(function() TambahAudio.dialogTema(st) end)
dl.setCancelable(false)
dl.show()
end

-- Langkah 4: terapkan sekarang, atau cari audio lain untuk diterapkan lagi
function TambahAudio.dialogAkhir(st)
local pesan = T("tambah_audio_akhir_pesan", "[N] audio sudah dipilih. Terapkan sekarang, atau cari audio lain untuk diterapkan lagi?")
pesan = string.gsub(pesan, "%[N%]", tostring(#st.tugas))
local dl = UI_Dialog(T("tambah_audio_akhir_judul", "Audio Siap Diterapkan"))
dl.setMessage(pesan)
dl.setButton(T("tambah_audio_terapkan_tutup", "Terapkan dan Tutup"), function() TambahAudio.jalankan(st) end)
dl.setButton2(T("tambah_audio_cari_lagi", "Cari Audio Lagi"), function() TambahAudio.pilihAudio(st) end)
dl.setButton3(T("batal", "Batal"), function() muatUlangBahasaDanMenu() end)
dl.setCancelable(false)
dl.show()
end

-- Proses salin + atur config di thread terpisah
function TambahAudio.jalankan(st)
local tugas = st.tugas
local base = basePath
jalankanDenganLoading(nil, function()
local hasil = { audio = 0, event = 0, gagal = 0 }
local cfgCache, temaSentuh = {}, {}
for ti = 1, #tugas do
local tg = tugas[ti]
-- Tolak nama berisi "..", "/" atau "\" supaya penyalinan tidak bisa keluar dari folder tema
local aman = not (string.find(tg.nama, "..", 1, true) or string.find(tg.nama, "/", 1, true) or string.find(tg.nama, "\\", 1, true))
if aman then
for nm in pairs(tg.tema) do
local dirTema = File(base .. "/" .. nm)
if dirTema.isDirectory() then
local src = File(tg.path)
local dst = File(base .. "/" .. nm .. "/" .. tg.nama)
local ok = true
-- Sama jalur = sudah di dalam tema itu; sama nama dan ukuran = dianggap audio yang sama, tidak disalin ulang
local samaBerkas = (src.getAbsolutePath() == dst.getAbsolutePath()) or (dst.exists() and dst.length() == src.length())
if not samaBerkas then
ok = pcall(function()
local fis = FileInputStream(src)
local fos = FileOutputStream(dst)
local buffer = byte[8192]
local len = fis.read(buffer)
while len ~= -1 do
fos.write(buffer, 0, len)
len = fis.read(buffer)
end
fos.flush()
fos.close()
fis.close()
end)
end
if ok then
cfgCache[nm] = cfgCache[nm] or bacaJson(base .. "/" .. nm .. "/config")
for key in pairs(tg.event) do
cfgCache[nm][key] = tg.nama
hasil.event = hasil.event + 1
end
temaSentuh[nm] = true
hasil.audio = hasil.audio + 1
else
hasil.gagal = hasil.gagal + 1
end
end
end
else
hasil.gagal = hasil.gagal + 1
end
end
local jumlahTema = 0
for nm, obj in pairs(cfgCache) do
simpanJson(base .. "/" .. nm .. "/config", obj)
jumlahTema = jumlahTema + 1
end
hasil.tema = jumlahTema
hasil.daftarTema = temaSentuh
return hasil
end, function(hasil)
if type(hasil) == "table" then
local prefs = PreferenceManager.getDefaultSharedPreferences(service)
local aktif = prefs.getString("sound_package", "")
if hasil.daftarTema and hasil.daftarTema[aktif] then pcall(function() service.loadSoundPackage(aktif) end) end
local pesan = T("tambah_audio_selesai", "Selesai. [A] audio diterapkan ke [T] tema, [E] event diatur.")
pesan = string.gsub(pesan, "%[A%]", tostring(hasil.audio))
pesan = string.gsub(pesan, "%[T%]", tostring(hasil.tema))
pesan = string.gsub(pesan, "%[E%]", tostring(hasil.event))
if hasil.gagal > 0 then
pesan = pesan .. " " .. string.gsub(T("tambah_audio_selesai_gagal", "[G] penyalinan gagal."), "%[G%]", tostring(hasil.gagal))
end
service.speak(pesan)
else
service.speak(T("tambah_audio_gagal", "Gagal menerapkan audio."))
end
muatUlangBahasaDanMenu()
end)
end

function TambahAudio.mulai()
folderSuara = dapatkanString("nama_folder_suara", "Suara")
basePath = jieshuoPath .. "/" .. folderSuara
TambahAudio.pilihAudio({ tugas = {} })
end

muatUlangBahasaDanMenu = function()
if ProgresJam then ProgresJam.selesai() end
btnPeriksaPembaruan = nil
btnKlaimJatah = nil
btnPesanDev = nil
local currLang = dapatkanString("app_language", "indonesia")
langData = bacaJson(langDir .. currLang .. ".json")

if dialogUtama then dialogUtama.dismiss() end

dialogUtama = UI_Dialog(T("menu_utama", "Pembuat Tema Suara Ultimate"))
local curTema = PreferenceManager.getDefaultSharedPreferences(service).getString("sound_package", "")
if curTema == "" then curTema = T("standar", "Standar") end
local layoutUtama = UI_Layout(
UI_Tombol("btnBahasaUtama", T("ganti_bahasa", "Ganti Bahasa")),
UI_Tombol("btnPengaturanUtama", T("pengaturan", "Pengaturan")),
UI_Tombol("btnTemaSaatIniUtama", T("edit_tema_saat_ini", "Edit tema suara saat ini: ") .. curTema),
UI_Tombol("btnEditUtama", T("edit_tema", "Edit Tema Suara")),
UI_Tombol("btnBuatJam", T("buat_jam_utama", "Buat Jam Bicara")),
UI_Tombol("btnBuatEfek", T("buat_efek", "Buat Efek")),
UI_Tombol("btnHapusKomponen", T("hapus_komponen", "Hapus Komponen Tema (Clock/Efek)")),
UI_Tombol("btnHapusEventUtama", T("hapus_event_tombol", "Hapus Event Suara Tertentu")),
UI_Tombol("btnTambahAudioBanyak", T("tambah_audio_tombol", "Tambah Audio di Beberapa Tema Suara")),
UI_Tombol("btnDemoUtama", T("buat_demo", "Buat Tema Suara Demo")),
UI_Tombol("btnDemoInstanUtama", T("buat_demo_instan", "Buat Demo Instan")),
UI_Tombol("btnImporSPKUtama", T("impor_spk", "Impor File SPK")),
UI_Tombol("btnEksternalUtama", T("kelola_tema_eksternal", "Manajer Tema Eksternal")),
UI_Tombol("btnDaftarKode", T("daftar_kode_suara", "Daftar Kode Suara Tema")),
UI_Tombol("btnPencadanganUtama", T("menu_pencadangan", "Menu Pencadangan")),
UI_Tombol("btnKomunitasUtama", T("komunitas_tema", "Komunitas Tema Suara")),
UI_Tombol("btnPanduanUtama", T("panduan_tombol", "Panduan Penggunaan")),
UI_Tombol("btnPremiumUtama", T("menu_premium", "Tingkatkan ke Premium")),
UI_Tombol("btnTentangUtama", T("tentang", "Tentang")),
UI_Tombol("btnPeriksaPembaruan", T("periksa_pembaruan", "Periksa Pembaruan")),
JATAH.perluTombol() and UI_Tombol("btnKlaimJatah", T("klaim_jatah", "Klaim Jatah")) or {LinearLayout, visibility=8},
JATAH.perluTombol() and UI_Tombol("btnPesanDev", T("pesan_ke_developer", "Pesan ke Developer")) or {LinearLayout, visibility=8},
{LinearLayout, orientation="horizontal", layout_width="fill",
ADMIN_IDS[DapatkanAndroidID_Asli()] and UI_Tombol_H("btnAdminUtama", "Mode Admin") or {LinearLayout, visibility=8},
UI_Tombol_H("btnTutupUtama", T("tutup", "Tutup"))
}
)
local scrollUtama = ScrollView(service)
scrollUtama.addView(loadlayout(layoutUtama))
dialogUtama.setView(scrollUtama)

btnImporSPKUtama.onClick = function() dialogUtama.dismiss(); showPickerSPK() end
btnEksternalUtama.onClick = function() dialogUtama.dismiss(); tampilkanTemaEksternal() end

btnBahasaUtama.onClick = function()
local dLang = UI_Dialog(T("ganti_bahasa", "Ganti Bahasa"))
local layoutLang = UI_Layout(
UI_Daftar("lvLang"),
UI_Tombol("btnTutupLang", T("tutup", "Tutup"))
)
dLang.setView(loadlayout(layoutLang))

local langFiles = ArrayList()
local dirLang = File(langDir)
if dirLang.exists() and dirLang.isDirectory() then
local files = dirLang.listFiles()
if files then
for i = 0, #files - 1 do
local name = files[i].getName()
if string.match(name, "%.json$") then
local namaBersih = string.gsub(name, "%.json$", "")
langFiles.add(namaBersih)
end
end
end
end
lvLang.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, langFiles))

lvLang.onItemClick = function(l2, v2, p2, id2)
local selected = tostring(langFiles.get(p2))
simpanString("app_language", selected)
dLang.dismiss()
muatUlangBahasaDanMenu()
end

btnTutupLang.onClick = function() dLang.dismiss(); muatUlangBahasaDanMenu() end
dLang.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dLang.show()
end

if btnPesanDev then
btnPesanDev.onClick = function()
dialogUtama.dismiss()
JATAH.menuPesan()
end
end

if btnKlaimJatah then
btnKlaimJatah.onClick = function()
dialogUtama.dismiss()
JATAH.klaim()
end
end

if btnPeriksaPembaruan then
btnPeriksaPembaruan.onClick = function()
dialogUtama.dismiss()
PeriksaPembaruanManual()
end
end

btnTentangUtama.onClick = function()
dialogUtama.dismiss()
local dTentang = UI_Dialog(T("judul_tentang", "Dibuat oleh Nadi"))
local layoutTentang = UI_Layout(
UI_Teks(T("pesan_ulang_tahun", "Skrip ini dibuat spesial untuk hadiah ulang tahun pasangan saya Dian Resya putri yang ke-21 tahun. Semoga dia selalu panjang umur, diberikan kelancaran dalam setiap kegiatan dan setiap urusan.")),
UI_Tombol("btnTelegram", T("join_telegram", "Join ke Telegram")),
UI_Teks(T("hak_cipta", "Copyright Hak Cipta 2026, Nadi"), true),
UI_Tombol("btnTutupTentang", T("tutup", "Tutup"))
)
dTentang.setView(loadlayout(layoutTentang))

btnTelegram.onClick = function()
dTentang.dismiss()
pcall(function()
local intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://t.me/jmninandadian"))
intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
service.startActivity(intent)
end)
end

btnTutupTentang.onClick = function() dTentang.dismiss(); muatUlangBahasaDanMenu() end
dTentang.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dTentang.show()
end

btnTemaSaatIniUtama.onClick = function()
local tAktif = PreferenceManager.getDefaultSharedPreferences(service).getString("sound_package", "")
if tAktif == "" then tAktif = T("standar", "Standar") end
if tAktif == "[Tema Demo]" then
service.speak(T("demo_tidak_bisa_diedit", "Tema demo tidak bisa diedit dari sini."))
elseif tAktif == T("standar", "Standar") then
service.speak(T("standar_tidak_bisa_diedit", "Tema standar tidak bisa diedit."))
else
dialogUtama.dismiss()
isShortcutMenu = true
showEventList(tAktif)
end
end

btnEditUtama.onClick = function() dialogUtama.dismiss(); tampilkanMenuEdit() end

btnBuatEfek.onClick = function()
dialogUtama.dismiss()
tampilkanMenuBuatEfek()
end

btnHapusKomponen.onClick = function()
dialogUtama.dismiss()
BukaMenuHapusKomponen()
end

btnHapusEventUtama.onClick = function()
dialogUtama.dismiss()
HapusEvent.mulai()
end

btnTambahAudioBanyak.onClick = function()
dialogUtama.dismiss()
TambahAudio.mulai()
end

btnBuatJam.onClick = function()
dialogUtama.dismiss()

local jenisJam = 1
local komponenDipilih = 1
local formatDipilih = 1
local temaTujuan = ""
local draftPath = BASE .. "draft_rekaman_jam.json"
local tempJamPath = basePath .. "/.temp_jam_manual"

local function BuatAntreanTeksJam(tema, komp, form, isTTS)
local clockPath = isTTS and (basePath .. "/" .. tema .. "/clock") or tempJamPath
local c = {}
local ext = isTTS and ".wav" or ".m4a"
if form == 2 then
local txt24 = pref.getString("txt_24", "waktu saat ini menunjukan pukul: [ANGKA]")
for i = 1, 24 do local n = (i == 24) and "0" or tostring(i); local item = { text = txt24:gsub("%[ANGKA%]", tostring(i)), path = clockPath .. "/hour/" .. n .. ext }; if isTTS then item.id = "h"..n end; table.insert(c, item) end
if komp == 2 then
local txt24_tepat = pref.getString("txt_24_tepat", "waktu saat ini menunjukan pukul: [ANGKA] ,tepat...")
for i = 1, 24 do local n = tostring(i); if i == 24 then n = "0" end; n = n .. "00"; if #n == 3 then n = "0" .. n end; local item = { text = txt24_tepat:gsub("%[ANGKA%]", tostring(i)), path = clockPath .. "/hourly/" .. n .. ext }; if isTTS then item.id = "hl"..n end; table.insert(c, item) end
end
else
local function get12(h, isT) local sfx = isT and "_tepat" or ""; local t = ""; if h <= 4 then t = pref.getString("txt_12_1"..sfx, "waktu saat ini menunjukkan pukul [ANGKA] dini hari") elseif h <= 10 then t = pref.getString("txt_12_2"..sfx, "waktu saat ini menunjukkan pukul [ANGKA] pagi") elseif h <= 14 then t = pref.getString("txt_12_3"..sfx, "waktu saat ini menunjukkan pukul [ANGKA] siang") elseif h <= 18 then t = pref.getString("txt_12_4"..sfx, "waktu saat ini menunjukkan pukul [ANGKA] sore") else t = pref.getString("txt_12_5"..sfx, "waktu saat ini menunjukkan pukul [ANGKA] malam") end; local h12 = h; if h12 > 12 then h12 = h12 - 12 end; return t:gsub("%[ANGKA%]", tostring(h12)) end
for i = 1, 24 do local n = (i == 24) and "0" or tostring(i); local item = { text = get12(i, false), path = clockPath .. "/hour/" .. n .. ext }; if isTTS then item.id = "h"..n end; table.insert(c, item) end
if komp == 2 then
for i = 1, 24 do local n = tostring(i); if i == 24 then n = "0" end; n = n .. "00"; if #n == 3 then n = "0" .. n end; local item = { text = get12(i, true), path = clockPath .. "/hourly/" .. n .. ext }; if isTTS then item.id = "hl"..n end; table.insert(c, item) end
end
end
local txt0 = pref.getString("txt_min_0", ",Tepat")
local txtx = pref.getString("txt_min_x", "Lewat: [ANGKA] menit...")
for m = 0, 55, 5 do local textM = (m == 0) and txt0 or txtx:gsub("%[ANGKA%]", tostring(m)); local item = { text = textM, path = clockPath .. "/minute/" .. tostring(m) .. ext }; if isTTS then item.id = "m"..tostring(m) end; table.insert(c, item) end
return c
end

local showJenis, showKomp, showForm, showTema, eksekusiJamTTS, showPengaturanMic, eksekusiJamManual, loopRekaman

showJenis = function()
local dJenis = UI_Dialog(T("pilih_jenis_jam", "Pilih Jenis Jam"))
local lvJenis = ListView(service)
local optJenis = {T("jam_tts", "Jam TTS Otomatis"), T("rekam_sendiri", "Rekam Sendiri (Manual)")}
lvJenis.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, optJenis))
dJenis.setView(lvJenis)
lvJenis.onItemClick = function(l, v, p, id)
jenisJam = p + 1
dJenis.dismiss()
showKomp()
end
dJenis.setButton(T("batal", "Batal"), function() dJenis.dismiss(); muatUlangBahasaDanMenu() end)
dJenis.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dJenis.show()
end

showKomp = function()
local dKomp = UI_Dialog(T("pilih_komponen", "Pilih Komponen Jam"))
local lvKomp = ListView(service)
local optKomp = {T("komp_1", "Jam dan Menit"), T("komp_2", "Jam, Jam Tepat, dan Menit")}
lvKomp.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, optKomp))
dKomp.setView(lvKomp)

lvKomp.onItemClick = function(lK, vK, pK, idK)
komponenDipilih = pK + 1
dKomp.dismiss()
showForm()
end
dKomp.setButton(T("kembali", "Kembali"), function() dKomp.dismiss(); showJenis() end)
dKomp.setOnCancelListener(function() showJenis() end)
dKomp.show()
end

showForm = function()
local dForm = UI_Dialog(T("pilih_format", "Pilih Format Jam"))
local lvForm = ListView(service)
local optForm = {T("form_12", "Format 12 Jam"), T("form_24", "Format 24 Jam")}
lvForm.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, optForm))
dForm.setView(lvForm)

lvForm.onItemClick = function(lF, vF, pF, idF)
formatDipilih = pF + 1
dForm.dismiss()
showTema()
end
dForm.setButton(T("kembali", "Kembali"), function() dForm.dismiss(); showKomp() end)
dForm.setOnCancelListener(function() showKomp() end)
dForm.show()
end

showTema = function()
local dTemaObj = UI_Dialog(T("pilih_tema_tujuan", "Pilih Tema Suara Tujuan"))
local lvTemaObj = ListView(service)
local listTema = ArrayList()
local dir = File(basePath)
local allT = {}
if dir.exists() then
local files = dir.listFiles()
if files then
for i = 0, #files - 1 do
if files[i].isDirectory() and File(files[i].getAbsolutePath() .. "/config").exists() then
table.insert(allT, files[i].getName())
end
end
end
end
table.sort(allT, function(a, b) return string.lower(a) < string.lower(b) end)
for i=1, #allT do listTema.add(allT[i]) end
lvTemaObj.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, listTema))
dTemaObj.setView(lvTemaObj)

lvTemaObj.onItemClick = function(lT, vT, pT, idT)
temaTujuan = tostring(listTema.get(pT))
dTemaObj.dismiss()

if jenisJam == 1 then
local clockPath = basePath .. "/" .. temaTujuan .. "/clock"
local targetDir = File(clockPath)
if targetDir.exists() then
local dWarn = UI_Dialog(T("konfirmasi", "Konfirmasi"))
dWarn.setMessage(T("jam_sudah_ada", "Folder jam (clock) sudah ada di tema ini. Apakah Anda ingin menimpanya?"))
dWarn.setButton(T("timpa", "Timpa"), function() eksekusiJamTTS() end)
dWarn.setButton2(T("kembali", "Kembali"), function() dWarn.dismiss(); showTema() end)
dWarn.setOnCancelListener(function() showTema() end)
dWarn.show()
else
eksekusiJamTTS()
end
else
local isAutoRec = pref.getBoolean("auto_record_quality", false)
if isAutoRec then
local initData = {
tema = temaTujuan,
komponen = komponenDipilih,
format = formatDipilih,
mic = pref.getInt("auto_rec_mic", 1),
sr = pref.getInt("auto_rec_sr", 44100),
br = pref.getInt("auto_rec_br", 128000),
ch = pref.getInt("auto_rec_ch", 1),
index = 1
}
simpanJson(draftPath, initData)
eksekusiJamManual(false)
else
showPengaturanMic()
end
end
end
dTemaObj.setButton(T("kembali", "Kembali"), function() dTemaObj.dismiss(); showForm() end)
dTemaObj.setOnCancelListener(function() showForm() end)
dTemaObj.show()
end

showPengaturanMic = function()
showHelperPanelAudio(T("pengaturan_rekaman", "Pengaturan Kualitas Rekaman"), T("simpan", "Simpan"), 1, 44100, 128000, 1, function(selMic, selSr, selBr, selCh)
local initData = {
tema = temaTujuan,
komponen = komponenDipilih,
format = formatDipilih,
mic = selMic,
sr = selSr,
br = selBr,
ch = selCh,
index = 1
}
EfekJam.siapkanSesi(function(pakaiEfek)
if pakaiEfek then initData.efek_cfg = (EfekJam.ambilCfg(false) or "") .. "\nbitrate=" .. tostring(selBr) end
simpanJson(draftPath, initData)
eksekusiJamManual(false)
end, function() showTema() end)
end, function()
showTema()
end)
end

eksekusiJamManual = function(dariDraf)
local drafData = bacaJson(draftPath)
temaTujuan = drafData.tema
komponenDipilih = drafData.komponen
formatDipilih = drafData.format
local mic = drafData.mic
local sr = drafData.sr
local br = drafData.br
local ch = drafData.ch or 1
local currIdx = drafData.index

local targetDir = File(tempJamPath)
if currIdx == 1 then
if targetDir.exists() then deleteRecursive(targetDir) end
targetDir.mkdirs()
File(tempJamPath .. "/hour").mkdirs()
File(tempJamPath .. "/minute").mkdirs()
if komponenDipilih == 2 then File(tempJamPath .. "/hourly").mkdirs() end
if CekSisaKuotaTTS() then CatatPemakaianFreemium("tts_jam", true) end
end

local chunks = BuatAntreanTeksJam(temaTujuan, komponenDipilih, formatDipilih, false)

loopRekaman = function(idx)
if idx > #chunks then
local infoJatahEfek = ""
local daftarM4a = EfekJam.kumpulFile(tempJamPath, ".m4a")
local tahapM = {}
if drafData.efek_cfg then table.insert(tahapM, { k = "efek", b = 35 }) end
if SisipanJam.adaSisipan(daftarM4a) then table.insert(tahapM, { k = "sisip", b = 35 }) end
table.insert(tahapM, { k = "pindah", b = 10 })
ProgresJam.mulai(tahapM, T("prog_siap", "Menyiapkan pembuatan jam..."))
ProgresJam.pesanBatal = T("prog_batal_manual", "Rekaman Anda tetap tersimpan sebagai draf.")
local function selesaikanJamManual()
ProgresJam.tahap("pindah", T("prog_pindah", "Menyimpan jam ke tema..."))
ProgresJam.matikanBatal()
local jamAsli = File(basePath .. "/" .. temaTujuan .. "/clock")
local itemsJam = {
{ src = tempJamPath .. "/hour", dst = jamAsli.getAbsolutePath() .. "/hour" },
{ src = tempJamPath .. "/minute", dst = jamAsli.getAbsolutePath() .. "/minute" }
}
if File(tempJamPath .. "/hourly").exists() then table.insert(itemsJam, { src = tempJamPath .. "/hourly", dst = jamAsli.getAbsolutePath() .. "/hourly" }) end
jalankanTaskLoading(nil, kerjaSelesaiJam, cjson.encode({ jamAsli = jamAsli.getAbsolutePath(), items = itemsJam, hapus = { tempJamPath, draftPath } }), function()
service.speak(T("jam_berhasil", "Jam bicara berhasil ditambahkan ke tema!") .. infoJatahEfek)
muatUlangBahasaDanMenu()
end)
end
local function selesaikanDenganSisipan()
SisipanJam.terapkanSesi(EfekJam.kumpulFile(tempJamPath, ".m4a"), function()
if ProgresJam.dibatalkan then ProgresJam.keluarBatal(nil, T("prog_batal_manual_selesai", "Dibatalkan. Rekaman Anda tetap tersimpan sebagai draf.")); return end
selesaikanJamManual()
end, br)
end
-- Layar progres sudah tampil; pekerjaan dimulai sesudah layar sempat tergambar.
uiHandler.postDelayed(Runnable({
run = function()
if drafData.efek_cfg then
EfekJam.terapkanDaftar(EfekJam.kumpulFile(tempJamPath, ".m4a"), drafData.efek_cfg, function(sukses, pesan)
if ProgresJam.dibatalkan then ProgresJam.keluarBatal(nil, T("prog_batal_manual_selesai", "Dibatalkan. Rekaman Anda tetap tersimpan sebagai draf.")); return end
if sukses then
if not drafData.efek_dihitung then infoJatahEfek = EfekJam.catatInfo(drafData.efek_cfg) end
else
infoJatahEfek = " " .. T("efekjam_gagal_diterapkan", "Efek gagal diterapkan: ") .. tostring(pesan)
end
selesaikanDenganSisipan()
end)
else
selesaikanDenganSisipan()
end
end
}), 120)
return
end

drafData.index = idx
simpanJson(draftPath, drafData)

local item = chunks[idx]
local dRekam = UI_Dialog(T("rekam_sendiri", "Rekam Sendiri (Manual)") .. " - " .. idx .. "/" .. #chunks)

local layRekam = {LinearLayout, orientation="vertical", layout_width="fill", layout_height="fill", backgroundColor="0xFF000000", gravity="center",
{TextView, id="tvInstruksiRekam", text=T("siap_merekam", "Menyiapkan instruksi..."), layout_width="fill", layout_height="fill", gravity="center", textSize="20sp", textColor="0xFFFFFFFF", padding="16dp"}
}

local viewRekam = loadlayout(layRekam)
dRekam.setView(viewRekam)
dRekam.setCancelable(true)
pcall(function() dRekam.setCanceledOnTouchOutside(false) end)
pcall(function() dRekam.getWindow().setType(2032) end)

local ttsMaker
local engine = pref.getString("tts_engine", "")
local isRecording = false
local isReady = false
local mr = nil
local tempWav = basePath .. "/.temp_rekam.m4a"

local function tutupDanBatal()
if isRecording and mr then pcall(function() mr.stop(); mr.release() end) end
pcall(function() ttsMaker.shutdown() end)
dRekam.dismiss()
EfekJam.peringatanKeluar(drafData, function() simpanJson(draftPath, drafData) end, function() muatUlangBahasaDanMenu() end, function() loopRekaman(idx) end)
end

dRekam.setOnCancelListener(function() tutupDanBatal() end)

local function playHitungMundur()
if CekSisaKuotaTTS() then
uiHandler.postDelayed(Runnable({run = function() pcall(function() ttsMaker.speak("1", TextToSpeech.QUEUE_FLUSH, nil, "num1") end) end}), 500)
uiHandler.postDelayed(Runnable({run = function() pcall(function() ttsMaker.speak("2", TextToSpeech.QUEUE_FLUSH, nil, "num2") end) end}), 1500)
uiHandler.postDelayed(Runnable({run = function() pcall(function() ttsMaker.speak("3", TextToSpeech.QUEUE_FLUSH, nil, "num3") end) end}), 2500)
uiHandler.postDelayed(Runnable({run = function()
uiHandler.post(Runnable({run = function()
isReady = true
tvInstruksiRekam.setText(item.text .. "\n\n" .. T("tombol_rekam", "Usap BAWAH: Mulai Rekam\nUsap ATAS: Berhenti\nUsap KIRI/KANAN: Tutup/Batal"))
end}))
end}), 3500)
else
uiHandler.postDelayed(Runnable({run = function()
uiHandler.post(Runnable({run = function()
isReady = true
tvInstruksiRekam.setText(item.text .. "\n\n" .. T("tombol_rekam", "Usap BAWAH: Mulai Rekam\nUsap ATAS: Berhenti\nUsap KIRI/KANAN: Tutup/Batal"))
end}))
end}), 1000)
end
end

ttsMaker = TextToSpeech(service, function(status)
if status == TextToSpeech.SUCCESS then
if engine ~= "" then pcall(function() ttsMaker.setEngineByPackageName(engine) end) end
local listener = UtteranceProgressListener{
onStart = function(uId) end,
onDone = function(uId)
if uId == "instruksi" then playHitungMundur() end
end,
onError = function(uId)
if uId == "instruksi" then playHitungMundur() end
end
}
pcall(function() ttsMaker.setOnUtteranceProgressListener(listener) end)

local param = {[TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID] = "instruksi"}

if CekSisaKuotaTTS() then
local instruksiFinal = T("instruksi_rekam", "Oke, saatnya mengatakan: ") .. item.text
pcall(function() ttsMaker.speak(instruksiFinal, TextToSpeech.QUEUE_FLUSH, param) end)
else
playHitungMundur()
end
end
end, engine == "" and nil or engine)

local function munculkanPratinjau()
local dPrev = UI_Dialog(T("pratinjau_rekaman", "Pratinjau Rekaman"))
local layPrev = UI_Layout(
UI_Tombol("btnPutarP", T("putar", "Putar")),
UI_Tombol("btnUlangP", T("ulang_rekaman", "Ulang Rekaman")),
UI_Tombol("btnLanjutP", T("lanjut", "Lanjut")),
UI_Tombol("btnNantiP", T("nanti_dulu", "Nanti Dulu")),
UI_Tombol("btnBatalP", T("batalkan_semua", "Batalkan Semua"))
)
dPrev.setView(loadlayout(layPrev))
dPrev.setCancelable(false)
dPrev.show()

local mp = nil
local isPlaying = false
btnPutarP.onClick = function()
if not isPlaying then
pcall(function()
mp = luajava.bindClass("android.media.MediaPlayer")()
mp.setDataSource(tempWav)
mp.prepare()
mp.start()
isPlaying = true
btnPutarP.setText(T("berhenti_merekam", "Berhenti"))
mp.setOnCompletionListener(function(m)
uiHandler.post(Runnable({run=function() btnPutarP.setText(T("putar", "Putar")); isPlaying=false end}))
end)
end)
else
pcall(function() if mp then mp.stop(); mp.release(); mp = nil end end)
btnPutarP.setText(T("putar", "Putar"))
isPlaying = false
end
end

btnUlangP.onClick = function()
pcall(function() if mp then mp.stop(); mp.release() end end)
File(tempWav).delete()
dPrev.dismiss()
loopRekaman(idx)
end

btnLanjutP.onClick = function()
pcall(function() if mp then mp.stop(); mp.release() end end)
SalinFile(tempWav, item.path)
File(tempWav).delete()
dPrev.dismiss()
loopRekaman(idx + 1)
end

btnNantiP.onClick = function()
pcall(function() if mp then mp.stop(); mp.release(); mp = nil; isPlaying = false end end)
EfekJam.peringatanKeluar(drafData, function() simpanJson(draftPath, drafData) end, function()
File(tempWav).delete()
dPrev.dismiss()
muatUlangBahasaDanMenu()
end, function() end)
end

btnBatalP.onClick = function()
pcall(function() if mp then mp.stop(); mp.release() end end)
showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("batalkan_semua_teks", "Hapus semua rekaman yang baru dibuat dan mulai dari nol?"), function()
EfekJam.peringatanKeluar(drafData, function() end, function()
File(draftPath).delete()
deleteRecursive(File(tempJamPath))
File(tempWav).delete()
dPrev.dismiss()
muatUlangBahasaDanMenu()
end, function() end)
end)
end
end

dRekam.show()

local startX, startY = 0, 0
pcall(function()
dRekam.getWindow().getDecorView().setOnTouchListener(luajava.createProxy("android.view.View$OnTouchListener", {
onTouch = function(v, e)
local act = e.getActionMasked()
if act == 0 then
startX = e.getRawX()
startY = e.getRawY()
elseif act == 1 then
local endX = e.getRawX()
local endY = e.getRawY()
local dx = endX - startX
local dy = endY - startY

if math.abs(dy) > math.abs(dx) then
if dy > 80 then
if not isRecording and isReady then
isRecording = true
tvInstruksiRekam.setText(item.text .. "\n\n" .. T("merekam", "[MEREKAM...]\nUsap layar ke ATAS untuk berhenti."))
pcall(function()
mr = luajava.bindClass("android.media.MediaRecorder")()
mr.setAudioSource(mic)
mr.setOutputFormat(2)
mr.setAudioEncoder(3)
mr.setAudioEncodingBitRate(br)
mr.setAudioSamplingRate(sr)
mr.setAudioChannels(ch)
mr.setOutputFile(tempWav)
mr.prepare()
mr.start()
end)
end
elseif dy < -80 then
if isRecording then
isRecording = false
pcall(function() if mr then mr.stop(); mr.release(); mr = nil end end)
dRekam.dismiss()
pcall(function() ttsMaker.shutdown() end)
munculkanPratinjau()
end
end
else
if math.abs(dx) > 100 then
tutupDanBatal()
end
end
end
return true
end
}))
end)
end
loopRekaman(currIdx)
end

eksekusiJamTTS = function()
-- Satu layar progres untuk seluruh proses. Layar ditampilkan lebih dulu, baru pekerjaan berat
-- dijalankan sesudah layar sempat tergambar, supaya tidak ada jeda macet sebelum layar muncul.
local autoKomp = pref.getBoolean("auto_compress", false)
ProgresJam.mulai({ { k = "siap", b = 5 } }, T("prog_siap", "Menyiapkan pembuatan jam..."))
ProgresJam.pesanBatal = T("prog_batal_tts", "Folder jam yang belum selesai akan dihapus.")
uiHandler.postDelayed(Runnable({
run = function()
EfekJam.siapkanSesi(function(pakaiEfek)
local cfgEfek = pakaiEfek and EfekJam.ambilCfg(false) or nil
local clockPath = basePath .. "/" .. temaTujuan .. "/clock"
local targetDir = File(clockPath)

-- Tahap dan bobotnya disesuaikan dengan yang benar-benar dipakai.
local daftarAwal = {}
for _, c in ipairs(BuatAntreanTeksJam(temaTujuan, komponenDipilih, formatDipilih, true)) do table.insert(daftarAwal, c.path) end
local tahapList = { { k = "siap", b = 5 }, { k = "tts", b = 55 } }
if cfgEfek then table.insert(tahapList, { k = "efek", b = 10 }) end
if SisipanJam.adaSisipan(daftarAwal) then table.insert(tahapList, { k = "sisip", b = 10 }) end
if autoKomp then table.insert(tahapList, { k = "konversi", b = 20 }) end
ProgresJam.atur(tahapList)
ProgresJam.tahap("siap", T("prog_siap_folder", "Menyiapkan folder jam..."))

jalankanDenganLoading(T("prog_siap_folder", "Menyiapkan folder jam..."), function()
if targetDir.exists() then deleteRecursive(targetDir) end
targetDir.mkdirs()
File(clockPath .. "/hour").mkdirs()
File(clockPath .. "/minute").mkdirs()
if komponenDipilih == 2 then File(clockPath .. "/hourly").mkdirs() end
end,
function()
if ProgresJam.dibatalkan then ProgresJam.keluarBatal(clockPath); return end
ProgresJam.tahap("tts", T("prog_tts_mulai", "Menyiapkan mesin suara..."))
uiHandler.postDelayed(Runnable({
run = function()

local engine = pref.getString("tts_engine", "")
local voiceName = pref.getString("tts_voice", "")
local pitch = pref.getFloat("tts_pitch", 1.0)
local rate = pref.getFloat("tts_rate", 1.0)

local chunks = BuatAntreanTeksJam(temaTujuan, komponenDipilih, formatDipilih, true)

import "android.speech.tts.UtteranceProgressListener"
local ttsMaker
local totalProses = #chunks
local prosesKe = 0
local isFinished = false
local HashMap = luajava.bindClass("java.util.HashMap")

local function finalizeProses(isError)
if isFinished then return end
isFinished = true
pcall(function() ttsMaker.shutdown() end)
uiHandler.post(Runnable({
run = function()
if isError then
service.speak(T("proses_selesai_error", "Proses selesai dengan beberapa error atau batas waktu habis."))
end

local function lanjutSetelahSisipan()
local isAutoComp = pref.getBoolean("auto_compress", false)
if isAutoComp then
local fSel = pref.getString("auto_comp_format", "M4A")
local brTarget = pref.getInt("auto_comp_br", 128000)

ProgresJam.tahap("konversi", T("mengonversi_otomatis_ke", "Mengonversi otomatis ke ") .. fSel .. "...")
local daftarKonversi = {}
for _, c in ipairs(chunks) do table.insert(daftarKonversi, c.path) end
SisipanJam.konversiSesi(daftarKonversi, fSel, brTarget, function(res)
if ProgresJam.dibatalkan or res.batal then ProgresJam.keluarBatal(clockPath); return end
ProgresJam.selesai()
if res.tanpaMesin then
muatUlangBahasaDanMenu()
elseif res.isErr then
service.speak(T("gagal_ogg", "Gagal! Perangkat tidak mendukung OGG, file dibiarkan dalam format WAV."))
muatUlangBahasaDanMenu()
else
local dSukses = UI_Dialog(T("proses_selesai", "Proses Selesai!"))
local brKbps = math.floor(brTarget / 1000)
local msgTemplate = T("info_berhasil_konversi", "Telah berhasil merubah ke [FMT], [BR] Kbps, dengan sample rate asli mesin [SR] Hz.")
local msg = msgTemplate:gsub("%[FMT%]", fSel):gsub("%[BR%]", tostring(brKbps)):gsub("%[SR%]", tostring(res.sr))
dSukses.setMessage(msg)
dSukses.setButton(T("tutup", "Tutup"), function() muatUlangBahasaDanMenu() end)
dSukses.setCancelable(false)
dSukses.show()
end
end)
else
-- Dialog kompresi kustom khusus untuk Jam TTS (tanpa opsi Sample Rate)
ProgresJam.selesai()
local dKonvJam = UI_Dialog(T("kompresi_audio", "Kompresi Audio"))
local layKonvJam = UI_Layout(
UI_Teks(T("pilih_format", "Pilih Format:")), {Spinner, id="spFmtJam"},
UI_Teks(T("pilih_bitrate", "Pilih Bitrate:")), {Spinner, id="spBrJam"}
)
local scrollK = ScrollView(service)
scrollK.addView(loadlayout(layKonvJam))
dKonvJam.setView(scrollK)

local fData = ArrayList()
fData.add("M4A")
fData.add("OGG")
spFmtJam.setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_item, fData))

local bData = ArrayList()
bData.add("32 kbps")
bData.add("64 kbps")
bData.add("128 kbps")
bData.add("192 kbps")
bData.add("256 kbps")
spBrJam.setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_item, bData))
spBrJam.setSelection(2)

dKonvJam.setButton(T("konversi", "Konversi"), function()
local fSel = tostring(spFmtJam.getSelectedItem())
local bSelStr = tostring(spBrJam.getSelectedItem())
local brTarget = 128000
if bSelStr == "32 kbps" then brTarget = 32000 elseif bSelStr == "64 kbps" then brTarget = 64000 elseif bSelStr == "128 kbps" then brTarget = 128000 elseif bSelStr == "192 kbps" then brTarget = 192000 elseif bSelStr == "256 kbps" then brTarget = 256000 end

ProgresJam.mulai({ { k = "konversi", b = 1 } }, T("mengonversi_ke", "Mengonversi ke ") .. fSel .. "...")
ProgresJam.tahap("konversi", T("mengonversi_ke", "Mengonversi ke ") .. fSel .. "...")
local daftarKonversi = {}
for _, c in ipairs(chunks) do table.insert(daftarKonversi, c.path) end
SisipanJam.konversiSesi(daftarKonversi, fSel, brTarget, function(res)
if ProgresJam.dibatalkan or res.batal then ProgresJam.keluarBatal(clockPath); return end
ProgresJam.selesai()
if res.tanpaMesin then
muatUlangBahasaDanMenu()
elseif res.isErr then
service.speak(T("perangkat_tidak_dukung_ogg", "Perangkat tidak mendukung format OGG. Silakan pilih M4A."))
muatUlangBahasaDanMenu()
else
local dSukses = UI_Dialog(T("proses_selesai", "Proses Selesai!"))
local brKbps = math.floor(brTarget / 1000)
local msgTemplate = T("info_berhasil_konversi", "Telah berhasil merubah ke [FMT], [BR] Kbps, dengan sample rate asli mesin [SR] Hz.")
local msg = msgTemplate:gsub("%[FMT%]", fSel):gsub("%[BR%]", tostring(brKbps)):gsub("%[SR%]", tostring(res.sr))
dSukses.setMessage(msg)
dSukses.setButton(T("tutup", "Tutup"), function() muatUlangBahasaDanMenu() end)
dSukses.setCancelable(false)
dSukses.show()
end
end)
end)
dKonvJam.setButton2(T("batal", "Batal"), function()
service.speak(T("proses_batal_wav", "Proses dibatalkan. Jam bicara dibiarkan dalam format WAV."))
muatUlangBahasaDanMenu()
end)
dKonvJam.setOnCancelListener(function()
service.speak(T("proses_batal_wav", "Proses dibatalkan. Jam bicara dibiarkan dalam format WAV."))
muatUlangBahasaDanMenu()
end)
dKonvJam.setCancelable(false)
dKonvJam.show()
end
end
local function lanjutSetelahEfek()
local daftarSisip = {}
for _, c in ipairs(chunks) do table.insert(daftarSisip, c.path) end
SisipanJam.terapkanSesi(daftarSisip, function()
if ProgresJam.dibatalkan then ProgresJam.keluarBatal(clockPath); return end
lanjutSetelahSisipan()
end)
end
if cfgEfek then
local daftarWav = {}
for _, c in ipairs(chunks) do table.insert(daftarWav, c.path) end
EfekJam.terapkanDaftar(daftarWav, cfgEfek, function(sukses, pesan)
if ProgresJam.dibatalkan then ProgresJam.keluarBatal(clockPath); return end
if sukses then
local info = EfekJam.catatInfo(cfgEfek)
if info ~= "" then service.speak(info) end
else
service.speak(T("efekjam_gagal_diterapkan", "Efek gagal diterapkan: ") .. tostring(pesan))
end
lanjutSetelahEfek()
end)
else
lanjutSetelahEfek()
end
end
}))
end

ProgresJam.padaBatal = function()
isFinished = true
pcall(function() ttsMaker.stop() end)
pcall(function() ttsMaker.shutdown() end)
ProgresJam.keluarBatal(clockPath)
end

local function handleTtsProgress(isError)
prosesKe = prosesKe + 1
ProgresJam.maju(prosesKe / math.max(totalProses, 1), nil, false)
if prosesKe >= totalProses then
finalizeProses(isError)
end
end

ttsMaker = TextToSpeech(service, function(status)
if status == TextToSpeech.SUCCESS then
if engine ~= "" then pcall(function() ttsMaker.setEngineByPackageName(engine) end) end
if voiceName ~= "" then
local voices = ttsMaker.getVoices()
if voices then
local iter = voices.iterator()
while iter.hasNext() do
local v = iter.next()
if v.getName() == voiceName then ttsMaker.setVoice(v); break end
end
end
end
ttsMaker.setPitch(pitch)
ttsMaker.setSpeechRate(rate)

local listener = UtteranceProgressListener{
onStart = function(uId) ProgresJam.maju(prosesKe / math.max(totalProses, 1), T("prog_membuat", "Membuat ") .. ProgresJam.labelId(uId), true) end,
onDone = function(uId) handleTtsProgress(false) end,
onError = function(uId) handleTtsProgress(true) end
}
pcall(function() ttsMaker.setOnUtteranceProgressListener(listener) end)

local timeoutHandler = Handler(Looper.getMainLooper())
timeoutHandler.postDelayed(Runnable({
run = function()
if not isFinished then
finalizeProses(true)
end
end
}), 45000)

for i, chunk in ipairs(chunks) do
local paramMap = HashMap()
paramMap.put(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, chunk.id)
local result = ttsMaker.synthesizeToFile(chunk.text, paramMap, chunk.path)
if result == TextToSpeech.ERROR then
handleTtsProgress(true)
end
end
else
uiHandler.post(Runnable({
run = function()
ProgresJam.selesai()
service.speak(T("gagal_mesin_tts", "Gagal memulai mesin TTS"))
muatUlangBahasaDanMenu()
end
}))
end
end, engine == "" and nil or engine)
end
}), 100)
end)
end, function() ProgresJam.selesai(); muatUlangBahasaDanMenu() end)
end
}), 120)
end

local fDraft = io.open(draftPath, "r")
if fDraft then
fDraft:close()
local dDraft = UI_Dialog(T("ada_draf_rekaman", "Draf Rekaman Ditemukan"))
dDraft.setMessage(T("teks_draf_rekaman", "Terdapat sesi rekaman manual yang belum selesai. Lanjutkan?"))
dDraft.setButton(T("lanjutkan", "Lanjutkan"), function() eksekusiJamManual(true) end)
dDraft.setButton2(T("mulai_baru", "Mulai Baru"), function() File(draftPath).delete(); deleteRecursive(File(tempJamPath)); showJenis() end)
dDraft.setButton3(T("nanti_dulu", "Nanti Dulu"), function() muatUlangBahasaDanMenu() end)
dDraft.setCancelable(false)
dDraft.show()
else
showJenis()
end

end

btnDemoInstanUtama.onClick = function()
CekKuotaFreemium("demo_instan", function()
demoSesiDihitung = false
dialogUtama.dismiss()
showDemoInstan()
end)
end

btnDemoUtama.onClick = function() dialogUtama.dismiss(); tampilkanMenuDemo() end
btnDaftarKode.onClick = function() dialogUtama.dismiss(); tampilkanDaftarKodeSuara() end
btnPencadanganUtama.onClick = function() dialogUtama.dismiss(); tampilkanMenuPencadangan() end

-- ==========================================================================
-- KOMUNITAS OFFICIAL CSR (toko resmi Jieshuo, kategori tema suara "sound/")
-- Tabel global supaya tidak menambah jumlah variabel local di chunk utama.
-- Satu akun = satu tema (nama berkas jieshuo_<pengguna>.spk), sama seperti toko resmi.
-- ==========================================================================
CSRO = {
AUTH = "https://nirenr.com:9000",
HOST = "https://d.jieshuo.ltd",
KATALOG = "https://jieshuo.ltd/download",
DISCOVER = "https://jieshuo.ltd/url.txt",
INVITE = "946049229",
hostSiap = false,
sesi = nil,
cacheSemua = nil,
cacheWaktu = 0
}

-- Worker task. Jalan di thread terpisah: TIDAK boleh memakai variabel di luar fungsi ini (termasuk CSRO).
function CSRO.kerja(jsonArgs)
require "import"
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.ByteArrayOutputStream"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.net.URL"
import "java.net.URLEncoder"
import "java.lang.String"
local cjson = require "cjson"
local a = cjson.decode(jsonArgs)

local function bytesDari(s) return String(s).getBytes("UTF-8") end
local function enc(s) return tostring(URLEncoder.encode(tostring(s or ""), "UTF-8")) end

local function http(metode, url, body, ctype, timeout)
local res = { code = 0, body = "" }
local conn = nil
local ok, err = pcall(function()
conn = URL(url).openConnection()
conn.setConnectTimeout(15000)
conn.setReadTimeout(timeout or 30000)
conn.setRequestMethod(metode)
if body ~= nil then
conn.setRequestProperty("Content-Type", ctype)
conn.setDoOutput(true)
local os_ = conn.getOutputStream()
os_.write(body)
os_.flush()
os_.close()
end
res.code = tonumber(conn.getResponseCode()) or 0
local flujo = nil
if res.code >= 200 and res.code < 400 then flujo = conn.getInputStream() else flujo = conn.getErrorStream() end
if flujo ~= nil then
local br = BufferedReader(InputStreamReader(flujo, "UTF-8"))
local baris = {}
local l = br.readLine()
while l ~= nil do baris[#baris + 1] = tostring(l); l = br.readLine() end
br.close()
res.body = table.concat(baris, "\n")
end
end)
if not ok then res.err = tostring(err) end
pcall(function() if conn ~= nil then conn.disconnect() end end)
return res
end

if a.aksi == "discover" then
local r = http("GET", a.url, nil, nil, 15000)
local h = (tostring(r.body or ""):gsub("%s+$", ""))
h = (h:gsub("/+$", ""))
-- hanya terima alamat HTTPS
if h:match("^https://") then return cjson.encode({ ok = true, host = h }) end
return cjson.encode({ ok = false })

elseif a.aksi == "post" then
local r = http("POST", a.url, bytesDari(a.body), "application/x-www-form-urlencoded", 30000)
return cjson.encode({ code = r.code, body = r.body, err = r.err })

elseif a.aksi == "katalog" or a.aksi == "semua" or a.aksi == "rentang" then
-- ambil satu halaman katalog; bahasa dicoba lalu cadangan "en" kalau kosong
local function ambil(p, bhs)
local url = string.format("%s/api.php?f=%s&p=%d&l=%s&s=%s&n=&sort=name&order=asc", a.katalog, enc("sound/"), p, enc(bhs), enc(a.cari))
for percobaan = 1, 2 do
local r = http("GET", url, nil, nil, 30000)
if r.code == 200 then
local ok, d = pcall(cjson.decode, r.body)
if ok and type(d) == "table" and type(d.files) == "table" then return d end
end
end
return nil
end
local bhs = a.bahasa or "en"
local hal = tonumber(a.p) or 1
local d = ambil(hal, bhs)
if (d == nil or #d.files == 0) and bhs ~= "en" and hal == 1 then
bhs = "en"
d = ambil(1, "en")
end
if d == nil then return cjson.encode({ ok = false }) end
local files = {}
local function tambah(src)
for i = 1, #src do
local f = src[i]
files[#files + 1] = { filename = f.filename, size_formatted = f.size_formatted, mtime_formatted = f.mtime_formatted }
end
end
tambah(d.files)
local total = math.max(1, tonumber(d.total_pages) or 1)
if a.aksi == "semua" then
for p = 2, math.min(total, 60) do
local dp = ambil(p, bhs)
if dp then tambah(dp.files) end
end
end
if a.aksi == "rentang" then
-- ambil halaman (p+1 .. sampai) saja; halaman p sudah ikut diambil di atas
for p = hal + 1, math.min(tonumber(a.sampai) or hal, total, 60) do
local dp = ambil(p, bhs)
if dp then tambah(dp.files) end
end
end
return cjson.encode({ ok = true, files = files, total = total, bhs = bhs })

elseif a.aksi == "upload" then
local f = File(a.path)
if not f.exists() then return cjson.encode({ ok = false, body = "berkas tema tidak ditemukan" }) end
local fis = FileInputStream(a.path)
local baos = ByteArrayOutputStream()
local buf = byte[65536]
local n = fis.read(buf)
while n ~= -1 do
baos.write(buf, 0, n)
n = fis.read(buf)
end
fis.close()
local boundary = "----NadiCsr" .. tostring(os.time())
local out = ByteArrayOutputStream()
local function t(s) out.write(bytesDari(s)) end
local function campo(nama, nilai)
t("--" .. boundary .. "\r\n")
t('Content-Disposition: form-data; name="' .. nama .. '"\r\n\r\n')
t(tostring(nilai) .. "\r\n")
end
campo("user_name", a.user)
campo("name", a.nama)
t("--" .. boundary .. "\r\n")
t('Content-Disposition: form-data; name="file"; filename="' .. a.nameFile .. '"\r\n')
t("Content-Type: application/octet-stream\r\n\r\n")
out.write(baos.toByteArray())
t("\r\n")
t("--" .. boundary .. "--\r\n")
local r = http("POST", a.url, out.toByteArray(), "multipart/form-data;boundary=" .. boundary, 180000)
pcall(function() f.delete() end)
local bersih = (tostring(r.body or ""):gsub("%s+", ""))
return cjson.encode({ ok = (r.err == nil and bersih == "0"), body = r.body, err = r.err, code = r.code })

elseif a.aksi == "hapus" then
local body = "password=" .. enc(a.password) .. "&name=" .. enc(a.nama) .. "&username=" .. enc(a.user)
local r = http("POST", a.url, bytesDari(body), "application/x-www-form-urlencoded", 30000)
local bersih = (tostring(r.body or ""):gsub("%s+", ""))
return cjson.encode({ ok = (r.err == nil and bersih == "0"), body = r.body, err = r.err, code = r.code })
end
return cjson.encode({ ok = false })
end

-- ---------- sesi akun ----------
function CSRO.muatSesi()
local s = dapatkanString("csr_sesi", "")
if s ~= "" then
local ok, d = pcall(cjson.decode, s)
if ok and type(d) == "table" and d.SID and d.username then CSRO.sesi = d end
end
end

function CSRO.simpanSesi()
if CSRO.sesi then simpanString("csr_sesi", cjson.encode(CSRO.sesi)) else simpanString("csr_sesi", "") end
end

function CSRO.deviceId()
local id = ""
pcall(function()
local Secure = luajava.bindClass("android.provider.Settings$Secure")
id = tostring(Secure.getString(service.getContentResolver(), "android_id"))
end)
if id == "nil" then id = "" end
return id:sub(1, 8)
end

function CSRO.bahasa()
local b = "en"
pcall(function()
local k = tostring(java.util.Locale.getDefault().getLanguage())
if k == "id" or k == "in" then b = "in" elseif k ~= "" and k ~= "nil" then b = k end
end)
return b
end

function CSRO.pesan(judul, teks, onTutup)
local d = UI_Dialog(judul)
d.setMessage(tostring(teks))
d.setButton(T("oke", "Oke"), function() d.dismiss(); if onTutup then onTutup() end end)
d.setOnCancelListener(function() if onTutup then onTutup() end end)
d.show()
end

function CSRO.siapkanHost(lanjut)
if CSRO.hostSiap then lanjut(); return end
jalankanTaskLoading(T("csr_menyiapkan", "Menyiapkan koneksi Official CSR..."), CSRO.kerja,
cjson.encode({ aksi = "discover", url = CSRO.DISCOVER }), function(h)
if h.ok and h.host then CSRO.HOST = h.host end
CSRO.hostSiap = true
lanjut()
end)
end

-- ---------- login / daftar ----------
-- data akun tersimpan (tetap ada walau sudah keluar), dipakai buat isi otomatis form Masuk
-- akun aplikasi CSR sendiri (pref user_name / user_password, sama kayak main.lua)
function CSRO.akunCsr()
local prefs = PreferenceManager.getDefaultSharedPreferences(service)
local all = prefs.getAll()
local u, p = all.get("user_name"), all.get("user_password")
u = u ~= nil and tostring(u) or ""
p = p ~= nil and tostring(p) or ""
return u, p
end

function CSRO.kredensial()
if CSRO.sesi and CSRO.sesi.username and CSRO.sesi.password and CSRO.sesi.password ~= "" then
return { username = CSRO.sesi.username, password = CSRO.sesi.password }
end
local au, ap = CSRO.akunCsr()
if au ~= "" and ap ~= "" then return { username = au, password = ap } end
local s = dapatkanString("csr_kredensial", "")
if s ~= "" then
local ok, k = pcall(cjson.decode, s)
if ok and type(k) == "table" and k.username and k.password and k.password ~= "" then return k end
end
return nil
end

function CSRO.lupakan() simpanString("csr_kredensial", "") end

function CSRO.dialogAkun(judul, tombolOk, onOk, onBatal, isiOtomatis)
local d = UI_Dialog(judul)
local lay = UI_Layout(
UI_Input("etCsrU", T("csr_nama_pengguna", "Nama pengguna")),
UI_Input("etCsrP", T("csr_kata_sandi", "Kata sandi"))
)
d.setView(loadlayout(lay))
local kred = isiOtomatis and CSRO.kredensial() or nil
if kred then
etCsrU.setText(tostring(kred.username))
etCsrP.setText(tostring(kred.password))
service.speak(T("csr_terisi_otomatis", "Nama pengguna dan kata sandi tersimpan sudah terisi. Tinggal tekan Masuk."))
end
pcall(function()
etCsrP.setTransformationMethod(luajava.bindClass("android.text.method.PasswordTransformationMethod").getInstance())
end)
d.setButton(tombolOk, function()
local u = tostring(etCsrU.getText()):match("^%s*(.-)%s*$") or ""
local p = tostring(etCsrP.getText())
d.dismiss()
onOk(u, p)
end)
d.setButton2(T("batal", "Batal"), function() d.dismiss(); if onBatal then onBatal() end end)
d.setOnCancelListener(function() if onBatal then onBatal() end end)
d.show()
end

function CSRO.Login(u, p, onOk, onBatal)
if u == "" or p == "" then
service.speak(T("csr_data_kurang", "Nama pengguna dan kata sandi wajib diisi."))
if onBatal then onBatal() end
return
end
local dev = CSRO.deviceId()
if dev == "" then
service.speak(T("csr_dev_gagal", "Gagal membaca ID perangkat."))
if onBatal then onBatal() end
return
end
jalankanTaskLoading(T("csr_masuk_proses", "Masuk ke akun Official CSR..."), CSRO.kerja,
cjson.encode({ aksi = "post", url = CSRO.AUTH .. "/login", body = cjson.encode({ username = u, password = p, deviceid = dev }) }), function(h)
local d = {}
pcall(function() d = cjson.decode(tostring(h.body)) end)
if type(d) ~= "table" then d = {} end
if h.code == 200 and d.SID then
CSRO.sesi = { username = d.Username or u, SID = d.SID, password = p }
CSRO.simpanSesi()
simpanString("csr_kredensial", cjson.encode({ username = CSRO.sesi.username, password = p }))
service.speak(T("csr_berhasil_masuk", "Berhasil masuk sebagai ") .. tostring(CSRO.sesi.username))
if onOk then onOk() end
else
CSRO.pesan(T("csr_gagal_masuk", "Gagal masuk"), tostring(d.Error or h.err or ("Kode " .. tostring(h.code))), onBatal)
end
end)
end

function CSRO.Daftar(u, p, onOk, onBatal)
if u == "" or p == "" then
service.speak(T("csr_data_kurang", "Nama pengguna dan kata sandi wajib diisi."))
if onBatal then onBatal() end
return
end
jalankanTaskLoading(T("csr_daftar_proses", "Membuat akun Official CSR..."), CSRO.kerja,
cjson.encode({ aksi = "post", url = CSRO.AUTH .. "/reg", body = cjson.encode({ username = u, password = p, InviteCode = CSRO.INVITE }) }), function(h)
local d = {}
pcall(function() d = cjson.decode(tostring(h.body)) end)
if type(d) ~= "table" then d = {} end
if (h.code == 200 or h.code == 201) and not d.Error then
service.speak(T("csr_akun_dibuat", "Akun dibuat. Masuk otomatis."))
CSRO.Login(u, p, onOk, onBatal)
else
CSRO.pesan(T("csr_gagal_daftar", "Gagal membuat akun"), tostring(d.Error or h.err or ("Kode " .. tostring(h.code))), onBatal)
end
end)
end

function CSRO.Keluar()
CSRO.sesi = nil
CSRO.simpanSesi()
end

function CSRO.FormMasuk(onOk, onBatal)
CSRO.dialogAkun(T("csr_masuk_tombol", "Masuk"), T("csr_masuk_tombol", "Masuk"), function(u, p) CSRO.Login(u, p, onOk, onBatal) end, onBatal, true)
end

function CSRO.FormDaftar(onOk, onBatal)
CSRO.dialogAkun(T("csr_buat_akun", "Buat Akun"), T("csr_buat_akun", "Buat Akun"), function(u, p) CSRO.Daftar(u, p, onOk, onBatal) end, onBatal)
end

-- Wajib punya akun untuk upload
function CSRO.Gerbang(onOk, onBatal)
if CSRO.sesi then onOk(); return end
local d = UI_Dialog(T("csr_akun_judul", "Akun Official CSR"))
d.setMessage(T("csr_perlu_akun", "Upload ke Official CSR wajib punya akun. Masuk atau buat akun dulu."))
d.setButton(T("csr_masuk_tombol", "Masuk"), function() d.dismiss(); CSRO.FormMasuk(onOk, onBatal) end)
d.setButton2(T("csr_buat_akun", "Buat Akun"), function() d.dismiss(); CSRO.FormDaftar(onOk, onBatal) end)
d.setButton3(T("batal", "Batal"), function() d.dismiss(); if onBatal then onBatal() end end)
d.setOnCancelListener(function() if onBatal then onBatal() end end)
d.show()
end

-- ---------- unduh ----------
-- Ubah satu berkas katalog menjadi item yang kompatibel dengan BukaDaftarTema / ProsesUnduhSekuensial
function CSRO.buatItem(f)
local nama = tostring(f.filename or "")
local base = (nama:gsub("%.%w+$", ""))
local u = base:match("^[Jj][Ii][Ee][Ss][Hh][Uu][Oo]_(.+)$")
if not u then u = base:match("^.*_([^_]+)$") end
if not u or u == "" then u = T("tidak_diketahui", "Tidak Diketahui") end
local Enc = luajava.bindClass("java.net.URLEncoder")
local e = (tostring(Enc.encode(nama, "UTF-8")):gsub("%+", "%%20"))
return {
cleanName = base, uploader = u, fileName = nama, path = "csr/" .. nama,
url = CSRO.HOST .. "/sound/" .. e, resmi = true
}
end

-- ctx = { Unduh = ProsesUnduhSekuensial, BukaDaftarTema = BukaDaftarTema, kembali = fungsi }
-- Cara tampil dipilih tiap kali buka (tidak disimpan otomatis): per halaman (cepat) atau seluruhnya.
function CSRO.Unduh(ctx)
CSRO.siapkanHost(function() CSRO.PilihMode(ctx) end)
end

function CSRO.PilihMode(ctx)
local d = UI_Dialog(T("csr_mode_judul", "Cara Menampilkan Tema Official CSR"))
local lay = UI_Layout(
UI_Tombol("btnCsrModeHal", T("csr_mode_halaman", "Per Halaman (Cepat)")),
UI_Tombol("btnCsrModeSemua", T("csr_mode_semua", "Seluruhnya Tanpa Halaman (Bisa Lama)")),
UI_Tombol("btnCsrModeBatal", T("kembali", "Kembali"))
)
d.setView(loadlayout(lay))
btnCsrModeHal.onClick = function() d.dismiss(); CSRO.BukaHalaman(ctx, 1, "") end
btnCsrModeSemua.onClick = function() d.dismiss(); CSRO.BukaSemua(ctx) end
btnCsrModeBatal.onClick = function() d.dismiss(); ctx.kembali() end
d.setOnCancelListener(function() ctx.kembali() end)
d.show()
end

function CSRO.BukaHalaman(ctx, p, cari)
jalankanTaskLoading(T("csr_mengambil", "Mengambil daftar tema Official CSR..."), CSRO.kerja,
cjson.encode({ aksi = "katalog", katalog = CSRO.KATALOG, p = p, cari = cari or "", bahasa = CSRO.bahasa() }), function(h)
if not h.ok then
service.speak(T("gagal_ambil_data", "Gagal mengambil data dari server. Periksa jaringan Anda."))
ctx.kembali()
return
end
local items = {}
for i = 1, #(h.files or {}) do items[#items + 1] = CSRO.buatItem(h.files[i]) end
if #items == 0 then
service.speak(T("folder_kosong", "Folder ini masih kosong."))
if (cari or "") ~= "" then CSRO.BukaHalaman(ctx, 1, "") else ctx.kembali() end
return
end
local total = tonumber(h.total) or 1
local d = UI_Dialog(T("csr_halaman", "Official CSR, halaman ") .. p .. "/" .. total)
local lay = UI_Layout(
UI_Daftar("lvCsrHal"),
{LinearLayout, orientation="horizontal", layout_width="fill",
UI_Tombol_H("btnCsrPrev", T("csr_sebelumnya", "Sebelumnya")),
UI_Tombol_H("btnCsrNext", T("csr_berikutnya", "Berikutnya"))},
{LinearLayout, orientation="horizontal", layout_width="fill",
UI_Tombol_H("btnCsrCari", T("csr_cari", "Cari")),
UI_Tombol_H("btnCsrMode", T("csr_ubah_mode", "Ubah Mode"))},
UI_Tombol("btnCsrKembali", T("kembali", "Kembali"))
)
d.setView(loadlayout(lay))
local arr = ArrayList()
for i = 1, #items do arr.add(items[i].cleanName .. "\n" .. T("diupload_oleh", "Oleh: ") .. items[i].uploader) end
lvCsrHal.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, arr))
lvCsrHal.onItemClick = function(l, v, pos, id)
local it = items[pos + 1]
showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("yakin_unduh", "Apakah Anda yakin ingin mendownload tema suara ini?\n\n") .. it.cleanName, function()
d.dismiss()
ctx.Unduh({ it }, function() CSRO.BukaHalaman(ctx, p, cari) end)
end)
end
btnCsrPrev.onClick = function()
if p > 1 then d.dismiss(); CSRO.BukaHalaman(ctx, p - 1, cari)
else service.speak(T("csr_halaman_pertama", "Ini halaman pertama.")) end
end
btnCsrNext.onClick = function()
if p < total then d.dismiss(); CSRO.BukaHalaman(ctx, p + 1, cari)
else service.speak(T("csr_halaman_terakhir", "Ini halaman terakhir.")) end
end
btnCsrCari.onClick = function()
showInputDialog(T("csr_cari", "Cari"), T("cari_tema", "Cari tema..."), cari or "", function(txt)
d.dismiss()
CSRO.BukaHalaman(ctx, 1, txt)
end, nil, true)
end
btnCsrMode.onClick = function() d.dismiss(); CSRO.PilihMode(ctx) end
btnCsrKembali.onClick = function() d.dismiss(); ctx.kembali() end
d.setOnCancelListener(function() ctx.kembali() end)
d.show()
end)
end

function CSRO.BukaSemua(ctx)
local function tampil(files)
local items = {}
for i = 1, #files do items[#items + 1] = CSRO.buatItem(files[i]) end
if #items == 0 then
service.speak(T("folder_kosong", "Folder ini masih kosong."))
CSRO.PilihMode(ctx)
return
end
ctx.BukaDaftarTema(items, T("csr_semua_judul", "Seluruh Tema Official CSR"), function() CSRO.PilihMode(ctx) end)
end
if CSRO.cacheSemua and (os.time() - CSRO.cacheWaktu) < 1800 then tampil(CSRO.cacheSemua); return end
-- Langkah 1: ambil halaman 1 (dapat total halaman). Langkah 2: sisa halaman diambil PARALEL (4 worker) biar tidak lemot.
jalankanTaskLoading(T("csr_mengambil_semua", "Mengumpulkan seluruh daftar Official CSR. Bisa agak lama..."), CSRO.kerja,
cjson.encode({ aksi = "katalog", katalog = CSRO.KATALOG, p = 1, cari = "", bahasa = CSRO.bahasa() }), function(h)
if not h.ok then
service.speak(T("gagal_ambil_data", "Gagal mengambil data dari server. Periksa jaringan Anda."))
CSRO.PilihMode(ctx)
return
end
local hasil1 = h.files or {}
local akhir = math.min(tonumber(h.total) or 1, 60)
local function selesaiSemua(daftar, lengkap)
if lengkap then CSRO.cacheSemua = daftar; CSRO.cacheWaktu = os.time() end
tampil(daftar)
end
if akhir <= 1 then selesaiSemua(hasil1, true); return end
local bagian = 4
local per = math.ceil((akhir - 1) / bagian)
local loading = nil
if not (ProgresJam and ProgresJam.aktif) then
loading = UI_Dialog(T("mohon_tunggu", "Mohon Tunggu"))
loading.setMessage(T("csr_mengambil_semua", "Mengumpulkan seluruh daftar Official CSR. Bisa agak lama..."))
loading.setCancelable(false)
loading.show()
end
local hasilBagian, jumlah, kembali, gagal = {}, 0, 0, false
for b = 1, bagian do
local dari = 2 + (b - 1) * per
local sampai = math.min(dari + per - 1, akhir)
if dari <= akhir then
jumlah = jumlah + 1
local idx = jumlah
task(CSRO.kerja, cjson.encode({ aksi = "rentang", katalog = CSRO.KATALOG, p = dari, sampai = sampai, cari = "", bahasa = h.bhs or CSRO.bahasa() }), function(json)
local r = {}
pcall(function() r = cjson.decode(tostring(json)) end)
if r.ok then hasilBagian[idx] = r.files or {} else gagal = true end
kembali = kembali + 1
if kembali == jumlah then
if loading then pcall(function() loading.dismiss() end) end
-- gabung sesuai urutan bagian supaya urutan A-Z tetap
local semua = {}
for i = 1, #hasil1 do semua[#semua + 1] = hasil1[i] end
for i = 1, jumlah do
local bag = hasilBagian[i] or {}
for j = 1, #bag do semua[#semua + 1] = bag[j] end
end
if gagal then service.speak(T("csr_sebagian_gagal", "Sebagian halaman gagal diambil. Daftar mungkin belum lengkap.")) end
selesaiSemua(semua, not gagal) -- cache hanya kalau lengkap
end
end)
end
end
end)
end

-- ---------- upload ----------
-- zipFn = jalankanZipTask(pesan, {{src=, out=}}, onSelesai)
function CSRO.UploadTema(folder, zipFn, onSelesai)
local nama = "jieshuo_" .. tostring(CSRO.sesi.username) .. ".spk"
local function fin() if onSelesai then onSelesai() end end
showConfirmDialog(T("csr_konfirmasi_upload", "Upload ke Official CSR"),
T("csr_peringatan_upload", "Tema ini akan tampil PUBLIK untuk semua pengguna CSR dan menimpa tema Official milik akunmu yang lama (satu akun hanya satu tema).\n\nLanjut upload?"),
function()
CSRO.siapkanHost(function()
local tmp = File("/storage/emulated/0/.temp_upload_nadi")
if not tmp.exists() then tmp.mkdirs() end
local zipPath = tmp.getAbsolutePath() .. "/" .. nama
zipFn(T("csr_mengompres", "Mengompres tema..."), { { src = File(folder).getAbsolutePath(), out = zipPath } }, function()
jalankanTaskLoading(T("csr_mengunggah", "Mengunggah ke Official CSR..."), CSRO.kerja,
cjson.encode({ aksi = "upload", url = CSRO.HOST .. "/sound/upload.php", user = CSRO.sesi.username, nama = nama,
nameFile = jieshuoPath .. "/.temp/" .. nama, path = zipPath }), function(h)
if h.ok then
CSRO.cacheSemua = nil
CSRO.pesan(T("sukses", "Berhasil"), T("csr_upload_sukses", "Tema berhasil diunggah ke Official CSR."), fin)
else
CSRO.pesan(T("csr_upload_gagal", "Gagal mengunggah"), tostring(h.body or h.err or h.code), fin)
end
end)
end)
end)
end, fin)
end

function CSRO.HapusSaya(onSelesai)
local function fin() if onSelesai then onSelesai() end end
CSRO.Gerbang(function()
showConfirmDialog(T("csr_hapus_judul", "Hapus Tema Saya"),
T("csr_hapus_pesan", "Tema Official CSR milik akunmu akan dihapus dari server. Tindakan ini tidak bisa dibatalkan.\n\nLanjut?"),
function()
CSRO.siapkanHost(function()
jalankanTaskLoading(T("csr_menghapus", "Menghapus tema dari Official CSR..."), CSRO.kerja,
cjson.encode({ aksi = "hapus", url = CSRO.HOST .. "/sound/delete.php", user = CSRO.sesi.username,
password = CSRO.sesi.password or "", nama = "jieshuo_" .. tostring(CSRO.sesi.username) .. ".spk" }), function(h)
if h.ok then
CSRO.cacheSemua = nil
CSRO.pesan(T("sukses", "Berhasil"), T("csr_hapus_sukses", "Tema berhasil dihapus."), fin)
else
CSRO.pesan(T("gagal", "Gagal"), tostring(h.body or h.err or h.code), fin)
end
end)
end)
end, fin)
end, fin)
end

-- ---------- salin ke clipboard (versi aman) ----------
function CSRO.salinAman(label, teks)
local cm = service.getSystemService(Context.CLIPBOARD_SERVICE)
local clip = ClipData.newPlainText(label, teks)
-- Android 13+: tandai sensitif biar isinya tidak muncul di preview clipboard (di bawah 13 flag ini diabaikan)
pcall(function()
local b = luajava.bindClass("android.os.PersistableBundle")()
b.putBoolean("android.content.extra.IS_SENSITIVE", true)
clip.getDescription().setExtras(b)
end)
cm.setPrimaryClip(clip)
-- auto-bersihkan clipboard setelah 30 detik, hanya kalau isinya masih sama
Thread(Runnable({ run = function()
pcall(function()
luajava.bindClass("java.lang.Thread").sleep(30000)
local cur = cm.getPrimaryClip()
if cur and cur.getItemCount() > 0 and tostring(cur.getItemAt(0).getText()) == teks then
cm.setPrimaryClip(ClipData.newPlainText("", ""))
end
end)
end })).start()
end

-- ---------- pengaturan ----------
function CSRO.Pengaturan(onKembali)
local d = UI_Dialog(T("csr_pengaturan_judul", "Pengaturan Komunitas Tema Suara CSR"))
local lv = ListView(service)
local arr = ArrayList()
local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, arr)
lv.setAdapter(adapter)
local data = {}
local function isi()
data = {}
if CSRO.sesi then
data[#data + 1] = { id = "info", t = T("csr_akun_status", "Akun: ") .. tostring(CSRO.sesi.username) }
data[#data + 1] = { id = "salin_user", t = T("csr_salin_pengguna", "Salin Nama Pengguna") }
data[#data + 1] = { id = "salin_sandi", t = T("csr_salin_sandi", "Salin Kata Sandi") }
data[#data + 1] = { id = "lihat_sandi", t = T("csr_lihat_sandi", "Lihat Nama Pengguna dan Kata Sandi") }
data[#data + 1] = { id = "hapus", t = T("csr_hapus_judul", "Hapus Tema Saya") }
data[#data + 1] = { id = "keluar", t = T("csr_keluar", "Keluar dari Akun") }
else
data[#data + 1] = { id = "masuk", t = T("csr_masuk_tombol", "Masuk") }
data[#data + 1] = { id = "daftar", t = T("csr_buat_akun", "Buat Akun") }
if CSRO.kredensial() then data[#data + 1] = { id = "lupakan", t = T("csr_lupakan", "Hapus Data Akun Tersimpan") } end
end
arr.clear()
for i = 1, #data do arr.add(data[i].t) end
adapter.notifyDataSetChanged()
end
isi()
d.setView(lv)
local function buka() d.dismiss(); CSRO.Pengaturan(onKembali) end
lv.onItemClick = function(l, v, pos, id)
local x = data[pos + 1].id
if x == "masuk" then d.dismiss(); CSRO.FormMasuk(function() CSRO.Pengaturan(onKembali) end, function() CSRO.Pengaturan(onKembali) end)
elseif x == "daftar" then d.dismiss(); CSRO.FormDaftar(function() CSRO.Pengaturan(onKembali) end, function() CSRO.Pengaturan(onKembali) end)
elseif x == "salin_user" then
CSRO.salinAman("csr_user", tostring(CSRO.sesi.username))
service.speak(T("csr_pengguna_tersalin", "Nama pengguna tersalin."))
elseif x == "salin_sandi" then
local pw = tostring(CSRO.sesi.password or "")
if pw == "" then service.speak(T("csr_sandi_kosong", "Kata sandi tidak tersimpan di perangkat ini. Silakan keluar lalu masuk lagi."))
else
CSRO.salinAman("csr_pass", pw)
service.speak(T("csr_sandi_tersalin", "Kata sandi tersalin. Clipboard dibersihkan otomatis dalam 30 detik."))
end
elseif x == "lihat_sandi" then
local pw = tostring(CSRO.sesi.password or "")
if pw == "" then pw = T("csr_sandi_kosong_singkat", "(tidak tersimpan)") end
d.dismiss()
CSRO.pesan(T("csr_akun_judul", "Akun Official CSR"),
T("csr_nama_pengguna", "Nama pengguna") .. ": " .. tostring(CSRO.sesi.username) .. "\n" .. T("csr_kata_sandi", "Kata sandi") .. ": " .. pw,
function() CSRO.Pengaturan(onKembali) end)
elseif x == "lupakan" then CSRO.lupakan(); service.speak(T("csr_sudah_lupa", "Data akun tersimpan dihapus.")); isi()
elseif x == "keluar" then CSRO.Keluar(); service.speak(T("csr_sudah_keluar", "Sudah keluar dari akun.")); isi()
elseif x == "hapus" then d.dismiss(); CSRO.HapusSaya(function() CSRO.Pengaturan(onKembali) end)
end
end
d.setButton(T("tutup", "Tutup"), function() d.dismiss(); if onKembali then onKembali() end end)
d.setOnCancelListener(function() if onKembali then onKembali() end end)
d.show()
end

CSRO.muatSesi()


btnKomunitasUtama.onClick = function()
dialogUtama.dismiss()

local function BukaMenuKomunitas()
local dKomunitas = UI_Dialog(T("komunitas_tema", "Komunitas Tema Suara"))
local layKomunitas = UI_Layout(
UI_Tombol("btnUnduhKomunitas", T("unduh_tema_komunitas", "Unduh Tema Suara")),
UI_Tombol("btnUploadKomunitas", T("upload_tema_komunitas", "Upload Tema Suara")),
UI_Tombol("btnTutupKomunitas", T("tutup", "Tutup"))
)
dKomunitas.setView(loadlayout(layKomunitas))

btnUnduhKomunitas.onClick = function()
dKomunitas.dismiss()
local myId = DapatkanAndroidID()

-- Forward declarations agar tidak error "nil value"
local BukaPemilihFolder, FetchDataGitHub, BukaModeTampilan, BukaDaftarTema, ProsesUnduhSekuensial, EksekusiHapusServer

EksekusiHapusServer = function(item, onBerhasil)
local argsHapus = { token = dapatkanString("github_admin_token", ""), fileName = item.fileName, sha = item.sha, path = item.path, repo = item.repo }
jalankanTaskLoading(T("menghapus_server", "Menghapus file dari server..."), kerjaHapusServer, cjson.encode(argsHapus), function(hasil)
if hasil.sukses == true then service.speak(T("hapus_sukses", "Berhasil dihapus dari server")); onBerhasil()
else service.speak(T("hapus_gagal", "Gagal menghapus file dari server.")) end
end)
end

ProsesUnduhSekuensial = function(antrean, onSelesaiTotal)
local targetFolder = File("/storage/emulated/0/Download/Tema Suara")
if not targetFolder.exists() then targetFolder.mkdirs() end

local total = #antrean
local successCount = 0
local downloadedFiles = {}
local galatUnduh = ""

local dProses = UI_Dialog(T("mengunduh", "Mengunduh..."))
dProses.setMessage(T("mohon_tunggu", "Mohon tunggu..."))
dProses.setCancelable(false)
dProses.show()

local function selesaiUnduh()
dProses.dismiss()

if successCount == 0 then
local dGagal = UI_Dialog(T("gagal", "Gagal"))
dGagal.setMessage(T("unduh_gagal_semua", "Semua unduhan gagal. Periksa koneksi jaringan Anda.") .. (galatUnduh ~= "" and ("\n\nDetail: " .. galatUnduh) or ""))
dGagal.setButton(T("tutup", "Tutup"), function() if onSelesaiTotal then onSelesaiTotal() end end)
dGagal.show()
return
end

local dAksi = UI_Dialog(T("unduh_selesai", "Unduh Selesai"))
dAksi.setMessage(T("unduh_sukses_pesan", "Berhasil mengunduh ") .. successCount .. T("dari", " dari ") .. total .. T("tema_tersimpan_di", " tema. File SPK telah tersimpan permanen di folder Download/Tema Suara.\n\nApa yang ingin Anda lakukan selanjutnya?"))

local function LakukanImpor(terapkanJuga)
local antreanImpor = {}
for i = 1, #downloadedFiles do
local spkFile = File(downloadedFiles[i])
if spkFile.exists() then table.insert(antreanImpor, spkFile.getAbsolutePath()) end
end

if #antreanImpor > 0 then
-- Melempar antrean ke mesin impor SPK bawaan (nilai 'nil' agar memunculkan dialog jika ada konflik nama)
prosesAntreanSPK(antreanImpor, 1, nil, {}, function(importedThemes)
for d = 1, #downloadedFiles do local fDel = File(downloadedFiles[d]); if fDel.exists() then fDel.delete() end end
if terapkanJuga and #importedThemes > 0 then
if #importedThemes == 1 then
local tDipilih = importedThemes[1]
PreferenceManager.getDefaultSharedPreferences(service).edit().putString("sound_package", tDipilih).apply()
service.loadSoundPackage(tDipilih)
service.speak(tDipilih .. " " .. T("status_aktif", "Aktif"))
if onSelesaiTotal then onSelesaiTotal() end
else
local dPilih = UI_Dialog(T("pilih_tema_diterapkan", "Pilih Tema untuk Diterapkan"))
local lvPilih = ListView(service)
local listPilih = ArrayList()
for i = 1, #importedThemes do listPilih.add(importedThemes[i]) end
lvPilih.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, listPilih))
dPilih.setView(lvPilih)
lvPilih.onItemClick = function(lP, vP, pP, idP)
local tDipilih = importedThemes[pP + 1]
PreferenceManager.getDefaultSharedPreferences(service).edit().putString("sound_package", tDipilih).apply()
service.loadSoundPackage(tDipilih)
service.speak(tDipilih .. " " .. T("status_aktif", "Aktif"))
dPilih.dismiss()
if onSelesaiTotal then onSelesaiTotal() end
end
dPilih.setButton(T("tutup", "Tutup"), function() dPilih.dismiss(); if onSelesaiTotal then onSelesaiTotal() end end)
dPilih.setOnCancelListener(function() if onSelesaiTotal then onSelesaiTotal() end end)
dPilih.show()
end
else
if #importedThemes > 0 then service.speak(T("sukses_impor", "Tema berhasil diimpor!")) end
if onSelesaiTotal then onSelesaiTotal() end
end
end)
end
end

dAksi.setButton(T("impor", "Impor"), function() LakukanImpor(false) end)
dAksi.setButton2(T("impor_terapkan", "Impor & Terapkan"), function() LakukanImpor(true) end)
dAksi.setButton3(T("tutup", "Tutup"), function() if onSelesaiTotal then onSelesaiTotal() end end)
dAksi.setOnCancelListener(function() if onSelesaiTotal then onSelesaiTotal() end end)
dAksi.setCancelable(false)
dAksi.show()
end

local hentikanPoller = mulaiPollerProgres(dProses)
task(kerjaUnduhSpk, cjson.encode({ items = antrean, folder = targetFolder.getAbsolutePath(), token = AKUN.tokenPrivat(), lbl = T("mengunduh", "Mengunduh: ") }), function(json)
hentikanPoller()
local r = {}
pcall(function() r = cjson.decode(tostring(json)) end)
downloadedFiles = r.files or {}
galatUnduh = r.galat or ""
successCount = #downloadedFiles
selesaiUnduh()
end)
end

BukaDaftarTema = function(listTemaInput, judul, onBack)
local dDaftar = UI_Dialog(judul)
-- PENTING: jangan pakai "local btnPilihSemuaTema" di sini. Variabel lokal akan menutupi tombol asli
-- yang dibuat loadlayout, sehingga onClick terpasang di tabel layout (bukan di tombol) dan tidak berfungsi.
local defPilihSemuaTema = UI_Tombol_H("btnPilihSemuaTema", T("pilih_semua", "Pilih Semua"))
local defBatalPilihTema = UI_Tombol_H("btnBatalPilihTema", T("batal_pilih", "Batal Pilih"))
local layBtnPilih = {LinearLayout, id="layoutAksiPilihTema", orientation="horizontal", layout_width="fill", layout_marginBottom="8dp", visibility=8, defPilihSemuaTema, defBatalPilihTema}

local layDaftar = UI_Layout(
UI_Input("etCariTema", T("cari_tema", "Cari tema...")),
UI_Tombol("btnModePilihTema", T("mode_pilih", "Aktifkan Mode Pemilihan")),
layBtnPilih,
UI_Daftar("lvDaftarTema"),
{LinearLayout, orientation="horizontal", layout_width="fill",
UI_Tombol_H("btnTutupDaftarTema", T("kembali", "Kembali")),
UI_Tombol_H("btnUnduhTema", T("unduh_terpilih", "Unduh Terpilih (0)"))
}
)
dDaftar.setView(loadlayout(layDaftar))

local itemLayout = UI_ItemBaris("cbItem", "tvName")
local listData = {}
local selectedItems = {}
local isSelectionMode = false
local adapter = nil

local function updateBtnUnduh()
local count = 0
for k, v in pairs(selectedItems) do count = count + 1 end
btnUnduhTema.setText(T("unduh_terpilih", "Unduh Terpilih") .. " (" .. count .. ")")
if count > 0 then btnUnduhTema.setVisibility(0) else btnUnduhTema.setVisibility(8) end
end

local function refreshList(query)
for i = #listData, 1, -1 do table.remove(listData, i) end
local q = tostring(query):lower()
for i = 1, #listTemaInput do
local item = listTemaInput[i]
if q == "" or string.find(item.cleanName:lower(), q, 1, true) or string.find(item.uploader:lower(), q, 1, true) then
table.insert(listData, {
cbItem = {visibility = isSelectionMode and 0 or 8, checked = (selectedItems[item.path] ~= nil)},
tvName = item.cleanName .. "\n" .. T("diupload_oleh", "Oleh: ") .. item.uploader,
_data = item
})
end
end
if not adapter then
adapter = LuaAdapter(service, listData, itemLayout)
lvDaftarTema.setAdapter(adapter)
else
adapter.notifyDataSetChanged()
end
end

refreshList("")
updateBtnUnduh()

etCariTema.addTextChangedListener(TextWatcher{ onTextChanged = function(c) refreshList(tostring(c)) end })

btnModePilihTema.onClick = function()
isSelectionMode = not isSelectionMode
if isSelectionMode then
btnModePilihTema.setText(T("batal_mode_pilih", "Batal Mode Pemilihan"))
layoutAksiPilihTema.setVisibility(0)
else
btnModePilihTema.setText(T("mode_pilih", "Aktifkan Mode Pemilihan"))
layoutAksiPilihTema.setVisibility(8)
selectedItems = {}
end
refreshList(tostring(etCariTema.getText()))
updateBtnUnduh()
end

btnPilihSemuaTema.onClick = function()
for i = 1, #listData do
selectedItems[listData[i]._data.path] = listData[i]._data
listData[i].cbItem.checked = true
end
adapter.notifyDataSetChanged()
updateBtnUnduh()
end

btnBatalPilihTema.onClick = function()
selectedItems = {}
for i = 1, #listData do listData[i].cbItem.checked = false end
adapter.notifyDataSetChanged()
updateBtnUnduh()
end

lvDaftarTema.onItemClick = function(l, v, p, id)
local itemUI = listData[p+1]
local itemData = itemUI._data
if isSelectionMode then
if selectedItems[itemData.path] then
selectedItems[itemData.path] = nil
itemUI.cbItem.checked = false
else
selectedItems[itemData.path] = itemData
itemUI.cbItem.checked = true
end
adapter.notifyDataSetChanged()
updateBtnUnduh()
else
showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("yakin_unduh", "Apakah Anda yakin ingin mendownload tema suara ini?\n\n") .. itemData.cleanName, function()
dDaftar.dismiss()
ProsesUnduhSekuensial({itemData}, onBack)
end)
end
end

lvDaftarTema.onItemLongClick = function(l, v, p, id)
if isSelectionMode then return true end
local isAdminUtama = ADMIN_IDS[myId] or (ID_CREATORS[myId])
local tokenValid = dapatkanString("github_admin_token", "") ~= ""

-- Validasi Gaib (Silent Reject)
if not isAdminUtama or not tokenValid then return true end

local itemData = listData[p+1]._data
if itemData.resmi then return true end
showConfirmDialog(T("hapus_server", "Hapus dari Server"), T("yakin_hapus_server", "PERINGATAN: Tindakan ini akan menghapus tema ini secara permanen dari server Komunitas.\n\nTema: ") .. itemData.cleanName, function()
EksekusiHapusServer(itemData, function()
for i=#listTemaInput, 1, -1 do
if listTemaInput[i].path == itemData.path then table.remove(listTemaInput, i); break end
end
refreshList(tostring(etCariTema.getText()))
end)
end)
return true
end

btnTutupDaftarTema.onClick = function() dDaftar.dismiss(); if onBack then onBack() end end
dDaftar.setOnCancelListener(function() if onBack then onBack() end end)

btnUnduhTema.onClick = function()
local antrean = {}
for k, v in pairs(selectedItems) do table.insert(antrean, v) end
if #antrean == 0 then return end
dDaftar.dismiss()
ProsesUnduhSekuensial(antrean, onBack)
end

dDaftar.show()
end

BukaModeTampilan = function(semuaData, folderTarget)
local dMode = UI_Dialog(T("cara_menampilkan", "Cara Menampilkan Tema"))
local layMode = UI_Layout(
UI_Tombol("btnModeSemua", T("tampilkan_semua_tema", "Tampilkan Seluruh Tema (A-Z)")),
UI_Tombol("btnModePengguna", T("berdasarkan_pengguna", "Berdasarkan Nama Pengguna")),
UI_Tombol("btnBatalMode", T("kembali", "Kembali"))
)
dMode.setView(loadlayout(layMode))

local function BukaDaftarPengguna()
local dPengguna = UI_Dialog(T("daftar_pengguna", "Daftar Pengguna"))
local layPengguna = UI_Layout(
UI_Input("etCariPengguna", T("cari_pengguna", "Cari pengguna...")),
UI_Daftar("lvPengguna"),
UI_Tombol("btnTutupPengguna", T("kembali", "Kembali"))
)
dPengguna.setView(loadlayout(layPengguna))

local mapPengguna = {}
for i=1, #semuaData do
local u = semuaData[i].uploader
if not mapPengguna[u] then mapPengguna[u] = {} end
table.insert(mapPengguna[u], semuaData[i])
end

local listUploader = {}
for u, _ in pairs(mapPengguna) do table.insert(listUploader, u) end
table.sort(listUploader, function(a,b) return string.lower(a) < string.lower(b) end)

local adapterP = nil
local listDataP = {}

local function refreshPengguna(query)
for i=#listDataP, 1, -1 do table.remove(listDataP, i) end
local q = tostring(query):lower()
for i=1, #listUploader do
if q == "" or string.find(listUploader[i]:lower(), q, 1, true) then
listDataP[#listDataP+1] = listUploader[i]
end
end
if not adapterP then
adapterP = ArrayAdapter(service, android.R.layout.simple_list_item_1, listDataP)
lvPengguna.setAdapter(adapterP)
else
adapterP.notifyDataSetChanged()
end
end

refreshPengguna("")
etCariPengguna.addTextChangedListener(TextWatcher{ onTextChanged = function(c) refreshPengguna(tostring(c)) end })

lvPengguna.onItemClick = function(l, v, p, id)
dPengguna.dismiss()
local uploaderDipilih = listDataP[p+1]
BukaDaftarTema(mapPengguna[uploaderDipilih], T("tema_milik", "Tema Milik: ") .. uploaderDipilih, function() BukaDaftarPengguna() end)
end

btnTutupPengguna.onClick = function() dPengguna.dismiss(); BukaModeTampilan(semuaData, folderTarget) end
dPengguna.setOnCancelListener(function() BukaModeTampilan(semuaData, folderTarget) end)
dPengguna.show()
end

btnModeSemua.onClick = function() dMode.dismiss(); BukaDaftarTema(semuaData, T("semua_tema", "Seluruh Tema (A-Z)"), function() BukaModeTampilan(semuaData, folderTarget) end) end
btnModePengguna.onClick = function() dMode.dismiss(); BukaDaftarPengguna() end
btnBatalMode.onClick = function() dMode.dismiss(); BukaPemilihFolder() end
dMode.setOnCancelListener(function() BukaPemilihFolder() end)
dMode.show()
end

FetchDataGitHub = function(folderTarget)
local privat = (string.sub(folderTarget, 1, #AKUN.SLOT_UTAMA) == AKUN.SLOT_UTAMA) -- folder Tema Admin
local tokenPakai = privat and AKUN.tokenPrivat() or dapatkanString("github_admin_token", "")
if privat and tokenPakai == "" then
service.speak(T("akun_token_kosong", "Token repo Tema Admin belum diatur oleh admin utama."))
BukaPemilihFolder()
return
end
local argsAmbil = { token = tokenPakai, repo = privat and AKUN.REPO_TEMA or nil, folderTarget = folderTarget, lblTakDiketahui = T("tidak_diketahui", "Tidak Diketahui") }
jalankanTaskLoading(T("mengambil_data", "Mengambil data dari server..."), kerjaAmbilDaftarKomunitas, cjson.encode(argsAmbil), function(hasil)
local data = nil
if hasil.ok == true then data = hasil.data or {} end
if data then
if #data == 0 then
service.speak(T("folder_kosong", "Folder ini masih kosong."))
BukaPemilihFolder()
else
BukaModeTampilan(data, folderTarget)
end
else
service.speak(T("gagal_ambil_data", "Gagal mengambil data dari server. Periksa jaringan Anda."))
BukaPemilihFolder()
end
end)
end

BukaPemilihFolder = function()
local dFolder = UI_Dialog(T("pilih_folder_unduh", "Pilih Kategori Tema"))
local layFolder = UI_Layout(
UI_Tombol("btnFolderPublik", T("tema_publik", "Tema Publik")),
UI_Tombol("btnFolderPrivate", T("tema_private", "Tema Private (Eksklusif)")),
UI_Tombol("btnFolderAdmin", T("tema_admin", "Tema Admin (Akun Admin)")),
UI_Tombol("btnFolderResmi", T("csr_official", "Official CSR (Toko Resmi Jieshuo)")),
UI_Tombol("btnKembaliFolder", T("kembali", "Kembali"))
)
dFolder.setView(loadlayout(layFolder))

btnFolderPublik.onClick = function() dFolder.dismiss(); FetchDataGitHub("tema_suara_publik") end
btnFolderPrivate.onClick = function()
local isAdminUtama = ADMIN_IDS[myId] or (ID_CREATORS[myId])
if not isAdminUtama then
service.speak(T("akses_ditolak", "Maaf, hanya Admin Utama yang bisa mengakses tema eksklusif ini."))
return
end
dFolder.dismiss()
FetchDataGitHub("tema_suara_private")
end
btnFolderAdmin.onClick = function()
dFolder.dismiss()
-- Admin Utama langsung masuk; Admin 2/3 wajib login akun (slot sendiri); lainnya ditolak
AKUN.gerbang(function(u) FetchDataGitHub(AKUN.folderTema(u)) end, function() BukaPemilihFolder() end)
end
btnFolderResmi.onClick = function()
dFolder.dismiss()
CSRO.Unduh({ Unduh = ProsesUnduhSekuensial, BukaDaftarTema = BukaDaftarTema, kembali = function() BukaPemilihFolder() end })
end
btnKembaliFolder.onClick = function() dFolder.dismiss(); BukaMenuKomunitas() end
dFolder.setOnCancelListener(function() BukaMenuKomunitas() end)
dFolder.show()
end

BukaPemilihFolder()
end

btnUploadKomunitas.onClick = function()
local myId = DapatkanAndroidID()
local isAdminUtama = ADMIN_IDS[myId] or (ID_CREATORS[myId])
dKomunitas.dismiss()

local function EksekusiUploadKomunitas(tipeUpload, antreanSPK, onSelesai)
local targetFolder = (tipeUpload == "private") and "tema_suara_private" or "tema_suara_publik"
if tipeUpload == "admin" then
-- Tema Admin: Admin 2/3 hanya ke slot akunnya sendiri; selain admin tidak boleh sama sekali
local peranP = AKUN.peran()
if peranP == nil or (peranP == "admin" and not AKUN.sesi) then
service.speak(T("akun_ditolak", "Maaf, tema admin hanya untuk admin."))
if onSelesai then onSelesai() else muatUlangBahasaDanMenu() end
return
end
targetFolder = AKUN.folderTema(AKUN.sesi)
end
local dProses = UI_Dialog(T("mengunggah_tema", "Mengunggah Tema..."))
dProses.setMessage(T("mohon_tunggu", "Mohon tunggu..."))
dProses.setCancelable(false)
dProses.show()

local tokenAdmin = ""
if isAdminUtama then tokenAdmin = dapatkanString("github_admin_token", "") end
local hentikanPoller = mulaiPollerProgres(dProses)
local function selesaiLanjut() if onSelesai then onSelesai() else muatUlangBahasaDanMenu() end end

task(kerjaUploadSpk, cjson.encode({ isAdmin = (isAdminUtama and true or false), token = tokenAdmin, repo = (tipeUpload == "admin") and AKUN.REPO_TEMA or nil, tokenTema = (tipeUpload == "admin") and AKUN.tokenPrivat() or nil, folder = targetFolder, items = antreanSPK, lbl = T("mengunggah", "Mengunggah: ") }), function(json)
hentikanPoller()
pcall(function() dProses.dismiss() end)
task(kerjaHapusPath, cjson.encode({ "/storage/emulated/0/.temp_upload_nadi" }), function() end)
local r = {}
pcall(function() r = cjson.decode(tostring(json)) end)
if r.status == "token_kosong" then
service.speak(T("token_kosong", "Token admin tidak ditemukan. Silakan isi di Panel Admin."))
selesaiLanjut()
elseif r.status == "gagal_token" then
service.speak(T("gagal_ambil_token", "Gagal mengambil token komunitas dari server."))
selesaiLanjut()
else
local total = r.total or #antreanSPK
local successCount = r.sukses or 0
if r.status == "selesai" and successCount == total then
local dSukses = UI_Dialog(T("sukses", "Berhasil"))
dSukses.setMessage(T("upload_selesai", "Berhasil mengunggah ") .. total .. T("tema_ke_komunitas", " tema ke komunitas!"))
dSukses.setButton(T("oke", "Oke"), function() selesaiLanjut() end)
dSukses.setCancelable(false)
dSukses.show()
else
local dGagal = UI_Dialog(T("peringatan", "Peringatan"))
dGagal.setMessage(T("upload_sebagian_gagal", "Beberapa tema gagal diunggah. Berhasil: ") .. successCount .. "/" .. total .. "\n\nError: " .. tostring(r.err or ""))
dGagal.setButton(T("oke", "Oke"), function() selesaiLanjut() end)
dGagal.setCancelable(false)
dGagal.show()
end
end
end)
end

local function ProsesUploadSPK(tipeUpload, listPathFolder, onSelesai)
if tipeUpload == "resmi" then
-- Official CSR: satu akun satu tema, wajib login, tidak lewat jatah/kuota GitHub
if #listPathFolder ~= 1 then
service.speak(T("csr_satu_tema", "Official CSR: satu akun hanya boleh satu tema. Pilih satu tema saja."))
if onSelesai then onSelesai() end
return
end
CSRO.Gerbang(function() CSRO.UploadTema(listPathFolder[1], jalankanZipTask, onSelesai) end, onSelesai)
return
end
local namaAdmin = DataAdminGlobal.admin_utama[myId] or DataAdminGlobal.admin_kedua[myId] or DataAdminGlobal.admin_ketiga[myId]
local function lanjutUpload(userName)
userName = string.gsub(userName, "%s+", "_")
local timestamp = os.date("%Y%m%d%H%M%S")

local tempUploadDir = File("/storage/emulated/0/.temp_upload_nadi")
if not tempUploadDir.exists() then tempUploadDir.mkdirs() end

local antreanSPK = {}

local itemsZip = {}
for i = 1, #listPathFolder do
local srcFolder = File(listPathFolder[i])
local themeName = string.gsub(srcFolder.getName(), "%s+", "_")
local spkName = themeName .. "_" .. timestamp .. "_" .. userName .. ".spk"
local zipPath = tempUploadDir.getAbsolutePath() .. "/" .. spkName
table.insert(itemsZip, {src = srcFolder.getAbsolutePath(), out = zipPath})
table.insert(antreanSPK, { name = spkName, path = zipPath })
end
jalankanZipTask(T("mempersiapkan_tema", "Mempersiapkan ") .. #listPathFolder .. T("tema_kompresi", " tema untuk dikompresi..."), itemsZip, function()
service.speak(T("berhasil_dikompresi", "Berhasil dikompresi. Melanjutkan ke proses upload..."))
EksekusiUploadKomunitas(tipeUpload, antreanSPK, onSelesai)
end)
end

if namaAdmin or not JATAH.AKTIF then
lanjutUpload(namaAdmin or "Free User")
else
-- Pengguna free: nama harus cocok dengan yang terdaftar di server, kalau tidak upload tidak valid
JATAH.validasiNama(function(namaSah) lanjutUpload(namaSah) end, function() if onSelesai then onSelesai() end end)
end
end

local function TampilkanPickerUpload(tipeUpload, isInternal, onBack)
local currentPath = isInternal and basePath or "/storage/emulated/0"
local judul = isInternal and T("pilih_tema_internal", "Pilih Tema Jieshuo (Internal)") or T("pilih_tema_eksternal", "Pilih Tema Eksternal")

local dPicker = UI_Dialog(judul)

local layPicker = UI_Layout(
not isInternal and {TextView, id="tvPathUP", text=currentPath, padding="10dp", layout_marginBottom="8dp", textColor="0xFF4CAF50"} or {LinearLayout, visibility=8},
UI_Input("etCariUP", T("cari_tema", "Cari tema...")),
{LinearLayout, orientation="horizontal", layout_width="fill", layout_marginBottom="8dp",
UI_Tombol_H("btnPilihSemuaUP", T("pilih_semua", "Pilih Semua")),
UI_Tombol_H("btnBatalPilihUP", T("batal_pilih", "Batal Pilih"))
},
UI_Daftar("lvUP"),
{LinearLayout, orientation="horizontal", layout_width="fill",
UI_Tombol_H("btnTutupUP", T("kembali", "Kembali")),
UI_Tombol_H("btnLanjutUpload", T("upload_terpilih", "Upload Terpilih (0)"))
}
)
dPicker.setView(loadlayout(layPicker))

local itemLayout = UI_ItemBaris("cbItem", "tvName")
local allItems = {}
local listData = {}
local selectedItems = {}
local adapter = nil

local function apakahFolderTemaKetat(dir)
local configF = File(dir.getAbsolutePath() .. "/config")
if not configF.exists() or not configF.isFile() then return false end
local anak = dir.listFiles()
if anak then
for i = 0, #anak - 1 do
if anak[i].isDirectory() then
local namaFolder = string.lower(anak[i].getName())
if namaFolder ~= "clock" and namaFolder ~= "effect" then return false end
end
end
end
return true
end

local function updateBtnUpload()
local count = 0
for k, v in pairs(selectedItems) do count = count + 1 end
btnLanjutUpload.setText(T("upload_terpilih", "Upload Terpilih") .. " (" .. count .. ")")
end

local function refreshList(query)
for i = #listData, 1, -1 do table.remove(listData, i) end
local q = tostring(query):lower()
for i = 1, #allItems do
local itemName = allItems[i].name
if q == "" or string.find(itemName:lower(), q, 1, true) then
local label = itemName
if not isInternal and allItems[i].isTheme then label = label .. " " .. T("label_tema", "[TEMA SUARA]") end

table.insert(listData, {
cbItem = {visibility = allItems[i].isTheme and 0 or 8, checked = (selectedItems[allItems[i].path] == true)},
tvName = label,
_path = allItems[i].path,
_isTheme = allItems[i].isTheme,
_name = itemName
})
end
end
if not adapter then
adapter = LuaAdapter(service, listData, itemLayout)
lvUP.setAdapter(adapter)
else
adapter.notifyDataSetChanged()
end
end

local function loadDir(pathTarget)
currentPath = pathTarget
if tvPathUP then tvPathUP.setText(currentPath) end
etCariUP.setText("")
allItems = {}

jalankanTaskLoading(T("memuat_file", "Memuat daftar folder..."), kerjaDaftarFolderTema, cjson.encode({ path = currentPath, isInternal = (isInternal and true or false) }), function(res)
allItems = res
selectedItems = {}
refreshList("")
updateBtnUpload()
end)
end

loadDir(currentPath)

etCariUP.addTextChangedListener(TextWatcher{ onTextChanged = function(c) refreshList(tostring(c)) end })

btnPilihSemuaUP.onClick = function()
for i = 1, #listData do
if listData[i]._isTheme then
selectedItems[listData[i]._path] = true
listData[i].cbItem.checked = true
end
end
adapter.notifyDataSetChanged()
updateBtnUpload()
end

btnBatalPilihUP.onClick = function()
selectedItems = {}
for i = 1, #listData do
listData[i].cbItem.checked = false
end
adapter.notifyDataSetChanged()
updateBtnUpload()
end

lvUP.onItemClick = function(l, v, p, id)
local item = listData[p+1]
if not item then return end

if item._isTheme then
if selectedItems[item._path] then
selectedItems[item._path] = nil
item.cbItem.checked = false
else
selectedItems[item._path] = true
item.cbItem.checked = true
end
adapter.notifyDataSetChanged()
updateBtnUpload()
else
loadDir(item._path)
end
end

dPicker.setOnKeyListener(function(dialog, keyCode, event)
if not isInternal and keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
if currentPath ~= "/storage/emulated/0" and currentPath ~= "/" then
local parent = File(currentPath).getParent()
if parent then loadDir(parent); return true end
else
dPicker.dismiss()
if onBack then onBack() end
return true
end
end
return false
end)

btnTutupUP.onClick = function() dPicker.dismiss(); if onBack then onBack() end end
dPicker.setOnCancelListener(function() if onBack then onBack() end end)

btnLanjutUpload.onClick = function()
local toProcess = {}
for k, v in pairs(selectedItems) do table.insert(toProcess, k) end
if #toProcess == 0 then
service.speak(T("pilih_minimal_satu", "Pilih minimal satu tema!"))
return
end

if tipeUpload == "resmi" then
ProsesUploadSPK(tipeUpload, toProcess, function()
selectedItems = {}
for i = 1, #listData do listData[i].cbItem.checked = false end
if adapter then adapter.notifyDataSetChanged() end
updateBtnUpload()
end)
return
end

CekKuotaFreemium("upload_komunitas", function()
ProsesUploadSPK(tipeUpload, toProcess, function()
selectedItems = {}
for i = 1, #listData do
listData[i].cbItem.checked = false
end
if adapter then adapter.notifyDataSetChanged() end
updateBtnUpload()
CatatPemakaianFreemium("upload_komunitas", false)
end)
end)
end

dPicker.show()
end

local function BukaTipeUpload()
local dTipe = UI_Dialog(T("tipe_upload", "Pilih Tipe Upload"))
local layTipe = UI_Layout(
UI_Tombol("btnTipePublish", T("upload_publish", "Upload Publish (Publik)")),
UI_Tombol("btnTipePrivate", T("upload_private", "Upload Private (Eksklusif)")),
UI_Tombol("btnTipeAdmin", T("upload_admin", "Upload Tema Admin (Akun Admin)")),
UI_Tombol("btnTipeResmi", T("csr_upload_resmi", "Upload ke Official CSR (Toko Resmi Jieshuo)")),
UI_Tombol("btnBatalTipe", T("kembali", "Kembali"))
)
dTipe.setView(loadlayout(layTipe))

local function kembaliKeTipe() BukaTipeUpload() end
local function BukaPemilihSumber(tipeUpload, onBackToTipe)
local dSumber = UI_Dialog(T("pilih_sumber_upload", "Pilih Sumber Tema"))
local laySumber = UI_Layout(
UI_Tombol("btnSumberInternal", T("sumber_internal", "Dari Tema Jieshuo (Internal)")),
UI_Tombol("btnSumberEksternal", T("sumber_eksternal", "Dari Folder Eksternal")),
UI_Tombol("btnBatalSumber", T("kembali", "Kembali"))
)
dSumber.setView(loadlayout(laySumber))

local function kembaliKeSumber() BukaPemilihSumber(tipeUpload, onBackToTipe) end

btnSumberInternal.onClick = function() dSumber.dismiss(); TampilkanPickerUpload(tipeUpload, true, kembaliKeSumber) end
btnSumberEksternal.onClick = function() dSumber.dismiss(); TampilkanPickerUpload(tipeUpload, false, kembaliKeSumber) end

btnBatalSumber.onClick = function() dSumber.dismiss(); if onBackToTipe then onBackToTipe() else BukaMenuKomunitas() end end
dSumber.setOnCancelListener(function() if onBackToTipe then onBackToTipe() else BukaMenuKomunitas() end end)
dSumber.show()
end

btnTipePublish.onClick = function() dTipe.dismiss(); BukaPemilihSumber("publik", kembaliKeTipe) end
btnTipePrivate.onClick = function() dTipe.dismiss(); BukaPemilihSumber("private", kembaliKeTipe) end
btnTipeAdmin.onClick = function()
dTipe.dismiss()
AKUN.gerbang(function() BukaPemilihSumber("admin", kembaliKeTipe) end, function() BukaTipeUpload() end)
end
-- Tema Private lama tetap khusus Admin Utama: tombolnya disembunyikan dari Admin 2/3
if not isAdminUtama then btnTipePrivate.setVisibility(8) end
btnTipeResmi.onClick = function() dTipe.dismiss(); BukaPemilihSumber("resmi", kembaliKeTipe) end
if not (isAdminUtama or AKUN.peran() == "admin") then btnTipeAdmin.setVisibility(8) end
btnBatalTipe.onClick = function() dTipe.dismiss(); BukaMenuKomunitas() end
dTipe.setOnCancelListener(function() BukaMenuKomunitas() end)

dTipe.show()
end

BukaTipeUpload()
end

btnTutupKomunitas.onClick = function() dKomunitas.dismiss(); muatUlangBahasaDanMenu() end
dKomunitas.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dKomunitas.show()
end

BukaMenuKomunitas()
end

btnPengaturanUtama.onClick = function() dialogUtama.dismiss(); tampilkanMenuPengaturan() end

btnPanduanUtama.onClick = function()
dialogUtama.dismiss()
local dPanduan = UI_Dialog(T("panduan_tombol", "Panduan Penggunaan"))
local lvPanduan = ListView(service)
local dataPanduan = ArrayList()
local panduanArray = langData["panduan_lengkap"]

if type(panduanArray) == "table" then
for i = 1, #panduanArray do
dataPanduan.add(tostring(panduanArray[i]))
end
else
dataPanduan.add("Panduan belum tersedia di bahasa ini.")
end

lvPanduan.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, dataPanduan))
dPanduan.setView(lvPanduan)
dPanduan.setButton(T("tutup", "Tutup"), function() dPanduan.dismiss(); muatUlangBahasaDanMenu() end)
dPanduan.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dPanduan.show()
end

BukaMenuPremiumGaib = function()
if dialogUtama then pcall(function() dialogUtama.dismiss() end) end
local dPremium = UI_Dialog(T("menu_premium", "Tingkatkan ke Premium"))

local myId = DapatkanAndroidID()
local txtStatus = T("status_free", "Status Akun: Pengguna Free")
if ID_CREATORS[myId] then
txtStatus = T("status_kreator", "Status Akun: Developer Kreator")
elseif ADMIN_IDS[myId] then
txtStatus = T("status_admin_1", "Status Akun: Developer Admin Utama")
elseif ADMIN_KEDUA_IDS[myId] then
txtStatus = T("status_admin_2", "Status Akun: Premium Lanjutan")
elseif ADMIN_KETIGA_IDS[myId] then
txtStatus = T("status_admin_3", "Status Akun: Premium Awal")
end

local layPrem = UI_Layout(
{TextView, text=txtStatus, textSize="18sp", textColor="0xFF4CAF50", layout_marginBottom="16dp"},
UI_Teks(T("promo_judul", "Mari kita lihat apa saja kemudahan yang bisa kalian dapatkan jika beralih ke versi Premium.")),
UI_Teks(T("promo_1", "Pembuat Demo Instan\nFitur ini sangat membantu kalian untuk melewati proses perakitan yang panjang dan meribetkan. Kalian bisa langsung memilih audio dari penyimpanan dan memetakannya ke puluhan event Jieshuo hanya dalam hitungan detik. Menguji tema suara yang sedang kalian buat akan terasa jauh lebih cepat dan praktis.")),
UI_Teks(T("promo_2", "Otomatisasi Ganti Nama Event\nBayangkan betapa repotnya jika harus mengetik ulang dan menyamakan nama file satu per satu secara manual. Dengan fitur ini, nama-nama file audio kalian akan diubah secara otomatis agar cocok seratus persen dengan nama event di UI Jieshuo. Pekerjaan kalian akan jadi jauh lebih rapi tanpa perlu buang-buang waktu.")),
UI_Teks(T("promo_3", "Asisten Suara Rekaman Jam Bicara\nKalian tidak akan lagi menatap layar yang bisu. Fitur ini akan memberikan panduan suara interaktif yang membisikkan instruksi dan memberikan hitungan mundur tepat di telinga kalian saat merekam jam manual. Hasil rekaman kalian pasti akan jauh lebih akurat, fokus, dan profesional.")),
UI_Teks(T("promo_4", "Pemulihan Tema Otomatis\nIni adalah perlindungan data maksimal untuk kalian. Jika suatu saat folder tema suara kesayangan kalian tidak sengaja terhapus, kalian tidak perlu panik. Sistem cerdas kami akan langsung mendeteksinya dan memulihkan data tersebut dari folder cadangan secara otomatis saat itu juga, tanpa perlu repot masuk ke menu pemulihan manual.")),
UI_Teks(T("promo_5", "Akses Fitur Tanpa Batas\nKalian bisa terbebas dari belenggu kuota harian. Fitur pembersih audio tak terdaftar untuk membuang file sampah, serta fitur penghilang format audio, bisa kalian jalankan sepuasnya kapan pun kalian mau. Tidak ada lagi batasan maksimal tiga kali pemakaian dalam sehari.")),
UI_Tombol("btnUpgradePrem", T("btn_tingkatkan_sekarang", "Tingkatkan ke Premium Sekarang")),
UI_Tombol("btnTutupPrem", T("tutup", "Tutup"))
)

local scrollPrem = ScrollView(service)
scrollPrem.addView(loadlayout(layPrem))
dPremium.setView(scrollPrem)

btnUpgradePrem.onClick = function()
if ID_CREATORS[myId] then
service.speak(T("tolak_kreator", "Tombol ini tidak tersedia untuk Anda karena Anda adalah kreatornya sendiri, wkwkwk."))
elseif ADMIN_IDS[myId] then
service.speak(T("tolak_admin1", "Anda tidak bisa meningkatkan ke premium karena Anda sudah menjadi Admin Utama."))
elseif ADMIN_KEDUA_IDS[myId] then
service.speak(T("tolak_admin2", "Anda tidak bisa meningkatkan ke tingkat Admin Utama. Anda sudah memiliki akses Premium Lanjutan dan itu adalah tingkat premium tertinggi."))
else
local dPaket = UI_Dialog(T("pilih_paket", "Pilih Paket Premium"))
local lvPaket = ListView(service)
local listPaket = ArrayList()
listPaket.add(T("paket_awal", "Premium Awal (Rp 10.000)\nMembuka semua fitur eksklusif, bebas kuota, asisten suara, dan auto-restore. Update skrip terenkripsi."))
listPaket.add(T("paket_lanjut", "Premium Lanjutan (Rp 15.000)\nSemua fitur Premium Awal, DITAMBAH update skrip mentah untuk dipelajari."))
lvPaket.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, listPaket))
dPaket.setView(lvPaket)

lvPaket.onItemClick = function(l, v, p, id)
local isAwal = (p == 0)
local tipePrem = isAwal and "Awal" or "Lanjutan"

if isAwal and ADMIN_KETIGA_IDS[myId] then
service.speak(T("tolak_admin3", "Anda sudah berada di tingkat Premium Awal. Silakan pilih Premium Lanjutan jika ingin meningkatkan akses."))
return
end

dPaket.dismiss()

local dDurasi = UI_Dialog(T("pilih_durasi", "Pilih Durasi"))
local lvDurasi = ListView(service)
local listDurasi = ArrayList()

local harga1 = isAwal and "Rp 10.000" or "Rp 15.000"
local harga2 = isAwal and "Rp 20.000" or "Rp 25.000"
local harga3 = isAwal and "Rp 50.000" or "Rp 60.000"

listDurasi.add(T("durasi_1_bulan", "1 Bulan") .. " (" .. harga1 .. ")")
listDurasi.add(T("durasi_2_bulan", "2 Bulan") .. " (" .. harga2 .. ")")
listDurasi.add(T("durasi_permanen", "Permanen") .. " (" .. harga3 .. ")")

lvDurasi.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, listDurasi))
dDurasi.setView(lvDurasi)

lvDurasi.onItemClick = function(ld, vd, pd, idd)
dDurasi.dismiss()
local durasiTxt = (pd == 0) and T("durasi_1_bulan", "1 Bulan") or ((pd == 1) and T("durasi_2_bulan", "2 Bulan") or T("durasi_permanen", "Permanen"))
local hargaPrem = (pd == 0) and harga1 or ((pd == 1) and harga2 or harga3)

local dKonfirm = UI_Dialog(T("konfirmasi", "Konfirmasi"))
dKonfirm.setMessage(T("konfirm_pesan", "Apakah Anda yakin ingin memesan Premium ") .. tipePrem .. " (" .. durasiTxt .. ")" .. T("konfirm_harga", " seharga ") .. hargaPrem .. T("konfirm_peringatan", "? Harap jangan sentuh layar setelah ini, karena seluruh tindakan pemesanan ke WhatsApp akan dilakukan secara otomatis oleh sistem."))

dKonfirm.setButton(T("lanjutkan", "Lanjutkan"), function()
dPremium.dismiss()
showInputDialog(T("pendaftaran", "Pendaftaran"), T("input_nama_pendaftaran", "Masukkan nama Anda untuk pendaftaran:"), "", function(namaInput)
if namaInput == "" then service.speak(T("tidak_boleh_kosong", "Kotak teks tidak boleh kosong!")); return end
local kodePrem = EnkripsiPayload(myId, namaInput, "PREM")
local uri = Uri.parse("https://wa.me/6283848085619?text=" .. kodePrem)
local intent = Intent(Intent.ACTION_VIEW, uri)
intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
pcall(function() service.startActivity(intent) end)

local pesan2 = "Halo admin, saya memesan premium " .. tipePrem .. " (" .. durasiTxt .. ").\nKode Pendaftaran: " .. kodePrem

local function klikNodeKirim()
local root = service.getRootInActiveWindow()
if not root then return false end
local nodes = root.findAccessibilityNodeInfosByText("Kirim")
if nodes == nil or nodes.size() == 0 then nodes = root.findAccessibilityNodeInfosByText("Send") end
if nodes and nodes.size() > 0 then
for j = 0, nodes.size() - 1 do
local n = nodes.get(j)
local desc = tostring(n.getContentDescription() or ""):lower()
if string.match(desc, "^kirim") or string.match(desc, "^send") then
local target = n.isClickable() and n or n.getParent()
if target and target.isClickable() then
target.performAction(16)
return true
end
end
end
end
return false
end

local function cariKotakInput(node)
if not node then return nil end
if node.getClassName() and string.find(tostring(node.getClassName()), "EditText") then return node end
for k = 0, node.getChildCount() - 1 do
local res = cariKotakInput(node.getChild(k))
if res then return res end
end
return nil
end

local hitungCobaKirim1 = 0
local function loopKirim1()
hitungCobaKirim1 = hitungCobaKirim1 + 1
if klikNodeKirim() then
task(1000, function()
local root2 = service.getRootInActiveWindow()
if root2 then
local editNode = root2.findFocus(1)
if not editNode or not string.find(tostring(editNode.getClassName() or ""), "EditText") then
editNode = cariKotakInput(root2)
end
if editNode then
local Bundle = luajava.bindClass("android.os.Bundle")
local args = Bundle()
args.putCharSequence("ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE", pesan2)
editNode.performAction(2097152, args)

local hitungCobaKirim2 = 0
local function loopKirim2()
hitungCobaKirim2 = hitungCobaKirim2 + 1
if not klikNodeKirim() and hitungCobaKirim2 < 10 then
task(500, loopKirim2)
end
end
task(500, loopKirim2)
end
end
end)
else
if hitungCobaKirim1 < 20 then
task(500, loopKirim1)
end
end
end

task(1000, loopKirim1)
end)
end)
dKonfirm.setButton2(T("batal", "Batal"), nil)
dKonfirm.setCancelable(false)
dKonfirm.show()
end
dDurasi.setButton(T("batal", "Batal"), nil)
dDurasi.show()
end
dPaket.setButton(T("tutup", "Tutup"), nil)
dPaket.show()
end
end

btnTutupPrem.onClick = function()
dPremium.dismiss()
muatUlangBahasaDanMenu()
end
dPremium.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dPremium.show()
end

btnPremiumUtama.onClick = function() BukaMenuPremiumGaib() end

if btnAdminUtama then
btnAdminUtama.onClick = function() dialogUtama.dismiss(); TampilkanPanelAdmin() end
end
btnTutupUtama.onClick = function() dialogUtama.dismiss() end

dialogUtama.show()
end

ID_CREATOR = "0fef1416c68c6769"
ID_CREATORS = {}
ID_CREATORS["0fef1416c68c6769"] = true -- Nanda
ID_CREATORS["0c3454d593fb8a16"] = true -- Dian Resya Putri

ADMIN_IDS = {}
for idKreator, _ in pairs(ID_CREATORS) do ADMIN_IDS[idKreator] = true end -- Kunci Dewa mutlak, tidak bisa dihapus
for id, nama in pairs(DataAdminGlobal.admin_utama) do ADMIN_IDS[id] = true end

ADMIN_KEDUA_IDS = {}
for id, nama in pairs(DataAdminGlobal.admin_kedua) do ADMIN_KEDUA_IDS[id] = true end

ADMIN_KETIGA_IDS = {}
for id, nama in pairs(DataAdminGlobal.admin_ketiga) do ADMIN_KETIGA_IDS[id] = true end

local TOKEN_CEK_UPDATE = ""
local REPO_OWNER = "nandadian20083123"
local REPO_NAME = "skrip-lua"

function DapatkanAndroidID_Asli()
local id = Settings.Secure.getString(service.getContentResolver(), Settings.Secure.ANDROID_ID)
return tostring(id)
end

function DapatkanAndroidID()
local pref = luajava.bindClass("android.preference.PreferenceManager").getDefaultSharedPreferences(service)
if pref.getBoolean("simulasi_free_user", false) then
return "FREE_USER_TEST"
end
return DapatkanAndroidID_Asli()
end

function EnkripsiPayload(id, nama, jenis)
local String = luajava.bindClass("java.lang.String")
local Base64 = luajava.bindClass("android.util.Base64")
local txt = "NADI|" .. id .. "|" .. (nama or "") .. "|" .. jenis
return Base64.encodeToString(String(txt).getBytes(), 2)
end

function DekripsiPayload(kode)
local String = luajava.bindClass("java.lang.String")
local Base64 = luajava.bindClass("android.util.Base64")
local ok, res = pcall(function()
local bytes = Base64.decode(kode, 2)
local txt = tostring(String(bytes))
local id, nama, jenis = string.match(txt, "^NADI%|([^%|]+)%|([^%|]*)%|([^%|]+)$")
if id then return {id=id, nama=nama, jenis=jenis} end
return txt
end)
return (ok and type(res)=="table") and res or kode
end

local function UploadKeGithub(token, localFilePath, repoPath, commitMsg, onProgress, onComplete)
local hentikanPoller = mulaiPollerProgres(function(t) if onProgress then onProgress(t) end end)
task(kerjaUploadGithub, cjson.encode({ token = token, localFilePath = localFilePath, repoPath = repoPath, commitMsg = commitMsg, owner = REPO_OWNER, repo = REPO_NAME }), function(json)
hentikanPoller()
local r = {}
pcall(function() r = cjson.decode(tostring(json)) end)
if onComplete then onComplete(r.ok == true, r.msg or "Proses unggah di latar belakang gagal") end
end)
end

function TampilkanPanelAdmin()
local tokenTersimpan = dapatkanString("github_admin_token", "")
if tokenTersimpan == "" then
showInputDialog("Akses Admin GitHub", "Masukkan Personal Access Token GitHub (Wajib)", "", function(txt, inputDialog)
jalankanTaskLoading("Mengecek token ke server GitHub...", kerjaCekToken, cjson.encode({ token = txt }), function(hasilCek)
local isValid = (hasilCek.valid == true)
if isValid then
service.speak("Token valid.")
simpanString("github_admin_token", txt)
if inputDialog then inputDialog.dismiss() end
TampilkanPanelAdmin()
else
service.speak("Token tidak valid atau repositori tidak ditemukan.")
end
end)
return false
end, function() muatUlangBahasaDanMenu() end, true)
return
end

local dAdmin = UI_Dialog("馃洜 Panel Developer (Mode Admin)")
local layoutAdmin = UI_Layout(
{LinearLayout, orientation="vertical", layout_width="fill", layout_marginBottom="8dp", padding="8dp",
{TextView, id="tvStatusUpload", text="0 file siap di-upload", textSize="14sp", textColor="0xFF4CAF50", gravity="center", layout_width="fill", layout_marginBottom="8dp"},
UI_Tombol("btnPilihUpload", "Pilih File yang Ingin Di-upload")
},
{LinearLayout, orientation="horizontal", layout_width="fill", layout_marginBottom="4dp",
UI_Tombol_H("btnMenuPengampunan", "Menu Pengampunan"),
UI_Tombol_H("btnKelolaRiwayat", "Kelola Riwayat")
},
{LinearLayout, orientation="horizontal", layout_width="fill", layout_marginBottom="4dp",
UI_Tombol_H("btnMenuAdminMaster", "Kelola Admin"),
UI_Tombol_H("btnMenuToken", "Menu Token")
},
{LinearLayout, orientation="horizontal", layout_width="fill", layout_marginBottom="8dp",
UI_Tombol_H("btnMenuSpesial", "Menu Spesial Admin"),
UI_Tombol_H("btnKelolaPengguna", "Kelola Pengguna")
},
{LinearLayout, orientation="horizontal", layout_width="fill", layout_marginBottom="8dp",
UI_Tombol_H("btnSaklarKlaim", "Saklar Klaim Jatah"),
UI_Tombol_H("btnAkunPrivate", "Akun Tema Admin")
},
{LinearLayout, orientation="horizontal", layout_width="fill", layout_marginTop="4dp",
UI_Tombol_H("btnTutupAdmin", "Tutup Panel"),
UI_Tombol_H("btnUploadAdmin", "Upload GitHub")
}
)
dAdmin.setView(loadlayout(layoutAdmin))
AKUN.dAdmin = dAdmin

local targetFiles = {
{ name = "main.lua", localPath = BASE .. "main.lua", repoPath = "main.lua" },
{ name = "terenkripsi.lua (Rilis Publik)", localPath = BASE .. "terenkripsi.lua", repoPath = "skrip Ter inkripsi/main.lua" },
{ name = "daftar_admin.json (Database User)", localPath = pathAdminJson, repoPath = "daftar_admin.json" },
{ name = "data_iven.json", localPath = BASE .. "data_iven.json", repoPath = "data_iven.json" },
{ name = "indonesia.json", localPath = langDir .. "indonesia.json", repoPath = "bahasa/indonesia.json" },
{ name = "inggris.json", localPath = langDir .. "inggris.json", repoPath = "bahasa/inggris.json" }
}

local listData, itemLayout = {}, UI_ItemBaris("cbFileAdmin", "tvFileAdmin")
for i=1, #targetFiles do table.insert(listData, { cbFileAdmin = {checked=false}, tvFileAdmin = targetFiles[i].name, _data = targetFiles[i] }) end
local adapter = LuaAdapter(service, listData, itemLayout)

btnPilihUpload.onClick = function()
local dPilih = UI_Dialog("Pilih File Upload")
local layPilih = UI_Layout(
UI_Daftar("lvAdminFile"),
UI_Tombol("btnTambahKustom", "Tambah File Kustom (nama dan format)"),
{LinearLayout, orientation="horizontal", layout_width="fill",
UI_Tombol_H("btnBatalPilihUp", "Batal"),
UI_Tombol_H("btnSimpanPilihUp", "Oke")
}
)
dPilih.setView(loadlayout(layPilih))
lvAdminFile.setAdapter(adapter)

lvAdminFile.onItemClick = function(l, v, p, id)
listData[p+1].cbFileAdmin.checked = not listData[p+1].cbFileAdmin.checked
adapter.notifyDataSetChanged()
end

btnBatalPilihUp.onClick = function() dPilih.dismiss() end
btnTambahKustom.onClick = function()
AksiDex.dialogTambahKustom(function(entri)
local sudah = false
for i = 1, #listData do
if listData[i]._data.repoPath == entri.repoPath then listData[i].cbFileAdmin.checked = true; sudah = true end
end
if not sudah then
table.insert(listData, { cbFileAdmin = {checked=true}, tvFileAdmin = entri.name, _data = entri })
end
adapter.notifyDataSetChanged()
end)
end
btnSimpanPilihUp.onClick = function()
local count = 0
for i=1, #listData do
if listData[i].cbFileAdmin.checked then count = count + 1 end
end
tvStatusUpload.setText(count .. " file siap di-upload")
dPilih.dismiss()
end
dPilih.show()
end

local function TambahAdminUniversal(jenisAdmin)
local kastaNama, kastaKey = "", ""
if jenisAdmin == 1 then kastaNama = "Admin Utama"; kastaKey = "admin_utama"
elseif jenisAdmin == 2 then kastaNama = "Admin Kedua"; kastaKey = "admin_kedua"
elseif jenisAdmin == 3 then kastaNama = "Admin Ketiga"; kastaKey = "admin_ketiga" end
local dTambah = UI_Dialog("Tambah " .. kastaNama)
local layoutT = UI_Layout(
UI_Input("etIdAdmin", "Tempel Kode Pendaftaran ATAU ID Murni"),
{LinearLayout, orientation="horizontal", layout_width="fill",
UI_Tombol_H("btnBatalA", "Batal"),
UI_Tombol_H("btnSimpanA", "Simpan")
}
)
dTambah.setView(loadlayout(layoutT))
btnSimpanA.onClick = function()
local inputTxt = tostring(etIdAdmin.getText()):match("^%s*(.-)%s*$") or ""
if inputTxt == "" then return end
local dec = DekripsiPayload(inputTxt)
if type(dec) == "table" and dec.id and dec.nama then
DataAdminGlobal[kastaKey][dec.id] = dec.nama
if simpanAdminJsonLokal(DataAdminGlobal) then
if jenisAdmin == 1 then ADMIN_IDS[dec.id] = true
elseif jenisAdmin == 2 then ADMIN_KEDUA_IDS[dec.id] = true
elseif jenisAdmin == 3 then ADMIN_KETIGA_IDS[dec.id] = true end
service.speak("Berhasil menambahkan " .. dec.nama)
dTambah.dismiss()
end
else
if not string.match(inputTxt, "^[a-zA-Z0-9]+$") then service.speak("Input tidak valid!"); return end
dTambah.dismiss()
showInputDialog("Nama Pengguna", "Masukkan nama untuk ID manual ini:", "", function(namaManual)
if namaManual ~= "" then
DataAdminGlobal[kastaKey][inputTxt] = namaManual
if simpanAdminJsonLokal(DataAdminGlobal) then
if jenisAdmin == 1 then ADMIN_IDS[inputTxt] = true
elseif jenisAdmin == 2 then ADMIN_KEDUA_IDS[inputTxt] = true
elseif jenisAdmin == 3 then ADMIN_KETIGA_IDS[inputTxt] = true end
service.speak("Berhasil menambahkan " .. namaManual)
end
end
end)
end
end
btnBatalA.onClick = function() dTambah.dismiss() end
dTambah.show()
end

local function KelolaAdminUniversal(jenisAdmin)
local judul, kastaKey, targetTable = "", "", nil
if jenisAdmin == 1 then judul = "Kelola Admin Utama"; kastaKey = "admin_utama"; targetTable = ADMIN_IDS
elseif jenisAdmin == 2 then judul = "Kelola Admin Kedua"; kastaKey = "admin_kedua"; targetTable = ADMIN_KEDUA_IDS
elseif jenisAdmin == 3 then judul = "Kelola Admin Ketiga"; kastaKey = "admin_ketiga"; targetTable = ADMIN_KETIGA_IDS end

local dKelola = UI_Dialog(judul)
local layoutKelola = UI_Layout(
UI_Teks("Ketuk: Salin ID.\nKetuk tahan: Info, Edit, Hapus.", true),
UI_Daftar("lvDaftarAdmin"),
UI_Tombol("btnTutupKelola", "Tutup")
)
dKelola.setView(loadlayout(layoutKelola))

local function refreshListKelola()
local listAdmin = ArrayList()
local rawAdmins = {}
for id_admin, nama_admin in pairs(DataAdminGlobal[kastaKey]) do
local label = nama_admin
if ID_CREATORS[id_admin] then label = label .. " (Creator Master)" end
listAdmin.add(label)
table.insert(rawAdmins, {id = id_admin, nama = nama_admin})
end
local adapterKelola = ArrayAdapter(service, android.R.layout.simple_list_item_1, listAdmin)
lvDaftarAdmin.setAdapter(adapterKelola)

lvDaftarAdmin.onItemClick = function(l, v, p, id)
local tId = rawAdmins[p+1].id
local isKlip = PreferenceManager.getDefaultSharedPreferences(service).getBoolean("use_jieshuo_clip", false)
if isKlip then service.copy(tId) else
local clipboard = service.getSystemService(Context.CLIPBOARD_SERVICE)
clipboard.setPrimaryClip(ClipData.newPlainText("IDAdmin", tId))
end
service.speak("Berhasil disalin: " .. tId)
end

lvDaftarAdmin.onItemLongClick = function(l, v, p, id)
local tId = rawAdmins[p+1].id
local tNama = rawAdmins[p+1].nama

local dOpt = UI_Dialog(tNama)
local opts = {"Informasi", "Edit", "Hapus", "Tutup"}
dOpt.setItems(opts)
dOpt.setOnItemClickListener(function(ol, ov, op, oid)
local act = opts[op+1]

if act == "Informasi" then
dOpt.dismiss()
local dInfo = UI_Dialog("Informasi Admin")
dInfo.setMessage("Nama: " .. tNama .. "\nID Android: " .. tId)
dInfo.setButton("Tutup", nil)
dInfo.show()

elseif act == "Edit" then
if ID_CREATORS[tId] then service.speak("Akses Ditolak: Kunci Dewa (Creator) tidak boleh diedit!"); return end
dOpt.dismiss()
local dEdit = UI_Dialog("Edit " .. tNama)
local layE = UI_Layout(
UI_Input("etENama", "Nama Pengguna"),
UI_Input("etEId", "ID Android"),
{LinearLayout, orientation="horizontal", layout_width="fill",
UI_Tombol_H("btnEBatal", "Batal"), UI_Tombol_H("btnESimpan", "Simpan")
}
)
dEdit.setView(loadlayout(layE))
etENama.setText(tNama)
etEId.setText(tId)
btnESimpan.onClick = function()
local nBaru = tostring(etENama.getText()):match("^%s*(.-)%s*$") or ""
local iBaru = tostring(etEId.getText()):match("^%s*(.-)%s*$") or ""
if nBaru == "" or iBaru == "" then service.speak("Tidak boleh kosong!"); return end

DataAdminGlobal[kastaKey][tId] = nil
targetTable[tId] = nil

DataAdminGlobal[kastaKey][iBaru] = nBaru
targetTable[iBaru] = true

simpanAdminJsonLokal(DataAdminGlobal)
service.speak("Berhasil diedit")
dEdit.dismiss()
refreshListKelola()
end
btnEBatal.onClick = function() dEdit.dismiss() end
dEdit.show()

elseif act == "Hapus" then
if ID_CREATORS[tId] then service.speak("Akses Ditolak: Kunci Dewa (Creator) tidak boleh dihapus!"); return end
dOpt.dismiss()
showConfirmDialog("Hapus Akses", "Yakin ingin menghapus akses untuk " .. tNama .. "?", function()
DataAdminGlobal[kastaKey][tId] = nil
targetTable[tId] = nil
simpanAdminJsonLokal(DataAdminGlobal)
service.speak("Berhasil dihapus.")
refreshListKelola()
end)

elseif act == "Tutup" then
dOpt.dismiss()
end
end)
dOpt.show()
return true
end
end

refreshListKelola()
AksiDex.pasang(lvDaftarAdmin, { labelKlik = T("aksi_salin_id", "Salin ID") })
btnTutupKelola.onClick = function() dKelola.dismiss() end
dKelola.show()
end

local function getRiwayatTabungan()
local str = PreferenceManager.getDefaultSharedPreferences(service).getString("tabungan_riwayat", "[]")
local ok, data = pcall(function() return cjson.decode(str) end)
return (ok and type(data)=="table") and data or {}
end
local function setRiwayatTabungan(tbl)
PreferenceManager.getDefaultSharedPreferences(service).edit().putString("tabungan_riwayat", cjson.encode(tbl)).apply()
end

btnKelolaRiwayat.onClick = function()
local dRiwayat = UI_Dialog("Kelola Riwayat Rilis")
local layR = UI_Layout(
UI_Tombol("btnTambahR", "Tambah Catatan Baru"),
UI_Daftar("lvR"),
UI_Tombol("btnBersihkanR", "Bersihkan Semua"),
UI_Tombol("btnTutupR", "Tutup")
)
dRiwayat.setView(loadlayout(layR))
local listR = getRiwayatTabungan()
local adapterR = ArrayAdapter(service, android.R.layout.simple_list_item_1, listR)
lvR.setAdapter(adapterR)

btnTambahR.onClick = function()
showInputDialog("Catatan Baru", "Ketik fitur/bug fix yang baru...", "", function(txt)
if txt ~= "" then table.insert(listR, txt) setRiwayatTabungan(listR) end
adapterR.notifyDataSetChanged()
end, nil, true)
end
lvR.onItemClick = function(l,v,p,id)
showConfirmDialog("Hapus Catatan", "Hapus catatan rilis ini?", function()
table.remove(listR, p+1) setRiwayatTabungan(listR) adapterR.notifyDataSetChanged()
end)
end
btnBersihkanR.onClick = function()
showConfirmDialog("Bersihkan", "Yakin mengosongkan semua riwayat?", function()
listR = {} setRiwayatTabungan(listR) adapterR.notifyDataSetChanged()
end)
end
btnTutupR.onClick = function() dRiwayat.dismiss() end
dRiwayat.show()
end

btnMenuAdminMaster.onClick = function()
local dMenuAdmin = UI_Dialog("Tambah dan Kelola Admin")
local layMenuAdmin = UI_Layout(
UI_Teks("Admin Utama (Akses Penuh):"),
{LinearLayout, orientation="horizontal", layout_width="fill", layout_marginBottom="4dp",
UI_Tombol_H("btnTambahAdmin1", "Tambah Utama"),
UI_Tombol_H("btnKelolaAdmin1", "Kelola Utama")
},
UI_Teks("Admin Kedua (Premium - Anti Edit):"),
{LinearLayout, orientation="horizontal", layout_width="fill", layout_marginBottom="4dp",
UI_Tombol_H("btnTambahAdmin2", "Tambah Ke-2"),
UI_Tombol_H("btnKelolaAdmin2", "Kelola Ke-2")
},
UI_Teks("Admin Ketiga (Premium - Terenkripsi):"),
{LinearLayout, orientation="horizontal", layout_width="fill", layout_marginBottom="8dp",
UI_Tombol_H("btnTambahAdmin3", "Tambah Ke-3"),
UI_Tombol_H("btnKelolaAdmin3", "Kelola Ke-3")
},
UI_Tombol("btnTutupMenuAdmin", "Tutup")
)
dMenuAdmin.setView(loadlayout(layMenuAdmin))

btnTambahAdmin1.onClick = function() dMenuAdmin.dismiss(); TambahAdminUniversal(1) end
btnTambahAdmin2.onClick = function() dMenuAdmin.dismiss(); TambahAdminUniversal(2) end
btnTambahAdmin3.onClick = function() dMenuAdmin.dismiss(); TambahAdminUniversal(3) end
btnKelolaAdmin1.onClick = function() dMenuAdmin.dismiss(); KelolaAdminUniversal(1) end
btnKelolaAdmin2.onClick = function() dMenuAdmin.dismiss(); KelolaAdminUniversal(2) end
btnKelolaAdmin3.onClick = function() dMenuAdmin.dismiss(); KelolaAdminUniversal(3) end
btnTutupMenuAdmin.onClick = function() dMenuAdmin.dismiss() end

dMenuAdmin.show()
end




btnMenuToken.onClick = function()
local dToken = UI_Dialog("Manajemen Token")
local layToken = UI_Layout(
UI_Tombol("btnGantiTokenAdmin", "Ganti Token Admin"),
UI_Tombol("btnUploadTokenKomunitas", "Upload Token Komunitas"),
UI_Tombol("btnTutupToken", "Tutup")
)
dToken.setView(loadlayout(layToken))

btnGantiTokenAdmin.onClick = function()
dToken.dismiss()
simpanString("github_admin_token", "") 
dAdmin.dismiss()
TampilkanPanelAdmin()
end

btnUploadTokenKomunitas.onClick = function()
dToken.dismiss()
showInputDialog("Token Komunitas", "Masukkan Token GitHub untuk upload komunitas:", "", function(txt)
if txt == "" then return end
jalankanTaskLoading("Memvalidasi token komunitas...", kerjaCekToken, cjson.encode({ token = txt }), function(hasilCek)
local pathLokal = nil
if hasilCek.valid == true then
local okEnc, tokenTersamar = pcall(function()
local B64 = luajava.bindClass("android.util.Base64")
local JStr = luajava.bindClass("java.lang.String")
local terbalik = string.reverse(txt)
return tostring(B64.encodeToString(JStr(terbalik).getBytes("UTF-8"), B64.NO_WRAP))
end)
if not okEnc then
service.speak("Gagal menyamarkan token.")
return
end
local dataToken = { k = tokenTersamar }
pathLokal = BASE .. "token_komunitas.json"
simpanJson(pathLokal, dataToken)
end
if pathLokal then
dAdmin.dismiss()
local dProses = UI_Dialog("Mengunggah Token...")
dProses.setMessage("Memulai upload rahasia...")
dProses.setCancelable(false)
dProses.show()
UploadKeGithub(tokenTersimpan, pathLokal, "token_komunitas.json", "SILENT_UPDATE_ADMIN",
function(statusMsg) dProses.setMessage(statusMsg) end,
function(isOk, resultMsg)
dProses.dismiss()
if isOk then
local dSukses = UI_Dialog("Upload Selesai!")
dSukses.setMessage("Token komunitas berhasil diunggah secara diam-diam (SILENT_UPDATE_ADMIN).")
dSukses.setButton("Oke", function() TampilkanPanelAdmin() end)
dSukses.setCancelable(false)
dSukses.show()
else
local dGagal = UI_Dialog("Gagal Upload")
dGagal.setMessage("Gagal mengunggah token.\n\nPesan: " .. tostring(resultMsg or "Tidak ada keterangan dari server"))
dGagal.setButton("Tutup", function() TampilkanPanelAdmin() end)
dGagal.show()
end
end)
else
service.speak("Token tidak valid atau gagal terhubung ke GitHub!")
end
end)
return true
end)
end

btnTutupToken.onClick = function() dToken.dismiss() end
dToken.show()
end

local function readBin(name)
    local f = io.open(jieshuoPath .. "/Plugin/inkripsi nadi3/" .. name, "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
end

local function runEncryption(targetPath, outDir, password)
    local ProgressBar = luajava.bindClass("android.widget.ProgressBar")
    local pdLayout = {
        LinearLayout,
        orientation = "vertical",
        padding = "20dp",
        gravity = "center",
        {
            ProgressBar,
            style = "?android:attr/progressBarStyleLarge",
            layout_width = "wrap_content",
            layout_height = "wrap_content",
            layout_marginBottom = "10dp"
        },
        {
            TextView,
            text = "Memproses Enkripsi...",
            textSize = "16sp",
            textColor = "0xFFFFFFFF"
        }
    }
    local pd = LuaDialog(service)
    pd.setTitle("Nadi Encryptor")
    pd.setView(loadlayout(pdLayout))
    pd.setCancelable(false)
    pd.show()

    Thread(Runnable({
        run = function()
            local function doFinish(errMsg, successMsg)
                uiHandler.post(Runnable({
                    run = function()
                        pd.dismiss()
                        if errMsg then
                            service.speak(errMsg)
                        else
                            service.speak(successMsg)
                        end
                    end
                }))
            end

            local d64 = readBin("libnadi_armor_64.so")
            local d32 = readBin("libnadi_armor_32.so")
            local e64 = readBin("libnadi_enc_64.so")
            local e32 = readBin("libnadi_enc_32.so")

            if not (d64 and d32 and e64 and e32) then
                return doFinish("Gagal: File .so Nadi tidak ditemukan di Plugin/inkripsi nadi3!", nil)
            end

            local tF = io.open(targetPath, "r")
            if not tF then
                return doFinish("Gagal membaca file main.lua target!", nil)
            end
            local raw = tF:read("*a")
            tF:close()

            local ok_tgt, bc = pcall(function() return string.dump(load(raw)) end)
            if not ok_tgt or not bc then
                return doFinish("Gagal compile target.lua", nil)
            end

            local Sys = luajava.bindClass("java.lang.System")
            local a = string.lower(Sys.getProperty("os.arch") or "")
            local i64 = (string.find(a, "64") or string.find(a, "aarch")) ~= nil
            local active_enc = i64 and e64 or e32
            
            local p_enc = service.getDir("n_bin", 0).getAbsolutePath() .. "/nadi_enc_" .. os.time() .. ".so"
            local f_temp = io.open(p_enc, "wb")
            if f_temp then f_temp:write(active_enc); f_temp:close() end

            local fn_enc = package.loadlib(p_enc, "luaopen_libnadi_enc")
            if not fn_enc then
                os.remove(p_enc)
                return doFinish("Gagal memuat mesin C enkriptor!", nil)
            end

            local ok_enc, enc_pay = pcall(fn_enc, bc, password)
            os.remove(p_enc)

            if not ok_enc or not enc_pay then
                return doFinish("Gagal mengenkripsi di dalam RAM!", nil)
            end

            if not outDir:match("/$") then outDir = outDir .. "/" end
            local outDirFile = File(outDir)
            if not outDirFile.exists() then outDirFile.mkdirs() end

            local datF = io.open(outDir .. "data.dat", "wb")
            if datF then
                datF:write(string.format("%010d", #d64))
                datF:write(d64)
                datF:write(string.format("%010d", #d32))
                datF:write(d32)
                datF:write(enc_pay)
                datF:close()
            else
                return doFinish("Gagal membuat data.dat!", nil)
            end

            math.randomseed(os.time())

            local function toDecEscape(str)
                local dec = ""
                for i = 1, #str do
                    dec = dec .. string.format("\\%03d", string.byte(str, i))
                end
                return dec
            end

            local function shred(s)
                local t = "((function() local _t={} "
                for i = 1, #s do
                    local b = string.byte(s, i)
                    local off = math.random(10, 50)
                    t = t .. "_t[#_t+1]=string.char(" .. (b + off) .. "-" .. off .. ") "
                end
                t = t .. "return table.concat(_t) end)())"
                return t
            end

            local function gen_junk_init()
                local j = "local _STATE = string.len(" .. shred(password) .. ") + string.len(_vPAYLOAD_ or '') + string.len(tostring(_vPROXY_ or ''))\n"
                local kalimatAneh = {"tuju minum teh", "mejanya hancur", "lingkungan bikin bahagia", "Smart Nateg SDP", "kopi Nanda tumpah", "kucing terbang ke bulan"}
                local operasi = {"+", "-", "*", "%"}
                for i = 1, 500 do
                    local k1 = kalimatAneh[math.random(1, #kalimatAneh)]
                    local k2 = kalimatAneh[math.random(1, #kalimatAneh)]
                    local op1 = operasi[math.random(1, 2)] 
                    local op2 = operasi[math.random(1, #operasi)]
                    local pengali = math.random(2, 9)
                    j = j .. "_STATE = math.abs((_STATE + ((string.len('" .. toDecEscape(k1) .. "') " .. op1 .. " _STATE) " .. op2 .. " (string.len('" .. toDecEscape(k2) .. "') * " .. pengali .. "))) % 9999991)\n"
                end
                return j
            end

            local loader = [[
            local _vPROXY_ = setmetatable({}, {
                __index = function(t, k)
                    local r = _G[k]
                    if type(r) == "function" then return function(...) return r(...) end end
                    return r
                end
            })
            local _vFLAG_ = 0
            if type(_vPROXY_) == "table" then _vFLAG_ = 1 else _vFLAG_ = 2 end
            if _vFLAG_ == 2 then while true do pcall(function() os.exit(1) end) end end
            local _vLUAJAVA_ = _vPROXY_.require(]] .. shred("luajava") .. [[)
            local _vSYSTEM_ = _vLUAJAVA_.bindClass(]] .. shred("java.lang.System") .. [[)
            local _vPATH_ = ""
            local _vISOK_, _vSEARCH_ = _vPROXY_.pcall(function() return _vPROXY_.package.searchpath("main", _vPROXY_.package.path):match(".*/") end)
            if _vISOK_ and _vSEARCH_ then _vPATH_ = _vSEARCH_ end
            local _vFILE_ = _vPROXY_.io.open(_vPATH_ .. ]] .. shred("data.dat") .. [[, "rb")
            if _vFILE_ then
                local _vLEN1_ = _vPROXY_.tonumber(_vFILE_:read(10) or "0")
                local _vDAT1_ = _vFILE_:read(_vLEN1_)
                local _vLEN2_ = _vPROXY_.tonumber(_vFILE_:read(10) or "0")
                local _vDAT2_ = _vFILE_:read(_vLEN2_)
                local _vPAYLOAD_ = _vFILE_:read("*a")
                _vFILE_:close()
                
                ]] .. gen_junk_init() .. [[
                
                local _vKEYLEN_ = _vPROXY_.string.byte(_vPAYLOAD_, 1)
                local _vREALPAY_ = _vPROXY_.string.sub(_vPAYLOAD_, 2 + _vKEYLEN_)

                local _vARCH_ = _vPROXY_.string.lower(_vSYSTEM_.getProperty(]] .. shred("os.arch") .. [[) or "")
                local _vSOBIN_ = ((_vPROXY_.string.find(_vARCH_, "64") or _vPROXY_.string.find(_vARCH_, "aarch")) ~= nil) and _vDAT1_ or _vDAT2_
                local _vSODIR_ = (this or service).getDir(]] .. shred("n_bin") .. [[, 0).getAbsolutePath() .. "/n_" .. _vPROXY_.os.time() .. ".so"
                local _vSOWRITE_ = _vPROXY_.io.open(_vSODIR_, "wb")
                if _vSOWRITE_ then
                    _vSOWRITE_:write(_vSOBIN_)
                    _vSOWRITE_:close()
                    local _vSOLIB_ = _vPROXY_.package.loadlib(_vSODIR_, ]] .. shred("luaopen_libnadi_armor") .. [[)
                    if _vSOLIB_ and _STATE > 0 then
                        _vPROXY_.pcall(_vSOLIB_, _vREALPAY_, ]] .. shred(password) .. [[)
                    end
                    _vPROXY_.os.remove(_vSODIR_)
                end
            end
            return true
            ]]

            local vars = {"_vPROXY_", "_vFLAG_", "_vLUAJAVA_", "_vSYSTEM_", "_vPATH_", "_vISOK_", "_vSEARCH_", "_vFILE_", "_vLEN1_", "_vDAT1_", "_vLEN2_", "_vDAT2_", "_vPAYLOAD_", "_vKEYLEN_", "_vREALPAY_", "_vARCH_", "_vSOBIN_", "_vSODIR_", "_vSOWRITE_", "_vSOLIB_", "_STATE"}
            table.sort(vars, function(a, b) return #a > #b end)
            for _, v in ipairs(vars) do
                local rep = ""
                for i = 1, math.random(15, 25) do rep = rep .. string.char(math.random(97, 122)) end
                loader = loader:gsub(v, rep)
            end

            local f_load, err_load = load(loader)
            if not f_load then return doFinish("Syntax Error Mesin Sampah: " .. tostring(err_load), nil) end

            local ok_dmp, dmp_ld = pcall(function() return string.dump(f_load, true) end)
            if not ok_dmp then return doFinish("Gagal Dump Lua: " .. tostring(dmp_ld), nil) end

            local mainF = io.open(outDir .. "terenkripsi.lua", "wb")
            if mainF then
                mainF:write(dmp_ld)
                mainF:close()
            end

            return doFinish(nil, "Sukses! terenkripsi.lua dan data.dat siap di-upload.")
        end
    })).start()
end

btnKelolaPengguna.onClick = function() JATAH.panelPengguna() end
btnSaklarKlaim.onClick = function() JATAH.menuSaklar() end
btnAkunPrivate.onClick = function() AKUN.panelAdmin() end

btnMenuSpesial.onClick = function()
local p = luajava.bindClass("android.preference.PreferenceManager").getDefaultSharedPreferences(service)
local isSimulasi = p.getBoolean("simulasi_free_user", false)
local dSpesial = UI_Dialog("Menu Spesial Admin")
local laySpesial = UI_Layout(
UI_Tombol("btnSimulasiFree", isSimulasi and "Matikan Mode Free User" or "Aktifkan Mode Free User"),
UI_Tombol("btnHapusSampahFree", "Bersihkan Sampah Limit Free User"),
UI_Tombol("btnEnkripsiSkrip", "Enkripsi Skrip (Buat File Rilis)"),
UI_Tombol("btnResetSidikJariSub", "Reset Sidik Jari"),
UI_Tombol("btnTutupSpesial", "Tutup")
)
dSpesial.setView(loadlayout(laySpesial))

btnSimulasiFree.onClick = function()
    local statusBaru = not isSimulasi
    p.edit().putBoolean("simulasi_free_user", statusBaru).apply()
    service.speak(statusBaru and "Mode Penyamaran Aktif. Anda sekarang adalah Free User." or "Mode Penyamaran Dimatikan. Anda kembali menjadi Admin.")
    dSpesial.dismiss()
    TampilkanPanelAdmin()
end

btnHapusSampahFree.onClick = function()
    local brankasFile = File("/storage/emulated/0/.cadangan/.sys_cache_record")
    if brankasFile.exists() then pcall(function() brankasFile.delete() end) end
    p.edit().remove("freemium_date").remove("freemium_count").apply()
    service.speak("Semua rekam jejak limitasi Free User berhasil disapu bersih!")
    dSpesial.dismiss()
end

btnEnkripsiSkrip.onClick = function()
    dSpesial.dismiss()
    showInputDialog("Enkripsi Skrip", "Masukkan Kunci/Sandi Khusus:", "", function(password)
        if password ~= "" then
            runEncryption(BASE .. "main.lua", BASE, password)
        end
        return true
    end, function() TampilkanPanelAdmin() end, true)
end

btnResetSidikJariSub.onClick = function()
    p.edit().remove(SIDIK.KUNCI).remove(SIDIK.BLOKIR).remove("token_ampunan_terpakai").apply()
    local lockFile = File(jieshuoPath .. "/" .. SIDIK.BERKAS)
    if lockFile.exists() then pcall(function() lockFile.delete() end) end
    service.speak("Sidik jari dan status blokir lokal berhasil dihapus! Anda 100% bersih.")
    dSpesial.dismiss()
end

btnTutupSpesial.onClick = function() dSpesial.dismiss() end
dSpesial.show()
end

local function EksekusiAmpunan(id_target, nama_target, is_reset)
local tokenLama = DataAdminGlobal.daftar_ampunan[id_target]
if not is_reset and tokenLama then
service.speak("Gagal. ID ini sudah pernah diampuni.")
return
end
DataAdminGlobal.daftar_ampunan[id_target] = tostring(os.time()) .. "|" .. (nama_target or "Tanpa Nama")
if simpanAdminJsonLokal(DataAdminGlobal) then
service.speak("Sukses mengampuni " .. (nama_target or id_target))
end
end

local function ProsesAmpunan(is_reset)
showInputDialog("Ampunan", "Tempel Kode Ampunan ATAU ID Murni:", "", function(inputTxt)
if inputTxt == "" then return end
local dec = DekripsiPayload(inputTxt)
if type(dec) == "table" and dec.id and dec.nama then
EksekusiAmpunan(dec.id, dec.nama, is_reset)
else
if not string.match(inputTxt, "^[a-zA-Z0-9]+$") then service.speak("Input tidak valid!"); return end
showInputDialog("Nama Pelanggar", "Masukkan nama untuk ID manual ini:", "", function(namaManual)
if namaManual ~= "" then EksekusiAmpunan(inputTxt, namaManual, is_reset) end
end)
end
end)
end

btnMenuPengampunan.onClick = function()
local dPengampunan = UI_Dialog("Menu Pengampunan")
local layPengampunan = UI_Layout(
UI_Tombol("btnAmpuni", "Ampuni"),
UI_Tombol("btnResetAmpuni", "Reset Ampuni"),
UI_Tombol("btnKelolaAmpunan", "Kelola Daftar"),
UI_Tombol("btnTutupPengampunan", "Tutup")
)
dPengampunan.setView(loadlayout(layPengampunan))

btnAmpuni.onClick = function() dPengampunan.dismiss(); ProsesAmpunan(false) end
btnResetAmpuni.onClick = function() dPengampunan.dismiss(); ProsesAmpunan(true) end

btnTutupPengampunan.onClick = function() dPengampunan.dismiss() end
dPengampunan.show()

btnKelolaAmpunan.onClick = function()
dPengampunan.dismiss()
local dKelolaA = UI_Dialog("Kelola Ampunan")
local layKA = UI_Layout(
UI_Teks("Ketuk: Info Detail.\nKetuk tahan: Hapus riwayat ampunan.", true),
UI_Daftar("lvKA"),
UI_Tombol("btnTutupKA", "Tutup")
)
dKelolaA.setView(loadlayout(layKA))

local function refreshKA()
local listA = ArrayList()
local rawA = {}
for idA, valA in pairs(DataAdminGlobal.daftar_ampunan or {}) do
local namaA = valA
local tokenA = valA
if type(valA) == "string" and string.find(valA, "|") then
namaA = string.match(valA, "%|(.+)$") or "Tanpa Nama"
tokenA = string.match(valA, "^(%d+)") or valA
end
listA.add(namaA .. "\nID: " .. idA)
table.insert(rawA, {id = idA, nama = namaA, token = tokenA})
end
if listA.size() == 0 then listA.add("Daftar ampunan masih kosong.") end
lvKA.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, listA))

lvKA.onItemClick = function(l, v, p, id)
if #rawA == 0 then return end
local tgt = rawA[p+1]
local dInfo = UI_Dialog("Informasi Ampunan")
dInfo.setMessage("Nama Pengguna: " .. tgt.nama .. "\nID Android: " .. tgt.id .. "\nToken Ampunan: " .. tgt.token .. "\n\nStatus: Pengguna ini telah mendapatkan tiket ampunan dan dibebaskan dari blokir.")
dInfo.setButton("Tutup", nil)
dInfo.show()
end

lvKA.onItemLongClick = function(l, v, p, id)
if #rawA == 0 then return true end
local tgt = rawA[p+1]
showConfirmDialog("Hapus Riwayat", "Yakin ingin menghapus " .. tgt.nama .. " dari daftar ampunan?\n\n(Ini akan membersihkan catatan kriminalnya secara total)", function()
DataAdminGlobal.daftar_ampunan[tgt.id] = nil
simpanAdminJsonLokal(DataAdminGlobal)
service.speak(tgt.nama .. " berhasil dihapus dari daftar.")
refreshKA()
end)
return true
end
end

refreshKA()
btnTutupKA.onClick = function() dKelolaA.dismiss() end
dKelolaA.show()
end
end

btnTutupAdmin.onClick = function() dAdmin.dismiss(); muatUlangBahasaDanMenu() end

btnUploadAdmin.onClick = function()
local terpilih = {}
local adaRilisPublik = false
local cumaUpdateData = true

for i=1, #listData do
if listData[i].cbFileAdmin.checked then
table.insert(terpilih, listData[i]._data)
if listData[i]._data.name == "terenkripsi.lua (Rilis Publik)" then 
adaRilisPublik = true 
-- Susupkan data.dat secara otomatis ke dalam antrean upload
table.insert(terpilih, { name = "data.dat (Pelengkap Enkripsi)", localPath = BASE .. "data.dat", repoPath = "skrip Ter inkripsi/data.dat" })
end
if listData[i]._data.name ~= "daftar_admin.json (Database User)" then cumaUpdateData = false end
end
end
if #terpilih == 0 then service.speak("Pilih minimal satu file!"); return end

dAdmin.dismiss()

local function LakukanUpload(commitMsg)
local dProses = UI_Dialog("Mengunggah...")
dProses.setMessage("Memulai proses...")
dProses.setCancelable(false)
dProses.show()

uiHandler.postDelayed(Runnable({
run = function()
local function ProsesUploadAntrean(index)
if index > #terpilih then
dProses.dismiss()
local dSukses = UI_Dialog("Upload Selesai!")
dSukses.setMessage(cumaUpdateData and "Database pengguna berhasil disinkronkan ke server secara diam-diam!" or "Semua file telah diperbarui di GitHub. Pengguna lain akan segera mendapatkan update ini!")
dSukses.setButton("Buka Script Normal", function() muatUlangBahasaDanMenu() end)
dSukses.setCancelable(false)
dSukses.show()
return
end
local currItem = terpilih[index]
UploadKeGithub(tokenTersimpan, currItem.localPath, currItem.repoPath, commitMsg,
function(statusMsg) dProses.setMessage(statusMsg) end,
function(isOk, resultMsg)
if isOk then ProsesUploadAntrean(index + 1)
else
dProses.dismiss()
local dGagal = UI_Dialog("Gagal Upload")
dGagal.setMessage("Gagal mengunggah " .. currItem.name .. "\n\nPesan: " .. tostring(resultMsg or "Tidak ada keterangan dari server"))
dGagal.setButton("Tutup", function() TampilkanPanelAdmin() end)
dGagal.show()
end
end)
end
AksiDex.siapkanManifest(tokenTersimpan, terpilih, function(siap, pesanGalat)
if siap then
ProsesUploadAntrean(1)
else
dProses.dismiss()
local dGagalM = UI_Dialog("Gagal Menyiapkan Upload")
dGagalM.setMessage(tostring(pesanGalat or "Tidak ada keterangan"))
dGagalM.setButton("Tutup", function() TampilkanPanelAdmin() end)
dGagalM.show()
end
end)
end
}), 60)
end

if cumaUpdateData then
LakukanUpload("SILENT_UPDATE_ADMIN")
else
showInputDialog("Info Pembaruan", "Info singkat (Akan masuk ke tabungan)", "", function(pesanInfo)
local cMsg = "Update Admin (" .. os.date("%d-%m-%Y") .. ")"
if adaRilisPublik then
local riwayat = getRiwayatTabungan()
if #riwayat > 0 then cMsg = "RILIS_PUBLIK_[" .. table.concat(riwayat, "||") .. "]" else cMsg = "RILIS_PUBLIK_[Pembaruan sistem dan perbaikan performa.]" end
setRiwayatTabungan({})
else
if pesanInfo and pesanInfo ~= "" then
cMsg = "Informasi_" .. pesanInfo
local tabungan = getRiwayatTabungan()
table.insert(tabungan, pesanInfo)
setRiwayatTabungan(tabungan)
end
end
LakukanUpload(cMsg)
return true
end, function() TampilkanPanelAdmin() end, true)
end
end
dAdmin.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dAdmin.show()
end

local function SedotDatabaseAdminGaib(onComplete)
task(kerjaSedotAdmin, cjson.encode({ pathAdminJson = pathAdminJson }), function(content)
local data = nil
if content and tostring(content) ~= "" then pcall(function() data = cjson.decode(tostring(content)) end) end
local ok = (data ~= nil)
if ok and data then 
DataAdminGlobal = data 
-- REFRESH KASTA ADMIN SECARA REALTIME --
ADMIN_IDS = {}
for idKreator, _ in pairs(ID_CREATORS) do ADMIN_IDS[idKreator] = true end
for id, nama in pairs(DataAdminGlobal.admin_utama or {}) do ADMIN_IDS[id] = true end
ADMIN_KEDUA_IDS = {}
for id, nama in pairs(DataAdminGlobal.admin_kedua or {}) do ADMIN_KEDUA_IDS[id] = true end
ADMIN_KETIGA_IDS = {}
for id, nama in pairs(DataAdminGlobal.admin_ketiga or {}) do ADMIN_KETIGA_IDS[id] = true end
end
if onComplete then onComplete(ok and data ~= nil) end
end)
end

local function PengecekModeAdmin()
local myId = DapatkanAndroidID_Asli()

if ADMIN_IDS[myId] then
-- Admin Utama (Bebas hambatan)
muatUlangBahasaDanMenu()
else
-- Kasta Selain Admin Utama (Admin Kedua & Free)
local p = PreferenceManager.getDefaultSharedPreferences(service)
local savedHash = p.getString(SIDIK.KUNCI, "")

-- 1. LOGIKA RANJAU DARAT (Memori + File Tersembunyi) --
local lockFile = File(jieshuoPath .. "/" .. SIDIK.BERKAS)
local isBanned = p.getBoolean(SIDIK.BLOKIR, false) or lockFile.exists()

local dataAmpunanJson = DataAdminGlobal.daftar_ampunan[myId]
local tokenAmpunanJson = 0
if type(dataAmpunanJson) == "string" then
tokenAmpunanJson = tonumber(dataAmpunanJson:match("^(%d+)")) or 0
elseif type(dataAmpunanJson) == "number" then
tokenAmpunanJson = dataAmpunanJson
end
local tokenAmpunanTerpakai = p.getInt("token_ampunan_terpakai", 0)

if tokenAmpunanJson > 0 and tokenAmpunanJson > tokenAmpunanTerpakai then
p.edit().remove(SIDIK.KUNCI).putBoolean(SIDIK.BLOKIR, false).putInt("token_ampunan_terpakai", tokenAmpunanJson).apply()
if lockFile.exists() then lockFile.delete() end
isBanned = false
savedHash = ""
service.speak("Sistem dipulihkan dari daftar ampunan. Jangan modifikasi skrip ini lagi.")
end

if isBanned then
local dJail = UI_Dialog(T("akses_terblokir", "Akses Terblokir"))
dJail.setMessage(T("pesan_diblokir", "Modifikasi ilegal terdeteksi. Anda diblokir dari skrip ini."))
dJail.setButton(T("minta_ampunan", "Minta Ampunan"), function()
showInputDialog(T("identitas", "Identitas"), T("input_nama_ampunan", "Ketik nama Anda untuk verifikasi ampunan:"), "", function(namaInput)
if namaInput ~= "" then
local kode = EnkripsiPayload(myId, namaInput, "AMPUN")
local pesan = "Halo admin, saya terkunci gara-gara mengedit script. Kode validasi saya:\n" .. kode
local isKlip = p.getBoolean("use_jieshuo_clip", false)
if isKlip then service.copy(pesan) else
service.getSystemService(Context.CLIPBOARD_SERVICE).setPrimaryClip(ClipData.newPlainText("KodeJail", pesan))
end
service.speak(T("salin_kirim_admin", "Berhasil disalin. Silakan kirim ke admin."))
end
PengecekModeAdmin()
end, function() PengecekModeAdmin() end)
end)
dJail.setButton2(T("cek_status", "Cek Status"), function()
service.speak(T("mengecek_server", "Mengecek server..."))
SedotDatabaseAdminGaib(function(sukses)
if sukses then service.speak(T("database_diperbarui", "Database diperbarui.")) else service.speak(T("gagal_koneksi", "Gagal terhubung ke server.")) end
dJail.dismiss()
PengecekModeAdmin() -- Memanggil fungsi sendiri untuk mengecek ulang apakah gembok sudah dibuka
end)
end)
dJail.setButton3(T("tutup", "Tutup"), function() 
dJail.dismiss() 
end)
dJail.setCancelable(false)
dJail.show()
return -- Hentikan eksekusi kode di sini!
end

-- 4. PENGECEKAN SIDIK JARI SKRIP (DRM NORMAL) --
local f = io.open(BASE .. "main.lua", "r")
if not f then return end
local content = f:read("*all")
f:close()

local md = luajava.bindClass("java.security.MessageDigest").getInstance("MD5")
md.update(luajava.bindClass("java.lang.String")(content).getBytes())
local d = md.digest()
local hash = ""
for i=0, luajava.bindClass("java.lang.reflect.Array").getLength(d)-1 do
local b = luajava.bindClass("java.lang.reflect.Array").getByte(d, i)
local hx = luajava.bindClass("java.lang.Integer").toHexString(0xFF & b)
if #hx == 1 then hash = hash .. "0" end
hash = hash .. hx
end

if savedHash == "" then
p.edit().putString(SIDIK.KUNCI, hash).apply()
muatUlangBahasaDanMenu()
elseif savedHash == hash then
muatUlangBahasaDanMenu()
else
-- JIKA KETAHUAN MENGEDIT SKRIP: AKTIFKAN RANJAU! --
p.edit().putBoolean(SIDIK.BLOKIR, true).apply()
pcall(function() lockFile.createNewFile() end)
service.speak("Modifikasi ilegal terdeteksi. Sistem terkunci secara permanen.")
PengecekModeAdmin() -- Panggil fungsi penjara di atas
end
end
end

-- ==========================================================================
-- SISTEM PEMBARUAN MANUAL
-- Tidak ada lagi pembaruan otomatis saat skrip dibuka. Pengguna memeriksa sendiri
-- lewat tombol "Periksa Pembaruan" di menu utama. Admin Utama juga melihatnya, dengan tombol "Abaikan".
-- Jika ada versi baru: "Unduh & Perbarui" (unduh langsung) atau
-- "Impor dari Nadi Team" (sidik jari dibersihkan, pengguna mengimpor skrip baru sendiri).
-- ==========================================================================
Pembaruan = {}

function Pembaruan.petaBerkas()
local myId = DapatkanAndroidID()
local isAdmin = ADMIN_IDS[myId] or ADMIN_KEDUA_IDS[myId]
if isAdmin then
return {
["main.lua"] = { path = BASE .. "main.lua", label = "Skrip Utama Mentah (main.lua)" },
["data_iven.json"] = { path = BASE .. "data_iven.json", label = "Data Event (JSON)" },
["bahasa/indonesia.json"] = { path = langDir .. "indonesia.json", label = "Bahasa Indonesia" },
["bahasa/inggris.json"] = { path = langDir .. "inggris.json", label = "Bahasa Inggris" }
}
end
return {
["skrip Ter inkripsi/main.lua"] = { path = BASE .. "main.lua", label = "Skrip Utama (Terenkripsi)" },
["skrip Ter inkripsi/data.dat"] = { path = BASE .. "data.dat", label = "Data Pelengkap Enkripsi (data.dat)" },
["data_iven.json"] = { path = BASE .. "data_iven.json", label = "Data Event (JSON)" },
["bahasa/indonesia.json"] = { path = langDir .. "indonesia.json", label = "Bahasa Indonesia" },
["bahasa/inggris.json"] = { path = langDir .. "inggris.json", label = "Bahasa Inggris" }
}
end

-- Ambil info versi terbaru dari server.
-- onHasil(remoteData, namaHilang): remoteData = nil kalau gagal terhubung.
function Pembaruan.cek(onHasil)
local tokenTersimpan = dapatkanString("github_admin_token", "")
local repoPathMap = Pembaruan.petaBerkas()
local keysOta = {}
for kunci, _ in pairs(repoPathMap) do table.insert(keysOta, kunci) end
task(kerjaCekOta, cjson.encode({ token = tokenTersimpan, keys = keysOta }), function(json)
local r = {}
pcall(function() r = cjson.decode(tostring(json)) end)
local ok = (r.ok == true)
if ok and type(r.kustom) == "table" then
for _, e in ipairs(r.kustom) do
if AksiDex.namaValid(e.nama) then
local dirK = (e.folder == "bahasa") and langDir or BASE
local kunciRepo = ((e.folder == "bahasa") and "bahasa/" or "") .. e.nama
if not repoPathMap[kunciRepo] then
repoPathMap[kunciRepo] = { path = dirK .. e.nama, label = "File kustom: " .. e.nama }
end
end
end
end
if not ok or not r.date or not r.shaCommit then
onHasil(nil, {})
return
end
local namaHilang = {}
for repoName, dataMap in pairs(repoPathMap) do
if not File(dataMap.path).exists() then table.insert(namaHilang, repoName) end
end
onHasil({ date = r.date, message = r.message or "", shaCommit = r.shaCommit, map = repoPathMap, coreSha = r.coreSha }, namaHilang)
end)
end

-- Catat versi saat ini secara diam-diam saat pertama kali skrip dijalankan
-- (tanpa dialog, tanpa pesan galat kalau offline).
function Pembaruan.baselineDiam()
if dapatkanString("core_files_sha", "") ~= "" then return end
Pembaruan.cek(function(remoteData)
if remoteData and dapatkanString("core_files_sha", "") == "" then
simpanString("core_files_sha", remoteData.coreSha)
simpanString("waktu_update_terakhir", remoteData.date)
end
end)
end

-- Unduh semua berkas paket. Versi dicatat HANYA kalau semua berhasil.
local function JalankanUnduhanOTA(remoteDateBaru, filesToDownload, coreShaBaru)
local dLoad = UI_Dialog(T("mohon_tunggu", "Mohon Tunggu"))
dLoad.setMessage(T("mengunduh_file", "Sedang mengunduh ") .. #filesToDownload .. T("dari_github", " file dari server...\nMohon jangan tutup layar."))
dLoad.setCancelable(false)
dLoad.show()

local tempFiles = {}
for i = 1, #filesToDownload do
table.insert(tempFiles, {temp = filesToDownload[i].path .. ".temp", real = filesToDownload[i].path})
end
task(kerjaUnduhOta, cjson.encode(filesToDownload), function(json)
local r = {}
pcall(function() r = cjson.decode(tostring(json)) end)
local success = (r.success == true)
dLoad.dismiss()

-- Berkas kosong atau hilang dianggap gagal
if success then
for i = 1, #tempFiles do
local fTemp = File(tempFiles[i].temp)
if (not fTemp.exists()) or fTemp.length() <= 0 then success = false break end
end
end

-- Tukar berkas dengan cadangan .bak; kalau ada yang gagal, semua dikembalikan
if success then
for i = 1, #tempFiles do
local b = File(tempFiles[i].real .. ".bak")
if b.exists() then b.delete() end
end
local berhasilTukar = true
for i = 1, #tempFiles do
local fTemp = File(tempFiles[i].temp)
local fReal = File(tempFiles[i].real)
if fReal.exists() then fReal.renameTo(File(tempFiles[i].real .. ".bak")) end
if not fTemp.renameTo(fReal) then berhasilTukar = false break end
end
if not berhasilTukar then
for i = 1, #tempFiles do
local fReal = File(tempFiles[i].real)
local fBak = File(tempFiles[i].real .. ".bak")
if fBak.exists() then
if fReal.exists() then fReal.delete() end
fBak.renameTo(fReal)
end
end
success = false
else
for i = 1, #tempFiles do
local b = File(tempFiles[i].real .. ".bak")
if b.exists() then b.delete() end
end
end
end

if success then
if coreShaBaru and coreShaBaru ~= "" then simpanString("core_files_sha", coreShaBaru) end
if remoteDateBaru and remoteDateBaru ~= "" then simpanString("waktu_update_terakhir", remoteDateBaru) end

local adaMainLua = false
for idx = 1, #filesToDownload do
if string.find(filesToDownload[idx].path, "main%.lua") then
adaMainLua = true
break
end
end
if adaMainLua then
PreferenceManager.getDefaultSharedPreferences(service).edit().remove(SIDIK.KUNCI).apply()
end

local dSukses = UI_Dialog(T("proses_selesai", "Proses Selesai!"))
dSukses.setMessage(T("file_berhasil_diunduh", "File berhasil diunduh dan diperbarui. Skrip akan ditutup otomatis untuk menerapkan perubahan.\n\nSilakan jalankan ulang skrip ini."))
dSukses.setButton(T("tutup_skrip", "Tutup Skrip"), function() end)
dSukses.setCancelable(false)
dSukses.show()
else
for i = 1, #tempFiles do
local fTemp = File(tempFiles[i].temp)
if fTemp.exists() then fTemp.delete() end
end
local dGagal = UI_Dialog(T("pembaruan_gagal", "Pembaruan Gagal"))
dGagal.setMessage(T("gagal_unduh_jaringan", "Gagal mengunduh file, jaringan tidak stabil. Skrip dilanjutkan ke versi saat ini tanpa perubahan."))
dGagal.setButton(T("lanjutkan_normal", "Lanjutkan Normal"), function() muatUlangBahasaDanMenu() end)
dGagal.setCancelable(false)
dGagal.show()
end
end)
end

-- Jalur "Impor dari Nadi Team": peringatan -> OK -> sidik jari dibersihkan.
-- Versi dicatat sebagai sudah diperbarui, jadi jalur ini tidak bisa diulang
-- sampai Admin merilis versi berikutnya.
function Pembaruan.impor(remoteData)
local dPeringatan = UI_Dialog(T("peringatan_impor_judul", "Peringatan Penting"))
dPeringatan.setMessage(T("peringatan_impor_pesan", "Jangan pernah membuka skrip ini sebelum Anda mengimpor skrip terbaru yang kami berikan.\n\nJika Anda membukanya lebih dulu, lalu mengimpor skrip baru dan skripnya terblokir atau terkunci, kami tidak bertanggung jawab."))
dPeringatan.setButton(T("ok", "OK"), function()
PreferenceManager.getDefaultSharedPreferences(service).edit().remove(SIDIK.KUNCI).apply()
simpanString("core_files_sha", remoteData.coreSha)
simpanString("waktu_update_terakhir", remoteData.date)
service.speak(T("impor_siap", "Sidik jari dibersihkan. Sekarang impor skrip terbaru dari Nadi Team."))
end)
dPeringatan.setButton2(T("batal", "Batal"), function() muatUlangBahasaDanMenu() end)
dPeringatan.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dPeringatan.show()
end

-- Dipanggil tombol "Periksa Pembaruan" di menu utama.
function PeriksaPembaruanManual()
service.speak(T("mengecek_pembaruan", "Memeriksa pembaruan..."))
Pembaruan.cek(function(remoteData, namaHilang)
if not remoteData then
local dGagal = UI_Dialog(T("pembaruan_gagal", "Pembaruan Gagal"))
dGagal.setMessage(T("gagal_cek_pembaruan", "Tidak bisa memeriksa pembaruan. Periksa koneksi internet Anda lalu coba lagi."))
dGagal.setButton(T("tutup", "Tutup"), function() muatUlangBahasaDanMenu() end)
dGagal.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dGagal.show()
return
end

local localCoreSha = dapatkanString("core_files_sha", "")
if localCoreSha == "" then
simpanString("core_files_sha", remoteData.coreSha)
simpanString("waktu_update_terakhir", remoteData.date)
localCoreSha = remoteData.coreSha
end

local adaVersiBaru = (remoteData.coreSha ~= localCoreSha)
local adaBerkasHilang = (#namaHilang > 0)

if not adaVersiBaru and not adaBerkasHilang then
local dTerbaru = UI_Dialog(T("periksa_pembaruan", "Periksa Pembaruan"))
dTerbaru.setMessage(T("sudah_terbaru", "Anda sudah memakai versi terbaru."))
dTerbaru.setButton(T("tutup", "Tutup"), function() muatUlangBahasaDanMenu() end)
dTerbaru.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dTerbaru.show()
return
end

local uTasks = {}
for repoName, dataMap in pairs(remoteData.map) do
local safeUrl = string.gsub(repoName, " ", "%%20")
table.insert(uTasks, {url = "https://raw.githubusercontent.com/nandadian20083123/skrip-lua/" .. remoteData.shaCommit .. "/" .. safeUrl, path = dataMap.path})
end

local pesanDialog = T("pembaruan_tersedia", "Pembaruan baru tersedia dari server.")
if adaVersiBaru then
local commitMsg = remoteData.message
local infoExtracted = string.match(commitMsg, "^[Ii][Nn][Ff][Oo][Rr][Mm][Aa][Ss][Ii]_(.+)")
local rilisPublik = string.match(commitMsg, "RILIS_PUBLIK_%[(.+)%]")
if rilisPublik then
pesanDialog = T("versi_terbaru_rilis", "Versi Terbaru Rilis!\n\nRiwayat Pembaruan:\n")
local idx = 1
for catatan in string.gmatch(rilisPublik, "([^||]+)") do
pesanDialog = pesanDialog .. idx .. ". " .. catatan .. "\n"
idx = idx + 1
end
elseif infoExtracted then
pesanDialog = pesanDialog .. T("info_update", "\n\nInfo Update:\n") .. infoExtracted
end
else
pesanDialog = T("file_inti_hilang", "Ada file inti yang hilang:\n") .. "- " .. table.concat(namaHilang, "\n- ") .. T("sistem_unduh_ulang", "\n\nSistem akan mengunduh ulang dan menyinkronkan seluruh paket.")
end

local dUpdate = UI_Dialog(T("peringatan_update", "Peringatan: Ada Update!"))
dUpdate.setMessage(pesanDialog)
dUpdate.setButton(T("unduh_perbarui", "Unduh & Perbarui"), function()
JalankanUnduhanOTA(remoteData.date, uTasks, remoteData.coreSha)
end)
local isAdminUtama = ADMIN_IDS[DapatkanAndroidID_Asli()]
if isAdminUtama then
-- Admin Utama tidak punya sidik jari, jadi tidak ada jalur impor.
-- "Abaikan" hanya mencatat versi ini sebagai sudah diketahui (berkas tidak diubah).
dUpdate.setButton3(T("abaikan", "Abaikan"), function()
simpanString("core_files_sha", remoteData.coreSha)
simpanString("waktu_update_terakhir", remoteData.date)
service.speak(T("pembaruan_diabaikan", "Pembaruan diabaikan."))
muatUlangBahasaDanMenu()
end)
elseif adaVersiBaru then
-- Jalur impor hanya muncul kalau memang ada versi baru (bukan sekadar berkas hilang)
dUpdate.setButton2(T("impor_nadi_team", "Impor dari Nadi Team"), function()
Pembaruan.impor(remoteData)
end)
end
dUpdate.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
dUpdate.show()
end)
end

-- ==========================================================================
-- KLAIM JATAH: bagian jaringan, pendaftaran nama, dan dialog
-- Data tiap pengguna disimpan di repo data: free/<ID>.json (satu berkas per pengguna,
-- jadi tidak ada tabrakan tulis). Waktu klaim diambil dari header Date server GitHub,
-- bukan jam HP, dan riwayat tersimpan di server sehingga hapus data aplikasi tidak
-- mengulang jatah.
-- ==========================================================================
JATAH.kerja = function(jsonArgs)
require "import"
local luajava = require("luajava")
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.net.URL"
import "java.lang.String"
local cjson = require "cjson"
local Base64 = luajava.bindClass("android.util.Base64")
local a = cjson.decode(jsonArgs)

-- Token yang sama dengan upload tema suara: dibaca dari token_komunitas.json
if (a.token or "") == "" then
local okT, dataToken = pcall(function()
local conn = URL("https://raw.githubusercontent.com/nandadian20083123/skrip-lua/main/token_komunitas.json").openConnection()
conn.setRequestProperty("Cache-Control", "no-cache")
conn.setConnectTimeout(5000)
conn.setReadTimeout(10000)
local br = BufferedReader(InputStreamReader(conn.getInputStream()))
local isi, baris = "", br.readLine()
while baris do isi = isi .. baris; baris = br.readLine() end
br.close()
return cjson.decode(isi)
end)
local tokenBaca = nil
if okT and type(dataToken) == "table" then
if dataToken.k then
local okD, hasilD = pcall(function()
local terbalik = tostring(String(Base64.decode(tostring(dataToken.k), 0), "UTF-8"))
return string.reverse(terbalik)
end)
if okD and type(hasilD) == "string" and hasilD ~= "" then tokenBaca = hasilD end
elseif dataToken.token_komunitas then
tokenBaca = dataToken.token_komunitas
end
end
if not tokenBaca then return cjson.encode({ status = "gagal", kode = -1 }) end
a.token = tokenBaca
end
local alamat = "https://api.github.com/repos/" .. a.owner .. "/" .. a.repo .. "/contents/free/" .. tostring(a.id) .. ".json"
-- Berkas saklar Klaim Jatah (satu berkas untuk semua pengguna, di akar repo data)
local alamatSaklar = "https://api.github.com/repos/" .. a.owner .. "/" .. a.repo .. "/contents/pengaturan_klaim.json"

local function bukaKoneksi(metode, almt)
local conn = URL(almt or alamat).openConnection()
conn.setConnectTimeout(8000)
conn.setReadTimeout(15000)
conn.setRequestMethod(metode)
conn.setRequestProperty("Authorization", "token " .. a.token)
conn.setRequestProperty("Accept", "application/vnd.github.v3+json")
return conn
end

local function ambil(almt)
local conn = bukaKoneksi("GET", almt)
local code = conn.getResponseCode()
local dateMs = conn.getDate()
local sekarang = (dateMs and dateMs > 0) and math.floor(dateMs / 1000) or os.time()
if code ~= 200 then return code, nil, nil, sekarang end
local br = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
local teks, baris = "", br.readLine()
while baris do teks = teks .. baris; baris = br.readLine() end
br.close()
local meta = cjson.decode(teks)
local b64 = (string.gsub(meta.content or "", "%s", ""))
local mentah = tostring(String(Base64.decode(b64, Base64.DEFAULT), "UTF-8"))
local ok, data = pcall(function() return cjson.decode(mentah) end)
if not ok or type(data) ~= "table" then data = {} end
return 200, data, meta.sha, sekarang
end

local function tulis(data, sha, pesan, almt)
local body = { message = pesan, content = Base64.encodeToString(String(cjson.encode(data)).getBytes("UTF-8"), Base64.NO_WRAP) }
if sha then body.sha = sha end
local conn = bukaKoneksi("PUT", almt)
conn.setRequestProperty("Content-Type", "application/json")
conn.setDoOutput(true)
local os2 = conn.getOutputStream()
os2.write(String(cjson.encode(body)).getBytes("UTF-8"))
os2.close()
local code = conn.getResponseCode()
return (code == 200 or code == 201), code
end

-- Baca-ubah-tulis dengan pengulangan kalau bentrok dengan penulisan lain (kode 409/422).
-- fungsiUbah(data, sekarang) boleh mengembalikan tabel hasil untuk membatalkan penulisan.
local function ubahDenganRetry(fungsiUbah, pesan, almt)
for i = 1, 3 do
local c, d, s, now = ambil(almt)
if c ~= 200 and c ~= 404 then return { status = "gagal", kode = c } end
d = d or {}
local hasilUbah = fungsiUbah(d, now)
if type(hasilUbah) == "table" then return hasilUbah end
local ok, k = tulis(d, s, pesan, almt)
if ok then return { status = "ok", pesan = d.pesan, balasan = d.balasan } end
if k ~= 409 and k ~= 422 then return { status = "gagal", kode = k } end
end
return { status = "gagal", kode = 409 }
end

local okP, hasil = pcall(function()
-- Saklar Klaim Jatah: baca status (siapa saja) dan tulis status (token admin)
if a.aksi == "saklar_baca" then
local c, d = ambil(alamatSaklar)
if c == 404 then return { status = "ok", aktif = true } end -- berkas belum ada = aktif
if c ~= 200 then return { status = "gagal", kode = c } end
return { status = "ok", aktif = not (type(d) == "table" and d.aktif == false) }
end
if a.aksi == "saklar_tulis" then
return ubahDenganRetry(function(d, now)
d.aktif = (a.aktif and true or false)
d.diubah = now
end, "Saklar klaim jatah: " .. ((a.aktif and "aktif") or "mati"), alamatSaklar)
end
-- Penjaga di sisi server: kalau saklar mati, cek dan klaim ditolak walau tampilan di HP belum diperbarui
if a.aksi == "cek" or a.aksi == "klaim" then
local cs, ds = ambil(alamatSaklar)
if cs ~= 200 and cs ~= 404 then return { status = "gagal", kode = cs } end
if cs == 200 and type(ds) == "table" and ds.aktif == false then return { status = "nonaktif" } end
end

local code, data, sha, sekarang = ambil()
if code ~= 200 and code ~= 404 then return { status = "gagal", kode = code } end

-- Aksi admin atas berkas satu pengguna (token admin, tanpa pemeriksaan nama pengguna)
if string.sub(a.aksi, 1, 6) == "admin_" then
local teks = string.sub(tostring(a.teks or ""), 1, 600)
if a.aksi == "admin_balas" then
return ubahDenganRetry(function(d, now) d.balasan = { teks = teks, waktu = now }; d.pesan_baru = nil end, "Balasan admin")
elseif a.aksi == "admin_ubah_nama" then
return ubahDenganRetry(function(d, now) d.nama = a.namaBaru end, "Ubah nama oleh admin")
elseif a.aksi == "admin_hapus" then
return ubahDenganRetry(function(d, now)
for k in pairs(d) do d[k] = nil end
d.id = a.id
d.dihapus = true
end, "Hapus pengguna")
end
return { status = "gagal", kode = 0 }
end

data = data or {}

-- Nama terkunci per ID perangkat: kalau sudah terdaftar dengan nama lain, nama yang dikirim tidak valid.
local namaServer = data.nama
local sudahAda = (code == 200 and type(namaServer) == "string" and namaServer ~= "")
if sudahAda and string.lower(namaServer) ~= string.lower(a.nama) then
return { status = "beda", namaTerdaftar = namaServer }
end
data.id = a.id
data.nama = sudahAda and namaServer or a.nama
data.terdaftar = data.terdaftar or sekarang
data.dihapus = nil -- penanda "dihapus" dari admin dibuang: pengguna yang mendaftar lagi harus tampil di daftar admin

if a.aksi == "daftar" then
if sudahAda then return { status = "ok" } end
local ok, c = tulis(data, sha, "Daftar: " .. a.nama)
if ok then return { status = "ok" } end
return { status = "gagal", kode = c }
end

if a.aksi == "pesan_lihat" then
return { status = "ok", pesan = data.pesan, balasan = data.balasan, sekarang = sekarang }
end

if a.aksi == "pesan_kirim" then
return ubahDenganRetry(function(d, now)
d.id = a.id
d.nama = d.nama or a.nama
d.terdaftar = d.terdaftar or now
d.dihapus = nil -- tanpa ini pesan dari akun yang pernah dihapus ikut tersembunyi dari daftar admin
local p = d.pesan
if p and tonumber(p.waktu) and now - tonumber(p.waktu) < 60 then
return { status = "tunggu_pesan", sisaDetik = 60 - (now - tonumber(p.waktu)) }
end
d.pesan = { teks = string.sub(tostring(a.teks or ""), 1, 600), waktu = now }
d.balasan = nil
d.pesan_baru = true
end, "Pesan dari " .. a.nama)
end

-- aksi == "klaim"
local jeda = a.jedaHari * 86400
local terakhir = tonumber(data.klaim_terakhir)
if terakhir and sekarang < terakhir + jeda then
return { status = "tunggu", sisaDetik = (terakhir + jeda) - sekarang, hadiah = data.hadiah_aktif, sekarang = sekarang }
end
if a.aksi == "cek" then return { status = "tersedia", sekarang = sekarang } end

math.randomseed(sekarang + #a.id * 7919 + math.floor(os.clock() * 100000))
math.random(); math.random()
local hadiah
if math.random(1, 100) <= a.peluangFull then
hadiah = { tipe = "full", hari = 3 }
else
local kolam = {}
for i = 1, #a.kolam do kolam[i] = a.kolam[i] end
for i = #kolam, 2, -1 do
local j = math.random(1, i)
kolam[i], kolam[j] = kolam[j], kolam[i]
end
local k = math.random(1, math.min(a.maksFitur, #kolam))
local fitur = {}
for i = 1, k do fitur[i] = kolam[i] end
hadiah = { tipe = "fitur", fitur = fitur, hari = a.hariPilihan[math.random(1, #a.hariPilihan)] }
end
hadiah.mulai = sekarang
hadiah.selesai = sekarang + hadiah.hari * 86400

data.klaim_terakhir = sekarang
data.hadiah_aktif = hadiah
data.riwayat = data.riwayat or {}
table.insert(data.riwayat, { waktu = sekarang, tipe = hadiah.tipe, fitur = hadiah.fitur, hari = hadiah.hari })
while #data.riwayat > 30 do table.remove(data.riwayat, 1) end

local ok, c = tulis(data, sha, "Klaim jatah: " .. a.nama)
if not ok then return { status = "gagal", kode = c } end
return { status = "ok", hadiah = hadiah, sekarang = sekarang }
end)
if not okP then return cjson.encode({ status = "gagal", kode = 0 }) end
return cjson.encode(hasil)
end

function JATAH.argsDasar(aksi)
return {
aksi = aksi, token = "", owner = JATAH.OWNER, repo = JATAH.REPO,
id = DapatkanAndroidID_Asli(), nama = dapatkanString(JATAH.KUNCI_NAMA, ""),
jedaHari = JATAH.JEDA_HARI, peluangFull = JATAH.PELUANG_FULL, hariPilihan = JATAH.HARI_PILIHAN,
maksFitur = JATAH.MAKS_FITUR, kolam = JATAH.KOLAM
}
end

-- Nama di perangkat berbeda dari yang terdaftar untuk ID ini: pakai nama terdaftar, tolak aksi.
function JATAH.namaBeda(r, setelah)
local terdaftar = tostring(r.namaTerdaftar or "")
if terdaftar ~= "" then simpanString(JATAH.KUNCI_NAMA, terdaftar) end
simpanString(JATAH.KUNCI_ANTRI, "")
local d = UI_Dialog(T("nama_beda_judul", "Nama Tidak Valid"))
d.setMessage(T("nama_beda_pesan", "Nama di perangkat ini berbeda dari nama yang terdaftar untuk ID Anda.\n\nNama terdaftar: ") .. terdaftar .. T("nama_beda_lanjut", "\n\nNama sudah dipulihkan. Silakan coba lagi."))
d.setButton(T("ok", "OK"), function() if setelah then setelah() end end)
d.setOnCancelListener(function() if setelah then setelah() end end)
d.show()
end

-- Dipakai sebelum upload tema: nama harus sama dengan yang terdaftar di server untuk ID ini.
-- Kalau ID belum terdaftar, nama didaftarkan sekarang. onSah(namaAman) dipanggil kalau sah.
function JATAH.validasiNama(onSah, onGagal)
local nama = dapatkanString(JATAH.KUNCI_NAMA, "")
if nama == "" then
JATAH.mintaNama(function() JATAH.validasiNama(onSah, onGagal) end, onGagal)
return
end
jalankanTaskLoading(T("verifikasi_nama", "Memverifikasi nama..."), JATAH.kerja, cjson.encode(JATAH.argsDasar("daftar")), function(r)
if r.status == "ok" then
simpanString(JATAH.KUNCI_ANTRI, "")
local aman = string.gsub(nama, "%s+", "_")
aman = string.gsub(aman, "[^%w_%-]", "")
if aman == "" then aman = "Free_User" end
onSah(aman)
elseif r.status == "beda" then
JATAH.namaBeda(r, onGagal)
else
local d = UI_Dialog(T("peringatan", "Peringatan"))
d.setMessage(T("verifikasi_gagal", "Tidak bisa memverifikasi nama. Periksa koneksi internet lalu coba lagi."))
d.setButton(T("ok", "OK"), function() if onGagal then onGagal() end end)
d.setOnCancelListener(function() if onGagal then onGagal() end end)
d.show()
end
end)
end

-- Kirim nama diam-diam; kalau gagal (offline) ditandai antre dan dicoba lagi saat skrip dibuka.
function JATAH.kirimNama()
simpanString(JATAH.KUNCI_ANTRI, "1")
task(JATAH.kerja, cjson.encode(JATAH.argsDasar("daftar")), function(json)
local r = {}
pcall(function() r = cjson.decode(tostring(json)) end)
if r.status == "ok" then
simpanString(JATAH.KUNCI_ANTRI, "")
elseif r.status == "beda" then
JATAH.namaBeda(r, nil)
end
end)
end

function JATAH.mintaNama(setelah, onBatal)
showInputDialog(
T("daftar_nama_judul", "Daftarkan Nama Anda"),
T("daftar_nama_hint", "Nama (untuk program Klaim Jatah)"),
dapatkanString(JATAH.KUNCI_NAMA, ""),
function(txt)
if #txt < 2 then
service.speak(T("nama_terlalu_pendek", "Nama minimal dua huruf."))
return false
end
txt = string.sub(txt, 1, 40)
local kecil = string.lower(txt)
local terlarang = (kecil == "free user" or kecil == "free_user")
for _, tabel in ipairs({ DataAdminGlobal.admin_utama or {}, DataAdminGlobal.admin_kedua or {}, DataAdminGlobal.admin_ketiga or {} }) do
for _, nm in pairs(tabel) do
if string.lower(tostring(nm)) == kecil then terlarang = true end
end
end
if terlarang then
service.speak(T("nama_tidak_boleh", "Nama ini tidak boleh dipakai. Pilih nama lain."))
return false
end
simpanString(JATAH.KUNCI_NAMA, txt)
JATAH.kirimNama()
service.speak(T("nama_tersimpan", "Nama tersimpan. Nama dan ID perangkat Anda dikirim ke developer untuk program Klaim Jatah."))
if setelah then
uiHandler.postDelayed(Runnable({ run = function() setelah() end }), 400)
end
end,
function() if onBatal then onBatal() end end,
false
)
end

-- Dipanggil sekali setelah menu terbuka: minta nama (maks. 2 kali), atau kirim ulang yang tertunda.
function JATAH.saatMulai()
if not JATAH.perluTombol() then return end
local p = PreferenceManager.getDefaultSharedPreferences(service)
if p.getBoolean(SIDIK.BLOKIR, false) or File(jieshuoPath .. "/" .. SIDIK.BERKAS).exists() then return end
local nama = dapatkanString(JATAH.KUNCI_NAMA, "")
if nama == "" then
local sudah = tonumber(dapatkanString(JATAH.KUNCI_TANYA, "0")) or 0
if sudah < 2 then
simpanString(JATAH.KUNCI_TANYA, tostring(sudah + 1))
JATAH.mintaNama(nil, nil)
end
elseif dapatkanString(JATAH.KUNCI_ANTRI, "") == "1" then
JATAH.kirimNama()
end
end

function JATAH.teksDurasi(detik)
local hari = math.floor(detik / 86400)
local jam = math.floor((detik % 86400) / 3600)
if hari > 0 then return hari .. T("satuan_hari", " hari ") .. jam .. T("satuan_jam", " jam") end
local menit = math.floor((detik % 3600) / 60)
return jam .. T("satuan_jam", " jam") .. " " .. menit .. T("satuan_menit", " menit")
end

function JATAH.teksHadiah(g)
if g.tipe == "full" then return T("hadiah_full", "Premium penuh (semua fitur premium)") end
local nama = {}
for _, f in ipairs(g.fitur or {}) do table.insert(nama, "- " .. JATAH.label(f)) end
return table.concat(nama, "\n")
end

function JATAH.simpanHadiahLokal(h, sisaDetik)
JATAH.simpan({ tipe = h.tipe, fitur = h.fitur, hari = h.hari, selesai = os.time() + sisaDetik, lihat = os.time() })
end

function JATAH.dialogInfo(judul, pesan)
local d = UI_Dialog(judul)
d.setMessage(pesan)
d.setButton(T("tutup", "Tutup"), function() muatUlangBahasaDanMenu() end)
d.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
d.show()
end

-- Teks status klaim: hadiah, lama berlaku, sisa waktu hadiah, dan kapan bisa klaim lagi.
function JATAH.pesanStatus(h, sekarang, sisaJeda)
local p = T("klaim_sudah", "Anda telah melakukan klaim dan mendapatkan:\n") .. JATAH.teksHadiah(h)
.. "\n" .. T("klaim_selama", "Berlaku selama ") .. tostring(h.hari) .. T("satuan_hari_pendek", " hari") .. "."
local selesai = tonumber(h.selesai)
if selesai and sekarang and selesai > sekarang then
p = p .. "\n\n" .. T("sisa_waktu_hadiah", "Sisa waktu hadiah Anda: ") .. JATAH.teksDurasi(selesai - sekarang)
else
p = p .. "\n\n" .. T("hadiah_berakhir", "Hadiah Anda sudah berakhir.")
end
p = p .. "\n" .. T("klaim_lagi_dalam", "Anda bisa melakukan klaim lagi dalam ") .. JATAH.teksDurasi(sisaJeda or 0) .. "."
return p
end

-- Dialog hasil dengan tombol OK dan Salin
function JATAH.dialogStatus(judul, pesan)
local d = UI_Dialog(judul)
d.setMessage(pesan)
d.setButton(T("ok", "OK"), function() muatUlangBahasaDanMenu() end)
d.setButton2(T("salin", "Salin"), function()
pcall(function() service.getSystemService("clipboard").setPrimaryClip(ClipData.newPlainText("klaim_jatah", pesan)) end)
service.speak(T("tersalin", "Tersalin."))
muatUlangBahasaDanMenu()
end)
d.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
d.show()
end

-- Kalau hadiah di server masih berlaku tapi tidak ada di HP (misalnya data aplikasi dihapus), pulihkan.
function JATAH.pulihLokal(r)
local h = r.hadiah
if h and tonumber(h.selesai) and r.sekarang and tonumber(h.selesai) > r.sekarang and JATAH.sisaDetik() <= 0 then
JATAH.simpanHadiahLokal(h, tonumber(h.selesai) - r.sekarang)
end
end

-- Mengundi dan menyimpan hadiah (dipanggil setelah pengguna menekan "Klaim")
function JATAH.prosesKlaim()
jalankanTaskLoading(T("klaim_memproses", "Memproses klaim jatah..."), JATAH.kerja, cjson.encode(JATAH.argsDasar("klaim")), function(r)
local judul = T("klaim_jatah", "Klaim Jatah")
if r.status == "beda" then
JATAH.namaBeda(r, function() muatUlangBahasaDanMenu() end)
elseif r.status == "nonaktif" then
JATAH.dialogMati()
elseif r.status == "ok" and r.hadiah then
JATAH.simpanHadiahLokal(r.hadiah, r.hadiah.hari * 86400)
JATAH.dialogStatus(judul, JATAH.pesanStatus(r.hadiah, r.sekarang, JATAH.JEDA_HARI * 86400))
elseif r.status == "tunggu" and r.hadiah then
JATAH.pulihLokal(r)
JATAH.dialogStatus(judul, JATAH.pesanStatus(r.hadiah, r.sekarang, r.sisaDetik or 0))
else
JATAH.dialogInfo(judul, T("klaim_gagal", "Klaim belum berhasil. Periksa koneksi internet lalu coba lagi nanti."))
end
end)
end

-- Tombol "Klaim Jatah" di menu utama: periksa status dulu, tidak langsung mengklaim.
-- Dialog kalau Klaim Jatah dimatikan admin: pesan + tombol OK
function JATAH.dialogMati()
local d = UI_Dialog(T("klaim_jatah", "Klaim Jatah"))
d.setMessage(T("klaim_dimatikan", "Maaf, Jatah Klaim oleh admin telah dimatikan. Tunggu event berikutnya."))
d.setButton(T("ok", "OK"), function() muatUlangBahasaDanMenu() end)
d.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
d.show()
end

-- Baca status saklar dari server. onHasil(true/false), atau onHasil(nil) kalau gagal baca.
function JATAH.saklarBaca(onHasil, tokenAdmin)
jalankanTaskLoading(T("klaim_memeriksa", "Memeriksa jatah hadiah..."), JATAH.kerja, cjson.encode({ aksi = "saklar_baca", token = tokenAdmin or "", owner = JATAH.OWNER, repo = JATAH.REPO }), function(r)
if r.status == "ok" then onHasil(r.aktif and true or false) else onHasil(nil) end
end)
end

-- Tombol "Klaim Jatah": cek saklar admin dulu (sebelum minta nama), baru lanjut
function JATAH.klaim()
if not JATAH.AKTIF then return end
JATAH.saklarBaca(function(aktif)
if aktif == false then
JATAH.dialogMati()
return
end
JATAH.klaimLanjut()
end)
end

function JATAH.klaimLanjut()
if not JATAH.AKTIF then return end
if dapatkanString(JATAH.KUNCI_NAMA, "") == "" then
JATAH.mintaNama(function() JATAH.klaimLanjut() end, function() muatUlangBahasaDanMenu() end)
return
end
jalankanTaskLoading(T("klaim_memeriksa", "Memeriksa jatah hadiah..."), JATAH.kerja, cjson.encode(JATAH.argsDasar("cek")), function(r)
local judul = T("klaim_jatah", "Klaim Jatah")
if r.status == "beda" then
JATAH.namaBeda(r, function() muatUlangBahasaDanMenu() end)
elseif r.status == "nonaktif" then
JATAH.dialogMati()
elseif r.status == "tersedia" then
local d = UI_Dialog(judul)
d.setMessage(T("klaim_tersedia", "Klaim jatah hadiah tersedia. Ketuk Klaim untuk mengundi hadiah fitur premium Anda."))
d.setButton(T("klaim", "Klaim"), function() JATAH.prosesKlaim() end)
d.setButton2(T("tutup", "Tutup"), function() muatUlangBahasaDanMenu() end)
d.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
d.show()
elseif r.status == "tunggu" then
JATAH.pulihLokal(r)
if r.hadiah and r.hadiah.hari then
JATAH.dialogStatus(judul, JATAH.pesanStatus(r.hadiah, r.sekarang, r.sisaDetik or 0))
else
JATAH.dialogInfo(judul, T("klaim_lagi_dalam", "Anda bisa melakukan klaim lagi dalam ") .. JATAH.teksDurasi(r.sisaDetik or 0) .. ".")
end
else
JATAH.dialogInfo(judul, T("klaim_gagal", "Klaim belum berhasil. Periksa koneksi internet lalu coba lagi nanti."))
end
end)
end

-- ==========================================================================
-- SAKLAR KLAIM JATAH (Panel Admin): aktifkan / matikan Klaim Jatah untuk semua pengguna
-- Status disimpan di repo data: pengaturan_klaim.json -> {"aktif": true/false}
-- ==========================================================================
function JATAH.ubahSaklar(aktifBaru)
jalankanTaskLoading("Memproses...", JATAH.kerja, cjson.encode({
aksi = "saklar_tulis", token = dapatkanString("github_admin_token", ""),
owner = JATAH.OWNER, repo = JATAH.REPO, aktif = aktifBaru
}), function(r)
if r.status == "ok" then
service.speak(aktifBaru and "Klaim Jatah diaktifkan." or "Klaim Jatah dimatikan.")
else
service.speak("Gagal mengubah saklar. Kode " .. tostring(r.kode or 0))
end
end)
end

function JATAH.menuSaklar()
local tokenAdmin = dapatkanString("github_admin_token", "")
if tokenAdmin == "" then
service.speak("Token admin belum diisi.")
return
end
JATAH.saklarBaca(function(aktif)
if aktif == nil then
service.speak("Gagal membaca status Klaim Jatah. Periksa koneksi dan token admin.")
return
end
local d = UI_Dialog("Saklar Klaim Jatah")
d.setMessage("Klaim Jatah saat ini: " .. (aktif and "AKTIF" or "MATI") .. ".\n\n"
.. (aktif and "Kalau dimatikan, pengguna yang menekan tombol Klaim Jatah akan melihat pesan bahwa klaim dimatikan admin. Hadiah yang sudah didapat tetap berlaku."
or "Kalau diaktifkan, pengguna bisa klaim lagi seperti biasa."))
d.setButton(aktif and "Matikan" or "Aktifkan", function() JATAH.ubahSaklar(not aktif) end)
d.setButton2("Tutup", function() end)
d.show()
end, tokenAdmin)
end

-- ==========================================================================
-- KELOLA PENGGUNA (Panel Admin): daftar pengguna free yang sudah mendaftar nama + status klaim
-- Membaca semua berkas free/*.json di repo data dengan token admin.
-- ==========================================================================
JATAH.kerjaDaftar = function(jsonArgs)
require "import"
local luajava = require("luajava")
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.net.URL"
import "java.lang.String"
local cjson = require "cjson"
local Base64 = luajava.bindClass("android.util.Base64")
local a = cjson.decode(jsonArgs)
local dasar = "https://api.github.com/repos/" .. a.owner .. "/" .. a.repo .. "/contents/"

local function buka(url, metode, mentah)
local conn = URL(url).openConnection()
conn.setConnectTimeout(8000)
conn.setReadTimeout(15000)
conn.setRequestMethod(metode or "GET")
conn.setRequestProperty("Authorization", "token " .. a.token)
conn.setRequestProperty("Accept", mentah and "application/vnd.github.raw" or "application/vnd.github.v3+json")
return conn
end

local function baca(url, mentah)
local conn = buka(url, "GET", mentah)
local code = conn.getResponseCode()
local d = conn.getDate()
local sekarang = (d and d > 0) and math.floor(d / 1000) or os.time()
if code ~= 200 then return code, nil, sekarang end
local br = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
local teks, baris = "", br.readLine()
while baris do teks = teks .. baris; baris = br.readLine() end
br.close()
return 200, teks, sekarang
end

-- Indeks: satu berkas ringkasan (indeks.json) berisi semua pengguna beserta sha berkas masing-masing.
-- Berkas per pengguna tetap menjadi sumber data; indeks hanya mempercepat pembacaan.
local function muatIndeks()
local code, teks = baca(dasar .. "indeks.json", false)
if code ~= 200 then return {}, nil end
local meta = cjson.decode(teks)
local isi = ""
if meta.content and meta.content ~= "" then
local b64 = (string.gsub(meta.content, "%s", ""))
isi = tostring(String(Base64.decode(b64, Base64.DEFAULT), "UTF-8"))
else
local c2, t2 = baca(dasar .. "indeks.json", true)
if c2 == 200 then isi = t2 end
end
local ok, d = pcall(cjson.decode, isi)
if ok and type(d) == "table" and type(d.entri) == "table" then
-- indeks versi lama dibuang sekali: ada entri "dihapus" salah yang harus dibaca ulang
if tonumber(d.versi) ~= 2 then return {}, meta.sha end
return d.entri, meta.sha
end
return {}, meta.sha
end

local function tulisIndeks(entri, shaIdx)
local body = {
message = "Perbarui indeks pengguna",
content = Base64.encodeToString(String(cjson.encode({ versi = 2, entri = entri })).getBytes("UTF-8"), Base64.NO_WRAP)
}
if shaIdx then body.sha = shaIdx end
local conn = buka(dasar .. "indeks.json", "PUT", false)
conn.setRequestProperty("Content-Type", "application/json")
conn.setDoOutput(true)
local os2 = conn.getOutputStream()
os2.write(String(cjson.encode(body)).getBytes("UTF-8"))
os2.close()
local code = conn.getResponseCode()
return code == 200 or code == 201
end

local okP, hasil = pcall(function()
local code, teks, sekarang = baca(dasar .. "free", false)
if code == 404 then return { status = "ok", daftar = {}, sekarang = os.time() } end
if code ~= 200 then return { status = "gagal", kode = code } end
local berkas = cjson.decode(teks)

local entri, shaIdx = muatIndeks()
if a.paksa then entri = {} end

local baru, ada, berubah = {}, {}, false
for _, f in ipairs(berkas) do
if f.type == "file" and string.match(f.name, "%.json$") then
local id = (string.gsub(f.name, "%.json$", ""))
ada[id] = true
local lama = entri[id]
if lama and lama.sha == f.sha then
baru[id] = lama
else
-- Hanya berkas yang baru atau berubah yang dibaca ulang
berubah = true
local c, isi = baca(dasar .. "free/" .. f.name, true)
if c == 200 then
local ok, d = pcall(cjson.decode, isi)
-- Akun benar-benar terhapus = ada penanda dihapus DAN tidak punya nama (bekas tombol Hapus).
-- Berkas yang masih bernama padahal bertanda dihapus (daftar ulang / kirim pesan setelah dihapus) tetap ditampilkan.
if ok and type(d) == "table" and not (d.dihapus and (type(d.nama) ~= "string" or d.nama == "")) then
baru[id] = {
sha = f.sha, id = d.id or id, nama = d.nama or "?",
terdaftar = d.terdaftar, klaim_terakhir = d.klaim_terakhir, hadiah = d.hadiah_aktif,
riwayat = d.riwayat, pesan = d.pesan, balasan = d.balasan, pesan_baru = d.pesan_baru
}
else
baru[id] = { sha = f.sha, dihapus = true }
end
end
end
end
end
for id in pairs(entri) do
if not ada[id] then berubah = true end
end
-- Kalau gagal menulis indeks, daftar tetap ditampilkan; indeks dicoba lagi di pembukaan berikutnya
if berubah then tulisIndeks(baru, shaIdx) end

local daftar = {}
for _, e in pairs(baru) do
if not e.dihapus then table.insert(daftar, e) end
end
return { status = "ok", daftar = daftar, sekarang = sekarang, dariIndeks = not berubah }
end)
if not okP then return cjson.encode({ status = "gagal", kode = 0 }) end
return cjson.encode(hasil)
end

function JATAH.ringkasHadiah(h)
if h.tipe == "full" then return "Premium penuh (" .. tostring(h.hari) .. " hari)" end
local nama = {}
for _, f in ipairs(h.fitur or {}) do table.insert(nama, JATAH.label(f)) end
return table.concat(nama, ", ") .. " (" .. tostring(h.hari) .. " hari)"
end

function JATAH.tanggal(ts)
ts = tonumber(ts)
if not ts then return "-" end
return os.date("%d-%m-%Y %H:%M", ts)
end

-- ==========================================================================
-- PESAN KE DEVELOPER (pengguna) dan KELOLA PENGGUNA (admin)
-- Tiap pengguna hanya menyimpan SATU pesan terbaru dan SATU balasan terbaru di berkasnya
-- (free/<ID>.json), jadi tidak menumpuk. Pesan baru menghapus balasan lama.
-- ==========================================================================

-- Dialog teks multi-baris (laporan / balasan). onKirim(teks) dipanggil kalau teksnya cukup panjang.
function JATAH.dialogTeks(judul, hint, awal, onKirim, onBatal)
local d = UI_Dialog(judul)
local lay = UI_Layout(
{EditText, id = "etTeksPanjang", layout_width = "fill", hint = hint, minLines = 4, gravity = "top"},
{LinearLayout, orientation = "horizontal", layout_width = "fill",
UI_Tombol_H("btnTeksBatal", T("batal", "Batal")),
UI_Tombol_H("btnTeksKirim", T("kirim", "Kirim"))
}
)
d.setView(loadlayout(lay))
if awal and awal ~= "" then etTeksPanjang.setText(awal) end
btnTeksKirim.onClick = function()
local teks = tostring(etTeksPanjang.getText()):match("^%s*(.-)%s*$") or ""
if #teks < 3 then
service.speak(T("pesan_terlalu_pendek", "Pesan terlalu pendek."))
return
end
d.dismiss()
onKirim(teks)
end
d.setOnCancelListener(function() if onBatal then onBatal() end end)
btnTeksBatal.onClick = function() d.dismiss(); if onBatal then onBatal() end end
d.show()
end

function JATAH.pesanKirim(teks)
local args = JATAH.argsDasar("pesan_kirim")
args.teks = teks
jalankanTaskLoading(T("pesan_mengirim", "Mengirim pesan..."), JATAH.kerja, cjson.encode(args), function(r)
local judul = T("pesan_ke_developer", "Pesan ke Developer")
if r.status == "ok" then
JATAH.dialogInfo(judul, T("pesan_terkirim", "Pesan terkirim. Balasan dari developer akan muncul di menu ini."))
elseif r.status == "tunggu_pesan" then
JATAH.dialogInfo(judul, T("pesan_tunggu", "Tunggu ") .. tostring(r.sisaDetik or 60) .. T("pesan_tunggu_detik", " detik sebelum mengirim pesan lagi."))
elseif r.status == "beda" then
JATAH.namaBeda(r, function() muatUlangBahasaDanMenu() end)
else
JATAH.dialogInfo(judul, T("pesan_gagal_kirim", "Pesan belum terkirim. Periksa koneksi internet lalu coba lagi."))
end
end)
end

-- Tombol "Pesan ke Developer" di menu utama
function JATAH.menuPesan()
if not JATAH.AKTIF then return end
if dapatkanString(JATAH.KUNCI_NAMA, "") == "" then
JATAH.mintaNama(function() JATAH.menuPesan() end, function() muatUlangBahasaDanMenu() end)
return
end
jalankanTaskLoading(T("pesan_memuat", "Memuat pesan..."), JATAH.kerja, cjson.encode(JATAH.argsDasar("pesan_lihat")), function(r)
local judul = T("pesan_ke_developer", "Pesan ke Developer")
if r.status == "beda" then
JATAH.namaBeda(r, function() muatUlangBahasaDanMenu() end)
return
end
if r.status ~= "ok" then
JATAH.dialogInfo(judul, T("pesan_gagal_muat", "Tidak bisa memuat pesan. Periksa koneksi internet lalu coba lagi."))
return
end
local teks
if r.pesan and r.pesan.teks then
teks = T("pesan_anda", "Pesan Anda:\n") .. r.pesan.teks .. "\n\n"
if r.balasan and r.balasan.teks then
teks = teks .. T("balasan_developer", "Balasan developer:\n") .. r.balasan.teks
else
teks = teks .. T("belum_ada_balasan", "Belum ada balasan.")
end
else
teks = T("belum_ada_pesan", "Anda belum mengirim pesan. Ceritakan bug atau masalah yang Anda temui, dan developer akan membalas di sini.")
end
local d = UI_Dialog(judul)
d.setMessage(teks)
d.setButton(T("tulis_pesan", "Tulis Pesan"), function()
JATAH.dialogTeks(T("tulis_pesan", "Tulis Pesan"), T("pesan_hint", "Jelaskan bug atau masalah Anda"), "",
function(isi) JATAH.pesanKirim(isi) end,
function() muatUlangBahasaDanMenu() end)
end)
d.setButton2(T("tutup", "Tutup"), function() muatUlangBahasaDanMenu() end)
d.setOnCancelListener(function() muatUlangBahasaDanMenu() end)
d.show()
end)
end

-- Jalankan aksi admin terhadap berkas satu pengguna (balas, ubah nama, hapus), lalu panggil setelah().
function JATAH.aksiAdmin(args, setelah)
args.token = dapatkanString("github_admin_token", "")
args.owner = JATAH.OWNER
args.repo = JATAH.REPO
jalankanTaskLoading("Memproses...", JATAH.kerja, cjson.encode(args), function(r)
if r.status == "ok" then
service.speak("Berhasil.")
else
service.speak("Gagal. Kode " .. tostring(r.kode or 0))
end
if setelah then setelah() end
end)
end

-- Pindahkan pengguna ke tingkat admin 1/2/3 (dicabut dulu dari tingkat lain). Disimpan ke database
-- admin lokal, sama seperti menu Kelola Admin.
function JATAH.jadikanAdmin(u, tingkat)
if ID_CREATORS[u.id] then
service.speak("Akses ditolak: Creator tidak boleh diubah.")
return
end
local kunci = { "admin_utama", "admin_kedua", "admin_ketiga" }
local tabel = { ADMIN_IDS, ADMIN_KEDUA_IDS, ADMIN_KETIGA_IDS }
for i = 1, 3 do
if DataAdminGlobal[kunci[i]] then DataAdminGlobal[kunci[i]][u.id] = nil end
tabel[i][u.id] = nil
end
DataAdminGlobal[kunci[tingkat]] = DataAdminGlobal[kunci[tingkat]] or {}
DataAdminGlobal[kunci[tingkat]][u.id] = tostring(u.nama)
tabel[tingkat][u.id] = true
simpanAdminJsonLokal(DataAdminGlobal)
service.speak(tostring(u.nama) .. " dijadikan Admin " .. tingkat .. ".")
end

-- Menu aksi untuk satu pengguna. Memakai pola UI_Dialog + setItems yang sama dengan Kelola Admin
-- supaya aksi ketuk-tahan otomatis muncul juga sebagai aksi aksesibilitas (AksiDex).
function JATAH.menuAksiPengguna(u, segarkan)
local opsi = {}
if u.pesan and u.pesan.teks then table.insert(opsi, "Balas Pesan") end
table.insert(opsi, "Ubah Nama")
table.insert(opsi, "Jadikan Admin 1")
table.insert(opsi, "Jadikan Admin 2")
table.insert(opsi, "Jadikan Admin 3")
table.insert(opsi, "Hapus")
table.insert(opsi, T("tutup", "Tutup"))
local dOpt = UI_Dialog(tostring(u.nama))
dOpt.setItems(opsi)
dOpt.setOnItemClickListener(function(ol, ov, op, oid)
local act = opsi[op + 1]
dOpt.dismiss()
if act == "Balas Pesan" then
JATAH.dialogTeks("Balas " .. tostring(u.nama), "Tulis balasan", "", function(isi)
JATAH.aksiAdmin({ aksi = "admin_balas", id = u.id, teks = isi }, segarkan)
end, nil)
elseif act == "Ubah Nama" then
showInputDialog("Ubah Nama", nil, tostring(u.nama), function(namaBaru)
if string.lower(namaBaru) == string.lower(tostring(u.nama)) then return end
JATAH.aksiAdmin({ aksi = "admin_ubah_nama", id = u.id, namaBaru = namaBaru }, segarkan)
end)
elseif act == "Jadikan Admin 1" or act == "Jadikan Admin 2" or act == "Jadikan Admin 3" then
local tingkat = tonumber(string.sub(act, -1))
showConfirmDialog(act, "Jadikan " .. tostring(u.nama) .. " sebagai Admin " .. tingkat .. "?", function()
JATAH.jadikanAdmin(u, tingkat)
end)
elseif act == "Hapus" then
showConfirmDialog("Hapus Pengguna", "Hapus " .. tostring(u.nama) .. " dari daftar pengguna? Dia bisa mendaftar ulang dengan nama baru.", function()
JATAH.aksiAdmin({ aksi = "admin_hapus", id = u.id }, segarkan)
end)
end
end)
dOpt.show()
end

function JATAH.detailPengguna(u, segarkan)
local teks = "Nama: " .. tostring(u.nama) .. "\nID: " .. tostring(u.id) .. "\nTerdaftar: " .. JATAH.tanggal(u.terdaftar) .. "\nKlaim terakhir: " .. JATAH.tanggal(u.klaim_terakhir)
if u.hadiah then teks = teks .. "\nHadiah terakhir: " .. JATAH.ringkasHadiah(u.hadiah) .. "\nBerakhir: " .. JATAH.tanggal(u.hadiah.selesai) end
if u.pesan and u.pesan.teks then
teks = teks .. "\n\nPesan (" .. JATAH.tanggal(u.pesan.waktu) .. "):\n" .. u.pesan.teks
if u.balasan and u.balasan.teks then
teks = teks .. "\n\nBalasan Anda (" .. JATAH.tanggal(u.balasan.waktu) .. "):\n" .. u.balasan.teks
else
teks = teks .. "\n\nBelum dibalas."
end
end
if type(u.riwayat) == "table" and #u.riwayat > 0 then
teks = teks .. "\n\nRiwayat klaim:"
for i = #u.riwayat, math.max(1, #u.riwayat - 9), -1 do
local rw = u.riwayat[i]
teks = teks .. "\n" .. JATAH.tanggal(rw.waktu) .. " - " .. JATAH.ringkasHadiah({ tipe = rw.tipe, fitur = rw.fitur, hari = rw.hari })
end
end
local dd = UI_Dialog("Informasi Pengguna")
dd.setMessage(teks)
dd.setButton("Tutup", function() end)
dd.setButton2("Aksi", function() JATAH.menuAksiPengguna(u, segarkan) end)
dd.show()
end

function JATAH.panelPengguna(paksa)
local tokenAdmin = dapatkanString("github_admin_token", "")
if tokenAdmin == "" then
service.speak("Token admin belum diisi.")
return
end
jalankanTaskLoading("Memuat daftar pengguna...", JATAH.kerjaDaftar, cjson.encode({ token = tokenAdmin, owner = JATAH.OWNER, repo = JATAH.REPO, paksa = paksa }), function(r)
if r.status ~= "ok" then
service.speak("Gagal memuat daftar pengguna. Kode " .. tostring(r.kode or 0) .. ". Pastikan token admin punya akses ke repo " .. JATAH.REPO .. ".")
return
end
local daftar = r.daftar or {}
local sekarang = tonumber(r.sekarang) or os.time()
table.sort(daftar, function(x, y)
if (x.pesan_baru and true or false) ~= (y.pesan_baru and true or false) then return x.pesan_baru and true or false end
local p, q = tonumber(x.klaim_terakhir) or 0, tonumber(y.klaim_terakhir) or 0
if p ~= q then return p > q end
return tostring(x.nama) < tostring(y.nama)
end)

local baris, aktifN, baruN = {}, 0, 0
for _, u in ipairs(daftar) do
local status
local kt = tonumber(u.klaim_terakhir)
if not kt then
status = "Belum pernah klaim"
else
status = "Klaim terakhir " .. math.floor((sekarang - kt) / 86400) .. " hari lalu"
local h = u.hadiah
if h and tonumber(h.selesai) and tonumber(h.selesai) > sekarang then
aktifN = aktifN + 1
status = status .. " | Hadiah AKTIF: " .. JATAH.ringkasHadiah(h)
end
local sisa = kt + JATAH.JEDA_HARI * 86400 - sekarang
if sisa > 0 then status = status .. " | Klaim lagi " .. JATAH.teksDurasi(sisa) else status = status .. " | Bisa klaim sekarang" end
end
local penanda = ""
if u.pesan_baru then penanda = "[Pesan baru] "; baruN = baruN + 1 end
table.insert(baris, penanda .. tostring(u.nama) .. " (" .. string.sub(tostring(u.id), -6) .. ") - " .. status)
end

local d = UI_Dialog("Kelola Pengguna")
local lay = UI_Layout(
UI_Teks(#daftar .. " pengguna terdaftar, " .. aktifN .. " sedang punya hadiah aktif, " .. baruN .. " pesan belum dibalas.\nKetuk: Informasi. Ketuk tahan: Balas, Ubah Nama, Jadikan Admin, Hapus.", true),
UI_Daftar("lvPengguna"),
UI_Tombol("btnSegarkanPengguna", "Segarkan"),
UI_Tombol("btnBangunUlangPengguna", "Bangun Ulang Indeks"),
UI_Tombol("btnTutupPengguna", "Tutup")
)
d.setView(loadlayout(lay))
if #baris == 0 then table.insert(baris, "Belum ada pengguna yang mendaftar.") end
lvPengguna.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, baris))

local function segarkan() d.dismiss(); JATAH.panelPengguna() end

lvPengguna.onItemClick = function(l, v, p, id)
local u = daftar[p + 1]
if u then JATAH.detailPengguna(u, segarkan) end
end
lvPengguna.onItemLongClick = function(l, v, p, id)
local u = daftar[p + 1]
if u then JATAH.menuAksiPengguna(u, segarkan) end
return true
end
AksiDex.pasang(lvPengguna, { labelKlik = "Buka Informasi" })
btnSegarkanPengguna.onClick = function() segarkan() end
btnBangunUlangPengguna.onClick = function()
showConfirmDialog("Bangun Ulang Indeks", "Baca ulang semua berkas pengguna dan bangun indeks dari awal? Ini lebih lama, tapi memperbaiki indeks yang tidak sesuai.", function()
d.dismiss()
JATAH.panelPengguna(true)
end)
end
btnTutupPengguna.onClick = function() d.dismiss() end
d.show()
end)
end

-- ==========================================================================
-- AKUN PRIVATE: tema suara private eksklusif
--   Admin Utama / Creator : langsung masuk (slot utama: tema_suara_private)
--   Admin 2 dan Admin 3   : wajib login akun tema admin, tiap akun punya slot sendiri
--                           tema_suara_private/<nama pengguna>
--   Pengguna free, hadiah Klaim Jatah, premium biasa : tidak bisa masuk sama sekali
-- Akun disimpan di repo data: private_akun/<nama pengguna>.json
-- Kata sandi TIDAK disimpan polos: PBKDF2 + garam acak. Pemulihan = admin utama membuat
-- kata sandi sementara baru (wajib diganti saat masuk), bukan melihat kata sandi lama.
-- ==========================================================================
AKUN = {
FOLDER = "private_akun",
SLOT_UTAMA = "tema_suara_admin", -- awalan folder di repo khusus (BEDA dari tema_suara_private lama)
-- Repo PRIVATE khusus Tema Admin (ubah di sini kalau nama repo di GitHub berbeda)
REPO_TEMA = "nandadian20083123/tema-suara-admin",
tokenTema = "", -- token repo itu untuk Admin 2/3, diterima setelah login (hanya di memori)
KUNCI_USER = "akun_private_terakhir", -- hanya nama pengguna, untuk isi otomatis kolom
sesi = nil                            -- nama pengguna yang sedang masuk (nil = admin utama)
}

-- "utama" = Admin Utama/Creator, "admin" = Admin 2/3 (wajib login), nil = tidak boleh
function AKUN.peran()
local id = DapatkanAndroidID()
if ADMIN_IDS[id] or ID_CREATORS[id] then return "utama" end
if ADMIN_KEDUA_IDS[id] or ADMIN_KETIGA_IDS[id] then return "admin" end
return nil
end

-- Token repo Tema Admin: Admin Utama pakai token admin, Admin 2/3 pakai token dari login
function AKUN.tokenPrivat()
local p = AKUN.peran()
if p == "utama" then return dapatkanString("github_admin_token", "") end
if p == "admin" then return AKUN.tokenTema or "" end
return ""
end

function AKUN.folderTema(u)
if u and u ~= "" then return AKUN.SLOT_UTAMA .. "/" .. u end
return AKUN.SLOT_UTAMA
end

-- Bagian jaringan + hash. Jalan di thread terpisah, jadi TIDAK boleh memakai variabel di luar fungsi ini.
AKUN.kerja = function(jsonArgs)
require "import"
local luajava = require("luajava")
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.net.URL"
import "java.lang.String"
local cjson = require "cjson"
local Base64 = luajava.bindClass("android.util.Base64")
local SecureRandom = luajava.bindClass("java.security.SecureRandom")
local PBEKeySpec = luajava.bindClass("javax.crypto.spec.PBEKeySpec")
local SKF = luajava.bindClass("javax.crypto.SecretKeyFactory")
local a = cjson.decode(jsonArgs)
local acak = SecureRandom()
local ITER = 20000
local MAKS_SALAH = 5
local KUNCI_DETIK = 900

local adaAdmin = string.sub(tostring(a.aksi), 1, 6) == "admin_"
if adaAdmin then
-- Aksi admin wajib memakai token admin, tidak boleh jatuh ke token komunitas
if (a.token or "") == "" then return cjson.encode({ status = "gagal", kode = -2 }) end
elseif (a.token or "") == "" then
local okT, dataToken = pcall(function()
local conn = URL("https://raw.githubusercontent.com/nandadian20083123/skrip-lua/main/token_komunitas.json").openConnection()
conn.setRequestProperty("Cache-Control", "no-cache")
conn.setConnectTimeout(5000)
conn.setReadTimeout(10000)
local br = BufferedReader(InputStreamReader(conn.getInputStream()))
local isi, baris = "", br.readLine()
while baris do isi = isi .. baris; baris = br.readLine() end
br.close()
return cjson.decode(isi)
end)
local tokenBaca = nil
if okT and type(dataToken) == "table" then
if dataToken.k then
local okD, hasilD = pcall(function()
local terbalik = tostring(String(Base64.decode(tostring(dataToken.k), 0), "UTF-8"))
return string.reverse(terbalik)
end)
if okD and type(hasilD) == "string" and hasilD ~= "" then tokenBaca = hasilD end
elseif dataToken.token_komunitas then
tokenBaca = dataToken.token_komunitas
end
end
if not tokenBaca then return cjson.encode({ status = "gagal", kode = -1 }) end
a.token = tokenBaca
end

local dasar = "https://api.github.com/repos/" .. a.owner .. "/" .. a.repo .. "/contents/"

local function pathAkun(u) return a.folder .. "/" .. u .. ".json" end

local function buka(url, metode)
local conn = URL(url).openConnection()
conn.setConnectTimeout(8000)
conn.setReadTimeout(15000)
conn.setRequestMethod(metode)
conn.setRequestProperty("Authorization", "token " .. a.token)
conn.setRequestProperty("Accept", "application/vnd.github.v3+json")
conn.setRequestProperty("Cache-Control", "no-cache")
return conn
end

local function bacaIsi(conn)
local br = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
local teks, baris = "", br.readLine()
while baris do teks = teks .. baris; baris = br.readLine() end
br.close()
return teks
end

-- Kembali: kode, data, sha, waktu server (dari header Date, bukan jam HP)
local function ambilPath(path)
local conn = buka(dasar .. path, "GET")
local code = conn.getResponseCode()
local dateMs = conn.getDate()
local sekarang = (dateMs and dateMs > 0) and math.floor(dateMs / 1000) or os.time()
if code ~= 200 then return code, nil, nil, sekarang end
local meta = cjson.decode(bacaIsi(conn))
local b64 = (string.gsub(meta.content or "", "%s", ""))
local mentah = tostring(String(Base64.decode(b64, Base64.DEFAULT), "UTF-8"))
local ok, data = pcall(function() return cjson.decode(mentah) end)
if not ok or type(data) ~= "table" then data = {} end
return 200, data, meta.sha, sekarang
end

local function kirimBody(conn, body)
conn.setRequestProperty("Content-Type", "application/json")
conn.setDoOutput(true)
local os2 = conn.getOutputStream()
os2.write(String(cjson.encode(body)).getBytes("UTF-8"))
os2.close()
return conn.getResponseCode()
end

local function tulisPath(path, data, sha, pesan)
local body = { message = pesan, content = Base64.encodeToString(String(cjson.encode(data)).getBytes("UTF-8"), Base64.NO_WRAP) }
if sha then body.sha = sha end
local code = kirimBody(buka(dasar .. path, "PUT"), body)
return (code == 200 or code == 201), code
end

local function acakHex(n)
local t = {}
for i = 1, n do t[i] = string.format("%02x", acak.nextInt(256)) end
return table.concat(t)
end

local function sandiAcak(n)
local abjad = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789"
local t = {}
for i = 1, n do
local k = acak.nextInt(#abjad) + 1
t[i] = string.sub(abjad, k, k)
end
return table.concat(t)
end

local function hashSandi(sandi, garam, iter)
local spec = PBEKeySpec(String(sandi).toCharArray(), String(garam).getBytes("UTF-8"), iter, 256)
local kunci = SKF.getInstance("PBKDF2WithHmacSHA1").generateSecret(spec).getEncoded()
local t = {}
for i = 0, #kunci - 1 do
local v = kunci[i]
if v < 0 then v = v + 256 end
t[#t + 1] = string.format("%02x", v)
end
return table.concat(t)
end

local function samaPersis(x, y)
x, y = tostring(x), tostring(y)
if #x ~= #y then return false end
local beda = 0
for i = 1, #x do
if string.byte(x, i) ~= string.byte(y, i) then beda = beda + 1 end
end
return beda == 0
end

local function namaSah(u)
u = tostring(u or "")
return #u >= 3 and #u <= 20 and string.match(u, "^[a-z0-9_]+$") ~= nil
end

local function angka(s) return (string.gsub(tostring(s or ""), "%D", "")) end

-- Salinan sandi untuk admin utama: dienkripsi RSA dengan KUNCI PUBLIK (kunci_publik.json di repo data).
-- Hanya kunci privat di HP admin utama yang bisa membukanya. Field garam/iter/hash TIDAK disentuh.
local function ambilKunciPublik()
local ok, hasil = pcall(function()
local c, d = ambilPath("kunci_publik.json")
if c == 200 and type(d) == "table" and type(d.pub) == "string" and d.pub ~= "" then return d.pub end
return nil
end)
if ok then return hasil end
return nil
end

local function enkripsiSandi(pub, sandi)
local ok, hasil = pcall(function()
local bytes = String(tostring(sandi)).getBytes("UTF-8")
if #bytes > 190 then return nil end -- batas RSA-2048 OAEP
local KF = luajava.bindClass("java.security.KeyFactory")
local X509 = luajava.bindClass("java.security.spec.X509EncodedKeySpec")
local Cipher = luajava.bindClass("javax.crypto.Cipher")
local kunci = KF.getInstance("RSA").generatePublic(X509(Base64.decode(pub, Base64.DEFAULT)))
local cph = Cipher.getInstance("RSA/ECB/OAEPWithSHA-1AndMGF1Padding")
cph.init(1, kunci)
return Base64.encodeToString(cph.doFinal(bytes), Base64.NO_WRAP)
end)
if ok then return hasil end
return nil
end

-- Periksa kata sandi + hitung percobaan salah (kunci 15 menit setelah 5 kali salah).
-- Mengembalikan "ok", "salah", atau "terkunci"; d diubah di tempat.
local function cobaSandi(d, now, sandi)
local sampai = tonumber(d.kunci_sampai)
if sampai and now < sampai then return "terkunci", sampai - now end
if samaPersis(hashSandi(sandi, d.garam or "", tonumber(d.iter) or ITER), d.hash or "") then
d.gagal = 0
d.kunci_sampai = nil
return "ok"
end
d.gagal = (tonumber(d.gagal) or 0) + 1
if d.gagal >= MAKS_SALAH then
d.gagal = 0
d.kunci_sampai = now + KUNCI_DETIK
return "terkunci", KUNCI_DETIK
end
return "salah", MAKS_SALAH - d.gagal
end

-- Baca-ubah-tulis dengan pengulangan kalau bentrok (409/422). fungsi(d, now) boleh
-- mengembalikan tabel untuk membatalkan penulisan dan langsung menjadi hasil.
local function ubahAkun(u, fungsi, pesan)
for i = 1, 3 do
local c, d, s, now = ambilPath(pathAkun(u))
if c == 404 then return { status = "tidakada" } end
if c ~= 200 then return { status = "gagal", kode = c } end
local batal = fungsi(d, now)
if type(batal) == "table" then
-- tetap simpan hitungan percobaan salah kalau ada perubahan
if batal.simpan then tulisPath(pathAkun(u), d, s, pesan) end
batal.simpan = nil
return batal
end
local ok, k = tulisPath(pathAkun(u), d, s, pesan)
if ok then return { status = "ok" } end
if k ~= 409 and k ~= 422 then return { status = "gagal", kode = k } end
end
return { status = "gagal", kode = 409 }
end

local okP, hasil = pcall(function()
local aksi = a.aksi

if aksi == "daftar" then
if not namaSah(a.u) then return { status = "nama_salah" } end
local sandi = tostring(a.sandi or "")
if #sandi < 8 or #sandi > 64 then return { status = "sandi_salah" } end
local hp = angka(a.hp)
if #hp < 10 or #hp > 15 then return { status = "hp_salah" } end
local c, _, _, now = ambilPath(pathAkun(a.u))
if c == 200 then return { status = "ada" } end
if c ~= 404 then return { status = "gagal", kode = c } end
local garam = acakHex(16)
local pubD = ambilKunciPublik()
local encD = pubD and enkripsiSandi(pubD, sandi) or nil
local data = { u = a.u, hp = hp, garam = garam, iter = ITER, hash = hashSandi(sandi, garam, ITER), id = a.id, dibuat = now, gagal = 0, sandi_enc = encD }
local ok, k = tulisPath(pathAkun(a.u), data, nil, "Daftar akun tema admin: " .. a.u)
if ok then return { status = "ok" } end
if k == 422 or k == 409 then return { status = "ada" } end
return { status = "gagal", kode = k }

elseif aksi == "masuk" then
if not namaSah(a.u) then return { status = "salah" } end
local c, d, s, now = ambilPath(pathAkun(a.u))
if c == 404 then return { status = "salah" } end -- sengaja sama dengan sandi salah
if c ~= 200 then return { status = "gagal", kode = c } end
local sebelum = (tonumber(d.gagal) or 0) > 0 or d.kunci_sampai ~= nil
local hasilCoba, info = cobaSandi(d, now, tostring(a.sandi or ""))
-- simpan hitungan percobaan hanya kalau berubah (gagal menyimpan tidak membatalkan hasil)
if hasilCoba == "salah" or (hasilCoba == "ok" and sebelum) or (hasilCoba == "terkunci" and info == KUNCI_DETIK) then
pcall(function() tulisPath(pathAkun(a.u), d, s, "Percobaan masuk: " .. a.u) end)
end
if hasilCoba == "ok" then
-- token repo Tema Admin diberikan hanya setelah sandi benar
local tokenTema = ""
local c2, d2 = ambilPath("pengaturan_private.json")
if c2 == 200 and type(d2) == "table" then tokenTema = tostring(d2.token or "") end
-- akun lama: isi salinan sandi terenkripsi saat login benar (bukan sandi sementara). Gagal = tidak masalah.
if not d.wajib_ganti and (type(d.sandi_enc) ~= "string" or d.sandi_enc == "") then
pcall(function()
local pubM = ambilKunciPublik()
local encM = pubM and enkripsiSandi(pubM, tostring(a.sandi or "")) or nil
if encM then
local c3, d3, s3 = ambilPath(pathAkun(a.u)) -- ambil ulang supaya sha terbaru
if c3 == 200 and type(d3) == "table" and (type(d3.sandi_enc) ~= "string" or d3.sandi_enc == "") then
d3.sandi_enc = encM
tulisPath(pathAkun(a.u), d3, s3, "Simpan salinan sandi: " .. a.u)
end
end
end)
end
return { status = "ok", wajib_ganti = d.wajib_ganti and true or false, tokenTema = tokenTema }
end
if hasilCoba == "terkunci" then return { status = "terkunci", sisaDetik = info } end
return { status = "salah", sisa = info }

elseif aksi == "ganti_sandi" then
if not namaSah(a.u) then return { status = "salah" } end
local baru = tostring(a.sandiBaru or "")
if #baru < 8 or #baru > 64 then return { status = "sandi_salah" } end
local pubG = ambilKunciPublik()
local encBaru = pubG and enkripsiSandi(pubG, baru) or nil
return ubahAkun(a.u, function(d, now)
local hasilCoba, info = cobaSandi(d, now, tostring(a.sandiLama or ""))
if hasilCoba == "terkunci" then return { status = "terkunci", sisaDetik = info, simpan = (info == KUNCI_DETIK) } end
if hasilCoba ~= "ok" then return { status = "salah", sisa = info, simpan = true } end
local garam = acakHex(16)
d.garam = garam
d.iter = ITER
d.hash = hashSandi(baru, garam, ITER)
d.sandi_enc = encBaru -- salinan lama otomatis usang, diganti yang baru (nil kalau kunci belum ada)
d.wajib_ganti = nil
d.minta_pulih = nil
end, "Ganti kata sandi: " .. a.u)

elseif aksi == "minta_pulih" then
if not namaSah(a.u) then return { status = "tidakada" } end
local hp = angka(a.hp)
return ubahAkun(a.u, function(d, now)
if hp == "" or hp ~= tostring(d.hp) then return { status = "tidakcocok" } end
local t = tonumber(d.minta_pulih)
if t and now - t < 600 then return { status = "ok" } end -- jangan menumpuk permintaan
d.minta_pulih = now
end, "Minta pulihkan kata sandi: " .. a.u)

elseif aksi == "admin_daftar" then
local conn = buka(dasar .. a.folder, "GET")
local code = conn.getResponseCode()
if code == 404 then return { status = "ok", daftar = {} } end
if code ~= 200 then return { status = "gagal", kode = code } end
local berkas = cjson.decode(bacaIsi(conn))
local daftar = {}
for _, f in ipairs(berkas) do
if f.type == "file" and string.match(tostring(f.name), "%.json$") then
local c, d = ambilPath(a.folder .. "/" .. f.name)
if c == 200 then
table.insert(daftar, { u = d.u, hp = d.hp, minta = d.minta_pulih, wajib = d.wajib_ganti and true or false, ada = (type(d.sandi_enc) == "string" and d.sandi_enc ~= "") })
end
end
end
return { status = "ok", daftar = daftar }

elseif aksi == "admin_pulihkan" then
if not namaSah(a.u) then return { status = "gagal", kode = 0 } end
local sementara = sandiAcak(10)
local hpTujuan = nil
local r = ubahAkun(a.u, function(d, now)
local garam = acakHex(16)
d.garam = garam
d.iter = ITER
d.hash = hashSandi(sementara, garam, ITER)
d.sandi_enc = nil
d.wajib_ganti = true
d.minta_pulih = nil
d.gagal = 0
d.kunci_sampai = nil
hpTujuan = d.hp
end, "Pulihkan akun: " .. a.u)
if r.status == "ok" then r.sementara = sementara; r.hp = hpTujuan end
return r

elseif aksi == "admin_buat_kunci" then
local c, d, sh = ambilPath("kunci_publik.json")
if c ~= 200 and c ~= 404 then return { status = "gagal", kode = c } end
if c == 200 and type(d) == "table" and d.pub and not a.paksa then return { status = "sudah_ada" } end
local KPG = luajava.bindClass("java.security.KeyPairGenerator")
local gen = KPG.getInstance("RSA")
gen.initialize(2048)
local pasang = gen.generateKeyPair()
local pub = Base64.encodeToString(pasang.getPublic().getEncoded(), Base64.NO_WRAP)
local priv = Base64.encodeToString(pasang.getPrivate().getEncoded(), Base64.NO_WRAP)
local ok, k = tulisPath("kunci_publik.json", { pub = pub }, (c == 200) and sh or nil, "Atur kunci publik sandi")
if ok then return { status = "ok", privat = priv } end
return { status = "gagal", kode = k }

elseif aksi == "admin_sandi" then
if not namaSah(a.u) then return { status = "gagal", kode = 0 } end
local c, d = ambilPath(pathAkun(a.u))
if c ~= 200 or type(d) ~= "table" then return { status = "gagal", kode = c } end
if type(d.sandi_enc) ~= "string" or d.sandi_enc == "" then return { status = "belum" } end
local okD, sandi = pcall(function()
local KF = luajava.bindClass("java.security.KeyFactory")
local PKCS8 = luajava.bindClass("java.security.spec.PKCS8EncodedKeySpec")
local Cipher = luajava.bindClass("javax.crypto.Cipher")
local kunci = KF.getInstance("RSA").generatePrivate(PKCS8(Base64.decode(tostring(a.kunciPrivat or ""), Base64.DEFAULT)))
local cph = Cipher.getInstance("RSA/ECB/OAEPWithSHA-1AndMGF1Padding")
cph.init(2, kunci)
return tostring(String(cph.doFinal(Base64.decode(d.sandi_enc, Base64.DEFAULT)), "UTF-8"))
end)
if okD and sandi ~= "" then return { status = "ok", sandi = sandi, hp = d.hp } end
return { status = "kunci_salah" }

elseif aksi == "admin_set_token" then
local c, _, sh, now = ambilPath("pengaturan_private.json")
if c ~= 200 and c ~= 404 then return { status = "gagal", kode = c } end
local ok, k = tulisPath("pengaturan_private.json", { token = tostring(a.tokenTema or ""), diubah = now }, sh, "Atur token repo tema admin")
if ok then return { status = "ok" } end
return { status = "gagal", kode = k }

elseif aksi == "admin_hapus" then
if not namaSah(a.u) then return { status = "gagal", kode = 0 } end
local c, d, s = ambilPath(pathAkun(a.u))
if c ~= 200 then return { status = "gagal", kode = c } end
local code = kirimBody(buka(dasar .. pathAkun(a.u), "DELETE"), { message = "Hapus akun tema admin: " .. a.u, sha = s })
if code == 200 then return { status = "ok" } end
return { status = "gagal", kode = code }
end

return { status = "gagal", kode = 0 }
end)
a.token = ""
if not okP then return cjson.encode({ status = "gagal", kode = 0, galat = tostring(hasil) }) end
return cjson.encode(hasil)
end

-- ===== Sisi aplikasi (dialog) =====
function AKUN.panggil(aksi, tambahan, onHasil)
local args = { aksi = aksi, token = "", owner = JATAH.OWNER, repo = JATAH.REPO, folder = AKUN.FOLDER }
for k, v in pairs(tambahan or {}) do args[k] = v end
jalankanTaskLoading(T("akun_memproses", "Memproses..."), AKUN.kerja, cjson.encode(args), onHasil)
end

-- Nomor ke format internasional: 08xx -> 628xx, 8xx -> 628xx
function AKUN.normalHp(s)
local d = string.gsub(tostring(s or ""), "%D", "")
if string.sub(d, 1, 1) == "0" then d = "62" .. string.sub(d, 2)
elseif string.sub(d, 1, 1) == "8" then d = "62" .. d end
return d
end

function AKUN.potong(s) return tostring(s or ""):match("^%s*(.-)%s*$") or "" end

-- Pintu masuk tema admin. onSukses(namaPengguna atau nil), onBatal() kalau ditolak / dibatalkan.
function AKUN.gerbang(onSukses, onBatal)
local peran = AKUN.peran()
if peran == "utama" then
AKUN.sesi = nil
onSukses(nil)
return
end
if peran ~= "admin" then
AKUN.sesi = nil
service.speak(T("akun_ditolak", "Maaf, tema admin hanya untuk admin."))
if onBatal then onBatal() end
return
end
AKUN.dialogMasuk(onSukses, onBatal)
end

function AKUN.dialogMasuk(onSukses, onBatal)
local d = UI_Dialog(T("akun_judul_masuk", "Masuk Tema Admin"))
local lay = UI_Layout(
UI_Teks(T("akun_info_masuk", "Tema private khusus admin. Masukkan nama pengguna dan kata sandi akun tema admin Anda.")),
{EditText, id = "etAkunNama", layout_width = "fill", hint = T("akun_hint_nama", "Nama pengguna"), singleLine = true},
{EditText, id = "etAkunSandi", layout_width = "fill", hint = T("akun_hint_sandi", "Kata sandi"), singleLine = true},
UI_Tombol("btnAkunMasuk", T("akun_masuk", "Masuk")),
UI_Tombol("btnAkunDaftar", T("akun_daftar", "Daftar Akun Baru")),
UI_Tombol("btnAkunLupa", T("akun_lupa", "Lupa Kata Sandi")),
UI_Tombol("btnAkunGanti", T("akun_ganti", "Ganti Kata Sandi")),
UI_Tombol("btnAkunKembali", T("kembali", "Kembali"))
)
local sv = ScrollView(service)
sv.addView(loadlayout(lay))
d.setView(sv)
etAkunSandi.setInputType(129) -- teks + kata sandi (disamarkan)
etAkunNama.setText(dapatkanString(AKUN.KUNCI_USER, ""))

local function batal() d.dismiss(); if onBatal then onBatal() end end
local function ulang() AKUN.dialogMasuk(onSukses, onBatal) end

local function ambilIsian()
local u = string.lower(AKUN.potong(etAkunNama.getText()))
local sandi = tostring(etAkunSandi.getText())
if u == "" or sandi == "" then
service.speak(T("akun_isi_semua", "Isi semua kolom dulu."))
return nil
end
return u, sandi
end

local function pesanGagal(r)
if r.status == "terkunci" then
service.speak(T("akun_terkunci", "Terlalu banyak percobaan salah. Coba lagi dalam ") .. math.ceil((tonumber(r.sisaDetik) or 900) / 60) .. T("akun_menit", " menit."))
elseif r.status == "salah" then
service.speak(T("akun_salah", "Nama pengguna atau kata sandi salah."))
else
service.speak(T("akun_gagal", "Gagal terhubung. Periksa internet lalu coba lagi."))
end
end

btnAkunMasuk.onClick = function()
local u, sandi = ambilIsian()
if not u then return end
AKUN.panggil("masuk", { u = u, sandi = sandi }, function(r)
if r.status ~= "ok" then
pesanGagal(r)
return
end
simpanString(AKUN.KUNCI_USER, u)
d.dismiss()
local function selesai()
AKUN.sesi = u
AKUN.tokenTema = r.tokenTema or ""
onSukses(u)
end
if r.wajib_ganti then
AKUN.dialogGanti(u, sandi, true, selesai, onBatal)
else
selesai()
end
end)
end

btnAkunDaftar.onClick = function() d.dismiss(); AKUN.dialogDaftar(ulang) end
btnAkunLupa.onClick = function() d.dismiss(); AKUN.dialogLupa(ulang) end
btnAkunGanti.onClick = function()
local u, sandi = ambilIsian()
if not u then return end
d.dismiss()
AKUN.dialogGanti(u, sandi, false, ulang, ulang)
end
btnAkunKembali.onClick = function() batal() end
d.setOnCancelListener(function() if onBatal then onBatal() end end)
d.show()
end

function AKUN.dialogDaftar(kembali)
local d = UI_Dialog(T("akun_judul_daftar", "Daftar Akun Tema Admin"))
local lay = UI_Layout(
UI_Teks(T("akun_nama_aturan", "Nama pengguna 3 sampai 20 karakter: huruf kecil, angka, atau garis bawah.")),
{EditText, id = "etDaftarNama", layout_width = "fill", hint = T("akun_hint_nama", "Nama pengguna"), singleLine = true},
{EditText, id = "etDaftarSandi", layout_width = "fill", hint = T("akun_hint_sandi", "Kata sandi"), singleLine = true},
{EditText, id = "etDaftarSandi2", layout_width = "fill", hint = T("akun_hint_sandi2", "Ulangi kata sandi"), singleLine = true},
{EditText, id = "etDaftarHp", layout_width = "fill", hint = T("akun_hint_hp", "Nomor telepon WhatsApp"), singleLine = true},
UI_Tombol("btnDaftarSimpan", T("akun_simpan", "Simpan")),
UI_Tombol("btnDaftarBatal", T("batal", "Batal"))
)
local sv = ScrollView(service)
sv.addView(loadlayout(lay))
d.setView(sv)
etDaftarSandi.setInputType(129)
etDaftarSandi2.setInputType(129)
etDaftarHp.setInputType(3) -- papan angka telepon

btnDaftarSimpan.onClick = function()
local u = string.lower(AKUN.potong(etDaftarNama.getText()))
local s1 = tostring(etDaftarSandi.getText())
local s2 = tostring(etDaftarSandi2.getText())
local hp = AKUN.normalHp(etDaftarHp.getText())
if #u < 3 or #u > 20 or not string.match(u, "^[a-z0-9_]+$") then
service.speak(T("akun_nama_aturan", "Nama pengguna 3 sampai 20 karakter: huruf kecil, angka, atau garis bawah."))
return
end
if #s1 < 8 then service.speak(T("akun_sandi_aturan", "Kata sandi minimal 8 karakter.")) return end
if s1 ~= s2 then service.speak(T("akun_sandi_beda", "Kata sandi dan ulangannya tidak sama.")) return end
if #hp < 10 or #hp > 15 then service.speak(T("akun_hp_aturan", "Nomor telepon tidak valid.")) return end
AKUN.panggil("daftar", { u = u, sandi = s1, hp = hp, id = DapatkanAndroidID_Asli() }, function(r)
if r.status == "ok" then
simpanString(AKUN.KUNCI_USER, u)
d.dismiss()
service.speak(T("akun_dibuat", "Akun dibuat. Silakan masuk."))
kembali()
elseif r.status == "ada" then
service.speak(T("akun_nama_dipakai", "Nama pengguna sudah dipakai. Pilih yang lain."))
else
service.speak(T("akun_gagal", "Gagal terhubung. Periksa internet lalu coba lagi."))
end
end)
end
btnDaftarBatal.onClick = function() d.dismiss(); kembali() end
d.setOnCancelListener(function() kembali() end)
d.show()
end

function AKUN.dialogLupa(kembali)
local d = UI_Dialog(T("akun_judul_lupa", "Lupa Kata Sandi"))
local lay = UI_Layout(
{EditText, id = "etLupaNama", layout_width = "fill", hint = T("akun_hint_nama", "Nama pengguna"), singleLine = true},
{EditText, id = "etLupaHp", layout_width = "fill", hint = T("akun_hint_hp", "Nomor telepon WhatsApp"), singleLine = true},
UI_Tombol("btnLupaKirim", T("akun_kirim_minta", "Kirim Permintaan")),
UI_Tombol("btnLupaBatal", T("batal", "Batal"))
)
d.setView(loadlayout(lay))
etLupaNama.setText(dapatkanString(AKUN.KUNCI_USER, ""))
etLupaHp.setInputType(3)
btnLupaKirim.onClick = function()
local u = string.lower(AKUN.potong(etLupaNama.getText()))
local hp = AKUN.normalHp(etLupaHp.getText())
if u == "" or hp == "" then service.speak(T("akun_isi_semua", "Isi semua kolom dulu.")) return end
AKUN.panggil("minta_pulih", { u = u, hp = hp }, function(r)
if r.status == "gagal" or r.status == nil then
service.speak(T("akun_gagal", "Gagal terhubung. Periksa internet lalu coba lagi."))
return
end
-- Jawaban sama untuk semua kasus agar nama pengguna tidak bisa ditebak
d.dismiss()
local dInfo = UI_Dialog(T("akun_judul_lupa", "Lupa Kata Sandi"))
dInfo.setMessage(T("akun_minta_terkirim", "Jika nama pengguna dan nomor telepon cocok, permintaan sudah dikirim ke admin utama. Admin akan menghubungi Anda lewat WhatsApp."))
dInfo.setButton(T("ok", "OK"), function() kembali() end)
dInfo.setOnCancelListener(function() kembali() end)
dInfo.show()
end)
end
btnLupaBatal.onClick = function() d.dismiss(); kembali() end
d.setOnCancelListener(function() kembali() end)
d.show()
end

-- wajib = true: setelah memakai kata sandi sementara, tidak bisa ditutup tanpa membuat yang baru
function AKUN.dialogGanti(u, sandiLama, wajib, onSelesai, onBatal)
local d = UI_Dialog(T("akun_judul_ganti", "Buat Kata Sandi Baru"))
local lay = UI_Layout(
UI_Teks(wajib and T("akun_info_wajib_ganti", "Anda masuk dengan kata sandi sementara. Buat kata sandi baru dulu.") or T("akun_sandi_aturan", "Kata sandi minimal 8 karakter.")),
{EditText, id = "etGantiBaru", layout_width = "fill", hint = T("akun_hint_sandi_baru", "Kata sandi baru"), singleLine = true},
{EditText, id = "etGantiBaru2", layout_width = "fill", hint = T("akun_hint_sandi2", "Ulangi kata sandi"), singleLine = true},
UI_Tombol("btnGantiSimpan", T("akun_simpan", "Simpan")),
UI_Tombol("btnGantiBatal", T("batal", "Batal"))
)
d.setView(loadlayout(lay))
etGantiBaru.setInputType(129)
etGantiBaru2.setInputType(129)
if wajib then d.setCancelable(false) end
btnGantiSimpan.onClick = function()
local s1 = tostring(etGantiBaru.getText())
local s2 = tostring(etGantiBaru2.getText())
if #s1 < 8 then service.speak(T("akun_sandi_aturan", "Kata sandi minimal 8 karakter.")) return end
if s1 ~= s2 then service.speak(T("akun_sandi_beda", "Kata sandi dan ulangannya tidak sama.")) return end
AKUN.panggil("ganti_sandi", { u = u, sandiLama = sandiLama, sandiBaru = s1 }, function(r)
if r.status == "ok" then
d.dismiss()
service.speak(T("akun_sandi_diganti", "Kata sandi diganti."))
if onSelesai then onSelesai() end
elseif r.status == "salah" then
service.speak(T("akun_salah", "Nama pengguna atau kata sandi salah."))
elseif r.status == "terkunci" then
service.speak(T("akun_terkunci", "Terlalu banyak percobaan salah. Coba lagi dalam ") .. math.ceil((tonumber(r.sisaDetik) or 900) / 60) .. T("akun_menit", " menit."))
else
service.speak(T("akun_gagal", "Gagal terhubung. Periksa internet lalu coba lagi."))
end
end)
end
btnGantiBatal.onClick = function() d.dismiss(); if onBatal then onBatal() end end
d.setOnCancelListener(function() if not wajib and onBatal then onBatal() end end)
d.show()
end

-- ===== Panel Admin Utama: daftar akun, permintaan pemulihan, hapus akun =====
function AKUN.tutupSemua()
for _, dlg in ipairs({ AKUN.dPanel, AKUN.dAdmin, dialogUtama }) do
if dlg then pcall(function() dlg.dismiss() end) end
end
end

-- Buka WhatsApp ke nomor tujuan dengan pesan terisi (tinggal tekan kirim)
function AKUN.kirimWA(hp, teks)
local uri = Uri.parse("https://wa.me/" .. tostring(hp) .. "?text=" .. Uri.encode(teks))
local intent = Intent(Intent.ACTION_VIEW, uri)
intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
pcall(function() service.startActivity(intent) end)
end

function AKUN.panelAdmin()
local tokenAdmin = dapatkanString("github_admin_token", "")
if tokenAdmin == "" then
service.speak("Token admin belum diisi.")
return
end
AKUN.panggil("admin_daftar", { token = tokenAdmin }, function(r)
if r.status ~= "ok" then
service.speak("Gagal memuat akun tema admin. Kode " .. tostring(r.kode or 0) .. ". Pastikan token admin punya akses ke repo " .. JATAH.REPO .. ".")
return
end
local daftar = r.daftar or {}
table.sort(daftar, function(x, y)
local p, q = x.minta and true or false, y.minta and true or false
if p ~= q then return p end
return tostring(x.u) < tostring(y.u)
end)
local baris, mintaN = {}, 0
for _, x in ipairs(daftar) do
local tanda = ""
if x.minta then tanda = "[Minta pulihkan kata sandi]\n"; mintaN = mintaN + 1 end
-- nama pengguna dan nomor telepon dipisah jelas, masing-masing di baris sendiri dengan labelnya
table.insert(baris, tanda .. "Nama pengguna: " .. tostring(x.u) .. "\nNomor telepon: " .. tostring(x.hp) .. "\nSandi tersimpan: " .. (x.ada and "ya" or "belum"))
end
local d = UI_Dialog("Akun Tema Admin")
AKUN.dPanel = d
local lay = UI_Layout(
UI_Teks(#daftar .. " akun terdaftar, " .. mintaN .. " minta pemulihan kata sandi.\nKetuk: buat kata sandi sementara dan kirim lewat WhatsApp. Ketuk tahan: hapus akun.", true),
UI_Daftar("lvAkunPrivate"),
UI_Tombol("btnTokenPrivat", "Atur Token Repo Tema Admin"),
UI_Tombol("btnBuatKunci", "Buat Kunci Sandi"),
UI_Tombol("btnSalinKunci", "Salin Kunci Cadangan"),
UI_Tombol("btnSegarkanAkun", "Segarkan"),
UI_Tombol("btnTutupAkun", "Tutup")
)
d.setView(loadlayout(lay))
if #baris == 0 then table.insert(baris, "Belum ada akun tema admin yang terdaftar.") end
lvAkunPrivate.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, baris))
local function segarkan() d.dismiss(); AKUN.panelAdmin() end

lvAkunPrivate.onItemClick = function(l, v, p, id)
local x = daftar[p + 1]
if not x then return end
local function pulihkanSementara()
showConfirmDialog("Pulihkan Kata Sandi", "Buat kata sandi sementara untuk " .. tostring(x.u) .. " dan kirim ke " .. tostring(x.hp) .. " lewat WhatsApp?", function()
AKUN.panggil("admin_pulihkan", { token = tokenAdmin, u = x.u }, function(h)
if h.status == "ok" then
AKUN.tutupSemua() -- semua dialog ditutup supaya WhatsApp langsung terlihat
AKUN.kirimWA(h.hp or x.hp, "Halo, ini kata sandi sementara akun Tema Admin Anda.\nNama pengguna: " .. tostring(x.u) .. "\nKata sandi sementara: " .. tostring(h.sementara) .. "\nSetelah masuk, Anda akan diminta membuat kata sandi baru.")
else
service.speak("Gagal memulihkan. " .. tostring(h.status) .. " " .. tostring(h.kode or ""))
end
end)
end)
end
local kunciPrivat = dapatkanString("akun_kunci_privat", "")
if x.ada and kunciPrivat ~= "" then
-- salinan sandi ada: kirim sandi yang mereka pakai sendiri (hash akun tidak diubah)
showConfirmDialog("Kirim Kata Sandi", "Kirim kata sandi akun " .. tostring(x.u) .. " ke " .. tostring(x.hp) .. " lewat WhatsApp?", function()
AKUN.panggil("admin_sandi", { token = tokenAdmin, u = x.u, kunciPrivat = kunciPrivat }, function(h)
if h.status == "ok" then
AKUN.tutupSemua()
AKUN.kirimWA(h.hp or x.hp, "Halo, ini kata sandi akun Tema Admin Anda.\nNama pengguna: " .. tostring(x.u) .. "\nKata sandi: " .. tostring(h.sandi))
elseif h.status == "kunci_salah" then
service.speak("Kunci di HP ini tidak cocok dengan salinan sandi akun itu.")
else
service.speak("Gagal mengambil sandi. " .. tostring(h.status) .. " " .. tostring(h.kode or ""))
end
end)
end)
else
pulihkanSementara()
end
end
lvAkunPrivate.onItemLongClick = function(l, v, p, id)
local x = daftar[p + 1]
if not x then return true end
showConfirmDialog("Hapus Akun", "Hapus akun tema admin " .. tostring(x.u) .. "? Tema di slotnya tidak ikut terhapus.", function()
AKUN.panggil("admin_hapus", { token = tokenAdmin, u = x.u }, function(h)
service.speak(h.status == "ok" and "Akun dihapus." or ("Gagal menghapus. Kode " .. tostring(h.kode or 0)))
segarkan()
end)
end)
return true
end
if AksiDex and AksiDex.pasang then pcall(function() AksiDex.pasang(lvAkunPrivate, { labelKlik = "Pulihkan Kata Sandi" }) end) end
btnSegarkanAkun.onClick = function() segarkan() end
btnTokenPrivat.onClick = function()
showInputDialog("Token Repo Tema Admin", "Tempel token (akses hanya ke repo " .. AKUN.REPO_TEMA .. ")", "", function(txt)
txt = AKUN.potong(txt)
if #txt < 20 then
service.speak("Token terlalu pendek.")
return false
end
AKUN.panggil("admin_set_token", { token = tokenAdmin, tokenTema = txt }, function(h)
service.speak(h.status == "ok" and "Token repo tema admin disimpan." or ("Gagal menyimpan. Kode " .. tostring(h.kode or 0)))
end)
end, function() end, true)
end
local function buatKunci(paksa)
AKUN.panggil("admin_buat_kunci", { token = tokenAdmin, paksa = paksa }, function(h)
if h.status == "ok" then
simpanString("akun_kunci_privat", h.privat)
service.speak("Kunci sandi dibuat dan disimpan di HP ini. Salin kunci cadangan lalu simpan di tempat aman.")
segarkan()
elseif h.status == "sudah_ada" then
showConfirmDialog("Kunci Sudah Ada", "Kunci publik sudah ada di server. Kalau kunci privat di HP ini hilang, buat ulang. Salinan sandi lama tidak terbaca sampai tiap admin masuk lagi. Buat ulang sekarang?", function() buatKunci(true) end)
else
service.speak("Gagal membuat kunci. Kode " .. tostring(h.kode or 0))
end
end)
end
btnBuatKunci.onClick = function()
if dapatkanString("akun_kunci_privat", "") ~= "" then
service.speak("Kunci sudah ada di HP ini.")
return
end
buatKunci(false)
end
btnSalinKunci.onClick = function()
local kp = dapatkanString("akun_kunci_privat", "")
if kp == "" then service.speak("Belum ada kunci di HP ini."); return end
local cm = service.getSystemService(Context.CLIPBOARD_SERVICE)
cm.setPrimaryClip(ClipData.newPlainText("KunciSandi", kp))
service.speak("Kunci cadangan disalin. Simpan di tempat aman lalu kosongkan papan klip.")
end
btnTutupAkun.onClick = function() d.dismiss() end
d.show()
end)
end

-- ===== START =====
cleanSpkTrash()
NadiMulai = { sudah = false }
NadiMulai.jalan = function()
if NadiMulai.sudah then return end
NadiMulai.sudah = true
Pembaruan.baselineDiam()
PengecekModeAdmin()
uiHandler.postDelayed(Runnable({ run = function() JATAH.saatMulai() end }), 1500)
end
-- Tunggu daftar admin/ampunan dari server (maksimal 6 detik), baru cek akses
SedotDatabaseAdminGaib(function() NadiMulai.jalan() end)
uiHandler.postDelayed(Runnable({ run = function() NadiMulai.jalan() end }), 6000)
