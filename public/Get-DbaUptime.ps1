function Get-DbaUptime {
    <#
    .SYNOPSIS
        Retrieves uptime information for SQL Server instances and their hosting Windows servers

    .DESCRIPTION
        This function determines SQL Server uptime by checking the tempdb creation date and calculates Windows server uptime using CIM/WMI calls to get the last boot time. Essential for monitoring system stability, troubleshooting unexpected restarts, and generating compliance reports that require uptime documentation. Returns both raw TimeSpan objects for calculations and formatted strings for reporting, covering both the SQL Server service and the underlying Windows host.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Specifies Windows credentials to connect to the hosting server for retrieving Windows boot time and uptime information.
        Use this when you need different credentials to access the Windows server than your current PowerShell session, such as when querying servers in different domains or when running under a service account that lacks WMI access.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: CIM, Instance, Utility
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaUptime

    .EXAMPLE
        PS C:\> Get-DbaUptime -SqlInstance SqlBox1\Instance2

        Returns an object with SQL Server start time, uptime as TimeSpan object, uptime as a string, and Windows host boot time, host uptime as TimeSpan objects and host uptime as a string for the sqlexpress instance on winserver

    .EXAMPLE
        PS C:\> Get-DbaUptime -SqlInstance winserver\sqlexpress, sql2016

        Returns an object with SQL Server start time, uptime as TimeSpan object, uptime as a string, and Windows host boot time, host uptime as TimeSpan objects and host uptime as a string for the sqlexpress instance on host winserver  and the default instance on host sql2016

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2014 | Get-DbaUptime

        Returns an object with SQL Server start time, uptime as TimeSpan object, uptime as a string, and Windows host boot time, host uptime as TimeSpan objects and host uptime as a string for every server listed in the Central Management Server on sql2014

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [switch]$EnableException
    )

    begin {
        $nowutc = (Get-Date).ToUniversalTime()
    }
    process {
        # uses cim commands


        foreach ($instance in $SqlInstance) {
            if ($instance.Gettype().FullName -eq [System.Management.Automation.PSCustomObject] ) {
                $servername = $instance.SqlInstance
            } elseif ($instance.Gettype().FullName -eq [Microsoft.SqlServer.Management.Smo.Server]) {
                $servername = $instance.ComputerName
            } else {
                $servername = $instance.ComputerName;
            }

            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Verbose -Message "Getting start times for $servername"
            #Get tempdb creation date
            [dbadatetime]$SQLStartTime = $server.Databases["tempdb"].CreateDate
            $SQLUptime = New-TimeSpan -Start $SQLStartTime.ToUniversalTime() -End $nowutc
            $SQLUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($SQLUptime.Days), $($SQLUptime.Hours), $($SQLUptime.Minutes), $($SQLUptime.Seconds)

            $WindowsServerName = (Resolve-DbaNetworkName $servername -Credential $Credential).FullComputerName

            try {
                Write-Message -Level Verbose -Message "Getting WinBootTime via CimInstance for $servername"
                $WinBootTime = (Get-DbaOperatingSystem -ComputerName $windowsServerName -Credential $Credential -ErrorAction SilentlyContinue).LastBootTime
                $WindowsUptime = New-TimeSpan -start $WinBootTime.ToUniversalTime() -end $nowutc
                $WindowsUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($WindowsUptime.Days), $($WindowsUptime.Hours), $($WindowsUptime.Minutes), $($WindowsUptime.Seconds)
            } catch {
                try {
                    Write-Message -Level Verbose -Message "Getting WinBootTime via CimInstance DCOM"
                    $CimOption = New-CimSessionOption -Protocol DCOM
                    $CimSession = New-CimSession -Credential:$Credential -ComputerName $WindowsServerName -SessionOption $CimOption
                    [dbadatetime]$WinBootTime = ($CimSession | Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
                    $WindowsUptime = New-TimeSpan -start $WinBootTime.ToUniversalTime() -end $nowutc
                    $WindowsUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($WindowsUptime.Days), $($WindowsUptime.Hours), $($WindowsUptime.Minutes), $($WindowsUptime.Seconds)
                } catch {
                    Stop-Function -Message "Failure getting WinBootTime" -ErrorRecord $_ -Target $instance -Continue
                }
            }

            [PSCustomObject]@{
                ComputerName     = $WindowsServerName
                InstanceName     = $server.ServiceName
                SqlServer        = $server.Name
                SqlUptime        = $SQLUptime
                WindowsUptime    = $WindowsUptime
                SqlStartTime     = $SQLStartTime
                WindowsBootTime  = $WinBootTime
                SinceSqlStart    = $SQLUptimeString
                SinceWindowsBoot = $WindowsUptimeString
            }
        }
    }
}