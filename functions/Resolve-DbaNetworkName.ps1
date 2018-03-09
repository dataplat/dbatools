function Resolve-DbaNetworkName {
    <#
        .SYNOPSIS
            Returns information about the network connection of the target computer including NetBIOS name, IP Address, domain name and fully qualified domain name (FQDN).

        .DESCRIPTION
            Retrieves the IPAddress, ComputerName from one computer.
            The object can be used to take action against its name or IPAddress.

            First ICMP is used to test the connection, and get the connected IPAddress.

            Multiple protocols (e.g. WMI, CIM, etc) are attempted before giving up.

            Important: Remember that FQDN doesn't always match "ComputerName dot Domain" as AD intends.
                There are network setup (google "disjoint domain") where AD and DNS do not match.
                "Full computer name" (as reported by sysdm.cpl) is the only match between the two,
                and it matches the "DNSHostName"  property of the computer object stored in AD.
                This means that the notation of FQDN that matches "ComputerName dot Domain" is incorrect
                in those scenarios.
                In other words, the "suffix" of the FQDN CAN be different from the AD Domain.

                This cmdlet has been providing good results since its inception but for lack of useful
                names some doubts may arise.
                Let this clear the doubts:
                - InputName: whatever has been passed in
                - ComputerName: hostname only
                - IPAddress: IP Address
                - DNSHostName: hostname only, coming strictly from DNS (as reported from the calling computer)
                - DNSDomain: domain only, coming strictly from DNS (as reported from the calling computer)
                - Domain: domain only, coming strictly from AD (i.e. the domain the ComputerName is joined to)
                - DNSHostEntry: Fully name as returned by DNS [System.Net.Dns]::GetHostEntry
                - FQDN: "legacy" notation of ComputerName "dot" Domain (coming from AD)
                - FullComputerName: Full name as configured from within the Computer (i.e. the only secure match between AD and DNS)

            So, if you need to use something, go with FullComputerName, always, as it is the most correct in every scenario.

        .PARAMETER ComputerName
            The Server that you're connecting to.
            This can be the name of a computer, a SMO object, an IP address or a SQL Instance.

        .PARAMETER Credential
            Credential object used to connect to the SQL Server as a different user

        .PARAMETER Turbo
            Resolves without accessing the server itself. Faster but may be less accurate because it relies on DNS only,
            so it may fail spectacularly for disjoin-domain setups. Also, everyone has its own DNS (i.e. results may vary
            changing the computer where the function runs)

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Network, Resolve
            Author: Klaas Vandenberghe ( @PowerDBAKlaas )
            Editor: niphlod

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Resolve-DbaNetworkName

        .EXAMPLE
            Resolve-DbaNetworkName -ComputerName ServerA

            Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, DNSDomain, Domain, DNSHostEntry, FQDN, DNSHostEntry for ServerA

        .EXAMPLE
            Resolve-DbaNetworkName -SqlInstance sql2016\sqlexpress

            Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, DNSDomain, Domain, DNSHostEntry, FQDN, DNSHostEntry  for the SQL instance sql2016\sqlexpress

        .EXAMPLE
            Resolve-DbaNetworkName -SqlInstance sql2016\sqlexpress, sql2014

            Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, DNSDomain, Domain, DNSHostEntry, FQDN, DNSHostEntry  for the SQL instance sql2016\sqlexpress and sql2014

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance sql2014 | Resolve-DbaNetworkName

            Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, Domain, FQDN for all SQL Servers returned by Get-DbaRegisteredServer
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [Alias('cn', 'host', 'ServerInstance', 'Server', 'SqlInstance')]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential] $Credential,
        [Alias('FastParrot')]
        [switch]$Turbo,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($Computer in $ComputerName) {
            $conn = $ipaddress = $null

            $OGComputer = $Computer

            if ($Computer.IsLocalhost) {
                $Computer = $env:COMPUTERNAME
            }
            else {
                $Computer = $Computer.ComputerName
            }

            if ($Turbo) {
                try {
                    Write-Message -Level VeryVerbose -Message "Resolving $Computer using .NET.Dns GetHostEntry"
                    $ipaddress = ([System.Net.Dns]::GetHostEntry($Computer)).AddressList[0].IPAddressToString
                    Write-Message -Level VeryVerbose -Message "Resolving $ipaddress using .NET.Dns GetHostByAddress"
                    $fqdn = [System.Net.Dns]::GetHostByAddress($ipaddress).HostName
                }
                catch {
                    try {
                        Write-Message -Level VeryVerbose -Message "Resolving $Computer and IP using .NET.Dns GetHostEntry"
                        $resolved = [System.Net.Dns]::GetHostEntry($Computer)
                        $ipaddress = $resolved.AddressList[0].IPAddressToString
                        $fqdn = $resolved.HostName
                    }
                    catch {
                        Stop-Function -Message "DNS name not found" -Continue -InnerErrorRecord $_
                    }
                }

                if ($fqdn -notmatch "\.") {
                    if ($computer.ComputerName -match "\.") {
                        $dnsdomain = $computer.ComputerName.Substring($computer.ComputerName.IndexOf(".") + 1)
                        $fqdn = "$resolved.$dnsdomain"
                    }
                    else {
                        $dnsdomain = "$env:USERDNSDOMAIN".ToLower()
                        if ($dnsdomain -match "\.") {
                            $fqdn = "$fqdn.$dnsdomain"
                        }
                    }
                }

                $hostname = $fqdn.Split(".")[0]

                [PSCustomObject]@{
                    InputName        = $OGComputer
                    ComputerName     = $hostname.ToUpper()
                    IPAddress        = $ipaddress
                    DNSHostname      = $hostname
                    DNSDomain        = $fqdn.Replace("$hostname.", "")
                    Domain           = $fqdn.Replace("$hostname.", "")
                    DNSHostEntry     = $fqdn
                    FQDN             = $fqdn
                    FullComputerName = $fqdn
                }

            }
            else {

                Write-Message -Level Verbose -Message "Connecting to $Computer"

                try {
                    $ipaddress = ((Test-Connection -ComputerName $Computer -Count 1 -ErrorAction Stop).Ipv4Address).IPAddressToString
                }
                catch {
                    try {
                        if ($env:USERDNSDOMAIN) {
                            $ipaddress = ((Test-Connection -ComputerName "$Computer.$env:USERDNSDOMAIN" -Count 1 -ErrorAction SilentlyContinue).Ipv4Address).IPAddressToString
                            $Computer = "$Computer.$env:USERDNSDOMAIN"
                        }
                    }
                    catch {
                        $Computer = $OGComputer
                        $ipaddress = ([System.Net.Dns]::GetHostEntry($Computer)).AddressList[0].IPAddressToString
                    }
                }

                if ($ipaddress) {
                    Write-Message -Level VeryVerbose -Message "IP Address from $Computer is $ipaddress"
                }
                else {
                    Write-Message -Level VeryVerbose -Message "No IP Address returned from $Computer"
                    Write-Message -Level VeryVerbose -Message "Using .NET.Dns to resolve IP Address"
                    return (Resolve-DbaNetworkName -ComputerName $Computer -Turbo)
                }

                if ($PSVersionTable.PSVersion.Major -gt 2) {
                    Write-Message -Level System -Message "Your PowerShell Version is $($PSVersionTable.PSVersion.Major)"
                    try {
                        try {
                            # if an alias (CNAME) is passed we should try to connect to the A name via CIM or WinRM
                            $ComputerNameIP = ([System.Net.Dns]::GetHostEntry($Computer)).AddressList[0].IPAddressToString
                            $RemoteComputer = [System.Net.Dns]::GetHostByAddress($ComputerNameIP).HostName
                        }
                        catch {
                            $RemoteComputer = $Computer
                        }
                        Write-Message -Level VeryVerbose -Message "Getting computer information from $RemoteComputer"
                        $ScBlock = {
                            $IPGProps = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
                            return [pscustomobject]@{
                                'DNSDomain' = $IPGProps.DomainName
                            }
                        }
                        if (Test-Bound "Credential") {
                            $conn = Get-DbaCmObject -ClassName win32_ComputerSystem -Computer $RemoteComputer -Credential $Credential -EnableException
                            $DNSSuffix = Invoke-Command2 -Computer $RemoteComputer -ScriptBlock $ScBlock -Credential $Credential -ErrorAction Stop
                        }
                        else {
                            $conn = Get-DbaCmObject -ClassName win32_ComputerSystem -Computer $RemoteComputer -EnableException
                            $DNSSuffix = Invoke-Command2 -Computer $RemoteComputer -ScriptBlock $ScBlock -ErrorAction Stop
                        }
                    }
                    catch {
                        Write-Message -Level Verbose -Message "Unable to get computer information from $Computer"
                    }

                    if (!$conn) {
                        Write-Message -Level Verbose -Message "No WMI/CIM from $Computer. Getting HostName via .NET.Dns"
                        try {
                            $fqdn = ([System.Net.Dns]::GetHostEntry($Computer)).HostName
                            $hostname = $fqdn.Split(".")[0]
                            $suffix = $fqdn.Replace("$hostname.", "")
                            if ($hostname -eq $fqdn) {
                                $suffix = ""
                            }
                            $conn = [PSCustomObject]@{
                                Name        = $Computer
                                DNSHostname = $hostname
                                Domain      = $suffix
                            }
                            $DNSSuffix = [PSCustomObject]@{
                                DNSDomain = $suffix
                            }
                        }
                        catch {
                            Stop-Function -Message "No .NET.Dns information from $Computer" -InnerErrorRecord $_ -Continue
                        }
                    }
                }
                if ($DNSSuffix.DNSDomain.Length -eq 0) {
                    $FullComputerName = $conn.DNSHostname
                }
                else {
                    $FullComputerName = $conn.DNSHostname + "." + $DNSSuffix.DNSDomain
                }
                try {
                    Write-Message -Level VeryVerbose -Message "Resolving $FullComputerName using .NET.Dns GetHostEntry"
                    $hostentry = ([System.Net.Dns]::GetHostEntry($FullComputerName)).HostName
                }
                catch {
                    Stop-Function -Message ".NET.Dns GetHostEntry failed for $FullComputerName" -InnerErrorRecord $_
                }

                $fqdn = "$($conn.DNSHostname).$($conn.Domain)"
                if ($fqdn -eq ".") {
                    Write-Message -Level VeryVerbose -Message "No full FQDN found. Setting to null"
                    $fqdn = $null
                }
                if ($FullComputerName -eq ".") {
                    Write-Message -Level VeryVerbose -Message "No DNS FQDN found. Setting to null"
                    $FullComputerName = $null
                }

                if ($FullComputerName -ne "." -and $FullComputerName -notmatch "\." -and $conn.Domain -match "\.") {
                    $d = $conn.Domain
                    $FullComputerName = "$FullComputerName.$d"
                }

                [PSCustomObject]@{
                    InputName        = $OGComputer
                    ComputerName     = $conn.Name
                    IPAddress        = $ipaddress
                    DNSHostName      = $conn.DNSHostname
                    DNSDomain        = $DNSSuffix.DNSDomain
                    Domain           = $conn.Domain
                    DNSHostEntry     = $hostentry
                    FQDN             = $fqdn.TrimEnd(".")
                    FullComputerName = $FullComputerName
                }
            }
        }
    }
}
