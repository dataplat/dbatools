function Set-DbaNetworkCertificate {
    <#
    .SYNOPSIS
        Sets the network certificate for SQL Server instance

    .DESCRIPTION
        Sets the network certificate for SQL Server instance in two possible ways. This setting is found in Configuration Manager.

        Without the Certificate or Thumbprint parameter (Way One): Calls Test-DbaNetworkCertificate to retrieve
        information about the currently configured certificate and available suitable certificates.
        Returns without changes if the currently configured certificate is still valid.
        Configures the suitable certificate if exactly one is available.
        Fails if more than one or no suitable certificate is found.

        With the Certificate or Thumbprint parameter (Way Two): Calls Test-DbaNetworkCertificate to retrieve
        information about the currently configured certificate and available suitable certificates.
        Returns without changes if the given certificate match the currently configured certificate that is still valid.
        Configures the given certificate if it is returned as a suitable certificate.
        If the given certificate is not returned as a suitable certificate, the command gets detailed information
        about why the given certificate is not suitable and fails with that information.

        This command also grants read permissions for the service account on the certificate's private key.

        The currently configured certificate can be unset by using the parameter -UnsetCertificate.

        References:
        https://www.itprotoday.com/sql-server/7-steps-ssl-encryption
        https://azurebi.jppp.org/2016/01/23/using-lets-encrypt-certificates-for-secure-sql-server-connections/
        https://blogs.msdn.microsoft.com/sqlserverfaq/2016/09/26/creating-and-registering-ssl-certificates/
        https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/certificate-requirements

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER Credential
        Allows you to login to the computer (not sql instance) using alternative credentials.

    .PARAMETER Certificate
        Specifies the X509Certificate2 object to configure as the network certificate for SQL Server.
        Use this when piping certificate objects from other dbatools commands like New-DbaComputerCertificate.
        The certificate must exist in the LocalMachine certificate store and have a private key for SQL Server to use it for SSL connections.

    .PARAMETER Thumbprint
        Specifies the thumbprint (SHA-1 hash) of the certificate to configure as the network certificate.
        Use this when you know the specific certificate thumbprint from certificates already installed in LocalMachine\My.
        Must be a 40-character hexadecimal string (no spaces). The certificate must have a private key and the SQL Server
        service account will be granted read permissions to it.

    .PARAMETER UnsetCertificate
        Unsets the currently configured network certificate for the SQL Server instance.
        This will remove the certificate configuration, and SQL Server will not use any certificate for SSL connections.

    .PARAMETER RestartService
        Forces an automatic restart of the SQL Server service after setting the network certificate.
        Certificate changes require a service restart to take effect - without this switch you'll need to manually restart SQL Server.
        Use this when you want the SSL configuration to be immediately active, but be aware it will cause a brief service interruption.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net | Refactored by Andreas Jordan (@andreasjordan)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaNetworkCertificate

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server instance processed, containing the following properties:

        - ComputerName: The name of the computer where the SQL Server instance is hosted
        - InstanceName: The SQL Server instance name (e.g., MSSQLSERVER, SQL2008R2SP2)
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - CertificateThumbprint: The SHA-1 thumbprint of the newly configured certificate in lowercase
        - Notes: Summary of actions performed, including whether an old certificate was replaced

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate | Set-DbaNetworkCertificate -SqlInstance localhost\SQL2008R2SP2

        Creates and imports a new certificate signed by an Active Directory CA on localhost then sets the network certificate for the SQL2008R2SP2 to that newly created certificate.

    .EXAMPLE
        PS C:\> Set-DbaNetworkCertificate -SqlInstance localhost\SQL2008R2SP2

        Sets the network certificate for the SQL2008R2SP2 instance if exactly one suitable certificate is found.

    .EXAMPLE
        PS C:\> Set-DbaNetworkCertificate -SqlInstance sql1\SQL2008R2SP2 -Thumbprint 1223FB1ACBCA44D3EE9640F81B6BA14A92F3D6E2

        Sets the network certificate for the SQL2008R2SP2 instance to the certificate with the thumbprint of 1223FB1ACBCA44D3EE9640F81B6BA14A92F3D6E2 in LocalMachine\My on sql1

    .EXAMPLE
        PS C:\> Set-DbaNetworkCertificate -SqlInstance localhost\SQL2008R2SP2 -UnsetCertificate -RestartService

        Unsets the network certificate for the SQL2008R2SP2 instance and restarts the SQL Server service.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias("ComputerName")]
        [DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$Credential,
        [Parameter(ValueFromPipeline)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Thumbprint,
        [switch]$UnsetCertificate,
        [switch]$RestartService,
        [switch]$EnableException
    )

    begin {
        # The beginning of this scriptblock should be kept aligned to the ones in Get- and Set-DbaNetworkConfiguration.
        $scriptBlock = {
            # This scriptblock will be processed by Invoke-Command2 on the target machine.
            # We take an object as the first parameter which has to include the properties ComputerName, InstanceName and SqlFullName,
            # so normally a DbaInstanceParameter.
            $instance = $args[0]
            # In addition to Get-DbaNetworkConfiguration we need the thumbprint of the certificate we want to configure.
            $thumbprint = $args[1]
            $verbose = @()
            $exception = $null

            try {
                $verbose += "Starting initialization of WMI object"

                # As we go remote, ensure the assembly is loaded
                [void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
                $wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
                $result = $wmi.Initialize()

                $verbose += "Initialization of WMI object finished with $result"

                $wmiService = $wmi.Services | Where-Object { $_.DisplayName -eq "SQL Server ($($instance.InstanceName))" }
                $regRoot = ($wmiService.AdvancedProperties | Where-Object Name -eq REGROOT).Value
                $verbose += "regRoot = '$regRoot'"
                if ([System.String]::IsNullOrEmpty($regRoot)) {
                    $regRoot = $wmiService.AdvancedProperties | Where-Object { $_ -match 'REGROOT' }
                    $verbose += "regRoot = '$regRoot'"
                    if (![System.String]::IsNullOrEmpty($regRoot)) {
                        $regRoot = ($regRoot -Split 'Value\=')[1]
                        $verbose += "regRoot = '$regRoot'"
                    } else {
                        # This is just for safty, as we just used Get-DbaNetworkConfiguration successfully
                        throw "Can't find regRoot"
                    }
                }
                $regPath = "Registry::HKEY_LOCAL_MACHINE\$regRoot\MSSQLServer\SuperSocketNetLib"

                if ($thumbprint) {
                    $verbose += "Certificate thumbprint to set: $thumbprint"

                    $cert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction Stop | Where-Object { $_.Thumbprint -eq $thumbprint }
                    $keyPath = $env:ProgramData + "\Microsoft\Crypto\RSA\MachineKeys\"
                    if ($PSVersionTable.PSVersion.Major -ge 6) {
                        $keyName = $cert.PrivateKey.Key.UniqueName
                    } else {
                        $keyName = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
                    }
                    $keyFullPath = $keyPath + $keyName
                    if (-not (Test-Path $keyFullPath -Type Leaf)) {
                        throw "Can't find private key path"
                    }

                    # Grant permissions to the Service SID
                    $sqlSSID = "NT SERVICE\MSSQLSERVER"
                    if ($instance.InstanceName -ne "MSSQLSERVER") {
                        $sqlSSID = "NT SERVICE\MSSQL$" + $instance.InstanceName
                    }
                    $permission = $sqlSSID, "Read", "Allow"
                    $accessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $permission
                    try {
                        $acl = Get-Acl -Path $keyFullPath -ErrorAction Stop
                        $null = $acl.AddAccessRule($accessRule)
                        Set-Acl -Path $keyFullPath -AclObject $acl -ErrorAction Stop
                    } catch {
                        throw "Failed to set read permissions on certificate private key: $_"
                    }

                    Set-ItemProperty -Path $regPath -Name Certificate -Value $thumbprint.ToLowerInvariant() # to make it compat with SQL config
                } else {
                    $verbose += "No certificate thumbprint provided, unsetting certificate configuration"

                    Set-ItemProperty -Path $regPath -Name Certificate -Value $null
                }
            } catch {
                $exception = $_
            }

            [PSCustomObject]@{
                Verbose   = $verbose
                Exception = $exception
            }
        }
    }
    process {
        # Registry access

        if (Test-FunctionInterrupt) { return }

        if ($UnsetCertificate -and ($Thumbprint -or $Certificate)) {
            Stop-Function -Message "-UnsetCertificate cannot be used with -Thumbprint or -Certificate."
            return
        }

        if ($Thumbprint -and $Thumbprint -notmatch '^[0-9A-Fa-f]{40}$') {
            Stop-Function -Message "The thumbprint must be a 40-character hexadecimal string (no spaces)."
            return
        }

        if ($Certificate) {
            Write-Message -Level Verbose -Message "Getting thumbprint"
            $Thumbprint = $Certificate.Thumbprint
        }

        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Processing $instance" -Target $instance
            # Using Test-DbaNetworkCertificate without certificate will use Get-DbaNetworkConfiguration to get all the information we need.
            # The commands also tests for elevation requirements and connectivity so we don't have to here.
            try {
                $splatTest = @{
                    SqlInstance     = $instance
                    Credential      = $Credential
                    EnableException = $true
                }
                $certTest = Test-DbaNetworkCertificate @splatTest
                $oldThumbprint = $certTest.ConfiguredCertificateThumbprint
            } catch {
                Stop-Function -Message "Failed to use Test-DbaNetworkCertificate to get information for $instance" -Target $instance -ErrorRecord $_ -Continue
            }

            if ($UnsetCertificate) {
                if (-not $certTest.ConfiguredCertificateThumbprint) {
                    Write-Message -Level Verbose -Message "There is no certificate configured for $instance"
                    [PSCustomObject]@{
                        ComputerName          = $certTest.ComputerName
                        InstanceName          = $certTest.InstanceName
                        SqlInstance           = $certTest.SqlInstance
                        CertificateThumbprint = $null
                        Notes                 = 'No changes needed'
                    }
                    continue
                } else {
                    Write-Message -Level Verbose -Message "Certificate $oldThumbprint will be unset for $instance"
                    $newThumbprint = $null
                }
            } elseif ($Thumbprint) {
                if ($Thumbprint -eq $oldThumbprint -and $certTest.ConfiguredCertificateValid) {
                    Write-Message -Level Verbose -Message "Certificate $oldThumbprint was already configured for $instance"
                    [PSCustomObject]@{
                        ComputerName          = $certTest.ComputerName
                        InstanceName          = $certTest.InstanceName
                        SqlInstance           = $certTest.SqlInstance
                        CertificateThumbprint = $oldThumbprint
                        Notes                 = 'No changes needed'
                    }
                    continue
                } elseif ($Thumbprint -in $certTest.SuitableCertificates.Thumbprint) {
                    Write-Message -Level Verbose -Message "Certificate $Thumbprint is suitable for $instance"
                    $newThumbprint = $Thumbprint
                } else {
                    Write-Message -Level Verbose -Message "Validating certificate $Thumbprint for $instance using Test-DbaNetworkCertificate"
                    try {
                        $splatTest = @{
                            SqlInstance     = $instance
                            Credential      = $Credential
                            Thumbprint      = $Thumbprint
                            EnableException = $true
                        }
                        $detailedCertTest = Test-DbaNetworkCertificate @splatTest
                    } catch {
                        Stop-Function -Message "Failed to validate certificate $Thumbprint for $instance" -Target $instance -ErrorRecord $_ -Continue
                    }

                    $failedChecks = @()
                    if (-not $detailedCertTest.CertificateFound) { $failedChecks += "CertificateNotFound" }
                    if ($detailedCertTest.CertificateFound -and -not $detailedCertTest.KeyUsagesValid) { $failedChecks += "KeyUsagesInvalid" }
                    if ($detailedCertTest.CertificateFound -and -not $detailedCertTest.DnsNamesValid) { $failedChecks += "DnsNamesInvalid" }
                    if ($detailedCertTest.CertificateFound -and -not $detailedCertTest.PrivateKeyValid) { $failedChecks += "PrivateKeyInvalid" }
                    if ($detailedCertTest.CertificateFound -and -not $detailedCertTest.PublicKeyValid) { $failedChecks += "PublicKeyInvalid" }
                    if ($detailedCertTest.CertificateFound -and -not $detailedCertTest.SignatureAlgorithmValid) { $failedChecks += "SignatureAlgorithmInvalid" }
                    if ($detailedCertTest.CertificateFound -and -not $detailedCertTest.EnhancedKeyUsageValid) { $failedChecks += "EnhancedKeyUsageInvalid" }
                    if ($detailedCertTest.CertificateFound -and -not $detailedCertTest.ValidityPeriodOk) { $failedChecks += "ValidityPeriodExpiredOrInsufficient" }
                    Stop-Function -Message "Certificate $Thumbprint is not suitable for SQL Server network encryption on $instance. Failed checks: $($failedChecks -join ', ')." -Target $instance -Continue
                }
            } else {
                if ($certTest.ConfiguredCertificateValid) {
                    Write-Message -Level Verbose -Message "Certificate $oldThumbprint was already configured for $instance"
                    [PSCustomObject]@{
                        ComputerName          = $certTest.ComputerName
                        InstanceName          = $certTest.InstanceName
                        SqlInstance           = $certTest.SqlInstance
                        CertificateThumbprint = $oldThumbprint
                        Notes                 = 'No changes needed'
                    }
                    continue
                } elseif ($certTest.SuitableCertificateAvailable -and $certTest.SuitableCertificateCount -eq 1) {
                    $newThumbprint = $certTest.SuitableCertificates.Thumbprint
                    Write-Message -Level Verbose -Message "Certificate $newThumbprint was selected for $instance"
                } elseif ($certTest.SuitableCertificateAvailable) {
                    Stop-Function -Message "More than one suitable certificate found on $instance. Please use -Thumbprint." -Target $instance -Continue
                } else {
                    Stop-Function -Message "No suitable certificate found on $instance. Please use New-DbaComputerCertificate to create one." -Target $instance -Continue
                }
            }

            if ($UnsetCertificate) {
                $message = "Unsetting certificate $oldThumbprint"
            } else {
                $message = "Configuring certificate $newThumbprint"
            }
            if ($PScmdlet.ShouldProcess($instance, $message)) {
                $result = Invoke-Command2 -ScriptBlock $scriptBlock -ArgumentList $instance, $newThumbprint -ComputerName $($certTest.ComputerName) -Credential $Credential -ErrorAction Stop
                foreach ($verbose in $result.Verbose) {
                    Write-Message -Level Verbose -Message $verbose
                }
                if ($result.Exception) {
                    # The new code pattern for WMI calls is used where all exceptions are catched and return as part of an object.
                    Write-Message -Level Verbose -Message "Execution against $($certTest.ComputerName) failed with: $($result.Exception)"
                    if ($UnsetCertificate) {
                        $message = "Failed to unset certificate $oldThumbprint for instance $instance."
                    } else {
                        $message = "Failed to configure certificate $newThumbprint for instance $instance."
                    }
                    Stop-Function -Message $message -Target $instance -ErrorRecord $result.Exception -Continue
                }

                $notes = $null
                if ($RestartService) {
                    try {
                        $null = Restart-DbaService -SqlInstance $instance -Type Engine -Force -EnableException
                    } catch {
                        $notes = "Failed to restart service"
                        Write-Message -Level Warning -Message "$notes for instance $instance."
                    }
                } else {
                    if ($UnsetCertificate) {
                        $notes = "Certificate removal will not take effect until SQL Server service is restarted"
                    } else {
                        $notes = "New certificate will not take effect until SQL Server service is restarted"
                    }
                    Write-Message -Level Warning -Message "$notes for instance $instance"
                }

                [PSCustomObject]@{
                    ComputerName          = $certTest.ComputerName
                    InstanceName          = $certTest.InstanceName
                    SqlInstance           = $certTest.SqlInstance
                    CertificateThumbprint = $newThumbprint
                    Notes                 = $notes
                }
            }
        }
    }
}