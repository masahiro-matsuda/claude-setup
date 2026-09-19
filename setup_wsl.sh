#!/bin/bash
# =============================================================================
# setup_wsl.sh — WSL2（Ubuntu）を「Web開発用の Claude Code 環境」に整える再現スクリプト
#
# 会社PCで 2026-09-19 に手で確かめた手順（docs/wsl-migration-plan.md 段階2〜3）を
# 自宅PCでも同じ結果になるようにまとめたもの。何度実行しても同じ状態に収束する（既にあるものは触らない）。
#
# 前提（Windows 側に有ること）
#   - `~/.claude`（Claude Code の設定一式・git 管理）と `~/claude code`（プロジェクト群）
#   - Git for Windows（GCM 同梱）・GitHub CLI（ログイン済み）・Python 3（keyring 導入済み）
#   - 鍵ファイルは C:\data\key\（ルール20B）
#   - WSL の Ubuntu に nvm で Node 22 が入っていること（`nvm install 22`）
#
# 使い方（PowerShell から）
#   wsl -d Ubuntu -u root -- bash "/mnt/c/Users/<user>/claude code/claude-setup/setup_wsl.sh" root
#   wsl -d Ubuntu         -- bash "/mnt/c/Users/<user>/claude code/claude-setup/setup_wsl.sh" user
#   wsl --terminate Ubuntu   ← metadata と fstab を効かせるために Ubuntu だけ再起動（Docker Desktop は落ちない）
#   ※ Git Bash から呼ぶときは MSYS_NO_PATHCONV=1 を付ける（/mnt/c/... が Windows のパスに読み替えられるのを防ぐ）
# =============================================================================
set -u

WIN_USER="${WIN_USER:-m-matsuda}"                 # Windows のユーザー名
LINUX_USER="${LINUX_USER:-m-matsuda}"             # WSL のユーザー名
WIN_HOME="/mnt/c/Users/$WIN_USER"
KEY_DIR_WIN='C:\data\key'                         # 鍵フォルダ（Windows 表記）
PNPM_VERSION="${PNPM_VERSION:-9.15.4}"            # em-tech-apps の packageManager と合わせる
GIT_EMAIL="${GIT_EMAIL:-61611032+masahiro-matsuda@users.noreply.github.com}"

mode="${1:-}"
if [ "$mode" != "root" ] && [ "$mode" != "user" ]; then
  echo "使い方: setup_wsl.sh root | user"; exit 1
fi

# -----------------------------------------------------------------------------
# root: OS 側の設定
# -----------------------------------------------------------------------------
if [ "$mode" = "root" ]; then
  [ "$(id -u)" = "0" ] || { echo "root で実行してください（wsl -u root）"; exit 1; }

  echo "== /etc/wsl.conf: /mnt/c で chmod が効くように metadata"
  grep -q '^\[automount\]' /etc/wsl.conf 2>/dev/null || printf '\n[automount]\noptions="metadata"\n' >> /etc/wsl.conf

  echo "== /etc/fstab: 鍵フォルダを umask=077 で /mnt/key に別 mount（NTFS のアクセス権が読み取りだけの鍵でも 400 に見えて ssh が受け付ける）"
  mkdir -p /mnt/key
  grep -q ' /mnt/key ' /etc/fstab 2>/dev/null || echo "$KEY_DIR_WIN /mnt/key drvfs uid=1000,gid=1000,umask=077,fmask=077 0 0" >> /etc/fstab

  echo "== apt: python（フックは python で起動する）・pip・gh"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq && apt-get install -y -qq python-is-python3 python3-pip gh

  echo "== claude のリンク（実体は user 側で公式インストーラが置く）。非ログインシェルでも Windows 版より先に見つかる"
  ln -sfn "/home/$LINUX_USER/.local/bin/claude" /usr/local/bin/claude

  echo "== linger: 接続が切れても利用者のサービス（systemd-run --user で切り離した build 等）を止めない"
  loginctl enable-linger "$LINUX_USER"

  echo "root 側 完了。続けて user 側を実行し、最後に wsl --terminate Ubuntu"
  exit 0
fi

# -----------------------------------------------------------------------------
# user: シェル・道具・Claude Code の設定
# -----------------------------------------------------------------------------
echo "== ~/.profile: nvm をログインシェルでも読む（.bashrc は対話シェルでしか読まれない）"
if ! grep -q 'NVM_DIR' ~/.profile 2>/dev/null; then
cat >> ~/.profile <<'EOP'

# nvm をログインシェルでも読む（.bashrc は対話シェルでしか読まれないため）
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
EOP
fi
if ! grep -q 'GH_TOKEN' ~/.profile; then
cat >> ~/.profile <<'EOP'

# GitHub CLI のトークンは Windows の資格情報マネージャーから毎回取る（WSL 側のファイルに残さない＝ルール20）
if [ -x "/mnt/c/Program Files/GitHub CLI/gh.exe" ]; then
  export GH_TOKEN="$("/mnt/c/Program Files/GitHub CLI/gh.exe" auth token 2>/dev/null | tr -d '\r')"
fi
EOP
fi
if ! grep -q 'PLAYWRIGHT_HOST_PLATFORM_OVERRIDE' ~/.profile; then
cat >> ~/.profile <<'EOP'

# Playwright 1.60 は Ubuntu 26.04 を未対応と判定するので、24.04 として通す
export PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu24.04-x64
EOP
fi
export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
command -v node >/dev/null || { echo "nvm の node が見つかりません。先に nvm install 22"; exit 1; }

echo "== claude: 公式インストーラ（node 不要・自分で更新する）"
[ -x ~/.local/bin/claude ] || curl -fsSL https://claude.ai/install.sh | bash
npm ls -g @anthropic-ai/claude-code >/dev/null 2>&1 && npm uninstall -g @anthropic-ai/claude-code   # npm 版が残っていると二重になる

echo "== git"
git config --global user.name "$LINUX_USER"
git config --global user.email "$GIT_EMAIL"
git config --global core.quotepath false
git config --global credential.helper '/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe'
mkdir -p ~/.config/git
[ -f "$WIN_HOME/.config/git/ignore" ] && cp "$WIN_HOME/.config/git/ignore" ~/.config/git/ignore

echo "== pnpm（corepack）"
corepack enable && corepack prepare "pnpm@$PNPM_VERSION" --activate

echo "== ~/.claude: Windows 側の正本へのリンク（セッションログ・認証情報はリンクしない）"
mkdir -p ~/.claude/projects
cd ~/.claude
for x in CLAUDE.md projects.md settings.json vocab-ng.json skills agents hooks lib tools pet output-styles scheduled handoff logs; do
  if [ -e "$x" ] && [ ! -L "$x" ]; then mv "$x" "$x.wsl-old-$(date +%Y%m%d)"; fi
  [ -L "$x" ] || ln -s "$WIN_HOME/.claude/$x" "$x"
done
# 記憶: 親フォルダのキー（recall-relevant.py がこの名で探す）と、em-tech-apps の移設先のキー
[ -e "projects/c--Users-$WIN_USER-claude-code" ] || ln -s "$WIN_HOME/.claude/projects/c--Users-$WIN_USER-claude-code" "projects/c--Users-$WIN_USER-claude-code"
mkdir -p "projects/-home-$LINUX_USER-dev-em-tech-apps"
[ -e "projects/-home-$LINUX_USER-dev-em-tech-apps/memory" ] || ln -s "$WIN_HOME/.claude/projects/C--Users-$WIN_USER-claude-code-dev-em-tech-apps/memory" "projects/-home-$LINUX_USER-dev-em-tech-apps/memory"
[ -e "$HOME/claude code" ] || ln -s "$WIN_HOME/claude code" "$HOME/claude code"

echo "== Claude Code プラグイン"
~/.local/bin/claude plugin install typescript-lsp@claude-plugins-official >/dev/null 2>&1 || true
~/.local/bin/claude plugin install pyright-lsp@claude-plugins-official >/dev/null 2>&1 || true

echo "== ssh（鍵は /mnt/key 経由。会社PCの ~/.ssh/config を手で写す）"
mkdir -p ~/.ssh && chmod 700 ~/.ssh
[ -f ~/.ssh/known_hosts ] || { [ -f "$WIN_HOME/.ssh/known_hosts" ] && cp "$WIN_HOME/.ssh/known_hosts" ~/.ssh/known_hosts && chmod 600 ~/.ssh/known_hosts; }
[ -f ~/.ssh/config ] || echo "  ~/.ssh/config は未作成。会社PCの WSL 側 ~/.ssh/config を写す（IdentityFile は /mnt/key/...）"

echo "== 確認"
bash -lc 'echo "node=$(which node) pnpm=$(pnpm --version) claude=$(which claude) $(claude --version) python=$(python --version 2>&1) gh=${GH_TOKEN:+set}"'
echo "user 側 完了。wsl --terminate Ubuntu のあと、リポジトリの複製（docs/wsl-migration-plan.md 段階4）へ"
