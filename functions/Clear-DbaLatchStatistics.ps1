function Clear-DbaLatchStatistics {
    <#
    .SYNOPSIS
        Clears Latch Statistics

    .DESCRIPTION
        Reset the aggregated statistics - basically just executes DBCC SQLPERF (N'sys.dm_os_latch_stats', CLEAR)

    .PARAMETER SqlInstance
        Allows you to specify a comma separated list of servers to query.

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
        Tags: LatchStatistic, Waits
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Clear-DbaLatchStatistics

    .EXAMPLE
        PS C:\> Clear-DbaLatchStatistics -SqlInstance sql2008, sqlserver2012

        After confirmation, clears latch statistics on servers sql2008 and sqlserver2012

    .EXAMPLE
        PS C:\> Clear-DbaLatchStatistics -SqlInstance sql2008, sqlserver2012 -Confirm:$false

        Clears latch statistics on servers sql2008 and sqlserver2012, without prompting

    .EXAMPLE
        PS C:\> 'sql2008','sqlserver2012' | Clear-DbaLatchStatistics

        After confirmation, clears latch statistics on servers sql2008 and sqlserver2012

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Clear-DbaLatchStatistics -SqlInstance sql2008 -SqlCredential $cred

        Connects using sqladmin credential and clears latch statistics on servers sql2008 and sqlserver2012
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
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Pscmdlet.ShouldProcess($instance, "Performing CLEAR of sys.dm_os_latch_stats")) {
                try {
                    $server.Query("DBCC SQLPERF (N'sys.dm_os_latch_stats' , CLEAR);")
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