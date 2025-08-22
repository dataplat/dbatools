function Test-DbaMaxMemory {
    <#
    .SYNOPSIS
        Calculates recommended SQL Server max memory settings to prevent OS memory pressure and optimize performance.

    .DESCRIPTION
        Analyzes server memory and SQL Server instances to calculate optimal max memory configuration settings. Uses a tiered algorithm that reserves appropriate memory for the operating system based on total server memory, accounting for multiple SQL instances and other SQL services like SSAS, SSRS, or SSIS. Compares current max memory settings against recommended values to help identify misconfigured servers that could cause memory pressure or performance issues. Based on Jonathan Kehayias's memory calculation methodology, this provides general recommendations that should be validated against your specific environment and workload requirements.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Windows Credential with permission to log on to the server running the SQL instance

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: MaxMemory, Memory
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaMaxMemory

    .EXAMPLE
        PS C:\> Test-DbaMaxMemory -SqlInstance sqlcluster,sqlserver2012

        Calculate the 'Max Server Memory' for SQL Server instances sqlcluster and sqlserver2012

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlcluster | Test-DbaMaxMemory

        Calculate the 'Max Server Memory' settings for all servers within the SQL Server Central Management Server "sqlcluster"

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlcluster | Test-DbaMaxMemory | Where-Object { $_.MaxValue -gt $_.Total } | Set-DbaMaxMemory

        Find all servers in CMS that have Max SQL memory set to higher than the total memory of the server (think 2147483647) and set it to recommended value.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Verbose -Target $instance -Message "Retrieving maximum memory statistics from $instance"
            $serverMemory = Get-DbaMaxMemory -SqlInstance $server
            try {
                if ($isLinux -or $isMacOS) {
                    Write-Message -Level Warning -Target $instance -Message "Can't determine instance count from Linux or Mac. Defaulting to 1."
                    $instanceCount = 1
                } else {
                    Write-Message -Level Verbose -Target $instance -Message "Retrieving number of instances from $($instance.ComputerName)"
                    if ($Credential) {
                        $serverService = Get-DbaService -ComputerName $instance -Credential $Credential -EnableException
                    } else {
                        $serverService = Get-DbaService -ComputerName $instance -EnableException
                    }

                    $instanceCount = ($serverService | Where-Object State -Like Running | Where-Object InstanceName | Where-Object ServiceType -eq 'Engine' | Group-Object InstanceName | Measure-Object Count).Count

                    if ($instanceCount -eq 0) {
                        Write-Message -Level Warning -Message "Couldn't get accurate SQL Server instance count on $instance. Defaulting to 1."
                        $instanceCount = 1
                    }

                    $otherConsumers = $serverService | Where-Object ServiceType -in ('SSAS', 'SSRS', 'SSIS')
                    if ($null -ne $otherConsumers) {
                        Write-Message -Level Warning -Message "The memory calculation may be inaccurate as the following SQL components have also been detected: $($otherConsumers.ServiceType -join(','))"
                    }


                }
            } catch {
                Write-Message -Level Warning -Message "Couldn't get accurate SQL Server instance count on $instance. Defaulting to 1." -Target $instance -ErrorRecord $_
                $instanceCount = 1
            }

            if ($null -eq $serverMemory) {
                continue
            }
            $reserve = 1

            $maxMemory = $serverMemory.MaxValue
            $totalMemory = $serverMemory.Total

            if ($totalMemory -ge 4096) {
                $currentCount = $totalMemory
                while ($currentCount / 4096 -gt 0) {
                    if ($currentCount -gt 16384) {
                        $reserve += 1
                        $currentCount += -8192
                    } else {
                        $reserve += 1
                        $currentCount += -4096
                    }
                }
                $recommendedMax = [int]($totalMemory - ($reserve * 1024))
            } else {
                $recommendedMax = $totalMemory * .5
            }

            $recommendedMax = $recommendedMax / $instanceCount

            [PSCustomObject]@{
                ComputerName     = $server.ComputerName
                InstanceName     = $server.ServiceName
                SqlInstance      = $server.DomainInstanceName
                InstanceCount    = $instanceCount
                Total            = [int]$totalMemory
                MaxValue         = [int]$maxMemory
                RecommendedValue = [int]$recommendedMax
                Server           = $server # This will allowing piping a non-connected object
            } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, InstanceCount, Total, MaxValue, RecommendedValue
        }
    }
}