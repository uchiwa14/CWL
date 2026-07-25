# CWL
CWL (Chrome Workspace Launcher)

CWL は、Google Chrome の複数プロファイルを業務開始時にまとめて起動し、指定したモニタ上に自動配置する AutoHotkey v2 製ランチャーです。業務終了時には管理対象のウィンドウをまとめて閉じ、日々の作業を効率化します。

## この README でわかること
- 何をするツールか
- 必要な環境と準備
- `config.ini` の設定方法
- Chrome プロファイルの確認手順
- 使い方と操作手順
- トラブルシューティング

## 主な機能
- 複数 Chrome プロファイルを同時に起動/再利用
- 画面の指定した位置・サイズにウィンドウを配置
- 外付けモニタ／ノート PC の選択
- 起動と終了を GUI で簡単操作
- ログ出力による動作確認

## 事前準備
- AutoHotkey v2.0 がインストールされていること
- Google Chrome がインストールされていること
- 使用する Chrome プロファイルの「プロフィール パス（Profile Path）」を確認しておくこと

> AutoHotkey v2.0 は公式サイトから入手してください。`CWL.ahk` は v2 構文で記述されています。

## config.ini の基本構成
`config.ini` に `General` と `Accounts` の項目を設定します。以下は最小構成の例です。

```ini
[General]
URL=https://example.com/
DisplayMode=Auto
ChromePath=
LogEnabled=1
LogFile=CWL.log
WindowWaitMs=10000
LaunchIntervalMs=800
ExternalMinWidth=1920

[Accounts]
Count=2

[Account1]
Name=Default_Profile
Folder=Default
X=0.0
Y=0.0
W=1.0
H=0.5

[Account2]
Name=Profile_8
Folder=Profile 8
X=0.0
Y=0.5
W=1.0
H=0.5
```

### 重要なポイント
- `Name`: 表示用の名前です。GUI 上やログに表示されます。
- `Folder`: Chrome の実際のプロファイルディレクトリ名です。`--profile-directory` にそのまま渡されます。
- `Folder` には Chrome の表示名ではなく、パス末尾のディレクトリ名を使います。
- `X` / `Y` / `W` / `H`: 0.0〜1.0 の比率で指定し、モニタ上の表示位置とサイズを決めます。
- `Count`: `Account1`〜`AccountN` の実際の数と合わせます。
- `ExternalMinWidth`: 外付けモニタと判定する横幅の閾値です。`DisplayMode=Auto` の場合に使用されます。

## Chrome プロファイルパスの確認方法
1. 対象の Chrome プロファイルを起動します。
2. アドレスバーに `chrome://version/` を入力して開きます。
3. 「Profile Path」欄の末尾を確認します。

### Default プロファイル
`Profile Path` が次のような場合、`Folder` は `Default` です。

`C:\Users\XXX\AppData\Local\Google\Chrome\User Data\Default`

```ini
[Account1]
Name=Default_Profile
Folder=Default
```

### その他プロファイル
`Profile Path` が次のような場合、`Folder` は `Profile 8` です。

`C:\Users\XXX\AppData\Local\Google\Chrome\User Data\Profile 8`

```ini
[Account2]
Name=Profile_8
Folder=Profile 8
```

> 画像が表示されない環境でも、本手順通りに確認してください。

## 使い方
1. `CWL.ahk` をダブルクリックするか、AutoHotkey から実行します。
2. GUI が表示されたら、`業務開始` をクリックします。
   - 指定したプロファイルの Chrome を起動/再利用し、設定した位置とサイズで配置します。
3. 作業が終わったら、`業務終了` をクリックします。
   - 管理対象のウィンドウをまとめて閉じる確認ダイアログが表示されます。

### 実行時の挙動
- `ChromePath` が空欄の場合は、自動検出を試みます。
- 既に起動済みのプロファイルがある場合は再利用します。
- 起動したウィンドウが指定時間内に見つからない場合、`WindowWaitMs` を延長してください。

## トラブルシューティング
- Chrome が見つからない
  - `ChromePath` に Chrome 実行ファイルのフルパスを設定してください。
  - 例: `C:\Program Files\Google\Chrome\Application\chrome.exe`
- 新しいウィンドウが出現しない
  - `WindowWaitMs` を大きめに設定します。
  - 起動済みプロファイルに別ウィンドウが存在する場合、再利用制御で待機することがあります。
- 誤ったプロファイルが開く
  - `Folder` の値が `chrome://version/` の `Profile Path` と一致しているか確認します。
  - 同じ Chrome プロファイル名が複数ある場合は、ディレクトリ名を正確に指定してください。
- 配置位置が意図どおりでない
  - `X` / `Y` / `W` / `H` の比率を調整してください。
  - 複数モニタ環境では `DisplayMode` と `ExternalMinWidth` の設定を見直してください。
- ログを確認したい
  - `LogEnabled=1` にして `LogFile` を開き、実行結果やエラーを確認します。
- GUI を閉じてもプロセスが残る
  - Chrome のプロセスは Chrome 自体が管理します。`業務終了` 後に残るウィンドウがある場合は、ログを確認してください。

## 追加の注意
- `config.ini` の記述ミスがあると正しく動作しません。`Count` の数と `[AccountX]` セクション数は必ず一致させてください。
- `ChromePath` を指定する場合は、`chrome.exe` まで含めたパスを入力してください。
- 本ツールは AutoHotkey v2 用です。v1 では動作しません。

## 連絡先
- リポジトリ管理者に問い合わせる場合は、README の配布元または `CWL.制作工程票.md` を確認してください。

