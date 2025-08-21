function Add-DbaComputerCertificate {
    <#
    .SYNOPSIS
        Imports X.509 certificates into the Windows certificate store on local or remote computers.

    .DESCRIPTION
        Imports X.509 certificates (including password-protected .pfx files with private keys) into the specified Windows certificate store on one or more computers. This function is essential for SQL Server TLS/SSL encryption setup, Availability Group certificate requirements, and Service Broker security configurations. 
        
        The function handles both certificate files from disk and certificate objects from the pipeline, supports remote installation via PowerShell remoting, and allows you to control import behavior through various flags like exportable/non-exportable private keys. By default, certificates are installed to the LocalMachine\My (Personal) store with exportable and persistent private keys, which is the standard location for SQL Server service certificates.

    .PARAMETER ComputerName
        The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials.

    .PARAMETER SecurePassword
        The password for the certificate, if it is password protected.

    .PARAMETER Certificate
        The target certificate object.

    .PARAMETER Path
        The local path to the target certificate object.

    .PARAMETER Store
        Certificate store. Default is LocalMachine.

    .PARAMETER Folder
        Certificate folder. Default is My (Personal).

    .PARAMETER Flag
        Defines where and how to import the private key of an X.509 certificate.

        Defaults to: Exportable, PersistKeySet

            EphemeralKeySet
            The key associated with a PFX file is created in memory and not persisted on disk when importing a certificate.

            Exportable
            Imported keys are marked as exportable.

            NonExportable
            Expliictly mark keys as nonexportable.

            PersistKeySet
            The key associated with a PFX file is persisted when importing a certificate.

            UserProtected
            Notify the user through a dialog box or other method that the key is accessed. The Cryptographic Service Provider (CSP) in use defines the precise behavior. NOTE: This can only be used when you add a certificate to localhost, as it causes a prompt to appear.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Add-DbaComputerCertificate

    .EXAMPLE
        PS C:\> Add-DbaComputerCertificate -ComputerName Server1 -Path C:\temp\cert.cer

        Adds the local C:\temp\cert.cer to the remote server Server1 in LocalMachine\My (Personal).

    .EXAMPLE
        PS C:\> Add-DbaComputerCertificate -Path C:\temp\cert.cer

        Adds the local C:\temp\cert.cer to the local computer's LocalMachine\My (Personal) certificate store.

    .EXAMPLE
        PS C:\> Add-DbaComputerCertificate -Path C:\temp\cert.cer

        Adds the local C:\temp\cert.cer to the local computer's LocalMachine\My (Personal) certificate store.

    .EXAMPLE
        PS C:\> Add-DbaComputerCertificate -ComputerName sql01 -Path C:\temp\sql01.pfx -Confirm:$false -Flag NonExportable

        Adds the local C:\temp\sql01.pfx to sql01's LocalMachine\My (Personal) certificate store and marks the private key as non-exportable. Skips confirmation prompt.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Alias("Password")]
        [SecureString]$SecurePassword,
        [parameter(ValueFromPipeline)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2[]]$Certificate,
        [string]$Path,
        [string]$Store = "LocalMachine",
        [string]$Folder = "My",
        [ValidateSet("EphemeralKeySet", "Exportable", "PersistKeySet", "UserProtected", "NonExportable")]
        [string[]]$Flag = @("Exportable", "PersistKeySet"),
        [switch]$EnableException
    )
    begin {
        if ("NonExportable" -in $Flag) {
            $flags = ($Flag | Where-Object { $PSItem -ne "Exportable" -and $PSItem -ne "NonExportable" } ) -join ","

            # It needs at least one flag
            if (-not $flags) {
                if ($Store -eq "LocalMachine") {
                    $flags = "MachineKeySet"
                } else {
                    $flags = "UserKeySet"
                }
            }
        } else {
            $flags = $Flag -join ","
        }

        Write-Message -Level Verbose -Message "Flags: $flags"
        if ($Path) {
            if (-not (Test-Path -Path $Path)) {
                Stop-Function -Message "Path ($Path) does not exist." -Category InvalidArgument
                return
            }

            try {
                # local has to be exportable to export to remote
                $bytes = [System.IO.File]::ReadAllBytes($Path)
                $Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                $null = $Certificate.Import($bytes, $SecurePassword, "Exportable, PersistKeySet")
            } catch {
                Stop-Function -Message "Can't import certificate." -ErrorRecord $_
                return
            }
        }

        #region Remoting Script
        $scriptBlock = {
            param (
                $CertificateData,
                [SecureString]$SecurePassword,
                $Store,
                $Folder,
                $flags
            )

            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            $cert.Import($CertificateData, $SecurePassword, $flags)
            Write-Verbose -Message "Importing cert to $Folder\$Store using flags: $flags"
            $tempStore = New-Object System.Security.Cryptography.X509Certificates.X509Store($Folder, $Store)
            $tempStore.Open('ReadWrite')
            $tempStore.Add($cert)
            $tempStore.Close()

            Write-Verbose -Message "Searching Cert:\$Store\$Folder"
            Get-ChildItem "Cert:\$Store\$Folder" -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
        }
        #endregion Remoting Script
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $Certificate) {
            Stop-Function -Message "You must specify either Certificate or Path" -Category InvalidArgument
            return
        }

        foreach ($cert in $Certificate) {
            try {
                $certData = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::PFX, $SecurePassword)
            } catch {
                Stop-Function -Message "Can't export certificate" -ErrorRecord $_ -Continue
            }

            foreach ($computer in $ComputerName) {
                if ($PSCmdlet.ShouldProcess("$computer", "Attempting to import cert")) {
                    if ($flags -contains "UserProtected" -and -not $computer.IsLocalHost) {
                        Stop-Function -Message "UserProtected flag is only valid for localhost because it causes a prompt, skipping for $computer" -Continue
                    }
                    try {
                        Invoke-Command2 -ComputerName $computer -Credential $Credential -ArgumentList $certdata, $SecurePassword, $Store, $Folder, $flags -ScriptBlock $scriptBlock -ErrorAction Stop |
                            Select-DefaultView -Property FriendlyName, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
                    }
                }
            }
        }
    }
}