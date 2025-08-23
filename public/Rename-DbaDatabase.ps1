function Rename-DbaDatabase {
    <#
    .SYNOPSIS
        Renames database names, filegroups, logical files, and physical files using customizable templates with placeholder support.

    .DESCRIPTION
        Systematically renames all database components using template-based naming conventions to enforce consistent standards across your SQL Server environment.
        This function addresses the common challenge of standardizing database naming when inheriting inconsistent systems or implementing new naming policies.

        The renaming process follows SQL Server's object hierarchy and executes in this order:
        - Database name is changed (optionally forcing users out)
        - Filegroup names are changed accordingly
        - Logical file names are changed accordingly
        - Physical file names are changed accordingly
        - If Move is specified, the database goes offline for file operations, then back online
        - If Move is not specified, the database remains online (unless SetOffline), and you handle file moves manually

        The function uses powerful template placeholders like <DBN> for database name, <FGN> for filegroup name, <DATE> for current date, and <FT> for file type.
        When naming conflicts occur, automatic counters are appended to ensure uniqueness.
        If any step fails, the entire process stops to prevent partial renames that could leave your database in an inconsistent state.

        Always backup your databases before using this function, and take a full backup of master after completion.
        The function returns detailed objects showing all completed renames, with hidden properties providing human-readable summaries.

        Store results in a variable for troubleshooting: "$result = Rename-DbaDatabase ....."
        Use the -Preview parameter first to see exactly what changes would occur: "Rename-DbaDatabase .... -Preview | Select-Object *"

    .PARAMETER SqlInstance
        Target any number of instances, in order to return their build state.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to include in the renaming operation. Accepts database names, wildcards, or arrays of database names.
        Use this when you need to rename specific databases instead of all user databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies databases to exclude from the renaming operation. Accepts database names, wildcards, or arrays of database names.
        Use this to protect specific databases when using -AllDatabases or when you want to process most databases except certain ones.

    .PARAMETER AllDatabases
        Applies the renaming operation to all user databases on the SQL Server instance. System databases are automatically excluded.
        Use this switch when standardizing naming conventions across your entire instance rather than targeting specific databases.

    .PARAMETER DatabaseName
        Specifies a template for renaming database names using placeholder substitution. Creates new database names based on the template pattern.
        Use this when you need to standardize database names according to organizational naming conventions. Common patterns include adding prefixes, suffixes, or date stamps.
        Valid placeholders are: <DBN> (current database name), <DATE> (current date in yyyyMMdd format).

    .PARAMETER FileGroupName
        Specifies a template for renaming filegroup names within databases using placeholder substitution. Note that the PRIMARY filegroup cannot be renamed due to SQL Server restrictions.
        Use this when you need consistent filegroup naming across databases or when implementing data organization strategies that require specific filegroup names.
        Valid placeholders are: <FGN> (current filegroup name), <DBN> (current database name), <DATE> (current date in yyyyMMdd format). If distinct names cannot be generated, a counter is appended (0001, 0002, etc).

    .PARAMETER LogicalName
        Specifies a template for renaming the logical names of database files using placeholder substitution. Logical names are used internally by SQL Server to reference files.
        Use this when you need consistent logical file naming for backup operations, maintenance scripts, or troubleshooting, as logical names are referenced in many SQL commands.
        Valid placeholders are: <FT> (file type: ROWS, LOG, MMO, FS), <LGN> (current logical name), <FGN> (current filegroup name), <DBN> (current database name), <DATE> (current date in yyyyMMdd format). If distinct names cannot be generated, a counter is appended (0001, 0002, etc).

    .PARAMETER FileName
        Specifies a template for renaming physical database file names on disk using placeholder substitution. Changes only the file name, preserving the original directory and file extension.
        Use this when you need to align physical file names with your database naming standards for easier file management, monitoring, and disaster recovery operations.
        Valid placeholders are: <FNN> (current file name without directory or extension), <FT> (file type: ROWS, LOG, MMO, FS), <LGN> (current logical name), <FGN> (current filegroup name), <DBN> (current database name), <DATE> (current date in yyyyMMdd format). If distinct names cannot be generated, a counter is appended (0001, 0002, etc).

    .PARAMETER ReplaceBefore
        Modifies how placeholder substitution works by removing old database, filegroup, and logical names from current names before applying templates. This prevents duplicate naming components in nested scenarios.
        Use this when your existing names already contain components that would be duplicated by the template placeholders, resulting in cleaner final names.
        For example, with -ReplaceBefore, renaming database "HR_DB" to "PROD_HR" and using template "<DBN>_Data" results in "PROD_HR_Data" instead of "PROD_HR_HR_DB_Data".

    .PARAMETER Force
        Terminates all active connections to target databases to allow renaming operations to proceed. Required when databases have active connections that would prevent rename operations.
        Use this when you need to force database renames in production environments where applications may maintain persistent connections.

    .PARAMETER SetOffline
        Forces the database offline after renaming operations to prepare for manual file moves. Terminates active connections and sets database state to offline.
        Use this when you need to rename physical files but want to handle the file movement operations manually rather than having the function move them automatically.

    .PARAMETER Move
        Automatically moves physical database files to match renamed file names. Sets the database offline, performs file operations, then brings the database back online.
        Use this for a complete automated renaming solution when you want the function to handle all file operations. Requires PowerShell remoting access to the SQL Server's file system.

    .PARAMETER Preview
        Displays what renaming operations would be performed without executing any changes to the databases. Shows the complete rename plan including all affected components.
        Use this first to verify your templates and parameters will produce the desired results before committing to actual database changes.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER InputObject
        Accepts database objects from the pipeline, typically from Get-DbaDatabase. Allows for advanced filtering and database selection before renaming.
        Use this when you need complex database selection logic or when chaining database operations in a pipeline.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Rename
        Author: Simone Bizzotto (@niphold)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Rename-DbaDatabase

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName HR2 -Preview | Select-Object *

        Shows the detailed result set you'll get renaming the HR database to HR2 without doing anything

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName HR2

        Renames the HR database to HR2

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqlserver2014a -Database HR | Rename-DbaDatabase -DatabaseName HR2

        Same as before, but with a piped database (renames the HR database to HR2)

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName "dbatools_<DBN>"

        Renames the HR database to dbatools_HR

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName "dbatools_<DBN>_<DATE>"

        Renames the HR database to dbatools_HR_20170807 (if today is 07th Aug 2017)

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -FileGroupName "dbatools_<FGN>"

        Renames every FileGroup within HR to "dbatools_[the original FileGroup name]"

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName "dbatools_<DBN>" -FileGroupName "<DBN>_<FGN>"

        Renames the HR database to "dbatools_HR", then renames every FileGroup within to "dbatools_HR_[the original FileGroup name]"

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -FileGroupName "dbatools_<DBN>_<FGN>"
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName "dbatools_<DBN>"

        Renames the HR database to "dbatools_HR", then renames every FileGroup within to "dbatools_HR_[the original FileGroup name]"

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName "dbatools_<DBN>" -FileName "<DBN>_<FGN>_<FNN>"

        Renames the HR database to "dbatools_HR" and then all filenames as "dbatools_HR_[Name of the FileGroup]_[original_filename]"
        The db stays online (watch out!). You can then proceed manually to move/copy files by hand, set the db offline and then online again to finish the rename process

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName "dbatools_<DBN>" -FileName "<DBN>_<FGN>_<FNN>" -SetOffline

        Renames the HR database to "dbatools_HR" and then all filenames as "dbatools_HR_[Name of the FileGroup]_[original_filename]"
        The db is then set offline (watch out!). You can then proceed manually to move/copy files by hand and then set it online again to finish the rename process

    .EXAMPLE
        PS C:\> Rename-DbaDatabase -SqlInstance sqlserver2014a -Database HR -DatabaseName "dbatools_<DBN>" -FileName "<DBN>_<FGN>_<FNN>" -Move

        Renames the HR database to "dbatools_HR" and then all filenames as "dbatools_HR_[Name of the FileGroup]_[original_filename]"
        The db is then set offline (watch out!). The function tries to do a simple rename and then sets the db online again to finish the rename process

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ParameterSetName = "Server")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [parameter(ParameterSetName = "Server")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllDatabases,
        [string]$DatabaseName,
        [string]$FileGroupName,
        [string]$LogicalName,
        [string]$FileName,
        [switch]$ReplaceBefore,
        [switch]$Force,
        [switch]$Move,
        [switch]$SetOffline,
        [switch]$Preview,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Pipe")]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $CurrentDate = Get-Date -Format 'yyyyMMdd'

        function Get-DbaNameStructure($database) {
            $obj = @()
            # db name
            $obj += "- Database : $database"
            # FileGroups
            foreach ($fg in $database.FileGroups) {
                $obj += "  - FileGroup: $($fg.Name)"
                # LogicalNames
                foreach ($ln in $fg.Files) {
                    $obj += "    - Logical: $($ln.Name)"
                    $obj += "      - FileName: $($ln.FileName)"
                }
            }
            $obj += "  - Logfiles"
            foreach ($log in $database.LogFiles) {
                $obj += "    - Logical: $($log.Name)"
                $obj += "      - FileName: $($log.FileName)"
            }
            return $obj -Join "`n"
        }


        function Get-DbaKeyByValue($hashtable, $Value) {
            ($hashtable.GetEnumerator() | Where-Object Value -eq $Value).Name
        }

        if ((Test-Bound -ParameterName SetOffline) -and (-not(Test-Bound -ParameterName FileName))) {
            Stop-Function -Category InvalidArgument -Message "-SetOffline is only useful when -FileName is passed. Quitting."
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        if (!$Database -and !$AllDatabases -and !$InputObject -and !$ExcludeDatabase) {
            Stop-Function -Message "You must specify a -AllDatabases or -Database/ExcludeDatabase to continue"
            return
        }
        if (!$DatabaseName -and !$FileGroupName -and !$LogicalName -and !$FileName) {
            Stop-Function -Message "You must specify at least one of -DatabaseName,-FileGroupName,-LogicalName or -Filename to continue"
            return
        }
        $dbs = @()
        if ($InputObject) {
            if ($InputObject.Name) {
                # comes from Get-DbaDatabase
                $dbs += $InputObject
            }
        } else {
            foreach ($instance in $SqlInstance) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $sqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
                $all_dbs = $server.Databases | Where-Object IsAccessible
                $dbs += $all_dbs | Where-Object { @('master', 'model', 'msdb', 'tempdb', 'distribution') -notcontains $_.Name }
                if ($Database) {
                    $dbs = $dbs | Where-Object { $Database -contains $_.Name }
                }
                if ($ExcludeDatabase) {
                    $dbs = $dbs | Where-Object { $ExcludeDatabase -notcontains $_.Name }
                }
            }
        }

        # holds all dbs per instance to avoid naming clashes
        $InstanceDbs = @{ }

        # holds all db file enumerations (used for -Move only)
        $InstanceFiles = @{ }

        #region db loop
        foreach ($db in $dbs) {
            # used to stop futher operations on database
            $failed = $false

            # pending renames initialized at db level
            $Pending_Renames = @()

            $Entities_Before = @{ }

            $server = $db.Parent
            if ($db.Name -in @('master', 'model', 'msdb', 'tempdb', 'distribution')) {
                Write-Message -Level Warning -Message "Database $($db.Name) is a system one, skipping..."
                continue
            }
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $($db.Name) is not accessible, skipping..."
                continue
            }
            if ($db.IsMirroringEnabled -eq $true -or $db.AvailabilityGroupName.Length -gt 0) {
                Write-Message -Level Warning -Message "Database $($db.Name) is either mirrored or in an AG, skipping..."
                continue
            }
            $Server_Id = $server.DomainInstanceName
            if ( !$InstanceDbs.ContainsKey($Server_Id) ) {
                $InstanceDbs[$Server_Id] = @{ }
                foreach ($dn in $server.Databases.Name) {
                    $InstanceDbs[$Server_Id][$dn] = 1
                }
            }

            $Entities_Before['DBN'] = @{ }
            $Entities_Before['FGN'] = @{ }
            $Entities_Before['LGN'] = @{ }
            $Entities_Before['FNN'] = @{ }
            $Entities_Before['DBN'][$db.Name] = $db.Name
            #region databasename
            if ($DatabaseName) {
                $Orig_DBName = $db.Name
                # fixed replacements
                $NewDBName = $DatabaseName.Replace('<DBN>', $Orig_DBName).Replace('<DATE>', $CurrentDate)
                if ($Orig_DBName -eq $NewDBName) {
                    Write-Message -Level VeryVerbose -Message "Database name unchanged, skipping"
                } else {
                    if ($InstanceDbs[$Server_Id].ContainsKey($NewDBName)) {
                        Write-Message -Level Warning -Message "Database $NewDBName exists already, skipping this rename"
                        $failed = $true
                    } else {
                        if ($PSCmdlet.ShouldProcess($db, "Renaming Database $db to $NewDBName")) {
                            if ($Force) {
                                $server.KillAllProcesses($Orig_DBName)
                            }
                            try {
                                if (!$Preview) {
                                    $db.Rename($NewDBName)
                                }
                                $InstanceDbs[$Server_Id].Remove($Orig_DBName)
                                $InstanceDbs[$Server_Id][$NewDBName] = 1
                                $Entities_Before['DBN'][$Orig_DBName] = $NewDBName
                                #$db.Refresh()
                            } catch {
                                Stop-Function -Message "Failed to rename Database : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage
                                # stop any further renames
                                $failed = $true
                            }
                        }
                    }
                }
            }
            #endregion databasename
            #region filegroupname
            if ($ReplaceBefore) {
                #backfill PRIMARY
                $Entities_Before['FGN']['PRIMARY'] = 'PRIMARY'
                foreach ($fg in $db.FileGroups.Name) {
                    $Entities_Before['FGN'][$fg] = $fg
                }
            }

            if (!$failed -and $FileGroupName) {
                $Editable_FGs = $db.FileGroups | Where-Object Name -ne 'PRIMARY'
                $New_FGNames = @{ }
                foreach ($fg in $db.FileGroups.Name) {
                    $New_FGNames[$fg] = 1
                }
                $FGCounter = 0
                foreach ($fg in $Editable_FGs) {
                    $Orig_FGName = $fg.Name
                    $Orig_Placeholder = $Orig_FGName
                    if ($ReplaceBefore) {
                        # at Filegroup level, we need to worry about database name
                        $Orig_Placeholder = $Orig_Placeholder.Replace($Entities_Before['DBN'][$Orig_DBName], '')
                    }
                    $NewFGName = $FileGroupName.Replace('<DBN>', $Entities_Before['DBN'][$db.Name]).Replace('<DATE>', $CurrentDate).Replace('<FGN>', $Orig_Placeholder)
                    $FinalFGName = $NewFGName
                    while ($fg.Name -ne $FinalFGName) {
                        if ($FinalFGName -in $New_FGNames.Keys) {
                            $FGCounter += 1
                            $FinalFGName = "$NewFGName$($FGCounter.ToString('000'))"
                        } else {
                            break
                        }
                    }
                    if ($fg.Name -eq $FinalFGName) {
                        Write-Message -Level VeryVerbose -Message "No rename necessary for FileGroup $($fg.Name) (on $db)"
                        continue
                    }
                    if ($PSCmdlet.ShouldProcess($db, "Renaming FileGroup $($fg.Name) to $FinalFGName")) {
                        try {
                            if (!$Preview) {
                                $fg.Rename($FinalFGName)
                            }
                            $New_FGNames.Remove($Orig_FGName)
                            $New_FGNames[$FinalFGName] = 1
                            $Entities_Before['FGN'][$Orig_FGName] = $FinalFGName
                        } catch {
                            Stop-Function -Message "Failed to rename FileGroup : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage
                            # stop any further renames
                            $failed = $true
                            break
                        }
                    }
                }
                #$db.FileGroups.Refresh()
            }

            #endregion filegroupname
            #region logicalname
            if ($ReplaceBefore) {
                foreach ($fn in $db.FileGroups.Files.Name) {
                    $Entities_Before['LGN'][$fn] = $fn
                }
                foreach ($fn in $db.Logfiles.Name) {
                    $Entities_Before['LGN'][$fn] = $fn
                }
            }
            if (!$failed -and $LogicalName) {
                $New_LogicalNames = @{ }
                foreach ($fn in $db.FileGroups.Files.Name) {
                    $New_LogicalNames[$fn] = 1
                }
                foreach ($fn in $db.Logfiles.Name) {
                    $New_LogicalNames[$fn] = 1
                }
                $LNCounter = 0
                foreach ($fg in $db.FileGroups) {
                    $logicalfiles = @($fg.Files)
                    for ($i = 0; $i -lt $logicalfiles.Count; $i++) {
                        $logical = $logicalfiles[$i]
                        $FileType = switch ($fg.FileGroupType) {
                            'RowsFileGroup' { 'ROWS' }
                            'MemoryOptimizedDataFileGroup' { 'MMO' }
                            'FileStreamDataFileGroup' { 'FS' }
                            default { 'STD' }
                        }
                        $Orig_LGName = $logical.Name
                        $Orig_Placeholder = $Orig_LGName
                        if ($ReplaceBefore) {
                            # at Logical Name level, we need to worry about database name and filegroup name
                            $Orig_Placeholder = $Orig_Placeholder.Replace((Get-DbaKeyByValue -HashTable $Entities_Before['DBN'] -Value $db.Name), '').Replace(
                                (Get-DbaKeyByValue -HashTable $Entities_Before['FGN'] -Value $fg.Name), '')
                        }
                        $NewLGName = $LogicalName.Replace('<DBN>', $db.Name).Replace('<DATE>', $CurrentDate).Replace('<FGN>', $fg.Name).Replace(
                            '<FT>', $FileType).Replace('<LGN>', $Orig_Placeholder)
                        $FinalLGName = $NewLGName
                        while ($logical.Name -ne $FinalLGName) {
                            if ($FinalLGName -in $New_LogicalNames.Keys) {
                                $LNCounter += 1
                                $FinalLGName = "$NewLGName$($LNCounter.ToString('000'))"
                            } else {
                                break
                            }
                        }
                        if ($logical.Name -eq $FinalLGName) {
                            Write-Message -Level VeryVerbose -Message "No rename necessary for LogicalFile $($logical.Name) (on FileGroup $($fg.Name) (on $db))"
                            continue
                        }
                        if ($PSCmdlet.ShouldProcess($db, "Renaming LogicalFile $($logical.Name) to $FinalLGName (on FileGroup $($fg.Name))")) {
                            try {
                                if (!$Preview) {
                                    $logical.Rename($FinalLGName)
                                }
                                $New_LogicalNames.Remove($Orig_LGName)
                                $New_LogicalNames[$FinalLGName] = 1
                                $Entities_Before['LGN'][$Orig_LGName] = $FinalLGName
                            } catch {
                                Stop-Function -Message "Failed to Rename Logical File : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage
                                # stop any further renames
                                $failed = $true
                                break
                            }
                        }
                    }
                }
                #$fg.Files.Refresh()
                if (!$failed) {
                    $logfiles = @($db.LogFiles)
                    for ($i = 0; $i -lt $logfiles.Count; $i++) {
                        $logicallog = $logfiles[$i]
                        $Orig_LGName = $logicallog.Name
                        $Orig_Placeholder = $Orig_LGName
                        if ($ReplaceBefore) {
                            # at Logical Name level, we need to worry about database name and filegroup name, but for logfiles filegroup is not there
                            $Orig_Placeholder = $Orig_Placeholder.Replace((Get-DbaKeyByValue -HashTable $Entities_Before['DBN'] -Value $db.Name), '').Replace(
                                (Get-DbaKeyByValue -HashTable $Entities_Before['FGN'] -Value $fg.Name), '')
                        }
                        $NewLGName = $LogicalName.Replace('<DBN>', $db.Name).Replace('<DATE>', $CurrentDate).Replace('<FGN>', '').Replace(
                            '<FT>', 'LOG').Replace('<LGN>', $Orig_Placeholder)
                        $FinalLGName = $NewLGName
                        if ($FinalLGName.Length -eq 0) {
                            #someone passed in -LogicalName '<FGN>'.... but we don't have FGN here
                            $FinalLGName = $Orig_LGName
                        }
                        while ($logicallog.Name -ne $FinalLGName) {
                            if ($FinalLGName -in $New_LogicalNames.Keys) {
                                $LNCounter += 1
                                $FinalLGName = "$NewLGName$($LNCounter.ToString('000'))"
                            } else {
                                break
                            }
                        }
                        if ($logicallog.Name -eq $FinalLGName) {
                            Write-Message -Level VeryVerbose -Message "No Rename necessary for LogicalFile log $($logicallog.Name) (LOG on (on $db))"
                            continue
                        }
                        if ($PSCmdlet.ShouldProcess($db, "Renaming LogicalFile log $($logicallog.Name) to $FinalLGName (LOG)")) {
                            try {
                                if (!$Preview) {
                                    $logicallog.Rename($FinalLGName)
                                }
                                $New_LogicalNames.Remove($Orig_LGName)
                                $New_LogicalNames[$FinalLGName] = 1
                                $Entities_Before['LGN'][$Orig_LGName] = $FinalLGName
                            } catch {
                                Stop-Function -Message "Failed to Rename Logical File : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage
                                # stop any further renames
                                $failed = $true
                                break
                            }
                        }
                    }
                    #$db.Logfiles.Refresh()
                }
            }
            #endregion logicalname
            #region filename
            if ($ReplaceBefore) {
                foreach ($fn in $db.FileGroups.Files.FileName) {
                    $Entities_Before['FNN'][$fn] = $fn
                }
                foreach ($fn in $db.Logfiles.FileName) {
                    $Entities_Before['FNN'][$fn] = $fn
                }
            }
            if (!$failed -and $FileName) {

                $New_FileNames = @{ }
                foreach ($fn in $db.FileGroups.Files.FileName) {
                    $New_FileNames[$fn] = 1
                }
                foreach ($fn in $db.Logfiles.FileName) {
                    $New_FileNames[$fn] = 1
                }
                # we need to inspect what files are in the same directory
                # to avoid failing the process because the move won't work
                # here we have a dict keyed by instance and then keyed by path
                if ( !$InstanceFiles.ContainsKey($Server_Id) ) {
                    $InstanceFiles[$Server_Id] = @{ }
                }
                foreach ($fn in $New_FileNames.Keys) {
                    $dirname = [IO.Path]::GetDirectoryName($fn)
                    if ( !$InstanceFiles[$Server_Id].ContainsKey($dirname) ) {
                        $InstanceFiles[$Server_Id][$dirname] = @{ }
                        try {
                            $dirfiles = Get-DbaFile -SqlInstance $server -Path $dirname -EnableException
                        } catch {
                            Write-Message -Level Warning -Message "Failed to enumerate existing files at $dirname, move could go wrong"
                        }
                        foreach ($f in $dirfiles) {
                            $InstanceFiles[$Server_Id][$dirname][$f.Filename] = 1
                        }
                    }
                }
                $FNCounter = 0
                foreach ($fg in $db.FileGroups) {
                    $FG_Files = @($fg.Files)
                    foreach ($logical in $FG_Files) {
                        $FileType = switch ($fg.FileGroupType) {
                            'RowsFileGroup' { 'ROWS' }
                            'MemoryOptimizedDataFileGroup' { 'MMO' }
                            'FileStreamDataFileGroup' { 'FS' }
                            default { 'STD' }
                        }
                        $FNName = $logical.FileName
                        $FNNameDir = [IO.Path]::GetDirectoryName($FNName)
                        $Orig_FNNameLeaf = [IO.Path]::GetFileNameWithoutExtension($logical.FileName)
                        $Orig_Placeholder = $Orig_FNNameLeaf
                        if ($ReplaceBefore) {
                            # at Filename level, we need to worry about database name, filegroup name and logical file name
                            $Orig_Placeholder = $Orig_Placeholder.Replace((Get-DbaKeyByValue -HashTable $Entities_Before['DBN'] -Value $db.Name), '').Replace(
                                (Get-DbaKeyByValue -HashTable $Entities_Before['FGN'] -Value $fg.Name), '').Replace(
                                (Get-DbaKeyByValue -HashTable $Entities_Before['LGN'] -Value $logical.Name), '')
                        }
                        $NewFNName = $FileName.Replace('<DBN>', $db.Name).Replace('<DATE>', $CurrentDate).Replace('<FGN>', $fg.Name).Replace(
                            '<FT>', $FileType).Replace('<LGN>', $logical.Name).Replace('<FNN>', $Orig_Placeholder)
                        $FinalFNName = [IO.Path]::Combine($FNNameDir, "$NewFNName$([IO.Path]::GetExtension($FNName))")

                        while ($logical.FileName -ne $FinalFNName) {
                            if ($InstanceFiles[$Server_Id][$FNNameDir].ContainsKey($FinalFNName)) {
                                $FNCounter += 1
                                $FinalFNName = [IO.Path]::Combine($FNNameDir, "$NewFNName$($FNCounter.ToString('000'))$([IO.Path]::GetExtension($FNName))"
                                )
                            } else {
                                break
                            }
                        }
                        if ($logical.FileName -eq $FinalFNName) {
                            Write-Message -Level VeryVerbose -Message "No rename necessary (on FileGroup $($fg.Name) (on $db))"
                            continue
                        }
                        if ($PSCmdlet.ShouldProcess($db, "Renaming FileName $($logical.FileName) to $FinalFNName (on FileGroup $($fg.Name))")) {
                            try {
                                if (!$Preview) {
                                    $logical.FileName = $FinalFNName
                                    $db.Alter()
                                }
                                $InstanceFiles[$Server_Id][$FNNameDir].Remove($FNName)
                                $InstanceFiles[$Server_Id][$FNNameDir][$FinalFNName] = 1
                                $Entities_Before['FNN'][$FNName] = $FinalFNName
                                $Pending_Renames += [PSCustomObject]@{
                                    Source      = $FNName
                                    Destination = $FinalFNName
                                }
                            } catch {
                                Stop-Function -Message "Failed to Rename FileName : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage
                                # stop any further renames
                                $failed = $true
                                break
                            }
                        }
                    }
                    if (!$failed) {
                        $FG_Files = @($db.Logfiles)
                        foreach ($logical in $FG_Files) {
                            $FNName = $logical.FileName
                            $FNNameDir = [IO.Path]::GetDirectoryName($FNName)
                            $Orig_FNNameLeaf = [IO.Path]::GetFileNameWithoutExtension($logical.FileName)
                            $Orig_Placeholder = $Orig_FNNameLeaf
                            if ($ReplaceBefore) {
                                # at Filename level, we need to worry about database name, filegroup name and logical file name
                                $Orig_Placeholder = $Orig_Placeholder.Replace((Get-DbaKeyByValue -HashTable $Entities_Before['DBN'] -Value $db.Name), '').Replace(
                                    (Get-DbaKeyByValue -HashTable $Entities_Before['FGN'] -Value $fg.Name), '').Replace(
                                    (Get-DbaKeyByValue -HashTable $Entities_Before['LGN'] -Value $logical.Name), '')
                            }
                            $NewFNName = $FileName.Replace('<DBN>', $db.Name).Replace('<DATE>', $CurrentDate).Replace('<FGN>', '').Replace(
                                '<FT>', 'LOG').Replace('<LGN>', $logical.Name).Replace('<FNN>', $Orig_Placeholder)
                            $FinalFNName = [IO.Path]::Combine($FNNameDir, "$NewFNName$([IO.Path]::GetExtension($FNName))")
                            while ($logical.FileName -ne $FinalFNName) {
                                if ($InstanceFiles[$Server_Id][$FNNameDir].ContainsKey($FinalFNName)) {
                                    $FNCounter += 1
                                    $FinalFNName = [IO.Path]::Combine($FNNameDir, "$NewFNName$($FNCounter.ToString('000'))$([IO.Path]::GetExtension($FNName))")
                                } else {
                                    break
                                }
                            }
                            if ($logical.FileName -eq $FinalFNName) {
                                Write-Message -Level VeryVerbose -Message "No rename necessary for $($logical.FileName) (LOG on (on $db))"
                                continue
                            }

                            if ($PSCmdlet.ShouldProcess($db, "Renaming FileName $($logical.FileName) to $FinalFNName (LOG)")) {
                                try {
                                    if (!$Preview) {
                                        $logical.FileName = $FinalFNName
                                        $db.Alter()
                                    }
                                    $InstanceFiles[$Server_Id][$FNNameDir].Remove($FNName)
                                    $InstanceFiles[$Server_Id][$FNNameDir][$FinalFNName] = 1
                                    $Entities_Before['FNN'][$FNName] = $FinalFNName
                                    $Pending_Renames += [PSCustomObject]@{
                                        Source      = $FNName
                                        Destination = $FinalFNName
                                    }
                                } catch {
                                    Stop-Function -Message "Failed to Rename FileName : $($_.Exception.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage
                                    # stop any further renames
                                    $failed = $true
                                    break
                                }
                            }
                        }
                    }

                }
                #endregion filename
                #region move
                $ComputerName = $null
                $Final_Renames = New-Object System.Collections.ArrayList
                if ([DbaValidate]::IsLocalhost($server.ComputerName)) {
                    # locally ran so we can just use rename-item
                    $ComputerName = $server.ComputerName
                } else {
                    # let's start checking if we can access .ComputerName
                    $testPS = $false
                    if ($SqlCredential) {
                        # why does Test-PSRemoting require a Credential param ? this is ugly...
                        $testPS = Test-PSRemoting -ComputerName $server.ComputerName -Credential $SqlCredential -ErrorAction Stop
                    } else {
                        $testPS = Test-PSRemoting -ComputerName $server.ComputerName -ErrorAction Stop
                    }
                    if (!($testPS)) {
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
                foreach ($op in $pending_renames) {
                    if ([DbaValidate]::IsLocalhost($server.ComputerName)) {
                        $null = $Final_Renames.Add([PSCustomObject]@{
                                Source       = $op.Source
                                Destination  = $op.Destination
                                ComputerName = $ComputerName
                            })
                    } else {
                        if ($null -eq $ComputerName) {
                            # if we don't have remote access ($ComputerName is null) we can fallback to admin shares if they're available
                            if (Test-Path (Join-AdminUnc -ServerName $server.ComputerName -filepath $op.Source)) {
                                $null = $Final_Renames.Add([PSCustomObject]@{
                                        Source       = Join-AdminUnc -ServerName $server.ComputerName -filepath $op.Source
                                        Destination  = Join-AdminUnc -ServerName $server.ComputerName -filepath $op.Destination
                                        ComputerName = $server.ComputerName
                                    })
                            } else {
                                # flag the impossible rename ($ComputerName is $null)
                                $null = $Final_Renames.Add([PSCustomObject]@{
                                        Source       = $op.Source
                                        Destination  = $op.Destination
                                        ComputerName = $ComputerName
                                    })
                            }
                        } else {
                            # we can do renames in a remote pssession
                            $null = $Final_Renames.Add([PSCustomObject]@{
                                    Source       = $op.Source
                                    Destination  = $op.Destination
                                    ComputerName = $ComputerName
                                })
                        }
                    }
                }
                $Status = 'FULL'
                if (!$failed -and ($SetOffline -or $Move) -and $Final_Renames) {
                    if (!$Move) {
                        Write-Message -Level VeryVerbose -Message "Setting the database offline. You are in charge of moving the files to the new location"
                        # because renames still need to be dealt with
                        $Status = 'PARTIAL'
                    } else {
                        if ($PSCmdlet.ShouldProcess($db, "File Rename required, setting db offline")) {
                            $SetState = Set-DbaDbState -SqlInstance $server -Database $db.Name -Offline -Force
                            if ($SetState.Status -ne 'OFFLINE') {
                                Write-Message -Level Warning -Message "Setting db offline failed, You are in charge of moving the files to the new location"
                                # because it was impossible to set the database offline
                                $Status = 'PARTIAL'
                            } else {
                                try {
                                    while ($Final_Renames.Count -gt 0) {
                                        $op = $Final_Renames.Item(0)
                                        if ($null -eq $op.ComputerName) {
                                            Stop-Function -Message "No access to physical files for renames"
                                        } else {
                                            Write-Message -Level VeryVerbose -Message "Moving file $($op.Source) to $($op.Destination)"
                                            if (!$Preview) {
                                                $scriptBlock = {
                                                    $op = $args[0]
                                                    Rename-Item -Path $op.Source -NewName $op.Destination
                                                }
                                                Invoke-Command2 -ComputerName $op.ComputerName -Credential $sqlCredential -ScriptBlock $scriptBlock -ArgumentList $op
                                            }
                                        }
                                        $null = $Final_Renames.RemoveAt(0)
                                    }
                                } catch {
                                    $failed = $true
                                    # because a rename operation failed
                                    $Status = 'PARTIAL'
                                    Stop-Function -Message "Failed to rename $($op.Source) to $($op.Destination), you are in charge of moving the files to the new location" -ErrorRecord $_ -Target $instance -Exception $_.Exception -Continue
                                }
                                if (!$failed) {
                                    if ($PSCmdlet.ShouldProcess($db, "Setting database online")) {
                                        $SetState = Set-DbaDbState -SqlInstance $server -Database $db.Name -Online -Force
                                        if ($SetState.Status -ne 'ONLINE') {
                                            Write-Message -Level Warning -Message "Setting db online failed"
                                            # because renames were done, but the database didn't wake up
                                            $Status = 'PARTIAL'
                                        } else {
                                            $Status = 'FULL'
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    # because of a previous error with renames to do
                    $Status = 'PARTIAL'
                }
            } else {
                if (!$failed) {
                    # because no previous error and not filename
                    $Status = 'FULL'
                } else {
                    # because previous errors and not filename
                    $Status = 'PARTIAL'
                }
            }
            #endregion move
            # remove entities that match for the output
            foreach ($k in $Entities_Before.Keys) {
                $ToRemove = $Entities_Before[$k].GetEnumerator() | Where-Object { $_.Name -eq $_.Value } | Select-Object -ExpandProperty Name
                foreach ($el in $ToRemove) {
                    $Entities_Before[$k].Remove($el)
                }
            }
            [PSCustomObject]@{
                ComputerName       = $server.ComputerName
                InstanceName       = $server.ServiceName
                SqlInstance        = $server.DomainInstanceName
                Database           = $db
                DBN                = $Entities_Before['DBN']
                DatabaseRenames    = ($Entities_Before['DBN'].GetEnumerator() | ForEach-Object { "$($_.Name) --> $($_.Value)" }) -Join "`n"
                FGN                = $Entities_Before['FGN']
                FileGroupsRenames  = ($Entities_Before['FGN'].GetEnumerator() | ForEach-Object { "$($_.Name) --> $($_.Value)" }) -Join "`n"
                LGN                = $Entities_Before['LGN']
                LogicalNameRenames = ($Entities_Before['LGN'].GetEnumerator() | ForEach-Object { "$($_.Name) --> $($_.Value)" }) -Join "`n"
                FNN                = $Entities_Before['FNN']
                FileNameRenames    = ($Entities_Before['FNN'].GetEnumerator() | ForEach-Object { "$($_.Name) --> $($_.Value)" }) -Join "`n"
                PendingRenames     = $Final_Renames
                Status             = $Status
            } | Select-DefaultView -ExcludeProperty DatabaseRenames, FileGroupsRenames, LogicalNameRenames, FileNameRenames
        }
        #endregion db loop
    }
}