#nullable enable

using System;
using System.Collections;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Finds dbatools commands via the help index. Port of public/Find-DbaCommand.ps1.
/// The command takes NO pipeline input, so the process block runs exactly once - and the begin
/// block only DEFINES the nested Get-DbaIndex function and sets $moduleDirectory (both consumed
/// in process), with no side effect of its own. Because process runs once and begin is pure
/// setup, begin and process fold into a SINGLE process hop (the begin function definition and
/// $moduleDirectory assignment lead the process body verbatim) - splitting them would strand the
/// nested function and variable across separate scriptblock scopes. There is a single terminal
/// emit (Select-DefaultView) and no Stop-Function anywhere, so the buffered-emit-then-throw shape
/// (records held back, then discarded by a terminating error) cannot arise; the hop still runs
/// through InvokeScopedStreaming for uniformity. The only substitution is
/// $Pscmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess (ConfirmImpact MEDIUM, the
/// SupportsShouldProcess default, mirrored); the body is otherwise verbatim.
///
/// -FunctionName/-ModuleName inside the hop belong to Write-Message ONLY. Running inside the
/// module scriptblock, Write-Message would otherwise infer the hop as its caller and label the
/// message with the scriptblock instead of this command, so both are pinned there. They are NOT a
/// blanket decoration for the hop body: Get-DbaIndex's Select-Object -Unique takes neither, and
/// appending them there is a parameter-binding error that kills the index rebuild - which runs on
/// the DEFAULT path, not just under -Rebuild, because the rebuild is also what populates a missing
/// index file on a fresh install.
/// </summary>
[Cmdlet(VerbsCommon.Find, "DbaCommand", SupportsShouldProcess = true)]
public sealed class FindDbaCommandCommand : DbaBaseCmdlet
{
    /// <summary>Text pattern to match against command help.</summary>
    [Parameter(Position = 0)]
    public string? Pattern { get; set; }

    /// <summary>Tag(s) to filter by.</summary>
    [Parameter(Position = 1)]
    public string[]? Tag { get; set; }

    /// <summary>Author to filter by.</summary>
    [Parameter(Position = 2)]
    public string? Author { get; set; }

    /// <summary>Minimum version to filter by.</summary>
    [Parameter(Position = 3)]
    public string? MinimumVersion { get; set; }

    /// <summary>Maximum version to filter by.</summary>
    [Parameter(Position = 4)]
    public string? MaximumVersion { get; set; }

    /// <summary>Rebuilds the help index before searching.</summary>
    [Parameter]
    public SwitchParameter Rebuild { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

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
            Pattern, Tag, Author, MinimumVersion, MaximumVersion, Rebuild.ToBool(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block's Get-DbaIndex function definition and $moduleDirectory assignment lead
    // the process body VERBATIM (folded - the command has no pipeline input, so both blocks run
    // once). Substitution only: $Pscmdlet -> $__realCmdlet.
    private const string ProcessScript = """
param($Pattern, $Tag, $Author, $MinimumVersion, $MaximumVersion, $Rebuild, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([String]$Pattern, [String[]]$Tag, [String]$Author, [String]$MinimumVersion, [String]$MaximumVersion, $Rebuild, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    function Get-DbaIndex() {
        if ($__realCmdlet.ShouldProcess($dest, "Recreating index")) {
            $dbamodules = Get-Module -Name 'dbatools*'
            $allCommands = $dbamodules.ExportedCommands.Values | Where-Object CommandType -In 'Function', 'Cmdlet' | Where-Object Name -NotIn 'Write-Message' | Sort-Object -Property Name -Unique
            #Had to add Unique because Select-DbaObject was getting populated twice once written to the index file

            $helpcoll = New-Object System.Collections.Generic.List[System.Object]
            foreach ($command in $allCommands) {
                $x = Get-DbaHelp "$command"
                $helpcoll.Add($x)
            }
            # $dest = Get-DbatoolsConfigValue -Name 'Path.TagCache' -Fallback "$(Resolve-Path $PSScriptRoot\..)\dbatools-index.json"
            $dest = Resolve-Path "$moduleDirectory\bin\dbatools-index.json"
            $helpcoll | ConvertTo-Json -Depth 4 | Out-File $dest -Encoding Unicode
        }
    }

    $moduleDirectory = $script:PSModuleRoot

    $Pattern = $Pattern.TrimEnd("s")
    $idxFile = Resolve-Path "$moduleDirectory\bin\dbatools-index.json"
    if (!(Test-Path $idxFile) -or $Rebuild) {
        Write-Message -Level Verbose -Message "Rebuilding index into $idxFile" -FunctionName Find-DbaCommand -ModuleName "dbatools"
        $swRebuild = [system.diagnostics.stopwatch]::StartNew()
        Get-DbaIndex
        Write-Message -Level Verbose -Message "Rebuild done in $($swRebuild.ElapsedMilliseconds)ms" -FunctionName Find-DbaCommand -ModuleName "dbatools"
    }
    $consolidated = Get-Content -Raw $idxFile | ConvertFrom-Json
    $result = $consolidated
    if ($Pattern.Length -gt 0) {
        $result = $result | Where-Object { $_.PsObject.Properties.Value -like "*$Pattern*" }
    }

    if ($Tag.Length -gt 0) {
        foreach ($t in $Tag) {
            $result = $result | Where-Object Tags -Contains $t
        }
    }

    if ($Author.Length -gt 0) {
        $result = $result | Where-Object Author -Like "*$Author*"
    }

    if ($MinimumVersion.Length -gt 0) {
        $result = $result | Where-Object MinimumVersion -GE $MinimumVersion
    }

    if ($MaximumVersion.Length -gt 0) {
        $result = $result | Where-Object MaximumVersion -LE $MaximumVersion
    }

    Select-DefaultView -InputObject $result -Property CommandName, Synopsis
} $Pattern $Tag $Author $MinimumVersion $MaximumVersion $Rebuild $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
