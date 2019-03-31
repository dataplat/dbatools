function Get-DbaStartupProcedure {
    <#
    .SYNOPSIS
        Get-DbaStartupProcedure gets startup procedures (user defined procedures within master database) from a SQL Server.

    .DESCRIPTION
        By default, this command returns for each SQL Server instance passed in, the name and schema for all procedures in the master database that are marked as a startup procedure.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

        $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

        Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

        To connect to SQL Server as a different Windows user, run PowerShell as that user.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Procedure, Startup, StartupProcedure
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaStartupProcedure

    .EXAMPLE
        PS C:\> Get-DbaStartupProcedure -SqlInstance SqlBox1\Instance2

        Returns an object with all startup procedures for the Instance2 instance on SqlBox1

    .EXAMPLE
        PS C:\> Get-DbaStartupProcedure -SqlInstance winserver\sqlexpress, sql2016

        Returns an object with SQL Server start time, uptime as TimeSpan object, uptime as a string, and Windows host boot time, host uptime as TimeSpan objects and host uptime as a string for the sqlexpress instance on host winserver  and the default instance on host sql2016

    .EXAMPLE
        PS C:\> Get-DbaCmsRegServer -SqlInstance sql2014 | Get-DbaStartupProcedure

        Returns an object with all startup procedures for every server listed in the Central Management Server on sql2014

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Verbose -Message "Getting startup procedures for $servername"

            $startupProcs = $server.EnumStartupProcedures()

            if ($startupProcs.Rows.Count -gt 0) {
                foreach ($proc in $startupProcs) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        SqlInstance  = $server.DomainInstanceName
                        InstanceName = $server.ServiceName
                        Schema       = $proc.Schema
                        Name         = $proc.Name
                    }
                }
            }
        }
    }
}