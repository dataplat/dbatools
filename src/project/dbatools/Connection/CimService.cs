using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Management.Automation.Remoting;
using System.Management.Automation.Runspaces;
using System.Runtime.InteropServices;
using Microsoft.Management.Infrastructure;
using Microsoft.Management.Infrastructure.Options;
using Dataplat.Dbatools.Configuration;

namespace Dataplat.Dbatools.Connection
{
    /// <summary>
    /// Compiled equivalent of public/Get-DbaCmObject.ps1 for ported computer-management
    /// commands. GetCmObject walks the full CimRM -> CimDCOM -> Wmi -> PowerShellRemoting
    /// protocol chain (Wave 5; the interim two-rung EnumerateInstances was retired when
    /// its consumers moved over). Drives the same ManagementConnection / ConnectionHost
    /// machinery the PS command uses, so protocol state, credential caches and CIM
    /// session reuse remain shared between the PS and compiled halves during the hybrid
    /// period.
    /// </summary>
    public static class CimService
    {
        /// <summary>
        /// The Get-DbaCmObject parameter surface for one computer. Exactly one of
        /// ClassName/Query is set (the PS parameter sets); Namespace null means the
        /// root\cimv2 default AND "not explicitly bound", which the Wmi/PowerShellRemoting
        /// rungs distinguish when composing their fallback calls.
        /// </summary>
        public sealed class CmObjectRequest
        {
            /// <summary>The target computer name.</summary>
            public string ComputerName;

            /// <summary>Optional explicit credential; null = integrated auth.</summary>
            public PSCredential Credential;

            /// <summary>The CIM/WMI class to enumerate (Class parameter set).</summary>
            public string ClassName;

            /// <summary>The WQL query to run (Query parameter set).</summary>
            public string Query;

            /// <summary>The namespace when explicitly bound; null = root\cimv2 default.</summary>
            public string Namespace;

            /// <summary>Protocols excluded up front (the -DoNotUse parameter).</summary>
            public ManagementConnectionType DoNotUse = ManagementConnectionType.None;

            /// <summary>Overrides the timeout on connections known to be bad (the -Force parameter).</summary>
            public bool Force;

            /// <summary>Optional: sees the run as it goes. Null changes nothing and calls nothing.</summary>
            public CmObjectObserver Observer;
        }

        /// <summary>The steps of one protocol rung an observer of GetCmObject sees.</summary>
        public enum CmObjectRungStep
        {
            /// <summary>The rung is about to be tried.</summary>
            Started,

            /// <summary>The rung returned its output.</summary>
            Succeeded,

            /// <summary>The rung failed; the error is the original exception, when there is one.</summary>
            Failed
        }

        /// <summary>Why GetCmObject gave up on a computer, from the failing condition itself.</summary>
        public enum CmObjectFailureKind
        {
            /// <summary>The connection refused the credential before any rung ran.</summary>
            Credential,

            /// <summary>No rung is left to try.</summary>
            NoConnection,

            /// <summary>A CIM rung rejected the credential.</summary>
            CimBadCredentials,

            /// <summary>A CIM rung failed in a way another protocol cannot help.</summary>
            CimError,

            /// <summary>The WMI rung rejected the credential.</summary>
            WmiBadCredentials,

            /// <summary>The WMI rung found no such class.</summary>
            WmiInvalidClass,

            /// <summary>The WMI rung hit a provider load failure.</summary>
            WmiProviderLoad
        }

        /// <summary>The failure GetCmObject reports to its observer just before it throws.</summary>
        public sealed class CmObjectFailure
        {
            /// <summary>What went wrong.</summary>
            public CmObjectFailureKind Kind;

            /// <summary>The original exception.</summary>
            public Exception Error;

            /// <summary>CimError: the triage message. Credential: the composed text, up to the exception's message.</summary>
            public string Message;

            /// <summary>NoConnection: the protocols the connection had enabled when the run began.</summary>
            public ManagementConnectionType EnabledProtocols;

            /// <summary>WmiInvalidClass: the class the rung looked for, also when a query named it.</summary>
            public string ClassName;
        }

        /// <summary>
        /// Lets a caller follow one GetCmObject run: each rung step, each object as it arrives, and the
        /// typed failure behind the exception it then throws. Every member is optional.
        /// </summary>
        public sealed class CmObjectObserver
        {
            /// <summary>Called for each rung step, with the rung and, on Failed, the original exception.</summary>
            public Action<ManagementConnectionType, CmObjectRungStep, Exception> Rung;

            /// <summary>Takes each object as it arrives instead of the result's Instances.</summary>
            public Action<PSObject> Output;

            /// <summary>Called once, just before GetCmObject throws for this failure.</summary>
            public Action<CmObjectFailure> Failure;
        }

        /// <summary>
        /// What a protocol-chain run produced. PassthroughErrors carries non-terminating
        /// errors of a PowerShellRemoting-rung run - the PS source let those flow to the
        /// caller's error stream while still reporting the rung a SUCCESS, so callers
        /// re-emit them and process the (possibly empty) output normally.
        /// </summary>
        public sealed class CmObjectResult
        {
            /// <summary>The instances the winning protocol produced, PSObject-wrapped.</summary>
            public List<PSObject> Instances = new List<PSObject>();

            /// <summary>Non-terminating errors surfaced by the PowerShellRemoting rung.</summary>
            public List<ErrorRecord> PassthroughErrors = new List<ErrorRecord>();
        }

        /// <summary>
        /// The Get-CimAssociatedInstance parameter surface for one CIM source instance.
        /// Used by GetAssociatedCmObjects to traverse CIM/WMI associations (equivalent
        /// to the PS pipe: $instance | Get-CimAssociatedInstance -ResultClassName X).
        /// </summary>
        public sealed class CmAssociationRequest
        {
            /// <summary>The target computer name (same as CmObjectRequest).</summary>
            public string ComputerName;

            /// <summary>Optional explicit credential; null = integrated auth.</summary>
            public PSCredential Credential;

            /// <summary>The source PSObject from a prior GetCmObject call.</summary>
            public PSObject SourceObject;

            /// <summary>The result class to enumerate associations for.</summary>
            public string ResultClassName;

            /// <summary>The namespace (defaults to root\cimv2).</summary>
            public string Namespace;
        }

        /// <summary>
        /// Retrieves instances associated with a source CIM/WMI instance.
        /// Mirrors the PS pipe: $instance | Get-CimAssociatedInstance -ResultClassName X.
        /// Protocol selection follows the source instance type: CimInstance -> CimRM then
        /// CimDCOM; ManagementObject -> WMI GetRelated. Other base types return empty.
        /// </summary>
        /// <param name="request">The association request (computer, credential, source, result class).</param>
        /// <returns>The associated instances, PSObject-wrapped; empty on any failure.</returns>
        public static CmObjectResult GetAssociatedCmObjects(CmAssociationRequest request)
        {
            if (request == null)
                throw new ArgumentNullException("request");
            if (String.IsNullOrWhiteSpace(request.ComputerName))
                throw new ArgumentNullException("request", "ComputerName is required");
            if (request.SourceObject == null)
                throw new ArgumentNullException("request", "SourceObject is required");
            if (String.IsNullOrEmpty(request.ResultClassName))
                throw new ArgumentException("ResultClassName is required", "request");

            string computer = request.ComputerName.ToLowerInvariant();
            string namespaceText = request.Namespace != null ? request.Namespace : @"root\cimv2";

            // CIM path: source is a CimInstance (from CimRM or CimDCOM rung).
            CimInstance sourceCim = request.SourceObject.BaseObject as CimInstance;
            if (sourceCim != null)
            {
                ManagementConnection connection;
                if (!ConnectionHost.Connections.TryGetValue(computer, out connection) || connection == null)
                    connection = new ManagementConnection(computer);

                PSCredential cred;
                try { cred = connection.GetCredential(request.Credential); }
                catch (Exception e) { throw new InvalidOperationException(ComposeBadCredentialMessage(connection, request.Credential, e), e); }

                // ACCEPTED DEVIATION: the PS pipe (Get-CimAssociatedInstance) has no protocol
                // fallback - the CimRM -> CimDCOM ladder below aligns association traversal with
                // the family's GetCmObject rung discipline. On the lab (CimRM answers) behavior
                // is identical to PS; when every rung fails, the failure surfaces through
                // PassthroughErrors like the PS error stream instead of a silent empty result
                // (cross-model review 2026-07-07 finding 2).
                Exception lastAssociationError = null;

                // Try CimRM first.
                if (connection.CimRM != ManagementConnectionProtocolState.Disabled)
                {
                    try
                    {
                        object raw = connection.GetCimRMAssociatedInstances(cred, sourceCim, request.ResultClassName, namespaceText);
                        CmObjectResult result = new CmObjectResult();
                        IEnumerable<CimInstance> sequence = raw as IEnumerable<CimInstance>;
                        if (sequence != null)
                        {
                            foreach (CimInstance instance in sequence)
                                result.Instances.Add(PSObject.AsPSObject(instance));
                        }
                        connection.ReportSuccess(ManagementConnectionType.CimRM);
                        connection.AddGoodCredential(cred);
                        if (!ConnectionHost.DisableCache)
                            ConnectionHost.Connections[computer] = connection;
                        return result;
                    }
                    catch (PipelineStoppedException) { throw; }
                    catch (Exception cimRmError)
                    {
                        lastAssociationError = cimRmError;
                        connection.ReportFailure(ManagementConnectionType.CimRM);
                    }
                }

                // Try CimDCOM as fallback.
                if (connection.CimDCOM != ManagementConnectionProtocolState.Disabled)
                {
                    try
                    {
                        object raw = connection.GetCimDComAssociatedInstances(cred, sourceCim, request.ResultClassName, namespaceText);
                        CmObjectResult result = new CmObjectResult();
                        IEnumerable<CimInstance> sequence = raw as IEnumerable<CimInstance>;
                        if (sequence != null)
                        {
                            foreach (CimInstance instance in sequence)
                                result.Instances.Add(PSObject.AsPSObject(instance));
                        }
                        connection.ReportSuccess(ManagementConnectionType.CimDCOM);
                        connection.AddGoodCredential(cred);
                        if (!ConnectionHost.DisableCache)
                            ConnectionHost.Connections[computer] = connection;
                        return result;
                    }
                    catch (PipelineStoppedException) { throw; }
                    catch (Exception cimDComError)
                    {
                        lastAssociationError = cimDComError;
                    }
                }

                if (!ConnectionHost.DisableCache)
                    ConnectionHost.Connections[computer] = connection;
                CmObjectResult failedResult = new CmObjectResult();
                if (lastAssociationError != null)
                {
                    failedResult.PassthroughErrors.Add(new ErrorRecord(
                        lastAssociationError, "GetAssociatedCmObjects", ErrorCategory.ConnectionError, computer));
                }
                return failedResult;
            }

            // WMI path: source is a ManagementObject (from the WMI rung).
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
#pragma warning disable CA1416
                System.Management.ManagementObject sourceMgmt = request.SourceObject.BaseObject as System.Management.ManagementObject;
                if (sourceMgmt != null)
                {
                    CmObjectResult result = new CmObjectResult();
                    foreach (System.Management.ManagementObject related in sourceMgmt.GetRelated(request.ResultClassName))
                        result.Instances.Add(PSObject.AsPSObject(related));
                    return result;
                }
#pragma warning restore CA1416
            }

            return new CmObjectResult();
        }

        /// <summary>
        /// Retrieves management objects with Get-DbaCmObject's full protocol chain and
        /// cache discipline: rungs are tried in GetConnectionType order, successes and
        /// failures are reported onto the cached ManagementConnection, good/bad
        /// credentials are recorded, and the connection is written back to ConnectionHost
        /// unless caching is disabled.
        /// </summary>
        /// <param name="host">The cmdlet making this request.</param>
        /// <param name="request">The one-computer request (class or query form).</param>
        /// <returns>The winning rung's output; enumeration happens inside the protocol loop so lazy faults are triaged.</returns>
        public static CmObjectResult GetCmObject(PSCmdlet host, CmObjectRequest request)
        {
            if (request == null)
                throw new ArgumentNullException("request");
            if (String.IsNullOrWhiteSpace(request.ComputerName))
                throw new ArgumentNullException("request", "ComputerName is required");
            bool isQuery = !String.IsNullOrEmpty(request.Query);
            if (!isQuery && String.IsNullOrEmpty(request.ClassName))
                throw new ArgumentException("Either ClassName or Query is required", "request");

            // PS: all connection caching runs using lower-case strings.
            string computer = request.ComputerName.ToLowerInvariant();
            string namespaceText = request.Namespace != null ? request.Namespace : @"root\cimv2";

            ManagementConnection connection;
            if (!ConnectionHost.Connections.TryGetValue(computer, out connection) || connection == null)
                connection = new ManagementConnection(computer);

            // PS: New-DbaCimSessionOptionWithTimeout - session options carry the configured
            // operation timeout (ComputerManagement.CimOperationTimeout, fallback 60s).
            TimeSpan operationTimeout = GetConfigTimeSpan("computermanagement.cimoperationtimeout", TimeSpan.FromSeconds(60));
            if (connection.CimWinRMOptions == null)
            {
                WSManSessionOptions wsmanOptions = new WSManSessionOptions();
                wsmanOptions.Timeout = operationTimeout;
                connection.CimWinRMOptions = wsmanOptions;
            }
            if (connection.CimDComOptions == null)
            {
                // Mirror GetDefaultCimDcomOptions/New-CimSessionOption -Protocol Dcom: a raw
                // DComSessionOptions without impersonation/packet settings makes local DCOM
                // enumerations fail with NotFound (verified live 2026-07-06).
                DComSessionOptions dcomOptions = new DComSessionOptions();
                dcomOptions.PacketPrivacy = true;
                dcomOptions.PacketIntegrity = true;
                dcomOptions.Impersonation = ImpersonationType.Impersonate;
                dcomOptions.Timeout = operationTimeout;
                connection.CimDComOptions = dcomOptions;
            }

            // The PS parameter binder caches the connection at bind time, BEFORE the process
            // block runs - so even a run that fails preflight leaves cache state behind.
            // Mirror that here (cross-model review 2026-07-06 finding 2).
            if (!ConnectionHost.DisableCache)
                ConnectionHost.Connections[computer] = connection;

            CmObjectObserver observer = request.Observer;

            PSCredential cred;
            try
            {
                cred = connection.GetCredential(request.Credential);
            }
            catch (Exception e)
            {
                NotifyFailure(observer, new CmObjectFailure { Kind = CmObjectFailureKind.Credential, Error = e, Message = ComposeBadCredentialText(connection, request.Credential) });
                throw new InvalidOperationException(ComposeBadCredentialMessage(connection, request.Credential, e), e);
            }

            // PS: $enabledProtocols computed from the connection state BEFORE the loop,
            // for the exhausted-chain message.
            ManagementConnectionType enabledProtocols = ManagementConnectionType.None;
            if (connection.CimRM != ManagementConnectionProtocolState.Disabled)
                enabledProtocols = enabledProtocols | ManagementConnectionType.CimRM;
            if (connection.CimDCOM != ManagementConnectionProtocolState.Disabled)
                enabledProtocols = enabledProtocols | ManagementConnectionType.CimDCOM;
            if (connection.Wmi != ManagementConnectionProtocolState.Disabled)
                enabledProtocols = enabledProtocols | ManagementConnectionType.Wmi;
            if (connection.PowerShellRemoting != ManagementConnectionProtocolState.Disabled)
                enabledProtocols = enabledProtocols | ManagementConnectionType.PowerShellRemoting;

            ManagementConnectionType excluded = request.DoNotUse;
            string classNameForMessages = request.ClassName != null ? request.ClassName : String.Empty;

            while (true)
            {
                ManagementConnectionType conType;
                try
                {
                    conType = connection.GetConnectionType(excluded, request.Force);
                }
                catch (Exception e)
                {
                    if (!ConnectionHost.DisableCache)
                        ConnectionHost.Connections[computer] = connection;
                    NotifyFailure(observer, new CmObjectFailure { Kind = CmObjectFailureKind.NoConnection, Error = e, EnabledProtocols = enabledProtocols });
                    throw new PSInvalidOperationException("[" + computer + "] Unable to find a connection to the target system. Ensure the name is typed correctly, and the server allows any of the following protocols: " + enabledProtocols, e);
                }

                NotifyRung(observer, conType, CmObjectRungStep.Started, null);

                // True while the observer holds an object: what it throws then (a stopped pipeline) is
                // not this rung's failure, so the rung catches below stay out of it.
                bool delivering = false;

                if (conType == ManagementConnectionType.CimRM || conType == ManagementConnectionType.CimDCOM)
                {
                    try
                    {
                        object raw;
                        if (conType == ManagementConnectionType.CimRM)
                            raw = isQuery
                                ? connection.QueryCimRMInstance(cred, request.Query, "WQL", namespaceText)
                                : connection.GetCimRMInstance(cred, request.ClassName, namespaceText);
                        else
                            raw = isQuery
                                ? connection.QueryCimDCOMInstance(cred, request.Query, "WQL", namespaceText)
                                : connection.GetCimDComInstance(cred, request.ClassName, namespaceText);

                        CmObjectResult result = new CmObjectResult();
                        IEnumerable<CimInstance> sequence = raw as IEnumerable<CimInstance>;
                        if (sequence != null)
                        {
                            foreach (CimInstance instance in sequence)
                                Keep(result, PSObject.AsPSObject(instance), observer, ref delivering);
                        }

                        NotifyRung(observer, conType, CmObjectRungStep.Succeeded, null);
                        connection.ReportSuccess(conType);
                        connection.AddGoodCredential(cred);
                        if (!ConnectionHost.DisableCache)
                            ConnectionHost.Connections[computer] = connection;
                        return result;
                    }
                    catch (Exception e) when (!delivering)
                    {
                        NotifyRung(observer, conType, CmObjectRungStep.Failed, e);

                        // PS: Resolve-CimError derives the message class name from the query
                        // ('.+from (\S+).{0,}' -> $1) when running the Query parameter set.
                        string triageClassName = isQuery ? ExtractQueryClassName(request.Query) : request.ClassName;
                        CimErrorVerdict verdict = ResolveCimError(e, computer, triageClassName, namespaceText);

                        if (verdict.BadCredentials)
                        {
                            connection.AddBadCredential(cred);
                            if (!ConnectionHost.DisableCache)
                                ConnectionHost.Connections[computer] = connection;
                            NotifyFailure(observer, new CmObjectFailure { Kind = CmObjectFailureKind.CimBadCredentials, Error = e });
                            throw new UnauthorizedAccessException("[" + computer + "] Invalid connection credentials", e);
                        }
                        if (verdict.BadConnection)
                        {
                            connection.ReportFailure(conType);
                            excluded = excluded | conType;
                            continue;
                        }
                        NotifyFailure(observer, new CmObjectFailure { Kind = CmObjectFailureKind.CimError, Error = e, Message = verdict.Message });
                        throw new InvalidOperationException(verdict.Message, e);
                    }
                }

                if (conType == ManagementConnectionType.Wmi)
                {
                    try
                    {
                        CmObjectResult result = new CmObjectResult();
                        foreach (object instance in EnumerateWmi(computer, cred, isQuery ? null : request.ClassName, isQuery ? request.Query : null, namespaceText))
                            Keep(result, PSObject.AsPSObject(instance), observer, ref delivering);

                        NotifyRung(observer, ManagementConnectionType.Wmi, CmObjectRungStep.Succeeded, null);
                        connection.ReportSuccess(ManagementConnectionType.Wmi);
                        connection.AddGoodCredential(cred);
                        if (!ConnectionHost.DisableCache)
                            ConnectionHost.Connections[computer] = connection;
                        return result;
                    }
                    catch (Exception e) when (!delivering)
                    {
                        NotifyRung(observer, ManagementConnectionType.Wmi, CmObjectRungStep.Failed, e);

                        // PS triage: $_.CategoryInfo.Reason -eq "UnauthorizedAccessException" /
                        // Category -eq "InvalidType" / $_.Exception.ErrorCode -eq "ProviderLoadFailure".
                        if (e is UnauthorizedAccessException)
                        {
                            connection.AddBadCredential(cred);
                            if (!ConnectionHost.DisableCache)
                                ConnectionHost.Connections[computer] = connection;
                            NotifyFailure(observer, new CmObjectFailure { Kind = CmObjectFailureKind.WmiBadCredentials, Error = e });
                            throw new UnauthorizedAccessException("[" + computer + "] Invalid connection credentials", e);
                        }
                        WmiErrorKind kind = ClassifyWmiError(e);
                        if (kind == WmiErrorKind.InvalidClass)
                        {
                            NotifyFailure(observer, new CmObjectFailure { Kind = CmObjectFailureKind.WmiInvalidClass, Error = e, ClassName = isQuery ? ExtractQueryClassName(request.Query) : request.ClassName });
                            throw new InvalidOperationException("[" + computer + "] Invalid class name (" + classNameForMessages + "), not found in current namespace (" + namespaceText + ")", e);
                        }
                        if (kind == WmiErrorKind.ProviderLoadFailure)
                        {
                            NotifyFailure(observer, new CmObjectFailure { Kind = CmObjectFailureKind.WmiProviderLoad, Error = e });
                            throw new InvalidOperationException("[" + computer + "] Failed to access: " + classNameForMessages + ", in namespace: " + namespaceText + " - There was a provider error. This indicates a potential issue with WMI on the server side.", e);
                        }

                        connection.ReportFailure(ManagementConnectionType.Wmi);
                        excluded = excluded | ManagementConnectionType.Wmi;
                        continue;
                    }
                }

                // PowerShellRemoting: forwards the ORIGINAL Credential parameter, not the
                // connection-resolved one, as the PS source does.
                try
                {
                    CmObjectResult remoteResult = RunRemotingRung(host, request, computer, isQuery, namespaceText);

                    CmObjectResult result = new CmObjectResult();
                    foreach (PSObject instance in remoteResult.Instances)
                        Keep(result, instance, observer, ref delivering);
                    result.PassthroughErrors.AddRange(remoteResult.PassthroughErrors);

                    NotifyRung(observer, ManagementConnectionType.PowerShellRemoting, CmObjectRungStep.Succeeded, null);
                    connection.ReportSuccess(ManagementConnectionType.PowerShellRemoting);
                    connection.AddGoodCredential(cred);
                    if (!ConnectionHost.DisableCache)
                        ConnectionHost.Connections[computer] = connection;
                    return result;
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch when (!delivering)
                {
                    NotifyRung(observer, ManagementConnectionType.PowerShellRemoting, CmObjectRungStep.Failed, null);

                    // PS: any failure here just reports the rung down - there is no way to
                    // differentiate authentication errors from server-not-reached.
                    connection.ReportFailure(ManagementConnectionType.PowerShellRemoting);
                    excluded = excluded | ManagementConnectionType.PowerShellRemoting;
                    continue;
                }
            }
        }

        // Runs Get-WmiObject on the target with the caller's class, query and namespace as parameter
        // values, so no text of theirs is ever parsed. A failed open is the rung's failure (New-PSSession
        // -ErrorAction Stop); an error of the remote command does not fail the rung, it travels with the
        // result, as a remote error does through Invoke-Command.
        private static CmObjectResult RunRemotingRung(PSCmdlet host, CmObjectRequest request, string computer, bool isQuery, string namespaceText)
        {
            CmObjectResult result = new CmObjectResult();

            // Invoke-Command2 runs in this process on the local computer, with no session or credential.
            if (new Parameter.DbaInstanceParameter(computer).IsLocalHost)
            {
                foreach (object instance in EnumerateWmi(computer, null, isQuery ? null : request.ClassName, isQuery ? request.Query : null, namespaceText))
                    result.Instances.Add(PSObject.AsPSObject(instance));
                return result;
            }

            bool useSsl = LanguagePrimitives.IsTrue(GetConfigValue("psremoting.pssession.usessl"));
            int port;
            if (!LanguagePrimitives.TryConvertTo<int>(GetConfigValue("psremoting.pssession.port"), out port) || port <= 0)
                port = useSsl ? 5986 : 5985;

            using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(new WSManConnectionInfo(useSsl, computer, port, "/wsman", "http://schemas.microsoft.com/powershell/Microsoft.PowerShell", request.Credential)
            {
                IdleTimeout = 600000,
                IncludePortInSPN = LanguagePrimitives.IsTrue(GetConfigValue("psremoting.pssessionoption.includeportinspn")),
                SkipCACheck = LanguagePrimitives.IsTrue(GetConfigValue("psremoting.pssessionoption.skipcacheck")),
                SkipCNCheck = LanguagePrimitives.IsTrue(GetConfigValue("psremoting.pssessionoption.skipcncheck")),
                SkipRevocationCheck = LanguagePrimitives.IsTrue(GetConfigValue("psremoting.pssessionoption.skiprevocationcheck"))
            }))
            {
                runspace.Open();
                using (PowerShell shell = PowerShell.Create().AddCommand("Get-WmiObject"))
                {
                    shell.Runspace = runspace;
                    if (isQuery)
                        shell.AddParameter("Query", request.Query);
                    else
                        shell.AddParameter("Class", request.ClassName);
                    shell.AddParameter("ErrorAction", "Stop");
                    if (request.Namespace != null)
                        shell.AddParameter("Namespace", request.Namespace);

                    // The remote pipeline does not stop with the caller's, so Ctrl+C is passed on here.
                    IAsyncResult running = shell.BeginInvoke();
                    while (!running.AsyncWaitHandle.WaitOne(200))
                    {
                        if (host != null && host.Stopping)
                            shell.Stop();
                    }

                    ErrorRecord remoteFailure = null;
                    try
                    {
                        foreach (PSObject item in shell.EndInvoke(running))
                        {
                            SetRemotingNote(item, "PSComputerName", computer);
                            SetRemotingNote(item, "RunspaceId", runspace.InstanceId);
                            SetRemotingNote(item, "PSShowComputerName", true);
                            result.Instances.Add(item);
                        }
                    }
                    catch (RuntimeException e) when (!(e is PipelineStoppedException) && !(e is PSRemotingTransportException))
                    {
                        remoteFailure = e.ErrorRecord;
                    }

                    foreach (ErrorRecord record in shell.Streams.Error)
                        result.PassthroughErrors.Add(record);
                    if (remoteFailure != null && result.PassthroughErrors.Count == 0)
                        result.PassthroughErrors.Add(remoteFailure);
                }
            }
            return result;
        }

        // Invoke-Command marks each object with where it came from. A WMI object's own PSComputerName
        // comes along from the remote side, so the note replaces it.
        private static void SetRemotingNote(PSObject item, string name, object value)
        {
            item.Properties.Remove(name);
            item.Properties.Add(new PSNoteProperty(name, value), true);
        }

        // Hands an object to the observer's Output, or keeps it for the result when there is none.
        private static void Keep(CmObjectResult result, PSObject instance, CmObjectObserver observer, ref bool delivering)
        {
            if (observer == null || observer.Output == null)
            {
                result.Instances.Add(instance);
                return;
            }
            delivering = true;
            observer.Output(instance);
            delivering = false;
        }

        private static void NotifyRung(CmObjectObserver observer, ManagementConnectionType rung, CmObjectRungStep step, Exception error)
        {
            if (observer != null && observer.Rung != null)
                observer.Rung(rung, step, error);
        }

        private static void NotifyFailure(CmObjectObserver observer, CmObjectFailure failure)
        {
            if (observer != null && observer.Failure != null)
                observer.Failure(failure);
        }

        private enum WmiErrorKind
        {
            Other,
            InvalidClass,
            ProviderLoadFailure
        }

        private static WmiErrorKind ClassifyWmiError(Exception error)
        {
#pragma warning disable CA1416
            System.Management.ManagementException managementError = error as System.Management.ManagementException;
            if (managementError == null)
                managementError = error.InnerException as System.Management.ManagementException;
            if (managementError == null)
                return WmiErrorKind.Other;
            if (managementError.ErrorCode == System.Management.ManagementStatus.InvalidClass)
                return WmiErrorKind.InvalidClass;
            if (managementError.ErrorCode == System.Management.ManagementStatus.ProviderLoadFailure)
                return WmiErrorKind.ProviderLoadFailure;
            return WmiErrorKind.Other;
#pragma warning restore CA1416
        }

        private static List<object> EnumerateWmi(string computer, PSCredential credential, string className, string query, string namespaceText)
        {
            // The compiled Get-WmiObject: same DCOM stack (System.Management), same defaults
            // (Impersonate, Unchanged authentication), materialized inside the caller's try
            // because ManagementObjectCollection faults lazily. On non-Windows platforms the
            // rung fails into the ordinary fall-through, like the missing Get-WmiObject
            // command does on PowerShell 7.
            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                throw new PlatformNotSupportedException("WMI is only available on Windows");
#pragma warning disable CA1416
            System.Management.ConnectionOptions options = new System.Management.ConnectionOptions();
            if (credential != null)
            {
                options.Username = credential.UserName;
                options.SecurePassword = credential.Password;
            }
            System.Management.ManagementScope scope = new System.Management.ManagementScope(@"\\" + computer + @"\" + namespaceText, options);
            scope.Connect();
            string queryText = query != null ? query : "select * from " + className;
            List<object> found = new List<object>();
            using (System.Management.ManagementObjectSearcher searcher = new System.Management.ManagementObjectSearcher(scope, new System.Management.ObjectQuery(queryText)))
            {
                foreach (System.Management.ManagementBaseObject instance in searcher.Get())
                    found.Add(instance);
            }
            return found;
#pragma warning restore CA1416
        }

        /// <summary>
        /// Converts a DMTF datetime string (the raw form Wmi-rung ManagementObjects carry)
        /// to a DateTime, like the ConvertToDateTime script method PS type data adds to
        /// System.Management.ManagementObject. CIM-rung instances already carry DateTime
        /// values and never need this.
        /// </summary>
        /// <param name="dmtfDate">The DMTF datetime string.</param>
        /// <returns>The converted DateTime.</returns>
        public static DateTime ConvertDmtfToDateTime(string dmtfDate)
        {
#pragma warning disable CA1416
            return System.Management.ManagementDateTimeConverter.ToDateTime(dmtfDate);
#pragma warning restore CA1416
        }

        private static string ExtractQueryClassName(string query)
        {
            // PS: $ClassName = $Query -replace '.+from (\S+).{0,}', '$1'
            if (query == null)
                return String.Empty;
            System.Text.RegularExpressions.Match match = System.Text.RegularExpressions.Regex.Match(query, ".+from (\\S+).{0,}", System.Text.RegularExpressions.RegexOptions.IgnoreCase | System.Text.RegularExpressions.RegexOptions.Singleline);
            if (match.Success)
                return match.Groups[1].Value;
            return query;
        }

        private static string ComposeBadCredentialMessage(ManagementConnection connection, PSCredential credential, Exception e)
        {
            return ComposeBadCredentialText(connection, credential) + e.Message;
        }

        private static string ComposeBadCredentialText(ManagementConnection connection, PSCredential credential)
        {
            // Message text mirrors Get-DbaCmObject's bad-credential composition; ported
            // callers triage on the "known to not work" phrase.
            string message = "Bad credentials. ";
            if (credential != null)
                message += "The credentials for " + credential.UserName + " are known to not work. ";
            else
                message += "The windows credentials are known to not work. ";
            if (connection.EnableCredentialFailover || connection.OverrideExplicitCredential)
                message += "The connection is configured to use credentials that are known to be good, but none have been registered yet. ";
            else if (connection.Credentials != null)
                message += "Working credentials are known for " + connection.Credentials.UserName + ", however the connection is not configured to automatically use them. This can be done using 'Set-DbaCmConnection -ComputerName " + connection + " -OverrideExplicitCredential' ";
            else if (connection.UseWindowsCredentials)
                message += "The windows credentials are known to work, however the connection is not configured to automatically use them. This can be done using 'Set-DbaCmConnection -ComputerName " + connection + " -OverrideExplicitCredential' ";
            return message;
        }

        private sealed class CimErrorVerdict
        {
            public string Message;
            public bool BadConnection;
            public bool BadCredentials;
        }

        private static CimErrorVerdict ResolveCimError(Exception error, string computer, string className, string cimNamespace)
        {
            // Port of Get-DbaCmObject's Resolve-CimError utility: decide the user-facing
            // message and whether the failure means "this protocol is not viable" (fall to
            // the next rung) or "the operation itself is invalid" (stop with the message).
            CimErrorVerdict verdict = new CimErrorVerdict();

            // ManagementConnection translates session-create credential failures into
            // UnauthorizedAccessException before they ever reach the triage table.
            if (error is UnauthorizedAccessException)
            {
                verdict.BadCredentials = true;
                verdict.Message = "[" + computer + "] Invalid connection credentials";
                return verdict;
            }

            CimException cimError = error as CimException;
            if (cimError == null)
                cimError = error.InnerException as CimException;
            if (cimError == null)
            {
                verdict.BadConnection = true;
                verdict.Message = "[" + computer + "] An otherwise unexpected error happened.";
                return verdict;
            }

            int code = (int)cimError.NativeErrorCode;
            string messageId = cimError.MessageId;

            // PS region "1 = Generic runtime error": specific HRESULTs re-map before the table.
            if (code == 1)
            {
                if (messageId == "HRESULT 0x8007052e" || messageId == "HRESULT 0x80070005")
                {
                    verdict.BadCredentials = true;
                    verdict.Message = "[" + computer + "] Invalid connection credentials";
                    return verdict;
                }
                if (messageId == "HRESULT 0x80041013")
                {
                    verdict.Message = "[" + computer + "] Failed to access " + className + " in namespace " + cimNamespace;
                    return verdict;
                }
                if (messageId == "HRESULT 0x8004100e")
                {
                    verdict.Message = "[" + computer + "] Invalid namespace: " + cimNamespace;
                    return verdict;
                }
                if (messageId == "HRESULT 0x80041010")
                {
                    verdict.Message = "[" + computer + "] Invalid class name (" + className + "), not found in current namespace (" + cimNamespace + ")";
                    return verdict;
                }
                verdict.BadConnection = true;
                verdict.Message = "[" + computer + "] An otherwise unexpected error happened.";
                return verdict;
            }

            // The messages table, verbatim from Resolve-CimError.
            switch (code)
            {
                case 2:
                    verdict.Message = "[" + computer + "] Access to computer granted, but access to " + cimNamespace + "\\" + className + " denied";
                    return verdict;
                case 3:
                    verdict.Message = "[" + computer + "] Invalid namespace: " + cimNamespace;
                    return verdict;
                case 4:
                    verdict.Message = "[" + computer + "] Invalid parameters were specified";
                    return verdict;
                case 5:
                    verdict.Message = "[" + computer + "] Invalid class name (" + className + "), not found in current namespace (" + cimNamespace + ")";
                    return verdict;
                case 6:
                    verdict.Message = "[" + computer + "] The requested object of class " + className + " could not be found";
                    return verdict;
                case 7:
                    verdict.Message = "[" + computer + "] The operation against class " + className + " was not supported. This generally is a serverside WMI Provider issue (That is: It is specific to the application being managed via WMI)";
                    return verdict;
                case 8:
                case 9:
                    verdict.Message = "[" + computer + "] The operation against class " + className + " is refused as long as it contains instances (data)";
                    return verdict;
                case 10:
                    verdict.Message = "[" + computer + "] The operation against class " + className + " cannot be carried out since the specified superclass does not exist.";
                    return verdict;
                case 11:
                    verdict.Message = "[" + computer + "] The specified object in " + className + " already exists.";
                    return verdict;
                case 12:
                    verdict.Message = "[" + computer + "] The specified property does not exist on " + className + ".";
                    return verdict;
                case 13:
                    verdict.Message = "[" + computer + "] The input type is invalid.";
                    return verdict;
                case 14:
                    verdict.Message = "[" + computer + "] Invalid query language. Please check your query string.";
                    return verdict;
                case 15:
                    verdict.Message = "[" + computer + "] Invalid query string. Please check your syntax.";
                    return verdict;
                case 16:
                    verdict.Message = "[" + computer + "] The specified method on " + className + " is not available.";
                    return verdict;
                case 17:
                    verdict.Message = "[" + computer + "] The specified method on " + className + " does not exist.";
                    return verdict;
                case 18:
                    verdict.Message = "[" + computer + "] An unexpected response has happened in this request";
                    return verdict;
                case 19:
                    verdict.Message = "[" + computer + "] The specified destination for this request is invalid.";
                    return verdict;
                case 20:
                    verdict.Message = "[" + computer + "] The specified namespace " + cimNamespace + " is not empty.";
                    return verdict;
                default:
                    // PS region "0 = Non-CIM Issue not covered by the framework": a provider
                    // reporting __ExtendedStatus stops with the descriptive message instead of
                    // falling to the next protocol; anything else reads as a connection-level
                    // failure (cross-model review 2026-07-06 finding 1).
                    if (HasExtendedStatusOriginalError(cimError))
                    {
                        verdict.Message = "[" + computer + "] Something went wrong when looking for " + className + ", in " + cimNamespace + ". This often indicates issues with the target system.";
                        return verdict;
                    }
                    verdict.BadConnection = true;
                    verdict.Message = "[" + computer + "] An otherwise unexpected error happened.";
                    return verdict;
            }
        }

        private static bool HasExtendedStatusOriginalError(CimException cimError)
        {
            // PS: $ErrorRecord.Exception.InnerException.ErrorData.original_error -like "__ExtendedStatus"
            // (loose member access; absent members simply fail the comparison).
            try
            {
                CimInstance errorData = cimError.ErrorData;
                if (errorData == null)
                    return false;
                CimProperty property = errorData.CimInstanceProperties["original_error"];
                if (property == null || property.Value == null)
                    return false;
                return String.Equals(property.Value.ToString(), "__ExtendedStatus", StringComparison.OrdinalIgnoreCase);
            }
            catch
            {
                return false;
            }
        }

        private static object GetConfigValue(string key)
        {
            Config config;
            if (ConfigurationHost.Configurations.TryGetValue(key, out config) && config != null)
                return config.Value;
            return null;
        }

        private static TimeSpan GetConfigTimeSpan(string key, TimeSpan fallback)
        {
            Config config;
            if (ConfigurationHost.Configurations.TryGetValue(key, out config) && config != null && config.Value != null)
            {
                if (config.Value is TimeSpan)
                    return (TimeSpan)config.Value;
                try
                {
                    return TimeSpan.Parse(config.Value.ToString(), System.Globalization.CultureInfo.InvariantCulture);
                }
                catch
                {
                    // fall through to the fallback on any malformed configuration value
                }
            }
            return fallback;
        }
    }
}
