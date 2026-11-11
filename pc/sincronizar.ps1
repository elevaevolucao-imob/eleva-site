# Envia a pasta IMOVEIS do computador para o site da Eleva.
# Roda sozinho a cada 5 minutos (tarefa agendada) e pelo atalho "PUBLICAR AGORA".
# So envia quando algo mudou. Nunca apaga nem altera nada na pasta do usuario.
param([switch]$Manual)

$ErrorActionPreference = 'Stop'
$Base = Join-Path $env:LOCALAPPDATA 'ElevaSite'
$Repo = Join-Path $Base 'repo'
$Cfg = Get-Content (Join-Path $Base 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$Pasta = $Cfg.pasta
$Fonte = Join-Path $Pasta 'IMOVEIS'
$Destino = Join-Path $Repo 'imoveis'
$ArqStatus = Join-Path $Pasta 'SITUACAO DO SITE.txt'
$ArqEstado = Join-Path $Base 'estado.txt'
$ArqManifesto = Join-Path $Base 'manifesto.txt'
$ArqLista = Join-Path $Base 'lista.txt'
$Site = 'https://elevaevolucao-imob.github.io/eleva-site/'
$ExtFoto = '.jpg', '.jpeg', '.png', '.bmp', '.jfif', '.webp'
$ExtTexto = '.txt', '.md'
$Avisos = New-Object System.Collections.Generic.List[string]

function Dizer($t) { if ($Manual) { Write-Host $t } }

function Gravar-Status($linhas) {
    $cab = @('SITE DA ELEVA', $Site, '', ('Atualizado em ' + (Get-Date -Format 'dd/MM/yyyy HH:mm')), '')
    [IO.File]::WriteAllLines($ArqStatus, [string[]]($cab + $linhas), (New-Object Text.UTF8Encoding($true)))
}

function Git {
    $antes = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $saida = & git -C $Repo @args 2>&1 | ForEach-Object { "$_" }
    $codigo = $LASTEXITCODE; $ErrorActionPreference = $antes
    if ($codigo -ne 0) { throw ("git " + ($args -join ' ') + ": " + ($saida -join ' ')) }
    return $saida
}

function Ignorada($nome) { return ($nome.StartsWith('_') -or $nome.StartsWith('.')) }

# Lista os arquivos de um empreendimento (inclui subpastas, menos as que comecam com _).
function Arquivos-De($dir) {
    $r = @()
    foreach ($f in (Get-ChildItem -LiteralPath $dir.FullName -File)) { $r += $f }
    foreach ($d in (Get-ChildItem -LiteralPath $dir.FullName -Directory)) {
        if (-not (Ignorada $d.Name)) { $r += Arquivos-De $d }
    }
    return $r
}

function Salvar-Jpeg($origem, $alvo) {
    $img = [System.Drawing.Image]::FromFile($origem)
    try {
        if ($img.PropertyIdList -contains 0x0112) {
            switch ([int]$img.GetPropertyItem(0x0112).Value[0]) {
                3 { $img.RotateFlip('Rotate180FlipNone') }
                6 { $img.RotateFlip('Rotate90FlipNone') }
                8 { $img.RotateFlip('Rotate270FlipNone') }
            }
        }
        $fator = [Math]::Min(1.0, 2000.0 / [Math]::Max($img.Width, $img.Height))
        $w = [int][Math]::Round($img.Width * $fator); $h = [int][Math]::Round($img.Height * $fator)
        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        try {
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
            $g.Clear([System.Drawing.Color]::White)
            $g.DrawImage($img, 0, 0, $w, $h); $g.Dispose()
            $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
            $p = New-Object System.Drawing.Imaging.EncoderParameters(1)
            $p.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]88)
            $bmp.Save($alvo, $codec, $p)
        } finally { $bmp.Dispose() }
    } finally { $img.Dispose() }
}

# Foto ja leve (ate 2200 px, ate 1,5 MB, sem rotacao pendente) vai como esta.
function Foto-Leve($f) {
    if ($f.Extension -notin '.jpg', '.jpeg') { return $false }
    if ($f.Length -gt 1500000) { return $false }
    $fs = [IO.File]::OpenRead($f.FullName)
    try {
        $img = [System.Drawing.Image]::FromStream($fs, $false, $false)
        try {
            $rot = 1
            if ($img.PropertyIdList -contains 0x0112) { $rot = [int]$img.GetPropertyItem(0x0112).Value[0] }
            return (([Math]::Max($img.Width, $img.Height) -le 2200) -and ($rot -le 1))
        } finally { $img.Dispose() }
    } finally { $fs.Dispose() }
}

$trava = New-Object System.Threading.Mutex($false, 'ElevaSitePublicar')
if (-not $trava.WaitOne(0)) { Dizer 'Ja existe uma publicacao em andamento. Tente de novo em um minuto.'; exit 0 }

try {
    if (-not (Test-Path -LiteralPath $Fonte)) {
        Gravar-Status @("ATENÇÃO: a pasta $Fonte não foi encontrada.", 'O site continua no ar como estava. Coloque a pasta IMOVEIS de volta neste lugar.')
        Dizer "A pasta $Fonte nao foi encontrada. Nada foi alterado no site."; exit 0
    }

    # 1. Levantamento: bairros > empreendimentos > arquivos
    $planos = @(); $assinatura = New-Object Text.StringBuilder; $maisNovo = [datetime]::MinValue; $lista = @()
    foreach ($b in (Get-ChildItem -LiteralPath $Fonte -Directory | Sort-Object Name)) {
        if (Ignorada $b.Name) { continue }
        foreach ($e in (Get-ChildItem -LiteralPath $b.FullName -Directory | Sort-Object Name)) {
            if (Ignorada $e.Name) { continue }
            $arqs = @(Arquivos-De $e); $nFotos = 0
            foreach ($f in $arqs) {
                $ext = $f.Extension.ToLower()
                if ($ext -in '.heic', '.heif') { $Avisos.Add("$($b.Name) / $($e.Name): a foto $($f.Name) está em HEIC (iPhone) e não entra no site. Salve como JPG.") }
                if (($ext -notin $ExtFoto) -and ($ext -notin $ExtTexto)) { continue }
                if ($ext -in $ExtFoto) { $nFotos++ }
                $rel = $f.FullName.Substring($e.FullName.Length).TrimStart('\')
                if ($ext -in '.png', '.bmp', '.jfif', '.jpeg') { $rel = [IO.Path]::ChangeExtension($rel, '.jpg') }
                $marca = "$($f.Length)|$($f.LastWriteTimeUtc.Ticks)"
                $planos += [pscustomobject]@{ Origem = $f; Alvo = (Join-Path (Join-Path $b.Name.Trim() $e.Name.Trim()) $rel); Marca = $marca; Ext = $ext }
                [void]$assinatura.AppendLine("$($b.Name)\$($e.Name)\$rel|$marca")
                foreach ($t in $f.LastWriteTime, $f.CreationTime) { if ($t -gt $maisNovo) { $maisNovo = $t } }
            }
            if ($nFotos -gt 0) { $lista += "$($b.Name.Trim()) / $($e.Name.Trim())" }
            else { $Avisos.Add("$($b.Name) / $($e.Name): pasta sem fotos, não aparece no site.") }
        }
    }
    if ($lista.Count -eq 0) {
        Gravar-Status @('ATENÇÃO: nenhum empreendimento com fotos foi encontrado na pasta IMOVEIS.', 'O site continua no ar como estava.')
        Dizer 'Nenhum empreendimento com fotos encontrado. Nada foi alterado no site.'; exit 0
    }

    $sha = [BitConverter]::ToString((New-Object Security.Cryptography.SHA1Managed).ComputeHash([Text.Encoding]::UTF8.GetBytes($assinatura.ToString())))
    $anterior = ''; if (Test-Path $ArqEstado) { $anterior = (Get-Content $ArqEstado -Raw).Trim() }
    if (-not $Manual) {
        if ($sha -eq $anterior) { exit 0 }                                  # nada mudou
        if (((Get-Date) - $maisNovo).TotalSeconds -lt 60) { exit 0 }        # ainda copiando arquivos; espera a proxima rodada
        $env:GIT_TERMINAL_PROMPT = '0'; $env:GCM_INTERACTIVE = 'never'
    }

    # 2. Deixa a copia de trabalho igual ao que esta no GitHub
    Dizer 'Conferindo com o site...'
    Git fetch --quiet origin conteudo | Out-Null
    Git reset --quiet --hard origin/conteudo | Out-Null

    # 3. Espelha a pasta do usuario (fotos grandes sao reduzidas na copia; os originais ficam intactos)
    Add-Type -AssemblyName System.Drawing
    $manifesto = @{}
    if (Test-Path $ArqManifesto) { foreach ($l in (Get-Content $ArqManifesto -Encoding UTF8)) { $p = $l.Split("`t"); if ($p.Count -eq 2) { $manifesto[$p[0]] = $p[1] } } }
    $novoManifesto = @{}; $querido = @{}
    foreach ($pl in $planos) {
        $alvo = Join-Path $Destino $pl.Alvo
        $querido[$alvo.ToLower()] = $true
        $novoManifesto[$pl.Alvo] = $pl.Marca
        if ((Test-Path -LiteralPath $alvo) -and ($manifesto[$pl.Alvo] -eq $pl.Marca)) { continue }
        New-Item -ItemType Directory -Force -Path (Split-Path $alvo) | Out-Null
        try {
            if (($pl.Ext -in $ExtTexto) -or ($pl.Ext -eq '.webp') -or (Foto-Leve $pl.Origem)) { Copy-Item -LiteralPath $pl.Origem.FullName -Destination $alvo -Force }
            else { Dizer "  Preparando foto: $($pl.Alvo)"; Salvar-Jpeg $pl.Origem.FullName $alvo }
        } catch {
            $Avisos.Add("$($pl.Alvo): não foi possível ler este arquivo, ficou fora do site.")
            $novoManifesto.Remove($pl.Alvo); $querido.Remove($alvo.ToLower())
        }
    }
    if (Test-Path -LiteralPath $Destino) {
        foreach ($f in (Get-ChildItem -LiteralPath $Destino -File -Recurse)) { if (-not $querido.ContainsKey($f.FullName.ToLower())) { Remove-Item -LiteralPath $f.FullName -Force } }
        foreach ($d in (Get-ChildItem -LiteralPath $Destino -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending)) {
            if (-not (Get-ChildItem -LiteralPath $d.FullName -Force)) { Remove-Item -LiteralPath $d.FullName -Force }
        }
    }

    # 4. Envia se houver diferenca
    Git add -A imoveis | Out-Null
    $mudou = @(Git status --porcelain)
    $antiga = @(); if (Test-Path $ArqLista) { $antiga = @(Get-Content $ArqLista -Encoding UTF8) }
    $entraram = @($lista | Where-Object { $_ -notin $antiga }); $sairam = @($antiga | Where-Object { $_ -notin $lista })
    $linhas = @()
    if ($mudou.Count -gt 0) {
        Dizer 'Enviando para o site...'
        Git commit --quiet -m ("Atualiza imoveis pelo computador " + (Get-Date -Format 'dd/MM/yyyy HH:mm')) | Out-Null
        Git push --quiet origin HEAD:conteudo | Out-Null
        $linhas += 'ENVIADO. As mudanças aparecem no site em cerca de 3 minutos.'
        Dizer 'Pronto! As mudancas aparecem no site em cerca de 3 minutos.'
    } else {
        $linhas += 'Tudo em dia: o site já está igual à pasta IMOVEIS.'
        Dizer 'Tudo em dia: o site ja esta igual a pasta IMOVEIS.'
    }
    if ($antiga.Count -gt 0 -and $entraram.Count -gt 0) { $linhas += ''; $linhas += 'Entraram no site:'; $linhas += ($entraram | ForEach-Object { "  + $_" }) }
    if ($sairam.Count -gt 0) { $linhas += ''; $linhas += 'Saíram do site:'; $linhas += ($sairam | ForEach-Object { "  - $_" }) }
    if ($Avisos.Count -gt 0) { $linhas += ''; $linhas += 'ATENÇÃO:'; $linhas += ($Avisos | Select-Object -Unique | ForEach-Object { "  ! $_" }) }
    $linhas += ''; $linhas += "No site agora ($($lista.Count) empreendimentos):"; $linhas += ($lista | ForEach-Object { "  $_" })
    Gravar-Status $linhas
    [IO.File]::WriteAllLines($ArqLista, [string[]]$lista, (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllLines($ArqManifesto, [string[]]@($novoManifesto.GetEnumerator() | ForEach-Object { $_.Key + "`t" + $_.Value }), (New-Object Text.UTF8Encoding($false)))
    Set-Content -Path $ArqEstado -Value $sha
    if ($Manual -and $Avisos.Count -gt 0) { Write-Host ''; $Avisos | Select-Object -Unique | ForEach-Object { Write-Host "ATENCAO: $_" } }
}
catch {
    $msg = "$($_.Exception.Message)"
    $dica = 'Abra o atalho PUBLICAR AGORA para tentar de novo. Se continuar, peça ajuda ao Claude e mostre este arquivo.'
    if ($msg -match 'Authentication|credential|could not read Username|403|denied') { $dica = 'O computador precisa entrar na conta do GitHub: abra o atalho PUBLICAR AGORA e faça o login na janela que aparecer.' }
    elseif ($msg -match 'Could not resolve host|unable to access|timed out') { $dica = 'Parece que o computador está sem internet. A publicação será tentada de novo sozinha.' }
    try { Gravar-Status @('NÃO FOI POSSÍVEL PUBLICAR. O site continua no ar como estava.', '', $dica, '', "Detalhe técnico: $msg") } catch {}
    Dizer "Nao foi possivel publicar: $msg"; Dizer $dica
}
finally { $trava.ReleaseMutex() }
