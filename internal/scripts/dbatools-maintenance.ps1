foreach ($item in (Get-ChildItem "$script:PSModuleRoot\internal\maintenance" -Filter *.ps1)) {
    if ($script:doDotSource) { . $item.FullName }
    else { $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($item.FullName))), $null, $null) }
}

$scriptBlock = {
    $script:___ScriptName = 'dbatools-maintenance'

    # Import module in a way where internals are available
    $dbatools_disableTimeMeasurements = $true
    Import-Module "$([Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleBase)\dbatools.psm1"

    try {
        #region Main Execution
        while ($true) {
            # This portion is critical to gracefully closing the script
            if ([Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLower()].State -notlike "Running") {
                break
            }

            $task = $null
            $tasksDone = @()
            while ($task = [Sqlcollaborative.Dbatools.Maintenance.MaintenanceHost]::GetNextTask($tasksDone)) {
                try { ([ScriptBlock]::Create($task.ScriptBlock.ToString())).Invoke() }
                catch { Write-Message -EnableException $false -Level Verbose -Message "[Maintenance] Task '$($task.Name)' failed to execute: $_" -ErrorRecord $_ -FunctionName "task:Maintenance" -Target $task }
                $task.LastExecution = Get-Date
                $tasksDone += $task.Name
            }

            Start-Sleep -Seconds 5
        }
        #endregion Main Execution
    }
    catch {  }
    finally {
        [Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLower()].SignalStopped()
    }
}

Register-DbaRunspace -ScriptBlock $scriptBlock -Name "dbatools-maintenance"
Start-DbaRunspace -Name "dbatools-maintenance"