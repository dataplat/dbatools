foreach ($item in (Get-ChildItem "$script:PSModuleRoot\internal\maintenance" -Filter *.ps1)) {
    if ($script:serialimport) {
        . $item.FullName
    }
    else {
        Import-Command -Path $item.FullName
    }
}

$scriptBlock = {
    $script:___ScriptName = 'dbatools-maintenance'

    # Import module in a way where internals are available
    Import-Module "$([Dataplat.Dbatools.dbaSystem.SystemHost]::ModuleBase)\dbatools.psm1"

    try {
        #region Main Execution
        while ($true) {
            # This portion is critical to gracefully closing the script
            if ([Dataplat.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLowerInvariant()].State -notlike "Running") {
                break
            }

            $task = $null
            $tasksDone = @()
            while ($task = [Dataplat.Dbatools.Maintenance.MaintenanceHost]::GetNextTask($tasksDone)) {
                try { ([ScriptBlock]::Create($task.ScriptBlock.ToString())).Invoke() }
                catch { Write-Message -EnableException $false -Level Verbose -Message "[Maintenance] Task '$($task.Name)' failed to execute: $_" -ErrorRecord $_ -FunctionName "task:Maintenance" -Target $task }
                $task.LastExecution = Get-Date
                $tasksDone += $task.Name
            }

            Start-Sleep -Seconds 5
        }
        #endregion Main Execution
    } catch {  }
    finally {
        [Dataplat.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLowerInvariant()].SignalStopped()
    }
}

Register-DbaRunspace -ScriptBlock $scriptBlock -Name "dbatools-maintenance"
Start-DbaRunspace -Name "dbatools-maintenance"