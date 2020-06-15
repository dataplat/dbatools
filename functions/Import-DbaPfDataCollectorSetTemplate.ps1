function Import-DbaPfDataCollectorSetTemplate {
    <#
    .SYNOPSIS
        Imports a new Performance Monitor Data Collector Set Template either from the dbatools repository or a file you specify.

    .DESCRIPTION
        Imports a new Performance Monitor Data Collector Set Template either from the dbatools repository or a file you specify.
        When importing data collector sets from the local instance, Run As Admin is required.

        Note: The included counters will be added for all SQL instances on the machine by default.
        For specific instances in addition to the default, use -Instance.

        See https://msdn.microsoft.com/en-us/library/windows/desktop/aa371952 for more information

    .PARAMETER ComputerName
        The target computer. Defaults to localhost.

    .PARAMETER Credential
        Allows you to login to servers using alternative credentials. To use:

        $scred = Get-Credential, then pass $scred object to the -Credential parameter.

    .PARAMETER Path
        The path to the xml file or files.

    .PARAMETER Template
        From one or more of the templates from the dbatools repository. Press Tab to cycle through the available options.

    .PARAMETER RootPath
        Sets the base path where the subdirectories are created.

    .PARAMETER DisplayName
        Sets the display name of the data collector set.

    .PARAMETER SchedulesEnabled
        If this switch is enabled, sets a value that indicates whether the schedules are enabled.

    .PARAMETER Segment
        Sets a value that indicates whether PLA creates new logs if the maximum size or segment duration is reached before the data collector set is stopped.

    .PARAMETER SegmentMaxDuration
        Sets the duration that the data collector set can run before it begins writing to new log files.

    .PARAMETER SegmentMaxSize
        Sets the maximum size of any log file in the data collector set.

    .PARAMETER Subdirectory
        Sets a base subdirectory of the root path where the next instance of the data collector set will write its logs.

    .PARAMETER SubdirectoryFormat
        Sets flags that describe how to decorate the subdirectory name. PLA appends the decoration to the folder name. For example, if you specify plaMonthDayHour, PLA appends the current month, day, and hour values to the folder name. If the folder name is MyFile, the result could be MyFile110816.

    .PARAMETER SubdirectoryFormatPattern
        Sets a format pattern to use when decorating the folder name. Default is 'yyyyMMdd\-NNNNNN'.

    .PARAMETER Task
        Sets the name of a Task Scheduler job to start each time the data collector set stops, including between segments.

    .PARAMETER TaskRunAsSelf
        If this switch is enabled, sets a value that determines whether the task runs as the data collector set user or as the user specified in the task.

    .PARAMETER TaskArguments
        Sets the command-line arguments to pass to the Task Scheduler job specified in the IDataCollectorSet::Task property.
        See https://msdn.microsoft.com/en-us/library/windows/desktop/aa371992 for more information.

    .PARAMETER TaskUserTextArguments
        Sets the command-line arguments that are substituted for the {usertext} substitution variable in the IDataCollectorSet::TaskArguments property.
        See https://msdn.microsoft.com/en-us/library/windows/desktop/aa371993 for more information.

    .PARAMETER StopOnCompletion
        If this switch is enabled, sets a value that determines whether the data collector set stops when all the data collectors in the set are in a completed state.

    .PARAMETER Instance
        By default, the template will be applied to all instances. If you want to set specific ones in addition to the default, supply just the instance name.

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