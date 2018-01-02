function Get-DbaAgentJobHistory {
    <#
        .SYNOPSIS
            Gets execution history of SQL Agent Job on instance(s) of SQL Server.

        .DESCRIPTION
            Get-DbaAgentJobHistory returns all information on the executions still available on each instance(s) of SQL Server submitted.
            The cleanup of SQL Agent history determines how many records are kept.

            https://msdn.microsoft.com/en-us/library/ms201680.aspx
            https://msdn.microsoft.com/en-us/library/microsoft.sqlserver.management.smo.agent.jobhistoryfilter(v=sql.120).aspx

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
            to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            SqlCredential object to connect as. If not specified, current Windows login will be used.

        .PARAMETER Job
            The name of the job from which the history is wanted. If unspecified, all jobs will be processed.

        .PARAMETER ExcludeJob
        The job(s) to exclude - this list is auto-populated from the server

        .PARAMETER StartDate
            The DateTime starting from which the history is wanted. If unspecified, all available records will be processed.

        .PARAMETER EndDate
            The DateTime before which the history is wanted. If unspecified, all available records will be processed.

        .PARAMETER NoJobSteps
            Use this switch to discard all job steps, and return only the job totals

        .PARAMETER WithOutputFile
            Use this switch to retrieve the output file (only if you want step details). Bonus points, we handle the quirks
            of SQL Agent tokens to the best of our knowledge (https://technet.microsoft.com/it-it/library/ms175575(v=sql.110).aspx)

        .PARAMETER JobCollection
            An array of SMO jobs

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Job, Agent
            Author: Klaas Vandenberghe ( @PowerDbaKlaas )
            Editor: niphlod

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaAgentJobHistory

        .EXAMPLE
            Get-DbaAgentJobHistory -SqlInstance localhost

            Returns all SQL Agent Job execution results on the local default SQL Server instance.

        .EXAMPLE
            Get-DbaAgentJobHistory -SqlInstance localhost, sql2016

            Returns all SQL Agent Job execution results for the local and sql2016 SQL Server instances.

        .EXAMPLE
            'sql1','sql2\Inst2K17' | Get-DbaAgentJobHistory

            Returns all SQL Agent Job execution results for sql1 and sql2\Inst2K17.

        .EXAMPLE
            Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 | select *

            Returns all properties for all SQl Agent Job execution results on sql2\Inst2K17.

        .EXAMPLE
            Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -Job 'Output File Cleanup'

            Returns all properties for all SQl Agent Job execution results of the 'Output File Cleanup' job on sql2\Inst2K17.


        .EXAMPLE
            Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -Job 'Output File Cleanup' -WithOutputFile

            Returns all properties for all SQl Agent Job execution results of the 'Output File Cleanup' job on sql2\Inst2K17,
            with additional properties that show the output filename path

        .EXAMPLE
            Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -NoJobSteps

            Returns the SQL Agent Job execution results for the whole jobs on sql2\Inst2K17, leaving out job step execution results.

        .EXAMPLE
            Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -StartDate '2017-05-22' -EndDate '2017-05-23 12:30:00'

            Returns the SQL Agent Job execution results between 2017/05/22 00:00:00 and 2017/05/23 12:30:00 on sql2\Inst2K17.

        .EXAMPLE
            Get-DbaAgentJob -SqlInstance sql2016 | Where Name -match backup | Get-DbaAgentJobHistory

            Gets all jobs with the name that match the regex pattern "backup" and then gets the job history from those. You can also use -Like *backup* in this example.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Server")]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Job,
        [object[]]$ExcludeJob,
        [DateTime]$StartDate = "1900-01-01",
        [DateTime]$EndDate = $(Get-Date),
        [switch]$NoJobSteps,
        [switch]$WithOutputFile,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Collection")]
        [Microsoft.SqlServer.Management.Smo.Agent.Job]$JobCollection,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        $filter = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobHistoryFilter
        $filter.StartRunDate = $StartDate
        $filter.EndRunDate = $EndDate


        if ($NoJobSteps -and $WithOutputFile) {
            Stop-Function -Message "You can't use -NoJobSteps and -WithOutputFile together"
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
                'MACH'      = $Server.NetName
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
                    }
                    elseif ($tok -eq 'STEPID') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value $exec.StepID
                        $outfile = $outfile.Replace($x.Value, $repl)
                    }
                    elseif ($tok -eq 'JOBID') {
                        # convert(binary(16), ?)
                        $repl = @('0x') + @($exec.JobID.ToByteArray() | foreach { $_.ToString('X2') }) -join ''
                        $repl = Resolve-TokenEscape -method $EscMethod -value $repl
                        $outfile = $outfile.Replace($x.Value, $repl)
                    }
                    elseif ($tok -eq 'STRTDT') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value $outcome.RunDate.toString('yyyyMMdd')
                        $outfile = $outfile.Replace($x.Value, $repl)
                    }
                    elseif ($tok -eq 'STRTTM') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value ([int]$outcome.RunDate.toString('HHmmss')).toString()
                        $outfile = $outfile.Replace($x.Value, $repl)
                    }
                    elseif ($tok -eq 'DATE') {
                        $repl = Resolve-TokenEscape -method $EscMethod -value $exec.RunDate.toString('yyyyMMdd')
                        $outfile = $outfile.Replace($x.Value, $repl)
                    }
                    elseif ($tok -eq 'TIME') {
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
                }
                else {
                    $executions = $server.JobServer.EnumJobHistory($filter)
                }
                if ($NoJobSteps) {
                    $executions = $executions | Where-Object { $_.StepID -eq 0 }
                }

                if ($WithOutputFile) {
                    $outmap = @{}
                    $outfiles = Get-DbaAgentJobOutputFile -SqlInstance $Server -SqlCredential $SqlCredential -Job $Job

                    foreach ($out in $outfiles) {
                        if (!$outmap.ContainsKey($out.Job)) {
                            $outmap[$out.Job] = @{}
                        }
                        $outmap[$out.Job][$out.StepId] = $out.OutputFileName
                    }
                }
                $outcome = [pscustomobject]@{}
                foreach ($execution in $executions) {
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name ComputerName -value $server.NetName
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    if ($WithOutputFile) {
                        if ($execution.StepID -eq 0) {
                            $outcome = $execution
                        }
                        try {
                            $outname = $outmap[$execution.JobName][$execution.StepID]
                            $outname = Resolve-JobToken -exec $execution -outcome $outcome -outfile $outname
                            $outremote = Join-AdminUNC $Server.NetName $outname
                        }
                        catch {
                            $outname = ''
                            $outremote = ''
                        }
                        Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name OutputFileName -value $outname
                        Add-Member -Force -InputObject $execution -MemberType NoteProperty -Name RemoteOutputFileName -value $outremote
                        Select-DefaultView -InputObject $execution -Property ComputerName, InstanceName, SqlInstance, 'JobName as Job', StepName, RunDate, RunDuration, RunStatus, OutputFileName, RemoteOutputFileName
                    }
                    else {
                        Select-DefaultView -InputObject $execution -Property ComputerName, InstanceName, SqlInstance, 'JobName as Job', StepName, RunDate, RunDuration, RunStatus
                    }

                }
            }
            catch {
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
            Write-Message -Message "Attempting to connect to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }


            if ($ExcludeJob) {
                $jobs = $server.JobServer.Jobs.Name | Where-Object { $_ -notin $ExcludeJob }
                foreach ($currentjob in $jobs) {
                    Get-JobHistory -Server $server -Job $currentjob -WithOutputFile:$WithOutputFile
                }
            }
            else {
                Get-JobHistory -Server $server -Job $Job -WithOutputFile:$WithOutputFile
            }
        }
    }
}