function Set-DbaTempDbConfig {
    <#
    .SYNOPSIS
        Sets tempdb data and log files according to best practices.

    .DESCRIPTION
        Calculates tempdb size and file configurations based on passed parameters, calculated values, and Microsoft best practices. User must declare SQL Server to be configured and total data file size as mandatory values. Function then calculates the number of data files based on logical cores on the target host and create evenly sized data files based on the total data size declared by the user.

        Other parameters can adjust the settings as the user desires (such as different file paths, number of data files, and log file size). No functions that shrink or delete data files are performed. If you wish to do this, you will need to resize tempdb so that it is "smaller" than what the function will size it to before running the function.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DataFileCount
        Specifies the number of data files to create. If this number is not specified, the number of logical cores of the host will be used.

    .PARAMETER DataFileSize
        Specifies the total data file size in megabytes. This is distributed across the total number of data files.

    .PARAMETER LogFileSize
        Specifies the log file size in megabytes. If not specified, no change will be made.

    .PARAMETER DataFileGrowth
        Specifies the growth amount for the data file(s) in megabytes. The default is 512 MB.

    .PARAMETER LogFileGrowth
        Specifies the growth amount for the log file in megabytes. The default is 512 MB.

    .PARAMETER DataPath
        Specifies the filesystem path in which to create the tempdb data files. If not specified, current tempdb location will be used.

    .PARAMETER LogPath
        Specifies the filesystem path in which to create the tempdb log file. If not specified, current tempdb location will be used.

    .PARAMETER OutputScriptOnly
        If this switch is enabled, only the T-SQL script to change the tempdb configuration is created and output.

    .PARAMETER OutFile
        Specifies the filesystem path into which the generated T-SQL script will be saved.

    .PARAMETER DisableGrowth
        If this switch is enabled, the tempdb files will be configured to not grow. This overrides -DataFileGrowth and -LogFileGrowth.

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
        Author: Michael Fal (@Mike_Fal), http://mikefal.net

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
        [string]$DataPath,
        [string]$LogPath,
        [string]$OutFile,
        [switch]$OutputScriptOnly,
        [switch]$DisableGrowth,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9

            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
                if ((Test-DbaPath -SqlInstance $server -Path $DataPath) -eq $false) {
                    Stop-Function -Message "$datapath is an invalid path." -Continue
                }
            } else {
                $Filepath = $server.Databases['tempdb'].Query('SELECT physical_name as PhysicalName FROM sys.database_files WHERE file_id = 1').PhysicalName
                $DataPath = Split-Path $Filepath
            }

            Write-Message -Message "Using data path: $datapath." -Level Verbose

            if (Test-Bound -ParameterName LogPath) {
                if ((Test-DbaPath -SqlInstance $server -Path $LogPath) -eq $false) {
                    Stop-Function -Message "$LogPath is an invalid path." -Continue
                }
            } else {
                $Filepath = $server.Databases['tempdb'].Query('SELECT physical_name as PhysicalName FROM sys.database_files WHERE file_id = 2').PhysicalName
                $LogPath = Split-Path $Filepath
            }
            Write-Message -Message "Using log path: $LogPath." -Level Verbose

            # Check if the file growth needs to be disabled
            if ($DisableGrowth) {
                $DataFileGrowth = 0
                $LogFileGrowth = 0
            }

            # Check current tempdb. Throw an error if current tempdb is larger than config.
            $CurrentFileCount = $server.Databases['tempdb'].Query('SELECT count(1) as FileCount FROM sys.database_files WHERE type=0').FileCount
            $TooBigCount = $server.Databases['tempdb'].Query("SELECT TOP 1 (size/128) as Size FROM sys.database_files WHERE size/128 > $DataFilesizeSingle AND type = 0").Size

            if ($CurrentFileCount -gt $DataFileCount) {
                Stop-Function -Message "Current tempdb in $instance is not suitable to be reconfigured. The current tempdb has a greater number of files ($CurrentFileCount) than the calculated configuration ($DataFileCount)." -Continue
            }

            if ($TooBigCount) {
                Stop-Function -Message "Current tempdb in $instance is not suitable to be reconfigured. The current tempdb has files with a size ($TooBigCount MB) larger than the calculated individual file configuration ($DataFilesizeSingle MB)." -Continue
            }

            Write-Message -Message "tempdb configuration validated." -Level Verbose

            $DataFiles = Get-DbaDbFile -SqlInstance $server -Database tempdb | Where-Object Type -eq 0 | Select-Object LogicalName, PhysicalName

            #Checks passed, process reconfiguration
            for ($i = 0; $i -lt $DataFileCount; $i++) {
                $File = $DataFiles[$i]
                if ($File) {
                    $Filename = Split-Path $File.PhysicalName -Leaf
                    $LogicalName = $File.LogicalName
                    $NewPath = "$datapath\$Filename"
                    $sql += "ALTER DATABASE tempdb MODIFY FILE(name=$LogicalName,filename='$NewPath',size=$DataFilesizeSingle MB,filegrowth=$DataFileGrowth);"
                } else {
                    $NewName = "tempdev$i.ndf"
                    $NewPath = "$datapath\$NewName"
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