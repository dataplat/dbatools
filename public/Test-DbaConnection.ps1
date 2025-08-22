
function Test-DbaConnection {
    <#
    .SYNOPSIS
        Validates SQL Server connectivity and gathers comprehensive connection diagnostics

    .DESCRIPTION
        Tests SQL Server instance connectivity while collecting detailed connection and environment information for troubleshooting. Returns authentication details, network configuration, TCP ports, and local PowerShell environment data. Essential for diagnosing connectivity issues before running automation scripts or validating access across multiple instances. Combines SQL connection testing with network diagnostics including ping status, PSRemoting access, and DNS resolution.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

        Utilized for gathering PSRemoting and TCPPort information.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER SkipPSRemoting
        This switch will skip the test for PSRemoting.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Connection
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaConnection

    .EXAMPLE
        PS C:\> Test-DbaConnection SQL2016

        ComputerName         : SQL2016
        InstanceName         : MSSQLSERVER
        SqlInstance          : sql2016
        SqlVersion           : 13.0.4001
        ConnectingAsUser     : BASE\ctrlb
        ConnectSuccess       : True
        AuthType             : Windows Authentication
        AuthScheme           : KERBEROS
        TcpPort              : 1433
        IPAddress            : 10.2.1.5
        NetBiosName          : sql2016.base.local
        IsPingable           : True
        PSRemotingAccessible : True
        DomainName           : base.local
        LocalWindows         : 10.0.15063.0
        LocalPowerShell      : 5.1.15063.502
        LocalCLR             : 4.0.30319.42000
        LocalSMOVersion      : 13.0.0.0
        LocalDomainUser      : True
        LocalRunAsAdmin      : False
        LocalEdition         : Desktop

        Test connection to SQL2016 and outputs information collected

    .EXAMPLE
        PS C:\> $winCred = Get-Credential sql2017\Administrator
        PS C:\> $sqlCred = Get-Credential sa
        PS C:\> Test-DbaConnection SQL2017 -SqlCredential $sqlCred -Credential $winCred

        ComputerName         : SQL2017
        InstanceName         : MSSQLSERVER
        SqlInstance          : sql2017
        SqlVersion           : 14.0.3356
        ConnectingAsUser     : sa
        ConnectSuccess       : True
        AuthType             : SQL Authentication
        AuthScheme           : SQL
        TcpPort              : 50164
        IPAddress            : 10.10.10.15
        NetBiosName          : sql2017.company.local
        IsPingable           : True
        PSRemotingAccessible : True
        DomainName           : company.local
        LocalWindows         : 10.0.15063.0
        LocalPowerShell      : 5.1.19041.610
        LocalCLR             : 4.0.30319.42000
        LocalSMOVersion      : 15.100.0.0
        LocalDomainUser      : True
        LocalRunAsAdmin      : False
        LocalEdition         : Desktop

        Test connection to SQL2017 instance and collecting information on SQL Server using the sa login, local Administrator account is used to collect port information
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [PSCredential]$SqlCredential,
        [switch]$SkipPSRemoting,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            # Clear loop variables assigned after connection test - https://github.com/dataplat/dbatools/issues/9066
            $authType = $null
            $tcpport = $null
            $authscheme = $null

            # Get local environment
            Write-Message -Level Verbose -Message "Getting local environment information"
            $localInfo = [PSCustomObject]@{
                Windows    = [environment]::OSVersion.Version.ToString()
                Edition    = $PSVersionTable.PSEdition
                PowerShell = $PSVersionTable.PSVersion.ToString()
                CLR        = [string]$PSVersionTable.CLRVersion
                SMO        = ((([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -like "Microsoft.SqlServer.SMO,*" }).FullName -Split ", ")[1]).TrimStart("Version=")
                DomainUser = $env:computername -ne $env:USERDOMAIN
                RunAsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
            }

            try {
                <# gather following properties #>
                <#
                    InputName        :
                    ComputerName     :
                    IPAddress        :
                    DNSHostName      :
                    DNSDomain        :
                    Domain           :
                    DNSHostEntry     :
                    FQDN             :
                    FullComputerName :
                #>
                $resolved = Resolve-DbaNetworkName -ComputerName $instance.ComputerName -Credential $Credential -EnableException
            } catch {
                Stop-Function -Message "Unable to resolve server information" -Category ConnectionError -Target $instance -ErrorRecord $_ -Continue
            }

            # Test for WinRM #Test-WinRM
            $remoting = $null
            if ($SkipPSRemoting) {
                Write-Message -Level Verbose -Message "Checking remote access will be skipped"
            } else {
                Write-Message -Level Verbose -Message "Checking remote access"
                try {
                    $null = Invoke-Command2 -ComputerName $instance.ComputerName -Credential $Credential -ScriptBlock { Get-ChildItem } -ErrorAction Stop
                    $remoting = $true
                } catch {
                    $remoting = $_
                }
            }

            # Test Connection first using Ping class which requires ICMP access then fail back to tcp if pings are blocked
            Write-Message -Level Verbose -Message "Testing ping to $($instance.ComputerName)"
            $ping = New-Object System.Net.NetworkInformation.Ping
            $timeout = 1000 #milliseconds

            try {
                $reply = $ping.Send($instance.ComputerName, $timeout)
                $pingable = $reply.Status -eq 'Success'
            } catch {
                $pingable = $false
            }

            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                $connectSuccess = $true
                $instanceName = $server.InstanceName
                if (-not $instanceName) {
                    $instanceName = $instance.InstanceName
                }

                $username = $server.ConnectionContext.TrueLogin
                if ($username -like "*\*") {
                    $authType = "Windows Authentication"
                } else {
                    $authType = "SQL Authentication"
                }

                # TCP Port
                try {
                    $tcpport = (Get-DbaTcpPort -SqlInstance $instance -SqlCredential $SqlCredential -Credential $Credential -EnableException).Port
                } catch {
                    $tcpport = $_
                }

                # Auth Scheme
                try {
                    $authscheme = (Test-DbaConnectionAuthScheme -SqlInstance $server -EnableException).AuthScheme
                } catch {
                    $authscheme = $_
                }
            } catch {
                $connectSuccess = $false
                $instanceName = $instance.InstanceName
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance
            }

            [PSCustomObject]@{
                ComputerName         = $resolved.ComputerName
                InstanceName         = $instanceName
                SqlInstance          = $instance.FullSmoName
                SqlVersion           = $server.Version
                ConnectingAsUser     = $username
                ConnectSuccess       = $connectSuccess
                AuthType             = $authType
                AuthScheme           = $authscheme
                TcpPort              = $tcpport
                IPAddress            = $resolved.IPAddress
                NetBiosName          = $resolved.FullComputerName
                IsPingable           = $pingable
                PSRemotingAccessible = $remoting
                DomainName           = $resolved.Domain
                LocalWindows         = $localInfo.Windows
                LocalPowerShell      = $localInfo.PowerShell
                LocalCLR             = $localInfo.CLR
                LocalSMOVersion      = $localInfo.SMO
                LocalDomainUser      = $localInfo.DomainUser
                LocalRunAsAdmin      = $localInfo.RunAsAdmin
                LocalEdition         = $localInfo.Edition
            }
        }
    }
}