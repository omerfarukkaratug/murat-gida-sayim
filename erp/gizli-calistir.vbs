' KRT Saha: PowerShell scriptini PENCERESIZ calistirir (Gorev Zamanlayici her dakika mavi pencere acmasin).
' Kullanim: wscript.exe //B //Nologo gizli-calistir.vbs "C:\Scripts\dosya.ps1" [arguman ...]
Set sh = CreateObject("WScript.Shell")
Set a = WScript.Arguments
If a.Count = 0 Then WScript.Quit 1
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & a(0) & """"
For i = 1 To a.Count - 1
  cmd = cmd & " " & a(i)
Next
WScript.Quit sh.Run(cmd, 0, True)
