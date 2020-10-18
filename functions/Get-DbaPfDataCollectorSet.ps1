function Get-DbaPfDataCollectorSet {
    <#
    .SYNOPSIS
        Gets Performance Monitor Data Collector Set.

    .DESCRIPTION
        Gets Performance Monitor Data Collector Set.

    .PARAMETER ComputerName
        The target computer. Defaults to localhost.

    .PARAMETER Credential
        Allows you to login to servers using alternative credentials. To use:

        $scred = Get-Credential, then pass $scred object to the -Credential parameter.

    .PARAMETER CollectorSet
        The Collector set name.

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

                    [pscustomobject]@{
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