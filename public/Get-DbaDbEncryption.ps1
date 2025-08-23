function Get-DbaDbEncryption {
    <#
    .SYNOPSIS
        Retrieves comprehensive encryption inventory from SQL Server databases including TDE status, certificates, and keys.

    .DESCRIPTION
        Audits database-level encryption across SQL Server instances by examining TDE encryption status, certificates, asymmetric keys, and symmetric keys within each database. Returns detailed information including key algorithms, lengths, owners, backup dates, and expiration dates for compliance reporting and security assessments. Particularly useful for encryption audits, certificate lifecycle management, and ensuring regulatory compliance across your SQL Server environment.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to examine for encryption objects including TDE, certificates, and keys. Accepts database names as strings or arrays.
        Use this to focus encryption audits on specific databases rather than scanning all user databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from the encryption inventory scan. Useful when you need to audit most databases but skip certain ones.
        Commonly used to exclude databases with known encryption issues or maintenance databases that don't require encryption compliance checks.

    .PARAMETER IncludeSystemDBs
        Includes system databases (master, model, msdb, tempdb) in the encryption inventory. By default, only user databases are scanned.
        Use this when conducting comprehensive security audits that require visibility into system database encryption objects and TDE configurations.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Encryption
        Author: Stephen Bennett, sqlnotesfromtheunderground.wordpress.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbEncryption

    .EXAMPLE
        PS C:\> Get-DbaDbEncryption -SqlInstance DEV01

        List all encryption found on the instance by database

    .EXAMPLE
        PS C:\> Get-DbaDbEncryption -SqlInstance DEV01 -Database MyDB

        List all encryption found for the MyDB database.

    .EXAMPLE
        PS C:\> Get-DbaDbEncryption -SqlInstance DEV01 -ExcludeDatabase MyDB

        List all encryption found for all databases except MyDB.

    .EXAMPLE
        PS C:\> Get-DbaDbEncryption -SqlInstance DEV01 -IncludeSystemDBs

        List all encryption found for all databases including the system databases.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline, Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$IncludeSystemDBs,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            #For each SQL Server in collection, connect and get SMO object

            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            #If IncludeSystemDBs is true, include systemdbs
            #only look at online databases (Status equal normal)
            try {
                if ($Database) {
                    $dbs = $server.Databases | Where-Object Name -In $Database
                } elseif ($IncludeSystemDBs) {
                    $dbs = $server.Databases | Where-Object IsAccessible
                } else {
                    $dbs = $server.Databases | Where-Object { $_.IsAccessible -and $_.IsSystemObject -eq 0 }
                }

                if ($ExcludeDatabase) {
                    $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
                }
            } catch {
                Stop-Function -Message "Unable to gather dbs for $instance" -Target $instance -Continue
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db"

                if ($db.EncryptionEnabled) {
                    $returnCertificate = [PSCustomObject]@{
                        ComputerName             = $server.ComputerName
                        InstanceName             = $server.ServiceName
                        SqlInstance              = $server.DomainInstanceName
                        Database                 = $db.Name
                        Encryption               = "EncryptionEnabled (TDE)"
                        Name                     = $null
                        LastBackup               = $null
                        PrivateKeyEncryptionType = $null
                        EncryptionAlgorithm      = $null
                        KeyLength                = $null
                        Owner                    = $null
                        Object                   = $null
                        ExpirationDate           = $null
                    }

                    if ($db.DatabaseEncryptionKey.EncryptionType -eq 'ServerCertificate') {
                        $serverCertificate = $server.Databases['master'].Certificates | Where-Object {
                            (Compare-Object -ReferenceObject $db.DatabaseEncryptionKey.Thumbprint -DifferenceObject $_.Thumbprint -SyncWindow 0).Length -eq 0
                        }

                        if (-not $serverCertificate) {
                            Stop-Function -Message "Could not locate TDE server certificate $($db.DatabaseEncryptionKey.Name)" -Target $instance -Continue
                        }

                        $returnCertificate.Name = $serverCertificate.Name
                        $returnCertificate.LastBackup = $serverCertificate.LastBackupDate
                        $returnCertificate.PrivateKeyEncryptionType = $serverCertificate.PrivateKeyEncryptionType
                        $returnCertificate.Owner = $serverCertificate.Owner
                        $returnCertificate.Object = $serverCertificate
                        $returnCertificate.ExpirationDate = $serverCertificate.ExpirationDate
                        $returnCertificate.EncryptionAlgorithm = $db.DatabaseEncryptionKey.EncryptionAlgorithm
                    }

                    $returnCertificate
                }

                foreach ($cert in $db.Certificates) {
                    [PSCustomObject]@{
                        ComputerName             = $server.ComputerName
                        InstanceName             = $server.ServiceName
                        SqlInstance              = $server.DomainInstanceName
                        Database                 = $db.Name
                        Encryption               = "Certificate"
                        Name                     = $cert.Name
                        LastBackup               = $cert.LastBackupDate
                        PrivateKeyEncryptionType = $cert.PrivateKeyEncryptionType
                        EncryptionAlgorithm      = $null
                        KeyLength                = $null
                        Owner                    = $cert.Owner
                        Object                   = $cert
                        ExpirationDate           = $cert.ExpirationDate
                    }

                }

                foreach ($ak in $db.AsymmetricKeys) {
                    [PSCustomObject]@{
                        ComputerName             = $server.ComputerName
                        InstanceName             = $server.ServiceName
                        SqlInstance              = $server.DomainInstanceName
                        Database                 = $db.Name
                        Encryption               = "Asymmetric key"
                        Name                     = $ak.Name
                        LastBackup               = $null
                        PrivateKeyEncryptionType = $ak.PrivateKeyEncryptionType
                        EncryptionAlgorithm      = $ak.KeyEncryptionAlgorithm
                        KeyLength                = $ak.KeyLength
                        Owner                    = $ak.Owner
                        Object                   = $ak
                        ExpirationDate           = $null
                    }

                }
                foreach ($sk in $db.SymmetricKeys) {
                    [PSCustomObject]@{
                        Server                   = $server.name
                        Instance                 = $server.InstanceName
                        Database                 = $db.Name
                        Encryption               = "Symmetric key"
                        Name                     = $sk.Name
                        LastBackup               = $null
                        PrivateKeyEncryptionType = $sk.PrivateKeyEncryptionType
                        EncryptionAlgorithm      = $ak.EncryptionAlgorithm
                        KeyLength                = $sk.KeyLength
                        Owner                    = $sk.Owner
                        Object                   = $sk
                        ExpirationDate           = $null
                    }
                }
            }
        }
    }
}