function Get-DbaAgentJobOutputFile {
    <#
    .SYNOPSIS
        Retrieves output file paths configured for SQL Agent job steps

    .DESCRIPTION
        This function returns the file paths where SQL Agent job steps write their output logs. When troubleshooting failed jobs or reviewing execution history, DBAs often need to locate these output files to examine detailed error messages and execution details. The function returns both the local file path and the UNC path for remote access, but only displays job steps that have an output file configured.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SQLCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance. be it Windows or SQL Server. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER Job
        Specifies specific SQL Agent jobs to examine for output file configurations. Accepts job names as strings and supports multiple values.
        Use this when you need to check output file paths for specific jobs rather than scanning all jobs on the instance.

    .PARAMETER ExcludeJob
        Specifies SQL Agent jobs to exclude from the output file search. Accepts job names as strings and supports multiple values.
        Use this when you want to scan most jobs but skip specific ones, such as excluding system maintenance jobs or jobs you know don't use output files.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job
        Author: Rob Sewell (sqldbawithabeard.com) | Simone Bizzotto (@niphlod)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentJobOutputFile

    .EXAMPLE
        PS C:\> Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME -Job 'The Agent Job'

        This will return the configured paths to the output files for each of the job step of the The Agent Job Job
        on the SERVERNAME instance

    .EXAMPLE
        PS C:\> Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME

        This will return the configured paths to the output files for each of the job step of all the Agent Jobs
        on the SERVERNAME instance

    .EXAMPLE
        PS C:\> Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME,SERVERNAME2 -Job 'The Agent Job'

        This will return the configured paths to the output files for each of the job step of the The Agent Job Job
        on the SERVERNAME instance and SERVERNAME2

    .EXAMPLE
        PS C:\> Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME  | Out-GridView

        This will return the configured paths to the output files for each of the job step of all the Agent Jobs
        on the SERVERNAME instance and Pipe them to Out-GridView

    .EXAMPLE
        PS C:\> Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME -Verbose

        This will return the configured paths to the output files for each of the job step of all the Agent Jobs
        on the SERVERNAME instance and also show the job steps without an output file

    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, HelpMessage = 'The SQL Server Instance',
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            ValueFromRemainingArguments = $false,
            Position = 0)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(HelpMessage = 'SQL Credential',
            ValueFromPipelineByPropertyName,
            ValueFromRemainingArguments = $false,
            Position = 1)]
        [PSCredential]$SqlCredential,
        [object[]]$Job,
        [object[]]$ExcludeJob,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $jobs = $server.JobServer.Jobs
            if ($Job) {
                $jobs = $jobs | Where-Object Name -In $Job
            }
            if ($ExcludeJob) {
                $jobs = $jobs | Where-Object Name -NotIn $ExcludeJob
            }
            foreach ($j in $Jobs) {
                foreach ($step in $j.JobSteps) {
                    if ($step.OutputFileName) {
                        [PSCustomObject]@{
                            ComputerName         = $server.ComputerName
                            InstanceName         = $server.ServiceName
                            SqlInstance          = $server.DomainInstanceName
                            Job                  = $j.Name
                            JobStep              = $step.Name
                            OutputFileName       = $step.OutputFileName
                            RemoteOutputFileName = Join-AdminUNC $server.ComputerName $step.OutputFileName
                            StepId               = $step.Id
                        } | Select-DefaultView -ExcludeProperty StepId
                    } else {
                        Write-Message -Level Verbose -Message "$step for $j has no output file"
                    }
                }
            }
        }
    }
}