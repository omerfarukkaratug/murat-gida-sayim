' MK Baski Programi - CALISTIR.bat'i GORUNMEZ pencerede baslatir (ekranda siyah pencere cikmaz).
' CALISTIR.bat program kapanirsa 15 saniye sonra yeniden baslatir. Sorun ararken DENE.bat kullanilir.
On Error Resume Next
Dim fso, sh, klasor
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
klasor = fso.GetParentFolderName(WScript.ScriptFullName)
If Not fso.FileExists(klasor & "\CALISTIR.bat") Then klasor = "C:\MKBaski"
sh.CurrentDirectory = klasor
sh.Run "cmd.exe /c """ & klasor & "\CALISTIR.bat""", 0, False
