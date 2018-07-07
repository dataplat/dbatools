function Get-DbaQueryPlan {
<#
    .SYNOPSIS
        Provides information about adhoc and prepared plan cache usage

    .DESCRIPTION
        "Checks ahoc and prepared plan cache for each database, if over 100 MBS should 
        consider you using Remove-DbaQueryPlan to clear the plan caches or turning on
        optimize for adhoc workloads configuration is running 2008 or later."

        References: https://www.sqlskills.com/blogs/kimberly/plan-cache-adhoc-workloads-and-clearing-the-single-use-plan-cache-bloat/

        Note: This command returns results from all SQL instances on the destionation server but the process
        column is specific to -SqlInstance passed.

    .PARAMETER SqlInstance
        Allows you to specify a comma separated list of servers to query.

    .PARAMETER SqlCredential
        Allows you to login to the SQL instance using alternative credentials.

    .PARAMETER Threshold
        Memoery used threshold.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Memory
        Author: Tracy Boggiano, databasesuperhero.com

        dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
        Copyright (C) 2016 Chrissy LeMaire
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
        https://dbatools.io/Get-DbaQueryPlan

    .EXAMPLE
        Get-DbaQueryPlan -SqlInstance sql2017

        Logs into the SQL Server instance "sql2017" and also the Computer itself (via WMI) to gather information

    .EXAMPLE
        Get-DbaQueryPlan -SqlInstance sql2017

        Get plan cache usage for SQLInstnace sql2017

    .EXAMPLE
        Get-DbaQueryPlan -SqlInstance sql2017 -SqlCredential (Get-Credential sqladmin) 

        Logs into the SQL instance using the SQL Login 'sqladmin'
#>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int]$Threshold = 100,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        $Sql = "SELECT MB = sum(cast((CASE WHEN usecounts = 1 AND objtype IN ('Adhoc', 'Prepared') THEN size_in_bytes ELSE 0 END) as decimal(12, 2))) / 1024 / 1024, 
                UseCount = sum(CASE WHEN usecounts = 1 AND objtype IN ('Adhoc', 'Prepared') THEN 1 ELSE 0 END) 
            FROM sys.dm_exec_cached_plans"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $sqlcredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $results = $server.Query($sql)
            
            Add-Member -Force -InputObject $thread -MemberType NoteProperty -Name ComputerName -value $server.NetName
            Add-Member -Force -InputObject $thread -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
            Add-Member -Force -InputObject $thread -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
            Add-Member -Force -InputObject $thread -MemberType NoteProperty -Name MB -Value $results.MB
            Add-Member -Force -InputObject $thread -MemberType NoteProperty -Name UseCount -Value $results.UseCount

            Select-DefaultView -InputObject $thread -Property ComputerName, InstanceName, SqlInstance, MB, UseCount
        }
    }
}