# CWL
CWL (Chrome Workspace Launcher) 


## config.iniの注意
`Name`と`Folder`は環境に合わせて修正

### Default プロファイルについて
Profile_DefaultプロファイルにてChromeを起動し
アドレスバーに`chrome://version/`を入力実行。

![Chrome_ProfilePath_Default_確認.png](img\Chrome_ProfilePath_Default_確認.png)
プロフィール パス（Profile Path）	C:\Users\XXX\AppData\Local\Google\Chrome\User Data\Default

```[Account1]
Name=Default_Profile_Name
Folder=Default
```

### その他プロファイルについて
Profile_Name01プロファイルにてChromeを起動し
アドレスバーに`chrome://version/`を入力実行。

![Chrome_ProfilePath_確認.png](img\Chrome_ProfilePath_8_確認.png)
プロフィール パス（Profile Path）	C:\Users\XXX\AppData\Local\Google\Chrome\User Data\Profile **8**

プロフィール パスの数値**８**を確認し

```[Account2]
Name=Profile_Name01
Folder=Profile 8
```
