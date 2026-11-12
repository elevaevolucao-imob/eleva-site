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
$ExtFoto = '.jpg', '.jpeg', '.png', '.bmp', '.jfif', '.webp', '.heic', '.heif', '.avif', '.tif', '.tiff'
$ExtTexto = '.txt', '.md'
$RemotoEsperado = 'https://github.com/elevaevolucao-imob/eleva-site.git'
$VersaoFotos = 'v2'                        # mudar este valor reprocessa todas as fotos uma vez
$MaxLado = 2400; $MaxBytes = 60MB; $MaxFotos = 40
$Avisos = New-Object System.Collections.Generic.List[string]

function Dizer($t) { if ($Manual) { Write-Host $t } }

function Gravar-Status($linhas) {
    $cab = @('SITE DA ELEVA', $Site, '', ('Atualizado em ' + (Get-Date -Format 'dd/MM/yyyy HH:mm')), '')
    [IO.File]::WriteAllLines($ArqStatus, [string[]]($cab + $linhas), (New-Object Text.UTF8Encoding($true)))
}

function Rodar-Git {
    $antes = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $saida = & git.exe -C $Repo @args 2>&1 | ForEach-Object { "$_" }
    $codigo = $LASTEXITCODE; $ErrorActionPreference = $antes
    if ($codigo -ne 0) { throw ("git " + ($args -join ' ') + ": " + ($saida -join ' ')) }
    return $saida
}

function Ignorada($nome) { return ($nome.StartsWith('_') -or $nome.StartsWith('.')) }
function E-Link($item) { return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint) }

# Lista os arquivos de um empreendimento (inclui subpastas, menos as que comecam com _).
function Arquivos-De($dir) {
    $r = @()
    foreach ($f in (Get-ChildItem -LiteralPath $dir.FullName -File)) { if (-not (E-Link $f)) { $r += $f } }
    foreach ($d in (Get-ChildItem -LiteralPath $dir.FullName -Directory)) {
        if (-not (Ignorada $d.Name) -and -not (E-Link $d)) { $r += Arquivos-De $d }
    }
    return $r
}

# ---------- Fotos ----------
# Toda foto que vai para o site passa por aqui. O original na pasta do usuario nunca e alterado.
# Seguranca: o repositorio do site e publico, entao nenhuma foto sai com metadados (localizacao GPS,
# modelo do celular, autor, data). JPEG pequeno e limpo sem recompressao; o resto e convertido para JPEG.
Add-Type -AssemblyName PresentationCore, WindowsBase

function Abrir-Decoder($fs, $opcao) {
    return [Windows.Media.Imaging.BitmapDecoder]::Create($fs, [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat, $opcao)
}

function Orientacao($frame) {
    foreach ($q in '/app1/ifd/{ushort=274}', '/ifd/{ushort=274}') {
        try { $v = $frame.Metadata.GetQuery($q); if ($v) { return [int]"$v" } } catch {}
    }
    return 1
}

# JPEG ja no tamanho certo e de pe: so tira os metadados (sem perder qualidade).
function Precisa-Converter($f) {
    if ($f.Extension.ToLower() -notin '.jpg', '.jpeg', '.jfif') { return $true }
    if ($f.Length -gt 4MB) { return $true }
    $fs = [IO.File]::OpenRead($f.FullName)
    try {
        $fr = (Abrir-Decoder $fs ([Windows.Media.Imaging.BitmapCacheOption]::None)).Frames[0]
        return (([Math]::Max($fr.PixelWidth, $fr.PixelHeight) -gt $MaxLado) -or ((Orientacao $fr) -gt 1))
    } finally { $fs.Dispose() }
}

# Copia o JPEG sem os blocos de metadados (EXIF/GPS, XMP, IPTC, comentarios). Mantem perfil de cor (APP2) e Adobe (APP14).
function Limpar-Jpeg($origem, $alvo) {
    $b = [IO.File]::ReadAllBytes($origem)
    if ($b.Length -lt 4 -or $b[0] -ne 0xFF -or $b[1] -ne 0xD8) { throw 'nao e um JPEG valido' }
    $ms = New-Object IO.MemoryStream
    $ms.WriteByte(0xFF); $ms.WriteByte(0xD8)
    $i = 2
    while ($true) {
        if ($i + 4 -gt $b.Length -or $b[$i] -ne 0xFF) { throw 'JPEG corrompido' }
        $m = $b[$i + 1]
        if ($m -eq 0xFF) { $i++; continue }
        if ($m -eq 0xDA -or $m -eq 0xD9) { $ms.Write($b, $i, $b.Length - $i); break }
        if ($m -eq 0x01 -or ($m -ge 0xD0 -and $m -le 0xD7)) { $ms.Write($b, $i, 2); $i += 2; continue }
        $len = [int]$b[$i + 2] * 256 + [int]$b[$i + 3]
        if ($len -lt 2 -or ($i + 2 + $len) -gt $b.Length) { throw 'JPEG corrompido' }
        $metadado = (($m -ge 0xE1 -and $m -le 0xEF -and $m -ne 0xE2 -and $m -ne 0xEE) -or $m -eq 0xFE)
        if (-not $metadado) { $ms.Write($b, $i, 2 + $len) }
        $i += 2 + $len
    }
    $tmp = "$alvo.tmp"
    [IO.File]::WriteAllBytes($tmp, $ms.ToArray())
    Move-Item -LiteralPath $tmp -Destination $alvo -Force
}

# Converte qualquer formato (PNG, WEBP, HEIC do iPhone, AVIF, TIFF, JPEG grande ou girado) para JPEG:
# coloca de pe, reduz para no maximo 2400 px, transparencia vira fundo branco, sem metadados.
function Converter-Foto($origem, $alvo) {
    $fs = [IO.File]::OpenRead($origem)
    try {
        $fr = (Abrir-Decoder $fs ([Windows.Media.Imaging.BitmapCacheOption]::OnLoad)).Frames[0]
        $o = Orientacao $fr
        $src = [Windows.Media.Imaging.BitmapSource]$fr
        $fator = [Math]::Min(1.0, $MaxLado / [Math]::Max($src.PixelWidth, $src.PixelHeight))
        $tg = New-Object Windows.Media.TransformGroup
        if ($fator -lt 1.0) { $tg.Children.Add((New-Object Windows.Media.ScaleTransform($fator, $fator))) }
        switch ($o) {
            3 { $tg.Children.Add((New-Object Windows.Media.RotateTransform(180))) }
            6 { $tg.Children.Add((New-Object Windows.Media.RotateTransform(90))) }
            8 { $tg.Children.Add((New-Object Windows.Media.RotateTransform(270))) }
        }
        if ($tg.Children.Count -gt 0) { $src = New-Object Windows.Media.Imaging.TransformedBitmap($src, $tg) }
        if ($src.Format -ne [Windows.Media.PixelFormats]::Cmyk32) {
            $w = $src.PixelWidth; $h = $src.PixelHeight
            $dv = New-Object Windows.Media.DrawingVisual
            $dc = $dv.RenderOpen()
            $ret = New-Object Windows.Rect(0, 0, $w, $h)
            $dc.DrawRectangle([Windows.Media.Brushes]::White, $null, $ret)
            $dc.DrawImage($src, $ret)
            $dc.Close()
            $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
            $rtb.Render($dv)
            $src = New-Object Windows.Media.Imaging.FormatConvertedBitmap($rtb, [Windows.Media.PixelFormats]::Bgr24, $null, 0)
        }
        $enc = New-Object Windows.Media.Imaging.JpegBitmapEncoder
        $enc.QualityLevel = 90
        $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($src))
        $tmp = "$alvo.tmp"
        $out = [IO.File]::Create($tmp)
        try { $enc.Save($out) } finally { $out.Dispose() }
        Move-Item -LiteralPath $tmp -Destination $alvo -Force
    } finally { $fs.Dispose() }
}

function Preparar-Foto($f, $alvo) {
    if (Precisa-Converter $f) { Converter-Foto $f.FullName $alvo } else { Limpar-Jpeg $f.FullName $alvo }
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
            $arqs = @(Arquivos-De $e); $nFotos = 0; $temDescricao = $false; $vistos = @{}
            foreach ($f in $arqs) {
                $ext = $f.Extension.ToLower()
                if ($ext -in $ExtTexto) {
                    # So a descricao vai para o site. Qualquer outro texto (anotacoes, senhas, contatos) fica so no computador.
                    if ($temDescricao -or -not $f.BaseName.ToLower().StartsWith('descri') -or $f.DirectoryName -ne $e.FullName) {
                        $Avisos.Add("$($b.Name) / $($e.Name): o arquivo $($f.Name) não vai para o site (só o descricao.txt vai)."); continue
                    }
                    $temDescricao = $true
                } elseif ($ext -in $ExtFoto) {
                    if ($f.Length -gt $MaxBytes) { $Avisos.Add("$($b.Name) / $($e.Name): a foto $($f.Name) tem mais de 60 MB e ficou de fora."); continue }
                    if ($nFotos -ge $MaxFotos) { $Avisos.Add("$($b.Name) / $($e.Name): só as primeiras $MaxFotos fotos entram no site."); continue }
                    $nFotos++
                } else {
                    if ($ext -notin '.ini', '.db', '.lnk', '.tmp') { $Avisos.Add("$($b.Name) / $($e.Name): o arquivo $($f.Name) não vai para o site (só fotos e o descricao.txt).") }
                    continue
                }
                $rel = $f.FullName.Substring($e.FullName.Length).TrimStart('\')
                if ($ext -in $ExtFoto) { $rel = [IO.Path]::ChangeExtension($rel, '.jpg') }
                if ($vistos.ContainsKey($rel.ToLower())) { $Avisos.Add("$($b.Name) / $($e.Name): há duas fotos com o nome $([IO.Path]::GetFileNameWithoutExtension($rel)); só uma entrou. Renomeie uma delas."); continue }
                $vistos[$rel.ToLower()] = $true
                $marca = "$VersaoFotos|$($f.Length)|$($f.LastWriteTimeUtc.Ticks)"
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
    $remoto = (Rodar-Git remote get-url origin | Select-Object -First 1).Trim()
    if ($remoto -ne $RemotoEsperado) { throw "Endereco do repositorio inesperado ($remoto). Envio bloqueado por seguranca." }
    Rodar-Git fetch --quiet origin conteudo | Out-Null
    Rodar-Git reset --quiet --hard origin/conteudo | Out-Null

    # 3. Espelha a pasta do usuario (fotos grandes sao reduzidas na copia; os originais ficam intactos)
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
            if ($pl.Ext -in $ExtTexto) { Copy-Item -LiteralPath $pl.Origem.FullName -Destination $alvo -Force }
            else { Dizer "  Preparando foto: $($pl.Alvo)"; Preparar-Foto $pl.Origem $alvo }
        } catch {
            $Avisos.Add("$($pl.Alvo): não foi possível ler este arquivo, ficou fora do site. Se for foto de iPhone (HEIC), instale a 'Extensão de Imagem HEIF' da Microsoft Store ou salve como JPG.")
            if (Test-Path -LiteralPath $alvo) { Remove-Item -LiteralPath $alvo -Force }
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
    Rodar-Git add -A imoveis | Out-Null
    $mudou = @(Rodar-Git status --porcelain)
    $antiga = @(); if (Test-Path $ArqLista) { $antiga = @(Get-Content $ArqLista -Encoding UTF8) }
    $entraram = @($lista | Where-Object { $_ -notin $antiga }); $sairam = @($antiga | Where-Object { $_ -notin $lista })
    $linhas = @()
    if ($mudou.Count -gt 0) {
        Dizer 'Enviando para o site...'
        Rodar-Git commit --quiet -m ("Atualiza imoveis pelo computador " + (Get-Date -Format 'dd/MM/yyyy HH:mm')) | Out-Null
        Rodar-Git push --quiet origin HEAD:conteudo | Out-Null
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
