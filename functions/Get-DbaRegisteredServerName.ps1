function Get-DbaRegisteredServerName {
    <#
.SYNOPSIS
Gets list of SQL Server names stored in SQL Server Central Management Server.

.DESCRIPTION
Returns a simple array of server names. Be aware of the dynamic parameter 'Group', which can be used to limit results to one or more groups you have created on the CMS. See get-help for examples.

.PARAMETER SqlInstance
The SQL Server instance. 

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 
Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Group
Auto-populated list of groups in SQL Server Central Management Server. You can specify one or more, comma separated.
		
.PARAMETER NoCmsServer
By default, the Central Management Server name is included in the list. Use -NoCmsServer to exclude the CMS itself.
	
.PARAMETER NetBiosName
Returns just the NetBios names of each server.
	
.PARAMETER IpAddr
Returns just the ip addresses of each server.
	
.NOTES 
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

.LINK
https://dbatools.io/Get-DbaRegisteredServerName

.EXAMPLE 
Get-DbaRegisteredServerName -SqlInstance sqlserver2014a

Gets a list of all server names from the Central Management Server on sqlserver2014a, using Windows Credentials

.EXAMPLE 
Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -SqlCredential $credential

Gets a list of all server names from the Central Management Server on sqlserver2014a, using SQL Authentication
		
.EXAMPLE 
Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -Group HR, Accounting
	
Gets a list of server names in the HR and Accounting groups from the Central Management Server on sqlserver2014a.
	
.EXAMPLE 
Get-DbaRegisteredServerName -SqlInstance sqlserver2014a -Group HR, Accounting -IpAddr
	
Gets a list of server IP addresses in the HR and Accounting groups from the Central Management Server on sqlserver2014a.
	
#>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [object]$SqlCredential,
        [switch]$NoCmsServer,
        [parameter(ParameterSetName = "NetBios")]
        [switch]$NetBiosName,
        [parameter(ParameterSetName = "IP")]
        [switch]$IpAddr
    )

    begin {
        $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        $sqlconnection = $server.ConnectionContext.SqlConnectionObject
		
        try {
            $cmstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sqlconnection)
        }
        catch {
            throw "Cannot access Central Management Server"
        }
    }

    process {

        # see notes at Get-ParamSqlCmsGroups
        Function Find-CmsGroup($CmsGrp, $base = '', $stopat) {
            $results = @()
            foreach ($el in $CmsGrp) {
                if ($base -eq '') {
                    $partial = $el.name
                }
                else {
                    $partial = "$base\$($el.name)"
                }
                if ($partial -eq $stopat) {
                    return $el
                }
                else {
                    foreach ($group in $el.ServerGroups) {
                        $results += Find-CmsGroup $group $partial $stopat
                    }
                }
            }
            return $results
        }
		
        $servers = @()
        if ($groups -ne $null) {
            foreach ($group in $groups) {
                $cms = Find-CmsGroup $cmstore.DatabaseEngineServerGroup.ServerGroups '' $group
                $servers += ($cms.GetDescendantRegisteredServers()).servername
            }
        }
        else {
            $cms = $cmstore.ServerGroups["DatabaseEngineServerGroup"]
            $servers = ($cms.GetDescendantRegisteredServers()).servername
        }
		
        if ($NoCmsServer -eq $false) {
            $servers += $SqlInstance
        }
    }
    end {
        if ($NetBiosName -or $IpAddr) {
            $ipcollection = @()
            $netbioscollection = @()
            $processed = @()
			
            foreach ($server in $servers) {
                if ($server -match '\\') {
                    $server = $server.Split('\')[0]
                }
				
                if ($processed -contains $server) { continue }
                $processed += $server 
				
                try {
                    Write-Verbose "Testing connection to $server and resolving IP address"
                    $ipaddress = ((Test-Connection $server -Count 1 -ErrorAction SilentlyContinue).Ipv4Address | Select-Object -First 1).IPAddressToString
                }
                catch {
                    Write-Warning "Could not resolve IP address for $server"
                    continue
                }
				
                if ($ipcollection -notcontains $ipaddress) { $ipcollection += $ipaddress }
				
                if ($NetBiosName) {
                    try {
                        $hostname = (Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter IPEnabled=TRUE -ComputerName $ipaddress -ErrorAction SilentlyContinue).PSComputerName
                        if ($hostname -is [array]) { $hostname = $hostname[0] }
                        Write-Verbose "Hostname resolved to $hostname"
                        if ($hostname -eq $null) { $hostname = (nbtstat -A $ipaddress | Where-Object { $_ -match '\<00\>  UNIQUE' } | ForEach-Object { $_.SubString(4, 14) }).Trim() }
                    }
                    catch {
                        Write-Warning "Could not resolve NetBios name for $server"
                        continue
                    }
					
                    if ($netbioscollection -notcontains $hostname) { $netbioscollection += $hostname }
                }
            }
			
            if ($NetBiosName) {
                return $netbioscollection
            }
            else {
                return $ipcollection
            }
        }
        else {
            return $servers
        }
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Get-SqlRegisteredServerName
    }
}