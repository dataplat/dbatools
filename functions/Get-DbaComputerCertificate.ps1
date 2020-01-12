function Get-DbaComputerCertificate {
    <#
    .SYNOPSIS
        Simplifies finding computer certificates that are candidates for using with SQL Server's network encryption

    .DESCRIPTION
        Gets computer certificates on localhost that are candidates for using with SQL Server's network encryption

    .PARAMETER ComputerName
        The target SQL Server instance or instances. Defaults to localhost. If target is a cluster, you must specify the distinct nodes.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials.

    .PARAMETER Store
        Certificate store - defaults to LocalMachine

    .PARAMETER Folder
        Certificate folder - defaults to My (Personal)

    .PARAMETER Path
        The path to a certificate - basically changes the path into a certificate object

    .PARAMETER Type
        The type of certificates to return. All or Service. Default is Service since this is SQL specific.

    .PARAMETER Thumbprint
        Return certificate based on thumbprint

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaComputerCertificate

    .EXAMPLE
        PS C:\> Get-DbaComputerCertificate

        Gets computer certificates on localhost that are candidates for using with SQL Server's network encryption

    .EXAMPLE
        PS C:\> Get-DbaComputerCertificate -ComputerName sql2016

        Gets computer certificates on sql2016 that are candidates for using with SQL Server's network encryption

    .EXAMPLE
        PS C:\> Get-DbaComputerCertificate -ComputerName sql2016 -Thumbprint 8123472E32AB412ED4288888B83811DB8F504DED, 04BFF8B3679BB01A986E097868D8D494D70A46D6

        Gets computer certificates on sql2016 that match thumbprints 8123472E32AB412ED4288888B83811DB8F504DED or 04BFF8B3679BB01A986E097868D8D494D70A46D6
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [string[]]$Store = "LocalMachine",
        [string[]]$Folder = "My",
        [ValidateSet("All", "Service")]
        [string]$Type = "Service",
        [string]$Path,
        [string[]]$Thumbprint,
        [switch]$EnableException
    )

    begin {
        #region Scriptblock for remoting
        $scriptblock = {
            param (
                $Thumbprint,
                $Store,
                $Folder,
                $Path
            )

            if ($Path) {
                $bytes = [System.IO.File]::ReadAllBytes($path)
                $Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                $Certificate.Import($bytes, $null, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
                return $Certificate
            }

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

                foreach ($c in $certs) {
                    Add-Member -Force -InputObject $c -NotePropertyName Algorithm -NotePropertyValue $c.SignatureAlgorithm.FriendlyName
                    Add-Member -Force -InputObject $c -NotePropertyName ComputerName -NotePropertyValue $env:ComputerName
                    # had to add Name because remotely, "FriendlyName" refused to work. no idea why.
                    Add-Member -Force -InputObject $c -NotePropertyName Name -NotePropertyValue $c.FriendlyName.ToString()
                    Add-Member -Force -InputObject $c -NotePropertyName Store -NotePropertyValue $Store
                    Add-Member -Force -InputObject $c -NotePropertyName Folder -NotePropertyValue $Folder -Passthru
                }
            }

            if ($Thumbprint) {
                try {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Verbose "Searching Cert:\$Store\$Folder"
                    Get-CoreCertificate -Store $Store -Folder $Folder -Thumbprint $Thumbprint
                } catch {
                    # don't care - there's a weird issue with remoting where an exception gets thrown for no apparent reason
                    # here to avoid an empty catch
                    $null = 1
                }
            } else {
                try {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Verbose "Searching Cert:\$Store\$Folder"
                    if ($Type -eq "Service") {
                        Get-CoreCertificate -Store $Store -Folder $Folder | Where-Object EnhancedKeyUsageList -match '1\.3\.6\.1\.5\.5\.7\.3\.1'
                    } else {
                        Get-CoreCertificate -Store $Store -Folder $Folder
                    }
                } catch {
                    # still don't care
                    # here to avoid an empty catch
                    $null = 1
                }
            }
        }
        #endregion Scriptblock for remoting
    }

    process {
        foreach ($computer in $computername) {
            if ($Store -eq "All") {
                try {
                    $Store = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock { Get-ChildItem Cert: | Select-Object -ExpandProperty Location } -Raw
                } catch {
                    Stop-Function -Message "Issue connecting to computer" -ErrorRecord $_ -Target $computer -Continue
                }
            }
            if ($Folder -eq "All") {
                try {
                    $Folder = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock { Get-ChildItem Cert: | Select-Object -ExpandProperty StoreNames | Select-Object -ExpandProperty Keys } -Raw
                } catch {
                    Stop-Function -Message "Issue connecting to computer" -ErrorRecord $_ -Target $computer -Continue
                }
            }
            foreach ($currentStore in $Store) {
                foreach ($currentFolder in $Folder) {
                    try {
                        Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptblock -ArgumentList $thumbprint, $currentStore, $currentFolder, $Path -ErrorAction Stop | Select-DefaultView -Property ComputerName, Store, Folder, Name, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer, Algorithm
                    } catch {
                        Stop-Function -Message "Issue connecting to computer" -ErrorRecord $_ -Target $computer -Continue
                    }
                }
            }
        }
    }
}