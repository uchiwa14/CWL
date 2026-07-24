# CWL (Chrome Workspace Launcher) Ver1.0 仕様書

## プロジェクト概要
Windows11上でChromeの複数プロファイルをワンクリックで起動・配置するAutoHotkey v2製ランチャー。

## 開発条件
- AutoHotkey v2のみ
- config.iniで全設定管理
- EXE化可能
- 日本語コメント

## 現在の環境
- ノートPC:1920x1080
- 外付け:3280x2160
- 通常は画面2のみ
- 外付けが無ければノートへ自動切替

## Chrome
|論理名|Folder|表示名|
|---|---|---|
|Account1|Default|直仁|
|Account2|Profile 6|NAS|
|Account3|Profile 8|モニタ001|

URL:
https://ksas.kubota.co.jp/ksas/farming/users/login

## 必須機能
1. config.ini読込
2. Chrome自動検出
3. Account数可変
4. DisplayMode=Auto
5. 外付け優先
6. 比率レイアウト
7. DPI対応
8. 起動済み再利用
9. ログ
10. エラー処理
11. 業務開始/業務終了

## config.ini方針
Accountを追加するだけで将来拡張可能。
