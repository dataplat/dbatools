#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

Function Test-DbaConnection {
<#
    .SYNOPSIS
        Exported function. Tests a the connection to a single instance and shows the output.
    
    .DESCRIPTION
        Tests a the connection to a single instance and shows the output.
    
    .PARAMETER SqlInstance
        The SQL Server Instance to test connection against
    
    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
        
        $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
        
        Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.
    
    .PARAMETER Silent
        Replaces user friendly yellow warnings with bloody red exceptions of doom!
        Use this if you want the function to throw terminating errors you want to catch.
    
    .EXAMPLE
        Test-DbaConnection sql01
        
        Sample output:
        
        Local PowerShell Enviornment
        
        Windows    : 10.0.10240.0
        PowerShell : 5.0.10240.16384
        CLR        : 4.0.30319.42000
        SMO        : 13.0.0.0
        DomainUser : True
        RunAsAdmin : False
        
        SQL Server Connection Information
        
        ServerName         : sql01
        BaseName           : sql01
        InstanceName       : (Default)
        AuthType           : Windows Authentication (Trusted)
        ConnectingAsUser   : ad\dba
        ConnectSuccess     : True
        SqlServerVersion   : 12.0.2370
        AddlConnectInfo    : N/A
        RemoteServer       : True
        IPAddress          : 10.0.1.4
        NetBIOSname        : SQLSERVER2014A
        RemotingAccessible : True
        Pingable           : True
        DefaultSQLPortOpen : True
        RemotingPortOpen   : True
    
    .NOTES
        Tags: CIM
        Original Author: Chrissy LeMaire
        dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
        Copyright (C) 2016 Chrissy LeMaire
        This program is free software: you can redistribute it and/or modify
        it under the terms of the GNU General Public License as published by
        the Free Software Foundation, either version 3 of the License, or
        (at your option) any later version.
        This program is distributed in the hope that it will be useful,
        but WITHOUT ANY WARRANTY; without even the implied warranty of
        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
        GNU General Public License for more details.
        You should have received a copy of the GNU General Public License
        along with this program.  If not, see <http://www.gnu.org/licenses/>.
#>    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]
        $SqlInstance,
        
        [System.Management.Automation.PSCredential]
        $SqlCredential,
        
        [switch]
        $Silent
    )
    
    Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Test-SqlConnection
    
    
    # Get local enviornment
    Write-Message -Level Verbose -Message "Getting local enivornment information"
    $localinfo = [pscustomobject]@{
        Windows = [environment]::OSVersion.Version.ToString()
        PowerShell = $PSVersionTable.PSversion.ToString()
        CLR = $PSVersionTable.CLRVersion.ToString()
        SMO = ((([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Fullname -like "Microsoft.SqlServer.SMO,*" }).FullName -Split ", ")[1]).TrimStart("Version=")
        DomainUser = $env:computername -ne $env:USERDOMAIN
        RunAsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    }
    
    $serverinfo = @{ } | Select-Object ServerName, BaseName, InstanceName, AuthType, ConnectingAsUser, ConnectSuccess, SqlServerVersion, AddlConnectInfo, RemoteServer, IPAddress, NetBIOSname, RemotingAccessible, Pingable, DefaultSQLPortOpen, RemotingPortOpen
    
    $serverinfo.ServerName = $SqlInstance.FullSmoName
    
    $baseaddress = $SqlInstance.ComputerName
    $instance = $SqlInstance.InstanceName
    if ([string]::IsNullOrEmpty($instance)) { $instance = "(Default)" }
    
    if ($baseaddress -eq "." -or $baseaddress -eq $env:COMPUTERNAME) {
        $ipaddr = "."
        $hostname = $env:COMPUTERNAME
        $baseaddress = $env:COMPUTERNAME
    }
    
    $serverinfo.BaseName = $baseaddress
    $remote = [dbavalidate]::IsLocalHost($env:COMPUTERNAME)
    $serverinfo.InstanceName = $instance
    $serverinfo.RemoteServer = $remote
    
    Write-Message -Level Verbose -Message "Resolving IP address"
    try {
        $hostentry = [System.Net.Dns]::GetHostEntry($baseaddress)
        $ipaddr = ($hostentry.AddressList | Where-Object { $_ -notlike '169.*' } | Select-Object -First 1).IPAddressToString
    }
    catch { $ipaddr = "Unable to resolve" }
    
    $serverinfo.IPAddress = $ipaddr
    
    Write-Message -Level Verbose -Message "Resolving NetBIOS name"
    try {
        $hostname = (Get-DbaCmObject -ClassName Win32_NetworkAdapterConfiguration -ComputerName $ipaddr -Silent | Where-Object IPEnabled).PSComputerName
                
        if ([string]::IsNullOrEmpty($hostname)) { $hostname = (nbtstat -A $ipaddr | Where-Object { $_ -match '\<00\>  UNIQUE' } | ForEach-Object { $_.SubString(4, 14) }).Trim() }
    }
    catch { $hostname = "Unknown" }
    
    $serverinfo.NetBIOSname = $hostname
    
    
    if ($remote -eq $true) {
        # Test for WinRM #Test-WinRM neh
        Write-Message -Level Verbose -Message "Checking remote acccess"
        winrm id -r:$hostname 2>$null | Out-Null
        if ($LastExitCode -eq 0) { $remoting = $true }
        else { $remoting = $false }
        
        $serverinfo.RemotingAccessible = $remoting
        
        Write-Message -Level Verbose -Message "Testing raw socket connection to PowerShell remoting port"
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $tcp.Connect($baseaddress, 135)
            $tcp.Close()
            $tcp.Dispose()
            $remotingport = $true
        }
        catch { $remotingport = $false }
        
        $serverinfo.RemotingPortOpen = $remotingport
    }
    
    # Test Connection first using Test-Connection which requires ICMP access then failback to tcp if pings are blocked
    Write-Message -Level Verbose -Message "Testing ping to $baseaddress"
    $serverinfo.Pingable = Test-Connection -ComputerName $baseaddress -Count 1 -Quiet
    
    # SQL Server connection
    if ($instance -eq "(Default)") {
        Write-Message -Level Verbose -Message "Testing raw socket connection to default SQL port"
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $tcp.Connect($baseaddress, 1433)
            $tcp.Close()
            $tcp.Dispose()
            $sqlport = $true
        }
        catch { $sqlport = $false }
        $serverinfo.DefaultSQLPortOpen = $sqlport
    }
    else { $serverinfo.DefaultSQLPortOpen = "N/A" }
    
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server $SqlInstance.FullSmoName
    
    try {
        if ($null -ne $SqlCredential) {
            $username = ($SqlCredential.username).TrimStart("\")
            
            if ($username -like "*\*") {
                $username = $username.Split("\")[1]
                $authtype = "Windows Authentication with Credential"
                $server.ConnectionContext.LoginSecure = $true
                $server.ConnectionContext.ConnectAsUser = $true
                $server.ConnectionContext.ConnectAsUserName = $username
                $server.ConnectionContext.ConnectAsUserPassword = ($SqlCredential).GetNetworkCredential().Password
            }
            else {
                $authtype = "SQL Authentication"
                $server.ConnectionContext.LoginSecure = $false
                $server.ConnectionContext.set_Login($username)
                $server.ConnectionContext.set_SecurePassword($SqlCredential.Password)
            }
        }
        else {
            $authtype = "Windows Authentication (Trusted)"
            $username = "$env:USERDOMAIN\$env:username"
        }
    }
    catch {
        Write-Message -Level Warning -Message $_ -ErrorRecord $_
        
        $authtype = "Windows Authentication (Trusted)"
        $username = "$env:USERDOMAIN\$env:username"
    }
    
    $serverinfo.ConnectingAsUser = $username
    $serverinfo.AuthType = $authtype
    
    
    Write-Message -Level Verbose -Message "Attempting to connect to $SqlInstance as $username "
    try {
        $server.ConnectionContext.ConnectTimeout = 10
        $server.ConnectionContext.Connect()
        $connectSuccess = $true
        $version = $server.Version.ToString()
        $addlinfo = "N/A"
        $server.ConnectionContext.Disconnect()
    }
    catch {
        $connectSuccess = $false
        $version = "N/A"
        $addlinfo = $_.Exception
    }
    
    $serverinfo.ConnectSuccess = $connectSuccess
    $serverinfo.SqlServerVersion = $version
    $serverinfo.AddlConnectInfo = $addlinfo
    
    Write-Message -Level Verbose -Message "Local PowerShell Environment" -Target $localinfo
    $localinfo | Select-Object Windows, PowerShell, CLR, SMO, DomainUser, RunAsAdmin
    
    Write-Message -Level Verbose -Message "SQL Server Connection Information" -Target $serverinfo
    $serverinfo | Select-Object ServerName, BaseName, InstanceName, AuthType, ConnectingAsUser, ConnectSuccess, SqlServerVersion, AddlConnectInfo, RemoteServer, IPAddress, NetBIOSname, RemotingAccessible, Pingable, DefaultSQLPortOpen, RemotingPortOpen
}
