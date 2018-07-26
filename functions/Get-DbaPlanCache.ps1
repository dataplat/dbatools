function Get-DbaPlanCache {
    <#
        .SYNOPSIS
            Provides information about adhoc and prepared plan cache usage

        .DESCRIPTION
            Checks ahoc and prepared plan cache for each database, if over 100 MBS you should consider you using Remove-DbaQueryPlan to clear the plan caches or turning on optimize for adhoc workloads configuration is running 2008 or later.

            References: https://www.sqlskills.com/blogs/kimberly/plan-cache-adhoc-workloads-and-clearing-the-single-use-plan-cache-bloat/

            Note: This command returns results from all SQL server instances on the destination server but the process column is specific to -SqlInstance passed.

        .PARAMETER SqlInstance
            The target SQL Server instance.

        .PARAMETER SqlCredential
           Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
            https://dbatools.io/Get-DbaPlanCache

        .EXAMPLE
            Get-DbaPlanCache -SqlInstance sql2017

            Returns the single use plan cashe usage information for SQL Server instance 2017

        .EXAMPLE
            Get-DbaPlanCache -SqlInstance sql2017

            Returns the single use plan cashe usage information for SQL Server instance 2017

        .EXAMPLE
            Get-DbaPlanCache -SqlInstance sql2017 -SqlCredential (Get-Credential sqladmin)

            Returns the single use plan cashe usage information for SQL Server instance 2017 using login 'sqladmin'
    #>
        [CmdletBinding()]
        Param (
            [parameter(Mandatory, ValueFromPipeline)]
            [Alias("ServerInstance", "SqlServer", "SqlServers")]
            [DbaInstanceParameter[]]$SqlInstance,
            [PSCredential]$SqlCredential,
            [switch]$EnableException
        )
        begin {
            $Sql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName,
        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
        SERVERPROPERTY('ServerName') AS SqlInstance, MB = sum(cast((CASE WHEN usecounts = 1 AND objtype IN ('Adhoc', 'Prepared') THEN size_in_bytes ELSE 0 END) as decimal(12, 2))) / 1024 / 1024,
        UseCount = sum(CASE WHEN usecounts = 1 AND objtype IN ('Adhoc', 'Prepared') THEN 1 ELSE 0 END)
        FROM sys.dm_exec_cached_plans;"
        }

        process {
            foreach ($instance in $SqlInstance) {
                try {
                    Write-Message -Level Verbose -Message "Connecting to $instance"
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $sqlcredential
                }
                catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                $results = $server.Query($sql)
                $size = [dbasize]($results.MB*1024*1024)
                Add-Member -Force -InputObject $results -MemberType NoteProperty -Name Size -Value $size

                Select-DefaultView -InputObject $results -Property ComputerName, InstanceName, SqlInstance, Size, UseCount
            }
        }
    }