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
            Write-Message -Level Verbose -Message "Connecting to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dataPath = $server.DefaultFile
            if ($dataPath.Length -eq 0) {
                $dataPath = $server.ConnectionContext.ExecuteScalar("SELECT SERVERPROPERTY('InstanceDefaultdataPath')")
            }

            if ($dataPath -eq [System.DBNull]::Value -or $dataPath.Length -eq 0) {
                $dataPath = Split-Path (Get-DbaDatabase -SqlInstance $server -Database model).FileGroups[0].Files[0].FileName
            }

            if ($dataPath.Length -eq 0) {
                $dataPath = $server.Information.MasterDbPath
            }

            $logPath = $server.DefaultLog

            if ($logPath.Length -eq 0) {
                $logPath = $server.ConnectionContext.ExecuteScalar("SELECT SERVERPROPERTY('InstanceDefaultLogPath')")
            }

            if ($logPath -eq [System.DBNull]::Value -or $logPath.Length -eq 0) {
                $logPath = Split-Path (Get-DbaDatabase -SqlInstance $server -Database model).LogFiles.FileName
            }

            if ($logPath.Length -eq 0) {
                $logPath = $server.Information.MasterDbLogPath
            }

            $dataPath = $dataPath.Trim().TrimEnd("\")
            $logPath = $logPath.Trim().TrimEnd("\")

            [PSCustomObject]@{
                ComputerName = $server.ComputerName
                InstanceName = $server.ServiceName
                SqlInstance  = $server.DomainInstanceName
                Data         = $dataPath
                Log          = $logPath
                Backup       = $server.BackupDirectory
                ErrorLog     = $server.ErrorlogPath
            }
        }
    }
}