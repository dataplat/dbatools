#nullable enable

using System;
using System.Collections;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Parses SQL Server audit files (.sqlaudit) into structured event data for security analysis and
/// compliance reporting.
/// </summary>
/// <remarks>
/// The file-type resolution, the wildcard expansion, the Read-XEvent parsing, the column/action
/// projection, and the per-event object shaping all run the original dbatools PowerShell body VERBATIM
/// inside the dbatools module scope rather than being reimplemented in C#, so the engine decides the
/// observable details.
///
/// Process-only, non-mutating (no ShouldProcess). The three Stop-Function calls gain -FunctionName
/// Read-DbaAuditFile (in-hop the call-stack frame is the generated scriptblock, so the attribution must
/// be explicit). The source's `return` statements exit the process block for the current record; inside
/// the hop scriptblock they exit that record's invocation identically.
///
/// $Path is value-from-pipeline and only READ per record, so there is no cross-record carry. Each parsed
/// audit event is emitted as it is shaped, and within a single record's multi-file loop an earlier
/// file's events are emitted before a later file may fail its validation Stop-Function under
/// -EnableException, so the process hop uses InvokeScopedStreaming to avoid losing events that were
/// already produced (DEF-001). Surface pinned by migration/baselines/Read-DbaAuditFile.json.
/// </remarks>
[Cmdlet(VerbsCommunications.Read, "DbaAuditFile")]
public sealed class ReadDbaAuditFileCommand : DbaBaseCmdlet
{
    /// <summary>The path to SQL Server audit files (.sqlaudit) to read and parse.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [Alias("FullName")]
    public object[] Path { get; set; } = null!;

    /// <summary>Returns the unprocessed enumeration object instead of structured PowerShell objects.</summary>
    [Parameter]
    public SwitchParameter Raw { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare, which the inherited
    // [Parameter] already matches; no override needed.

    protected override void ProcessRecord()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            Path, Raw.ToBool(), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from -FunctionName Read-DbaAuditFile on the three Stop-Function
    // sites. EnableException is bound so Stop-Function's scope-walking default inherits the caller's value.
    private const string ProcessScript = """
param($Path, $Raw, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([object[]]$Path, $Raw, $EnableException)
    foreach ($file in $Path) {
        # in order to ensure CSV gets all fields, all columns will be
        # collected and output in the first (all all subsequent) object
        $columns = @("name", "timestamp")

        if ($file -is [System.String]) {
            $currentFile = $file
        } elseif ($file -is [System.IO.FileInfo]) {
            $currentFile = $file.FullName
        } else {
            if ($file -isnot [Microsoft.SqlServer.Management.Smo.Audit]) {
                Stop-Function -Message "Unsupported file type." -FunctionName Read-DbaAuditFile
                return
            }

            if (-not $file.FullName) {
                Stop-Function -Message "This Audit does not have an associated file." -FunctionName Read-DbaAuditFile
                return
            }

            $instance = [DbaInstanceParameter]$file.ComputerName

            if ($instance.IsLocalHost) {
                $currentFile = $file.FullName
            } else {
                $currentFile = $file.RemoteFullName
            }
        }

        # $currentFile is only the base filename and must be expanded using a wildcard
        $fileNames = (Get-ChildItem -Path ($currentFile -replace '\.sqlaudit$', '*.sqlaudit') | Sort-Object CreationTime).FullName
        $enum = @( )
        foreach ($fileName in $fileNames) {
            $accessible = Test-Path -Path $fileName
            $whoami = whoami
            if (-not $accessible) {
                Stop-Function -Continue -Message "$fileName cannot be accessed from $($env:COMPUTERNAME). Does $whoami have access?" -FunctionName Read-DbaAuditFile
            }

            $enum += Read-XEvent -FileName $fileName
        }

        if ($Raw) {
            return $enum
        }

        $newcolumns = ($enum.Fields.Name | Select-Object -Unique)

        $actions = ($enum.Actions.Name | Select-Object -Unique)
        foreach ($action in $actions) {
            $newcolumns += ($action -Split '\.')[-1]
        }

        $newcolumns = $newcolumns | Sort-Object
        $columns = ($columns += $newcolumns) | Select-Object -Unique

        # Make it selectable, otherwise it's a weird enumeration
        foreach ($event in $enum) {
            $hash = [ordered]@{ }

            foreach ($column in $columns) {
                $null = $hash.Add($column, $event.$column)
            }

            foreach ($key in $event.Actions.Keys) {
                $hash[$key] = $event.Actions[$key]
            }

            foreach ($key in $event.Fields.Keys) {
                $hash[$key] = $event.Fields[$key]
            }

            [PSCustomObject]$hash
        }
    }
} $Path $Raw $EnableException @__commonParameters 3>&1 2>&1
""";
}
