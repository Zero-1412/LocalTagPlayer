[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$CertificatePath,

  [Parameter(Mandatory = $true)]
  [string]$CertificatePassword,

  [Parameter(Mandatory = $true)]
  [string[]]$Files,

  [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'

<#
  在 Windows SDK 中选择最新的 x64 SignTool，避免依赖 runner 的固定 SDK 版本。
#>
function Resolve-SignTool {
  $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
  $candidate = Get-ChildItem -Path $kitsRoot -Recurse -Filter signtool.exe |
    Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
  if ($null -eq $candidate) {
    throw '未找到 Windows SDK x64 SignTool。'
  }
  return $candidate.FullName
}

$resolvedCertificate = (Resolve-Path -LiteralPath $CertificatePath).Path
$resolvedFiles = foreach ($file in $Files) {
  (Resolve-Path -LiteralPath $file).Path
}
$signTool = Resolve-SignTool
$securePassword = ConvertTo-SecureString $CertificatePassword -AsPlainText -Force
$certificate = $null

try {
  # 先导入临时用户证书存储，再按指纹签名，避免把 PFX 密码传给 SignTool 进程。
  $importParameters = @{
    FilePath          = $resolvedCertificate
    CertStoreLocation = 'Cert:\CurrentUser\My'
    Password          = $securePassword
    Exportable        = $false
  }
  $certificate = Import-PfxCertificate @importParameters

  if ($null -eq $certificate -or [string]::IsNullOrWhiteSpace($certificate.Thumbprint)) {
    throw 'PFX 已导入，但没有得到可用于签名的证书指纹。'
  }

  foreach ($file in $resolvedFiles) {
    & $signTool sign `
      /sha1 $certificate.Thumbprint `
      /fd SHA256 `
      /tr $TimestampUrl `
      /td SHA256 `
      /d 'Local Tag Player' `
      $file
    if ($LASTEXITCODE -ne 0) {
      throw "SignTool 签名失败：$file"
    }

    & $signTool verify /pa /v $file
    if ($LASTEXITCODE -ne 0) {
      throw "SignTool 验证失败：$file"
    }
  }
}
finally {
  # GitHub runner 是临时环境，但仍主动移除证书，避免后续步骤意外复用。
  if ($null -ne $certificate -and -not [string]::IsNullOrWhiteSpace($certificate.Thumbprint)) {
    Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($certificate.Thumbprint)" -Force -ErrorAction SilentlyContinue
  }
}
