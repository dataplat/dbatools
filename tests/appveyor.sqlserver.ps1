Write-Host -Object "appveyor.sqlserver: Setting up instances for scenario $($env:SCENARIO)" -ForegroundColor DarkGreen
$instances = @( )
if ($env:InstanceSingle) {
    $instances += $env:InstanceSingle
}
if ($env:InstanceMulti1) {
    $instances += $env:InstanceMulti1
}
if ($env:InstanceMulti2) {
    $instances += $env:InstanceMulti2
}
if ($env:InstanceCopy1) {
    $instances += $env:InstanceCopy1
}
if ($env:InstanceCopy2) {
    $instances += $env:InstanceCopy2
}
if ($env:InstanceHadr) {
    $instances += $env:InstanceHadr
}
if ($env:InstanceRestart) {
    $instances += $env:InstanceRestart
}
if ($instances) {
    $instances = $instances | Sort-Object -Unique
    foreach ($instance in $instances) {
        $Setup_Script = "tests\appveyor.$($instance).ps1"
        Write-Host -Object "appveyor.sqlserver: Running setup script $Setup_Script for instance $instance" -ForegroundColor DarkGreen
        $SetupScriptPath = Join-Path $env:APPVEYOR_BUILD_FOLDER $Setup_Script
        Add-AppveyorTest -Name $Setup_Script -Framework NUnit -FileName $Setup_Script -Outcome Running
        $sw = [system.diagnostics.stopwatch]::startNew()
        . $SetupScriptPath
        $sw.Stop()
        Update-AppveyorTest -Name $Setup_Script -Framework NUnit -FileName $Setup_Script -Outcome Passed -Duration $sw.ElapsedMilliseconds
    }
} else {
    Write-Host -Object "appveyor.sqlserver: No instances needed" -ForegroundColor DarkGreen
}