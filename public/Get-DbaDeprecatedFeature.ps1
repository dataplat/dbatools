function Get-DbaDeprecatedFeature {
    <#
    .SYNOPSIS
        Displays usage information relating to deprecated features for SQL Server 2005 and above.

    .DESCRIPTION
        Displays usage information relating to deprecated features for SQL Server 2005 and above.
        More information: https://learn.microsoft.com/en-us/sql/relational-databases/performance-monitor/sql-server-deprecated-features-object

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
        Tags: Deprecated, General
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDeprecatedFeature

    .EXAMPLE
        PS C:\> Get-DbaDeprecatedFeature -SqlInstance sql2008, sqlserver2012

        Get usage information relating to deprecated features on the servers sql2008 and sqlserver2012.

    .EXAMPLE
        PS C:\> Get-DbaDeprecatedFeature -SqlInstance sql2008

        Get usage information relating to deprecated features on server sql2008.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
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

            $usedDeprecatedFeatures = $server.Query("SELECT LTRIM(RTRIM(instance_name)) AS DeprecatedFeature, cntr_value AS UsageCount FROM sys.dm_os_performance_counters WHERE object_name LIKE '%SQL%Deprecated Features%' AND cntr_value > 0")
            foreach ($feature in $usedDeprecatedFeatures) {
                [PSCustomObject]@{
                    ComputerName      = $server.ComputerName
                    InstanceName      = $server.ServiceName
                    SqlInstance       = $server.DomainInstanceName
                    DeprecatedFeature = $feature.DeprecatedFeature
                    UsageCount        = $feature.UsageCount
                }
            }
        }
    }
}