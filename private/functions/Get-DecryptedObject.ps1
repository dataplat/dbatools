function Get-DecryptedObject {
    <#
    .SYNOPSIS
        Internal function.

    .DESCRIPTION
        Copies SQL Server credentials from source to destination instances without losing the original passwords, which normally can't be retrieved through standard methods. This function uses a Dedicated Admin Connection (DAC) and password decryption techniques to extract the actual credential passwords from the source server and recreate them identically on the destination.

        This is essential for server migrations, disaster recovery setup, or environment synchronization where you need to move service accounts, proxy credentials, or linked server authentication without having to reset passwords or contact application teams for credentials.

        This function is used by the following public functions:
        - Copy-DbaCredential
        - Copy-DbaDbMail
        - Copy-DbaLinkedServer
        - Export-DbaCredential
        - Export-DbaLinkedServer

        This function is heavily based on Antti Rantasaari's script at http://goo.gl/wpqSib
        Antti Rantasaari 2014, NetSPI
        License: BSD 3-Clause http://opensource.org/licenses/BSD-3-Clause

    .PARAMETER SqlInstance
        Dedicated admin connection (DAC) to the SQL Server instance.

    .PARAMETER Credential
        This command requires access to the Windows OS via PowerShell remoting. Use this credential to connect to Windows using alternative credentials.

    .PARAMETER Type
        LinkedServer or Credential - what type of object to decrypt.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    #>
    param (
        [Parameter(Mandatory)]
        [Microsoft.SqlServer.Management.Smo.Server]$SqlInstance,
        [pscredential]$Credential,
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
        $sql = "SELECT SUBSTRING(crypt_property, 9, LEN(crypt_property) - 8) AS smk FROM sys.key_encryptions WHERE key_id = 102 AND thumbprint = 0x0300000001"
        $smkBytes = $server.Query($sql).smk
        if (-not $smkBytes) {
            $sql = "SELECT SUBSTRING(crypt_property, 9, LEN(crypt_property) - 8) AS smk FROM sys.key_encryptions WHERE key_id = 102 AND thumbprint = 0x03"
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
        $serviceKey = Invoke-Command2 -Raw -ComputerName $fullComputerName -Credential $Credential -ArgumentList $serviceInstanceId, $smkBytes {
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

    $sql = switch ($Type) {
        "LinkedServer" {
            "SELECT sysservers.srvname AS Name,
                NULL AS Quotename,
                syslnklgns.name AS Identity,
                SUBSTRING(syslnklgns.pwdhash, 5, $ivlen) AS iv,
                SUBSTRING(syslnklgns.pwdhash, $($ivlen + 5), LEN(syslnklgns.pwdhash) - $($ivlen + 4)) AS pass,
                NULL AS MappedClassType,
                NULL AS ProviderName
            FROM master.sys.syslnklgns
                INNER JOIN master.sys.sysservers
                ON syslnklgns.srvid = sysservers.srvid
            WHERE LEN(syslnklgns.pwdhash) > 0"
        }
        "Credential" {
            "SELECT cred.name AS Name,
                QUOTENAME(cred.name) AS Quotename,
                cred.credential_identity AS Identity,
                SUBSTRING(obj.imageval, 5, $ivlen) AS iv,
                SUBSTRING(obj.imageval, $($ivlen + 5), LEN(obj.imageval) - $($ivlen + 4)) AS pass,
                cred.target_type AS MappedClassType,
                cp.name AS ProviderName
            FROM sys.credentials cred
                INNER JOIN sys.sysobjvalues obj
                ON cred.credential_id = obj.objid
                LEFT OUTER JOIN sys.cryptographic_providers cp
                ON cred.target_id = cp.provider_id
            WHERE valclass = 28
                AND valnum = 2"
        }
    }

    Write-Message -Level Verbose -Message "Query password information from the Db."
    Write-Message -Level Debug -Message $sql
    $results = $server.Query($sql)

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

        [PSCustomObject]@{
            Name            = $result.Name
            Quotename       = $result.Quotename
            Identity        = $result.Identity
            Password        = $encode.GetString($decrypted)
            MappedClassType = $result.MappedClassType
            ProviderName    = $result.ProviderName
        }
    }
}
