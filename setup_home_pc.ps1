# ============================================================
# 自宅PC セットアップスクリプト
# 用途: 会社PCと同じClaude Code環境を自宅PCに再現する
# 実行方法: PowerShell を管理者として開き、このスクリプトを実行
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   & "C:\Users\m-matsuda\Downloads\setup_home_pc.ps1"
# ============================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Step($msg) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $msg" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-OK($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-SKIP($msg) { Write-Host "  [スキップ] $msg" -ForegroundColor Yellow }
function Write-INFO($msg) { Write-Host "  $msg" -ForegroundColor White }

# ============================================================
# STEP 1: 必須ソフトウェアのインストール確認
# ============================================================
Write-Step "STEP 1: 必須ソフトウェアの確認・インストール"

# winget の確認
$hasWinget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
if (-not $hasWinget) {
    Write-Host "  [エラー] winget が見つかりません。Microsoft Store から 'アプリ インストーラー' をインストールしてください。" -ForegroundColor Red
    exit 1
}

# Git
if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-INFO "Git をインストール中..."
    winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-OK "Git インストール完了"
} else {
    Write-SKIP "Git は導入済み: $(git --version)"
}

# Node.js (LTS)
if ($null -eq (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-INFO "Node.js をインストール中..."
    winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-OK "Node.js インストール完了"
} else {
    Write-SKIP "Node.js は導入済み: $(node --version)"
}

# Python
if ($null -eq (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-INFO "Python をインストール中..."
    winget install --id Python.Python.3.11 -e --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-OK "Python インストール完了"
} else {
    Write-SKIP "Python は導入済み: $(python --version)"
}

# GitHub CLI
if ($null -eq (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-INFO "GitHub CLI をインストール中..."
    winget install --id GitHub.cli -e --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-OK "GitHub CLI インストール完了"
} else {
    Write-SKIP "GitHub CLI は導入済み: $(gh --version | Select-Object -First 1)"
}

# Claude Code CLI
if ($null -eq (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-INFO "Claude Code CLI をインストール中..."
    npm install -g @anthropic-ai/claude-code
    Write-OK "Claude Code インストール完了"
} else {
    Write-SKIP "Claude Code は導入済み"
}

# ============================================================
# STEP 2: Git ユーザー設定
# ============================================================
Write-Step "STEP 2: Git ユーザー設定"

git config --global user.name "Masahiro Matsuda"
git config --global user.email "61611032+masahiro-matsuda@users.noreply.github.com"
git config --global core.autocrlf true
Write-OK "git config 設定完了"

# ============================================================
# STEP 3: GitHub 認証（ブラウザ経由）
# ============================================================
Write-Step "STEP 3: GitHub 認証"

$ghStatus = gh auth status 2>&1
if ($ghStatus -match "Logged in") {
    Write-SKIP "GitHub 認証済み"
} else {
    Write-INFO "ブラウザが開きます。GitHub にログインしてください..."
    Write-INFO "選択肢が出たら: GitHub.com → HTTPS → Login with a web browser"
    gh auth login --hostname github.com --git-protocol https --web
    Write-OK "GitHub 認証完了"
}

# ============================================================
# STEP 4: Claude Code 設定の復元（claude-config）
# ============================================================
Write-Step "STEP 4: Claude Code 設定を GitHub から復元"

$claudeDir = "$env:USERPROFILE\.claude"

if (Test-Path "$claudeDir\.git") {
    Write-INFO ".claude/ リポジトリが既にあります。最新を取得します..."
    git -C $claudeDir pull
    Write-OK "claude-config 更新完了"
} elseif ((Get-ChildItem $claudeDir -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
    # フォルダは存在するがgit管理されていない場合（VS Code拡張インストール後など）
    Write-INFO ".claude/ にファイルがあります。git init して remote を設定します..."
    git -C $claudeDir init
    git -C $claudeDir remote add origin https://github.com/masahiro-matsuda/claude-config.git
    git -C $claudeDir fetch origin
    git -C $claudeDir checkout -b main --track origin/main 2>$null
    # リモートの内容でローカルを上書き（.credentials.json等は保持）
    git -C $claudeDir reset --hard origin/main
    Write-OK "claude-config 復元完了（既存ファイルは上書き）"
} else {
    Write-INFO "~/.claude/ を clone します..."
    git clone https://github.com/masahiro-matsuda/claude-config.git $claudeDir
    Write-OK "claude-config clone 完了"
}

# ============================================================
# STEP 5: プロジェクトの clone
# ============================================================
Write-Step "STEP 5: プロジェクト群を clone"

$projectsDir = "$env:USERPROFILE\claude code"
if (-not (Test-Path $projectsDir)) {
    New-Item -ItemType Directory -Path $projectsDir | Out-Null
}

$repos = @(
    @{ name = "visit-scheduler";   url = "https://github.com/masahiro-matsuda/visit-scheduler.git" },
    @{ name = "AI-news";           url = "https://github.com/masahiro-matsuda/AI-news.git" },
    @{ name = "em-tech-knowledge"; url = "https://github.com/masahiro-matsuda/em-tech-knowledge.git" },
    @{ name = "hp-gep202604";      url = "https://github.com/masahiro-matsuda/hp-gep202604.git" },
    @{ name = "isms-cms";          url = "https://github.com/masahiro-matsuda/isms-cms.git" },
    @{ name = "emtech_system";     url = "https://github.com/masahiro-matsuda/emtech_system.git" },
    @{ name = "api-documentation"; url = "https://github.com/masahiro-matsuda/api-documentation.git" }
)

foreach ($repo in $repos) {
    $dest = Join-Path $projectsDir $repo.name
    if (Test-Path "$dest\.git") {
        Write-INFO "$($repo.name) は既に存在します。pull します..."
        git -C $dest pull
        Write-OK "$($repo.name) 更新完了"
    } else {
        Write-INFO "$($repo.name) を clone 中..."
        git clone $repo.url $dest
        Write-OK "$($repo.name) clone 完了"
    }
}

# ============================================================
# STEP 6: visit-scheduler のセットアップ
# ============================================================
Write-Step "STEP 6: visit-scheduler のセットアップ"

$vsDir = Join-Path $projectsDir "visit-scheduler"
Set-Location $vsDir

Write-INFO "npm install 中..."
npm install
Write-OK "npm install 完了"

Write-INFO "Prisma クライアント生成中..."
npx prisma generate
Write-OK "prisma generate 完了"

Write-INFO "DB シード中..."
npx prisma db seed
Write-OK "prisma db seed 完了"

# ============================================================
# STEP 7: MCP サーバーの npm パッケージインストール
# ============================================================
Write-Step "STEP 7: MCP サーバー（npm パッケージ）のインストール"

# Playwright MCP
Write-INFO "playwright-mcp をインストール中..."
npm install -g @executeautomation/mcp-playwright
Write-OK "playwright-mcp インストール完了"

# MySQL MCP
Write-INFO "mysql-mcp をインストール中..."
npm install -g @f4ww4z/mcp-mysql-server
Write-OK "mysql-mcp インストール完了"

# ============================================================
# STEP 8: email-assistant の Python 依存ライブラリ
# ============================================================
Write-Step "STEP 8: email-assistant MCP の Python ライブラリインストール"

$emailMcpDir = "$env:USERPROFILE\.claude\mcp-servers\email-assistant"
if (Test-Path "$emailMcpDir\requirements.txt") {
    pip install -r "$emailMcpDir\requirements.txt"
    Write-OK "email-assistant 依存ライブラリ インストール完了"
} else {
    Write-INFO "requirements.txt が見つかりません（スキップ）"
}

# keyring 単体もインストール
pip install keyring 2>$null
Write-OK "keyring インストール完了"

# ============================================================
# STEP 9: Claude Code に MCP サーバーを登録
# ============================================================
Write-Step "STEP 9: MCP サーバーを Claude Code に登録"

$npmDir = "$env:APPDATA\npm"

# Notion MCP（HTTP型）
Write-INFO "Notion MCP を登録中..."
claude mcp add --scope user notion --transport http https://mcp.notion.com/mcp 2>$null
Write-OK "Notion MCP 登録完了"

# Browser MCP（Playwright）
$playwrightCmd = "$npmDir\playwright-mcp.cmd"
if (Test-Path $playwrightCmd) {
    Write-INFO "Browser MCP (Playwright) を登録中..."
    claude mcp add --scope user browser -- $playwrightCmd 2>$null
    Write-OK "Browser MCP 登録完了"
} else {
    Write-Host "  [警告] playwright-mcp.cmd が見つかりません: $playwrightCmd" -ForegroundColor Yellow
}

# MySQL MCP
$mysqlCmd = "$npmDir\mysql-mcp.cmd"
if (-not (Test-Path $mysqlCmd)) {
    # ~/.claude/mysql-mcp.cmd のコピーを使用
    $mysqlCmd = "$env:USERPROFILE\.claude\mysql-mcp.cmd"
}
if (Test-Path $mysqlCmd) {
    Write-INFO "MySQL MCP を登録中..."
    claude mcp add --scope user mysql -- $mysqlCmd 2>$null
    Write-OK "MySQL MCP 登録完了"
} else {
    Write-Host "  [警告] mysql-mcp.cmd が見つかりません" -ForegroundColor Yellow
}

# email-assistant MCP
$emailCmd = "$env:USERPROFILE\.claude\mcp-servers\email-assistant\email-assistant-mcp.cmd"
if (Test-Path $emailCmd) {
    Write-INFO "email-assistant MCP を登録中..."
    claude mcp add --scope user email-assistant -- $emailCmd 2>$null
    Write-OK "email-assistant MCP 登録完了"
} else {
    Write-Host "  [警告] email-assistant-mcp.cmd が見つかりません: $emailCmd" -ForegroundColor Yellow
}

# ============================================================
# STEP 10: SSH 鍵フォルダの作成
# ============================================================
Write-Step "STEP 10: SSH 鍵フォルダの準備"

$sshKeyDir = "C:\Data\key\sakura_sys.em-tech.co.jp"
if (-not (Test-Path $sshKeyDir)) {
    New-Item -ItemType Directory -Path $sshKeyDir -Force | Out-Null
    Write-OK "フォルダ作成: $sshKeyDir"
    Write-INFO "→ 会社PCから id_rsa を暗号化USBでこのフォルダにコピーしてください"
} else {
    Write-SKIP "SSH フォルダは既に存在します"
}

# ============================================================
# STEP 11: keyring 認証情報の登録
# ============================================================
Write-Step "STEP 11: keyring 認証情報の登録（対話入力が必要）"

Write-INFO "各種パスワードを入力してください（会社PCのメモを参照）"
Write-Host ""
python "$env:USERPROFILE\.claude\setup_credentials.py"

# ============================================================
# STEP 12: .env 生成（keyring から）
# ============================================================
Write-Step "STEP 12: .env ファイルの生成"

$vsDir = Join-Path $projectsDir "visit-scheduler"
if (Test-Path "$vsDir\gen_env.py") {
    Set-Location $vsDir
    python gen_env.py
    Write-OK "visit-scheduler .env 生成完了"
}

$aiNewsDir = Join-Path $projectsDir "AI-news"
if (Test-Path "$aiNewsDir\gen_env.py") {
    Set-Location $aiNewsDir
    python gen_env.py
    Write-OK "AI-news .env 生成完了"
}

# ============================================================
# 完了
# ============================================================
Write-Host "`n"
Write-Host "============================================" -ForegroundColor Green
Write-Host "  セットアップ完了！" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "残り手動タスク:" -ForegroundColor Yellow
Write-Host "  1. SSH 鍵 (id_rsa) を暗号化USBで C:\Data\key\sakura_sys.em-tech.co.jp\ にコピー" -ForegroundColor Yellow
Write-Host "  2. VS Code で 'C:\Users\m-matsuda\claude code' を開いて claude コマンドを起動" -ForegroundColor Yellow
Write-Host ""
Write-Host "動作確認:" -ForegroundColor Cyan
Write-Host "  cd 'C:\Users\m-matsuda\claude code\visit-scheduler'" -ForegroundColor Cyan
Write-Host "  npm run dev   → http://localhost:3000 で確認" -ForegroundColor Cyan
Write-Host ""
