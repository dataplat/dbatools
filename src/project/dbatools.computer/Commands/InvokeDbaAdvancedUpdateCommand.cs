#nullable enable
#pragma warning disable CA1416 // Windows-only command: SQL Server setup, WinRM remoting, restarts

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Installs SQL Server updates/patches on a target computer, coordinating extraction, setup.exe,
/// and restart sequencing. Port of public/Invoke-DbaAdvancedUpdate.ps1; surface pinned by
/// migration/baselines/Invoke-DbaAdvancedUpdate.json.
///
/// Every dbatools dependency (Invoke-Program, Test-PendingReboot, Get-DbaDiskSpace,
/// Restart-Computer, Invoke-CommandWithFallBack, Invoke-Command2, Write-ProgressHelper) is invoked
/// through the dbatools MODULE SCOPE so that Pester's `-ModuleName dbatools` mocks intercept the
/// call and Assert-MockCalled -ModuleName dbatools counts it (the mock-based test contract).
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaAdvancedUpdate", SupportsShouldProcess = true)]
public sealed class InvokeDbaAdvancedUpdateCommand : DbaBaseCmdlet
{
    /// <summary>The remote computer where SQL Server updates will be installed.</summary>
    [Parameter(Position = 0)]
    public string? ComputerName { get; set; }

    /// <summary>The update action plan objects created by Update-DbaInstance.</summary>
    [Parameter(Position = 1)]
    public object[]? Action { get; set; }

    /// <summary>Automatically restarts the target computer after successful patch installation.</summary>
    [Parameter(Position = 2)]
    public bool Restart { get; set; }

    /// <summary>The WinRM authentication protocol for remote connections.</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    [ValidateSet("Default", "Basic", "Negotiate", "NegotiateWithImplicitCredential", "Credssp", "Digest", "Kerberos")]
    public string Authentication { get; set; } = "Credssp";

    /// <summary>Windows credential with permission to log on to the remote server.</summary>
    [Parameter(Position = 4)]
    public PSCredential? Credential { get; set; }

    /// <summary>The directory where update files will be extracted on the target.</summary>
    [Parameter(Position = 5)]
    public string? ExtractPath { get; set; }

    /// <summary>Additional command-line arguments passed to setup.exe.</summary>
    [Parameter(Position = 6)]
    public string[]? ArgumentList { get; set; }

    /// <summary>Skips the pending file-rename reboot check.</summary>
    [Parameter]
    public SwitchParameter NoPendingRenameCheck { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        string? computer = ComputerName;
        string activity = $"Updating SQL Server components on {computer}";
        bool restarted = false;

        // PS: $restartParams built once; Credential adds WsmanAuthentication.
        Hashtable restartParams = new Hashtable
        {
            { "ComputerName", computer },
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

        // PS: $restartNeeded = Test-PendingReboot ...; catch { $restartNeeded = $false; Stop-Function }
        bool restartNeeded;
        try
        {
            restartNeeded = LanguagePrimitives.IsTrue(ScalarModuleScoped("Test-PendingReboot", new Hashtable
            {
                { "ComputerName", computer },
                { "Credential", Credential },
                { "NoPendingRename", NoPendingRenameCheck }
            }));
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            restartNeeded = false;
            StopFunction($"Failed to get reboot status from {computer}", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
        }

        if (restartNeeded && Restart)
        {
            // PS: pre-work restart on a pending reboot.
            WriteMessage(MessageLevel.Verbose, $"Restarting computer {computer} due to pending restart");
            try
            {
                InvokeModuleScoped("Restart-Computer", restartParams);
                restarted = true;
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction($"Failed to restart computer {computer}", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
            }
        }

        int actionCount = Action?.Length ?? 0;
        WriteMessage(MessageLevel.Debug, $"Processing {computer} with {actionCount} actions");

        foreach (object? actionObj in Action ?? Array.Empty<object>())
        {
            // PS: $output = $currentAction (a REFERENCE - the input object is mutated in place and
            // is the emitted object). The port mutates the same PSObject's note properties.
            PSObject output = PSObject.AsPSObject(actionObj);
            SetNote(output, "Successful", false);
            SetNote(output, "Restarted", restarted);

            object? kb = GetNote(output, "KB");
            object? installer = GetNote(output, "Installer");
            object? build = GetNote(output, "Build");
            object? instanceNameValue = GetNote(output, "InstanceName");
            object? majorVersion = GetNote(output, "MajorVersion");
            object? targetLevel = GetNote(output, "TargetLevel");

            // PS: $execParams = @{ ComputerName; ErrorAction=Stop; Authentication } (+Credential)
            Hashtable execParams = new Hashtable
            {
                { "ComputerName", computer },
                { "ErrorAction", "Stop" },
                { "Authentication", Authentication }
            };
            if (Credential is not null)
            {
                execParams["Credential"] = Credential;
            }

            string chosenDrive;
            if (string.IsNullOrEmpty(ExtractPath))
            {
                // PS: (Get-DbaDiskSpace ... | Sort Free -Descending | Select -First 1).Name, else
                //     Invoke-Command2 { $env:SystemDrive } -Raw fallback.
                try
                {
                    Collection<PSObject> disks = CollectionModuleScoped("Get-DbaDiskSpace", new Hashtable
                    {
                        { "ComputerName", computer },
                        { "Credential", Credential },
                        { "EnableException", true }
                    });
                    object? top = SortSelectTopByFree(disks);
                    chosenDrive = LanguagePrimitives.ConvertTo<string>(GetNote(PSObject.AsPSObject(top), "Name")) ?? string.Empty;
                    if (string.IsNullOrEmpty(chosenDrive))
                    {
                        Hashtable icParams = new Hashtable(execParams);
                        icParams.Remove("Authentication");
                        icParams["ScriptBlock"] = ScriptBlock.Create("$env:SystemDrive");
                        icParams["Raw"] = true;
                        object? sysDrive = ScalarModuleScoped("Invoke-Command2", icParams);
                        chosenDrive = LanguagePrimitives.ConvertTo<string>(sysDrive) ?? string.Empty;
                    }
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    string msg = "Failed to retrieve a disk drive to extract the update";
                    AppendNote(output, "Notes", msg);
                    StopFunction(msg, exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
                    WriteObject(output);
                    return;
                }
            }
            else
            {
                // The else of `if (string.IsNullOrEmpty(ExtractPath))` guarantees a non-null value.
                chosenDrive = ExtractPath!;
            }

            // PS: "$($chosenDrive.TrimEnd('\'))\dbatools_KB<KB>_Extract_<guid-no-dashes>"
            string guid = Guid.NewGuid().ToString("N");
            string spExtractPath = $"{chosenDrive.TrimEnd('\\')}\\dbatools_KB{PsStr(kb)}_Extract_{guid}";
            SetNote(output, "ExtractPath", spExtractPath);

            PSObject? updateResult = null;
            try
            {
                // PS: extract - Invoke-Program -Path $Installer -ArgumentList @("/x:...","/quiet") -Fallback
                Hashtable extractParams = new Hashtable(execParams)
                {
                    { "Path", installer },
                    { "ArgumentList", new object?[] { $"/x:\"{spExtractPath}\"", "/quiet" } },
                    { "Fallback", true }
                };
                PSObject extractResult = PSObject.AsPSObject(ScalarModuleScoped("Invoke-Program", extractParams));
                if (!LanguagePrimitives.IsTrue(GetNote(extractResult, "Successful")))
                {
                    string msg = $"Extraction failed with exit code {PsStr(GetNote(extractResult, "ExitCode"))}, try specifying a different location using -ExtractPath";
                    AppendNote(output, "Notes", msg);
                    StopFunction(msg);
                    WriteObject(output);
                    return;
                }

                // PS: instanceClause + version-gated license-terms arg.
                string instanceClause = LanguagePrimitives.IsTrue(instanceNameValue)
                    ? $"/instancename={PsStr(instanceNameValue)}"
                    : "/allinstances";
                List<object?> programArguments = new();
                if (ArgumentList is not null)
                {
                    programArguments.AddRange(ArgumentList);
                }
                if (PsLike(PsStr(build), "10.0.*"))
                {
                    programArguments.Add("/quiet");
                    programArguments.Add(instanceClause);
                }
                else
                {
                    programArguments.Add("/quiet");
                    programArguments.Add(instanceClause);
                    programArguments.Add("/IAcceptSQLServerLicenseTerms");
                }

                WriteMessage(MessageLevel.Verbose, $"Starting installation from {spExtractPath}");
                Hashtable installParams = new Hashtable(execParams)
                {
                    { "Path", $"{spExtractPath}\\setup.exe" },
                    { "ArgumentList", programArguments.ToArray() },
                    { "WorkingDirectory", spExtractPath },
                    { "Fallback", true }
                };
                updateResult = PSObject.AsPSObject(ScalarModuleScoped("Invoke-Program", installParams));
                SetNote(output, "ExitCode", GetNote(updateResult, "ExitCode"));
                if (LanguagePrimitives.IsTrue(GetNote(updateResult, "Successful")))
                {
                    SetNote(output, "Successful", true);
                }
                else
                {
                    string msg = $"Update failed with exit code {PsStr(GetNote(updateResult, "ExitCode"))}";
                    AppendNote(output, "Notes", msg);
                    StopFunction(msg);
                    WriteObject(output);
                    return;
                }
                SetNote(output, "Log", GetNote(updateResult, "stdout"));
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction("Upgrade failed", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
                AppendNote(output, "Notes", PsExceptionMessage(ex));
                WriteObject(output);
                return;
            }
            finally
            {
                // PS: cleanup temp via Invoke-CommandWithFallBack, tolerant of failure.
                try
                {
                    Hashtable cleanupParams = new Hashtable(execParams)
                    {
                        { "ScriptBlock", ScriptBlock.Create("if ($args[0] -like '*\\dbatools_KB*_Extract*' -and (Test-Path $args[0])) { Remove-Item -Recurse -Force -LiteralPath $args[0] -ErrorAction Stop }") },
                        { "Raw", true },
                        { "ArgumentList", spExtractPath }
                    };
                    InvokeModuleScoped("Invoke-CommandWithFallBack", cleanupParams);
                }
                catch (Exception ex)
                {
                    string message = $"Failed to cleanup temp folder on computer {computer}: {PsExceptionMessage(ex)}";
                    WriteMessage(MessageLevel.Verbose, message);
                    AppendNote(output, "Notes", message);
                }
            }

            // PS: double-check restart need after install.
            try
            {
                restartNeeded = LanguagePrimitives.IsTrue(ScalarModuleScoped("Test-PendingReboot", new Hashtable
                {
                    { "ComputerName", computer },
                    { "Credential", Credential },
                    { "NoPendingRename", NoPendingRenameCheck }
                }));
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                restartNeeded = false;
                StopFunction($"Failed to get reboot status from {computer}", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
            }

            object? exitCode = updateResult is null ? null : GetNote(updateResult, "ExitCode");
            // PS: $updateResult.ExitCode -eq 3010 - Invoke-Program returns ExitCode as a uint32[]
            // (a single-element array), and PS -eq on an array LHS filters and is truthy when ANY
            // element matches; a scalar .Equals would miss the array case entirely.
            bool exit3010 = PsEqTruthy(exitCode, 3010);
            if (exit3010 || restartNeeded)
            {
                if (Restart)
                {
                    WriteMessage(MessageLevel.Verbose, $"Restarting computer {computer} and waiting for it to come back online");
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
                        StopFunction($"Failed to restart computer {computer}", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
                        AppendNote(output, "Notes", $"Restart is required for computer {computer} to finish the installation of SQL{PsStr(majorVersion)}{PsStr(targetLevel)}");
                    }
                }
                else
                {
                    AppendNote(output, "Notes", $"Restart is required for computer {computer} to finish the installation of SQL{PsStr(majorVersion)}{PsStr(targetLevel)}");
                }
            }

            WriteObject(output);
        }
    }

    // & (Get-Module dbatools | Where ModuleType -eq Script | Select -First 1) { param($c,$p) & $c @p }
    // runs the command in the dbatools module scope so a `-ModuleName dbatools` Pester mock intercepts
    // it and Assert-MockCalled -ModuleName dbatools counts it. Returns every emitted object.
    private Collection<PSObject> CollectionModuleScoped(string command, Hashtable splat)
    {
        ScriptBlock script = ScriptBlock.Create(
            "param($__c, $__p) " +
            "$__m = Get-Module dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1; " +
            "& $__m ([ScriptBlock]::Create('param($c, $p) & $c @p')) $__c $__p");
        NestedCommand.RequireDbatoolsScriptModule(this);
        Collection<PSObject> raw = InvokeCommand.InvokeScript(false, script, null, command, splat);
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

    // PS: $disks | Sort-Object Free -Descending | Select-Object -First 1.
    private static object? SortSelectTopByFree(Collection<PSObject> disks)
    {
        PSObject? best = null;
        double bestFree = double.NegativeInfinity;
        foreach (PSObject disk in disks)
        {
            if (disk is null)
            {
                continue;
            }
            object? freeValue = disk.Properties["Free"]?.Value;
            double free = freeValue is null ? double.NegativeInfinity : LanguagePrimitives.ConvertTo<double>(freeValue);
            if (free > bestFree)
            {
                bestFree = free;
                best = disk;
            }
        }
        return best;
    }

    private static object? GetNote(PSObject source, string name)
    {
        return source.Properties[name]?.Value;
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

    // PS: $output.Notes += $msg - array append (Notes starts @()).
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

    // PS -eq: an array LHS filters (result is truthy when ANY element equals rhs); a scalar LHS is
    // a direct engine equality. Invoke-Program's ExitCode is a single-element uint32[].
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

    private static bool PsLike(string? value, string pattern)
    {
        WildcardPattern wildcard = new(pattern, WildcardOptions.IgnoreCase);
        return wildcard.IsMatch(value ?? string.Empty);
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

    // Extracts the underlying ErrorRecord from a nested pipeline failure so StopFunction reports the
    // real error like the PS -ErrorRecord $_ path; returns true when a record was found.
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
}
