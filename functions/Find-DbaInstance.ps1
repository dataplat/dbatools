#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Find-DbaInstance {
<#
    .SYNOPSIS
        Search for SQL Server Instances.
    
    .DESCRIPTION
        This function searches for SQL Server Instances.
    
        It supports a variety of scans for this purpose which can be separated in two categories:
        - Discovery
        - Scan
    
        Discovery:
        This is where it compiles a list of computers / addresses to check.
        It supports several methods of generating such lists (including Active Directory lookup or IP Ranges), but also supports specifying a list of computers to check.
        - For details on discovery, see the documentation on the '-DiscoveryType' parameter
        - For details on explicitly providing a list, see the documentation on the '-ComputerName' parameter
    
        Scan:
        Once a list of computers has been provided, this command will execute a variety of actions to determine any instances present for each of them.
        This is described in more detail in the documentation on the '-ScanType' parameter.
        Additional parameters allow more granular control over individual scans (e.g. Credentials to use).
        
        Note on logging and auditing:
        The Discovery phase is unproblematic since it is non-intrusive, however during the scan phase, all targeted computers may be accessed repeatedly.
        This may cause issues with security teams, due to many logon events and possibly failed authentication.
        This action constitutes a network scan, which may be illegal depending on the nation you are in and whether you own the network you scan.
        If you are unsure whether you may use this command in your environment, check the detailed description on the '-ScanType' parameter and contact your IT security team for advice.
    
    .PARAMETER ComputerName
        The computer to scan. Can be a variety of input types, including text or the output of Get-ADComputer.
        Any extra instance information (such as connection strings or live sql server connections) beyond the computername will be discarded.
    
    .PARAMETER DiscoveryType
        The mechanisms to be used to discover instances.
        Supports any combination of:
        - Service Principal Name lookup ('Domain'; from Active Directory)
        - SQL Instance Enumeration ('DataSourceEnumeration'; same as SSMS uses)
        - IP Address range ('IPRange'; all IP Addresses will be scanned)
    
        SPN Lookup:
        The function tries to connect active directory to look up all computers with registered SQL Instances.
        Not all instances need to be registered properly, making this not 100% reliable.
        By default, your nearest Domain Controller is contacted for this scan.
        However it is possible to explicitly state the DC to contact using its DistinguishedName and the '-DomainController' parameter.
        If credentials were specified using the '-Credential' parameter, those same credentials are used to perform this lookup, allowing the scan of other domains.
    
        SQL Instance Enumeration:
        This uses the default UDP Broadcast based instance enumeration used by SSMS to detect instances.
        Note that the result from this is not used in the actual scan, but only to compile a list of computers to scan.
        To enable the same results for the scan, ensure that the 'Browser' scan is enabled.
    
        IP Address range:
        This 'Discovery' uses a range of IPAddresses and simply passes them on to be tested.
        See the 'Description' part of help on security issues of network scanning.
        By default, it will enumerate all ethernet network adapters on the local computer and scan the entire subnet they are on.
        By using the '-IpAddress' parameter, custom network ranges can be specified.
    
    .PARAMETER Credential
        The credentials to use on windows network connection.
        These credentials are used for:
        - Contact to domain controllers for SPN lookups (only if explicit Domain Controller is specified)
        - CIM/WMI contact to the scanned computers during the scan phase (see the '-ScanType' parameter documentation on affected scans).
    
    .PARAMETER SqlCredential
        The credentials used to connect to SqlInstances to during the scan phase.
        See the '-ScanType' parameter documentation on affected scans.
    
    .PARAMETER ScanType
        The scans are the individual methods used to retrieve information about the scanned computer and any potentially installed instances.
        This parameter is optional, by default all scans except for establishing an actual SQL connection are performed.
        Scans can be specified in any arbitrary combination, however at least one instance detecting scan needs to be specified in order for data to be returned.
    
        Scans:
        DNSResolve
        - Tries resolving the computername in DNS
        Ping
        - Tries pinging the computer. Failure will NOT terminate scans.
        SQLService
        - Tries listing all SQL Services using CIM/WMI
        - This scan uses credentials specified in the '-Credential' parameter if any.
        - This scan detects instances.
        - Success in this scan guarantees high confidence (See parameter '-MinimumConfidence' for details).
        Browser
        - Tries discovering all instances via the browser service
        - This scan detects instances.
        TCPPort
        - Tries connecting to the TCP Ports.
        - By default, port 1433 is connected to.
        - The parameter '-TCPPort' can be used to provide a list of port numbers to scan.
        - This scan detects possible instances. Since other services might bind to a given port, this is not the most reliable test.
        - This scan is also used to validate found SPNs if both scans are used in combination
        SqlConnect
        - Tries to establish a SQL connection to the server
        - Uses windows credentials by default
        - Specify custom credentials using the '-SqlCredential' parameter
        - This scan is not used by default
        - Success in this scan guarantees high confidence (See parameter '-MinimumConfidence' for details).
        SPN
        - Tries looking up the Service Principal Names for each instance
        - Will use the nearest Domain Controller by default
        - Target a specific domain controller using the '-DomainController' parameter
        - If using the '-DomainController' parameter, use the '-Credential' parameter to specify the credentials used to connect
    
    .PARAMETER IpAddress
        This parameter can be used to override the defaults for the IPRange discovery.
        This parameter accepts a list of strings supporting any combination of:
        - Plain IP Addresses (e.g.: "10.1.1.1")
        - IP Address Ranges (e.g.: "10.1.1.1-10.1.1.5")
        - IP Address & Subnet Mask (e.g.: "10.1.1.1/255.255.255.0")
        - IP Address & Subnet Length: (e.g.: "10.1.1.1/24)
        Overlapping addresses will not result in duplicate scans.
    
    .PARAMETER DomainController
        The domain controller to contact for SPN lookups / searches.
        Uses the credentials from the '-Credential' parameter if specified.
    
    .PARAMETER TCPPort
        The ports to scan in the TCP Port Scan method.
        Defaults to 1433.
    
    .PARAMETER MinimumConfidence
        This command tries to discover instances, which isn't always a sure thing.
        Depending on the number and type of scans completed, we have different levels of confidence in our results.
        By default, we will return anything that we have at least a low confidence of being an instance.
        These are the confidence levels we support and how they are determined:
        - High: Established SQL Connection (including rejection for bad credentials) or service scan.
        - Medium: Browser reply or a combination of TCPConnect _and_ SPN test.
        - Low: Either TCPConnect _or_ SPN
        - None: Computer existence could be verified, but no sign of an SQL Instance
    
    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    
    .EXAMPLE
        PS C:\> Find-DbaInstance -DiscoveryType Domain,DataSourceEnumeration
        
        Performs a network search for SQL Instances by:
        - Looking up the Service Principal Names of computers in active directory
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
        PS C:\> Get-Content .\servers.txt | Find-DbaInstance -SqlCredential $cred -ScanType Browser,SqlConnect
        
        Reads all servers from the servers.txt file (one server per line),
        then scans each of them for instances using the browser service
        and finally attempts to connect to each instance found using the specified credentials.
    
    .NOTES
        Original Design by: Scott Sutherland, 2018 NetSPI
        Conversion & Refactoring by: Friedrich Weinmann
        
        Outside resources used and modified:
        - https://gallery.technet.microsoft.com/scriptcenter/List-the-IP-addresses-in-a-60c5bb6b
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'Computer', ValueFromPipeline = $true)]
        [DbaInstance[]]$ComputerName,
        [Parameter(Mandatory = $true, ParameterSetName = 'Discover')]
        [Sqlcollaborative.Dbatools.Discovery.DbaInstanceDiscoveryType]$DiscoveryType,
        [System.Management.Automation.PSCredential]$Credential,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]$ScanType = "Default",
        [Parameter(ParameterSetName = 'Discover')]
        [string[]]$IpAddress,
        [string]$DomainController,
        [int[]]$TCPPort = 1433,
        [Sqlcollaborative.Dbatools.Discovery.DbaInstanceConfidenceLevel]$MinimumConfidence = 'Low',
        [Alias('Silent')]
        [switch]$EnableException
    )
    
    begin {
        # TCPPort = 1 | SqlService = 4 | SPN = 16 | Browser = 32
        if (-not ($ScanType -band 53)) {
            Stop-Function -Message "Invalid Scan Types specified: $ScanType | Specify at least one of the following types: Browser, SqlService, SPN, TCPPort, Default or All. Otherwise no detection will be possible." -EnableException $EnableException -Category InvalidArgument
            return
        }
        
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
                [Parameter(ValueFromPipeline = $true)][DbaInstance[]]$Target,
                [PSCredential]$Credential,
                [PSCredential]$SqlCredential,
                [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]$ScanType,
                [string]$DomainController,
                [int[]]$TCPPort = 1433,
                [Sqlcollaborative.Dbatools.Discovery.DbaInstanceConfidenceLevel]$MinimumConfidence,
                [switch]$EnableException
            )
            
            begin {
                [System.Collections.ArrayList]$computersScanned = @()
            }
            
            process {
                foreach ($computer in $Target) {
                    if ($computersScanned.Contains($computer.ComputerName)) {
                        continue
                    }
                    else {
                        $null = $computersScanned.Add($computer.ComputerName)
                    }
                    Write-Message -Level Verbose -Message "Processing: $($computer)" -Target $computer -EnableException $EnableException -FunctionName Find-DbaInstance
                    
                    #region Null variables to prevent scope lookup on conditional existence
                    $resolution = $null
                    $pingReply = $null
                    $sPNs = @()
                    $ports = @()
                    $browseResult = $null
                    $services = @()
                    $serverObject = $null
                    $browseFailed = $false
                    #endregion Null variables to prevent scope lookup on conditional existence
                    
                    #region Gather data
                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::DNSResolve) {
                        try { $resolution = [System.Net.Dns]::GetHostEntry($computer.ComputerName) }
                        catch { }
                    }
                    
                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::Ping) {
                        $ping = New-Object System.Net.NetworkInformation.Ping
                        try { $pingReply = $ping.Send($computer.ComputerName) }
                        catch { }
                    }
                    
                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::SPN) {
                        $computerByName = $computer.ComputerName
                        if ($resolution.HostName) { $computerByName = $resolution.HostName }
                        if ($computerByName -notmatch "$([dbargx]::IPv4)|$([dbargx]::IPv6)") {
                            try { $sPNs = Get-DomainSPN -DomainController $DomainController -Credential $Credential -ComputerName $computerByName -GetSPN }
                            catch { }
                        }
                    }
                    
                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::TCPPort) {
                        $ports = $TCPPort | Test-TcpPort -ComputerName $computer
                    }
                    
                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::Browser) {
                        try {
                            $browseResult = Get-SQLInstanceBrowserUDP -ComputerName $computer -EnableException
                        }
                        catch {
                            $browseFailed = $true
                        }
                    }
                    
                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::SqlService) {
                        if ($Credential) { $services = Get-DbaSqlService -ComputerName $computer -Credential $Credential -EnableException -ErrorAction Ignore -WarningAction SilentlyCOntinue }
                        else { $services = Get-DbaSqlService -ComputerName $computer -ErrorAction Ignore -WarningAction SilentlyContinue }
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
                        }
                        catch {
                            if ($inst -and ($instanceNames -notcontains $inst)) {
                                $instanceNames += $inst
                            }
                        }
                    }
                    #endregion Gather list of found instance indicators
                    
                    #region Case: Nothing found
                    if ((-not $instanceNames) -and (-not $portsDetected)) {
                        if ($resolution -or ($pingReply.Status -like "Success")) {
                            if ($MinimumConfidence -eq [Sqlcollaborative.Dbatools.Discovery.DbaInstanceConfidenceLevel]::None) {
                                New-Object Sqlcollaborative.Dbatools.Discovery.DbaInstanceReport -Property @{
                                    MachineName   = $computer.ComputerName
                                    ComputerName  = $computer.ComputerName
                                    Ping          = $pingReply.Status -like 'Success'
                                }
                            }
                            else {
                                Write-Message -Level Verbose -Message "Computer $computer could be contacted, but no trace of an SQL Instance was found. Skipping..." -Target $computer -EnableException $EnableException -FunctionName Find-DbaInstance
                            }
                        }
                        else {
                            Write-Message -Level Verbose -Message "Computer $computer could not be contacted, skipping." -Target $computer -EnableException $EnableException -FunctionName Find-DbaInstance
                        }
                        
                        continue
                    }
                    #endregion Case: Nothing found
                    
                    [System.Collections.ArrayList]$masterList = @()
                    
                    #region Case: Named instance found
                    foreach ($instance in $instanceNames) {
                        $object = New-Object Sqlcollaborative.Dbatools.Discovery.DbaInstanceReport
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
                        
                        $object = New-Object Sqlcollaborative.Dbatools.Discovery.DbaInstanceReport
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
                    
                    if ($ScanType -band [Sqlcollaborative.Dbatools.Discovery.DbaInstanceScanType]::SqlConnect) {
                        $instanceHash = @{ }
                        $toDelete = @()
                        foreach ($dataSet in $masterList) {
                            try {
                                $server = Connect-SqlInstance -SqlInstance $dataSet.FullSmoName -SqlCredential $SqlCredential
                                $dataSet.SqlConnected = $true
                                $dataSet.Confidence = 'High'
                                
                                # Remove duplicates
                                if ($instanceHash.ContainsKey($server.DomainInstanceName)) {
                                    $toDelete += $dataSet
                                }
                                else {
                                    $instanceHash[$server.DomainInstanceName] = $dataSet
                                    
                                    try {
                                        $dataSet.MachineName = $server.ComputerNamePhysicalNetBIOS
                                    }
                                    catch { }
                                }
                            }
                            catch {
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
                    
                    $masterList
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
                [object]$Credential,
                [string]$ComputerName = "*",
                [switch]$GetSPN
            )
            
            try {
                if ($DomainController) {
                    if ($Credential) {
                        $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList "LDAP://$DomainController", $Credential.UserName, $Credential.GetNetworkCredential().Password
                    }
                    else {
                        $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList "LDAP://$DomainController"
                    }
                }
                else {
                    $entry = [ADSI]''
                }
                $objSearcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher -ArgumentList $entry
                
                $objSearcher.PageSize = 200
                $objSearcher.Filter = "(&(objectcategory=computer)(servicePrincipalName=MSSQLsvc*)(|(name=$ComputerName)(dnshostname=$ComputerName)))"
                $objSearcher.SearchScope = 'Subtree'
                
                $results = $objSearcher.FindAll()
                foreach ($computer in $results) {
                    if ($GetSPN) {
                        $computer.Properties["serviceprincipalname"] | Where-Object { $_ -like "MSSQLsvc*:*" }
                    }
                    else {
                        if ($computer.Properties["dnshostname"]) {
                            $computer.Properties["dnshostname"][0]
                        }
                        else {
                            $computer.Properties["name"][0]
                        }
                    }
                }
            }
            catch {
                throw
            }
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
                [Parameter(Mandatory = $true, ValueFromPipeline = $true)][DbaInstance[]]$ComputerName,
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
                        $Response | Select-String "(ServerName;(\w+);InstanceName;(\w+);IsClustered;(\w+);Version;(\d+\.\d+\.\d+\.\d+);(tcp;(\d+)){0,1})" -AllMatches | Select-Object -ExpandProperty Matches | ForEach-Object {
                            $obj = New-Object Sqlcollaborative.Dbatools.Discovery.DbaBrowserReply -Property @{
                                MachineName       = $computer.ComputerName
                                ComputerName      = $_.Groups[2].Value
                                SqlInstance       = "$($_.Groups[2].Value)\$($_.Groups[3].Value)"
                                InstanceName      = $_.Groups[3].Value
                                Version           = $_.Groups[5].Value
                                IsClustered       = "Yes" -eq $_.Groups[4].Value
                            }
                            if ($_.Groups[7].Success) {
                                $obj.TCPPort = $_.Groups[7].Value
                            }
                            $obj
                        }
                        #endregion Parse Output
                        
                        $UDPClient.Close()
                    }
                    catch {
                        try {
                            $UDPClient.Close()
                        }
                        catch {
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
                [Parameter(ValueFromPipeline = $true)][int[]]$Port
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
                            New-Object -TypeName Sqlcollaborative.Dbatools.Discovery.DbaPortReport -ArgumentList $ComputerName.ComputerName, $item, $true
                        }
                        else {
                            New-Object -TypeName Sqlcollaborative.Dbatools.Discovery.DbaPortReport -ArgumentList $ComputerName.ComputerName, $item, $false
                        }
                    }
                    catch {
                        New-Object -TypeName Sqlcollaborative.Dbatools.Discovery.DbaPortReport -ArgumentList $ComputerName.ComputerName, $item, $false
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
                
                return ([System.Net.IPAddress](([math]::truncate($int/16777216)).tostring() + "." + ([math]::truncate(($int % 16777216)/65536)).tostring() + "." + ([math]::truncate(($int % 65536)/256)).tostring() + "." + ([math]::truncate($int % 256)).tostring()))
            }
            
            if ($Cidr) {
                $maskaddr = [Net.IPAddress]::Parse((INT64-toIP -int ([convert]::ToInt64(("1" * $Cidr + "0" * (32 - $Cidr)), 2))))
            }
            if ($Mask) {
                $maskaddr = [Net.IPAddress]::Parse($Mask)
            }
            if ($IPAddress) {
                $ipaddr = [Net.IPAddress]::Parse($IPAddress)
                $networkaddr = new-object net.ipaddress ($maskaddr.address -band $ipaddr.address)
                $broadcastaddr = new-object net.ipaddress (([system.net.ipaddress]::parse("255.255.255.255").address -bxor $maskaddr.address -bor $networkaddr.address))
                $startaddr = IP-toINT64 -ip $networkaddr.ipaddresstostring
                $endaddr = IP-toINT64 -ip $broadcastaddr.ipaddresstostring
            }
            else {
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
                    }
                    elseif ($parts[1] -as [int]) {
                        $cidr = [int]$parts[1]
                        
                        if (($cidr -lt 8) -or ($cidr -gt 31)) {
                            throw "$IpAddress does not contain a valid cidr mask!"
                        }
                        
                        $mode = 'CIDR'
                    }
                    else {
                        throw "$IpAddress is not a valid IP Range!"
                    }
                }
                elseif ($IpAddress -like "*-*") {
                    $rangeStart = $IpAddress.Split("-")[0]
                    $rangeEnd = $IpAddress.Split("-")[1]
                    
                    if ($rangeStart -notmatch ([dbargx]::IPv4)) {
                        throw "$IpAddress is not a valid IP Range!"
                    }
                    if ($rangeEnd -notmatch ([dbargx]::IPv4)) {
                        throw "$IpAddress is not a valid IP Range!"
                    }
                    
                    $mode = 'Range'
                }
                else {
                    if ($IpAddress -notmatch ([dbargx]::IPv4)) {
                        throw "$IpAddress is not a valid IP Address!"
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
            ScanType            = $ScanType
            TCPPort             = $TCPPort
            EnableException     = $EnableException
            MinimumConfidence   = $MinimumConfidence
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
                if ($DiscoveryType -band ([Sqlcollaborative.Dbatools.Discovery.DbaInstanceDiscoveryType]::DataSourceEnumeration)) {
                    try {
                        # Discover instances
                        foreach ($instance in ([System.Data.Sql.SqlDataSourceEnumerator]::Instance.GetDataSources())) {
                            if ($instance.InstanceName -ne [System.DBNull]::Value) {
                                $steppablePipeline.Process("$($instance.Servername)\$($instance.InstanceName)")
                            }
                            else {
                                $steppablePipeline.Process($instance.Servername)
                            }
                        }
                    }
                    catch {
                        Write-Message -Level Warning -Message "Datasource enumeration failed" -ErrorRecord $_ -EnableException $EnableException
                    }
                }
                #endregion Discovery: DataSource Enumeration
                
                #region Discovery: SPN Search
                if ($DiscoveryType -band ([Sqlcollaborative.Dbatools.Discovery.DbaInstanceDiscoveryType]::Domain)) {
                    try {
                        Get-DomainSPN -DomainController $DomainController -Credential $Credential -ErrorAction Stop | Invoke-SteppablePipeline -Pipeline $steppablePipeline
                    }
                    catch {
                        Write-Message -Level Warning -Message "Failed to execute Service Principal Name discovery" -ErrorRecord $_ -EnableException $EnableException
                    }
                }
                #endregion Discovery: SPN Search
                
                #region Discovery: IP Range
                if ($DiscoveryType -band ([Sqlcollaborative.Dbatools.Discovery.DbaInstanceDiscoveryType]::IPRange)) {
                    if ($IpAddress) {
                        foreach ($address in $IpAddress) {
                            Resolve-IPRange -IpAddress $address | Invoke-SteppablePipeline -Pipeline $steppablePipeline
                        }
                    }
                    else {
                        Resolve-IPRange | Invoke-SteppablePipeline -Pipeline $steppablePipeline
                    }
                }
                #endregion Discovery: IP Range
            }
            default {
                Stop-Function -Message "Invalid parameterset, some developer probably had a beer too much. Please file an issue so we can fix this" -EnableException $EnableException
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
