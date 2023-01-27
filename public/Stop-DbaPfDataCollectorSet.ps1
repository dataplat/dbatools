function Stop-DbaPfDataCollectorSet {
    <#
    .SYNOPSIS
        Stops Performance Monitor Data Collector Set.

    .DESCRIPTION
        Stops Performance Monitor Data Collector Set.

    .PARAMETER ComputerName
        The target computer. Defaults to localhost.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials. To use:

        $cred = Get-Credential, then pass $cred object to the -Credential parameter.

    .PARAMETER CollectorSet
        The name of the Collector Set to stop.

    .PARAMETER NoWait
        If this switch is enabled, the collector is stopped and the results are returned immediately.

    .PARAMETER InputObject
        Accepts the object output by Get-DbaPfDataCollectorSet via the pipeline.

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
        https://dbatools.io/Stop-DbaPfDataCollectorSet

    .EXAMPLE
        PS C:\> Stop-DbaPfDataCollectorSet

        Attempts to stop all ready Collectors on localhost.

    .EXAMPLE
        PS C:\> Stop-DbaPfDataCollectorSet -ComputerName sql2017

        Attempts to stop all ready Collectors on localhost.

    .EXAMPLE
        PS C:\> Stop-DbaPfDataCollectorSet -ComputerName sql2017, sql2016 -Credential ad\sqldba -CollectorSet 'System Correlation'

        Stops the 'System Correlation' Collector on sql2017 and sql2016 using alternative credentials.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSet -CollectorSet 'System Correlation' | Stop-DbaPfDataCollectorSet

        Stops the 'System Correlation' Collector.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Alias("DataCollectorSet")]
        [string[]]$CollectorSet,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$NoWait,
        [switch]$EnableException
    )
    begin {
        #Variable marked as unused by PSScriptAnalyzer
        #$sets = @()
        $wait = $NoWait -eq $false

        $setscript = {
            $setname = $args[0]; $wait = $args[1]
            $collectorset = New-Object -ComObject Pla.DataCollectorSet
            $collectorset.Query($setname, $null)
            $null = $collectorset.Stop($wait)
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

            Write-Message -Level Verbose -Message "$setname on $ComputerName is $status."
            if ($status -ne "Running") {
                Stop-Function -Message "$setname on $computer is already stopped." -Continue
            }
            if ($Pscmdlet.ShouldProcess($computer, "Stoping Performance Monitor collection set")) {
                try {
                    Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $setscript -ArgumentList $setname, $wait -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Failure stopping $setname on $computer." -ErrorRecord $_ -Target $computer -Continue
                }

                Get-DbaPfDataCollectorSet -ComputerName $computer -Credential $Credential -CollectorSet $setname
            }
        }
    }
}