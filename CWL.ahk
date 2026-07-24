#Requires AutoHotkey v2.0
#SingleInstance Force
; =====================================================================
;  CWL (Chrome Workspace Launcher) Ver1.0
;  Windows11 上で Chrome の複数プロファイルをワンクリックで
;  起動・配置する AutoHotkey v2 製ランチャー。
;
;  構成モジュール（制作工程票準拠）:
;    ConfigManager  … config.ini 読込・管理
;    ChromeManager  … Chrome自動検出／起動／再利用
;    MonitorManager … モニタ検出・DisplayMode(Auto/外付け優先)
;    LayoutManager  … 比率レイアウト計算(DPI対応)
;    WindowManager  … ウィンドウ移動・配置
;    Logger         … ログ出力
;    ErrorManager   … エラー処理
;  操作: 業務開始 / 業務終了
; =====================================================================

; --- 実行ディレクトリを固定（EXE化時も config.ini を隣から読む） ---
SetWorkingDir(A_ScriptDir)

; --- Per-Monitor DPI Aware V2 に設定（複数DPI環境での座標ずれ防止） ---
try DllCall("SetProcessDpiAwarenessContext", "ptr", -4)  ; DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2

; =====================================================================
;  Logger : ログ出力
; =====================================================================
class Logger {
    file := ""
    enabled := false

    __New(filePath, enabled) {
        this.file := filePath
        this.enabled := enabled
    }

    Write(level, msg) {
        line := FormatTime(, "yyyy-MM-dd HH:mm:ss") . " [" . level . "] " . msg
        if (this.enabled) {
            try FileAppend(line . "`n", this.file, "UTF-8")
        }
        ; GUIステータス欄へも反映
        if (IsSet(App) && App.HasProp("gui") && App.gui)
            App.StatusLog(line)
    }
    Info(msg)  => this.Write("INFO",  msg)
    Warn(msg)  => this.Write("WARN",  msg)
    Error(msg) => this.Write("ERROR", msg)
}

; =====================================================================
;  ErrorManager : エラー処理
; =====================================================================
class ErrorManager {
    log := ""
    __New(logger) => this.log := logger

    ; 致命的エラー: ログに残しダイアログ表示（起動は継続可能な範囲で）
    Fatal(msg) {
        this.log.Error(msg)
        MsgBox(msg, "CWL エラー", "Iconx")
    }
    ; 警告: ログのみ／必要ならトースト的表示
    Warn(msg) {
        this.log.Warn(msg)
    }
    ; 例外を包んで処理
    Guard(fn) {
        try {
            return fn.Call()
        } catch as e {
            this.Fatal("例外: " . e.Message . "`n" . e.What)
            return false
        }
    }
}

; =====================================================================
;  ConfigManager : config.ini 読込・管理
; =====================================================================
class ConfigManager {
    path := ""
    general := Map()
    monitor := Map()
    accounts := []     ; 各要素: Map("Name","Folder","X","Y","W","H")

    __New(iniPath) {
        this.path := iniPath
        if !FileExist(iniPath)
            throw Error("config.ini が見つかりません: " . iniPath)
        this.Load()
    }

    Get(section, key, default := "") {
        return IniRead(this.path, section, key, default)
    }

    Load() {
        ; --- General ---
        this.general["URL"]              := this.Get("General", "URL", "")
        this.general["DisplayMode"]      := this.Get("General", "DisplayMode", "Auto")
        this.general["ChromePath"]       := this.Get("General", "ChromePath", "")
        this.general["LogEnabled"]       := this.Get("General", "LogEnabled", "1") = "1"
        this.general["LogFile"]          := this.Get("General", "LogFile", "CWL.log")
        this.general["WindowWaitMs"]     := Integer(this.Get("General", "WindowWaitMs", "10000"))
        this.general["LaunchIntervalMs"] := Integer(this.Get("General", "LaunchIntervalMs", "800"))

        ; --- Monitor ---
        this.monitor["ExternalMinWidth"] := Integer(this.Get("Monitor", "ExternalMinWidth", "2560"))

        ; --- Accounts（可変） ---
        count := Integer(this.Get("Accounts", "Count", "0"))
        this.accounts := []
        loop count {
            sec := "Account" . A_Index
            acc := Map()
            acc["Name"]   := this.Get(sec, "Name", sec)
            acc["Folder"] := this.Get(sec, "Folder", "Default")
            acc["X"] := this.Num(this.Get(sec, "X", "0"))
            acc["Y"] := this.Num(this.Get(sec, "Y", "0"))
            acc["W"] := this.Num(this.Get(sec, "W", "1"))
            acc["H"] := this.Num(this.Get(sec, "H", "1"))
            this.accounts.Push(acc)
        }
        if (this.accounts.Length = 0)
            throw Error("有効なアカウントが config.ini にありません。")
    }

    ; 文字列→数値（小数）安全変換
    Num(v) {
        return v is Number ? v : Number(v = "" ? 0 : v)
    }
}

; =====================================================================
;  MonitorManager : モニタ検出・DisplayMode
; =====================================================================
class MonitorManager {
    log := ""
    err := ""
    minExternalWidth := 2560

    __New(logger, errmgr, minExternalWidth) {
        this.log := logger
        this.err := errmgr
        this.minExternalWidth := minExternalWidth
    }

    ; 全モニタ情報を配列で返す（作業領域=タスクバー除外）
    List() {
        mons := []
        primary := MonitorGetPrimary()
        loop MonitorGetCount() {
            i := A_Index
            MonitorGetWorkArea(i, &l, &t, &r, &b)
            mons.Push(Map(
                "index", i,
                "left", l, "top", t, "right", r, "bottom", b,
                "width", r - l, "height", b - t,
                "primary", (i = primary)
            ))
        }
        return mons
    }

    ; DisplayMode に応じて配置対象モニタを1つ決定
    Resolve(displayMode) {
        mons := this.List()
        external := this.FindExternal(mons)
        primary  := this.FindPrimary(mons)

        mode := StrLower(displayMode)
        switch mode {
            case "notebook":
                target := primary
                this.log.Info("DisplayMode=Notebook → プライマリ(ノートPC)を使用")
            case "external":
                if (external) {
                    target := external
                    this.log.Info("DisplayMode=External → 外付けモニタを使用")
                } else {
                    target := primary
                    this.err.Warn("外付けモニタ未検出のためノートPCへフォールバック")
                }
            default: ; Auto（外付け優先）
                if (external) {
                    target := external
                    this.log.Info("DisplayMode=Auto → 外付けモニタを使用")
                } else {
                    target := primary
                    this.log.Info("DisplayMode=Auto → 外付け無し、ノートPCを使用")
                }
        }
        this.log.Info(Format("対象モニタ #{1}  {2}x{3}  @({4},{5})",
            target["index"], target["width"], target["height"], target["left"], target["top"]))
        return target
    }

    ; 外付け判定: 幅が閾値以上、かつ複数モニタなら非プライマリを優先
    FindExternal(mons) {
        if (mons.Length <= 1)
            return ""
        candidate := ""
        for m in mons {
            if (!m["primary"] && m["width"] >= this.minExternalWidth)
                return m                       ; 非プライマリ かつ 大画面 = 最有力
            if (m["width"] >= this.minExternalWidth && candidate = "")
                candidate := m
        }
        ; 閾値を満たす非プライマリが無ければ、非プライマリの中で最大を採用
        if (candidate = "") {
            best := ""
            for m in mons {
                if (!m["primary"] && (best = "" || m["width"] > best["width"]))
                    best := m
            }
            candidate := best
        }
        return candidate
    }

    FindPrimary(mons) {
        for m in mons
            if (m["primary"])
                return m
        return mons[1]
    }
}

; =====================================================================
;  LayoutManager : 比率レイアウト計算（DPI対応=物理ピクセル）
; =====================================================================
class LayoutManager {
    ; モニタ作業領域とアカウントの比率から物理ピクセルの矩形を算出
    ; 返り値: Map("x","y","w","h")
    Compute(monitor, acc) {
        x := monitor["left"] + Round(monitor["width"]  * acc["X"])
        y := monitor["top"]  + Round(monitor["height"] * acc["Y"])
        w := Round(monitor["width"]  * acc["W"])
        h := Round(monitor["height"] * acc["H"])
        ; 最低サイズの保証
        w := Max(w, 200)
        h := Max(h, 150)
        return Map("x", x, "y", y, "w", w, "h", h)
    }
}

; =====================================================================
;  ChromeManager : Chrome自動検出／起動／再利用
; =====================================================================
class ChromeManager {
    log := ""
    err := ""
    exePath := ""
    windowWaitMs := 10000

    __New(logger, errmgr, configuredPath, windowWaitMs) {
        this.log := logger
        this.err := errmgr
        this.windowWaitMs := windowWaitMs
        this.exePath := this.Detect(configuredPath)
    }

    ; Chrome実行ファイルを検出（config指定→レジストリ→既定パス）
    Detect(configuredPath) {
        if (configuredPath != "" && FileExist(configuredPath)) {
            this.log.Info("Chrome(config指定): " . configuredPath)
            return configuredPath
        }
        ; レジストリ App Paths
        for hive in ["HKLM", "HKCU"] {
            try {
                p := RegRead(hive . "\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe", "")
                if (p != "" && FileExist(p)) {
                    this.log.Info("Chrome(レジストリ): " . p)
                    return p
                }
            }
        }
        ; 既定インストールパス
        candidates := [
            EnvGet("ProgramFiles") . "\Google\Chrome\Application\chrome.exe",
            EnvGet("ProgramFiles(x86)") . "\Google\Chrome\Application\chrome.exe",
            EnvGet("LocalAppData") . "\Google\Chrome\Application\chrome.exe"
        ]
        for p in candidates {
            if (FileExist(p)) {
                this.log.Info("Chrome(既定パス): " . p)
                return p
            }
        }
        throw Error("Chrome が見つかりません。config.ini の ChromePath を指定してください。")
    }

    ; 現在のChromeウィンドウのHWND一覧
    ChromeWindows() {
        try
            return WinGetList("ahk_exe chrome.exe")
        catch
            return []
    }

    ; 指定プロファイルでURLを新規ウィンドウ起動し、新規HWNDを返す
    Launch(folder, url) {
        before := Map()
        for h in this.ChromeWindows()
            before[h] := true

        ; --profile-directory でプロファイル指定、--new-window で新規ウィンドウ
        cmd := Format('"{1}" --profile-directory="{2}" --new-window "{3}"',
            this.exePath, folder, url)
        this.log.Info("起動: " . folder . "  URL=" . url)
        try Run(cmd)
        catch as e {
            this.err.Fatal("Chrome起動失敗 (" . folder . "): " . e.Message)
            return 0
        }

        ; 新規ウィンドウの出現を待つ
        deadline := A_TickCount + this.windowWaitMs
        while (A_TickCount < deadline) {
            Sleep(200)
            for h in this.ChromeWindows() {
                if (!before.Has(h)) {
                    ; タイトルが付くまで（描画開始まで）少し待つ
                    try {
                        if (WinGetTitle("ahk_id " . h) != "")
                            return h
                    }
                }
            }
        }
        this.err.Warn("新規ウィンドウを検出できませんでした (" . folder . ")")
        return 0
    }

    ; 業務URLを開いている既存Chromeウィンドウ（再利用候補）を返す
    ExistingWorkWindows(titleKeyword) {
        result := []
        for h in this.ChromeWindows() {
            try {
                t := WinGetTitle("ahk_id " . h)
                if (titleKeyword = "" || InStr(t, titleKeyword))
                    result.Push(h)
            }
        }
        return result
    }
}

; =====================================================================
;  WindowManager : ウィンドウ移動・配置
; =====================================================================
class WindowManager {
    log := ""
    __New(logger) => this.log := logger

    ; HWNDを指定矩形へ配置（最大化解除→移動→最前面化）
    Place(hwnd, rect) {
        if (!hwnd || !WinExist("ahk_id " . hwnd))
            return false
        try {
            ; 最大化されていると移動できないため通常状態へ
            if (WinGetMinMax("ahk_id " . hwnd) != 0)
                WinRestore("ahk_id " . hwnd)
            WinMove(rect["x"], rect["y"], rect["w"], rect["h"], "ahk_id " . hwnd)
            WinActivate("ahk_id " . hwnd)
            this.log.Info(Format("配置: HWND={1} → ({2},{3}) {4}x{5}",
                hwnd, rect["x"], rect["y"], rect["w"], rect["h"]))
            return true
        } catch as e {
            this.log.Warn("配置失敗 HWND=" . hwnd . " : " . e.Message)
            return false
        }
    }

    Close(hwnd) {
        try {
            if (WinExist("ahk_id " . hwnd)) {
                WinClose("ahk_id " . hwnd)
                return true
            }
        }
        return false
    }
}

; =====================================================================
;  App : 全体制御 + GUI（業務開始 / 業務終了）
; =====================================================================
class App {
    static config := ""
    static log := ""
    static err := ""
    static monitor := ""
    static layout := ""
    static chrome := ""
    static window := ""
    static gui := ""
    static statusCtrl := ""
    static managedWindows := []   ; 起動/再利用したHWND

    static Init() {
        iniPath := A_ScriptDir . "\config.ini"

        ; ConfigManager
        this.config := ConfigManager(iniPath)
        ; Logger / ErrorManager
        this.log := Logger(A_ScriptDir . "\" . this.config.general["LogFile"],
                           this.config.general["LogEnabled"])
        this.err := ErrorManager(this.log)
        this.log.Info("===== CWL Ver1.0 起動 =====")

        ; 各Manager
        this.monitor := MonitorManager(this.log, this.err,
                                       this.config.monitor["ExternalMinWidth"])
        this.layout  := LayoutManager()
        this.chrome  := ChromeManager(this.log, this.err,
                                      this.config.general["ChromePath"],
                                      this.config.general["WindowWaitMs"])
        this.window  := WindowManager(this.log)

        this.BuildGui()
    }

    ; --- GUI構築 ---
    static BuildGui() {
        g := Gui("+Resize", "CWL - Chrome Workspace Launcher")
        g.SetFont("s10", "Meiryo UI")
        g.AddText("w360", "アカウント数: " . this.config.accounts.Length
                        . "  /  DisplayMode: " . this.config.general["DisplayMode"])
        btnStart := g.AddButton("w170 h44", "業務開始")
        btnEnd   := g.AddButton("x+20 yp w170 h44", "業務終了")
        btnStart.OnEvent("Click", (*) => this.Start())
        btnEnd.OnEvent("Click", (*) => this.End())
        this.statusCtrl := g.AddEdit("xm w360 r10 +ReadOnly +VScroll")
        g.OnEvent("Close", (*) => ExitApp())
        this.gui := g
        g.Show("AutoSize")

        ; トレイメニュー
        A_TrayMenu.Delete()
        A_TrayMenu.Add("業務開始", (*) => this.Start())
        A_TrayMenu.Add("業務終了", (*) => this.End())
        A_TrayMenu.Add()
        A_TrayMenu.Add("ウィンドウ表示", (*) => this.gui.Show())
        A_TrayMenu.Add("終了", (*) => ExitApp())
        A_TrayMenu.Default := "ウィンドウ表示"
    }

    static StatusLog(line) {
        if (this.statusCtrl)
            this.statusCtrl.Value .= line . "`r`n"
    }

    ; --- 業務開始: 各アカウントを起動/再利用し比率配置 ---
    static Start() {
        this.err.Guard(() => this._Start())
    }
    static _Start() {
        url := this.config.general["URL"]
        target := this.monitor.Resolve(this.config.general["DisplayMode"])
        interval := this.config.general["LaunchIntervalMs"]

        ; 再利用: 業務URLを開いている既存ウィンドウを収集（KSASキーワード）
        reuse := this.chrome.ExistingWorkWindows("KSAS")
        reuseIdx := 1
        this.managedWindows := []

        accounts := this.config.accounts
        for acc in accounts {
            rect := this.layout.Compute(target, acc)
            hwnd := 0

            if (reuseIdx <= reuse.Length) {
                ; 既存ウィンドウを再利用
                hwnd := reuse[reuseIdx]
                reuseIdx += 1
                this.log.Info("再利用: " . acc["Name"] . " (HWND=" . hwnd . ")")
            } else {
                ; 新規起動
                hwnd := this.chrome.Launch(acc["Folder"], url)
                Sleep(interval)
            }

            if (hwnd) {
                this.window.Place(hwnd, rect)
                this.managedWindows.Push(hwnd)
            } else {
                this.err.Warn("配置対象ウィンドウ無し: " . acc["Name"])
            }
        }
        this.log.Info("業務開始 完了（" . accounts.Length . " アカウント）")
    }

    ; --- 業務終了: 管理下のウィンドウを閉じる ---
    static End() {
        this.err.Guard(() => this._End())
    }
    static _End() {
        ; 管理下ウィンドウ + 業務URLウィンドウを対象に
        targets := Map()
        for h in this.managedWindows
            targets[h] := true
        for h in this.chrome.ExistingWorkWindows("KSAS")
            targets[h] := true

        if (targets.Count = 0) {
            this.log.Info("業務終了: 閉じる対象がありません")
            return
        }
        if (MsgBox("業務用ウィンドウ " . targets.Count . " 件を閉じます。よろしいですか？",
                   "業務終了の確認", "YesNo Icon?") != "Yes") {
            this.log.Info("業務終了: ユーザーによりキャンセル")
            return
        }
        closed := 0
        for h in targets {
            if (this.window.Close(h))
                closed += 1
        }
        this.managedWindows := []
        this.log.Info("業務終了 完了（" . closed . " ウィンドウを閉じました）")
    }
}

; =====================================================================
;  エントリポイント
; =====================================================================
try {
    App.Init()
} catch as e {
    MsgBox("初期化に失敗しました:`n" . e.Message, "CWL 起動エラー", "Iconx")
    ExitApp()
}
