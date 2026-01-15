if ($env:SETUP_SCRIPTS) {
    Write-Host -Object "Scenario $($env:SCENARIO)" -ForegroundColor DarkGreen
    $Setup_Scripts = $env:SETUP_SCRIPTS.split(',').Trim()
    foreach ($Setup_Script in $Setup_Scripts) {
        $SetupScriptPath = Join-Path $env:APPVEYOR_BUILD_FOLDER $Setup_Script
        Add-AppveyorTest -Name $Setup_Script -Framework NUnit -FileName $Setup_Script -Outcome Running
        $sw = [system.diagnostics.stopwatch]::startNew()
        . $SetupScriptPath
        $sw.Stop()
        Update-AppveyorTest -Name $Setup_Script -Framework NUnit -FileName $Setup_Script -Outcome Passed -Duration $sw.ElapsedMilliseconds
    }
}