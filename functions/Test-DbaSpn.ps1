function Test-DbaSpn {
    <#
    .SYNOPSIS
        Test-DbaSpn will determine what SPNs *should* be set for a given server (and any instances of SQL running on it) and return
        whether the SPNs are set or not.

    .DESCRIPTION
        This function is designed to take in a server name(s) and attempt to determine required SPNs. It was initially written to mimic the (previously) broken functionality of the Microsoft Kerberos Configuration manager and SQL Server 2016.

        - For any instances with TCP/IP enabled, the script will determine which port(s) the instances are listening on and generate the required SPNs.
        - For named instances NOT using dynamic ports, the script will generate a port-based SPN for those instances as well.
        - At a minimum, the script will test a base, port-less SPN for each instance discovered.

        Once the required SPNs are generated, the script will connect to Active Directory and search for any of the SPNs (if any) that are already set. The function will return a custom object(s) that contains the server name checked, the instance name discovered, the account the service is running under, and what the "required" SPN should be. It will also return a boolean property indicating if the SPN is set in Active Directory or not.

    .PARAMETER ComputerName
        The computer you want to discover any SQL Server instances on. This parameter is required.

    .PARAMETER Credential
        The credential you want to use to connect to the remote server and active directory.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SPN
        Author: Drew Furgiuele (@pittfurg), http://www.port1433.com | niphlod

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaSpn

    .EXAMPLE
        Test-DbaSpn -ComputerName SQLSERVERA -Credential ad\sqldba

        Connects to a computer (SQLSERVERA) and queries WMI for all SQL instances and return "required" SPNs. It will then take each SPN it generates
        and query Active Directory to make sure the SPNs are set.

    .EXAMPLE
        Test-DbaSpn -ComputerName SQLSERVERA,SQLSERVERB -Credential ad\sqldba

        Connects to multiple computers (SQLSERVERA, SQLSERVERB) and queries WMI for all SQL instances and return "required" SPNs.
        It will then take each SPN it generates and query Active Directory to make sure the SPNs are set.

    .EXAMPLE
        Test-DbaSpn -ComputerName SQLSERVERC -Credential ad\sqldba

        Connects to a computer (SQLSERVERC) on a specified and queries WMI for all SQL instances and return "required" SPNs.
        It will then take each SPN it generates and query Active Directory to make sure the SPNs are set. Note that the credential you pass must have be a valid login with appropriate rights on the domain

    #>
    [cmdletbinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$ComputerName,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    begin {
        # spare the cmdlet to search for the same account over and over
        $resultCache = @{ }
    }
    process {
        foreach ($computer in $ComputerName) {
            try {
                $resolved = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Credential $Credential -ErrorAction Stop
            } catch {
                $resolved = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Turbo
            }

            if ($null -eq $resolved.IPAddress) {
                Write-Message -Level Warning -Message "Cannot resolve IP address, moving on."
                continue
            }

            $hostEntry = $resolved.FullComputerName

            Write-Message -Message "Resolved ComputerName to FQDN: $hostEntry" -Level Verbose

            $Scriptblock = {

                function Convert-SqlVersion {
                    [cmdletbinding()]
                    param (
                        [version]$version
                    )

                    switch ($version.Major) {
                        9 { "SQL Server 2005" }
                        10 {
                            if ($version.Minor -eq 0) {
                                "SQL Server 2008"
                            } else {
                                "SQL Server 2008 R2"
                            }
                        }
                        11 { "SQL Server 2012" }
                        12 { "SQL Server 2014" }
                        13 { "SQL Server 2016" }
                        14 { "SQL Server 2017" }
                        default { $version }
                    }
                }

                $spns = @()
                $servereName = $args[0]
                $hostEntry = $args[1]
                $instanceName = $args[2]
                $instanceCount = $wmi.ServerInstances.Count

                <# DO NOT use Write-Message as this is inside of a script block #>
                Write-Verbose "Found $instanceCount instances"

                foreach ($instance in $wmi.ServerInstances) {
                    $spn = [pscustomobject] @{
                        ComputerName           = $servereName
                        InstanceName           = $instanceName
                        #SKUNAME
                        SqlProduct             = $null
                        InstanceServiceAccount = $null
                        RequiredSPN            = $null
                        IsSet                  = $false
                        Cluster                = $false
                        TcpEnabled             = $false
                        Port                   = $null
                        DynamicPort            = $false
                        Warning                = "None"
                        Error                  = "None"
                        # for piping
                        Credential             = $Credential
                    }

                    $spn.InstanceName = $instance.Name
                    $instanceName = $spn.InstanceName

                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Verbose "Parsing $instanceName"

                    $services = $wmi.Services | Where-Object DisplayName -EQ "SQL Server ($instanceName)"
                    $spn.InstanceServiceAccount = $services.ServiceAccount
                    $spn.Cluster = ($services.advancedproperties | Where-Object Name -EQ 'Clustered').Value

                    if ($spn.Cluster) {
                        $hostEntry = ($services.advancedproperties | Where-Object Name -EQ 'VSNAME').Value.ToLowerInvariant()
                        <# DO NOT use Write-Message as this is inside of a script block #>
                        Write-Verbose "Found cluster $hostEntry"
                        $hostEntry = ([System.Net.Dns]::GetHostEntry($hostEntry)).HostName
                        $spn.ComputerName = $hostEntry
                    }

                    $rawVersion = [version]($services.AdvancedProperties | Where-Object Name -EQ 'VERSION').Value

                    $version = Convert-SqlVersion $rawVersion
                    $skuName = ($services.AdvancedProperties | Where-Object Name -EQ 'SKUNAME').Value

                    $spn.SqlProduct = "$version $skuName"

                    #is tcp enabled on this instance? If not, we don't need an spn, son
                    if ((($instance.ServerProtocols | Where-Object { $_.Displayname -eq "TCP/IP" }).ProtocolProperties | Where-Object { $_.Name -eq "Enabled" }).Value -eq $true) {
                        <# DO NOT use Write-Message as this is inside of a script block #>
                        Write-Verbose "TCP is enabled, gathering SPN requirements"
                        $spn.TcpEnabled = $true
                        #Each instance has a default SPN of MSSQLSvc\<fqdn> or MSSSQLSvc\<fqdn>:Instance
                        if ($instance.Name -eq "MSSQLSERVER") {
                            $spn.RequiredSPN = "MSSQLSvc/$hostEntry"
                        } else {
                            $spn.RequiredSPN = "MSSQLSvc/" + $hostEntry + ":" + $instance.Name
                        }
                    }

                    $spns += $spn
                }
                # Now, for each spn, do we need a port set? Only if TCP is enabled and NOT DYNAMIC!
                foreach ($spn in $spns) {
                    $ports = @()

                    $ips = (($wmi.ServerInstances | Where-Object { $_.Name -eq $spn.InstanceName }).ServerProtocols | Where-Object { $_.DisplayName -eq "TCP/IP" -and $_.IsEnabled -eq "True" }).IpAddresses
                    $ipAllPort = $null
                    foreach ($ip in $ips) {
                        if ($ip.Name -eq "IPAll") {
                            $ipAllPort = ($ip.IPAddressProperties | Where-Object { $_.Name -eq "TCPPort" }).Value
                            if (($ip.IpAddressProperties | Where-Object { $_.Name -eq "TcpDynamicPorts" }).Value -ne "") {
                                $ipAllPort = ($ip.IPAddressProperties | Where-Object { $_.Name -eq "TcpDynamicPorts" }).Value + "d"
                            }
                        } else {
                            $enabled = ($ip.IPAddressProperties | Where-Object { $_.Name -eq "Enabled" }).Value
                            $active = ($ip.IPAddressProperties | Where-Object { $_.Name -eq "Active" }).Value
                            $tcpDynamicPorts = ($ip.IPAddressProperties | Where-Object { $_.Name -eq "TcpDynamicPorts" }).Value
                            if ($enabled -and $active -and $tcpDynamicPorts -eq "") {
                                $ports += ($ip.IPAddressProperties | Where-Object { $_.Name -eq "TCPPort" }).Value
                            } elseif ($enabled -and $active -and $tcpDynamicPorts -ne "") {
                                $ports += $ipAllPort + "d"
                            }
                        }
                    }
                    if ($ipAllPort -ne "") {
                        #IPAll overrides any set ports. Not sure why that's the way it is?
                        $ports = $ipAllPort
                    }

                    $ports = $ports | Select-Object -Unique
                    foreach ($port in $ports) {
                        $newspn = $spn.PSObject.Copy()
                        if ($port -like "*d") {
                            $newspn.Port = ($port.replace("d", ""))
                            $newspn.RequiredSPN = $newspn.RequiredSPN.Replace($newSPN.InstanceName, $newspn.Port)
                            $newspn.DynamicPort = $true
                            $newspn.Warning = "Dynamic port is enabled"
                        } else {
                            #If this is a named instance, replace the instance name with a port number (for non-dynamic ported named instances)
                            $newspn.Port = $port
                            $newspn.DynamicPort = $false

                            if ($newspn.InstanceName -eq "MSSQLSERVER") {
                                $newspn.RequiredSPN = $newspn.RequiredSPN + ":" + $port
                            } else {
                                $newspn.RequiredSPN = $newspn.RequiredSPN.Replace($newSPN.InstanceName, $newspn.Port)
                            }
                        }
                        $spns += $newspn
                    }
                }
                $spns
            }


            try {
                $spns = Invoke-ManagedComputerCommand -ComputerName $hostEntry -ScriptBlock $Scriptblock -ArgumentList $resolved.FullComputerName, $hostEntry, $computer.InstanceName -Credential $Credential -ErrorAction Stop
            } catch {
                Stop-Function -Message "Couldn't connect to $computer" -ErrorRecord $_ -Continue
            }

            #Now query AD for each required SPN
            foreach ($spn in $spns) {
                $searchfor = 'User'
                if ($spn.InstanceServiceAccount -eq 'LocalSystem' -or $spn.InstanceServiceAccount -like 'NT SERVICE\*') {
                    Write-Message -Level Verbose -Message "Virtual account detected, changing target registration to computername"
                    $spn.InstanceServiceAccount = "$($resolved.Domain)\$($resolved.ComputerName)$"
                    $searchfor = 'Computer'
                } elseif ($spn.InstanceServiceAccount -like '*\*$') {
                    Write-Message -Level Verbose -Message "Managed Service Account detected"
                    $searchfor = 'Computer'
                }

                $serviceAccount = $spn.InstanceServiceAccount
                # spare the cmdlet to search for the same account over and over
                if ($spn.InstanceServiceAccount -notin $resultCache.Keys) {
                    Write-Message -Message "Searching for $serviceAccount" -Level Verbose
                    try {
                        $result = Get-DbaADObject -ADObject $serviceAccount -Type $searchfor -Credential $Credential -EnableException
                        $resultCache[$spn.InstanceServiceAccount] = $result
                    } catch {
                        if (![System.String]::IsNullOrEmpty($spn.InstanceServiceAccount)) {
                            Write-Message -Message "AD lookup failure. This may be because the domain cannot be resolved for the SQL Server service account ($serviceAccount)." -Level Warning
                        }
                    }
                } else {
                    $result = $resultCache[$spn.InstanceServiceAccount]
                }
                if ($result.Count -gt 0) {
                    try {
                        $results = $result.GetUnderlyingObject()
                        if ($results.Properties.servicePrincipalName -contains $spn.RequiredSPN) {
                            $spn.IsSet = $true
                        }
                    } catch {
                        Write-Message -Message "The SQL Service account ($serviceAccount) has been found, but you don't have enough permission to inspect its SPNs" -Level Warning
                        continue
                    }
                } else {
                    Write-Message -Level Warning -Message "SQL Service account not found. Results may not be accurate."
                    $spn
                    continue
                }
                if (!$spn.IsSet -and $spn.TcpEnabled) {
                    $spn.Error = "SPN missing"
                }

                $spn | Select-DefaultView -ExcludeProperty Credential, DomainName
            }
        }
    }
}