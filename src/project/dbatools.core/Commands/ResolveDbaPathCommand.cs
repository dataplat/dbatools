#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Validates and resolves paths with provider verification. Port of
/// public/Resolve-DbaPath.ps1 (W1-035). Every engine call (Get-Location, Resolve-Path,
/// Split-Path, Join-Path) rides the REAL engine cmdlet through the module-scope hop on the
/// caller's runspace, so provider semantics, wildcard expansion, PSDrives, and the session's
/// current location behave exactly as they did for the function (the hop also applies the
/// module PSDPV shield). Every Stop-Function site hardcodes -EnableException $true (the
/// W1-014 mapping: set the inherited property, then StopFunction - all failures TERMINATE);
/// the two -ErrorRecord-carrying sites surface the ORIGINAL exception text ("Cannot find
/// path ..."), the record-less sites the composed message (lab-pinned by TA-044). The
/// Provider check reproduces PS member enumeration + array-LHS -ne semantics: a single
/// resolved path compares case-insensitively as a scalar, several act as an any-mismatch
/// filter, and the failure message interpolates the projected names space-joined. Output is
/// each resolved ProviderPath (or the NewChild Join-Path result) streamed per item.
/// Positions: Path 0, Provider 1 (switches never positional).
/// Surface pinned by migration/baselines/Resolve-DbaPath.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Resolve, "DbaPath")]
public sealed class ResolveDbaPathCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared. The function has
    // no such parameter and hardcodes $true at every Stop-Function site.

    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsStringArrayCast]
    public string[] Path { get; set; } = null!;

    [Parameter(Position = 1)]
    public string? Provider { get; set; }

    [Parameter]
    public SwitchParameter SingleItem { get; set; }

    [Parameter]
    public SwitchParameter NewChild { get; set; }

    protected override void ProcessRecord()
    {
        foreach (string? rawPath in Path)
        {
            // PS: [string[]] coerces a null element to "" at bind time.
            string inputPath = rawPath ?? "";

            // PS: if ($inputPath -eq ".") { $inputPath = (Get-Location).Path }
            if (PsString.Eq(inputPath, "."))
                inputPath = NestedCommand.InvokeScoped(this, GetLocationPathScript) is { Count: > 0 } loc
                    ? (PsAssignment.Unwrap(loc[0]) as string ?? "")
                    : "";

            if (NewChild.ToBool())
            {
                // PS: $parent = Split-Path -Path $inputPath; $child = Split-Path -Path $inputPath -Leaf
                string? parent = FirstString(NestedCommand.InvokeScoped(this, SplitParentScript, inputPath));
                string? child = FirstString(NestedCommand.InvokeScoped(this, SplitLeafScript, inputPath));

                List<PSObject> parentPath;
                try
                {
                    // PS: if (-not $parent) { Get-Location -ErrorAction Stop } else { Resolve-Path $parent -ErrorAction Stop }
                    parentPath = string.IsNullOrEmpty(parent)
                        ? new List<PSObject>(NestedCommand.InvokeScoped(this, GetLocationScript))
                        : new List<PSObject>(NestedCommand.InvokeScoped(this, ResolvePathScript, parent));
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    // PS: catch { Stop-Function -Message "Failed to resolve path" -ErrorRecord $_ -EnableException $true }
                    EnableException = true;
                    StopFunction("Failed to resolve path", errorRecord: ToCaughtRecord(ex));
                    return;
                }

                // PS: if ($SingleItem -and (($parentPath | Measure-Object).Count -gt 1))
                if (SingleItem.ToBool() && parentPath.Count > 1)
                {
                    EnableException = true;
                    StopFunction("Could not resolve to a single parent path.");
                    return;
                }

                // PS: if ($Provider -and ($parentPath.Provider.Name -ne $Provider))
                if (ProviderMismatch(parentPath, out string providerNames))
                {
                    EnableException = true;
                    StopFunction("Resolved provider is " + providerNames + " when it should be " + Provider);
                    return;
                }

                // PS: foreach ($parentItem in $parentPath) { Join-Path $parentItem.ProviderPath $child }
                foreach (PSObject parentItem in parentPath)
                {
                    object? providerPath = PsProperty.Get(parentItem, "ProviderPath");
                    foreach (PSObject joined in NestedCommand.InvokeScoped(this, JoinPathScript, providerPath, child))
                        WriteObject(joined);
                }
            }
            else
            {
                List<PSObject> resolvedPaths;
                try
                {
                    // PS: $resolvedPaths = Resolve-Path $inputPath -ErrorAction Stop
                    resolvedPaths = new List<PSObject>(NestedCommand.InvokeScoped(this, ResolvePathScript, inputPath));
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    // PS: catch { Stop-Function -Message "Failed to resolve path" -ErrorRecord $_ -EnableException $true }
                    EnableException = true;
                    StopFunction("Failed to resolve path", errorRecord: ToCaughtRecord(ex));
                    return;
                }

                // PS: if ($SingleItem -and (($resolvedPaths | Measure-Object).Count -gt 1))
                if (SingleItem.ToBool() && resolvedPaths.Count > 1)
                {
                    EnableException = true;
                    StopFunction("Could not resolve to a single parent path.");
                    return;
                }

                // PS: if ($Provider -and ($resolvedPaths.Provider.Name -ne $Provider))
                if (ProviderMismatch(resolvedPaths, out string providerNames))
                {
                    EnableException = true;
                    StopFunction("Resolved provider is " + providerNames + " when it should be " + Provider);
                    return;
                }

                // PS: $resolvedPaths.ProviderPath - member enumeration streams each path.
                foreach (PSObject resolved in resolvedPaths)
                {
                    object? providerPath = PsProperty.Get(resolved, "ProviderPath");
                    if (providerPath is not null)
                        WriteObject(providerPath);
                }
            }
        }
    }

    /// <summary>PS: $items.Provider.Name -ne $Provider under an `if ($Provider -and ...)`
    /// guard. Member enumeration projects Provider.Name per item (null elements skipped); a
    /// single projection compares as a case-insensitive scalar, several filter any-mismatch,
    /// an empty projection is $null (mismatching any non-empty Provider). The out value is
    /// the interpolated "$($items.Provider.Name)" rendering (space-joined names).</summary>
    private bool ProviderMismatch(List<PSObject> items, out string providerNames)
    {
        List<string> names = new List<string>();
        foreach (PSObject item in items)
        {
            if (PsProperty.Get(PsProperty.Get(item, "Provider"), "Name") is string name)
                names.Add(name);
        }
        providerNames = string.Join(" ", names);

        if (!LanguagePrimitives.IsTrue(Provider))
            return false;
        if (names.Count == 0)
            return true;
        if (names.Count == 1)
            return !PsString.Eq(names[0], Provider);
        foreach (string name in names)
        {
            if (!PsString.Eq(name, Provider))
                return true;
        }
        return false;
    }

    private static string? FirstString(ICollection<PSObject> results)
    {
        foreach (PSObject item in results)
            return PsAssignment.Unwrap(item) as string;
        return null;
    }

    /// <summary>PS: catch { $_ } - a hand-built RuntimeException's lazy record drops the
    /// inner chain (ParentContainsErrorRecordException), so that shape rebuilds.</summary>
    private static ErrorRecord ToCaughtRecord(Exception ex)
    {
        if (ex is RuntimeException runtime && runtime.ErrorRecord is not null &&
            runtime.ErrorRecord.Exception is not ParentContainsErrorRecordException)
        {
            return runtime.ErrorRecord;
        }
        return new ErrorRecord(ex, "Resolve-DbaPath", ErrorCategory.NotSpecified, null);
    }

    private const string GetLocationPathScript = """
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    (Get-Location).Path
}
""";

    private const string GetLocationScript = """
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    Get-Location -ErrorAction Stop
}
""";

    private const string ResolvePathScript = """
param($path)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($path)
    Resolve-Path $path -ErrorAction Stop
} $path
""";

    private const string SplitParentScript = """
param($path)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($path)
    Split-Path -Path $path
} $path
""";

    private const string SplitLeafScript = """
param($path)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($path)
    Split-Path -Path $path -Leaf
} $path
""";

    private const string JoinPathScript = """
param($parent, $child)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($parent, $child)
    Join-Path $parent $child
} $parent $child
""";
}
