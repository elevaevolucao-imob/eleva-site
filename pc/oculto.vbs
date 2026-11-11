' Roda a sincronizacao sem abrir janela (usado pela tarefa agendada).
Dim pasta
pasta = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & pasta & "\sincronizar.ps1""", 0, False
