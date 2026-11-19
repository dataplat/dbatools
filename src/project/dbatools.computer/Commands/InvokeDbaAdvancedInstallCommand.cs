#nullable enable
#pragma warning disable CA1416 // Windows-only command: SQL Server setup, WinRM remoting, restarts

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Installs SQL Server on a target computer from a configuration file, coordinating remote config
/// delivery, setup.exe, summary-log parsing, post-install privilege/port changes, and restart
/// sequencing. Port of public/Invoke-DbaAdvancedInstall.ps1; surface pinned by
/// migration/baselines/Invoke-DbaAdvancedInstall.json.
///
/// Every dbatools dependency is invoked through the dbatools MODULE SCOPE so Pester's
/// `-ModuleName dbatools` mocks intercept the calls (the install-family test contract).
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaAdvancedInstall")]
public sealed class InvokeDbaAdvancedInstallCommand : DbaBaseCmdlet
{
    /// <summary>The target computer.</summary>
    [Parameter(Position = 0)]
    public string? ComputerName { get; set; }

    /// <summary>The SQL Server instance name.</summary>
    [Parameter(Position = 1)]
    public string? InstanceName { get; set; }

    /// <summary>The TCP port to set after installation.</summary>
    [Parameter(Position = 2)]
    public int? Port { get; set; }

    /// <summary>Path to the setup installer.</summary>
    [Parameter(Position = 3)]
    public string? InstallationPath { get; set; }

    /// <summary>Path to the SQL Server configuration.ini.</summary>
    [Parameter(Position = 4)]
    public string? ConfigurationPath { get; set; }

    /// <summary>Additional setup.exe arguments.</summary>
    [Parameter(Position = 5)]
    public string[]? ArgumentList { get; set; }

    /// <summary>The SQL Server version being installed.</summary>
    [Parameter(Position = 6)]
    public Version? Version { get; set; }

    /// <summary>The configuration hashtable.</summary>
    [Parameter(Position = 7)]
    public Hashtable? Configuration { get; set; }

    /// <summary>Restart the computer as needed.</summary>
    [Parameter(Position = 8)]
    public bool Restart { get; set; }

    /// <summary>Grant Instant File Initialization (LPIM/IFI) to the service account after install.</summary>
    [Parameter(Position = 9)]
    public bool PerformVolumeMaintenanceTasks { get; set; }

    /// <summary>A path to save a copy of the configuration file.</summary>
    [Parameter(Position = 10)]
    public string? SaveConfiguration { get; set; }

    /// <summary>The WinRM authentication protocol.</summary>
    [Parameter(Position = 11)]
    [PsStringCast]
    [ValidateSet("Default", "Basic", "Negotiate", "NegotiateWithImplicitCredential", "Credssp", "Digest", "Kerberos")]
    public string Authentication { get; set; } = "Credssp";

    /// <summary>Windows credential for the remote server.</summary>
    [Parameter(Position = 12)]
    public PSCredential? Credential { get; set; }

    /// <summary>The sa credential (passed through to the output).</summary>
    [Parameter(Position = 13)]
    public PSCredential? SaCredential { get; set; }

    /// <summary>Skips the pending file-rename reboot check.</summary>
    [Parameter]
    public SwitchParameter NoPendingRenameCheck { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The Get-SqlInstallSummary inner scriptblock, verbatim from the PS source (run over
    // Invoke-Command2 -Raw against the target).
    private const string GetSummaryScript = @"
            Param (
                [parameter(Mandatory)]
                [version]$Version
            )
            $versionNumber = ""$($Version.Major)$($Version.Minor)"".Substring(0, 3)
            $rootPath = ""$([System.Environment]::GetFolderPath(""ProgramFiles""))\Microsoft SQL Server\$versionNumber\Setup Bootstrap\Log""
            $summaryPath = ""$rootPath\Summary.txt""
            $output = [PSCustomObject]@{
                Path              = $null
                Content           = $null
                ExitMessage       = $null
                ConfigurationFile = $null
            }
            if (Test-Path $summaryPath) {
                $output.Path = $summaryPath
                $output.Content = Get-Content -Path $summaryPath
                $output.ExitMessage = ($output.Content | Select-String ""Exit message"").Line -replace '^ *Exit message: *', ''
                $lastLogFolder = Get-ChildItem -Path $rootPath -Directory | Sort-Object -Property Name -Descending | Select-Object -First 1 -ExpandProperty FullName
                if (Test-Path $lastLogFolder\ConfigurationFile.ini) {
                    $output.ConfigurationFile = ""$lastLogFolder\ConfigurationFile.ini""
                }
                return $output
            }
        ";

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        bool isLocalHost = new DbaInstanceParameter(ComputerName).IsLocalHost;

        // PS: fixed 15-property $output object.
        PSObject output = new();
        output.Properties.Add(new PSNoteProperty("ComputerName", ComputerName));
        output.Properties.Add(new PSNoteProperty("Version", Version));
        output.Properties.Add(new PSNoteProperty("SACredential", SaCredential));
        output.Properties.Add(new PSNoteProperty("Successful", false));
        output.Properties.Add(new PSNoteProperty("Restarted", false));
        output.Properties.Add(new PSNoteProperty("Configuration", Configuration));
        output.Properties.Add(new PSNoteProperty("InstanceName", InstanceName));
        output.Properties.Add(new PSNoteProperty("Installer", InstallationPath));
        output.Properties.Add(new PSNoteProperty("Port", Port));
        output.Properties.Add(new PSNoteProperty("Notes", Array.Empty<object?>()));
        output.Properties.Add(new PSNoteProperty("ExitCode", null));
        output.Properties.Add(new PSNoteProperty("ExitMessage", null));
        output.Properties.Add(new PSNoteProperty("Log", null));
        output.Properties.Add(new PSNoteProperty("LogFile", null));
        output.Properties.Add(new PSNoteProperty("ConfigurationFile", null));

        Hashtable restartParams = new Hashtable
        {
            { "ComputerName", ComputerName },
            { "ErrorAction", "Stop" },
            { "For", "WinRM" },
            { "Wait", true },
            { "Force", true }
        };
        if (Credential is not null)
        {
            restartParams["Credential"] = Credential;
            restartParams["WsmanAuthentication"] = Authentication;
        }

        string activity = $"Installing SQL Server ({Version}) components on {ComputerName}";

        // PS: pre-work reboot check + optional restart.
        bool restartNeeded;
        try
        {
            restartNeeded = LanguagePrimitives.IsTrue(ScalarModuleScoped("Test-PendingReboot", TestRebootSplat()));
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            restartNeeded = false;
            StopFunction($"Failed to get reboot status from {ComputerName}", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
        }
        if (restartNeeded && Restart)
        {
            WriteMessage(MessageLevel.Verbose, $"Restarting computer {ComputerName} due to pending restart");
            try
            {
                InvokeModuleScoped("Restart-Computer", restartParams);
                SetNote(output, "Restarted", true);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction($"Failed to restart computer {ComputerName}", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
            }
        }

        // PS: save config if requested (real Copy-Item, tolerant).
        if (LanguagePrimitives.IsTrue(SaveConfiguration))
        {
            try
            {
                InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__s, $__d) $null = Copy-Item $__s -Destination $__d -ErrorAction Stop"), null, ConfigurationPath, SaveConfiguration);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                string msg = $"Could not save configuration file to {SaveConfiguration}";
                StopFunction(msg, exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
                AppendNote(output, "Notes", msg);
            }
        }

        // PS: connectionParams for the remote config copy (config-driven UseSSL/Port).
        Hashtable connectionParams = new Hashtable
        {
            { "ComputerName", ComputerName },
            { "ErrorAction", "Stop" },
            { "UseSSL", GetConfigBool("psremoting.pssession.usessl", false) }
        };
        int? winRmPort = GetConfigInt("psremoting.pssession.port");
        if (winRmPort.HasValue && winRmPort.Value > 0)
        {
            connectionParams["Port"] = winRmPort.Value;
            WriteMessage(MessageLevel.Verbose, $"Using Port: {winRmPort.Value}");
        }
        if (Credential is not null)
        {
            connectionParams["Credential"] = Credential;
        }

        // PS: localhost keeps the config in place; remote copies it via New-PSSession/Send-File.
        string? remoteConfig;
        if (isLocalHost)
        {
            remoteConfig = ConfigurationPath;
        }
        else
        {
            try
            {
                WriteMessage(MessageLevel.Verbose, $"Copying configuration file to {ComputerName}");
                remoteConfig = CopyConfigToRemote(connectionParams, ConfigurationPath, activity);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction($"Failed to copy file {ConfigurationPath} to remote on {ComputerName}, exiting", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
                return;
            }
        }

        // PS: $installParams = $ArgumentList + "/q" + "/CONFIGURATIONFILE=..."
        List<object?> installParams = new();
        if (ArgumentList is not null)
        {
            installParams.AddRange(ArgumentList);
        }
        installParams.Add("/q");
        installParams.Add($"/CONFIGURATIONFILE=\"{remoteConfig}\"");

        WriteMessage(MessageLevel.Verbose, $"Setup starting from {InstallationPath}");
        Hashtable execParams = new Hashtable
        {
            { "ComputerName", ComputerName },
            { "ErrorAction", "Stop" },
            { "Authentication", Authentication }
        };
        if (Credential is not null)
        {
            execParams["Credential"] = Credential;
        }
        else if (!TestBound("Authentication"))
        {
            // PS: Default authentication when neither Credential nor Authentication is bound.
            execParams["Authentication"] = "Default";
        }

        PSObject? installResult = null;
        try
        {
            WriteMessage(MessageLevel.Verbose, $"Installing SQL Server on {ComputerName} from {InstallationPath}");
            Hashtable installProgramSplat = new Hashtable(execParams)
            {
                { "Path", InstallationPath },
                { "ArgumentList", installParams.ToArray() },
                { "Fallback", true }
            };
            installResult = PSObject.AsPSObject(ScalarModuleScoped("Invoke-Program", installProgramSplat));
            SetNote(output, "ExitCode", GetNote(installResult, "ExitCode"));

            // PS: Get-SqlInstallSummary (tolerant - a failure warns and leaves the props empty).
            try
            {
                // When the remote returns no summary object the PS source just reads $null-valued
                // properties (no warning). Guard the null so AsPSObject(null) does not NRE here:
                // that NRE was caught below and re-emitted as a warning whose EnableException
                // error-record write terminated the nested worker, masking the real "Installation
                // failed with exit code N" StopFunction. Only a genuine throw warns, per the
                // function's try/catch tolerance.
                object? summaryRaw = ScalarModuleScoped("Invoke-Command2", new Hashtable
                {
                    { "ComputerName", ComputerName },
                    { "Credential", Credential },
                    { "ScriptBlock", ScriptBlock.Create(GetSummaryScript) },
                    { "ArgumentList", new object?[] { Version?.ToString() } },
                    { "ErrorAction", "Stop" },
                    { "Raw", true }
                });
                if (summaryRaw is not null)
                {
                    PSObject summary = PSObject.AsPSObject(summaryRaw);
                    SetNote(output, "ExitMessage", GetNote(summary, "ExitMessage"));
                    SetNote(output, "Log", GetNote(summary, "Content"));
                    SetNote(output, "LogFile", GetNote(summary, "Path"));
                    SetNote(output, "ConfigurationFile", GetNote(summary, "ConfigurationFile"));
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                WriteMessage(MessageLevel.Warning, $"Could not get the contents of the summary file from {ComputerName}. Related properties will be empty", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? rec!.Exception : ex);
            }
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            StopFunction("Installation failed", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
            AppendNote(output, "Notes", PsExceptionMessage(ex));
            WriteObject(output);
            return;
        }
        finally
        {
            try
            {
                WriteMessage(MessageLevel.Verbose, $"Cleaning up temporary files on {ComputerName}");
                if (!isLocalHost)
                {
                    Hashtable cleanupSplat = new Hashtable(connectionParams)
                    {
                        { "ScriptBlock", ScriptBlock.Create("if ($args[0] -like '*\\Configuration_*.ini' -and (Test-Path $args[0])) { Remove-Item -LiteralPath $args[0] -ErrorAction Stop }") },
                        { "Raw", true },
                        { "ArgumentList", remoteConfig }
                    };
                    InvokeModuleScoped("Invoke-Command2", cleanupSplat);
                }
                // PS: Remove-Item $ConfigurationPath (real - deletes the local config).
                InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__p) Remove-Item $__p"), null, ConfigurationPath);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction("Temp cleanup failed", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
            }
        }

        if (LanguagePrimitives.IsTrue(GetNote(installResult, "Successful")))
        {
            SetNote(output, "Successful", true);
        }
        else
        {
            string msg = $"Installation failed with exit code {PsStr(GetNote(installResult, "ExitCode"))}. Expand 'ExitMessage' and 'Log' property to find more details.";
            AppendNote(output, "Notes", msg);
            StopFunction(msg);
            WriteObject(output);
            return;
        }

        // PS: PerformVolumeMaintenanceTasks -> Set-DbaPrivilege IFI.
        if (PerformVolumeMaintenanceTasks)
        {
            InvokeModuleScoped("Set-DbaPrivilege", new Hashtable
            {
                { "ComputerName", ComputerName },
                { "Credential", Credential },
                { "Type", "IFI" },
                { "EnableException", EnableException }
            });
        }

        // PS: change port -> Set-DbaTcpPort + Restart-DbaService (tolerant).
        if (LanguagePrimitives.IsTrue(Port))
        {
            InvokeModuleScoped("Set-DbaTcpPort", new Hashtable
            {
                { "SqlInstance", $"{ComputerName}\\{InstanceName}" },
                { "Credential", Credential },
                { "Port", Port },
                { "EnableException", EnableException },
                { "Confirm", false }
            });
            try
            {
                InvokeModuleScoped("Restart-DbaService", new Hashtable
                {
                    { "ComputerName", ComputerName },
                    { "InstanceName", InstanceName },
                    { "Credential", Credential },
                    { "Type", "Engine" },
                    { "Force", true },
                    { "EnableException", EnableException },
                    { "Confirm", false }
                });
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                AppendNote(output, "Notes", $"Port for {ComputerName}\\{InstanceName} has been changed, but instance restart failed ({PsExceptionMessage(ex)}). Restart of instance is necessary for the new settings to become effective.");
            }
        }

        // PS: post-install reboot check + optional restart.
        try
        {
            restartNeeded = LanguagePrimitives.IsTrue(ScalarModuleScoped("Test-PendingReboot", TestRebootSplat()));
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            restartNeeded = false;
            StopFunction($"Failed to get reboot status from {ComputerName}", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
        }

        bool exit3010 = PsEqTruthy(GetNote(installResult, "ExitCode"), 3010);
        if (exit3010 || restartNeeded)
        {
            if (Restart)
            {
                WriteMessage(MessageLevel.Verbose, $"Restarting computer {ComputerName} and waiting for it to come back online");
                try
                {
                    InvokeModuleScoped("Restart-Computer", restartParams);
                    SetNote(output, "Restarted", true);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    StopFunction($"Failed to restart computer {ComputerName}", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
                    AppendNote(output, "Notes", $"Restart is required for computer {ComputerName} to finish the installation of Sql Server version {Version}");
                }
            }
            else
            {
                AppendNote(output, "Notes", $"Restart is required for computer {ComputerName} to finish the installation of Sql Server version {Version}");
            }
        }

        // PS: Select-DefaultView -Property ComputerName,InstanceName,Version,Port,Successful,Restarted,Installer,ExitCode,LogFile,Notes
        OutputHelper.SetDefaultDisplayPropertySet(output, new[] { "ComputerName", "InstanceName", "Version", "Port", "Successful", "Restarted", "Installer", "ExitCode", "LogFile", "Notes" });
        WriteObject(output);
    }

    private Hashtable TestRebootSplat()
    {
        return new Hashtable
        {
            { "ComputerName", ComputerName },
            { "Credential", Credential },
            { "NoPendingRename", NoPendingRenameCheck }
        };
    }

    // PS: New-PSSession + remote temp path + Send-File + Remove-PSSession. Driven through the
    // dbatools module scope so Send-File (private) resolves and any mock applies.
    private string CopyConfigToRemote(Hashtable connectionParams, string? configurationPath, string activity)
    {
        Hashtable payload = new Hashtable
        {
            { "ConnectionParams", connectionParams },
            { "ConfigurationPath", configurationPath }
        };
        Collection<PSObject> result = CollectionModuleScoped(
            "param($__p) " +
            "$session = New-PSSession @($__p.ConnectionParams); " +
            "$chosenPath = Invoke-Command -Session $session -ScriptBlock { (Get-Item ([System.IO.Path]::GetTempPath())).FullName } -ErrorAction Stop; " +
            "$remoteConfig = Join-DbaPath $chosenPath.TrimEnd('\\') (Split-Path $__p.ConfigurationPath -Leaf); " +
            "$null = Send-File -Path $__p.ConfigurationPath -Destination $chosenPath -Session $session -ErrorAction Stop; " +
            "$session | Remove-PSSession; " +
            "$remoteConfig",
            payload,
            rawScript: true);
        return result.Count > 0 ? LanguagePrimitives.ConvertTo<string>(result[result.Count - 1]) ?? string.Empty : string.Empty;
    }

    // ---- module-scoped invocation helpers (shared with the update worker pattern) ----

    // rawScript: the passed scriptText is the module-scoped body itself (already a param() block);
    // otherwise scriptText is a command NAME invoked as `& $c @p`.
    private Collection<PSObject> CollectionModuleScoped(string commandOrScript, object payload, bool rawScript = false)
    {
        ScriptBlock script;
        if (rawScript)
        {
            script = ScriptBlock.Create(
                "param($__body, $__p) " +
                "$__m = Get-Module dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1; " +
                "& $__m ([ScriptBlock]::Create($__body)) $__p");
            NestedCommand.RequireDbatoolsScriptModule(this);
            Collection<PSObject> rawOut = InvokeCommand.InvokeScript(false, script, null, commandOrScript, payload);
            return FilterWarnings(rawOut);
        }
        script = ScriptBlock.Create(
            "param($__c, $__p) " +
            "$__m = Get-Module dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1; " +
            "& $__m ([ScriptBlock]::Create('param($c, $p) & $c @p')) $__c $__p");
        NestedCommand.RequireDbatoolsScriptModule(this);
        Collection<PSObject> raw = InvokeCommand.InvokeScript(false, script, null, commandOrScript, payload);
        return FilterWarnings(raw);
    }

    private Collection<PSObject> FilterWarnings(Collection<PSObject> raw)
    {
        Collection<PSObject> output = new();
        foreach (PSObject item in raw)
        {
            if (item?.BaseObject is WarningRecord warning)
            {
                WriteWarning(warning.Message);
            }
            else if (item is not null)
            {
                output.Add(item);
            }
        }
        return output;
    }

    private object? ScalarModuleScoped(string command, Hashtable splat)
    {
        Collection<PSObject> output = CollectionModuleScoped(command, splat);
        if (output.Count == 0)
        {
            return null;
        }
        if (output.Count == 1)
        {
            return output[0];
        }
        object?[] many = new object?[output.Count];
        for (int i = 0; i < output.Count; i++)
        {
            many[i] = output[i];
        }
        return many;
    }

    private void InvokeModuleScoped(string command, Hashtable splat)
    {
        _ = CollectionModuleScoped(command, splat);
    }

    private static object? GetNote(PSObject? source, string name)
    {
        return source?.Properties[name]?.Value;
    }

    private static void SetNote(PSObject target, string name, object? value)
    {
        PSPropertyInfo? property = target.Properties[name];
        if (property is not null)
        {
            property.Value = value;
        }
        else
        {
            target.Properties.Add(new PSNoteProperty(name, value));
        }
    }

    private static void AppendNote(PSObject target, string name, object? value)
    {
        object? current = target.Properties[name]?.Value;
        List<object?> items = new();
        foreach (object? existing in EnumerateAny(current))
        {
            items.Add(existing);
        }
        items.Add(value);
        SetNote(target, name, items.ToArray());
    }

    private static IEnumerable<object?> EnumerateAny(object? value)
    {
        if (value is null)
        {
            yield break;
        }
        object unwrapped = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (unwrapped is string)
        {
            yield return value;
            yield break;
        }
        if (unwrapped is IEnumerable enumerable)
        {
            foreach (object? item in enumerable)
            {
                yield return item;
            }
            yield break;
        }
        yield return value;
    }

    private static bool PsEqTruthy(object? lhs, object rhs)
    {
        object? unwrapped = lhs is PSObject wrapped ? wrapped.BaseObject : lhs;
        if (unwrapped is not string && unwrapped is IEnumerable enumerable)
        {
            foreach (object? item in enumerable)
            {
                if (LanguagePrimitives.Equals(item, rhs, ignoreCase: true))
                {
                    return true;
                }
            }
            return false;
        }
        return LanguagePrimitives.Equals(unwrapped, rhs, ignoreCase: true);
    }

    private static string PsStr(object? value)
    {
        if (value is null)
        {
            return string.Empty;
        }
        return LanguagePrimitives.ConvertTo<string>(value) ?? string.Empty;
    }

    private static string PsExceptionMessage(Exception ex)
    {
        if (ex is RuntimeException rex && rex.ErrorRecord?.Exception is not null)
        {
            return rex.ErrorRecord.Exception.Message;
        }
        return ex.Message;
    }

    private static bool UnwrapRecord(Exception ex, out ErrorRecord? record)
    {
        if (ex is RuntimeException rex && rex.ErrorRecord is not null)
        {
            record = rex.ErrorRecord;
            return true;
        }
        record = null;
        return false;
    }

    private static bool GetConfigBool(string key, bool fallback)
    {
        if (ConfigurationHost.Configurations.TryGetValue(key, out Config? config) && config != null && config.Value != null)
        {
            try
            {
                return LanguagePrimitives.IsTrue(config.Value);
            }
            catch
            {
                // malformed configuration values fall back to the default
            }
        }
        return fallback;
    }

    private static int? GetConfigInt(string key)
    {
        if (ConfigurationHost.Configurations.TryGetValue(key, out Config? config) && config != null && config.Value != null)
        {
            try
            {
                return LanguagePrimitives.ConvertTo<int>(config.Value);
            }
            catch
            {
                // malformed configuration values fall back to null
            }
        }
        return null;
    }
}
