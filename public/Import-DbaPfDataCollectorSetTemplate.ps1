function Import-DbaPfDataCollectorSetTemplate {
    <#
    .SYNOPSIS
        Creates Windows Performance Monitor data collector sets with SQL Server-specific performance counters from predefined templates.

    .DESCRIPTION
        Creates Windows Performance Monitor data collector sets using XML templates containing SQL Server performance counters. This eliminates the need to manually configure dozens of performance counters through the Performance Monitor GUI. The function can use built-in templates from the dbatools repository (like 'Long Running Query' or 'db_ola_health') or custom XML template files you specify.

        Performance counters are automatically configured for all SQL Server instances detected on the target machine. When multiple instances exist, the function duplicates relevant counters for each instance so you get complete coverage across your SQL Server environment.

        Requires local administrator privileges on the target computer when importing data collector sets.

        See https://msdn.microsoft.com/en-us/library/windows/desktop/aa371952 for more information

    .PARAMETER ComputerName
        Specifies the Windows server where the Performance Monitor data collector set will be created. Defaults to the local machine.
        Use this when monitoring SQL Server instances on remote servers or when centralizing performance monitoring from a management workstation.

    .PARAMETER Credential
        Allows you to login to servers using alternative credentials. To use:

        $scred = Get-Credential, then pass $scred object to the -Credential parameter.

    .PARAMETER Path
        Specifies the file path to custom XML template files containing performance counter definitions. Accepts multiple file paths.
        Use this when you have custom performance monitoring templates or need to import templates from sources other than the built-in dbatools repository.

    .PARAMETER Template
        Selects predefined performance monitoring templates from the dbatools repository such as 'Long Running Query' or 'db_ola_health'. Press Tab to see available options.
        Use this for quick deployment of SQL Server-specific performance monitoring without creating custom XML templates.

    .PARAMETER RootPath
        Specifies the base directory where performance log files will be stored. Defaults to %systemdrive%\PerfLogs\Admin\[CollectorSetName].
        Change this when you need to store performance logs on a different drive with more space or faster storage for high-frequency data collection.

    .PARAMETER DisplayName
        Sets the display name for the data collector set as it appears in Performance Monitor. Defaults to the template name.
        Use this to create meaningful names when deploying multiple collector sets or to distinguish between environments like 'Prod-SQL-Perf' or 'Dev-Query-Analysis'.

    .PARAMETER SchedulesEnabled
        Enables scheduled data collection for the collector set if defined in the template. When disabled, the collector set must be started manually.
        Use this switch when you want the collector set to automatically start and stop based on predefined schedules rather than manual intervention.

    .PARAMETER Segment
        Enables automatic log file segmentation when maximum file size or duration limits are reached during data collection.
        Use this to prevent single log files from becoming too large and to maintain manageable file sizes for analysis tools and storage management.

    .PARAMETER SegmentMaxDuration
        Specifies the maximum time duration (in seconds) before a new log file is created during data collection. Requires -Segment to be enabled.
        Set this to control how long each performance log file covers, which helps with organizing data by time periods for analysis.

    .PARAMETER SegmentMaxSize
        Specifies the maximum size (in bytes) for each performance log file before a new file is created. Requires -Segment to be enabled.
        Set this to prevent individual log files from consuming excessive disk space and to maintain consistent file sizes for easier management.

    .PARAMETER Subdirectory
        Specifies a subdirectory name under the root path where log files will be stored for this collector set instance.
        Use this to organize performance logs by purpose, environment, or time period within your monitoring directory structure.

    .PARAMETER SubdirectoryFormat
        Controls how Performance Monitor decorates the subdirectory name with timestamp information. Uses numeric flags where 3 includes day/hour formatting.
        This automatically creates time-stamped subdirectories to organize log files chronologically, making it easier to locate performance data from specific time periods.

    .PARAMETER SubdirectoryFormatPattern
        Specifies the timestamp format pattern used for decorating subdirectory names. Default is 'yyyyMMdd\-NNNNNN' (year-month-day-sequence).
        Customize this pattern when you need specific date/time formatting for your log file organization or to match existing naming conventions.

    .PARAMETER Task
        Specifies a Windows Task Scheduler job name to execute automatically when the data collector set stops or between log segments.
        Use this to trigger post-processing tasks like data analysis scripts, log file compression, or alerting when performance data collection completes.

    .PARAMETER TaskRunAsSelf
        Forces the scheduled task to run using the same user account as the data collector set rather than the account specified in the task definition.
        Use this when you need consistent security context between data collection and post-processing tasks for file access permissions.

    .PARAMETER TaskArguments
        Specifies command-line arguments to pass to the scheduled task when it executes after data collection stops.
        Use this to pass parameters like log file paths, collection timestamps, or processing options to your post-collection analysis scripts.

    .PARAMETER TaskUserTextArguments
        Provides replacement text for the {usertext} placeholder variable in task arguments when the scheduled task executes.
        Use this to dynamically pass environment-specific information like server names, database names, or custom identifiers to your post-processing tasks.

    .PARAMETER StopOnCompletion
        Automatically stops the data collector set when all individual data collectors within the set have finished their collection tasks.
        Use this switch when you want the collector set to terminate cleanly after completing defined collection tasks rather than running indefinitely.

    .PARAMETER Instance
        Specifies additional SQL Server named instances to include in performance monitoring beyond the default instance. The template applies to all detected instances by default.
        Use this when you have multiple SQL Server instances on a server and want to add specific named instances like 'SHAREPOINT' or 'REPORTING' to the monitoring scope.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

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
        https://dbatools.io/Import-DbaPfDataCollectorSetTemplate

    .EXAMPLE
        PS C:\> Import-DbaPfDataCollectorSetTemplate -ComputerName sql2017 -Template 'Long Running Query'

        Creates a new data collector set named 'Long Running Query' from the dbatools repository on the SQL Server sql2017.

    .EXAMPLE
        PS C:\> Import-DbaPfDataCollectorSetTemplate -ComputerName sql2017 -Template 'Long Running Query' -DisplayName 'New Long running query' -Confirm

        Creates a new data collector set named "New Long Running Query" using the 'Long Running Query' template. Forces a confirmation if the template exists.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSet -ComputerName sql2017 -Session db_ola_health | Remove-DbaPfDataCollectorSet
        Import-DbaPfDataCollectorSetTemplate -ComputerName sql2017 -Template db_ola_health | Start-DbaPfDataCollectorSet

        Imports a session if it exists, then recreates it using a template.

    .EXAMPLE
        PS C:\> Get-DbaPfDataCollectorSetTemplate | Out-GridView -PassThru | Import-DbaPfDataCollectorSetTemplate -ComputerName sql2017

        Allows you to select a Session template then import to an instance named sql2017.

    .EXAMPLE
        PS C:\> Import-DbaPfDataCollectorSetTemplate -ComputerName sql2017 -Template 'Long Running Query' -Instance SHAREPOINT

        Creates a new data collector set named 'Long Running Query' from the dbatools repository on the SQL Server sql2017 for both the default and the SHAREPOINT instance.

        If you'd like to remove counters for the default instance, use Remove-DbaPfDataCollectorCounter.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [string]$DisplayName,
        [switch]$SchedulesEnabled,
        [string]$RootPath,
        [switch]$Segment,
        [int]$SegmentMaxDuration,
        [int]$SegmentMaxSize,
        [string]$Subdirectory,
        [int]$SubdirectoryFormat = 3,
        [string]$SubdirectoryFormatPattern = 'yyyyMMdd\-NNNNNN',
        [string]$Task,
        [switch]$TaskRunAsSelf,
        [string]$TaskArguments,
        [string]$TaskUserTextArguments,
        [switch]$StopOnCompletion,
        [parameter(ValueFromPipelineByPropertyName)]
        [Alias("FullName")]
        [string[]]$Path,
        [string[]]$Template,
        [string[]]$Instance,
        [switch]$EnableException
    )
    begin {
        #Variable marked as unused by PSScriptAnalyzer
        #$metadata = Import-Clixml "$script:PSModuleRoot\bin\perfmontemplates\collectorsets.xml"

        $setscript = {
            $setname = $args[0]; $templatexml = $args[1]
            $collectorset = New-Object -ComObject Pla.DataCollectorSet
            $collectorset.SetXml($templatexml)
            $null = $collectorset.Commit($setname, $null, 0x0003) #add or modify.
            $null = $collectorset.Query($setname, $Null)
        }

        $instancescript = {
            $services = Get-Service -DisplayName *sql* | Select-Object -ExpandProperty DisplayName
            [regex]::matches($services, '(?<=\().+?(?=\))').Value | Where-Object { $PSItem -ne 'MSSQLSERVER' } | Select-Object -Unique
        }
    }
    process {


        if ((Test-Bound -ParameterName Path -Not) -and (Test-Bound -ParameterName Template -Not)) {
            Stop-Function -Message "You must specify Path or Template"
        }

        if (($Path.Count -gt 1 -or $Template.Count -gt 1) -and (Test-Bound -ParameterName Template)) {
            Stop-Function -Message "Name cannot be specified with multiple files or templates because the Session will already exist"
        }

        foreach ($computer in $ComputerName) {
            $null = Test-ElevationRequirement -ComputerName $computer -Continue

            foreach ($file in $template) {
                $templatepath = "$script:PSModuleRoot\bin\perfmontemplates\collectorsets\$file.xml"
                if ((Test-Path $templatepath)) {
                    $Path += $templatepath
                } else {
                    Stop-Function -Message "Invalid template ($templatepath does not exist)" -Continue
                }
            }

            foreach ($file in $Path) {

                if ((Test-Bound -ParameterName DisplayName -Not)) {
                    Set-Variable -Name DisplayName -Value (Get-ChildItem -Path $file).BaseName
                }

                $Name = $DisplayName

                Write-Message -Level Verbose -Message "Processing $file for $computer"

                if ((Test-Bound -ParameterName RootPath -Not)) {
                    Set-Variable -Name RootName -Value "%systemdrive%\PerfLogs\Admin\$Name"
                }

                # Perform replace
                $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("").TrimEnd("\")
                $tempfile = "$temp\import-dbatools-perftemplate.xml"

                try {
                    # Get content
                    $contents = Get-Content $file -ErrorAction Stop

                    # Replace content
                    $replacements = 'RootPath', 'DisplayName', 'SchedulesEnabled', 'Segment', 'SegmentMaxDuration', 'SegmentMaxSize', 'SubdirectoryFormat', 'SubdirectoryFormatPattern', 'Task', 'TaskRunAsSelf', 'TaskArguments', 'TaskUserTextArguments', 'StopOnCompletion', 'DisplayNameUnresolved'

                    foreach ($replacement in $replacements) {
                        $phrase = "<$replacement></$replacement>"
                        $value = (Get-Variable -Name $replacement -ErrorAction SilentlyContinue).Value
                        if ($value -eq $false) {
                            $value = "0"
                        }
                        if ($value -eq $true) {
                            $value = "1"
                        }
                        $replacephrase = "<$replacement>$value</$replacement>"
                        $contents = $contents.Replace($phrase, $replacephrase)
                    }

                    # Set content
                    $null = Set-Content -Path $tempfile -Value $contents -Encoding Unicode
                    $xml = [xml](Get-Content $tempfile -ErrorAction Stop)
                    $plainxml = Get-Content $tempfile -ErrorAction Stop -Raw
                    $file = $tempfile
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue
                }
                if (-not $xml.DataCollectorSet) {
                    Stop-Function -Message "$file is not a valid Performance Monitor template document" -Continue
                }

                try {
                    Write-Message -Level Verbose -Message "Importing $file as $name "

                    if ($instance) {
                        $instances = $instance
                    } else {
                        $instances = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $instancescript -ErrorAction Stop -Raw
                    }

                    $scriptBlock = {
                        try {
                            $results = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $setscript -ArgumentList $Name, $plainxml -ErrorAction Stop
                            Write-Message -Level Verbose -Message " $results"
                        } catch {
                            Stop-Function -Message "Failure starting $setname on $computer" -ErrorRecord $_ -Target $computer -Continue
                        }
                    }

                    if ((Get-DbaPfDataCollectorSet -ComputerName $computer -CollectorSet $Name)) {
                        if ($Pscmdlet.ShouldProcess($computer, "CollectorSet $Name already exists. Modify?")) {
                            Invoke-Command -Scriptblock $scriptBlock
                            $output = Get-DbaPfDataCollectorSet -ComputerName $computer -CollectorSet $Name
                        }
                    } else {
                        if ($Pscmdlet.ShouldProcess($computer, "Importing collector set $Name")) {
                            Invoke-Command -Scriptblock $scriptBlock
                            $output = Get-DbaPfDataCollectorSet -ComputerName $computer -CollectorSet $Name
                        }
                    }

                    $newcollection = @()
                    foreach ($instance in $instances) {
                        $datacollector = Get-DbaPfDataCollectorSet -ComputerName $computer -CollectorSet $Name | Get-DbaPfDataCollector
                        $sqlcounters = $datacollector | Get-DbaPfDataCollectorCounter | Where-Object { $_.Name -match 'sql.*\:' -and $_.Name -notmatch 'sqlclient' } | Select-Object -ExpandProperty Name

                        foreach ($counter in $sqlcounters) {
                            $split = $counter.Split(":")
                            $firstpart = switch ($split[0]) {
                                'SQLServer' { 'MSSQL' }
                                '\SQLServer' { '\MSSQL' }
                                default { $split[0] }
                            }
                            $secondpart = $split[-1]
                            $finalcounter = "$firstpart`$$instance`:$secondpart"
                            $newcollection += $finalcounter
                        }
                    }

                    if ($newcollection.Count) {
                        if ($Pscmdlet.ShouldProcess($computer, "Adding $($newcollection.Count) additional counters")) {
                            $null = Add-DbaPfDataCollectorCounter -InputObject $datacollector -Counter $newcollection
                        }
                    }

                    Remove-Item $tempfile -ErrorAction SilentlyContinue
                    $output
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $store -Continue
                }
            }
        }
    }
}