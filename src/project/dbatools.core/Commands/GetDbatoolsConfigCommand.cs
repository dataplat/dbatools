#nullable enable

using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using Dataplat.Dbatools.Configuration;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves configuration elements by name. Port of public/Get-DbatoolsConfig.ps1: the two
/// parameter-set filters run directly over ConfigurationHost.Configurations.Values with
/// WildcardPattern IgnoreCase matching (FullName mode does NOT lowercase its input, Module
/// mode lowers both Name and Module exactly like the function), Hidden gated by -Force, and
/// Sort-Object Module, Name modeled as current-culture case-insensitive OrderBy/ThenBy - the
/// same absorbed shapes the W1-007 Export-DbatoolsConfig port validated byte-identical and
/// two independent reviews passed with no findings. The function body had no
/// begin/process/end blocks, so EndProcessing preserves the END-block semantics. Surface
/// pinned by migration/baselines/Get-DbatoolsConfig.json (FullName default set + Module set).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbatoolsConfig", DefaultParameterSetName = "FullName")]
[OutputType(typeof(Config))]
public sealed class GetDbatoolsConfigCommand : DbaBaseCmdlet
{
    /// <summary>The full name (module.name) filter, default "*".</summary>
    [Parameter(ParameterSetName = "FullName", Position = 0)]
    public string FullName { get; set; } = "*";

    /// <summary>The setting name filter within the module, default "*".</summary>
    [Parameter(ParameterSetName = "Module", Position = 1)]
    public string Name { get; set; } = "*";

    /// <summary>The module filter, default "*".</summary>
    [Parameter(ParameterSetName = "Module", Position = 0)]
    public string Module { get; set; } = "*";

    /// <summary>Includes hidden configuration elements.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>Retains internal exception state without adding a parameter absent from the pinned function.</summary>
    public override SwitchParameter EnableException
    {
        get => base.EnableException;
        set => base.EnableException = value;
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        List<Config> configs;
        if (ParameterSetName == "Module")
        {
            // PS: $Name/$Module lowered, then -like filters + Sort-Object Module, Name
            WildcardPattern namePattern = WildcardPattern.Get(Name.ToLowerInvariant(), WildcardOptions.IgnoreCase);
            WildcardPattern modulePattern = WildcardPattern.Get(Module.ToLowerInvariant(), WildcardOptions.IgnoreCase);
            configs = ConfigurationHost.Configurations.Values
                .Where(c => namePattern.IsMatch(c.Name) && modulePattern.IsMatch(c.Module) && (!c.Hidden || Force.IsPresent))
                .OrderBy(c => c.Module, System.StringComparer.CurrentCultureIgnoreCase)
                .ThenBy(c => c.Name, System.StringComparer.CurrentCultureIgnoreCase)
                .ToList();
        }
        else
        {
            // PS: "$($_.Module).$($_.Name)" -like $FullName (input NOT lowered) + Sort-Object
            WildcardPattern pattern = WildcardPattern.Get(FullName, WildcardOptions.IgnoreCase);
            configs = ConfigurationHost.Configurations.Values
                .Where(c => pattern.IsMatch(c.Module + "." + c.Name) && (!c.Hidden || Force.IsPresent))
                .OrderBy(c => c.Module, System.StringComparer.CurrentCultureIgnoreCase)
                .ThenBy(c => c.Name, System.StringComparer.CurrentCultureIgnoreCase)
                .ToList();
        }

        foreach (Config config in configs)
        {
            WriteObject(config);
        }
    }
}
