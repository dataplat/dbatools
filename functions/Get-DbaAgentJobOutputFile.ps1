function Get-DbaAgentJobOutputFile {
    <#
    .Synopsis
        Returns the Output File for each step of one or many agent job with the Job Names provided dynamically if
        required for one or more SQL Instances

    .DESCRIPTION
        This function returns for one or more SQL Instances the output file value for each step of one or many agent job with the Job Names
        provided dynamically. It will not return anything if there is no Output File

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SQLCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance. be it Windows or SQL Server. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER Job
        The job(s) to process - this list is auto-populated from the server. If unspecified, all jobs will be processed.

    .PARAMETER ExcludeJob
        The job(s) to exclude - this list is auto-populated from the server

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job
        Author: Rob Sewell (https://sqldbawithabeard.com) | Simone Bizzotto (@niphold)

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
        $Servers = 'SERVER','SERVER\INSTANCE1'
        Get-DbaAgentJobOutputFile -SqlInstance $Servers -Job 'The Agent Job' -OpenFile

        This will return the configured paths to the output files for each of the job step of the The Agent Job Job
        on the SERVER instance and the SERVER\INSTANCE1 and open the files if they are available

    .EXAMPLE
        PS C:\> Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME  | Out-GridView

        This will return the configured paths to the output files for each of the job step of all the Agent Jobs
        on the SERVERNAME instance and Pipe them to Out-GridView

    .EXAMPLE
        PS C:\> (Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME | Out-GridView -PassThru).FileName | Invoke-Item

        This will return the configured paths to the output files for each of the job step of all the Agent Jobs
        on the SERVERNAME instance and Pipe them to Out-GridView and enable you to choose the output
        file and open it

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
        foreach ($instance in $sqlinstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $jobs = $Server.JobServer.Jobs
            if ($Job) {
                $jobs = $jobs | Where-Object Name -In $Job
            }
            if ($ExcludeJob) {
                $jobs = $jobs | Where-Object Name -NotIn $ExcludeJob
            }
            foreach ($j in $Jobs) {
                foreach ($Step in $j.JobSteps) {
                    if ($Step.OutputFileName) {
                        [pscustomobject]@{
                            ComputerName         = $server.ComputerName
                            InstanceName         = $server.ServiceName
                            SqlInstance          = $server.DomainInstanceName
                            Job                  = $j.Name
                            JobStep              = $Step.Name
                            OutputFileName       = $Step.OutputFileName
                            RemoteOutputFileName = Join-AdminUNC $Server.ComputerName $Step.OutputFileName
                            StepId               = $Step.Id
                        } | Select-DefaultView -ExcludeProperty StepId
                    } else {
                        Write-Message -Level Verbose -Message "$step for $j has no output file"
                    }
                }
            }
        }
    }
}