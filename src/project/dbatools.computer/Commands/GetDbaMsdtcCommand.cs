#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves Microsoft Distributed Transaction Coordinator (MSDTC) service status and
/// configuration details from target servers. Port of public/Get-DbaMsdtc.ps1; surface pinned
/// by migration/baselines/Get-DbaMsdtc.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaMsdtc")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaMsdtcCommand : DbaBaseCmdlet
{
    /// <summary>The server or computer names where MSDTC information should be retrieved; defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [Alias("cn", "host", "Server")]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Alternative credential.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS begin block, verbatim: the WQL service query and the two registry scriptblocks that run
    // through Invoke-Command2 (cooked, no -Raw). Both transports are kept faithful: the service
    // read is the ENGINE Get-CimInstance (not Get-DbaCmObject - no CimRM->DCOM laddering, no
    // dbatools connection cache, and NO credential on the WSMan read, exactly like the PS source),
    // driven through a nested pipeline; the registry reads ride RemoteExecutionService.
    private const string Query = "Select * FROM Win32_Service WHERE Name = 'MSDTC'";

    private const string DtcSecurityScript = @"
            Get-ItemProperty -Path HKLM:\Software\Microsoft\MSDTC\Security |
                Select-Object PSPath, PSComputerName, AccountName, networkDTCAccess,
                networkDTCAccessAdmin, networkDTCAccessClients, networkDTCAccessInbound,
                networkDTCAccessOutBound, networkDTCAccessTip, networkDTCAccessTransactions, XATransactions
        ";

    private const string DtcCidsScript = @"
            New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT | Out-Null
            Get-ItemProperty -Path HKCR:\CID\*\Description |
                Select-Object @{ l = 'Data'; e = { $_.'(default)' } }, @{ l = 'CID'; e = { $_.PSParentPath.split('\')[-1] } }
            Remove-PSDrive -Name HKCR | Out-Null
        ";

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (ComputerName is null)
        {
            return;
        }

        // PS: foreach ($computer in $ComputerName.ComputerName) - member enumeration over the
        // parameter array yields each element's ComputerName string (null elements contribute none).
        foreach (DbaInstanceParameter computerParam in ComputerName)
        {
            if (computerParam is null)
            {
                continue;
            }
            string computer = computerParam.ComputerName;

            // PS: $reg = $cids = $null ; $cidHash = @{ } - a PS @{} literal is a case-insensitive
            // Hashtable; only the four fixed lookups below ever read it, so the comparer is the
            // whole observable contract.
            object? reg = null;
            object? cids = null;
            // PS hashtable literals are ORDINAL case-insensitive (not current-culture); use
            // OrdinalIgnoreCase so CID lookups match under any culture (e.g. Turkish 'I'/'i')
            // (codex parity fix 2026-07-10).
            Hashtable cidHash = new(StringComparer.OrdinalIgnoreCase);

            // PS: if ($Credential) { Test-PSRemoting -ComputerName $computer -Credential $Credential }
            //     else { Test-PSRemoting -ComputerName $computer } - both shapes collapse to the same
            //     probe because Test-PSRemoting defaults its Credential to [PSCredential]::Empty.
            bool remotingEnabled = TestPSRemoting(computer);

            object? dtcservice = null;
            if (remotingEnabled)
            {
                WriteMessage(MessageLevel.Verbose, $"Getting DTC on {computer} via WSMan");
                dtcservice = GetDtcServiceViaWsman(computer);
                if (dtcservice is null)
                {
                    WriteMessage(MessageLevel.Warning, $"Can't connect to CIM on {computer} via WSMan");
                }

                WriteMessage(MessageLevel.Verbose, $"Getting MSDTC Security Registry Values on {computer}");
                try
                {
                    reg = InvokeCommand2(computer, DtcSecurityScript);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException rex)
                {
                    StopFunction("Failure", errorRecord: rex.ErrorRecord, continueLoop: true);
                    continue;
                }
                catch (Exception ex)
                {
                    StopFunction("Failure", exception: ex, continueLoop: true);
                    continue;
                }
                if (reg is null)
                {
                    WriteMessage(MessageLevel.Warning, $"Can't connect to MSDTC Security registry on {computer}");
                }

                WriteMessage(MessageLevel.Verbose, $"Getting MSDTC CID Registry Values on {computer}");
                try
                {
                    cids = InvokeCommand2(computer, DtcCidsScript);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException rex)
                {
                    StopFunction("Failure", errorRecord: rex.ErrorRecord, continueLoop: true);
                    continue;
                }
                catch (Exception ex)
                {
                    StopFunction("Failure", exception: ex, continueLoop: true);
                    continue;
                }

                if (cids is not null)
                {
                    // PS: foreach ($key in $cids) { $cidHash.Add($key.Data, $key.CID) } - a duplicate
                    // (or null) Data key makes .Add throw a statement-terminating error: the record
                    // surfaces on the error stream and the loop moves to the next key. The PS method
                    // binder unwraps PSObject arguments before the .NET call, so the Hashtable holds
                    // RAW strings - without the unwrap the string lookups below miss silently.
                    foreach (object key in EnumeratePipeline(cids))
                    {
                        PSObject keyObject = PSObject.AsPSObject(key);
                        object? data = UnwrapForMethodCall(keyObject.Properties["Data"]?.Value);
                        object? cid = UnwrapForMethodCall(keyObject.Properties["CID"]?.Value);
                        try
                        {
                            cidHash.Add(data!, cid);
                        }
                        catch (Exception ex)
                        {
                            WriteError(new ErrorRecord(ex, "dbatools_Get-DbaMsdtc", ErrorCategory.NotSpecified, key));
                        }
                    }
                }
                else
                {
                    WriteMessage(MessageLevel.Warning, $"Can't connect to MSDTC CID registry on {computer}");
                }
            }
            else
            {
                WriteMessage(MessageLevel.Verbose, $"PSRemoting is not enabled on {computer}");
                try
                {
                    WriteMessage(MessageLevel.Verbose, $"Failed To get DTC via WinRM. Getting DTC on {computer} via DCom");
                    dtcservice = GetDtcServiceViaDcom(computer);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException rex)
                {
                    StopFunction($"Can't connect to CIM on {computer} via DCom", target: computer, errorRecord: rex.ErrorRecord, continueLoop: true);
                    continue;
                }
                catch (Exception ex)
                {
                    StopFunction($"Can't connect to CIM on {computer} via DCom", target: computer, exception: ex, continueLoop: true);
                    continue;
                }
            }

            // PS: if ( $dtcservice ) { [PSCustomObject]@{ ... } } - 18 fixed-order properties; the
            // registry halves stay null whenever $reg/$cidHash never populated (DCom branch, failed
            // reads), exactly like the PS null-propagation.
            if (LanguagePrimitives.IsTrue(dtcservice))
            {
                WriteObject(BuildOutput(dtcservice!, reg, cidHash));
            }
        }
    }

    // PS (private/functions/Test-PSRemoting.ps1): a config-driven Test-WSMan probe emitting
    // $true/$false. Get-DbaMsdtc does NOT forward its -EnableException, so a probe failure is
    // always the nested function's Stop-Function WARNING (message plus appended exception detail)
    // and $false - never a throw, even when the outer cmdlet runs with -EnableException.
    private bool TestPSRemoting(string computer)
    {
        bool useSsl = GetConfigBool("psremoting.pssession.usessl", false);
        int? port = GetConfigInt("psremoting.pssession.port");

        WriteMessage(MessageLevel.VeryVerbose, $"Testing {computer}");
        try
        {
            using PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace);
            shell.AddCommand("Test-WSMan")
                .AddParameter("ComputerName", computer)
                .AddParameter("Authentication", "Default")
                .AddParameter("Credential", Credential ?? PSCredential.Empty)
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
            WriteMessage(MessageLevel.Warning, $"Testing {computer}", target: computer, exception: ex);
            return false;
        }
    }

    // PS: $dtcservice = Get-CimInstance -ComputerName $computer -Query $query - the engine CIM
    // cmdlet over WSMan, deliberately WITHOUT -Credential (the PS source never passes it here).
    // No try/catch in the source: a failure is a statement-terminating error, so the record
    // surfaces on the caller's error stream, $dtcservice stays null and execution continues with
    // the "Can't connect to CIM ... via WSMan" warning.
    private object? GetDtcServiceViaWsman(string computer)
    {
        using PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace);
        shell.AddCommand("Get-CimInstance")
            .AddParameter("ComputerName", computer)
            .AddParameter("Query", Query);
        ForwardVerboseSwitch(shell);

        List<PSObject> output = new();
        try
        {
            foreach (PSObject item in shell.Invoke())
            {
                if (item is not null)
                {
                    output.Add(item);
                }
            }
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (RuntimeException rex)
        {
            ReemitNestedStreams(shell);
            WriteError(NestedCommand.PreserveErrorIdentity(rex.ErrorRecord));
            return null;
        }
        ReemitNestedStreams(shell);
        return ShapeOutput(output);
    }

    // PS DCom branch, statement for statement inside one try: New-CimSessionOption -Protocol Dcom,
    // New-CimSession (non-terminating failures flow to the error stream and leave $Session null),
    // then Get-CimInstance -CimSession $Session (a null session is a terminating binding error).
    // Terminating errors propagate to the caller's catch -> Stop-Function "... via DCom". The
    // session is never removed, matching the PS source.
    private object? GetDtcServiceViaDcom(string computer)
    {
        object? sessionOption = null;
        using (PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace))
        {
            shell.AddCommand("New-CimSessionOption").AddParameter("Protocol", "Dcom");
            foreach (PSObject item in shell.Invoke())
            {
                if (item is not null)
                {
                    sessionOption = item.BaseObject;
                    break;
                }
            }
        }

        object? session = null;
        using (PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace))
        {
            shell.AddCommand("New-CimSession")
                .AddParameter("ComputerName", computer)
                .AddParameter("SessionOption", sessionOption);
            ForwardVerboseSwitch(shell);
            foreach (PSObject item in shell.Invoke())
            {
                if (item is not null)
                {
                    session = item.BaseObject;
                    break;
                }
            }
            ReemitNestedStreams(shell);
        }

        using (PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace))
        {
            shell.AddCommand("Get-CimInstance")
                .AddParameter("CimSession", session)
                .AddParameter("Query", Query);
            ForwardVerboseSwitch(shell);
            List<PSObject> output = new();
            foreach (PSObject item in shell.Invoke())
            {
                if (item is not null)
                {
                    output.Add(item);
                }
            }
            ReemitNestedStreams(shell);
            return ShapeOutput(output);
        }
    }

    // PS: Invoke-Command2 -ComputerName $computer -ScriptBlock $block -Credential $Credential -
    // cooked (no -Raw), no -ErrorAction Stop: non-terminating remote errors flow to the caller's
    // error stream WITHOUT tripping the try/catch; only terminating failures (session creation)
    // throw out of RemoteExecutionService into the caller's catch.
    private object? InvokeCommand2(string computer, string scriptText)
    {
        RemoteExecutionService.RemoteCommandRequest request = new()
        {
            ComputerName = new DbaInstanceParameter(computer),
            Credential = Credential,
            ScriptText = scriptText
        };
        RemoteExecutionService.RemoteCommandResult result = RemoteExecutionService.InvokeCommand(this, request);
        foreach (ErrorRecord error in result.Errors)
        {
            WriteError(NestedCommand.PreserveErrorIdentity(error));
        }
        return ShapeOutput(result.Output);
    }

    // PS: [PSCustomObject]@{ ... } with 18 literal properties in declaration order.
    private static PSObject BuildOutput(object dtcservice, object? reg, Hashtable cidHash)
    {
        PSObject result = new();
        result.Properties.Add(new PSNoteProperty("ComputerName", GetMemberValue(dtcservice, "PSComputerName")));
        result.Properties.Add(new PSNoteProperty("DTCServiceName", GetMemberValue(dtcservice, "DisplayName")));
        result.Properties.Add(new PSNoteProperty("DTCServiceState", GetMemberValue(dtcservice, "State")));
        result.Properties.Add(new PSNoteProperty("DTCServiceStatus", GetMemberValue(dtcservice, "Status")));
        result.Properties.Add(new PSNoteProperty("DTCServiceStartMode", GetMemberValue(dtcservice, "StartMode")));
        result.Properties.Add(new PSNoteProperty("DTCServiceAccount", GetMemberValue(dtcservice, "StartName")));
        result.Properties.Add(new PSNoteProperty("DTCCID_MSDTC", cidHash["MSDTC"]));
        result.Properties.Add(new PSNoteProperty("DTCCID_MSDTCUIS", cidHash["MSDTCUIS"]));
        result.Properties.Add(new PSNoteProperty("DTCCID_MSDTCTIPGW", cidHash["MSDTCTIPGW"]));
        result.Properties.Add(new PSNoteProperty("DTCCID_MSDTCXATM", cidHash["MSDTCXATM"]));
        result.Properties.Add(new PSNoteProperty("networkDTCAccess", GetMemberValue(reg, "networkDTCAccess")));
        result.Properties.Add(new PSNoteProperty("networkDTCAccessAdmin", GetMemberValue(reg, "networkDTCAccessAdmin")));
        result.Properties.Add(new PSNoteProperty("networkDTCAccessClients", GetMemberValue(reg, "networkDTCAccessClients")));
        result.Properties.Add(new PSNoteProperty("networkDTCAccessInbound", GetMemberValue(reg, "networkDTCAccessInbound")));
        result.Properties.Add(new PSNoteProperty("networkDTCAccessOutBound", GetMemberValue(reg, "networkDTCAccessOutBound")));
        result.Properties.Add(new PSNoteProperty("networkDTCAccessTip", GetMemberValue(reg, "networkDTCAccessTip")));
        result.Properties.Add(new PSNoteProperty("networkDTCAccessTransactions", GetMemberValue(reg, "networkDTCAccessTransactions")));
        result.Properties.Add(new PSNoteProperty("XATransactions", GetMemberValue(reg, "XATransactions")));
        return result;
    }

    // Engine CIM cmdlets only generate their "Perform operation ..." verbose records when they see
    // -Verbose; a nested pipeline does not inherit the outer cmdlet's bound switch, so forward it.
    private void ForwardVerboseSwitch(PowerShell shell)
    {
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out object? verbose) && LanguagePrimitives.IsTrue(verbose))
        {
            shell.AddParameter("Verbose", true);
        }
    }

    // A nested pipeline buffers stream records instead of surfacing them; re-emit through THIS
    // cmdlet's channels so verbose/warning/error output lands exactly where the PS function's did.
    private void ReemitNestedStreams(PowerShell shell)
    {
        foreach (VerboseRecord record in shell.Streams.Verbose)
        {
            WriteVerbose(record.Message);
        }
        foreach (WarningRecord record in shell.Streams.Warning)
        {
            WriteWarning(record.Message);
        }
        foreach (ErrorRecord record in shell.Streams.Error)
        {
            WriteError(NestedCommand.PreserveErrorIdentity(record));
        }
        shell.Streams.ClearStreams();
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

    // PS: foreach ($key in $cids) - a scalar iterates once, an array element-wise.
    private static IEnumerable<object> EnumeratePipeline(object value)
    {
        if (value is object[] many)
        {
            foreach (object item in many)
            {
                if (item is not null)
                {
                    yield return item;
                }
            }
        }
        else
        {
            yield return value;
        }
    }

    // PS unwraps PSObject method arguments to their base object before a .NET call; deserialized
    // and Select-Object-projected property values arrive PSObject-wrapped, so mirror the binder.
    private static object? UnwrapForMethodCall(object? value)
    {
        if (value is PSObject wrapped)
        {
            return wrapped.BaseObject;
        }
        return value;
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
