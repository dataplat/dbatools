function Copy-DbaBackupDevice {
    <#
        .SYNOPSIS
            Copies backup devices one by one. Copies both SQL code and the backup file itself.

        .DESCRIPTION
            Backups are migrated using Admin shares. If the destination directory does not exist, SQL Server's default backup directory will be used.

            If a backup device with same name exists on destination, it will not be dropped and recreated unless -Force is used.

        .PARAMETER Source
            Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

        .PARAMETER SourceSqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

            Windows Authentication will be used if SourceSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Destination
            Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

        .PARAMETER DestinationSqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

            Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER BackupDevice
            BackupDevice to be copied. Auto-populated list of devices. If not provided all BackupDevice(s) will be copied.

        .PARAMETER Force
            If this switch is enabled, backup device(s) will be dropped and recreated if they already exists on destination.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Migration, DisasterRecovery, Backup
            Author: Chrissy LeMaire (@cl), netnerds.net
            Requires: sysadmin access on SQL Servers

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Copy-DbaBackupDevice

        .EXAMPLE
            Copy-DbaBackupDevice -Source sqlserver2014a -Destination sqlcluster

            Copies all server backup devices from sqlserver2014a to sqlcluster using Windows credentials. If backup devices with the same name exist on sqlcluster, they will be skipped.

        .EXAMPLE
            Copy-DbaBackupDevice -Source sqlserver2014a -Destination sqlcluster -BackupDevice backup01 -SourceSqlCredential $cred -Force

            Copies only the backup device named backup01 from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a    and Windows credentials for sqlcluster. If a backup device with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

        .EXAMPLE
            Copy-DbaBackupDevice -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

            Shows what would happen if the command were executed using force.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$BackupDevice,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )

    begin {

        $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

        $source = $sourceServer.DomainInstanceName
        $destination = $destServer.DomainInstanceName

        $serverBackupDevices = $sourceServer.BackupDevices
        $destBackupDevices = $destServer.BackupDevices

        $sourceNetBios = Resolve-NetBiosName $sourceServer
        $destNetBios = Resolve-NetBiosName $destServer
    }
    process {
        foreach ($currentBackupDevice in $serverBackupDevices) {
            $deviceName = $currentBackupDevice.Name

            $copyBackupDeviceStatus = [pscustomobject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Name              = $deviceName
                Type              = "Backup Device"
                Status            = $null
                Notes             = $null
                DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
            }

            if ($BackupDevice -and $BackupDevice -notcontains $deviceName) {
                continue
            }

            if ($destBackupDevices.Name -contains $deviceName) {
                if ($force -eq $false) {
                    $copyBackupDeviceStatus.Status = "Skipped"
                    $copyBackupDeviceStatus.Notes = "Already exists"
                    $copyBackupDeviceStatus

                    Write-Message -Level Verbose -Message "backup device $deviceName exists at destination. Use -Force to drop and migrate."
                    continue
                }
                else {
                    if ($Pscmdlet.ShouldProcess($destination, "Dropping backup device $deviceName")) {
                        try {
                            Write-Message -Level Verbose -Message "Dropping backup device $deviceName"
                            $destServer.BackupDevices[$deviceName].Drop()
                        }
                        catch {
                            $copyBackupDeviceStatus.Status = "Failed"
                            $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Issue dropping backup device" -Target $deviceName -ErrorRecord $_ -Continue
                        }
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Generating SQL code for $deviceName")) {
                Write-Message -Level Verbose -Message "Scripting out SQL for $deviceName"
                try {
                    $sql = $currentBackupDevice.Script() | Out-String
                    $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                }
                catch {
                    $copyBackupDeviceStatus.Status = "Failed"
                    $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    Stop-Function -Message "Issue scripting out backup device" -Target $deviceName -ErrorRecord $_ -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess("console", "Stating that the actual file copy is about to occur")) {
                Write-Message -Level Verbose -Message "Preparing to copy actual backup file"
            }

            $path = Split-Path $sourceServer.BackupDevices[$deviceName].PhysicalLocation
            $destPath = Join-AdminUnc $destNetBios $path
            $sourcepath = Join-AdminUnc $sourceNetBios $sourceServer.BackupDevices[$deviceName].PhysicalLocation

            Write-Message -Level Verbose -Message "Checking if directory $destPath exists"

            if ($(Test-DbaSqlPath -SqlInstance $Destination -Path $path) -eq $false) {
                $backupDirectory = $destServer.BackupDirectory
                $destPath = Join-AdminUnc $destNetBios $backupDirectory

                if ($Pscmdlet.ShouldProcess($destination, "Updating create code to use new path")) {
                    Write-Message -Level Verbose -Message "$path doesn't exist on $destination"
                    Write-Message -Level Verbose -Message "Using default backup directory $backupDirectory"

                    try {
                        Write-Message -Level Verbose -Message "Updating $deviceName to use $backupDirectory"
                        $sql = $sql -replace $path, $backupDirectory
                    }
                    catch {
                        $copyBackupDeviceStatus.Status = "Failed"
                        $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        Stop-Function -Message "Issue updating script of backup device with new path" -Target $deviceName -ErrorRecord $_ -Continue
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Copying $sourcepath to $destPath using BITSTransfer")) {
                try {
                    Start-BitsTransfer -Source $sourcepath -Destination $destPath -ErrorAction Stop
                    Write-Message -Level Verbose -Message "Backup device $deviceName successfully copied"
                }
                catch {
                    $copyBackupDeviceStatus.Status = "Failed"
                    $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    Stop-Function -Message "Issue copying backup device to destination" -Target $deviceName -ErrorRecord $_ -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Adding backup device $deviceName")) {
                Write-Message -Level Verbose -Message "Adding backup device $deviceName on $destination"
                try {
                    $destServer.Query($sql)
                    $destServer.BackupDevices.Refresh()

                    $copyBackupDeviceStatus.Status = "Successful"
                    $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                catch {
                    $copyBackupDeviceStatus.Status = "Failed"
                    $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    Stop-Function -Message "Issue adding backup device" -Target $deviceName -ErrorRecord $_ -Continue
                }
            }
        } #end foreach backupDevice
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlBackupDevice
    }
}
