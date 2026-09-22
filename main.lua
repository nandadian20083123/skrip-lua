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
["a4d22753d28a9086"] = "Nanda",
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
if entry.isDirectory() then
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
local d = LuaDialog(service)
if judul then d.setTitle(judul) end
return d
end

local folderJieshuo = string.char(232, 167, 163, 232, 175, 180)
local jieshuoPath = "/storage/emulated/0/" .. folderJieshuo
local folderSuara = dapatkanString("nama_folder_suara", "Suara")
local basePath = jieshuoPath .. "/" .. folderSuara
local backupPath = "/storage/emulated/0/.cadangan"

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

local uiHandler = Handler(Looper.getMainLooper())

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

local function CekKuotaFreemium(onDiizinkan)
local myId = DapatkanAndroidID()
if ADMIN_IDS[myId] or ADMIN_KEDUA_IDS[myId] or ADMIN_KETIGA_IDS[myId] then onDiizinkan() return end
local prefs = PreferenceManager.getDefaultSharedPreferences(service)
local tanggalSekarang = os.date("%Y-%m-%d")
local tanggalTersimpan = prefs.getString("freemium_date", "")
local jumlahPakai = prefs.getInt("freemium_count", 0)
if tanggalSekarang ~= tanggalTersimpan then
jumlahPakai = 0
prefs.edit().putString("freemium_date", tanggalSekarang).putInt("freemium_count", 0).apply()
end
if jumlahPakai >= 3 then
local dLimit = UI_Dialog(T("jatah_habis", "Batas Harian Tercapai"))
dLimit.setMessage(T("jatah_3_dari_3", "Anda telah menggunakan jatah sebanyak tiga dari tiga. Limit Anda untuk perintah tersebut telah selesai untuk hari ini. Kembali lagi untuk hari esok atau berlangganan ke premium."))
dLimit.setButton(T("tombol_oke", "Oke"), function() dLimit.dismiss() end)
dLimit.show()
else onDiizinkan() end
end

local function CatatPemakaianFreemium()
local myId = DapatkanAndroidID()
if ADMIN_IDS[myId] or ADMIN_KEDUA_IDS[myId] or ADMIN_KETIGA_IDS[myId] then return end
local prefs = PreferenceManager.getDefaultSharedPreferences(service)
local jatahSekarang = prefs.getInt("freemium_count", 0) + 1
prefs.edit().putInt("freemium_count", jatahSekarang).apply()
local dInfo = UI_Dialog(T("informasi", "Informasi"))
if jatahSekarang == 1 then dInfo.setMessage(T("jatah_1_dari_3", "Anda telah menggunakan jatah sebanyak satu dari tiga."))
elseif jatahSekarang == 2 then dInfo.setMessage(T("jatah_2_dari_3", "Anda telah menggunakan jatah sebanyak dua dari tiga."))
else dInfo.setMessage(T("jatah_3_dari_3", "Anda telah menggunakan jatah sebanyak tiga dari tiga. Limit Anda untuk perintah tersebut telah selesai untuk hari ini. Kembali lagi untuk hari esok atau berlangganan ke premium.")) end
dInfo.setButton(T("tombol_oke", "Oke"), function() dInfo.dismiss() end)
dInfo.setCancelable(false)
dInfo.show()
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
Thread(Runnable({
run = function()
local dir = File(jieshuoPath)
if dir.exists() and dir.isDirectory() then
local files = dir.listFiles()
if files then
for i = 0, #files - 1 do
local f = files[i]
if f.isFile() and string.match(string.lower(f.getName()), "%.spk$") then f.delete() end
end
end
end
end
})).start()
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

local function prosesAntreanImporAudio(queue, index, themeName, overrideAction, importedNames, onComplete)
if index > #queue then
onComplete(importedNames)
return
end

local srcFile = File(queue[index])
local targetName = srcFile.getName()
local targetFile = File(basePath .. "/" .. themeName .. "/" .. targetName)

local function eksekusiTindakan(action, newOverride)
jalankanDenganLoading(nil, function()
if action == "timpa" then
SalinFile(srcFile.getAbsolutePath(), targetFile.getAbsolutePath())
table.insert(importedNames, targetName)
elseif action == "ganti_nama" then
local safeName = DapatkanNamaUnik(basePath .. "/" .. themeName, targetName)
SalinFile(srcFile.getAbsolutePath(), basePath .. "/" .. themeName .. "/" .. safeName)
table.insert(importedNames, safeName)
end
end, function()
prosesAntreanImporAudio(queue, index + 1, themeName, newOverride, importedNames, onComplete)
end)
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
jalankanDenganLoading(nil, function()
if action == "timpa" then
if targetFolder.exists() then deleteRecursive(targetFolder) end
targetFolder.mkdirs()
EkstrakSPK(spkFile.getAbsolutePath(), targetFolder.getAbsolutePath())
rapikanFolderStruktur(targetFolder.getAbsolutePath())
table.insert(importedThemes, rawName)
elseif action == "ganti_nama" then
local safeName = DapatkanNamaUnik(basePath, rawName)
local newFolder = File(basePath .. "/" .. safeName)
newFolder.mkdirs()
EkstrakSPK(spkFile.getAbsolutePath(), newFolder.getAbsolutePath())
rapikanFolderStruktur(newFolder.getAbsolutePath())
table.insert(importedThemes, safeName)
end
end, function()
prosesAntreanSPK(queue, index + 1, newOverride, importedThemes, onComplete)
end)
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
jalankanDenganLoading(nil, function()
targetAudioFile.renameTo(targetBaru)
end, function()
refreshAudioListUI()
end)
return true
end
end
return true
end)
elseif action == T("hapus", "Hapus") then
showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("hapus", "Hapus") .. " " .. selectedAudioName .. "?", function()
jalankanDenganLoading(nil, function()
targetAudioFile.delete()
end, function()
refreshAudioListUI()
end)
end)
end
end)
optDialog.show()
return true
end

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

prosesAntreanBagikan = function()
local is_sharing = pref.getBoolean("is_sharing_massal", false)
if not is_sharing then return false end
local queueStr = pref.getString("share_queue", "[]")
local queue = {}
pcall(function() queue = cjson.decode(queueStr) end)
local curr_index = pref.getInt("share_index", 1)
if curr_index <= #queue then
local selectedTheme = queue[curr_index]
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

local zipFilePath = jieshuoPath .. "/" .. selectedTheme .. middleFmt .. suffixExt .. ".spk"
if targetFolder.exists() then
service.speak(T("membagikan", "Membagikan tema ") .. curr_index .. " " .. T("dari", "dari") .. " " .. #queue .. ": " .. selectedTheme)
jalankanDenganLoading(T("membagikan", "Membagikan tema ") .. selectedTheme, function()
local fos = FileOutputStream(zipFilePath)
local zos = ZipOutputStream(fos)
local files = targetFolder.listFiles()
local buffer = byte[8192]
if files then
for i = 0, #files - 1 do
ZipRekursif(files[i], files[i].getName(), zos, buffer)
end
end
zos.close()
fos.close()
end, function()
editor.putInt("share_index", curr_index + 1)
editor.commit()
pcall(function() service.shareFile(zipFilePath) end)
end)
else
editor.putInt("share_index", curr_index + 1)
editor.commit()
prosesAntreanBagikan()
end
else
cleanSpkTrash()
editor.putBoolean("is_sharing_massal", false)
editor.commit()
service.speak(T("antrean_selesai", "Semua tema selesai dibagikan."))
end
return true
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
if ADMIN_IDS[myId] or ADMIN_KEDUA_IDS[myId] or ADMIN_KETIGA_IDS[myId] then
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
if onComplete then onComplete() end
end)
else
local dPremium = UI_Dialog(T("informasi", "Informasi"))
dPremium.setMessage(T("info_pulih_premium", "Pemulihan otomatis tema terhapus hanya untuk pengguna premium. Silakan masuk ke menu pencadangan, atau gunakan mod premium."))
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

local function getThemeData()
local pinnedList = {}
local normalList = {}
for i = 1, #filteredList do
local fName = filteredList[i]
local itemData = {
cbItem = {visibility = isSelectionModeEdit and 0 or 8, checked = selectedThemes[fName] == true},
realName = fName
}
if isInList("pinned_themes", fName) then
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
selectedThemes[themeData[i].tvName] = true
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
table.insert(options, T("tutup", "Tutup"))
local optDialog = UI_Dialog(T("aksi_massal", "Aksi Lainnya...") .. " (" .. #toProcess .. ")")
optDialog.setItems(options)
optDialog.setOnItemClickListener(function(al, av, ap, ai)
local action = options[ap + 1]

-- GERBANG PREMIUM: Tahan eksekusi sebelum dialog ditutup!
if action == T("nama_tanpa_format", "Nama Event Tanpa Format") or action == T("nama_dengan_format", "Nama Event Dengan Format") then
local myId = DapatkanAndroidID()
if not ADMIN_IDS[myId] and not ADMIN_KEDUA_IDS[myId] and not ADMIN_KETIGA_IDS[myId] then
service.speak(T("fitur_premium", "Maaf, fitur ini khusus untuk pengguna Premium."))
return -- Hentikan kode di sini, dialog akan tetap terbuka!
end
end

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
editor.putBoolean("is_sharing_massal", true)
editor.putString("share_queue", cjson.encode(toProcess))
editor.putInt("share_index", 1)
editor.commit()
prosesAntreanBagikan()
elseif action == T("cadangkan_spk", "Cadangkan Jadi SPK") then
mainDialog.dismiss()
jalankanDenganLoading("Mencadangkan " .. #toProcess .. " tema ke SPK...", function()
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
local fos = FileOutputStream(zipFilePath)
local zos = ZipOutputStream(fos)
local files = targetFolder.listFiles()
local buffer = byte[8192]
if files then
for i = 0, #files - 1 do ZipRekursif(files[i], files[i].getName(), zos, buffer) end
end
zos.close()
fos.close()
end
end, function() service.speak("Semua tema berhasil dicadangkan ke SPK."); tampilkanMenuEdit() end)
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
CekKuotaFreemium(function()
jalankanDenganLoading(nil, function()
for pt=1, #toProcess do HelperHilangkanFormat(toProcess[pt]) end
end, function() tampilkanMenuEdit(); CatatPemakaianFreemium() end)
end)
elseif action == T("nama_tanpa_format", "Nama Event Tanpa Format") or action == T("nama_dengan_format", "Nama Event Dengan Format") then
local myId = DapatkanAndroidID()
if not ADMIN_IDS[myId] and not ADMIN_KEDUA_IDS[myId] and not ADMIN_KETIGA_IDS[myId] then
service.speak(T("fitur_premium", "Maaf, fitur ini khusus untuk pengguna Premium."))
return
end
mainDialog.dismiss()
local withFormat = (action == T("nama_dengan_format", "Nama Event Dengan Format"))
jalankanDenganLoading(nil, function()
for pt=1, #toProcess do HelperNamaEventFormat(toProcess[pt], withFormat) end
end, function() tampilkanMenuEdit() end)
elseif action == T("hapus_tak_terdaftar", "Hapus Audio Tak Terdaftar") then
CekKuotaFreemium(function()
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
jalankanDenganLoading(nil, function()
for i = 1, #allTrash do
local fToDelete = File(allTrash[i])
if fToDelete.exists() then fToDelete.delete() end
end
end, function()
tampilkanMenuEdit()
CatatPemakaianFreemium()
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
jalankanDenganLoading(nil, function()
for i=1, #toDelete do
local f = File(basePath .. "/" .. toDelete[i])
if f.exists() then deleteRecursive(f) end
local fc = File(backupPath .. "/" .. toDelete[i])
if fc.exists() then deleteRecursive(fc) end
end
end, function()
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
local statusCad = cekStatusCadangan(selectedTheme)

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
table.insert(options, T("tutup", "Tutup"))
local optDialog = UI_Dialog(selectedTheme)
optDialog.setItems(options)
optDialog.setOnItemClickListener(function(al, av, ap, ai)
local action = options[ap + 1]

-- GERBANG PREMIUM: Tahan eksekusi sebelum dialog ditutup!
if action == T("nama_tanpa_format", "Nama Event Tanpa Format") or action == T("nama_dengan_format", "Nama Event Dengan Format") then
local myId = DapatkanAndroidID()
if not ADMIN_IDS[myId] and not ADMIN_KEDUA_IDS[myId] and not ADMIN_KETIGA_IDS[myId] then
service.speak(T("fitur_premium", "Maaf, fitur ini khusus untuk pengguna Premium."))
return -- Hentikan kode di sini, dialog akan tetap terbuka!
end
end

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
jalankanDenganLoading(nil, function()
targetFolder.renameTo(cekDir)
if cadF.exists() then cadF.renameTo(File(backupPath .. "/" .. newName)) end
updateNameInPref("pinned_themes", selectedTheme, newName)
updateNameInPref("favorite_themes", selectedTheme, newName)
end, function()
refreshData(tostring(searchBarEdit.getText()))
end)
return true
end
end
return true
end)
elseif action == T("cadangkan", "Cadangkan") or action == T("cadangkan_ulang", "Cadangkan Ulang") then
jalankanDenganLoading(nil, function()
File(backupPath).mkdirs()
if cadF.exists() then deleteRecursive(cadF) end
cadF.mkdirs()
local files = targetFolder.listFiles()
if files then for i=0, #files-1 do SalinFile(files[i].getAbsolutePath(), cadF.getAbsolutePath() .. "/" .. files[i].getName()) end end
end, function() end)
elseif action == T("hapus_cadangan", "Hapus dari Cadangan") then
jalankanDenganLoading(nil, function()
if cadF.exists() then deleteRecursive(cadF) end
end, function() end)
elseif action == txtSemat then
toggleListPref("pinned_themes", selectedTheme)
refreshData(tostring(searchBarEdit.getText()))
elseif action == txtFav then
toggleListPref("favorite_themes", selectedTheme)
refreshData(tostring(searchBarEdit.getText()))
elseif action == T("hapus", "Hapus") then
showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("hapus", "Hapus") .. " " .. selectedTheme .. "?", function()
jalankanDenganLoading(nil, function()
deleteRecursive(targetFolder)
if cadF.exists() then deleteRecursive(cadF) end
end, function()
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
jalankanDenganLoading(nil, function()
local fos = FileOutputStream(zipFilePath)
local zos = ZipOutputStream(fos)
local files = targetFolder.listFiles()
local buffer = byte[8192]
if files then
for i = 0, #files - 1 do
ZipRekursif(files[i], files[i].getName(), zos, buffer)
end
end
zos.close()
fos.close()
end, function()
pcall(function() service.shareFile(zipFilePath) end)
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
jalankanDenganLoading(T("sedang_memproses", "Sedang memproses..."), function()
local fos = FileOutputStream(zipFilePath)
local zos = ZipOutputStream(fos)
local files = targetFolder.listFiles()
local buffer = byte[8192]
if files then
for i = 0, #files - 1 do ZipRekursif(files[i], files[i].getName(), zos, buffer) end
end
zos.close()
fos.close()
end, function()
service.speak("Berhasil dicadangkan ke " .. finalSpkName)
tampilkanMenuEdit()
end)
elseif action == T("hilangkan_format", "Hilangkan Format Audio") then
mainDialog.dismiss()
CekKuotaFreemium(function()
jalankanDenganLoading(nil, function()
HelperHilangkanFormat(selectedTheme)
end, function() showEventList(selectedTheme); CatatPemakaianFreemium() end)
end)
elseif action == T("nama_tanpa_format", "Nama Event Tanpa Format") or action == T("nama_dengan_format", "Nama Event Dengan Format") then
local myId = DapatkanAndroidID()
if not ADMIN_IDS[myId] and not ADMIN_KEDUA_IDS[myId] and not ADMIN_KETIGA_IDS[myId] then
service.speak(T("fitur_premium", "Maaf, fitur ini khusus untuk pengguna Premium."))
return
end
mainDialog.dismiss()
local withFormat = (action == T("nama_dengan_format", "Nama Event Dengan Format"))
jalankanDenganLoading(nil, function()
HelperNamaEventFormat(selectedTheme, withFormat)
end, function() showEventList(selectedTheme) end)
elseif action == T("hapus_tak_terdaftar", "Hapus Audio Tak Terdaftar") then
CekKuotaFreemium(function()
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
jalankanDenganLoading(nil, function()
for i = 1, #trashFiles do
local fToDelete = File(trashFiles[i])
if fToDelete.exists() then fToDelete.delete() end
end
end, function() CatatPemakaianFreemium() end)
end)
end
end)
end)
end
end)
optDialog.show()
return true
end

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

local function showHelperPanelKompresi(judul, teksSimpan, defFmt, defSr, defBr, onSimpan, onBatal)
local dKonv = UI_Dialog(judul)
local layKonv = UI_Layout(
UI_Teks(T("pilih_format", "Pilih Format:")), {Spinner, id="spFormat"},
UI_Teks(T("pilih_sample_rate", "Pilih Sample Rate:")), {Spinner, id="spSR"},
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

local sData = ArrayList()
sData.add(T("otomatis_bawaan", "Otomatis (Bawaan WAV)"))
sData.add("8000 Hz")
sData.add("16000 Hz")
sData.add("22050 Hz")
sData.add("44100 Hz")
sData.add("48000 Hz")
spSR.setAdapter(ArrayAdapter(service, android.R.layout.simple_spinner_item, sData))
if defSr == 8000 then spSR.setSelection(1) elseif defSr == 16000 then spSR.setSelection(2) elseif defSr == 22050 then spSR.setSelection(3) elseif defSr == 44100 then spSR.setSelection(4) elseif defSr == 48000 then spSR.setSelection(5) else spSR.setSelection(0) end

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
local sSelStr = tostring(spSR.getSelectedItem())
local srTarget = 0
if sSelStr == "8000 Hz" then srTarget = 8000 elseif sSelStr == "16000 Hz" then srTarget = 16000 elseif sSelStr == "22050 Hz" then srTarget = 22050 elseif sSelStr == "44100 Hz" then srTarget = 44100 elseif sSelStr == "48000 Hz" then srTarget = 48000 end
local bSelStr = tostring(spBR.getSelectedItem())
local brTarget = 128000
if bSelStr == "32 kbps" then brTarget = 32000 elseif bSelStr == "64 kbps" then brTarget = 64000 elseif bSelStr == "128 kbps" then brTarget = 128000 elseif bSelStr == "192 kbps" then brTarget = 192000 elseif bSelStr == "256 kbps" then brTarget = 256000 end
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

if selectedId == "suara" then
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
local svSr = pref.getInt("auto_comp_sr", 44100)
local svBr = pref.getInt("auto_comp_br", 128000)
showHelperPanelKompresi(T("menu_autocomp_set", "Pengaturan Konversi Audio"), T("simpan", "Simpan"), svFmt, svSr, svBr, function(fSel, srTarget, brTarget)
editor.putString("auto_comp_format", fSel)
editor.putInt("auto_comp_sr", srTarget)
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
T("dapur_menit", "Format Teks Menit")
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

local function HelperGunakanDemo()
hentikanAudioGlobal()
local folderDemo = File(basePath .. "/[Tema Demo]")
jalankanDenganLoading(nil, function()
if folderDemo.exists() then deleteRecursive(folderDemo) end
folderDemo.mkdirs()
local configAsli = {}
local dData = bacaJson(BASE .. "draft_demo.json")
for k, pathLengkap in pairs(dData) do
local fAsal = File(pathLengkap)
if fAsal.exists() then
local namaFile = DapatkanNamaUnik(folderDemo.getAbsolutePath(), fAsal.getName())
SalinFile(pathLengkap, folderDemo.getAbsolutePath() .. "/" .. namaFile)
configAsli[k] = namaFile
end
end
simpanJson(folderDemo.getAbsolutePath() .. "/config", configAsli)
end, function()
PreferenceManager.getDefaultSharedPreferences(service).edit().putString("sound_package", "[Tema Demo]").apply()

service.loadSoundPackage("[Tema Demo]")
service.speak(T("demo_aktif", "Tema Demo aktif!"))
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
jalankanDenganLoading(nil, function()
folderBaru.mkdirs()
local configAsli = {}
for k, pathLengkap in pairs(dData) do
local fAsal = File(pathLengkap)
if fAsal.exists() then
local namaFile = DapatkanNamaUnik(folderBaru.getAbsolutePath(), fAsal.getName())
SalinFile(pathLengkap, folderBaru.getAbsolutePath() .. "/" .. namaFile)
configAsli[k] = namaFile
end
end
simpanJson(folderBaru.getAbsolutePath() .. "/config", configAsli)
end, function()
PreferenceManager.getDefaultSharedPreferences(service).edit().putString("sound_package", namaBaru).apply()
service.loadSoundPackage(namaBaru)
service.speak(T("demo_tersimpan", "Berhasil disimpan sebagai tema ") .. namaBaru)

Thread(Runnable({
run = function()
local folderDemo = File(basePath .. "/[Tema Demo]")
if folderDemo.exists() then deleteRecursive(folderDemo) end
File(BASE .. "draft_demo.json").delete()
end
})).start()

if dialogToDismiss then dialogToDismiss.dismiss() end
muatUlangBahasaDanMenu()
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
jalankanDenganLoading(nil, function()
if folderDemo.exists() then deleteRecursive(folderDemo) end
local fDraft = File(BASE .. "draft_demo.json")
if fDraft.exists() then fDraft.delete() end
end, function()
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
jalankanDenganLoading(nil, function()
File(backupPath).mkdirs()
for i=1,#diproses do
local src = File(basePath.."/"..diproses[i])
local dst = File(backupPath.."/"..diproses[i])
if dst.exists() then deleteRecursive(dst) end
dst.mkdirs()
local f = src.listFiles()
if f then for j=0,#f-1 do SalinFile(f[j].getAbsolutePath(), dst.getAbsolutePath().."/"..f[j].getName()) end end
end
end, function() tampilkanMenuPencadangan() end)
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
jalankanDenganLoading(nil, function()
for i=1,#diproses do
local src = File(backupPath.."/"..diproses[i])
local dst = File(basePath.."/"..diproses[i])
if dst.exists() then deleteRecursive(dst) end
dst.mkdirs()
local f = src.listFiles()
if f then for j=0,#f-1 do SalinFile(f[j].getAbsolutePath(), dst.getAbsolutePath().."/"..f[j].getName()) end end
end
end, function() tampilkanMenuPencadangan() end)
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
jalankanDenganLoading(nil, function()
local src = File(basePath.."/"..item)
local dst = File(backupPath.."/"..item)
if dst.exists() then deleteRecursive(dst) end
dst.mkdirs()
local f = src.listFiles()
if f then for j=0,#f-1 do SalinFile(f[j].getAbsolutePath(), dst.getAbsolutePath().."/"..f[j].getName()) end end
end, function()
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
jalankanDenganLoading(nil, function()
for k=0, listModif.size()-1 do
local item = tostring(listModif.get(k))
local src = File(basePath.."/"..item)
local dst = File(backupPath.."/"..item)
if dst.exists() then deleteRecursive(dst) end
dst.mkdirs()
local f = src.listFiles()
if f then for j=0,#f-1 do SalinFile(f[j].getAbsolutePath(), dst.getAbsolutePath().."/"..f[j].getName()) end end
end
end, function() tampilkanMenuPencadangan() end)
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
jalankanDenganLoading(nil, function()
local targetDir = File(basePath .. "/" .. temaTujuan .. "/effect")
if not targetDir.exists() then targetDir.mkdirs() end
SalinFile(srcFile.getAbsolutePath(), targetDir.getAbsolutePath() .. "/" .. namaBaruFinal)
end, function()
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

jalankanDenganLoading(T("memuat_file", "Memuat daftar folder..."), function()
local tempItems = {}
local d = File(currentPath)
if d.exists() and d.isDirectory() then
local files = d.listFiles()
if files then
for i = 0, #files - 1 do
local f = files[i]
if f.isDirectory() and not string.match(f.getName(), "^%.") then
-- Gunakan fungsi validasi ketat yang baru
local isT = apakahFolderTema(f)
table.insert(tempItems, {name = f.getName(), path = f.getAbsolutePath(), isTheme = isT})
end
end
end
end
table.sort(tempItems, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
return tempItems
end, function(res)
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
jalankanDenganLoading(nil, function()
local targetDir = File(basePath .. "/" .. item._name)
if not targetDir.exists() then targetDir.mkdirs() end
local srcDir = File(item._path)
local files = srcDir.listFiles()
if files then
for i=0, #files-1 do
SalinFile(files[i].getAbsolutePath(), targetDir.getAbsolutePath() .. "/" .. files[i].getName())
end
end
end, function() service.speak(T("sukses", "Berhasil diimpor!")) end)
end)

dImpor.setButton2(T("impor_terapkan", "Impor & Terapkan"), function()
jalankanDenganLoading(nil, function()
local targetDir = File(basePath .. "/" .. item._name)
if not targetDir.exists() then targetDir.mkdirs() end
local srcDir = File(item._path)
local files = srcDir.listFiles()
if files then
for i=0, #files-1 do
SalinFile(files[i].getAbsolutePath(), targetDir.getAbsolutePath() .. "/" .. files[i].getName())
end
end
end, function()
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
jalankanDenganLoading(T("membagikan", "Mengekspor tema..."), function()
local zipFilePath = currentPath .. "/" .. item._name .. ".spk"
local fos = FileOutputStream(zipFilePath)
local zos = ZipOutputStream(fos)
local srcDir = File(item._path)
local files = srcDir.listFiles()
local buffer = byte[8192]
if files then
for i = 0, #files - 1 do
ZipRekursif(files[i], files[i].getName(), zos, buffer)
end
end
zos.close()
fos.close()
return zipFilePath
end, function(zipPath)
pcall(function() service.shareFile(zipPath) end)
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

jalankanDenganLoading(T("sedang_memproses", "Sedang memproses..."), function()
local fos = FileOutputStream(zipFilePath)
local zos = ZipOutputStream(fos)
local files = srcFolder.listFiles()
local buffer = byte[8192]
if files then
for i = 0, #files - 1 do ZipRekursif(files[i], files[i].getName(), zos, buffer) end
end
zos.close()
fos.close()
end, function()
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
File(item._path).renameTo(targetBaru)
loadDir(currentPath)
return true
end
end
return true
end)

elseif action == T("hapus", "Hapus") then
showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("hapus", "Hapus") .. " " .. item._name .. "?", function()
jalankanDenganLoading(nil, function() deleteRecursive(File(item._path)) end, function() loadDir(currentPath) end)
end)
end
end)
optDialog.show()
return true
end

btnEksporEks.onClick = function()
local toProcess = {}
for k, v in pairs(selectedItems) do table.insert(toProcess, k) end

dialogEks.dismiss()
jalankanDenganLoading("Mengekspor " .. #toProcess .. " tema...", function()
for i = 1, #toProcess do
local srcFolder = File(toProcess[i])
local zipFilePath = currentPath .. "/" .. srcFolder.getName() .. ".spk"
local fos = FileOutputStream(zipFilePath)
local zos = ZipOutputStream(fos)
local files = srcFolder.listFiles()
local buffer = byte[8192]
if files then
for j = 0, #files - 1 do
ZipRekursif(files[j], files[j].getName(), zos, buffer)
end
end
zos.close()
fos.close()
end
end, function()
service.speak("Berhasil diekspor menjadi SPK di folder ini.")
muatUlangBahasaDanMenu()
end)
end

btnCadangSpkEks.onClick = function()
local toProcess = {}
for k, v in pairs(selectedItems) do table.insert(toProcess, k) end

dialogEks.dismiss()
jalankanDenganLoading("Mencadangkan " .. #toProcess .. " tema ke SPK...", function()
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
local fos = FileOutputStream(zipFilePath)
local zos = ZipOutputStream(fos)
local files = srcFolder.listFiles()
local buffer = byte[8192]
if files then
for j = 0, #files - 1 do ZipRekursif(files[j], files[j].getName(), zos, buffer) end
end
zos.close()
fos.close()
end
end, function()
service.speak("Semua tema berhasil dicadangkan ke SPK.")
muatUlangBahasaDanMenu()
end)
end

btnHapusEks.onClick = function()
local toProcess = {}
for k, v in pairs(selectedItems) do table.insert(toProcess, k) end

showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("hapus", "Hapus") .. " " .. #toProcess .. " tema?", function()
jalankanDenganLoading(nil, function()
for i=1, #toProcess do deleteRecursive(File(toProcess[i])) end
end, function()
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

muatUlangBahasaDanMenu = function()
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
UI_Tombol("btnDemoUtama", T("buat_demo", "Buat Tema Suara Demo")),
UI_Tombol("btnDemoInstanUtama", T("buat_demo_instan", "Buat Demo Instan")),
UI_Tombol("btnImporSPKUtama", T("impor_spk", "Impor File SPK")),
UI_Tombol("btnEksternalUtama", T("kelola_tema_eksternal", "Manajer Tema Eksternal")),
UI_Tombol("btnDaftarKode", T("daftar_kode_suara", "Daftar Kode Suara Tema")),
UI_Tombol("btnPencadanganUtama", T("menu_pencadangan", "Menu Pencadangan")),
UI_Tombol("btnPanduanUtama", T("panduan_tombol", "Panduan Penggunaan")),
UI_Tombol("btnPremiumUtama", T("menu_premium", "Tingkatkan ke Premium")),
UI_Tombol("btnTentangUtama", T("tentang", "Tentang")),
{LinearLayout, orientation="horizontal", layout_width="fill",
ADMIN_IDS[DapatkanAndroidID()] and UI_Tombol_H("btnAdminUtama", "Mode Admin") or {LinearLayout, visibility=8},
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
simpanJson(draftPath, initData)
eksekusiJamManual(false)
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
end

local chunks = BuatAntreanTeksJam(temaTujuan, komponenDipilih, formatDipilih, false)

loopRekaman = function(idx)
if idx > #chunks then
local jamAsli = File(basePath .. "/" .. temaTujuan .. "/clock")
if jamAsli.exists() then deleteRecursive(jamAsli) end
jamAsli.mkdirs()

local function pindahIsi(srcStr, dstStr)
local src = File(srcStr)
local dst = File(dstStr)
if not dst.exists() then dst.mkdirs() end
local files = src.listFiles()
if files then
for i=0, #files-1 do
SalinFile(files[i].getAbsolutePath(), dst.getAbsolutePath() .. "/" .. files[i].getName())
end
end
end

pindahIsi(tempJamPath .. "/hour", jamAsli.getAbsolutePath() .. "/hour")
pindahIsi(tempJamPath .. "/minute", jamAsli.getAbsolutePath() .. "/minute")
if File(tempJamPath .. "/hourly").exists() then pindahIsi(tempJamPath .. "/hourly", jamAsli.getAbsolutePath() .. "/hourly") end

deleteRecursive(File(tempJamPath))
File(draftPath).delete()

service.speak(T("jam_berhasil", "Jam bicara berhasil ditambahkan ke tema!"))
muatUlangBahasaDanMenu()
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
muatUlangBahasaDanMenu()
end

dRekam.setOnCancelListener(function() tutupDanBatal() end)

local function playHitungMundur()
local myId = DapatkanAndroidID()
if ADMIN_IDS[myId] or ADMIN_KEDUA_IDS[myId] or ADMIN_KETIGA_IDS[myId] then
-- Kasta Premium: Ada panduan hitung mundur 1, 2, 3 yang nyaman
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
-- Kasta Gratisan: Bisu total. Hanya dikasih jeda 1 detik lalu disuruh baca sendiri.
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

local myId = DapatkanAndroidID()
local param = {[TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID] = "instruksi"}

if ADMIN_IDS[myId] or ADMIN_KEDUA_IDS[myId] or ADMIN_KETIGA_IDS[myId] then
-- Kasta Premium: Dibisikin instruksi lengkap
local instruksiFinal = T("instruksi_rekam", "Oke, saatnya mengatakan: ") .. item.text
pcall(function() ttsMaker.speak(instruksiFinal, TextToSpeech.QUEUE_FLUSH, param) end)
else
-- Kasta Gratisan: Iklan Premium
local instruksiFree = T("instruksi_rekam_free", "Panduan suara adalah fitur premium. Silakan baca teks di layar.")
pcall(function() ttsMaker.speak(instruksiFree, TextToSpeech.QUEUE_FLUSH, param) end)
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
pcall(function() if mp then mp.stop(); mp.release() end end)
File(tempWav).delete()
dPrev.dismiss()
muatUlangBahasaDanMenu()
end

btnBatalP.onClick = function()
pcall(function() if mp then mp.stop(); mp.release() end end)
showConfirmDialog(T("konfirmasi", "Konfirmasi"), T("batalkan_semua_teks", "Hapus semua rekaman yang baru dibuat dan mulai dari nol?"), function()
File(draftPath).delete()
deleteRecursive(File(tempJamPath))
File(tempWav).delete()
dPrev.dismiss()
muatUlangBahasaDanMenu()
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
local clockPath = basePath .. "/" .. temaTujuan .. "/clock"
local targetDir = File(clockPath)

jalankanDenganLoading(T("mohon_tunggu", "Menyiapkan folder jam..."), function()
if targetDir.exists() then deleteRecursive(targetDir) end
targetDir.mkdirs()
File(clockPath .. "/hour").mkdirs()
File(clockPath .. "/minute").mkdirs()
if komponenDipilih == 2 then File(clockPath .. "/hourly").mkdirs() end
end,
function()
local dLoading = UI_Dialog(T("mohon_tunggu", "Mohon Tunggu"))
dLoading.setMessage(T("proses_jam", "Sedang memproses rekaman jam (WAV)..."))
dLoading.setCancelable(false)
dLoading.show()

local engine = pref.getString("tts_engine", "")
local voiceName = pref.getString("tts_voice", "")
local pitch = pref.getFloat("tts_pitch", 1.0)
local rate = pref.getFloat("tts_rate", 1.0)

local chunks = BuatAntreanTeksJam(temaTujuan, komponenDipilih, formatDipilih, true)

local function kompresiWav(wavPath, formatStr, sr, br)
local isOgg = (formatStr == "OGG")
local ext = isOgg and ".ogg" or ".m4a"
local outPath = string.gsub(wavPath, "%.wav$", ext)
local wavFile = File(wavPath)
if not wavFile.exists() or wavFile.length() < 44 then return false end

local encoder, muxer, raf
local muxerStarted = false
local encodeOk, errMsg = pcall(function()
raf = luajava.bindClass("java.io.RandomAccessFile")(wavFile, "r")
raf.seek(24)
local function readUnsigned(r)
local b = tonumber(r.readByte())
if b < 0 then b = b + 256 end
return b
end
local b1 = readUnsigned(raf)
local b2 = readUnsigned(raf)
local b3 = readUnsigned(raf)
local b4 = readUnsigned(raf)
local originSr = b1 + (b2 * 256) + (b3 * 65536) + (b4 * 16777216)
raf.seek(44)

local outFile = File(outPath)
if outFile.exists() then outFile.delete() end

local MediaMuxer = luajava.bindClass("android.media.MediaMuxer")
local MediaFormat = luajava.bindClass("android.media.MediaFormat")
local MediaCodec = luajava.bindClass("android.media.MediaCodec")

local muxerFormat = isOgg and 4 or 0
muxer = MediaMuxer(outPath, muxerFormat)

local targetSr = sr
if targetSr == 0 then targetSr = originSr end

local mimeType = isOgg and "audio/opus" or "audio/mp4a-latm"
local audioFormat = MediaFormat.createAudioFormat(mimeType, targetSr, 1)
if not isOgg then
audioFormat.setInteger(MediaFormat.KEY_AAC_PROFILE, 2)
end
audioFormat.setInteger(MediaFormat.KEY_BIT_RATE, br)
audioFormat.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 65536)

encoder = MediaCodec.createEncoderByType(mimeType)
encoder.configure(audioFormat, nil, nil, 1)
encoder.start()

local bufferInfo = luajava.bindClass("android.media.MediaCodec$BufferInfo")()
local trackIndex = -1
local isEOS = false
local pts = 0
local pcmBuf = luajava.bindClass("java.lang.reflect.Array").newInstance(luajava.bindClass("java.lang.Byte").TYPE, 65536)

while not isEOS do
pcall(function() java.lang.Thread.sleep(5) end)
local inIndex = tonumber(encoder.dequeueInputBuffer(8000))
if inIndex >= 0 then
local inBuf = encoder.getInputBuffer(inIndex)
inBuf.clear()

local capacity = tonumber(inBuf.capacity())
if capacity > 65536 then capacity = 65536 end

local readBytes = tonumber(raf.read(pcmBuf, 0, capacity))
if readBytes <= 0 then
encoder.queueInputBuffer(inIndex, 0, 0, pts, 4)
isEOS = true
else
inBuf.put(pcmBuf, 0, readBytes)
encoder.queueInputBuffer(inIndex, 0, readBytes, pts, 0)
local sampleCount = readBytes / 2
pts = pts + math.floor((sampleCount * 1000000) / originSr)
end
end

local outIndex = tonumber(encoder.dequeueOutputBuffer(bufferInfo, 8000))
while outIndex >= 0 do
pcall(function() java.lang.Thread.sleep(3) end)
local flags = tonumber(bufferInfo.flags)
local size = tonumber(bufferInfo.size)

local isConfig = (math.floor(flags / 2) % 2) ~= 0
local isEnd = (math.floor(flags / 4) % 2) ~= 0

if isConfig then
encoder.releaseOutputBuffer(outIndex, false)
else
if not muxerStarted then
trackIndex = tonumber(muxer.addTrack(encoder.getOutputFormat()))
muxer.start()
muxerStarted = true
end
local outBuf = encoder.getOutputBuffer(outIndex)
if size > 0 and muxerStarted then
outBuf.position(tonumber(bufferInfo.offset))
outBuf.limit(tonumber(bufferInfo.offset) + size)
muxer.writeSampleData(trackIndex, outBuf, bufferInfo)
end
encoder.releaseOutputBuffer(outIndex, false)
if isEnd then break end
end
outIndex = tonumber(encoder.dequeueOutputBuffer(bufferInfo, 4000))
end
end
end)

pcall(function() if encoder then encoder.stop() encoder.release() end end)
pcall(function() if muxer then if muxerStarted then muxer.stop() end muxer.release() end end)
pcall(function() if raf then raf.close() end end)

if not encodeOk then
local errF = io.open(wavPath .. "_error.txt", "w")
if errF then errF:write(tostring(errMsg)); errF:close() end
return false
end

local fOut = File(outPath)
if fOut.exists() and fOut.length() > 0 then
wavFile.delete()
return true
elseif fOut.exists() then
fOut.delete()
return false
end
end

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
dLoading.dismiss()
if isError then
service.speak(T("proses_selesai_error", "Proses selesai dengan beberapa error atau batas waktu habis."))
end

local isAutoComp = pref.getBoolean("auto_compress", false)
if isAutoComp then
local fSel = pref.getString("auto_comp_format", "M4A")
local srTarget = pref.getInt("auto_comp_sr", 44100)
local brTarget = pref.getInt("auto_comp_br", 128000)

jalankanDenganLoading(T("mengonversi_otomatis_ke", "Mengonversi otomatis ke ") .. fSel .. "...", function()
local errorFormat = false
for i, chunk in ipairs(chunks) do
local sukses = kompresiWav(chunk.path, fSel, srTarget, brTarget)
if not sukses and fSel == "OGG" then
errorFormat = true
break
end
end
return errorFormat
end, function(isErr)
if isErr then
service.speak(T("gagal_ogg", "Gagal! Perangkat tidak mendukung OGG, file dibiarkan dalam format WAV."))
else
service.speak(T("jam_otomatis_berhasil", "Jam bicara berhasil ditambahkan secara otomatis."))
end
muatUlangBahasaDanMenu()
end)
else
showHelperPanelKompresi(T("kompresi_audio", "Kompresi Audio"), T("konversi", "Konversi"), "M4A", 44100, 128000, function(fSel, srTarget, brTarget)
jalankanDenganLoading(T("mengonversi_ke", "Mengonversi ke ") .. fSel .. "...", function()
local errorFormat = false
for i, chunk in ipairs(chunks) do
local sukses = kompresiWav(chunk.path, fSel, srTarget, brTarget)
if not sukses and fSel == "OGG" then
errorFormat = true
break
end
end
return errorFormat
end, function(isErr)
if isErr then
service.speak(T("perangkat_tidak_dukung_ogg", "Perangkat tidak mendukung format OGG. Silakan pilih M4A."))
else
service.speak(T("jam_berhasil_dikonversi", "Jam bicara berhasil dikonversi ke ") .. fSel)
muatUlangBahasaDanMenu()
end
end)
end, function()
service.speak(T("proses_batal_wav", "Proses dibatalkan. Jam bicara dibiarkan dalam format WAV."))
muatUlangBahasaDanMenu()
end)
end
end
}))
end

local function handleTtsProgress(isError)
prosesKe = prosesKe + 1
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
onStart = function(uId) end,
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
dLoading.dismiss()
service.speak(T("gagal_mesin_tts", "Gagal memulai mesin TTS"))
muatUlangBahasaDanMenu()
end
}))
end
end, engine == "" and nil or engine)
end)
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
local myId = DapatkanAndroidID()
if not ADMIN_IDS[myId] and not ADMIN_KEDUA_IDS[myId] and not ADMIN_KETIGA_IDS[myId] then
service.speak(T("fitur_premium", "Maaf, fitur ini khusus untuk pengguna Premium."))
return
end
dialogUtama.dismiss()
showDemoInstan()
end

btnDemoUtama.onClick = function() dialogUtama.dismiss(); tampilkanMenuDemo() end
btnDaftarKode.onClick = function() dialogUtama.dismiss(); tampilkanDaftarKodeSuara() end
btnPencadanganUtama.onClick = function() dialogUtama.dismiss(); tampilkanMenuPencadangan() end
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

btnPremiumUtama.onClick = function()
dialogUtama.dismiss()
local dPremium = UI_Dialog(T("menu_premium", "Tingkatkan ke Premium"))

local myId = DapatkanAndroidID()
local txtStatus = T("status_free", "Status Akun: Pengguna Free")
if myId == ID_CREATOR then
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
if myId == ID_CREATOR then
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
local hargaPrem = isAwal and "Rp 10.000" or "Rp 15.000"

if isAwal and ADMIN_KETIGA_IDS[myId] then
service.speak(T("tolak_admin3", "Anda sudah berada di tingkat Premium Awal. Silakan pilih Premium Lanjutan jika ingin meningkatkan akses."))
return
end

dPaket.dismiss()
local dKonfirm = UI_Dialog(T("konfirmasi", "Konfirmasi"))
dKonfirm.setMessage(T("konfirm_pesan", "Apakah Anda yakin ingin memesan Premium ") .. tipePrem .. T("konfirm_harga", " seharga ") .. hargaPrem .. T("konfirm_peringatan", "? Harap jangan sentuh layar setelah ini, karena seluruh tindakan pemesanan ke WhatsApp akan dilakukan secara otomatis oleh sistem."))

dKonfirm.setButton(T("lanjutkan", "Lanjutkan"), function()
dPremium.dismiss()
showInputDialog("Pendaftaran", "Masukkan nama Anda untuk pendaftaran:", "", function(namaInput)
if namaInput == "" then service.speak("Dibatalkan. Nama tidak boleh kosong."); return end
local kodePrem = EnkripsiPayload(myId, namaInput, "PREM")
local uri = Uri.parse("https://wa.me/6283848085619?text=" .. kodePrem)
local intent = Intent(Intent.ACTION_VIEW, uri)
intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
pcall(function() service.startActivity(intent) end)

local pesan2 = "Halo admin, saya memesan premium " .. tipePrem .. ".\nKode Pendaftaran: " .. kodePrem

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

if btnAdminUtama then
btnAdminUtama.onClick = function() dialogUtama.dismiss(); TampilkanPanelAdmin() end
end
btnTutupUtama.onClick = function() dialogUtama.dismiss() end

dialogUtama.show()
end

ID_CREATOR = "a4d22753d28a9086"

ADMIN_IDS = {}
ADMIN_IDS[ID_CREATOR] = true -- Kunci Dewa mutlak, tidak bisa dihapus
for id, nama in pairs(DataAdminGlobal.admin_utama) do ADMIN_IDS[id] = true end

ADMIN_KEDUA_IDS = {}
for id, nama in pairs(DataAdminGlobal.admin_kedua) do ADMIN_KEDUA_IDS[id] = true end

ADMIN_KETIGA_IDS = {}
for id, nama in pairs(DataAdminGlobal.admin_ketiga) do ADMIN_KETIGA_IDS[id] = true end

local TOKEN_CEK_UPDATE = ""
local REPO_OWNER = "nandadian20083123"
local REPO_NAME = "skrip-lua"

function DapatkanAndroidID()
local id = Settings.Secure.getString(service.getContentResolver(), Settings.Secure.ANDROID_ID)
return tostring(id)
end

local function EnkripsiPayload(id, nama, jenis)
local String = luajava.bindClass("java.lang.String")
local Base64 = luajava.bindClass("android.util.Base64")
local txt = "NADI|" .. id .. "|" .. (nama or "") .. "|" .. jenis
return Base64.encodeToString(String(txt).getBytes(), 2)
end

local function DekripsiPayload(kode)
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
Thread(Runnable({
run = function()
local success, msg = pcall(function()
local f = File(localFilePath)
if not f.exists() then return false, "File lokal tidak ditemukan" end
local fis = FileInputStream(f)
local bos = ByteArrayOutputStream()
local buf = byte[8192]
local len = fis.read(buf)
while len > 0 do
pcall(function() java.lang.Thread.sleep(3) end)
bos.write(buf, 0, len)
len = fis.read(buf)
end
fis.close()
pcall(function() java.lang.Thread.sleep(10) end)
local base64Data = Base64.encodeToString(bos.toByteArray(), Base64.NO_WRAP)
bos.close()

uiHandler.post(Runnable({run = function() onProgress("Mengambil data " .. repoPath .. " dari server...") end}))
local sha = nil
pcall(function() java.lang.Thread.sleep(20) end)
local urlGet = URL("https://api.github.com/repos/"..REPO_OWNER.."/"..REPO_NAME.."/contents/"..repoPath)
local connGet = urlGet.openConnection()
connGet.setRequestMethod("GET")
connGet.setRequestProperty("Authorization", "token " .. token)
connGet.setRequestProperty("Accept", "application/vnd.github.v3+json")
if connGet.getResponseCode() == 200 then
local is = connGet.getInputStream()
local br = BufferedReader(InputStreamReader(is))
local jsonText, line = "", br.readLine()
while line do jsonText = jsonText .. line; line = br.readLine() end
br.close()
local jsonData = cjson.decode(jsonText)
sha = jsonData.sha
end

uiHandler.post(Runnable({run = function() onProgress("Mengunggah " .. repoPath .. " ke GitHub...") end}))
local bodyTable = {
message = commitMsg,
content = base64Data
}
if sha then bodyTable.sha = sha end
local bodyJson = cjson.encode(bodyTable)

pcall(function() java.lang.Thread.sleep(20) end)
local urlPut = URL("https://api.github.com/repos/"..REPO_OWNER.."/"..REPO_NAME.."/contents/"..repoPath)
local connPut = urlPut.openConnection()
connPut.setRequestMethod("PUT")
connPut.setRequestProperty("Authorization", "token " .. token)
connPut.setRequestProperty("Accept", "application/vnd.github.v3+json")
connPut.setRequestProperty("Content-Type", "application/json")
connPut.setDoOutput(true)

local os = connPut.getOutputStream()
os.write(String(bodyJson).getBytes("UTF-8"))
os.close()

pcall(function() java.lang.Thread.sleep(15) end)
local code = connPut.getResponseCode()
if code == 200 or code == 201 then
return true, "Berhasil"
else
return false, "Error Code: " .. tostring(code)
end
end)
uiHandler.post(Runnable({run = function()
if success then onComplete(true, msg) else onComplete(false, msg) end
end}))
end
})).start()
end

function TampilkanPanelAdmin()
local tokenTersimpan = dapatkanString("github_admin_token", "")
if tokenTersimpan == "" then
showInputDialog("Akses Admin GitHub", "Masukkan Personal Access Token GitHub (Wajib)", "", function(txt, inputDialog)
jalankanDenganLoading("Mengecek token ke server GitHub...", function()
local ok, status = pcall(function()
local url = URL("https://api.github.com/repos/nandadian20083123/skrip-lua")
local conn = url.openConnection()
conn.setConnectTimeout(5000)
conn.setReadTimeout(5000)
conn.setRequestProperty("Authorization", "token " .. txt)
return conn.getResponseCode() == 200
end)
return ok and status
end, function(isValid)
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
UI_Teks("Pilih file lokal yang ingin diupload ke GitHub:", true),
UI_Daftar("lvAdminFile"),
UI_Teks("Pemutihan (Ampunan Pengguna):"),
{LinearLayout, orientation="horizontal", layout_width="fill", layout_marginBottom="4dp",
UI_Tombol_H("btnAmpuni", "Ampuni"),
UI_Tombol_H("btnResetAmpuni", "Reset & Ampuni")
},
UI_Teks("Riwayat Rilis & Sistem:"),
{LinearLayout, orientation="horizontal", layout_width="fill", layout_marginBottom="4dp",
UI_Tombol_H("btnKelolaRiwayat", "Kelola Riwayat"),
UI_Tombol_H("btnResetToken", "Ganti Token"),
UI_Tombol_H("btnResetSidikJari", "Reset Sidik Jari")
},
UI_Teks("Pengujian Freemium:"),
{LinearLayout, orientation="horizontal", layout_width="fill", layout_marginBottom="4dp",
UI_Tombol_H("btnResetLimit", "Reset Limit Harian")
},
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
{LinearLayout, orientation="horizontal", layout_width="fill", layout_marginTop="4dp",
UI_Tombol_H("btnTutupAdmin", "Tutup Panel"),
UI_Tombol_H("btnUploadAdmin", "Upload GitHub")
}
)
dAdmin.setView(loadlayout(layoutAdmin))

local targetFiles = {
{ name = "main.lua", localPath = BASE .. "main.lua", repoPath = "main.lua" },
{ name = "terenkripsi.lua (Rilis Publik)", localPath = BASE .. "terenkripsi.lua", repoPath = "skrip Ter inkripsi/main.lua" },
{ name = "data_iven.json", localPath = BASE .. "data_iven.json", repoPath = "data_iven.json" },
{ name = "indonesia.json", localPath = langDir .. "indonesia.json", repoPath = "bahasa/indonesia.json" },
{ name = "inggris.json", localPath = langDir .. "inggris.json", repoPath = "bahasa/inggris.json" }
}

local listData, itemLayout = {}, UI_ItemBaris("cbFileAdmin", "tvFileAdmin")
for i=1, #targetFiles do table.insert(listData, { cbFileAdmin = {checked=false}, tvFileAdmin = targetFiles[i].name, _data = targetFiles[i] }) end
local adapter = LuaAdapter(service, listData, itemLayout)
lvAdminFile.setAdapter(adapter)

lvAdminFile.onItemClick = function(l, v, p, id)
listData[p+1].cbFileAdmin.checked = not listData[p+1].cbFileAdmin.checked
adapter.notifyDataSetChanged()
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
if id_admin == ID_CREATOR then label = label .. " (Creator Master)" end
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
if tId == ID_CREATOR then service.speak("Akses Ditolak: Kunci Dewa (Creator) tidak boleh diedit!"); return end
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
if tId == ID_CREATOR then service.speak("Akses Ditolak: Kunci Dewa (Creator) tidak boleh dihapus!"); return end
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

btnTambahAdmin1.onClick = function() TambahAdminUniversal(1) end
btnTambahAdmin2.onClick = function() TambahAdminUniversal(2) end
btnTambahAdmin3.onClick = function() TambahAdminUniversal(3) end
btnKelolaAdmin1.onClick = function() KelolaAdminUniversal(1) end
btnKelolaAdmin2.onClick = function() KelolaAdminUniversal(2) end
btnKelolaAdmin3.onClick = function() KelolaAdminUniversal(3) end

btnResetToken.onClick = function()
simpanString("github_admin_token", "") dAdmin.dismiss(); TampilkanPanelAdmin()
end

btnResetSidikJari.onClick = function()
local p = PreferenceManager.getDefaultSharedPreferences(service)
p.edit().remove("symbiotic_key").apply()
service.speak("Sidik jari lokal berhasil dihapus! Anda bersih sekarang.")
end

btnResetLimit.onClick = function()
local p = PreferenceManager.getDefaultSharedPreferences(service)
p.edit().remove("freemium_date").remove("freemium_count").apply()
service.speak("Batas limit harian berhasil direset!")
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

btnAmpuni.onClick = function() ProsesAmpunan(false) end
btnResetAmpuni.onClick = function() ProsesAmpunan(true) end

btnTutupAdmin.onClick = function() dAdmin.dismiss(); muatUlangBahasaDanMenu() end

btnUploadAdmin.onClick = function()
local terpilih = {}
local adaRilisPublik = false
local cumaUpdateData = true

for i=1, #listData do
if listData[i].cbFileAdmin.checked then
table.insert(terpilih, listData[i]._data)
if listData[i]._data.name == "terenkripsi.lua (Rilis Publik)" then adaRilisPublik = true end
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
dGagal.setMessage("Gagal mengunggah " .. currItem.name .. "\n\nPesan: " .. resultMsg)
dGagal.setButton("Tutup", function() TampilkanPanelAdmin() end)
dGagal.show()
end
end)
end
ProsesUploadAntrean(1)
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
Thread(Runnable({
run = function()
local ok, data = pcall(function()
local url = luajava.bindClass("java.net.URL")("https://raw.githubusercontent.com/nandadian20083123/skrip-lua/main/daftar_admin.json")
local conn = url.openConnection()
conn.setRequestProperty("Cache-Control", "no-cache")
conn.setConnectTimeout(3000)
local is = conn.getInputStream()
local content = ""
local br = luajava.bindClass("java.io.BufferedReader")(luajava.bindClass("java.io.InputStreamReader")(is))
local line = br.readLine()
while line do content = content .. line; line = br.readLine() end
br.close()
local parsed = require("cjson").decode(content)
if type(parsed) == "table" then
local f = io.open(pathAdminJson, "w")
if f then f:write(content); f:close() end
return parsed
end
return nil
end)
uiHandler.post(Runnable({
run = function()
if ok and data then DataAdminGlobal = data end
if onComplete then onComplete(ok and data ~= nil) end
end
}))
end
})).start()
end

local function PengecekModeAdmin()
local myId = DapatkanAndroidID()

if ADMIN_IDS[myId] then
-- Admin Utama (Bebas hambatan)
muatUlangBahasaDanMenu()
else
-- Kasta Selain Admin Utama (Admin Kedua & Free)
local p = PreferenceManager.getDefaultSharedPreferences(service)
local savedHash = p.getString("symbiotic_key", "")

-- 1. LOGIKA RANJAU DARAT (Memori + File Tersembunyi) --
local lockFile = File(jieshuoPath .. "/.sys_core_lock")
local isBanned = p.getBoolean("is_banned", false) or lockFile.exists()

local dataAmpunanJson = DataAdminGlobal.daftar_ampunan[myId]
local tokenAmpunanJson = 0
if type(dataAmpunanJson) == "string" then
tokenAmpunanJson = tonumber(dataAmpunanJson:match("^(%d+)")) or 0
elseif type(dataAmpunanJson) == "number" then
tokenAmpunanJson = dataAmpunanJson
end
local tokenAmpunanTerpakai = p.getInt("token_ampunan_terpakai", 0)

if tokenAmpunanJson > 0 and tokenAmpunanJson > tokenAmpunanTerpakai then
p.edit().remove("symbiotic_key").putBoolean("is_banned", false).putInt("token_ampunan_terpakai", tokenAmpunanJson).apply()
if lockFile.exists() then lockFile.delete() end
isBanned = false
savedHash = ""
service.speak("Sistem dipulihkan dari daftar ampunan. Jangan modifikasi skrip ini lagi.")
end

if isBanned then
local dJail = UI_Dialog("Akses Terblokir")
dJail.setMessage("Modifikasi ilegal terdeteksi. Anda diblokir dari skrip ini.")
dJail.setButton("Minta Ampunan", function()
showInputDialog("Identitas", "Ketik nama Anda untuk verifikasi ampunan:", "", function(namaInput)
if namaInput ~= "" then
local kode = EnkripsiPayload(myId, namaInput, "AMPUN")
local pesan = "Halo admin, saya terkunci gara-gara mengedit script. Kode validasi saya:\n" .. kode
local isKlip = p.getBoolean("use_jieshuo_clip", false)
if isKlip then service.copy(pesan) else
service.getSystemService(Context.CLIPBOARD_SERVICE).setPrimaryClip(ClipData.newPlainText("KodeJail", pesan))
end
service.speak("Berhasil disalin. Silakan kirim ke admin.")
end
PengecekModeAdmin()
end, function() PengecekModeAdmin() end)
end)
dJail.setButton2("Cek Status", function()
service.speak("Mengecek server...")
SedotDatabaseAdminGaib(function(sukses)
if sukses then service.speak("Database diperbarui.") else service.speak("Gagal terhubung ke server.") end
dJail.dismiss()
PengecekModeAdmin() -- Memanggil fungsi sendiri untuk mengecek ulang apakah gembok sudah dibuka
end)
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
p.edit().putString("symbiotic_key", hash).apply()
muatUlangBahasaDanMenu()
elseif savedHash == hash then
muatUlangBahasaDanMenu()
else
-- JIKA KETAHUAN MENGEDIT SKRIP: AKTIFKAN RANJAU! --
p.edit().putBoolean("is_banned", true).apply()
pcall(function() lockFile.createNewFile() end)
service.speak("Modifikasi ilegal terdeteksi. Sistem terkunci secara permanen.")
PengecekModeAdmin() -- Panggil fungsi penjara di atas
end
end
end

local function JalankanUnduhanOTA(remoteDateBaru, filesToDownload)
local dLoad = UI_Dialog("Mohon Tunggu")
dLoad.setMessage("Sedang mengunduh " .. #filesToDownload .. " file dari GitHub...\nMohon jangan tutup layar.")
dLoad.setCancelable(false)
dLoad.show()

Thread(Runnable({
run = function()
local success = true
for i=1, #filesToDownload do
local ok = pcall(function()
local url = URL(filesToDownload[i].url)
local conn = url.openConnection()
conn.setConnectTimeout(5000)
conn.setReadTimeout(5000)
local is = conn.getInputStream()
local fos = FileOutputStream(filesToDownload[i].path)
local buffer = byte[8192]
local len = is.read(buffer)
while len > 0 do fos.write(buffer, 0, len); len = is.read(buffer) end
fos.close()
is.close()
end)
if not ok then success = false break end
end

uiHandler.post(Runnable({
run = function()
dLoad.dismiss()
if success then
if remoteDateBaru and remoteDateBaru ~= "" then
simpanString("waktu_update_terakhir", remoteDateBaru)

-- PATCH ZERO-DAY: Cek apakah pembaruan ini benar-benar mengunduh main.lua
local adaMainLua = false
for idx = 1, #filesToDownload do
if string.find(filesToDownload[idx].path, "main%.lua") then
adaMainLua = true
break
end
end

-- Hanya hapus sidik jari DRM lama JIKA main.lua ikut diperbarui
if adaMainLua then
PreferenceManager.getDefaultSharedPreferences(service).edit().remove("symbiotic_key").apply()
end

end
local dSukses = UI_Dialog("Proses Selesai!")
dSukses.setMessage("File berhasil diunduh dan diperbarui. Skrip akan ditutup otomatis untuk menerapkan perubahan.\n\nSilakan jalankan ulang skrip ini.")
dSukses.setButton("Tutup Skrip", function() end)
dSukses.setCancelable(false)
dSukses.show()
else
local dGagal = UI_Dialog("Pembaruan Gagal")
dGagal.setMessage("Gagal mengunduh file, jaringan tidak stabil. Skrip dilanjutkan ke versi saat ini.")
dGagal.setButton("Lanjutkan Normal", function() PengecekModeAdmin() end)
dGagal.setCancelable(false)
dGagal.show()
end
end
}))
end
})).start()
end

local function CekPembaruanOTA()
Thread(Runnable({
run = function()
local myId = DapatkanAndroidID()
local isAdmin = ADMIN_IDS[myId] or ADMIN_KEDUA_IDS[myId]

local ok, remoteData = pcall(function()
local tokenTersimpan = dapatkanString("github_admin_token", "")

local url = URL("https://api.github.com/repos/nandadian20083123/skrip-lua/commits/main")
local conn = url.openConnection()
conn.setConnectTimeout(3000) conn.setReadTimeout(3000) conn.setRequestProperty("Cache-Control", "no-cache")
if tokenTersimpan ~= "" then conn.setRequestProperty("Authorization", "token " .. tokenTersimpan) end
local br = BufferedReader(InputStreamReader(conn.getInputStream()))
local jsonText, line = "", br.readLine()
while line do jsonText = jsonText .. line; line = br.readLine() end
br.close()
local json = cjson.decode(jsonText)

local repoPathMap = {}
if isAdmin then
repoPathMap = {
["main.lua"] = { path = BASE .. "main.lua", label = "Skrip Utama Mentah (main.lua)" },
["data_iven.json"] = { path = BASE .. "data_iven.json", label = "Data Event (JSON)" },
["bahasa/indonesia.json"] = { path = langDir .. "indonesia.json", label = "Bahasa Indonesia" },
["bahasa/inggris.json"] = { path = langDir .. "inggris.json", label = "Bahasa Inggris" }
}
else
repoPathMap = {
["skrip Ter inkripsi/main.lua"] = { path = BASE .. "main.lua", label = "Skrip Utama (Terenkripsi)" },
["data_iven.json"] = { path = BASE .. "data_iven.json", label = "Data Event (JSON)" },
["bahasa/indonesia.json"] = { path = langDir .. "indonesia.json", label = "Bahasa Indonesia" },
["bahasa/inggris.json"] = { path = langDir .. "inggris.json", label = "Bahasa Inggris" }
}
end

return { date = json.commit.committer.date, message = json.commit.message, map = repoPathMap }
end)

uiHandler.post(Runnable({
run = function()
local fileHilang = false
local missingNames = {}
local missingTasks = {}

if ok and remoteData then
for repoName, dataMap in pairs(remoteData.map) do
if not File(dataMap.path).exists() then
fileHilang = true
table.insert(missingNames, repoName)
local safeUrl = string.gsub(repoName, " ", "%%20")
table.insert(missingTasks, {url = "https://raw.githubusercontent.com/nandadian20083123/skrip-lua/main/"..safeUrl, path = dataMap.path})
end
end
end

if not ok or not remoteData or not remoteData.date then
if fileHilang then
local dGagal = UI_Dialog("Kesalahan Sistem")
dGagal.setMessage("File inti hilang:\n- " .. table.concat(missingNames, "\n- ") .. "\n\nSistem butuh koneksi internet.")
dGagal.setButton("Tutup", function() end)
dGagal.setCancelable(false)
dGagal.show()
else PengecekModeAdmin() end
return
end

local remoteDate = remoteData.date
local commitMsg = remoteData.message or ""
local localDate = dapatkanString("waktu_update_terakhir", "")

if fileHilang then
local dUpdate = UI_Dialog("Perbaikan Sistem")
dUpdate.setMessage("Ada file inti yang hilang:\n- " .. table.concat(missingNames, "\n- ") .. "\n\nSistem akan mengunduh ulang.")
dUpdate.setButton("Unduh Sekarang", function() JalankanUnduhanOTA(localDate, missingTasks) end)
dUpdate.setCancelable(false)
dUpdate.show()

elseif localDate == "" or remoteDate ~= localDate then
local uTasks = {}
for repoName, dataMap in pairs(remoteData.map) do
local safeUrl = string.gsub(repoName, " ", "%%20")
table.insert(uTasks, {url = "https://raw.githubusercontent.com/nandadian20083123/skrip-lua/main/"..safeUrl, path = dataMap.path})
end

local pesanDialog = "Pembaruan baru tersedia dari server."
local infoExtracted = string.match(commitMsg, "^[Ii][Nn][Ff][Oo][Rr][Mm][Aa][Ss][Ii]_(.+)")
local rilisPublik = string.match(commitMsg, "RILIS_PUBLIK_%[(.+)%]")

if rilisPublik then
pesanDialog = "Versi Terbaru Rilis!\n\nRiwayat Pembaruan:\n"
local idx = 1
for catatan in string.gmatch(rilisPublik, "([^||]+)") do
pesanDialog = pesanDialog .. idx .. ". " .. catatan .. "\n"
idx = idx + 1
end
elseif infoExtracted then
pesanDialog = pesanDialog .. "\n\nInfo Update:\n" .. infoExtracted
end

pesanDialog = pesanDialog .. "\n\nSistem akan menyinkronkan seluruh berkas inti untuk keamanan."

local dUpdate = UI_Dialog("Peringatan: Ada Update!")
dUpdate.setMessage(pesanDialog)
dUpdate.setButton("Perbarui Sekarang", function()
JalankanUnduhanOTA(remoteDate, uTasks)
end)
dUpdate.setButton2("Nanti Saja", function() PengecekModeAdmin() end)

if DapatkanAndroidID() == ID_CREATOR then
dUpdate.setButton3("Abaikan (Script Sendiri)", function()
simpanString("waktu_update_terakhir", remoteDate)
PengecekModeAdmin()
end)
end

dUpdate.setCancelable(false)
dUpdate.show()
else
PengecekModeAdmin()
end
end
}))
end
})).start()
end


if not prosesAntreanBagikan() then
cleanSpkTrash()
SedotDatabaseAdminGaib()
CekPembaruanOTA()
end
