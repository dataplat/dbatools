#nullable enable
#pragma warning disable CA1416 // Windows-only command: the Task Scheduler and Performance Logs and Alerts COM objects, as in the source

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Remoting;
using System.Management.Automation.Runspaces;
using System.Runtime.InteropServices;
using System.Xml;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaPfDataCollector.ps1 at refs/pins/dbatools-2026-10-22. The pin reads each computer's collector sets through
// the nested Get-DbaPfDataCollectorSet (public/Get-DbaPfDataCollectorSet.ps1), whose script block runs through Invoke-Command2: in
// this process for a local address, in a remote session otherwise. Here the local computer is read in C# through the Task Scheduler
// and Performance Logs and Alerts COM objects, called through the PowerShell COM adapter so values and failure texts are the ones the
// script block sees; a remote computer is read in a remote runspace by one script that takes -CollectorSet as a parameter. Only the
// set fields this command uses (ComputerName, Name, Xml) are kept; Get-DbaPfDataCollectorSet asks the same reader for its full rows
// (fullRows). The collectors are then read from each set's XML through the
// PowerShell XML adapter, as the pin's ([xml]$set.Xml).DataCollectorSet.PerformanceCounterDataCollector walk reads them.
/// <summary>Retrieves Windows Performance Monitor data collectors and their configuration details from local or remote computers.</summary>
/// <para>
/// Retrieves detailed information about Windows Performance Monitor data collectors within collector sets, commonly used by DBAs to monitor SQL Server performance counters. This function parses the XML configuration of existing data collectors to show their settings, file locations, sample intervals, and the specific performance counters they collect.
/// </para>
/// <para>
/// Use this when you need to audit existing performance monitoring setups, verify collector configurations, or identify which performance counters are being captured for SQL Server baseline analysis and troubleshooting. The function works across multiple computers and integrates with Get-DbaPfDataCollectorSet for filtering specific collector sets.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollector
/// </code>
/// <para>
/// Gets all Collectors on localhost.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollector -ComputerName sql2017
/// </code>
/// <para>
/// Gets all Collectors on sql2017.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollector -ComputerName sql2017, sql2016 -Credential ad\sqldba -CollectorSet 'System Correlation'
/// </code>
/// <para>
/// Gets all Collectors for the 'System Correlation' CollectorSet on sql2017 and sql2016 using alternative credentials.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollectorSet -CollectorSet 'System Correlation' | Get-DbaPfDataCollector
/// </code>
/// <para>
/// Gets all Collectors for the 'System Correlation' CollectorSet.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Performance, DataCollector, PerfCounter
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
/// <seealso href="https://dbatools.io/Get-DbaPfDataCollector" />
[Cmdlet(VerbsCommon.Get, "DbaPfDataCollector")]
public sealed class GetDbaPfDataCollectorCommand : DbaBaseCmdlet
{
    private const string DefaultShellUri = "http://schemas.microsoft.com/powershell/Microsoft.PowerShell";
    private const string NestedSetCommand = "Get-DbaPfDataCollectorSet";

    /// <para>
    /// Specifies the target computer(s) to retrieve performance data collectors from. Defaults to localhost.
    /// Use this to monitor performance collectors across multiple SQL Server environments or remote systems where SQL Server performance monitoring is configured.
    /// </para>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <para>
    /// Allows you to login to servers using alternative credentials. To use:
    /// </para>
    /// <para>
    /// $scred = Get-Credential, then pass $scred object to the -Credential parameter.
    /// </para>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <para>
    /// Filters results to data collectors within specific collector sets by name. Accepts wildcards for pattern matching.
    /// Use this when you want to examine collectors in a particular performance monitoring setup, such as 'System Correlation' or custom SQL Server baseline collector sets.
    /// </para>
    [Parameter(Position = 2)]
    [Alias("DataCollectorSet")]
    public string[]? CollectorSet { get; set; }

    /// <para>
    /// Filters results to specific data collectors by name within the collector sets. Accepts wildcards for pattern matching.
    /// Use this when you need to examine a particular collector's configuration, such as one focused on SQL Server counters or system resource monitoring.
    /// </para>
    [Parameter(Position = 3)]
    [Alias("DataCollector")]
    public string[]? Collector { get; set; }

    /// <para>
    /// Accepts collector set objects from Get-DbaPfDataCollectorSet via the pipeline to retrieve their individual data collectors.
    /// Use this for pipeline operations when you want to drill down from collector sets to examine the specific performance counters and configuration details of their data collectors.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public object[]? InputObject { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    // PS: $columns, the Select-DefaultView -Property list.
    private static readonly string[] Columns =
    {
        "ComputerName", "DataCollectorSet", "Name", "DataCollectorType", "DataSourceName", "FileName", "FileNameFormat", "FileNameFormatPattern",
        "LatestOutputLocation", "LogAppend", "LogCircular", "LogFileFormat", "LogOverwrite", "SampleInterval", "SegmentMaxRecords", "Counters",
    };

    // PS (set script): the IDataCollectorSet properties the pinned script block reads after Query, in its order. This command keeps
    // only Xml, but every read is made, so a property the set cannot return skips the set with the same warning.
    private static readonly string[] SetProperties =
    {
        "OutputLocation", "LatestOutputLocation", "LatestOutputLocation", "OutputLocation", "RootPath", "Duration", "Description",
        "DescriptionUnresolved", "DisplayName", "DisplayNameUnresolved", "Keywords", "Segment", "SegmentMaxDuration", "SegmentMaxSize",
        "SerialNumber", "Server", "Status", "Subdirectory", "SubdirectoryFormat", "SubdirectoryFormatPattern", "Task", "TaskRunAsSelf",
        "TaskArguments", "TaskUserTextArguments", "Schedules", "SchedulesEnabled", "UserAccount", "Xml", "Security", "StopOnCompletion",
    };

    // PS (set script): switch ($task.State) { 0 { "Unknown" } 1 { "Disabled" } 2 { "Queued" } 3 { "Ready" } 4 { "Running" } }
    private static readonly string[] TaskStates = { "Unknown", "Disabled", "Queued", "Ready", "Running" };

    // PS: $Credential is a function variable: a value adopted from $InputObject.Credential keeps for later pipeline records.
    private PSCredential? _credential;
    private bool _credentialAdopted;

    // PS: [DbaInstance[]]$ComputerName = $env:COMPUTERNAME; an unset variable leaves the parameter null.
    private static DbaInstanceParameter[]? DefaultComputerName()
    {
        string? name = Environment.GetEnvironmentVariable("COMPUTERNAME");
        return String.IsNullOrEmpty(name) ? null : new[] { new DbaInstanceParameter(name) };
    }

    protected override void ProcessRecord()
    {
        // PS: $InputObject is bound afresh for every pipeline record; += below grows only this record's array.
        List<object?> inputs = new();
        if (InputObject is not null)
            inputs.AddRange(InputObject);

        PSCredential? credential = _credentialAdopted ? _credential : Credential;

        // PS: if ($InputObject.Credential -and (Test-Bound -ParameterName Credential -Not)) { $Credential = $InputObject.Credential }
        // The [PSCredential] variable converts the value; a value it cannot convert, or a property read that fails, is a statement
        // error and $Credential keeps its value.
        try
        {
            object? inputCredential = MemberEnumeration(inputs, "Credential");
            if (LanguagePrimitives.IsTrue(inputCredential) && !TestBound("Credential"))
            {
                credential = (PSCredential?)LanguagePrimitives.ConvertTo(inputCredential, typeof(PSCredential), CultureInfo.InvariantCulture);
                _credential = credential;
                _credentialAdopted = true;
            }
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            ReportFault(ex, "RuntimeException");
        }

        CollectorReader reader = new(this, CollectorSet, Collector,
            (function, message, target, record) => WarnNestedStopFunction(function, message, target: target, errorRecord: record),
            (function, message) => WriteAttributedMessage(function, MessageLevel.Verbose, message),
            ReportFault);

        // PS: if (-not $InputObject -or ($InputObject -and (Test-Bound -ParameterName ComputerName))) {
        //         foreach ($computer in $ComputerName) { $InputObject += Get-DbaPfDataCollectorSet -ComputerName $computer -Credential $Credential -CollectorSet $CollectorSet } }
        if (!IsTrueList(inputs) || TestBound("ComputerName"))
        {
            foreach (DbaInstanceParameter? computer in ComputerName ?? Array.Empty<DbaInstanceParameter>())
            {
                // PS: Get-DbaPfDataCollectorSet loops over $ComputerName.ComputerName, which skips a null element.
                if (computer is null)
                    continue;
                reader.ReadCollectorSets(computer.ComputerName, credential, inputs);
            }
        }

        // PS: if ($InputObject) { if (-not $InputObject.DataCollectorSetObject) { Stop-Function -Message "..."; return } }
        // No Test-FunctionInterrupt follows in the pin, so a later pipeline record is still read. A property read that fails in the
        // condition is a statement error, and the sets are read.
        bool wrongType = false;
        try
        {
            wrongType = IsTrueList(inputs) && !LanguagePrimitives.IsTrue(MemberEnumeration(inputs, "DataCollectorSetObject"));
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            ReportFault(ex, "RuntimeException");
        }
        if (wrongType)
        {
            StopFunction("InputObject is not of the right type. Please use Get-DbaPfDataCollectorSet.");
            return;
        }

        foreach (object? set in inputs)
            reader.ReadCollectors(set, credential, WriteObject);
    }

    // A statement error of the pin's body: a plain call writes the record and goes on, a caller's try catches it, and
    // -EnableException stops here ("Operator decision: keep going unless -EnableException", point 3).
    private void ReportFault(Exception fault, string fallbackErrorId)
    {
        ErrorRecord record = StatementFault.Record(fault, fallbackErrorId);
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(record); // style-ok: cs-raw-streams a statement error of the pin, outside Stop-Function
        }

        StatementFault.Surface(this, record);
    }

    // The collector read: this command's body for its collector sets, and its nested call in public/Get-DbaPfDataCollectorCounter.ps1,
    // which runs it for one computer with the counter command's streams (CollectorReader.ReadComputer). A cmdlet that derives from
    // PSCmdlet cannot be called directly from another one (Microsoft Learn, "How to invoke a PSCmdlet from within a PSCmdlet"), so
    // both commands share this class; the calling command supplies its own Stop-Function, message and statement-error paths.
    internal sealed class CollectorReader
    {
        private readonly PSCmdlet _host;
        private readonly string[]? _collectorSet;
        private readonly string[]? _collector;
        private readonly Action<string, string, object, ErrorRecord> _warnNested;
        private readonly Action<string, string> _verbose;
        private readonly Action<Exception, string> _fault;
        private readonly bool _fullRows;

        // host: the command whose streams the read writes to; collectorSet and collector: -CollectorSet and -Collector; warnNested:
        // the host's WarnNestedStopFunction (function name, message, target, error record); verbose: the host's attributed verbose
        // message (function name, message); fault: the host's statement error (the fault and its fallback error id); fullRows: the
        // set rows as Get-DbaPfDataCollectorSet writes them (GetDbaPfDataCollectorSetCommand), else the fields this command uses.
        internal CollectorReader(PSCmdlet host, string[]? collectorSet, string[]? collector, Action<string, string, object, ErrorRecord> warnNested,
            Action<string, string> verbose, Action<Exception, string> fault, bool fullRows = false)
        {
            _host = host;
            _collectorSet = collectorSet;
            _collector = collector;
            _warnNested = warnNested;
            _verbose = verbose;
            _fault = fault;
            _fullRows = fullRows;
        }

        // PS: Get-DbaPfDataCollector -ComputerName $computer -Credential $Credential -CollectorSet $CollectorSet -Collector $Collector,
        // with no input: the collector sets of the computer, then their collectors.
        internal void ReadComputer(string computer, PSCredential? credential, Action<PSObject> emit)
        {
            List<object?> sets = new();
            ReadCollectorSets(computer, credential, sets);
            foreach (object? set in sets)
                ReadCollectors(set, credential, emit);
        }

        // PS: foreach ($set in $InputObject) { $collectorxml = ([xml]$set.Xml).DataCollectorSet.PerformanceCounterDataCollector; foreach ($col in $collectorxml) { ... } }
        internal void ReadCollectors(object? set, PSCredential? credential, Action<PSObject> emit)
        {
            object? collectorXml;
            try
            {
                object? document = LanguagePrimitives.ConvertTo(Member(set, "Xml"), typeof(XmlDocument), CultureInfo.InvariantCulture);
                collectorXml = Member(Member(document, "DataCollectorSet"), "PerformanceCounterDataCollector");
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                _fault(ex, "InvalidCastToXmlDocument");

                // Correction stale-collectors: the pin's failed assignment left $collectorxml as the previous set's collectors and
                // reported them again under this set's name; a set whose XML cannot be read reports no collectors.
                return;
            }

            foreach (object? collector in ForeachItems(collectorXml))
            {
                // PS: a statement in the loop body that fails (a set property that cannot be read) is a statement error, and the
                // loop goes on with the next collector.
                try
                {
                    PSObject? row = CollectorRow(set, collector, credential);
                    if (row is not null)
                        emit(row);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    _fault(ex, "RuntimeException");
                }
            }
        }

        // PS: the per-collector body: the -Collector filter, the remote output location and the 22-property object with its default
        // view. Null when -Collector leaves the collector out.
        private PSObject? CollectorRow(object? set, object? collector, PSCredential? credential)
        {
            // PS: if ($Collector -and $Collector -notcontains $col.Name) { continue }
            // Correction wildcards: the help says -Collector accepts wildcards, which the pin's -notcontains never matched.
            object? name = Member(collector, "Name");
            if (LanguagePrimitives.IsTrue(_collector) && !NameMatches(_collector!, name))
                return null;

            // PS: if ($outputlocation) { $dir = ($outputlocation).Replace(':', '$'); $remote = "\\$($set.ComputerName)\$dir" } else { $remote = $null }
            // PLA writes LatestOutputLocation as one text element, which the XML adapter reads as a string.
            object? latest = Member(collector, "LatestOutputLocation");
            string? remote = null;
            if (LanguagePrimitives.IsTrue(latest))
            {
                string location = latest as string ?? LanguagePrimitives.ConvertTo<string>(latest);
                remote = @"\\" + LanguagePrimitives.ConvertTo<string>(Member(set, "ComputerName")) + @"\" + location.Replace(":", "$");
            }

            PSObject row = new();
            row.Properties.Add(new PSNoteProperty("ComputerName", Member(set, "ComputerName"))); // style-ok: cs-output-props pinned Windows computer of the collector set; no SQL Server connection exists.
            row.Properties.Add(new PSNoteProperty("DataCollectorSet", Member(set, "Name")));
            row.Properties.Add(new PSNoteProperty("Name", name));
            row.Properties.Add(new PSNoteProperty("FileName", Member(collector, "FileName")));
            row.Properties.Add(new PSNoteProperty("DataCollectorType", Member(collector, "DataCollectorType")));
            row.Properties.Add(new PSNoteProperty("FileNameFormat", Member(collector, "FileNameFormat")));
            row.Properties.Add(new PSNoteProperty("FileNameFormatPattern", Member(collector, "FileNameFormatPattern")));
            row.Properties.Add(new PSNoteProperty("LogAppend", Member(collector, "LogAppend")));
            row.Properties.Add(new PSNoteProperty("LogCircular", Member(collector, "LogCircular")));
            row.Properties.Add(new PSNoteProperty("LogOverwrite", Member(collector, "LogOverwrite")));
            row.Properties.Add(new PSNoteProperty("LatestOutputLocation", latest));
            row.Properties.Add(new PSNoteProperty("DataCollectorSetXml", Member(set, "Xml")));
            row.Properties.Add(new PSNoteProperty("RemoteLatestOutputLocation", remote));
            row.Properties.Add(new PSNoteProperty("DataSourceName", Member(collector, "DataSourceName")));
            row.Properties.Add(new PSNoteProperty("SampleInterval", Member(collector, "SampleInterval")));
            row.Properties.Add(new PSNoteProperty("SegmentMaxRecords", Member(collector, "SegmentMaxRecords")));
            row.Properties.Add(new PSNoteProperty("LogFileFormat", Member(collector, "LogFileFormat")));
            row.Properties.Add(new PSNoteProperty("Counters", Member(collector, "Counter")));
            row.Properties.Add(new PSNoteProperty("CounterDisplayNames", Member(collector, "CounterDisplayName")));
            row.Properties.Add(new PSNoteProperty("CollectorXml", collector));
            row.Properties.Add(new PSNoteProperty("DataCollectorObject", true));
            row.Properties.Add(new PSNoteProperty("Credential", credential));
            OutputHelper.SetDefaultDisplayPropertySet(row, Columns);
            return row;
        }

        // ---------- the nested Get-DbaPfDataCollectorSet ----------

        // PS (Get-DbaPfDataCollectorSet): try { Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $setscript
        //     -ArgumentList $CollectorSet, $Credential -ErrorAction Stop } catch { Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue }
        // The nested command runs without -EnableException, so a failure only warns under its name, whatever the calling command's
        // -EnableException; sets read before the failure are kept, as the pin's += keeps the rows the nested command wrote.
        internal void ReadCollectorSets(string computer, PSCredential? credential, List<object?> sets)
        {
            ReadCollectorSets(computer, credential, sets.Add);
        }

        // The same read, handing each set to add as it is read (Get-DbaPfDataCollectorSet writes them to the pipeline).
        internal void ReadCollectorSets(string computer, PSCredential? credential, Action<object?> add)
        {
            try
            {
                if (new DbaInstanceParameter(computer).IsLocalHost)
                    ReadLocalSets(credential, add);
                else
                    ReadRemoteSets(computer, credential, add);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (FlowControlException)
            {
                // A downstream Select-Object -First stops this pipeline; it is not a failure of the read.
                throw;
            }
            catch (Exception ex)
            {
                _warnNested(NestedSetCommand, "Failure", computer, StatementFault.Record(ex, NestedSetCommand));
            }
        }

        // The set script block in this process (Invoke-Command2 runs it here for a local address). A failure outside its per-set try
        // ends the read, as -ErrorAction Stop makes the script block's first error end Invoke-Command.
        private void ReadLocalSets(PSCredential? credential, Action<object?> add)
        {
            string? computerName = Environment.GetEnvironmentVariable("COMPUTERNAME");

            // PS: $schedule = New-Object -ComObject "Schedule.Service"; $schedule.Connect(); $folder = $schedule.GetFolder("Microsoft\Windows\PLA")
            object schedule = CreateComObject("Schedule.Service");
            CallMethod(schedule, "Connect");
            object? folder = CallMethod(schedule, "GetFolder", @"Microsoft\Windows\PLA");

            // PS: do { try { $task = $folder.GetTasks($tasknumber); $tasknumber++; if ($task) { $tasks += $task } } catch { $done = $true } } while ($done -eq $false)
            // Correction visible-tasks: the pin adds GetTasks(0), the visible tasks, and GetTasks(1), TASK_ENUM_HIDDEN, which lists the
            // hidden and the visible tasks (Microsoft Learn, ITaskFolder::GetTasks), so a set whose task is visible was listed twice.
            // The tasks are read once, with TASK_ENUM_HIDDEN; a refused call reads no task, as the pin's catch ends its loop.
            const int TaskEnumHidden = 1;
            List<object?> tasks = new();
            try
            {
                object? collection = CallMethod(folder, "GetTasks", TaskEnumHidden);
                if (LanguagePrimitives.IsTrue(collection))
                    tasks.AddRange(ForeachItems(collection));
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception)
            {
                // PS: catch { $done = $true }: a call the folder refuses ends the read.
                tasks.Clear();
            }
            Marshal.ReleaseComObject(schedule);

            // PS: if ($args[0]) { $tasks = $tasks | Where-Object Name -in $args[0] }
            // Correction wildcards: the help says -CollectorSet accepts wildcards, which the pin's -in never matched.
            if (LanguagePrimitives.IsTrue(_collectorSet))
                tasks = tasks.FindAll(task => NameMatches(_collectorSet!, Member(task, "Name")));

            // PS: $sets = New-Object -ComObject Pla.DataCollectorSet
            object query = CreateComObject("Pla.DataCollectorSet");
            string? state = null;
            // PS: $remote and $remotelatest, which live across the loop.
            object? remote = null;
            object? remoteLatest = null;
            foreach (object? task in tasks)
            {
                object? setName = Member(task, "Name");
                if (LanguagePrimitives.TryConvertTo(Member(task, "State"), CultureInfo.InvariantCulture, out int stateValue) && stateValue >= 0 && stateValue < TaskStates.Length)
                    state = TaskStates[stateValue];

                object? row;
                try
                {
                    // PS: $sets.Query($setname, $null); $set = $sets.PSObject.Copy(); $outputlocation, $latestoutputlocation, the remote
                    // locations, then the property reads of the row.
                    CallMethod(query, "Query", setName, null);
                    Dictionary<string, object?> values = new(StringComparer.Ordinal);
                    for (int index = 0; index < SetProperties.Length; index++)
                    {
                        values[SetProperties[index]] = Member(query, SetProperties[index]);
                        if (index == 1)
                            GetDbaPfDataCollectorSetCommand.RemoteLocations(_host.SessionState.Path, computerName, values["OutputLocation"], values["LatestOutputLocation"], ref remote, ref remoteLatest);
                    }

                    // PS: State = $state.Trim(): no state yet is a method call on a null value.
                    if (state is null)
                        throw new RuntimeException("You cannot call a method on a null-valued expression.");

                    row = _fullRows
                        ? GetDbaPfDataCollectorSetCommand.LocalRow(computerName, setName, values, remote, remoteLatest, state.Trim(), task, credential)
                        : SetRow(computerName, setName, values["Xml"], credential);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    // PS: Write-Warning -Message "Issue with getting Collector Set $setname on $env:Computername : $_."
                    _host.WriteWarning(String.Format(CultureInfo.InvariantCulture, "Issue with getting Collector Set {0} on {1} : {2}.", setName, computerName, ex.Message)); // style-ok: cs-raw-streams the pinned set script block calls plain Write-Warning, not Write-Message
                    continue;
                }

                // PS: the row is written as it is made; the next set is read after it.
                add(row);
            }
        }

        // The set script block in a remote session, with the PSRemoting.* settings Invoke-Command2 gives New-PSSession.
        private void ReadRemoteSets(string computer, PSCredential? credential, Action<object?> add)
        {
            bool ssl = LanguagePrimitives.IsTrue(RemotingSetting("psremoting.pssession.usessl"));
            int port = ssl ? 5986 : 5985;
            if (LanguagePrimitives.TryConvertTo(RemotingSetting("psremoting.pssession.port"), out int configured) && configured > 0)
            {
                _verbose("Invoke-Command2", "Using Port: " + configured.ToString(CultureInfo.InvariantCulture));
                port = configured;
            }

            // Fully qualified: Dataplat.Dbatools.Runspace is a namespace, and it hides the type's simple name here.
            using System.Management.Automation.Runspaces.Runspace session = RunspaceFactory.CreateRunspace(new WSManConnectionInfo(ssl, computer, port, "/wsman", SessionConfiguration(), credential)
            {
                SkipRevocationCheck = LanguagePrimitives.IsTrue(RemotingSetting("psremoting.pssessionoption.skiprevocationcheck")),
                SkipCNCheck = LanguagePrimitives.IsTrue(RemotingSetting("psremoting.pssessionoption.skipcncheck")),
                SkipCACheck = LanguagePrimitives.IsTrue(RemotingSetting("psremoting.pssessionoption.skipcacheck")),
                IncludePortInSPN = LanguagePrimitives.IsTrue(RemotingSetting("psremoting.pssessionoption.includeportinspn")),
                IdleTimeout = 600000,
            });
            try
            {
                session.Open();
            }
            catch (PSRemotingTransportException ex)
            {
                // PS: New-PSSession -ErrorAction Stop reports a session that fails to open as PSSessionOpenFailed, category OpenError.
                throw new RuntimeException(ex.Message, ex, new ErrorRecord(ex, "PSSessionOpenFailed", ErrorCategory.OpenError, computer));
            }

            List<PSObject> output = new();
            using (PowerShell shell = PowerShell.Create().AddScript(CollectorSetReadScript).AddParameter("CollectorSet", _collectorSet))
            {
                shell.Runspace = session;
                RuntimeException? failure = null;
                try
                {
                    shell.Invoke(null, output);
                }
                catch (RuntimeException ex)
                {
                    failure = ex;
                }

                // PS: Invoke-Command writes the script block's warnings here as plain warnings.
                foreach (WarningRecord warning in shell.Streams.Warning)
                    _host.WriteWarning(warning.Message); // style-ok: cs-raw-streams the pinned set script block calls plain Write-Warning, not Write-Message

                foreach (PSObject row in output)
                    add(_fullRows ? GetDbaPfDataCollectorSetCommand.RemoteRow(row, credential) : SetRow(Member(row, "ComputerName"), Member(row, "Name"), Member(row, "Xml"), credential));

                // PS: -ErrorAction Stop: the script block's first error ends Invoke-Command and reaches the nested command's catch.
                if (failure is not null)
                    throw failure;
                if (shell.Streams.Error.Count > 0)
                    throw new RuntimeException(shell.Streams.Error[0].Exception.Message, shell.Streams.Error[0].Exception, shell.Streams.Error[0]);
            }
        }

        // PS: Invoke-Command2 gives New-PSSession no -ConfigurationName, so the session opens on the caller's $PSSessionConfigurationName,
        // by default the Microsoft.PowerShell configuration; a bare name gets the http://schemas.microsoft.com/powershell/ prefix from
        // WSManConnectionInfo.
        private string SessionConfiguration()
        {
            object? value = _host.SessionState.PSVariable.GetValue("PSSessionConfigurationName");
            if (value is PSObject wrapped)
                value = wrapped.BaseObject;
            string? name = value as string;
            return String.IsNullOrEmpty(name) ? DefaultShellUri : name!;
        }
    }

    // One collector set as this command reads it: the pinned set row's ComputerName, Name, Xml, DataCollectorSetObject and Credential.
    private static PSObject SetRow(object? computerName, object? name, object? xml, PSCredential? credential)
    {
        PSObject set = new();
        set.Properties.Add(new PSNoteProperty("ComputerName", computerName)); // style-ok: cs-output-props an internal collector set row, never written to the pipeline.
        set.Properties.Add(new PSNoteProperty("Name", name));
        set.Properties.Add(new PSNoteProperty("Xml", xml));
        set.Properties.Add(new PSNoteProperty("DataCollectorSetObject", true));
        set.Properties.Add(new PSNoteProperty("Credential", credential));
        return set;
    }

    private static object? RemotingSetting(string name)
    {
        ConfigurationHost.Configurations.TryGetValue(name, out Config? setting);
        return setting?.Value;
    }

    // ---------- PowerShell language semantics the pin relies on ----------

    // PS: New-Object -ComObject <ProgID>.
    private static object CreateComObject(string progId)
    {
        Type? type = Type.GetTypeFromProgID(progId, true);
        return Activator.CreateInstance(type!)!;
    }

    // PS: $object.Method(arguments), through the PowerShell adapter: a failing COM call raises the same MethodInvocationException text.
    private static object? CallMethod(object? target, string method, params object?[] arguments)
    {
        if (target is null)
            throw new RuntimeException("You cannot call a method on a null-valued expression.");
        PSMethodInfo? info = PSObject.AsPSObject(target).Methods[method];
        if (info is null)
            throw new RuntimeException(String.Format(CultureInfo.InvariantCulture, "Method invocation failed because [{0}] does not contain a method named '{1}'.", target.GetType().FullName, method));
        return Unwrap(info.Invoke(arguments));
    }

    // PS: $object.Name: the adapted property (the XML adapter for an XmlNode, the COM adapter for a COM object), else member
    // enumeration over a collection, else $null.
    internal static object? Member(object? target, string name)
    {
        if (target is null)
            return null;
        PSObject wrapped = PSObject.AsPSObject(target);
        PSPropertyInfo? property = wrapped.Properties[name];
        if (property is not null)
            return Unwrap(property.Value);
        if (LanguagePrimitives.GetEnumerable(wrapped.BaseObject) is not null)
            return MemberEnumeration(ForeachItems(wrapped.BaseObject), name);
        return null;
    }

    // PS: $list.Name over a collection: each element's value, a collection value flattened one level; a PSCustomObject without
    // the property gives $null; none is $null, one is the value itself.
    internal static object? MemberEnumeration(IEnumerable<object?> items, string name)
    {
        List<object?> collected = new();
        foreach (object? item in items)
        {
            if (item is null)
                continue;
            PSObject wrapped = PSObject.AsPSObject(item);
            PSPropertyInfo? property = wrapped.Properties[name];
            if (property is null)
            {
                if (wrapped.BaseObject is PSCustomObject)
                    collected.Add(null);
                continue;
            }
            object? value = Unwrap(property.Value);
            if (value is not string && LanguagePrimitives.GetEnumerable(value) is IEnumerable elements)
            {
                foreach (object? element in elements)
                    collected.Add(Unwrap(element));
            }
            else
            {
                collected.Add(value);
            }
        }
        if (collected.Count == 0)
            return null;
        return collected.Count == 1 ? collected[0] : collected.ToArray();
    }

    // PS: foreach ($x in $value): nothing for $null, the elements of a collection, else the value itself (an XmlNode is not a collection).
    internal static List<object?> ForeachItems(object? value)
    {
        List<object?> items = new();
        if (value is null)
            return items;
        IEnumerable? elements = LanguagePrimitives.GetEnumerable(value);
        if (elements is null)
        {
            List<object?>? comItems = ComCollectionItems(value);
            if (comItems is not null)
                return comItems;
            items.Add(value);
            return items;
        }
        foreach (object? element in elements)
            items.Add(Unwrap(element));
        return items;
    }

    // PS: foreach and += enumerate a COM collection (the Task Scheduler's IRegisteredTaskCollection) through its own enumerator, which
    // LanguagePrimitives.GetEnumerable does not offer for COM objects. Its Count and Item(index) members are read through the COM
    // adapter instead; Task Scheduler collections are 1-based (Learn: IRegisteredTaskCollection::get_Item). Null when the value is
    // not a COM collection.
    private static List<object?>? ComCollectionItems(object value)
    {
        if (!Marshal.IsComObject(value))
            return null;
        PSObject wrapped = PSObject.AsPSObject(value);
        PSPropertyInfo? count = wrapped.Properties["Count"];
        if (count is null || wrapped.Members["Item"] is not PSParameterizedProperty item)
            return null;
        int total = LanguagePrimitives.ConvertTo<int>(count.Value);
        List<object?> items = new();
        for (int index = 1; index <= total; index++)
            items.Add(Unwrap(item.Invoke(index)));
        return items;
    }

    // PS: -contains and -in, case-insensitive with the invariant culture; and, as the help describes, a name with wildcard characters
    // matches as -like does. A name matches itself first, so a set or collector whose name holds wildcard characters is still found.
    private static bool NameMatches(string[] names, object? value)
    {
        string? text = value is null ? null : value as string ?? LanguagePrimitives.ConvertTo<string>(value);
        foreach (string name in names)
        {
            if (LanguagePrimitives.Equals(name, value, true, CultureInfo.InvariantCulture))
                return true;
            if (name is null || text is null || !WildcardPattern.ContainsWildcardCharacters(name))
                continue;
            try
            {
                if (new WildcardPattern(name, WildcardOptions.IgnoreCase | WildcardOptions.CultureInvariant).IsMatch(text))
                    return true;
            }
            catch (WildcardPatternException)
            {
                // Not a valid pattern, such as an unclosed bracket: the name matches only itself, as checked above.
                continue;
            }
        }
        return false;
    }

    // PS truthiness of an array value: empty is false, one element is that element's truthiness, more is true.
    internal static bool IsTrueList(List<object?> values)
    {
        if (values.Count == 0)
            return false;
        return values.Count > 1 || LanguagePrimitives.IsTrue(values[0]);
    }

    // A value as a script sees it: the base object of a PSObject that wraps a .NET object.
    private static object? Unwrap(object? value)
    {
        if (value is PSObject wrapped && wrapped.BaseObject is not PSCustomObject)
            return wrapped.BaseObject;
        return value;
    }

    // The pinned set script block, run in the remote session with -CollectorSet as a parameter. It reads the sets as the pin does and
    // returns each set's row without Credential, which the caller adds; $ErrorActionPreference Stop makes its first error end it, as
    // the pin's Invoke-Command -ErrorAction Stop does. Correction visible-tasks: the tasks are read once, with TASK_ENUM_HIDDEN (1), not
    // the pin's GetTasks(0) plus GetTasks(1), which listed a visible task twice. Correction remote-locations (Get-DbaPfDataCollectorSet):
    // the last else clears $remotelatest, where the pin clears $remote.
    private const string CollectorSetReadScript = @"
param($CollectorSet)
$ErrorActionPreference = 'Stop'
$schedule = New-Object -ComObject 'Schedule.Service'
$schedule.Connect()
$folder = $schedule.GetFolder('Microsoft\Windows\PLA')
$tasks = @()
try {
    $task = $folder.GetTasks(1)
    if ($task) {
        $tasks += $task
    }
} catch {
    $tasks = @()
}
$null = [System.Runtime.Interopservices.Marshal]::ReleaseComObject($schedule)

if ($CollectorSet) {
    $tasks = $tasks | Where-Object {
        $taskName = $PSItem.Name
        $found = $false
        foreach ($wanted in $CollectorSet) {
            if ($taskName -eq $wanted) {
                $found = $true
                break
            }
            if ($null -ne $wanted -and [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($wanted)) {
                try {
                    if ($taskName -like $wanted) {
                        $found = $true
                        break
                    }
                } catch {
                    $found = $false
                }
            }
        }
        $found
    }
}

$sets = New-Object -ComObject Pla.DataCollectorSet
foreach ($task in $tasks) {
    $setname = $task.Name
    switch ($task.State) {
        0 { $state = 'Unknown' }
        1 { $state = 'Disabled' }
        2 { $state = 'Queued' }
        3 { $state = 'Ready' }
        4 { $state = 'Running' }
    }

    try {
        $sets.Query($setname, $null)
        $set = $sets.PSObject.Copy()

        $outputlocation = $set.OutputLocation
        $latestoutputlocation = $set.LatestOutputLocation

        if ($outputlocation) {
            $dir = (Split-Path $outputlocation).Replace(':', '$')
            $remote = ""\\$env:COMPUTERNAME\$dir""
        } else {
            $remote = $null
        }

        if ($latestoutputlocation) {
            $dir = ($latestoutputlocation).Replace(':', '$')
            $remotelatest = ""\\$env:COMPUTERNAME\$dir""
        } else {
            $remotelatest = $null
        }

        [PSCustomObject]@{
            ComputerName               = $env:COMPUTERNAME
            Name                       = $setname
            LatestOutputLocation       = $set.LatestOutputLocation
            OutputLocation             = $set.OutputLocation
            RemoteOutputLocation       = $remote
            RemoteLatestOutputLocation = $remotelatest
            RootPath                   = $set.RootPath
            Duration                   = $set.Duration
            Description                = $set.Description
            DescriptionUnresolved      = $set.DescriptionUnresolved
            DisplayName                = $set.DisplayName
            DisplayNameUnresolved      = $set.DisplayNameUnresolved
            Keywords                   = $set.Keywords
            Segment                    = $set.Segment
            SegmentMaxDuration         = $set.SegmentMaxDuration
            SegmentMaxSize             = $set.SegmentMaxSize
            SerialNumber               = $set.SerialNumber
            Server                     = $set.Server
            Status                     = $set.Status
            Subdirectory               = $set.Subdirectory
            SubdirectoryFormat         = $set.SubdirectoryFormat
            SubdirectoryFormatPattern  = $set.SubdirectoryFormatPattern
            Task                       = $set.Task
            TaskRunAsSelf              = $set.TaskRunAsSelf
            TaskArguments              = $set.TaskArguments
            TaskUserTextArguments      = $set.TaskUserTextArguments
            Schedules                  = $set.Schedules
            SchedulesEnabled           = $set.SchedulesEnabled
            UserAccount                = $set.UserAccount
            Xml                        = $set.Xml
            Security                   = $set.Security
            StopOnCompletion           = $set.StopOnCompletion
            State                      = $state.Trim()
            DataCollectorSetObject     = $true
            TaskObject                 = $task
        }
    } catch {
        Write-Warning -Message ""Issue with getting Collector Set $setname on $env:Computername : $_.""
        continue
    }
}
";
}
