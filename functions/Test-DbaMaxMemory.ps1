#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Test-DbaMaxMemory {
    <#
        .SYNOPSIS
            Calculates the recommended value for SQL Server 'Max Server Memory' configuration setting. Works on SQL Server 2000-2014.

        .DESCRIPTION
            Inspired by Jonathan Kehayias's post about SQL Server Max memory (http://bit.ly/sqlmemcalc), this script displays a SQL Server's: total memory, currently configured SQL max memory, and the calculated recommendation.

            Jonathan notes that the formula used provides a *general recommendation* that doesn't account for everything that may be going on in your specific environment.

        .PARAMETER SqlInstance
            Allows you to specify a comma separated list of servers to query.

        .PARAMETER SqlCredential
            Windows or Sql Login Credential with permission to log into the SQL instance

        .PARAMETER Credential
            Windows Credential with permission to log on to the server running the SQL instance

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: MaxMemory, Memory
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Test-DbaMaxMemory

        .EXAMPLE
            Test-DbaMaxMemory -SqlInstance sqlcluster,sqlserver2012

            Calculate the 'Max Server Memory' settings for all servers within the SQL Server Central Management Server "sqlcluster"

        .EXAMPLE
            Test-DbaMaxMemory -SqlInstance sqlcluster | Where-Object { $_.SqlMaxMB -gt $_.TotalMB } | Set-DbaMaxMemory

            Find all servers in CMS that have Max SQL memory set to higher than the total memory of the server (think 2147483647) and set it to recommended value.
    #>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level VeryVerbose -Message "Processing $instance" -Target $instance

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Verbose -Target $instance -Message "Retrieving maximum memory statistics from $instance"
            $serverMemory = Get-DbaMaxMemory -SqlInstance $server
            try {
                Write-Message -Level Verbose -Target $instance -Message "Retrieving number of instances from $($instance.ComputerName)"
                if ($Credential) {
                    $serverService = Get-DbaSqlService -ComputerName $instance -Credential $Credential -EnableException
                }
                else {
                    $serverService = Get-DbaSqlService -ComputerName $instance -EnableException
                }
                $instanceCount = ($serverService | Where-Object State -Like Running | Where-Object InstanceName | Group-Object InstanceName | Measure-Object Count).Count
            }
            catch {
                Write-Message -Level Warning -Message "Couldn't get accurate SQL Server instance count on $instance. Defaulting to 1." -Target $instance -ErrorRecord $_
                $instanceCount = 1
            }

            if ($null -eq $serverMemory) {
                continue
            }
            $reserve = 1

            $maxMemory = $serverMemory.SqlMaxMB
            $totalMemory = $serverMemory.TotalMB

            if ($totalMemory -ge 4096) {
                $currentCount = $totalMemory
                while ($currentCount / 4096 -gt 0) {
                    if ($currentCount -gt 16384) {
                        $reserve += 1
                        $currentCount += -8192
                    }
                    else {
                        $reserve += 1
                        $currentCount += -4096
                    }
                }
                $recommendedMax = [int]($totalMemory - ($reserve * 1024))
            }
            else {
                $recommendedMax = $totalMemory * .5
            }

            $recommendedMax = $recommendedMax / $instanceCount

            [pscustomobject]@{
                ComputerName  = $server.NetName
                InstanceName  = $server.ServiceName
                SqlInstance   = $server.DomainInstanceName
                InstanceCount = $instanceCount
                TotalMB       = [int]$totalMemory
                SqlMaxMB      = [int]$maxMemory
                RecommendedMB = [int]$recommendedMax
            } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, InstanceCount, TotalMB, SqlMaxMB, RecommendedMB
        }
    }
}