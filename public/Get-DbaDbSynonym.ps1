function Get-DbaDbSynonym {
    <#
    .SYNOPSIS
        Retrieves database synonyms and their target object mappings from SQL Server instances

    .DESCRIPTION
        Returns database synonym objects along with their target object details including base server, database, schema, and object name. Synonyms are database-scoped aliases that point to objects in the same or different databases, even on remote servers. This function helps DBAs document database dependencies, track cross-database references, and analyze synonym usage across their SQL Server environment. The output includes both the synonym definition and its underlying target, making it useful for impact analysis when planning database migrations or refactoring.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. This list is auto-populated from the server.

    .PARAMETER Schema
        The schema(s) to process. If unspecified, all schemas will be processed.

    .PARAMETER ExcludeSchema
        The schema(s) to exclude.

    .PARAMETER Synonym
        The synonym(s) to process. If unspecified, all synonyms will be processed.

    .PARAMETER ExcludeSynonym
        The synonym(s) to exclude.

    .PARAMETER InputObject
        Enables piped input from Get-DbaDatabase

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Synonym
        Author: Mikey Bronowski (@MikeyBronowski), bronowski.it

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbSynonym

    .EXAMPLE
        PS C:\> Get-DbaDbSynonym -SqlInstance localhost

        Returns all database synonyms in all databases on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaDbSynonym -SqlInstance localhost, sql2016

        Returns all synonyms of all database(s) on the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> $servers = Get-Content C:\servers.txt
        PS C:\> $servers | Get-DbaDbSynonym

        Returns synonyms of all database(s) for every server in C:\servers.txt

    .EXAMPLE
        PS C:\> Get-DbaDbSynonym -SqlInstance localhost -Database db1

        Returns synonyms of the database db1 on localhost.

    .EXAMPLE
        PS C:\> Get-DbaDbSynonym -SqlInstance localhost -Database db1 -Synonym 'synonym1'

        Returns the synonym1 synonym in the db1 database on localhost.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Schema,
        [string[]]$ExcludeSchema,
        [string[]]$Synonym,
        [string[]]$ExcludeSynonym,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    process {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a database or specify a SqlInstance"
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            if ($db.IsAccessible -eq $false) {
                continue
            }
            $server = $db.Parent
            Write-Message -Level 'Verbose' -Message "Getting Database Synonyms for $db on $server"

            $dbSynonyms = $db.Synonyms

            if ($Synonym) {
                $dbSynonyms = $dbSynonyms | Where-Object { $_.Name -in $Synonym }
            }

            if ($ExcludeSynonym) {
                $dbSynonyms = $dbSynonyms | Where-Object { $_.Name -notin $ExcludeSynonym }
            }

            if ($Schema) {
                $dbSynonyms = $dbSynonyms | Where-Object { $_.Schema -in $Schema }
            }

            if ($ExcludeSchema) {
                $dbSynonyms = $dbSynonyms | Where-Object { $_.Schema -notin $ExcludeSchema }
            }

            foreach ($dbSynonym in $dbSynonyms) {
                Add-Member -Force -InputObject $dbSynonym -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $dbSynonym -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $dbSynonym -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $dbSynonym -MemberType NoteProperty -Name Database -Value $db.Name

                Select-DefaultView -InputObject $dbSynonym -Property "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name", "BaseServer", "BaseDatabase", "BaseSchema", "BaseObject"
            }
        }
    }
}