function Invoke-DbaDbDecryptObject {
    <#
    .SYNOPSIS
        Decrypts encrypted stored procedures, functions, views, and triggers

    .DESCRIPTION
        Recovers the original source code from encrypted database objects when the original scripts have been lost or are unavailable. WITH ENCRYPTION stores the source text combined with a keystream using XOR rather than really encrypting it, so the original T-SQL can be recovered.

        This is particularly useful in disaster recovery scenarios where you need to recreate objects but only have access to the encrypted versions in the database. The function can decrypt stored procedures, user-defined functions (scalar, inline, table-valued), views, and triggers.

        The command outputs results to the console by default, with an option to export all decrypted objects to organized .sql files in a folder structure.

        Two methods are available and are selected with DataPages.

        By default the command uses a Dedicated Admin Connection (DAC) to read the binary definition from sys.sysobjvalues. It then alters the object to a known placeholder inside a transaction that is rolled back, which produces a known plaintext together with its matching ciphertext, and recovers the original text from those three values.

        With -DataPages no DAC is used and the object is never altered. The binary definition is read straight from the raw data pages with DBCC PAGE and the keystream is rebuilt from database and object metadata, so nothing is written to the database at any point. This method needs sysadmin, and it returns the definition exactly as it is stored, so object definitions that contain Unicode characters come back intact.

        Both methods need SQL Server 2008 or later. Encrypted definitions have been stored this way since SQL Server 2005, but SMO cannot work against 2005 at all, so no dbatools command reaches that version.

        The following paragraphs only apply to the default method that uses the DAC.

        To connect to a remote SQL instance, the remote dedicated administrator connection option must be configured. The binary versions of encrypted objects can only be retrieved using a DAC connection.
        You can check the remote DAC connection with:
        'Get-DbaSpConfigure -SqlInstance [yourinstance] -ConfigName RemoteDacConnectionsEnabled'
        The ConfiguredValue should be 1.

        The local DAC connection is enabled by default.

        To enable remote DAC connections, use:
        'Set-DbaSpConfigure -SqlInstance [yourinstance] -ConfigName RemoteDacConnectionsEnabled -Value 1'
        In some cases you may need to restart the SQL Server instance after enabling this setting.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases contain the encrypted objects you want to decrypt. Accepts multiple database names.
        Use this to target specific databases instead of searching across all databases on the instance.

    .PARAMETER ObjectName
        Specifies the names of encrypted objects to decrypt (stored procedures, functions, views, or triggers). Accepts multiple object names.
        When omitted, all encrypted objects in the specified databases will be decrypted. Use this to target specific objects when you only need a few items recovered.

    .PARAMETER EncodingType
        Determines the text encoding used during the XOR decryption process to convert binary data back to readable T-SQL code. Defaults to ASCII.
        Use UTF8 when dealing with databases that contain Unicode characters in object definitions or when ASCII decryption produces garbled text.

        Only applies to the default method that uses the DAC. With -DataPages the definition is decoded with the encoding that SQL Server actually stores it in, so this parameter is not used.

    .PARAMETER ExportDestination
        Specifies the folder path where decrypted T-SQL scripts will be saved as individual .sql files.
        When specified, creates an organized folder structure by instance, database, and object type (e.g., C:\temp\decrypt\SQLDB1\DB1\StoredProcedure). When omitted, results are displayed in the console only.

    .PARAMETER DataPages
        Reads the binary definition from the raw data pages with DBCC PAGE instead of through a Dedicated Admin Connection. No DAC is needed, the instance does not have to allow remote DAC connections, only one connection is used, and no object is ever altered, so no write happens against the database. This needs sysadmin.

        Leave it off to keep the original behaviour of the command, where a Dedicated Admin Connection reads sys.sysobjvalues and each object is briefly altered inside a transaction that is rolled back to obtain a known plaintext.

        Two cases need -DataPages rather than merely preferring it, and both come from the default method having to alter the object.

        An INSTEAD OF trigger defined on a view cannot be decrypted by the default method at all, because that method obtains its known plaintext by rewriting the object as an AFTER trigger and a view only accepts INSTEAD OF. Reading the data pages has no such restriction.

        A read-only database is the other. A database snapshot and an availability group readable secondary can both be read with -DataPages, while the default method fails against either because it cannot alter anything there.

        Not available on Azure SQL Database or Azure SQL Managed Instance, neither of which supports DBCC PAGE. The command refuses -DataPages on both rather than failing part way through reading the pages.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Encryption, Decrypt, Utility
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        PSCustomObject

        Returns one object per encrypted database object that is successfully decrypted. If no encrypted objects are found, nothing is returned.

        Properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Database: The name of the database containing the encrypted object
        - Type: The type of database object (StoredProcedure, UserDefinedFunction, View, or Trigger)
        - Schema: The schema name containing the object
        - Name: The object name
        - FullName: The fully qualified name in schema.name format
        - Script: The decrypted T-SQL source code of the object
        - OutputFile: The file path where the script was exported; null if -ExportDestination was not specified and results were displayed in console only

    .LINK
        https://dbatools.io/Invoke-DbaDbDecryptObject

    .EXAMPLE
        PS C:\> Invoke-DbaDbDecryptObject -SqlInstance SQLDB1 -Database DB1 -ObjectName Function1

        Decrypt object "Function1" in DB1 of instance SQLDB1 and output the data to the user.

    .EXAMPLE
        PS C:\> Invoke-DbaDbDecryptObject -SqlInstance SQLDB1 -Database DB1 -ObjectName Function1 -ExportDestination C:\temp\decrypt

        Decrypt object "Function1" in DB1 of instance SQLDB1 and output the data to the folder "C:\temp\decrypt".

    .EXAMPLE
        PS C:\> Invoke-DbaDbDecryptObject -SqlInstance SQLDB1 -Database DB1 -ExportDestination C:\temp\decrypt

        Decrypt all objects in DB1 of instance SQLDB1 and output the data to the folder "C:\temp\decrypt"

    .EXAMPLE
        PS C:\> Invoke-DbaDbDecryptObject -SqlInstance SQLDB1 -Database DB1 -ObjectName Function1, Function2

        Decrypt objects "Function1" and "Function2" and output the data to the user.

    .EXAMPLE
        PS C:\> "SQLDB1" | Invoke-DbaDbDecryptObject -Database DB1 -ObjectName Function1, Function2

        Decrypt objects "Function1" and "Function2" and output the data to the user using a pipeline for the instance.

    .EXAMPLE
        PS C:\> Invoke-DbaDbDecryptObject -SqlInstance SQLDB1 -Database DB1 -DataPages

        Decrypt all objects in DB1 of instance SQLDB1 without using a dedicated admin connection and without altering any of the objects.

    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [object[]]$Database,
        [string[]]$ObjectName,
        [ValidateSet('ASCII', 'UTF8')]
        [string]$EncodingType = 'ASCII',
        [string]$ExportDestination,
        [switch]$DataPages,
        [switch]$EnableException
    )

    begin {

        function Invoke-DecryptData() {
            param(
                [parameter(Mandatory)]
                [byte[]]$Secret,
                [parameter(Mandatory)]
                [byte[]]$KnownPlain,
                [parameter(Mandatory)]
                [byte[]]$KnownSecret
            )

            # Declare pointers
            [int]$i = 0

            # Loop through each of the characters and apply an XOR to decrypt the data
            $result = $(

                # Loop through the byte string
                while ($i -lt $Secret.Length) {

                    # Compare the byte string character to the key character using XOR
                    if ($i -lt $Secret.Length) {
                        $Secret[$i] -bxor $KnownPlain[$i] -bxor $KnownSecret[$i]
                    }

                    # Increment the byte string indicator
                    $i += 2

                } # end while loop

            ) # end data value

            # Get the string value from the data
            $decryptedData = $Encoding.GetString($result)

            # Return the decrypted data
            return $decryptedData
        }

        # Set the encoding
        if ($EncodingType -eq 'ASCII') {
            $encoding = [System.Text.Encoding]::ASCII
        } elseif ($EncodingType -eq 'UTF8') {
            $encoding = [System.Text.Encoding]::UTF8
        }

        # EncodingType only means anything to the method that uses the DAC, which decodes the low byte of
        # each character. Reading the data pages returns the definition in the encoding SQL Server actually
        # stored it in, so say so rather than letting the parameter look like it did something.
        if ($DataPages -and (Test-Bound -ParameterName EncodingType)) {
            Write-Message -Level Warning -Message "EncodingType is ignored when DataPages is used, because the definition is decoded as the UCS-2 that SQL Server stores."
        }

        # Check the export parameter
        if ($ExportDestination -and -not (Test-Path $ExportDestination)) {
            try {
                # Create the new destination
                New-Item -Path $ExportDestination -ItemType Directory -Force | Out-Null
            } catch {
                Stop-Function -Message "Couldn't create destination folder $ExportDestination" -ErrorRecord $_ -Target $instance -Continue
            }
        }

    }

    process {

        if (Test-FunctionInterrupt) { return }

        # Loop through all the instances
        foreach ($instance in $SqlInstance) {

            # Check the configuration of the intance to see if the DAC is enabled
            if (-not $DataPages) {
                $config = Get-DbaSpConfigure -SqlInstance $instance -SqlCredential $SqlCredential -ConfigName RemoteDacConnectionsEnabled
            }
            if (-not $DataPages -and $config.ConfiguredValue -ne 1) {
                Stop-Function -Message "DAC is not enabled for instance $instance.`nPlease use 'Set-DbaSpConfigure -SqlInstance $instance -SqlCredential <credential> -ConfigName RemoteDacConnectionsEnabled -Value 1' to configure the instance to allow DAC connections" -Target $instance -Continue
            }

            $dacOpened = $false

            # Cleared per instance, because the finally below restores whatever these hold and a capture
            # that failed for this instance would otherwise put the previous instance's fields on it.
            $savedInitFieldsProcedure = $null
            $savedInitFieldsView = $null
            $savedInitFieldsFunction = $null

            # Try to connect to instance
            try {
                if (-not $DataPages) {
                    # Do we have a dedicated admin connection already?
                    $dacConnected = Test-DacConnection -InputObject $instance
                    if ($dacConnected) {
                        Write-Message -Level Verbose -Message "Reusing dedicated admin connection."
                        $server = $instance.InputObject
                    } else {
                        Write-Message -Level Verbose -Message "Opening dedicated admin connection."
                        $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -DedicatedAdminConnection -WarningAction SilentlyContinue
                        $dacOpened = $true
                    }
                } else {
                    # Reading the data pages needs no dedicated admin connection, so the connection of
                    # the caller is used as it is and is left alone afterwards.
                    #
                    # sys.sysobjvalues, which holds the encrypted definitions, arrived with SQL Server
                    # 2005, but the floor here is 2008. SMO cannot work against 2005 at all: enumerating
                    # any collection issues CONNECTIONPROPERTY and reading the databases asks for
                    # is_cdc_enabled, both of which arrived in 2008, so the command fails on
                    # $server.Databases before a page is read. 2008 itself is verified, seek route and
                    # page chain walk both, with every storage shape byte exact.
                    #
                    # Note that this does not actually refuse a 2005 instance. Connect-DbaInstance only
                    # applies MinimumVersion when it can read VersionMajor, and on 2005 that property
                    # comes back empty for the same reason everything else does, so the connection is
                    # allowed and fails later in SMO. The floor is here to say what is supported, not
                    # because it can be enforced at the one version where it would matter.
                    Write-Message -Level Verbose -Message "Opening a regular connection to read the data pages."
                    $connectParams = @{
                        SqlInstance    = $instance
                        SqlCredential  = $SqlCredential
                        MinimumVersion = 10
                    }
                    $server = Connect-DbaInstance @connectParams
                }
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # An instance allows only one dedicated admin connection, so one that is left behind blocks the
            # next run until the session is killed. A terminating error anywhere below would leak the one
            # this command opened, so the disconnect sits in a finally rather than at the end of the body.
            try {
                # Neither Azure SQL Database nor Azure SQL Managed Instance supports DBCC PAGE, so reading
                # the data pages cannot work on either. MinimumVersion does not catch them, because both
                # report a version this command is happy with, and without this the run gets as far as the
                # first DBCC and fails on something that does not name the real problem.
                #
                # Both checks are needed. DatabaseEngineType only distinguishes Azure SQL Database, so a
                # Managed Instance is identified by its engine edition, and that is tested first so the
                # message names the right one whichever way the engine type reads.
                if ($DataPages) {
                    $azurePlatform = $null
                    if ($server.DatabaseEngineEdition -eq "SqlManagedInstance") {
                        $azurePlatform = "Azure SQL Managed Instance"
                    } elseif ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                        $azurePlatform = "Azure SQL Database"
                    }

                    if ($azurePlatform) {
                        Stop-Function -Message "Reading the encrypted objects on $instance without a dedicated admin connection uses DBCC PAGE, which $azurePlatform does not support." -Target $instance -Continue
                    }

                    # DBCC PAGE is limited to sysadmin, so checking up front gives a clear message instead of
                    # a permission error in the middle of reading the pages. sys.database_recovery_status, which
                    # supplies the family GUID, needs only VIEW SERVER STATE, which a sysadmin already holds.
                    $querySysadmin = @"
SELECT IS_SRVROLEMEMBER('sysadmin') AS IsSysadmin
"@
                    $sysadmin = @($server.Query($querySysadmin))
                    if ($sysadmin[0].IsSysadmin -ne 1) {
                        Stop-Function -Message "Reading the encrypted objects without a dedicated admin connection uses DBCC PAGE, which requires sysadmin on $instance. Connect as a sysadmin or drop -DataPages." -Target $instance -Continue
                    }
                }

                # Finding the encrypted objects reads IsEncrypted on every stored procedure, function and view
                # in the database. SMO does not include that property in the set it fetches when it enumerates
                # a collection, so it goes back to the instance once per object, and on a database with a
                # couple of thousand modules that costs far more than the decryption itself. Asking for it up
                # front makes SMO fetch it as part of the enumeration. This mirrors what Connect-DbaInstance
                # already does for databases, logins and jobs.
                #
                # ID rides along with it for the same reason. Both decrypt methods below select an object's
                # rows by id rather than by name, and SMO's own ID property is already the object id, so
                # fetching it here means neither method ever needs a name based lookup to get one.
                #
                # The setting belongs to the connection and outlives this command on one the caller owns, so
                # whatever is there is captured first and put back in the finally below. Without that, a
                # caller who had chosen their own fields for these three types would find them replaced for
                # the rest of their session. GetDefaultInitFields hands back a copy rather than the live
                # collection, which is what makes capturing it work.
                try {
                    $savedInitFieldsProcedure = $server.GetDefaultInitFields([Microsoft.SqlServer.Management.Smo.StoredProcedure])
                    $savedInitFieldsView = $server.GetDefaultInitFields([Microsoft.SqlServer.Management.Smo.View])
                    $savedInitFieldsFunction = $server.GetDefaultInitFields([Microsoft.SqlServer.Management.Smo.UserDefinedFunction])

                    $initFieldsModule = New-Object System.Collections.Specialized.StringCollection
                    [void]$initFieldsModule.AddRange([string[]]@("Name", "Schema", "IsEncrypted", "IsSystemObject", "ID"))
                    $initFieldsFunction = New-Object System.Collections.Specialized.StringCollection
                    [void]$initFieldsFunction.AddRange([string[]]@("Name", "Schema", "IsEncrypted", "IsSystemObject", "FunctionType", "ID"))
                    $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.StoredProcedure], $initFieldsModule)
                    $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.View], $initFieldsModule)
                    $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.UserDefinedFunction], $initFieldsFunction)
                } catch {
                    Write-Message -Level Debug -Message "SetDefaultInitFields failed with $_"
                    # Only a performance measure, so the command carries on with whatever SMO fetches by default.
                }

                # Get all the databases that compare to the database parameter
                $databaseCollection = $server.Databases | Where-Object { $_.Name -in $Database }

                # Use the table's schema for the trigger's schema. The schema name is not returned as a property for triggers (except in the URN).
                $triggerSchema = @{label = "Schema"; expression = { $_.Parent.Schema } }

                # Loop through each of databases
                # Working through a Database object moves the connection into that database and never moves it
                # back - the queries below run there, and so does every enumeration of a database level
                # collection. The database of the caller is put back when the work is done. See #10555.
                $callerDatabase = $server.ConnectionContext.CurrentDatabase
                try {
                    foreach ($db in $databaseCollection) {

                        # Create array list to hold the results. This starts empty for every database, because the
                        # objects of one database must not be looked up again in the next one.
                        $objectCollection = @()

                        # A trigger's collection hangs off its parent table, so asking every table for its triggers
                        # costs one round trip per table: on a database of a thousand tables that is a thousand
                        # queries, run even when the object asked for is a stored procedure. The tables that own an
                        # encrypted trigger are identified in one query first, and only those are asked. A database
                        # with no encrypted triggers touches no tables at all.
                    $queryTriggerParent = @"
SELECT DISTINCT SCHEMA_NAME(p.schema_id) AS ParentSchema, p.name AS ParentName
FROM sys.sql_modules AS m
INNER JOIN sys.objects AS t ON t.object_id = m.object_id
INNER JOIN sys.objects AS p ON p.object_id = t.parent_object_id
WHERE m.definition IS NULL
AND t.type = 'TR'
AND p.is_ms_shipped = 0
"@

                        $triggers = @(
                            foreach ($triggerParent in @($db.Query($queryTriggerParent))) {
                                # A trigger's parent is a table or a view, and an INSTEAD OF trigger on a view is
                                # just as encryptable as one on a table. Looking only at tables silently skipped
                                # those, so both collections are asked.
                                $parentObject = $db.Tables[$triggerParent.ParentName, $triggerParent.ParentSchema]
                                if ($null -eq $parentObject) {
                                    $parentObject = $db.Views[$triggerParent.ParentName, $triggerParent.ParentSchema]
                                }
                                if ($null -ne $parentObject) {
                                    $parentObject.Triggers
                                }
                            }
                        )

                        # Get the objects
                        if ($ObjectName) {
                            $storedProcedures = @($db.StoredProcedures | Where-Object { $_.Name -in $ObjectName -and $_.IsEncrypted -eq $true } | Select-Object Name, Schema, ID, @{N = "ObjectType"; E = { "StoredProcedure" } }, @{N = "SubType"; E = { "" } })
                            $functions = @($db.UserDefinedFunctions | Where-Object { $_.Name -in $ObjectName -and $_.IsEncrypted -eq $true } | Select-Object Name, Schema, ID, @{N = "ObjectType"; E = { "UserDefinedFunction" } }, @{N = "SubType"; E = { $_.FunctionType.ToString().Trim() } })
                            $views = @($db.Views | Where-Object { $_.Name -in $ObjectName -and $_.IsEncrypted -eq $true } | Select-Object Name, Schema, ID, @{N = "ObjectType"; E = { "View" } }, @{N = "SubType"; E = { "" } })
                            $triggers = @($triggers | Where-Object { $_.Name -in $ObjectName -and $_.IsEncrypted -eq $true } | Select-Object Name, $triggerSchema, ID, Parent, @{N = "ObjectType"; E = { "Trigger" } }, @{N = "SubType"; E = { "" } })
                        } else {
                            # Get all encrypted objects
                            $storedProcedures = @($db.StoredProcedures | Where-Object { $_.IsEncrypted -eq $true } | Select-Object Name, Schema, ID, @{N = "ObjectType"; E = { "StoredProcedure" } }, @{N = "SubType"; E = { "" } })
                            $functions = @($db.UserDefinedFunctions | Where-Object { $_.IsEncrypted -eq $true } | Select-Object Name, Schema, ID, @{N = "ObjectType"; E = { "UserDefinedFunction" } }, @{N = "SubType"; E = { $_.FunctionType.ToString().Trim() } })
                            $views = @($db.Views | Where-Object { $_.IsEncrypted -eq $true } | Select-Object Name, Schema, ID, @{N = "ObjectType"; E = { "View" } }, @{N = "SubType"; E = { "" } })
                            $triggers = @($triggers | Where-Object { $_.IsEncrypted -eq $true } | Select-Object Name, $triggerSchema, ID, Parent, @{N = "ObjectType"; E = { "Trigger" } }, @{N = "SubType"; E = { "" } })
                        }

                        # Check if there are any objects
                        if ($storedProcedures.Count -ge 1) {
                            $objectCollection += $storedProcedures
                        }
                        if ($functions.Count -ge 1) {
                            $objectCollection += $functions
                        }
                        if ($views.Count -ge 1) {
                            $objectCollection += $views
                        }
                        if ($triggers.Count -ge 1) {
                            $objectCollection += $triggers
                        }

                        # Both methods identify an object by its id rather than by its name. The method that
                        # reads the data pages needs the id to pick the rows out of sys.sysobjvalues, and the
                        # method that uses the dedicated admin connection needs it because an object name is
                        # allowed to contain a single quote: splicing the name into an OBJECT_ID('...') literal
                        # would let a crafted name end the literal early and run whatever followed it as a
                        # further statement in the same batch, as sysadmin over the dedicated admin connection.
                        # An id is a number, so nothing a name contains can reach the query text.
                        #
                        # The id is SMO's own ID property on each object, fetched as part of the enumeration
                        # above rather than looked up afterwards by schema and name. A lookup keyed by
                        # "$schema.$name" cannot be unambiguous, because either half may itself contain a dot:
                        # schema [a], object [b.c] and schema [a.b], object [c] both key as "a.b.c", so whichever
                        # of the two is read last silently overwrites the other's id in the map, and the object
                        # that lost the race is then decrypted with the wrong ciphertext. Reading the id SMO
                        # already carries on the object needs no key at all, so two objects sharing a dotted name
                        # can no longer collide.

                        # Without a dedicated admin connection the ciphertext of every requested object is read in
                        # a single pass over the data pages of sys.sysobjvalues, because reading those pages is by
                        # far the most expensive part. The family GUID of the database and the object ids are the
                        # only other inputs that rebuilding the keystream needs.
                        if ($DataPages) {
                            $familyGuid = $null
                            $imageValueMap = @{ }

                            # The family GUID comes from the catalog view sys.database_recovery_status, a typed
                            # uniqueidentifier present since SQL Server 2005, rather than by scraping dbi_familyGUID
                            # out of DBCC DBINFO's text dump. The two were measured byte for byte across SQL Server
                            # 2019, 2022 and 2025, for user databases and master, and always agree, so the swap keeps
                            # the keystream input identical while dropping a trace flag toggle and a regex over prose.
                            try {
                                $familyGuidRow = @($db.Query("SELECT family_guid FROM sys.database_recovery_status WHERE database_id = DB_ID()"))
                            } catch {
                                Stop-Function -Message "Couldn't read the family GUID of database $($db.Name) on $instance" -ErrorRecord $_ -Target $instance -Continue
                            }

                            if ($familyGuidRow.Count -eq 0 -or $null -eq $familyGuidRow[0].family_guid -or $familyGuidRow[0].family_guid -is [System.DBNull]) {
                                Stop-Function -Message "Couldn't read the family GUID of database $($db.Name) on $instance" -Target $instance -Continue
                            }
                            $familyGuid = [guid]$familyGuidRow[0].family_guid

                            $wantedObjectId = @($objectCollection.ID)

                            if ($wantedObjectId.Count -ge 1) {
                                try {
                                    foreach ($imageValue in (Get-EncryptedObjectImageValue -Database $db -ObjectId $wantedObjectId)) {
                                        if (-not $imageValueMap.ContainsKey($imageValue.ObjectId)) {
                                            $imageValueMap[$imageValue.ObjectId] = @()
                                        }
                                        $imageValueMap[$imageValue.ObjectId] += $imageValue
                                    }
                                } catch {
                                    Stop-Function -Message "Couldn't read the encrypted definitions from the data pages of database $($db.Name) on $instance" -ErrorRecord $_ -Target $instance -Continue
                                }
                            }
                        }

                        # Loop through all the objects
                        foreach ($object in $objectCollection) {

                            $result = $null

                            # Both methods below select this object's rows by id, taken from SMO's own ID
                            # property rather than looked up by schema and name.
                            $decryptObjectId = [int]$object.ID

                            # Without a dedicated admin connection the ciphertext that was collected for this object
                            # is combined with the keystream that its own metadata produces.
                            if ($DataPages) {
                                # Asked for a key it does not hold, a hashtable answers with null, and wrapping
                                # null in @() gives an array of one null rather than an empty one. That reads as
                                # a chunk with no ciphertext, so an object the reader deliberately skipped - a
                                # CLR module, say - would be reported as one whose body could not be recovered.
                                $chunkCollection = @()
                                if ($imageValueMap.ContainsKey($decryptObjectId)) {
                                    $chunkCollection = @($imageValueMap[$decryptObjectId])
                                }

                                # A chunk without ciphertext means an off row body that could not be reassembled.
                                # Decrypting the rest would return a definition built from a fragment, so this
                                # object is reported and skipped while the others carry on.
                                $unresolvedChunk = @($chunkCollection | Where-Object { $null -eq $PSItem.Cipher })

                                if ($unresolvedChunk.Count -gt 0) {
                                    Write-Message -Level Warning -Message "Couldn't recover the off row body of $($object.Schema).$($object.Name) in database $($db.Name) on $instance, so it is not returned."
                                } elseif ($chunkCollection.Count -ge 1) {
                                    $chunkParams = @{
                                        FamilyGuid = $familyGuid
                                        ObjectId   = $decryptObjectId
                                        Chunk      = $chunkCollection
                                    }

                                    # Anything wrong with this object's ciphertext fails this object and lets the
                                    # rest of the run stand, rather than ending the command part way through.
                                    try {
                                        $result = ConvertFrom-EncryptedObjectChunk @chunkParams
                                    } catch {
                                        Stop-Function -Message "Couldn't decrypt $($object.Schema).$($object.Name) in database $($db.Name) on $instance" -ErrorRecord $_ -Target $instance -Continue
                                    }
                                }
                            }

                            # Only the DAC can read imageval directly, so none of this runs for the method that reads
                            # the data pages, and the block below is skipped with it.
                            $secret = $null
                            if (-not $DataPages) {
                                # Setup the query to get the secret. Select by object id rather than by name. Exclude null values in sys.sysobjvalues for triggers.
                            $querySecret = @"
SELECT imageval AS Value FROM sys.sysobjvalues WHERE objid = $decryptObjectId AND imageval IS NOT NULL
"@

                                # Get the result of the secret query
                                try {
                                    $secret = $server.Databases[$db.Name].Query($querySecret)
                                } catch {
                                    Stop-Function -Message "Couldn't retrieve secret from $instance" -ErrorRecord $_ -Target $instance -Continue
                                }
                            }

                            # Check if at least a value came back
                            if ($secret) {

                                # A schema, object or parent name is allowed to contain a closing bracket, which
                                # would end the identifier early and leave the rest of the name standing as
                                # statement text. Doubling it keeps the whole name inside the brackets.
                                $bracketedSchema = $object.Schema -replace "\]", "]]"
                                $bracketedName = $object.Name -replace "\]", "]]"

                                # Cleared per object, because it survives the loop otherwise and an object type
                                # that matched no branch below would be altered with the previous object's
                                # statement instead of reaching the check that says the known plain is missing.
                                $queryKnownPlain = $null

                                # Setup a known plain command and get the binary version of it
                                switch ($object.ObjectType) {

                                    'StoredProcedure' {
                                        $queryKnownPlain = (" " * $secret.Value.Length) + "ALTER PROCEDURE [$bracketedSchema].[$bracketedName] WITH ENCRYPTION AS RETURN 0;"
                                    }
                                    'UserDefinedFunction' {

                                        switch ($object.SubType) {
                                            'Inline' {
                                                $queryKnownPlain = (" " * $secret.value.length) + "ALTER FUNCTION [$bracketedSchema].[$bracketedName]() RETURNS TABLE WITH ENCRYPTION AS RETURN SELECT 0 i;"
                                            }
                                            'Scalar' {
                                                $queryKnownPlain = (" " * $secret.value.length) + "ALTER FUNCTION [$bracketedSchema].[$bracketedName]() RETURNS INT WITH ENCRYPTION AS BEGIN RETURN 0 END;"
                                            }
                                            'Table' {
                                                $queryKnownPlain = (" " * $secret.value.length) + "ALTER FUNCTION [$bracketedSchema].[$bracketedName]() RETURNS @r TABLE(i INT) WITH ENCRYPTION AS BEGIN RETURN END;"
                                            }
                                        }
                                    }
                                    'View' {
                                        $queryKnownPlain = (" " * $secret.Value.Length) + "ALTER VIEW [$bracketedSchema].[$bracketedName] WITH ENCRYPTION AS SELECT NULL AS [Value];"
                                    }
                                    'Trigger' {
                                        # A trigger names its parent as well as itself, so the parent gets the same
                                        # treatment: taken from the object rather than left to however the SMO
                                        # object renders as a string, and bracketed like every other identifier.
                                        $bracketedParentSchema = $object.Parent.Schema -replace "\]", "]]"
                                        $bracketedParentName = $object.Parent.Name -replace "\]", "]]"

                                        # The quotes around the message are single, not doubled. This statement is
                                        # written as it should reach SQL Server, and the doubling that puts it
                                        # inside the EXEC literal happens in one place below, so that a quote in
                                        # an object name is escaped by the same pass rather than being missed.
                                    $statementTrigger = @"
ALTER TRIGGER [$bracketedSchema].[$bracketedName] ON [$bracketedParentSchema].[$bracketedParentName] WITH ENCRYPTION AFTER INSERT AS RAISERROR ('Invoke-DbaDbDecryptObject', 16, 10);
"@
                                        $queryKnownPlain = (" " * $secret.Value.Length) + $statementTrigger
                                    }
                                }

                                # Convert the known plain into binary
                                if ($queryKnownPlain) {
                                    try {
                                        $knownPlain = $encoding.GetBytes(($queryKnownPlain))
                                    } catch {
                                        Stop-Function -Message "Couldn't convert the known plain to binary" -ErrorRecord $_ -Target $instance -Continue
                                    }
                                } else {
                                    Stop-Function -Message "Something went wrong setting up the known plain" -Target $instance -Continue
                                }

                                # Setup the query to change the object in SQL Server and roll it back getting the encrypted version
                                # Exclude null values in sys.sysobjvalues for triggers and select the object by id.
                                #
                                # The whole statement goes inside the string literal that EXEC runs, so every
                                # single quote in it has to be doubled or the literal ends early and whatever
                                # follows runs as a further statement in the same batch - as sysadmin, over the
                                # dedicated admin connection. An object name may contain a quote, so this is the
                                # escape that has to be in place, not only the doubling of the quotes written
                                # above. Character 39 is the quote itself, named so that this line does not
                                # need one of its own.
                                $quoteCharacter = [string][char]39
                                $queryKnownPlainLiteral = $queryKnownPlain -replace $quoteCharacter, ($quoteCharacter * 2)

                            $queryKnownSecret = @"
BEGIN TRANSACTION;
    EXEC ($quoteCharacter$queryKnownPlainLiteral$quoteCharacter);
    SELECT imageval AS Value
    FROM sys.sysobjvalues
    WHERE objid = $decryptObjectId
    AND imageval IS NOT NULL;
ROLLBACK;
"@

                                # Get the result for the known encrypted
                                try {
                                    $knownSecret = $server.Databases[$db.Name].Query($queryKnownSecret)
                                } catch {
                                    Stop-Function -Message "Couldn't retrieve known secret from $instance" -ErrorRecord $_ -Target $instance -Continue
                                }

                                # Get the result
                                $result = Invoke-DecryptData -Secret $secret.value -KnownPlain $knownPlain -KnownSecret $knownSecret.value
                            }

                            # Both methods arrive at the decrypted script here, so exporting it and returning it is
                            # shared between them.
                            if ($null -ne $result) {
                                # Check if the results need to be exported
                                $filePath = $null
                                if ($ExportDestination) {
                                    # make up the file name
                                    $filename = "$($object.Schema).$($object.Name).sql"

                                    # Check the export destination
                                    if ($ExportDestination.EndsWith("\")) {
                                        $destinationFolder = "$ExportDestination$instance\$($db.Name)\$($object.ObjectType)\"
                                    } else {
                                        $destinationFolder = "$ExportDestination\$instance\$($db.Name)\$($object.ObjectType)\"
                                    }

                                    # Check if the destination folder exists
                                    if (-not (Test-Path $destinationFolder)) {
                                        try {
                                            # Create the new destination
                                            # Plain -Force, matching the call in begin. It must not be written as
                                            # -Force:$Force: this command has no Force parameter, so that binds
                                            # $null and silently turns the switch off, and under StrictMode it
                                            # throws instead.
                                            New-Item -Path $destinationFolder -ItemType Directory -Force | Out-Null
                                        } catch {
                                            Stop-Function -Message "Couldn't create destination folder $destinationFolder" -ErrorRecord $_ -Target $instance -Continue
                                        }
                                    }

                                    # Combine the destination folder and the file name to get the path
                                    $filePath = $destinationFolder + $filename

                                    # Export the result
                                    try {
                                        $result | Out-File -FilePath $filePath -Force
                                    } catch {
                                        Stop-Function -Message "Couldn't export the results of $($object.Name) to $filePath" -ErrorRecord $_ -Target $instance -Continue
                                    }

                                }

                                # Add the results to the custom object
                                [PSCustomObject]@{
                                    ComputerName = $instance.ComputerName
                                    InstanceName = $server.ServiceName
                                    SqlInstance  = $server.DomainInstanceName
                                    Database     = $db.Name
                                    Type         = $object.ObjectType
                                    Schema       = $object.Schema
                                    Name         = $object.Name
                                    FullName     = "$($object.Schema).$($object.Name)"
                                    Script       = $result
                                    OutputFile   = $filePath
                                }
                            }
                        }
                    }
                } finally {
                    Restore-DatabaseContext -Server $server -Database $callerDatabase
                }
            } finally {
                # The init fields belong to the connection, not to this command, so they go back however
                # the run ended. Its own try/catch, because a failure here must not replace whatever error
                # sent us to this finally in the first place.
                if ($null -ne $savedInitFieldsProcedure) {
                    try {
                        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.StoredProcedure], $savedInitFieldsProcedure)
                        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.View], $savedInitFieldsView)
                        $server.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.UserDefinedFunction], $savedInitFieldsFunction)
                    } catch {
                        Write-Message -Level Debug -Message "Restoring the default init fields failed with $_"
                    }
                }

                if ($dacOpened) {
                    $null = $server | Disconnect-DbaInstance -WhatIf:$false
                }
            }
        }
    }
    end {
        Write-Message -Message "Finished decrypting data" -Level Verbose
    }
}
