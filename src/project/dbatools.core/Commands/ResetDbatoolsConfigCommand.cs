#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Configuration;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Resets dbatools configuration items to their initialize-time defaults. Port of
/// public/Reset-DbatoolsConfig.ps1 (W1-034). Three process-block regions run in order per
/// pipeline record: bound Config objects reset directly; FullName strings resolve through
/// the REAL (compiled) Get-DbatoolsConfig via the module-scope hop (compiled-calling-compiled,
/// the W1-017 pattern) after the function's case-sensitive type-name filter absorbs the
/// pipeline double-bind (a piped Config also binds to -FullName as its type-name string);
/// the Module branch resolves -Module/-Name the same way. Each item resets under its own
/// Low-impact ShouldProcess; a ResetValue fault re-raises as the PS method-invocation wrap
/// and routes to the function's exact Stop-Function -Continue call site (the foreach is
/// function-local, so continue targets the item loop). A null Config element reproduces the
/// engine's method-on-null failure inside the try, exactly like $item.ResetValue() on $null.
/// Bind-time null coercions follow the W1-032 class: a null -FullName ELEMENT and an
/// explicitly bound null -Name read as "" (an omitted -Name keeps its "*" default). The
/// command emits nothing to the pipeline. All parameter positions are null in the baseline
/// (explicit parameter sets suppress the implicit positional numbering).
/// Surface pinned by migration/baselines/Reset-DbatoolsConfig.json.
/// </summary>
[Cmdlet(VerbsCommon.Reset, "DbatoolsConfig", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low, DefaultParameterSetName = "Pipeline")]
public sealed class ResetDbatoolsConfigCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    [Parameter(ValueFromPipeline = true, ParameterSetName = "Pipeline")]
    public Config[]? ConfigurationItem { get; set; }

    [Parameter(ValueFromPipeline = true, ParameterSetName = "Pipeline")]
    public string[]? FullName { get; set; }

    [Parameter(Mandatory = true, ParameterSetName = "Module")]
    [PsStringCast]
    public string? Module { get; set; }

    [Parameter(ParameterSetName = "Module")]
    public string? Name { get; set; } = "*";

    protected override void ProcessRecord()
    {
        #region By configuration Item
        if (ConfigurationItem is not null)
        {
            foreach (Config? item in ConfigurationItem)
            {
                // PS: $PSCmdlet.ShouldProcess($item.FullName, 'Reset to default value') -
                // the target expression evaluates non-strict, so a null item targets null.
                if (ShouldProcess(item is null ? null : item.FullName, "Reset to default value"))
                {
                    if (!TryResetValue(item))
                        continue;
                }
            }
        }
        #endregion By configuration Item

        #region By FullName
        if (FullName is not null)
        {
            foreach (string? rawName in FullName)
            {
                // PS: [string[]] coerces a null element to "" at bind time.
                string nameItem = rawName ?? "";

                // The configuration items themselves can be cast to string, so they need to be filtered out,
                // otherwise on bind they would execute for this code-path as well.
                // PS: if ($nameItem -ceq "Dataplat.Dbatools.Configuration.Config") { continue }
                if (string.Equals(nameItem, "Dataplat.Dbatools.Configuration.Config", StringComparison.Ordinal))
                    continue;

                foreach (PSObject resolved in NestedCommand.InvokeScoped(this, GetConfigByFullNameScript, nameItem))
                {
                    Config? item = PsAssignment.Unwrap(resolved) as Config;
                    if (ShouldProcess(item is null ? null : item.FullName, "Reset to default value"))
                    {
                        if (!TryResetValue(item))
                            continue;
                    }
                }
            }
        }
        #endregion By FullName

        // PS: if ($Module) - string truthiness; only ever true in the Module parameter set.
        if (LanguagePrimitives.IsTrue(Module))
        {
            // PS: an explicitly bound null -Name coerces to "" at bind; omitted keeps "*".
            string name = Name ?? "";
            foreach (PSObject resolved in NestedCommand.InvokeScoped(this, GetConfigByModuleScript, Module, name))
            {
                Config? item = PsAssignment.Unwrap(resolved) as Config;
                if (ShouldProcess(item is null ? null : item.FullName, "Reset to default value"))
                {
                    if (!TryResetValue(item))
                        continue;
                }
            }
        }
    }

    /// <summary>PS: try { $item.ResetValue() } catch { Stop-Function -Message "Failed to
    /// reset the configuration item." -ErrorRecord $_ -Continue -EnableException
    /// $EnableException }. Returns false when the catch ran (the caller's loop continues,
    /// matching the function-local -Continue). A .NET fault re-raises as the PS
    /// method-invocation wrap; a null item raises the engine's method-on-null text.</summary>
    private bool TryResetValue(Config? item)
    {
        try
        {
            if (item is null)
                throw new PSInvalidOperationException("You cannot call a method on a null-valued expression.");
            try
            {
                item.ResetValue();
            }
            catch (Exception resetFault)
            {
                throw WrapAsMethodInvocation(resetFault, "ResetValue", 0);
            }
            return true;
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            StopFunction("Failed to reset the configuration item.", errorRecord: ToCaughtRecord(ex), continueLoop: true);
            return false;
        }
    }

    /// <summary>Rebuilds the MethodInvocationException the PS method binder raised for a
    /// failed .NET call: 'Exception calling "Name" with "N" argument(s): "inner"'.</summary>
    private static MethodInvocationException WrapAsMethodInvocation(Exception inner, string methodName, int argumentCount)
    {
        string text = "Exception calling \"" + methodName + "\" with \"" + argumentCount + "\" argument(s): \"" + inner.Message + "\"";
        return new MethodInvocationException(text, inner);
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
        return new ErrorRecord(ex, "Reset-DbatoolsConfig", ErrorCategory.NotSpecified, null);
    }

    private const string GetConfigByFullNameScript = """
param($fullName)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($fullName)
    Get-DbatoolsConfig -FullName $fullName 3>&1
} $fullName
""";

    private const string GetConfigByModuleScript = """
param($module, $name)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($module, $name)
    Get-DbatoolsConfig -Module $module -Name $name 3>&1
} $module $name
""";
}
