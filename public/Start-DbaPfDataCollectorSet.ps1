function Start-DbaPfDataCollectorSet {
    <#
    .SYNOPSIS
        Starts Windows Performance Monitor Data Collector Sets on local or remote computers.

    .DESCRIPTION
        Starts Performance Monitor Data Collector Sets that have been configured to gather system performance data. This is useful for SQL Server performance troubleshooting when you need to collect OS-level metrics like CPU, memory, disk I/O, and network statistics alongside your SQL Server monitoring. The function checks the collector set status before starting and will skip sets that are already running or disabled.

    .PARAMETER ComputerName
        Specifies the target computer(s) where Performance Monitor Data Collector Sets will be started. Defaults to localhost.
        Use this when you need to start collector sets on remote SQL Server machines or when managing multiple servers from a central location.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials. To use:

        $cred = Get-Credential, then pass $cred object to the -Credential parameter.

    .PARAMETER CollectorSet
        Specifies the name(s) of specific Performance Monitor Data Collector Sets to start. When omitted, all ready collector sets will be started.
        Use this when you only need to start particular collector sets like 'System Performance' or custom sets created for SQL Server monitoring.

    .PARAMETER NoWait
        When specified, starts the collector set and returns results immediately without waiting for the startup process to complete.
        Use this when starting multiple collector sets in scripts where you don't need to confirm each one fully initialized before proceeding.

    .PARAMETER InputObject
        Accepts Performance Monitor Data Collector Set objects from Get-DbaPfDataCollectorSet via the pipeline. Objects must contain DataCollectorSetObject property.
        Use this when you want to filter collector sets with Get-DbaPfDataCollectorSet first, then start only the matching sets through the pipeline.

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

    .OUTPUTS
        PSCustomObject

        Returns one Performance Monitor Data Collector Set object for each collector set that was successfully started.

        Default display properties (via Get-DbaPfDataCollectorSet):
        - ComputerName: The name of the computer where the Data Collector Set is located
        - Name: The name of the Data Collector Set
        - State: The current state of the Data Collector Set (Running, Stopped, etc.)

        Additional properties available (access via Select-Object *):
        - DataCollectorSetObject: The underlying Windows Performance Monitor Data Collector Set COM object

        Returns nothing if no collector sets are found matching the specified parameters, if they are already running, if they are disabled, or if the -WhatIf parameter is used.

    .LINK
        https://dbatools.io/Start-DbaPfDataCollectorSet

    .EXAMPLE
        PS C:\> Start-DbaPfDataCollectorSet

        Attempts to start all ready Collectors on localhost.

    .EXAMPLE
        PS C:\> Start-DbaPfDataCollectorSet -ComputerName sql2017

        Attempts to start all ready Collectors on localhost.

    .EXAMPLE
        PS C:\> Start-DbaPfDataCollectorSet -ComputerName sql2017, sql2016 -Credential ad\sqldba -CollectorSet 'System Correlation'

        Starts the 'System Correlation' Collector on sql2017 and sql2016 using alternative credentials.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSet -CollectorSet 'System Correlation' | Start-DbaPfDataCollectorSet

        Starts the 'System Correlation' Collector.

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
        $wait = $NoWait -eq $false

        $setscript = {
            $setname = $args[0]; $wait = $args[1]
            $collectorset = New-Object -ComObject Pla.DataCollectorSet
            $collectorset.Query($setname, $null)
            $null = $collectorset.Start($wait)
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
            if ($Pscmdlet.ShouldProcess($computer, "Starting Performance Monitor collection set")) {
                if ($status -eq "Running") {
                    Stop-Function -Message "$setname on $computer is already running." -Continue
                }
                if ($status -eq "Disabled") {
                    Stop-Function -Message "$setname on $computer is disabled." -Continue
                }
                try {
                    Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $setscript -ArgumentList $setname, $wait -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Failure starting $setname on $computer." -ErrorRecord $_ -Target $computer -Continue
                }

                Get-DbaPfDataCollectorSet -ComputerName $computer -Credential $Credential -CollectorSet $setname
            }
        }
    }
}