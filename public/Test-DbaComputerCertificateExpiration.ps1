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
        Specifies the certificate store to scan for certificates. Defaults to LocalMachine which contains system-wide certificates.
        Use this when you need to check certificates in different stores like CurrentUser for user-specific certificates.

    .PARAMETER Folder
        Specifies the certificate folder within the store to examine. Defaults to My (Personal) where SSL certificates are typically stored.
        Common folders include My for personal certificates, Root for trusted root authorities, and CA for intermediate certificate authorities.

    .PARAMETER Path
        Specifies the file system path to a specific certificate file to examine instead of scanning certificate stores.
        Use this when you have certificate files (.cer, .crt, .pfx) on disk that you want to check for expiration.

    .PARAMETER Type
        Determines which certificates to examine based on their intended use. Defaults to Service which finds certificates suitable for SQL Server.
        Service finds certificates that meet SQL Server's requirements but may also be used by other services like IIS. SQL Server returns only certificates currently configured for use by SQL Server instances. All examines every certificate in the specified store regardless of suitability.

    .PARAMETER Thumbprint
        Filters results to certificates matching the specified thumbprint values. Accepts multiple thumbprints as an array.
        Use this when you need to check specific certificates you've identified through other means or are monitoring for compliance.

    .PARAMETER Threshold
        Sets the number of days before expiration to trigger a warning. Defaults to 30 days.
        Adjust this based on your certificate renewal process - use 90 days if you need longer lead times for procurement and testing.

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

    .OUTPUTS
        System.Security.Cryptography.X509Certificates.X509Certificate2

        Returns certificate objects from either Get-DbaNetworkCertificate or Get-DbaComputerCertificate for any certificates that are expired or will expire within the threshold period. If no certificates meet the expiration criteria, nothing is returned.

        Displayed properties (via Select-DefaultView):
        - ComputerName: The name of the computer where the certificate is stored
        - Store: The certificate store location (LocalMachine, CurrentUser, etc.)
        - Folder: The certificate folder within the store (My, Root, CA, etc.)
        - Name: The friendly name of the certificate
        - DnsNameList: Array of DNS names associated with the certificate (Subject Alternative Names)
        - Thumbprint: The SHA-1 hash of the certificate used for identification
        - NotBefore: DateTime when the certificate becomes valid (validity start date)
        - NotAfter: DateTime when the certificate expires (validity end date)
        - Subject: The certificate subject Distinguished Name (DN)
        - Issuer: The certificate issuer Distinguished Name (DN)
        - Algorithm: The signature algorithm used by the certificate (e.g., sha256RSA)
        - ExpiredOrExpiring: Boolean value indicating the certificate is expired or expiring (always $true for returned objects)
        - Note: Human-readable description of the expiration status (e.g., "This certificate expires in 15 days" or "This certificate has expired and is no longer valid")

        All standard X.509 certificate properties are accessible using Select-Object *.

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