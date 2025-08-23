function Get-DbaAgentJobHistory {
    <#
    .SYNOPSIS
        Retrieves SQL Server Agent job execution history from msdb database for troubleshooting and compliance reporting.

    .DESCRIPTION
        Get-DbaAgentJobHistory queries the msdb database to retrieve detailed execution records for SQL Server Agent jobs, helping you troubleshoot failures, monitor performance trends, and generate compliance reports. This function accesses the same historical data you'd find in SQL Server Management Studio's Job Activity Monitor, but with powerful filtering and output options.

        The function is essential when investigating why jobs failed, analyzing execution patterns over time, or preparing audit documentation. You can filter results by specific jobs, date ranges, or outcome types (failed, succeeded, retry, etc.), and optionally include job step details or just summary-level information.

        Results include calculated fields like duration, formatted start/end dates, and readable status descriptions. When used with -WithOutputFile, it resolves SQL Agent token placeholders in output file paths, making it easier to locate job logs for further investigation.

        Historical data availability depends on your SQL Agent history cleanup settings - older executions may have been purged based on your retention configuration.

        https://msdn.microsoft.com/en-us/library/ms201680.aspx
        https://msdn.microsoft.com/en-us/library/microsoft.sqlserver.management.smo.agent.jobhistoryfilter(v=sql.120).aspx

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        Specifies specific SQL Agent jobs to retrieve history for by name. Accepts wildcards and arrays for multiple jobs.
        Use this when investigating specific job failures or monitoring particular maintenance routines instead of reviewing all job history.

    .PARAMETER ExcludeJob
        Excludes specified jobs from the history results by name. Accepts arrays for multiple job exclusions.
        Useful when you want to review most jobs but skip noisy or less critical ones like frequent maintenance jobs.

    .PARAMETER StartDate
        Sets the earliest date and time for job history records to include. Defaults to 1900-01-01 to include all available history.
        Specify this when investigating issues within a specific timeframe or when older history isn't relevant to your troubleshooting.

    .PARAMETER EndDate
        Sets the latest date and time for job history records to include. Defaults to current date and time.
        Use this with StartDate to focus on a specific time window when troubleshooting incidents or analyzing patterns during maintenance windows.

    .PARAMETER OutcomeType
        Filters job history to only show executions with a specific completion result. Valid values are Failed, Succeeded, Retry, Cancelled, InProgress, Unknown.
        Most commonly used with 'Failed' when troubleshooting job failures or 'Succeeded' when verifying successful completion patterns.

    .PARAMETER ExcludeJobSteps
        Returns only job-level execution summaries, excluding individual step details. Shows overall job success/failure without step-by-step breakdown.
        Use this when you need high-level job completion status for reporting or when step details aren't needed for your analysis.

    .PARAMETER WithOutputFile
        Includes resolved output file paths for job steps that write to files. Automatically resolves SQL Agent token placeholders like $(SQLLOGDIR) to actual paths.
        Essential when you need to locate and review job output files for troubleshooting failures or verifying job step results.

    .PARAMETER JobCollection
        Accepts an array of SQL Server Management Objects (SMO) job objects instead of job names. Enables pipeline input from Get-DbaAgentJob.
        Use this when you need to filter jobs by complex criteria first, then get their history, such as jobs matching specific patterns or properties.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job
        Author: Klaas Vandenberghe (@PowerDbaKlaas) | Simone Bizzotto (@niphold)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentJobHistory

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance localhost

        Returns all SQL Agent Job execution results on the local default SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance localhost, sql2016

        Returns all SQL Agent Job execution results for the local and sql2016 SQL Server instances.

    .EXAMPLE
        PS C:\> 'sql1','sql2\Inst2K17' | Get-DbaAgentJobHistory

        Returns all SQL Agent Job execution results for sql1 and sql2\Inst2K17.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 | Select-Object *

        Returns all properties for all SQl Agent Job execution results on sql2\Inst2K17.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -Job 'Output File Cleanup'

        Returns all properties for all SQl Agent Job execution results of the 'Output File Cleanup' job on sql2\Inst2K17.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -Job 'Output File Cleanup' -WithOutputFile

        Returns all properties for all SQl Agent Job execution results of the 'Output File Cleanup' job on sql2\Inst2K17,
        with additional properties that show the output filename path

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -ExcludeJobSteps

        Returns the SQL Agent Job execution results for the whole jobs on sql2\Inst2K17, leaving out job step execution results.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -StartDate '2017-05-22' -EndDate '2017-05-23 12:30:00'

        Returns the SQL Agent Job execution results between 2017/05/22 00:00:00 and 2017/05/23 12:30:00 on sql2\Inst2K17.

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sql2016 | Where-Object Name -Match backup | Get-DbaAgentJobHistory

        Gets all jobs with the name that match the regex pattern "backup" and then gets the job history from those. You can also use -Like *backup* in this example.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobHistory -SqlInstance sql2016 -OutcomeType Failed

        Returns only the failed SQL Agent Job execution results for the sql2016 SQL Server instance.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Server")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Job,
        [object[]]$ExcludeJob,
        [DateTime]$StartDate = "1900-01-01",
        [DateTime]$EndDate = $(Get-Date),
        [ValidateSet('Failed', 'Succeeded', 'Retry', 'Cancelled', 'InProgress', 'Unknown')]
        [Microsoft.SqlServer.Management.Smo.Agent.CompletionResult]$OutcomeType,
        [switch]$ExcludeJobSteps,
        [switch]$WithOutputFile,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Collection")]
        [Microsoft.SqlServer.Management.Smo.Agent.Job]$JobCollection,
        [switch]$EnableException
    )

    begin {
        $filter = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobHistoryFilter
        $filter.StartRunDate = $StartDate
        $filter.EndRunDate = $EndDate

        if (Test-Bound OutcomeType) {
            $filter.OutcomeTypes = $OutcomeType
        }

        if ($ExcludeJobSteps -and $WithOutputFile) {
            Stop-Function -Message "You can't use -ExcludeJobSteps and -WithOutputFile together"
        }

        function Get-JobHistory {
            [CmdletBinding()]
            param (
                $Server,
                $Job,
                [switch]$WithOutputFile
            )
            $tokenrex = [regex]'\$\((?<method>[^()]+)\((?<tok>[^)]+)\)\)|\$\((?<tok>[^)]+)\)'
            $propmap = @{
                'INST'      = $Server.ServiceName
                'MACH'      = $Server.ComputerName
                'SQLDIR'    = $Server.InstallDataDirectory
                'SQLLOGDIR' = $Server.ErrorLogPath
                #'STEPCT' loop number ?
                'SRVR'      = $Server.DomainInstanceName
                # WMI( property ) impossible
            }


            $squote_rex = [regex]"(?<!')'(?!')"
            $dquote_rex = [regex]'(?<!")"(?!")'
            $rbrack_rex = [regex]'(?<!])](?!])'

            function Resolve-TokenEscape($method, $value) {
                if (!$method) {
                    return $value
                }
                $value = switch ($method) {
                    'ESCAPE_SQUOTE' { $squote_rex.Replace($value, "''") }
                    'ESCAPE_DQUOTE' { $dquote_rex.Replace($value, '""') }
                    'ESCAPE_RBRACKET' { $rbrack_rex.Replace($value, ']]') }
                    'ESCAPE_NONE' { $value }
                    default { $value }
                }
                return $value
            }

            #'STEPID' =  stepid
            #'STRTTM' job begin time
            #'STRTDT' job begin date
            #'JOBID' = JobId
            function Resolve-JobToken($exec, $outfile, $outcome) {
                $n = $tokenrex.Matches($outfile)
                foreach ($x in $n) {
                    $tok = $x.Groups['tok'].Value
                    $EscMethod = $x.Groups['method'].Value
                    if ($propmap.containskey($tok)) {
                        $repl = Resolve-TokenEscape -method $EscMethod -value $propmap[$tok]
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'STEPID') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value $exec.StepID
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'JOBID') {
                        # convert(binary(16), ?)
                        $repl = @('0x') + @($exec.JobID.ToByteArray() | ForEach-Object -Process { $_.ToString('X2') }) -join ''
                        $repl = Resolve-TokenEscape -method $EscMethod -value $repl
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'STRTDT') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value $outcome.RunDate.toString('yyyyMMdd')
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'STRTTM') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value ([int]$outcome.RunDate.toString('HHmmss')).toString()
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'DATE') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value $exec.RunDate.toString('yyyyMMdd')
                        $outfile = $outfile.Replace($x.Value, $repl)
                    } elseif ($tok -eq 'TIME') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value ([int]$exec.RunDate.toString('HHmmss')).toString()
                        $outfile = $outfile.Replace($x.Value, $repl)
                    }
                }
                return $outfile
            }
            try {
                Write-Message -Message "Attempting to get job history from $instance" -Level Verbose
                if ($Job) {
                    foreach ($currentjob in $Job) {
                        $filter.JobName = $currentjob
                        $executions += $server.JobServer.EnumJobHistory($filter)
                    }
                } else {
                    $executions = $server.JobServer.EnumJobHistory($filter)
                }
                if ($ExcludeJobSteps) {
                    $executions = $executions | Where-Object { $_.StepID -eq 0 }
                }

                if ($WithOutputFile) {
                    $outmap = @{ }
                    $outfiles = Get-DbaAgentJobOutputFile -SqlInstance $Server -SqlCredential $SqlCredential -Job $Job

                    foreach ($out in $outfiles) {
                        if (!$outmap.ContainsKey($out.Job)) {
                            $outmap[$out.Job] = @{ }
                        }
                        $outmap[$out.Job][$out.StepId] = $out.OutputFileName
                    }
                }
                $outcome = [PSCustomObject]@{ }
                foreach ($execution in $executions) {
                    $status = switch ($execution.RunStatus) {
                        0 { "Failed" }
                        1 { "Succeeded" }
                        2 { "Retry" }
                        3 { "Canceled" }
                    }

                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    $DurationInSeconds = ($execution.RunDuration % 100) + [math]::floor( ($execution.RunDuration % 10000 ) / 100 ) * 60 + [math]::floor( ($execution.RunDuration % 1000000 ) / 10000 ) * 60 * 60
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name StartDate -value ([dbadatetime]$execution.RunDate)
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name EndDate -value ([dbadatetime]$execution.RunDate.AddSeconds($DurationInSeconds))
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name Duration -value ([prettytimespan](New-TimeSpan -Seconds $DurationInSeconds))
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name Status -value $status
                    if ($WithOutputFile) {
                        if ($execution.StepID -eq 0) {
                            $outcome = $execution
                        }
                        try {
                            $outname = $outmap[$execution.JobName][$execution.StepID]
                            $outname = Resolve-JobToken -exec $execution -outcome $outcome -outfile $outname
                            $outremote = Join-AdminUNC $Server.ComputerName $outname
                        } catch {
                            $outname = ''
                            $outremote = ''
                        }
                        Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name OutputFileName -value $outname
                        Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name RemoteOutputFileName -value $outremote
                        # Add this in for easier ConvertTo-DbaTimeline Support
                        Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name TypeName -value AgentJobHistory
                        Select-DefaultView -InputObject $execution -Property ComputerName, InstanceName, SqlInstance, 'JobName as Job', StepName, RunDate, StartDate, EndDate, Duration, Status, OperatorEmailed, Message, OutputFileName, RemoteOutputFileName -TypeName AgentJobHistory
                    } else {
                        Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name TypeName -value AgentJobHistory
                        Select-DefaultView -InputObject $execution -Property ComputerName, InstanceName, SqlInstance, 'JobName as Job', StepName, RunDate, StartDate, EndDate, Duration, Status, OperatorEmailed, Message -TypeName AgentJobHistory
                    }

                }
            } catch {
                Stop-Function -Message "Could not get Agent Job History from $instance" -Target $instance -Continue
            }
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        if ($JobCollection) {
            foreach ($currentjob in $JobCollection) {
                Get-JobHistory -Server $currentjob.Parent.Parent -Job $currentjob.Name -WithOutputFile:$WithOutputFile
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($ExcludeJob) {
                $jobs = $server.JobServer.Jobs.Name | Where-Object { $_ -notin $ExcludeJob }
                foreach ($currentjob in $jobs) {
                    Get-JobHistory -Server $server -Job $currentjob -WithOutputFile:$WithOutputFile
                }
            } else {
                Get-JobHistory -Server $server -Job $Job -WithOutputFile:$WithOutputFile
            }
        }
    }
}