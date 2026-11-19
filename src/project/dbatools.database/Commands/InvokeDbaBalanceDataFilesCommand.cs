#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Balances data across a database's data files by rebuilding clustered indexes. Port of
/// public/Invoke-DbaBalanceDataFiles.ps1; the workflow remains a module-scoped PowerShell compatibility hop. This
/// is a MUTATING command (rebuilds indexes) with real SupportsShouldProcess and PARAMETER SETS.
///
/// A process-only port. PARAMETER SETS: SqlInstance is in the "Pipe" set (Mandatory, NOT ValueFromPipeline); all
/// other parameters (including the inherited EnableException) are in __AllParameterSets, matching the source, so NO
/// per-set EnableException override is needed. DefaultParameterSetName is "Default". There is NO ValueFromPipeline
/// parameter, so process fires once, and the source begin block (if ($Force) { $ConfirmPreference = 'none' }) is
/// PREPENDED (verbatim) into the process hop. The single $PSCmdlet.ShouldProcess("Rebuilding indexes to balance
/// data") becomes $__realCmdlet.ShouldProcess(...) with the compiled cmdlet (this) passed as $__realCmdlet, so
/// -WhatIf/-Confirm are honored by the real cmdlet. All Stop-Function -Continue and the three continue statements are
/// inside foreach loops (instance/db/table/drive) - loop-bound, so NO continue-guard is needed. There is NO
/// Test-FunctionInterrupt, so no interrupt carry (the no-Continue Stop-Function guards set the interrupt but nothing
/// reads it; their bare return exits the process cleanly). RebuildOffline and Force are switches consumed as VALUES
/// (if ($RebuildOffline)/if ($Force)), so they are marshaled bools in UNTYPED inner params (binding-probed).
/// NOTE (deferred to the live gate, per the probes-outrank-readings rule): the -Force -> $ConfirmPreference='none'
/// interaction (the hop scriptblock's $ConfirmPreference may not propagate to $__realCmdlet.ShouldProcess) and the
/// interactive $host.ui.PromptForChoice offline-rebuild prompt are runtime Confirm/prompt behaviors that the gate
/// must probe. Edits: -FunctionName Invoke-DbaBalanceDataFiles on the Stop-Function/Write-Message, 1 ShouldProcess sub.
/// Surface pinned by migration/baselines/Invoke-DbaBalanceDataFiles.json (SqlInstance Pipe/Mandatory, rest __AllParameterSets, SupportsShouldProcess ConfirmImpact Medium).
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaBalanceDataFiles", DefaultParameterSetName = "Default", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class InvokeDbaBalanceDataFilesCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ParameterSetName = "Pipe", Mandatory = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to balance.</summary>
    [Parameter]
    public object[]? Database { get; set; }

    /// <summary>The table(s) to balance.</summary>
    [Parameter]
    [Alias("Tables")]
    public object[]? Table { get; set; }

    /// <summary>Move all eligible tables' clustered indexes to this filegroup.</summary>
    [Parameter]
    public string? TargetFileGroup { get; set; }

    /// <summary>Rebuild indexes offline (required on non-Enterprise/Developer editions).</summary>
    [Parameter]
    public SwitchParameter RebuildOffline { get; set; }

    /// <summary>Skip the disk-space check and confirmation.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet (__AllParameterSets, matching the source) - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, Table, TargetFileGroup, RebuildOffline.ToBool(),
            EnableException.ToBool(), Force.ToBool(), this, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }
    // PS: the source begin block (if ($Force) { $ConfirmPreference = 'none' }) PREPENDED to the process block.
    // Edits: -FunctionName Invoke-DbaBalanceDataFiles on the Stop-Function/Write-Message; $PSCmdlet.ShouldProcess ->
    // $__realCmdlet.ShouldProcess. RebuildOffline/Force arrive as marshaled bools (untyped inner params).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Table, $TargetFileGroup, $RebuildOffline, $EnableException, $Force, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$Table, [string]$TargetFileGroup, $RebuildOffline, $EnableException, $Force, $__realCmdlet, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if ($Force) { $ConfirmPreference = 'none' }


        Write-Message -Message "Starting balancing out data files" -Level Verbose -FunctionName Invoke-DbaBalanceDataFiles -ModuleName "dbatools"

        # Set the initial success flag
        [bool]$success = $true

        foreach ($instance in $SqlInstance) {
            # Try connecting to the instance
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -FunctionName Invoke-DbaBalanceDataFiles -Continue
            }

            # Check the database parameter
            if ($Database) {
                if ($Database -notin $server.Databases.Name) {
                    Stop-Function -Message "One or more databases cannot be found on instance on instance $instance" -Target $instance -FunctionName Invoke-DbaBalanceDataFiles -Continue
                }

                $DatabaseCollection = $server.Databases | Where-Object { $_.Name -in $Database }
            } else {
                Stop-Function -Message "Please supply a database to balance out" -Target $instance -FunctionName Invoke-DbaBalanceDataFiles -Continue
            }

            # Get the server version
            $serverVersion = $server.Version.Major

            # Check edition of the sql instance
            if ($RebuildOffline) {
                Write-Message -Message "Continuing with offline rebuild." -Level Verbose -FunctionName Invoke-DbaBalanceDataFiles -ModuleName "dbatools"
            } elseif (-not $RebuildOffline -and ($serverVersion -lt 9 -or (([string]$Server.Edition -notmatch "Developer") -and ($Server.Edition -notmatch "Enterprise")))) {
                # Set up the confirm part
                $message = "The server does not support online rebuilds of indexes. `nDo you want to rebuild the indexes offline?"
                $choiceYes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Answer Yes."
                $choiceNo = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Answer No."
                $options = [System.Management.Automation.Host.ChoiceDescription[]]($choiceYes, $choiceNo)
                $result = $host.ui.PromptForChoice($title, $message, $options, 0)

                # Check the result from the confirm
                switch ($result) {
                    # If yes
                    0 {
                        # Set the option to generate a full backup
                        Write-Message -Message "Continuing with offline rebuild." -Level Verbose -FunctionName Invoke-DbaBalanceDataFiles -ModuleName "dbatools"

                        [bool]$supportOnlineRebuild = $false
                    }
                    1 {
                        Stop-Function -Message "You chose to not allow offline rebuilds of indexes. Use -RebuildOffline" -Target $instance -FunctionName Invoke-DbaBalanceDataFiles
                        return
                    }
                } # switch
            } elseif ($serverVersion -ge 9 -and (([string]$Server.Edition -like "Developer*") -or ($Server.Edition -like "Enterprise*"))) {
                [bool]$supportOnlineRebuild = $true
            }

            # Loop through each of the databases
            foreach ($db in $DatabaseCollection) {
                $dataFilesStarting = Get-DbaDbFile -SqlInstance $server -Database $db.Name | Where-Object { $_.TypeDescription -eq 'ROWS' } | Select-Object ID, LogicalName, PhysicalName, Size, UsedSpace, AvailableSpace | Sort-Object ID

                if (-not $Force -and $server.HostPlatform -eq "Windows") {
                    # Check the amount of disk space available
                    $query = "SELECT SUBSTRING(physical_name, 0, 4) AS 'Drive' ,
                                        SUM(( CAST( size AS BIGINT ) * 8 ) / 1024) AS 'SizeMB'
                                FROM    sys.master_files
                                WHERE    DB_NAME(database_id) = '$($db.Name)'
                                GROUP BY SUBSTRING(physical_name, 0, 4)"
                    # Execute the query
                    try {
                        $dbDiskUsage = $Server.Query($query)
                    } catch {
                        $errormsg = Get-ErrorMessage -Record $PSItem
                        Stop-Function -Message "$errormsg" -ErrorRecord $_ -Target $instance -FunctionName Invoke-DbaBalanceDataFiles -Continue
                    }

                    # Get the free space for each drive
                    try {
                        $result = $Server.Query("xp_fixeddrives")
                    } catch {
                        Stop-Function -Message "Error occurred while finding free space on drives" -ErrorRecord $_ -Target $instance -FunctionName Invoke-DbaBalanceDataFiles -Continue
                    }
                    $MbFreeColName = $result[0].psobject.Properties.Name[1]
                    $diskFreeSpace = $result | Select-Object Drive, @{ Name = 'FreeMB'; Expression = { $_.$MbFreeColName } }

                    # Loop through each of the drives to see if the size of files on that
                    # particular disk do not exceed the free space of that disk
                    foreach ($d in $dbDiskUsage) {
                        $freeSpace = $diskFreeSpace | Where-Object { $_.Drive -eq $d.Drive.Trim(':\') } | Select-Object FreeMB
                        if ($d.SizeMB -gt $freeSpace.FreeMB) {
                            # Set the success flag
                            $success = $false

                            Stop-Function -Message "The available space may not be sufficient to continue the process. Please use -Force to try anyway." -Target $instance -FunctionName Invoke-DbaBalanceDataFiles -Continue
                            return
                        }
                    }
                }

                # Create the start time
                $start = Get-Date

                # Check if the function needs to continue
                if ($success) {

                    # Get the database files before all the alterations
                    Write-Message -Message "Retrieving data files before data move" -Level Verbose -FunctionName Invoke-DbaBalanceDataFiles -ModuleName "dbatools"
                    Write-Message -Message "Processing database $db" -Level Verbose -FunctionName Invoke-DbaBalanceDataFiles -ModuleName "dbatools"

                    # Check the datafiles of the database
                    $dataFiles = Get-DbaDbFile -SqlInstance $server -Database $db | Where-Object { $_.TypeDescription -eq 'ROWS' }
                    if ($dataFiles.Count -eq 1) {
                        # Set the success flag
                        $success = $false

                        Stop-Function -Message "Database $db only has one data file. Please add a data file to balance out the data" -Target $instance -FunctionName Invoke-DbaBalanceDataFiles -Continue
                    }

                    # Check the tables parameter
                    if ($Table) {
                        $tableParts = $Table | ForEach-Object { Get-ObjectNameParts -ObjectName $_ }
                        $missingTables = foreach ($tablePart in $tableParts) {
                            $matchingTable = $db.Tables | Where-Object {
                                $_.Name -eq $tablePart.Name -and
                                $tablePart.Schema -in ($_.Schema, $null) -and
                                $tablePart.Database -in ($_.Parent.Name, $null)
                            }
                            if (-not $matchingTable) {
                                $tablePart.InputValue
                            }
                        }

                        if ($missingTables) {
                            # Set the success flag
                            $success = $false

                            Stop-Function -Message "One or more tables cannot be found in database $db on instance $instance" -Target $instance -FunctionName Invoke-DbaBalanceDataFiles -Continue
                        }

                        $tableCollection = foreach ($tablePart in $tableParts) {
                            $db.Tables | Where-Object {
                                $_.Name -eq $tablePart.Name -and
                                $tablePart.Schema -in ($_.Schema, $null) -and
                                $tablePart.Database -in ($_.Parent.Name, $null)
                            }
                        }
                    } else {
                        $tableCollection = $db.Tables
                    }

                    # Get the database file groups and check the aount of data files
                    Write-Message -Message "Retrieving file groups" -Level Verbose -FunctionName Invoke-DbaBalanceDataFiles -ModuleName "dbatools"
                    $fileGroups = $Server.Databases[$db.Name].FileGroups

                    # ARray to hold the file groups with properties
                    $balanceableTables = @()

                    if ($TargetFileGroup) {
                        # Validate the target filegroup exists and is writable
                        $targetFG = $fileGroups[$TargetFileGroup]
                        if (-not $targetFG) {
                            Stop-Function -Message "FileGroup '$TargetFileGroup' does not exist in database $db on instance $instance" -Target $instance -FunctionName Invoke-DbaBalanceDataFiles -Continue
                            continue
                        }
                        if ($targetFG.Readonly) {
                            Stop-Function -Message "FileGroup '$TargetFileGroup' is read-only in database $db on instance $instance" -Target $instance -FunctionName Invoke-DbaBalanceDataFiles -Continue
                            continue
                        }
                        if ($targetFG.Files.Count -lt 1) {
                            Stop-Function -Message "FileGroup '$TargetFileGroup' does not contain any data files in database $db on instance $instance" -Target $instance -FunctionName Invoke-DbaBalanceDataFiles -Continue
                            continue
                        }

                        # When a target filegroup is specified, all tables are eligible
                        Write-Message -Message "Target filegroup '$TargetFileGroup' specified - all tables with clustered indexes are eligible" -Level Verbose -FunctionName Invoke-DbaBalanceDataFiles -ModuleName "dbatools"
                        $balanceableTables = $db.Tables
                    } else {
                        # Loop through each of the file groups

                        foreach ($fg in $fileGroups) {

                            # If there is less than 2 files balancing out data is not possible
                            if (($fg.Files.Count -ge 2) -and ($fg.Readonly -eq $false)) {
                                $balanceableTables += $fg.EnumObjects() | Where-Object { $_.GetType().Name -eq 'Table' }
                            }
                        }
                    }

                    $unsuccessfulTables = @()

                    # Loop through each of the tables
                    foreach ($tbl in $tableCollection) {

                        # Chck if the table balanceable
                        if ($tbl.Name -in $balanceableTables.Name) {

                            Write-Message -Message "Processing table $tbl" -Level Verbose -FunctionName Invoke-DbaBalanceDataFiles -ModuleName "dbatools"

                            # Chck the tables and get the clustered indexes
                            if (@($tbl.Indexes).Count -lt 1) {
                                # Set the success flag
                                $success = $false

                                Stop-Function -Message "Table $tbl does not contain any indexes" -Target $instance -FunctionName Invoke-DbaBalanceDataFiles -Continue
                            } else {

                                # Get all the clustered indexes for the table
                                $clusteredIndexes = @($tbl.Indexes | Where-Object { $_.IndexType -eq 'ClusteredIndex' })

                                if ($clusteredIndexes.Count -lt 1) {
                                    # Set the success flag
                                    $success = $false

                                    Stop-Function -Message "No clustered indexes found in table $tbl" -Target $instance -FunctionName Invoke-DbaBalanceDataFiles -Continue
                                }
                            }

                            # Loop through each of the clustered indexes and rebuild them
                            Write-Message -Message "$($clusteredIndexes.Count) clustered index(es) found for table $tbl" -Level Verbose -FunctionName Invoke-DbaBalanceDataFiles -ModuleName "dbatools"
                            if ($__realCmdlet.ShouldProcess("Rebuilding indexes to balance data")) {
                                foreach ($ci in $clusteredIndexes) {

                                    Write-Message -Message "Rebuilding index $($ci.Name)" -Level Verbose -FunctionName Invoke-DbaBalanceDataFiles -ModuleName "dbatools"

                                    # Get the original index operation
                                    [bool]$originalIndexOperation = $ci.OnlineIndexOperation

                                    # Save the original filegroup in case of error
                                    $originalFileGroup = $ci.FileGroup

                                    # Set the rebuild option to be either offline or online
                                    if ($RebuildOffline) {
                                        $ci.OnlineIndexOperation = $false
                                    } elseif ($serverVersion -ge 9 -and $supportOnlineRebuild -and -not $RebuildOffline) {
                                        Write-Message -Message "Setting the index operation for index $($ci.Name) to online" -Level Verbose -FunctionName Invoke-DbaBalanceDataFiles -ModuleName "dbatools"
                                        $ci.OnlineIndexOperation = $true
                                    }

                                    # Set the target filegroup if specified
                                    if ($TargetFileGroup) {
                                        Write-Message -Message "Setting filegroup for index $($ci.Name) to $TargetFileGroup" -Level Verbose -FunctionName Invoke-DbaBalanceDataFiles -ModuleName "dbatools"
                                        $ci.FileGroup = $TargetFileGroup
                                    }

                                    # Rebuild the index
                                    try {
                                        Write-Message -Message "Rebuilding index $($ci.Name)" -Level Verbose -FunctionName Invoke-DbaBalanceDataFiles -ModuleName "dbatools"
                                        $ci.Rebuild()

                                        # Set the success flag
                                        $success = $true
                                    } catch {
                                        # Set the original index operation back for the index
                                        $ci.OnlineIndexOperation = $originalIndexOperation

                                        # Restore the original filegroup if we changed it
                                        if ($TargetFileGroup) {
                                            $ci.FileGroup = $originalFileGroup
                                        }

                                        # Set the success flag
                                        $success = $false

                                        Stop-Function -Message "Something went wrong rebuilding index $($ci.Name). `n$($_.Exception.Message)" -ErrorRecord $_ -Target $instance -FunctionName Invoke-DbaBalanceDataFiles -Continue
                                    }

                                    # Set the original index operation back for the index
                                    Write-Message -Message "Setting the index operation for index $($ci.Name) back to the original value" -Level Verbose -FunctionName Invoke-DbaBalanceDataFiles -ModuleName "dbatools"
                                    $ci.OnlineIndexOperation = $originalIndexOperation

                                } # foreach index

                            } # if process

                        } # if table is balanceable
                        else {
                            # Add the table to the unsuccessful array
                            $unsuccessfulTables += $tbl.Name

                            # Set the success flag
                            $success = $false

                            Write-Message -Message "Table $tbl cannot be balanced out" -Level Verbose -FunctionName Invoke-DbaBalanceDataFiles -ModuleName "dbatools"
                        }

                    } #foreach table
                }

                # Create the end time
                $end = Get-Date

                # Create the time span
                $timespan = New-TimeSpan -Start $start -End $end
                $ts = [timespan]::fromseconds($timespan.TotalSeconds)
                $elapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)

                # Get the database files after all the alterations
                Write-Message -Message "Retrieving data files after data move" -Level Verbose -FunctionName Invoke-DbaBalanceDataFiles -ModuleName "dbatools"
                $dataFilesEnding = Get-DbaDbFile -SqlInstance $server -Database $db.Name | Where-Object { $_.TypeDescription -eq 'ROWS' } | Select-Object ID, LogicalName, PhysicalName, Size, UsedSpace, AvailableSpace | Sort-Object ID

                [PSCustomObject]@{
                    ComputerName   = $server.ComputerName
                    InstanceName   = $server.ServiceName
                    SqlInstance    = $server.DomainInstanceName
                    Database       = $db.Name
                    Start          = $start
                    End            = $end
                    Elapsed        = $elapsed
                    Success        = $success
                    Unsuccessful   = $unsuccessfulTables -join ","
                    DataFilesStart = $dataFilesStarting
                    DataFilesEnd   = $dataFilesEnding
                }

            } # foreach database

        } # end process
} $SqlInstance $SqlCredential $Database $Table $TargetFileGroup $RebuildOffline $EnableException $Force $__realCmdlet $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
