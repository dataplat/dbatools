#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Get-DbaMaxMemory {
    <#
        .SYNOPSIS
            Gets the 'Max Server Memory' configuration setting and the memory of the server.  Works on SQL Server 2000-2014.

        .DESCRIPTION
            This command retrieves the SQL Server 'Max Server Memory' configuration setting as well as the total  physical installed on the server.

        .PARAMETER SqlInstance
            Allows you to specify a comma separated list of servers to query.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

            $cred = Get-Credential, then pass $cred variable to this parameter.

            Windows Authentication will be used when SqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.

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
            https://dbatools.io/Get-DbaMaxMemory

        .EXAMPLE
            Get-DbaMaxMemory -SqlInstance sqlcluster,sqlserver2012

            Get memory settings for all servers within the SQL Server Central Management Server "sqlcluster".

        .EXAMPLE
            Get-DbaMaxMemory -SqlInstance sqlcluster | Where-Object { $_.SqlMaxMB -gt $_.TotalMB }

            Find all servers in Server Central Management Server that have 'Max Server Memory' set to higher than the total memory of the server (think 2147483647)
    #>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $totalMemory = $server.PhysicalMemory

            # Some servers under-report by 1MB.
            if (($totalMemory % 1024) -ne 0) {
                $totalMemory = $totalMemory + 1
            }

            [pscustomobject]@{
                ComputerName = $server.NetName
                InstanceName = $server.ServiceName
                SqlInstance  = $server.DomainInstanceName
                TotalMB      = [int]$totalMemory
                SqlMaxMB     = [int]$server.Configuration.MaxServerMemory.ConfigValue
            } | Select-DefaultView -ExcludeProperty Server
        }
    }
}
