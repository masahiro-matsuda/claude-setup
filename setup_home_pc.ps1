# Claude Code Home PC Setup Script
# Run as Administrator in PowerShell:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   & "$env:USERPROFILE\Downloads\setup_home_pc.ps1"

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " $msg" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}
function Write-OK($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-SKIP($msg) { Write-Host "  [SKIP] $msg" -ForegroundColor Yellow }
function Write-INFO($msg) { Write-Host "  $msg" -ForegroundColor White }

# ============================================================
# STEP 1: Install required software
# ============================================================
Write-Step "STEP 1: Check and install required software"

if ($null -eq (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "  [ERROR] winget not found. Install 'App Installer' from Microsoft Store." -ForegroundColor Red
    exit 1
}

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-INFO "Installing Git..."
    winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-OK "Git installed"
} else {
    Write-SKIP "Git already installed: $(git --version)"
}

if ($null -eq (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-INFO "Installing Node.js..."
    winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-OK "Node.js installed"
} else {
    Write-SKIP "Node.js already installed: $(node --version)"
}

if ($null -eq (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-INFO "Installing Python..."
    winget install --id Python.Python.3.11 -e --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-OK "Python installed"
} else {
    Write-SKIP "Python already installed: $(python --version)"
}

if ($null -eq (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-INFO "Installing GitHub CLI..."
    winget install --id GitHub.cli -e --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-OK "GitHub CLI installed"
} else {
    Write-SKIP "GitHub CLI already installed: $(gh --version | Select-Object -First 1)"
}

if ($null -eq (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-INFO "Installing Claude Code CLI..."
    npm install -g @anthropic-ai/claude-code
    Write-OK "Claude Code installed"
} else {
    Write-SKIP "Claude Code already installed"
}

# ============================================================
# STEP 2: Git user config
# ============================================================
Write-Step "STEP 2: Git user config"

git config --global user.name "Masahiro Matsuda"
git config --global user.email "61611032+masahiro-matsuda@users.noreply.github.com"
git config --global core.autocrlf true
Write-OK "git config done"

# ============================================================
# STEP 3: GitHub authentication (browser)
# ============================================================
Write-Step "STEP 3: GitHub authentication"

$ghStatus = gh auth status 2>&1
if ($ghStatus -match "Logged in") {
    Write-SKIP "Already logged in to GitHub"
} else {
    Write-INFO "A browser will open. Please log in to GitHub."
    Write-INFO "Choose: GitHub.com -> HTTPS -> Login with a web browser"
    gh auth login --hostname github.com --git-protocol https --web
    Write-OK "GitHub authentication done"
}

# ============================================================
# STEP 4: Restore Claude Code config (claude-config)
# ============================================================
Write-Step "STEP 4: Restore Claude Code config from GitHub"

$claudeDir = "$env:USERPROFILE\.claude"

if (Test-Path "$claudeDir\.git") {
    Write-INFO "claude-config repo already exists. Pulling latest..."
    git -C $claudeDir pull
    Write-OK "claude-config updated"
} elseif ((Get-ChildItem $claudeDir -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
    Write-INFO ".claude/ has files (VS Code extension). Linking to GitHub repo..."
    git -C $claudeDir init
    git -C $claudeDir remote add origin https://github.com/masahiro-matsuda/claude-config.git
    git -C $claudeDir fetch origin
    $prev = $ErrorActionPreference; $ErrorActionPreference = "SilentlyContinue"
    git -C $claudeDir checkout -b main --track origin/main 2>$null
    $ErrorActionPreference = $prev
    git -C $claudeDir reset --hard origin/main
    Write-OK "claude-config restored"
} else {
    Write-INFO "Cloning claude-config to ~/.claude/ ..."
    git clone https://github.com/masahiro-matsuda/claude-config.git $claudeDir
    Write-OK "claude-config cloned"
}

# ============================================================
# STEP 5: Clone all projects
# ============================================================
Write-Step "STEP 5: Clone all projects"

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
        Write-INFO "$($repo.name) already exists. Pulling..."
        git -C $dest pull
        Write-OK "$($repo.name) updated"
    } else {
        Write-INFO "Cloning $($repo.name) ..."
        git clone $repo.url $dest
        Write-OK "$($repo.name) cloned"
    }
}

# ============================================================
# STEP 6: visit-scheduler setup
# ============================================================
Write-Step "STEP 6: visit-scheduler setup"

$vsDir = Join-Path $projectsDir "visit-scheduler"
Set-Location $vsDir

Write-INFO "Running npm install..."
npm install
Write-OK "npm install done"

Write-INFO "Generating Prisma client..."
npx prisma generate
Write-OK "prisma generate done"

Write-INFO "Seeding database..."
npx prisma db seed
Write-OK "prisma db seed done"

# ============================================================
# STEP 7: MCP server npm packages
# ============================================================
Write-Step "STEP 7: Install MCP server npm packages"

Write-INFO "Installing playwright-mcp..."
npm install -g @executeautomation/mcp-playwright
Write-OK "playwright-mcp installed"

Write-INFO "Installing mysql-mcp..."
npm install -g @f4ww4z/mcp-mysql-server
Write-OK "mysql-mcp installed"

# ============================================================
# STEP 8: email-assistant Python dependencies
# ============================================================
Write-Step "STEP 8: Install email-assistant Python dependencies"

$emailMcpDir = "$env:USERPROFILE\.claude\mcp-servers\email-assistant"
if (Test-Path "$emailMcpDir\requirements.txt") {
    python -m pip install -r "$emailMcpDir\requirements.txt"
    Write-OK "email-assistant dependencies installed"
} else {
    Write-INFO "requirements.txt not found (skipping)"
}

python -m pip install keyring
Write-OK "keyring installed"

# ============================================================
# STEP 9: Register MCP servers in Claude Code
# ============================================================
Write-Step "STEP 9: Register MCP servers in Claude Code"

$npmDir = "$env:APPDATA\npm"

Write-INFO "Registering Notion MCP..."
claude mcp add --scope user notion --transport http https://mcp.notion.com/mcp 2>$null
Write-OK "Notion MCP registered"

$playwrightCmd = "$npmDir\playwright-mcp.cmd"
if (Test-Path $playwrightCmd) {
    Write-INFO "Registering Browser MCP (Playwright)..."
    claude mcp add --scope user browser -- $playwrightCmd 2>$null
    Write-OK "Browser MCP registered"
} else {
    Write-Host "  [WARN] playwright-mcp.cmd not found: $playwrightCmd" -ForegroundColor Yellow
}

$mysqlCmd = "$npmDir\mysql-mcp.cmd"
if (-not (Test-Path $mysqlCmd)) {
    $mysqlCmd = "$env:USERPROFILE\.claude\mysql-mcp.cmd"
}
if (Test-Path $mysqlCmd) {
    Write-INFO "Registering MySQL MCP..."
    claude mcp add --scope user mysql -- $mysqlCmd 2>$null
    Write-OK "MySQL MCP registered"
} else {
    Write-Host "  [WARN] mysql-mcp.cmd not found" -ForegroundColor Yellow
}

$emailCmd = "$env:USERPROFILE\.claude\mcp-servers\email-assistant\email-assistant-mcp.cmd"
if (Test-Path $emailCmd) {
    Write-INFO "Registering email-assistant MCP..."
    claude mcp add --scope user email-assistant -- $emailCmd 2>$null
    Write-OK "email-assistant MCP registered"
} else {
    Write-Host "  [WARN] email-assistant-mcp.cmd not found: $emailCmd" -ForegroundColor Yellow
}

# ============================================================
# STEP 10: Create SSH key folder
# ============================================================
Write-Step "STEP 10: Create SSH key folder"

$sshKeyDir = "C:\Data\key\sakura_sys.em-tech.co.jp"
if (-not (Test-Path $sshKeyDir)) {
    New-Item -ItemType Directory -Path $sshKeyDir -Force | Out-Null
    Write-OK "Folder created: $sshKeyDir"
    Write-INFO "-> Copy id_rsa from company PC to this folder via encrypted USB"
} else {
    Write-SKIP "SSH folder already exists"
}

# ============================================================
# STEP 11: Register keyring credentials (interactive)
# ============================================================
Write-Step "STEP 11: Register keyring credentials (interactive input required)"

Write-INFO "Please enter passwords when prompted (refer to company PC notes)"
Write-Host ""
python "$env:USERPROFILE\.claude\setup_credentials.py"

# ============================================================
# STEP 12: Generate .env files from keyring
# ============================================================
Write-Step "STEP 12: Generate .env files"

$vsDir = Join-Path $projectsDir "visit-scheduler"
if (Test-Path "$vsDir\gen_env.py") {
    Set-Location $vsDir
    python gen_env.py
    Write-OK "visit-scheduler .env generated"
}

$aiNewsDir = Join-Path $projectsDir "AI-news"
if (Test-Path "$aiNewsDir\gen_env.py") {
    Set-Location $aiNewsDir
    python gen_env.py
    Write-OK "AI-news .env generated"
}

# ============================================================
# Done
# ============================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Remaining manual tasks:" -ForegroundColor Yellow
Write-Host "  1. Copy id_rsa to C:\Data\key\sakura_sys.em-tech.co.jp\ via encrypted USB" -ForegroundColor Yellow
Write-Host "  2. Open VS Code -> open 'C:\Users\m-matsuda\claude code' -> run claude" -ForegroundColor Yellow
Write-Host ""
Write-Host "Test visit-scheduler:" -ForegroundColor Cyan
Write-Host "  cd 'C:\Users\m-matsuda\claude code\visit-scheduler'" -ForegroundColor Cyan
Write-Host "  npm run dev  ->  http://localhost:3000" -ForegroundColor Cyan
Write-Host ""
