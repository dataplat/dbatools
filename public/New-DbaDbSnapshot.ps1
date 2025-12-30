function New-DbaDbSnapshot {
    <#
    .SYNOPSIS
        Creates database snapshots for point-in-time recovery and testing scenarios

    .DESCRIPTION
        Creates read-only database snapshots that capture the state of a database at a specific moment in time. Snapshots provide a fast way to revert databases to a previous state without restoring from backup files, making them ideal for pre-maintenance snapshots, testing scenarios, or quick rollback points.

        The function automatically generates snapshot file names with timestamps and handles the underlying file structure creation. Snapshots share pages with the source database until changes occur, making them storage-efficient for short-term use. Note that snapshots are not a replacement for regular backups and should be dropped when no longer needed to avoid performance impacts.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AllDatabases
        Creates snapshots for all user databases on the instance that support snapshotting.
        Automatically excludes system databases (master, model, tempdb), snapshots, and databases with memory-optimized filegroups.
        Use this when you need to create snapshots for disaster recovery or before major maintenance operations.

    .PARAMETER Database
        Specifies which databases to create snapshots for. Accepts an array of database names.
        Use this when you need snapshots for specific databases rather than all databases on the instance.
        Cannot be used together with AllDatabases parameter.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from snapshot creation when using AllDatabases.
        Useful when you want to snapshot most databases but skip certain ones like development or staging databases.
        Accepts an array of database names to exclude from the operation.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step.

    .PARAMETER Name
        Sets a custom name for the database snapshot. Only works when targeting a single database.
        Use this when you need a meaningful snapshot name like 'Sales_PreUpgrade' instead of the default timestamped name.
        For multiple databases, use NameSuffix parameter instead to avoid naming conflicts.

    .PARAMETER NameSuffix
        Customizes the suffix appended to database names when creating snapshots. Defaults to yyyyMMdd_HHmmss format.
        Use simple strings like '_PrePatch' or templates with {0} placeholder where {0} represents the database name.
        Examples: '_BeforeMaintenance' creates 'HR_BeforeMaintenance', or 'Snap_{0}_v1' creates 'Snap_HR_v1'.

    .PARAMETER Path
        Specifies the directory where snapshot files will be stored. Defaults to the same location as the source database files.
        Use this when you need snapshots on different storage for performance or capacity reasons.
        The SQL Server service account must have write access to the specified path.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase for pipeline operations.
        Enables scenarios like filtering databases with specific criteria before creating snapshots.
        Example: Get-DbaDatabase -SqlInstance sql01 | Where-Object Size -gt 1000 | New-DbaDbSnapshot

    .PARAMETER Force
        Creates partial snapshots for databases containing FILESTREAM filegroups. FILESTREAM data is excluded and marked offline in the snapshot.
        Use this when you need to snapshot databases with FILESTREAM for testing or point-in-time analysis of non-FILESTREAM data.
        Warning: Databases cannot be restored from partial snapshots due to the missing FILESTREAM data.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Snapshot, Restore, Database
        Author: Simone Bizzotto (@niphold)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDbSnapshot

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Database

        Returns one Database object for each snapshot successfully created. The returned object represents the newly created database snapshot with its configuration and usage properties.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the database snapshot
        - SnapshotOf: The name of the base database from which this snapshot was created (alias for DatabaseSnapshotBaseName)
        - CreateDate: DateTime when the snapshot was created
        - DiskUsage: The amount of disk space consumed by the snapshot (formatted as dbasize object: KB, MB, GB, TB, etc.)

        Additional properties available (from SMO Database object):
        - DatabaseSnapshotBaseName: The name of the source database
        - IsDatabaseSnapshot: Boolean indicating if the database is a snapshot (always $true for snapshots)
        - SnapshotIsolationState: Snapshot isolation setting
        - DatabaseGuid: Unique identifier for the database
        - Owner: Database owner login name
        - Compatibility: Database compatibility level
        - IsAccessible: Boolean indicating if the snapshot is accessible
        - Status: Current status of the snapshot database
        - Collation: The database collation

        All properties from the base SMO Database object are accessible via Select-Object * even though only default properties are displayed without using the -Property parameter.

    .EXAMPLE
        PS C:\> New-DbaDbSnapshot -SqlInstance sqlserver2014a -Database HR, Accounting

        Creates snapshot for HR and Accounting, returning a custom object displaying Server, Database, DatabaseCreated, SnapshotOf, SizeMB, DatabaseCreated, PrimaryFilePath, Status, Notes

    .EXAMPLE
        PS C:\> New-DbaDbSnapshot -SqlInstance sqlserver2014a -Database HR -Name HR_snap

        Creates snapshot named "HR_snap" for HR

    .EXAMPLE
        PS C:\> New-DbaDbSnapshot -SqlInstance sqlserver2014a -Database HR -NameSuffix 'fool_{0}_snap'

        Creates snapshot named "fool_HR_snap" for HR

    .EXAMPLE
        PS C:\> New-DbaDbSnapshot -SqlInstance sqlserver2014a -Database HR, Accounting -Path F:\snapshotpath

        Creates snapshots for HR and Accounting databases, storing files under the F:\snapshotpath\ dir

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 -Database df | New-DbaDbSnapshot

        Creates a snapshot for the database df on sql2016

    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllDatabases,
        [string]$Name,
        [string]$NameSuffix,
        [string]$Path,
        [switch]$Force,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $NoSupportForSnap = @('model', 'master', 'tempdb')
        # Evaluate the default suffix here for naming consistency
        $DefaultSuffix = (Get-Date -Format "yyyyMMdd_HHmmss")
        if ($NameSuffix.Length -gt 0) {
            #Validate if Name can be interpolated
            try {
                $null = $NameSuffix -f 'some_string'
            } catch {
                Stop-Function -Message "NameSuffix parameter must be a template only containing one parameter {0}" -ErrorRecord $_
            }
        }

        function Resolve-SnapshotError($server) {
            $errHelp = ''
            $CurrentEdition = $server.Edition.ToLowerInvariant()
            $CurrentVersion = $server.Version.Major * 1000000 + $server.Version.Minor * 10000 + $server.Version.Build
            if ($server.Version.Major -lt 9) {
                $errHelp = 'Not supported before 2005'
            }
            if ($CurrentVersion -lt 12002000 -and $errHelp.Length -eq 0) {
                if ($CurrentEdition -notmatch '.*enterprise.*|.*developer.*|.*datacenter.*') {
                    $errHelp = 'Supported only for Enterprise, Developer or Datacenter editions'
                }
            }
            $message = ""
            if ($errHelp.Length -gt 0) {
                $message += "Please make sure your version supports snapshots : ($errHelp)"
            } else {
                $message += "This module can't tell you why the snapshot creation failed. Feel free to report back to dbatools what happened"
            }
            Write-Message -Level Warning -Message $message
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject -and -not $Database -and $AllDatabases -eq $false) {
            Stop-Function -Message "You must specify a -AllDatabases or -Database to continue" -EnableException $EnableException
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            #Checks for path existence, left the length test because test-bound wasn't working for some reason
            if ($Path.Length -gt 0) {
                if (!(Test-DbaPath -SqlInstance $server -Path $Path)) {
                    Stop-Function -Message "$instance cannot access the directory $Path" -Target $instance -Continue -EnableException $EnableException
                }
            }

            if ($AllDatabases) {
                $dbs = $server.Databases
            }

            if ($Database) {
                $dbs = $server.Databases | Where-Object { $Database -contains $_.Name }
            }

            if ($ExcludeDatabase) {
                $dbs = $server.Databases | Where-Object { $ExcludeDatabase -notcontains $_.Name }
            }

            ## double check for gotchas
            foreach ($db in $dbs) {
                if ($db.IsMirroringEnabled) {
                    $InputObject += $db
                } elseif ($db.IsDatabaseSnapshot) {
                    Write-Message -Level Warning -Message "$($db.name) is a snapshot, skipping"
                } elseif ($db.name -in $NoSupportForSnap) {
                    Write-Message -Level Warning -Message "$($db.name) snapshots are prohibited"
                } elseif ($db.IsAccessible -ne $true -and ($server.AvailabilityGroups | Where-Object Name -eq $db.AvailabilityGroupName).LocalReplicaRole -eq 'Secondary') {
                    # Readable secondaries are considered accessible.
                    # This accounts for every other valid state of an AG (e.g. a database in a Basic Availability Group is a valid target).
                    $InputObject += $db
                } elseif ($db.IsAccessible -ne $true) {
                    Write-Message -Level Verbose -Message "$($db.name) is not accessible, skipping"
                } else {
                    $InputObject += $db
                }
            }

            if ($InputObject.Count -gt 1 -and $Name) {
                Stop-Function -Message "You passed the Name parameter that is fixed but selected multiple databases to snapshot: use the NameSuffix parameter" -Continue -EnableException $EnableException
            }
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            # In case stuff is piped in
            if ($server.VersionMajor -lt 9) {
                Stop-Function -Message "SQL Server version 9 required - $server not supported" -Continue
            }

            if ($NameSuffix.Length -gt 0) {
                $SnapName = $NameSuffix -f $db.Name
                if ($SnapName -eq $NameSuffix) {
                    #no interpolation, just append
                    $SnapName = '{0}{1}' -f $db.Name, $NameSuffix
                }
            } elseif ($Name.Length -gt 0) {
                $SnapName = $Name
            } else {
                $SnapName = "{0}_{1}" -f $db.Name, $DefaultSuffix
            }
            if ($SnapName -in $server.Databases.Name) {
                Write-Message -Level Warning -Message "A database named $SnapName already exists, skipping"
                continue
            }
            # Refresh database and FileGroups collection to ensure SMO has populated data
            # This is especially important for AG secondary replicas where collections may not be auto-populated
            $db.Refresh()
            $db.FileGroups.Refresh()
            $all_FSD = $db.FileGroups | Where-Object FileGroupType -eq 'FileStreamDataFileGroup'
            $all_MMO = $db.FileGroups | Where-Object FileGroupType -eq 'MemoryOptimizedDataFileGroup'
            $has_FSD = $all_FSD.Count -gt 0
            $has_MMO = $all_MMO.Count -gt 0
            if ($has_MMO) {
                Write-Message -Level Warning -Message "MEMORY_OPTIMIZED_DATA detected, snapshots are not possible"
                continue
            }
            if ($has_FSD -and $Force -eq $false) {
                Write-Message -Level Warning -Message "Filestream detected, skipping. You need to specify -Force. See Get-Help for details"
                continue
            }
            $snapType = "db snapshot"
            if ($has_FSD) {
                $snapType = "partial db snapshot"
            }
            If ($PSCmdlet.ShouldProcess($server, "Create $snapType $SnapName of $($db.Name)")) {
                $CustomFileStructure = @{ }
                $counter = 0
                foreach ($fg in $db.FileGroups) {
                    $CustomFileStructure[$fg.Name] = @()
                    if ($fg.FileGroupType -eq 'FileStreamDataFileGroup') {
                        Continue
                    }
                    foreach ($file in $fg.Files) {
                        $counter += 1
                        # Linux can't handle windows paths, so split it
                        $basename = [IO.Path]::GetFileNameWithoutExtension((Split-Path $file.FileName -Leaf))
                        $originalExtension = [IO.Path]::GetExtension((Split-Path $file.FileName -Leaf))
                        $basePath = Split-Path $file.FileName -Parent
                        # change path if specified
                        if ($Path.Length -gt 0) {
                            $basePath = $Path
                        }

                        # we need to avoid cases where basename is the same for multiple FG
                        $fName = [IO.Path]::Combine($basePath, ("{0}_{1}_{2:0000}_{3:000}{4}" -f $basename, $DefaultSuffix, (Get-Date).MilliSecond, $counter, $originalExtension))
                        # fixed extension is hardcoded as "ss", which seems a "de-facto" standard
                        $fName = [IO.Path]::ChangeExtension($fName, "ss")
                        Write-Message -Level Debug -Message "$fName"

                        # change slashes for Linux, change slashes for Windows
                        if ($server.HostPlatform -eq 'Linux') {
                            $fName = $fName.Replace("\", "/")
                        } else {
                            $fName = $fName.Replace("/", "\")
                        }
                        $CustomFileStructure[$fg.Name] += @{ 'name' = $file.name; 'filename' = $fName }
                    }
                }

                $SnapDB = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $SnapName
                $SnapDB.DatabaseSnapshotBaseName = $db.Name

                foreach ($fg in $CustomFileStructure.Keys) {
                    $SnapFG = New-Object -TypeName Microsoft.SqlServer.Management.Smo.FileGroup $SnapDB, $fg
                    $SnapDB.FileGroups.Add($SnapFG)
                    foreach ($file in $CustomFileStructure[$fg]) {
                        $SnapFile = New-Object -TypeName Microsoft.SqlServer.Management.Smo.DataFile $SnapFG, $file['name'], $file['filename']
                        $SnapDB.FileGroups[$fg].Files.Add($SnapFile)
                    }
                }

                # we're ready to issue a Create, but SMO is a little uncooperative here
                # there are cases we can manage and others we can't, and we need all the
                # info we can get both from testers and from users

                $sql = $SnapDB.Script()

                try {
                    $SnapDB.Create()
                    $server.Databases.Refresh()
                    Get-DbaDbSnapshot -SqlInstance $server -Snapshot $SnapName
                } catch {
                    try {
                        $server.Databases.Refresh()
                        if ($SnapName -notin $server.Databases.Name) {
                            # previous creation failed completely, snapshot is not there already
                            $null = $server.Query($sql[0])
                            $server.Databases.Refresh()
                            $SnapDB = Get-DbaDbSnapshot -SqlInstance $server -Snapshot $SnapName
                        } else {
                            $SnapDB = Get-DbaDbSnapshot -SqlInstance $server -Snapshot $SnapName
                        }

                        $Notes = @()
                        if ($db.ReadOnly -eq $true) {
                            $Notes += 'SMO is probably trying to set a property on a read-only snapshot, run with -Debug to find out and report back'
                        }
                        if ($has_FSD) {
                            #Variable marked as unused by PSScriptAnalyzer
                            #$Status = 'Partial'
                            $Notes += 'Filestream groups are not viable for snapshot'
                        }
                        $Notes = $Notes -Join ';'

                        $hints = @("Executing these commands led to a partial failure")
                        foreach ($stmt in $sql) {
                            $hints += $stmt
                        }

                        Write-Message -Level Debug -Message ($hints -Join "`n")

                        $SnapDB
                    } catch {
                        # Resolve-SnapshotError $server
                        $hints = @("Executing these commands led to a failure")
                        foreach ($stmt in $sql) {
                            $hints += $stmt
                        }
                        Write-Message -Level Debug -Message ($hints -Join "`n")

                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $SnapDB -Continue
                    }
                }
            }
        }
    }
}