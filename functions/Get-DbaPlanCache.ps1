function Get-DbaPlanCache {
    <#
    .SYNOPSIS
        Provides information about adhoc and prepared plan cache usage

    .DESCRIPTION
        Checks adhoc and prepared plan cache for each database, if over 100 MB you should consider using Remove-DbaQueryPlan to clear the plan caches or turning on "optimize for adhoc workloads" configuration if running 2008 or later.

        References: https://www.sqlskills.com/blogs/kimberly/plan-cache-adhoc-workloads-and-clearing-the-single-use-plan-cache-bloat/

        Note: This command returns results from all SQL server instances on the destination server but the process column is specific to -SqlInstance passed.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Memory
        Author: Tracy Boggiano, databasesuperhero.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaPlanCache

    .EXAMPLE
        PS C:\> Get-DbaPlanCache -SqlInstance sql2017

        Returns the single use plan cache usage information for SQL Server instance 2017

    .EXAMPLE
        PS C:\> Get-DbaPlanCache -SqlInstance sql2017 -SqlCredential sqladmin

        Returns the single use plan cache usage information for SQL Server instance 2017 using login 'sqladmin'

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    begin {
        $Sql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName,
    ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
    SERVERPROPERTY('ServerName') AS SqlInstance, MB = SUM(CAST((CASE WHEN usecounts = 1 AND objtype IN ('Adhoc', 'Prepared') THEN size_in_bytes ELSE 0 END) AS DECIMAL(12, 2))) / 1024 / 1024,
    UseCount = SUM(CASE WHEN usecounts = 1 AND objtype IN ('Adhoc', 'Prepared') THEN 1 ELSE 0 END)
    FROM sys.dm_exec_cached_plans;"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $results = $server.Query($sql)
            $size = [dbasize]($results.MB * 1024 * 1024)
            Add-Member -Force -InputObject $results -MemberType NoteProperty -Name Size -Value $size

            Select-DefaultView -InputObject $results -Property ComputerName, InstanceName, SqlInstance, Size, UseCount
        }
    }
}