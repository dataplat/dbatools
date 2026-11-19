#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Configuration;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Configures a managed path (Path.Managed.*) in the dbatools configuration system. Port of
/// public/Set-DbatoolsPath.ps1 (W1-038). The Set-DbatoolsConfig call (no -PassThru - the
/// function emits nothing) and the -Register branch's Register-DbatoolsConfig ride the REAL
/// compiled cmdlets through module-scope hops; hop params are __-prefixed (the W1-037
/// collision rule). The baseline records NO positional bindings (parameter-set declarations
/// suppress implicit numbering) and two sets: Default and Register (Register mandatory in
/// its set, Scope defaulting to UserDefault).
/// Surface pinned by migration/baselines/Set-DbatoolsPath.json.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbatoolsPath", DefaultParameterSetName = "Default")]
public sealed class SetDbatoolsPathCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared. The function has
    // no such parameter (nothing here ever calls Stop-Function).

    [Parameter(Mandatory = true)]
    [PsStringCast]
    public string Name { get; set; } = null!;

    [Parameter(Mandatory = true)]
    [PsStringCast]
    public string Path { get; set; } = null!;

    [Parameter(ParameterSetName = "Register", Mandatory = true)]
    public SwitchParameter Register { get; set; }

    [Parameter(ParameterSetName = "Register")]
    public ConfigScope Scope { get; set; } = ConfigScope.UserDefault;

    protected override void ProcessRecord()
    {
        // PS: Set-DbatoolsConfig -FullName "Path.Managed.$Name" -Value $Path (unassigned -
        // no -PassThru, so nothing streams; anything the engine DID emit would flow).
        string fullName = "Path.Managed." + Name;
        foreach (PSObject item in NestedCommand.InvokeScoped(this, SetConfigScript, fullName, Path))
            WriteObject(item);

        // PS: if ($Register) { Register-DbatoolsConfig -FullName "Path.Managed.$Name" -Scope $Scope }
        if (Register.ToBool())
        {
            foreach (PSObject item in NestedCommand.InvokeScoped(this, RegisterConfigScript, fullName, Scope))
                WriteObject(item);
        }
    }

    private const string SetConfigScript = """
param($__fullName, $__value)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__fullName, $__value)
    Set-DbatoolsConfig -FullName $__fullName -Value $__value 3>&1
} $__fullName $__value
""";

    private const string RegisterConfigScript = """
param($__fullName, $__scope)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__fullName, $__scope)
    Register-DbatoolsConfig -FullName $__fullName -Scope $__scope 3>&1
} $__fullName $__scope
""";
}
