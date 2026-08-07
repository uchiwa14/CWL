# CWL Ver1.0 設計書

## 1. 目的
この設計書は、`CWL.ahk` と `config.ini` から実装内容を整理し、今後の保守・拡張を容易にするための構造を定義する。

## 2. 設計方針
- すべての設定を `config.ini` に集約する
- UI 操作と実行ロジックを分離し、`App` クラスで全体を制御する
- 各責務をモジュール単位で分け、独立性を高める
- 既存の Chrome ウィンドウを再利用して起動時間を短縮する

## 3. アーキテクチャ
CWL は単一の AutoHotkey スクリプトとして実装され、以下の責務分担で構成される。

- `Logger`: 実行ログの生成と GUI ステータス欄への反映
- `ErrorManager`: エラーの統一処理とメッセージボックス通知
- `ConfigManager`: `config.ini` の読み込みとパース
- `MonitorManager`: モニタ一覧取得と対象モニタ決定
- `LayoutManager`: モニタ作業領域とレイアウト比率から矩形を計算
- `ChromeManager`: Chrome 実行ファイル検出、起動、再利用候補収集
- `WindowManager`: ウィンドウ移動・配置・終了
- `App`: GUI 構築と業務開始/終了のオーケストレーション

## 4. モジュール詳細
### 4.1 ConfigManager
- 入力: `config.ini` のパス
- 出力: `general`, `monitor`, `accounts` を保持した状態
- 主な処理:
  - `[General]`, `[Monitor]`, `[Accounts]`, `[AccountN]` の読み取り
  - `Count` とアカウントセクション数の整合確認（不足・余剰セクションの厳密な検出とエラー処理）
  - 各設定項目（X, Y, W, H等）の不正値バリデーション
  - 不整合や不正値が検出された場合は直ちにエラーをスローし、起動を停止する
  - 数値変換（`X/Y/W/H`）

### 4.2 Logger / ErrorManager
- 実行ログは `LogEnabled=1` の場合にファイルへ追記する
- GUI のステータス欄へも同時出力する
- AutoHotkey v2のクラスプロパティに対する未定義（unset）チェックは `HasProp()` などの適切なメソッド・判定を使用し、エラーを防ぐ。
- 例外処理は `ErrorManager.Guard()` で統一する

### 4.3 MonitorManager
- `MonitorGetCount()` と `MonitorGetWorkArea()` を使って全モニタ情報を収集する
- `DisplayMode` に応じて、外付けモニタまたはプライマリモニタを選択する
- `ExternalMinWidth` を基準に外付けモニタ判定を行う

### 4.4 LayoutManager
- `Compute(monitor, acc)` により、各アカウントごとの矩形を返す
- 返却値は `Map("x", ..., "y", ..., "w", ..., "h", ...)`
- 最低サイズ 200x150 を保証する
- 画面外への配置や設定ミスによる異常な比率を検知し、作業領域内に収まるよう座標とサイズをクランプ（補正）する

### 4.5 ChromeManager
- Chrome 実行パスを以下の優先順位で検出する
  1. `config.ini` の `ChromePath`
  2. レジストリ `App Paths\chrome.exe`
  3. 既定インストール先
- `Launch(folder, url)` では `--profile-directory` と `--new-window` を指定して起動する
- `ExistingWorkWindows(url, profile)` により、業務 URL かつ対象プロファイルの再利用候補ウィンドウの HWND を取得し、`account -> hwnd` の対応を明示的に収集する

### 4.6 WindowManager
- `Place(hwnd, rect)` でウィンドウを移動・サイズ変更・アクティブ化する
- `Close(hwnd)` で対象ウィンドウを閉じる
- 最大化状態の場合は `WinRestore()` で通常状態へ戻す

### 4.7 App
- `Init()` で各モジュールを初期化する
- `BuildGui()` で GUI を構築し、トレイメニューを登録する
- `Start()` / `End()` が業務フロー全体を制御する

## 5. データ構造
### 5.1 設定データ
`ConfigManager` は次の構造を保持する。

- `general`: URL, DisplayMode, ChromePath, LogEnabled, LogFile, WindowWaitMs, LaunchIntervalMs, ExternalMinWidth
- `accounts`: 各アカウントの `Name`, `Folder`, `X`, `Y`, `W`, `H`

### 5.2 実行時データ
- `managedWindows`: 業務開始時に配置・制御したウィンドウの HWND
- `statusCtrl`: GUI のログ表示用コントロール

## 6. 処理フロー
### 6.1 業務開始フロー
1. `App.Init()` で設定・ログ・各モジュールを初期化する
2. `App.Start()` が呼び出される
3. `MonitorManager.Resolve()` により対象モニタを決定する
4. `ChromeManager.ExistingWorkWindows()` で再利用候補を取得する
5. 各アカウントについて、既存ウィンドウがあれば再利用し、なければ新規起動する
6. `LayoutManager.Compute()` で矩形を算出し、`WindowManager.Place()` で配置する
7. すべての結果をログへ記録する

### 6.2 業務終了フロー
1. `App.End()` が呼び出される
2. 起動時に配置・制御した `managedWindows` を収集する
3. 確認ダイアログ（終了対象ウィンドウ一覧を含む）を表示する
4. 承認時に `WindowManager.Close()` を呼び、対象ウィンドウを閉じる

## 7. エラー処理設計
- エラー分類を明確化し、例外を適切に処理する
- `ErrorManager.Fatal()` は致命的エラーをログに残し、処理を停止してダイアログで通知する
- `ErrorManager.Warn()` は処理を継続可能な軽微な失敗に対して警告ログを残す
- `ErrorManager.Info()` は状態の変化や成功を情報ログとして残す
- `ErrorManager.Guard()` で `fn.Call()` を実行し、例外発生時に統一収束する

## 8. 実装ファイル構成
- `CWL.ahk`: 全体実装
- `config.ini`: 設定値
- `doc/CWL_仕様書.md`: 仕様書
- `doc/CWL_設計書.md`: 設計書
- `README.md`: 利用手順

## 9. 拡張方針
- アカウント追加は `[Accounts]` の `Count` と `[AccountN]` セクションを増やすだけで対応可能
- モニタ判定条件は `ExternalMinWidth` で変更可能
- ログ出力は `LogEnabled` と `LogFile` で制御可能
