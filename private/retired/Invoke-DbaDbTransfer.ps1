function Invoke-DbaDbTransfer {
    <#
    .SYNOPSIS
        Transfers database objects and data between SQL Server instances or databases using SMO Transfer objects.

    .DESCRIPTION
        Transfers database objects and data between SQL Server instances or databases by executing an SMO Transfer object. This function handles database migrations, environment synchronization, and selective object deployment scenarios where you need to copy specific objects or data without doing a full database restore. You can transfer everything at once, copy only schema without data, copy only data without schema, or generate scripts for manual review. The function works with transfer objects created by New-DbaDbTransfer or generates them automatically based on the parameters you provide.

    .PARAMETER SqlInstance
        Source SQL Server instance name.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DestinationSqlInstance
        Target SQL Server instance where database objects will be transferred to. You must have appropriate permissions to create and modify objects on the destination server.
        Use this to specify a different server for migrations, environment promotions, or cross-server object synchronization.

    .PARAMETER DestinationSqlCredential
        Credentials for connecting to the destination SQL Server instance. Accepts PowerShell credentials created with Get-Credential.
        Only SQL Server Authentication is supported for destination connections. When not specified, the function uses Windows Integrated Authentication.

    .PARAMETER Database
        Source database name containing the objects to transfer. This database must exist on the source SQL Server instance.
        Specify the exact database name - wildcards are not supported for this parameter.

    .PARAMETER DestinationDatabase
        Target database name where objects will be transferred to. If not specified, uses the same name as the source database.
        Use this when transferring objects to a database with a different name, such as during environment refreshes where databases have different naming conventions.

    .PARAMETER BatchSize
        Number of rows to transfer in each batch operation during data copy. Defaults to 50,000 rows per batch.
        Increase this value for faster transfers of large tables, or decrease it to reduce memory usage and lock duration on busy systems.

    .PARAMETER BulkCopyTimeOut
        Timeout in seconds for bulk copy operations when transferring table data. Defaults to 5000 seconds.
        Increase this value when transferring very large tables that take longer than the default timeout to complete.

    .PARAMETER ScriptingOption
        Custom scripting configuration created by New-DbaScriptingOption that controls how objects are scripted during transfer.
        Use this to customize object scripting behavior such as including permissions, indexes, triggers, or generating DROP statements.

    .PARAMETER InputObject
        Pre-configured SMO Transfer object created by New-DbaDbTransfer that defines what to transfer and how.
        Use this when you need to customize transfer settings beyond what the direct parameters provide, or when reusing the same transfer configuration multiple times.

    .PARAMETER CopyAllObjects
        Transfers all database objects including tables, views, stored procedures, functions, users, roles, and other database-level objects.
        Use this for complete database migrations where you need to copy everything from the source database to the destination.

    .PARAMETER CopyAll
        Specific types of database objects to transfer. Accepts an array of object type names for selective copying.
        Use this when you only need certain object types instead of everything, such as copying only tables and views for a data warehouse refresh.
        Common values include Tables, Views, StoredProcedures, UserDefinedFunctions, Users, Roles, and Schemas.

    .PARAMETER SchemaOnly
        Transfers only the structure and definitions of database objects without copying any table data.
        Use this for setting up new environments where you need the database structure but will populate data separately, or for schema synchronization between environments.

    .PARAMETER DataOnly
        Transfers only table data without creating or modifying object schemas. Target objects must already exist in the destination database.
        Use this for data refreshes where the destination database structure is already in place and you only need to update the data.

    .PARAMETER ScriptOnly
        Generates T-SQL scripts for creating the selected objects without actually executing the transfer.
        Use this to review what would be created, save scripts for later execution, or integrate with deployment pipelines that require script artifacts.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: General, Object
        Author: Kirill Kravtsov (@nvarscar)

        Website: https://dbatools.io
        Copyright: (c) 2020 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbTransfer

    .OUTPUTS
        PSCustomObject (default behavior)

        Returns one object with transfer summary information when the transfer completes successfully.

        Properties:
        - SourceInstance: Name of the source SQL Server instance
        - SourceDatabase: Name of the source database
        - DestinationInstance: Name of the destination SQL Server instance
        - DestinationDatabase: Name of the destination database
        - Status: Transfer status (returns "Success" when transfer completes)
        - Elapsed: Time elapsed during the transfer operation displayed as a human-readable timespan (e.g., "00:05:30")
        - Log: Array of event messages captured during transfer from DataTransferEvent events

        System.String array (when -ScriptOnly is specified)

        When -ScriptOnly is specified, returns an array of T-SQL script statements that would be executed to create the transferred objects, without actually performing the transfer.

    .EXAMPLE
        PS C:\> Invoke-DbaDbTransfer -SqlInstance sql1 -DestinationSqlInstance sql2 -Database mydb -CopyAll Tables -DestinationDatabase newdb

        Copies all tables from database mydb on sql1 to database newdb on sql2.

    .EXAMPLE
        PS C:\> Invoke-DbaDbTransfer -SqlInstance sql1 -DestinationSqlInstance sql2 -Database mydb -CopyAllObjects

        Copies all objects from database mydb on sql1 to database mydb on sql2.

    .EXAMPLE
        PS C:\> $transfer = New-DbaDbTransfer -SqlInstance sql1 -DestinationSqlInstance sql2 -Database mydb -CopyAllObjects
        PS C:\> $transfer.Options.ScriptDrops = $true
        PS C:\> $transfer.SchemaOnly = $true
        PS C:\> $transfer | Invoke-DbaDbTransfer

        Copies object schema from database mydb on sql1 to database mydb on sql2 using customized transfer parameters.

    .EXAMPLE
        PS C:\> $options = New-DbaScriptingOption
        PS C:\> $options.ScriptDrops = $true
        PS C:\> $transfer = New-DbaDbTransfer -SqlInstance sql1 -DestinationSqlInstance sql2 -Database mydb -CopyAll StoredProcedures -ScriptingOption $options
        PS C:\> $transfer | Invoke-DbaDbTransfer

        Copies procedures from database mydb on sql1 to database mydb on sql2 using custom scripting parameters.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
    Param (
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [DbaInstanceParameter]$DestinationSqlInstance,
        [PSCredential]$DestinationSqlCredential,
        [string]$Database,
        [string]$DestinationDatabase = $Database,
        [int]$BatchSize = 50000,
        [int]$BulkCopyTimeOut = 5000,
        [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOption,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Transfer]$InputObject,
        [switch]$CopyAllObjects,
        [ValidateSet('FullTextCatalogs', 'FullTextStopLists', 'SearchPropertyLists',
            'Tables', 'Views', 'StoredProcedures', 'UserDefinedFunctions', 'UserDefinedDataTypes',
            'UserDefinedTableTypes', 'PlanGuides', 'Rules', 'Defaults', 'Users', 'Roles', 'PartitionSchemes',
            'PartitionFunctions', 'XmlSchemaCollections', 'SqlAssemblies', 'UserDefinedAggregates',
            'UserDefinedTypes', 'Schemas', 'Synonyms', 'Sequences', 'DatabaseTriggers', 'DatabaseScopedCredentials',
            'ExternalFileFormats', 'ExternalDataSources', 'Logins', 'ExternalLibraries')]
        [string[]]$CopyAll,
        [switch]$SchemaOnly,
        [switch]$DataOnly,
        [switch]$ScriptOnly,
        [switch]$EnableException
    )
    begin {
        $newTransferParams = (Get-Command New-DbaDbTransfer).Parameters.Keys | Where-Object { $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters }
    }
    process {
        if ($InputObject) {
            $transfer = $InputObject
        } else {
            $paramSet = @{ }
            # generate transfer object by adding all applicable parameters to the New-DbaDbTransfer call
            foreach ($key in $PSBoundParameters.Keys) {
                if ($key -in $newTransferParams) {
                    $paramSet[$key] = $PSBoundParameters[$key]
                }
            }
            Write-Message -Message "Generating a transfer object based on current parameters" -Level Verbose
            $transfer = New-DbaDbTransfer @paramSet
        }
        # add event handling
        $events = Register-ObjectEvent -InputObject $transfer -EventName DataTransferEvent -Action {
            "[$(Get-Date)] [$($args[1].DataTransferEventType)] $($args[1].Message)"
        }
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        if ($PSCmdlet.ShouldProcess("Begin transfer")) {
            try {
                if ($ScriptOnly) {
                    return $transfer.ScriptTransfer()
                } else {
                    $transfer.TransferData()
                }
            } catch {
                Stop-Function -ErrorRecord $_ -Message "Transfer failed"
                return
            }

            return [PSCustomObject]@{
                SourceInstance      = $transfer.Database.Parent.Name
                SourceDatabase      = $transfer.Database.Name
                DestinationInstance = $transfer.DestinationServer
                DestinationDatabase = $transfer.DestinationDatabase
                Status              = 'Success'
                Elapsed             = [prettytimespan]$elapsed.Elapsed
                Log                 = $events.Output
            }
        }
    }
}