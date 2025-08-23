function Get-DbaNetworkConfiguration {
    <#
    .SYNOPSIS
        Retrieves SQL Server network protocols, TCP/IP settings, and SSL certificate configuration from SQL Server Configuration Manager

    .DESCRIPTION
        Collects comprehensive network configuration details for SQL Server instances, providing the same information visible in SQL Server Configuration Manager but in a scriptable PowerShell format. This function is essential for network connectivity troubleshooting, security audits, and compliance reporting across multiple SQL Server environments.

        The function retrieves protocol status for Shared Memory, Named Pipes, and TCP/IP, along with detailed TCP/IP properties including port configurations, IP address bindings, and dynamic port settings. It also extracts SSL certificate information, encryption settings, and advanced security properties like SPNs and extended protection settings.

        Since the function accesses SQL WMI and Windows registry data, it uses PowerShell remoting to execute on the target machine, requiring appropriate permissions on both the local and remote systems.

        For a detailed explanation of the different properties see the documentation at:
        https://docs.microsoft.com/en-us/sql/tools/configuration-manager/sql-server-network-configuration

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER OutputType
        Defines what information is returned from the command.
        Options include: Full, ServerProtocols, TcpIpProperties, TcpIpAddresses or Certificate. Full by default.

        Full returns one object per SqlInstance with information about the server protocols
        and nested objects with information about TCP/IP properties and TCP/IP addresses.
        It also outputs advanced properties including information about the used certificate.

        ServerProtocols returns one object per SqlInstance with information about the server protocols only.

        TcpIpProperties returns one object per SqlInstance with information about the TCP/IP protocol properties only.

        TcpIpAddresses returns one object per SqlInstance and IP address.
        If the instance listens on all IP addresses (TcpIpProperties.ListenAll), only the information about the IPAll address is returned.
        Otherwise only information about the individual IP addresses is returned.
        For more details see: https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/configure-a-server-to-listen-on-a-specific-tcp-port

        Certificate returns one object per SqlInstance with information about the configured network certificate and whether encryption is enforced.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Connection, SQLWMI
        Author: Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaNetworkConfiguration

    .EXAMPLE
        PS C:\> Get-DbaNetworkConfiguration -SqlInstance sqlserver2014a

        Returns the network configuration for the default instance on sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaNetworkConfiguration -SqlInstance winserver\sqlexpress, sql2016 -OutputType ServerProtocols

        Returns information about the server protocols for the sqlexpress on winserver and the default instance on sql2016.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [ValidateSet('Full', 'ServerProtocols', 'TcpIpProperties', 'TcpIpAddresses', 'Certificate')]
        [string]$OutputType = 'Full',
        [switch]$EnableException
    )

    begin {
        $scriptBlock = {
            # This scriptblock will be processed by Invoke-Command2 on the target machine.
            # We take an object as the first parameter which has to include the properties ComputerName, InstanceName and SqlFullName,
            # so normally a DbaInstanceParameter.
            $instance = $args[0]
            $verbose = @( )

            # As we go remote, ensure the assembly is loaded
            [void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
            $wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
            $null = $wmi.Initialize()
            $wmiServerProtocols = ($wmi.ServerInstances | Where-Object { $_.Name -eq $instance.InstanceName } ).ServerProtocols

            $wmiSpSm = $wmiServerProtocols | Where-Object { $_.Name -eq 'Sm' }
            $wmiSpNp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Np' }
            $wmiSpTcp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Tcp' }

            $outputTcpIpProperties = [PSCustomObject]@{
                Enabled   = ($wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'Enabled' } ).Value
                KeepAlive = ($wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'KeepAlive' } ).Value
                ListenAll = ($wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'ListenOnAllIPs' } ).Value
            }

            $wmiIPn = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -ne 'IPAll' }
            $outputTcpIpAddressesIPn = foreach ($ip in $wmiIPn) {
                [PSCustomObject]@{
                    Name            = $ip.Name
                    Active          = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'Active' } ).Value
                    Enabled         = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'Enabled' } ).Value
                    IpAddress       = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'IpAddress' } ).Value
                    TcpDynamicPorts = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' } ).Value
                    TcpPort         = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' } ).Value
                }
            }

            $wmiIPAll = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -eq 'IPAll' }
            $outputTcpIpAddressesIPAll = [PSCustomObject]@{
                Name            = $wmiIPAll.Name
                TcpDynamicPorts = ($wmiIPAll.IPAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' } ).Value
                TcpPort         = ($wmiIPAll.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' } ).Value
            }

            $wmiService = $wmi.Services | Where-Object { $_.DisplayName -eq "SQL Server ($($instance.InstanceName))" }
            $serviceAccount = $wmiService.ServiceAccount
            $regRoot = ($wmiService.AdvancedProperties | Where-Object Name -eq REGROOT).Value
            $vsname = ($wmiService.AdvancedProperties | Where-Object Name -eq VSNAME).Value
            $verbose += "regRoot = '$regRoot' / vsname = '$vsname'"
            if ([System.String]::IsNullOrEmpty($regRoot)) {
                $regRoot = $wmiService.AdvancedProperties | Where-Object { $_ -match 'REGROOT' }
                $vsname = $wmiService.AdvancedProperties | Where-Object { $_ -match 'VSNAME' }
                $verbose += "regRoot = '$regRoot' / vsname = '$vsname'"
                if (![System.String]::IsNullOrEmpty($regRoot)) {
                    $regRoot = ($regRoot -Split 'Value\=')[1]
                    $vsname = ($vsname -Split 'Value\=')[1]
                    $verbose += "regRoot = '$regRoot' / vsname = '$vsname'"
                } else {
                    $verbose += "Can't find regRoot"
                }
            }
            if ($regRoot) {
                $regPath = "Registry::HKEY_LOCAL_MACHINE\$regRoot\MSSQLServer\SuperSocketNetLib"
                try {
                    $acceptedSPNs = (Get-ItemProperty -Path $regPath -Name AcceptedSPNs).AcceptedSPNs
                    $thumbprint = (Get-ItemProperty -Path $regPath -Name Certificate).Certificate
                    $cert = Get-ChildItem Cert:\LocalMachine -Recurse -ErrorAction SilentlyContinue | Where-Object Thumbprint -eq $thumbprint | Select-Object -First 1
                    $extendedProtection = switch ((Get-ItemProperty -Path $regPath -Name ExtendedProtection).ExtendedProtection) { 0 { $false } 1 { $true } }
                    $forceEncryption = switch ((Get-ItemProperty -Path $regPath -Name ForceEncryption).ForceEncryption) { 0 { $false } 1 { $true } }
                    $hideInstance = switch ((Get-ItemProperty -Path $regPath -Name HideInstance).HideInstance) { 0 { $false } 1 { $true } }

                    $outputCertificate = [PSCustomObject]@{
                        VSName          = $vsname
                        ServiceAccount  = $serviceAccount
                        ForceEncryption = $forceEncryption
                        FriendlyName    = $cert.FriendlyName
                        DnsNameList     = $cert.DnsNameList
                        Thumbprint      = $cert.Thumbprint
                        Generated       = $cert.NotBefore
                        Expires         = $cert.NotAfter
                        IssuedTo        = $cert.Subject
                        IssuedBy        = $cert.Issuer
                        Certificate     = $cert
                    }

                    $outputAdvanced = [PSCustomObject]@{
                        ForceEncryption    = $forceEncryption
                        HideInstance       = $hideInstance
                        AcceptedSPNs       = $acceptedSPNs
                        ExtendedProtection = $extendedProtection
                    }
                } catch {
                    $outputCertificate = $outputAdvanced = "Failed to get information from registry: $_"
                }
            } else {
                $outputCertificate = $outputAdvanced = "Failed to get information from registry: Path not found"
            }

            [PSCustomObject]@{
                ComputerName        = $instance.ComputerName
                InstanceName        = $instance.InstanceName
                SqlInstance         = $instance.SqlFullName.Trim('[]')
                SharedMemoryEnabled = $wmiSpSm.IsEnabled
                NamedPipesEnabled   = $wmiSpNp.IsEnabled
                TcpIpEnabled        = $wmiSpTcp.IsEnabled
                TcpIpProperties     = $outputTcpIpProperties
                TcpIpAddresses      = $outputTcpIpAddressesIPn + $outputTcpIpAddressesIPAll
                Certificate         = $outputCertificate
                Advanced            = $outputAdvanced
                Verbose             = $verbose
            }
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $computerName = Resolve-DbaComputerName -ComputerName $instance.ComputerName -Credential $Credential
                $null = Test-ElevationRequirement -ComputerName $computerName -EnableException $true
                $netConf = Invoke-Command2 -ScriptBlock $scriptBlock -ArgumentList $instance -ComputerName $computerName -Credential $Credential -ErrorAction Stop
                foreach ($verbose in $netConf.Verbose) {
                    Write-Message -Level Verbose -Message $verbose
                }

                # Test if object is filled to test if instance was found on computer
                if ($null -eq $netConf.SharedMemoryEnabled) {
                    Stop-Function -Message "Failed to collect network configuration from $($instance.ComputerName) for instance $($instance.InstanceName). No data was found for this instance, so skipping." -Target $instance -ErrorRecord $_ -Continue
                }

                if ($OutputType -eq 'Full') {
                    [PSCustomObject]@{
                        ComputerName        = $netConf.ComputerName
                        InstanceName        = $netConf.InstanceName
                        SqlInstance         = $netConf.SqlInstance
                        SharedMemoryEnabled = $netConf.SharedMemoryEnabled
                        NamedPipesEnabled   = $netConf.NamedPipesEnabled
                        TcpIpEnabled        = $netConf.TcpIpEnabled
                        TcpIpProperties     = $netConf.TcpIpProperties
                        TcpIpAddresses      = $netConf.TcpIpAddresses
                        Certificate         = $netConf.Certificate
                        Advanced            = $netConf.Advanced
                    }
                } elseif ($OutputType -eq 'ServerProtocols') {
                    [PSCustomObject]@{
                        ComputerName        = $netConf.ComputerName
                        InstanceName        = $netConf.InstanceName
                        SqlInstance         = $netConf.SqlInstance
                        SharedMemoryEnabled = $netConf.SharedMemoryEnabled
                        NamedPipesEnabled   = $netConf.NamedPipesEnabled
                        TcpIpEnabled        = $netConf.TcpIpEnabled
                    }
                } elseif ($OutputType -eq 'TcpIpProperties') {
                    [PSCustomObject]@{
                        ComputerName = $netConf.ComputerName
                        InstanceName = $netConf.InstanceName
                        SqlInstance  = $netConf.SqlInstance
                        Enabled      = $netConf.TcpIpProperties.Enabled
                        KeepAlive    = $netConf.TcpIpProperties.KeepAlive
                        ListenAll    = $netConf.TcpIpProperties.ListenAll
                    }
                } elseif ($OutputType -eq 'TcpIpAddresses') {
                    if ($netConf.TcpIpProperties.ListenAll) {
                        $ipConf = $netConf.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }
                        [PSCustomObject]@{
                            ComputerName    = $netConf.ComputerName
                            InstanceName    = $netConf.InstanceName
                            SqlInstance     = $netConf.SqlInstance
                            Name            = $ipConf.Name
                            TcpDynamicPorts = $ipConf.TcpDynamicPorts
                            TcpPort         = $ipConf.TcpPort
                        }
                    } else {
                        $ipConf = $netConf.TcpIpAddresses | Where-Object { $_.Name -ne 'IPAll' }
                        foreach ($ip in $ipConf) {
                            [PSCustomObject]@{
                                ComputerName    = $netConf.ComputerName
                                InstanceName    = $netConf.InstanceName
                                SqlInstance     = $netConf.SqlInstance
                                Name            = $ip.Name
                                Active          = $ip.Active
                                Enabled         = $ip.Enabled
                                IpAddress       = $ip.IpAddress
                                TcpDynamicPorts = $ip.TcpDynamicPorts
                                TcpPort         = $ip.TcpPort
                            }
                        }
                    }
                } elseif ($OutputType -eq 'Certificate') {
                    if ($netConf.Certificate -like 'Failed*') {
                        Stop-Function -Message "Failed to collect certificate information from $($instance.ComputerName) for instance $($instance.InstanceName): $($netConf.Certificate)" -Target $instance -Continue
                    }
                    $output = [PSCustomObject]@{
                        ComputerName    = $netConf.ComputerName
                        InstanceName    = $netConf.InstanceName
                        SqlInstance     = $netConf.SqlInstance
                        VSName          = $netConf.Certificate.VSName
                        ServiceAccount  = $netConf.Certificate.ServiceAccount
                        ForceEncryption = $netConf.Certificate.ForceEncryption
                        FriendlyName    = $netConf.Certificate.FriendlyName
                        DnsNameList     = $netConf.Certificate.DnsNameList
                        Thumbprint      = $netConf.Certificate.Thumbprint
                        Generated       = $netConf.Certificate.Generated
                        Expires         = $netConf.Certificate.Expires
                        IssuedTo        = $netConf.Certificate.IssuedTo
                        IssuedBy        = $netConf.Certificate.IssuedBy
                        Certificate     = $netConf.Certificate.Certificate
                    }
                    $defaultView = 'ComputerName,InstanceName,SqlInstance,VSName,ServiceAccount,ForceEncryption,FriendlyName,DnsNameList,Thumbprint,Generated,Expires,IssuedTo,IssuedBy'.Split(',')
                    if (-not $netConf.Certificate.VSName) {
                        $defaultView = $defaultView | Where-Object { $_ -ne 'VSNAME' }
                    }
                    $output | Select-DefaultView -Property $defaultView
                }
            } catch {
                Stop-Function -Message "Failed to collect network configuration from $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
            }
        }
    }
}