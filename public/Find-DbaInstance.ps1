function Find-DbaInstance {
    <#
    .SYNOPSIS
        Discovers SQL Server instances across networks using multiple scanning methods

    .DESCRIPTION
        This function performs comprehensive SQL Server instance discovery across your network infrastructure using multiple detection methods. Perfect for creating complete SQL Server inventories, compliance auditing, and finding forgotten or undocumented instances that might pose security risks.

        The function combines two distinct phases to systematically locate SQL Server instances:

        Discovery Phase:
        Compiles target lists using several methods: Active Directory SPN lookups (finds registered SQL services), SQL Instance Enumeration (same method SSMS uses for browsing), IP address range scanning (scans entire subnets), and Domain Server searches (targets all Windows servers in AD).
        You can specify explicit computer lists via -ComputerName or use automated discovery via -DiscoveryType.

        Scan Phase:
        Tests each discovered target using multiple verification methods: Browser service queries, WMI/CIM SQL service enumeration, TCP port connectivity testing (default 1433), DNS resolution checks, ping tests, and optional SQL connection attempts.
        Results include confidence levels (High/Medium/Low) based on scan success combinations.

        Common DBA scenarios:
        - Audit all SQL instances before migrations or compliance reviews
        - Discover shadow IT databases that bypass standard deployment processes
        - Inventory instances across acquired companies or merged networks
        - Validate disaster recovery documentation against actual running instances
        - Identify instances running on non-standard ports or with unusual configurations

        Security considerations:
        The Discovery phase is non-intrusive, but the Scan phase generates network traffic and authentication attempts across your infrastructure. This creates audit logs and may trigger security monitoring systems. Some scan types require elevated privileges for WMI access or SQL connections. Always coordinate with your security team before running network-wide scans, especially in regulated environments.

    .PARAMETER ComputerName
        Specifies target computers to scan for SQL Server instances. Accepts computer names, IP addresses, or output from Get-ADComputer.
        Use this when you have a specific list of servers to inventory rather than performing network-wide discovery.
        Only the computer name portion is used - connection strings or SQL instance details are ignored.

    .PARAMETER DiscoveryType
        Specifies which automatic discovery methods to use for finding SQL Server targets across your network.
        Choose discovery methods based on your environment: DomainSPN for registered services, DataSourceEnumeration for broadcasting instances, IPRange for subnet scanning, or DomainServer for all Windows servers.
        Combine multiple types for comprehensive coverage, but be aware that IPRange scanning can be time-intensive on large networks.

        ---

        - SPN Lookup

            The function tries to connect active directory to look up all computers with registered SQL Instances.
            Not all instances need to be registered properly, making this not 100% reliable.
            By default, your nearest Domain Controller is contacted for this scan.
            However it is possible to explicitly state the DC to contact using its DistinguishedName and the '-DomainController' parameter.
            If credentials were specified using the '-Credential' parameter, those same credentials are used to perform this lookup, allowing the scan of other domains.

        - SQL Instance Enumeration

            This uses the default UDP Broadcast based instance enumeration used by SSMS to detect instances.
            Note that the result from this is not used in the actual scan, but only to compile a list of computers to scan.
            To enable the same results for the scan, ensure that the 'Browser' scan is enabled.

        - IP Address range:

            This 'Discovery' uses a range of IPAddresses and simply passes them on to be tested.
            See the 'Description' part of help on security issues of network scanning.
            By default, it will enumerate all ethernet network adapters on the local computer and scan the entire subnet they are on.
            By using the '-IpAddress' parameter, custom network ranges can be specified.

        - Domain Server:

            This will discover every single computer in Active Directory that is a Windows Server and enabled.
            By default, your nearest Domain Controller is contacted for this scan.
            However it is possible to explicitly state the DC to contact using its DistinguishedName and the '-DomainController' parameter.
            If credentials were specified using the '-Credential' parameter, those same credentials are used to perform this lookup, allowing the scan of other domains.

    .PARAMETER Credential
        The credentials to use on windows network connection.
        These credentials are used for:
        - Contact to domain controllers for SPN lookups (only if explicit Domain Controller is specified)
        - CIM/WMI contact to the scanned computers during the scan phase (see the '-ScanType' parameter documentation on affected scans).

    .PARAMETER SqlCredential
        The credentials used to connect to SqlInstances to during the scan phase.
        See the '-ScanType' parameter documentation on affected scans.

    .PARAMETER ScanType
        Controls which verification methods are used to detect and validate SQL Server instances on target computers.
        Use specific scan types to optimize performance or reduce network impact - for example, use only Browser and SQLService for quick detection, or add SqlConnect for definitive verification.
        Default performs all scans except SqlConnect, which requires explicit specification due to authentication overhead.

        Scans:
        - Browser
          - Tries discovering all instances via the browser service
          - This scan detects instances.
        - SQLService
          - Tries listing all SQL Services using CIM/WMI
          - This scan uses credentials specified in the '-Credential' parameter if any.
          - This scan detects instances.
          - Success in this scan guarantees high confidence (See parameter '-MinimumConfidence' for details).
        - SPN
          - Tries looking up the Service Principal Names for each instance
          - Will use the nearest Domain Controller by default
          - Target a specific domain controller using the '-DomainController' parameter
          - If using the '-DomainController' parameter, use the '-Credential' parameter to specify the credentials used to connect
        - TCPPort
          - Tries connecting to the TCP Ports.
          - By default, port 1433 is connected to.
          - The parameter '-TCPPort' can be used to provide a list of port numbers to scan.
          - This scan detects possible instances. Since other services might bind to a given port, this is not the most reliable test.
          - This scan is also used to validate found SPNs if both scans are used in combination
        - DNSResolve
          - Tries resolving the computername in DNS
        - Ping
          - Tries pinging the computer. Failure will NOT terminate scans.
        - SqlConnect
          - Tries to establish a SQL connection to the server
          - Uses windows credentials by default
          - Specify custom credentials using the '-SqlCredential' parameter
          - This scan is not used by default
          - Success in this scan guarantees high confidence (See parameter '-MinimumConfidence' for details).
        - All
          - All of the above

    .PARAMETER IpAddress
        Defines custom IP ranges to scan when using IPRange discovery instead of auto-detecting local subnets.
        Use this to target specific network segments like DMZ subnets or remote locations where SQL instances might exist.
        Supports multiple formats: single IPs (10.1.1.1), ranges (10.1.1.1-10.1.1.5), CIDR notation (10.1.1.1/24), or subnet masks (10.1.1.1/255.255.255.0).

    .PARAMETER DomainController
        Specifies a specific domain controller for Active Directory queries when using DomainSPN or DomainServer discovery.
        Use this when you need to target a specific DC for cross-domain searches or when the nearest DC is unavailable.
        Requires the '-Credential' parameter when querying remote domains or when explicit authentication is needed.

    .PARAMETER TCPPort
        Specifies which TCP ports to test for SQL Server connectivity during port scanning.
        Use this to detect instances running on non-standard ports or to scan multiple common SQL Server ports like 1433, 1434, and custom ports.
        Defaults to 1433 (SQL Server default port).

    .PARAMETER MinimumConfidence
        Filters results based on how certain the scan is that a SQL Server instance exists on each target.
        Use High for definitive results when you need accurate inventories, Medium for likely instances, or Low for comprehensive discovery that includes potential false positives.
        High confidence requires successful SQL service detection or connection, Medium requires browser response or combined port+SPN validation, Low accepts single indicators like open ports or SPN records.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Instance, Connect, SqlServer, Lookup
        Author: Scott Sutherland, 2018 NetSPI | Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Outside resources used and modified:
        https://gallery.technet.microsoft.com/scriptcenter/List-the-IP-addresses-in-a-60c5bb6b

    .LINK
        https://dbatools.io/Find-DbaInstance

    .EXAMPLE
        PS C:\> Find-DbaInstance -DiscoveryType Domain, DataSourceEnumeration

        Performs a network search for SQL Instances by:
        - Looking up the Service Principal Names of computers in Active Directory
        - Using the UDP broadcast based auto-discovery of SSMS
        After that it will extensively scan all hosts thus discovered for instances.

    .EXAMPLE
        PS C:\> Find-DbaInstance -DiscoveryType All

        Performs a network search for SQL Instances, using all discovery protocols:
        - Active directory search for Service Principal Names
        - SQL Instance Enumeration (same as SSMS does)
        - All IPAddresses in the current computer's subnets of all connected network interfaces
        Note: This scan will take a long time, due to including the IP Scan

    .EXAMPLE
        PS C:\> Get-ADComputer -Filter "*" | Find-DbaInstance

        Scans all computers in the domain for SQL Instances, using a deep probe:
        - Tries resolving the name in DNS
        - Tries pinging the computer
        - Tries listing all SQL Services using CIM/WMI
        - Tries discovering all instances via the browser service
        - Tries connecting to the default TCP Port (1433)
        - Tries connecting to the TCP port of each discovered instance
        - Tries to establish a SQL connection to the server using default windows credentials
        - Tries looking up the Service Principal Names for each instance

    .EXAMPLE
        PS C:\> Get-Content .\servers.txt | Find-DbaInstance -SqlCredential $cred -ScanType Browser, SqlConnect

        Reads all servers from the servers.txt file (one server per line),
        then scans each of them for instances using the browser service
        and finally attempts to connect to each instance found using the specified credentials.
        then scans each of them for instances using the browser service and SqlService

    .EXAMPLE
        PS C:\> Find-DbaInstance -ComputerName localhost | Get-DbaDatabase | Format-Table -Wrap

        Scans localhost for instances using the browser service, traverses all instances for all databases and displays all information in a formatted table.

    .EXAMPLE
        PS C:\> $databases = Find-DbaInstance -ComputerName localhost | Get-DbaDatabase
        PS C:\> $results = $databases | Select-Object SqlInstance, Name, Status, RecoveryModel, SizeMB, Compatibility, Owner, LastFullBackup, LastDiffBackup, LastLogBackup
        PS C:\> $results | Format-Table -Wrap

        Scans localhost for instances using the browser service, traverses all instances for all databases and displays a subset of the important information in a formatted table.

        Using this method regularly is not recommended. Use Get-DbaService or Get-DbaRegServer instead.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "", Justification = "Internal functions are ignored")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Computer', ValueFromPipeline)]
        [DbaInstance[]]$ComputerName,
        [Parameter(Mandatory, ParameterSetName = 'Discover')]
        [Dataplat.Dbatools.Discovery.DbaInstanceDiscoveryType]$DiscoveryType,
        [System.Management.Automation.PSCredential]$Credential,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [ValidateSet('Default', 'SQLService', 'Browser', 'TCPPort', 'All', 'SPN', 'Ping', 'SqlConnect', 'DNSResolve')]
        [Dataplat.Dbatools.Discovery.DbaInstanceScanType[]]$ScanType = "Default",
        [Parameter(ParameterSetName = 'Discover')]
        [string[]]$IpAddress,
        [string]$DomainController,
        [int[]]$TCPPort = 1433,
        [Dataplat.Dbatools.Discovery.DbaInstanceConfidenceLevel]$MinimumConfidence = 'Low',
        [switch]$EnableException
    )
    begin {
        #region Utility Functions
        function Test-SqlInstance {
            <#
            .SYNOPSIS
                Performs the actual scanning logic

            .DESCRIPTION
                Performs the actual scanning logic
                Each potential target is accessed using the specified scan routines.

            .PARAMETER Target
                The target to scan.

            .EXAMPLE
                PS C:\> Test-SqlInstance
        #>
            [CmdletBinding()]
            param (
                [Parameter(ValueFromPipeline)]
                [DbaInstance[]]$Target,
                [PSCredential]$Credential,
                [PSCredential]$SqlCredential,
                [Dataplat.Dbatools.Discovery.DbaInstanceScanType]$ScanType,
                [string]$DomainController,
                [int[]]$TCPPort = 1433,
                [Dataplat.Dbatools.Discovery.DbaInstanceConfidenceLevel]$MinimumConfidence,
                [switch]$EnableException
            )
            begin {
                [System.Collections.ArrayList]$computersScanned = @()
            }
            process {
                foreach ($computer in $Target) {
                    $stepCounter = 0
                    if ($computersScanned.Contains($computer.ComputerName)) {
                        continue
                    } else {
                        $null = $computersScanned.Add($computer.ComputerName)
                    }
                    Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Starting"
                    Write-Message -Level Verbose -Message "Processing: $($computer)" -Target $computer -FunctionName Find-DbaInstance

                    #region Null variables to prevent scope lookup on conditional existence
                    $resolution = $null
                    $pingReply = $null
                    $sPNs = @()
                    $ports = @()
                    $browseResult = $null
                    $services = @()
                    #Variable marked as unused by PSScriptAnalyzer
                    #$serverObject = $null
                    #$browseFailed = $false
                    #endregion Null variables to prevent scope lookup on conditional existence

                    #region Gather data
                    if ($ScanType -band [Dataplat.Dbatools.Discovery.DbaInstanceScanType]::DNSResolve) {
                        try {
                            Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Performing DNS resolution"
                            $resolution = [System.Net.Dns]::GetHostEntry($computer.ComputerName)
                        } catch {
                            # here to avoid an empty catch
                            $null = 1
                        }
                    }

                    if ($ScanType -band [Dataplat.Dbatools.Discovery.DbaInstanceScanType]::Ping) {
                        $ping = New-Object System.Net.NetworkInformation.Ping
                        try {
                            Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Waiting for ping response"
                            $pingReply = $ping.Send($computer.ComputerName)
                        } catch {
                            # here to avoid an empty catch
                            $null = 1
                        }
                    }

                    if ($ScanType -band [Dataplat.Dbatools.Discovery.DbaInstanceScanType]::SPN) {
                        $computerByName = $computer.ComputerName
                        if ($resolution.HostName) { $computerByName = $resolution.HostName }
                        if ($computerByName -notmatch "$([dbargx]::IPv4)|$([dbargx]::IPv6)") {
                            try {
                                Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Finding SPNs"
                                $sPNs = Get-DomainSPN -DomainController $DomainController -Credential $Credential -ComputerName $computerByName -GetSPN
                            } catch {
                                # here to avoid an empty catch
                                $null = 1
                            }
                        }
                    }

                    # $ports required for all scans
                    Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Testing TCP ports"

                    if ($ScanType -band [Dataplat.Dbatools.Discovery.DbaInstanceScanType]::Browser) {
                        try {
                            Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Probing Browser service"
                            $browseResult = Get-SQLInstanceBrowserUDP -ComputerName $computer -EnableException
                            $ports = $browseResult.TCPPort | Test-TcpPort -ComputerName $computer
                        } catch {
                            # here to avoid an empty catch
                            $null = 1
                        }
                    } else {
                        $ports = $TCPPort | Test-TcpPort -ComputerName $computer
                    }

                    if ($ScanType -band [Dataplat.Dbatools.Discovery.DbaInstanceScanType]::SqlService) {
                        Write-ProgressHelper -Activity "Processing: $($computer)" -StepNumber ($stepCounter++) -Message "Finding SQL services using SQL WMI"
                        if ($Credential) {
                            $services = Get-DbaService -ComputerName $computer -Credential $Credential -EnableException -ErrorAction Ignore -WarningAction SilentlyCOntinue
                        } else {
                            $services = Get-DbaService -ComputerName $computer -ErrorAction Ignore -WarningAction SilentlyContinue
                        }
                    }
                    #endregion Gather data

                    #region Gather list of found instance indicators
                    $instanceNames = @()
                    if ($Services) {
                        $Services | Select-Object -ExpandProperty InstanceName -Unique | Where-Object { $_ -and ($instanceNames -notcontains $_) } | ForEach-Object {
                            $instanceNames += $_
                        }
                    }
                    if ($browseResult) {
                        $browseResult | Select-Object -ExpandProperty InstanceName -Unique | Where-Object { $_ -and ($instanceNames -notcontains $_) } | ForEach-Object {
                            $instanceNames += $_
                        }
                    }

                    $portsDetected = @()
                    foreach ($portResult in $ports) {
                        if ($portResult.IsOpen) { $portsDetected += $portResult.Port }
                    }
                    foreach ($sPN in $sPNs) {
                        try { $inst = $sPN.Split(':')[1] }
                        catch { continue }

                        try {
                            [int]$portNumber = $inst
                            if ($portNumber -and ($portsDetected -notcontains $portNumber)) {
                                $portsDetected += $portNumber
                            }
                        } catch {
                            if ($inst -and ($instanceNames -notcontains $inst)) {
                                $instanceNames += $inst
                            }
                        }
                    }
                    #endregion Gather list of found instance indicators

                    #region Case: Nothing found
                    if ((-not $instanceNames) -and (-not $portsDetected)) {
                        if ($resolution -or ($pingReply.Status -like "Success")) {
                            if ($MinimumConfidence -eq [Dataplat.Dbatools.Discovery.DbaInstanceConfidenceLevel]::None) {
                                New-Object Dataplat.Dbatools.Discovery.DbaInstanceReport -Property @{
                                    MachineName  = $computer.ComputerName
                                    ComputerName = $computer.ComputerName
                                    Ping         = $pingReply.Status -like 'Success'
                                }
                            } else {
                                Write-Message -Level Verbose -Message "Computer $computer could be contacted, but no trace of an SQL Instance was found. Skipping..." -Target $computer -FunctionName Find-DbaInstance
                            }
                        } else {
                            Write-Message -Level Verbose -Message "Computer $computer could not be contacted, skipping." -Target $computer -FunctionName Find-DbaInstance
                        }

                        continue
                    }
                    #endregion Case: Nothing found

                    [System.Collections.ArrayList]$masterList = @()

                    #region Case: Named instance found
                    foreach ($instance in $instanceNames) {
                        $object = New-Object Dataplat.Dbatools.Discovery.DbaInstanceReport
                        $object.MachineName = $computer.ComputerName
                        $object.ComputerName = $computer.ComputerName
                        $object.InstanceName = $instance
                        $object.DnsResolution = $resolution
                        $object.Ping = $pingReply.Status -like 'Success'
                        $object.ScanTypes = $ScanType
                        $object.Services = $services | Where-Object InstanceName -EQ $instance
                        $object.SystemServices = $services | Where-Object { -not $_.InstanceName }
                        $object.SPNs = $sPNs

                        if ($result = $browseResult | Where-Object InstanceName -EQ $instance) {
                            $object.BrowseReply = $result
                        }
                        if ($ports) {
                            $object.PortsScanned = $ports
                        }

                        if ($object.BrowseReply) {
                            $object.Confidence = 'Medium'
                            if ($object.BrowseReply.TCPPort) {
                                $object.Port = $object.BrowseReply.TCPPort

                                $object.PortsScanned | Where-Object Port -EQ $object.Port | ForEach-Object {
                                    $object.TcpConnected = $_.IsOpen
                                }
                            }
                        }
                        if ($object.Services) {
                            $object.Confidence = 'High'

                            $engine = $object.Services | Where-Object ServiceType -EQ "Engine"
                            switch ($engine.State) {
                                "Running" { $object.Availability = 'Available' }
                                "Stopped" { $object.Availability = 'Unavailable' }
                                default { $object.Availability = 'Unknown' }
                            }
                        }

                        $object.Timestamp = Get-Date

                        $masterList += $object
                    }
                    #endregion Case: Named instance found

                    #region Case: Port number found
                    foreach ($port in $portsDetected) {
                        if ($masterList.Port -contains $port) { continue }

                        $object = New-Object Dataplat.Dbatools.Discovery.DbaInstanceReport
                        $object.MachineName = $computer.ComputerName
                        $object.ComputerName = $computer.ComputerName
                        $object.Port = $port
                        $object.DnsResolution = $resolution
                        $object.Ping = $pingReply.Status -like 'Success'
                        $object.ScanTypes = $ScanType
                        $object.SystemServices = $services | Where-Object { -not $_.InstanceName }
                        $object.SPNs = $sPNs
                        $object.Confidence = 'Low'
                        if ($ports) {
                            $object.PortsScanned = $ports

                            if (($ports | Where-Object IsOpen).Port -eq 1433) {
                                $object.Confidence = 'Medium'
                            }
                        }

                        if (($ports.Port -contains $port) -and ($sPNs | Where-Object { $_ -like "*:$port" })) {
                            $object.Confidence = 'Medium'
                        }

                        $object.PortsScanned | Where-Object Port -EQ $object.Port | ForEach-Object {
                            $object.TcpConnected = $_.IsOpen
                        }
                        $object.Timestamp = Get-Date

                        if ($masterList.SqlInstance -contains $object.SqlInstance) {
                            continue
                        }

                        $masterList += $object
                    }
                    #endregion Case: Port number found

                    if ($ScanType -band [Dataplat.Dbatools.Discovery.DbaInstanceScanType]::SqlConnect) {
                        $instanceHash = @{ }
                        $toDelete = @()
                        foreach ($dataSet in $masterList) {
                            try {
                                $server = Connect-DbaInstance -SqlInstance $dataSet.SqlInstance -SqlCredential $SqlCredential
                                $dataSet.SqlConnected = $true
                                $dataSet.Confidence = 'High'

                                # Remove duplicates
                                if ($instanceHash.ContainsKey($server.DomainInstanceName)) {
                                    $toDelete += $dataSet
                                } else {
                                    $instanceHash[$server.DomainInstanceName] = $dataSet

                                    try {
                                        $dataSet.MachineName = $server.ComputerNamePhysicalNetBIOS
                                    } catch {
                                        # here to avoid an empty catch
                                        $null = 1
                                    }
                                }
                            } catch {
                                # Error class definitions
                                # https://docs.microsoft.com/en-us/sql/relational-databases/errors-events/database-engine-error-severities
                                # 24 or less means an instance was found, but had some issues

                                #region Processing error (Access denied, server error, ...)
                                if ($_.Exception.InnerException.Errors.Class -lt 25) {
                                    # There IS an SQL Instance and it listened to network traffic
                                    $dataSet.SqlConnected = $true
                                    $dataSet.Confidence = 'High'
                                }
                                #endregion Processing error (Access denied, server error, ...)

                                #region Other connection errors
                                else {
                                    $dataSet.SqlConnected = $false
                                }
                                #endregion Other connection errors
                            }
                        }

                        foreach ($item in $toDelete) {
                            $masterList.Remove($item)
                        }
                    }

                    $masterList | Where-Object { $_.Confidence -ge $MinimumConfidence }
                }
            }
        }

        function Get-DomainSPN {
            <#
            .SYNOPSIS
                Returns all computernames with registered MSSQL SPNs.

            .DESCRIPTION
                Returns all computernames with registered MSSQL SPNs.

            .PARAMETER DomainController
                The domain controller to ask.

            .PARAMETER Credential
                The credentials to use while asking.

            .PARAMETER ComputerName
                Filter by computername

            .PARAMETER GetSPN
                Returns the service SPNs instead of the hostname

            .EXAMPLE
                PS C:\> Get-DomainSPN -DomainController $DomainController -Credential $Credential

                Returns all computernames with MSQL SPNs known to $DomainController, assuming credentials are valid.
        #>
            [CmdletBinding()]
            param (
                [string]$DomainController,
                [PSCredential]$Credential,
                [string]$ComputerName = "*",
                [switch]$GetSPN
            )

            try {
                if ($DomainController) {
                    if ($Credential) {
                        $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList "LDAP://$DomainController", $Credential.UserName, $Credential.GetNetworkCredential().Password
                    } else {
                        $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList "LDAP://$DomainController"
                    }
                } else {
                    $entry = [ADSI]''
                }
                $objSearcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher -ArgumentList $entry

                $objSearcher.PageSize = 200
                $objSearcher.Filter = "(&(servicePrincipalName=MSSQLsvc*)(|(name=$ComputerName)(dnshostname=$ComputerName)))"
                $objSearcher.SearchScope = 'Subtree'

                $results = $objSearcher.FindAll()
                foreach ($computer in $results) {
                    if ($GetSPN) {
                        $computer.Properties["serviceprincipalname"] | Where-Object { $_ -like "MSSQLsvc*:*" }
                    } else {
                        if ($computer.Properties["dnshostname"] -and $computer.Properties["dnshostname"] -ne '') {
                            $computer.Properties["dnshostname"][0]
                        } else {
                            $computer.Properties["serviceprincipalname"][0] -match '(?<=/)[^:]*' > $null
                            if ($matches) {
                                $matches[0]
                            } else {
                                $computer.Properties["name"][0]
                            }
                        }
                    }
                }
            } catch {
                throw
            }
        }

        function Get-DomainServer {
            <#
            .SYNOPSIS
                Returns a list of all Domain Computer objects that are servers.

            .DESCRIPTION
                Returns a list of all Domain Computer objects that are ...
                - Enabled
                - Have an OS named like "*windows*server*"

            .PARAMETER DomainController
                The domain controller to ask.

            .PARAMETER Credential
                The credentials to use while asking.

            .EXAMPLE
                PS C:\> Get-DomainServer

                Returns a list of all Domain Computer objects that are servers.
        #>
            [CmdletBinding()]
            param (
                [string]$DomainController,
                [PSCredential]$Credential
            )

            try {
                if ($DomainController) {
                    if ($Credential) {
                        $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList "LDAP://$DomainController", $Credential.UserName, $Credential.GetNetworkCredential().Password
                    } else {
                        $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList "LDAP://$DomainController"
                    }
                } else {
                    $entry = [ADSI]''
                }
                $objSearcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher -ArgumentList $entry

                $objSearcher.PageSize = 200
                $objSearcher.Filter = "(&(objectcategory=computer)(operatingSystem=*windows*server*)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"
                $objSearcher.SearchScope = 'Subtree'

                $results = $objSearcher.FindAll()
                foreach ($computer in $results) {
                    if ($computer.Properties["dnshostname"]) {
                        $computer.Properties["dnshostname"][0]
                    } else {
                        $computer.Properties["name"][0]
                    }
                }
            } catch { throw }
        }

        function Get-SQLInstanceBrowserUDP {
            <#
            .SYNOPSIS
                Requests a list of instances from the browser service.

            .DESCRIPTION
                Requests a list of instances from the browser service.

            .PARAMETER ComputerName
                Computer name or IP address to enumerate SQL Instance from.

            .PARAMETER UDPTimeOut
                Timeout in seconds. Longer timeout = more accurate.

            .PARAMETER EnableException
                By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
                This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
                Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

            .EXAMPLE
                PS C:\> Get-SQLInstanceBrowserUDP -ComputerName 'sql2017'

                Contacts the browsing service on sql2017 and requests its instance information.

            .NOTES
                Original Author: Eric Gruber
                Editors:
                - Scott Sutherland (Pipeline and timeout mods)
                - Friedrich Weinmann (Cleanup & dbatools Standardization)

        #>
            [CmdletBinding()]
            param (
                [Parameter(Mandatory, ValueFromPipeline)][DbaInstance[]]$ComputerName,
                [int]$UDPTimeOut = 2,
                [switch]$EnableException
            )

            process {
                foreach ($computer in $ComputerName) {
                    try {
                        #region Connect to browser service and receive response
                        $UDPClient = New-Object -TypeName System.Net.Sockets.Udpclient
                        $UDPClient.Client.ReceiveTimeout = $UDPTimeOut * 1000
                        $UDPClient.Connect($computer.ComputerName, 1434)
                        $UDPPacket = 0x03
                        $UDPEndpoint = New-Object -TypeName System.Net.IpEndPoint -ArgumentList ([System.Net.Ipaddress]::Any, 0)
                        $UDPClient.Client.Blocking = $true
                        [void]$UDPClient.Send($UDPPacket, $UDPPacket.Length)
                        $BytesRecived = $UDPClient.Receive([ref]$UDPEndpoint)
                        # Skip first three characters, since those contain trash data (SSRP metadata)
                        #$Response = [System.Text.Encoding]::ASCII.GetString($BytesRecived[3..($BytesRecived.Length - 1)])
                        $Response = [System.Text.Encoding]::ASCII.GetString($BytesRecived)
                        #endregion Connect to browser service and receive response

                        #region Parse Output
                        $Response | Select-String "(ServerName;([a-zA-Z0-9_-]+);InstanceName;(\w+);IsClustered;(\w+);Version;(\d+\.\d+\.\d+\.\d+);(tcp;(\d+)){0,1})" -AllMatches | Select-Object -ExpandProperty Matches | ForEach-Object {
                            $obj = New-Object Dataplat.Dbatools.Discovery.DbaBrowserReply -Property @{
                                MachineName  = $computer.ComputerName
                                ComputerName = $_.Groups[2].Value
                                SqlInstance  = "$($_.Groups[2].Value)\$($_.Groups[3].Value)"
                                InstanceName = $_.Groups[3].Value
                                Version      = $_.Groups[5].Value
                                IsClustered  = "Yes" -eq $_.Groups[4].Value
                            }
                            if ($_.Groups[7].Success) {
                                $obj.TCPPort = $_.Groups[7].Value
                            }
                            $obj
                        }
                        #endregion Parse Output

                        $UDPClient.Close()
                    } catch {
                        try {
                            $UDPClient.Close()
                        } catch {
                            # here to avoid an empty catch
                            $null = 1
                        }

                        if ($EnableException) { throw }
                    }
                }
            }
        }

        function Test-TcpPort {
            <#
            .SYNOPSIS
                Tests whether a TCP Port is open or not.

            .DESCRIPTION
                Tests whether a TCP Port is open or not.

            .PARAMETER ComputerName
                The name of the computer to scan.

            .PARAMETER Port
                The port(s) to scan.

            .EXAMPLE
                PS C:\> $ports | Test-TcpPort -ComputerName "foo"

                Tests for each port in $ports whether the TCP port is open on computer "foo"
        #>
            [CmdletBinding()]
            param (
                [DbaInstance]$ComputerName,
                [Parameter(ValueFromPipeline)][int[]]$Port
            )

            begin {
                $client = New-Object Net.Sockets.TcpClient
            }
            process {
                foreach ($item in $Port) {
                    try {
                        $client.Connect($ComputerName.ComputerName, $item)
                        if ($client.Connected) {
                            $client.Close()
                            New-Object -TypeName Dataplat.Dbatools.Discovery.DbaPortReport -ArgumentList $ComputerName.ComputerName, $item, $true
                        } else {
                            New-Object -TypeName Dataplat.Dbatools.Discovery.DbaPortReport -ArgumentList $ComputerName.ComputerName, $item, $false
                        }
                    } catch {
                        New-Object -TypeName Dataplat.Dbatools.Discovery.DbaPortReport -ArgumentList $ComputerName.ComputerName, $item, $false
                    }
                }
            }
        }

        function Get-IPrange {
            <#
            .SYNOPSIS
                Get the IP addresses in a range

            .DESCRIPTION
                A detailed description of the Get-IPrange function.

            .PARAMETER Start
                A description of the Start parameter.

            .PARAMETER End
                A description of the End parameter.

            .PARAMETER IPAddress
                A description of the IPAddress parameter.

            .PARAMETER Mask
                A description of the Mask parameter.

            .PARAMETER Cidr
                A description of the Cidr parameter.

            .EXAMPLE
                Get-IPrange -Start 192.168.8.2 -End 192.168.8.20

            .EXAMPLE
                Get-IPrange -IPAddress 192.168.8.2 -Mask 255.255.255.0

            .EXAMPLE
                Get-IPrange -IPAddress 192.168.8.3 -Cidr 24

            .NOTES
                Author: BarryCWT
                Reference: https://gallery.technet.microsoft.com/scriptcenter/List-the-IP-addresses-in-a-60c5bb6b
        #>

            param
            (
                [string]$Start,
                [string]$End,
                [string]$IPAddress,
                [string]$Mask,
                [int]$Cidr
            )

            function IP-toINT64 {
                param ($ip)

                $octets = $ip.split(".")
                return [int64]([int64]$octets[0] * 16777216 + [int64]$octets[1] * 65536 + [int64]$octets[2] * 256 + [int64]$octets[3])
            }

            function INT64-toIP {
                param ([int64]$int)

                return ([System.Net.IPAddress](([math]::truncate($int / 16777216)).tostring() + "." + ([math]::truncate(($int % 16777216) / 65536)).tostring() + "." + ([math]::truncate(($int % 65536) / 256)).tostring() + "." + ([math]::truncate($int % 256)).tostring()))
            }

            if ($Cidr) {
                $maskaddr = [Net.IPAddress]::Parse((INT64-toIP -int ([convert]::ToInt64(("1" * $Cidr + "0" * (32 - $Cidr)), 2))))
            }
            if ($Mask) {
                $maskaddr = [Net.IPAddress]::Parse($Mask)
            }
            if ($IPAddress) {
                $ipaddr = [Net.IPAddress]::Parse($IPAddress)
                $networkaddr = New-Object net.ipaddress ($maskaddr.address -band $ipaddr.address)
                $broadcastaddr = New-Object net.ipaddress (([system.net.ipaddress]::parse("255.255.255.255").address -bxor $maskaddr.address -bor $networkaddr.address))
                $startaddr = IP-toINT64 -ip $networkaddr.ipaddresstostring
                $endaddr = IP-toINT64 -ip $broadcastaddr.ipaddresstostring
            } else {
                $startaddr = IP-toINT64 -ip $Start
                $endaddr = IP-toINT64 -ip $End
            }

            for ($i = $startaddr; $i -le $endaddr; $i++) {
                INT64-toIP -int $i
            }
        }

        function Resolve-IPRange {
            <#
            .SYNOPSIS
                Returns a number of IPAddresses based on range specified.

            .DESCRIPTION
                Returns a number of IPAddresses based on range specified.
                Warning: A too large range can lead to memory exceptions.

                Scans subnet of active computer if no address is specified.

            .PARAMETER IpAddress
                The address / range / mask / cidr to scan. Example input:
                - 10.1.1.1
                - 10.1.1.1/24
                - 10.1.1.1-10.1.1.254
                - 10.1.1.1/255.255.255.0
        #>
            [CmdletBinding()]
            param (
                [AllowEmptyString()][string]$IpAddress
            )

            #region Scan defined range
            if ($IpAddress) {
                #region Determine processing mode
                $mode = 'Unknown'
                if ($IpAddress -like "*/*") {
                    $parts = $IpAddress.Split("/")

                    $address = $parts[0]
                    if ($parts[1] -match ([dbargx]::IPv4)) {
                        $mask = $parts[1]
                        $mode = 'Mask'
                    } elseif ($parts[1] -as [int]) {
                        $cidr = [int]$parts[1]

                        if (($cidr -lt 8) -or ($cidr -gt 31)) {
                            Stop-Function -Message "$IpAddress does not contain a valid cidr mask"
                            return
                        }

                        $mode = 'CIDR'
                    } else {
                        Stop-Function -Message "$IpAddress is not a valid IP range"
                    }
                } elseif ($IpAddress -like "*-*") {
                    $rangeStart = $IpAddress.Split("-")[0]
                    $rangeEnd = $IpAddress.Split("-")[1]

                    if ($rangeStart -notmatch ([dbargx]::IPv4)) {
                        Stop-Function -Message "$IpAddress is not a valid IP range"
                        return
                    }
                    if ($rangeEnd -notmatch ([dbargx]::IPv4)) {
                        Stop-Function -Message "$IpAddress is not a valid IP range"
                        return
                    }

                    $mode = 'Range'
                } else {
                    if ($IpAddress -notmatch ([dbargx]::IPv4)) {
                        Stop-Function -Message "$IpAddress is not a valid IP address"
                        return
                    }
                    return $IpAddress
                }
                #endregion Determine processing mode

                switch ($mode) {
                    'CIDR' {
                        Get-IPrange -IPAddress $address -Cidr $cidr
                    }
                    'Mask' {
                        Get-IPrange -IPAddress $address -Mask $mask
                    }
                    'Range' {
                        Get-IPrange -Start $rangeStart -End $rangeEnd
                    }
                }
            }
            #endregion Scan defined range

            #region Scan own computer range
            else {
                foreach ($interface in ([System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object NetworkInterfaceType -Like '*Ethernet*')) {
                    foreach ($property in ($interface.GetIPProperties().UnicastAddresses | Where-Object { $_.Address.AddressFamily -like "InterNetwork" })) {
                        Get-IPrange -IPAddress $property.Address -Cidr $property.PrefixLength
                    }
                }
            }
            #endregion Scan own computer range
        }
        #endregion Utility Functions

        #region Build parameter Splat for scan
        $paramTestSqlInstance = @{
            ScanType          = $ScanType
            TCPPort           = $TCPPort
            EnableException   = $EnableException
            MinimumConfidence = $MinimumConfidence
        }

        # Only specify when passed by user to avoid credential prompts on PS3/4
        if ($SqlCredential) {
            $paramTestSqlInstance["SqlCredential"] = $SqlCredential
        }
        if ($Credential) {
            $paramTestSqlInstance["Credential"] = $Credential
        }
        if ($DomainController) {
            $paramTestSqlInstance["DomainController"] = $DomainController
        }
        #endregion Build parameter Splat for scan

        # Prepare item processing in a pipeline compliant way
        $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Test-SqlInstance', [System.Management.Automation.CommandTypes]::Function)
        $scriptCmd = {
            & $wrappedCmd @paramTestSqlInstance
        }
        $steppablePipeline = $scriptCmd.GetSteppablePipeline()
        $steppablePipeline.Begin($true)
    }

    process {
        if (Test-FunctionInterrupt) { return }
        #region Process items or discover stuff
        switch ($PSCmdlet.ParameterSetName) {
            'Computer' {
                $ComputerName | Invoke-SteppablePipeline -Pipeline $steppablePipeline
            }
            'Discover' {
                #region Discovery: DataSource Enumeration
                if ($DiscoveryType -band ([Dataplat.Dbatools.Discovery.DbaInstanceDiscoveryType]::DataSourceEnumeration)) {
                    try {
                        # Discover instances
                        foreach ($instance in ([System.Data.Sql.SqlDataSourceEnumerator]::Instance.GetDataSources())) {
                            if ($instance.InstanceName -ne [System.DBNull]::Value) {
                                $steppablePipeline.Process("$($instance.Servername)\$($instance.InstanceName)")
                            } else {
                                $steppablePipeline.Process($instance.Servername)
                            }
                        }
                    } catch {
                        Write-Message -Level Warning -Message "Datasource enumeration failed" -ErrorRecord $_ -EnableException $EnableException.ToBool()
                    }
                }
                #endregion Discovery: DataSource Enumeration

                #region Discovery: SPN Search
                if ($DiscoveryType -band ([Dataplat.Dbatools.Discovery.DbaInstanceDiscoveryType]::DomainSPN)) {
                    try {
                        Get-DomainSPN -DomainController $DomainController -Credential $Credential -ErrorAction Stop | Invoke-SteppablePipeline -Pipeline $steppablePipeline
                    } catch {
                        Write-Message -Level Warning -Message "Failed to execute Service Principal Name discovery" -ErrorRecord $_ -EnableException $EnableException.ToBool()
                    }
                }
                #endregion Discovery: SPN Search

                #region Discovery: IP Range
                if ($DiscoveryType -band ([Dataplat.Dbatools.Discovery.DbaInstanceDiscoveryType]::IPRange)) {
                    if ($IpAddress) {
                        foreach ($address in $IpAddress) {
                            Resolve-IPRange -IpAddress $address | Invoke-SteppablePipeline -Pipeline $steppablePipeline
                        }
                    } else {
                        Resolve-IPRange | Invoke-SteppablePipeline -Pipeline $steppablePipeline
                    }
                }
                #endregion Discovery: IP Range

                #region Discovery: Windows Server Search
                if ($DiscoveryType -band ([Dataplat.Dbatools.Discovery.DbaInstanceDiscoveryType]::DomainServer)) {
                    try {
                        Get-DomainServer -DomainController $DomainController -Credential $Credential -ErrorAction Stop | Invoke-SteppablePipeline -Pipeline $steppablePipeline
                    } catch {
                        Write-Message -Level Warning -Message "Failed to execute Windows Server discovery" -ErrorRecord $_ -EnableException $EnableException.ToBool()
                    }
                }
                #endregion Discovery: Windows Server Search
            }
            "Default" {
                Stop-Function -Message "Please specify DiscoveryType or ScanType. Try Get-Help Find-DbaInstance -Examples for working examples." -EnableException $EnableException
                return
            }
            default {
                Stop-Function -Message "Invalid parameterset, some developer probably had a beer too much. Please file an issue so we can fix this." -EnableException $EnableException
                return
            }
        }
        #endregion Process items or discover stuff
    }

    end {
        if (Test-FunctionInterrupt) {
            return
        }
        $steppablePipeline.End()
    }
}