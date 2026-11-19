#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Moves database files to a new location, taking the database offline, copying, re-pointing the
/// metadata and bringing it back online. Port of public/Move-DbaDbFile.ps1; the workflow remains a
/// module-scoped PowerShell compatibility hop.
///
/// BEGIN+PROCESS, two hops. SqlInstance is a scalar ValueFromPipeline parameter, so process fires
/// once per piped instance. Begin only validates that -FileDestination accompanies -FileType.
///
/// THREE PARAMETER SETS - "All" (FileType + FileDestination), "Detailed" (FileToMove), and
/// "FileStructure" (FileStructureOnly) - with DeleteAfterMove declared in BOTH "All" and "Detailed"
/// via two [Parameter] attributes on the one property, and SqlInstance/SqlCredential/Database/Force/
/// EnableException in every set. There is no DefaultParameterSetName, matching the source.
///
/// THE PROCESS HOP STREAMS (InvokeScopedStreaming). This command DELETES source files after copying
/// them and emits one result object PER FILE - that per-file record is the audit trail of
/// destructive work already done. Buffered invocation would discard the records for files already
/// moved and deleted when a later file's failure terminates the hop under -EnableException, which
/// is exactly the DEF-001 class.
///
/// INTERRUPT CARRY IS LIVE HERE, unlike the two rows before it. Every one of the eleven
/// Stop-Function calls omits -Continue, so each sets the module interrupt flag, and the source's
/// process opens with "if (Test-FunctionInterrupt) { return }". Within one function scope that
/// means a begin validation failure, or a failure on an earlier piped instance, silences every
/// later record. Across separate hop invocations the flag does not survive, so each hop reads it at
/// Get-Variable -Scope 0 after its dot-sourced body and carries it, and C# skips process when a
/// prior hop carried true. The body keeps its own verbatim Test-FunctionInterrupt line as well.
///
/// CROSS-RECORD STATE. No PARAMETER is reassigned in the body, but three non-parameter locals are
/// branch-assigned and read on paths that can run before any assignment in a later record, so the
/// source's function scope carries them and a per-record hop would not:
///  - $failed is set true on a copy failure and NEVER reset, and the metadata-update and
///    source-file-deletion block is gated on "if (-not $failed)". In the source one failure
///    therefore suppresses those DESTRUCTIVE steps for every later piped instance; without the
///    carry the port would resume deleting source files after a failure the source treated as
///    disqualifying. This is the safety-relevant one.
///  - $ComputerName is assigned only on the localhost branch, the successful-remoting branches, or
///    the "$null -eq $ComputerName" fallback. When BOTH remoting probes fail on a later record, no
///    branch assigns it and the fallback does not fire because it still holds the PREVIOUS record's
///    value - so the source reuses the earlier host and the port would substitute the current one.
///  - $returnObject is assigned once per file in the main path but READ in the "already exists"
///    branch, which can run before any assignment in a record; the source reuses the prior record's
///    object there, where a fresh hop scope would raise a null-property error.
/// All three ride the state sentinel with per-name Assigned flags, so unset-vs-assigned survives.
///
/// Test-Bound never rides a hop, so the two begin probes become carried caller-boundness flags. All
/// seven $PSCmdlet.ShouldProcess gates route to the real cmdlet via $__realCmdlet so a "Yes to All"
/// persists across the whole invocation (SupportsShouldProcess, ConfirmImpact Medium mirrored). The
/// -FileStructureOnly path does "Write-Output $fileStructure" then returns - it EMITS before
/// exiting, which the dot-sourced body preserves. The four switches ride UNTYPED so positional
/// binding is not shifted. Surface pinned by migration/baselines/Move-DbaDbFile.json.
/// </summary>
[Cmdlet(VerbsCommon.Move, "DbaDbFile", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class MoveDbaDbFileCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true)]
    public DbaInstanceParameter SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instance.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database whose files are moved.</summary>
    [Parameter(Mandatory = true)]
    [PsStringCast]
    public string Database { get; set; } = null!;

    /// <summary>Move data files, log files, or both.</summary>
    [Parameter(ParameterSetName = "All")]
    [ValidateSet("Data", "Log", "Both")]
    [PsStringCast]
    public string? FileType { get; set; }

    /// <summary>Destination directory for every moved file.</summary>
    [Parameter(ParameterSetName = "All")]
    [PsStringCast]
    public string? FileDestination { get; set; }

    /// <summary>A logical-name to destination-directory map for per-file destinations.</summary>
    [Parameter(ParameterSetName = "Detailed")]
    public Hashtable? FileToMove { get; set; }

    /// <summary>Delete each source file once its copy is verified.</summary>
    [Parameter(ParameterSetName = "All")]
    [Parameter(ParameterSetName = "Detailed")]
    public SwitchParameter DeleteAfterMove { get; set; }

    /// <summary>Emit a ready-to-edit FileToMove hashtable and make no changes.</summary>
    [Parameter(ParameterSetName = "FileStructure")]
    public SwitchParameter FileStructureOnly { get; set; }

    /// <summary>Force the database offline, disconnecting users.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // A begin validation failure, or a failure on an earlier piped instance, silences the rest.
    private bool _interrupted;
    // The three branch-assigned locals the source keeps in function scope (opaque to C#).
    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            MyInvocation.BoundParameters.ContainsKey("FileType"),
            MyInvocation.BoundParameters.ContainsKey("FileDestination"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__moveDbaDbFileBegin"))
            {
                if (sentinel["__moveDbaDbFileBegin"] is Hashtable state)
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
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
        if (Interrupted || _interrupted)
            return;

        // Streaming, not buffered (DEF-001): this command deletes source files and emits one record
        // per file, so those records must reach the caller before a later file's failure can
        // terminate the hop under -EnableException.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__moveDbaDbFileProcess"))
            {
                if (sentinel["__moveDbaDbFileProcess"] is Hashtable result)
                {
                    _state = result["State"] as Hashtable;
                    _interrupted = LanguagePrimitives.IsTrue(result["Interrupted"]);
                }
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, FileType, FileDestination, FileToMove,
            DeleteAfterMove.ToBool(), FileStructureOnly.ToBool(), Force.ToBool(),
            EnableException.ToBool(), _state, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block VERBATIM, dot-sourced. Edits: the two Test-Bound probes become the
    // carried caller-boundness flags, -FunctionName on the one Stop-Function. That Stop-Function
    // omits -Continue, so it sets the interrupt and the sentinel reports it.
    private const string BeginScript = """
param($__boundFileType, $__boundFileDestination, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__boundFileType, $__boundFileDestination, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if (($__boundFileType) -and (-not($__boundFileDestination))) {
            Stop-Function -Category InvalidArgument -Message "FileDestination parameter is missing. Quitting." -FunctionName Move-DbaDbFile
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __moveDbaDbFileBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $__boundFileType $__boundFileDestination $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM per record, dot-sourced so every "Stop-Function; return" and
    // the -FileStructureOnly "Write-Output then return" exit only the body while the sentinel still
    // emits. Edits: the seven $PSCmdlet gates route to $__realCmdlet and -FunctionName is stamped on
    // the 24 direct Stop-Function/Write-Message calls. The sentinel carries this record's interrupt
    // so a failure silences later piped instances, as the single function scope did.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $FileType, $FileDestination, $FileToMove, $DeleteAfterMove, $FileStructureOnly, $Force, $EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [PSCredential]$SqlCredential, [string]$Database, [string]$FileType, [string]$FileDestination, [hashtable]$FileToMove, $DeleteAfterMove, $FileStructureOnly, $Force, $EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # Restore the three branch-assigned locals the source keeps in function scope. $failed gates the
    # DESTRUCTIVE metadata-update and source-delete block, so losing it would resume deletions the
    # source suppressed; $ComputerName is reused when both remoting probes fail on a later record;
    # $returnObject is read in the already-exists branch without being assigned there.
    if ($null -ne $__state) {
        foreach ($__name in "failed", "ComputerName", "returnObject") {
            if ($__state[$__name + "Assigned"]) { Set-Variable -Name $__name -Value $__state[$__name] }
        }
    }

    . {
        if (Test-FunctionInterrupt) { return }

        if ((-not $FileType) -and (-not $FileToMove) -and (-not $FileStructureOnly) ) {
            Stop-Function -Message "You must specify at least one of -FileType or -FileToMove or -FileStructureOnly to continue" -FunctionName Move-DbaDbFile
            return
        }

        if ($Database -in @("master", "model", "msdb", "tempdb")) {
            Stop-Function -Message "System database detected as input. The command does not support moving system databases. Quitting." -FunctionName Move-DbaDbFile
            return
        }

        try {
            try {
                $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -FunctionName Move-DbaDbFile
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
                Write-Message -Level Verbose -Message "Database $Database is not ONLINE. Getting file structure from sys.master_files." -FunctionName Move-DbaDbFile -ModuleName "dbatools"
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
                    if ($__realCmdlet.ShouldProcess($database, "Setting database $Database offline")) {
                        try {
                            $SetState = Set-DbaDbState -SqlInstance $server -Database $Database -Offline -Force:$Force
                            if ($SetState.Status -ne 'Offline') {
                                Stop-Function -Message "Setting database Offline failed!" -FunctionName Move-DbaDbFile
                                return
                            } else {
                                Write-Message -Level Verbose -Message "Database $Database was set to Offline status." -FunctionName Move-DbaDbFile -ModuleName "dbatools"
                            }
                        } catch {
                            Stop-Function -Message "Setting database Offline failed!" -ErrorRecord $_ -Target $SqlInstance -FunctionName Move-DbaDbFile
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

                # Test if defined paths are accessible by the instance
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
                    Stop-Function -Message "The path(s):`r`n $($testPathResults -join [Environment]::NewLine)`r`n is/are not accessible by the instance. Confirm if it/they exists." -FunctionName Move-DbaDbFile
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
                            if ($__realCmdlet.ShouldProcess($database, "Copying file $physicalName to $destination using Bits locally on $ComputerName")) {
                                try {
                                    Start-BitsTransfer -Source $physicalName -Destination $destination -ErrorAction Stop
                                } catch {
                                    try {
                                        Write-Message -Level Warning -Message "WARN: Could not copy file using Bits transfer. $_" -FunctionName Move-DbaDbFile -ModuleName "dbatools"
                                        Write-Message -Level Verbose -Message "Trying with Copy-Item" -FunctionName Move-DbaDbFile -ModuleName "dbatools"
                                        Copy-Item -Path $physicalName -Destination $destination -ErrorAction Stop

                                    } catch {
                                        $failed = $true

                                        Write-Message -Level Important -Message "ERROR: Could not copy file. $_" -FunctionName Move-DbaDbFile -ModuleName "dbatools"
                                    }
                                }
                            }
                        } else {
                            # Use Remoting PS to run the command on the server
                            try {
                                if ($__realCmdlet.ShouldProcess($database, "Copying file $physicalName to $destination using remote PS on $ComputerName")) {
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

                                    if ($__realCmdlet.ShouldProcess($database, "Copying file $physicalNameUNC to $destinationUNC using UNC path for $ComputerName")) {

                                        try {
                                            Write-Message -Level Verbose -Message "Try copying using Start-BitsTransfer with UNC paths." -FunctionName Move-DbaDbFile -ModuleName "dbatools"
                                            Start-BitsTransfer -Source $physicalNameUNC -Destination $destinationUNC -ErrorAction Stop
                                        } catch {
                                            Write-Message -Level Warning -Message "Did not work using Start-BitsTransfer. ERROR: $_" -FunctionName Move-DbaDbFile -ModuleName "dbatools"
                                            Write-Message -Level Verbose -Message "Trying using Copy-Item with UNC paths instead." -FunctionName Move-DbaDbFile -ModuleName "dbatools"
                                            Copy-Item -Path $physicalNameUNC -Destination $destinationUNC -ErrorAction Stop
                                        }

                                        # Force the copy of the file's ACL
                                        Get-Acl -Path $physicalNameUNC | Set-Acl $destinationUNC

                                        Write-Message -Level Verbose -Message "File $fileName was copied successfully" -FunctionName Move-DbaDbFile -ModuleName "dbatools"
                                    }
                                } catch {
                                    $failed = $true

                                    Write-Message -Level Important -Message "ERROR: Could not copy file. $_" -FunctionName Move-DbaDbFile -ModuleName "dbatools"
                                }
                            }

                            Write-Message -Level Verbose -Message "File $fileName was copied successfully" -FunctionName Move-DbaDbFile -ModuleName "dbatools"
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

                            $query = "ALTER DATABASE [$Database] MODIFY FILE (NAME=[$LogicalName], FILENAME='$destination'); "

                            if ($__realCmdlet.ShouldProcess($Database, "Executing ALTER DATABASE query - $query")) {
                                # Change database file path
                                $server.Databases["master"].Query($query)
                            }
                            if ($DeleteAfterMove) {
                                try {
                                    if ($__realCmdlet.ShouldProcess($database, "Deleting source file $physicalName")) {
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

                                    Stop-Function -Message "ERROR:" -ErrorRecord $_ -FunctionName Move-DbaDbFile
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
                        Write-Message -Level Verbose -Message "File $fileName already exists on $destination. Skipping." -FunctionName Move-DbaDbFile -ModuleName "dbatools"
                        $returnObject.SourceFileDeleted = "N/A"
                        $returnObject.DatabaseFileMetadata = "N/A"
                        $returnObject.Result = "Already exists. Skipping"
                        $returnObject
                    }
                }

                if ($__realCmdlet.ShouldProcess($Database, "Setting database Online")) {
                    try {
                        $SetState = Set-DbaDbState -SqlInstance $server -Database $Database -Online -ErrorVariable dbstate
                        if ($SetState.Status -ne 'Online') {
                            Stop-Function -Message "$($SetState.Notes)! : $($dbstate.Exception.InnerException.InnerException.InnerException.InnerException)." -FunctionName Move-DbaDbFile
                        } else {
                            Write-Message -Level Verbose -Message "Database is online!" -FunctionName Move-DbaDbFile -ModuleName "dbatools"
                        }
                    } catch {
                        Stop-Function -Message "Setting database online failed! : $($_.Exception.InnerException.InnerException.InnerException.InnerException)" -ErrorRecord $_ -Target $server.DomainInstanceName -OverrideExceptionMessage -FunctionName Move-DbaDbFile
                    }
                }
            } else {
                Write-Message -Level Warning -Message "We could not get any files for database $Database!" -FunctionName Move-DbaDbFile -ModuleName "dbatools"
            }
        } catch {
            Stop-Function -Message "ERROR:" -ErrorRecord $_ -FunctionName Move-DbaDbFile
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    $__snap = @{}
    foreach ($__name in "failed", "ComputerName", "returnObject") {
        $__v = Get-Variable -Name $__name -Scope 0 -ErrorAction Ignore
        if ($__v) { $__snap[$__name + "Assigned"] = $true; $__snap[$__name] = $__v.Value } else { $__snap[$__name + "Assigned"] = $false }
    }
    @{ __moveDbaDbFileProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value); State = $__snap } }
} $SqlInstance $SqlCredential $Database $FileType $FileDestination $FileToMove $DeleteAfterMove $FileStructureOnly $Force $EnableException $__state $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
