#nullable enable

namespace Dataplat.Dbatools.Commands;

// Hop script constants (the verbatim retired PS bodies) - split out per the repo 400-line file limit.
public sealed partial class ExportDbaPfDataCollectorSetTemplateCommand
{

    private const string SetContentScript = """
param($__params)
& Set-Content @__params 3>&1 2>&1
""";

    private const string GetChildItemScript = """
param($__params)
& Get-ChildItem @__params 3>&1 2>&1
""";

    private const string TestExportDirectoryScript = """
param($__path, $EnableException, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__path, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    $null = Test-ExportDirectory -Path $__path
} $__path $EnableException $__boundVerbose $__boundDebug 3>&1
""";

    private const string RemoveInvalidFileNameCharsScript = """
param($__name, $EnableException, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__name, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    Remove-InvalidFileNameChars -Name $__name
} $__name $EnableException $__boundVerbose $__boundDebug 3>&1
""";
}
