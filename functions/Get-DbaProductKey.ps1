function Get-DbaProductKey {
    <#
    .SYNOPSIS
        Gets SQL Server Product Keys from local or destination SQL Servers. Works with SQL Server 2005-2017

    .DESCRIPTION
        This command find the product key for all installed instances. Clustered instances are supported as well.

        Uses key decoder by Jakob Bindslet (http://goo.gl/1jiwcB)

    .PARAMETER ComputerName
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Login to the target Windows instance using alternative credentials. Windows Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER SqlCredential
        This command logs into the SQL instance to gather additional information.

        Use this parameter to connect to the discovered SQL instances using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
        PS C:\> Get-DbaProductKey -ComputerName winxp, sqlservera, sqlserver2014a, win2k8

        Gets SQL Server versions, editions and product keys for all instances within each server or workstation.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline, Mandatory)]
        [Alias("SqlInstance")]
        [DbaInstanceParameter[]]$ComputerName,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [switch]$EnableException
    )

    begin {
        $scriptblock = {
            $versionMajor = $args[0]
            $instanceReg = $args[1]
            $edition = $args[2]

            Function Unlock-SqlInstanceKey {
                [CmdletBinding()]
                param (
                    [Parameter(Mandatory)]
                    [byte[]]$data,
                    [int]$version
                )
                try {
                    if ($version -ge 11) {
                        $binArray = ($data)[0 .. 66]
                    } else {
                        $binArray = ($data)[52 .. 66]
                    }
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
            $localmachine = [Microsoft.Win32.RegistryHive]::LocalMachine
            $defaultview = [Microsoft.Win32.RegistryView]::Default
            $reg = [Microsoft.Win32.RegistryKey]::OpenBaseKey($localmachine, $defaultview)

            switch ($versionMajor) {
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
            if ($edition -notlike "*Express*") {
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
                    $sqlkey = "Could not read Product Key from registry on $env:COMPUTERNAME"
                } else {
                    try {
                        $sqlkey = Unlock-SqlInstanceKey $binarykey $versionMajor
                    } catch {
                        $sqlkey = "Unable to unlock key"
                    }
                }
            } else {
                $sqlkey = "SQL Server Express Edition"
            }

            [pscustomobject]@{
                Version = $sqlversion
                Key     = $sqlkey
            }
            $reg.Close()
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            try {
                $registryroot = Get-DbaRegistryRoot -ComputerName $computer.ComputerName -Credential $Credential -EnableException
            } catch {
                Stop-Function -Message "Can't access registry for $($computer.ComputerName). Is the Remote Registry service started?" -Continue
            }

            if (-not $registryroot) {
                Stop-Function -Message "No instances found on $($computer.ComputerName)" -Continue
            }

            # Get Product Keys for all instances on the server.
            foreach ($instanceReg in $registryroot) {
                try {
                    $server = Connect-SqlInstance -SqlInstance $instanceReg.SqlInstance -SqlCredential $SqlCredential -MinimumVersion 10
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instanceReg.SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $instanceReg.SqlInstance -Continue
                }

                $servicePack = $server.ProductLevel
                $versionMajor = $server.VersionMajor
                Write-Message -Level Debug -Message "$instance $instanceName version is $($server.VersionMajor)"

                try {
                    $results = Invoke-Command2 -ComputerName $computer.ComputerName -Credential $Credential -ScriptBlock $scriptblock -ArgumentList $server.VersionMajor, $instanceReg, $server.Edition
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_
                }

                [pscustomobject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Version      = $results.Version
                    Edition      = $server.Edition
                    Key          = $results.Key
                }
            }
        }
    }
}