#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Calculates disk space requirements for migrating a database between two instances. Port of
/// public/Measure-DbaDiskSpaceRequirement.ps1; the workflow remains a module-scoped PowerShell
/// compatibility hop. Surface pinned by migration/baselines/Measure-DbaDiskSpaceRequirement.json.
///
/// BEGIN+PROCESS lifecycle split. EVERY parameter is ValueFromPipelineByPropertyName, so process
/// fires once per piped record while begin runs exactly once, and begin's state has to survive the
/// hop scope dying between records. There is no end block.
///
/// BEGIN -> PROCESS CARRY. The source's begin declares two caches and three helpers that close over
/// them (Get-MountPoint, Get-MountPointFromPath, Get-MountPointFromDefaultPath). begin and process
/// share one function scope in the script world, which is why the helpers see the caches at all.
///   $cacheMP / $cacheDP - the mount-point and default-path caches, keyed by computer and by
///     instance. These are the POINT of the split: a per-record cache would re-query CIM and
///     Get-DbaDefaultPath for every piped row and re-emit "cacheDP[...] is now cached" each time.
///     They are built by @{ } in the begin hop rather than by a C# constructor because PowerShell's
///     hashtable literal is case-INSENSITIVE and new Hashtable() is not - the keys are computer and
///     instance names, whose case varies between the SMO ComputerName and the caller's argument.
///   The three helpers are declarations, not state, so they are declared in the process hop.
///
/// THREE MORE LOCALS RIDE THE CARRIER, AND REPRODUCING THEM IS THE POINT. In the source they leak
/// across records by accident, and a port that reset them per record would be the divergence:
///   $destFiles - assigned ONLY inside "if ($destDb = Get-DbaDatabase ...)"; the else branch does
///     not clear it, so a record whose destination database is absent walks the PREVIOUS record's
///     destination file list and reports "Source and Destination" rows against it.
///   $found     - assigned only inside the inner match loop, so when $destFiles is empty the loop
///     body never runs and "if (!$found)" reads the prior file's or prior record's value.
///   $destFile  - the inner loop variable, which the "Only on Destination" row reads at source
///     :330 instead of $destFileNotSource.
/// $destDb needs no carrier: it is assigned by the if-condition itself on every record, including
/// to $null. $computerName is assigned in both branches. $sourceServer, $destServer, $sourceDb and
/// $sourceFiles are assigned before any read on every record that gets past the connect guards.
///
/// BOUND-NESS IS STICKY, DELIBERATELY. "Test-Bound 'DestinationDatabase' -not" reads the caller's
/// $PSBoundParameters, and for a pipeline-bound parameter that bag KEEPS the key once any record
/// has supplied it - measured on both editions, for an advanced function and for a compiled cmdlet
/// alike - even though the binder resets the variable itself to "". So a second record that omits
/// DestinationDatabase does NOT fall back to $Database; it runs with an empty destination database
/// name. _boundNames accumulates the union across records so that behaviour does not depend on
/// binder internals.
///
/// NO INTERRUPT CARRY. The source's process block never reads Test-FunctionInterrupt, so a
/// Stop-Function on one record does not silence later ones and there is no latch to carry. The
/// Stop-Function at :249 is unreachable: it guards on "Test-Bound 'Database' -not" for a Mandatory
/// parameter. Both are preserved as written.
/// </summary>
[Cmdlet(VerbsDiagnostic.Measure, "DbaDiskSpaceRequirement")]
public sealed class MeasureDbaDiskSpaceRequirementCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance holding the database to analyze.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipelineByPropertyName = true)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>The database to analyze on the source instance.</summary>
    [Parameter(Mandatory = true, Position = 1, ValueFromPipelineByPropertyName = true)]
    public string Database { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 2, ValueFromPipelineByPropertyName = true)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>The destination SQL Server instance the database will be migrated to.</summary>
    [Parameter(Mandatory = true, Position = 3, ValueFromPipelineByPropertyName = true)]
    public DbaInstanceParameter Destination { get; set; } = null!;

    /// <summary>The database name to use on the destination, when it differs from the source.</summary>
    [Parameter(Position = 4, ValueFromPipelineByPropertyName = true)]
    public string? DestinationDatabase { get; set; }

    /// <summary>Alternative credential for the destination instance.</summary>
    [Parameter(Position = 5, ValueFromPipelineByPropertyName = true)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>The credential used to connect via CIM/WMI/PowerShell remoting.</summary>
    [Parameter(Position = 6, ValueFromPipelineByPropertyName = true)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // begin's two caches plus the three locals the source leaks across records.
    private Hashtable? _beginState;
    // The caller's bound set never loses a key once a record supplies it; mirror that.
    private readonly HashSet<string> _boundNames = new(StringComparer.OrdinalIgnoreCase);

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__measureDbaDiskSpaceRequirementBegin"))
            {
                if (sentinel["__measureDbaDiskSpaceRequirementBegin"] is Hashtable state)
                {
                    _beginState = state;
                }
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void ProcessRecord()
    {
        // NO Interrupted PROLOGUE, and its absence is load-bearing. The nested hop reports a
        // Stop-Function back to the host, which latches Interrupted for the rest of the pipeline;
        // the source's process block reads Test-FunctionInterrupt nowhere, so a record whose source
        // instance will not connect must not silence the records behind it. Guarding here does
        // silence them - measured red on a sibling row's "should still process the record after the
        // failure" leg, against a pre-flip run of the same suite that was green.
        foreach (string name in MyInvocation.BoundParameters.Keys)
        {
            _boundNames.Add(name);
        }

        // The hop writes its carried locals straight back into _beginState, which is the same
        // Hashtable instance the script sees, so there is no process sentinel to demux.
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            Source, Database, SourceSqlCredential, Destination, DestinationDatabase,
            DestinationSqlCredential, Credential, EnableException.ToBool(), _beginState,
            _boundNames.Contains("Database"), _boundNames.Contains("DestinationDatabase"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    // PS: the begin block VERBATIM apart from the three helper declarations, which move to the
    // process hop because a declaration carries no state. The sentinel hands the two caches on.
    private const string BeginScript = """
param($__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__boundVerbose, $__boundDebug)

    $local:cacheMP = @{ }
    $local:cacheDP = @{ }

    @{ __measureDbaDiskSpaceRequirementBegin = @{ CacheMP = $cacheMP; CacheDP = $cacheDP; DestFiles = $null; DestDb = $null; Found = $null; DestFile = $null } }
} $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM, preceded by begin's helpers and the carried locals. Edits:
    // -FunctionName Measure-DbaDiskSpaceRequirement (plus -ModuleName "dbatools" on Write-Message)
    // on every DIRECT call and none inside the three helpers, which attribute to their own names in
    // the script world; and the two Test-Bound reads become the carried bound flags.
    private const string ProcessScript = """
param($Source, $Database, $SourceSqlCredential, $Destination, $DestinationDatabase, $DestinationSqlCredential, $Credential, $EnableException, $__beginState, $__boundDatabase, $__boundDestinationDatabase, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, [string]$Database, [PSCredential]$SourceSqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Destination, [string]$DestinationDatabase, [PSCredential]$DestinationSqlCredential, [PSCredential]$Credential, $EnableException, $__beginState, $__boundDatabase, $__boundDestinationDatabase)

    # begin's caches, and the three locals the source leaks from the previous record.
    $cacheMP = $__beginState.CacheMP
    $cacheDP = $__beginState.CacheDP
    $destFiles = $__beginState.DestFiles
    $destDb = $__beginState.DestDb
    $found = $__beginState.Found
    $destFile = $__beginState.DestFile

    function Get-MountPoint {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            $computerName,
            [PSCredential]$credential
        )
        Get-DbaCmObject -Class Win32_MountPoint -ComputerName $computerName -Credential $credential | Select-Object @{n = 'Mountpoint'; e = { $_.Directory.split('=')[1].Replace('"', '').Replace('\\', '\') } }
    }
    function Get-MountPointFromPath {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            $path,
            [Parameter(Mandatory)]
            $computerName,
            [PSCredential]$credential
        )
        if (!$cacheMP[$computerName]) {
            try {
                $cacheMP.Add($computerName, (Get-MountPoint -computerName $computerName -credential $credential))
                Write-Message -Level Verbose -Message "cacheMP[$computerName] is now cached"
            } catch {
                # This way, I won't be asking again for this computer.
                $cacheMP.Add($computerName, '?')
                Stop-Function -Message "Can't connect to $computerName. cacheMP[$computerName] = ?" -ErrorRecord $_ -Target $computerName -Continue
            }
        }
        if ($cacheMP[$computerName] -eq '?') {
            return '?'
        }
        foreach ($m in ($cacheMP[$computerName] | Sort-Object -Property Mountpoint -Descending)) {
            if ($path -like "$($m.Mountpoint)*") {
                return $m.Mountpoint
            }
        }
        Write-Message -Level Warning -Message "Path $path can't be found in any MountPoints of $computerName"
    }
    function Get-MountPointFromDefaultPath {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateSet('Log', 'Data')]
            $DefaultPathType,
            [Parameter(Mandatory)]
            $SqlInstance,
            [PSCredential]$SqlCredential,
            # Could probably use the computer defined in SqlInstance but info was already available from the caller
            $computerName,
            [PSCredential]$Credential
        )
        if (!$cacheDP[$SqlInstance]) {
            try {
                $cacheDP.Add($SqlInstance, (Get-DbaDefaultPath -SqlInstance $SqlInstance -SqlCredential $SqlCredential -EnableException))
                Write-Message -Level Verbose -Message "cacheDP[$SqlInstance] is now cached"
            } catch {
                Stop-Function -Message "Can't connect to $SqlInstance" -Continue
                $cacheDP.Add($SqlInstance, '?')
                return '?'
            }
        }
        if ($cacheDP[$SqlInstance] -eq '?') {
            return '?'
        }
        if (!$computerName) {
            $computerName = $cacheDP[$SqlInstance].ComputerName
        }
        if (!$cacheMP[$computerName]) {
            try {
                $cacheMP.Add($computerName, (Get-MountPoint -computerName $computerName -Credential $Credential))
            } catch {
                Stop-Function -Message "Can't connect to $computerName." -Continue
                $cacheMP.Add($computerName, '?')
                return '?'
            }
        }
        if ($DefaultPathType -eq 'Log') {
            $path = $cacheDP[$SqlInstance].Log
        } else {
            $path = $cacheDP[$SqlInstance].Data
        }
        foreach ($m in ($cacheMP[$computerName] | Sort-Object -Property Mountpoint -Descending)) {
            if ($path -like "$($m.Mountpoint)*") {
                return $m.Mountpoint
            }
        }
    }

    . {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source -FunctionName Measure-DbaDiskSpaceRequirement
            return
        }

        try {
            $destServer = Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination -FunctionName Measure-DbaDiskSpaceRequirement
            return
        }

        if (-not $__boundDestinationDatabase) {
            $DestinationDatabase = $Database
        }
        Write-Message -Level Verbose -Message "$Source.[$Database] -> $Destination.[$DestinationDatabase]" -FunctionName Measure-DbaDiskSpaceRequirement -ModuleName "dbatools"

        $sourceDb = Get-DbaDatabase -SqlInstance $sourceServer -Database $Database -SqlCredential $SourceSqlCredential
        if (-not $__boundDatabase) {
            Stop-Function -Message "Database [$Database] MUST exist on Source Instance $Source." -FunctionName Measure-DbaDiskSpaceRequirement
        }
        $sourceFiles = @($sourceDb.FileGroups.Files | Select-Object Name, FileName, Size, @{n = 'Type'; e = { 'Data' } })
        $sourceFiles += @($sourceDb.LogFiles | Select-Object Name, FileName, Size, @{n = 'Type'; e = { 'Log' } })

        if ($destDb = Get-DbaDatabase -SqlInstance $destServer -Database $DestinationDatabase -SqlCredential $DestinationSqlCredential) {
            $destFiles = @($destDb.FileGroups.Files | Select-Object Name, FileName, Size, @{n = 'Type'; e = { 'Data' } })
            $destFiles += @($destDb.LogFiles | Select-Object Name, FileName, Size, @{n = 'Type'; e = { 'Log' } })
            $computerName = $destDb.ComputerName
        } else {
            Write-Message -Level Verbose -Message "Database [$DestinationDatabase] does not exist on Destination Instance $Destination." -FunctionName Measure-DbaDiskSpaceRequirement -ModuleName "dbatools"
            $computerName = $destServer.ComputerName
        }

        foreach ($sourceFile in $sourceFiles) {
            foreach ($destFile in $destFiles) {
                if (($found = ($sourceFile.Name -eq $destFile.Name))) {
                    # Files found on both sides
                    [PSCustomObject]@{
                        SourceComputerName      = $sourceServer.ComputerName
                        SourceInstance          = $sourceServer.ServiceName
                        SourceSqlInstance       = $sourceServer.DomainInstanceName
                        DestinationComputerName = $destServer.ComputerName
                        DestinationInstance     = $destServer.ServiceName
                        DestinationSqlInstance  = $destServer.DomainInstanceName
                        SourceDatabase          = $sourceDb.Name
                        SourceLogicalName       = $sourceFile.Name
                        SourceFileName          = $sourceFile.FileName
                        SourceFileSize          = [DbaSize]($sourceFile.Size * 1000)
                        DestinationDatabase     = $destDb.Name
                        DestinationLogicalName  = $destFile.Name
                        DestinationFileName     = $destFile.FileName
                        DestinationFileSize     = [DbaSize]($destFile.Size * 1000) * -1
                        DifferenceSize          = [DbaSize]( ($sourceFile.Size * 1000) - ($destFile.Size * 1000) )
                        MountPoint              = Get-MountPointFromPath -Path $destFile.Filename -ComputerName $computerName -Credential $Credential
                        FileLocation            = 'Source and Destination'
                    } | Select-DefaultView -ExcludeProperty SourceComputerName, SourceInstance, DestinationInstance, DestinationLogicalName
                    break
                }
            }
            if (!$found) {
                # Files on source but not on destination
                [PSCustomObject]@{
                    SourceComputerName      = $sourceServer.ComputerName
                    SourceInstance          = $sourceServer.ServiceName
                    SourceSqlInstance       = $sourceServer.DomainInstanceName
                    DestinationComputerName = $destServer.ComputerName
                    DestinationInstance     = $destServer.ServiceName
                    DestinationSqlInstance  = $destServer.DomainInstanceName
                    SourceDatabase          = $sourceDb.Name
                    SourceLogicalName       = $sourceFile.Name
                    SourceFileName          = $sourceFile.FileName
                    SourceFileSize          = [DbaSize]($sourceFile.Size * 1000)
                    DestinationDatabase     = $DestinationDatabase
                    DestinationLogicalName  = $null
                    DestinationFileName     = $null
                    DestinationFileSize     = [DbaSize]0
                    DifferenceSize          = [DbaSize]($sourceFile.Size * 1000)
                    MountPoint              = Get-MountPointFromDefaultPath -DefaultPathType $sourceFile.Type -SqlInstance $Destination -SqlCredential $DestinationSqlCredential -computerName $computerName -credential $Credential
                    FileLocation            = 'Only on Source'
                } | Select-DefaultView -ExcludeProperty SourceComputerName, SourceInstance, DestinationInstance, DestinationLogicalName
            }
        }
        if ($destDb) {
            # Files on destination but not on source (strange scenario but possible)
            $destFilesNotSource = Compare-Object -ReferenceObject $destFiles -DifferenceObject $sourceFiles -Property Name -PassThru
            foreach ($destFileNotSource in $destFilesNotSource) {
                [PSCustomObject]@{
                    SourceComputerName      = $sourceServer.ComputerName
                    SourceInstance          = $sourceServer.ServiceName
                    SourceSqlInstance       = $sourceServer.DomainInstanceName
                    DestinationComputerName = $destServer.ComputerName
                    DestinationInstance     = $destServer.ServiceName
                    DestinationSqlInstance  = $destServer.DomainInstanceName
                    SourceDatabaseName      = $Database
                    SourceLogicalName       = $null
                    SourceFileName          = $null
                    SourceFileSize          = [DbaSize]0
                    DestinationDatabaseName = $destDb.Name
                    DestinationLogicalName  = $destFileNotSource.Name
                    DestinationFileName     = $destFile.FileName
                    DestinationFileSize     = [DbaSize]($destFileNotSource.Size * 1000) * -1
                    DifferenceSize          = [DbaSize]($destFileNotSource.Size * 1000) * -1
                    MountPoint              = Get-MountPointFromPath -Path $destFileNotSource.Filename -ComputerName $computerName -Credential $Credential
                    FileLocation            = 'Only on Destination'
                } | Select-DefaultView -ExcludeProperty SourceComputerName, SourceInstance, DestinationInstance, DestinationLogicalName
            }
        }
        $DestinationDatabase = $null
    }

    $__beginState.DestFiles = $destFiles
    $__beginState.DestDb = $destDb
    $__beginState.Found = $found
    $__beginState.DestFile = $destFile
} $Source $Database $SourceSqlCredential $Destination $DestinationDatabase $DestinationSqlCredential $Credential $EnableException $__beginState $__boundDatabase $__boundDestinationDatabase @__commonParameters 3>&1 2>&1
""";
}
