function Test-DbaDbCompatibility {
    <#
    .SYNOPSIS
        Compares Database Compatibility level to Server Compatibility

    .DESCRIPTION
        Compares Database Compatibility level to Server Compatibility

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Compatibility
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaDbCompatibility

    .EXAMPLE
        PS C:\> Test-DbaDbCompatibility -SqlInstance sqlserver2014a

        Returns server name, database name and true/false if the compatibility level match for all databases on sqlserver2014a.

    .EXAMPLE
        PS C:\> Test-DbaDbCompatibility -SqlInstance sqlserver2014a -Database db1, db2

        Returns detailed information for database and server compatibility level for the db1 and db2 databases on sqlserver2014a.

    .EXAMPLE
        PS C:\> Test-DbaDbCompatibility -SqlInstance sqlserver2014a, sql2016 -Exclude db1

        Returns detailed information for database and server compatibility level for all databases except db1 on sqlserver2014a and sql2016.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2014 | Test-DbaDbCompatibility

        Returns db/server compatibility information for every database on every server listed in the Central Management Server on sql2016.

    #>
    [CmdletBinding()]
    [OutputType("System.Collections.ArrayList")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $serverversion = "Version$($server.VersionMajor)0"
            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object { $Database -contains $_.Name }
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $($db.name) on $instance."
                [PSCustomObject]@{
                    ComputerName          = $server.ComputerName
                    InstanceName          = $server.ServiceName
                    SqlInstance           = $server.DomainInstanceName
                    ServerLevel           = $serverversion
                    Database              = $db.name
                    DatabaseCompatibility = $db.CompatibilityLevel
                    IsEqual               = $db.CompatibilityLevel -eq $serverversion
                }
            }
        }
    }
}