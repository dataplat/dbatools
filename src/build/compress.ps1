function compress-dbatools {
    #Remove-Item C:\gallery\dbatools\dbatools.dat -ErrorAction Ignore
    #Remove-Item C:\gallery\dbatools\dbatools.ps1 -ErrorAction Ignore

    Remove-Item C:\gallery\dbatools -Recurse -ErrorAction Ignore

    Set-Location C:\github\dbatools
    Import-Module C:\github\dbatools
    # Create dbatools.ps1 and build help file
    $null = Install-Maml -FunctionRoot public, private\functions -Module dbatools -Compact -NoVersion -ScriptName dbatools.ps1
    # Update DiagnosticQueryScript
    try {
        Remove-Item -Path C:\github\dbatools\bin\diagnosticquery\* -ErrorAction SilentlyContinue
        $null = Save-DbaDiagnosticQueryScript -Path C:\github\dbatools\bin\diagnosticquery -ErrorAction Stop
    } catch {
        throw $PSItem
    }

    # Prep for gallery
    $null = New-Item -Type Directory -Path C:\gallery\dbatools
    robocopy C:\github\dbatools C:\gallery\dbatools /S /XF .markdownlint.json *.psproj* *.git* *.yml *.md compress.ps1 /XD .devcontainer .git .github Tests .vscode install.ps1 compress.ps1 | Out-String | Out-Null
    # Grrr, Windows and Linux look in different places for external help

    # robocopy gives exit codes other than 0, which breaks github actions
    if ($LASTEXITCODE -eq 1) {
        $LASTEXITCODE = 0
    }

    Remove-Item -Recurse C:\gallery\dbatools\bin\build -ErrorAction Ignore
    Remove-Item -Recurse C:\gallery\dbatools\bin\projects -ErrorAction Ignore
    Remove-Item -Recurse C:\gallery\dbatools\bin\StructuredLogger.dll -ErrorAction Ignore

    Move-Item C:\github\dbatools\dbatools.ps1 C:\github\gallery
    #Remove-Item C:\github\dbatools\dbatools.ps1 -ErrorAction Ignore

    Remove-Item -Recurse C:\gallery\dbatools\public -ErrorAction Ignore
    Remove-Item -Recurse C:\gallery\dbatools\private\functions -ErrorAction Ignore


(Get-Content C:\gallery\dbatools\opt\*) | Set-Content C:\gallery\dbatools\opt\opt.ps1
    Get-ChildItem C:\gallery\dbatools\opt\ | Where-Object Name -ne opt.ps1 | Remove-Item -Force
(Get-Content C:\gallery\dbatools\private\dynamicparams\*) | Set-Content C:\gallery\dbatools\private\dynamicparams\dynamicparams.ps1
    Get-ChildItem C:\gallery\dbatools\private\dynamicparams\ | Where-Object Name -ne dynamicparams.ps1 | Remove-Item -Force
(Get-Content C:\gallery\dbatools\private\configurations\validation\*) | Set-Content C:\gallery\dbatools\private\configurations\validation\validation.ps1
    Get-ChildItem C:\gallery\dbatools\private\configurations\validation | Where-Object Name -ne validation.ps1 | Remove-Item -Force
(Get-Content C:\gallery\dbatools\private\maintenance\*) | Set-Content C:\gallery\dbatools\private\maintenance\maintenance.ps1
    Get-ChildItem C:\gallery\dbatools\private\maintenance\ | Where-Object Name -ne maintenance.ps1 | Remove-Item -Force
(Get-Content C:\gallery\dbatools\private\configurations\settings\*) | Set-Content C:\gallery\dbatools\private\configurations\settings\settings.ps1
    Get-ChildItem C:\gallery\dbatools\private\configurations\settings | Where-Object Name -ne settings.ps1 | Remove-Item -Force

    # $files = 'C:\gallery\dbatools\private\scripts\LibraryImport.ps1', 'C:\gallery\dbatools\opt\', 'C:\gallery\dbatools\private\configurations\configuration.ps1', 'C:\gallery\dbatools\bin\typealiases.ps1', 'C:\gallery\dbatools\bin\library.ps1', 'C:\gallery\dbatools\dbatools.ps1', 'C:\gallery\dbatools\xml\dbatools.Types.ps1xml', 'C:\gallery\dbatools\install.ps1', 'C:\gallery\dbatools\xml\dbatools.Format.ps1xml', 'C:\gallery\dbatools\dbatools.psm1', 'C:\gallery\dbatools\dbatools.psd1', 'C:\gallery\dbatools\private\scripts\'


    $ps1 = [IO.File]::Open("C:\gallery\dbatools\dbatools.ps1", "Open")
    $dat = [IO.File]::Create("C:\gallery\dbatools\dbatools.dat")
    $compressor = New-Object System.IO.Compression.DeflateStream($dat, [System.IO.Compression.CompressionMode]::Compress)
    $ps1.CopyTo($compressor)
    $compressor.Flush()
    $dat.Flush()
    $ps1.Close()
    $compressor.Close()
    $dat.Close()
    $compressor.Dispose()
    $dat.Dispose()

    Remove-Item C:\gallery\dbatools\dbatools.ps1 -ErrorAction Ignore

    $files = Get-ChildItem C:\gallery\dbatools -File -Recurse -Include *.ps1, *.ps1xml, *.psd1, *.psm1, *.pssc, *.psrc, *.cdxml | Where-Object Directory -notmatch private | Where-Object Directory -notmatch opt

    foreach ($file in $files) {
        Get-ChildItem -Recurse -Path $file | Set-AuthenticodeSignature -Certificate (Get-ChildItem -Path Cert:\CurrentUser\My\fd0dde81152c4d4868afd88d727e78a9b6881cf4) -TimestampServer http://timestamp.digicert.com -HashAlgorithm SHA256
    }

}