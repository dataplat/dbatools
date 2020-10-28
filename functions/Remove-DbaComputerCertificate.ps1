function Remove-DbaComputerCertificate {
    <#
    .SYNOPSIS
        Removes a computer certificate - useful for removing easily certs from remote computers

    .DESCRIPTION
        Removes a computer certificate from a local or remote compuer

    .PARAMETER ComputerName
        The target computer. Defaults to localhost.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials

    .PARAMETER Thumbprint
        The thumbprint of the certificate object

    .PARAMETER Store
        Certificate store - defaults to LocalMachine (otherwise exceptions can be thrown on remote connections)

    .PARAMETER Folder
        Certificate folder

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .NOTES
        Tags: Certificate
        Author: Chrissy LeMaire (@cl), netnerds.net
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaComputerCertificate

    .EXAMPLE
        PS C:\> Remove-DbaComputerCertificate -ComputerName Server1 -Thumbprint C2BBE81A94FEE7A26FFF86C2DFDAF6BFD28C6C94

        Removes certificate with thumbprint C2BBE81A94FEE7A26FFF86C2DFDAF6BFD28C6C94 in the LocalMachine store on Server1

    .EXAMPLE
        PS C:\> Get-DbaComputerCertificate | Where-Object Thumbprint -eq E0A071E387396723C45E92D42B2D497C6A182340 | Remove-DbaComputerCertificate

        Removes certificate using the pipeline

    .EXAMPLE
        PS C:\> Remove-DbaComputerCertificate -ComputerName Server1 -Thumbprint C2BBE81A94FEE7A26FFF86C2DFDAF6BFD28C6C94 -Store User -Folder My

        Removes certificate with thumbprint C2BBE81A94FEE7A26FFF86C2DFDAF6BFD28C6C94 in the User\My (Personal) store on Server1

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [parameter(ValueFromPipelineByPropertyName, Mandatory)]
        [string[]]$Thumbprint,
        [string]$Store = "LocalMachine",
        [string]$Folder = "My",
        [switch]$EnableException
    )

    begin {
        #region Scriptblock for remoting
        $scriptBlock = {
            param (
                $Thumbprint,
                $Store,
                $Folder
            )
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose "Searching Cert:\$Store\$Folder for thumbprint: $thumbprint"
            function Get-CoreCertStore {
                [CmdletBinding()]
                param (
                    [ValidateSet("CurrentUser", "LocalMachine")]
                    [string]$Store,
                    [ValidateSet("AddressBook", "AuthRoot, CertificateAuthority", "Disallowed", "My", "Root", "TrustedPeople", "TrustedPublisher")]
                    [string]$Folder,
                    [ValidateSet("ReadOnly", "ReadWrite")]
                    [string]$Flag = "ReadOnly"
                )

                $storename = [System.Security.Cryptography.X509Certificates.StoreLocation]::$Store
                $foldername = [System.Security.Cryptography.X509Certificates.StoreName]::$Folder
                $flags = [System.Security.Cryptography.X509Certificates.OpenFlags]::$Flag
                $certstore = [System.Security.Cryptography.X509Certificates.X509Store]::New($foldername, $storename)
                $certstore.Open($flags)

                $certstore
            }

            function Get-CoreCertificate {
                [CmdletBinding()]
                param (
                    [ValidateSet("CurrentUser", "LocalMachine")]
                    [string]$Store,
                    [ValidateSet("AddressBook", "AuthRoot, CertificateAuthority", "Disallowed", "My", "Root", "TrustedPeople", "TrustedPublisher")]
                    [string]$Folder,
                    [ValidateSet("ReadOnly", "ReadWrite")]
                    [string]$Flag = "ReadOnly",
                    [string[]]$Thumbprint,
                    [System.Security.Cryptography.X509Certificates.X509Store[]]$InputObject
                )

                if (-not $InputObject) {
                    $InputObject += Get-CoreCertStore -Store $Store -Folder $Folder -Flag $Flag
                }

                $certs = ($InputObject).Certificates

                if ($Thumbprint) {
                    $certs = $certs | Where-Object Thumbprint -in $Thumbprint
                }
                $certs
            }

            if ($Thumbprint) {
                try {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Verbose "Searching Cert:\$Store\$Folder"
                    $cert = Get-CoreCertificate -Store $Store -Folder $Folder -Thumbprint $Thumbprint
                } catch {
                    # don't care - there's a weird issue with remoting where an exception gets thrown for no apparent reason
                    # here to avoid an empty catch
                    $null = 1
                }
            }

            if ($cert) {
                $certstore = Get-CoreCertStore -Store $Store -Folder $Folder -Flag ReadWrite
                $certstore.Remove($cert)
                $status = "Removed"
            } else {
                $status = "Certificate not found in Cert:\$Store\$Folder"
            }

            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                Store        = $Store
                Folder       = $Folder
                Thumbprint   = $thumbprint
                Status       = $status
            }
        }
        #endregion Scriptblock for remoting
    }

    process {
        foreach ($computer in $computername) {
            foreach ($thumb in $Thumbprint) {
                if ($PScmdlet.ShouldProcess("local", "Connecting to $computer to remove cert from Cert:\$Store\$Folder")) {
                    try {
                        Invoke-Command2 -ComputerName $computer -Credential $Credential -ArgumentList $thumb, $Store, $Folder -ScriptBlock $scriptBlock -ErrorAction Stop
                    } catch {
                        Stop-Function -Message $_ -ErrorRecord $_ -Target $computer -Continue
                    }
                }
            }
        }
    }
}