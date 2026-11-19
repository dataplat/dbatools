#nullable enable

using System;
using System.Collections;
using System.Globalization;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Lists the bundled Extended Events session templates and their metadata.
/// </summary>
/// <remarks>
/// The module-root resolution, the metadata Import-Clixml, the per-directory Get-ChildItem listing, the
/// Template base-name filter, the per-file [xml] cast, the metadata lookup, the -Pattern match, and the
/// PSCustomObject + Select-DefaultView projection all run the original dbatools PowerShell body VERBATIM
/// inside the dbatools module scope rather than being reimplemented in C#, so the engine decides the
/// observable details. Structured on the proven template-command pattern
/// (GetDbaPfDataCollectorSetTemplateCommand).
///
/// The begin block resolves $script:PSModuleRoot and Import-Clixml's the metadata bag - a once-only hop
/// whose result rides a sentinel Hashtable (Import-Clixml is I/O and can throw terminating, so it must
/// NOT be folded into the per-record process). It has no other output. In C# BeginProcessing the unbound
/// -Path is recomputed from the module root (the source default "$script:PSModuleRoot\bin\XEtemplates",
/// applied only when -Path was not bound), and $Pattern's like-to-regex Replace pair is reproduced (the
/// source line "$Pattern = $Pattern.Replace('*', '.*').Replace('..*', '.*')"; the unbound [string] reads
/// "" so the pair never faults - this IS assigned back in the source, so it is a real reassignment, not
/// the unconsumed-expression leak seen elsewhere).
///
/// Each -Path directory then rides one VERBATIM projection hop (the source's outer "foreach ($directory
/// in $Path)" is lifted into C#). The per-file [xml] cast's Stop-Function is -Continue (contained by the
/// hop's own file loop; -FunctionName pinned). Each matching template is emitted before a later file may
/// throw under -EnableException (DEF-001), so the projection hop uses InvokeScopedStreaming. There is no
/// ShouldProcess; TestBound is a C#-side check for the -Path default only. Surface pinned by
/// migration/baselines/Get-DbaXESessionTemplate.json.
/// </remarks>
[Cmdlet(VerbsCommon.Get, "DbaXESessionTemplate")]
public sealed class GetDbaXESessionTemplateCommand : DbaBaseCmdlet
{
    /// <summary>The template directory or directories.</summary>
    [Parameter(Position = 0)]
    public string[]? Path { get; set; }

    /// <summary>Regex (or like-mutated) filter against template name/category/source/description.</summary>
    [Parameter(Position = 1)]
    public string? Pattern { get; set; }

    /// <summary>The template base name(s) to include.</summary>
    [Parameter(Position = 2)]
    public string[]? Template { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _metadata;
    private string _pattern = "";

    protected override void BeginProcessing()
    {
        // No interrupt is read anywhere in this command (the one Stop-Function is -Continue), and the
        // base Interrupted flag is never set by a hop (it uses the module-scope PS Stop-Function, not the
        // C# StopFunction), so there is no guard here - the once-only begin hop must always run.
        object? moduleRoot = null;
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__getDbaXESessionTemplateBegin"))
            {
                if (sentinel["__getDbaXESessionTemplateBegin"] is Hashtable state)
                {
                    moduleRoot = state["ModuleRoot"];
                    _metadata = state["Metadata"];
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

        // PS: [string[]]$Path = "$script:PSModuleRoot\bin\XEtemplates" - the runtime default is applied
        // only when -Path was not bound (a bound -Path $null keeps the null, matching the source binder).
        if (!TestBound("Path"))
        {
            Path = new string[] { PsText(moduleRoot) + "\\bin\\XEtemplates" };
        }

        // PS: $Pattern = $Pattern.Replace("*", ".*").Replace("..*", ".*") - the unbound [string] reads ""
        // so the pair never faults.
        _pattern = (Pattern ?? "").Replace("*", ".*").Replace("..*", ".*");
    }

    protected override void ProcessRecord()
    {
        foreach (string? directory in Path ?? new string[0])
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
            }, DirectoryProjectionScript,
                directory, Template, _pattern, _metadata, EnableException.ToBool(),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
        }
    }

    /// <summary>PS string interpolation via LanguagePrimitives (invariant).</summary>
    private static string PsText(object? value)
    {
        if (value is null)
        {
            return "";
        }
        return (string)LanguagePrimitives.ConvertTo(value, typeof(string), CultureInfo.InvariantCulture);
    }

    // PS: the begin block's module-root + metadata Import-Clixml, returned via a sentinel. The
    // "$Pattern = $Pattern.Replace(...)" line is reproduced in C# (_pattern). Runs once in BeginProcessing.
    // The source reads $script:PSModuleRoot; the module's script scope is NOT reliably visible inside the
    // nested hop under the gate harness (it resolved EMPTY there, making both the metadata path and the
    // -Path default CWD-relative in sibling commands), so the
    // module root comes from the module OBJECT's ModuleBase instead. Same value, different resolution path.
    private const string BeginScript = """
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    $__moduleRoot = (Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1).ModuleBase
    $xmlpath = Join-DbaPath $__moduleRoot "bin" "xetemplates-metadata.xml"
    $metadata = Import-Clixml $xmlpath
    @{ __getDbaXESessionTemplateBegin = @{ ModuleRoot = $__moduleRoot; Metadata = $metadata } }
} 3>&1 2>&1
""";

    // PS: the per-directory process body VERBATIM (the source outer "foreach ($directory in $Path)" is
    // lifted into C#) apart from -FunctionName Get-DbaXESessionTemplate on the direct Stop-Function.
    private const string DirectoryProjectionScript = """
param($directory, $Template, $Pattern, $metadata, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($directory, [string[]]$Template, $Pattern, $metadata, $EnableException)
    $files = Get-ChildItem "$(Join-DbaPath $directory *.xml)"

    if ($Template) {
        $files = $files | Where-Object BaseName -in $Template
    }

    foreach ($file in $files) {
        try {
            $xml = [xml](Get-Content $file)
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue -FunctionName Get-DbaXESessionTemplate
        }

        foreach ($session in $xml.event_sessions) {
            $meta = $metadata | Where-Object Name -eq $session.event_session.name
            if ($Pattern) {
                if (
                    # There's probably a better way to do this
                    ($session.event_session.name -match $Pattern) -or
                    ($session.event_session.TemplateCategory.'#text' -match $Pattern) -or
                    ($session.event_session.TemplateSource -match $Pattern) -or
                    ($session.event_session.TemplateDescription.'#text' -match $Pattern) -or
                    ($session.event_session.TemplateName.'#text' -match $Pattern) -or
                    ($meta.Source -match $Pattern)
                ) {
                    [PSCustomObject]@{
                        Name          = $session.event_session.name
                        Category      = $session.event_session.TemplateCategory.'#text'
                        Source        = $meta.Source
                        Compatibility = ("$($meta.Compatibility)").ToString().Replace(",", "")
                        Description   = $session.event_session.TemplateDescription.'#text'
                        TemplateName  = $session.event_session.TemplateName.'#text'
                        Path          = $file
                        File          = $file.Name
                    } | Select-DefaultView -ExcludeProperty File, TemplateName, Path
                }
            } else {
                [PSCustomObject]@{
                    Name          = $session.event_session.name
                    Category      = $session.event_session.TemplateCategory.'#text'
                    Source        = $meta.Source
                    Compatibility = $meta.Compatibility.ToString().Replace(",", "")
                    Description   = $session.event_session.TemplateDescription.'#text'
                    TemplateName  = $session.event_session.TemplateName.'#text'
                    Path          = $file
                    File          = $file.Name
                } | Select-DefaultView -ExcludeProperty File, TemplateName, Path
            }
        }
    }
} $directory $Template $Pattern $metadata $EnableException @__commonParameters 3>&1 2>&1
""";
}
