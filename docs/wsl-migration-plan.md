# WSL2 移行計画（Web開発をWSLへ、業務はPowerShellのまま）

更新: 2026-09-19 ／ 承認: 2026-09-19 ／ 実行の主担当: **PowerShell側の Claude セッション**（理由は §0）
関連: 引継書 `~/.claude/handoff/wsl-migration.md`、記憶 `project_wsl_migration`

## 0. 方針

- 対象: `dev/em-tech-apps`（＋ `dev/apps-platform`。`inside-sales-automation` は第2波）。それ以外はすべて PowerShell のまま。
- 原則: ①正本は1つ（Windows側）。WSLからはリンクで参照し、写しを作らない ②同じフォルダを両側から触らない ③Windowsに残すものを明文化する。
- 実行は PowerShell 側で行う: フック等の安全装置が効く／`wsl -d Ubuntu -u root -- <cmd>` はパスワード無しで管理者実行できる／`wsl --shutdown` を自分のセッションを落とさずに打てる／Windows側の作業（git・Terminal・Docker・VS Code）が本体。WSL側の作業は `wsl -d Ubuntu -- bash -lc "<cmd>"` で打つ。
- 段階5（検証）だけは新しい WSL セッションで行う（フックと設定は新セッションで効く）。

## 1. 診断の要約（2026-09-18〜19 実測）

- `/mnt/c` は Linux 側より書き込みが約114倍遅く（300ファイル: 0.798秒 vs 0.007秒）、ファイル変更通知が届かない（Next.js の自動更新が効かない）。
- 23リポジトリ全部で、WSLから見ると改行差の偽差分が出る（Windows git `core.autocrlf=true` × WSL 未設定）。内部（index）は4リポジトリで全LF確認済み（`i/crlf` 0件）→ `.gitattributes` に `* text=auto` を足すだけで消える見込み。正規化コミットは不要。
- em-tech-apps: 本物の未コミット9件（全部未追跡: PDF2本・スクショ3枚・diff1.txt ほか）、未push 39件、ローカルブランチ30本、作業場5つ（`C:\wt\board|ccguide|kintai|kintai-leave|tasks-satellite`）。**ccguide は未push 592件・未コミット1件**。`C:\wt\schedule` は git 管理外の残骸（node_modules 入り）。
- node_modules に Windows 専用の部品10個 → 両OSで共有不可。pnpm 未導入（corepack で入る）。Playwright の Linux 用ブラウザ未導入。
- WSL側 `~/.claude` はほぼ空。フックは全部 `python` 起動（WSLに `python` 無し → `python-is-python3` で解決）。全フックは標準ライブラリのみ。固定パス依存は `recall-relevant.py`（`USERPROFILE`）と `session-digest.ps1`（WSL側ログを探せない）。
- 記憶の置き場がパス表記の違いで別キーになる（`c--Users-m-matsuda-claude-code` vs `-mnt-c-Users-m-matsuda-claude-code`）。`@~/.claude/projects.md` も WSL では解決しない。
- MCP: Windows 6個 / WSL 0個。obsidian 2本は移植可、mysql は書き直し、email-assistant・browser・travel-browser は不可。
- 認証情報は `python.exe` 経由で Windows 資格情報マネージャーに届く（WinVaultKeyring 実測）。`es.exe`・`gh.exe`（ログイン済み）も WSL から呼べる。Git Credential Manager あり。
- SSH鍵: `/mnt/c` では `chmod` が効かない（`metadata` 未設定）。鍵は 444/777 に見える。
- Docker Desktop の WSL 統合は未有効（統合ディストロ0件）。VS Code の WSL 拡張は未導入。
- sudo はパスワードが要る。Ubuntu 26.04 / Python 3.14.4（pip 無し）/ Node 22.23.2（nvm。`bash -c` では nvm が読まれず Windows 版 claude を掴む → `/usr/local/bin/claude` にリンク）。
- 夜間バッチ7件は Windows タスクスケジューラ駆動 → WSL 移行で止まらない。
- スキル37個: 指示だけのもの約17個は WSL でも使える。Windows のプログラム依存9個・MCP依存6個は使えない（業務系のみ）。

## 2. 段階表

| 段階 | 内容 | 所要 | 戻せるか |
|---|---|---|---|
| 0 | 事故防止（計画保存・記憶リンク・記録） | 30分 | 戻せる |
| 1 | 改行対策（`.gitattributes`） | 1時間 | 戻せる |
| 2 | WSLの土台（OS設定・道具） | 1.5時間＋WSL再起動 | 戻せる |
| 3 | Claude Code 設定の1本化 | 2〜3時間 | 戻せる |
| 4 | リポジトリ移設 | 1時間＋インストール待ち | Windows側を残すので戻せる |
| 5 | 動作検証（新しいWSLセッションで） | 1時間 | ─ |
| 6 | 切替・後始末 | 30分＋冷却2週間 | 冷却中は戻せる |
| 7 | 文書・記憶・自宅PC | 1.5時間 | ─ |

段階ごとに y/n。段階内はまとめて進める。外向き・戻せない操作（push・本番へのssh・削除・`wsl --shutdown`）は都度 y/n。

## 段階0: 事故防止 ✅ 2026-09-19 完了

- [x] 計画書を本ファイルに保存
- [x] WSL側 `~/.claude/projects/-mnt-c-Users-m-matsuda-claude-code/memory` → Windows側 `c--Users-m-matsuda-claude-code/memory` へのリンク
- [x] 記憶 `project_wsl_migration`・MEMORY.md 索引・承認待ち台帳に記録
- [x] 引継書 `~/.claude/handoff/wsl-migration.md`
- [ ] （運用）段階1が終わるまで WSL から `git add` を打たない

## 段階1: 改行対策

`.gitattributes` に `* text=auto`。内部はLF・Windowsの作業ツリーはCRLF・WSLの作業ツリーはLF。

- [ ] em-tech-apps: 既存2行（`*.svg`・`tools/app-icons/**`）の上に `* text=auto` → コミット（main。未push39件と同じ枝）→ WSLから `git status` が9件（本物のみ）になることを確認
- [ ] ain-kitting-touchless: `* text=auto` を追加。既存の `*.bat`/`*.cmd` の CRLF 固定と `.ppkg` binary は残す
- [ ] em-tech-knowledge・apps-platform・claude-setup: 同様
- [ ] 残りのリポジトリ: `git ls-files --eol | Select-String i/crlf` で内部に CRLF が無いことを確認してから追加。CRLF があるものだけ `git add --renormalize .`。既に `*` の指定があるもの（`emtech_system_live` の `* -text`、`emtech_system` の `* text=auto`）は触らない
- [ ] `init-project-claude-md` スキルの「.gitignoreベースライン」に `.gitattributes`（`* text=auto`）を足す

## 段階2: WSLの土台

WSL側は `wsl -d Ubuntu -u root -- bash -lc "<cmd>"`（管理者）／`wsl -d Ubuntu -- bash -lc "<cmd>"`（通常）。

- [ ] `/etc/wsl.conf` に `[automount]` `options="metadata"` を追加（既存の `[boot] systemd=true`・`[user] default=m-matsuda` は残す）
- [ ] `apt install -y python-is-python3 python3-pip gh`
- [ ] `ln -s /home/m-matsuda/.nvm/versions/node/v22.23.2/bin/claude /usr/local/bin/claude`
- [ ] git（通常ユーザー）: `user.name m-matsuda` / `user.email 61611032+masahiro-matsuda@users.noreply.github.com` / `core.quotepath false` / `credential.helper "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe"`（Microsoft 公式手順。Windows のログインを流用）
- [ ] `gh auth login --with-token`（トークンは `gh.exe auth token` の出力を直接パイプ。ファイルに書かない）
- [ ] `corepack enable && corepack prepare pnpm@9.15.4 --activate`
- [ ] `~/.ssh/config`: Windows側の2ホスト（鍵 `C:/Data/key/sakura_sys.em-tech.co.jp/id_rsa`・`C:/Users/m-matsuda/.ssh/cybozu_archive`）＋ `apps.em-tech.co.jp`（`/mnt/c/data/key/apps.em-tech.co.jp/id_ed25519`）を `/mnt/c/...` 表記で。`known_hosts` を写す
- [ ] Claude Code プラグイン `typescript-lsp`・`pyright-lsp` を WSL 側にも
- [ ] **`wsl --shutdown`**（PowerShell から。WSL の全セッションが落ちる）→ 再起動後 `chmod 600` が `/mnt/c` で効くことを確認 → `chmod 600 /mnt/c/data/key/*/id_*`。NTFS で読み取り専用の2本（apps・sakura）が拒否されたら判断④
- [ ] 松田さんの操作: Docker Desktop → Settings → Resources → WSL integration → Ubuntu を ON → `wsl -d Ubuntu -- docker info` が通る
- [ ] 松田さんの操作: VS Code に「WSL」拡張（ms-vscode-remote.remote-wsl）

## 段階3: Claude Code 設定の1本化

### 3-1. リンク（WSL側 → Windows側）

| WSL側 | → Windows側 | 理由 |
|---|---|---|
| `CLAUDE.md` `projects.md` `settings.json` `vocab-ng.json` | 同名 | 正本1つ |
| `skills/` `agents/` `hooks/` `lib/` `tools/` `pet/` `output-styles/` `scheduled/` | 同名 | 正本1つ |
| `handoff/` `logs/` | 同名 | 引継書と死活ログを共有 |
| `projects/c--Users-m-matsuda-claude-code/` | 同名 | `recall-relevant.py` がこの名で探す |
| `projects/-home-m-matsuda-dev-em-tech-apps/memory` | `C--Users-m-matsuda-claude-code-dev-em-tech-apps/memory`（33件） | 移設先の記憶 |
| `~/claude code` | `/mnt/c/Users/m-matsuda/claude code` | `~/claude code/...` を両側で通す |

リンクしない: `projects/` 配下のセッションログ、`sessions/` `session-env/` `shell-snapshots/` `cache/` `history.jsonl` `.credentials.json` `.context-usage.*` `.compact-handoff.*` `plugins/`。
WSL側の既存 `settings.json`（`{"model":"claude-fable-5-1[1m]","modelSettings":{"claude-opus-5":{"effortLevel":"xhigh"}},"theme":"dark"}`）は消える（判断⑦＝ルール24どおり）。

### 3-2. `settings.json`（Windows側の正本）を両側で通る形に

| 対象 | 今 | 直し |
|---|---|---|
| `fix-ps1-encoding.py` `knowledge_inbox_notify.py` `statusline.py` | `python "C:\Users\...\x.py"` | `python "$HOME/.claude/.../x.py"`（他10本が既にこの形） |
| `session-start.ps1` `session-digest.ps1` | `powershell -File "C:\..."` | `powershell.exe -File "C:\..."`（パスはそのまま。どちらから呼んでも Windows で走る） |
| `packages-lag-check.js` | 全体設定に `$HOME/claude code/dev/em-tech-apps/...` | em-tech-apps の `.claude/settings.json` へ移す（`$CLAUDE_PROJECT_DIR`） |
| `env` `permissions` `outputStyle` `statusLine` | ─ | そのまま共有 |

直後に **Windows側で** PowerShell の Claude を起動し、フックが従来どおり動くことを確認する。

### 3-3. スクリプト修正

- [ ] `hooks/recall-relevant.py`: `USERPROFILE` が無ければ `HOME`（1行）
- [ ] `lib/session-digest.ps1`: `cwd` が `/` 始まりならセッションログを `\\wsl.localhost\Ubuntu\home\m-matsuda\.claude\projects\...` から探す（数行）。**これが無いと WSL の会話が外部脳に残らない**
- [ ] `tools/knowledge_inbox_notify.py`: `C:\Users\...` 直書きを `~/claude code/...` 由来に

### 3-4. Windows Terminal（`~/.claude/tools/claude-shortcuts.ps1 add`）

- [ ] 「Claude: em-tech-apps（WSL）」: `-Path \\wsl.localhost\Ubuntu\home\m-matsuda\dev\em-tech-apps` `-Command 'wsl.exe -d Ubuntu --cd /home/m-matsuda/dev/em-tech-apps -- bash -c "claude; exec bash -i"'`
- [ ] 「Claude: アプリ質問対応（速い・WSL）」: 同上に `claude --model sonnet`
- [ ] 既存の PowerShell 版「Claude: em-tech-apps」「Claude: アプリ質問対応（速い）」は `remove`（Windows側の写しを誤って開かないため）
- [ ] 親フォルダ用の WSL プロファイルは作らない（業務系は PowerShell の役割）

## 段階4: リポジトリ移設

- [ ] 棚卸し（Windows側 git）: ブランチ30本・作業場5つ・stash 0。ccguide 作業場の未コミット1件を先に片付ける（内容を確認して y/n）
- [ ] 未追跡9件の扱い（判断⑥）
- [ ] `wsl -d Ubuntu -- git clone "/mnt/c/Users/m-matsuda/claude code/dev/em-tech-apps" ~/dev/em-tech-apps`（未push39件も運ばれる）→ `git remote set-url origin https://github.com/...`（Windows側の `git remote get-url origin` の値）→ 30本のブランチを取り込む（`git fetch <ローカルパス> "+refs/heads/*:refs/heads/*"`）
- [ ] `.env` 10本を写す（`apps/board|ccguide|cct|meetings|schedule|tasks|visit|workflow/.env`、`apps/isms/.env.local`。`chmod 600`）
- [ ] `pnpm install` → `pnpm build`
- [ ] `apps/visit`: `pnpm exec playwright install --with-deps chromium`（管理者）
- [ ] apps-platform: 同様に `~/dev/apps-platform`（未push3件）
- [ ] `_design-system` は移さない（参照のみ）
- [ ] 作業場（`C:\wt\*`）は Windows 側のまま。WSL で必要になったら `git worktree add ~/wt/<name> <branch>` で作り直す。`C:\wt\schedule` の残骸は段階6で削除

## 段階5: 動作検証（新しい WSL セッションで。全部通るまで段階6に進まない）

- [ ] Windows Terminal の WSL プロファイルから起動 → スキル一覧・CLAUDE.md・記憶の自動読み込み・ステータス行の使用率
- [ ] フック: モデル未指定でサブエージェントを起動して止まる／語彙チェック／引継書フックを手動実行
- [ ] WSL セッションを終えて Windows側 `_inbox/session-log.md` に1行増える（session-digest）
- [ ] `git status` が本物の変更だけ／テストコミット／テストpush（y/n）
- [ ] `docker build` が通り、PowerShell 側の `docker images` からも見える
- [ ] `pnpm dev` → Windows のブラウザで `localhost:3000` → 保存で自動更新
- [ ] `ssh apps.em-tech.co.jp true`（y/n）
- [ ] `python.exe` 経由で `keyring_helper.py` が読める
- [ ] Windows側: 修正後の `settings.json` で PowerShell の Claude を起動し従来どおり動く

## 段階6: 切替・後始末

- [ ] Windows側 `dev\em-tech-apps` に `MOVED_TO_WSL.md` を置き `em-tech-apps.old-20260919` に改名
- [ ] 2週間の冷却 → 問題なければ削除（親 CLAUDE.md の手順: node 停止 → GitHub 同期確認 → `Remove-Item`）。判断③
- [ ] apps-platform も同様。`C:\wt\schedule` の残骸も削除

## 段階7: 文書・記憶・自宅PC

- [ ] グローバル `CLAUDE.md`: 「WSL／PowerShell の役割分担」を短く追加。ルール20B に WSL での鍵の扱い、ルール22 に WSL 側の `quotepath`
- [ ] `projects.md`: パスを `~/claude code/...` に。em-tech-apps の行は WSL 側のパス
- [ ] 親 `claude code/CLAUDE.md`: 入口に WSL を追加。em-tech-apps の正本が WSL 側であることを明記
- [ ] `em-tech-apps/CLAUDE.md` 53行目: 「`docker build` は PowerShell で」→「PowerShell または WSL の bash（Git Bash は不可）」
- [ ] 記憶: `apps-prod-deploy-playbook`（WSL から打つ場合）、`reference_pwsh_terminal_setup`、`project_status_board`
- [ ] スキル: `git-sync`・`obsidian-memory`・`weekly-review`・`session-handoff` に WSL の注意
- [ ] `claude-setup/setup_wsl.sh`（段階2〜3を再現する。自宅PC用＝判断②）

## Windows に残すもの（WSL では動かない・動かさない）

Office 操作（doc-extract・excel-dynamic-extraction・styled-pptx の描画確認）／画面撮影（screen-capture・image-inspect）／Everything／出張予約用ブラウザ（travel-browser）／メール（email-assistant MCP）／InCircle／ルーター点検／タスクスケジューラの7ジョブ／育成ソフト（pet）の画面／Vault の自己修復（vault-bootstrap.ps1）／認証情報の登録（読むのは WSL からも可）／NAS の参照（WSL からは `powershell.exe` 経由のみ）。

## 判断

| # | 内容 | 状態 |
|---|---|---|
| ① | inside-sales-automation を移すか | 推奨どおり第2波（em-tech-apps 安定後） |
| ② | 自宅PCにも WSL を入れるか | 推奨どおり `setup_wsl.sh` を作る。導入は松田さん |
| ③ | Windows側の写しの削除 | 冷却2週間後に再確認 |
| ④ | SSH鍵: 読み取り専用2本が `chmod` 拒否なら `~/.ssh` へ複製してよいか（ルール20B の例外） | 起きたら聞く |
| ⑤ | Defender の除外（`ext4.vhdx`） | **保留** |
| ⑥ | 未追跡9件: PDF2本はコミットか／スクショ3枚・diff1.txt は削除か | **段階4の前に聞く** |
| ⑦ | 設定1本化で WSL 側に保存された「Fable 5.1・xhigh 既定」が消える | 推奨どおり消す（ルール24）。異議があれば言う |

## 併用と無関係に見つかった問題（未対処）

1. `mysql-mcp.cmd` に接続パスワードが直接書かれている（ルール20）
2. `_inbox` の `*_raw候補.md` が53件溜まり続けている（消す手順が抜けている）
3. `rtx1210-log-review/setup_syslog_collector.ps1` に日本語があるのに BOM が無い（ルール22）
4. `C:\Users\m-matsuda\.ssh\cybozu_archive` — 鍵が `C:\data\key` の外（ルール20B）
5. C: ドライブが85%使用

## 戻し方

段階0〜3: WSL 側のリンクを消し `settings.json` を元に戻す。Windows 側の `settings.json` の修正は Windows でも通る形（段階5で確認）。段階4〜6: 冷却中は Windows 側の写しが残っているので改名を戻す。`wsl.conf`: 1行消して `wsl --shutdown`。`.gitattributes`: ファイルを消してコミット。

## 検証済み／適用時に確認

実測済み: 速度差・変更通知・記憶の分断・フックの依存・認証情報の到達・`chmod`・PATH の順位・Docker 未統合・gh.exe ログイン・GCM・index の改行・本物の未コミット数・作業場の状態。
適用時に確認: `.gitattributes` だけで偽差分が消える（根拠＝index 全LF）／読み取り専用の鍵2本への `chmod`／`$HOME` 形式のフックが Windows でも動く（根拠＝既に10本がその形）。

## 実行記録

- 2026-09-19 段階0 完了（WSL セッション dfc968a3）。以降は PowerShell 側のセッションで実行。
