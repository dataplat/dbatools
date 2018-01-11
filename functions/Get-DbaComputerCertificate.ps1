function Get-DbaComputerCertificate {
    <#
    .SYNOPSIS
        Simplifies finding computer certificates that are candidates for using with SQL Server's network encryption

    .DESCRIPTION
        Gets computer certificates on localhost that are candidates for using with SQL Server's network encryption

    .PARAMETER ComputerName
        The target SQL Server - defaults to localhost. If target is a cluster, you must specify the distinct nodes.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials.

    .PARAMETER Store
        Certificate store - defaults to LocalMachine

    .PARAMETER Folder
        Certificate folder - defaults to My (Personal)

    .PARAMETER Path
        The path to a certificate - basically changes the path into a certificate object

    .PARAMETER Thumbprint
        Return certificate based on thumbprint

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        Get-DbaComputerCertificate
        Gets computer certificates on localhost that are candidates for using with SQL Server's network encryption

    .EXAMPLE
        Get-DbaComputerCertificate -ComputerName sql2016

        Gets computer certificates on sql2016 that are candidates for using with SQL Server's network encryption

    .EXAMPLE
        Get-DbaComputerCertificate -ComputerName sql2016 -Thumbprint 8123472E32AB412ED4288888B83811DB8F504DED, 04BFF8B3679BB01A986E097868D8D494D70A46D6

        Gets computer certificates on sql2016 that match thumbprints 8123472E32AB412ED4288888B83811DB8F504DED or 04BFF8B3679BB01A986E097868D8D494D70A46D6

    .NOTES
        Tags: Certificate

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
#>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)][Alias("ServerInstance", "SqlServer", "SqlInstance")][DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [string]$Store = "LocalMachine",
        [string]$Folder = "My",
        [string]$Path,
        [string[]]$Thumbprint,
        [switch][Alias('Silent')]$EnableException
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

            if ($Thumbprint) {
                try {
                    Write-Verbose "Searching Cert:\$Store\$Folder"
                    Get-ChildItem "Cert:\$Store\$Folder" -Recurse | Where-Object Thumbprint -in $Thumbprint
                }
                catch {
                    # don't care - there's a weird issue with remoting where an exception gets thrown for no apparent reason
                }
            }
            else {
                try {
                    Write-Verbose "Searching Cert:\$Store\$Folder"
                    Get-ChildItem "Cert:\$Store\$Folder" -Recurse | Where-Object { "$($_.EnhancedKeyUsageList)" -match '1\.3\.6\.1\.5\.5\.7\.3\.1' }
                }
                catch {
                    # still don't care
                }
            }
        }
        #endregion Scriptblock for remoting
    }

    process {
        foreach ($computer in $computername) {


            try {
                Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptblock -ArgumentList $thumbprint, $Store, $Folder, $Path -ErrorAction Stop |
                    Select-DefaultView -Property FriendlyName, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer
            }
            catch {
                Stop-Function -Message $_ -ErrorRecord $_ -Target $computer -Continue
            }
        }
    }
}
