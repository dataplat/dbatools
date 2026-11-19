using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Management.Automation.Remoting;
using System.Management.Automation.Runspaces;
using System.Runtime.InteropServices;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Connection
{
    /// <summary>
    /// Compiled equivalent of private/functions/Invoke-Command2.ps1 (Wave 5 infrastructure).
    /// Drives the engine remoting cmdlets (New-PSSession / Connect-PSSession /
    /// Invoke-Command / Remove-PSSession) through a nested pipeline in the caller's
    /// runspace, so session objects, serialization behavior and error semantics are
    /// identical to the PS implementation, and sessions are cached in the SAME
    /// ConnectionHost.PSSessions store under the SAME composed session names - the PS and
    /// compiled halves reuse each other's sessions during the hybrid period.
    /// </summary>
    public static class RemoteExecutionService
    {
        /// <summary>
        /// The Invoke-Command2 parameter surface. Fields default to the PS parameter
        /// defaults; leave UseSsl/Port null to resolve the PSRemoting.* configuration
        /// values exactly like the PS param block did.
        /// </summary>
        public sealed class RemoteCommandRequest
        {
            /// <summary>The computer to invoke the scriptblock on; null means the local computer.</summary>
            public DbaInstanceParameter ComputerName;

            /// <summary>The credentials to use; stays object-typed for legacy reasons (accepts null).</summary>
            public PSCredential Credential;

            /// <summary>The code to run on the targeted system, as script text.</summary>
            public string ScriptText;

            /// <summary>Any arguments to pass to the scriptblock being run.</summary>
            public object[] ArgumentList;

            /// <summary>Objects available in the scriptblock as $input (serialized over the wire).</summary>
            public object[] InputObject;

            /// <summary>The authentication mechanism for the connection (Invoke-Command2 default: Default).</summary>
            public string Authentication = "Default";

            /// <summary>Name of the remote PSSessionConfiguration to use, when any.</summary>
            public string ConfigurationName;

            /// <summary>Enables SSL; null resolves PSRemoting.PsSession.UseSSL (fallback false).</summary>
            public bool? UseSsl;

            /// <summary>Connection port; null resolves PSRemoting.PsSession.Port (fallback none).</summary>
            public int? Port;

            /// <summary>Passes through the raw return data rather than prettifying stuff.</summary>
            public bool Raw;

            /// <summary>Verifies the remote PowerShell version meets this requirement before running.</summary>
            public Version RequiredPSVersion;

            /// <summary>
            /// Replicates an explicit `Invoke-Command2 -Verbose` at a call site: passes -Verbose to
            /// the nested Invoke-Command so the scriptblock's Write-Verbose records are generated
            /// (locally the preference propagates into the invoked script; remotely the records are
            /// transported) and land in the result's Verbose list for the caller to re-emit.
            /// </summary>
            public bool ForceVerbose;
        }

        /// <summary>
        /// What a run produced. Terminating failures (session creation, version gate) throw
        /// out of InvokeCommand instead; non-terminating errors land here because the PS
        /// source let them flow to the caller's error stream without failing the call -
        /// callers that mirror Get-DbaCmObject's PowerShellRemoting rung treat a run with
        /// errors as a SUCCESS, exactly like the PS try/catch did.
        /// </summary>
        public sealed class RemoteCommandResult
        {
            /// <summary>The pipeline output of the invocation.</summary>
            public List<PSObject> Output = new List<PSObject>();

            /// <summary>Non-terminating errors the nested pipeline surfaced.</summary>
            public List<ErrorRecord> Errors = new List<ErrorRecord>();

            /// <summary>Verbose messages the nested pipeline surfaced (populated for ForceVerbose runs).</summary>
            public List<string> Verbose = new List<string>();
        }

        /// <summary>
        /// Executes a scriptblock locally or on a remote computer with Invoke-Command2's
        /// exact session discipline: cache lookup by composed session name, reconnect of
        /// disconnected sessions, session-option construction from PSRemoting.* config,
        /// the optional remote version gate, and Raw/cooked output shaping.
        /// </summary>
        /// <param name="host">The cmdlet making this request.</param>
        /// <param name="request">The Invoke-Command2 parameter surface.</param>
        /// <returns>Output plus any non-terminating errors of the run.</returns>
        public static RemoteCommandResult InvokeCommand(PSCmdlet host, RemoteCommandRequest request)
        {
            NativeExecutionGuard.Check(host);
            if (request == null)
                throw new ArgumentNullException("request");
            if (String.IsNullOrEmpty(request.ScriptText))
                throw new ArgumentException("A scriptblock is required", "request");

            DbaInstanceParameter computer = request.ComputerName;
            if (computer == null)
                computer = new DbaInstanceParameter(Environment.MachineName);

            ScriptBlock scriptBlock = ScriptBlock.Create(request.ScriptText);

            PSSession currentSession = null;
            Guid runspaceId = Guid.Empty;
            string sessionName = null;

            if (!computer.IsLocalHost)
            {
                if (System.Management.Automation.Runspaces.Runspace.DefaultRunspace == null)
                    throw new InvalidOperationException("Remote execution requires a running PowerShell pipeline (no default runspace is present).");
                runspaceId = System.Management.Automation.Runspaces.Runspace.DefaultRunspace.InstanceId;

                // PS: sessions with different Authentication should have different session names
                if (!String.IsNullOrEmpty(request.ConfigurationName))
                    sessionName = String.Format("dbatools_{0}_{1}_{2}_{3}", request.Authentication, request.ConfigurationName, runspaceId, computer.ComputerName);
                else
                    sessionName = String.Format("dbatools_{0}_{1}_{2}", request.Authentication, runspaceId, computer.ComputerName);

                // Retrieve a session from the session cache, if available (unique per runspace).
                PSSession cached = ConnectionHost.PSSessionGet(runspaceId, sessionName);
                if (cached != null && cached.Runspace != null)
                {
                    RunspaceState state = cached.Runspace.RunspaceStateInfo.State;
                    if (state == RunspaceState.Opened || state == RunspaceState.Disconnected)
                        currentSession = cached;
                }

                if (currentSession == null)
                {
                    bool useSsl = request.UseSsl.HasValue ? request.UseSsl.Value : GetConfigBool("psremoting.pssession.usessl", false);
                    int? port = request.Port.HasValue ? request.Port : GetConfigInt("psremoting.pssession.port");

                    using (PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace))
                    {
                        shell.AddCommand("New-PSSession")
                            .AddParameter("ComputerName", computer.ComputerName)
                            .AddParameter("Authentication", request.Authentication)
                            .AddParameter("Name", sessionName)
                            .AddParameter("ErrorAction", "Stop")
                            .AddParameter("UseSSL", useSsl);
                        if (port.HasValue && port.Value > 0)
                            shell.AddParameter("Port", port.Value);
                        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                        {
                            PSSessionOption sessionOption = new PSSessionOption();
                            sessionOption.IdleTimeout = TimeSpan.FromMinutes(10);
                            sessionOption.IncludePortInSPN = GetConfigBool("psremoting.pssessionoption.includeportinspn", false);
                            sessionOption.SkipCACheck = GetConfigBool("psremoting.pssessionoption.skipcacheck", false);
                            sessionOption.SkipCNCheck = GetConfigBool("psremoting.pssessionoption.skipcncheck", false);
                            sessionOption.SkipRevocationCheck = GetConfigBool("psremoting.pssessionoption.skiprevocationcheck", false);
                            shell.AddParameter("SessionOption", sessionOption);
                        }
                        if (request.Credential != null)
                            shell.AddParameter("Credential", request.Credential);
                        if (!String.IsNullOrEmpty(request.ConfigurationName))
                            shell.AddParameter("ConfigurationName", request.ConfigurationName);

                        foreach (PSObject result in shell.Invoke())
                        {
                            currentSession = result == null ? null : result.BaseObject as PSSession;
                            if (currentSession != null)
                                break;
                        }
                    }

                    if (currentSession == null)
                        throw new InvalidOperationException(String.Format("Failed to establish a remoting session to {0}", computer.ComputerName));
                }
                else
                {
                    if (currentSession.Runspace.RunspaceStateInfo.State == RunspaceState.Disconnected)
                    {
                        using (PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace))
                        {
                            shell.AddCommand("Connect-PSSession")
                                .AddParameter("Session", currentSession)
                                .AddParameter("ErrorAction", "Stop");
                            shell.Invoke();
                        }
                    }

                    // Refresh the session registration if registered, to reset countdown until purge
                    ConnectionHost.PSSessionSet(runspaceId, sessionName, currentSession);
                }
            }

            if (request.RequiredPSVersion != null)
            {
                Version remoteVersion = ProbeVersion(currentSession);
                if (remoteVersion != null && remoteVersion < request.RequiredPSVersion)
                    throw new InvalidOperationException(String.Format("Remote PS version {0} is less than defined requirement ({1})", remoteVersion, request.RequiredPSVersion));
            }

            RemoteCommandResult resultBag = new RemoteCommandResult();
            using (PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace))
            {
                System.Collections.Hashtable invokeParams = new System.Collections.Hashtable();
                if (currentSession != null)
                    invokeParams["Session"] = currentSession;
                invokeParams["ScriptBlock"] = scriptBlock;
                // PS: if ($ArgumentList) / if ($InputObject) - PowerShell array truthiness,
                // so a single-element array holding $null/$false/0/"" is NOT passed
                // (cross-model review 2026-07-06 pm2 finding 1).
                if (request.ArgumentList != null && LanguagePrimitives.IsTrue(request.ArgumentList))
                    invokeParams["ArgumentList"] = request.ArgumentList;
                if (request.InputObject != null && LanguagePrimitives.IsTrue(request.InputObject))
                    invokeParams["InputObject"] = request.InputObject;
                if (request.ForceVerbose)
                {
                    // An explicit `Invoke-Command2 -Verbose` call site set $VerbosePreference =
                    // Continue in the function's scope, which the IN-PROCESS scriptblock's dynamic
                    // preference lookup walks to; -Verbose on the Invoke-Command CMDLET alone only
                    // flips its own runtime flag, which that lookup never consults. Run the
                    // invocation from a wrapper scope carrying the preference (in-process path,
                    // useLocalScope so the assignment cannot leak into the caller's scope), keep
                    // -Verbose for the remote transport path, and merge the verbose records into
                    // the output stream (4>&1) - written to the host directly they would neither
                    // reach this result bag nor survive a caller-side redirect.
                    string wrapper = "param($__params) $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue; Invoke-Command @__params -Verbose 4>&1";
                    if (!request.Raw)
                    {
                        // PS: Invoke-Command ... | Select-Object -Property * -ExcludeProperty
                        //     PSComputerName, RunspaceId, PSShowComputerName
                        // (verbose records bypass Select-Object in PS because they are not
                        // pipeline objects; here they ride the output stream, so project only
                        // the real output objects around them).
                        wrapper += " | ForEach-Object { if ($_ -is [System.Management.Automation.VerboseRecord]) { $_ } else { $_ | Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName } }";
                    }
                    shell.AddScript(wrapper, true);
                    shell.AddParameter("__params", invokeParams);
                }
                else
                {
                    shell.AddCommand("Invoke-Command");
                    foreach (System.Collections.DictionaryEntry entry in invokeParams)
                        shell.AddParameter((string)entry.Key, entry.Value);
                    if (!request.Raw)
                    {
                        // PS: Invoke-Command ... | Select-Object -Property * -ExcludeProperty
                        //     PSComputerName, RunspaceId, PSShowComputerName
                        shell.AddCommand("Select-Object")
                            .AddParameter("Property", new string[] { "*" })
                            .AddParameter("ExcludeProperty", new string[] { "PSComputerName", "RunspaceId", "PSShowComputerName" });
                    }
                }

                foreach (PSObject output in shell.Invoke())
                {
                    VerboseRecord verboseOutput = output == null ? null : output.BaseObject as VerboseRecord;
                    if (verboseOutput != null)
                        resultBag.Verbose.Add(verboseOutput.Message);
                    else
                        resultBag.Output.Add(output);
                }
                foreach (ErrorRecord error in shell.Streams.Error)
                    resultBag.Errors.Add(error);
                foreach (VerboseRecord verbose in shell.Streams.Verbose)
                    resultBag.Verbose.Add(verbose.Message);
            }

            if (!computer.IsLocalHost)
            {
                // Tell the system to clean up if the session expires
                ConnectionHost.PSSessionSet(runspaceId, sessionName, currentSession);

                if (!GetConfigBool("psremoting.sessions.enable", true))
                {
                    using (PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace))
                    {
                        shell.AddCommand("Remove-PSSession").AddParameter("Session", currentSession);
                        shell.Invoke();
                    }
                }
            }

            return resultBag;
        }

        private static Version ProbeVersion(PSSession session)
        {
            // PS: $remoteVersion = Invoke-Command @InvokeCommandSplat -ScriptBlock { $PSVersionTable }
            //     if ($remoteVersion.PSVersion -and $remoteVersion.PSVersion -lt $RequiredPSVersion) { throw }
            // A missing or unconvertible PSVersion skips the gate, exactly like the PS truthiness check.
            using (PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace))
            {
                shell.AddCommand("Invoke-Command");
                if (session != null)
                    shell.AddParameter("Session", session);
                shell.AddParameter("ScriptBlock", ScriptBlock.Create("$PSVersionTable"));

                foreach (PSObject tableResult in shell.Invoke())
                {
                    if (tableResult == null)
                        continue;
                    object rawVersion = null;
                    PSPropertyInfo property = tableResult.Properties["PSVersion"];
                    if (property != null)
                        rawVersion = property.Value;
                    else
                    {
                        System.Collections.IDictionary dictionary = tableResult.BaseObject as System.Collections.IDictionary;
                        if (dictionary != null && dictionary.Contains("PSVersion"))
                            rawVersion = dictionary["PSVersion"];
                    }
                    if (rawVersion == null)
                        continue;

                    Version converted;
                    if (LanguagePrimitives.TryConvertTo<Version>(rawVersion, out converted))
                        return converted;

                    // SemanticVersion values (pwsh remotes) stringify with prerelease tags;
                    // keep only the dotted numeric prefix, like a [version] cast would need.
                    string text = rawVersion.ToString();
                    int cut = text.IndexOfAny(new char[] { '-', '+' });
                    if (cut > 0)
                        text = text.Substring(0, cut);
                    if (Version.TryParse(text, out converted))
                        return converted;
                }
            }
            return null;
        }

        private static bool GetConfigBool(string key, bool fallback)
        {
            Config config;
            if (ConfigurationHost.Configurations.TryGetValue(key, out config) && config != null && config.Value != null)
            {
                try
                {
                    return LanguagePrimitives.IsTrue(config.Value);
                }
                catch
                {
                    // malformed configuration values fall back, like Get-DbatoolsConfigValue -Fallback
                }
            }
            return fallback;
        }

        private static int? GetConfigInt(string key)
        {
            Config config;
            if (ConfigurationHost.Configurations.TryGetValue(key, out config) && config != null && config.Value != null)
            {
                try
                {
                    return LanguagePrimitives.ConvertTo<int>(config.Value);
                }
                catch
                {
                    // malformed configuration values fall back, like Get-DbatoolsConfigValue -Fallback
                }
            }
            return null;
        }
    }
}
