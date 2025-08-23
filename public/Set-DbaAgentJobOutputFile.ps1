function Set-DbaAgentJobOutputFile {
    <#
    .Synopsis
        Configures the output file path for SQL Server Agent job steps to capture step execution logs.

    .DESCRIPTION
        Modifies the output file location where SQL Server Agent writes job step execution details, error messages, and command output. This centralizes logging for troubleshooting failed jobs, monitoring step execution, and maintaining audit trails without manually editing each job step through SQL Server Management Studio. When no specific step is provided, an interactive selection interface appears for jobs with multiple steps.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SQLCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance. be it Windows or SQL Server. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER Job
        The name of the job to process.

        This parameter is not officially mandatory, but you will always be asked to provide a job if you have not.

    .PARAMETER Step
        The name of the Agent Job Step to provide Output File Path for.

        Within a job, step names are unique so this is a safe way to select steps.

        Also available dynamically. If you do not specify this parameter and the target job has only one step, then we use that step. If it has more than one, then a GUI will be used to make you pick steps. If that GUI does not work, then we use all steps.

    .PARAMETER OutputFile
        The Full Path to the New Output file.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job, SqlAgent
        Author: Rob Sewell, sqldbawithabeard.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        .LINK
        https://dbatools.io/Set-DbaAgentJobOutputFile

    .EXAMPLE
        PS C:\> Set-DbaAgentJobOutputFile -SqlInstance SERVERNAME -Job 'The Agent Job' -OutPutFile E:\Logs\AgentJobStepOutput.txt

        Sets the Job step for The Agent job on SERVERNAME to E:\Logs\AgentJobStepOutput.txt

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, HelpMessage = 'The SQL Server Instance',
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            ValueFromRemainingArguments = $false,
            Position = 0)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(HelpMessage = 'SQL Credential',
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            ValueFromRemainingArguments = $false)]
        [PSCredential]$SqlCredential,
        [object[]]$Job,
        [Parameter(HelpMessage = 'The Job Step name',
            ValueFromPipeline,
            ValueFromPipelineByPropertyName)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [object[]]$Step,
        [Parameter(Mandatory, HelpMessage = 'The Full Output File Path',
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            ValueFromRemainingArguments = $false)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]$OutputFile,
        [switch]$EnableException
    )

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        }

        if (!$Job) {
            # This is because jobname isn't yet required
            Write-Message -Level Warning -Message "You must specify a job using the -Job parameter."
            return
        }

        foreach ($name in $Job) {
            $currentJob = $server.JobServer.Jobs[$name]

            if ($Step) {
                $steps = $currentJob.JobSteps | Where-Object Name -in $Step

                if (!$steps) {
                    Write-Message -Level Warning -Message "$Step didn't return any steps"
                    return
                }
            } else {
                if (($currentJob.JobSteps).Count -gt 1) {
                    Write-Message -Level Output -Message "Which Job Step do you wish to add output file to?"
                    $steps = $currentJob.JobSteps | Out-GridView -Title "Choose the Job Steps to add an output file to" -PassThru -Verbose
                } else {
                    $steps = $currentJob.JobSteps
                }
            }

            if (!$steps) {
                $steps = $currentJob.JobSteps
            }

            foreach ($jobStep in $steps) {
                $currentOutputFile = $jobStep.OutputFileName

                Write-Message -Level Verbose -Message "Current Output File for $currentJob is $currentOutputFile"
                Write-Message -Level Verbose -Message "Adding $OutputFile to $jobStep for $currentJob"

                try {
                    if ($Pscmdlet.ShouldProcess($jobStep, "Changing Output File from $currentOutputFile to $OutputFile")) {
                        $jobStep.OutputFileName = $OutputFile
                        $jobStep.Alter()
                        $jobStep.Refresh()

                        [PSCustomObject]@{
                            ComputerName      = $server.ComputerName
                            InstanceName      = $server.ServiceName
                            SqlInstance       = $server.DomainInstanceName
                            Job               = $currentJob.Name
                            JobStep           = $jobStep.Name
                            OutputFileName    = $OutputFile
                            OldOutputFileName = $currentOutputFile
                        }
                    }
                } catch {
                    Stop-Function -Message "Failed to add $OutputFile to $jobStep for $currentJob" -InnerErrorRecord $_ -Target $currentJob
                }
            }
        }
    }
}