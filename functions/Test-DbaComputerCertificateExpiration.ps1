function Test-DbaComputerCertificateExpiration {
    <#
    .SYNOPSIS
        Tests for certificates that are expiring soon

    .DESCRIPTION
        Tests for certificates that are expiring soon

        By default, it tests candidates that are ideal for using with SQL Server's network encryption

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
        Number of days before expiration to warn

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate
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
            try {
                if ($Type -eq "SQL Server") {
                    $certs = Get-DbaNetworkCertificate -ComputerName $computer -Credential $Credential -EnableException:$true
                } else {
                    $parms = $PSBoundParameters
                    $null = $parms.Remove("ComputerName")
                    $null = $parms.Remove("Threshold")
                    $null = $parms.Remove("EnableException")
                    $certs = Get-DbaComputerCertificate @parms -EnableException:$true
                }

                foreach ($cert in $certs) {
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