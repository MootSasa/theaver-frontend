param(
    [Parameter(Mandatory = $false)]
    [string[]]$Files = @(),

    [Parameter(Mandatory = $false)]
    [string]$Directory = "",

    [Parameter(Mandatory = $false)]
    [string]$PfxPath = "",

    [Parameter(Mandatory = $false)]
    [string]$PfxPassword = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$FrontendDir = Resolve-Path (Join-Path $ScriptDir "..")

if ([string]::IsNullOrWhiteSpace($PfxPath)) {
    if (-not [string]::IsNullOrWhiteSpace($env:WINDOWS_PFX_PATH)) {
        $PfxPath = $env:WINDOWS_PFX_PATH
    } else {
        $PfxPath = Join-Path $FrontendDir "signing/windows/theaver-windows-codesign.pfx"
    }
}

if ([string]::IsNullOrWhiteSpace($PfxPassword)) {
    if (-not [string]::IsNullOrWhiteSpace($env:WINDOWS_PFX_PASSWORD)) {
        $PfxPassword = $env:WINDOWS_PFX_PASSWORD
    } else {
        $EnvFile = Join-Path $FrontendDir "signing/windows/windows-signing.env"
        if (Test-Path $EnvFile) {
            foreach ($line in Get-Content $EnvFile) {
                if ($line -match "^WINDOWS_PFX_PASSWORD=(.+)$") {
                    $PfxPassword = $Matches[1].Trim()
                    break
                }
            }
        }
    }
}

if (-not (Test-Path $PfxPath)) {
    if (-not [string]::IsNullOrWhiteSpace($env:WINDOWS_PFX_BASE64)) {
        $TempPfx = Join-Path ([System.IO.Path]::GetTempPath()) "theaver-codesign.pfx"
        [System.IO.File]::WriteAllBytes($TempPfx, [System.Convert]::FromBase64String($env:WINDOWS_PFX_BASE64.Trim()))
        $PfxPath = $TempPfx
    } else {
        Write-Warning "Windows signing PFX not found at $PfxPath. Skipping code signing."
        exit 0
    }
}

if ([string]::IsNullOrWhiteSpace($PfxPassword)) {
    Write-Warning "Windows PFX password not provided. Skipping code signing."
    exit 0
}

$Targets = New-Object System.Collections.Generic.List[string]
foreach ($f in $Files) {
    if (Test-Path $f) {
        $Targets.Add((Resolve-Path $f).Path)
    }
}

if (-not [string]::IsNullOrWhiteSpace($Directory) -and (Test-Path $Directory)) {
    $ExeFiles = Get-ChildItem -Path $Directory -Filter "*.exe" -File
    foreach ($exe in $ExeFiles) {
        if (-not $Targets.Contains($exe.FullName)) {
            $Targets.Add($exe.FullName)
        }
    }
}

if ($Targets.Count -eq 0) {
    $DefaultReleaseExe = Join-Path $FrontendDir "build/windows/x64/runner/Release/theaver.exe"
    if (Test-Path $DefaultReleaseExe) {
        $Targets.Add((Resolve-Path $DefaultReleaseExe).Path)
    }
    $DistDir = Join-Path $FrontendDir "dist/windows"
    if (Test-Path $DistDir) {
        foreach ($exe in (Get-ChildItem -Path $DistDir -Filter "*.exe" -File)) {
            $Targets.Add($exe.FullName)
        }
    }
}

if ($Targets.Count -eq 0) {
    Write-Host "No Windows executables found to sign."
    exit 0
}

# Locate signtool.exe from Windows SDK if available
$SignTool = $null
$WinKitsRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
if (Test-Path $WinKitsRoot) {
    $FoundSignTools = Get-ChildItem -Path $WinKitsRoot -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\x64\\signtool\.exe$" } |
        Sort-Object FullName -Descending
    if ($FoundSignTools -and $FoundSignTools.Count -gt 0) {
        $SignTool = $FoundSignTools[0].FullName
    }
}

foreach ($TargetFile in $Targets) {
    Write-Host "Signing Windows binary: $TargetFile"
    $Signed = $false

    if ($null -ne $SignTool) {
        & $SignTool sign /f $PfxPath /p $PfxPassword /fd SHA256 /tr "http://timestamp.digicert.com" /td SHA256 $TargetFile
        if ($LASTEXITCODE -eq 0) {
            $Signed = $true
        } else {
            & $SignTool sign /f $PfxPath /p $PfxPassword /fd SHA256 $TargetFile
            if ($LASTEXITCODE -eq 0) {
                $Signed = $true
            }
        }
    }

    if (-not $Signed) {
        $SecurePass = ConvertTo-SecureString $PfxPassword -AsPlainText -Force
        $Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($PfxPath, $SecurePass)
        $Result = Set-AuthenticodeSignature -FilePath $TargetFile -Certificate $Cert -HashAlgorithm SHA256 -TimestampServer "http://timestamp.digicert.com" -ErrorAction SilentlyContinue
        if ($null -eq $Result -or $Result.Status -eq "UnknownError") {
            $Result = Set-AuthenticodeSignature -FilePath $TargetFile -Certificate $Cert -HashAlgorithm SHA256
        }
        Write-Host "Authenticode status for $(Split-Path -Leaf $TargetFile): $($Result.Status)"
    } else {
        Write-Host "Signed $(Split-Path -Leaf $TargetFile) via signtool.exe"
    }
}
