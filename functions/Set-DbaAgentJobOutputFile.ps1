function Set-DbaAgentJobOutputFile {
    <#
        .Synopsis
            Set the output file for a step within an Agent job.

        .DESCRIPTION
            Sets the Output File for a step of an agent job with the Job Names and steps provided dynamically if required

        .PARAMETER SqlInstance
            The SQL Server that you're connecting to.

        .PARAMETER SQLCredential
            Credential object used to connect to the SQL Server as a different user be it Windows or SQL Server. Windows users are determiend by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

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
            Original Author - Rob Sewell (https://sqldbawithabeard.com)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

            # todo - allow piping and add -All

        .EXAMPLE
            Set-DbaAgentJobOutputFile -SqlInstance SERVERNAME -JobName 'The Agent Job' -OutPutFile E:\Logs\AgentJobStepOutput.txt

            Sets the Job step for The Agent job on SERVERNAME to E:\Logs\AgentJobStepOutput.txt
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'The SQL Server Instance',
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false,
            Position = 0)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(Mandatory = $false, HelpMessage = 'SQL Credential',
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [PSCredential]$SqlCredential,
        [object[]]$Job,
        [Parameter(Mandatory = $false, HelpMessage = 'The Job Step name',
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [object[]]$Step,
        [Parameter(Mandatory = $true, HelpMessage = 'The Full Output File Path',
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]$OutputFile,
        [switch][Alias('Silent')]$EnableException
    )

    foreach ($instance in $sqlinstance) {
        try {
            $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
        }
        catch {
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
            }
            else {
                if (($currentJob.JobSteps).Count -gt 1) {
                    Write-Message -Level Output -Message "Which Job Step do you wish to add output file to?"
                    $steps = $currentJob.JobSteps | Out-GridView -Title "Choose the Job Steps to add an output file to" -PassThru -Verbose
                }
                else {
                    $steps = $currentJob.JobSteps
                }
            }

            if (!$steps) {
                $steps = $currentJob.JobSteps
            }

            foreach ($jobstep in $steps) {
                $currentoutputfile = $jobstep.OutputFileName

                Write-Message -Level Verbose -Message "Current Output File for $currentJob is $currentoutputfile"
                Write-Message -Level Verbose -Message "Adding $OutputFile to $jobstep for $currentJob"

                try {
                    if ($Pscmdlet.ShouldProcess($jobstep, "Changing Output File from $currentoutputfile to $OutputFile")) {
                        $jobstep.OutputFileName = $OutputFile
                        $jobstep.Alter()
                        $jobstep.Refresh()

                        [pscustomobject]@{
                            ComputerName   = $server.NetName
                            InstanceName   = $server.ServiceName
                            SqlInstance    = $server.DomainInstanceName
                            Job            = $currentJob.Name
                            JobStep        = $jobstep.Name
                            OutputFileName = $currentoutputfile
                        }
                    }
                }
                catch {
                    Stop-Function -Message "Failed to add $OutputFile to $jobstep for $currentJob" -InnerErrorRecord $_ -Target $currentJob
                }
            }
        }
    }
}