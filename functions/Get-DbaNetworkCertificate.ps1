function Get-DbaNetworkCertificate {
    <#
    .SYNOPSIS
        Gets the computer certificate enabled for the SQL Server instance's network encryption.

    .DESCRIPTION
        Gets the computer certificates that is assigned to the SQL Server instance for enabling network encryption.

    .PARAMETER ComputerName
        The target SQL Server instance or instances. Defaults to localhost. If target is a cluster, you must specify the distinct nodes.

    .PARAMETER Credential
        Alternate credential object to use for accessing the target computer(s).

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Encryption
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaNetworkCertificate

    .EXAMPLE
        PS C:\> Get-DbaNetworkCertificate

        Gets computer certificates on localhost that are candidates for using with SQL Server's network encryption

    .EXAMPLE
        PS C:\> Get-DbaNetworkCertificate -ComputerName sql2016

        Gets computer certificates on sql2016 that are being used for SQL Server network encryption
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    process {
        # Registry access
        foreach ($computer in $computername) {
            try {
                $sqlwmis = Invoke-ManagedComputerCommand -ComputerName $computer.ComputerName -ScriptBlock { $wmi.Services } -Credential $Credential -ErrorAction Stop | Where-Object DisplayName -match "SQL Server \("
            } catch {
                Stop-Function -Message $_ -Target $sqlwmi -Continue
            }

            foreach ($sqlwmi in $sqlwmis) {
                $regRoot = ($sqlwmi.AdvancedProperties | Where-Object Name -eq REGROOT).Value
                $vsname = ($sqlwmi.AdvancedProperties | Where-Object Name -eq VSNAME).Value
                $instanceName = $sqlwmi.DisplayName.Replace('SQL Server (', '').Replace(')', '') # Don't clown, I don't know regex :(
                $serviceAccount = $sqlwmi.ServiceAccount

                if ([System.String]::IsNullOrEmpty($regRoot)) {
                    $regRoot = $sqlwmi.AdvancedProperties | Where-Object { $_ -match 'REGROOT' }
                    $vsname = $sqlwmi.AdvancedProperties | Where-Object { $_ -match 'VSNAME' }

                    if (![System.String]::IsNullOrEmpty($regRoot)) {
                        $regRoot = ($regRoot -Split 'Value\=')[1]
                        $vsname = ($vsname -Split 'Value\=')[1]
                    } else {
                        Write-Message -Level Warning -Message "Can't find instance $vsname on $env:COMPUTERNAME"
                        return
                    }
                }

                if ([System.String]::IsNullOrEmpty($vsname)) { $vsname = $computer }

                Write-Message -Level Verbose -Message "Regroot: $regRoot"
                Write-Message -Level Verbose -Message "ServiceAcct: $serviceAccount"
                Write-Message -Level Verbose -Message "InstanceName: $instanceName"
                Write-Message -Level Verbose -Message "VSNAME: $vsname"

                $scriptBlock = {
                    $regRoot = $args[0]
                    $serviceAccount = $args[1]
                    $instanceName = $args[2]
                    $vsname = $args[3]

                    $regPath = "Registry::HKEY_LOCAL_MACHINE\$regRoot\MSSQLServer\SuperSocketNetLib"

                    $thumbprint = (Get-ItemProperty -Path $regPath -Name Certificate -ErrorAction SilentlyContinue).Certificate

                    try {
                        $cert = Get-ChildItem Cert:\LocalMachine -Recurse -ErrorAction Stop | Where-Object Thumbprint -eq $Thumbprint
                    } catch {
                        # Don't care - sometimes there's errors that are thrown for apparent good reason
                        # here to avoid an empty catch
                        $null = 1
                    }

                    if (!$cert) { continue }

                    [pscustomobject]@{
                        ComputerName   = $env:COMPUTERNAME
                        InstanceName   = $instanceName
                        SqlInstance    = $vsname
                        ServiceAccount = $serviceAccount
                        FriendlyName   = $cert.FriendlyName
                        DnsNameList    = $cert.DnsNameList
                        Thumbprint     = $cert.Thumbprint
                        Generated      = $cert.NotBefore
                        Expires        = $cert.NotAfter
                        IssuedTo       = $cert.Subject
                        IssuedBy       = $cert.Issuer
                        Certificate    = $cert
                    }
                }

                try {
                    Invoke-Command2 -ComputerName $computer.ComputerName -Credential $Credential -ArgumentList $regRoot, $serviceAccount, $instanceName, $vsname -ScriptBlock $scriptBlock -ErrorAction Stop | Select-DefaultView -ExcludeProperty Certificate
                } catch {
                    Stop-Function -Message $_ -ErrorRecord $_ -Target $ComputerName -Continue
                }
            }
        }
    }
}