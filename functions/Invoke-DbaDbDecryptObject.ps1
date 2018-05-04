function Invoke-DbaDbDecryptObject {
    <#
    .SYNOPSIS
        Invoke-DbaDbDecryptObject returns the decrypted version of an object

    .DESCRIPTION
        When a procedure or a function is created with encryption and you lost the code you're in trouble.
        You cannot alter the object or view the definition.
        With this command you can search for the object and decrypt the it.

        The comand will output the results to the console.
        There is an option to export all the results to a folder creating .sql files

        Make sure the instance allowed dedicated administrator connections (DAC).
        The binary versions of the objects can only be retrieved using a DAC connection.
        You can check the DAC connection with:
        'Get-DbaSpConfigure -SqlInstance [yourinstance] -ConfigName RemoteDacConnectionsEnabled'
        It should say 1 in the ConfiguredValue

        To change the configurations you can use the Set-DbaSpConfigure command:
        'Set-DbaSpConfigure -SqlInstance [yourinstance] -ConfigName RemoteDacConnectionsEnabled -Value 1'
        In some cases you may ned to reboot the instance

    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the SQL Server to connect to

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

        $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

        Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
        To connect as a different Windows user, run PowerShell as that user.

    .PARAMETER Database
        Database to look through for the object.

    .PARAMETER ObjectName
        The name of the object to search for in the database.

    .PARAMETER EncodingType
        The encoding that's used to decrypt and encrypt values

    .PARAMETER ExportDestination
        Used for exporting the results to.
        The destiation will use the instance name, database name and object type i.e.: C:\temp\decrypt\SQLDB1\DB1\StoredProcedure

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Author: Sander Stad (@sqlstad, sqlstad.nl)
        Tags: Log Shipping, Configuration

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbDecryptObject

    .EXAMPLE
    Invoke-DbaDbDecryptObject -SqlInstance SQLDB1 -Database DB1 -ObjectName Function1

    Decrypt objct "Function1" in DB1 of instance SQLDB1 and output the data to the user

    .EXAMPLE
    Invoke-DbaDbDecryptObject -SqlInstance SQLDB1 -Database DB1 -ObjectName Function1 -Force -ExportDestination C:\temp\decrypt

    Decrypt object "Function1" in DB1 of instance SQLDB1 and output the data to the folder "C:\temp\decrypt"

    .EXAMPLE
    Invoke-DbaDbDecryptObject -SqlInstance SQLDB1 -Database DB1 -ObjectName Function1, Function2

    Decrypt objects "Function1" and "Function2" and output the data to the user

    .EXAMPLE
    "SQLDB1" | Invoke-DbaDbDecryptObject -Database DB1 -ObjectName Function1, Function2

    Decrypt objects "Function1" and "Function2" and output the data to the user using a pipeline for the instance

#>
   [CmdletBinding()]
    param(
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory = $true)]
        [object[]]$Database,
        [parameter(Mandatory = $true)]
        [string[]]$ObjectName,
        [ValidateSet('ASCII', 'UTF8')]
        [string]$EncodingType = 'ASCII',
        [string]$ExportDestination,
        [switch]$EnableException
    )

    begin {

        function Invoke-DecryptData() {
            param(
                [parameter(Mandatory = $true)]
                [byte[]]$Secret,
                [parameter(Mandatory = $true)]
                [byte[]]$KnownPlain,
                [parameter(Mandatory = $true)]
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
        }
        elseif ($EncodingType -eq 'UTF8') {
            $encoding = [System.Text.Encoding]::UTF8
        }

        # Check the export parameter
        if ($ExportDestination -and -not (Test-Path $ExportDestination)) {
            try {
                # Create the new destination
                New-Item -Path $ExportDestination -ItemType Directory -Force | Out-Null
            }
            catch {
                Stop-Function -Message "Couldn't create destination folder $ExportDestination" -ErrorRecord $_ -Target $instance -Continue
            }
        }

    }

    process {

        if (Test-FunctionInterrupt) { return }

        # Loop through all the instances
        foreach ($instance in $SqlInstance) {

            # Check the configuration of the intance to see if the DAC is enabled
            $config = Get-DbaSpConfigure -SqlInstance $instance -ConfigName RemoteDacConnectionsEnabled
            if ($config.ConfiguredValue -ne 1) {
                Stop-Function -Message "DAC is not enabled for instance $instance.`nPlease use 'Set-DbaSpConfigure -SqlInstance $instance -ConfigName RemoteDacConnectionsEnabled -Value 1' to configure the instance to allow DAC connections" -Target $instance -Continue
            }

            # Try to connect to instance
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = New-Object Microsoft.SqlServer.Management.Smo.Server "ADMIN:$instance"
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Get all the databases that compare to the database parameter
            $databaseCollection = $server.Databases | Where-Object {$_.Name -in $Database}

            # Loop through each of databases
            foreach ($db in $databaseCollection) {

                # Get all the objects
                $storedProcedures = @($db.StoredProcedures | Where-Object {$_.Name -in $ObjectName -and $_.IsEncrypted -eq $true} | Select-Object Name, Schema, @{N = "ObjectType"; E = {'StoredProcedure'}}, @{N = "SubType"; E = {''}})
                $functions = @($db.UserDefinedFunctions | Where-Object {$_.Name -in $ObjectName -and $_.IsEncrypted -eq $true} | Select-Object Name, Schema, @{N = "ObjectType"; E = {"UserDefinedFunction"}}, @{N = "SubType"; E = {$_.FunctionType.ToString().Trim()}})
                $views = @($db.Views | Where-Object {$_.Name -in $ObjectName -and $_.IsEncrypted -eq $true} | Select-Object Name, Schema, @{N = "ObjectType"; E = {'View'}}, @{N = "SubType"; E = {''}})

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

                # Loop through all the objects
                foreach ($object in $objectCollection) {

                    # Setup the query to get the secret
                    $querySecret = "SELECT imageval AS Value FROM sys.sysobjvalues WHERE objid = OBJECT_ID('$($object.Name)')"

                    # Get the result of the secret query
                    try {
                        $secret = $server.Databases[$db.Name].Query($querySecret)
                    }
                    catch {
                        Stop-Function -Message "Couldn't retrieve secret from $instance" -ErrorRecord $_ -Target $instance -Continue
                    }

                    # Check if at least a value came back
                    if ($secret) {

                        # Setup a known plain command and get the binary version of it
                        switch ($object.ObjectType) {

                            'StoredProcedure' {
                                $queryKnownPlain = (" " * $secret.Value.Length) + "ALTER PROCEDURE $($object.Schema).$($object.Name) WITH ENCRYPTION AS RETURN 0;"
                            }
                            'UserDefinedFunction' {

                                switch ($object.SubType) {
                                    'Inline' {
                                        $queryKnownPlain = (" " * $secret.value.length) + "ALTER FUNCTION $($object.Schema).$($object.Name)() RETURNS TABLE WITH ENCRYPTION AS BEGIN RETURN SELECT 0 i END;"
                                    }
                                    'Scalar' {
                                        $queryKnownPlain = (" " * $secret.value.length) + "ALTER FUNCTION $($object.Schema).$($object.Name)() RETURNS INT WITH ENCRYPTION AS BEGIN RETURN 0 END;"
                                    }
                                    'Table' {
                                        $queryKnownPlain = (" " * $secret.value.length) + "ALTER FUNCTION $($object.Schema).$($object.Name)() RETURNS @r TABLE(i INT) WITH ENCRYPTION AS BEGIN RETURN END;"
                                    }
                                }
                            }
                            'View' {
                                $queryKnownPlain = (" " * $secret.Value.Length) + "ALTER VIEW $($object.Schema).$($object.Name) WITH ENCRYPTION AS SELECT NULL AS [Value];"
                            }
                        }

                        # Convert the known plain into binary
                        if ($queryKnownPlain) {
                            try {
                                $knownPlain = $encoding.GetBytes(($queryKnownPlain))
                            }
                            catch {
                                Stop-Function -Message "Couldn't convert the known plain to binary" -ErrorRecord $_ -Target $instance -Continue
                            }
                        }
                        else {
                            Stop-Function -Message "Something went wrong setting up the known plain" -ErrorRecord $_ -Target $instance -Continue
                        }

                        # Setup the query to change the object in SQL Server and roll it back getting the encrypted version
                        $queryKnownSecret = "
                            BEGIN TRAN;
                                EXEC ('$queryKnownPlain');
                                SELECT imageval AS Value
                                FROM sys.sysobjvalues
                                WHERE objid = OBJECT_ID('$($object.Name)');
                            ROLLBACK;
                        "

                        # Get the result for the known encrypted
                        try {
                            $knownSecret = $server.Databases[$db.Name].Query($queryKnownSecret)
                        }
                        catch {
                            Stop-Function -Message "Couldn't retrieve known secret from $instance" -ErrorRecord $_ -Target $instance -Continue
                        }

                        # Get the result
                        $result = Invoke-DecryptData -Secret $secret.value -KnownPlain $knownPlain -KnownSecret $knownSecret.value

                        # Check if the results need to be exported
                        if ($ExportDestination) {
                            # make up the file name
                            $filename = "$($object.Schema).$($object.Name).sql"

                            # Check the export destination
                            if ($ExportDestination.EndsWith("\")) {
                                $destinationFolder = "$ExportDestination$instance\$($db.Name)\$($object.ObjectType)\"
                            }
                            else {
                                $destinationFolder = "$ExportDestination\$instance\$($db.Name)\$($object.ObjectType)\"
                            }

                            # Check if the destination folder exists
                            if (-not (Test-Path $destinationFolder)) {
                                try {
                                    # Create the new destination
                                    New-Item -Path $destinationFolder -ItemType Directory -Force:$Force | Out-Null
                                }
                                catch {
                                    Stop-Function -Message "Couldn't create destination folder $destinationFolder" -ErrorRecord $_ -Target $instance -Continue
                                }
                            }

                            # Combine the destination folder and the file name to get the path
                            $filePath = $destinationFolder + $filename

                            # Export the result
                            try {
                                $result | Out-File -FilePath $filePath -Force
                            }
                            catch {
                                Stop-Function -Message "Couldn't export the results of $($object.Name) to $filePath" -ErrorRecord $_ -Target $instance -Continue
                            }

                        }

                        # Add the results to the custom object
                        [PSCustomObject]@{
                                ComputerName    = $server.NetName
                                InstanceName    = $server.ServiceName
                                SqlInstance     = $server.DomainInstanceName
                                Database        = $db.Name
                                Type            = $object.ObjectType
                                Schema          = $object.Schema
                                Name            = $object.Name
                                FullName        = "$($object.Schema).$($object.Name)"
                                Script          = $result
                            }

                    } # end if secret

                } # end for each object

            } # end for each database

        } # end for each instance

    } # process

    end {
        if (Test-FunctionInterrupt) { return }

        Write-Message -Message "Finished decrypting data" -Level Verbose
    }
}