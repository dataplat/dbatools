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
using DmfCondition = Microsoft.SqlServer.Management.Dmf.Condition;
using DmfPolicyStore = Microsoft.SqlServer.Management.Dmf.PolicyStore;
using SqlStoreConnection = Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves Policy-Based Management conditions from SQL Server instances for compliance monitoring and policy evaluation.</summary>
/// <para>Retrieves Policy-Based Management (PBM) conditions from SQL Server instances, which define the rules and criteria used to evaluate database objects for compliance. These conditions form the building blocks of PBM policies and specify what to check (like database settings, table properties, or server configurations) and what values are acceptable. Use this to audit existing conditions, troubleshoot policy failures, or inventory your compliance framework across multiple instances.</para>
/// <example><code>PS C:\&gt; Get-DbaPbmCondition -SqlInstance sql2016</code>
/// <para>Returns all conditions from the sql2016 PBM server</para></example>
/// <example><code>PS C:\&gt; Get-DbaPbmCondition -SqlInstance sql2016 -SqlCredential $cred</code>
/// <para>Uses a credential $cred to connect and return all conditions from the sql2016 PBM server</para></example>
/// <list type="alertSet"><item><term></term><description>
/// <para>Tags: Policy, PolicyBasedManagement, PBM Author: Chrissy LeMaire (@cl), netnerds.net</para>
/// <para>Website: https://dbatools.io Copyright: (c) 2018 by dbatools, licensed under MIT License: MIT https://opensource.org/licenses/MIT</para>
/// </description></item><item><term>OUTPUTS</term><description>
/// <para>Microsoft.SqlServer.Management.Dmf.Condition</para>
/// <para>Returns one condition object for each policy condition found on the specified PBM store. Conditions define the rules and criteria used to evaluate database objects for compliance with policies.</para>
/// <para>Default display properties (via Select-DefaultView): - ComputerName: The computer name of the SQL Server instance - InstanceName: The SQL Server instance name - SqlInstance: The full SQL Server instance name (computer\instance) - Id: Unique identifier for the condition - Name: The name of the condition - CreateDate: DateTime when the condition was created - CreatedBy: User who created the condition - DateModified: DateTime when the condition was last modified - Description: Description of the condition - ExpressionNode: The expression tree that defines the condition logic - Facet: The facet that the condition applies to (management area such as Database, Server, Table, etc.) - HasScript: Boolean indicating if the condition contains a dynamic script expression - IsSystemObject: Boolean indicating if this is a system-provided condition or user-created - ModifiedBy: User who last modified the condition</para>
/// <para>Additional properties available via Select-Object *: - IsEnumerable: Boolean indicating if the condition can be used as a target set level filter - Parent: Reference to the parent PolicyStore object - State: Current state of the condition object (Existing, Creating, Pending, etc.) - Urn: Uniform Resource Name (URN) for the condition object - IdentityKey: Identity key of the condition object - Metadata: Metadata information - KeyChain: Identity path of the condition object - Properties: Properties collection for the condition</para>
/// </description></item></list>
/// <seealso href="https://dbatools.io/Get-DbaPbmCondition" />
[Cmdlet(VerbsCommon.Get, "DbaPbmCondition")]
[OutputType(typeof(DmfCondition))]
public sealed class GetDbaPbmConditionCommand : DbaBaseCmdlet
{
    /// <para>The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.</para>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <para>Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).</para>
    /// <para>Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.</para>
    /// <para>For MFA support, please use Connect-DbaInstance.</para>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <para>Filters results to only return conditions that match the specified names. Accepts multiple condition names and supports wildcards. Use this when you need to examine specific PBM conditions rather than retrieving all conditions from the instance.</para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Condition { get; set; }

    /// <para>Accepts Policy-Based Management store objects from Get-DbaPbmStore via pipeline input. This allows you to chain commands and work with multiple PBM stores efficiently. Use this when processing conditions from multiple instances or when working with previously retrieved PBM store objects.</para>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public PSObject[]? InputObject { get; set; }

    /// <para>Includes built-in system conditions in the results, which are filtered out by default. System conditions are predefined by SQL Server for common compliance scenarios. Use this when you need to see all available conditions including Microsoft's built-in templates for policy creation.</para>
    [Parameter]
    public SwitchParameter IncludeSystemObject { get; set; }

    /// <para>By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message. This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting. Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.</para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    private static readonly string[] InstanceProperties = { "ComputerName", "InstanceName", "SqlInstance" };
    private static readonly string[] DisplayProperties = {
        "ComputerName", "InstanceName", "SqlInstance", "Id", "Name", "CreateDate", "CreatedBy",
        "DateModified", "Description", "ExpressionNode", "Facet", "HasScript", "IsSystemObject", "ModifiedBy"
    };
    private bool _instancesRead;
    private bool _instancePipeline;

    protected override void BeginProcessing()
    {
        _instancePipeline = MyInvocation.ExpectingInput && !MyInvocation.BoundParameters.ContainsKey(nameof(InputObject));
        AddPbmLibrary();
    }

    protected override void ProcessRecord()
    {
        if (Interrupted) return;
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            StopFunction("This command is not supported on Linux or macOS");
            return;
        }

        List<PSObject> stores = new();
        if (InputObject is not null)
            foreach (PSObject store in InputObject)
            {
                if (store is null) continue;
                PSObject? resolved = store;
                // The documented instance pipeline form uses the existing InputObject binding.
                if (_instancePipeline && store.Properties["Conditions"] is null)
                {
                    DbaInstanceParameter? instance = store.BaseObject switch
                    {
                        DbaInstanceParameter parameter => parameter,
                        string name => new DbaInstanceParameter(name),
                        Server server => new DbaInstanceParameter(server),
                        _ => null
                    };
                    if (instance is not null) resolved = OpenStore(instance);
                }
                if (resolved is not null) stores.Add(resolved);
            }

        if (SqlInstance is not null && !_instancesRead)
        {
            _instancesRead = true;
            foreach (DbaInstanceParameter instance in SqlInstance)
            {
                CancellationToken.ThrowIfCancellationRequested();
                if (instance is null)
                {
                    ReportNullInstance();
                    continue;
                }
                PSObject? store = OpenStore(instance);
                if (store is not null) stores.Add(store);
            }
        }

        foreach (PSObject store in stores)
        {
            CancellationToken.ThrowIfCancellationRequested();
            object? conditions = Property(store, "Conditions");
            if (conditions is null) continue;
            List<PSObject>? scope = null;
            if (!IncludeSystemObject)
            {
                List<PSObject>? loaded = ReadConditions(conditions);
                if (loaded is not null)
                {
                    scope = loaded;
                    conditions = loaded.FindAll(condition => LanguagePrimitives.Equals(Property(condition, "IsSystemObject"), false, true, CultureInfo.InvariantCulture));
                }
            }
            if (LanguagePrimitives.IsTrue(Condition))
            {
                List<PSObject>? loaded = ReadConditions(conditions);
                if (loaded is not null)
                {
                    // A real name containing * or ? remains literal, including names hidden by the system filter.
                    WildcardNameMatcher? matcher = Array.Exists(Condition!, WildcardNameFilter.IsPatternCandidate)
                        ? WildcardNameFilter.CreateMatcher(Condition, true,
                            (filter, name) => LanguagePrimitives.Equals(filter, name, true, CultureInfo.InvariantCulture),
                            (scope ?? loaded).ConvertAll(condition => LanguagePrimitives.ConvertTo<string>(Property(condition, "Name"))))
                        : null;
                    conditions = loaded.FindAll(condition => matcher is null
                        ? Array.Exists(Condition!, filter => LanguagePrimitives.Equals(filter, Property(condition, "Name"), true, CultureInfo.InvariantCulture))
                        : matcher.Matches(LanguagePrimitives.ConvertTo<string>(Property(condition, "Name"))));
                }
            }

            VisitConditions(conditions, condition => EmitCondition(condition, store));
        }
    }

    // Each pinned filter assigns only after its pipeline succeeds; a fault leaves the original collection for the next statement.
    private List<PSObject>? ReadConditions(object conditions)
    {
        List<PSObject> loaded = new();
        return VisitConditions(conditions, loaded.Add, filtering: true) ? loaded : null;
    }

    private bool VisitConditions(object conditions, Action<PSObject> visit, bool filtering = false)
    {
        IEnumerator? iterator;
        try { iterator = LanguagePrimitives.GetEnumerator(conditions); }
        catch (Exception failure) when (failure is not PipelineStoppedException && failure is not OperationCanceledException)
        {
            ReportEnumerationFault(failure, null, filtering);
            return false;
        }
        if (iterator is null)
        {
            visit(PSObject.AsPSObject(conditions));
            return true;
        }
        try
        {
            while (true)
            {
                CancellationToken.ThrowIfCancellationRequested();
                object? current;
                try
                {
                    if (!iterator.MoveNext()) return true;
                    current = iterator.Current;
                }
                catch (Exception failure) when (failure is not PipelineStoppedException && failure is not OperationCanceledException)
                {
                    ReportEnumerationFault(failure, iterator, filtering);
                    return false;
                }
                if (current is not null) visit(PSObject.AsPSObject(current));
            }
        }
        finally { (iterator as IDisposable)?.Dispose(); }
    }

    private void ReportEnumerationFault(Exception failure, IEnumerator? iterator, bool filtering)
    {
        ErrorRecord fault = failure is IContainsErrorRecord container && container.ErrorRecord is not null
            ? new ErrorRecord(container.ErrorRecord, failure)
            : filtering ? new ErrorRecord(new RuntimeException(String.Format(CultureInfo.InvariantCulture,
                "An error occurred while enumerating through a collection: {0}.", failure.Message), failure),
                "BadEnumeration", ErrorCategory.InvalidOperation, iterator)
            // The pinned foreach surfaces the original MoveNext exception, unlike its filter pipelines.
            : new ErrorRecord(failure, failure.GetType().FullName, ErrorCategory.OperationStopped, null);
        if (EnableException)
            // caller-try: terminate -- -EnableException requests a stop for the pinned enumeration fault.
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams preserve the pinned statement-fault record.
        StatementFault.Surface(this, fault);
    }

    private void EmitCondition(PSObject condition, PSObject store)
    {
        WriteMessage(MessageLevel.Verbose, "Processing " + condition);
        foreach (string name in InstanceProperties)
        {
            condition.Properties.Remove(name);
            condition.Properties.Add(new PSNoteProperty(name, Property(store, name)));
        }
        OutputHelper.SetDefaultDisplayPropertySet(condition, DisplayProperties);
        WriteObject(condition);
    }

    private void ReportNullInstance()
    {
        ErrorRecord fault = new(new ParameterBindingException("Cannot bind argument to parameter 'SqlInstance' because it is null."),
            "ParameterArgumentValidationErrorNullNotAllowed", ErrorCategory.InvalidData, null);
        fault.CategoryInfo.Reason = "ParameterBindingValidationException";
        bool stopAsked = MyInvocation.BoundParameters.TryGetValue("ErrorAction", out object? action)
            && String.Equals(LanguagePrimitives.ConvertTo<string>(action), "Stop", StringComparison.OrdinalIgnoreCase);
        if (!stopAsked && !StatementFault.CallerHasEnclosingTry(this))
            fault.CategoryInfo.Activity = "Get-DbaPbmStore";
        if (EnableException)
            // caller-try: terminate -- -EnableException requests a stop for the nested binder fault.
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams preserve the nested binder record under the installed EnableException stop contract.
        StatementFault.Surface(this, fault);
    }

    private PSObject? OpenStore(DbaInstanceParameter instance)
    {
        // Get-DbaPbmStore has its own begin block and does not receive this command's EnableException.
        AddPbmLibrary();
        void Relay(MessageLevel level, string message) => WriteAttributedMessage("Connect-DbaInstance", level, message);
        try
        {
            Relay(MessageLevel.Debug, "Starting process block");
            Server server = ConnectionService.GetServer(new SmoConnectionRequest
            {
                Instance = instance,
                SqlCredential = SqlCredential,
                MinimumVersion = 10,
                AzureUnsupported = true,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "MinimumVersion", "AzureUnsupported" },
                MessageCallback = Relay
            });
            SetActiveConnection(server.ConnectionContext);
            Relay(MessageLevel.Debug, "We are finished with this instance");
            PSObject store = PSObject.AsPSObject(new DmfPolicyStore(new SqlStoreConnection(server.ConnectionContext.SqlConnectionObject)));
            OutputHelper.AddInstanceProperties(store, server);
            return store;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException && failure is not OperationCanceledException)
        {
            ErrorRecord record = new(failure, "dbatools_Get-DbaPbmStore", ErrorCategory.ConnectionError, instance);
            if (failure is ConnectionResolutionException resolution && resolution.Kind == ConnectionResolutionFailure.ConnectFailure)
            {
                string message = String.Format("Failure | Error connecting to [{0}]: {1}", MaskedTargetText(instance), MessageService.GetErrorMessage(record));
                WarnNestedStopFunction("Get-DbaPbmStore", message, instance, record, ErrorCategory.ConnectionError, overrideExceptionMessage: true);
            }
            else
                WarnNestedStopFunction("Get-DbaPbmStore", "Failure", instance, record, ErrorCategory.ConnectionError);
            return null;
        }
    }

    private void AddPbmLibrary()
    {
        try
        {
            string libraryLib = Path.GetDirectoryName(typeof(DmfLibrary).Assembly.Location) ?? "";
            DmfLibrary.Load(Path.GetDirectoryName(libraryLib) ?? "");
        }
        catch (Exception failure) when (failure is not PipelineStoppedException && failure is not OperationCanceledException)
        {
            WarnNestedStopFunction("Add-PbmLibrary", "Could not load DMF libraries",
                errorRecord: new ErrorRecord(failure, "dbatools_Add-PbmLibrary", ErrorCategory.NotSpecified, null));
        }
    }

    private static object? Property(PSObject value, string name)
    {
        try { return value.Properties[name]?.Value; }
        catch (GetValueException) { return null; } // PowerShell member access yields null for a failed getter.
    }
}

