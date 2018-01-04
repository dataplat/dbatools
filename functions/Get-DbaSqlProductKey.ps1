function Get-DbaSqlProductKey {
    <#
.SYNOPSIS
Gets SQL Server Product Keys from local or destination SQL Servers. Works with SQL Server 2005-2016

.DESCRIPTION
Using a string of servers, a text file, or Central Management Server to provide a list of servers, this script will go to each server and get the product key for all installed instances. Clustered instances are supported as well. Requires regular user access to the SQL instances, SMO installed locally, Remote Registry enabled and accessible by the account running the script.

Uses key decoder by Jakob Bindslet (http://goo.gl/1jiwcB)

.PARAMETER SqlInstances
A comma separated list of servers. This can be the NetBIOS name, IP, or SQL instance name

.PARAMETER SqlCms
Compiles list of servers to inventory using all servers stored within a Central Management Server. Requires having SQL Management Studio installed.

.PARAMETER ServersFromFile
Uses a text file as input. The file must be formatted as such:
sqlserver1
sqlserver2

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$cred = Get-Credential, this pass this $cred to the param.

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.

.NOTES
Author: Chrissy LeMaire (@cl), netnerds.net
Tags: SQL, Product Key

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Get-DbaSqlProductKey

.EXAMPLE
Get-DbaSqlProductKey winxp, sqlservera, sqlserver2014a, win2k8
Gets SQL Server versions, editions and product keys for all instances within each server or workstation.

.EXAMPLE
Get-DbaSqlProductKey -SqlCms sqlserver01
Gets SQL Server versions, editions and product keys for all instances within sqlserver01's Central Management Server

.EXAMPLE
Get-DbaSqlProductKey -ServersFromFile C:\Scripts\servers.txt
Gets SQL Server versions, editions and product keys for all instances listed within C:\Scripts\servers.txt
#>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    Param (
        [parameter(Position = 0)]
        [Alias("ServerInstance", "SqlServer")]
        [string[]]$SqlInstances,
        # Central Management Server

        [string]$SqlCms,
        # File with one server per line

        [string]$ServersFromFile,
        [PSCredential]$SqlCredential
    )

    BEGIN {

        Function Unlock-SqlInstanceKey {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                [byte[]]$data,
                [int]$version
            )
            try {
                if ($version -ge 11) { $binArray = ($data)[0..66] }
                else { $binArray = ($data)[52..66] }
                $charsArray = "B", "C", "D", "F", "G", "H", "J", "K", "M", "P", "Q", "R", "T", "V", "W", "X", "Y", "2", "3", "4", "6", "7", "8", "9"
                for ($i = 24; $i -ge 0; $i--) {
                    $k = 0
                    for ($j = 14; $j -ge 0; $j--) {
                        $k = $k * 256 -bxor $binArray[$j]
                        $binArray[$j] = [math]::truncate($k / 24)
                        $k = $k % 24
                    }
                    $productKey = $charsArray[$k] + $productKey
                    if (($i % 5 -eq 0) -and ($i -ne 0)) {
                        $productKey = "-" + $productKey
                    }
                }
            }
            catch { $productkey = "Cannot decode product key." }
            return $productKey
        }
    }

    PROCESS {

        if ($SqlCms) {
            if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.RegisteredServers") -eq $null)
            { throw "Can't load CMS assemblies. You must have SQL Server Management Studio installed to use the -SqlCms switch." }

            Write-Verbose "Gathering SQL Servers names from Central Management Server"
            $server = Connect-SqlInstance -SqlInstance $SqlCms -SqlCredential $SqlCredential
            $sqlconnection = $server.ConnectionContext.SqlConnectionObject

            try { $cmstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sqlconnection) }
            catch { throw "Cannot access Central Management Server" }
            $dbstore = $cmstore.DatabaseEngineServerGroup
            $SqlInstances = $dbstore.GetDescendantRegisteredServers().servername
            # Add the CM server itself, which can't be stored in the CM server.
            $servers += $SqlCms
            $basenames = @()
            foreach ($server in $SqlInstances) { $basenames += $server.Split("\")[0] }
            $SqlInstances = $basenames | Get-Unique
        }

        If ($ServersFromFile) {
            if ((Test-Path $ServersFromFile) -eq $false) { throw "Could not find file: $ServersFromFile" }
            $SqlInstances = Get-Content $ServersFromFile
        }

        if ([string]::IsNullOrEmpty($SqlInstances)) { $SqlInstances = $env:computername }

        $basepath = "SOFTWARE\Microsoft\Microsoft SQL Server"
        # Loop through each server
        $objectCollection = @()
        foreach ($servername in $SqlInstances) {
            $servername = $servername.Split("\")[0]

            if ($servername -eq "." -or $servername -eq "localhost" -or $servername -eq $env:computername) {
                $localmachine = [Microsoft.Win32.RegistryHive]::LocalMachine
                $defaultview = [Microsoft.Win32.RegistryView]::Default
                $reg = [Microsoft.Win32.RegistryKey]::OpenBaseKey($localmachine, $defaultview)
            }
            else {
                # Get IP for remote registry access. It's the most reliable.
                try { $ipaddr = ([System.Net.Dns]::GetHostAddresses($servername)).IPAddressToString }
                catch { Write-Warning "Can't resolve $servername. Skipping."; continue }

                try {
                    $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey("LocalMachine", $ipaddr)
                }
                catch { Write-Warning "Can't access registry for $servername. Is the Remote Registry service started?"; continue }
            }

            $instances = $reg.OpenSubKey("$basepath\Instance Names\SQL", $false)
            if ($instances -eq $null) { Write-Warning "No instances found on $servername. Skipping."; continue }
            # Get Product Keys for all instances on the server.
            foreach ($instance in $instances.GetValueNames()) {
                if ($instance -eq "MSSQLSERVER") { $SqlInstance = $servername }
                else { $SqlInstance = "$servername\$instance" }

                $subkeys = $reg.OpenSubKey("$basepath", $false)
                $instancekey = $subkeys.GetSubKeynames() | Where-Object { $_ -like "*.$instance" }
                if ($instancekey -eq $null) { $instancekey = $instance } # SQL 2k5

                # Cluster instance hostnames are required for SMO connection
                $cluster = $reg.OpenSubKey("$basepath\$instancekey\Cluster", $false)
                if ($cluster -ne $null) {
                    $clustername = $cluster.GetValue("ClusterName")
                    if ($instance -eq "MSSQLSERVER") { $SqlInstance = $clustername }
                    else { $SqlInstance = "$clustername\$instance" }
                }

                Write-Verbose "Attempting to connect to $SqlInstance"
                try { $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential }
                catch { Write-Warning "Can't connect to $SqlInstance or access denied. Skipping."; continue }

                $servicePack = $server.ProductLevel
                Write-Debug "$servername $instance version is $($server.VersionMajor)"
                switch ($server.VersionMajor) {
                    9 {
                        $sqlversion = "SQL Server 2005 $servicePack"
                        $findkeys = $reg.OpenSubKey("$basepath\90\ProductID", $false)
                        foreach ($findkey in $findkeys.GetValueNames()) {
                            if ($findkey -like "DigitalProductID*") { $key = "$basepath\90\ProductID\$findkey" }
                        }
                    }
                    10 {
                        $sqlversion = "SQL Server 2008 $servicePack"
                        $key = "$basepath\MSSQL10"
                        if ($server.VersionMinor -eq 50) { $key += "_50"; $sqlversion = "SQL Server 2008 R2 $servicePack" }
                        $key += ".$instance\Setup\DigitalProductID"
                    }
                    11 { $key = "$basepath\110\Tools\Setup\DigitalProductID"; $sqlversion = "SQL Server 2012 $servicePack" }
                    12 { $key = "$basepath\120\Tools\Setup\DigitalProductID"; $sqlversion = "SQL Server 2014 $servicePack" }
                    13 { $key = "$basepath\130\Tools\Setup\DigitalProductID"; $sqlversion = "SQL Server 2016 $servicePack" }
                    default { Write-Warning "SQL version not currently supported."; continue }
                }
                if ($server.Edition -notlike "*Express*") {
                    try {
                        $subkey = Split-Path $key; $binaryvalue = Split-Path $key -leaf
                        $binarykey = $($reg.OpenSubKey($subkey)).GetValue($binaryvalue)
                    }
                    catch { $sqlkey = "Could not connect." }
                    try { $sqlkey = Unlock-SqlInstanceKey $binarykey $server.VersionMajor }
                    catch { }
                }
                else { $sqlkey = "SQL Server Express Edition" }
                $server.ConnectionContext.Disconnect()

                $object = New-Object PSObject -Property @{
                    "SQL Instance" = $SqlInstance
                    "SQL Version"  = $sqlversion
                    "SQL Edition"  = $server.Edition
                    "Product Key"  = $sqlkey
                }
                $objectCollection += $object
            }
            $reg.Close()
        }
        $objectCollection | Select "SQL Instance", "SQL Version", "SQL Edition", "Product Key"
    }

    END {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Get-SqlServerKey
    }
}
