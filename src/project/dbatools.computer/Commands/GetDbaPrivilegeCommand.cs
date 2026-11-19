#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Management.Automation.Internal;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves Windows security privileges critical for SQL Server performance from target
/// computers via a secedit export. Port of public/Get-DbaPrivilege.ps1; surface pinned by
/// migration/baselines/Get-DbaPrivilege.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaPrivilege")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaPrivilegeCommand : DbaBaseCmdlet
{
    /// <summary>The target computer names to audit Windows privileges on; defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [Alias("cn", "host", "Server")]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Credential object used to connect to the computer as a different user.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS begin block: the here-string's backtick-escaped $ signs expand to literal text at parse
    // time; this is that expanded text, passed as -ArgumentList to the remote scriptblock.
    private const string ResolveSidFunctionText = @"function Convert-SIDToUserName ([string] $SID ) {
    try {
        $objSID = New-Object System.Security.Principal.SecurityIdentifier ($SID)
        $objUser = $objSID.Translate([System.Security.Principal.NTAccount])
        $objUser.Value
    } catch {
        $SID
    }
}";

    // The Invoke-Command2 -Raw scriptblock, verbatim from the PS source (comments included).
    private const string PrivilegeScript = @"
                    param ($ResolveSIDToAccountName)
                    . ([ScriptBlock]::Create($ResolveSIDToAccountName))

                    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("""")
                    secedit /export /cfg $temp\secpolByDbatools.cfg > $null
                    $CFG = Get-Content $temp\secpolByDbatools.cfg -Force
                    Remove-Item $temp\secpolByDbatools.cfg -Force

                    $blEntries = $CFG | Where-Object { $_ -like ""SeBatchLogonRight*"" }
                    $bl = if ($null -ne $blEntries) {
                        $blEntries.Substring(20).Split("","") | ForEach-Object {
                            if ($_ -match '^\*S-') {
                                <# DO NOT use Write-Message as this is inside of a script block #>
                                Convert-SIDToUserName -SID $_.TrimStart('*')
                            } else {
                                $_
                            }
                        }
                    }

                    $ifiEntries = $CFG | Where-Object { $_ -like 'SeManageVolumePrivilege*' }
                    $ifi = if ($null -ne $ifiEntries) {
                        $ifiEntries.Substring(26).Split("","") | ForEach-Object {
                            if ($_ -match '^\*S-') {
                                <# DO NOT use Write-Message as this is inside of a script block #>
                                Convert-SIDToUserName -SID $_.TrimStart('*')
                            } else {
                                $_
                            }
                        }
                    }

                    $lpimEntries = $CFG | Where-Object { $_ -like 'SeLockMemoryPrivilege*' }
                    $lpim = if ($null -ne $lpimEntries) {
                        $lpimEntries.Substring(24).Split("","") | ForEach-Object {
                            if ($_ -match '^\*S-') {
                                <# DO NOT use Write-Message as this is inside of a script block #>
                                Convert-SIDToUserName -SID $_.TrimStart('*')
                            } else {
                                $_
                            }
                        }
                    }

                    $gsaEntries = $CFG | Where-Object { $_ -like 'SeAuditPrivilege*' }
                    $gsa = if ($null -ne $gsaEntries) {
                        $gsaEntries.Substring(19).Split("","") | ForEach-Object {
                            if ($_ -match '^\*S-') {
                                <# DO NOT use Write-Message as this is inside of a script block #>
                                Convert-SIDToUserName -SID $_.TrimStart('*')
                            } else {
                                $_
                            }
                        }
                    }

                    $losEntries = $CFG | Where-Object { $_ -like ""SeServiceLogonRight*"" }
                    $los = if ($null -ne $losEntries) {
                        $losEntries.Substring(22).split("","") | ForEach-Object {
                            if ($_ -match '^\*S-') {
                                <# DO NOT use Write-Message as this is inside of a script block #>
                                Convert-SIDToUserName -SID $_.TrimStart('*')
                            } else {
                                $_
                            }
                        }
                    }

                    $cgoEntries = $CFG | Where-Object { $_ -like ""SeCreateGlobalPrivilege*"" }
                    $cgo = if ($null -ne $cgoEntries) {
                        $cgoEntries.Substring(26).Split("","") | ForEach-Object {
                            if ($_ -match '^\*S-') {
                                <# DO NOT use Write-Message as this is inside of a script block #>
                                Convert-SIDToUserName -SID $_.TrimStart('*')
                            } else {
                                $_
                            }
                        }
                    }

                    [PSCustomObject]@{
                        BatchLogon                = $bl
                        InstantFileInitialization = $ifi
                        LockPagesInMemory         = $lpim
                        GenerateSecurityAudit     = $gsa
                        LogonAsAService           = $los
                        CreateGlobalObjects       = $cgo
                    }";

    // PS begin block: $ComputerName = $ComputerName.ComputerName | Select-Object -Unique.
    // The variable keeps its [DbaInstanceParameter[]] type constraint, so the unique ComputerName
    // STRINGS re-parse into DbaInstanceParameter elements (the output objects carry a
    // DbaInstanceParameter in ComputerName, live-proven). Pipeline input re-binds the parameter
    // per record, overwriting this - exactly the PS begin/process interplay.
    private readonly List<DbaInstanceParameter> _beginComputers = new();

    protected override void BeginProcessing()
    {
        List<object?> names = new();
        if (ComputerName is not null)
        {
            foreach (DbaInstanceParameter? item in ComputerName)
            {
                if (item is null)
                {
                    continue;
                }
                names.Add(item.ComputerName);
            }
        }
        foreach (object? name in SelectUnique(names))
        {
            if (name is string text)
            {
                _beginComputers.Add(new DbaInstanceParameter(text));
            }
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        IEnumerable<DbaInstanceParameter> computers;
        if (MyInvocation.ExpectingInput)
        {
            computers = ComputerName ?? (IEnumerable<DbaInstanceParameter>)Array.Empty<DbaInstanceParameter>();
        }
        else
        {
            computers = _beginComputers;
        }

        foreach (DbaInstanceParameter computer in computers)
        {
            if (computer is null)
            {
                continue;
            }
            string computerText = computer.ToString();

            // PS: try { $null = Test-PSRemoting -ComputerName $Computer -EnableException } catch {
            //     Stop-Function -Message "Failure on $computer" -ErrorRecord $_ -Continue } - the
            // nested probe THROWS here (EnableException forwarded) and runs WITHOUT -Credential.
            try
            {
                TestPSRemotingOrThrow(computer.ComputerName);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException rex)
            {
                // PS: Stop-Function -Message "Failure on $computer" -ErrorRecord $_ - pass the ORIGINAL
                // Test-PSRemoting error record so its Test-WSMan detail is preserved in the message
                // (codex parity fix 2026-07-10).
                StopFunction($"Failure on {computerText}", target: computer, errorRecord: rex.ErrorRecord, continueLoop: true);
                continue;
            }
            catch (Exception ex)
            {
                StopFunction($"Failure on {computerText}", target: computer, exception: ex, continueLoop: true);
                continue;
            }

            // PS: one try around the export, the six shapes and the emission; any terminating
            // failure lands in Stop-Function "Failure" -Continue.
            try
            {
                WriteMessage(MessageLevel.Verbose, $"Exporting Privileges on {computerText} and cleaning up temporary files");

                RemoteExecutionService.RemoteCommandRequest request = new()
                {
                    ComputerName = computer,
                    Credential = Credential,
                    ScriptText = PrivilegeScript,
                    ArgumentList = new object[] { ResolveSidFunctionText },
                    Raw = true
                };
                RemoteExecutionService.RemoteCommandResult result = RemoteExecutionService.InvokeCommand(this, request);
                foreach (ErrorRecord error in result.Errors)
                {
                    WriteError(NestedCommand.PreserveErrorIdentity(error));
                }
                object? privData = ShapeOutput(result.Output);

                // PS: $bl = @($privData.BatchLogon) etc. - an empty remote privilege is
                // AutomationNull (count 0, fires the "No users ..." verbose); a null property from
                // a deserialized remote bag is a real $null (count 1), exactly like PS @().
                List<object?> bl = WrapArray(GetMemberValue(privData, "BatchLogon"));
                List<object?> ifi = WrapArray(GetMemberValue(privData, "InstantFileInitialization"));
                List<object?> lpim = WrapArray(GetMemberValue(privData, "LockPagesInMemory"));
                List<object?> gsa = WrapArray(GetMemberValue(privData, "GenerateSecurityAudit"));
                List<object?> los = WrapArray(GetMemberValue(privData, "LogonAsAService"));
                List<object?> cgo = WrapArray(GetMemberValue(privData, "CreateGlobalObjects"));

                WriteMessage(MessageLevel.Verbose, $"Getting Batch Logon Privileges on {computerText}");
                if (bl.Count == 0)
                {
                    WriteMessage(MessageLevel.Verbose, $"No users with Batch Logon Rights on {computerText}");
                }

                WriteMessage(MessageLevel.Verbose, $"Getting Instant File Initialization Privileges on {computerText}");
                if (ifi.Count == 0)
                {
                    WriteMessage(MessageLevel.Verbose, $"No users with Instant File Initialization Rights on {computerText}");
                }

                WriteMessage(MessageLevel.Verbose, $"Getting Lock Pages in Memory Privileges on {computerText}");
                if (lpim.Count == 0)
                {
                    WriteMessage(MessageLevel.Verbose, $"No users with Lock Pages in Memory Rights on {computerText}");
                }

                WriteMessage(MessageLevel.Verbose, $"Getting Generate Security Audits Privileges on {computerText}");
                if (gsa.Count == 0)
                {
                    WriteMessage(MessageLevel.Verbose, $"No users with Generate Security Audits Rights on {computerText}");
                }

                WriteMessage(MessageLevel.Verbose, $"Getting Logon as a service Privileges on {computerText}");
                if (los.Count == 0)
                {
                    WriteMessage(MessageLevel.Verbose, $"No users with Logon as a service Rights on {computerText}");
                }

                WriteMessage(MessageLevel.Verbose, $"Getting Create Global Objects Privileges on {computerText}");
                if (cgo.Count == 0)
                {
                    WriteMessage(MessageLevel.Verbose, $"No users with Create Global Objects Rights on {computerText}");
                }

                // PS: $users = @() + $bl + $ifi + $lpim + $gsa + $los + $cgo | Select-Object -Unique
                // (case-SENSITIVE, first occurrence wins) then one object per user with
                // case-insensitive -contains membership flags.
                List<object?> all = new();
                all.AddRange(bl);
                all.AddRange(ifi);
                all.AddRange(lpim);
                all.AddRange(gsa);
                all.AddRange(los);
                all.AddRange(cgo);

                foreach (object? user in SelectUnique(all))
                {
                    PSObject output = new();
                    output.Properties.Add(new PSNoteProperty("ComputerName", computer));
                    output.Properties.Add(new PSNoteProperty("User", user));
                    output.Properties.Add(new PSNoteProperty("LogonAsBatch", ContainsPs(bl, user)));
                    output.Properties.Add(new PSNoteProperty("InstantFileInitialization", ContainsPs(ifi, user)));
                    output.Properties.Add(new PSNoteProperty("LockPagesInMemory", ContainsPs(lpim, user)));
                    output.Properties.Add(new PSNoteProperty("GenerateSecurityAudit", ContainsPs(gsa, user)));
                    output.Properties.Add(new PSNoteProperty("LogonAsAService", ContainsPs(los, user)));
                    output.Properties.Add(new PSNoteProperty("CreateGlobalObjects", ContainsPs(cgo, user)));
                    WriteObject(output);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException rex)
            {
                StopFunction("Failure", target: computer, errorRecord: rex.ErrorRecord, continueLoop: true);
                continue;
            }
            catch (Exception ex)
            {
                StopFunction("Failure", target: computer, exception: ex, continueLoop: true);
                continue;
            }
        }
    }

    // PS (private/functions/Test-PSRemoting.ps1) invoked WITH -EnableException and WITHOUT
    // -Credential: the config-driven Test-WSMan probe (Credential stays [PSCredential]::Empty)
    // whose Stop-Function THROWS on failure - the caller's catch turns it into "Failure on X".
    private void TestPSRemotingOrThrow(string computerName)
    {
        bool useSsl = GetConfigBool("psremoting.pssession.usessl", false);
        int? port = GetConfigInt("psremoting.pssession.port");

        WriteMessage(MessageLevel.VeryVerbose, $"Testing {computerName}");
        try
        {
            using PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace);
            shell.AddCommand("Test-WSMan")
                .AddParameter("ComputerName", computerName)
                .AddParameter("Authentication", "Default")
                .AddParameter("Credential", PSCredential.Empty)
                .AddParameter("UseSSL", useSsl)
                .AddParameter("ErrorAction", "Stop");
            if (port.HasValue && port.Value > 0)
            {
                WriteMessage(MessageLevel.Verbose, $"Test using Port: {port.Value}");
                shell.AddParameter("Port", port.Value);
            }
            shell.Invoke();
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception)
        {
            // Re-throw the ORIGINAL Test-PSRemoting failure (a RuntimeException carrying the
            // Test-WSMan error record) so the caller's Stop-Function preserves its detail; wrapping
            // it replaced that detail with generic text (codex parity fix 2026-07-10).
            throw;
        }
    }

    // PS @( ... ) wrap: null -> one null element, AutomationNull -> empty, a collection -> its
    // elements, anything else -> one element. Strings and dictionaries never enumerate.
    private static List<object?> WrapArray(object? value)
    {
        List<object?> list = new();
        if (value is null)
        {
            list.Add(null);
            return list;
        }
        if (ReferenceEquals(value, AutomationNull.Value))
        {
            return list;
        }
        object? baseObject = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (baseObject is string || baseObject is System.Collections.IDictionary)
        {
            list.Add(value);
            return list;
        }
        if (baseObject is System.Collections.IEnumerable enumerable)
        {
            foreach (object? item in enumerable)
            {
                list.Add(item);
            }
            return list;
        }
        list.Add(value);
        return list;
    }

    // Select-Object -Unique: case-sensitive, first occurrence wins, order preserved. It also DROPS
    // $null pipeline inputs (codex parity fix 2026-07-10: keep parity with the PS pipeline).
    private static List<object?> SelectUnique(List<object?> items)
    {
        List<object?> unique = new();
        foreach (object? item in items)
        {
            if (item is null)
            {
                continue;
            }
            bool seen = false;
            foreach (object? kept in unique)
            {
                if (LanguagePrimitives.Equals(kept, item, ignoreCase: false))
                {
                    seen = true;
                    break;
                }
            }
            if (!seen)
            {
                unique.Add(item);
            }
        }
        return unique;
    }

    // PS -contains: element -eq candidate per element, case-insensitive like -eq.
    private static bool ContainsPs(List<object?> list, object? candidate)
    {
        foreach (object? item in list)
        {
            if (LanguagePrimitives.Equals(item, candidate, ignoreCase: true))
            {
                return true;
            }
        }
        return false;
    }

    // PS pipeline-assignment shape: empty -> null, one -> the scalar, many -> object[].
    private static object? ShapeOutput(List<PSObject> output)
    {
        if (output.Count == 0)
        {
            return null;
        }
        if (output.Count == 1)
        {
            return output[0];
        }
        return output.ToArray();
    }

    // PS property read over a pipeline-shaped value: null -> null, scalar -> the property value,
    // array -> member enumeration (values of elements that carry the property).
    private static object? GetMemberValue(object? source, string name)
    {
        if (source is null)
        {
            return null;
        }
        if (source is object[] many)
        {
            List<object?> values = new();
            foreach (object item in many)
            {
                if (item is null)
                {
                    continue;
                }
                PSPropertyInfo? property = PSObject.AsPSObject(item).Properties[name];
                if (property is not null)
                {
                    values.Add(property.Value);
                }
            }
            if (values.Count == 0)
            {
                return null;
            }
            if (values.Count == 1)
            {
                return values[0];
            }
            return values.ToArray();
        }
        return PSObject.AsPSObject(source).Properties[name]?.Value;
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
                // malformed configuration values fall back to the default, like Get-DbatoolsConfigValue -Fallback
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
                // malformed configuration values fall back to the default, like Get-DbatoolsConfigValue -Fallback
            }
        }
        return null;
    }

    // PS: [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME
    private static DbaInstanceParameter[]? DefaultComputerName()
    {
        string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(machine))
        {
            return null;
        }
        return new[] { new DbaInstanceParameter(machine) };
    }
}
