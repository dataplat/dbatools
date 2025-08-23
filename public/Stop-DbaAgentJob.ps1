function Stop-DbaAgentJob {
    <#
    .SYNOPSIS
        Stops running SQL Server Agent jobs by calling their Stop() method.

    .DESCRIPTION
        Stops currently executing SQL Server Agent jobs and returns the job objects for verification after the stop attempt.
        Perfect for halting runaway jobs during maintenance windows, stopping jobs that are causing blocking or performance issues, or clearing job queues before scheduled operations.
        The function automatically skips jobs that are already idle and can optionally wait until jobs have completely finished stopping before returning results.
        Works with individual job names, exclusion filters, or accepts piped job objects from Get-DbaAgentJob and other dbatools commands.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        Specifies which SQL Agent jobs to stop by name. Accepts exact job names from the target instance.
        Use this when you need to stop specific jobs instead of all running jobs. If unspecified, all currently running jobs will be processed.

    .PARAMETER ExcludeJob
        Specifies SQL Agent job names to exclude from the stop operation. Accepts exact job names from the target instance.
        Use this when you want to stop most jobs but preserve critical ones like backup jobs, monitoring jobs, or maintenance routines during troubleshooting.

    .PARAMETER Wait
        Waits for each job to completely finish stopping before returning results. Without this switch, the function returns immediately after sending the stop command.
        Use this when you need to ensure jobs have fully terminated before proceeding with subsequent operations like maintenance or troubleshooting steps.

    .PARAMETER InputObject
        Accepts SQL Agent job objects from pipeline operations, typically from Get-DbaAgentJob or other dbatools commands.
        This allows you to filter jobs using complex criteria upstream and then pipe the results directly to Stop-DbaAgentJob for processing.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Job, Agent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Stop-DbaAgentJob

    .EXAMPLE
        PS C:\> Stop-DbaAgentJob -SqlInstance localhost

        Stops all running SQL Agent Jobs on the local SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sql2016 -Job cdc.DBWithCDC_capture | Stop-DbaAgentJob

        Stops the cdc.DBWithCDC_capture SQL Agent Job on sql2016

    .EXAMPLE
        PS C:\> Stop-DbaAgentJob -SqlInstance sql2016 -Job cdc.DBWithCDC_capture

        Stops the cdc.DBWithCDC_capture SQL Agent Job on sql2016

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ParameterSetName = "Instance")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Job,
        [string[]]$ExcludeJob,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Object")]
        [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject,
        [switch]$Wait,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $InputObject += $server.JobServer.Jobs

            if ($Job) {
                $InputObject = $InputObject | Where-Object Name -In $Job
            }
            if ($ExcludeJob) {
                $InputObject = $InputObject | Where-Object Name -NotIn $ExcludeJob
            }
        }

        foreach ($currentjob in $InputObject) {

            $server = $currentjob.Parent.Parent
            $status = $currentjob.CurrentRunStatus

            if ($status -eq 'Idle') {
                Stop-Function -Message "$currentjob on $server is idle ($status)" -Target $currentjob -Continue
            }

            If ($Pscmdlet.ShouldProcess($server, "Stopping job $currentjob")) {
                $null = $currentjob.Stop()
                Start-Sleep -Milliseconds 300
                $currentjob.Refresh()

                $waits = 0
                while ($currentjob.CurrentRunStatus -ne 'Idle' -and $waits++ -lt 10) {
                    Start-Sleep -Milliseconds 100
                    $currentjob.Refresh()
                }

                if ($wait) {
                    while ($currentjob.CurrentRunStatus -ne 'Idle') {
                        Write-Message -Level Verbose -Message "$currentjob is $($currentjob.CurrentRunStatus)"
                        Start-Sleep -Seconds 3
                        $currentjob.Refresh()
                    }
                    $currentjob
                } else {
                    $currentjob
                }
            }
        }
    }
}