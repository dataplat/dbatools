function Get-DbaPfDataCollectorSet {
    <#
    .SYNOPSIS
        Retrieves Windows Performance Monitor Data Collector Sets and their configuration details.

    .DESCRIPTION
        Retrieves detailed information about Windows Performance Monitor Data Collector Sets, which are used to collect performance counters for SQL Server monitoring and troubleshooting. Data Collector Sets define what performance counters to collect, when to collect them, and where to store the collected data. This function helps DBAs inventory existing collector sets, check their status (running, stopped, scheduled), and review their configuration including output locations and schedules. Particularly useful when inheriting a SQL Server environment or auditing existing performance monitoring setup.

    .PARAMETER ComputerName
        Specifies the Windows server(s) where you want to inventory Performance Monitor Data Collector Sets.
        Use this when checking collector sets across multiple SQL Server hosts or when managing performance monitoring from a central location.
        Accepts multiple computer names and defaults to the local computer.

    .PARAMETER Credential
        Allows you to login to servers using alternative credentials. To use:

        $scred = Get-Credential, then pass $scred object to the -Credential parameter.

    .PARAMETER CollectorSet
        Specifies the name(s) of specific Data Collector Sets to retrieve instead of returning all collector sets.
        Use this when you need to check the status or configuration of specific performance monitoring setups like 'SQL Server Default' or custom collector sets.
        Accepts wildcards and multiple collector set names for targeted monitoring inventory.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Performance, DataCollector, PerfCounter
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaPfDataCollectorSet

    .OUTPUTS
        PSCustomObject

        Returns one object per Data Collector Set found on the target computer(s).

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer where the Data Collector Set is configured
        - Name: The name of the Data Collector Set
        - DisplayName: The user-friendly display name of the collector set
        - Description: Text description of what the collector set monitors
        - State: Current state (Unknown, Disabled, Queued, Ready, Running)
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
        - StopOnCompletion: Boolean indicating if the collector set stops automatically when complete
        - Subdirectory: Subdirectory path for organizing collector set output
        - SubdirectoryFormat: Format pattern for subdirectory naming
        - SubdirectoryFormatPattern: Detailed format pattern specification
        - Task: Name of the Windows Task Scheduler task associated with the collector set
        - TaskArguments: Command-line arguments passed to the collector set task
        - TaskRunAsSelf: Boolean indicating if the task runs under the specified user account
        - TaskUserTextArguments: User-specified text arguments for the task
        - UserAccount: Windows user account under which the collector set runs

        Additional properties available (via Select-Object *):
        - Keywords: Keywords associated with the collector set for searching/categorizing
        - DescriptionUnresolved: Raw description text before localization/resolution
        - DisplayNameUnresolved: Raw display name before localization/resolution
        - Schedules: Collection of schedule objects for the collector set
        - Xml: Raw XML configuration of the collector set
        - Security: Security descriptor for the collector set
        - DataCollectorSetObject: Boolean indicating the object came from a Data Collector Set COM object
        - TaskObject: Reference to the underlying Task Scheduler COM object
        - Credential: The credentials used to retrieve this collector set

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSet

        Gets all Collector Sets on localhost.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSet -ComputerName sql2017

        Gets all Collector Sets on sql2017.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSet -ComputerName sql2017 -Credential ad\sqldba -CollectorSet 'System Correlation'

        Gets the 'System Correlation' CollectorSet on sql2017 using alternative credentials.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSet | Select-Object *

        Displays extra columns and also exposes the original COM object in DataCollectorSetObject.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Alias("DataCollectorSet")]
        [string[]]$CollectorSet,
        [switch]$EnableException
    )

    begin {
        $setscript = {
            # Get names / status info
            $schedule = New-Object -ComObject "Schedule.Service"
            $schedule.Connect()
            $folder = $schedule.GetFolder("Microsoft\Windows\PLA")
            $tasks = @()
            $tasknumber = 0
            $done = $false
            do {
                try {
                    $task = $folder.GetTasks($tasknumber)
                    $tasknumber++
                    if ($task) {
                        $tasks += $task
                    }
                } catch {
                    $done = $true
                }
            }
            while ($done -eq $false)
            $null = [System.Runtime.Interopservices.Marshal]::ReleaseComObject($schedule)

            if ($args[0]) {
                $tasks = $tasks | Where-Object Name -in $args[0]
            }

            $sets = New-Object -ComObject Pla.DataCollectorSet
            foreach ($task in $tasks) {
                $setname = $task.Name
                switch ($task.State) {
                    0 { $state = "Unknown" }
                    1 { $state = "Disabled" }
                    2 { $state = "Queued" }
                    3 { $state = "Ready" }
                    4 { $state = "Running" }
                }

                try {
                    # Query changes $sets so work from there
                    $sets.Query($setname, $null)
                    $set = $sets.PSObject.Copy()

                    $outputlocation = $set.OutputLocation
                    $latestoutputlocation = $set.LatestOutputLocation

                    if ($outputlocation) {
                        $dir = (Split-Path $outputlocation).Replace(':', '$')
                        $remote = "\\$env:COMPUTERNAME\$dir"
                    } else {
                        $remote = $null
                    }

                    if ($latestoutputlocation) {
                        $dir = ($latestoutputlocation).Replace(':', '$')
                        $remotelatest = "\\$env:COMPUTERNAME\$dir"
                    } else {
                        $remote = $null
                    }

                    [PSCustomObject]@{
                        ComputerName               = $env:COMPUTERNAME
                        Name                       = $setname
                        LatestOutputLocation       = $set.LatestOutputLocation
                        OutputLocation             = $set.OutputLocation
                        RemoteOutputLocation       = $remote
                        RemoteLatestOutputLocation = $remotelatest
                        RootPath                   = $set.RootPath
                        Duration                   = $set.Duration
                        Description                = $set.Description
                        DescriptionUnresolved      = $set.DescriptionUnresolved
                        DisplayName                = $set.DisplayName
                        DisplayNameUnresolved      = $set.DisplayNameUnresolved
                        Keywords                   = $set.Keywords
                        Segment                    = $set.Segment
                        SegmentMaxDuration         = $set.SegmentMaxDuration
                        SegmentMaxSize             = $set.SegmentMaxSize
                        SerialNumber               = $set.SerialNumber
                        Server                     = $set.Server
                        Status                     = $set.Status
                        Subdirectory               = $set.Subdirectory
                        SubdirectoryFormat         = $set.SubdirectoryFormat
                        SubdirectoryFormatPattern  = $set.SubdirectoryFormatPattern
                        Task                       = $set.Task
                        TaskRunAsSelf              = $set.TaskRunAsSelf
                        TaskArguments              = $set.TaskArguments
                        TaskUserTextArguments      = $set.TaskUserTextArguments
                        Schedules                  = $set.Schedules
                        SchedulesEnabled           = $set.SchedulesEnabled
                        UserAccount                = $set.UserAccount
                        Xml                        = $set.Xml
                        Security                   = $set.Security
                        StopOnCompletion           = $set.StopOnCompletion
                        State                      = $state.Trim()
                        DataCollectorSetObject     = $true
                        TaskObject                 = $task
                        Credential                 = $args[1]
                    }
                } catch {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Warning -Message "Issue with getting Collector Set $setname on $env:Computername : $_."
                    continue
                }
            }
        }

        $columns = 'ComputerName', 'Name', 'DisplayName', 'Description', 'State', 'Duration', 'OutputLocation', 'LatestOutputLocation',
        'RootPath', 'SchedulesEnabled', 'Segment', 'SegmentMaxDuration', 'SegmentMaxSize',
        'SerialNumber', 'Server', 'StopOnCompletion', 'Subdirectory', 'SubdirectoryFormat',
        'SubdirectoryFormatPattern', 'Task', 'TaskArguments', 'TaskRunAsSelf', 'TaskUserTextArguments', 'UserAccount'
    }
    process {


        foreach ($computer in $ComputerName.ComputerName) {
            try {
                Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $setscript -ArgumentList $CollectorSet, $Credential -ErrorAction Stop | Select-DefaultView -Property $columns
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
            }
        }
    }
}