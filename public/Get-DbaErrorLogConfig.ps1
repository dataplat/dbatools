function Get-DbaErrorLogConfig {
    <#
    .SYNOPSIS
        Retrieves SQL Server error log configuration settings including file count, size limits, and storage location

    .DESCRIPTION
        Retrieves current error log configuration from SQL Server instances, showing how many log files are retained, where they're stored, and size limits if configured. This information helps DBAs understand log retention policies and troubleshoot logging issues without connecting to SQL Server Management Studio. Log size information is only available on SQL Server 2012 and later versions.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Instance, ErrorLog, Logging
        Author: Shawn Melton (@wsmelton), wsmelton.github.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaErrorLogConfig

    .EXAMPLE
        PS C:\> Get-DbaErrorLogConfig -SqlInstance server2017,server2014

        Returns error log configuration for server2017 and server2014

    #>
    [cmdletbinding()]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $numLogs = $server.NumberOfLogFiles
            $logSize =
            if ($server.VersionMajor -ge 11) {
                [dbasize]($server.ErrorLogSizeKb * 1024)
            } else {
                $null
            }

            [PSCustomObject]@{
                ComputerName = $server.ComputerName
                InstanceName = $server.ServiceName
                SqlInstance  = $server.DomainInstanceName
                LogCount     = $numLogs
                LogSize      = $logSize
                LogPath      = $server.ErrorLogPath
            }
        }
    }
}