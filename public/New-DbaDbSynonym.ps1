function New-DbaDbSynonym {
    <#
    .SYNOPSIS
        Creates database synonyms to provide alternate names for tables, views, procedures, and other database objects.

    .DESCRIPTION
        Creates database synonyms that serve as alternate names or aliases for database objects like tables, views, stored procedures, and functions. Synonyms simplify object references by providing shorter names, hiding complex schema structures, or creating abstraction layers for applications. You can create synonyms that reference objects in the same database, different databases, or even on linked servers, making cross-database and cross-server object access more manageable for applications and users.

   .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to create the synonym in. Accepts wildcards for pattern matching.
        When omitted, synonyms will be created in all accessible databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from synonym creation when processing multiple databases.
        Useful when you want to create synonyms across most databases but skip system databases or specific user databases.

    .PARAMETER Synonym
        The name of the synonym to create. This becomes the alternate name that applications and users will reference.
        Choose meaningful names that follow your organization's naming conventions and make object access more intuitive.

    .PARAMETER Schema
        The schema where the synonym will be created. Defaults to 'dbo' if not specified.
        Consider using application-specific schemas to organize synonyms logically and control access through schema permissions.

    .PARAMETER BaseServer
        The linked server name when creating cross-server synonyms. Requires BaseDatabase and BaseSchema parameters.
        Use this to create synonyms that reference objects on remote SQL Server instances through established linked server connections.

    .PARAMETER BaseDatabase
        The database containing the target object that the synonym will reference. Requires BaseSchema when specified.
        Use this for cross-database synonyms or when creating synonyms on linked servers to reference objects in specific databases.

    .PARAMETER BaseSchema
        The schema containing the target object that the synonym will reference.
        Required when BaseDatabase is specified, ensuring the synonym points to the correct object in complex multi-schema environments.

    .PARAMETER BaseObject
        The name of the database object that the synonym will reference. Supports tables, views, stored procedures, functions, and other schema-scoped objects.
        This is the actual object that users will access through the synonym name, enabling abstraction and simplified references.

    .PARAMETER InputObject
        Accepts database objects piped from Get-DbaDatabase for creating synonyms across multiple databases.
        Useful for batch operations when you need to create the same synonym in multiple databases selected by specific criteria.

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
        https://dbatools.io/New-DbaDbSynonym

        .EXAMPLE
        PS C:\> New-DbaDbSynonym -SqlInstance sql2017a -Database db1 -Synonym synObj1 -BaseObject Obj1

        Will create a new synonym named synObj1 in db1 database in dbo schema on sql2017a instance for Obj1 object in the same database.

    .EXAMPLE
        PS C:\> New-DbaDbSynonym -SqlInstance sql2017a -Database db1 -Synonym synObj1 -BaseObject Obj1

        Will create a new synonym named synObj1 in db1 database in dbo schema on sql2017a instance for Obj1 object in the same database.

    .EXAMPLE
        PS C:\> New-DbaDbSynonym -SqlInstance sql2017a -Database db1 -Schema sch1 -Synonym synObj1 -BaseObject Obj1

        Will create a new synonym named synObj1 within dbo schema in db1 database  on sql2017a instance for Obj1 object in the same database.

    .EXAMPLE
        PS C:\> New-DbaDbSynonym -SqlInstance sql2017a -Database db1 -Schema sch1 -Synonym synObj1 -BaseObject Obj1 -BaseSchema bSch2

        Will create a new synonym named synObj1 within sch1 schema in db1 database on sql2017a instance for Obj1 object within bSch2 schema in the same database.

    .EXAMPLE
        PS C:\> New-DbaDbSynonym -SqlInstance sql2017a -Database db1 -Schema sch1 -Synonym synObj1 -BaseObject Obj1 -BaseSchema bSch2 -BaseDatabase bDb3

        Will create a new synonym named synObj1 within sch1 schema in db1 database on sql2017a instance for Obj1 object within bSch2 schema in bDb3 database.

    .EXAMPLE
        PS C:\> New-DbaDbSynonym -SqlInstance sql2017a -Database db1 -Schema sch1 -Synonym synObj1 -BaseObject Obj1 -BaseSchema bSch2 -BaseDatabase bDb3 -BaseServer bSrv4

        Will create a new synonym named synObj1 within sch1 schema in db1 database on sql2017a instance for Obj1 object within bSch2 schema in bDb3 database on bSrv4 linked server.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2017a -ExcludeSystem | New-DbaDbSynonym -Synonym synObj1 -BaseObject Obj1

        Will create a new synonym named synObj1 within dbo schema in all user databases on sql2017a instance for Obj1 object in the respective databases.


    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [String]$Synonym,
        [String]$Schema = "dbo",
        [String]$BaseServer,
        [String]$BaseDatabase,
        [String]$BaseSchema,
        [parameter(Mandatory)]
        [String]$BaseObject,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a database or specify a SqlInstance."
            return
        }

        if (-not $BaseObject) {
            Stop-Function -Message "You must provide base object name."
            return
        }

        if ($BaseServer -and -not $BaseDatabase) {
            Stop-Function -Message "BaseServer parameter used - you must provide base database name."
            return
        }

        if ($BaseDatabase -and -not $BaseSchema) {
            Stop-Function -Message "BaseDatabase parameter used - you must provide base schema name."
            return
        }

        if (-not $Synonym) {
            Stop-Function -Message "You must specify a new synonym name."
            return
        }

        if ($SqlInstance) {
            foreach ($instance in $SqlInstance) {
                $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
            }
        }

        $InputObject = $InputObject | Where-Object { $_.IsAccessible -eq $true }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            Write-Message -Level 'Verbose' -Message "Getting Database Synonyms for $db on $server"

            $dbSynonyms = $db.Synonyms

            foreach ($syn in $Synonym) {
                if ($dbSynonyms | Where-Object Name -EQ $syn) {
                    Stop-Function -Message "The $syn synonym already exist within database $db on instance $server." -Target $db -Continue
                }

                Write-Message -Level Verbose -Message "Add synonyms to Database $db on target $server"

                if ($Pscmdlet.ShouldProcess("Creating new Synonym $synonym on database $db", $server)) {
                    try {
                        $newSynonym = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Synonym
                        $newSynonym.Name = $syn
                        $newSynonym.Schema = $Schema
                        $newSynonym.Parent = $db

                        $newSynonym.BaseDatabase = $BaseDatabase
                        $newSynonym.BaseSchema = $BaseSchema
                        $newSynonym.BaseObject = $BaseObject
                        $newSynonym.BaseServer = $BaseServer

                        $newSynonym.Create()

                        Add-Member -Force -InputObject $newSynonym -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                        Add-Member -Force -InputObject $newSynonym -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                        Add-Member -Force -InputObject $newSynonym -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                        Add-Member -Force -InputObject $newSynonym -MemberType NoteProperty -Name ParentName -Value $db.Name

                        Select-DefaultView -InputObject $newSynonym -Property ComputerName, InstanceName, SqlInstance, 'ParentName as Database', Name, Schema, BaseServer, BaseDatabase, BaseSchema, BaseObject
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                    }
                }
            }

        }
    }
}