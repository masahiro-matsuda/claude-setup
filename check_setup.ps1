# Claude Code Setup Verification Script

$pass = 0; $fail = 0

function Check($label, $ok, $detail = "") {
    if ($ok) {
        Write-Host "  [OK] $label" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  [NG] $label $(if($detail){"-> $detail"})" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host ""
Write-Host "=== Claude Code Setup Check ===" -ForegroundColor Cyan

# Python
Write-Host "`n[Python]" -ForegroundColor Yellow
$pyVer = python --version 2>&1
$realPython = (python -c "import sys; print(sys.executable)" 2>&1)
Check "Python installed" ($pyVer -match "3\.\d+") $pyVer
Check "Not Windows Store stub" ($realPython -notmatch "WindowsApps") $realPython
Check "keyring installed" ((python -c "import keyring; print('ok')" 2>&1) -eq "ok")
Check "email-assistant deps" ((python -c "import imapclient; print('ok')" 2>&1) -eq "ok")

# keyring credentials
Write-Host "`n[Keyring credentials]" -ForegroundColor Yellow
$emailPw = python "$env:USERPROFILE\.claude\get_credential.py" "email/password" 2>&1
Check "email/password registered" ($emailPw -and $emailPw -ne "None" -and $emailPw -notmatch "Error")

# Git
Write-Host "`n[Git / GitHub]" -ForegroundColor Yellow
Check "Git installed" ($null -ne (Get-Command git -ErrorAction SilentlyContinue))
$ghStatus = gh auth status 2>&1
Check "GitHub authenticated" ($ghStatus -match "Logged in")

# Repositories
Write-Host "`n[Repositories]" -ForegroundColor Yellow
$repos = @("visit-scheduler","AI-news","em-tech-knowledge","hp-gep202604","isms-cms","emtech_system","api-documentation")
foreach ($r in $repos) {
    $path = "$env:USERPROFILE\claude code\$r"
    Check "$r cloned" (Test-Path "$path\.git")
}

# claude-config
Check "claude-config (.claude)" (Test-Path "$env:USERPROFILE\.claude\.git")
Check "CLAUDE.md exists" (Test-Path "$env:USERPROFILE\.claude\CLAUDE.md")
Check "Skills exist" ((Get-ChildItem "$env:USERPROFILE\.claude\skills" -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
Check "Memory exists" (Test-Path "$env:USERPROFILE\.claude\projects\c--Users-m-matsuda-claude-code\memory\MEMORY.md")

# visit-scheduler
Write-Host "`n[visit-scheduler]" -ForegroundColor Yellow
$vsDir = "$env:USERPROFILE\claude code\visit-scheduler"
Check "node_modules exists" (Test-Path "$vsDir\node_modules")
Check "Prisma client generated" (Test-Path "$vsDir\app\generated\prisma")
Check "Database exists" (Test-Path "$vsDir\prisma\dev.db")
Check ".env exists" (Test-Path "$vsDir\.env")

# MCP servers
Write-Host "`n[MCP servers]" -ForegroundColor Yellow
Check "browser(playwright) cmd" (Test-Path "$env:APPDATA\npm\playwright-mcp.cmd")
Check "mysql cmd" ((Test-Path "$env:APPDATA\npm\mysql-mcp.cmd") -or (Test-Path "$env:USERPROFILE\.claude\mysql-mcp.cmd"))
Check "email-assistant cmd" (Test-Path "$env:USERPROFILE\.claude\mcp-servers\email-assistant\email-assistant-mcp.cmd")

# SSH key
Write-Host "`n[SSH key]" -ForegroundColor Yellow
Check "SSH key folder exists" (Test-Path "C:\Data\key\sakura_sys.em-tech.co.jp")
Check "id_rsa copied" (Test-Path "C:\Data\key\sakura_sys.em-tech.co.jp\id_rsa")

# Result
Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "  OK: $pass  NG: $fail" -ForegroundColor $(if($fail -eq 0){"Green"}else{"Yellow"})
Write-Host "================================" -ForegroundColor Cyan
if ($fail -eq 0) {
    Write-Host "  All checks passed!" -ForegroundColor Green
} else {
    Write-Host "  $fail item(s) need attention." -ForegroundColor Yellow
}
Write-Host ""
