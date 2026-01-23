function Get-DecryptedObject {
    <#
            .SYNOPSIS
                Internal function.

                This function is heavily based on Antti Rantasaari's script at http://goo.gl/wpqSib
                Antti Rantasaari 2014, NetSPI
                License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause
    #>
    param (
        [Parameter(Mandatory)]
        [Microsoft.SqlServer.Management.Smo.Server]$SqlInstance,
        [Parameter(Mandatory)]
        [ValidateSet("LinkedServer", "Credential")]
        [string]$Type,
        [switch]$EnableException
    )

    $server = $SqlInstance
    $sourceName = $server.Name

    # Query Service Master Key from the database - remove padding from the key
    # key_id 102 eq service master key, thumbprint 3 means encrypted with machinekey
    Write-Message -Level Verbose -Message "Querying service master key"
    try {
        $sql = "SELECT SUBSTRING(crypt_property,9,LEN(crypt_property)-8) AS smk FROM sys.key_encryptions WHERE key_id=102 AND thumbprint=0x0300000001"
        $smkBytes = $server.Query($sql).smk
        if (-not $smkBytes) {
            $sql = "SELECT SUBSTRING(crypt_property,9,LEN(crypt_property)-8) AS smk FROM sys.key_encryptions WHERE key_id=102 AND thumbprint=0x03"
            $smkBytes = $server.Query($sql).smk
        }
    } catch {
        Stop-Function -Message "Can't execute query on $sourceName" -Target $server -ErrorRecord $_
        return
    }

    $fullComputerName = Resolve-DbaComputerName -ComputerName $server -Credential $Credential
    $serviceInstanceId = $server.ServiceInstanceId

    Write-Message -Level Verbose -Message "Decrypt the service master key"
    try {
        $serviceKey = Invoke-Command2 -Raw -Credential $Credential -ComputerName $fullComputerName -ArgumentList $serviceInstanceId, $smkBytes {
            $serviceInstanceId = $args[0]
            $smkBytes = $args[1]
            Add-Type -AssemblyName System.Security
            Add-Type -AssemblyName System.Core
            $entropy = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$serviceInstanceId\Security\").Entropy
            $serviceKey = [System.Security.Cryptography.ProtectedData]::Unprotect($smkBytes, $entropy, 'LocalMachine')
            return $serviceKey
        }
    } catch {
        Stop-Function -Message "Can't unprotect registry data on $sourceName. Do you have administrative access to the Windows registry on $($sourceName)? Otherwise, we're out of ideas." -Target $sourceName
        return
    }

    # Choose the encryption algorithm based on the SMK length - 3DES for 2008, AES for 2012
    # Choose IV length based on the algorithm
    Write-Message -Level Verbose -Message "Choose the encryption algorithm based on the SMK length - 3DES for 2008, AES for 2012"

    if (($serviceKey.Length -ne 16) -and ($serviceKey.Length -ne 32)) {
        Write-Message -Level Verbose -Message "ServiceKey found: $serviceKey.Length"
        Stop-Function -Message "Unknown key size. Do you have administrative access to the Windows registry on $($sourceName)? Otherwise, we're out of ideas." -Target $sourceName
        return
    }

    if ($serviceKey.Length -eq 16) {
        $decryptor = New-Object System.Security.Cryptography.TripleDESCryptoServiceProvider
        $ivlen = 8
    } elseif ($serviceKey.Length -eq 32) {
        $decryptor = New-Object System.Security.Cryptography.AESCryptoServiceProvider
        $ivlen = 16
    }

    <# NOTE: This query is accessing syslnklgns table. Can only be done via the DAC connection #>

    $sql = switch ($Type) {
        "LinkedServer" {
            "SELECT sysservers.srvname,
                syslnklgns.name,
                SUBSTRING(syslnklgns.pwdhash,5,$ivlen) iv,
                SUBSTRING(syslnklgns.pwdhash,$($ivlen + 5),
                LEN(syslnklgns.pwdhash)-$($ivlen + 4)) pass
            FROM master.sys.syslnklgns
                INNER JOIN master.sys.sysservers
                ON syslnklgns.srvid=sysservers.srvid
            WHERE LEN(pwdhash) > 0"
        }
        "Credential" {
            #"SELECT name,QUOTENAME(name) quotename,credential_identity,SUBSTRING(imageval,5,$ivlen) iv, SUBSTRING(imageval,$($ivlen + 5),LEN(imageval)-$($ivlen + 4)) pass FROM sys.credentials cred INNER JOIN sys.sysobjvalues obj ON cred.credential_id = obj.objid WHERE valclass=28 AND valnum=2"
            "SELECT cred.name,QUOTENAME(cred.name) quotename,credential_identity,SUBSTRING(imageval,5,$ivlen) iv, SUBSTRING(imageval,$($ivlen + 5),LEN(imageval)-$($ivlen + 4)) pass,target_type AS 'mappedClassType', cp.name AS 'ProviderName' FROM sys.credentials cred INNER JOIN sys.sysobjvalues obj ON cred.credential_id = obj.objid LEFT OUTER JOIN sys.cryptographic_providers cp ON cred.target_id = cp.provider_id WHERE valclass=28 AND valnum=2"
        }
    }

    Write-Message -Level Debug -Message $sql

    <#
        Query link server password information from the Db.
        Remove header from pwdhash, extract IV (as iv) and ciphertext (as pass)
        Ignore links with blank credentials (integrated auth ?)
    #>

    Write-Message -Level Verbose -Message "Query password information from the Db."

    if ($server.Name -like 'ADMIN:*') {
        Write-Message -Level Verbose -Message "We already have a dac, so we use it."
        $results = $server.Query($sql)
    } else {
        $instance = $server.InstanceName
        if (-not $server.IsClustered) {
            $connString = "Server=ADMIN:127.0.0.1\$instance;Trusted_Connection=True;Pooling=false"
        } else {
            $dacEnabled = $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue

            if ($dacEnabled -eq $false) {
                If ($Pscmdlet.ShouldProcess($server.Name, "Enabling remote DAC on clustered instance.")) {
                    try {
                        Write-Message -Level Verbose -Message "DAC must be enabled for clusters, even when accessed from active node. Enabling."
                        $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $true
                        $server.Configuration.Alter()
                    } catch {
                        Stop-Function -Message "Failure enabling remote DAC on clustered instance $sourceName" -Target $sourceName -ErrorRecord $_
                        return
                    }
                }
            }

            $connString = "Server=ADMIN:$sourceName;Trusted_Connection=True;Pooling=false;"
        }

        try {
            $results = Invoke-Command2 -Raw -Credential $Credential -ComputerName $fullComputerName -ArgumentList $connString, $sql {
                try {
                    $connString = $args[0]
                    $sql = $args[1]
                    $conn = New-Object System.Data.SqlClient.SQLConnection($connString)
                    $cmd = New-Object System.Data.SqlClient.SqlCommand($sql, $conn)
                    $dt = New-Object System.Data.DataTable
                    $conn.open()
                    $dt.Load($cmd.ExecuteReader())
                    $conn.Close()
                    $conn.Dispose()
                    return $dt
                } catch {
                    $exception = $_
                    try {
                        $conn.Close()
                        $conn.Dispose()
                    } catch {
                        $null = 1
                    }
                    throw $exception
                }
            }
        } catch {
            Stop-Function -Message "Can't establish local DAC connection on $sourceName." -Target $server -ErrorRecord $_
        }

        if ($server.IsClustered -and $dacEnabled -eq $false) {
            If ($Pscmdlet.ShouldProcess($server.Name, "Disabling remote DAC on clustered instance.")) {
                try {
                    Write-Message -Level Verbose -Message "Setting remote DAC config back to 0."
                    $server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $false
                    $server.Configuration.Alter()
                } catch {
                    Stop-Function -Message "Failure disabling remote DAC on clustered instance $sourceName" -Target $server -ErrorRecord $_
                }
            }
        }
    }

    Write-Message -Level Verbose -Message "Go through each row in results"
    foreach ($result in $results) {
        # decrypt the password using the service master key and the extracted IV
        $decryptor.Padding = "None"
        $decrypt = $decryptor.Createdecryptor($serviceKey, $result.iv)
        $stream = New-Object System.IO.MemoryStream ( , $result.pass)
        $crypto = New-Object System.Security.Cryptography.CryptoStream $stream, $decrypt, "Write"

        $crypto.Write($result.pass, 0, $result.pass.Length)
        [byte[]]$decrypted = $stream.ToArray()

        # convert decrypted password to unicode
        $encode = New-Object System.Text.UnicodeEncoding

        # Print results - removing the weird padding (8 bytes in the front, some bytes at the end)...
        # Might cause problems but so far seems to work.. may be dependant on SQL server version...
        # If problems arise remove the next three lines..
        $i = 8; foreach ($b in $decrypted) { if ($decrypted[$i] -ne 0 -and $decrypted[$i + 1] -ne 0 -or $i -eq $decrypted.Length) { $i -= 1; break; }; $i += 1; }
        $decrypted = $decrypted[8 .. $i]

        if ($Type -eq "LinkedServer") {
            $name = $result.srvname
            $quotename = $null
            $identity = $result.Name
        } else {
            $name = $result.name
            $quotename = $result.quotename
            $identity = $result.credential_identity
            $mappedClassType = $result.mappedClassType
            $ProviderName = $result.ProviderName
        }
        [pscustomobject]@{
            Name            = $name
            Quotename       = $quotename
            Identity        = $identity
            Password        = $encode.GetString($decrypted)
            MappedClassType = $mappedClassType
            ProviderName    = $ProviderName
        }
    }
}
