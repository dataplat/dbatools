function New-DbaDbEncryptionKey {
    <#
    .SYNOPSIS
        Creates database encryption keys for Transparent Data Encryption (TDE)

    .DESCRIPTION
        Creates database encryption keys (DEKs) required for Transparent Data Encryption, using certificates or asymmetric keys from the master database. This is the essential first step before enabling TDE on any database to encrypt data at rest. The function automatically validates that certificates have been backed up before creating encryption keys, preventing potential data loss scenarios. If no encryptor is specified, it will automatically select an appropriate certificate or asymmetric key from master database.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database where the encryption key will be created to enable Transparent Data Encryption.
        This is the user database you want to encrypt, not the master database where certificates are stored.

    .PARAMETER EncryptorName
        Specifies the name of the certificate or asymmetric key in the master database to encrypt the database encryption key.
        If not provided, the function automatically selects an appropriate certificate from master (requires exactly one non-system certificate to exist).
        For asymmetric keys, the key must reside on an extensible key management provider like Azure Key Vault or Hardware Security Module.

    .PARAMETER Type
        Specifies whether to use a Certificate or AsymmetricKey from the master database as the encryptor.
        Certificates are more common for TDE implementations, while asymmetric keys are typically used with external key management providers.

    .PARAMETER EncryptionAlgorithm
        Specifies the symmetric encryption algorithm used for the database encryption key.
        Aes256 provides the strongest encryption and is recommended for production environments, while Aes128 offers faster performance.
        TripleDes is legacy and should be avoided for new implementations.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase to create encryption keys for multiple databases.
        Use this when you need to enable TDE on several databases across one or more SQL Server instances.

    .PARAMETER Force
        Bypasses the safety check that prevents creating encryption keys with unbackup certificates, which could lead to unrecoverable data loss.
        Also creates the specified certificate automatically if it doesn't exist in the master database.
        Use this only in development environments or when you have verified certificate backups exist through other means.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.DatabaseEncryptionKey

        Returns one DatabaseEncryptionKey object per database where the encryption key was successfully created. If creation fails or is skipped (e.g., database already has an encryption key), no object is returned for that database.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The database name containing the encryption key
        - CreateDate: DateTime when the encryption key was created
        - EncryptionAlgorithm: The encryption algorithm used (Aes128, Aes192, Aes256, or TripleDes)
        - EncryptionState: Current encryption state (Encrypted, EncryptionInProgress, DecryptionInProgress, or EncryptionUnsupported)
        - EncryptionType: Type of encryptor used (ServerCertificate or ServerAsymmetricKey)
        - EncryptorName: Name of the certificate or asymmetric key protecting this encryption key
        - ModifyDate: DateTime when the encryption key was last modified
        - OpenedDate: DateTime when the encryption key was last opened
        - RegenerateDate: DateTime when the encryption key was last regenerated
        - SetDate: DateTime when the encryption key was last set
        - Thumbprint: Thumbprint hash of the certificate protecting this encryption key

        All properties from the base SMO DatabaseEncryptionKey object are accessible even though only default properties are displayed without using Select-Object *.

    .LINK
        https://dbatools.io/New-DbaDbEncryptionKey

    .EXAMPLE
        PS C:\> $dbs = Get-DbaDatabase -SqlInstance sql01 -Database pubs
        PS C:\> $db | New-DbaDbEncryptionKey

        Creates an Aes256 encryption key for the pubs database on sql01. Automatically selects a cert database in master if one (and only one) non-system certificate exists.

        Prompts for confirmation.

    .EXAMPLE
        PS C:\> New-DbaDbEncryptionKey -SqlInstance sql01 -Database db1 -EncryptorName "sql01 cert" -EncryptionAlgorithm Aes192 -Confirm:$false

        Creates an Aes192 encryption key for the pubs database on sql01 using the certiciated named "sql01 cert" in master.

        Does not prompt for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database = "master",
        [Alias("Certificate", "CertificateName")]
        [string]$EncryptorName,
        [ValidateSet("Certificate", "AsymmetricKey")]
        [string]$Type = "Certificate",
        [ValidateSet("Aes128", "Aes192", "Aes256", "TripleDes")]
        [string]$EncryptionAlgorithm = 'Aes256',
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            if ($db.HasDatabaseEncryptionKey) {
                Stop-Function -Message "$($db.Name) on $($db.Parent.Name) already has a database encryption key" -Continue
            }

            if ((Test-Bound -Not -ParameterName EncryptorName)) {
                Write-Message -Level Verbose -Message "Name of encryptor not specified, looking for candidates on master"

                if ($Type -eq "Certificate") {
                    $null = $db.Parent.Databases["master"].Certificates.Refresh()
                    $dbcert = Get-DbaDbCertificate -SqlInstance $db.Parent -Database master | Where-Object Name -notmatch "##"
                    if ($dbcert.Name.Count -ne 1) {
                        if ($dbcert.Name.Count -lt 1) {
                            Stop-Function -Message "No usable certificates found in master on $($db.Parent.Name)" -Continue
                        } else {
                            Stop-Function -Message "More than one certificate found in master, please specify a name" -Continue
                        }
                    } else {
                        $EncryptorName = $dbcert.Name
                    }
                } else {
                    $EncryptorName = (Get-DbaDbAsymmetricKey -SqlInstance $db.Parent -Database master).Name
                    if (-not $EncryptorName) {
                        Stop-Function -Message "No usable Asymmetric Keys found in master on $($db.Parent.Name)" -Continue
                    }
                }
            }

            # asym is backed up with db, so only check certs for backups
            if ($Type -eq "Certificate") {
                Write-Message -Level Verbose "Getting certificate '$EncryptorName' from $($db.Parent) on $($db.Parent.Name)"
                $dbcert = Get-DbaDbCertificate -SqlInstance $db.Parent -Database master -Certificate $EncryptorName
                if (-not $dbcert -and $Force -and $EncryptorName) {
                    $dbcert = New-DbaDbCertificate -SqlInstance $db.Parent -Database master -Name $EncryptorName
                    $null = $db.Parent.Refresh()
                    $null = $db.Parent.Databases["master"].Refresh()
                }
                if ($dbcert.LastBackupDate.Year -eq 1 -and -not $Force -and -not $WhatIfPreference) {
                    Stop-Function -Message "Certificate ($EncryptorName) in master on $($db.Parent) has not been backed up. Please backup your certificate or use -Force to continue" -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Creating encryption key for database '$($db.Name)'")) {

                # something is up with .net, force a stop
                $eap = $ErrorActionPreference
                $ErrorActionPreference = 'Stop'
                try {
                    # Shoutout to https://www.mssqltips.com/sqlservertip/6316/configure-sql-server-transparent-data-encryption-with-powershell/
                    $smoencryptionkey = New-Object -TypeName Microsoft.SqlServer.Management.Smo.DatabaseEncryptionKey
                    $smoencryptionkey.Parent = $db
                    $smoencryptionkey.EncryptionAlgorithm = $EncryptionAlgorithm
                    $smoencryptionkey.EncryptionType = "Server$Type"
                    $smoencryptionkey.EncryptorName = $EncryptorName
                    $null = $smoencryptionkey.Create()
                    $null = $db.Refresh()
                    if ($db.Certficates) {
                        $null = $db.Certficates.Refresh()
                    }
                    if ($db.AsymmetricKeys) {
                        $null = $db.AsymmetricKeys.Refresh()
                    }
                    $db | Get-DbaDbEncryptionKey
                } catch {
                    $ErrorActionPreference = $eap
                    Stop-Function -Message "Failed to create encryption key in $($db.Name) on $($db.Parent.Name)" -Target $smoencryptionkey -ErrorRecord $_ -Continue
                }
                $ErrorActionPreference = $eap
            }
        }
    }
}