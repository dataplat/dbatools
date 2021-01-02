function Get-DbaUptime {
    <#
    .SYNOPSIS
        Returns the uptime of the SQL Server instance, and if required the hosting windows server

    .DESCRIPTION
        By default, this command returns for each SQL Server instance passed in:
        SQL Instance last startup time, Uptime as a PS TimeSpan, Uptime as a formatted string
        Hosting Windows server last startup time, Uptime as a PS TimeSpan, Uptime as a formatted string

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Allows you to login to the computer (not SQL Server instance) using alternative Windows credentials.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: CIM
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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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