function New-DbaDbTransfer {
    <#
    .SYNOPSIS
        Creates a configured SMO Transfer object for copying database objects between SQL Server instances

    .DESCRIPTION
        Returns a configured SMO Transfer object that defines what database objects to copy and how to copy them between SQL Server instances.
        This function prepares the transfer configuration but does not execute the actual copy operation - you must call .TransferData() on the returned object or pipe it to Invoke-DbaDbTransfer to perform the transfer.
        Useful for database migrations, environment refreshes, or selective object deployment where you need to copy specific tables, views, stored procedures, users, or other database objects.
        Supports copying schema only, data only, or both, with configurable batch sizes and timeout values for large data transfers.

    .PARAMETER SqlInstance
        Source SQL Server instance name.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DestinationSqlInstance
        Specifies the target SQL Server instance where database objects will be transferred. The function configures the SMO Transfer object to connect to this destination.
        You must have appropriate permissions to create the specified objects on the target server.

    .PARAMETER DestinationSqlCredential
        Credentials for connecting to the destination SQL Server instance. Accepts PowerShell credential objects created with Get-Credential.
        Only SQL Server authentication is supported for the destination connection. When not specified, uses Windows Authentication.

    .PARAMETER Database
        Specifies the source database containing the objects to transfer. This database must exist on the source SQL Server instance.
        Use this to define which database serves as the source for the transfer operation.

    .PARAMETER DestinationDatabase
        Specifies the target database where objects will be transferred. The database should already exist on the destination instance.
        When not specified, uses the same database name as the source database.

    .PARAMETER BatchSize
        Sets the number of rows to transfer in each batch during data copy operations. Controls memory usage and transaction log growth on the destination.
        Larger batch sizes improve performance but use more memory. Smaller batches reduce memory pressure but may slow transfer speed. Default is 50,000 rows.

    .PARAMETER BulkCopyTimeOut
        Sets the timeout in seconds for each bulk copy operation before it times out and fails. Prevents long-running transfers from hanging indefinitely.
        Increase this value when transferring large tables or working with slower network connections. Default is 5000 seconds.

    .PARAMETER ScriptingOption
        Provides custom scripting options that control how database objects are scripted during the transfer. Must be created using New-DbaScriptingOption.
        Use this to control object scripting behavior such as including permissions, check constraints, triggers, or indexes in the transfer.

    .PARAMETER InputObject
        Accepts specific database objects (tables, views, stored procedures, etc.) to transfer via pipeline input from other dbatools commands.
        Use this to transfer only selected objects instead of entire object types. Objects must be SMO objects from the source database.

    .PARAMETER CopyAllObjects
        Includes all transferable database objects in the transfer operation, regardless of object type. This is the broadest transfer scope available.
        Use this for complete database migrations or when you need to transfer everything except system objects and data.

    .PARAMETER CopyAll
        Specifies which types of database objects to include in the transfer operation. You can specify multiple object types to transfer specific categories.
        Common values include Tables, Views, StoredProcedures, UserDefinedFunctions, Users, and Roles for typical database migrations. Use this for selective transfers instead of copying all objects.
        Allowed values: FullTextCatalogs, FullTextStopLists, SearchPropertyLists, Tables, Views, StoredProcedures, UserDefinedFunctions, UserDefinedDataTypes, UserDefinedTableTypes, PlanGuides, Rules, Defaults, Users, Roles, PartitionSchemes, PartitionFunctions, XmlSchemaCollections, SqlAssemblies, UserDefinedAggregates, UserDefinedTypes, Schemas, Synonyms, Sequences, DatabaseTriggers, DatabaseScopedCredentials, ExternalFileFormats, ExternalDataSources, Logins, ExternalLibraries

    .PARAMETER SchemaOnly
        Transfers only the structure and definitions of database objects without copying any table data. Creates empty tables with all constraints, indexes, and triggers.
        Use this for setting up database structure in development environments or when data will be loaded separately.

    .PARAMETER DataOnly
        Transfers only table data without creating or modifying database object structures. Assumes that tables and other objects already exist on the destination.
        Use this for data refresh scenarios where the database schema is already in place and you only need to update the data.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: General, Transfer, Object
        Author: Kirill Kravtsov (@nvarscar)

        Website: https://dbatools.io
        Copyright: (c) 2020 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Transfer

        Returns a single configured SMO Transfer object that defines what database objects to copy and how to copy them to a destination SQL Server instance.
        The returned object is not executed - you must call .TransferData() on it or pipe it to Invoke-DbaDbTransfer to perform the actual transfer operation.

        Default properties configured based on parameters:
        - BatchSize: Number of rows to transfer in each batch (rows)
        - BulkCopyTimeOut: Timeout in seconds for bulk copy operations
        - CopyAllObjects: Boolean indicating if all transferable objects are included
        - CopyAll[ObjectType]: Individual boolean properties for each object type (CopyAllTables, CopyAllViews, CopyAllStoredProcedures, etc.)
        - Options: Scripting options controlling how objects are scripted (from -ScriptingOption parameter)
        - ObjectList: Collection of specific objects to transfer (populated from InputObject pipeline parameter)
        - DestinationServer: Target SQL Server instance name
        - DestinationDatabase: Target database name on destination instance
        - DestinationServerConnection: ServerConnection object configured for destination with SSL/TLS settings from source
        - DestinationLoginSecure: Boolean indicating if destination uses integrated security (True) or SQL authentication (False)
        - DestinationLogin: Username for SQL Server authentication on destination (only set if not using integrated security)
        - DestinationPassword: Password for SQL Server authentication on destination (only set if not using integrated security)
        - CopyData: Boolean indicating if table data will be copied (False when -SchemaOnly specified)
        - CopySchema: Boolean indicating if database object schema will be copied (False when -DataOnly specified)

        When -SchemaOnly is specified: CopyData property is set to False (schema only, no data)
        When -DataOnly is specified: CopySchema property is set to False (data only, assumes objects exist on destination)

        The Transfer object maintains all SMO Transfer properties and can be further customized by modifying returned object properties before calling TransferData().

    .LINK
        https://dbatools.io/New-DbaDbTransfer

    .EXAMPLE
        PS C:\> New-DbaDbTransfer -SqlInstance sql1 -Destination sql2 -Database mydb -CopyAll Tables

        Creates a transfer object that, when invoked, would copy all tables from database sql1.mydb to sql2.mydb

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance sql1 -Database MyDb -Table a, b, c | New-DbaDbTransfer -SqlInstance sql1 -Destination sql2 -Database mydb

        Creates a transfer object to copy specific tables from database sql1.mydb to sql2.mydb
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [OutputType([Microsoft.SqlServer.Management.Smo.Transfer])]
    [CmdletBinding(DefaultParameterSetName = "Default")]
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
        [Microsoft.SqlServer.Management.Smo.NamedSmoObject[]]$InputObject,
        [switch]$CopyAllObjects,
        [ValidateSet('FullTextCatalogs', 'FullTextStopLists', 'SearchPropertyLists', 'Tables',
            'Views', 'StoredProcedures', 'UserDefinedFunctions', 'UserDefinedDataTypes', 'UserDefinedTableTypes',
            'PlanGuides', 'Rules', 'Defaults', 'Users', 'Roles', 'PartitionSchemes', 'PartitionFunctions',
            'XmlSchemaCollections', 'SqlAssemblies', 'UserDefinedAggregates', 'UserDefinedTypes', 'Schemas',
            'Synonyms', 'Sequences', 'DatabaseTriggers', 'DatabaseScopedCredentials', 'ExternalFileFormats',
            'ExternalDataSources', 'Logins', 'ExternalLibraries')]
        [string[]]$CopyAll,
        [switch]$SchemaOnly,
        [switch]$DataOnly,
        [switch]$EnableException
    )
    begin {
        $objectCollection = New-Object System.Collections.ArrayList
    }
    process {
        if (Test-Bound -Not SqlInstance) {
            Stop-Function -Message "Source instance was not specified"
            return
        }
        if (Test-Bound -Not Database) {
            Stop-Function -Message "Source database was not specified"
            return
        }
        foreach ($object in $InputObject) {
            if (-not $object) {
                Stop-Function -Message "Object is empty"
                return
            }
            $objectCollection.Add($object) | Out-Null
        }

    }
    end {
        try {
            $sourceDb = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -EnableException
        } catch {
            Stop-Function -Message "Failed to retrieve database from the source instance $SqlInstance" -ErrorRecord $_
            return
        }
        if (-not $sourceDb) {
            Stop-Function -Message "Database $Database not found on $SqlInstance"
            return
        } elseif ($sourceDb.Count -gt 1) {
            Stop-Function -Message "More than one database found on $SqlInstanced with the parameters provided"
            return
        }
        # Create transfer object and define properties based on parameters
        $transfer = New-Object Microsoft.SqlServer.Management.Smo.Transfer($sourceDb)
        foreach ($object in $objectCollection) {
            $transfer.ObjectList.Add($object) | Out-Null
        }
        $transfer.BatchSize = $BatchSize
        $transfer.BulkCopyTimeOut = $BulkCopyTimeOut
        $transfer.CopyAllObjects = $CopyAllObjects
        foreach ($copyType in $CopyAll) {
            $transfer."CopyAll$copyType" = $true
        }
        if ($ScriptingOption) { $transfer.Options = $ScriptingOption }

        # Add destination connection parameters
        # Infer SSL/TLS settings from source connection
        $sourceTrustCert = $sourceDb.Parent.ConnectionContext.TrustServerCertificate
        $sourceEncrypt = $sourceDb.Parent.ConnectionContext.EncryptConnection

        if ($DestinationSqlInstance.IsConnectionString) {
            $connString = $DestinationSqlInstance.InputObject
        } elseif ($DestinationSqlInstance.Type -eq 'RegisteredServer' -and $DestinationSqlInstance.InputObject.ConnectionString) {
            $connString = $DestinationSqlInstance.InputObject.ConnectionString
        } elseif ($DestinationSqlInstance.Type -eq 'Server' -and $DestinationSqlInstance.InputObject.ConnectionContext.ConnectionString) {
            $connString = $DestinationSqlInstance.InputObject.ConnectionContext.ConnectionString
        } else {
            $transfer.DestinationServer = $DestinationSqlInstance.InputObject
            $transfer.DestinationLoginSecure = $true
        }

        # Build connection string for destination with SSL settings from source
        $destServer = $null
        $destDatabase = $DestinationDatabase
        $destIntegratedSecurity = $true
        $destUserName = $null
        $destPassword = $null

        if ($connString) {
            $connStringBuilder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder $connString
            $destServer = if ($srv = $connStringBuilder["Data Source"]) { $srv } else { "localhost" }
            if (($db = $connStringBuilder["Initial Catalog"]) -and (Test-Bound -Not -Parameter DestinationDatabase)) {
                $destDatabase = $db
            }
            $destIntegratedSecurity = $connStringBuilder["Integrated Security"]
            $destUserName = $connStringBuilder["User ID"]
            $destPassword = $connStringBuilder["Password"]
        } else {
            $destServer = $DestinationSqlInstance.InputObject
        }

        # Override with DestinationSqlCredential if provided
        if ($DestinationSqlCredential) {
            $destIntegratedSecurity = $false
            $destUserName = $DestinationSqlCredential.UserName
            $destPassword = $DestinationSqlCredential.GetNetworkCredential().Password
        }

        # Build connection string with SSL settings from source
        $destConnStringBuilder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder
        $destConnStringBuilder["Data Source"] = $destServer
        $destConnStringBuilder["Initial Catalog"] = $destDatabase
        $destConnStringBuilder["Integrated Security"] = $destIntegratedSecurity
        $destConnStringBuilder["TrustServerCertificate"] = $sourceTrustCert
        $destConnStringBuilder["Encrypt"] = $sourceEncrypt

        if (-not $destIntegratedSecurity) {
            $destConnStringBuilder["User ID"] = $destUserName
            $destConnStringBuilder["Password"] = $destPassword
        }

        # Create ServerConnection with SSL settings
        $destSqlConnection = New-Object Microsoft.Data.SqlClient.SqlConnection $destConnStringBuilder.ConnectionString
        $destServerConnection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection $destSqlConnection
        $transfer.DestinationServerConnection = $destServerConnection

        # Also set individual properties for backward compatibility
        $transfer.DestinationServer = $destServer
        $transfer.DestinationDatabase = $destDatabase
        $transfer.DestinationLoginSecure = $destIntegratedSecurity
        if (-not $destIntegratedSecurity) {
            $transfer.DestinationLogin = $destUserName
            $transfer.DestinationPassword = $destPassword
        }
        if (Test-Bound -Parameter SchemaOnly) { $transfer.CopyData = -not $SchemaOnly }
        if (Test-Bound -Parameter DataOnly) { $transfer.CopySchema = -not $DataOnly }

        return $transfer
    }
}