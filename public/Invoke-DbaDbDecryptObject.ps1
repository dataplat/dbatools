function Invoke-DbaDbDecryptObject {
    <#
    .SYNOPSIS
        Decrypts encrypted stored procedures, functions, views, and triggers using Dedicated Admin Connection (DAC)

    .DESCRIPTION
        Recovers the original source code from encrypted database objects when the original scripts have been lost or are unavailable. This command uses the Dedicated Admin Connection (DAC) to access binary data from sys.sysobjvalues and performs XOR decryption to retrieve the original T-SQL code.

        This is particularly useful in disaster recovery scenarios where you need to recreate objects but only have access to the encrypted versions in the database. The function can decrypt stored procedures, user-defined functions (scalar, inline, table-valued), views, and triggers.

        The command outputs results to the console by default, with an option to export all decrypted objects to organized .sql files in a folder structure.

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

    .PARAMETER ExportDestination
        Specifies the folder path where decrypted T-SQL scripts will be saved as individual .sql files.
        When specified, creates an organized folder structure by instance, database, and object type (e.g., C:\temp\decrypt\SQLDB1\DB1\StoredProcedure). When omitted, results are displayed in the console only.

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

        # Create array list to hold the results
        $objectCollection = New-Object System.Collections.ArrayList

        # Set the encoding
        if ($EncodingType -eq 'ASCII') {
            $encoding = [System.Text.Encoding]::ASCII
        } elseif ($EncodingType -eq 'UTF8') {
            $encoding = [System.Text.Encoding]::UTF8
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
            $config = Get-DbaSpConfigure -SqlInstance $instance -SqlCredential $SqlCredential -ConfigName RemoteDacConnectionsEnabled
            if ($config.ConfiguredValue -ne 1) {
                Stop-Function -Message "DAC is not enabled for instance $instance.`nPlease use 'Set-DbaSpConfigure -SqlInstance $instance -SqlCredential <credential> -ConfigName RemoteDacConnectionsEnabled -Value 1' to configure the instance to allow DAC connections" -Target $instance -Continue
            }

            # Try to connect to instance
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -DedicatedAdminConnection
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Get all the databases that compare to the database parameter
            $databaseCollection = $server.Databases | Where-Object { $_.Name -in $Database }

            # Use the table's schema for the trigger's schema. The schema name is not returned as a property for triggers (except in the URN).
            $triggerSchema = @{label = "Schema"; expression = { $_.Parent.Schema } }

            # Loop through each of databases
            foreach ($db in $databaseCollection) {

                $triggers = @($db.Tables | Where-Object { $_.IsSystemObject -eq $false } | ForEach-Object { $_.Triggers })

                # Get the objects
                if ($ObjectName) {
                    $storedProcedures = @($db.StoredProcedures | Where-Object { $_.Name -in $ObjectName -and $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { 'StoredProcedure' } }, @{N = "SubType"; E = { '' } })
                    $functions = @($db.UserDefinedFunctions | Where-Object { $_.Name -in $ObjectName -and $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { "UserDefinedFunction" } }, @{N = "SubType"; E = { $_.FunctionType.ToString().Trim() } })
                    $views = @($db.Views | Where-Object { $_.Name -in $ObjectName -and $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { 'View' } }, @{N = "SubType"; E = { '' } })
                    $triggers = @($triggers | Where-Object { $_.Name -in $ObjectName -and $_.IsEncrypted -eq $true } | Select-Object Name, $triggerSchema, Parent, @{N = "ObjectType"; E = { 'Trigger' } }, @{N = "SubType"; E = { '' } })
                } else {
                    # Get all encrypted objects
                    $storedProcedures = @($db.StoredProcedures | Where-Object { $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { 'StoredProcedure' } }, @{N = "SubType"; E = { '' } })
                    $functions = @($db.UserDefinedFunctions | Where-Object { $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { "UserDefinedFunction" } }, @{N = "SubType"; E = { $_.FunctionType.ToString().Trim() } })
                    $views = @($db.Views | Where-Object { $_.IsEncrypted -eq $true } | Select-Object Name, Schema, @{N = "ObjectType"; E = { 'View' } }, @{N = "SubType"; E = { '' } })
                    $triggers = @($triggers | Where-Object { $_.IsEncrypted -eq $true } | Select-Object Name, $triggerSchema, Parent, @{N = "ObjectType"; E = { 'Trigger' } }, @{N = "SubType"; E = { '' } })
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
                # Loop through all the objects
                foreach ($object in $objectCollection) {

                    # Setup the query to get the secret. Include the schema name to find the object. Exclude null values in sys.sysobjvalues for triggers.
                    $querySecret = "SELECT imageval AS Value FROM sys.sysobjvalues WHERE objid = OBJECT_ID('$($object.Schema).$($object.Name)') AND imageval IS NOT NULL"

                    # Get the result of the secret query
                    try {
                        $secret = $server.Databases[$db.Name].Query($querySecret)
                    } catch {
                        Stop-Function -Message "Couldn't retrieve secret from $instance" -ErrorRecord $_ -Target $instance -Continue
                    }

                    # Check if at least a value came back
                    if ($secret) {

                        # Setup a known plain command and get the binary version of it
                        switch ($object.ObjectType) {

                            'StoredProcedure' {
                                $queryKnownPlain = (" " * $secret.Value.Length) + "ALTER PROCEDURE [$($object.Schema)].[$($object.Name)] WITH ENCRYPTION AS RETURN 0;"
                            }
                            'UserDefinedFunction' {

                                switch ($object.SubType) {
                                    'Inline' {
                                        $queryKnownPlain = (" " * $secret.value.length) + "ALTER FUNCTION [$($object.Schema)].[$($object.Name)]() RETURNS TABLE WITH ENCRYPTION AS RETURN SELECT 0 i;"
                                    }
                                    'Scalar' {
                                        $queryKnownPlain = (" " * $secret.value.length) + "ALTER FUNCTION [$($object.Schema)].[$($object.Name)]() RETURNS INT WITH ENCRYPTION AS BEGIN RETURN 0 END;"
                                    }
                                    'Table' {
                                        $queryKnownPlain = (" " * $secret.value.length) + "ALTER FUNCTION [$($object.Schema)].[$($object.Name)]() RETURNS @r TABLE(i INT) WITH ENCRYPTION AS BEGIN RETURN END;"
                                    }
                                }
                            }
                            'View' {
                                $queryKnownPlain = (" " * $secret.Value.Length) + "ALTER VIEW [$($object.Schema)].[$($object.Name)] WITH ENCRYPTION AS SELECT NULL AS [Value];"
                            }
                            'Trigger' {
                                $queryKnownPlain = (" " * $secret.Value.Length) + "ALTER TRIGGER [$($object.Schema)].[$($object.Name)] ON $($object.Parent) WITH ENCRYPTION AFTER INSERT AS RAISERROR (''Invoke-DbaDbDecryptObject'', 16, 10);"
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
                        # Exclude null values in sys.sysobjvalues for triggers and include the full schema and object name.
                        $queryKnownSecret = "
                            BEGIN TRANSACTION;
                                EXEC ('$queryKnownPlain');
                                SELECT imageval AS Value
                                FROM sys.sysobjvalues
                                WHERE objid = OBJECT_ID('$($object.Schema).$($object.Name)')
                                AND imageval IS NOT NULL;
                            ROLLBACK;
                        "

                        # Get the result for the known encrypted
                        try {
                            $knownSecret = $server.Databases[$db.Name].Query($queryKnownSecret)
                        } catch {
                            Stop-Function -Message "Couldn't retrieve known secret from $instance" -ErrorRecord $_ -Target $instance -Continue
                        }

                        # Get the result
                        $result = Invoke-DecryptData -Secret $secret.value -KnownPlain $knownPlain -KnownSecret $knownSecret.value

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
                                    New-Item -Path $destinationFolder -ItemType Directory -Force:$Force | Out-Null
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
            $null = $server | Disconnect-DbaInstance
        }
    }
    end {
        Write-Message -Message "Finished decrypting data" -Level Verbose
    }
}