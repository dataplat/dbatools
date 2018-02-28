function Set-DbaBackupPath {
    <#
        .SYNOPSIS
            Sets SQL Server default backup directory to a new value then displays information this setting.

        .DESCRIPTION
            Sets SQL Server default backup directory then displays information relating to the configuration setting.

            If the path does not exist it will try to create it and grant the instance service account access.

        .PARAMETER SqlInstance
            Allows you to specify a comma separated list of servers to query.

        .PARAMETER Path
            Specifies the new backup directory

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
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer", "SqlServers", "ComputerName")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Alias('Silent')]
        [switch]$EnableException
    )

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

            if (!(Test-SqlSa -SqlInstance $server -SqlCredential $SqlCredential)) {
                Stop-Function -Message "Not a sysadmin on $server. Skipping." -Category PermissionDenied -ErrorRecord $_ -Target $server -Continue
            }

            # create directory if it doesn't exist
            $results = Invoke-Command -ComputerName $server.NetName -ScriptBlock {
                param ($ServiceAccount, $Path)

                if (-not (Test-Path -Path $Path)) {
                    # create it
                    try {
                        $null = New-Item -Path $Path -ItemType 'Directory'
                    }
                    catch {
                        return $false
                    }

                    # assign permissions to service account
                    try {
                        # TODO: if running under system account and using a network path and domain joined grant access to computer account instead
                        $acl = Get-Acl -Path $Path
                        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($ServiceAccount, 'FullControl', 'Allow')
                        $acl.SetAccessRule($rule)
                        Set-Acl -Path $Path -AclObject $acl
                    }
                    catch {
                        return $false
                    }
                }
            } -ArgumentList $server.ServiceAccount, $Path
            if (-not $results) {
                Write-Message -Level Warning -Message "Could not create or set permissions on path"
            }

            $oldBackupPath = $server.BackupDirectory

            try {
                Write-Message -Level Verbose -Message "Change $server backup path from $($server.BackupDirectory) to $Path"
                $server.BackupDirectory = $Path

                if (Test-ShouldProcess -Context $PSCmdlet -Target $server -Action "Change backup path from $oldBackupPath to $($server.BackupDirectory)") {
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
            } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, OldBackupPath, BackupPath
        }
    }
}