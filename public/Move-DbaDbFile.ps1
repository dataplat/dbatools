function Move-DbaDbFile {
    <#
    .SYNOPSIS
        Relocates database files to different drives or folders while maintaining database integrity.

    .DESCRIPTION
        Relocates database data and log files to new locations on the same SQL Server instance. The function takes the database offline, copies files to the new location, updates the database metadata with ALTER DATABASE commands, and brings the database back online.

        This is typically used when you need to move databases to faster storage, free up disk space, or reorganize your file layout without restoring from backup. The function handles both local and remote SQL Server instances, preserves file permissions, and optionally removes the original files after successful moves.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the user database whose files will be relocated to new paths.
        System databases (master, model, msdb, tempdb) are not supported for safety reasons.

    .PARAMETER FileToMove
        Defines specific file movements using a hashtable where keys are logical file names and values are destination directory paths.
        Use this when you need granular control over where each file goes, like separating data and log files to different drives.
        Example: @{'MyDB_Data'='E:\Data'; 'MyDB_Log'='F:\Logs'}

    .PARAMETER FileType
        Specifies which file types to relocate: Data, Log, or Both (default).
        Use this with FileDestination when you want to move all files of a specific type to the same directory.
        Cannot be combined with FileToMove parameter as they serve different movement strategies.

    .PARAMETER FileDestination
        Sets the target directory where all selected database files will be moved.
        Used with FileType parameter to move all data files, log files, or both to a single location.
        Must be accessible to the SQL Server service account and have sufficient space for the files.

    .PARAMETER DeleteAfterMove
        Removes the original database files from their source location after successful relocation.
        Use this to free up disk space on the source drive once files are confirmed copied and database metadata updated.
        Files are only deleted after successful copy and database metadata update to prevent data loss.

    .PARAMETER FileStructureOnly
        Returns the current file structure as a hashtable template without performing any file operations.
        Use this to discover logical file names and current paths, then modify the output for use with FileToMove.
        Helpful for planning complex moves or scripting multiple database relocations.

    .PARAMETER Force
        Forces the database offline using WITH ROLLBACK IMMEDIATE, terminating active transactions and connections.
        Use this when the database has active connections that would prevent it from going offline gracefully.
        Without this switch, the operation may fail if users are connected to the database.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Move, File
        Author: Claudio Silva (@claudioessilva), claudioeesilva.eu

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Move-DbaDbFile

    .EXAMPLE
        PS C:\> Move-DbaDbFile -SqlInstance sql2017 -Database dbatools -FileType Data -FileDestination D:\DATA2

        Copy all data files of dbatools database on sql2017 instance to the "D:\DATA2" path.
        Before it puts database offline and after copy each file will update database metadata and it ends by set the database back online

    .EXAMPLE
        PS C:\> $fileToMove=@{
        >> 'dbatools'='D:\DATA3'
        >> 'dbatools_log'='D:\LOG2'
        >> }
        PS C:\> Move-DbaDbFile -SqlInstance sql2019 -Database dbatools -FileToMove $fileToMove

        Declares a hashtable that says for each logical file the new path.
        Copy each dbatools database file referenced on the hashtable on the sql2019 instance from the current location to the new mentioned location (D:\DATA3 and D:\LOG2 paths).
        Before it puts database offline and after copy each file will update database metadata and it ends by set the database back online

    .EXAMPLE
        PS C:\> Move-DbaDbFile -SqlInstance sql2017 -Database dbatools -FileStructureOnly

        Shows the current database file structure (without filenames). Example: 'dbatools'='D:\Data'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$Database,
        [parameter(ParameterSetName = "All")]
        [ValidateSet('Data', 'Log', 'Both')]
        [string]$FileType,
        [parameter(ParameterSetName = "All")]
        [string]$FileDestination,
        [parameter(ParameterSetName = "Detailed")]
        [hashtable]$FileToMove,
        [parameter(ParameterSetName = "All")]
        [parameter(ParameterSetName = "Detailed")]
        [switch]$DeleteAfterMove,
        [parameter(ParameterSetName = "FileStructure")]
        [switch]$FileStructureOnly,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ((Test-Bound -ParameterName FileType) -and (-not(Test-Bound -ParameterName FileDestination))) {
            Stop-Function -Category InvalidArgument -Message "FileDestination parameter is missing. Quitting."
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        if ((-not $FileType) -and (-not $FileToMove) -and (-not $FileStructureOnly) ) {
            Stop-Function -Message "You must specify at least one of -FileType or -FileToMove or -FileStructureOnly to continue"
            return
        }

        if ($Database -in @("master", "model", "msdb", "tempdb")) {
            Stop-Function -Message "System database detected as input. The command does not support moving system databases. Quitting."
            return
        }

        try {
            try {
                $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
                return
            }

            switch ($FileType) {
                'Data' { $fileTypeFilter = 0 }
                'Log' { $fileTypeFilter = 1 }
                'Both' { $fileTypeFilter = -1 }
                default { $fileTypeFilter = -1 }
            }

            $dbStatus = (Get-DbaDbState -SqlInstance $server -Database $Database).Status
            if ($dbStatus -ne 'ONLINE') {
                Write-Message -Level Verbose -Message "Database $Database is not ONLINE. Getting file strucutre from sys.master_files."
                if ($fileTypeFilter -eq -1) {
                    $DataFiles = Get-DbaDbPhysicalFile -SqlInstance $server | Where-Object Name -EQ $Database | Select-Object LogicalName, PhysicalName
                } else {
                    $DataFiles = Get-DbaDbPhysicalFile -SqlInstance $server | Where-Object { $_.Name -eq $Database -and $_.Type -eq $fileTypeFilter } | Select-Object LogicalName, PhysicalName
                }
            } else {
                if ($fileTypeFilter -eq -1) {
                    $DataFiles = Get-DbaDbFile -SqlInstance $server -Database $Database | Select-Object LogicalName, PhysicalName
                } else {
                    $DataFiles = Get-DbaDbFile -SqlInstance $server -Database $Database | Where-Object Type -EQ $fileTypeFilter | Select-Object LogicalName, PhysicalName
                }
            }

            if (@($DataFiles).Count -gt 0) {

                if ($FileStructureOnly) {
                    $fileStructure = "`$fileToMove=@{`n"
                    foreach ($file in $DataFiles) {
                        $fileStructure += "`t'$($file.LogicalName)'='$(Split-Path -Path $file.PhysicalName -Parent)'`n"
                    }
                    $fileStructure += "}"
                    Write-Output $fileStructure
                    return
                }

                if ($FileDestination) {
                    $DataFilesToMove = $DataFiles | Select-Object -ExpandProperty LogicalName
                } else {
                    $DataFilesToMove = $FileToMove.Keys
                }

                if ($dbStatus -ne "Offline") {
                    if ($PSCmdlet.ShouldProcess($database, "Setting database $Database offline")) {
                        try {
                            $SetState = Set-DbaDbState -SqlInstance $server -Database $Database -Offline -Force:$Force
                            if ($SetState.Status -ne 'Offline') {
                                Stop-Function -Message "Setting database Offline failed!"
                                return
                            } else {
                                Write-Message -Level Verbose -Message "Database $Database was set to Offline status."
                            }
                        } catch {
                            Stop-Function -Message "Setting database Offline failed!" -ErrorRecord $_ -Target $SqlInstance
                            return
                        }
                    }
                }

                $locally = $false
                if ([DbaValidate]::IsLocalhost($server.ComputerName)) {
                    # locally ran so we can just use Start-BitsTransfer
                    $ComputerName = $server.ComputerName
                    $locally = $true
                } else {
                    # let's start checking if we can access .ComputerName
                    $testPS = $false
                    if ($SqlCredential) {
                        # why does Test-PSRemoting require a Credential param ? this is ugly...
                        $testPS = Test-PSRemoting -ComputerName $server.ComputerName -Credential $SqlCredential -ErrorAction Stop
                    } else {
                        $testPS = Test-PSRemoting -ComputerName $server.ComputerName -ErrorAction Stop
                    }
                    if (-not ($testPS)) {
                        # let's try to resolve it to a more qualified name, without "cutting" knowledge about the domain (only $server.Name possibly holds the complete info)
                        $Resolved = (Resolve-DbaNetworkName -ComputerName $server.Name).FullComputerName
                        if ($SqlCredential) {
                            $testPS = Test-PSRemoting -ComputerName $Resolved -Credential $SqlCredential -ErrorAction Stop
                        } else {
                            $testPS = Test-PSRemoting -ComputerName $Resolved -ErrorAction Stop
                        }
                        if ($testPS) {
                            $ComputerName = $Resolved
                        }
                    } else {
                        $ComputerName = $server.ComputerName
                    }
                }

                # if we don't have remote access ($ComputerName is null) we can fallback to admin shares if they're available
                if ($null -eq $ComputerName) {
                    $ComputerName = $server.ComputerName
                }

                # Test if defined paths are accesible by the instance
                $testPathResults = @()
                if ($FileDestination) {
                    if (-not (Test-DbaPath -SqlInstance $server -Path $FileDestination)) {
                        $testPathResults += $FileDestination
                    }
                } else {
                    foreach ($filePath in $FileToMove.Keys) {
                        if (-not (Test-DbaPath -SqlInstance $server -Path $FileToMove[$filePath])) {
                            $testPathResults += $FileToMove[$filePath]
                        }
                    }
                }
                if (@($testPathResults).Count -gt 0) {
                    Stop-Function -Message "The path(s):`r`n $($testPathResults -join [Environment]::NewLine)`r`n is/are not accessible by the instance. Confirm if it/they exists."
                    return
                }

                foreach ($LogicalName in $DataFilesToMove) {
                    $physicalName = $DataFiles | Where-Object LogicalName -EQ $LogicalName | Select-Object -ExpandProperty PhysicalName

                    if ($FileDestination) {
                        $destinationPath = $FileDestination
                    } else {
                        $destinationPath = $FileToMove[$LogicalName]
                    }
                    $fileName = [IO.Path]::GetFileName($physicalName)
                    $destination = "$destinationPath\$fileName"

                    if ($physicalName -ne $destination) {
                        if ($locally) {
                            if ($PSCmdlet.ShouldProcess($database, "Copying file $physicalName to $destination using Bits locally on $ComputerName")) {
                                try {
                                    Start-BitsTransfer -Source $physicalName -Destination $destination -ErrorAction Stop
                                } catch {
                                    try {
                                        Write-Message -Level Warning -Message "WARN: Could not copy file using Bits transfer. $_"
                                        Write-Message -Level Verbose -Message "Trying with Copy-Item"
                                        Copy-Item -Path $physicalName -Destination $destination -ErrorAction Stop

                                    } catch {
                                        $failed = $true

                                        Write-Message -Level Important -Message "ERROR: Could not copy file. $_"
                                    }
                                }
                            }
                        } else {
                            # Use Remoting PS to run the command on the server
                            try {
                                if ($PSCmdlet.ShouldProcess($database, "Copying file $physicalName to $destination using remote PS on $ComputerName")) {
                                    $scriptBlock = {
                                        $physicalName = $args[0]
                                        $destination = $args[1]

                                        # Version 1 will yield - "The remote use of BITS is not supported." when using Remoting PS
                                        if ((Get-Command -Name Start-BitsTransfer).Version.Major -gt 1) {
                                            Write-Verbose "Try copying using Start-BitsTransfer."
                                            Start-BitsTransfer -Source $physicalName -Destination $destination -ErrorAction Stop
                                        } else {
                                            Write-Verbose "Can't use Bits. Using Copy-Item instead"
                                            Copy-Item -Path $physicalName -Destination $destination -ErrorAction Stop
                                        }

                                        Get-Acl -Path $physicalName | Set-Acl $destination
                                    }
                                    Invoke-Command2 -ComputerName $ComputerName -Credential $SqlCredential -ScriptBlock $scriptBlock -ArgumentList $physicalName, $destination
                                }
                            } catch {
                                # Try using UNC paths
                                try {
                                    $physicalNameUNC = Join-AdminUnc -ServerName $ComputerName -Filepath $physicalName
                                    $destinationUNC = Join-AdminUnc -ServerName $ComputerName -Filepath $destination

                                    if ($PSCmdlet.ShouldProcess($database, "Copying file $physicalNameUNC to $destinationUNC using UNC path for $ComputerName")) {

                                        try {
                                            Write-Message -Level Verbose -Message "Try copying using Start-BitsTransfer with UNC paths."
                                            Start-BitsTransfer -Source $physicalNameUNC -Destination $destinationUNC -ErrorAction Stop
                                        } catch {
                                            Write-Message -Level Warning -Message "Did not work using Start-BitsTransfer. ERROR: $_"
                                            Write-Message -Level Verbose -Message "Trying using Copy-Item with UNC paths instead."
                                            Copy-Item -Path $physicalNameUNC -Destination $destinationUNC -ErrorAction Stop
                                        }

                                        # Force the copy of the file's ACL
                                        Get-Acl -Path $physicalNameUNC | Set-Acl $destinationUNC

                                        Write-Message -Level Verbose -Message "File $fileName was copied successfully"
                                    }
                                } catch {
                                    $failed = $true

                                    Write-Message -Level Important -Message "ERROR: Could not copy file. $_"
                                }
                            }

                            Write-Message -Level Verbose -Message "File $fileName was copied successfully"
                        }
                        # initialize the returnobject first with the values of a successful move
                        $returnObject = [PSCustomObject]@{
                            Instance             = $SqlInstance
                            Database             = $Database
                            LogicalName          = $LogicalName
                            Source               = $physicalName
                            Destination          = $destination
                            Result               = "Success"
                            DatabaseFileMetadata = "Updated"
                            SourceFileDeleted    = $true
                        }
                        if (-not $failed) {

                            $query = "ALTER DATABASE [$Database] MODIFY FILE (name=[$LogicalName], filename='$destination'); "

                            if ($PSCmdlet.ShouldProcess($Database, "Executing ALTER DATABASE query - $query")) {
                                # Change database file path
                                $server.Databases["master"].Query($query)
                            }
                            if ($DeleteAfterMove) {
                                try {
                                    if ($PSCmdlet.ShouldProcess($database, "Deleting source file $physicalName")) {
                                        if ($locally) {
                                            Remove-Item -Path $physicalName -ErrorAction Stop
                                        } else {
                                            $scriptBlock = {
                                                $source = $args[0]
                                                Remove-Item -Path $source -ErrorAction Stop
                                            }
                                            Invoke-Command2 -ComputerName $ComputerName -Credential $SqlCredential -ScriptBlock $scriptBlock -ArgumentList $physicalName
                                        }
                                        $returnObject
                                    }
                                } catch {
                                    $returnObject.SourceFileDeleted = $false
                                    $returnObject

                                    Stop-Function -Message "ERROR:" -ErrorRecord $_
                                }
                            } else {
                                $returnObject.SourceFileDeleted = $false
                                $returnObject
                            }
                        } else {
                            $returnObject.SourceFileDeleted = "N/A"
                            $returnObject.DatabaseFileMetadata = "N/A"
                            $returnObject.Result = "Failed"
                            $returnObject
                        }
                    } else {
                        Write-Message -Level Verbose -Message "File $fileName already exists on $destination. Skipping."
                        $returnObject.SourceFileDeleted = "N/A"
                        $returnObject.DatabaseFileMetadata = "N/A"
                        $returnObject.Result = "Already exists. Skipping"
                        $returnObject
                    }
                }

                if ($PSCmdlet.ShouldProcess($Database, "Setting database Online")) {
                    try {
                        $SetState = Set-DbaDbState -SqlInstance $server -Database $Database -Online -ErrorVariable dbstate
                        if ($SetState.Status -ne 'Online') {
                            Stop-Function -Message "$($SetState.Notes)! : $($dbstate.Exception.InnerException.InnerException.InnerException.InnerException)."
                        } else {
                            Write-Message -Level Verbose -Message "Database is online!"
                        }
                    } catch {
                        Stop-Function -Message "Setting database online failed! : $($_.Exception.InnerException.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage
                    }
                }
            } else {
                Write-Message -Level Warning -Message "We could not get any files for database $Database!"
            }
        } catch {
            Stop-Function -Message "ERROR:" -ErrorRecord $_
        }
    }
}