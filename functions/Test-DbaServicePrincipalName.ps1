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

