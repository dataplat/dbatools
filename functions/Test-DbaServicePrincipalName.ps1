Function Test-DbaServicePrincipalName
{
<#
.SYNOPSIS 
Test-DbaServicePrincipalName will determine what SPNs *should* be set for a given server (and any instances of SQL running on it) and return
whether the SPNs are set or not.

.DESCRIPTION
This function is designed to take in a server name(s) and attempt to determine required SPNs. It was initially written to mimic the (previously)
broken functionality of the Microsoft Kerberos Configuration manager and SQL Server 2016. The functon will connect to a remote server and,
through WMI, discover all running intances of SQL Server. For any instances with TCP/IP enabled, the script will determine which port(s)
the instances are listening on and generate the required SPNs. For named instances NOT using dynamic ports, the script will generate a port-
based SPN for those instances as well.  At a minimum, the script will test a base, port-less SPN for each instance discovered.

Once the required SPNs are generated, the script will connect to Active Directory and search for any of the SPNs (if any) that are already
set.

The function will return a custom object(s) that contains the server name checked, the instance name discovered, the account the service is
running under, and what the "required" SPN should be. It will also return a boolean property indicating if the SPN is set in Active Directory
or not.

.PARAMETER Servername
The server name you want to discover any SQL Server instances on. This parameter is required.

.PARAMETER Credential
The credential you want to use to connect to the remote server and active directory. This parameter is required.

.PARAMETER Domain
If your server resides on a different domain than what your current session is authenticated against, you can specify a domain here. This
parameter is optional.

.NOTES 
Author: Drew Furgiuele (@pittfurg), http://www.port1433.com

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)

Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Test-DbaServicePrincipalName

.EXAMPLE   
Test-DbaServicePrincipalName -ServerName SQLSERVERA -Credential (Get-Credential)

Connects to a computer (SQLSERVERA) and queries WMI for all SQL instances and return "required" SPNs. It will then take each SPN it generates
and query Active Directory to make sure the SPNs are set.

.EXAMPLE   
Test-DbaServicePrincipalName -ServerName SQLSERVERA,SQLSERVERB -Credential (Get-Credential)

Connects to multiple computers (SQLSERVERA, SQLSERVERB) and queries WMI for all SQL instances and return "required" SPNs. 
It will then take each SPN it generates and query Active Directory to make sure the SPNs are set.

.EXAMPLE
Test-DbaServicePrincipalName -ServerName SQLSERVERC -Domain domain.something -Credential (Get-Credential)

Connects to a computer (SQLSERVERC) on a specified and queries WMI for all SQL instances and return "required" SPNs. 
It will then take each SPN it generates and query Active Directory to make sure the SPNs are set. Note that the credential you pass must
have be a valid login with appropriate rights on the domain you specify

#>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Servername,
        [Parameter(Mandatory = $true)]
        [PSCredential]$Credential,
        [Parameter(Mandatory = $false)]
        [string]$domain=$null
    )

    begin {
        if (!$domain) {
            $domain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
        }

        if ($Servername -notcontains $domain) {
            $servername = $servername + "." + $domain
        }
    }


    process {
        $Scriptblock = {
            $spns = @()
            $servername = $args[0]
            $mc = new-object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $servername
            $Instances = $mc.ServerInstances

            ForEach ($i in $Instances) {
                $spn = [pscustomobject] @{
                    ServerName = $servername
                    InstanceName = $null
                    InstanceServiceAccount = $null
                    RequiredSPN = $null
                    IsSet = $false
                }

                #is tcp enabled on this instance? If not, we don't need an spn, son
                if ((($i.serverprotocols | Where-Object {$_.Displayname -eq "TCP/IP"}).ProtocolProperties | Where-Object {$_.Name -eq "Enabled"}).Value -eq $true)
                {

                    #Each instance has a default SPN of MSSQLSvc\<fqdn> or MSSSQLSvc\<fqdn>:Instance    
                    if ($i.Name -eq "MSSQLSERVER") {
                        $spn.InstanceName = $i.name
                        $spn.RequiredSPN =  "MSSQLSvc/$servername"
                    } else {
                        $spn.InstanceName = $i.name
                        $spn.RequiredSPN = "MSSQLSvc/" + $servername + ":" + $i.name
                    }
                    $InstanceName = $spn.InstanceName
                    $spn.InstanceServiceAccount = (Get-WmiObject win32_service | Where-Object {$_.DisplayName -eq "SQL Server ($InstanceName)"}).startName
                    $spns += $spn
                }        
            }
        
            #Now, for each spn, do we need a port set? Only if TCP is enabled and NOT DYNAMIC!

            ForEach ($s in $spns)
            {
                $ips = (($instances | Where-Object {$_.name -eq $s.InstanceName}).ServerProtocols | Where-Object {$_.DisplayName -eq "TCP/IP" -and $_.IsEnabled -eq "True"}).IpAddresses
                $ports = @()
                $ipAllPort = $null
                ForEach ($ip in $ips) {
                    if ($ip.Name -eq "IPAll") {
                        $ipAllPort += ($ip.IPAddressProperties | Where-Object {$_.Name -eq "TCPPort"}).Value
                    } else {
                        $enabled = ($ip.IPAddressProperties | Where-Object {$_.Name -eq "Enabled"}).Value
                        $active = ($ip.IPAddressProperties | Where-Object {$_.Name -eq "Active"}).Value
                        $TcpDynamicPorts = ($ip.IPAddressProperties | Where-Object {$_.Name -eq "TcpDynamicPorts"}).Value # | Select-Object Value
                        if ($enabled -and $active -and $TcpDynamicPorts -eq "") {
                            $ports += ($ip.IPAddressProperties | Where-Object {$_.Name -eq "TCPPort"}).Value
                        }
                    }
                }
                if ($ipAllPort -ne "") {
                    $ports = $ipAllPort
                }
                $ports = $ports | Select-Object -Unique
                ForEach ($p in $ports) {
                    $spn = [pscustomobject] @{
                        ServerName = $servername
                        InstanceName = $s.InstanceName
                        InstanceServiceAccount = $s.InstanceServiceAccount
                        RequiredSPN = "MSSQLSvc/" + $servername + ":" + $p
                        IsSet = $false
                    }
                    $spns += $spn
                }

            }
            return $spns
        }

        $spns = Invoke-ManagedComputerCommand -ComputerName $servername -ScriptBlock $Scriptblock -ArgumentList $servername -Credential $Credential

        #Now query AD for each required SPN
        ForEach ($s in $spns) {
            $DN = "DC=" + $domain -Replace("\.",',DC=')
            $LDAP = "LDAP://$DN"
            $root = [ADSI]$LDAP
            $ADObject = New-Object System.DirectoryServices.DirectorySearcher
            $ADObject.SearchRoot = $root

            $serviceAccount = $s.InstanceServiceAccount

            if ($serviceaccount -like "*\*") {
                Write-Verbose "Account provided in in domain\user format, stripping out domain info..."
                $serviceaccount = ($serviceaccount.split("\"))[1]
            }
            if ($serviceaccount -like "*@") {
                Write-Verbose "Account provided in in user@domain format, stripping out domain info..."
                $serviceaccount = ($serviceaccount.split("@"))[0]
            }

            $ADObject.Filter = $("(&(samAccountName={0}))" -f $serviceaccount)

            $results = $ADObject.FindAll()

            if ($results.Count -gt 0) {
                if ($results.Properties.serviceprincipalname -contains $s.RequiredSPN) {
                    $s.IsSet = $true
                }
            }
        }
    }

    end {
        return $spns
    }
}