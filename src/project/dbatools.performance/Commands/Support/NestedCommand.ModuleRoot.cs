#nullable enable

using System;
using System.Collections;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

internal static partial class NestedCommand
{
    private const string InterruptBeaconVariable = "__dbatools_nested_interrupt_beacon_q7N4v2";

    private sealed class InterruptBeacon : IDisposable
    {
        private readonly PSCmdlet _host;
        private bool _disposed;

        internal InterruptBeacon(PSCmdlet host)
        {
            _host = host;
            State = new Hashtable
            {
                ["Interrupted"] = false,
                ["CallerCommand"] = null,
                ["CallerHasBoundParameters"] = false,
                ["CommandName"] = host.MyInvocation?.MyCommand?.Name
            };
        }

        internal Hashtable State { get; }

        public void Dispose()
        {
            if (_disposed)
                return;
            _disposed = true;

            if (!LanguagePrimitives.IsTrue(State["Interrupted"]) ||
                !LanguagePrimitives.IsTrue(State["CallerHasBoundParameters"]))
                return;

            string? caller = LanguagePrimitives.ConvertTo<string>(State["CallerCommand"]);
            string? commandName = LanguagePrimitives.ConvertTo<string>(State["CommandName"]);
            if (!string.Equals(caller, "<ScriptBlock>", StringComparison.Ordinal) &&
                !string.Equals(caller, commandName, StringComparison.OrdinalIgnoreCase))
                return;

            if (_host is INestedCommandInterruptHost interruptHost)
                interruptHost.InterruptFromNestedCommand();
        }
    }

    private static string InterruptBeaconSeedProlog(string seedToken)
    {
        string module = "$__dbatoolsInterruptModule_" + seedToken;
        string prior = "$__dbatoolsPriorInterruptBeacon_" + seedToken;
        string priorValue = "$__dbatoolsPriorInterruptBeaconValue_" + seedToken;
        return
            module + " = Get-Module -Name dbatools | Where-Object ModuleType -eq \"Script\" | Select-Object -First 1\n" +
            prior + " = if ($null -ne " + module + ") { & " + module + " { Get-Variable -Name " + InterruptBeaconVariable + " -Scope Script -ErrorAction Ignore } } else { $null }\n" +
            priorValue + " = if ($null -ne " + prior + ") { " + prior + ".Value } else { $null }\n" +
            "if ($null -ne " + module + ") { & " + module + " { param($__beacon) Set-Variable -Name " + InterruptBeaconVariable + " -Scope Script -Value $__beacon -Force -WhatIf:$false -Confirm:$false -ErrorAction Ignore } $__nestedInterruptBeacon }\n" +
            "try {\n";
    }

    private static string InterruptBeaconSeedEpilog(string seedToken)
    {
        string module = "$__dbatoolsInterruptModule_" + seedToken;
        string prior = "$__dbatoolsPriorInterruptBeacon_" + seedToken;
        string priorValue = "$__dbatoolsPriorInterruptBeaconValue_" + seedToken;
        return
            "\n} finally { " +
            "if ($null -ne " + module + ") { " +
            "if ($null -ne " + prior + ") { & " + module + " { param($__beacon) Set-Variable -Name " + InterruptBeaconVariable + " -Scope Script -Value $__beacon -Force -WhatIf:$false -Confirm:$false -ErrorAction Ignore } " + priorValue + " } " +
            "else { & " + module + " { Remove-Variable -Name " + InterruptBeaconVariable + " -Scope Script -Force -WhatIf:$false -Confirm:$false -ErrorAction Ignore } } } " +
            "Remove-Variable -Name __dbatoolsInterruptModule_" + seedToken + ", __dbatoolsPriorInterruptBeacon_" + seedToken + ", __dbatoolsPriorInterruptBeaconValue_" + seedToken + " -Force -WhatIf:$false -Confirm:$false -ErrorAction Ignore }";
    }

    // U-4 randomizer/PSModuleRoot cluster, INFRA fix. Retired bodies resolve module-relative
    // assets via "$script:PSModuleRoot\bin\..." - in the function world that hit the dbatools
    // module's script scope. A body-carrying hop executes in the CALLER'S session state, where
    // $script: resolves to the caller's script scope: the GLOBAL scope at a console, but the
    // TEST FILE'S script scope under the gate's Invoke-ManualPester - empty in both, and the
    // module's own copy is ALSO emptied by Pester 5.x session-state churn (root-caused on
    // Install-DbaInstance: path collapsed to "\bin\..."). The churn-immune source of truth is
    // [SystemHost]::ModuleBase (C# static, write-once at import), so every body-carrying hop
    // seeds the current script scope from it and restores the caller's prior value afterwards
    // (third-party callers may own a script-scoped PSModuleRoot of their own - the function
    // world never touched it, so neither may the hop). -WhatIf:$false because Set/Remove-Variable
    // honor ShouldProcess and a hop running under -WhatIf must still seed. Failures to seed fall
    // back to pre-fix behavior (SilentlyContinue) rather than killing the hop.
    // Get-Variable returns a LIVE PSVariable whose .Value mutates when the seed overwrites it,
    // so the prior VALUE is snapshotted into its own variable up front; the PSVariable object
    // itself only witnesses prior EXISTENCE (codex: restoring from .Value after the seed would
    // restore ModuleBase, not the caller's original).
    // -ErrorAction Ignore (not SilentlyContinue) everywhere: Ignore leaves NO $Error
    // bookkeeping, and the ErrorVariableBridge reconciles hop-era $Error entries into the
    // caller's bound -ErrorVariable - a phantom VariableNotFound from this best-effort seed
    // must never be delivered as if the command emitted it (codex r2).
    // The wrapper is DOT-SOURCED (InvokeScript useLocalScope:false), so these snapshot
    // variables land in the CALLER'S scope. A re-entrant hop (body invokes another compiled
    // dbatools cmdlet in the same frame) would overwrite fixed names and make the outer finally
    // restore the SEED instead of the caller's value (codex r3) - so every invocation gets
    // GUID-suffixed snapshot names, and the finally removes them to leave no scope litter.
    internal static void RequireDbatoolsScriptModule(PSCmdlet host)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        var modules = host.InvokeCommand.InvokeScript(
            "Get-Module -Name dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1");
        PSModuleInfo? scriptModule = modules.Count > 0 ? modules[0].BaseObject as PSModuleInfo : null;
        if (scriptModule is not null && scriptModule.ModuleType == ModuleType.Script)
            return;

        string? commandName = host.MyInvocation?.MyCommand?.Name;
        if (string.IsNullOrEmpty(commandName))
            commandName = "this command";
        throw new PSInvalidOperationException(
            "The dbatools script module is not loaded; Import-Module dbatools before calling " + commandName + ".");
    }

    private static string ModuleRootSeedProlog(PSCmdlet host, string scriptText, string seedToken)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        if (scriptText.IndexOf("$__dbatoolsModule", StringComparison.Ordinal) >= 0)
            RequireDbatoolsScriptModule(host);

        string prior = "$__dbatoolsPriorModuleRoot_" + seedToken;
        string priorValue = "$__dbatoolsPriorModuleRootValue_" + seedToken;
        return
            // Module-scope repair FIRST: bodies with a module-scoped inner hop
            // (& $__dbatoolsModule { ... }) resolve $script:PSModuleRoot against the MODULE's
            // script scope, which the same Pester churn empties and which the caller-scope seed
            // below cannot reach. Its correct value IS ModuleBase (what the psm1 set at import),
            // so this is a repair, not an override - no prior-value dance needed.
            "$null = Get-Module -Name dbatools | Where-Object ModuleType -eq \"Script\" | Select-Object -First 1 | ForEach-Object { & $_ { Set-Variable -Name PSModuleRoot -Scope Script -Value ([Dataplat.Dbatools.dbaSystem.SystemHost]::ModuleBase) -Force -WhatIf:$false -Confirm:$false -ErrorAction Ignore } }\n" +
            prior + " = Get-Variable -Name PSModuleRoot -Scope Script -ErrorAction Ignore\n" +
            priorValue + " = if ($null -ne " + prior + ") { " + prior + ".Value } else { $null }\n" +
            "Set-Variable -Name PSModuleRoot -Scope Script -Value ([Dataplat.Dbatools.dbaSystem.SystemHost]::ModuleBase) -Force -WhatIf:$false -Confirm:$false -ErrorAction Ignore\n" +
            "try {\n";
    }

    private static string ModuleRootSeedEpilog(string seedToken)
    {
        string prior = "$__dbatoolsPriorModuleRoot_" + seedToken;
        string priorValue = "$__dbatoolsPriorModuleRootValue_" + seedToken;
        return
            "\n} finally { " +
            "if ($null -ne " + prior + ") { Set-Variable -Name PSModuleRoot -Scope Script -Value " + priorValue + " -Force -WhatIf:$false -Confirm:$false -ErrorAction Ignore } " +
            "else { Remove-Variable -Name PSModuleRoot -Scope Script -Force -WhatIf:$false -Confirm:$false -ErrorAction Ignore } " +
            "Remove-Variable -Name __dbatoolsPriorModuleRoot_" + seedToken + ", __dbatoolsPriorModuleRootValue_" + seedToken + " -Force -WhatIf:$false -Confirm:$false -ErrorAction Ignore }";
    }
}
