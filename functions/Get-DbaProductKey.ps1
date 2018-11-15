function Get-DbaProductKey {
    <#
    .SYNOPSIS
        Gets SQL Server Product Keys from local or destination SQL Servers. Works with SQL Server 2005-2016

    .DESCRIPTION
        Using a string of servers, a text file, or Central Management Server to provide a list of servers, this script will go to each server and get the product key for all installed instances. Clustered instances are supported as well. Requires regular user access to the SQL instances, SMO installed locally, Remote Registry enabled and accessible by the account running the script.

        Uses key decoder by Jakob Bindslet (http://goo.gl/1jiwcB)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER SqlCms
        Deprecated, pipe in from Get-DbaCmsRegServer

    .PARAMETER ServersFromFile
        Deprecated, pipe in from Get-Content

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ProductKey
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaProductKey

    .EXAMPLE
        PS C:\> Get-DbaProductKey -SqlInstance winxp, sqlservera, sqlserver2014a, win2k8

        Gets SQL Server versions, editions and product keys for all instances within each server or workstation.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline, Mandatory)]
        [Alias("ServerInstance", "SqlServer", "SqlInstances")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$SqlCms,
        [string]$ServersFromFile,
        [switch]$EnableException
    )

    begin {
        Function Unlock-SqlInstanceKey {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [byte[]]$data,
                [int]$version
            )
            try {
                if ($version -ge 11) { $binArray = ($data)[0 .. 66] }
                else { $binArray = ($data)[52 .. 66] }
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
            } catch {
                $productkey = "Cannot decode product key."
            }
            return $productKey
        }
    }

    process {
        if ($SqlCms) {
            Stop-Function -Message "Please pipe in servers using Get-DbaCmsRegServer instead"
            return
        }

        If ($ServersFromFile) {
            Stop-Function -Message "Please pipe in servers using Get-Content instead"
            return
        }

        foreach ($instance in $SqlInstance) {
            $computerName = $instance.ComputerName
            try {
                $regRoots = Get-DbaRegistryRoot -ComputerName $computerName -EnableException
            } catch {
                Stop-Function -Message "Can't access registry for $computerName. Is the Remote Registry service started?" -Continue
            }
            if ($instance.IsLocalhost) {
                $localmachine = [Microsoft.Win32.RegistryHive]::LocalMachine
                $defaultview = [Microsoft.Win32.RegistryView]::Default
                $reg = [Microsoft.Win32.RegistryKey]::OpenBaseKey($localmachine, $defaultview)
            } else {
                # Get IP for remote registry access. It's the most reliable.
                try { $ipaddr = ([System.Net.Dns]::GetHostAddresses($computerName)).IPAddressToString }
                catch {
                    Stop-Function -Message "Can't resolve $computerName. Skipping." -Continue
                }

                try {
                    $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey("LocalMachine", $ipaddr)
                } catch {
                    Stop-Function -Message "Can't access registry for $computerName. Is the Remote Registry service started?" -Continue
                }
            }

            if (-not($regRoots)) {
                Stop-Function -Message "No instances found on $computerName. Skipping." -Continue
            }

            # Get Product Keys for all instances on the server.
            foreach ($instanceReg in $regRoots) {

                try {
                    $server = Connect-SqlInstance -SqlInstance $instanceReg.SqlInstance -SqlCredential $SqlCredential -MinimumVersion 10
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instanceReg.SqlInstance -Continue
                }

                $servicePack = $server.ProductLevel
                Write-Message -Level Debug -Message "$instance $instanceName version is $($server.VersionMajor)"

                switch ($server.VersionMajor) {
                    9 {
                        $sqlversion = "SQL Server 2005 $servicePack"
                        $findkeys = $reg.OpenSubKey("$($instanceReg.Path)\ProductID", $false)
                        foreach ($findkey in $findkeys.GetValueNames()) {
                            if ($findkey -like "DigitalProductID*") {
                                $key = @("$($instanceReg.Path)\ProductID\$findkey")
                            }
                        }
                    }
                    10 {
                        $sqlversion = "SQL Server 2008 $servicePack"
                        if ($server.VersionMinor -eq 50) {
                            $sqlversion = "SQL Server 2008 R2 $servicePack"
                        }
                        $key = @("$($instanceReg.Path)\Setup\DigitalProductID")
                    }
                    11 {
                        $key = @("$($instanceReg.Path)\Setup\DigitalProductID", "$($instanceReg.Path)\ClientSetup\DigitalProductID")
                        $sqlversion = "SQL Server 2012 $servicePack"
                    }
                    12 {
                        $key = @("$($instanceReg.Path)\Setup\DigitalProductID", "$($instanceReg.Path)\ClientSetup\DigitalProductID")
                        $sqlversion = "SQL Server 2014 $servicePack"
                    }
                    13 {
                        $key = @("$($instanceReg.Path)\Setup\DigitalProductID", "$($instanceReg.Path)\ClientSetup\DigitalProductID")
                        $sqlversion = "SQL Server 2016 $servicePack"
                    }
                    14 {
                        $key = @("$($instanceReg.Path)\Setup\DigitalProductID", "$($instanceReg.Path)\ClientSetup\DigitalProductID")
                        $sqlversion = "SQL Server 2017 $servicePack"
                    }
                    default {
                        Stop-Function -Message "SQL version not currently supported." -Continue
                    }
                }
                if ($server.Edition -notlike "*Express*") {
                    $sqlkey = ''
                    foreach ($k in $key) {
                        $subkey = Split-Path $k
                        $binaryvalue = Split-Path $k -Leaf
                        try {
                            $binarykey = $($reg.OpenSubKey($subkey)).GetValue($binaryvalue)
                            break
                        } catch {
                            $binarykey = $null
                        }
                    }

                    if ($null -eq $binarykey) {
                        $sqlkey = "Could not read Product Key from registry on $computername"
                    } else {
                        try {
                            $sqlkey = Unlock-SqlInstanceKey $binarykey $server.VersionMajor
                        } catch {
                            $sqlkey = "Unable to unlock key"
                        }
                    }
                } else {
                    $sqlkey = "SQL Server Express Edition"
                }

                [pscustomobject]@{
                    "SQL Instance" = $server.DomainInstanceName
                    "SQL Version"  = $sqlversion
                    "SQL Edition"  = $server.Edition
                    "Product Key"  = $sqlkey
                }
            }
            $reg.Close()
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Get-SqlServerKey
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Get-DbaSqlProductKey

        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Parameter CMSStore
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Parameter ServersFromFile
    }
}