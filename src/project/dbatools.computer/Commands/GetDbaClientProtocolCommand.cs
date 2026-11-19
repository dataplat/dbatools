#nullable enable

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Management.Automation.Runspaces;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Management.Infrastructure;
using Microsoft.Management.Infrastructure.Options;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Server client network protocol configuration and status from local or remote computers.
/// </summary>
/// <para>
/// Retrieves the configuration and status of SQL Server client network protocols (Named Pipes, TCP/IP, Shared Memory, VIA) from local or remote computers. This function helps DBAs audit and troubleshoot client connectivity issues by showing which protocols are enabled, their order of precedence, and associated DLL files.
/// </para>
/// <para>
/// The returned objects include Enable() and Disable() methods, allowing you to modify protocol settings directly without opening SQL Server Configuration Manager. This is particularly useful for standardizing client configurations across multiple servers or troubleshooting connectivity problems.
/// </para>
/// <para>
/// Requires Local Admin rights on destination computer(s) and SQL Server 2005 or later.
/// The client protocols can be enabled and disabled when retrieved via WSMan.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaClientProtocol -ComputerName sqlserver2014a
/// </code>
/// <para>
/// Gets the SQL Server related client protocols on computer sqlserver2014a.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'sql1','sql2','sql3' | Get-DbaClientProtocol
/// </code>
/// <para>
/// Gets the SQL Server related client protocols on computers sql1, sql2 and sql3.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaClientProtocol -ComputerName sql1,sql2 | Out-GridView
/// </code>
/// <para>
/// Gets the SQL Server related client protocols on computers sql1 and sql2, and shows them in a grid view.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; (Get-DbaClientProtocol -ComputerName sql2 | Where-Object { $_.DisplayName -eq 'Named Pipes' }).Disable()
/// </code>
/// <para>
/// Disables the VIA ClientNetworkProtocol on computer sql2.
/// If successful, return code 0 is shown.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Management, Protocol, OS
/// Author: Klaas Vandenberghe (@PowerDBAKlaas)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaClientProtocol" />
[Cmdlet(VerbsCommon.Get, "DbaClientProtocol")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaClientProtocolCommand : DbaBaseCmdlet
{
    /// <para>
    /// Specifies the target computer(s) to retrieve SQL Server client protocol configuration from. Accepts computer names, IP addresses, or SQL Server instance names.
    /// Use this when you need to audit client protocol settings on remote servers or troubleshoot connectivity issues across multiple machines.
    /// Defaults to the local computer if not specified.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [Alias("cn", "host", "Server")]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <para>
    /// Credential object used to connect to the computer as a different user.
    /// </para>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

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

        // The Enable()/Disable() methods of the returned protocols read the caller's preferences through this runspace's engine.
        RegisterRunspaceEngine(SessionState.PSVariable.GetValue("ExecutionContext") as EngineIntrinsics);

        // PS: foreach ($computer in $ComputerName.ComputerName) — the loop value is the
        // bare host-name string; the "Failed to connect" message below uses it as it was
        // BEFORE the FullComputerName reassignment inside the success branch.
        foreach (DbaInstanceParameter computer in ComputerName)
        {
            // PS member enumeration ($ComputerName.ComputerName) skips null array slots.
            if (computer is null)
            {
                continue;
            }
            string originalName = computer.ComputerName;

            // PS: $server = Resolve-DbaNetworkName -ComputerName $computer -Credential $credential
            // (no EnableException forwarded): a DNS failure is Resolve-DbaNetworkName's own
            // Stop-Function -Continue, its "DNS name ... not found" warning and its record in $error,
            // whatever this command's -EnableException, plus a null result; nothing throws (pin
            // probe 236550ae, case S1, all four call modes, both editions). NetworkResolutionService.Resolve
            // returns null on that same path, so the nested Stop-Function is written here.
            NetworkResolutionService.NetworkResolutionResult? resolution = null;
            string dnsProbeName = computer.IsLocalHost ? Environment.MachineName : computer.ComputerName;
            bool resolveWarned = false;
            try
            {
                resolution = NetworkResolutionService.Resolve(this, new DbaInstanceParameter(computer.ComputerName), Credential, turbo: false);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                resolveWarned = true;
                WarnNestedStopFunction("Resolve-DbaNetworkName", "DNS name " + dnsProbeName + " not found", errorRecord: new ErrorRecord(ex, ex.GetType().Name, ErrorCategory.NotSpecified, null));
            }
            if (resolution is null && !resolveWarned)
            {
                // PS: Stop-Function -Message "DNS name $cName not found" -Continue -ErrorRecord $_,
                // where $_ is the failed [System.Net.Dns]::GetHostEntry($cName) call, so the warning
                // ends with " | " and the DNS exception's message.
                WarnNestedStopFunction("Resolve-DbaNetworkName", "DNS name " + dnsProbeName + " not found", errorRecord: GetDnsFailure(dnsProbeName));
            }

            string? computerResolved = resolution?.FullComputerName;

            // PS: if ($server.FullComputerName) { ... } else { "Failed to connect to $computer" }
            if (string.IsNullOrEmpty(computerResolved))
            {
                WriteMessage(MessageLevel.Warning, "Failed to connect to " + originalName);
                continue;
            }

            // PS: $computer = $server.FullComputerName — every subsequent message uses the full name.
            WriteMessage(MessageLevel.Verbose, "Getting SQL Server namespace on " + computerResolved);

            // PS: Get-DbaCmObject -Namespace root\Microsoft\SQLServer -Query "..." -ErrorAction
            // SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
            List<PSObject> namespaces = QueryNamespaces(computerResolved!);
            string? namespaceName = SelectHighestNamespaceName(namespaces);

            // PS: if ($namespace.Name) { ... } else { "No ComputerManagement Namespace ..." }
            if (!string.IsNullOrEmpty(namespaceName))
            {
                WriteMessage(MessageLevel.Verbose, "Getting Cim class ClientNetworkProtocol in Namespace " + namespaceName + " on " + computerResolved);
                try
                {
                    // PS: $prot = Get-DbaCmObject -Namespace ("root\Microsoft\SQLServer\" + name)
                    //     -ClassName ClientNetworkProtocol -ErrorAction SilentlyContinue
                    // A chain failure warns (the exact composed message) and returns nothing WITHOUT
                    // throwing (non-EnableException Stop-Function), so the catch below never fires for it.
                    List<PSObject>? protocols = ReadProtocols(computerResolved!, @"root\Microsoft\SQLServer\" + namespaceName);
                    if (protocols is null)
                    {
                        continue;
                    }

                    // Correction: -ErrorAction SilentlyContinue keeps the pin's catch from running, so
                    // a read that returned no rows (SQL Server 2022 ships no SQL Native Client) wrote
                    // no object and no message. It writes the warning that catch was there to give.
                    if (protocols.Count == 0)
                    {
                        WriteMessage(MessageLevel.Warning, "No Sql ClientNetworkProtocol found on " + computerResolved);
                        continue;
                    }

                    foreach (PSObject protocol in protocols)
                    {
                        // PS: $prot | Add-Member -Force ScriptProperty IsEnabled + ScriptMethod
                        // Enable/Disable; the returned objects keep a live IsEnabled and working
                        // Enable()/Disable() methods.
                        AddProtocolMembers(protocol);

                        // PS: Select-DefaultView -InputObject $protocol -Property
                        //   'PSComputerName as ComputerName', 'ProtocolDisplayName as DisplayName',
                        //   'ProtocolDll as DLL', 'ProtocolOrder as Order', 'IsEnabled'
                        OutputHelper.AddAliasProperty(protocol, "ComputerName", "PSComputerName");
                        OutputHelper.AddAliasProperty(protocol, "DisplayName", "ProtocolDisplayName");
                        OutputHelper.AddAliasProperty(protocol, "DLL", "ProtocolDll");
                        OutputHelper.AddAliasProperty(protocol, "Order", "ProtocolOrder");
                        OutputHelper.SetDefaultDisplayPropertySet(protocol, "ComputerName", "DisplayName", "DLL", "Order", "IsEnabled");
                        WriteObject(protocol);
                    }
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch
                {
                    // PS: catch { Write-Message -Level Warning -Message "No Sql ClientNetworkProtocol found on $computer" }
                    WriteMessage(MessageLevel.Warning, "No Sql ClientNetworkProtocol found on " + computerResolved);
                }
            }
            else
            {
                // PS: Write-Message -Level Warning -Message "No ComputerManagement Namespace on $computer. Please note that this function is available from SQL 2005 up."
                WriteMessage(MessageLevel.Warning, "No ComputerManagement Namespace on " + computerResolved + ". Please note that this function is available from SQL 2005 up.");
            }
        }
    }

    // PS: Get-DbaCmObject -Namespace root\Microsoft\SQLServer -Query "..." -ErrorAction
    // SilentlyContinue | Sort-Object ..., with NO -EnableException. Empty after a failure, which
    // has already warned (see ReadCmObject).
    private List<PSObject> QueryNamespaces(string computerResolved)
    {
        return ReadCmObject(computerResolved, @"root\Microsoft\SQLServer", "Select * FROM __NAMESPACE WHERE Name LIke 'ComputerManagement%'", null)
            ?? new List<PSObject>();
    }

    // PS: Get-DbaCmObject -Namespace <root\Microsoft\SQLServer\ComputerManagementNN>
    // -ClassName ClientNetworkProtocol -ErrorAction SilentlyContinue, NO -EnableException.
    // Null after a failure, which has already warned; an empty list is a read that returned no rows.
    private List<PSObject>? ReadProtocols(string computerResolved, string cimNamespace)
    {
        return ReadCmObject(computerResolved, cimNamespace, null, "ClientNetworkProtocol");
    }

    // PS: Get-DbaCmObject -ComputerName $computer -Namespace ... (-Query | -ClassName) -ErrorAction SilentlyContinue, without
    // -EnableException. The parameter binds the resolved name. A run that gives up ends in the nested Stop-Function -Continue:
    // its warning under Get-DbaCmObject's name and its record in $error, whatever this command's -EnableException, and no
    // object; nothing throws, so a caller's try, -EnableException and -ErrorAction Stop catch nothing (pin probes 236550ae,
    // case S2, the namespace query, and 86cfbcd7, case S3, the ClientNetworkProtocol read; all four call modes, both editions).
    // CmObjectFailureRecord gives the pin's Stop-Function call for each kind. -ErrorAction SilentlyContinue silences only the
    // PowerShellRemoting-rung passthrough error stream, so the PassthroughErrors are not written. Null after a failure.
    private List<PSObject>? ReadCmObject(string computerResolved, string cimNamespace, string? query, string? className)
    {
        DbaCmConnectionParameter target = new(computerResolved);
        if (!target.Success)
        {
            // The pin prints $connectionObject.Input, a member this type does not have, so the text ends after the colon.
            WarnNestedStopFunction("Get-DbaCmObject", "Failed to interpret input: ", category: ErrorCategory.InvalidArgument);
            return null;
        }

        string name = target.Connection.ComputerName.ToLowerInvariant();
        ManagementConnectionType lastRung = ManagementConnectionType.None;
        CimService.CmObjectFailure? failure = null;
        CimService.CmObjectRequest request = new()
        {
            ComputerName = name,
            Namespace = cimNamespace,
            Query = query,
            ClassName = className,
            // Correction: the pin passed -Credential only to Resolve-DbaNetworkName, so both
            // SQL WMI reads ran as the current user and ignored the documented Credential.
            // They connect with it, as Get-DbaInstanceProtocol's reads do.
            Credential = Credential,
            Observer = new CimService.CmObjectObserver
            {
                Rung = (rung, step, error) => lastRung = rung,
                Failure = reported => failure = reported
            }
        };

        try
        {
            CimService.CmObjectResult result = CimService.GetCmObject(this, request);
            return result.Instances;
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            CmObjectFailureRecord? report = failure is null ? null : CmObjectFailureRecord.Build(failure, target.Connection, name, lastRung, className is not null, className!, cimNamespace);
            if (report is null)
            {
                WriteNestedWarning("Get-DbaCmObject", ex.Message, ex);
                return null;
            }

            WarnNestedStopFunction("Get-DbaCmObject", report.Message, report.Target, report.Record, report.Category, report.OverrideExceptionMessage);
            return null;
        }
    }

    // PS: | Sort-Object Name -Descending | Select-Object -First 1  then  $namespace.Name.
    // Descending order over the __NAMESPACE Name property picks the highest ComputerManagement<NN>
    // (newest SQL). Sort-Object's default comparer is CASE-INSENSITIVE, so use OrdinalIgnoreCase
    // (codex parity fix 2026-07-10: a mixed-case namespace pair would have flipped an Ordinal
    // compare).
    private static string? SelectHighestNamespaceName(List<PSObject> namespaces)
    {
        string? best = null;
        foreach (PSObject ns in namespaces)
        {
            string? name = ns.Properties["Name"]?.Value?.ToString();
            if (name is null)
            {
                continue;
            }
            if (best is null || string.Compare(name, best, StringComparison.OrdinalIgnoreCase) > 0)
            {
                best = name;
            }
        }
        return best;
    }

    // PS Add-Member -Force per protocol: replace any same-named member, then attach IsEnabled and
    // the Enable/Disable methods. They are code members here: the property stays live (it reads
    // ProtocolOrder when asked, as the script property did) and the methods call the WMI method
    // on the protocol's own computer. ClientNetworkProtocol carries no native member of these
    // names, so the -Force remove is a no-op in practice; it is kept for parity.
    private static void AddProtocolMembers(PSObject protocol)
    {
        protocol.Members.Remove("IsEnabled");
        protocol.Properties.Add(new PSCodeProperty("IsEnabled",
            ((Func<PSObject, bool>)GetProtocolIsEnabled).Method));

        protocol.Members.Remove("Enable");
        protocol.Methods.Add(new PSCodeMethod("Enable",
            ((Func<PSObject, PSObject?>)EnableProtocol).Method));

        protocol.Members.Remove("Disable");
        protocol.Methods.Add(new PSCodeMethod("Disable",
            ((Func<PSObject, PSObject?>)DisableProtocol).Method));
    }

    /// <summary>
    /// The IsEnabled property of each returned protocol: false when ProtocolOrder is 0, true otherwise.
    /// </summary>
    /// <param name="instance">The protocol object.</param>
    /// <returns>Whether the protocol is enabled.</returns>
    public static bool GetProtocolIsEnabled(PSObject instance)
    {
        // PS: switch ( $this.ProtocolOrder ) { 0 { $false } default { $true } }
        // The switch compares with -eq, the value on the left, so a missing or null order is
        // "default" (true) and the constant converts to the value's own type.
        object? order = instance.Properties["ProtocolOrder"]?.Value;
        if (order is null)
        {
            return true;
        }
        return !LanguagePrimitives.Equals(order, 0, true, CultureInfo.InvariantCulture);
    }

    /// <summary>
    /// The Enable() method of each returned protocol: calls the WMI SetEnable method.
    /// </summary>
    /// <param name="instance">The protocol object.</param>
    /// <returns>The method result, with ReturnValue and PSComputerName; null when WhatIf or a declined confirmation skips it.</returns>
    /// <exception cref="PSInvalidOperationException">Called where the caller's WhatIf and Confirm preferences cannot be read: a runspace Get-DbaClientProtocol has not run in. Nothing changes.</exception>
    public static PSObject? EnableProtocol(PSObject instance)
    {
        // PS: { Invoke-CimMethod -MethodName SetEnable -InputObject $this }
        return InvokeProtocolMethod(instance, "Enable", "SetEnable");
    }

    /// <summary>
    /// The Disable() method of each returned protocol: calls the WMI SetDisable method.
    /// </summary>
    /// <param name="instance">The protocol object.</param>
    /// <returns>The method result, with ReturnValue and PSComputerName; null when WhatIf or a declined confirmation skips it.</returns>
    /// <exception cref="PSInvalidOperationException">Called where the caller's WhatIf and Confirm preferences cannot be read: a runspace Get-DbaClientProtocol has not run in. Nothing changes.</exception>
    public static PSObject? DisableProtocol(PSObject instance)
    {
        // PS: { Invoke-CimMethod -MethodName SetDisable -InputObject $this }
        return InvokeProtocolMethod(instance, "Disable", "SetDisable");
    }

    // Invoke-CimMethod -InputObject with neither -CimSession nor -ComputerName opens a new session
    // to the instance's own CIM session computer (WSMan, current user; DCOM when the name is
    // empty), invokes the method in the instance's namespace and writes one object per result:
    // a note property per out parameter (ReturnValue among them), PSComputerName from the
    // session, and the CimMethodResult type names. Before the call it asks ShouldProcess with
    // Invoke-CimMethod's target (the instance's ToString()) and action ("Invoke-CimMethod: <method>"),
    // so WhatIf and a declined confirmation write nothing and change nothing.
    private static PSObject? InvokeProtocolMethod(PSObject instance, string memberName, string methodName)
    {
        if (!(instance.BaseObject is CimInstance cimInstance))
        {
            // Invoke-CimMethod's -InputObject binds only a CIM instance; an object from
            // Get-DbaCmObject's WMI rung has none to call.
            throw new PSArgumentException("The protocol object is not a CIM instance, so " + methodName + " cannot be invoked on it.", "InputObject");
        }

        // The caller's preferences come from the runspace the method is called in. Where they cannot be read
        // (a thread with no runspace, or a runspace Get-DbaClientProtocol never ran in, such as one a copy of
        // the object was handed to), the method refuses before it opens a session: it never acts as if the
        // default preferences applied.
        EngineIntrinsics? engine = FindRunspaceEngine();
        if (engine is null)
        {
            throw new PSInvalidOperationException(memberName + "() changed nothing: the caller's WhatIf and Confirm preferences cannot be read here, because Get-DbaClientProtocol has not run in this runspace. Call " + memberName + "() on a protocol Get-DbaClientProtocol returned in the runspace that calls it.");
        }

        string? sessionComputer = cimInstance.GetCimSessionComputerName();
        bool defaultComputer = string.IsNullOrEmpty(sessionComputer);
        CimSessionOptions options = defaultComputer ? new DComSessionOptions() : new WSManSessionOptions();
        using CimSession session = CimSession.Create(defaultComputer ? null : sessionComputer, options);

        if (!ShouldInvokeProtocolMethod(engine, cimInstance.ToString(), string.Format(CultureInfo.CurrentUICulture, "Invoke-CimMethod: {0}", methodName)))
        {
            return null;
        }

        using CimMethodParametersCollection parameters = new CimMethodParametersCollection();
        using CimMethodResult result = session.InvokeMethod(cimInstance.CimSystemProperties.Namespace, cimInstance, methodName, parameters);

        PSObject output = new PSObject();
        foreach (CimMethodParameter parameter in result.OutParameters)
        {
            output.Properties.Add(new PSNoteProperty(parameter.Name, parameter.Value));
        }
        output.Properties.Add(new PSNoteProperty("PSComputerName", session.ComputerName));
        output.TypeNames.Insert(0, "Microsoft.Management.Infrastructure.CimMethodResult");
        output.TypeNames.Insert(0, "Microsoft.Management.Infrastructure.CimMethodResult#" + cimInstance.CimSystemProperties.ClassName + "#" + methodName);
        return output;
    }

    // The engine intrinsics ($ExecutionContext) of each runspace Get-DbaClientProtocol ran in, by runspace id. Weak, so a
    // closed runspace is not kept alive; dead entries are dropped when another call registers.
    private static readonly Dictionary<Guid, WeakReference<EngineIntrinsics>> RunspaceEngines = new Dictionary<Guid, WeakReference<EngineIntrinsics>>();

    private static void RegisterRunspaceEngine(EngineIntrinsics? engine)
    {
        // Qualified: Dataplat.Dbatools.Runspace is a namespace, which the bare name would resolve to here.
        Guid? runspaceId = System.Management.Automation.Runspaces.Runspace.DefaultRunspace?.InstanceId;
        if (engine is null || runspaceId is null)
        {
            return;
        }

        lock (RunspaceEngines)
        {
            List<Guid> closed = new List<Guid>();
            foreach (KeyValuePair<Guid, WeakReference<EngineIntrinsics>> entry in RunspaceEngines)
            {
                if (!entry.Value.TryGetTarget(out _))
                {
                    closed.Add(entry.Key);
                }
            }
            foreach (Guid id in closed)
            {
                RunspaceEngines.Remove(id);
            }
            RunspaceEngines[runspaceId.Value] = new WeakReference<EngineIntrinsics>(engine);
        }
    }

    // The engine of the runspace whose pipeline thread calls the method, or null when the thread has no runspace or
    // Get-DbaClientProtocol never ran in it.
    private static EngineIntrinsics? FindRunspaceEngine()
    {
        Guid? runspaceId = System.Management.Automation.Runspaces.Runspace.DefaultRunspace?.InstanceId;
        if (runspaceId is null)
        {
            return null;
        }

        lock (RunspaceEngines)
        {
            if (RunspaceEngines.TryGetValue(runspaceId.Value, out WeakReference<EngineIntrinsics>? reference) && reference.TryGetTarget(out EngineIntrinsics? engine))
            {
                return engine;
            }
        }
        return null;
    }

    // Invoke-CimMethod is SupportsShouldProcess with the default ConfirmImpact, Medium. Its ShouldProcess
    // (MshCommandRuntime.DoShouldProcess): under $WhatIfPreference it writes "What if: <description>" to the
    // host and skips the call; otherwise it goes on without asking unless $ConfirmPreference is Medium or
    // Low, and then asks Yes, Yes to All, No, No to All (and Suspend outside a remote host). A method call
    // takes no -WhatIf or -Confirm, so only the two preferences count. They are read when the method is
    // called, through the engine's current session state from the calling scope outwards, as a compiled
    // command called there reads them; the What if line and the question go to that runspace's host. A copy
    // of a protocol (PSObject.Copy() clones the CIM instance on Windows PowerShell) is read the same way.
    private static bool ShouldInvokeProtocolMethod(EngineIntrinsics engine, string target, string action)
    {
        SessionState state = engine.SessionState;
        PSHost host = engine.Host;
        string description = string.Format(CultureInfo.CurrentUICulture, "Performing the operation \"{0}\" on target \"{1}\".", action, target);
        // ShouldProcess writes its What if line and asks its question through the host itself, not a
        // message stream, so the port does the same; WriteMessage would change where the line goes.
        PSHostUserInterface ui = host.UI;
        if (ReadWhatIfPreference(state))
        {
            ui.WriteLine("What if: " + description);
            return false;
        }

        ConfirmImpact threshold = ReadConfirmPreference(state);
        if (threshold == ConfirmImpact.None || threshold > ConfirmImpact.Medium)
        {
            return true;
        }

        // The engine's ShouldProcessWarningFallback text and its InquireHelper choices, both editions.
        string message = "Are you sure you want to perform this action?\r\n" + description;
        Collection<ChoiceDescription> choices = new Collection<ChoiceDescription>
        {
            new ChoiceDescription("&Yes", "Continue with only the next step of the operation."),
            new ChoiceDescription("Yes to &All", "Continue with all the steps of the operation."),
            new ChoiceDescription("&No", "Skip this operation and proceed with the next operation."),
            new ChoiceDescription("No to A&ll", "Skip this operation and all subsequent operations."),
        };
        bool allowSuspend = !string.Equals(host.Name, "ServerRemoteHost", StringComparison.Ordinal);
        if (allowSuspend)
        {
            choices.Add(new ChoiceDescription("&Suspend", "Pause the current pipeline and return to the command prompt. Type \"exit\" to resume the pipeline."));
        }

        while (true)
        {
            int response = ui.PromptForChoice("Confirm", message, choices, 0);
            switch (response)
            {
                case 0:
                case 1:
                    return true;
                case 2:
                case 3:
                    return false;
                default:
                    // Suspend: a nested prompt; the question comes back when the user exits it.
                    host.EnterNestedPrompt();
                    break;
            }
        }
    }

    // ExecutionContext.GetBooleanPreference: a null or unconvertible value is the default, false.
    private static bool ReadWhatIfPreference(SessionState state)
    {
        object? value = state.PSVariable.GetValue("WhatIfPreference");
        if (value is null)
        {
            return false;
        }
        return LanguagePrimitives.TryConvertTo(value, out bool whatIf) && whatIf;
    }

    // ExecutionContext.GetEnumPreference: the enum itself, a name parsed ignoring case, or the default, High.
    private static ConfirmImpact ReadConfirmPreference(SessionState state)
    {
        object? value = state.PSVariable.GetValue("ConfirmPreference");
        if (value is ConfirmImpact impact)
        {
            return impact;
        }
        if (value is string text)
        {
            return Enum.TryParse(text, true, out ConfirmImpact parsed) ? parsed : ConfirmImpact.High;
        }
        if (value is PSObject wrapped && wrapped.BaseObject is ConfirmImpact unwrapped)
        {
            return unwrapped;
        }
        return ConfirmImpact.High;
    }

    // NetworkResolutionService.Resolve returns null on a DNS failure without the error, so look
    // the name up once more for it. Stop-Function words the warning with Get-ErrorMessage, the
    // deepest message of the caught GetHostEntry call: the DNS exception's own message. Its record
    // holds the pin's method-call wrapper over the DNS exception (pin probe 236550ae, case S1:
    // 'Exception calling "GetHostEntry" with "1" argument(s): ...' over SocketException). Null when
    // the second lookup succeeds, and then the warning carries the bare message.
    private static ErrorRecord? GetDnsFailure(string name)
    {
        try
        {
            System.Net.Dns.GetHostEntry(name);
            return null;
        }
        catch (Exception ex)
        {
            string text = String.Format(CultureInfo.InvariantCulture, "Exception calling \"GetHostEntry\" with \"1\" argument(s): \"{0}\"", ex.Message);
            return new ErrorRecord(new MethodInvocationException(text, ex), ex.GetType().Name, ErrorCategory.NotSpecified, null);
        }
    }

    // A Get-DbaCmObject failure the observer did not report: the nested command's warning under its
    // own name, without a record, whatever this command's -EnableException says.
    private void WriteNestedWarning(string functionName, string message, Exception? exception)
    {
        MessageService.Write(this, new MessageService.MessageRequest
        {
            FunctionName = functionName,
            ModuleName = "dbatools",
            Level = MessageLevel.Warning,
            Message = message,
            Exception = exception,
            EnableException = false,
            File = MyInvocation.ScriptName,
            Line = MyInvocation.ScriptLineNumber
        });
    }

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
