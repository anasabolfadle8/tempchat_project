' run-hidden.vbs
' Run the start-all.ps1 script hidden and set CHAT_PASSWORD for the process
' EDIT: change projectPath or chatPass below if needed

Option Explicit

Dim WshShell, projectPath, psCommand, chatPass, psExe

Set WshShell = CreateObject("WScript.Shell")

' === تعديل المسار إن لزم ===
projectPath = "E:\tempchat_project"    ' ← اذا مجلد مشروعك مختلف غيّره هنا
psExe = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"               ' مسار PowerShell، غيره لو تحتاج مسار كامل

' === كلمة السر الثابتة التي تريد استخدامها (غيرها لو تحب) ===
chatPass = "11122009"          ' ← غيّرها لكلمة سر آمنة لو حبيت

' === ضع متغيّر البيئة للعملية (يُورَّث للعمليات الفرعية) ===
WshShell.Environment("Process")("CHAT_PASSWORD") = chatPass

' === أمر تشغيل الباورشيل على ملف start-all.ps1 في المجلد المحدد (مخفي) ===
psCommand = psExe & " -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & projectPath & "\start-all.ps1"""

' تشغيل السكربت بصمت (0 = مخفي)، False = لا ننتظر انتهاء العملية
WshShell.Run psCommand, 0, False

' انهاء الـ VBS فوراً
WScript.Quit 0

