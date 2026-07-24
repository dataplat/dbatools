function Copy-DbaBackupDevice {
    <#
    .SYNOPSIS
        Migrates SQL Server backup devices between instances including both device definitions and physical files

    .DESCRIPTION
        Copies SQL Server backup devices from one instance to another, handling both the logical device definition and the physical backup files. This simplifies server migrations and disaster recovery setup by ensuring backup devices are available on target instances.

        Physical backup files are transferred using admin shares, and if the original directory structure doesn't exist on the destination, files are automatically placed in SQL Server's default backup directory. Existing backup devices are skipped unless -Force is specified to overwrite them.

    .PARAMETER Source
        Specifies the source SQL Server instance containing the backup devices to copy. The source instance must be SQL Server 2000 or higher with sysadmin access required.
        Use this when migrating backup devices from an existing SQL Server to consolidate backup infrastructure or during server migrations.

    .PARAMETER SourceSqlCredential
        Specifies alternative credentials for connecting to the source SQL Server instance. Accepts PowerShell credentials created with Get-Credential.
        Use this when the source server requires different authentication than your current Windows session, such as SQL Server authentication or a different domain account.
        Supports Windows Authentication, SQL Server Authentication, Active Directory Password, and Active Directory Integrated. For MFA support, use Connect-DbaInstance first.

    .PARAMETER Destination
        Specifies one or more destination SQL Server instances where backup devices will be created. Each destination instance must be SQL Server 2000 or higher with sysadmin access required.
        Use this to specify target servers during migrations, disaster recovery setup, or when standardizing backup device configurations across multiple instances.

    .PARAMETER DestinationSqlCredential
        Specifies alternative credentials for connecting to the destination SQL Server instances. Accepts PowerShell credentials created with Get-Credential.
        Use this when destination servers require different authentication than your current Windows session, such as SQL Server authentication or different domain accounts.
        Supports Windows Authentication, SQL Server Authentication, Active Directory Password, and Active Directory Integrated. For MFA support, use Connect-DbaInstance first.

    .PARAMETER BackupDevice
        Specifies which backup devices to copy from the source instance. Accepts an array of backup device names and supports tab completion with available devices.
        Use this to selectively copy specific backup devices instead of migrating all devices, which is helpful when you only need certain backup configurations on the destination.

    .PARAMETER Force
        Forces the recreation of backup devices that already exist on the destination instance by dropping them first. Without this switch, existing backup devices are skipped.
        Use this when you need to overwrite existing backup device configurations with updated settings from the source, such as changing file paths or device properties during migrations.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Backup
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaBackupDevice

    .OUTPUTS
        PSCustomObject

        Returns one object per backup device processed, containing the status and details of the copy operation.

        Properties:
        - DateTime: Timestamp when the operation was processed (DbaDateTime object)
        - SourceServer: Name of the source SQL Server instance
        - DestinationServer: Name of the destination SQL Server instance
        - Name: Name of the backup device
        - Type: Always returns "Backup Device"
        - Status: Result of the operation (Successful, Skipped, or Failed)
        - Notes: Additional information about the operation (e.g., "Already exists on destination" or error details)

        The output uses Select-DefaultView to display the properties in the order: DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes. All properties are available via Select-Object * if additional fields are needed.

    .EXAMPLE
        PS C:\> Copy-DbaBackupDevice -Source sqlserver2014a -Destination sqlcluster

        Copies all server backup devices from sqlserver2014a to sqlcluster using Windows credentials. If backup devices with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaBackupDevice -Source sqlserver2014a -Destination sqlcluster -BackupDevice backup01 -SourceSqlCredential $cred -Force

        Copies only the backup device named backup01 from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a    and Windows credentials for sqlcluster. If a backup device with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaBackupDevice -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$BackupDevice,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if (-not $script:isWindows) {
            Stop-Function -Message "Copy-DbaBackupDevice does not support Linux yet though it looks doable"
            return
        }
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        $serverBackupDevices = $sourceServer.BackupDevices
        $sourceNetBios = $Source.ComputerName

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            $destBackupDevices = $destServer.BackupDevices
            $destNetBios = $destinstance.ComputerName

            foreach ($currentBackupDevice in $serverBackupDevices) {
                $deviceName = $currentBackupDevice.Name

                $copyBackupDeviceStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $deviceName
                    Type              = "Backup Device"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($BackupDevice -and $BackupDevice -notcontains $deviceName) {
                    continue
                }

                if ($destBackupDevices.Name -contains $deviceName) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Backup device $deviceName exists at destination. Use -Force to drop and migrate.")) {
                            $copyBackupDeviceStatus.Status = "Skipped"
                            $copyBackupDeviceStatus.Notes = "Already exists on destination"
                            $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Backup device $deviceName exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping backup device $deviceName")) {
                            try {
                                Write-Message -Level Verbose -Message "Dropping backup device $deviceName"
                                $destServer.BackupDevices[$deviceName].Drop()
                            } catch {
                                $copyBackupDeviceStatus.Status = "Failed"
                                $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue dropping backup device $deviceName on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Generating SQL code for $deviceName")) {
                    Write-Message -Level Verbose -Message "Scripting out SQL for $deviceName"
                    try {
                        $sql = $currentBackupDevice.Script() | Out-String
                        $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destinstance'"
                    } catch {
                        $copyBackupDeviceStatus.Status = "Failed"
                        $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue scripting out backup device $deviceName on $destinstance | $PSItem"
                        continue
                    }
                }

                Write-Message -Level Verbose -Message "Preparing to copy actual backup file"

                $path = Split-Path $sourceServer.BackupDevices[$deviceName].PhysicalLocation
                $destPath = Join-AdminUnc $destNetBios $path
                $sourcepath = Join-AdminUnc $sourceNetBios $sourceServer.BackupDevices[$deviceName].PhysicalLocation

                Write-Message -Level Verbose -Message "Checking if directory $destPath exists"

                if ($(Test-DbaPath -SqlInstance $destServer -Path $path) -eq $false) {
                    $backupDirectory = $destServer.BackupDirectory
                    $destPath = Join-AdminUnc $destNetBios $backupDirectory

                    if ($Pscmdlet.ShouldProcess($destinstance, "Updating create code to use new path")) {
                        Write-Message -Level Verbose -Message "$path doesn't exist on $destinstance"
                        Write-Message -Level Verbose -Message "Using default backup directory $backupDirectory"

                        try {
                            Write-Message -Level Verbose -Message "Updating $deviceName to use $backupDirectory"
                            $sql = $sql -replace [Regex]::Escape($path), $backupDirectory
                        } catch {
                            $copyBackupDeviceStatus.Status = "Failed"
                            $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Issue updating script of backup device $deviceName with new path on $destinstance | $PSItem"
                            continue
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Copying $sourcepath to $destPath using BITSTransfer")) {
                    try {
                        Start-BitsTransfer -Source $sourcepath -Destination $destPath -ErrorAction Stop
                        Write-Message -Level Verbose -Message "Backup device $deviceName successfully copied"
                    } catch {
                        $copyBackupDeviceStatus.Status = "Failed"
                        $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue copying $sourcepath to $destPath for backup device $deviceName on $destinstance | $PSItem"
                        continue
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Adding backup device $deviceName")) {
                    Write-Message -Level Verbose -Message "Adding backup device $deviceName on $destinstance"
                    try {
                        $destServer.Query($sql)
                        $destServer.BackupDevices.Refresh()

                        $copyBackupDeviceStatus.Status = "Successful"
                        $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyBackupDeviceStatus.Status = "Failed"
                        $copyBackupDeviceStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue creating backup device $deviceName on $destinstance | $PSItem"
                        continue
                    }
                }
            }
        }
    }
}