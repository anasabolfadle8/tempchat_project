# run-tempchat.ps1
# Usage: .\run-tempchat.ps1

# Read password securely
$secure = Read-Host "Enter chat password" -AsSecureString
if (-not $secure) {
    Write-Host "Password empty - abort."
    exit 1
}

# Convert secure string to plain (only for env variable; kept in memory)
$ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)

# Set environment variable for this PowerShell process
$env:CHAT_PASSWORD = $plain

# Show info and run
Write-Host "Starting server with CHAT_PASSWORD set. Press Ctrl+C to stop."
node server.js
