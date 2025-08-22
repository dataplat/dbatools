function Test-DbaComputerCertificateExpiration {
    <#
    .SYNOPSIS
        Identifies SSL/TLS certificates that are expired or expiring soon on SQL Server computers

    .DESCRIPTION
        Scans computer certificate stores to find certificates that are expired or will expire within a specified timeframe. This function focuses on certificates used for SQL Server network encryption, helping DBAs proactively identify potential connection failures before they occur.

        By default, it examines certificates that are candidates for SQL Server's network encryption feature. You can also check certificates currently in use by SQL Server instances or scan all certificates in the specified store. The function compares each certificate's expiration date against a configurable threshold (30 days by default) and returns detailed information about any certificates requiring attention.

        This is essential for maintaining secure SQL Server connections and preventing unexpected service disruptions caused by expired certificates.

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
        The type of certificates to return. All, Service or SQL Server.

        All is all certificates
        Service is certificates that are candidates for SQL Server services (But may be for IIS, etc)
        SQL Server is certificates currently in use by SQL Server

    .PARAMETER Thumbprint
        Return certificate based on thumbprint

    .PARAMETER Threshold
        Number of days before expiration to warn. Defaults to 30.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaComputerCertificateExpiration

    .EXAMPLE
        PS C:\> Test-DbaComputerCertificateExpiration

        Gets computer certificates on localhost that are candidates for using with SQL Server's network encryption then checks to see if they'll be expiring within 30 days

    .EXAMPLE
        PS C:\> Test-DbaComputerCertificateExpiration -ComputerName sql2016 -Threshold 90

        Gets computer certificates on sql2016 that are candidates for using with SQL Server's network encryption then checks to see if they'll be expiring within 90 days

    .EXAMPLE
        PS C:\> Test-DbaComputerCertificateExpiration -ComputerName sql2016 -Thumbprint 8123472E32AB412ED4288888B83811DB8F504DED, 04BFF8B3679BB01A986E097868D8D494D70A46D6

        Gets computer certificates on sql2016 that match thumbprints 8123472E32AB412ED4288888B83811DB8F504DED or 04BFF8B3679BB01A986E097868D8D494D70A46D6 then checks to see if they'll be expiring within 30 days
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [string[]]$Store = "LocalMachine",
        [string[]]$Folder = "My",
        [ValidateSet("All", "Service", "SQL Server")]
        [string]$Type = "Service",
        [string]$Path,
        [string[]]$Thumbprint,
        [int]$Threshold = 30,
        [switch]$EnableException
    )
    process {
        foreach ($computer in $computername) {
            Write-Message -Level Verbose "Processing $computer"
            try {
                if ($Type -eq "SQL Server") {
                    Write-Message -Level Verbose "Type is SQL Server, getting network SQL Server-only certificate"
                    $certs = Get-DbaNetworkCertificate -ComputerName $computer -Credential $Credential -EnableException:$true
                } else {
                    Write-Message -Level Verbose "Type is Service, getting all computer certificates on $computer"
                    $parms = @{
                        ComputerName    = $computer
                        Store           = $Store
                        Folder          = $Folder
                        EnableException = $true
                    }
                    if ($Credential) {
                        $parms.Credential = $Credential
                    }
                    if ($Path) {
                        $parms.Path = $Path
                    }
                    if ($Thumbprint) {
                        $parms.Thumbprint = $Thumbprint
                    }

                    $certs = Get-DbaComputerCertificate @parms
                }

                Write-Message -Level Verbose "Found $($certs.Name.Count) certificates"
                foreach ($cert in $certs) {
                    Write-Message -Level Verbose "Checking $($cert.Name) cert"
                    $expiration = $cert.NotAfter.Date.Subtract((Get-Date)).Days
                    if ($expiration -lt $Threshold) {
                        if ($cert.NotAfter -le (Get-Date)) {
                            $note = "This certificate has expired and is no longer valid"
                        } else {
                            $note = "This certificate expires in $expiration days"
                        }
                        $cert | Add-Member -NotePropertyName ExpiredOrExpiring -NotePropertyValue $true
                        $cert | Add-Member -NotePropertyName Note -NotePropertyValue $note
                        $cert | Select-DefaultView -Property ComputerName, Store, Folder, Name, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer, Algorithm, ExpiredOrExpiring, Note
                    }
                }
            } catch {
                Stop-Function -Message "Failure for $computer" -ErrorRecord $_
            }
        }
    }
}