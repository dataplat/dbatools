using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands
{
    /// <summary>
    /// Base class for every ported cmdlet whose baseline carries SqlInstance. The properties
    /// are abstract and attribute-free ON PURPOSE: each concrete cmdlet declares mandatory-ness,
    /// position, pipeline attributes and aliases itself, because the baseline JSON is law and
    /// base-level attributes could never be tightened or loosened per command
    /// (migration/specs/architecture.md section 3).
    /// </summary>
    public abstract class DbaInstanceCmdlet : DbaBaseCmdlet
    {
        /// <summary>The target SQL Server instance or instances.</summary>
        public abstract DbaInstanceParameter[] SqlInstance { get; set; }

        /// <summary>Login to the target instance using alternative credentials.</summary>
        public abstract PSCredential SqlCredential { get; set; }

        /// <summary>
        /// Wraps ConnectionService.GetServer with the canonical failure shape: on any connect
        /// failure (including MinimumVersion and AzureUnsupported rejections) it runs the
        /// Stop-Function -Continue equivalent and returns null; the call site continues its
        /// loop. Under -EnableException the StopFunction call throws out of the cmdlet.
        /// </summary>
        /// <param name="instance">The instance being connected</param>
        /// <param name="failureMessage">The verbatim failure message from the PS source</param>
        /// <param name="minimumVersion">The -MinimumVersion value the PS source passed, when any</param>
        /// <param name="azureUnsupported">Whether the PS source passed -AzureUnsupported</param>
        /// <returns>The connected server, or null on failure</returns>
        protected Server ConnectInstance(DbaInstanceParameter instance,
            string failureMessage = "Failure",
            int minimumVersion = 0,
            bool azureUnsupported = false)
        {
            return ConnectInstance(instance, out _, failureMessage, minimumVersion, azureUnsupported);
        }

        /// <summary>
        /// The same connect, also reporting what Connect-DbaInstance -IsNewConnectionReference reports: whether the
        /// connection was opened here (true) or is the caller's own Server or connection (false).
        /// </summary>
        /// <param name="instance">The instance being connected</param>
        /// <param name="isNewConnection">Whether the connection was opened here; false on failure</param>
        /// <param name="failureMessage">The verbatim failure message from the PS source</param>
        /// <param name="minimumVersion">The -MinimumVersion value the PS source passed, when any</param>
        /// <param name="azureUnsupported">Whether the PS source passed -AzureUnsupported</param>
        /// <returns>The connected server, or null on failure</returns>
        protected Server ConnectInstance(DbaInstanceParameter instance,
            out bool isNewConnection,
            string failureMessage = "Failure",
            int minimumVersion = 0,
            bool azureUnsupported = false)
        {
            isNewConnection = false;
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
            try
            {
                return ResolveConnection(instance, out isNewConnection, minimumVersion, azureUnsupported);
            }
            catch (Exception ex)
            {
                ErrorRecord record = new ErrorRecord(ex, String.Format("dbatools_{0}", MyInvocation.MyCommand.Name), ErrorCategory.ConnectionError, instance);
                string line = ConnectFailureLine(ex, record, instance, failureMessage);
                if (line != null)
                {
                    StopFunction(line, target: instance, errorRecord: record, category: ErrorCategory.ConnectionError, continueLoop: true, overrideExceptionMessage: true);
                    return null;
                }

                StopFunction(failureMessage, target: instance, errorRecord: record, category: ErrorCategory.ConnectionError, continueLoop: true);
                return null;
            }
        }

        /// <summary>
        /// The connect ConnectInstance wraps, without its Stop-Function: Connect-DbaInstance's steps for one instance,
        /// which throw on any failure (including MinimumVersion and AzureUnsupported refusals). For a command whose pin
        /// connects through a nested dbatools command and reports the failure under that command's name. The caller
        /// writes Connect-DbaInstance's "Starting process block" debug line before its own try, as ConnectInstance does.
        /// </summary>
        /// <param name="instance">The instance being connected</param>
        /// <param name="isNewConnection">Whether the connection was opened here; false on failure</param>
        /// <param name="minimumVersion">The -MinimumVersion value the PS source passed, when any</param>
        /// <param name="azureUnsupported">Whether the PS source passed -AzureUnsupported</param>
        /// <returns>The connected server</returns>
        protected Server ResolveConnection(DbaInstanceParameter instance,
            out bool isNewConnection,
            int minimumVersion = 0,
            bool azureUnsupported = false)
        {
            isNewConnection = false;
            SmoConnectionRequest request = new SmoConnectionRequest();
            request.Instance = instance;
            request.SqlCredential = SqlCredential;
            request.MinimumVersion = minimumVersion;
            request.AzureUnsupported = azureUnsupported;
            request.BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "SqlInstance",
                "SqlCredential"
            };
            request.MessageCallback = (level, message) =>
                WriteAttributedMessage("Connect-DbaInstance", level, message);

            // ConnectionService.GetServer's own steps, keeping the resolution's IsNewConnection.
            if (request.Instance == null)
                throw new ArgumentException("The request carries no target instance", "request");
            request.ApplyConfigurationDefaults();
            ConnectionResolution resolution = ConnectionService.ResolveInstance(request);
            if (resolution.Server == null)
                throw new InvalidOperationException("The request resolved to a bare SqlConnection; use GetSqlConnection for SqlConnectionOnly requests");
            ConnectionService.FinalizeConnection(resolution, request);
            Server server = resolution.Server;
            isNewConnection = resolution.IsNewConnection;
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return server;
        }

        /// <summary>
        /// The one warning line naming the server for a failed connection, in place of the pin's separate
        /// [Connect-DbaInstance] line, whose wording it keeps; the record is unchanged (harness-edits.md, "Script-scope
        /// preferences and the one-line connect warning", point 5). A refusal is not a failed connection and the pin's
        /// nested line names no server there, so it gets no line (null) and keeps the failure message.
        /// </summary>
        /// <param name="ex">The connect failure</param>
        /// <param name="record">The Stop-Function record built on it</param>
        /// <param name="instance">The instance being connected</param>
        /// <param name="failureMessage">The verbatim failure message from the PS source</param>
        /// <returns>The line, shown with -OverrideExceptionMessage, or null</returns>
        protected static string ConnectFailureLine(Exception ex, ErrorRecord record, DbaInstanceParameter instance, string failureMessage)
        {
            ConnectionResolutionException resolution = ex as ConnectionResolutionException;
            if (resolution == null || resolution.Kind != ConnectionResolutionFailure.ConnectFailure)
                return null;
            return String.Format("{0} | Error connecting to [{1}]: {2}", failureMessage, MaskedTargetText(instance), MessageService.GetErrorMessage(record));
        }
    }
}
