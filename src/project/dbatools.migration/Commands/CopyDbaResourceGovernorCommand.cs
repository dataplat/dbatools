#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Copies Resource Governor pools, workload groups and the classifier function through SMO. Port of public/Copy-DbaResourceGovernor.ps1.
/// <summary>Copies SQL Server Resource Governor configuration including pools, workload groups, and classifier functions between instances</summary>
[Cmdlet(VerbsCommon.Copy, "DbaResourceGovernor", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaResourceGovernorCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance. Requires sysadmin and SQL Server 2008 or higher.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>The destination SQL Server instances.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Only copy the resource pools with these names.</summary>
    [Parameter(Position = 4)]
    public object[]? ResourcePool { get; set; }

    /// <summary>Skip the resource pools with these names.</summary>
    [Parameter(Position = 5)]
    public object[]? ExcludeResourcePool { get; set; }

    /// <summary>Drop and recreate pools, workload groups and the classifier function that already exist on the destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private const string Reconfigure = "ALTER RESOURCE GOVERNOR RECONFIGURE;";
    private const string EditionMessage = "The resource governor is not available in this edition of SQL Server. You can manipulate resource governor metadata but you will not be able to apply resource governor configuration. Only Enterprise edition of SQL Server supports resource governor.";
    private const string SettingsType = "Resource Governor Settings";

    private Server _source = null!;

    // The source's function-scope variables. Correction per-pool-rows: they are reset per pool and per destination,
    // where the source carried them over and reported an earlier pool's workload group or destination's fault.
    private PSObject? _workloadRow;
    private string? _workloadName;
    private object? _alterMessage;

    protected override void ProcessRecord()
    {
        Server? source = Connect(Source, SourceSqlCredential, continueLoop: false);
        if (source is null)
            return;
        _source = source;
        UserDefinedFunction? sourceClassifier = FindClassifierFunction(source);

        foreach (DbaInstanceParameter destination in Destination)
        {
            if (Interrupted)
                return;
            Server? server = Connect(destination, DestinationSqlCredential, continueLoop: true);
            if (server is null)
                continue;
            CopyTo(destination, server, sourceClassifier);
        }
    }

    private void CopyTo(DbaInstanceParameter destination, Server server, UserDefinedFunction? sourceClassifier)
    {
        UserDefinedFunction? destClassifier = FindClassifierFunction(server);
        _alterMessage = null;
        PSObject settingRow = Row(server, SettingsType, "All Settings");
        PSObject classifierRow = Row(server, SettingsType, "Classifier Function");

        if (Approve(destination, "Updating Resource Governor settings"))
        {
            if (!HasGovernorEdition(server))
            {
                WriteMessage(MessageLevel.Verbose, EditionMessage);
            }
            else
            {
                ErrorRecord? fault = CopyClassifier(destination, ref server, sourceClassifier, destClassifier, classifierRow);
                if (fault is not null)
                {
                    Emit(settingRow, "Failed", MessageService.GetErrorMessage(fault));
                    RunReconfigure(server);
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Issue reconfiguring Resource Governor on {0} | {1}", destination, fault));
                }
            }
        }

        WriteMessage(MessageLevel.Verbose, "Migrating pools.");
        foreach (ResourcePool pool in SelectPools())
            server = CopyPool(destination, server, pool);

        if (!Approve(destination, "Finalizing migration by reconfiguring Resource Governor."))
            return;
        if (!HasGovernorEdition(server))
        {
            WriteMessage(MessageLevel.Verbose, EditionMessage);
            return;
        }
        WriteMessage(MessageLevel.Verbose, "Reconfiguring Resource Governor.");
        try
        {
            if (!_source.ResourceGovernor.Enabled)
            {
                Query(server, "ALTER RESOURCE GOVERNOR DISABLE");
                RunReconfigureSteps(server);
                // Correction disabled-source-kept-disabled: RECONFIGURE enables the governor, so disable it again.
                Query(server, "ALTER RESOURCE GOVERNOR DISABLE");
            }
            else
            {
                Query(server, "ALTER RESOURCE GOVERNOR RECONFIGURE");
            }
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            // PS: catch { $altermsg = $_.Exception }
            _alterMessage = Record(ex).Exception;
        }
        PSObject reconfigureRow = Row(server, "Reconfigure Resource Governor", "Reconfigure Resource Governor");
        Emit(reconfigureRow, "Successful", _alterMessage);
    }

    /// <summary>The source's classifier try block ("ALL IN ONE, NO CONTINUES"); returns the record its catch receives.</summary>
    private ErrorRecord? CopyClassifier(DbaInstanceParameter destination, ref Server server,
        UserDefinedFunction? sourceClassifier, UserDefinedFunction? destClassifier, PSObject classifierRow)
    {
        try
        {
            WriteMessage(MessageLevel.Verbose, "Managing classifier function.");
            if (sourceClassifier is null)
            {
                Emit(classifierRow, "Skipped", null);
                return null;
            }

            string mapping = String.Format(CultureInfo.InvariantCulture,
                "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = {0});", ClassifierName(sourceClassifier));
            if (destClassifier is null)
            {
                server = Reconnect(destination);
                UserDefinedFunction? existing = MasterFunction(server, sourceClassifier.Name);
                if (existing is not null)
                {
                    UserDefinedFunction namesake = existing;
                    WriteMessage(MessageLevel.Verbose, "Dropping the function with the source classifier function name.");
                    Invoke(() => namesake.Drop(), "Drop");
                }
                WriteMessage(MessageLevel.Verbose, "Creating function.");
                Query(server, ClassifierScript(sourceClassifier));
                RunMapping(server, mapping);
                Emit(classifierRow, "Successful", "The new classifier function has been created");
                RunReconfigureSteps(server);
                return null;
            }

            if (!Force)
            {
                Emit(classifierRow, "Skipped", "Already exists on destination");
                return null;
            }

            UserDefinedFunction current = destClassifier;
            const string clear = "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL);";
            WriteMessage(MessageLevel.Debug, clear);
            WriteMessage(MessageLevel.Verbose, "Disabling the Resource Governor.");
            Query(server, clear);
            RunReconfigureSteps(server);
            WriteMessage(MessageLevel.Verbose, "Dropping the destination classifier function.");
            server = Reconnect(destination);
            // PS: $destFunction = ...UserDefinedFunctions[$sourceClassifierFunction.Name], read and unused.
            MasterFunction(server, sourceClassifier.Name);
            Invoke(() => current.Drop(), "Drop");
            WriteMessage(MessageLevel.Verbose, "Re-creating the Resource Governor classifier function.");
            Query(server, ClassifierScript(sourceClassifier));
            RunMapping(server, mapping);
            RunReconfigureSteps(server);
            Emit(classifierRow, "Successful", "The old classifier function has been overwritten.");
            return null;
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            return Record(ex);
        }
    }

    private void RunMapping(Server server, string mapping)
    {
        WriteMessage(MessageLevel.Debug, mapping);
        WriteMessage(MessageLevel.Verbose, "Mapping Resource Governor classifier function.");
        Query(server, mapping);
    }

    /// <summary>PS: $sql = "ALTER RESOURCE GOVERNOR RECONFIGURE;"; Write-Message Debug, Verbose; $destServer.Query($sql).</summary>
    private void RunReconfigureSteps(Server server)
    {
        WriteMessage(MessageLevel.Debug, Reconfigure);
        WriteMessage(MessageLevel.Verbose, "Reconfiguring Resource Governor.");
        Query(server, Reconfigure);
    }

    /// <summary>The reconfigure a source catch block runs: nothing encloses it there, so its fault leaves the command.</summary>
    private void RunReconfigure(Server server)
    {
        try
        {
            RunReconfigureSteps(server);
        }
        catch (QueryFault ex)
        {
            // caller-try: terminate -- a Query fault inside the source's catch block is statement-terminating; terminate is the rule's default
            ThrowTerminatingError(ex.Record); // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
        }
    }

    /// <summary>One pool of the source's pool loop; returns the destination server, which a -Force drop reconnects.</summary>
    private Server CopyPool(DbaInstanceParameter destination, Server server, ResourcePool pool)
    {
        string poolName = pool.Name;
        PSObject poolRow = Row(server, "Resource Governor Pool", poolName);
        _workloadRow = null;
        _workloadName = null;

        if (server.ResourceGovernor.ResourcePools[poolName] is not null)
        {
            if (!Force)
            {
                string skipped = String.Format(CultureInfo.InvariantCulture,
                    "Pool '{0}' was skipped because it already exists on {1}. Use -Force to drop and recreate.", poolName, destination);
                if (Approve(destination, skipped))
                {
                    WriteMessage(MessageLevel.Verbose, skipped);
                    Emit(poolRow, "Skipped", "Already exists on destination");
                }
            }
            else if (Approve(destination, "Attempting to drop " + poolName))
            {
                WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Pool '{0}' exists on {1}.", poolName, destination));
                WriteMessage(MessageLevel.Verbose, "Force specified. Dropping " + poolName + ".");
                try
                {
                    server = Reconnect(destination);
                    DropPool(server, poolName);
                }
                catch (Exception ex) when (ex is not PipelineStoppedException)
                {
                    ErrorRecord record = Record(ex);
                    Emit(poolRow, "Failed", MessageService.GetErrorMessage(record));
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Issue dropping pool {0} on {1} | {2}", poolName, destination, record));
                    RunReconfigure(server);
                    return server;
                }
            }
        }

        if (!Approve(destination, "Migrating pool " + poolName))
            return server;
        try
        {
            string sql = OutString(Invoke(() => pool.Script(), "Script"));
            WriteMessage(MessageLevel.Debug, sql);
            WriteMessage(MessageLevel.Verbose, "Copying pool " + poolName + ".");
            Query(server, sql);
            Emit(poolRow, "Successful", null);
            foreach (WorkloadGroup workloadGroup in pool.WorkloadGroups)
            {
                _workloadName = workloadGroup.Name;
                _workloadRow = Row(server, "Resource Governor Pool Workgroup", _workloadName);
                string groupSql = OutString(Invoke(() => workloadGroup.Script(), "Script"));
                WriteMessage(MessageLevel.Debug, groupSql);
                WriteMessage(MessageLevel.Verbose, "Copying " + _workloadName + ".");
                Query(server, groupSql);
                Emit(_workloadRow, "Successful", null);
                RunReconfigureSteps(server);
            }
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            ErrorRecord record = Record(ex);
            if (_workloadRow is not null)
                Emit(_workloadRow, "Failed", MessageService.GetErrorMessage(record));
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                "Issue creating {0} on {1} | {2}", _workloadName, destination, record));
        }
        return server;
    }

    /// <summary>PS: the destination pool's workload groups collected first and dropped, then the pool, then ResourceGovernor.Alter().</summary>
    private static void DropPool(Server server, string poolName)
    {
        ResourcePool? destPool = server.ResourceGovernor.ResourcePools[poolName];
        List<WorkloadGroup> groups = new List<WorkloadGroup>();
        if (destPool is not null)
        {
            foreach (WorkloadGroup group in destPool.WorkloadGroups)
                groups.Add(group);
        }
        foreach (WorkloadGroup group in groups)
            Invoke(() => group.Drop(), "Drop");
        if (destPool is null)
            throw new QueryFault(NullMethodRecord());
        ResourcePool dropped = destPool;
        Invoke(() => dropped.Drop(), "Drop");
        Invoke(() => server.ResourceGovernor.Alter(), "Alter");
    }

    /// <summary>The source's pool selection over the source governor's pools.</summary>
    private List<ResourcePool> SelectPools()
    {
        List<ResourcePool> pools = new List<ResourcePool>();
        bool include = LanguagePrimitives.IsTrue(ResourcePool);
        bool exclude = !include && LanguagePrimitives.IsTrue(ExcludeResourcePool);
        foreach (ResourcePool pool in _source.ResourceGovernor.ResourcePools)
        {
            bool system = InList(pool.Name, new object[] { "internal", "default" });
            bool selected;
            if (include)
                // Correction system-pools-excluded: help says -ResourcePool excludes internal and default automatically.
                selected = !system && InList(pool.Name, ResourcePool);
            else if (exclude)
                selected = !system && !InList(pool.Name, ExcludeResourcePool);
            else
                selected = !system;
            if (selected)
                pools.Add(pool);
        }
        return pools;
    }

    /// <summary>The classifier's schema-qualified name for ALTER RESOURCE GOVERNOR, as quoted identifiers.</summary>
    private static string ClassifierName(UserDefinedFunction function)
    {
        // Correction classifier-name-quoted: the source spliced $schema.$name unquoted, server text run as SQL.
        return String.Format(CultureInfo.InvariantCulture, "[{0}].[{1}]",
            function.Schema.Replace("]", "]]"), function.Name.Replace("]", "]]"));
    }

    /// <summary>PS: $sourceClassifierFunction.Script() | Where-Object { $_ -notmatch '^SET QUOTED_IDENTIFIER' -and $_ -notmatch '^SET ANSI_NULLS' }, bound to Query's [string]$Query.</summary>
    private static string ClassifierScript(UserDefinedFunction function)
    {
        List<object> lines = new List<object>();
        foreach (string? line in Invoke(() => function.Script(), "Script"))
        {
            string text = line ?? String.Empty;
            if (!Regex.IsMatch(text, "^SET QUOTED_IDENTIFIER", RegexOptions.IgnoreCase) && !Regex.IsMatch(text, "^SET ANSI_NULLS", RegexOptions.IgnoreCase))
                lines.Add(text);
        }
        object? value = lines.Count == 0 ? null : lines.Count == 1 ? lines[0] : lines.ToArray();
        return LanguagePrimitives.ConvertTo<string>(value) ?? String.Empty;
    }

    /// <summary>PS: ... | Out-String over the lines of an SMO Script() call.</summary>
    private static string OutString(System.Collections.Specialized.StringCollection lines)
    {
        StringBuilder text = new StringBuilder();
        foreach (string? line in lines)
            text.AppendLine(line);
        return text.ToString();
    }

    /// <summary>PS: $destServer.Databases["master"].UserDefinedFunctions[$name].</summary>
    private static UserDefinedFunction? MasterFunction(Server server, string name)
    {
        Microsoft.SqlServer.Management.Smo.Database? master = server.Databases["master"];
        if (master is null)
            throw new QueryFault(new ErrorRecord(new RuntimeException("Cannot index into a null array."), "NullArray", ErrorCategory.InvalidOperation, null));
        return master.UserDefinedFunctions[name];
    }

    /// <summary>
    /// Get-DbaRgClassifierFunction -SqlInstance $server: the master function whose [schema].[name] equals the governor's
    /// ClassifierFunction, case-insensitively; the last match wins.
    /// </summary>
    private static UserDefinedFunction? FindClassifierFunction(Server server)
    {
        string? comparand = server.ResourceGovernor?.ClassifierFunction;
        Microsoft.SqlServer.Management.Smo.Database? master = server.Databases["master"];
        UserDefinedFunction? found = null;
        if (master is null)
            return null;
        foreach (UserDefinedFunction function in master.UserDefinedFunctions)
        {
            string qualified = String.Format(CultureInfo.InvariantCulture, "[{0}].[{1}]", function.Schema, function.Name);
            if (LanguagePrimitives.Equals(qualified, comparand, true, CultureInfo.InvariantCulture))
                found = function;
        }
        return found;
    }

    /// <summary>PS: $destServer.Edition -notmatch 'Enterprise' -and -notmatch 'Datacenter' -and -notmatch 'Developer', negated.</summary>
    private static bool HasGovernorEdition(Server server)
    {
        string edition = server.Edition ?? String.Empty;
        return Regex.IsMatch(edition, "Enterprise", RegexOptions.IgnoreCase)
            || Regex.IsMatch(edition, "Datacenter", RegexOptions.IgnoreCase)
            || Regex.IsMatch(edition, "Developer", RegexOptions.IgnoreCase);
    }

    /// <summary>PS: Connect-DbaInstance -MinimumVersion 10 in a try whose catch is Stop-Function "Failure" -Category ConnectionError.</summary>
    private Server? Connect(DbaInstanceParameter target, PSCredential? credential, bool continueLoop)
    {
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            Server server = ConnectionService.GetServer(Request(target, credential, 10));
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            ErrorRecord record = new ErrorRecord(ex, "dbatools_Copy-DbaResourceGovernor", ErrorCategory.ConnectionError, target);
            StopFunction("Failure", target: target, errorRecord: record, category: ErrorCategory.ConnectionError, continueLoop: continueLoop);
            return null;
        }
    }

    /// <summary>PS: $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential, inside the source's try.</summary>
    private Server Reconnect(DbaInstanceParameter target)
    {
        try
        {
            Server server = ConnectionService.GetServer(Request(target, DestinationSqlCredential, 0));
            SetActiveConnection(server.ConnectionContext);
            return server;
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            throw new QueryFault(new ErrorRecord(ex, "dbatools_Connect-DbaInstance", ErrorCategory.ConnectionError, target));
        }
    }

    private SmoConnectionRequest Request(DbaInstanceParameter target, PSCredential? credential, int minimumVersion)
    {
        HashSet<string> bound = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" };
        if (minimumVersion > 0)
            bound.Add("MinimumVersion");
        return new SmoConnectionRequest
        {
            Instance = target,
            SqlCredential = credential,
            MinimumVersion = minimumVersion,
            // Correction azure-unsupported: Resource Governor exists only in SQL Server and Managed Instance.
            AzureUnsupported = true,
            BoundParameters = bound,
            MessageCallback = (level, text) => WriteAttributedMessage("Connect-DbaInstance", level, text)
        };
    }

    /// <summary>PS: if ($Force) { $ConfirmPreference = 'none' } in begin, so -Force never prompts.</summary>
    private bool Approve(DbaInstanceParameter target, string action)
    {
        if (!Force)
            return ShouldProcess(target.ToString(), action);
        // Binary cmdlets share the caller's preference scope, unlike advanced functions.
        object? previous = SessionState.PSVariable.GetValue("ConfirmPreference");
        try
        {
            SessionState.PSVariable.Set("ConfirmPreference", ConfirmImpact.None);
            return ShouldProcess(target.ToString(), action);
        }
        finally
        {
            SessionState.PSVariable.Set("ConfirmPreference", previous);
        }
    }

    /// <summary>PS: $name -in $list, case-insensitive. -in compares each list value with the name, the value on the
    /// left, so the name converts to the value's type: a pool named 01 is -in @(1).</summary>
    private static bool InList(string name, object[]? list)
    {
        if (list is null)
            return false;
        foreach (object? value in list)
        {
            if (LanguagePrimitives.Equals(value, name, true))
                return true;
        }
        return false;
    }

    /// <summary>The source's status [PSCustomObject], DateTime taken when it is built.</summary>
    private PSObject Row(Server destination, string type, string name)
    {
        PSObject row = new PSObject();
        row.Properties.Add(new PSNoteProperty("SourceServer", _source.Name));
        row.Properties.Add(new PSNoteProperty("DestinationServer", destination.Name));
        row.Properties.Add(new PSNoteProperty("Type", type));
        row.Properties.Add(new PSNoteProperty("Name", name));
        row.Properties.Add(new PSNoteProperty("Status", null));
        row.Properties.Add(new PSNoteProperty("Notes", null));
        row.Properties.Add(new PSNoteProperty("DateTime", new DbaDateTime(DateTime.Now)));
        return row;
    }

    /// <summary>Sets Status and Notes, then $row | Select-DefaultView ... -TypeName MigrationObject.</summary>
    private void Emit(PSObject row, string status, object? notes)
    {
        row.Properties["Status"].Value = status;
        row.Properties["Notes"].Value = notes;
        OutputHelper.InsertTypeName(row, "MigrationObject");
        OutputHelper.SetDefaultDisplayPropertySet(row, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        WriteObject(row);
    }

    /// <summary>PS: $null = $server.Query($sql), the dbatools Server.Query script method.</summary>
    private static void Query(Server server, string sql)
    {
        try
        {
            server.ConnectionContext.ExecuteWithResults(sql);
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            throw new QueryFault(QueryRecord(ex));
        }
    }

    private static void Invoke(Action call, string method)
    {
        Invoke<object?>(() => { call(); return null; }, method);
    }

    private static T Invoke<T>(Func<T> call, string method)
    {
        try
        {
            return call();
        }
        catch (Exception ex) when (ex is not PipelineStoppedException and not QueryFault)
        {
            throw new QueryFault(MethodRecord(ex, method, 0));
        }
    }

    /// <summary>The record a script catch receives for a failed .NET method call.</summary>
    private static ErrorRecord MethodRecord(Exception failure, string method, int argumentCount)
    {
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"", method, argumentCount, failure.Message), failure);
        return new ErrorRecord(call, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    /// <summary>The record a source catch block receives for a fault of its try statement.</summary>
    private static ErrorRecord Record(Exception failure)
    {
        if (failure is QueryFault fault)
            return fault.Record;
        return new ErrorRecord(failure, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    /// <summary>The record a script catch receives for a method call on $null.</summary>
    private static ErrorRecord NullMethodRecord()
    {
        return new ErrorRecord(new RuntimeException("You cannot call a method on a null-valued expression."),
            "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null);
    }

    /// <summary>
    /// The record a failed Server.Query call raises: its catch concatenates the messages of the failure's exception
    /// chain without separators and throws that string, reported as the ScriptMethodRuntimeException of "Query".
    /// </summary>
    private static ErrorRecord QueryRecord(Exception failure)
    {
        StringBuilder message = new StringBuilder();
        Exception current = failure;
        while (current.InnerException is not null)
        {
            message.Append(current.Message);
            current = current.InnerException;
        }
        message.Append(current.Message);
        string text = message.ToString();
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", text), new RuntimeException(text, failure));
        return new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }

    /// <summary>Carries the ErrorRecord a source catch block would receive for a statement inside its try.</summary>
    private sealed class QueryFault : Exception
    {
        internal QueryFault(ErrorRecord record) : base(record.Exception.Message, record.Exception)
        {
            Record = record;
        }

        internal ErrorRecord Record { get; }
    }
}
