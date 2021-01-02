function Get-DbaDeprecatedFeature {
    <#
    .SYNOPSIS
        Displays information relating to deprecated features for SQL Server 2005 and above.

    .DESCRIPTION
        Displays information relating to deprecated features for SQL Server 2005 and above.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Deprecated
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDeprecatedFeature

    .EXAMPLE
        PS C:\> Get-DbaDeprecatedFeature -SqlInstance sql2008, sqlserver2012

        Check deprecated features for all databases on the servers sql2008 and sqlserver2012.

    .EXAMPLE
        PS C:\> Get-DbaDeprecatedFeature -SqlInstance sql2008

        Check deprecated features on server sql2008.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    begin {
        $sql = "SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
        SERVERPROPERTY('ServerName') AS SqlInstance, object_name, instance_name as DeprecatedFeature, object_name as ObjectName, instance_name as deprecated_feature, cntr_value as UsageCount
        FROM sys.dm_os_performance_counters WHERE object_name like '%Deprecated%'
        and cntr_value > 0 ORDER BY deprecated_feature"
    }

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $server.Query($sql) | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, ObjectName, DeprecatedFeature, UsageCount
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $instance -Continue
            }

        }
    }
}