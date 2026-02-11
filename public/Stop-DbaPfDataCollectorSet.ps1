function Stop-DbaPfDataCollectorSet {
    <#
    .SYNOPSIS
        Stops Windows Performance Monitor Data Collector Sets used for SQL Server performance monitoring.

    .DESCRIPTION
        Stops running Performance Monitor Data Collector Sets that are actively collecting performance counters for SQL Server monitoring and analysis. This function interacts with the Windows Performance Logs and Alerts (PLA) service to gracefully halt data collection processes. Commonly used to stop baseline data collection after capturing sufficient performance metrics, or to halt monitoring during maintenance windows when counter data isn't needed.

    .PARAMETER ComputerName
        Specifies the target computer where Performance Monitor Data Collector Sets are running. Accepts multiple computer names for bulk operations.
        Use this when stopping collectors on remote SQL Server instances or when managing multiple servers from a central location.
        Defaults to localhost when not specified.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials. To use:

        $cred = Get-Credential, then pass $cred object to the -Credential parameter.

    .PARAMETER CollectorSet
        Specifies the exact name of the Data Collector Set to stop. Supports multiple collector names for stopping several sets simultaneously.
        Use this when you need to stop specific performance monitoring sets without affecting other running collectors on the system.
        Common SQL Server collector sets include 'SQL Server Data Collector Set' and custom monitoring configurations.

    .PARAMETER NoWait
        Returns control immediately after initiating the stop command without waiting for the collector to fully terminate.
        Use this in automated scripts where you need to stop multiple collectors quickly or when the stopping process might take time due to large data buffers being flushed.

    .PARAMETER InputObject
        Accepts Data Collector Set objects from Get-DbaPfDataCollectorSet via pipeline input.
        Use this approach when you need to filter or examine collector properties before stopping them, or when building complex monitoring workflows.

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

    .OUTPUTS
        PSCustomObject

        Returns Data Collector Set objects from Get-DbaPfDataCollectorSet after successfully stopping each collector set.

        Default display properties (via Select-DefaultView in Get-DbaPfDataCollectorSet):
        - ComputerName: The computer where the Data Collector Set is configured
        - Name: The name of the Data Collector Set
        - DisplayName: The user-friendly display name of the collector set
        - Description: Text description of what the collector set monitors
        - State: Current state (should reflect Stopped after successful termination)
        - Duration: Duration in seconds for which the collector set will run
        - OutputLocation: File system path where collected data is stored
        - LatestOutputLocation: Path to the most recently collected output files
        - RootPath: Root directory path for the collector set configuration
        - SchedulesEnabled: Boolean indicating if schedules are enabled
        - Segment: Segment configuration value for data collection
        - SegmentMaxDuration: Maximum duration in seconds for a collection segment
        - SegmentMaxSize: Maximum size in MB for a collection segment
        - SerialNumber: Serial number or identifier for the collector set
        - Server: Name of the server hosting the collector set
        - StopOnCompletion: Whether the collector stops on completion
        - Subdirectory: Subdirectory name for output
        - SubdirectoryFormat: Format for subdirectory naming
        - SubdirectoryFormatPattern: Pattern for subdirectory format
        - Task: Task associated with the collector set
        - TaskArguments: Arguments for the associated task
        - TaskRunAsSelf: Whether the task runs as self
        - TaskUserTextArguments: User text arguments for the task
        - UserAccount: The user account under which the collector set runs

        Note: If a collector set is not in "Running" state, Stop-Function prevents output and returns no objects for that set. Only successfully stopped collectors generate output.

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