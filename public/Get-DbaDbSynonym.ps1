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
        Specifies which database(s) to search for synonyms. Accepts wildcards for pattern matching.
        Use this when you need to focus on specific databases instead of scanning all databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific database(s) from the synonym search. Accepts wildcards for pattern matching.
        Useful for skipping system databases, test environments, or databases you know don't contain relevant synonyms.

    .PARAMETER Schema
        Filters synonyms to only those in the specified schema(s). Accepts wildcards for pattern matching.
        Use this when you need to focus on synonyms within specific schemas, such as application-specific or departmental schemas.

    .PARAMETER ExcludeSchema
        Excludes synonyms from specific schema(s) in the results. Accepts wildcards for pattern matching.
        Helpful for filtering out system schemas or schemas that contain synonyms you're not interested in analyzing.

    .PARAMETER Synonym
        Specifies exact synonym name(s) to retrieve. Accepts multiple synonym names as an array.
        Use this when you need details about specific synonyms, such as checking where a particular synonym points or verifying its target object.

    .PARAMETER ExcludeSynonym
        Excludes specific synonym(s) from the results by name. Accepts multiple synonym names as an array.
        Useful when you want to see all synonyms except certain ones you already know about or don't need to review.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase via pipeline input. Allows you to chain database filtering commands.
        Use this to process synonyms only from databases that meet specific criteria, such as specific compatibility levels or last backup dates.

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

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Synonym

        Returns one Synonym object per database synonym found. The output includes details about each synonym and its target object mapping.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance hosting the synonym
        - InstanceName: The SQL Server instance name where the synonym is located
        - SqlInstance: The full SQL Server instance name (ComputerName\InstanceName)
        - Database: The database containing the synonym
        - Schema: The schema that contains the synonym
        - Name: The name of the synonym object
        - BaseServer: The linked server name if the synonym references a remote object, or the server name for local references
        - BaseDatabase: The database containing the target object that the synonym references
        - BaseSchema: The schema containing the target object that the synonym references
        - BaseObject: The name of the target object that the synonym references (table, view, function, etc.)

        All properties from the base SMO Synonym object are accessible through Select-Object * even though only the default properties are displayed without using Select-Object.

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