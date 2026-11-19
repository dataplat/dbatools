#nullable enable

using System;
using System.Collections;
using System.Globalization;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Replication;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Disables replication publishing on SQL Server instances and removes publisher configuration.
/// </summary>
/// <para>
/// Removes the publisher role from SQL Server instances that are currently configured for replication publishing. This function safely dismantles the publishing configuration by removing the publisher from the distributor, which stops all publication activity on the target instance. Use this when decommissioning replication setups or troubleshooting publisher configuration issues that require a clean restart.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Disable-DbaReplPublishing -SqlInstance mssql1
/// </code>
/// <para>
/// Disables replication distribution for the mssql1 instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $cred = Get-Credential sqladmin
/// PS C:\&gt; Disable-DbaReplPublishing -SqlInstance mssql1, mssql2 -SqlCredential $cred -Force
/// </code>
/// <para>
/// Disables replication distribution for the mssql1 and mssql2 instances using a sql login.
/// </para>
/// <para>
/// Specifies force so all the replication objects associated with the Publisher are dropped even
/// if the Publisher is on a remote server that cannot be reached.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: repl, Replication
/// Author: Jess Pomfret (@jpomfret), jesspomfret.com
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2023 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Disable-DbaReplPublishing" />
[Cmdlet(VerbsLifecycle.Disable, "DbaReplPublishing", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class DisableDbaReplPublishingCommand : DbaBaseCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Forces the removal of publisher configuration without verifying the distributor connection status.
    /// Use this when the distributor server is unreachable or when you need to forcibly clean up orphaned replication objects.
    /// Without this switch, the function will fail if it cannot communicate with the distributor to perform proper cleanup verification.
    /// </para>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        if (SqlInstance is null)
            return;
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException
            PSObject? wrapped = null;
            try
            {
                // Upstream correction azure-unsupported: Azure SQL Database can only be a push subscriber, so the connection
                // refuses it as Connect-DbaInstance -AzureUnsupported does.
                Server server = NativeReplicationServer.Connect(instance, SqlCredential, azureUnsupported: true);
                SetActiveConnection(server.ConnectionContext);
                wrapped = NativeReplicationServer.Wrap(server);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception exception)
            {
                // The pinned nested Get-DbaReplServer forwards EnableException; its failure is outside the command's try.
                // PS (Get-DbaReplServer): Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                ErrorRecord caught = NestedConnectFailure(instance, exception)
                    ?? new ErrorRecord(exception, "dbatools_Get-DbaReplServer", ErrorCategory.ConnectionError, instance);
                StopAttributedFunction("Get-DbaReplServer", "Failure", target: instance, errorRecord: caught,
                    category: ErrorCategory.ConnectionError, continueLoop: true, interruptCallerScope: false);
            }

            // PS: if (-not $replServer) { continue } - Get-DbaReplServer has already warned why it could not connect.
            if (wrapped?.BaseObject is not ReplicationServer replicationServer)
                continue;

            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Disabling and removing publishing for {0}", instance));

            bool isPublisher;
            try
            {
                isPublisher = replicationServer.IsPublisher;
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                // PS: if ($replServer.IsPublisher) sits outside the pinned try; a failing getter is the adapter's
                // GetValueInvocationException, a statement fault after which the foreach goes on to the next instance.
                GetValueInvocationException fault = new(String.Format(CultureInfo.InvariantCulture,
                    "Exception getting \"IsPublisher\": \"{0}\"", failure.Message), failure);
                // caller-try: continue -- without a caller try the pin goes on to the next instance; terminating would drop the remaining SqlInstance input and changes nothing on the server
                WriteError(new ErrorRecord(fault, "CatchFromBaseAdapterGetValue", ErrorCategory.NotSpecified, null));
                continue;
            }

            if (isPublisher)
            {
                try
                {
                    if (ShouldProcess(instance.ToString(), String.Format(CultureInfo.InvariantCulture, "Disabling and removing publishing on {0}", instance)))
                        RemovePublishers(replicationServer, instance);

                    replicationServer.Refresh();
                    WriteObject(wrapped);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception exception)
                {
                    StopFunction("Unable to disable replication publishing", target: instance,
                        errorRecord: FaultRecord(exception), continueLoop: true);
                    continue;
                }
            }
            else
            {
                StopFunction(String.Format(CultureInfo.InvariantCulture, "{0} isn't currently enabled for publishing.", instance),
                    target: instance, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }
        }
    }

    // The pinned Get-DbaReplServer calls Connect-DbaInstance, which forces its own EnableException on. Its Stop-Function
    // therefore writes the warning with 3>$null (never displayed, still captured by every enclosing -WarningVariable)
    // and throws the record that Get-DbaReplServer's catch receives as $_. Returns null for a failure that did not
    // come from the connection itself.
    private ErrorRecord? NestedConnectFailure(DbaInstanceParameter instance, Exception failure)
    {
        if (failure is not ConnectionResolutionException resolution)
            return null;

        const string functionName = "Connect-DbaInstance";
        MessageService.MessageRequest context = new() { FunctionName = functionName, ModuleName = "dbatools" };
        object? target = MessageService.CollapseTarget(MessageService.ResolveTarget(this, context, instance));
        string message;
        ErrorRecord record;
        bool overrideExceptionMessage;
        if (resolution.Kind == ConnectionResolutionFailure.ConnectFailure)
        {
            // PS: Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $connectionError -Continue
            Exception connectionError = MessageService.ResolveException(this, context, resolution.InnerException ?? resolution);
            string instanceText = instance.ToString();
            if (Regex.IsMatch(instanceText, "(?i)(password|pwd)\\s*="))
                instanceText = Regex.Replace(instanceText, "(?i)(password|pwd)(\\s*=\\s*)[^;]*", "$1$2****");
            string text = String.Format(CultureInfo.InvariantCulture, "Error connecting to [{0}]: {1}", instanceText,
                MessageService.GetErrorMessage(new ErrorRecord(connectionError, "dbatools_" + functionName, ErrorCategory.NotSpecified, instance)));
            message = "Failure";
            record = new ErrorRecord(new Exception(text, connectionError), "dbatools_" + functionName, ErrorCategory.ConnectionError, target);
            overrideExceptionMessage = false;
        }
        else
        {
            // PS: Stop-Function -Target $instance -Message "<refusal>" -Continue, e.g. "Azure SQL Database not supported"
            message = resolution.Message;
            record = new ErrorRecord(new Exception(message), "dbatools_" + functionName, ErrorCategory.NotSpecified, target);
            overrideExceptionMessage = true;
        }

        MessageService.MessageRequest request = new()
        {
            Level = MessageLevel.Warning,
            Message = message,
            FunctionName = functionName,
            ModuleName = "dbatools",
            Target = target,
            ErrorRecord = new[] { record },
            EnableException = true,
            OverrideExceptionMessage = overrideExceptionMessage,
            SuppressWarningDisplay = true,
            FromStopFunction = true,
            File = MyInvocation.ScriptName,
            Line = MyInvocation.ScriptLineNumber
        };
        MessageService.Write(this, request);
        return record;
    }

    // PS: $replServer.DistributionPublishers.Remove($Force). DistributionPublisherCollection has no Remove method, so
    // PowerShell member enumeration calls DistributionPublisher.Remove(bool) on every publisher in the collection, in
    // order, stopping at the first failure; an empty collection has nothing to enumerate and the call fails as
    // MethodNotFound.
    // Upstream correction publisher-scope: on a distributor that serves several publishers the pin removed every
    // registration (measured, evidence/two-publisher-scope-20261031.txt). The port removes only the registration of the
    // connected instance, registered under its @@SERVERNAME or under the name the caller gave (Enable-DbaReplPublishing
    // registers $instance), and leaves the others in place; with no registration to enumerate the pinned
    // MethodNotFound failure stays.
    private void RemovePublishers(ReplicationServer replicationServer, DbaInstanceParameter instance)
    {
        DistributionPublisherCollection publishers = replicationServer.DistributionPublishers;
        if (publishers.Count == 0)
            throw new PublisherRemovalNotFoundException();
        string publisherName = Convert.ToString(replicationServer.ConnectionContext.ExecuteScalar("SELECT @@SERVERNAME"), CultureInfo.InvariantCulture) ?? String.Empty;
        DistributionPublisher? own = null;
        foreach (object? item in (IEnumerable)publishers)
        {
            if (item is DistributionPublisher publisher && own is null
                && (String.Equals(publisher.Name, publisherName, StringComparison.OrdinalIgnoreCase)
                    || String.Equals(publisher.Name, instance.ToString(), StringComparison.OrdinalIgnoreCase)))
                own = publisher;
        }
        if (own is null)
        {
            throw new InvalidOperationException(String.Format(CultureInfo.InvariantCulture,
                "{0} is not a Publisher for {1}.", publisherName, replicationServer.Name));
        }
        try
        {
            own.Remove(Force.ToBool());
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            throw new MethodInvocationException(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"Remove\" with \"1\" argument(s): \"{0}\"", failure.Message), failure);
        }
    }

    // The record PowerShell hands the pinned catch as $_: a .NET method failure carries the inner exception's type
    // name as its error id; the empty-collection call is the binder's MethodNotFound record.
    private static ErrorRecord FaultRecord(Exception exception)
    {
        if (exception is PublisherRemovalNotFoundException)
        {
            return new ErrorRecord(new RuntimeException(
                "Method invocation failed because [Microsoft.SqlServer.Replication.DistributionPublisherCollection] does not contain a method named 'Remove'."),
                "MethodNotFound", ErrorCategory.InvalidOperation, null);
        }
        if (exception is MethodInvocationException call && call.InnerException is not null)
            return new ErrorRecord(call, call.InnerException.GetType().Name, ErrorCategory.NotSpecified, null);
        return new ErrorRecord(exception, exception.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    private sealed class PublisherRemovalNotFoundException : Exception
    {
    }
}
