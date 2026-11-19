#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Runtime.InteropServices;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.dbaSystem;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using DmfPolicyStore = Microsoft.SqlServer.Management.Dmf.PolicyStore;
using SqlStoreConnection = Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves database subscriptions to Policy-Based Management categories that control automatic policy evaluation.
/// </summary>
/// <para>
/// Retrieves all database subscriptions to policy categories from SQL Server's Policy-Based Management feature. These subscriptions determine which databases are subject to automatic policy evaluation for specific policy categories. When a database subscribes to a category (either voluntarily or through mandatory subscription), all policies in that category will be automatically evaluated against the database. This is essential for auditing policy compliance, troubleshooting evaluation failures, and understanding which databases are governed by which policy sets.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPbmCategorySubscription -SqlInstance sql2016
/// </code>
/// <para>
/// Returns all policy category subscriptions from the sql2016 PBM server
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPbmCategorySubscription -SqlInstance sql2016 -SqlCredential $cred
/// </code>
/// <para>
/// Uses a credential $cred to connect and return all policy category subscriptions from the sql2016 PBM server
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Policy, PolicyBasedManagement, PBM
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaPbmCategorySubscription" />
// No [OutputType]: the pin declares none, and the DMF types load at run time through Add-PbmLibrary.
[Cmdlet(VerbsCommon.Get, "DbaPbmCategorySubscription")]
public sealed class GetDbaPbmCategorySubscriptionCommand : DbaBaseCmdlet
{
    // The nested commands the pin calls without -EnableException, whose messages carry their own names.
    private const string StoreReader = "Get-DbaPbmStore";
    private const string LibraryLoader = "Add-PbmLibrary";
    private const string ConnectRunner = "Connect-DbaInstance";

    // PS: Select-DefaultView -InputObject $current -ExcludeProperty Properties, Urn, Parent
    private static readonly string[] SubscriptionHidden = { "Properties", "Urn", "Parent" };

    // PS (Get-DbaPbmStore): Select-DefaultView -InputObject $store -ExcludeProperty SqlStoreConnection, ConnectionContext,
    //     Properties, Urn, Parent, DomainInstanceName, Metadata, IdentityKey, Name
    private static readonly string[] StoreHidden =
    {
        "SqlStoreConnection", "ConnectionContext", "Properties", "Urn", "Parent", "DomainInstanceName", "Metadata", "IdentityKey", "Name"
    };

    // The note properties the pin copies from the store onto each subscription with Add-Member -Force, in its order.
    private static readonly string[] CopiedProperties = { "ComputerName", "InstanceName", "SqlInstance" };

    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
    /// to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

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
    /// Accepts Policy-Based Management store objects from Get-DbaPbmStore for pipeline processing.
    /// Use this when you need to query category subscriptions from an already retrieved PBM store object, improving performance
    /// when working with multiple PBM operations on the same instance.
    /// </para>
    [Parameter(Position = 2, ValueFromPipeline = true)]
    public PSObject[]? InputObject { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    // PS: begin { Add-PbmLibrary }
    protected override void BeginProcessing()
    {
        AddPbmLibrary();
    }

    // PS: if (Test-FunctionInterrupt) { return } -- no Stop-Function runs in this function's own scope (each one is inside
    // Add-PbmLibrary or the nested Get-DbaPbmStore), so the latch is never set and the check never returns.
    protected override void ProcessRecord()
    {
        // PS: foreach ($instance in $SqlInstance) { $InputObject += Get-DbaPbmStore -SqlInstance $instance -SqlCredential $SqlCredential }
        // Every store of this record is gathered first, so every connection message comes before the first subscription.
        List<PSObject?> stores = new();
        if (InputObject is not null)
        {
            stores.AddRange(InputObject);
        }

        if (SqlInstance is not null)
        {
            foreach (DbaInstanceParameter instance in SqlInstance)
            {
                PSObject? store = ReadStore(instance);
                if (store is not null)
                {
                    stores.Add(store);
                }
            }
        }

        // PS: foreach ($store in $InputObject)
        foreach (PSObject? store in stores)
        {
            WriteSubscriptions(store);
        }
    }

    // Add-PbmLibrary: loads the DMF assemblies from the library's lib folder. Its Stop-Function runs in the helper's own scope
    // without -EnableException, so a failure warns under the helper's name and stops nothing.
    private void AddPbmLibrary()
    {
        try
        {
            string libraryLib = Path.GetDirectoryName(typeof(DmfLibrary).Assembly.Location) ?? "";
            DmfLibrary.Load(Path.GetDirectoryName(libraryLib) ?? "");
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WarnNestedStopFunction(LibraryLoader, "Could not load DMF libraries",
                errorRecord: new ErrorRecord(failure, "dbatools_" + LibraryLoader, ErrorCategory.NotSpecified, null));
        }
    }

    // PS: Get-DbaPbmStore -SqlInstance $instance -SqlCredential $SqlCredential, one call per instance and without
    // -EnableException: its begin block loads the library again, and its refusal and connection failures warn under its
    // name whatever this command's -EnableException, and that instance then brings no store.
    private PSObject? ReadStore(DbaInstanceParameter instance)
    {
        AddPbmLibrary();

        // PS: if ($IsLinux -or $IsMacOS) { Stop-Function -Message "This command is not supported on Linux or macOS"; return }
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux) || RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            WarnNestedStopFunction(StoreReader, "This command is not supported on Linux or macOS");
            return null;
        }

        // PS: try { $server = Connect-DbaInstance ... -MinimumVersion 10; New-Object ...SqlStoreConnection; New-Object ...PolicyStore }
        //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
        Server server;
        DmfPolicyStore policyStore;
        try
        {
            server = ConnectNested(instance);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record = new(failure, "dbatools_" + StoreReader, ErrorCategory.ConnectionError, instance);
            if (failure is ConnectionResolutionException resolution && resolution.Kind == ConnectionResolutionFailure.ConnectFailure)
            {
                string line = String.Format(CultureInfo.InvariantCulture, "Failure | Error connecting to [{0}]: {1}",
                    MaskedTargetText(instance), MessageService.GetErrorMessage(record));
                WarnNestedStopFunction(StoreReader, line, target: instance, errorRecord: record, category: ErrorCategory.ConnectionError,
                    overrideExceptionMessage: true);
                return null;
            }

            // A refusal (MinimumVersion, or correction azure-unsupported) is not a failed connection and keeps the plain text.
            WarnNestedStopFunction(StoreReader, "Failure", target: instance, errorRecord: record, category: ErrorCategory.ConnectionError);
            return null;
        }

        try
        {
            // DMF is the Declarative Management Framework, Policy Based Management's old name
            policyStore = new DmfPolicyStore(new SqlStoreConnection(server.ConnectionContext.SqlConnectionObject));
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WarnNestedStopFunction(StoreReader, "Failure", target: instance,
                errorRecord: new ErrorRecord(failure, "dbatools_" + StoreReader, ErrorCategory.ConnectionError, instance),
                category: ErrorCategory.ConnectionError);
            return null;
        }

        // PS: Add-Member -Force ComputerName ($server.ComputerName), InstanceName ($server.ServiceName),
        //     SqlInstance ($server.DomainInstanceName); then Select-DefaultView. The store is reachable as each subscription's Parent.
        PSObject store = PSObject.AsPSObject(policyStore);
        OutputHelper.AddInstanceProperties(store, server);
        OutputHelper.SetDefaultDisplayPropertySetExcluding(store, StoreHidden);
        return store;
    }

    // PS: Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10 inside the nested
    // Get-DbaPbmStore. Correction azure-unsupported: Policy-Based Management keeps everything in msdb, which Azure SQL Database
    // does not have, so the connect refuses it as Connect-DbaInstance -AzureUnsupported does.
    private Server ConnectNested(DbaInstanceParameter instance)
    {
        SmoConnectionRequest request = new();
        request.Instance = instance;
        request.SqlCredential = SqlCredential;
        request.MinimumVersion = 10;
        request.AzureUnsupported = true;
        request.BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "SqlInstance", "SqlCredential", "MinimumVersion", "AzureUnsupported"
        };
        request.MessageCallback = (level, message) => WriteAttributedMessage(ConnectRunner, level, message);
        WriteAttributedMessage(ConnectRunner, MessageLevel.Debug, "Starting process block");
        Server server = ConnectionService.GetServer(request);
        SetActiveConnection(server.ConnectionContext);
        WriteAttributedMessage(ConnectRunner, MessageLevel.Debug, "We are finished with this instance");
        return server;
    }

    // PS: $all = $store.PolicycategorySubscriptions; foreach ($current in $all) { ... }
    private void WriteSubscriptions(PSObject? store)
    {
        // $null.PolicycategorySubscriptions is $null, and foreach over $null runs no iteration.
        if (store is null)
        {
            return;
        }

        object? all = MemberValue(store, "PolicyCategorySubscriptions");
        if (all is null)
        {
            return;
        }

        IEnumerator? enumerator;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(all);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ReportFault(EnumerationFault(failure, null));
            return;
        }

        // foreach over a value PowerShell does not enumerate runs once, with the value itself.
        if (enumerator is null)
        {
            WriteSubscription(all, store);
            return;
        }

        while (true)
        {
            object? current;
            try
            {
                if (!enumerator.MoveNext())
                {
                    break;
                }

                current = enumerator.Current;
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                // The foreach statement ends at the fault; what it already emitted stays, and the next store follows.
                ReportFault(EnumerationFault(failure, enumerator));
                return;
            }

            WriteSubscription(current, store);
        }
    }

    // PS: the loop body - Write-Message, three Add-Member -Force note properties read from the store, then Select-DefaultView.
    private void WriteSubscription(object? current, PSObject store)
    {
        // A DMF subscription collection holds no null element; Select-DefaultView returns nothing for $null.
        if (current is null)
        {
            return;
        }

        PSObject output = PSObject.AsPSObject(current);
        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Processing {0}", output));

        foreach (string name in CopiedProperties)
        {
            // PS: Add-Member -Force -InputObject $current -MemberType NoteProperty <name> -value $store.<name>
            object? value = MemberValue(store, name);
            output.Properties.Remove(name);
            // style-ok: cs-output-props the values are the store's own note properties, which a piped store carries without a Server
            output.Properties.Add(new PSNoteProperty(name, value));
        }

        OutputHelper.SetDefaultDisplayPropertySetExcluding(output, SubscriptionHidden);
        WriteObject(output);
    }

    // $object.<name> as PowerShell reads it outside strict mode: a dictionary's key first, else the member, else $null. A member
    // whose getter fails reads as $null, with no error a try can catch: measured on this item's red (result
    // 20261111T1512290677902Z, every leg: the script read of a throwing alias property raised nothing) and on the pin for
    // Get-DbaLinkedServer's $server.LinkedServers (item evidence pin-azure-lsgetter).
    private static object? MemberValue(PSObject target, string name)
    {
        if (target.BaseObject is IDictionary dictionary && dictionary.Contains(name))
        {
            return dictionary[name];
        }

        try
        {
            return target.Properties[name]?.Value;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // The engine's member read swallows the getter's fault outside strict mode (see above); nothing to report.
            return null;
        }
    }

    // The engine's record for a failed foreach enumeration: the one the failure carries (ExceptionInGetEnumerator), otherwise
    // the record a failing MoveNext gives (BadEnumeration, InvalidOperation, the enumerator as target).
    private static ErrorRecord EnumerationFault(Exception failure, IEnumerator? enumerator)
    {
        if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
        {
            return new ErrorRecord(container.ErrorRecord, failure);
        }

        RuntimeException enumeration = new(String.Format(CultureInfo.InvariantCulture,
            "An error occurred while enumerating through a collection: {0}.", failure.Message), failure);
        return new ErrorRecord(enumeration, "BadEnumeration", ErrorCategory.InvalidOperation, enumerator);
    }

    // A statement fault of the pin, which writes it and goes on with its next statement. Accepted difference kept by the
    // keep-going section's point 3: -EnableException stops here with this record; -ErrorAction Stop has the effect
    // PowerShell gives WriteError.
    private void ReportFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }

        // A plain call goes on; under a caller try the record stops the command, as the fault stops the pin's statement.
        StatementFault.Surface(this, fault);
    }
}
