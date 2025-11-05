# start-all.ps1
# تشغيل السيرفر و ngrok في الخلفية ثم فتح Chrome بالرابط العام تلقائيًا

param(
    [string]$NgrokPath = 'C:\Program Files\WindowsApps\ngrok.ngrok_3.24.0.0_x64__1g87z0zv29zzc\ngrok.exe',
    [int]$WaitSeconds = 2,
    [int]$NgrokTimeoutSeconds = 30
)

# --- تحقق أساسي ---
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host 'Error: Node.js not found. Install Node.js first.' -ForegroundColor Red
    exit 1
}

$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $projectDir

if (-not (Test-Path '.\server.js')) {
    Write-Host 'Error: server.js not found in the project directory.' -ForegroundColor Red
    exit 1
}

# --- اقرأ كلمة السر بشكل آمن ---
# --- كلمة السر (محدثة: تفضّل قراءة متغيّر البيئة CHAT_PASSWORD إن وُجد) ---
if ($env:CHAT_PASSWORD -and $env:CHAT_PASSWORD.Trim() -ne "") {
    # إذا المتغير موجود نستخدمه مباشرة (مفيد للتشغيل المخفي)
    $plain = $env:CHAT_PASSWORD
    Write-Host "Using CHAT_PASSWORD from environment."
} else {
    # غير ذلك نطلبها تفاعليًا (للاختبار المحلي)
    $secure = Read-Host 'Enter chat password' -AsSecureString
    if (-not $secure) {
        Write-Host 'Password empty. Abort.'
        exit 1
    }
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}

# اضبط المتغير لنفس العملية (يُورَّث للعمليات الفرعية)
$env:CHAT_PASSWORD = $plain
# --- شغّل السيرفر في الخلفية (مخفى) ---
Write-Host 'Starting local server...' -ForegroundColor Cyan
Start-Process -FilePath 'node' -ArgumentList 'server.js' -WindowStyle Hidden

Start-Sleep -Seconds $WaitSeconds

# --- تحقق من وجود ngrok.exe ---
if (-not (Test-Path $NgrokPath)) {
    Write-Host 'ngrok.exe not found at path:' -ForegroundColor Red
    Write-Host $NgrokPath
    Write-Host 'Put ngrok.exe in a simpler path if needed, e.g., C:\tools\ngrok\'
    exit 1
}

# --- شغّل ngrok في Job واكتب الخرج لملف لُوغ ---
$outFile = Join-Path $projectDir 'ngrok_output.log'
if (Test-Path $outFile) { Remove-Item $outFile -ErrorAction SilentlyContinue }

$ngrokCommand = { param($p,$out) & $p http 3000 --log=stdout --log-format=json 2>&1 | Out-File -FilePath $out -Encoding utf8 }
$job = Start-Job -ScriptBlock $ngrokCommand -ArgumentList $NgrokPath, $outFile

Write-Host 'ngrok started as background job (writing logs to):' $outFile -ForegroundColor Cyan

# --- بحث دوري عن الرابط العام في ملف اللوج ---
$publicUrl = $null
$elapsed = 0
while ($elapsed -lt $NgrokTimeoutSeconds -and -not $publicUrl) {
    Start-Sleep -Seconds 1
    $elapsed += 1
    if (Test-Path $outFile) {
        try {
            $text = Get-Content $outFile -Raw -ErrorAction SilentlyContinue
            if ($text -match '"url":"(https:[^"]+)"') {
                $publicUrl = $matches[1]
                break
            }
            # بعض نسخ ngrok تكتب "public_url"
            if ($text -match '"public_url":"(https:[^"]+)"') {
                $publicUrl = $matches[1]
                break
            }
            # fallback: بحث عن أي https://...ngrok...
            if ($text -match '(https://[^\s"]+\.ngrok[^\s"]*)') {
                $publicUrl = $matches[1]
                break
            }
        } catch { }
    }
}

if (-not $publicUrl) {
    Write-Host 'Timeout: could not detect ngrok public URL within' $NgrokTimeoutSeconds 'seconds.' -ForegroundColor Yellow
    Write-Host 'Open the ngrok log file to inspect:' $outFile
    Write-Host 'Or run ngrok manually: "'$NgrokPath' http 3000"'
    Write-Host 'Press Enter to exit...'
    Read-Host | Out-Null
    # optionally stop job
    Try { Stop-Job -Job $job -ErrorAction SilentlyContinue; Remove-Job -Job $job -ErrorAction SilentlyContinue } Catch { }
    exit 1
}

# --- افتح Chrome بالرابط العام ---
Write-Host "`nPublic URL detected: $publicUrl" -ForegroundColor Green
# حاول فتح الافتراضي للمستعرض (chrome.exe غالباً على PATH)
try {
    Start-Process 'chrome.exe' $publicUrl -ErrorAction Stop
} catch {
    # fallback: افتح بالمتصفح الافتراضي عبر Start-Process مع URL
    Start-Process $publicUrl
}

Write-Host "`nngrok job id:" $job.Id " (keep running in background)."
Write-Host "To stop ngrok job: Stop-Job -Id $($job.Id) ; Remove-Job -Id $($job.Id)"
Write-Host "To stop Node: stop node process from Task Manager or run: Get-Process node | Stop-Process"

# إبقاء السكربت مفتوحًا حتى يفضل الـ job شغالًا (أو يمكن تخرج يدوياً)
Write-Host "`nPress Ctrl+C to exit this script (ngrok job will continue running)."
while ($true) { Start-Sleep -Seconds 60 }
