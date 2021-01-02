function Register-DbaMaintenanceTask {
    <#
        .SYNOPSIS
            Allows scheduling maintenance tasks, that are perfomed in the background.

        .DESCRIPTION
            Allows scheduling maintenance tasks, that are perfomed in the background.

            All scriptblocks scheduled like this will be performed on a separate runspace and have access to all internal dbatools commands.
            None of the scriptblocks will affect the main session (so you cannot manipulate variables, etc.)

        .PARAMETER Name
            The name of the task.
            Must be unique, otherwise it will update the existing task.

        .PARAMETER ScriptBlock
            The task/scriptblock that should be performed as part of the maintenance.
            It will have all of dbatools including internal commands available.

        .PARAMETER Once
            Whether the interval should be performed only once.

        .PARAMETER Interval
            The interval at which the task should be repeated.

        .PARAMETER Delay
            How far after the initial registration should the maintenance script wait before processing this.
            This can be used to delay background stuff that should not content with items that would be good to have as part of the module import.
            Some library specific items can be moved to maintenance if their processing would take too much time on original import, even if it is desirable to have them available as soon as possible.

        .PARAMETER Priority
            How important is this task?
            If multiple tasks are due at the same maintenance cycle, the more critical one will be processed first.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .EXAMPLE
            PS C:\> Register-DbaMaintenanceTask -Name 'value1' -ScriptBlock $ScriptBlock -Once
       #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Name,

        [Parameter(Mandatory)]
        [System.Management.Automation.ScriptBlock]
        $ScriptBlock,

        [Parameter(Mandatory, ParameterSetName = "Once")]
        [switch]
        $Once,

        [Parameter(Mandatory, ParameterSetName = "Repeating")]
        [System.TimeSpan]
        $Interval,

        [System.TimeSpan]
        $Delay,

        [Sqlcollaborative.Dbatools.Maintenance.MaintenancePriority]
        $Priority = "Medium",

        [switch]$EnableException
    )

    #region Case: Task already registered
    if ([Sqlcollaborative.Dbatools.Maintenance.MaintenanceHost]::Tasks.ContainsKey($Name.ToLowerInvariant())) {
        $task = [Sqlcollaborative.Dbatools.Maintenance.MaintenanceHost]::Tasks[$Name.ToLowerInvariant()]
        if ($task.ScriptBlock -ne $ScriptBlock) { $task.ScriptBlock = $ScriptBlock }
        if (Test-Bound -ParameterName Once) { $task.Once = $Once }
        if (Test-Bound -ParameterName Interval) {
            $task.Once = $false
            $task.Interval = $Interval
        }
        if (Test-Bound -ParameterName Delay) { $task.Delay = $Delay }
        if (Test-Bound -ParameterName Priority) { $task.Priority = $Priority }
    }
    #endregion Case: Task already registered

    #region New Task
    else {
        $task = New-Object Sqlcollaborative.Dbatools.Maintenance.MaintenanceTask
        $task.Name = $Name.ToLowerInvariant()
        $task.ScriptBlock = $ScriptBlock
        if (Test-Bound -ParameterName Once) { $task.Once = $true }
        if (Test-Bound -ParameterName Interval) {
            if ($Interval.Ticks -le 0) {
                Stop-Function -Message "Failed to register task: $Name - Interval cannot be 0 or less" -Category InvalidArgument
                return
            } else { $task.Interval = $Interval }
        }
        if (Test-Bound -ParameterName Delay) { $task.Delay = $Delay }
        $task.Priority = $Priority
        $task.Registered = Get-Date
        [Sqlcollaborative.Dbatools.Maintenance.MaintenanceHost]::Tasks[$Name.ToLowerInvariant()] = $task
    }
    #endregion New Task
}