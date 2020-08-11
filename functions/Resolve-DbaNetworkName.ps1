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
        The target SQL Server instance or instances.
        This can be the name of a computer, a SMO object, an IP address or a SQL Instance.

    .PARAMETER Credential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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
        Author: Klaas Vandenberghe (@PowerDBAKlaas) | Simone Bizzotto (@niphold)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Resolve-DbaNetworkName

    .EXAMPLE
        PS C:\> Resolve-DbaNetworkName -ComputerName sql2014

        Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, DNSDomain, Domain, DNSHostEntry, FQDN, DNSHostEntry for sql2014
        
    .EXAMPLE
        PS C:\> Resolve-DbaNetworkName -ComputerName sql2016, sql2014

        Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, DNSDomain, Domain, DNSHostEntry, FQDN, DNSHostEntry for sql2016 and sql2014

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2014 | Resolve-DbaNetworkName

        Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, DNSDomain, Domain, DNSHostEntry, FQDN, DNSHostEntry for all SQL Servers returned by Get-DbaRegServer

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2014, sql2016\sqlexpress | Resolve-DbaNetworkName

        Returns a custom object displaying InputName, ComputerName, IPAddress, DNSHostName, DNSDomain, Domain, DNSHostEntry, FQDN, DNSHostEntry for all SQL Servers returned by Get-DbaRegServer

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Alias('FastParrot')]
        [switch]$Turbo,
        [switch]$EnableException
    )
    begin {
        Function Get-ComputerDomainName {
            Param (
                $FQDN,
                $ComputerName
            )
            # deduce the domain name based on resolved name + original request
            if ($fqdn -notmatch "\.") {
                if ($ComputerName -match "\.") {
                    return $ComputerName.Substring($ComputerName.IndexOf(".") + 1)
                } else {
                    return "$env:USERDNSDOMAIN".ToLowerInvariant()
                }
            } else {
                return $fqdn.Substring($fqdn.IndexOf(".") + 1)
            }
        }
    }
    process {
        if ((Get-DbatoolsConfigValue -FullName commands.resolve-dbanetworkname.bypass)) {
            foreach ($computer in $ComputerName) {
                [pscustomobject]@{
                    InputName        = $computer
                    ComputerName     = $computer
                    IPAddress        = $computer
                    DNSHostname      = $computer
                    DNSDomain        = $computer # (Get-ComputerDomainName -ComputerName $computer)
                    Domain           = $computer # (Get-ComputerDomainName -ComputerName $computer)
                    DNSHostEntry     = $computer
                    FQDN             = $computer
                    FullComputerName = $computer
                }
                continue
            }
            return
        }

        if (-not (Test-Windows -NoWarn)) {
            Write-Message -Level Verbose -Message "Non-Windows client detected. Turbo (DNS resolution only) set to $true"
            $Turbo = $true
        }

        foreach ($computer in $ComputerName) {
            if ($computer.IsLocalhost) {
                $cName = $env:COMPUTERNAME
            } else {
                $cName = $computer.ComputerName
            }

            # resolve IP address
            try {
                Write-Message -Level VeryVerbose -Message "Resolving $cName using .NET.Dns GetHostEntry"
                $resolved = [System.Net.Dns]::GetHostEntry($cName)
                $ipaddresses = $resolved.AddressList | Sort-Object -Property AddressFamily # prioritize IPv4
                $ipaddress = $ipaddresses[0].IPAddressToString
            } catch {
                Stop-Function -Message "DNS name $cName not found" -Continue -ErrorRecord $_
            }

            # try to resolve IP into a hostname
            try {
                Write-Message -Level VeryVerbose -Message "Resolving $ipaddress using .NET.Dns GetHostByAddress"
                $fqdn = [System.Net.Dns]::GetHostByAddress($ipaddress).HostName
            } catch {
                Write-Message -Level Debug -Message "Failed to resolve $ipaddress using .NET.Dns GetHostByAddress"
                $fqdn = $resolved.HostName
            }

            $dnsDomain = Get-ComputerDomainName -FQDN $fqdn -ComputerName $cName
            # augment fqdn if needed
            if ($fqdn -notmatch "\." -and $dnsDomain) {
                $fqdn = "$fqdn.$dnsdomain"
            }
            $hostname = $fqdn.Split(".")[0]

            # create an output object with some preliminary data gathered so far
            $result = [PSCustomObject]@{
                InputName        = $computer
                ComputerName     = $hostname.ToUpper()
                IPAddress        = $ipaddress
                DNSHostname      = $hostname
                DNSDomain        = $dnsdomain
                Domain           = $dnsdomain
                DNSHostEntry     = $fqdn
                FQDN             = $fqdn
                FullComputerName = $cName
            }
            if ($Turbo) {
                # that's a finish line for a Turbo mode
                return $result
            }

            # finding out which IP to use by pinging all of them. The first to respond is the one.
            $ping = New-Object System.Net.NetworkInformation.Ping
            $timeout = 1000 #milliseconds
            foreach ($ip in $ipaddresses) {
                $reply = $ping.Send($ip, $timeout)
                if ($reply.Status -eq 'Success') {
                    $ipaddress = $ip.IPAddressToString
                    break
                }
            }
            $result.IPAddress = $ipaddress

            # re-try DNS reverse zone lookup if the IP to use is not the first one
            if ($ipaddresses[0].IPAddressToString -ne $ipaddress) {
                try {
                    Write-Message -Level VeryVerbose -Message "Resolving $ipaddress using .NET.Dns GetHostByAddress"
                    $fqdn = [System.Net.Dns]::GetHostByAddress($ipaddress).HostName
                    # re-adjust DNS domain again
                    $dnsDomain = Get-ComputerDomainName -FQDN $fqdn -ComputerName $cName
                    # augment fqdn if needed
                    if ($fqdn -notmatch "\." -and $dnsDomain) {
                        $fqdn = "$fqdn.$dnsdomain"
                    }
                    $hostname = $fqdn.Split(".")[0]

                    # update result fields accordingly
                    $result.ComputerName = $hostname.ToUpper()
                    $result.DNSHostname = $hostname
                    $result.DNSDomain = $dnsdomain
                    $result.Domain = $dnsdomain
                    $result.DNSHostEntry = $fqdn
                    $result.FQDN = $fqdn
                } catch {
                    Write-Message -Level VeryVerbose -Message "Failed to obtain a new name from $ipaddress, re-using $fqdn"
                }
            }


            Write-Message -Level Debug -Message "Getting domain name from the remote host $fqdn"
            try {
                $ScBlock = {
                    return [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().DomainName
                }
                $cParams = @{
                    ComputerName = $cName
                }
                if ($Credential) { $cParams.Credential = $Credential }

                $conn = Get-DbaCmObject @cParams -ClassName win32_ComputerSystem -EnableException
                if ($conn) {
                    # update results accordingly
                    $result.ComputerName = $conn.Name
                    $dnsHostname = $conn.DNSHostname
                    $dnsDomain = $conn.Domain
                    $result.FQDN = "$dnsHostname.$dnsDomain".TrimEnd('.')
                    $result.DNSHostName = $dnsHostname
                    $result.Domain = $dnsDomain
                }
                try {
                    Write-Message -Level Debug -Message "Getting DNS domain from the remote host $($cParams.ComputerName)"
                    $dnsSuffix = Invoke-Command2 @cParams -ScriptBlock $ScBlock -ErrorAction Stop -Raw
                    $result.DNSDomain = $dnsSuffix
                    if ($dnsSuffix) {
                        $fullComputerName = $result.DNSHostName + "." + $dnsSuffix
                    } else {
                        $fullComputerName = $result.DNSHostName
                    }
                    $result.FullComputerName = $fullComputerName
                } catch {
                    Write-Message -Level Verbose -Message "Unable to get DNS domain information from $($cParams.ComputerName)"
                }
            } catch {
                Write-Message -Level Verbose -Message "Unable to get domain name from $($cParams.ComputerName)"
            }

            # getting a DNS host entry for the full name
            try {
                Write-Message -Level VeryVerbose -Message "Resolving $($result.FullComputerName) using .NET.Dns GetHostEntry"
                $result.DNSHostEntry = ([System.Net.Dns]::GetHostEntry($result.FullComputerName)).HostName
            } catch {
                Write-Message -Level Verbose -Message ".NET.Dns GetHostEntry failed for $($result.FullComputerName)"
            }

            # returning the final result
            $result
        }
    }
}