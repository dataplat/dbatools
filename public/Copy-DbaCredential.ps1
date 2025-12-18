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
        This command requires access to the Windows OS via PowerShell remoting. Use this credential to connect to Windows using alternative credentials.

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
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if (-not $script:isWindows) {
            Stop-Function -Message "Copy-DbaCredential is only supported on Windows"
            return
        }
        $results = Test-ElevationRequirement -ComputerName $Source.ComputerName

        if (-not $results) {
            return
        }

        if ($Force) { $ConfirmPreference = 'none' }

        try {
            Write-Message -Level Verbose -Message "We will try to open a dedicated admin connection."
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9 -DedicatedAdminConnection -WarningAction SilentlyContinue
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        Invoke-SmoCheck -SqlInstance $sourceServer

        if ($null -ne $SourceSqlCredential.Username) {
            Write-Message -Level Verbose -Message "You are using SQL credentials and this script requires Windows admin access to the $Source server. Trying anyway."
        }

        Write-Message -Level Verbose -Message "Decrypting all Credential logins and passwords on $($sourceServer.Name)"
        try {
            $decryptedCredentials = Get-DecryptedObject -SqlInstance $sourceServer -Type Credential -EnableException
        } catch {
            Stop-Function -Message "Failed to decrypt credentials on $($sourceServer.Name)" -ErrorRecord $_
            return
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
            Invoke-SmoCheck -SqlInstance $destServer

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
                    $decryptedCred = $decryptedCredentials | Where-Object { $_.Name -eq $credentialName }
                    $sqlcredentialName = $decryptedCred.Quotename
                    $identity = $decryptedCred.Identity.Replace("'", "''")
                    $password = $decryptedCred.Password.Replace("'", "''")

                    if ($cred.MappedClassType -eq "CryptographicProvider") {
                        $cryptoConfiguredOnDestination = $destServer.Query("SELECT is_enabled FROM sys.cryptographic_providers WHERE name = '$($cred.ProviderName)'")

                        if (-not $cryptoConfiguredOnDestination.is_enabled) {
                            throw "The cryptographic provider $($cred.ProviderName) needs to be configured and enabled on $destServer"
                        } else {
                            $cryptoSQL = " FOR CRYPTOGRAPHIC PROVIDER $($cred.ProviderName) "
                        }
                    }

                    if ($Pscmdlet.ShouldProcess($destinstance, "Copying $identity ($credentialName)")) {
                        $destServer.Query("CREATE CREDENTIAL $sqlcredentialName WITH IDENTITY = N'$identity', SECRET = N'$password' $cryptoSQL")
                        $destServer.Credentials.Refresh()
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
        $null = $sourceServer | Disconnect-DbaInstance -WhatIf:$false
    }
}