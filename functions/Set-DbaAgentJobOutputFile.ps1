function Set-DbaAgentJobOutputFile {
    <#
    .Synopsis
        Set the output file for a step within an Agent job.

    .DESCRIPTION
        Sets the Output File for a step of an agent job with the Job Names and steps provided dynamically if required

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SQLCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance. be it Windows or SQL Server. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER Job
        The job to process - this list is auto-populated from the server.

    .PARAMETER Step
        The Agent Job Step to provide Output File Path for. Also available dynamically

    .PARAMETER OutputFile
        The Full Path to the New Output file

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
        Author: Rob Sewell, https://sqldbawithabeard.com

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
            $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Write-Message -Level Warning -Message "Failed to connect to: $instance"
            continue
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

                        [pscustomobject]@{
                            ComputerName   = $server.ComputerName
                            InstanceName   = $server.ServiceName
                            SqlInstance    = $server.DomainInstanceName
                            Job            = $currentJob.Name
                            JobStep        = $jobStep.Name
                            OutputFileName = $currentOutputFile
                        }
                    }
                } catch {
                    Stop-Function -Message "Failed to add $OutputFile to $jobStep for $currentJob" -InnerErrorRecord $_ -Target $currentJob
                }
            }
        }
    }
}