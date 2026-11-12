# Instalacao (uma vez): baixa o projeto, cria a pasta SITE ELEVA na Area de Trabalho e agenda a publicacao automatica.
$ErrorActionPreference = 'Stop'
$Base = Join-Path $env:LOCALAPPDATA 'ElevaSite'
$Repo = Join-Path $Base 'repo'
$Pasta = Join-Path ([Environment]::GetFolderPath('Desktop')) 'SITE ELEVA'
$Fonte = Join-Path $Pasta 'IMOVEIS'
New-Item -ItemType Directory -Force -Path $Base | Out-Null
$ErrorActionPreference = 'Continue'
if (-not (Test-Path (Join-Path $Repo '.git'))) {
    git clone --quiet --branch conteudo --single-branch https://github.com/elevaevolucao-imob/eleva-site.git $Repo 2>&1 | ForEach-Object { "$_" }
} else {
    git -C $Repo fetch --quiet origin conteudo 2>&1 | ForEach-Object { "$_" }
    git -C $Repo reset --quiet --hard origin/conteudo 2>&1 | ForEach-Object { "$_" }
}
git -C $Repo config core.longpaths true
git -C $Repo config core.autocrlf false
git -C $Repo config user.name "Eleva (computador)"
git -C $Repo config user.email "site@users.noreply.github.com"
$ErrorActionPreference = 'Stop'
if (-not (Test-Path (Join-Path $Repo 'pc\sincronizar.ps1'))) { throw 'Nao foi possivel baixar o projeto.' }

New-Item -ItemType Directory -Force -Path $Pasta | Out-Null
if (-not (Test-Path $Fonte)) {
    Copy-Item -LiteralPath (Join-Path $Repo 'imoveis') -Destination $Fonte -Recurse
    "Pasta IMOVEIS criada com os empreendimentos que ja estao no site."
} else { "A pasta IMOVEIS ja existia; nada foi sobrescrito." }
$modelo = Join-Path $Fonte '_MODELO (copie esta pasta)'
New-Item -ItemType Directory -Force -Path $modelo | Out-Null
Copy-Item -LiteralPath (Join-Path $Repo 'pc\modelo-descricao.txt') -Destination (Join-Path $modelo 'descricao.txt') -Force
New-Item -ItemType Directory -Force -Path (Join-Path $Fonte '_VENDIDOS (fora do site)') | Out-Null
Copy-Item -LiteralPath (Join-Path $Repo 'pc\COMO USAR.txt') -Destination (Join-Path $Pasta 'COMO USAR.txt') -Force
Copy-Item -LiteralPath (Join-Path $Repo 'pc\PUBLICAR AGORA.bat') -Destination (Join-Path $Pasta 'PUBLICAR AGORA.bat') -Force

$cfg = '{"pasta": ' + ($Pasta | ConvertTo-Json) + '}'
[IO.File]::WriteAllText((Join-Path $Base 'config.json'), $cfg, (New-Object Text.UTF8Encoding($false)))

$vbs = Join-Path $Repo 'pc\oculto.vbs'
$ErrorActionPreference = 'Continue'
schtasks /Create /F /TN "Eleva - Publicar site" /SC MINUTE /MO 5 /TR "wscript.exe \`"$vbs\`"" 2>&1 | ForEach-Object { "$_" }
# Notebook: publica tambem na bateria, recupera rodadas perdidas (computador dormindo) e nunca fica travado mais de 30 min.
try {
    $ajuste = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew
    Set-ScheduledTask -TaskName "Eleva - Publicar site" -Settings $ajuste | Out-Null
} catch { "Aviso: nao foi possivel ajustar a tarefa agendada ($($_.Exception.Message))." }
"Instalado. Pasta: $Pasta"
