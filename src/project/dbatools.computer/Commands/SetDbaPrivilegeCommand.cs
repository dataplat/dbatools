#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Internal;
using System.Runtime.InteropServices;
using System.Security.Principal;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Grants essential Windows privileges (IFI, LPIM, logon rights, security-audit and
/// create-global-objects) to SQL Server service accounts via a secedit round-trip on the target.
/// Port of public/Set-DbaPrivilege.ps1; surface pinned by migration/baselines/Set-DbaPrivilege.json.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaPrivilege", SupportsShouldProcess = true)]
public sealed class SetDbaPrivilegeCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s) whose SQL service accounts receive the privileges; defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [Alias("cn", "host", "Server")]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Credential object used to connect to the computer as a different user.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>Which Windows privileges to grant.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [ValidateSet("IFI", "LPIM", "BatchLogon", "SecAudit", "ServiceLogon", "CreateGlobalObjects")]
    public string[]? Type { get; set; }

    /// <summary>A custom account to receive the privileges instead of the discovered SQL service accounts.</summary>
    [Parameter(Position = 3)]
    public string? User { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS begin block: the here-string's backtick-escaped $ signs expand to literal text at parse
    // time; this is that expanded text, passed as -ArgumentList to the remote scriptblock.
    private const string ResolveAccountToSidText = @"function Convert-UserNameToSID ([string] $Acc ) {
$objUser = New-Object System.Security.Principal.NTAccount(""$Acc"")
$strSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
$strSID.Value
}";

    // The three Invoke-Command2 -Raw scriptblocks, verbatim from the PS source (comments included).
    private const string ExportScript = @"
                            $temp = ([System.IO.Path]::GetTempPath()).TrimEnd(""""); secedit /export /cfg $temp\secpolByDbatools.cfg > $NULL;
                        ";

    private const string MainScript = @"
                                [CmdletBinding()]
                                param ($ResolveAccountToSID,
                                    $SQLServiceAccounts,
                                    $SQLPerServiceSIDs,
                                    $Type
                                )
                                . ([ScriptBlock]::Create($ResolveAccountToSID))
                                $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("""");
                                $tempfile = ""$temp\secpolByDbatools.cfg""
                                if ('BatchLogon' -in $Type) {
                                    $BLline = Get-Content $tempfile | Where-Object { $_ -match ""SeBatchLogonRight"" }
                                    ForEach ($acc in $SQLServiceAccounts) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $BLline) {
                                            $BLline = ""SeBatchLogonRight = *$SID""
                                            (Get-Content $tempfile) -replace ""\[Privilege Rights\]"", ""[Privilege Rights]`n$BLline"" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""Added $acc to Batch Logon Privileges on $env:ComputerName""
                                        } elseif ($BLline -notmatch $SID) {
                                            (Get-Content $tempfile) -replace ""SeBatchLogonRight = "", ""SeBatchLogonRight = *$SID,"" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""Added $acc to Batch Logon Privileges on $env:ComputerName""
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""$acc already has Batch Logon Privilege on $env:ComputerName""
                                        }
                                    }
                                }
                                if ('IFI' -in $Type) {
                                    $IFIline = Get-Content $tempfile | Where-Object { $_ -match ""SeManageVolumePrivilege"" }
                                    # Use per-service SIDs for IFI: SQL Server uses the NT SERVICE\<ServiceName>
                                    # SID for volume maintenance tasks, matching SQL Server setup.exe behavior.
                                    ForEach ($acc in $SQLPerServiceSIDs) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $IFIline) {
                                            $IFIline = ""SeManageVolumePrivilege = *$SID""
                                            (Get-Content $tempfile) -replace ""\[Privilege Rights\]"", ""[Privilege Rights]`n$IFIline"" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""Added $acc to Instant File Initialization Privileges on $env:ComputerName""
                                        } elseif ($IFIline -notmatch $SID) {
                                            (Get-Content $tempfile) -replace ""SeManageVolumePrivilege = "", ""SeManageVolumePrivilege = *$SID,"" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""Added $acc to Instant File Initialization Privileges on $env:ComputerName""
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""$acc already has Instant File Initialization Privilege on $env:ComputerName""
                                        }
                                    }
                                }
                                if ('LPIM' -in $Type) {
                                    $LPIMline = Get-Content $tempfile | Where-Object { $_ -match ""SeLockMemoryPrivilege"" }
                                    # Use per-service SIDs for LPIM: SQL Server uses the NT SERVICE\<ServiceName>
                                    # SID for locked memory pages, matching SQL Server setup.exe behavior.
                                    ForEach ($acc in $SQLPerServiceSIDs) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $LPIMline) {
                                            $LPIMline = ""SeLockMemoryPrivilege = *$SID""
                                            (Get-Content $tempfile) -replace ""\[Privilege Rights\]"", ""[Privilege Rights]`n$LPIMline"" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""Added $acc to Lock Pages in Memory Privileges on $env:ComputerName""
                                        } elseif ($LPIMline -notmatch $SID) {
                                            (Get-Content $tempfile) -replace ""SeLockMemoryPrivilege = "", ""SeLockMemoryPrivilege = *$SID,"" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""Added $acc to Lock Pages in Memory Privileges on $env:ComputerName""
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""$acc already has Lock Pages in Memory Privilege on $env:ComputerName""
                                        }
                                    }
                                }
                                if ('SecAudit' -in $Type) {
                                    $SALine = Get-Content $tempfile | Where-Object { $_ -match ""SeAuditPrivilege"" }
                                    # Use per-service SIDs for SecAudit: SQL Server uses the NT SERVICE\<ServiceName>
                                    # SID when writing security audit events, matching SQL Server setup.exe behavior.
                                    ForEach ($acc in $SQLPerServiceSIDs) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $SALine) {
                                            $SALine = ""SeAuditPrivilege = *$SID""
                                            (Get-Content $tempfile) -replace ""\[Privilege Rights\]"", ""[Privilege Rights]`n$SALine"" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""Added $acc to Security Log Privileges on $env:ComputerName""
                                        } elseif ($SALine -notmatch $SID) {
                                            (Get-Content $tempfile) -replace ""SeAuditPrivilege = "", ""SeAuditPrivilege = *$SID,"" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""Added $acc to Write to Security Log Privileges on $env:ComputerName""
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""$acc already has Write To Security Audit Privilege on $env:ComputerName""
                                        }
                                    }
                                }
                                if ('ServiceLogon' -in $Type) {
                                    $SLline = Get-Content $tempfile | Where-Object { $_ -match ""SeServiceLogonRight"" }
                                    ForEach ($acc in $SQLServiceAccounts) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $SLline) {
                                            $SLline = ""SeServiceLogonRight = *$SID""
                                            (Get-Content $tempfile) -replace ""\[Privilege Rights\]"", ""[Privilege Rights]`n$SLline"" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""Added $acc to Service Logon Privileges on $env:ComputerName""
                                        } elseif ($SLline -notmatch $SID) {
                                            (Get-Content $tempfile) -replace ""SeServiceLogonRight = "", ""SeServiceLogonRight = *$SID,"" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""Added $acc to Service Logon Privileges on $env:ComputerName""
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""$acc already has Service Logon Privilege on $env:ComputerName""
                                        }
                                    }
                                }
                                if ('CreateGlobalObjects' -in $Type) {
                                    $CGOline = Get-Content $tempfile | Where-Object { $_ -match ""SeCreateGlobalPrivilege"" }
                                    ForEach ($acc in $SQLServiceAccounts) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $CGOline) {
                                            $CGOline = ""SeCreateGlobalPrivilege = *$SID""
                                            (Get-Content $tempfile) -replace ""\[Privilege Rights\]"", ""[Privilege Rights]`n$CGOline"" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""Added $acc to Create Global Objects Privileges on $env:ComputerName""
                                        } elseif ($CGOline -notmatch $SID) {
                                            (Get-Content $tempfile) -replace ""SeCreateGlobalPrivilege = "", ""SeCreateGlobalPrivilege = *$SID,"" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""Added $acc to Create Global Objects Privileges on $env:ComputerName""
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose ""$acc already has Create Global Objects Privilege on $env:ComputerName""
                                        }
                                    }
                                }
                                $null = secedit /configure /cfg $tempfile /db secedit.sdb /areas USER_RIGHTS /overwrite /quiet
                            ";

    private const string CleanupScript = @" $temp = ([System.IO.Path]::GetTempPath()).TrimEnd(""""); Remove-Item $temp\secpolByDbatools.cfg -Force > $NULL ";

    // PS begin block: $ComputerName = $ComputerName.ComputerName | Select-Object -Unique. The
    // variable keeps its [DbaInstanceParameter[]] type constraint, so the unique ComputerName
    // STRINGS re-parse into DbaInstanceParameter elements. Pipeline input re-binds the parameter
    // per record, overwriting this - exactly the PS begin/process interplay (W5-021 pattern).
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

            // PS: if ($Pscmdlet.ShouldProcess($computer, "Setting Privilege for SQL Service Account"))
            if (!ShouldProcess(computerText, "Setting Privilege for SQL Service Account"))
            {
                continue;
            }

            try
            {
                // PS: $null = Test-ElevationRequirement -ComputerName $Computer -Continue
                // (private/functions/flowcontrol/Test-ElevationRequirement.ps1 inlined: the test
                // only fails for a localhost target in a non-elevated process; -Continue is a
                // Stop-Function warning + continue with the next computer).
                if (!TestElevationRequirement(computer))
                {
                    StopFunction("Console not elevated, but elevation is required to perform some actions on localhost for this command.", continueLoop: true);
                    continue;
                }

                // PS: if (Test-PSRemoting -ComputerName $Computer) - invoked WITHOUT -Credential and
                // WITHOUT -EnableException: a failed probe writes Test-PSRemoting's own Stop-Function
                // warning ("Testing X") and returns false, and the caller's else adds its warning.
                if (TestPSRemoting(computer.ComputerName))
                {
                    WriteMessage(MessageLevel.Verbose, $"Exporting Privileges on {computerText}");
                    RemoteExecutionService.RemoteCommandRequest exportRequest = new()
                    {
                        ComputerName = computer,
                        Credential = Credential,
                        ScriptText = ExportScript,
                        Raw = true
                    };
                    RemoteExecutionService.RemoteCommandResult exportResult = RemoteExecutionService.InvokeCommand(this, exportRequest);
                    foreach (ErrorRecord error in exportResult.Errors)
                    {
                        WriteError(NestedCommand.PreserveErrorIdentity(error));
                    }

                    // PS: $SQLServiceAccounts = @(); $SQLPerServiceSIDs = @() then either the bound
                    // -User lands in BOTH lists, or Get-DbaService -Type Engine (nested, no
                    // -Credential, no -EnableException - its failure warns and yields nothing) fills
                    // them: += $services.StartName appends the member-enumerated values (a null/empty
                    // result appends ONE null element, PS @() + $null semantics), and the per-service
                    // SIDs are "NT SERVICE\<ServiceName>" per pipeline element.
                    List<object?> serviceAccounts = new();
                    List<object?> perServiceSids = new();
                    if (TestBound("User"))
                    {
                        serviceAccounts.Add(User);
                        perServiceSids.Add(User);
                    }
                    else
                    {
                        WriteMessage(MessageLevel.Verbose, $"Getting SQL Service Accounts on {computerText}");
                        Hashtable splatService = new Hashtable
                        {
                            { "ComputerName", computer },
                            { "Type", "Engine" }
                        };
                        Collection<PSObject> services = NestedCommand.Invoke(this, "Get-DbaService", splatService);
                        object? shapedServices = ShapeOutput(new List<PSObject>(services));
                        object? startNames = GetMemberValue(shapedServices, "StartName");
                        if (startNames is object[] startNameArray)
                        {
                            serviceAccounts.AddRange(startNameArray);
                        }
                        else
                        {
                            serviceAccounts.Add(startNames);
                        }
                        foreach (PSObject service in services)
                        {
                            if (service is null)
                            {
                                continue;
                            }
                            object? serviceName = service.Properties["ServiceName"]?.Value;
                            perServiceSids.Add("NT SERVICE\\" + PsToString(serviceName));
                        }
                    }

                    if (serviceAccounts.Count >= 1)
                    {
                        WriteMessage(MessageLevel.Verbose, $"Setting Privileges on {computerText}");
                        RemoteExecutionService.RemoteCommandRequest mainRequest = new()
                        {
                            ComputerName = computer,
                            Credential = Credential,
                            ScriptText = MainScript,
                            ArgumentList = new object?[] { ResolveAccountToSidText, serviceAccounts.ToArray(), perServiceSids.ToArray(), Type },
                            Raw = true,
                            // PS: Invoke-Command2 ... -Verbose - the remote Write-Verbose lines are
                            // shown UNCONDITIONALLY (the explicit -Verbose sets the invocation's
                            // preference), so the port re-emits them forced below.
                            ForceVerbose = true
                        };
                        RemoteExecutionService.RemoteCommandResult mainResult = RemoteExecutionService.InvokeCommand(this, mainRequest);
                        foreach (ErrorRecord error in mainResult.Errors)
                        {
                            WriteError(NestedCommand.PreserveErrorIdentity(error));
                        }
                        EmitForcedVerbose(mainResult.Verbose);

                        WriteMessage(MessageLevel.Verbose, $"Removing secpol file on {computerText}");
                        RemoteExecutionService.RemoteCommandRequest cleanupRequest = new()
                        {
                            ComputerName = computer,
                            Credential = Credential,
                            ScriptText = CleanupScript,
                            Raw = true
                        };
                        RemoteExecutionService.RemoteCommandResult cleanupResult = RemoteExecutionService.InvokeCommand(this, cleanupRequest);
                        foreach (ErrorRecord error in cleanupResult.Errors)
                        {
                            WriteError(NestedCommand.PreserveErrorIdentity(error));
                        }
                    }
                    else
                    {
                        WriteMessage(MessageLevel.Warning, $"No SQL Service Accounts found on {computerText}");
                    }
                }
                else
                {
                    WriteMessage(MessageLevel.Warning, $"Failed to connect to {computerText}");
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

    // PS (private/functions/flowcontrol/Test-ElevationRequirement.ps1): only a localhost target in
    // a non-elevated process fails the requirement (same inlining as the W5-037/W5-018 rows).
    private bool TestElevationRequirement(DbaInstanceParameter computer)
    {
        if (GetConfigTruthy("commands.test-elevationrequirement.disable"))
        {
            return true;
        }
        if (!computer.IsLocalHost)
        {
            return true;
        }
        // PS on non-Windows faults inside [Security.Principal.WindowsIdentity]::GetCurrent();
        // the throw lands in the caller's catch -> Stop-Function "Failure" + continue (codex
        // round finding: passing the requirement through instead let the command proceed into
        // remoting on Linux where PS never even probes).
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            throw new PlatformNotSupportedException("Windows Principal functionality is not supported on this platform.");
        }
        using WindowsIdentity identity = WindowsIdentity.GetCurrent();
        WindowsPrincipal principal = new(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    // PS (private/functions/Test-PSRemoting.ps1) invoked WITHOUT -Credential (stays
    // [PSCredential]::Empty) and WITHOUT -EnableException: the config-driven Test-WSMan probe whose
    // failure is Test-PSRemoting's own Stop-Function WARNING ("Testing X") + false (W5-015 shape).
    private bool TestPSRemoting(string computerName)
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
            return true;
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            // The PS catch variable is the UNWRAPPED error record: an -ErrorAction Stop failure
            // reaches C# as ActionPreferenceStopException whose Message is the preference wrapper
            // ("The running command stopped because..."), but $_ in PS carries the original
            // WSMan fault - compose the warning from the underlying record's exception.
            Exception composed = ex;
            if (ex is ActionPreferenceStopException apex && apex.ErrorRecord?.Exception is not null)
            {
                composed = apex.ErrorRecord.Exception;
            }
            else if (ex is RuntimeException rex && rex.ErrorRecord?.Exception is not null)
            {
                composed = rex.ErrorRecord.Exception;
            }
            WriteMessage(MessageLevel.Warning, $"Testing {computerName}", target: computerName, exception: composed);
            return false;
        }
    }

    // Re-emits captured remote verbose lines exactly as `Invoke-Command2 -Verbose` bubbled them:
    // the records left the function through its verbose stream regardless of the caller's
    // preference, so they both displayed AND survived a caller-side 4>&1 redirect. WriteVerbose
    // resolves the effective preference from the VerbosePreference variable per write (unless the
    // caller bound -Verbose/-Verbose:$false explicitly), so the swap forces emission through the
    // cmdlet's own stream 4 - the same channel the function records exited through.
    private void EmitForcedVerbose(List<string> messages)
    {
        if (messages.Count == 0)
        {
            return;
        }
        object saved = SessionState.PSVariable.GetValue("VerbosePreference");
        SessionState.PSVariable.Set("VerbosePreference", ActionPreference.Continue);
        try
        {
            foreach (string message in messages)
            {
                WriteVerbose(message);
            }
        }
        finally
        {
            SessionState.PSVariable.Set("VerbosePreference", saved ?? ActionPreference.SilentlyContinue);
        }
    }

    // PS "$($_.ServiceName)" string interpolation: null -> empty string, everything else via the
    // engine's string conversion.
    private static string PsToString(object? value)
    {
        if (value is null)
        {
            return string.Empty;
        }
        return LanguagePrimitives.ConvertTo<string>(value) ?? string.Empty;
    }

    // Select-Object -Unique: case-sensitive, first occurrence wins, order preserved, drops $null
    // pipeline inputs (the Get-DbaPrivilege W5-021 shape).
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

    private static bool GetConfigTruthy(string fullName)
    {
        if (ConfigurationHost.Configurations.TryGetValue(fullName, out Config? config) && config != null && config.Value != null)
        {
            try
            {
                return LanguagePrimitives.IsTrue(config.Value);
            }
            catch
            {
                // malformed configuration values count as unset, like Get-DbatoolsConfigValue -Fallback
            }
        }
        return false;
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
