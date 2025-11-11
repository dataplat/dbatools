function Add-DbaDbFile {
    <#
    .SYNOPSIS
        Adds data files to existing filegroups in SQL Server databases.

    .DESCRIPTION
        Adds new data files (.mdf or .ndf) to existing filegroups in SQL Server databases. This is essential after creating new filegroups (especially MemoryOptimizedDataFileGroup for In-Memory OLTP) because filegroups cannot store data until they contain at least one file. The function supports all filegroup types including standard row data, FileStream, and memory-optimized storage, with automatic path resolution to SQL Server default data directories when no explicit path is specified.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database(s) containing the filegroup where the file will be added. Supports multiple database names for bulk operations.
        Use this when you need to add files to the same filegroup across multiple databases for consistency.

    .PARAMETER FileGroup
        Specifies the name of the filegroup where the new file will be added. The filegroup must already exist in the database.
        This is typically used after creating a new filegroup with New-DbaDbFileGroup, especially for MemoryOptimizedDataFileGroup which requires files before use.

    .PARAMETER FileName
        Sets the logical name for the new file being created. This name is used within SQL Server to reference the file.
        If not specified, a name will be auto-generated based on the database and filegroup names to ensure uniqueness.

    .PARAMETER Path
        Specifies the full physical path where the file will be created on disk, including the filename and extension (.ndf for data files).
        If not specified, the file will be placed in the SQL Server default data directory with an auto-generated filename.
        For MemoryOptimizedDataFileGroup, the path should point to a directory (not a file) where the container will be created.

    .PARAMETER Size
        Sets the initial size of the file in megabytes (MB). Defaults to 128MB if not specified.
        Use larger values for high-volume databases or smaller values for development/test databases to optimize storage allocation.
        For MemoryOptimizedDataFileGroup, this parameter is ignored as memory-optimized filegroups manage their own sizing.

    .PARAMETER Growth
        Specifies the file growth increment in megabytes (MB). Defaults to 64MB if not specified.
        This controls how much the file expands when it runs out of space, with fixed-size growth preferred over percentage-based for predictable space management.
        For MemoryOptimizedDataFileGroup, this parameter is ignored as memory-optimized filegroups do not use auto-growth settings.

    .PARAMETER MaxSize
        Sets the maximum size the file can grow to in megabytes (MB). Defaults to unlimited (-1) if not specified.
        Use this to prevent runaway file growth and protect disk space, particularly important on shared storage or systems with limited capacity.
        For MemoryOptimizedDataFileGroup, this parameter is ignored.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase for pipeline operations. This enables you to filter databases first, then add files to the selected ones.
        Useful when working with multiple databases that match specific criteria rather than specifying database names directly.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, Data, File, FileGroup
        Author: the dbatools team + Claude

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2025 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Add-DbaDbFile

    .EXAMPLE
        PS C:\> Add-DbaDbFile -SqlInstance sql2016 -Database TestDb -FileGroup HRFG1 -FileName "HRFG1_data1"

        Adds a new data file named HRFG1_data1 to the HRFG1 filegroup in the TestDb database using default size and growth settings.

    .EXAMPLE
        PS C:\> Add-DbaDbFile -SqlInstance sql2016 -Database TestDb -FileGroup dbatools_inmem -FileName "inmem_container" -Path "C:\Data\inmem"

        Adds a memory-optimized container to the dbatools_inmem MemoryOptimizedDataFileGroup. For memory-optimized filegroups, the Path should be a directory.

    .EXAMPLE
        PS C:\> Add-DbaDbFile -SqlInstance sql2016 -Database TestDb -FileGroup Secondary -FileName "Secondary_data2" -Size 512 -Growth 128 -MaxSize 10240

        Adds a new 512MB data file with 128MB growth increments and a maximum size of 10GB to the Secondary filegroup.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 -Database TestDb | Add-DbaDbFile -FileGroup HRFG1 -FileName "HRFG1_data1"

        Pipes the TestDb database and adds a new file to the HRFG1 filegroup using pipeline input.

    .EXAMPLE
        PS C:\> Add-DbaDbFile -SqlInstance sql2016 -Database TestDb -FileGroup HRFG1 -FileName "HRFG1_data1" -Path "E:\SQLData\TestDb_HRFG1_data1.ndf"

        Adds a new data file with a custom path and filename to the HRFG1 filegroup.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string]$FileGroup,
        [string]$FileName,
        [string]$Path,
        [int]$Size = 128,
        [int]$Growth = 64,
        [int]$MaxSize = -1,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {

        if (Test-Bound -Not -ParameterName FileGroup) {
            Stop-Function -Message "FileGroup is required"
            return
        }

        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            # Verify the filegroup exists
            if ($db.FileGroups.Name -notcontains $FileGroup) {
                Stop-Function -Message "Filegroup $FileGroup does not exist in database $($db.Name) on $($server.Name)" -Continue
            }

            $fileGroupObject = $db.FileGroups[$FileGroup]

            # Check SQL Server version for memory-optimized filegroups
            if ($fileGroupObject.FileGroupType -eq "MemoryOptimizedDataFileGroup") {
                if ($server.VersionMajor -lt 12) {
                    Stop-Function -Message "Memory-optimized filegroups require SQL Server 2014 or higher. Server $($server.Name) is version $($server.VersionMajor) (SQL Server $($server.VersionString))." -Continue
                }
            }

            # Auto-generate filename if not provided
            if (Test-Bound -Not -ParameterName FileName) {
                $existingFileCount = $fileGroupObject.Files.Count
                $FileName = "$($db.Name)_$($FileGroup)_$($existingFileCount + 1)"
            }

            # Check if a file with this logical name already exists
            if ($db.FileGroups.Files.Name -contains $FileName) {
                Stop-Function -Message "A file with the logical name $FileName already exists in database $($db.Name) on $($server.Name)" -Continue
            }

            # Determine the file path
            if (Test-Bound -Not -ParameterName Path) {
                $defaultPath = (Get-DbaDefaultPath -SqlInstance $server).Data

                # For MemoryOptimizedDataFileGroup, use directory path without file extension
                if ($fileGroupObject.FileGroupType -eq "MemoryOptimizedDataFileGroup") {
                    $Path = "$defaultPath\$FileName"
                } else {
                    # Standard data file with .ndf extension
                    $Path = "$defaultPath\$FileName.ndf"
                }
            }

            if ($Pscmdlet.ShouldProcess($server.Name, "Adding file $FileName to filegroup $FileGroup in database $($db.Name) on $($server.Name)")) {
                try {
                    # For MemoryOptimizedDataFileGroup, we create a different type of file
                    if ($fileGroupObject.FileGroupType -eq "MemoryOptimizedDataFileGroup") {
                        Write-Message -Level Verbose -Message "Creating memory-optimized container $FileName in filegroup $FileGroup"

                        $newFile = New-Object Microsoft.SqlServer.Management.Smo.DataFile -ArgumentList $fileGroupObject, $FileName
                        $newFile.FileName = $Path

                        # Memory-optimized filegroups don't use Size, Growth, or MaxSize properties
                        # Add the file to the filegroup
                        $fileGroupObject.Files.Add($newFile)

                        # Alter the filegroup to persist the changes
                        $fileGroupObject.Alter()

                        # Refresh to get updated state
                        $db.Refresh()

                        # Return the newly created file
                        $db.FileGroups[$FileGroup].Files[$FileName]
                    } else {
                        # Standard data file creation
                        Write-Message -Level Verbose -Message "Creating data file $FileName in filegroup $FileGroup"

                        $newFile = New-Object Microsoft.SqlServer.Management.Smo.DataFile -ArgumentList $fileGroupObject, $FileName
                        $newFile.FileName = $Path
                        $newFile.Size = ($Size * 1024)
                        $newFile.Growth = ($Growth * 1024)
                        $newFile.GrowthType = "KB"

                        if ($MaxSize -gt 0) {
                            $newFile.MaxSize = ($MaxSize * 1024)
                        } else {
                            $newFile.MaxSize = -1
                        }

                        # Add the file to the filegroup
                        $fileGroupObject.Files.Add($newFile)

                        # Alter the filegroup to persist the changes
                        $fileGroupObject.Alter()

                        # Refresh to get updated state
                        $db.Refresh()

                        # Return the newly created file
                        $db.FileGroups[$FileGroup].Files[$FileName]
                    }
                } catch {
                    Stop-Function -Message "Failure on $($server.Name) to add file $FileName to filegroup $FileGroup in database $($db.Name)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}
