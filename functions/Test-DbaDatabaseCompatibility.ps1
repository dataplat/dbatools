function Test-DbaDatabaseCompatibility {
    <#
        .SYNOPSIS
            Compares Database Compatibility level to Server Compatibility

        .DESCRIPTION
            Compares Database Compatibility level to Server Compatibility

        .PARAMETER SqlInstance
            The SQL Server that you're connecting to.

        .PARAMETER Credential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -Credential parameter.

            Windows Authentication will be used if Credential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Database
            Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.

        .PARAMETER Detailed
            Will be deprecated in 1.0.0 release.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags:
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Test-DbaDatabaseCompatibility

        .EXAMPLE
            Test-DbaDatabaseCompatibility -SqlInstance sqlserver2014a

            Returns server name, database name and true/false if the compatibility level match for all databases on sqlserver2014a.

        .EXAMPLE
            Test-DbaDatabaseCompatibility -SqlInstance sqlserver2014a -Database db1, db2

            Returns detailed information for database and server compatibility level for the db1 and db2 databases on sqlserver2014a.

        .EXAMPLE
            Test-DbaDatabaseCompatibility -SqlInstance sqlserver2014a, sql2016 -Exclude db1

            Returns detailed information for database and server compatibility level for all databases except db1 on sqlserver2014a and sql2016.

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance sql2014 | Test-DbaDatabaseCompatibility

            Returns db/server compatibility information for every database on every server listed in the Central Management Server on sql2016.
    #>
    [CmdletBinding()]
    [OutputType("System.Collections.ArrayList")]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$Detailed,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Parameter "Detailed"
    }

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance."
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $serverversion = "Version$($server.VersionMajor)0"
            $dbs = $server.Databases | Where-Object IsAccessible

            if ($Database) {
                $dbs = $dbs | Where-Object { $Database -contains $_.Name }
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $($db.name) on $instance."
                [PSCustomObject]@{
                    ComputerName          = $server.NetName
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
