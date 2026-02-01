function Copy-DbaCredential {
    <#
    .SYNOPSIS
        Migrates SQL Server credentials between instances while preserving encrypted passwords.

    .DESCRIPTION
        Copies SQL Server credentials from source to destination instances without losing the original passwords, which normally can't be retrieved through standard methods. This function uses a Dedicated Admin Connection (DAC) and password decryption techniques to extract the actual credential passwords from the source server and recreate them identically on the destination.

        This is essential for server migrations, disaster recovery setup, or environment synchronization where you need to move service accounts, proxy credentials, or linked server authentication without having to reset passwords or contact application teams for credentials.

        The function requires sysadmin privileges on both servers, Windows administrator access, and DAC enabled on the source instance. It supports filtering by credential name or identity and can handle cryptographic provider credentials used for Extensible Key Management (EKM).

        Credit: Based on password decryption techniques by Antti Rantasaari (NetSPI, 2014)
        https://blog.netspi.com/decrypting-mssql-database-link-server-passwords/

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2005 or higher.

        You must be able to open a dedicated admin connection (DAC) to the source SQL Server.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2005 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Login to the target OS using alternative credentials. Accepts credential objects (Get-Credential)

        Only used when passwords are being exported, as it requires access to the Windows OS via PowerShell remoting to decrypt the passwords.

    .PARAMETER Name
        Specifies the credential names to copy from the source server. Does not supports wildcards for pattern matching.
        Use this when you only need to migrate specific credentials instead of all credentials on the server.
        Note: if spaces exist in the credential name, you will have to type "" or '' around it.

    .PARAMETER ExcludeName
        Specifies credential names to exclude from the copy operation. Does not support wildcards for pattern matching.
        Use this when you want to copy most credentials but skip specific ones like test accounts or deprecated credentials.

    .PARAMETER Identity
        Specifies the credential identities (user accounts) to copy from the source server. Does not support wildcards for pattern matching.
        Use this when you need to migrate credentials for specific service accounts or domain users rather than filtering by credential name.
        Note: if spaces exist in the credential identity, you will have to type "" or '' around it.

    .PARAMETER ExcludeIdentity
        Specifies credential identities (user accounts) to exclude from the copy operation. Does not support wildcards for pattern matching.
        Use this when you want to copy most credentials but skip those associated with specific service accounts or domain users.

    .PARAMETER ExcludePassword
        Copies credential definitions without the actual password values.
        Use this in security-conscious environments where password decryption is restricted or when passwords should be manually reset after migration.

    .PARAMETER Force
        Overwrites existing credentials on the destination server by dropping and recreating them with the source values.
        Use this when you need to update credential passwords or identities that have changed on the source server since the last migration.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: WSMan, Migration
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires:
        - PowerShell Version 3.0
        - Administrator access on Windows
        - sysadmin access on SQL Server.
        - DAC access enabled for local (default)

    .OUTPUTS
        PSCustomObject (MigrationObject type)

        Returns one object per credential copy operation (successful, skipped, or failed).

        Properties:
        - DateTime: Timestamp of when the operation was executed (DbaDateTime)
        - SourceServer: The name of the source SQL Server instance where the credential was copied from
        - DestinationServer: The name of the destination SQL Server instance where the credential was copied to
        - Name: The name of the credential that was migrated
        - Type: The type of object migrated (always "Credential" for this command)
        - Status: The result of the operation (Successful, Skipping, or Failed)
        - Notes: Additional details about the operation result, such as why a credential was skipped or the reason for failure

    .LINK
        https://dbatools.io/Copy-DbaCredential

    .EXAMPLE
        PS C:\> Copy-DbaCredential -Source sqlserver2014a -Destination sqlcluster

        Copies all SQL Server Credentials on sqlserver2014a to sqlcluster. If Credentials exist on destination, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaCredential -Source sqlserver2014a -Destination sqlcluster -Name "PowerShell Proxy Account" -Force

        Copies over one SQL Server Credential (PowerShell Proxy Account) from sqlserver to sqlcluster. If the Credential already exists on the destination, it will be dropped and recreated.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Justification = "For Credentials")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]
        $SourceSqlCredential,
        [PSCredential]
        $Credential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [string[]]$Name,
        [string[]]$ExcludeName,
        [Alias('CredentialIdentity')]
        [string[]]$Identity,
        [Alias('ExcludeCredentialIdentity')]
        [string[]]$ExcludeIdentity,
        [switch]$ExcludePassword,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if (-not $script:isWindows) {
            Stop-Function -Message "Copy-DbaCredential is only supported on Windows"
            return
        }

        if ($Force) { $ConfirmPreference = 'none' }

        try {
            if ($ExcludePassword) {
                Write-Message -Level Verbose -Message "Opening normal connection because we don't need the passwords."
                $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9
            } else {
                Write-Message -Level Verbose -Message "Opening dedicated admin connection for password retrieval."
                $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9 -DedicatedAdminConnection -WarningAction SilentlyContinue
            }
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        if (-not $ExcludePassword) {
            Write-Message -Level Verbose -Message "Decrypting all Credential logins and passwords on $($sourceServer.Name)"
            try {
                $decryptedCredentials = Get-DecryptedObject -SqlInstance $sourceServer -Credential $Credential -Type Credential -EnableException
            } catch {
                Stop-Function -Message "Failed to decrypt credentials on $($sourceServer.Name)" -ErrorRecord $_
                return
            }
        }

        Write-Message -Level Verbose -Message "Getting all Credentials that should be processed on $($sourceServer.Name)"
        $credentialList = Get-DbaCredential -SqlInstance $sourceServer -Name $Name -ExcludeName $ExcludeName -Identity $Identity -ExcludeIdentity $ExcludeIdentity
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            Write-Message -Level Verbose -Message "Starting migration"
            $destServer.Credentials.Refresh()
            foreach ($cred in $credentialList) {
                $credentialName = $cred.Name

                $copyCredentialStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.DomainInstanceName
                    DestinationServer = $destServer.DomainInstanceName
                    Type              = "Credential"
                    Name              = $credentialName
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($null -ne $destServer.Credentials[$credentialName]) {
                    if (!$force) {
                        $copyCredentialStatus.Status = "Skipping"
                        $copyCredentialStatus.Notes = "Already exists on destination"
                        if ($Pscmdlet.ShouldProcess($destServer.Name, "Skipping $credentialName, already exists")) {
                            $copyCredentialStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping $credentialName")) {
                            try {
                                $destServer.Credentials[$credentialName].Drop()
                            } catch {
                                $copyCredentialStatus.Status = "Failed"
                                $copyCredentialStatus.Notes = "$PSItem"
                                Write-Message -Level Verbose -Message "Issue dropping $credentialName on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }

                Write-Message -Level Verbose -Message "Attempting to migrate $credentialName"
                try {
                    $splatNewCredential = @{
                        SqlInstance     = $destServer
                        Name            = $cred.Name
                        Identity        = $cred.Identity
                        MappedClassType = $cred.MappedClassType
                        EnableException = $true
                    }
                    if ($cred.mappedClassType -eq "CryptographicProvider") {
                        $cryptoConfiguredOnDestination = $destServer.Query("SELECT is_enabled FROM sys.cryptographic_providers WHERE name = '$($cred.ProviderName)'")
                        if (-not $cryptoConfiguredOnDestination.is_enabled) {
                            throw "The cryptographic provider $($cred.ProviderName) needs to be configured and enabled on $destServer"
                        }
                        $splatNewCredential.ProviderName = $cred.ProviderName
                    }
                    if (-not $ExcludePassword) {
                        $decryptedCred = $decryptedCredentials | Where-Object { $_.Name -eq $credentialName }
                        $splatNewCredential.SecurePassword = ConvertTo-SecureString -String $decryptedCred.Password -AsPlainText -Force
                    }

                    if ($Pscmdlet.ShouldProcess($destinstance, "Copying $identity ($credentialName)")) {
                        $null = New-DbaCredential @splatNewCredential
                        Write-Message -Level Verbose -Message "$credentialName successfully copied"
                        $copyCredentialStatus.Status = "Successful"
                        $copyCredentialStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                } catch {
                    $copyCredentialStatus.Status = "Failed"
                    $copyCredentialStatus.Notes = "$PSItem"
                    $copyCredentialStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Issue creating $credentialName on $destinstance | $PSItem"
                    continue
                }
            }
        }
    }
    end {
        # Disconnect is important because it is a DAC
        # Disconnect in case of WhatIf, as we opened the connection
        if (-not $ExcludePassword) {
            $null = $sourceServer | Disconnect-DbaInstance -WhatIf:$false
        }
    }
}