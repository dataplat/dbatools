#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets the insecure-connection defaults (trust all server certificates, no encryption).
/// Port of public/Set-DbatoolsInsecureConnection.ps1 (W1-037). The two Set-DbatoolsConfig
/// -Passthru calls and the two Register-DbatoolsConfig calls ride the REAL compiled cmdlets
/// through the module-scope hop (compiled-calling-compiled); the -Passthru Config objects
/// stream to the pipeline UNASSIGNED exactly like the function's bare statements. A bound
/// -Register emits the deprecation warning. Scope is the only non-switch parameter, so it
/// carries the sole implicit position (0).
/// Surface pinned by migration/baselines/Set-DbatoolsInsecureConnection.json.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbatoolsInsecureConnection")]
public sealed class SetDbatoolsInsecureConnectionCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared. The function has
    // no such parameter (nothing here ever calls Stop-Function).

    [Parameter]
    public SwitchParameter SessionOnly { get; set; }

    [Parameter(Position = 0)]
    public ConfigScope Scope { get; set; } = ConfigScope.UserDefault;

    [Parameter]
    public SwitchParameter Register { get; set; }

    protected override void ProcessRecord()
    {
        // PS: if ($Register) { Write-Message -Level Warning -Message "..." }
        if (Register.ToBool())
            WriteMessage(MessageLevel.Warning, "The Register parameter is deprecated and will be removed in a future release.");

        // Set these defaults for all future sessions on this machine
        // PS: Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Passthru (unassigned - streams)
        foreach (PSObject item in NestedCommand.InvokeScoped(this, SetConfigScript, "sql.connection.trustcert", true))
            WriteObject(item);
        foreach (PSObject item in NestedCommand.InvokeScoped(this, SetConfigScript, "sql.connection.encrypt", false))
            WriteObject(item);

        // PS: if (-not $SessionOnly) { Register-DbatoolsConfig -FullName ... -Scope $Scope }
        if (!SessionOnly.ToBool())
        {
            foreach (PSObject item in NestedCommand.InvokeScoped(this, RegisterConfigScript, "sql.connection.trustcert", Scope))
                WriteObject(item);
            foreach (PSObject item in NestedCommand.InvokeScoped(this, RegisterConfigScript, "sql.connection.encrypt", Scope))
                WriteObject(item);
        }
    }

    private const string SetConfigScript = """
param($__fullName, $__value)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__fullName, $__value)
    Set-DbatoolsConfig -FullName $__fullName -Value $__value -Passthru 3>&1
} $__fullName $__value
""";

    // Hop params carry the __ prefix: an unprefixed name (e.g. $scope) collides with the
    // NESTED compiled command's own internal `$Scope = ...` assignment - dynamic scoping
    // reaches this block's optimized local and dies "Cannot overwrite variable Scope
    // because the variable has been optimized" (lab-caught by the FileUserLocal smoke).
    private const string RegisterConfigScript = """
param($__fullName, $__scope)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__fullName, $__scope)
    Register-DbatoolsConfig -FullName $__fullName -Scope $__scope 3>&1
} $__fullName $__scope
""";
}
