function Get-DbaSqlLogConfig {
    <#
        .SYNOPSIS
            Pulls the configuration for the ErrorLog on a given SQL Server instance
        .DESCRIPTION
            Pulls the configuration for the ErrorLog on a given SQL Server instance.
            Includes number of log files configured and size in KB (SQL Server 2012+ only)

        .PARAMETER SqlInstance
            The target SQL Server instance(s)

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Configure, Instance, ErrorLog
            Author: Shawn Melton (@wsmelton)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaSqlLogConfig

       .EXAMPLE
            Get-DbaSqlLogConfig -SqlInstance server2017,server2014

            Returns error log configuration for server2017 and server2014
    #>
    [cmdletbinding()]
    param(
        [Parameter(ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $numLogs = $server.NumberOfLogFiles
            $logSize =
                if ($server.VersionMajor -ge 11) {
                    $server.ErrorLogSizeKb
                }
                else {
                    $null
                }

            [PSCustomObject]@{
                ComputerName    = $server.NetName
                InstanceName    = $server.ServiceName
                SqlInstance     = $server.DomainInstanceName
                NumberErrorLogs = $numLogs
                ErrorLogSizeKb  = $logSize
            }
        }
    }
}