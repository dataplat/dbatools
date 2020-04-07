function New-DbaDbAsymmetricKey {
    <#
    .SYNOPSIS
        Creates a new database asymmetric key

    .DESCRIPTION
        Creates a new database asymmetric key. If no database is specified, the asymmetric key will be created in master.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database where the asymmetric key will be created. Defaults to master.

    .PARAMETER Name
        Optional name to create the asymmetric key. Defaults to database name.

    .PARAMETER SecurePassword
        Optional password - if no password is supplied, the password will be protected by the master key

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER KeySourceType
        The source of external keys loaded in, can be one of Executable, File or Assemnly
        We do not currently support Provider

    .PARAMETER KeySource
        The path to the Executable, File or Assembly to be passed in.
        The path is parsed by the SQL Server instance, so needs to visiable to the instance

    .PARAMETER Algorithm
        The algorithm used to generate the key. Can be one of RSA512, RSA1024, RSA1024, RSA2048, RSA3072 or RSA4096. If not specified RSA2048 is the default
        This value will be ignored when KeySource is supplied, as the algorithm is embedded in the KeySource

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Owner
        User within the database who will own the key. Defaults to the user creating the key if not specified. User must exist withing the database already

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: asymmetrickey
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDbAsymmetricKey

    .EXAMPLE
        PS C:\> New-DbaDbAsymmetricKey -SqlInstance Server1

        You will be prompted to securely enter your password, then an asymmetric key will be created in the master database on server1 if it does not exist.

    .EXAMPLE
        PS C:\> New-DbaDbAsymmetricKey -SqlInstance Server1 -Database db1 -Confirm:$false

        Suppresses all prompts to install but prompts to securely enter your password and creates an asymmetric key in the 'db1' database

    .EXAMPLE
        PS C:\> New-DbaDbAsymmetrickKey -SqlInstance Server1 -Database enctest -KeySourceType File -KeySource c:\keys\NewKey.snk -Name BackupKey -Owner KeyOwner

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
            write-message -level verbose -message 'keysource paramter check'
            Stop-Function -Message 'Both Keysource and KeySourceType must be provided' -Continue
            break
        }
    }
    process {
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
                                    if ($null -eq (Get-DbaDbAssembly -SqlInstance $sqlInstance -SqlCredential $SqlCredential -Database $db -Name $KeySource)) {
                                        Stop-Function -Message "Instance $SqlInstance cannot see $keysource to create key, skipping" -Target $db -Continue
                                    }
                                }
                            }
                            if ($SecurePassword) {
                                $smokey.Create($KeySource, [Microsoft.SqlServer.Management.Smo.AsymmetricKeySourceType]::$KeySourceType, ([System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($SecurePassword))))
                            } else {
                                $smokey.Create($Keysource, [Microsoft.SqlServer.Management.Smo.AsymmetricKeySourceType]::$KeySourceType)
                            }

                        } else {
                            Write-Message -Level Verbose -Message 'Creating normal key without source'
                            if ($SecurePassword) {
                                $smokey.Create([Microsoft.SqlServer.Management.Smo.AsymmetricKeyEncryptionAlgorithm]::$Algorithm, ([System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($SecurePassword))))
                            } else {
                                $smokey.Create([Microsoft.SqlServer.Management.Smo.AsymmetricKeyEncryptionAlgorithm]::$Algorithm)
                            }
                        }

                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name ComputerName -value $db.Parent.ComputerName
                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name InstanceName -value $db.Parent.ServiceName
                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name SqlInstance -value $db.Parent.DomainInstanceName
                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name Database -value $db.Name
                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name Credential -value $Credential
                        Select-DefaultView -InputObject $smokey -Property ComputerName, InstanceName, SqlInstance, Database, Name, Subject, StartDate, ActiveForServiceBrokerDialog, ExpirationDate, Issuer, LastBackupDate, Owner, PrivateKeyEncryptionType, Serial
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