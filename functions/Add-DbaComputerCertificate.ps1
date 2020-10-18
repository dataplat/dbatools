function Add-DbaComputerCertificate {
    <#
    .SYNOPSIS
        Adds a computer certificate - useful for older systems.

    .DESCRIPTION
        Adds a computer certificate from a local or remote computer.

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

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Certificate
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
        [switch]$EnableException
    )

    begin {

        if ($Path) {
            if (!(Test-Path -Path $Path)) {
                Stop-Function -Message "Path ($Path) does not exist." -Category InvalidArgument
                return
            }

            try {
                # This may be too much, but oh well
                $bytes = [System.IO.File]::ReadAllBytes($Path)
                $Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                $Certificate.Import($bytes, $SecurePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
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

                $Folder
            )

            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            $cert.Import($CertificateData, $SecurePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
            Write-Message -Level Verbose -Message "Importing cert to $Folder\$Store"
            $tempStore = New-Object System.Security.Cryptography.X509Certificates.X509Store($Folder, $Store)
            $tempStore.Open('ReadWrite')
            $tempStore.Add($cert)
            $tempStore.Close()

            Write-Message -Level Verbose -Message "Searching Cert:\$Store\$Folder"
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

                if ($PSCmdlet.ShouldProcess("local", "Connecting to $computer to import cert")) {
                    try {
                        Invoke-Command2 -ComputerName $computer -Credential $Credential -ArgumentList $certdata, $SecurePassword, $Store, $Folder -ScriptBlock $scriptBlock -ErrorAction Stop |
                            Select-DefaultView -Property FriendlyName, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
                    }
                }
            }
        }
    }
}