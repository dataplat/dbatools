#ValidationTags#FlowControl#
function New-DbaDatabaseSnapshot {
    <#
.SYNOPSIS
Creates database snapshots

.DESCRIPTION
Creates database snapshots without hassles

.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER AllDatabases
Creates snapshot for all eligible databases

.PARAMETER Database
The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto-populated from the server

.PARAMETER WhatIf
Shows what would happen if the command were to run

.PARAMETER Confirm
Prompts for confirmation of every step.

.PARAMETER Name
The specific snapshot name you want to create. Works only if you target a single database. If you need to create multiple snapshot,
you must use the NameSuffix parameter

.PARAMETER NameSuffix
When you pass a simple string, it'll be appended to use it to build the name of the snapshot. By default snapshots are created with yyyyMMdd_HHmmss suffix
You can also pass a standard placeholder, in which case it'll be interpolated (e.g. '{0}' gets replaced with the database name)

.PARAMETER Path
Snapshot files will be created here (by default the filestructure will be created in the same folder as the base db)

.PARAMETER Force
Databases with Filestream FG can be snapshotted, but the Filestream FG is marked offline
in the snapshot. To create a "partial" snapshot, you need to pass -Force explicitely

NB: You can't then restore the Database from the newly-created snapshot.
For details, check https://msdn.microsoft.com/en-us/library/bb895334.aspx

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Tags: DisasterRecovery, Snapshot, Restore, Databases
Author: niphlod

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
 https://dbatools.io/New-DbaDatabaseSnapshot

.EXAMPLE
New-DbaDatabaseSnapshot -SqlInstance sqlserver2014a -Database HR, Accounting

Creates snapshot for HR and Accounting, returning a custom object displaying Server, Database, DatabaseCreated, SnapshotOf, SizeMB, DatabaseCreated, PrimaryFilePath, Status, Notes

.EXAMPLE
New-DbaDatabaseSnapshot -SqlInstance sqlserver2014a -Database HR -Name HR_snap

Creates snapshot named "HR_snap" for HR

.EXAMPLE
New-DbaDatabaseSnapshot -SqlInstance sqlserver2014a -Database HR -NameSuffix 'fool_{0}_snap'

Creates snapshot named "fool_HR_snap" for HR

.EXAMPLE
New-DbaDatabaseSnapshot -SqlInstance sqlserver2014a -Database HR, Accounting -Path F:\snapshotpath

Creates snapshots for HR and Accounting databases, storing files under the F:\snapshotpath\ dir

#>

    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]
        $SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllDatabases,
        [string]$Name,
        [string]$NameSuffix,
        [string]$Path,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )

    begin {

        $NoSupportForSnap = @('model', 'master', 'tempdb')
        # Evaluate the default suffix here for naming consistency
        $DefaultSuffix = (Get-Date -Format "yyyyMMdd_HHmmss")
        if ($NameSuffix.Length -gt 0) {
            #Validate if Name can be interpolated
            try {
                $null = $NameSuffix -f 'some_string'
            }
            catch {
                Stop-Function -Message "NameSuffix parameter must be a template only containing one parameter {0}" -ErrorRecord $_
            }
        }

        function Resolve-SnapshotError($server) {
            $errhelp = ''
            $CurrentEdition = $server.Edition.toLower()
            $CurrentVersion = $server.Version.Major * 1000000 + $server.Version.Minor * 10000 + $server.Version.Build
            if ($server.Version.Major -lt 9) {
                $errhelp = 'Not supported before 2005'
            }
            if ($CurrentVersion -lt 12002000 -and $errhelp.Length -eq 0) {
                if ($CurrentEdition -notmatch '.*enterprise.*|.*developer.*|.*datacenter.*') {
                    $errhelp = 'Supported only for Enterprise, Developer or Datacenter editions'
                }
            }
            $message = ""
            if ($errhelp.Length -gt 0) {
                $message += "Please make sure your version supports snapshots : ($errhelp)"
            }
            else {
                $message += "This module can't tell you why the snapshot creation failed. Feel free to report back to dbatools what happened"
            }
            Write-Message -Level Warning -Message $message
        }
    }
    process {
        if (!$Database -and $AllDatabases -eq $false) {
            Stop-Function -Message "You must specify a -AllDatabases or -Database to continue" -EnableException $EnableException
            return
        }

        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            #Checks for path existence
            if ($Path.Length -gt 0) {
                if (!(Test-DbaSqlPath -SqlInstance $instance -Path $Path)) {
                    Stop-Function -Message "$instance cannot access the directory $Path" -ErrorRecord $_ -Target $instance -Continue -EnableException $EnableException
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

            $sourcedbs = @()

            ## double check for gotchas
            foreach ($db in $dbs) {
                if ($db.IsDatabaseSnapshot) {
                    Write-Message -Level Warning -Message "$($db.name) is a snapshot, skipping"
                }
                elseif ($db.name -in $NoSupportForSnap) {
                    Write-Message -Level Warning -Message "$($db.name) snapshots are prohibited"
                }
                elseif ($db.IsAccessible -ne $true) {
                    Write-Message -Level Verbose -Message "$($db.name) is not accessible, skipping"
                }
                else {
                    $sourcedbs += $db
                }
            }
            if ($sourcedbs.Length -gt 1 -and $Name) {
                Stop-Function -Message "You passed the Name parameter that is fixed but selected multiple databases to snapshot: use the NameSuffix parameter" -Continue -EnableException $EnableException
            }
            foreach ($db in $sourcedbs) {
                if ($NameSuffix.Length -gt 0) {
                    $SnapName = $NameSuffix -f $db.Name
                    if ($SnapName -eq $NameSuffix) {
                        #no interpolation, just append
                        $SnapName = '{0}{1}' -f $db.Name, $NameSuffix
                    }
                }
                elseif ($Name.Length -gt 0) {
                    $SnapName = $Name
                }
                else {
                    $SnapName = "{0}_{1}" -f $db.Name, $DefaultSuffix
                }
                if ($SnapName -in $server.Databases.Name) {
                    Write-Message -Level Warning -Message "A database named $Snapname already exists, skipping"
                    continue
                }
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
                $snaptype = "db snapshot"
                if ($has_FSD) {
                    $snaptype = "partial db snapshot"
                }
                If ($Pscmdlet.ShouldProcess($instance, "Create $snaptype $SnapName of $($db.Name)")) {
                    $CustomFileStructure = @{ }
                    $counter = 0
                    foreach ($fg in $db.FileGroups) {
                        $CustomFileStructure[$fg.Name] = @()
                        if ($fg.FileGroupType -eq 'FileStreamDataFileGroup') {
                            Continue
                        }
                        foreach ($file in $fg.Files) {
                            $counter += 1
                            $basename = [IO.Path]::GetFileNameWithoutExtension($file.FileName)
                            $basepath = Split-Path $file.FileName -Parent
                            # change path if specified
                            if ($Path.Length -gt 0) {
                                $basepath = $Path
                            }
                            # we need to avoid cases where basename is the same for multiple FG
                            $fname = [IO.Path]::Combine($basepath, ("{0}_{1}_{2:0000}_{3:000}" -f $basename, $DefaultSuffix, (Get-Date).MilliSecond, $counter))
                            # fixed extension is hardcoded as "ss", which seems a "de-facto" standard
                            $fname = [IO.Path]::ChangeExtension($fname, "ss")
                            $CustomFileStructure[$fg.Name] += @{ 'name' = $file.name; 'filename' = $fname }
                        }
                    }
                    $SnapDB = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $Snapname
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

                        [PSCustomObject]@{
                            ComputerName    = $server.NetName
                            InstanceName    = $server.ServiceName
                            SqlInstance     = $server.DomainInstanceName
                            Database        = $SnapDB.Name
                            SnapshotOf      = $SnapDB.DatabaseSnapshotBaseName
                            SizeMB          = [Math]::Round($SnapDB.Size, 2) ##FIXME, should use the stats for sparse files
                            DatabaseCreated = [dbadatetime]$SnapDB.createDate
                            PrimaryFilePath = $SnapDB.PrimaryFilePath
                            Status          = 'Created'
                            Notes           = $null
                            SnapshotDb      = $SnapDB
                        } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Database, SnapshotOf, SizeMB, DatabaseCreated, PrimaryFilePath, Status
                    }
                    catch {
                        $Status = 'Created'
                        # here we manage issues we DO know about, hoping that the first command
                        # is always the one creating the snapshot, and give an helpful hint
                        try {
                            $server.Databases.Refresh()
                            if ($SnapName -notin $server.Databases.Name) {
                                # previous creation failed completely, snapshot is not there already
                                $null = $server.Query($sql[0])
                                $server.Databases.Refresh()
                                $SnapDB = $server.Databases[$Snapname]
                            }
                            else {
                                $SnapDB = $server.Databases[$Snapname]
                            }
                            $Notes = @()
                            if ($db.ReadOnly -eq $true) {
                                $Notes += 'SMO is probably trying to set a property on a read-only snapshot, run with -Debug to find out and report back'
                            }
                            if ($has_FSD) {
                                $Status = 'Partial'
                                $Notes += 'Filestream groups are not viable for snapshot'
                            }
                            $Notes = $Notes -Join ';'

                            $hints = @("Executing these commands led to a partial failure")
                            foreach ($stmt in $sql) {
                                $hints += $stmt
                            }
                            Write-Message -Level Debug -Message ($hints -Join "`n")

                            [PSCustomObject]@{
                                ComputerName    = $server.NetName
                                InstanceName    = $server.ServiceName
                                SqlInstance     = $server.DomainInstanceName
                                Database        = $SnapDB.Name
                                SnapshotOf      = $SnapDB.DatabaseSnapshotBaseName
                                SizeMB          = [Math]::Round($SnapDB.Size, 2) ##FIXME, should use the stats for sparse files
                                DatabaseCreated = [dbadatetime]$SnapDB.createDate
                                PrimaryFilePath = $SnapDB.PrimaryFilePath
                                Status          = $Status
                                Notes           = $Notes
                                SnapshotDb      = $SnapDB
                            } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Database, SnapshotOf, SizeMB, DatabaseCreated, PrimaryFilePath, Status, Notes
                        }
                        catch {
                            # we end up here when even the first issued command didn't create
                            # a valid snapshot
                            Write-Message -Level Warning -Message 'SMO failed to create the snapshot, run with -Debug to find out and report back' -ErrorRecord $_
                            $hints = @("Executing these commands led to a failure")
                            foreach ($stmt in $sql) {
                                $hints += $stmt
                            }
                            Write-Message -Level Debug -Message ($hints -Join "`n")
                            Resolve-SnapshotError $server
                        }
                    }
                }
            }
        }
    }
}

