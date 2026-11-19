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
/// Retrieves Policy-Based Management policies from SQL Server instances for compliance auditing and configuration review.
/// </summary>
/// <para>
/// Retrieves all Policy-Based Management policies configured on SQL Server instances, allowing DBAs to audit compliance configurations and review policy settings across their environment. This function connects to the PBM store and returns policy details including categories, conditions, and evaluation modes. Use this when you need to document existing policies, troubleshoot policy evaluations, or verify compliance configurations without manually navigating through SQL Server Management Studio's Policy-Based Management node.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPbmPolicy -SqlInstance sql2016
/// </code>
/// <para>
/// Returns all policies from sql2016 server
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPbmPolicy -SqlInstance sql2016 -SqlCredential $cred
/// </code>
/// <para>
/// Uses a credential $cred to connect and return all policies from sql2016 instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPbmPolicy -SqlInstance sql2016 -Category MorningCheck
/// </code>
/// <para>
/// Returns all policies from sql2016 server that part of the PolicyCategory MorningCheck
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Policy, PolicyBasedManagement, PBM
/// Author: Stephen Bennett, sqlnotesfromtheunderground.wordpress.com
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaPbmPolicy" />
// No [OutputType]: the emitted DMF Policy type ships in assemblies that Add-PbmLibrary loads at run time, and the pinned
// function declares none.
[Cmdlet(VerbsCommon.Get, "DbaPbmPolicy")]
public sealed class GetDbaPbmPolicyCommand : DbaBaseCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
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
    /// Specifies one or more policy names to retrieve, filtering the results to only those policies. Supports exact name matching for targeted policy retrieval.
    /// Use this when you need to examine specific policies rather than all policies on the instance.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Policy { get; set; }

    /// <para>
    /// Filters results to show only policies belonging to specific policy categories. Categories help organize policies by function or compliance framework.
    /// Use this to focus on policies related to specific areas like security, performance, or maintenance checks.
    /// </para>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Category { get; set; }

    /// <para>
    /// Accepts PBM store objects from Get-DbaPbmStore via pipeline, allowing efficient processing of multiple instances. Enables chaining PBM commands together.
    /// Use this when building complex PBM workflows or when you already have PBM store objects from previous commands.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public PSObject[]? InputObject { get; set; }

    /// <para>
    /// Includes Microsoft's built-in system policies in the results, which are excluded by default. System policies cover standard SQL Server best practices.
    /// Use this when you need to review or document all policies including Microsoft's predefined compliance policies.
    /// </para>
    [Parameter]
    public SwitchParameter IncludeSystemObject { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    private const string StoreCommandName = "Get-DbaPbmStore";

    // PS: Select-DefaultView -ExcludeProperty ...
    private static readonly string[] HiddenProperties =
    {
        "HelpText", "HelpLink", "Urn", "Properties", "Metadata", "Parent", "IdentityKey", "HasScript", "PolicyEvaluationStarted",
        "ConnectionProcessingStarted", "TargetProcessed", "ConnectionProcessingFinished", "PolicyEvaluationFinished",
        "PropertyMetadataChanged", "PropertyChanged"
    };

    // Set once the named instances have been read (correction named-instance-repeat).
    private bool _instancesRead;

    // PS: begin { Add-PbmLibrary }
    protected override void BeginProcessing()
    {
        AddPbmLibrary();
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }. Nothing in this command sets its own stop flag: the Stop-Function
        // calls of Add-PbmLibrary and Get-DbaPbmStore run in their own scopes.
        if (Interrupted)
            return;

        // PS: foreach ($instance in $SqlInstance) { $InputObject += Get-DbaPbmStore -SqlInstance $instance -SqlCredential $SqlCredential }
        // The record's own stores come first, then each instance's store.
        // Correction named-instance-repeat: the pin reads the named instances again for every piped record, so each piped
        // store repeats the named instances' policies. They are read once, with the first record.
        List<object?> stores = new List<object?>();
        if (InputObject is not null)
            stores.AddRange(InputObject);
        if (SqlInstance is not null && !_instancesRead)
        {
            _instancesRead = true;
            foreach (DbaInstanceParameter? instance in SqlInstance)
            {
                if (instance is null)
                {
                    ReportNestedBindingFault();
                    continue;
                }
                PSObject? store = GetStore(instance);
                if (store is not null)
                    stores.Add(store);
            }
        }

        foreach (object? store in stores)
            WritePolicies(store);
    }

    // PS: foreach ($store in $InputObject) { ... }. $allpolicies keeps its value when one of the filter statements faults,
    // as the pin's assignment does; each statement enumerates $allpolicies again.
    private void WritePolicies(object? store)
    {
        object? allPolicies = PropertyValue(store, "Policies");

        // PS: if (-not $IncludeSystemObject) { $allpolicies = $allpolicies | Where-Object IsSystemObject -eq $false }
        if (!IncludeSystemObject.ToBool())
            allPolicies = Filter(allPolicies, item => IsFalseValue(PropertyValue(item, "IsSystemObject")));

        // PS: if ($Category) { $allpolicies = $allpolicies | Where-Object PolicyCategory -in $Category }
        if (LanguagePrimitives.IsTrue(Category))
            allPolicies = Filter(allPolicies, item => ValueIn(Category!, PropertyValue(item, "PolicyCategory")));

        // PS: if ($Policy) { $allpolicies = $allpolicies | Where-Object Name -in $Policy }
        if (LanguagePrimitives.IsTrue(Policy))
            allPolicies = Filter(allPolicies, item => ValueIn(Policy!, PropertyValue(item, "Name")));

        // PS: foreach ($currentpolicy in $allpolicies) { ... }; a foreach over $null runs no iteration.
        if (allPolicies is null)
            return;
        if (!Enumerate(allPolicies, out IEnumerator? enumerator))
            return;
        if (enumerator is null)
        {
            WritePolicy(allPolicies, store);
            return;
        }
        while (Next(enumerator, out object? current) == true)
            WritePolicy(current, store);
    }

    // The start of a statement's enumeration of $allpolicies: false when getting the enumerator faulted (an SFC collection
    // loads its members here, so an unavailable store faults here) and its record was reported; the statement ends there
    // and the next statement, or the next store, goes on, as in the pin.
    private bool Enumerate(object? allPolicies, out IEnumerator? enumerator)
    {
        enumerator = null;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(allPolicies);
            return true;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ReportEnumerationFault(failure, allPolicies);
            return false;
        }
    }

    // One step of a statement's enumeration of $allpolicies: true with the next item, false at the end, null when the
    // enumeration faulted and its record was reported. Only the collection's own step counts as the fault, never the
    // output written.
    private bool? Next(IEnumerator enumerator, out object? current)
    {
        current = null;
        try
        {
            if (!enumerator.MoveNext())
                return false;
            current = enumerator.Current;
            return true;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ReportEnumerationFault(failure, enumerator);
            return null;
        }
    }

    private void WritePolicy(object? current, object? store)
    {
        // A policy collection holds no null element.
        if (current is null)
            return;
        PSObject wrapped = PSObject.AsPSObject(current);

        // PS: Write-Message -Level Verbose -Message "Processing $currentpolicy"
        WriteMessage(MessageLevel.Verbose, "Processing " + wrapped.ToString());
        // PS: Add-Member -Force ComputerName, InstanceName, SqlInstance from the store
        ReplaceNoteProperty(wrapped, "ComputerName", PropertyValue(store, "ComputerName"));
        ReplaceNoteProperty(wrapped, "InstanceName", PropertyValue(store, "InstanceName"));
        ReplaceNoteProperty(wrapped, "SqlInstance", PropertyValue(store, "SqlInstance"));
        // PS: Select-DefaultView -InputObject $currentpolicy -ExcludeProperty HelpText, HelpLink, ...
        OutputHelper.SetDefaultDisplayPropertySetExcluding(wrapped, HiddenProperties);
        WriteObject(wrapped);
    }

    // One "$allpolicies = $allpolicies | Where-Object ..." statement. $null pipes as one item, which the filters pass or
    // drop as the pin's do; the result is the passing items, or $allpolicies unchanged when the enumeration faults.
    private object? Filter(object? allPolicies, Func<object?, bool> keep)
    {
        List<object?> kept = new List<object?>();
        if (!Enumerate(allPolicies, out IEnumerator? enumerator))
            return allPolicies;
        if (enumerator is null)
        {
            if (keep(allPolicies))
                kept.Add(allPolicies);
        }
        else
        {
            while (true)
            {
                bool? next = Next(enumerator, out object? current);
                if (next is null)
                    return allPolicies;
                if (next == false)
                    break;
                if (keep(current))
                    kept.Add(current);
            }
        }
        if (kept.Count == 0)
            return null;
        if (kept.Count == 1)
            return kept[0];
        return kept.ToArray();
    }

    // PS: Where-Object <property> -in $values: $values -contains the value, each element compared as -eq does, without case.
    private static bool ValueIn(string[] values, object? value)
    {
        foreach (string? element in values)
        {
            if (LanguagePrimitives.Equals(element, value, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    // PS: IsSystemObject -eq $false holds only for a value equal to $false; $null is not.
    private static bool IsFalseValue(object? value)
    {
        return value is not null && LanguagePrimitives.Equals(value, false, true, CultureInfo.InvariantCulture);
    }

    // PS member access: a missing member, or a null object, reads $null.
    private static object? PropertyValue(object? source, string name)
    {
        if (source is null)
            return null;
        PSPropertyInfo? property = PSObject.AsPSObject(source).Properties[name];
        return property?.Value;
    }

    private static void ReplaceNoteProperty(PSObject wrapped, string name, object? value)
    {
        wrapped.Properties.Remove(name);
        wrapped.Properties.Add(new PSNoteProperty(name, value));
    }

    // The nested Get-DbaPbmStore: begin { Add-PbmLibrary }, then its process block for one instance. Its Stop-Function
    // calls run without -EnableException, because the pinned call passes none, so they only warn under its name.
    private PSObject? GetStore(DbaInstanceParameter instance)
    {
        AddPbmLibrary();

        // PS: if ($IsLinux -or $IsMacOS) { Stop-Function -Message "This command is not supported on Linux or macOS"; return }
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux) || RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            WarnNestedStopFunction(StoreCommandName, "This command is not supported on Linux or macOS");
            return null;
        }

        try
        {
            Server server = Connect(instance);
            // PS: New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $server.ConnectionContext.SqlConnectionObject
            //     New-Object Microsoft.SqlServer.Management.DMF.PolicyStore $sqlStoreConnection
            PSObject store = NewStore(server);
            // PS: Add-Member -Force ComputerName ($server.ComputerName), InstanceName ($server.ServiceName),
            // SqlInstance ($server.DomainInstanceName)
            OutputHelper.AddInstanceProperties(store, server);
            return store;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS: Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            ErrorRecord record = new ErrorRecord(failure, "dbatools_" + StoreCommandName, ErrorCategory.ConnectionError, instance);
            WarnNestedStopFunction(StoreCommandName, "Failure", instance, record, ErrorCategory.ConnectionError);
            return null;
        }
    }

    // PS: Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
    private Server Connect(DbaInstanceParameter instance)
    {
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        Server server = ConnectionService.GetServer(new SmoConnectionRequest
        {
            Instance = instance,
            SqlCredential = SqlCredential,
            MinimumVersion = 10,
            // Correction azure-unsupported: Policy-Based Management keeps its policies in msdb, which Azure SQL Database
            // does not have, so the store refuses it as Connect-DbaInstance -AzureUnsupported does.
            AzureUnsupported = true,
            BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "MinimumVersion", "AzureUnsupported" },
            MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
        });
        SetActiveConnection(server.ConnectionContext);
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
        return server;
    }

    // Its own method, so the DMF types bind only after Add-PbmLibrary has loaded them.
    private static PSObject NewStore(Server server)
    {
        return PSObject.AsPSObject(new DmfPolicyStore(new SqlStoreConnection(server.ConnectionContext.SqlConnectionObject)));
    }

    // Add-PbmLibrary: loads the DMF assemblies from the library's lib folder. Its Stop-Function runs in the helper's own
    // scope without -EnableException, so a failure warns and does not stop this command.
    private void AddPbmLibrary()
    {
        try
        {
            string libraryLib = Path.GetDirectoryName(typeof(DmfLibrary).Assembly.Location) ?? "";
            DmfLibrary.Load(Path.GetDirectoryName(libraryLib) ?? "");
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WriteAttributedMessage("Add-PbmLibrary", MessageLevel.Warning, "Could not load DMF libraries", exception: failure);
        }
    }

    // A null element of -SqlInstance reaches Get-DbaPbmStore, whose mandatory -SqlInstance binder refuses it. The fault ends
    // the pin's "$InputObject += Get-DbaPbmStore ..." statement, and its loop goes on to the next instance.
    private void ReportNestedBindingFault()
    {
        ErrorRecord fault = new(new ParameterBindingException("Cannot bind argument to parameter 'SqlInstance' because it is null."),
            "ParameterArgumentValidationErrorNullNotAllowed", ErrorCategory.InvalidData, null);
        // The binder's own exception type is internal, so the record carries its public base and the Reason callers read.
        fault.CategoryInfo.Reason = "ParameterBindingValidationException";
        // The pin's activity is the nested command when the caller has no try and the call has no -ErrorAction Stop. Under a
        // caller's try or that switch the fault leaves through this command, and the engine's default activity, this
        // cmdlet's name, is already the pin's.
        bool stopAsked = MyInvocation.BoundParameters.TryGetValue("ErrorAction", out object? errorAction)
            && String.Equals(LanguagePrimitives.ConvertTo<string>(errorAction), "Stop", StringComparison.OrdinalIgnoreCase);
        if (!stopAsked && !StatementFault.CallerHasEnclosingTry(this))
            fault.CategoryInfo.Activity = StoreCommandName;

        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop (keep-going point 3); the pin writes the record and goes on
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams binder fault of the nested Get-DbaPbmStore, outside Stop-Function, as in the pin
        }

        // A plain call writes the record and goes on to the next instance, as the pin does; under a caller's try the record
        // stops the command, as the binder fault stops the pin.
        StatementFault.Surface(this, fault);
    }

    // A fault while a statement enumerates $allpolicies: the engine's enumeration record ends that statement.
    private void ReportEnumerationFault(Exception failure, object? enumerator)
    {
        ErrorRecord record;
        if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
        {
            record = new ErrorRecord(container.ErrorRecord, failure);
        }
        else
        {
            RuntimeException fault = new(String.Format(CultureInfo.InvariantCulture,
                "An error occurred while enumerating through a collection: {0}.", failure.Message), failure);
            record = new ErrorRecord(fault, "BadEnumeration", ErrorCategory.InvalidOperation, enumerator);
        }
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop (keep-going point 3); the pin writes the record and goes on
            ThrowTerminatingError(record); // style-ok: cs-raw-streams the enumeration fault of the pinned statement, outside Stop-Function
        }
        StatementFault.Surface(this, record);
    }
}
