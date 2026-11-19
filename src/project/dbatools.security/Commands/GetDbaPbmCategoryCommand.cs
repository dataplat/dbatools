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
/// Retrieves Policy-Based Management categories from SQL Server instances for governance and compliance management.
/// </summary>
/// <para>
/// Retrieves all policy categories configured in SQL Server's Policy-Based Management (PBM) feature. Policy categories help organize and group related policies for easier management and selective enforcement across database environments. This function allows DBAs to inventory existing categories, audit category assignments, and understand which categories mandate database subscriptions for automatic policy evaluation.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPbmCategory -SqlInstance sql2016
/// </code>
/// <para>
/// Returns all policy categories from the sql2016 PBM server
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPbmCategory -SqlInstance sql2016 -SqlCredential $cred
/// </code>
/// <para>
/// Uses a credential $cred to connect and return all policy categories from the sql2016 PBM server
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
/// <seealso href="https://dbatools.io/Get-DbaPbmCategory" />
// No [OutputType]: the emitted DMF PolicyCategory type ships in assemblies that Add-PbmLibrary loads at run time, and
// the pinned function declares none.
[Cmdlet(VerbsCommon.Get, "DbaPbmCategory")]
public sealed class GetDbaPbmCategoryCommand : DbaBaseCmdlet
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
    /// Filters results to only show specific policy categories by name. Accepts multiple category names for targeted retrieval.
    /// Use this when you need to check specific categories rather than retrieving all configured PBM categories.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Category { get; set; }

    /// <para>
    /// Accepts Policy-Based Management store objects from Get-DbaPbmStore for processing categories from specific stores.
    /// Use this when you need to work with categories from a pre-filtered set of PBM stores or when chaining multiple PBM commands together.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public PSObject[]? InputObject { get; set; }

    /// <para>
    /// Excludes built-in system policy categories from the results, showing only user-created categories.
    /// Use this when you want to focus on custom categories that you or your team have created, filtering out SQL Server's default categories.
    /// </para>
    [Parameter]
    public SwitchParameter ExcludeSystemObject { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    private const string StoreCommandName = "Get-DbaPbmStore";

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
        // store repeats the named instances' categories. They are read once, with the first record, as in
        // Get-DbaDbMailServer's port.
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
            WriteCategories(store);
    }

    // PS: foreach ($store in $InputObject) { ... }. $all keeps its value when one of the three statements below faults, as
    // the pin's assignment does; each statement enumerates $all again.
    private void WriteCategories(object? store)
    {
        object? all = PropertyValue(store, "PolicyCategories");

        // PS: if (-not $ExcludeSystemObject) { $all = $all | Where-Object IsSystemObject -ne $true }
        // A DMF PolicyCategory has no IsSystemObject property (Microsoft Learn, PolicyCategory class), so every
        // category passes; see the item's follow-ups for -ExcludeSystemObject.
        if (!ExcludeSystemObject.ToBool())
            all = Filter(all, item => !IsTrueValue(PropertyValue(item, "IsSystemObject")));

        // PS: if ($Category) { $all = $all | Where-Object Name -in $Category }
        if (LanguagePrimitives.IsTrue(Category))
            all = Filter(all, item => NameIn(PropertyValue(item, "Name")));

        // PS: foreach ($current in $all) { ... }; a foreach over $null runs no iteration.
        if (all is null)
            return;
        if (!Enumerate(all, out IEnumerator? enumerator))
            return;
        if (enumerator is null)
        {
            WriteCategory(all, store);
            return;
        }
        while (Next(enumerator, out object? current) == true)
            WriteCategory(current, store);
    }

    // The start of a statement's enumeration of $all: false when getting the enumerator faulted (an SFC collection loads
    // its members here, so an unavailable store faults here) and its record was reported; the statement ends there and the
    // next statement, or the next store, goes on, as in the pin.
    private bool Enumerate(object? all, out IEnumerator? enumerator)
    {
        enumerator = null;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(all);
            return true;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ReportEnumerationFault(failure, all);
            return false;
        }
    }

    // One step of a statement's enumeration of $all: true with the next item, false at the end, null when the enumeration
    // faulted and its record was reported. Only the collection's own step counts as the fault, never the output written.
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

    private void WriteCategory(object? current, object? store)
    {
        // A category collection holds no null element.
        if (current is null)
            return;
        PSObject wrapped = PSObject.AsPSObject(current);

        // PS: Write-Message -Level Verbose -Message "Processing $current"
        WriteMessage(MessageLevel.Verbose, "Processing " + wrapped.ToString());
        // PS: Add-Member -Force ComputerName, InstanceName, SqlInstance from the store; Select-DefaultView -Property ...
        ReplaceNoteProperty(wrapped, "ComputerName", PropertyValue(store, "ComputerName"));
        ReplaceNoteProperty(wrapped, "InstanceName", PropertyValue(store, "InstanceName"));
        ReplaceNoteProperty(wrapped, "SqlInstance", PropertyValue(store, "SqlInstance"));
        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
            "ComputerName", "InstanceName", "SqlInstance", "Id", "Name", "MandateDatabaseSubscriptions");
        WriteObject(wrapped);
    }

    // One "$all = $all | Where-Object ..." statement. $null pipes as one item, which both filters pass or drop as the
    // pin's do; the result is the passing items, or $all unchanged when the enumeration faults.
    private object? Filter(object? all, Func<object?, bool> keep)
    {
        List<object?> kept = new List<object?>();
        if (!Enumerate(all, out IEnumerator? enumerator))
            return all;
        if (enumerator is null)
        {
            if (keep(all))
                kept.Add(all);
        }
        else
        {
            while (true)
            {
                bool? next = Next(enumerator, out object? current);
                if (next is null)
                    return all;
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

    // PS: Where-Object Name -in $Category: $Category -contains the name, each element compared as -eq does, without case.
    private bool NameIn(object? name)
    {
        foreach (string? value in Category!)
        {
            if (LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    // PS: IsSystemObject -ne $true is false only for a value equal to $true.
    private static bool IsTrueValue(object? value)
    {
        return value is not null && LanguagePrimitives.Equals(value, true, true, CultureInfo.InvariantCulture);
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
            // Correction azure-unsupported: Policy-Based Management keeps its categories in msdb, which Azure SQL Database
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

    // A fault while a statement enumerates $all: the engine's enumeration record ends that statement.
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
