function Get-DbaDbStoredProcedure {
    <#
        .SYNOPSIS
            Gets database Stored Procedures

        .DESCRIPTION
            Gets database Stored Procedures

        .PARAMETER SqlInstance
            The target SQL Server instance(s)

        .PARAMETER SqlCredential
            Allows you to login to SQL Server using alternative credentials

        .PARAMETER Database
            To get Stored Procedures from specific database(s)

        .PARAMETER ExcludeDatabase
            The database(s) to exclude - this list is auto populated from the server

        .PARAMETER ExcludeSystemSp
            This switch removes all system objects from the Stored Procedure collection

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Databases
            Author: Klaas Vandenberghe ( @PowerDbaKlaas )

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .EXAMPLE
            Get-DbaDbStoredProcedure -SqlInstance sql2016

            Gets all database Stored Procedures

        .EXAMPLE
            Get-DbaDbStoredProcedure -SqlInstance Server1 -Database db1

            Gets the Stored Procedures for the db1 database

        .EXAMPLE
            Get-DbaDbStoredProcedure -SqlInstance Server1 -ExcludeDatabase db1

            Gets the Stored Procedures for all databases except db1

        .EXAMPLE
            Get-DbaDbStoredProcedure -SqlInstance Server1 -ExcludeSystemSp

            Gets the Stored Procedures for all databases that are not system objects

        .EXAMPLE
            'Sql1','Sql2/sqlexpress' | Get-DbaDbStoredProcedure

            Gets the Stored Procedures for the databases on Sql1 and Sql2/sqlexpress
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemSp,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $databases = $server.Databases | Where-Object IsAccessible

            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $databases) {
                if (!$db.IsAccessible) {
                    Write-Message -Level Warning -Message "Database $db is not accessible. Skipping."
                    continue
                }
                if ($db.StoredProcedures.Count -eq 0) {
                    Write-Message -Message "No Stored Procedures exist in the $db database on $instance" -Target $db -Level Output
                    continue
                }

                foreach ($proc in $db.StoredProcedures) {
                    if ( (Test-Bound -ParameterName ExcludeSystemSp) -and $proc.IsSystemObject ) {
                        continue
                    }

                    Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name ComputerName -value $server.NetName
                    Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $proc -MemberType NoteProperty -Name Database -value $db.Name

                    $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Schema', 'ID as ObjectId', 'CreateDate',
                    'DateLastModified', 'Name', 'ImplementationType', 'Startup'
                    Select-DefaultView -InputObject $proc -Property $defaults
                }
            }
        }
    }
}