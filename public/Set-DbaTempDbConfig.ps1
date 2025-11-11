function Set-DbaTempDbConfig {
    <#
    .SYNOPSIS
        Configures tempdb database files according to Microsoft best practices for optimal performance

    .DESCRIPTION
        Configures tempdb database files to follow Microsoft's recommended best practices for performance optimization. This function calculates the optimal number of data files based on logical CPU cores (capped at 8) and distributes the specified total data file size evenly across those files. You must specify the target SQL Server instance and total data file size as mandatory parameters.

        The function automatically determines the appropriate number of data files based on your server's logical cores, but you can override this behavior. It validates the current tempdb configuration to ensure it won't conflict with your desired settings - existing files must be smaller than the calculated target size and you cannot have more existing files than the target configuration.

        Additional parameters let you customize file paths, log file size, and growth settings. The function generates ALTER DATABASE statements but does not shrink or delete existing files. If your current tempdb is larger than your target configuration, you'll need to shrink it manually before running this function. A SQL Server restart is required for tempdb changes to take effect.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DataFileCount
        Sets the number of tempdb data files to create. When omitted, automatically uses the logical core count (capped at 8 per Microsoft best practices).
        Override this when you need a specific file count different from core count, though exceeding core count generates a warning as it goes against best practices.

    .PARAMETER DataFileSize
        Sets the total size in MB for all tempdb data files combined. This value gets evenly divided across all data files.
        For example, 1000MB with 4 files creates four 250MB files. Choose based on your workload's tempdb usage patterns and available storage.

    .PARAMETER LogFileSize
        Sets the tempdb log file size in MB. When omitted, the existing log file size remains unchanged.
        Use this to resize the log file when current sizing doesn't match your tempdb transaction volume requirements.

    .PARAMETER DataFileGrowth
        Controls the growth increment for tempdb data files in MB when they need to expand. Defaults to 512 MB.
        Set this based on your typical tempdb usage spikes to avoid frequent small growths that can impact performance. Use 0 with -DisableGrowth to prevent growth entirely.

    .PARAMETER LogFileGrowth
        Controls the growth increment for the tempdb log file in MB when it needs to expand. Defaults to 512 MB.
        Size this according to your transaction log activity in tempdb to minimize auto-growth events during peak workloads.

    .PARAMETER DataPath
        Sets the folder path(s) where tempdb data files will be created. When omitted, uses the current tempdb data file location.
        Specify multiple paths to distribute files across different drives for performance. Files are distributed round-robin across the provided paths.

    .PARAMETER LogPath
        Sets the folder path where the tempdb log file will be created. When omitted, uses the current tempdb log file location.
        Consider placing the log file on a separate drive from data files to reduce I/O contention for write-heavy tempdb workloads.

    .PARAMETER OutputScriptOnly
        Returns the generated T-SQL script without executing it against the SQL Server instance.
        Use this to review the configuration changes before applying them, or to run the script manually during maintenance windows.

    .PARAMETER OutFile
        Saves the generated T-SQL script to the specified file path instead of executing it.
        Useful for storing configuration scripts in source control or running them later through scheduled maintenance processes.

    .PARAMETER DisableGrowth
        Prevents tempdb files from auto-growing by setting growth to 0. Overrides any values specified for -DataFileGrowth and -LogFileGrowth.
        Use this when you want to pre-size tempdb files appropriately and prevent unexpected growth during production workloads.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Tempdb, Configuration
        Author: Michael Fal (@Mike_Fal), mikefal.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaTempDbConfig

    .EXAMPLE
        PS C:\> Set-DbaTempDbConfig -SqlInstance localhost -DataFileSize 1000

        Creates tempdb with a number of data files equal to the logical cores where each file is equal to 1000MB divided by the number of logical cores, with a log file of 250MB.

    .EXAMPLE
        PS C:\> Set-DbaTempDbConfig -SqlInstance localhost -DataFileSize 1000 -DataFileCount 8

        Creates tempdb with 8 data files, each one sized at 125MB, with a log file of 250MB.

    .EXAMPLE
        PS C:\> Set-DbaTempDbConfig -SqlInstance localhost -DataFileSize 1000 -OutputScriptOnly

        Provides a SQL script output to configure tempdb according to the passed parameters.

    .EXAMPLE
        PS C:\> Set-DbaTempDbConfig -SqlInstance localhost -DataFileSize 1000 -DisableGrowth

        Disables the growth for the data and log files.

    .EXAMPLE
        PS C:\> Set-DbaTempDbConfig -SqlInstance localhost -DataFileSize 1000 -OutputScriptOnly

        Returns the T-SQL script representing tempdb configuration.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int]$DataFileCount,
        [Parameter(Mandatory)]
        [int]$DataFileSize,
        [int]$LogFileSize,
        [int]$DataFileGrowth = 512,
        [int]$LogFileGrowth = 512,
        [string[]]$DataPath,
        [string]$LogPath,
        [string]$OutFile,
        [switch]$OutputScriptOnly,
        [switch]$DisableGrowth,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $cores = $server.Processors
            if ($cores -gt 8) {
                $cores = 8
            }

            #Set DataFileCount if not specified. If specified, check against best practices.
            if (-not $DataFileCount) {
                $DataFileCount = $cores
                Write-Message -Message "Data file count set to number of cores: $DataFileCount" -Level Verbose
            } else {
                if ($DataFileCount -gt $cores) {
                    Write-Message -Message "Data File Count of $DataFileCount exceeds the Logical Core Count of $cores. This is outside of best practices." -Level Warning
                }
                Write-Message -Message "Data file count set explicitly: $DataFileCount" -Level Verbose
            }

            $DataFilesizeSingle = $([Math]::Floor($DataFileSize / $DataFileCount))
            Write-Message -Message "Single data file size (MB): $DataFilesizeSingle." -Level Verbose

            if (Test-Bound -ParameterName DataPath) {
                foreach ($dataDirPath in $DataPath) {
                    if ((Test-DbaPath -SqlInstance $server -Path $dataDirPath) -eq $false) {
                        $invalidPathFound = "$dataDirPath does not exist"
                        break
                    }
                }

                if ($invalidPathFound) {
                    Stop-Function -Message $invalidPathFound -Continue
                }
            } else {
                $Filepath = $server.Databases['tempdb'].Query('SELECT physical_name AS PhysicalName FROM sys.database_files WHERE file_id = 1').PhysicalName
                $DataPath = Split-Path $Filepath
            }

            Write-Message -Message "Using data path(s): $DataPath." -Level Verbose

            if (Test-Bound -ParameterName LogPath) {
                if ((Test-DbaPath -SqlInstance $server -Path $LogPath) -eq $false) {
                    Stop-Function -Message "$LogPath is an invalid path." -Continue
                }
            } else {
                $Filepath = $server.Databases['tempdb'].Query('SELECT physical_name AS PhysicalName FROM sys.database_files WHERE file_id = 2').PhysicalName
                $LogPath = Split-Path $Filepath
            }
            Write-Message -Message "Using log path: $LogPath." -Level Verbose

            # Check if the file growth needs to be disabled
            if ($DisableGrowth) {
                $DataFileGrowth = 0
                $LogFileGrowth = 0
            }

            # Check current tempdb. Throw an error if current tempdb is larger than config.
            $CurrentFileCount = $server.Databases['tempdb'].Query('SELECT COUNT(1) AS FileCount FROM sys.database_files WHERE type=0').FileCount
            $TooBigCount = $server.Databases['tempdb'].Query("SELECT TOP 1 (size/128) AS Size FROM sys.database_files WHERE size/128 > $DataFilesizeSingle AND type = 0").Size

            if ($CurrentFileCount -gt $DataFileCount) {
                Stop-Function -Message "Current tempdb in $instance is not suitable to be reconfigured. The current tempdb has a greater number of files ($CurrentFileCount) than the calculated configuration ($DataFileCount)." -Continue
            }

            if ($TooBigCount) {
                Stop-Function -Message "Current tempdb in $instance is not suitable to be reconfigured. The current tempdb has files with a size ($TooBigCount MB) larger than the calculated individual file configuration ($DataFilesizeSingle MB)." -Continue
            }

            Write-Message -Message "tempdb configuration validated." -Level Verbose

            $DataFiles = Get-DbaDbFile -SqlInstance $server -Database tempdb | Where-Object Type -eq 0 | Select-Object LogicalName, PhysicalName

            # Used to round-robin the placement of tempdb data files if more than one value for $DataPath was passed in.
            $dataPathIndexToUse = 0

            #Checks passed, process reconfiguration
            for ($i = 0; $i -lt $DataFileCount; $i++) {
                $File = $DataFiles[$i]

                if ($DataPath.Count -gt 1) {
                    $newDataDirPath = $DataPath[$dataPathIndexToUse]

                    $dataPathIndexToUse += 1

                    # reset the round robin index variable
                    if ($dataPathIndexToUse -ge $DataPath.Count ) {
                        $dataPathIndexToUse = 0
                    }
                } else {
                    $newDataDirPath = $DataPath
                }

                if ($File) {
                    $Filename = Split-Path $File.PhysicalName -Leaf
                    $LogicalName = $File.LogicalName
                    $NewPath = "$newDataDirPath\$Filename"
                    $sql += "ALTER DATABASE tempdb MODIFY FILE(name=$LogicalName,filename='$NewPath',size=$DataFilesizeSingle MB,filegrowth=$DataFileGrowth);"
                } else {
                    $NewName = "tempdev$i.ndf"
                    $NewPath = "$newDataDirPath\$NewName"
                    $sql += "ALTER DATABASE tempdb ADD FILE(name=tempdev$i,filename='$NewPath',size=$DataFilesizeSingle MB,filegrowth=$DataFileGrowth);"
                }
            }

            $logfile = Get-DbaDbFile -SqlInstance $server -Database tempdb | Where-Object Type -eq 1 | Select-Object LogicalName, PhysicalName, @{L = "SizeMb"; E = { $_.Size.Megabyte } }

            if ($LogPath -or $LogFileSize) {
                $Filename = Split-Path $logfile.PhysicalName -Leaf
                $LogicalName = $logfile.LogicalName

                if ($LogPath) {
                    $NewPath = "$LogPath\$Filename"
                } else {
                    $NewPath = $logfile.PhysicalName
                }

                if (-not($LogFileSize)) {
                    $LogFileSize = $logfile.SizeMb
                }

                $sql += "ALTER DATABASE tempdb MODIFY FILE(name=$LogicalName,filename='$NewPath',size=$LogFileSize MB,filegrowth=$LogFileGrowth);"
            }

            Write-Message -Message "SQL Statement to resize tempdb." -Level Verbose
            Write-Message -Message ($sql -join "`n`n") -Level Verbose

            if ($OutputScriptOnly) {
                return $sql
            } elseif ($OutFile) {
                $sql | Set-Content -Path $OutFile
            } else {
                if ($Pscmdlet.ShouldProcess($instance, "Executing query and informing that a restart is required.")) {
                    try {
                        $server.Databases['master'].ExecuteNonQuery($sql)
                        Write-Message -Level Verbose -Message "tempdb successfully reconfigured."

                        [PSCustomObject]@{
                            ComputerName       = $server.ComputerName
                            InstanceName       = $server.ServiceName
                            SqlInstance        = $server.DomainInstanceName
                            DataFileCount      = $DataFileCount
                            DataFileSize       = [dbasize]($DataFileSize * 1024 * 1024)
                            SingleDataFileSize = [dbasize]($DataFilesizeSingle * 1024 * 1024)
                            LogSize            = [dbasize]($LogFileSize * 1024 * 1024)
                            DataPath           = $DataPath
                            LogPath            = $LogPath
                            DataFileGrowth     = [dbasize]($DataFileGrowth * 1024 * 1024)
                            LogFileGrowth      = [dbasize]($LogFileGrowth * 1024 * 1024)
                        }

                        Write-Message -Level Output -Message "tempdb reconfigured. You must restart the SQL Service for settings to take effect."
                    } catch {
                        Stop-Function -Message "Unable to reconfigure tempdb. Exception: $_" -Target $sql -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}