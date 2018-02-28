function Set-DbaBackupPath {
    <#
        .SYNOPSIS
            Sets SQL Server default backup directory to a new value then displays information this setting.

        .DESCRIPTION
            Sets SQL Server max memory then displays information relating to SQL Server Max Memory configuration settings.

            Inspired by Jonathan Kehayias's post about SQL Server Max memory (http://bit.ly/sqlmemcalc), this uses a formula to
            determine the default optimum RAM to use, then sets the SQL max value to that number.

            Jonathan notes that the formula used provides a *general recommendation* that doesn't account for everything that may
            be going on in your specific environment.

        .PARAMETER SqlInstance
            Allows you to specify a comma separated list of servers to query.

        .PARAMETER Path
            Specifies the path

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials
            being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .PARAMETER WhatIf
            Shows what would happen if the cmdlet runs. The cmdlet is not run.

        .PARAMETER Confirm
            Prompts you for confirmation before running the cmdlet.

        .NOTES
            Tags: Storage, DisasterRecovery, Backup
            Author: Andrew Wickham, @awickham, www.awickham.com

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Set-DbaBackupPath

        .EXAMPLE
            Set-DbaBackupPath -SqlInstance 'sqlserver1' -Path 'Q:\Backups'

            Set the backup path to Q:\Backups for one server named "sqlserver1"

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance sqlserver | Set-DbaBackupPath 'Q:\Backups'

            Find all servers in SQL Server Central Management server, then pipe those to Set-DbaBackupPath
            and set the backup directory to Q:\Backups.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Position = 0)]
        [Alias("ServerInstance", "SqlServer", "SqlServers", "ComputerName")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [Parameter(Position = 1)]
        [string]$Path,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        if ((Test-Bound -Not -Parameter SqlInstance) -and (Test-Bound -Not -Parameter Collection)) {
            Stop-Function -Category InvalidArgument -Message "You must specify a server list source using -SqlInstance or you can pipe results"
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (!(Test-SqlSa -SqlInstance $server)) {
                Stop-Function -Message "Not a sysadmin on $server. Skipping." -Category PermissionDenied -ErrorRecord $_ -Target $server -Continue
            }

            # TODO: Validate path
            # TODO: Grant read/write access to instance account

            $oldBackupPath = $server.BackupDirectory

            try {
                Write-Message -Level Verbose -Message "Change $server backup path from $($server.BackupDirectory) to $Path"
                $server.BackupDirectory = $Path

                if ($PSCmdlet.ShouldProcess($server, "Change backup path from $oldBackupPath to $($server.BackupDirectory)")) {
                    try {
                        $server.Alter()
                        $newBackupPath = $server.BackupDirectory
                    }
                    catch {
                        Stop-Function -Message "Failed to apply configuration change for $server" -ErrorRecord $_ -Target $server -Continue
                    }
                }
            }
            catch {
                Stop-Function -Message "Could not modify backup path for $server" -ErrorRecord $_ -Target $server -Continue
            }

            [PSCustomObject]@{
                ComputerName  = $server.NetName
                InstanceName  = $server.ServiceName
                SqlInstance   = $server.DomainInstanceName
                OldBackupPath = $oldBackupPath
                BackupPath    = $newBackupPath
            } | Select-DefaultView
        }
    }
}