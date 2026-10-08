param(
    [string]$Assembler = "sjasmplus"
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $here "mtvol.asm"
$output = Join-Path $here "MTVOL.COM"
$sourceForAssembler = $source.Replace('\', '/')
$outputForAssembler = $output.Replace('\', '/')

& $Assembler "--raw=$outputForAssembler" $sourceForAssembler
if ($LASTEXITCODE -ne 0) {
    throw "No se pudo ensamblar MTVOL.COM. Instala sjasmplus o indica -Assembler con su ruta."
}

Get-FileHash -Algorithm SHA256 $output
