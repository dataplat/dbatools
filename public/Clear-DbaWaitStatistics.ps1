function Clear-DbaWaitStatistics {
    <#
    .SYNOPSIS
        Resets SQL Server wait statistics to establish a clean monitoring baseline

    .DESCRIPTION
        Clears all accumulated wait statistics from sys.dm_os_wait_stats by executing DBCC SQLPERF (N'sys.dm_os_wait_stats', CLEAR). This is essential for performance troubleshooting when you need to establish a new baseline for wait analysis. DBAs commonly clear wait stats after resolving performance issues, during maintenance windows, or when beginning focused monitoring periods to isolate specific workload patterns without historical noise.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, WaitStats, Waits
        Author: Chrissy LeMaire (@cl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Clear-DbaWaitStatistics

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server instance, confirming the operation status.

        Properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (ComputerName\InstanceName)
        - Status: Either "Success" if the wait statistics were cleared, or the exception message if the operation failed

    .EXAMPLE
        PS C:\> Clear-DbaWaitStatistics -SqlInstance sql2008, sqlserver2012

        After confirmation, clears wait stats on servers sql2008 and sqlserver2012

    .EXAMPLE
        PS C:\> Clear-DbaWaitStatistics -SqlInstance sql2008, sqlserver2012 -Confirm:$false

        Clears wait stats on servers sql2008 and sqlserver2012, without prompting

    #>
    [CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "Singular Noun doesn't make sense")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Pscmdlet.ShouldProcess($instance, "Performing CLEAR of sys.dm_os_wait_stats")) {
                try {
                    $server.Query("DBCC SQLPERF (N'sys.dm_os_wait_stats', CLEAR);")
                    $status = "Success"
                } catch {
                    $status = $_.Exception
                }

                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Status       = $status
                }
            }
        }
    }
}