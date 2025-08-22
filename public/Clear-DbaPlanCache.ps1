function Clear-DbaPlanCache {
    <#
    .SYNOPSIS
        Clears SQL Server plan cache when single-use adhoc and prepared plans exceed memory threshold

    .DESCRIPTION
        Monitors your SQL Server's plan cache for single-use adhoc and prepared plans that consume excessive memory. When these plans exceed the specified threshold (default 100MB), the function clears the entire plan cache using DBCC FREESYSTEMCACHE('SQL Plans').

        Single-use plans are a common cause of memory pressure in SQL Server environments with dynamic SQL or applications that don't use parameterized queries. Instead of manually checking sys.dm_exec_cached_plans and running DBCC commands, this function automates the detection and cleanup process.

        Use this when you're experiencing memory pressure from plan cache bloat or as part of regular maintenance to prevent cache-related performance issues. The function only clears the cache when necessary, avoiding unnecessary disruption to your server's performance.

        References: https://www.sqlskills.com/blogs/kimberly/plan-cache-adhoc-workloads-and-clearing-the-single-use-plan-cache-bloat/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Threshold
        Memory used threshold.

    .PARAMETER InputObject
        Enables results to be piped in from Get-DbaPlanCache.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, Memory
        Author: Tracy Boggiano, databasesuperhero.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Clear-DbaPlanCache

    .EXAMPLE
        PS C:\> Clear-DbaPlanCache -SqlInstance sql2017 -Threshold 200

        Logs into the SQL Server instance "sql2017" and removes plan caches if over 200 MB.

    .EXAMPLE
        PS C:\> Clear-DbaPlanCache -SqlInstance sql2017 -SqlCredential sqladmin

        Logs into the SQL instance using the SQL Login 'sqladmin' and then Windows instance as 'ad\sqldba'
        and removes if Threshold over 100 MB.

    .EXAMPLE
        PS C:\> Find-DbaInstance -ComputerName localhost | Get-DbaPlanCache | Clear-DbaPlanCache -Threshold 200

        Scans localhost for instances using the browser service, traverses all instances and gets the plan cache for each, clears them out if they are above 200 MB.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int]$Threshold = 100,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaPlanCache -SqlInstance $instance -SqlCredential $SqlCredential
        }

        foreach ($result in $InputObject) {
            if ($result.MB -ge $Threshold) {
                if ($Pscmdlet.ShouldProcess($($result.SqlInstance), "Cleared SQL Plans plan cache")) {
                    try {
                        $server = Connect-DbaInstance -SqlInstance $result.SqlInstance -SqlCredential $SqlCredential
                    } catch {
                        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $result.SqlInstance -Continue
                    }

                    $server.Query("DBCC FREESYSTEMCACHE('SQL Plans')")
                    [PSCustomObject]@{
                        ComputerName = $result.ComputerName
                        InstanceName = $result.InstanceName
                        SqlInstance  = $result.SqlInstance
                        Size         = $result.Size
                        Status       = "Plan cache cleared"
                    }
                }
            } else {
                if ($Pscmdlet.ShouldProcess($($result.SqlInstance), "Results $($result.Size) below threshold")) {
                    [PSCustomObject]@{
                        ComputerName = $result.ComputerName
                        InstanceName = $result.InstanceName
                        SqlInstance  = $result.SqlInstance
                        Size         = $result.Size
                        Status       = "Plan cache size below threshold ($Threshold) "
                    }
                    Write-Message -Level Verbose -Message "Plan cache size below threshold ($Threshold) "
                }
            }
        }
    }
}