function Get-DbaDbEncryption {
    <#
    .SYNOPSIS
        Returns a summary of encryption used on databases passed to it.

    .DESCRIPTION
        Shows if a database has Transparent Data Encryption (TDE), any certificates, asymmetric keys or symmetric keys with details for each.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server.

    .PARAMETER IncludeSystemDBs
        Switch parameter that when used will display system database information.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Encryption, Database
        Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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

                if ($db.EncryptionEnabled -eq $true) {
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
                        $returnCertificate.EncryptionAlgorithm = $db.DatabaseEncryptionKey.Properties | Where-Object( { $psitem.name -eq 'EncryptionAlgorithm' }).value
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