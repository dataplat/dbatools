function Get-DbaProductKey {
    <#
    .SYNOPSIS
        Retrieves SQL Server product keys from registry data for license compliance and inventory management.

    .DESCRIPTION
        Decodes SQL Server product keys from registry DigitalProductID entries across all installed instances on target computers. This is essential for license compliance auditing, asset inventory during migrations, and generating compliance reports for auditors. The command handles different SQL Server versions (2005+), supports clustered instances, and automatically identifies Express editions that don't require product keys. Works by connecting to each SQL instance to determine version and edition, then accessing registry data remotely to decode the binary product key information.

    .PARAMETER ComputerName
        Specifies the SQL Server instances or computer names to retrieve product keys from. Accepts multiple values for bulk operations.
        Use this when you need to audit license compliance across multiple servers or gather product key inventory during migrations.

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
        Tags: ProductKey, Utility
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaProductKey

    .OUTPUTS
        System.Management.Automation.PSCustomObject

        Returns one object per SQL Server instance found on the target computer(s) with license key information.

        Default display properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Version: The SQL Server version name (e.g., "SQL Server 2019", "SQL Server 2016")
        - Edition: The SQL Server edition (Enterprise, Standard, Express, Developer, etc.)
        - Key: The decoded product key in format XXXXX-XXXXX-XXXXX-XXXXX-XXXXX; returns "SQL Server Express Edition" for Express editions, or an error message if the key cannot be read or decoded from the registry

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
        $scriptBlock = {
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

                    $isNKey = ([math]::truncate($binArray[14] / 0x6) -band 0x1) -ne 0
                    if ($isNKey) {
                        $binArray[14] = $binArray[14] -band 0xF7
                    }
                    $last = 0

                    for ($i = 24; $i -ge 0; $i--) {
                        $k = 0
                        for ($j = 14; $j -ge 0; $j--) {
                            $k = $k * 256 -bxor $binArray[$j]
                            $binArray[$j] = [math]::truncate($k / 24)
                            $k = $k % 24
                        }
                        $productKey = $charsArray[$k] + $productKey
                        $last = $k
                    }

                    if ($isNKey) {
                        $part1 = $productKey.Substring(1, $last)
                        $part2 = $productKey.Substring(1, $productKey.Length - 1)
                        if ($last -eq 0) {
                            $productKey = "N" + $part2
                        } else {
                            $productKey = $part2.Insert($part2.IndexOf($part1) + $part1.Length, "N")
                        }
                    }

                    $productKey = $productKey.Insert(20, "-").Insert(15, "-").Insert(10, "-").Insert(5, "-")
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
                    $findkeys = $reg.OpenSubKey("$($instanceReg.Path)\ProductID", $false)
                    foreach ($findkey in $findkeys.GetValueNames()) {
                        if ($findkey -like "DigitalProductID*") {
                            $key = @("$($instanceReg.Path)\ProductID\$findkey")
                        }
                    }
                }
                10 {
                    $key = @("$($instanceReg.Path)\Setup\DigitalProductID")
                }
                default {
                    $key = @("$($instanceReg.Path)\Setup\DigitalProductID", "$($instanceReg.Path)\ClientSetup\DigitalProductID")
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

            [PSCustomObject]@{
                Key = $sqlkey
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
                    $server = Connect-DbaInstance -SqlInstance $instanceReg.SqlInstance -SqlCredential $SqlCredential -MinimumVersion 9
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instanceReg.SqlInstance -Continue
                }

                $versionMajor = $server.VersionMajor
                Write-Message -Level Debug -Message "$instance $instanceName version is $($server.VersionMajor)"

                try {
                    $results = Invoke-Command2 -ComputerName $computer.ComputerName -Credential $Credential -ScriptBlock $scriptBlock -ArgumentList $server.VersionMajor, $instanceReg, $server.Edition
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }

                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Version      = $server.GetSqlServerVersionName()
                    Edition      = $server.Edition
                    Key          = $results.Key
                }
            }
        }
    }
}