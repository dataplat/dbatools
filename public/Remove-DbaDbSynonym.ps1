function Remove-DbaDbSynonym {
    <#
    .SYNOPSIS
        Removes database synonyms from SQL Server databases

    .DESCRIPTION
        Removes one or more database synonyms from SQL Server databases by executing DROP SYNONYM commands. Synonyms are database objects that provide alternate names for tables, views, or other objects, often used to simplify complex object names or provide abstraction layers. This function helps clean up obsolete synonyms during database refactoring, migrations, or general maintenance activities, so you don't have to manually script DROP statements across multiple databases or instances.

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
        Enables piped input from Get-DbaDbSynonym or Get-DbaDatabase

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Synonym, Database
        Author: Mikey Bronowski (@MikeyBronowski), bronowski.it

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbSynonym

    .EXAMPLE
        PS C:\> Remove-DbaDbSynonym -SqlInstance localhost -Database db1 -Synonym "synonym1", "synonym2"

        Removes synonyms synonym1 and synonym2 from the database db1 on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Remove-DbaDbSynonym -SqlInstance localhost, sql2016 -Database db1, db2 -Synonym synonym1, synonym2, synonym3

        Removes synonym1, synonym2, synonym3 from db1 and db2 on the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> $servers = Get-Content C:\servers.txt
        PS C:\> $servers | Remove-DbaDbSynonym -Database db1, db2 -Synonym synonym1

        Removes synonym1 from db1 and db2 on the servers in C:\servers.txt

    .EXAMPLE
        PS C:\> $synonyms = Get-DbaDbSynonym -SqlInstance localhost, sql2016 -Database db1, db2 -Synonym synonym1, synonym2, synonym3
        PS C:\> $synonyms | Remove-DbaDbSynonym

        Removes synonym1, synonym2, synonym3 from db1 and db2 on the local and sql2016 SQL Server instances
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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
        [object[]]$InputObject,
        [switch]$EnableException
    )

    process {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a synonym, database, or server or specify a SqlInstance"
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName
            switch ($inputType) {
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject"
                    $dbSynonyms = Get-DbaDbSynonym -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Schema $Schema -ExcludeSchema $ExcludeSchema -Synonym $Synonym -ExcludeSynonym $ExcludeSynonym
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $dbSynonyms = Get-DbaDbSynonym -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Schema $Schema -ExcludeSchema $ExcludeSchema -Synonym $Synonym -ExcludeSynonym $ExcludeSynonym
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject"
                    $dbSynonyms = Get-DbaDbSynonym -InputObject $input
                }
                'Microsoft.SqlServer.Management.Smo.Synonym' {
                    Write-Message -Level Verbose -Message "Processing DatabaseSynonym through InputObject"
                    $dbSynonyms = $input
                }
                default {
                    Stop-Function -Message "InputObject is not a server, database, or database synonym."
                    return
                }
            }

            foreach ($dbSynonym in $dbSynonyms) {
                $db = $dbSynonym.Parent
                $instance = $db.Parent

                if ($PSCmdlet.ShouldProcess($instance, "Remove synonym $dbSynonym from database $db")) {

                    try {
                        # avoid enumeration issues
                        $db.Query("DROP SYNONYM $dbSynonym")
                        [PSCustomObject]@{
                            ComputerName = $db.ComputerName
                            InstanceName = $db.InstanceName
                            SqlInstance  = $db.SqlInstance
                            Database     = $db.Name
                            Synonym      = $dbSynonym
                            Status       = "Removed"
                        }
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                    }

                }

            }
        }
    }
}