Add-AppveyorTest -Name "appveyor.sqlserver" -Framework NUnit -FileName "appveyor.sqlserver.ps1" -Outcome Running
$sw = [system.diagnostics.stopwatch]::startNew()

Write-Host -Object "appveyor.sqlserver: Creating temp directory" -ForegroundColor DarkGreen
New-Item -Path C:\temp -ItemType Directory -ErrorAction SilentlyContinue | Out-Null

Write-Host -Object "appveyor.sqlserver: Configuring WinRM (see #9782)" -ForegroundColor DarkGreen
'y' | winrm quickconfig

Write-Host -Object "appveyor.sqlserver: Trust SQL Server Cert (now required)" -ForegroundColor DarkGreen
Import-Module dbatools.library
Import-Module C:\github\dbatools\dbatools.psd1
Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register

Write-Host -Object "appveyor.sqlserver: Setting up SQL Server Browser" -ForegroundColor DarkGreen
Set-Service -Name SQLBrowser -StartupType Automatic
Start-Service -Name SQLBrowser

$sw.Stop()
Update-AppveyorTest -Name "appveyor.sqlserver" -Framework NUnit -FileName "appveyor.sqlserver.ps1" -Outcome Passed -Duration $sw.ElapsedMilliseconds

Write-Host -Object "Scenario $($env:scenario)" -ForegroundColor DarkGreen
$Setup_Scripts = $env:SETUP_SCRIPTS.split(',').Trim()
foreach ($Setup_Script in $Setup_Scripts) {
    $SetupScriptPath = Join-Path $env:APPVEYOR_BUILD_FOLDER $Setup_Script
    Add-AppveyorTest -Name $Setup_Script -Framework NUnit -FileName $Setup_Script -Outcome Running
    $sw = [system.diagnostics.stopwatch]::startNew()
    . $SetupScriptPath
    $sw.Stop()
    Update-AppveyorTest -Name $Setup_Script -Framework NUnit -FileName $Setup_Script -Outcome Passed -Duration $sw.ElapsedMilliseconds
}