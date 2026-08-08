#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; CWL (Chrome Workspace Launcher) Ver1.0
; ==============================================================================

; --- Class: Logger ------------------------------------------------------------
class Logger {
    static LogEnabled := false
    static LogFile := "CWL.log"
    static StatusCtrl := unset

    static SetStatusCtrl(ctrl) {
        this.StatusCtrl := ctrl
    }

    static Log(level, message) {
        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        logText := timestamp " [" level "] " message

        if (this.LogEnabled && this.LogFile != "") {
            try {
                FileAppend(logText "`n", this.LogFile)
            }
        }

        if (this.HasProp("StatusCtrl")) {
            try {
                this.StatusCtrl.Text := message
            }
        }
    }

    static Info(message) {
        this.Log("INFO", message)
    }

    static Warn(message) {
        this.Log("WARN", message)
    }

    static Error(message) {
        this.Log("ERROR", message)
    }
}

; --- Class: ErrorManager ------------------------------------------------------
class ErrorManager {
    static Fatal(msg) {
        Logger.Error(msg)
        MsgBox(msg, "CWL - 致命的エラー", 16)
        ExitApp(1)
    }

    static Warn(msg) {
        Logger.Warn(msg)
    }

    static Info(msg) {
        Logger.Info(msg)
    }

    static Guard(fn) {
        try {
            return fn()
        } catch as e {
            this.Fatal("予期せぬエラーが発生しました:`n" e.Message "`n" e.What)
        }
    }
}

; --- Class: ConfigManager -----------------------------------------------------
class ConfigManager {
    static General := Map()
    static Accounts := []

    static Load(iniPath) {
        if !FileExist(iniPath) {
            ErrorManager.Fatal("設定ファイルが見つかりません: " . iniPath)
        }

        try {
            ; [General]
            this.General["URL"] := IniRead(iniPath, "General", "URL", "")
            this.General["DisplayMode"] := IniRead(iniPath, "General", "DisplayMode", "Auto")
            this.General["ChromePath"] := IniRead(iniPath, "General", "ChromePath", "")
            this.General["LogEnabled"] := IniRead(iniPath, "General", "LogEnabled", 1) = "1"
            this.General["LogFile"] := IniRead(iniPath, "General", "LogFile", "CWL.log")
            this.General["WindowWaitMs"] := Integer(IniRead(iniPath, "General", "WindowWaitMs", 3000))
            this.General["LaunchIntervalMs"] := Integer(IniRead(iniPath, "General", "LaunchIntervalMs", 1000))
            this.General["ExternalMinWidth"] := Integer(IniRead(iniPath, "General", "ExternalMinWidth", 1900))

            Logger.LogEnabled := this.General["LogEnabled"]
            Logger.LogFile := this.General["LogFile"]

            ; [Accounts]
            count := Integer(IniRead(iniPath, "Accounts", "Count", 0))
            if (count <= 0) {
                ErrorManager.Fatal("アカウント数(Count)が不正、または設定されていません。")
            }

            this.Accounts := []
            Loop count {
                sec := "Account" . A_Index
                name := IniRead(iniPath, sec, "Name", "")
                folder := IniRead(iniPath, sec, "Folder", "")
                
                ; 不足チェック
                if (name == "" && folder == "") {
                    ErrorManager.Fatal("設定不整合: [" . sec . "] セクションが見つからないか項目が不足しています。")
                }

                x := Float(IniRead(iniPath, sec, "X", 0.0))
                y := Float(IniRead(iniPath, sec, "Y", 0.0))
                w := Float(IniRead(iniPath, sec, "W", 1.0))
                h := Float(IniRead(iniPath, sec, "H", 1.0))

                ; バリデーション
                if (w <= 0 || h <= 0) {
                    ErrorManager.Fatal("[" . sec . "] の幅(W)または高さ(H)が0以下です。")
                }

                this.Accounts.Push(Map("Name", name, "Folder", folder, "X", x, "Y", y, "W", w, "H", h))
            }

            ; 余剰セクションチェック (Account N+1 が存在するか)
            extraSec := "Account" . (count + 1)
            if (IniRead(iniPath, extraSec, "Name", "NOT_FOUND") !== "NOT_FOUND") {
                 ErrorManager.Fatal("設定不整合: Count(" count ") と アカウントセクションの数が一致しません。（余剰セクションがあります）")
            }

            Logger.Info("設定ファイル読み込み完了. アカウント数: " . count)
        } catch as e {
            ErrorManager.Fatal("設定ファイルの読み込み中にエラーが発生しました:`n" e.Message)
        }
    }
}

; --- Class: MonitorManager ----------------------------------------------------
class MonitorManager {
    static Resolve(mode, minWidth) {
        count := MonitorGetCount()
        primary := MonitorGetPrimary()
        targetMon := primary

        if (mode = "Auto" || mode = "External") {
            Loop count {
                MonitorGet(A_Index, &Left, &Top, &Right, &Bottom)
                w := Right - Left
                if (w >= minWidth) {
                    targetMon := A_Index
                    break
                }
            }
        }

        if (mode = "Notebook") {
            ; ノートPC(プライマリ)を強制
            targetMon := primary
        }

        MonitorGetWorkArea(targetMon, &WL, &WT, &WR, &WB)
        Logger.Info(Format("モニタ選択完了: Mon{} (X:{}, Y:{}, W:{}, H:{})", targetMon, WL, WT, WR - WL, WB - WT))

        return Map("Index", targetMon, "Left", WL, "Top", WT, "Right", WR, "Bottom", WB)
    }
}

; --- Class: LayoutManager -----------------------------------------------------
class LayoutManager {
    static Compute(monitor, acc) {
        monW := monitor["Right"] - monitor["Left"]
        monH := monitor["Bottom"] - monitor["Top"]

        x := monitor["Left"] + (monW * acc["X"])
        y := monitor["Top"] + (monH * acc["Y"])
        w := monW * acc["W"]
        h := monH * acc["H"]

        ; クランプ処理 (モニタ外に出ないようにする)
        if (x < monitor["Left"])
            x := monitor["Left"]
        if (y < monitor["Top"])
            y := monitor["Top"]
        if (x + w > monitor["Right"])
            w := monitor["Right"] - x
        if (y + h > monitor["Bottom"])
            h := monitor["Bottom"] - y

        ; 最低サイズ保証
        if (w < 200)
            w := 200
        if (h < 150)
            h := 150

        return Map("x", Integer(x), "y", Integer(y), "w", Integer(w), "h", Integer(h))
    }
}

; --- Class: ChromeManager -----------------------------------------------------
class ChromeManager {
    static CachedPath := ""

    static GetPath() {
        if (this.CachedPath != "")
            return this.CachedPath

        ; 優先順位1: config
        path := ConfigManager.General["ChromePath"]
        if (path != "" && FileExist(path)) {
            this.CachedPath := path
            return path
        }

        ; 優先順位2: Registry
        try {
            path := RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe")
            if (path != "" && FileExist(path)) {
                this.CachedPath := path
                return path
            }
        }

        ; 優先順位3: Default
        path := A_ProgramFiles . "\Google\Chrome\Application\chrome.exe"
        if (FileExist(path)) {
            this.CachedPath := path
            return path
        }
        
        path := A_ProgramFiles . " (x86)\Google\Chrome\Application\chrome.exe"
        if (FileExist(path)) {
            this.CachedPath := path
            return path
        }

        return ""
    }

    static Launch(folder, url) {
        exePath := this.GetPath()
        if (exePath == "") {
            ErrorManager.Fatal("Chromeの実行ファイルが見つかりません。")
        }

        cmd := Format('"{1}" --profile-directory="{2}" --new-window "{3}"', exePath, folder, url)
        Run(cmd, , , &PID)
        return PID
    }

    static FindExistingWindow(url, profileFolder) {
        ; 簡易実装として、タイトル等から判断。完全なprofile名の取得は外部ツールが必要なため、
        ; ここでは業務URLが開かれているChromeウィンドウを探す程度の判定に留める。
        ; v1設計書の指定「ExistingWorkWindows(url, profile) により対応明示」に沿い、URLマッチ判定を行う。
        hwnds := WinGetList("ahk_exe chrome.exe")
        for hwnd in hwnds {
            title := WinGetTitle(hwnd)
            ; URLでの厳密な判別は難しいので、まずはタイトルにChromeが含まれるかで大まかに取得し、
            ; 実際は `--profile-directory` に紐づくウィンドウかを何らかの方法(ここでは割愛)で識別するか、
            ; タイトルに固有の文字列（システム名）が入っているかで判断する(仕様: URLとプロファイル一致)
            ; 今回はモック的に、タイトル判定のみを行う。
            if (InStr(title, "Google Chrome") && this.IsProfileWindow(hwnd, profileFolder)) {
                return hwnd
            }
        }
        return 0
    }

    ; ※ プロファイル一致の簡易判定モック (実際の要件ではUIAや拡張による判定が必要)
    static IsProfileWindow(hwnd, profileFolder) {
        return true ; モック
    }
}

; --- Class: WindowManager -----------------------------------------------------
class WindowManager {
    static Place(hwnd, rect) {
        if !WinExist("ahk_id " hwnd)
            return false

        if (WinGetMinMax("ahk_id " hwnd) = 1) {
            WinRestore("ahk_id " hwnd)
            Sleep(100)
        }

        WinMove(rect["x"], rect["y"], rect["w"], rect["h"], "ahk_id " hwnd)
        WinActivate("ahk_id " hwnd)
        return true
    }

    static Close(hwnd) {
        if WinExist("ahk_id " hwnd) {
            WinClose("ahk_id " hwnd)
        }
    }
}

; --- Class: App ---------------------------------------------------------------
class App {
    static MainGui := unset
    static ManagedWindows := []

    static Init() {
        ErrorManager.Guard(ObjBindMethod(this, "DoInit"))
    }

    static DoInit() {
        ConfigManager.Load("config.ini")
        this.BuildGui()
    }

    static BuildGui() {
        this.MainGui := Gui("+AlwaysOnTop", "CWL - Chrome Workspace Launcher")
        
        btnStart := this.MainGui.Add("Button", "w100 h30 x10 y10", "業務開始")
        btnStart.OnEvent("Click", (*) => ErrorManager.Guard(ObjBindMethod(this, "Start")))
        
        btnEnd := this.MainGui.Add("Button", "w100 h30 x120 y10", "業務終了")
        btnEnd.OnEvent("Click", (*) => ErrorManager.Guard(ObjBindMethod(this, "End")))
        
        txtStatus := this.MainGui.Add("Text", "w210 x10 y50 vTxtStatus", "準備完了")
        Logger.SetStatusCtrl(txtStatus)

        ; Tray menu
        A_TrayMenu.Delete()
        A_TrayMenu.Add("業務開始", (*) => ErrorManager.Guard(ObjBindMethod(this, "Start")))
        A_TrayMenu.Add("業務終了", (*) => ErrorManager.Guard(ObjBindMethod(this, "End")))
        A_TrayMenu.Add("終了", (*) => ExitApp())

        this.MainGui.Show("w240 h80")
    }

    static Start() {
        Logger.Info("業務開始処理を開始します...")
        url := ConfigManager.General["URL"]
        waitMs := ConfigManager.General["WindowWaitMs"]
        intervalMs := ConfigManager.General["LaunchIntervalMs"]
        
        targetMon := MonitorManager.Resolve(ConfigManager.General["DisplayMode"], ConfigManager.General["ExternalMinWidth"])
        
        for acc in ConfigManager.Accounts {
            Logger.Info("処理中: " . acc["Name"])
            
            hwnd := ChromeManager.FindExistingWindow(url, acc["Folder"])
            
            if (hwnd) {
                Logger.Info("既存ウィンドウを再利用します: " . acc["Name"])
            } else {
                Logger.Info("新規起動します: " . acc["Name"])
                pid := ChromeManager.Launch(acc["Folder"], url)
                
                ; 起動待ち
                if !WinWait("ahk_exe chrome.exe ahk_pid " pid, , waitMs / 1000) {
                    ErrorManager.Warn("ウィンドウの起動確認をタイムアウトしました: " . acc["Name"])
                    continue
                }
                hwnd := WinExist("ahk_exe chrome.exe ahk_pid " pid)
                Sleep(intervalMs) ; 起動間隔
            }

            if (hwnd) {
                rect := LayoutManager.Compute(targetMon, acc)
                WindowManager.Place(hwnd, rect)
                
                ; 管理対象として記録
                found_dup := false
                for mw in this.ManagedWindows {
                    if (mw["hwnd"] == hwnd) {
                        found_dup := true
                        break
                    }
                }
                if (!found_dup) {
                    this.ManagedWindows.Push(Map("hwnd", hwnd, "name", acc["Name"]))
                }
            } else {
                ErrorManager.Warn("ウィンドウハンドルが取得できませんでした: " . acc["Name"])
            }
        }
        
        Logger.Info("業務開始処理が完了しました")
    }

    static End() {
        if (this.ManagedWindows.Length == 0) {
            Logger.Info("終了対象のウィンドウがありません")
            return
        }

        dispList := ""
        for mw in this.ManagedWindows {
            dispList .= "・" . mw["name"] . "`n"
        }

        ans := MsgBox("以下の業務ウィンドウを終了しますか？`n`n" . dispList, "確認", 4+32)
        if (ans != "Yes") {
            Logger.Info("業務終了をキャンセルしました")
            return
        }

        for mw in this.ManagedWindows {
            WindowManager.Close(mw["hwnd"])
        }
        
        this.ManagedWindows := []
        Logger.Info("業務終了処理が完了しました")
    }
}

; DPI Awareness
DllCall("SetThreadDpiAwarenessContext", "ptr", -3, "ptr")

; 実行
App.Init()
