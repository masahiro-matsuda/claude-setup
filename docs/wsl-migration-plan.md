# WSL2 移行計画（Web開発をWSLへ、業務はPowerShellのまま）

更新: 2026-09-19 ／ 承認: 2026-09-19 ／ 検証: 2026-09-19（PowerShell 側で実機と突き合わせ、抜け13件を反映） ／ 実行の主担当: **PowerShell側の Claude セッション**（理由は §0）
関連: 引継書 `~/.claude/handoff/wsl-migration.md`、記憶 `project_wsl_migration`

## 0. 方針

- 対象: `dev/em-tech-apps`（＋ `dev/apps-platform`。`inside-sales-automation` は第2波）。それ以外はすべて PowerShell のまま。
- 原則: ①正本は1つ（Windows側）。WSLからはリンクで参照し、写しを作らない ②同じフォルダを両側から触らない ③Windowsに残すものを明文化する。
- 実行は PowerShell 側で行う: フック等の安全装置が効く／`wsl -d Ubuntu -u root -- <cmd>` はパスワード無しで管理者実行できる／`wsl --shutdown` を自分のセッションを落とさずに打てる／Windows側の作業（git・Terminal・Docker・VS Code）が本体。WSL側の作業は `wsl -d Ubuntu -- bash -lc "<cmd>"` で打つ。
- 段階5（検証）だけは新しい WSL セッションで行う（フックと設定は新セッションで効く）。

## 1. 診断の要約（2026-09-18〜19 実測）

- `/mnt/c` は Linux 側より書き込みが約114倍遅く（300ファイル: 0.798秒 vs 0.007秒）、ファイル変更通知が届かない（Next.js の自動更新が効かない）。
- 23リポジトリ全部で、WSLから見ると改行差の偽差分が出る（Windows git `core.autocrlf=true` × WSL 未設定）。内部（index）は4リポジトリで全LF確認済み（`i/crlf` 0件）→ `.gitattributes` に `* text=auto` を足すだけで消える見込み。正規化コミットは不要。
- em-tech-apps: 本物の未コミット9件（全部未追跡: PDF2本・jpeg 3枚・diff1〜4.txt）、未push 39件、ローカルブランチ30本、作業場5つ（`C:\wt\board|ccguide|kintai|kintai-leave|tasks-satellite`）。**ccguide は未push 592件・未コミット1件**。`C:\wt\schedule` は git 管理外の残骸（node_modules 入り）。
- node_modules に Windows 専用の部品10個 → 両OSで共有不可。pnpm 未導入（corepack で入る）。Playwright の Linux 用ブラウザ未導入。
- WSL側 `~/.claude` はほぼ空。フックは全部 `python` 起動（WSLに `python` 無し → `python-is-python3` で解決）。全フックは標準ライブラリのみ。固定パス依存は `recall-relevant.py`（`USERPROFILE`）と `session-digest.ps1`（WSL側ログを探せない）。
- 記憶の置き場がパス表記の違いで別キーになる（`c--Users-m-matsuda-claude-code` vs `-mnt-c-Users-m-matsuda-claude-code`）。`@~/.claude/projects.md` も WSL では解決しない。
- MCP: Windows 6個 / WSL 0個。obsidian 2本は移植可、mysql は書き直し、email-assistant・browser・travel-browser は不可。
- 認証情報は `python.exe` 経由で Windows 資格情報マネージャーに届く（WinVaultKeyring 実測）。`es.exe`・`gh.exe`（ログイン済み）も WSL から呼べる。Git Credential Manager あり。
- SSH鍵: `/mnt/c` では `chmod` が効かない（`metadata` 未設定）。鍵は 444/777 に見える。
- Docker Desktop の WSL 統合は未有効（統合ディストロ0件）。VS Code の WSL 拡張は未導入。
- sudo はパスワードが要る。Ubuntu 26.04 / Python 3.14.4（pip 無し）/ Node 22.23.2（nvm）と apt の `/usr/bin/node` 22.22.1 が並存。**nvm は対話シェルでしか読まれない**（`.bashrc` の先頭で非対話なら抜ける）ので、`bash -c` でも `bash -lc` でも node は apt 側・claude は Windows 側 `/mnt/c/.../Roaming/npm/claude` を掴む（2026-09-19 実測）→ 段階2で `~/.profile` に nvm を足し、claude は公式インストーラ＋`/usr/local/bin` のリンクにする。
- 夜間バッチ7件は Windows タスクスケジューラ駆動 → WSL 移行で止まらない。タスクスケジューラに em-tech-apps／apps-platform を指すジョブは無い（改名で止まるものなし）。
- ローカルDBは全部 Docker Desktop のコンテナ（Postgres 17・各アプリの `compose.yaml`・名前付きボリューム `<app>-db-data`）。接続先は `.env` の `localhost:<ポート>`。統合ONなら WSL からも同じ接続先で届き、データもそのまま使える見込み（段階5で確認）。
- `.env` に Windows パスは1つ（`apps/workflow/.env` の `GOOGLE_APPLICATION_CREDENTIALS=C:/data/key/...`）。
- gitignore 対象は `git clone` で運ばれない: SQLite の開発DB 3本（`apps/ccguide|cct|visit/prisma/dev.db`）・`apps/workflow/uploads/`・`apps/kintai/docs/管理部門資料/`（規程の PDF・Excel 6点）・`apps/ccguide/docs/ads/` ほか。
- 容量: C: 空き 144GB、WSL 仮想ディスク 4.2GB（上限 1TB）、WSL メモリ 15GB／32GB、inotify 上限 1,048,576 → 足りる。
- フックの Python に Windows 専用の部品・3.13 で消えた部品は無し。`session-start.ps1` は UTF-8 出力を設定済み（WSL から呼んでも化けない）。`scheduled/` は emtime のスクリプト置き場（Claude の予約実行ではない）。
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

## 段階1: 改行対策 ✅ 2026-09-19 完了

`.gitattributes` に `* text=auto`。内部はLF・Windowsの作業ツリーはCRLF・WSLの作業ツリーはLF。

- [x] em-tech-apps: 既存2行（`*.svg`・`tools/app-icons/**`）の上に `* text=auto` → コミット `c3f7180b`（main）→ WSLから `git status` が本物だけになった（改行の偽差分 0・権限の差分 0）
  - 作業場5本のブランチには main を取り込むまで入らない（偽差分のまま）＝**作業場では段階1のあとも WSL から `git add` しない**。なお Windows の作業場は WSL からは開けない（`.git` の指す先が `C:/...` 表記）
- [x] ain-kitting-touchless: `65729c7`。既存の `*.bat`/`*.cmd` の CRLF 固定と `.ppkg` binary は残した
- [x] em-tech-knowledge `2399c71`・apps-platform `53cab2a`・claude-setup `db81add`
- [x] 残りのリポジトリ: 全22リポジトリで内部の CRLF・混在は 0 件（`emtech_system_live` の346件は `* -text` 指定済みで対象外）→ `~/.claude`（`f7d6f0a`・WSL からも引継書をコミットするため）を含む22本に追加してコミット。`emtech_system`／`emtech_system_live` は触らず
- [x] `init-project-claude-md` スキル STEP 5 に `.gitattributes` を追加
- 発見: WSL から見ると `apps/.claude/`・`apps/meetings/.claude/`（em-tech-apps）と `.claude/`（vuln-mgmt）が未追跡に見える。原因＝Windows の全体除外 `~/.config/git/ignore`（`**/.claude/settings.local.json`）が WSL に無い → 段階2の git 設定で解消

## 段階2: WSLの土台

WSL側は `wsl -d Ubuntu -u root -- bash -lc "<cmd>"`（管理者）／`wsl -d Ubuntu -- bash -lc "<cmd>"`（通常）。

- [ ] `/etc/wsl.conf` に `[automount]` `options="metadata"` を追加（既存の `[boot] systemd=true`・`[user] default=m-matsuda` は残す）
- [ ] `apt install -y python-is-python3 python3-pip gh`
- [ ] `~/.profile` の末尾に nvm の3行（`.bashrc` 119〜121行と同じ `export NVM_DIR`／`nvm.sh`／`bash_completion`）→ `bash -lc "which node corepack"` が `~/.nvm/...` を返す（足す前は apt の `/usr/bin/node`）
- [ ] claude: 公式インストーラ `curl -fsSL https://claude.ai/install.sh | bash`（`~/.local/bin/claude`・node 不要・自分で更新する）→ `ln -s /home/m-matsuda/.local/bin/claude /usr/local/bin/claude`（非ログインシェルでも Windows 版 `/mnt/c/.../npm/claude` より先に見つかる）→ `bash -c "claude --version"` が Linux 版を返す → nvm 内の npm 版は `npm uninstall -g @anthropic-ai/claude-code`（対話シェルでは nvm の bin が先に来るため残すと二重になる）
- [ ] git（通常ユーザー）: `user.name m-matsuda` / `user.email 61611032+masahiro-matsuda@users.noreply.github.com` / `core.quotepath false` / `credential.helper "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe"`（Microsoft 公式手順。Windows のログインを流用）/ `~/.config/git/ignore` を Windows と同じ内容（`**/.claude/settings.local.json`）で作る（無いと WSL だけ `.claude/` が未追跡に見える。段階1で発見）
- [ ] `gh auth login --with-token`（トークンは `gh.exe auth token` の出力を直接パイプ。ファイルに書かない）
- [ ] `corepack enable && corepack prepare pnpm@9.15.4 --activate`（`~/.profile` を足した後・nvm の node で。apt の corepack は root 所有の場所に書こうとして失敗する）
- [ ] `~/.ssh/config`: Windows側の2ホスト（鍵 `C:/Data/key/sakura_sys.em-tech.co.jp/id_rsa`・`C:/Users/m-matsuda/.ssh/cybozu_archive`）＋ `apps.em-tech.co.jp`（`/mnt/c/data/key/apps.em-tech.co.jp/id_ed25519`）を `/mnt/c/...` 表記で。`known_hosts` を写す
- [ ] Claude Code プラグイン `typescript-lsp`・`pyright-lsp` を WSL 側にも
- [ ] **`wsl --shutdown`**（PowerShell から。WSL の全セッションが落ちる）→ 再起動後 `chmod 600` が `/mnt/c` で効くことを確認 → `chmod 600 /mnt/c/data/key/*/id_*`。NTFS で読み取り専用の2本（apps・sakura）が拒否されたら判断④
- [ ] 松田さんの操作: Docker Desktop → Settings → Resources → WSL integration → Ubuntu を ON → `wsl -d Ubuntu -- docker info` が通る → `wsl -d Ubuntu -- docker ps -a` に Windows 側と同じコンテナ（`schedule-postgres-1` 等）が見える
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
WSL側の既存 `settings.json`（`{"model":"claude-fable-5-1[1m]","modelSettings":{"claude-opus-5":{"effortLevel":"xhigh"}},"theme":"dark"}`）はリンクで置き換わる。**Windows 側の正本にも 2026-09-19 の `/model` で `claude-fable-5-1[1m]` 既定と opus・fable の xhigh が保存されている**ので、1本化後は両側でその値が効く（判断⑦）。

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
- [ ] `tools/nightly_knowledge_backfill.py`（夜間の知見抽出）: WSL セッションのログ（`\\wsl.localhost\Ubuntu\home\m-matsuda\.claude\projects\-home-m-matsuda-dev-em-tech-apps\`）も読めるようにする。**digest の1行だけ直しても、本文を読む後段が WSL を探せなければ知見に残らない**（ログの探し方は着手時に読んで確かめる）
- [ ] （任意）obsidian MCP 2本を WSL 側 `~/.claude.json` に登録（`mcp-setup` スキル。Vault は `/mnt/c/Users/m-matsuda/claude-vault`）。記憶の読み書きはファイル経由なので無くても動く

### 3-4. Windows Terminal（`~/.claude/tools/claude-shortcuts.ps1 add`）

- [ ] 「Claude: em-tech-apps（WSL）」: `-Path \\wsl.localhost\Ubuntu\home\m-matsuda\dev\em-tech-apps` `-Command 'wsl.exe -d Ubuntu --cd /home/m-matsuda/dev/em-tech-apps -- bash -lc "claude; exec bash -i"'`（`-lc`＝ログインシェルで `~/.profile` の nvm を読む。`-c` だと node・pnpm が apt 側になる）
- [ ] 「Claude: アプリ質問対応（速い・WSL）」: 同上に `claude --model sonnet`
- [ ] 既存の PowerShell 版「Claude: em-tech-apps」「Claude: アプリ質問対応（速い）」は `remove`（Windows側の写しを誤って開かないため）
- [ ] 親フォルダ用の WSL プロファイルは作らない（業務系は PowerShell の役割）

## 段階4: リポジトリ移設

- [ ] 棚卸し（Windows側 git）: ブランチ30本・作業場5つ・stash 0。ccguide 作業場の未コミット1件＝`apps/ccguide/prisma/dev.db.bak-20260815`（8/15 の開発DBの控え）は削除（2026-09-19 承認）
- [ ] 未追跡9件（判断⑥・2026-09-19 承認）: `apps/schedule/docs/*.pdf` 2本はコミット、`cct-*.jpeg` 3枚と `diff1〜4.txt` は削除
- [ ] **保険の push（y/n）**: main（39件先行）と全ブランチ（ccguide 592・schedule-p6 314・board 73・meetings-zero-redesign 39・追跡先なし19本）を GitHub へ。移設中に Windows 側を壊しても戻せる。段階5の「テストpush」はこれで代える
- [ ] `wsl -d Ubuntu -- git clone "/mnt/c/Users/m-matsuda/claude code/dev/em-tech-apps" ~/dev/em-tech-apps`（未push39件も運ばれる）→ 30本のブランチを取り込む（`git fetch <ローカルパス> "+refs/heads/*:refs/heads/*"`）→ `git remote set-url origin https://github.com/masahiro-matsuda/em-tech-apps.git` → `git fetch origin --prune`（複製元のローカル参照を GitHub の参照に置き換える）→ `git for-each-ref refs/heads | wc -l` が Windows 側と同じ 30
- [ ] `.env` 10本を写す（`apps/board|ccguide|cct|meetings|schedule|tasks|visit|workflow/.env`、`apps/isms/.env.local`。`chmod 600`）。`apps/workflow/.env` の `GOOGLE_APPLICATION_CREDENTIALS` は `/mnt/c/data/key/...` に書き換える（Windows パスのまま写すと鍵が見つからない）
- [ ] gitignore 対象で要るものを写す（`git status --ignored --short` から node_modules・.next・ログ・スクショを除いた分）: `apps/ccguide|cct|visit/prisma/dev.db`、`apps/workflow/uploads/`、`apps/kintai/docs/管理部門資料/`、`apps/ccguide/docs/ads/`・同 `セキュリティ委員会_検討事項_2026-08.md`、`apps/tasks/docs/briefing/`、`apps/schedule/tmp/`。Postgres のデータは Docker の名前付きボリュームに在るので写さない
- [ ] `pnpm install` → `pnpm build`
- [ ] `apps/visit`: root で `pnpm exec playwright install-deps chromium`（OS の部品）→ 通常ユーザーで `pnpm exec playwright install chromium`（ブラウザ本体。root で `--with-deps` を打つと root 側の `~/.cache` に入って通常ユーザーから見えない）
- [ ] apps-platform: 同様に `~/dev/apps-platform`（未push3件）
- [ ] `_design-system` は移さない（参照のみ）
- [ ] 作業場（`C:\wt\*`）は段階6の改名まで Windows 側でそのまま使える。WSL で必要になったら `git worktree add ~/wt/<name> <branch>` で作り直す。`C:\wt\schedule` の残骸は段階6で削除

## 段階5: 動作検証（新しい WSL セッションで。全部通るまで段階6に進まない）

- [ ] Windows Terminal の WSL プロファイルから起動 → スキル一覧・CLAUDE.md・記憶の自動読み込み・ステータス行の使用率
- [ ] フック: モデル未指定でサブエージェントを起動して止まる／語彙チェック／引継書フックを手動実行
- [ ] WSL セッションを終えて Windows側 `_inbox/session-log.md` に1行増える（session-digest）
- [ ] Claude の Bash から `node --version`・`pnpm --version` が nvm 側（22.23.2／9.15.4）を返す
- [ ] `git status` が本物の変更だけ／テストコミット／push は段階4の保険 push で済んでいれば省略（残っていれば y/n。main に捨てコミットは作らない）
- [ ] `docker build` が通り、PowerShell 側の `docker images` からも見える
- [ ] アプリ1つ（schedule）で `docker compose up -d` → `docker ps` に Windows 側と同じコンテナ名 → `localhost:<ポート>` に届き、既存データが見える
- [ ] `pnpm dev` → Windows のブラウザで `localhost:3000` → 保存で自動更新
- [ ] `ssh apps.em-tech.co.jp true`（y/n）
- [ ] `python.exe` 経由で `keyring_helper.py` が読める
- [ ] Windows側: 修正後の `settings.json` で PowerShell の Claude を起動し従来どおり動く

## 段階6: 切替・後始末

- [ ] **改名の前に Windows 側の作業場5つを畳む**: 各作業場が clean（`git status`）で、そのブランチが WSL 側にある（`git -C ~/dev/em-tech-apps branch --list <branch>`）ことを確認 → `git worktree remove C:\wt\<name>`。作業場の `.git` は `dev/em-tech-apps/.git/worktrees/…` を指しているので、先に改名すると5つとも「git のリポジトリではない」になる
- [ ] Windows側 `dev\em-tech-apps` に `MOVED_TO_WSL.md` を置き `em-tech-apps.old-20260919` に改名
- [ ] `lib/git-sync-status.ps1` の走査から `*.old-*` を除外（改名した写しを「未push 39」と警告し続けないため。段階7の WSL 走査と同じ変更で）
- [ ] 2週間の冷却 → 問題なければ削除（親 CLAUDE.md の手順: node 停止 → GitHub 同期確認 → `Remove-Item`）。判断③
- [ ] apps-platform も同様。`C:\wt\schedule` の残骸も削除

## 段階7: 文書・記憶・自宅PC

- [ ] グローバル `CLAUDE.md`: 「WSL／PowerShell の役割分担」を短く追加。ルール20B に WSL での鍵の扱い、ルール22 に WSL 側の `quotepath`
- [ ] `projects.md`: パスを `~/claude code/...` に。em-tech-apps の行は WSL 側のパス
- [ ] 親 `claude code/CLAUDE.md`: 入口に WSL を追加。em-tech-apps の正本が WSL 側であることを明記
- [ ] `em-tech-apps/CLAUDE.md` 53行目: 「`docker build` は PowerShell で」→「PowerShell または WSL の bash（Git Bash は不可）」
- [ ] `em-tech-apps/CLAUDE.md`「作業場（git worktree）の標準」: `C:\wt\<アプリ名>` → `~/wt/<アプリ名>`、作業場の表を WSL の実態に、`corepack pnpm install` の注記を見直す
- [ ] `lib/git-sync-status.ps1`: WSL 側 `~/dev/*` も `wsl -d Ubuntu -- git -C …` で走査に加える（改名後は em-tech-apps が監視から消えるため）。`weekly-review` の横断検知も同じ
- [ ] `agents/apps-answerer.md`（15行目）・`skills/apps-qa/SKILL.md`: Windows 側のセッションから読むパスを `\\wsl.localhost\Ubuntu\home\m-matsuda\dev\em-tech-apps` に（そのままだと改名した古い写しを読む）
- [ ] `settings.json` の autoMode 本文: 鍵のパスに WSL 表記（`/mnt/c/data/key/...`）を併記
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
| ⑥ | 未追跡9件: PDF2本はコミットか／jpeg 3枚・diff1〜4.txt は削除か | **決定（2026-09-19）**: PDF はコミット、jpeg・diff は削除。ccguide 作業場の `dev.db.bak-20260815` も削除 |
| ⑦ | 既定モデル・effort（settings.json の1本化） | **前提が変わった（2026-09-19）**: Windows 側の正本に `/model` で `claude-fable-5-1[1m]` 既定と opus・fable の xhigh が保存済み。1本化後は両側でこの値が効く。**新機能7件の試用が終わったらルール24へ戻す**（`model` を消し effort を high） |

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
実測済み（2026-09-19 検証で追加）: nvm は非対話シェルで読まれない／ローカルDBは Docker の名前付きボリューム／タスクスケジューラの参照なし／容量・メモリ／フックに Windows 依存なし／記憶リンクが WSL から読める／WSL の claude はログイン済み・MCP 0件／作業場の `.git` が本体の `worktrees/` を指す。
適用時に確認: `.gitattributes` だけで偽差分が消える（根拠＝index 全LF）／読み取り専用の鍵2本への `chmod`／`$HOME` 形式のフックが Windows でも動く（根拠＝既に10本がその形）／WSL から `localhost:<ポート>` で Docker の Postgres に届く（根拠＝WSL2 は全ディストロが同じ仮想マシンの網を使う）／夜間の知見抽出が WSL のログを読める。

## 実行記録

- 2026-09-19 段階0 完了（WSL セッション dfc968a3）。以降は PowerShell 側のセッションで実行。
- 2026-09-19 PowerShell 側セッションで計画を実機と突き合わせ、抜け13件を反映（nvm が非対話で読まれない／`.env` の Windows パス／gitignore 対象の写し／作業場の破損／同期チェック／夜間の知見抽出／Windows 側から読む役／判断⑦の前提／Playwright の root／保険の push／作業場の偽差分／`i/mixed`／判断⑥の決定）。
