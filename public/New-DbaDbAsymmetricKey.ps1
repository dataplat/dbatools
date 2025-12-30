function New-DbaDbAsymmetricKey {
    <#
    .SYNOPSIS
        Creates RSA asymmetric keys in SQL Server databases for encryption and digital signing

    .DESCRIPTION
        Creates asymmetric keys within SQL Server databases using RSA encryption algorithms (512-4096 bit). These keys are essential for database-level encryption features like Transparent Data Encryption (TDE), column-level encryption, and digital signing of assemblies or stored procedures. You can generate new key pairs directly on the server or import existing keys from files, executables, or assemblies. Keys can be password-protected or secured using the database master key, and ownership can be assigned to specific database users.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the target database where the asymmetric key will be created. Defaults to master database if not specified.
        Use this when creating encryption keys for specific user databases rather than system-wide keys.

    .PARAMETER Name
        Specifies the name for the asymmetric key object within the database. Defaults to the database name if not provided.
        Choose meaningful names that reflect the key's purpose, such as 'TDE_Key' or 'BackupKey' for easier identification.

    .PARAMETER SecurePassword
        Provides a password to encrypt the asymmetric key's private key. If omitted, the database master key protects the private key.
        Use this when you need explicit password control or when the database master key is not available.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase through the pipeline for batch key creation.
        Use this when creating asymmetric keys across multiple databases in a single operation.

    .PARAMETER KeySourceType
        Specifies the type of external key source when importing existing keys. Valid values are Executable, File, or SqlAssembly.
        Required when using KeySource parameter to import keys from external files rather than generating new ones.

    .PARAMETER KeySource
        Specifies the path or name of the external key source (file, executable, or SQL assembly name).
        The path must be accessible by the SQL Server service account when using File or Executable types.

    .PARAMETER Algorithm
        Sets the RSA encryption algorithm strength for newly generated keys. Valid options are Rsa512, Rsa1024, Rsa2048, Rsa3072, or Rsa4096.
        Defaults to Rsa2048 which provides good security for most scenarios. Higher bit strengths offer stronger encryption but slower performance.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Owner
        Specifies the database user who will own the asymmetric key. Defaults to the current user if not specified.
        The specified user must already exist in the target database before creating the key.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Security
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDbAsymmetricKey

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.AsymmetricKey

        Returns one AsymmetricKey object for each asymmetric key successfully created in the target database(s).

        Display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The database containing the asymmetric key
        - Name: The name of the asymmetric key
        - Owner: The database user who owns the key
        - KeyEncryptionAlgorithm: The RSA algorithm used (Rsa512, Rsa1024, Rsa2048, Rsa3072, or Rsa4096)
        - KeyLength: The key length in bits (512, 1024, 2048, 3072, or 4096)
        - PrivateKeyEncryptionType: How the private key is encrypted (Password, MasterKey, or None)
        - Thumbprint: The SHA-1 hash of the public key for identification

        Additional properties available via Select-Object * from the SMO AsymmetricKey object include standard SMO object properties such as Parent (reference to the parent Database), Urn (Uniform Resource Name), and State (current SMO object state).

    .EXAMPLE
        PS C:\> New-DbaDbAsymmetricKey -SqlInstance Server1

        You will be prompted to securely enter your password, then an asymmetric key will be created in the master database on server1 if it does not exist.

    .EXAMPLE
        PS C:\> New-DbaDbAsymmetricKey -SqlInstance Server1 -Database db1 -Confirm:$false

        Suppresses all prompts to install but prompts to securely enter your password and creates an asymmetric key in the 'db1' database

    .EXAMPLE
        PS C:\> New-DbaDbAsymmetricKey -SqlInstance Server1 -Database enctest -KeySourceType File -KeySource c:\keys\NewKey.snk -Name BackupKey -Owner KeyOwner

        Installs the key pair held in NewKey.snk into the enctest database creating an AsymmetricKey called BackupKey, which will be owned by KeyOwner
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Name,
        [string[]]$Database = "master",
        [Alias("Password")]
        [Security.SecureString]$SecurePassword,
        [String]$Owner,
        [String]$KeySource,
        [ValidateSet('Executable', 'File', 'SqlAssembly')]
        [String]$KeySourceType,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [ValidateSet('Rsa4096', 'Rsa3072', 'Rsa2048', 'Rsa1024', 'Rsa512')]
        [string]$Algorithm = 'Rsa2048',
        [switch]$EnableException
    )
    begin {
        if (((Test-Bound 'KeySource') -xor (Test-Bound 'KeySourceType'))) {
            Write-Message -Level Verbose -Message 'keysource paramter check'
            Stop-Function -Message 'Both Keysource and KeySourceType must be provided'
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            if (!($null -ne $name)) {
                Write-Message -Level Verbose -Message "Name of asymmetric key not specified, setting it to '$db'"
                $Name = $db.Name
            }

            foreach ($askey in $Name) {
                if ($null -ne $db.AsymmetricKeys[$askey]) {
                    Stop-Function -Message "Asymmetric Key '$askey' already exists in $($db.Name) on $($db.Parent.Name)" -Target $db -Continue
                }

                if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Creating asymmetric key for database '$($db.Name)'")) {

                    # something is up with .net, force a stop
                    $eap = $ErrorActionPreference
                    $ErrorActionPreference = 'Stop'
                    try {
                        $smokey = New-Object -TypeName Microsoft.SqlServer.Management.Smo.AsymmetricKey $db, $askey
                        if ($owner -ne '') {
                            if ((Get-DbaDbUser -SqlInstance $db.Parent -Database $db.name | Where-Object name -eq $owner).count -eq 1) {
                                Write-Message -Level Verbose -Message "Setting key owner to $owner"
                                $smokey.owner = $owner
                            } else {
                                Stop-Function -Message "$owner is unkown or ambiguous in $($db.name)" -Target $db -Continue
                            }
                        }
                        if ('' -ne $Keysource) {
                            switch ($KeySourceType) {
                                'Executable' {
                                    Write-Message -Level Verbose -Message 'Executable passed in as key source'
                                    if (!(Test-DbaPath -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Path $KeySource)) {
                                        Stop-Function -Message "Instance $SqlInstance cannot see $keysource to create key, skipping" -Target $db -Continue
                                    }
                                }
                                'File' {
                                    Write-Message -Level Verbose -Message 'File passed in as key source'
                                    if (!(Test-DbaPath -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Path $KeySource)) {
                                        Stop-Function -Message "Instance $SqlInstance cannot see $keysource to create key, skipping" -Target $db -Continue
                                    }
                                }
                                'SqlAssembly' {
                                    Write-Message -Level Verbose -Message 'SqlAssembly passed in as key source'
                                    if ($null -eq (Get-DbaDbAssembly -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $db -Name $KeySource)) {
                                        Stop-Function -Message "Instance $SqlInstance cannot see $keysource to create key, skipping" -Target $db -Continue
                                    }
                                }
                            }
                            if ($SecurePassword) {
                                $smokey.Create($KeySource, [Microsoft.SqlServer.Management.Smo.AsymmetricKeySourceType]::$KeySourceType, ($SecurePassword | ConvertFrom-SecurePass))
                            } else {
                                $smokey.Create($Keysource, [Microsoft.SqlServer.Management.Smo.AsymmetricKeySourceType]::$KeySourceType)
                            }

                        } else {
                            Write-Message -Level Verbose -Message 'Creating normal key without source'
                            if ($SecurePassword) {
                                $smokey.Create([Microsoft.SqlServer.Management.Smo.AsymmetricKeyEncryptionAlgorithm]::$Algorithm, ($SecurePassword | ConvertFrom-SecurePass))
                            } else {
                                $smokey.Create([Microsoft.SqlServer.Management.Smo.AsymmetricKeyEncryptionAlgorithm]::$Algorithm)
                            }
                        }

                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name ComputerName -value $db.Parent.ComputerName
                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name InstanceName -value $db.Parent.ServiceName
                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name SqlInstance -value $db.Parent.DomainInstanceName
                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name Database -value $db.Name
                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name Credential -value $Credential
                        Select-DefaultView -InputObject $smokey -Property ComputerName, InstanceName, SqlInstance, Database, Name, Owner, KeyEncryptionAlgorithm, KeyLength, PrivateKeyEncryptionType, Thumbprint
                    } catch {
                        $ErrorActionPreference = $eap
                        Stop-Function -Message "Failed to create asymmetric key in $($db.Name) on $($db.Parent.Name)" -Target $smocert -ErrorRecord $_ -Continue
                    }
                    $ErrorActionPreference = $eap
                }
            }
        }
    }
}