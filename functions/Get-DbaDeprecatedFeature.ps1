function Get-DbaDeprecatedFeature {
    <#
        .SYNOPSIS
            Displays information relating to deprecated features for SQL Server 2005 and above.

        .DESCRIPTION
            Displays information relating to deprecated features for SQL Server 2005 and above.

        .PARAMETER SqlInstance
            The target SQL Server instance

        .PARAMETER SqlCredential
            Login to the target instance using alternate Windows or SQL Login Authentication. Accepts credential objects (Get-Credential).

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Chrissy LeMaire (@cl), netnerds.net
            Tags: Deprecated
            Website: https://dbatools.io
            Copyright: (c) 2018 by dbatools, licensed under MIT
-           License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaDeprecatedFeature

        .EXAMPLE
            Get-DbaDatabase -SqlInstance sql2008 -Database testdb, db2 | Get-DbaDeprecatedFeature
            Check deprecated features on server sql2008 for only the testdb and db2 databases

        .EXAMPLE
            Get-DbaDeprecatedFeature -SqlInstance sql2008, sqlserver2012
            Check deprecated features for all databases on the servers sql2008 and sqlserver2012.

        .EXAMPLE
            Get-DbaDeprecatedFeature -SqlInstance sql2008 -Database TestDB
            Check deprecated features on server sql2008 for only the TestDB database

        .EXAMPLE
            Get-DbaDeprecatedFeature -SqlInstance sql2008 -Database TestDB -Threshold 20
            Check deprecated features on server sql2008 for only the TestDB database, limiting results to 20% utilization of seed range or higher
        #>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    begin {
        $sql = "SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
        SERVERPROPERTY('ServerName') AS SqlInstance, object_name, instance_name as deprecated_feature, cntr_value as UsageCount
        FROM sys.dm_os_performance_counters WHERE object_name like '%Deprecated%'
        and cntr_value > 0 ORDER BY deprecated_feature"
    }

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $server.Query($sql)
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $instance -Continue
            }

        }
    }
}