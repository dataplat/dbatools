function Remove-DbaPfDataCollectorSet {
    <#
    .SYNOPSIS
        Removes Windows Performance Monitor Data Collector Sets from local or remote computers

    .DESCRIPTION
        Removes Windows Performance Monitor Data Collector Sets that are no longer needed for SQL Server performance monitoring. This is useful for cleaning up old monitoring configurations, freeing disk space, or standardizing performance monitoring setups across your SQL Server environment. The collector set must be stopped before removal - running collector sets will generate an error and must be stopped first using Stop-DbaPfDataCollectorSet. When removing collector sets from the local computer, administrator privileges are required.

    .PARAMETER ComputerName
        Specifies the target computer(s) where Performance Monitor Data Collector Sets will be removed. Supports multiple computers for bulk operations.
        Use this when removing collector sets from remote SQL Server hosts or when standardizing monitoring configurations across multiple servers.

    .PARAMETER Credential
        Allows you to login to the target computer using alternative credentials. To use:

        $cred = Get-Credential, then pass $cred object to the -Credential parameter.

    .PARAMETER CollectorSet
        Specifies the exact name(s) of the Performance Monitor Data Collector Sets to remove. Accepts multiple collector set names for batch operations.
        Use this when you need to remove specific monitoring configurations rather than all available collector sets on the target computer.

    .PARAMETER InputObject
        Accepts Data Collector Set objects from Get-DbaPfDataCollectorSet for pipeline operations. Enables chaining commands together for workflow automation.
        Use this when you need to filter collector sets with Get-DbaPfDataCollectorSet first, then remove only the matching results.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: PerfMon
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaPfDataCollectorSet

    .OUTPUTS
        PSCustomObject

        Returns one object per Performance Monitor Data Collector Set removed.

        Properties:
        - ComputerName: The name of the computer from which the collector set was removed
        - Name: The name of the Data Collector Set that was removed
        - Status: The operation status (Removed)

    .EXAMPLE
        PS C:\> Remove-DbaPfDataCollectorSet

        Prompts for confirmation then removes all ready Collectors on localhost.

    .EXAMPLE
        PS C:\> Remove-DbaPfDataCollectorSet -ComputerName sql2017 -Confirm:$false

        Attempts to remove all ready Collectors on localhost and does not prompt to confirm.

    .EXAMPLE
        PS C:\> Remove-DbaPfDataCollectorSet -ComputerName sql2017, sql2016 -Credential ad\sqldba -CollectorSet 'System Correlation'

        Prompts for confirmation then removes the 'System Correlation' Collector on sql2017 and sql2016 using alternative credentials.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSet -CollectorSet 'System Correlation' | Remove-DbaPfDataCollectorSet

        Removes the 'System Correlation' Collector.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSet -CollectorSet 'System Correlation' | Stop-DbaPfDataCollectorSet | Remove-DbaPfDataCollectorSet

        Stops and removes the 'System Correlation' Collector.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Alias("DataCollectorSet")]
        [string[]]$CollectorSet,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $setscript = {
            $setname = $args
            $collectorset = New-Object -ComObject Pla.DataCollectorSet
            $collectorset.Query($setname, $null)
            if ($collectorset.name -eq $setname) {
                $null = $collectorset.Delete()
            } else {
                <# DO NOT use Write-Message as this is inside of a script block #>
                Write-Warning "Data Collector Set $setname does not exist on $env:COMPUTERNAME."
            }
        }
    }
    process {


        if (-not $InputObject -or ($InputObject -and (Test-Bound -ParameterName ComputerName))) {
            foreach ($computer in $ComputerName) {
                $InputObject += Get-DbaPfDataCollectorSet -ComputerName $computer -Credential $Credential -CollectorSet $CollectorSet
            }
        }

        if ($InputObject) {
            if (-not $InputObject.DataCollectorSetObject) {
                Stop-Function -Message "InputObject is not of the right type. Please use Get-DbaPfDataCollectorSet."
                return
            }
        }

        # Check to see if its running first
        foreach ($set in $InputObject) {
            $setname = $set.Name
            $computer = $set.ComputerName
            $status = $set.State

            $null = Test-ElevationRequirement -ComputerName $computer -Continue

            Write-Message -Level Verbose -Message "$setname on $ComputerName is $status."

            if ($status -eq "Running") {
                Stop-Function -Message "$setname on $computer is running. Use Stop-DbaPfDataCollectorSet to stop first." -Continue
            }

            if ($Pscmdlet.ShouldProcess("$computer", "Removing collector set $setname")) {
                try {
                    Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $setscript -ArgumentList $setname -ErrorAction Stop
                    [PSCustomObject]@{
                        ComputerName = $computer
                        Name         = $setname
                        Status       = "Removed"
                    }
                } catch {
                    Stop-Function -Message "Failure Removing $setname on $computer." -ErrorRecord $_ -Target $computer -Continue
                }
            }
        }
    }
}