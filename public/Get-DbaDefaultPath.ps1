function Get-DbaDefaultPath {
    <#
    .SYNOPSIS
        Retrieves default file paths for SQL Server data, log, backup, and error log directories

    .DESCRIPTION
        Retrieves the default directory paths that SQL Server uses for new database files, transaction logs, backups, and error logs. This information is essential for capacity planning, automated database provisioning, and understanding where SQL Server will place files when no explicit path is specified. The function uses multiple fallback methods to determine these paths, including server properties, system queries, and examining existing system databases when standard properties are unavailable.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, Data, Log, Backup
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDefaultPath

    .EXAMPLE
        PS C:\> Get-DbaDefaultPath -SqlInstance sql01\sharepoint

        Returns the default file paths for sql01\sharepoint

    .EXAMPLE
        PS C:\> $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
        PS C:\> $servers | Get-DbaDefaultPath

        Returns the default file paths for "sql2014","sql2016" and "sqlcluster\sharepoint"

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dataPath = $server.DefaultFile
            if ($dataPath.Length -eq 0) {
                $dataPath = $server.Query("SELECT SERVERPROPERTY('InstanceDefaultdataPath') as Data").Data
            }

            if ($dataPath -eq [System.DBNull]::Value -or $dataPath.Length -eq 0) {
                $dataPath = Split-Path (Get-DbaDatabase -SqlInstance $server -Database model).FileGroups[0].Files[0].FileName
            }

            if ($dataPath.Length -eq 0) {
                $dataPath = $server.Information.MasterDbPath
            }

            $logPath = $server.DefaultLog

            if ($logPath.Length -eq 0) {
                $logPath = $server.Query("SELECT SERVERPROPERTY('InstanceDefaultLogPath') as Log").Log
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