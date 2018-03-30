function Get-DbaDefaultPath {
    <#
    .SYNOPSIS
        Gets the default SQL Server paths for data, logs and backups

    .DESCRIPTION
        Gets the default SQL Server paths for data, logs and backups

    .PARAMETER SqlInstance
        The SQL Server instance, or instances.

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Config
        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDefaultPath

    .EXAMPLE
        Get-DbaDefaultPath -SqlInstance sql01\sharepoint

        Returns the default file paths for sql01\sharepoint

    .EXAMPLE
        $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
        $servers | Get-DbaDefaultPath

        Returns the default file paths for "sql2014","sql2016" and "sqlcluster\sharepoint"

#>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]
        $SqlCredential,
        [Alias('Silent')]
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $datapath = $server.DefaultFile

            if ($datapath.Length -eq 0) {
                $datapath = $server.ConnectionContext.ExecuteScalar("SELECT SERVERPROPERTY('InstanceDefaultDataPath')")
            }

            <# eh, this can be a failback if we can get it to work ;)
            if ($datapath -eq [System.DBNull]::Value -or $datapath.Length -eq 0) {
                $datapath = $server.ConnectionContext.ExecuteScalar("master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'DefaultData'")
            }
            #>

            if ($datapath -eq [System.DBNull]::Value -or $datapath.Length -eq 0) {
                $datapath = Split-Path (Get-DbaDatabase -SqlInstance $server -Database model).FileGroups[0].Files[0].FileName
            }

            if ($datapath.Length -eq 0) {
                $datapath = $server.Information.MasterDbPath
            }

            $logpath = $server.DefaultLog

            if ($logpath.Length -eq 0) {
                $logpath = $server.ConnectionContext.ExecuteScalar("SELECT SERVERPROPERTY('InstanceDefaultLogPath')")
            }

            <#
            eh, this can be a failback if we can get it to work ;)
            right now, the Get-Database thing below causes enumeration which slows stuff down on systems with hundreds of dbs
            if ($logpath -eq [System.DBNull]::Value -or $logpath.Length -eq 0) {
                $logpath = $server.ConnectionContext.ExecuteScalar("master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'DefaultLog'")
            }
            #>

            if ($logpath -eq [System.DBNull]::Value -or $logpath.Length -eq 0) {
                $logpath = Split-Path (Get-DbaDatabase -SqlInstance $server -Database model).LogFiles.FileName
            }

            if ($logpath.Length -eq 0) {
                $logpath = $server.Information.MasterDbLogPath
            }

            $datapath = $datapath.Trim().TrimEnd("\")
            $logpath = $logpath.Trim().TrimEnd("\")

            [pscustomobject]@{
                ComputerName = $server.NetName
                InstanceName = $server.ServiceName
                SqlInstance  = $server.DomainInstanceName
                Data         = $datapath
                Log          = $logpath
                Backup       = $server.BackupDirectory
                ErrorLog     = $server.ErrorLogPath
            }
        }
    }
}