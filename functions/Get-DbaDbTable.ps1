function Get-DbaDbTable {
    <#
    .SYNOPSIS
        Returns a summary of information on the tables

    .DESCRIPTION
        Shows table information around table row and data sizes and if it has any table type information.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER IncludeSystemDBs
        Switch parameter that when used will display system database information

    .PARAMETER Table
        Define a specific table you would like to query. You can specify up to three-part name like db.sch.tbl.

        If the object has special characters please wrap them in square brackets [ ].
        Using dbo.First.Table will try to find table named 'Table' on schema 'First' and database 'dbo'.
        The correct way to find table named 'First.Table' on schema 'dbo' is by passing dbo.[First.Table]
        Any actual usage of the ] must be escaped by duplicating the ] character.
        The correct way to find a table Name] in schema Schema.Name is by passing [Schema.Name].[Name]]]

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Tables
        Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbTable

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance DEV01 -Database Test1

        Return all tables in the Test1 database

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance DEV01 -Database MyDB -Table MyTable

        Return only information on the table MyTable from the database MyDB

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance DEV01 -Table MyTable

        Returns information on table called MyTable if it exists in any database on the server, under any schema

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance DEV01 -Table dbo.[First.Table]

        Returns information on table called First.Table on schema dbo if it exists in any database on the server

    .EXAMPLE
        PS C:\> 'localhost','localhost\namedinstance' | Get-DbaDbTable -Database DBA -Table Commandlog

        Returns information on the CommandLog table in the DBA database on both instances localhost and the named instance localhost\namedinstance

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance DEV01 -Table "[[DbName]]].[Schema.With.Dots].[`"[Process]]`"]" -Verbose

        For the instance Dev01 Returns information for a table named: "[Process]" in schema named: Schema.With.Dots in database named: [DbName]
        The Table name, Schema name and Database name must be wrapped in square brackets [ ]
        Special charcters like " must be escaped by a ` charcter.
        In addition any actual instance of the ] character must be escaped by being duplicated.
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [switch]$IncludeSystemDBs,
        [string[]]$Table,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ($Table) {
            $fqtns = @()
            foreach ($t in $Table) {
                $fqtn = Get-ObjectNameParts -ObjectName $t

                if (!$fqtn.Parsed) {
                    Write-Message -Level Warning -Message "Please check you are using proper three-part names. If your search value contains special characters you must use [ ] to wrap the name. The value $t could not be parsed as a valid name."
                    Continue
                }

                $fqtns += [PSCustomObject] @{
                    Database   = $fqtn.Database
                    Schema     = $fqtn.Schema
                    Table      = $fqtn.Name
                    InputValue = $fqtn.InputValue
                }
            }
            if (!$fqtns) {
                Stop-Function -Message "No Valid Table specified"  -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            Write-Message -Level Verbose -Message "Processing $db"

            if ($fqtns) {
                $tables = @()
                foreach ($fqtn in $fqtns) {
                    # If the user specified a database in a three-part name, and it's not the
                    # database currently being processed, skip this table.
                    if ($fqtn.Database) {
                        if ($fqtn.Database -ne $db.Name) {
                            continue
                        }
                    }

                    $tbl = $db.tables | Where-Object { $_.Name -in $fqtn.Table -and $fqtn.Schema -in ($_.Schema, $null) -and $fqtn.Database -in ($_.Parent.Name, $null) }

                    if (-not $tbl) {
                        Write-Message -Level Verbose -Message "Could not find table $($fqtn.Name) in $db on $server"
                    }
                    $tables += $tbl
                }
            } else {
                $tables = $db.Tables
            }

            foreach ($sqlTable in $tables) {
                $sqlTable | Add-Member -Force -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                $sqlTable | Add-Member -Force -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                $sqlTable | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                $sqlTable | Add-Member -Force -MemberType NoteProperty -Name Database -Value $db.Name

                $defaultProps = "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name", "IndexSpaceUsed", "DataSpaceUsed", "RowCount", "HasClusteredIndex", "IsFileTable", "IsMemoryOptimized", "IsPartitioned", "FullTextIndex", "ChangeTrackingEnabled"

                Select-DefaultView -InputObject $sqlTable -Property $defaultProps
            }
        }
    }
}