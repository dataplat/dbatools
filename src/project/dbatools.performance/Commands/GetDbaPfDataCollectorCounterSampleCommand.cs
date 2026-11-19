#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaPfDataCollectorCounterSample.ps1 at refs/pins/dbatools-2026-10-22. The pin reads each computer's counters through
// the nested Get-DbaPfDataCollectorCounter, called without -EnableException; here that call is
// GetDbaPfDataCollectorCounterCommand.ReadComputerCounters over GetDbaPfDataCollectorCommand.CollectorReader, the code the native commands
// run, writing to this command's streams. Each counter is then sampled as the pin's Get-Counter call samples it, natively on pdh.dll
// (GetDbaPfDataCollectorCounterSampleCommand.Pdh.cs).
/// <summary>Retrieves real-time performance counter samples from SQL Server systems for monitoring and troubleshooting.</summary>
/// <para>
/// Collects performance counter data from Windows Performance Monitor collector sets and individual counters on SQL Server systems. This function wraps PowerShell's Get-Counter cmdlet to provide structured performance data that DBAs use for monitoring CPU, memory, disk I/O, and SQL Server-specific metrics. You can capture single snapshots for quick checks or continuous samples for ongoing monitoring during troubleshooting sessions. The output integrates seamlessly with Get-DbaPfDataCollectorCounter to build comprehensive performance monitoring workflows.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollectorCounterSample
/// </code>
/// <para>
/// Gets a single sample for all counters for all Collector Sets on localhost.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollectorCounterSample -Counter '\Processor(_Total)\% Processor Time'
/// </code>
/// <para>
/// Gets a single sample for all counters for all Collector Sets on localhost.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollectorCounter -ComputerName sql2017, sql2016 | Out-GridView -PassThru | Get-DbaPfDataCollectorCounterSample -MaxSamples 10
/// </code>
/// <para>
/// Gets 10 samples for all counters for all Collector Sets for servers sql2016 and sql2017.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollectorCounterSample -ComputerName sql2017
/// </code>
/// <para>
/// Gets a single sample for all counters for all Collector Sets on sql2017.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollectorCounterSample -ComputerName sql2017, sql2016 -Credential ad\sqldba -CollectorSet 'System Correlation'
/// </code>
/// <para>
/// Gets a single sample for all counters for the 'System Correlation' CollectorSet on sql2017 and sql2016 using alternative credentials.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollectorCounterSample -CollectorSet 'System Correlation'
/// </code>
/// <para>
/// Gets a single sample for all counters for the 'System Correlation' CollectorSet.
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
/// <seealso href="https://dbatools.io/Get-DbaPfDataCollectorCounterSample" />
[Cmdlet(VerbsCommon.Get, "DbaPfDataCollectorCounterSample")]
public sealed partial class GetDbaPfDataCollectorCounterSampleCommand : DbaBaseCmdlet
{
    /// <para>
    /// The target computer where performance counters will be collected. Defaults to localhost.
    /// Use this when monitoring remote SQL Server systems or collecting performance data from multiple servers simultaneously.
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
    /// Specifies which Performance Monitor Data Collector Set to sample counters from. Accepts wildcard patterns for matching multiple sets.
    /// Use this to focus on specific pre-configured collector sets like 'System Performance' or custom SQL Server monitoring sets instead of sampling all available counters.
    /// </para>
    [Parameter(Position = 2)]
    [Alias("DataCollectorSet")]
    public string[]? CollectorSet { get; set; }

    /// <para>
    /// Specifies which individual Data Collector within a Collector Set to sample from. Accepts wildcard patterns.
    /// Use this when you need samples from specific collectors rather than all collectors in a set, such as targeting only SQL Server-related collectors.
    /// </para>
    [Parameter(Position = 3)]
    [Alias("DataCollector")]
    public string[]? Collector { get; set; }

    /// <para>
    /// Specifies individual performance counter paths to sample in the standard format like '\Processor(_Total)\% Processor Time' or '\SQLServer:Buffer Manager\Page life expectancy'.
    /// Use this when you need specific counters for targeted troubleshooting rather than sampling all available counters from collector sets.
    /// </para>
    [Parameter(Position = 4)]
    public string[]? Counter { get; set; }

    /// <para>
    /// Enables continuous sampling until you press CTRL+C instead of taking a single snapshot. Combine with SampleInterval to control timing between samples.
    /// Use this during active troubleshooting sessions when you need to monitor performance trends in real-time, such as during query execution or system load events.
    /// </para>
    [Parameter]
    public SwitchParameter Continuous { get; set; }

    /// <para>
    /// Lists available performance counter sets on the target computers without collecting samples. Supports wildcard patterns for filtering.
    /// Use this to discover what counter sets are available before running collection commands, especially useful when working with unfamiliar systems or custom monitoring configurations.
    /// </para>
    [Parameter(Position = 5)]
    public SwitchParameter[]? ListSet { get; set; }

    /// <para>
    /// Specifies the maximum number of samples to collect from each counter before stopping. Default is 1 sample.
    /// Use this when you need a specific number of data points for analysis, such as collecting 60 samples at 1-second intervals to get one minute of baseline performance data.
    /// </para>
    [Parameter(Position = 6)]
    public int MaxSamples { get; set; }

    /// <para>
    /// Sets the time interval between samples in seconds with a minimum and default of 1 second.
    /// Use this to control sampling frequency based on your monitoring needs - shorter intervals for active troubleshooting or longer intervals for baseline collection to reduce overhead.
    /// </para>
    [Parameter(Position = 7)]
    public int SampleInterval { get; set; }

    /// <para>
    /// Accepts the object output by Get-DbaPfDataCollectorCounter via the pipeline.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 8)]
    public object[]? InputObject { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    // PS: $Credential is a function variable: a value adopted from $InputObject.Credential keeps for later pipeline records.
    private PSCredential? _adoptedCredential;

    protected override void ProcessRecord()
    {
        // PS: $InputObject is bound afresh for every pipeline record; += below grows only this record's array.
        List<object?> inputs = new(InputObject ?? Array.Empty<object?>());
        PSCredential? credential = _adoptedCredential ?? Credential;

        // PS: if ($InputObject.Credential -and (Test-Bound -ParameterName Credential -Not)) { $Credential = $InputObject.Credential }
        // The [PSCredential] variable converts the value; a value it cannot convert, or a property read that fails, is a statement
        // error and $Credential keeps its value. A $null adopted value cannot happen: the condition needs a true value.
        Statement(() =>
        {
            object? inputCredential = GetDbaPfDataCollectorCommand.MemberEnumeration(inputs, "Credential");
            if (!LanguagePrimitives.IsTrue(inputCredential) || TestBound("Credential"))
                return;
            credential = (PSCredential?)LanguagePrimitives.ConvertTo(inputCredential, typeof(PSCredential), CultureInfo.InvariantCulture);
            _adoptedCredential = credential;
        });

        // PS: if ($InputObject.Counter -and (Test-Bound -ParameterName Counter -Not)) { $Counter = $InputObject.Counter }
        // The adopted value is never read: the -Counter filter below runs only when -Counter is bound, when nothing is adopted. What
        // remains is the statement itself: a property read that fails, or a value [string[]] cannot take, is a statement error.
        Statement(() =>
        {
            object? inputCounter = GetDbaPfDataCollectorCommand.MemberEnumeration(inputs, "Counter");
            if (LanguagePrimitives.IsTrue(inputCounter) && !TestBound("Counter"))
                LanguagePrimitives.ConvertTo(inputCounter, typeof(string[]), CultureInfo.InvariantCulture);
        });

        // PS: if (-not $InputObject -or ($InputObject -and (Test-Bound -ParameterName ComputerName))) {
        //         foreach ($computer in $ComputerName) { $InputObject += Get-DbaPfDataCollectorCounter -ComputerName $computer -Credential $Credential -CollectorSet $CollectorSet -Collector $Collector } }
        // The nested command has no input and no -EnableException: its nested collector set failure only warns. Its statement errors
        // are written here, and stop under this command's -EnableException as this command's own do ("Operator decision: keep going
        // unless -EnableException", point 3).
        if (!GetDbaPfDataCollectorCommand.IsTrueList(inputs) || TestBound("ComputerName"))
        {
            GetDbaPfDataCollectorCommand.CollectorReader reader = new(this, CollectorSet, Collector,
                (function, message, target, record) => WarnNestedStopFunction(function, message, target: target, errorRecord: record),
                (function, message) => WriteAttributedMessage(function, MessageLevel.Verbose, message),
                ReportFault);
            foreach (DbaInstanceParameter? computer in ComputerName ?? Array.Empty<DbaInstanceParameter>())
            {
                // PS: Get-DbaPfDataCollectorCounter -ComputerName $null reads no computer.
                if (computer is null)
                    continue;
                GetDbaPfDataCollectorCounterCommand.ReadComputerCounters(reader, computer.ComputerName, credential, ReportFault, inputs.Add);
            }
        }

        // PS: if ($InputObject) { if (-not $InputObject.CounterObject) { Stop-Function -Message "..."; return } }
        // No Test-FunctionInterrupt follows in the pin, so a later pipeline record is still read. A property read that fails in the
        // condition is a statement error, and the counters are sampled.
        bool wrongType = false;
        Statement(() => wrongType = GetDbaPfDataCollectorCommand.IsTrueList(inputs)
            && !LanguagePrimitives.IsTrue(GetDbaPfDataCollectorCommand.MemberEnumeration(inputs, "CounterObject")));
        if (wrongType)
        {
            StopFunction("InputObject is not of the right type. Please use Get-DbaPfDataCollectorCounter.");
            return;
        }

        foreach (object? counterObject in inputs)
            SampleCounter(counterObject, credential);
    }

    // The pin's loop body for one counter row: the -Counter filter, the Get-Counter call and the rows of its samples.
    private void SampleCounter(object? counterObject, PSCredential? credential)
    {
        // PS: if ((Test-Bound -ParameterName Counter) -and ($Counter -notcontains $counterobject.Name)) { continue }
        // $params = @{ Counter = $counterobject.Name }: a name read that fails is a statement error. Upstream would go on with a
        // $params left from the previous counter, or none; this counter is left out instead.
        object? name = null;
        object? computerName = null;
        if (!Statement(() =>
            {
                name = GetDbaPfDataCollectorCommand.Member(counterObject, "Name");
                computerName = GetDbaPfDataCollectorCommand.Member(counterObject, "ComputerName");
            }))
            return;
        if (TestBound("Counter") && !GetDbaPfDataCollectorCounterCommand.CounterListed(Counter ?? Array.Empty<string>(), name))
            return;

        // PS: if (-not ([dbainstance]$counterobject.ComputerName).IsLocalHost) { $params.Add("ComputerName", $counterobject.ComputerName) }
        // A computer name [dbainstance] cannot take is a statement error, and the counter is read on this computer.
        bool remote = false;
        Statement(() => remote = !((DbaInstanceParameter)LanguagePrimitives.ConvertTo(computerName, typeof(DbaInstanceParameter), CultureInfo.InvariantCulture)).IsLocalHost);

        CounterQuery query = new()
        {
            Counter = name,
            ComputerName = remote ? computerName : null,
            Credential = credential,
            Continuous = Continuous.ToBool(),
            ListSet = LanguagePrimitives.IsTrue(ListSet),
            MaxSamples = MaxSamples,
            SampleInterval = SampleInterval,
        };

        // PS: if ($Continuous) { Get-Counter @params }: the sample sets go out as Get-Counter writes them, and its errors are this
        // command's. A Get-Counter refusal is a statement error, which stops here under -EnableException. What the pipeline after this
        // command throws, or a written error under -ErrorAction Stop, passes through.
        if (Continuous.ToBool())
        {
            try
            {
                ReadCounter(query, WriteError, WriteObject);
            }
            catch (CounterFailure failure)
            {
                ReportFault(failure, "CounterApiError");
            }
            return;
        }

        // PS: try { $pscounters = Get-Counter @params -ErrorAction Stop } catch { Stop-Function -Message "Failure for $($counterobject.Name) on
        // $($counterobject.ComputerName)." -ErrorRecord $_ -Continue }: the first error of the call, written or thrown, ends it with
        // nothing assigned.
        List<object> sets = new();
        try
        {
            ReadCounter(query, record => throw new CounterFailure(record), sets.Add);
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            // The caught Get-Counter record stays in $Error and the caller's -ErrorVariable before Stop-Function's, as the pin leaves it
            // (evidence/pin-pfsample-records-20261112.txt). The pin's ErrorVariable also takes the engine's ActionPreferenceStopException
            // and ContinueException objects, flow-control objects of a script function, which a cmdlet does not raise; not reproduced.
            if (ex is CounterFailure failure)
                KeepCaughtRecord(failure.ErrorRecord);
            StopFunction(String.Format(CultureInfo.InvariantCulture, "Failure for {0} on {1}.", PsText(name), PsText(computerName)),
                errorRecord: StatementFault.Record(ex, "CounterApiError"), continueLoop: true);
            return;
        }

        foreach (object set in sets)
        {
            PSObject setValue = PSObject.AsPSObject(set);
            object? timestamp = setValue.Properties["Timestamp"]?.Value;
            object? samples = setValue.Properties["CounterSamples"]?.Value;
            // PS: [PSCustomObject]@{ ... } | Select-DefaultView -ExcludeProperty Sample, CounterSampleObject: a property read that fails is
            // a statement error, and the loop goes on with the next sample.
            foreach (object? sample in GetDbaPfDataCollectorCommand.ForeachItems(samples))
                Statement(() => WriteObject(SampleRow(counterObject, timestamp, sample, samples)));
        }
    }

    // PS: Select-DefaultView -ExcludeProperty Sample, CounterSampleObject
    private static readonly string[] ExcludedColumns = { "Sample", "CounterSampleObject" };

    // PS: [DbaInstance[]]$ComputerName = $env:COMPUTERNAME; an unset variable leaves the parameter null.
    private static DbaInstanceParameter[]? DefaultComputerName()
    {
        string? computer = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (String.IsNullOrEmpty(computer))
            return null;
        return new[] { new DbaInstanceParameter(computer) };
    }

    // One statement of the pin's body: a fault is a statement error (ReportFault) and the body goes on. False when it faulted.
    private bool Statement(Action body)
    {
        try
        {
            body();
            return true;
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            ReportFault(ex, "RuntimeException");
            return false;
        }
    }

    // PS: the 19-property PSCustomObject, in its written order, and Select-DefaultView -ExcludeProperty.
    private static PSObject SampleRow(object? counterObject, object? timestamp, object? sample, object? samples)
    {
        PSObject row = new();
        row.Properties.Add(new PSNoteProperty("ComputerName", GetDbaPfDataCollectorCommand.Member(counterObject, "ComputerName"))); // style-ok: cs-output-props pinned Windows computer of the counter row; no SQL Server connection exists.
        row.Properties.Add(new PSNoteProperty("DataCollectorSet", GetDbaPfDataCollectorCommand.Member(counterObject, "DataCollectorSet")));
        row.Properties.Add(new PSNoteProperty("DataCollector", GetDbaPfDataCollectorCommand.Member(counterObject, "DataCollector")));
        row.Properties.Add(new PSNoteProperty("Name", GetDbaPfDataCollectorCommand.Member(counterObject, "Name")));
        row.Properties.Add(new PSNoteProperty("Timestamp", timestamp));
        row.Properties.Add(new PSNoteProperty("Path", GetDbaPfDataCollectorCommand.Member(sample, "Path")));
        row.Properties.Add(new PSNoteProperty("InstanceName", GetDbaPfDataCollectorCommand.Member(sample, "InstanceName"))); // style-ok: cs-output-props the performance counter instance of the sample, not a SQL Server instance.
        row.Properties.Add(new PSNoteProperty("CookedValue", GetDbaPfDataCollectorCommand.Member(sample, "CookedValue")));
        row.Properties.Add(new PSNoteProperty("RawValue", GetDbaPfDataCollectorCommand.Member(sample, "RawValue")));
        row.Properties.Add(new PSNoteProperty("SecondValue", GetDbaPfDataCollectorCommand.Member(sample, "SecondValue")));
        row.Properties.Add(new PSNoteProperty("MultipleCount", GetDbaPfDataCollectorCommand.Member(sample, "MultipleCount")));
        row.Properties.Add(new PSNoteProperty("CounterType", GetDbaPfDataCollectorCommand.Member(sample, "CounterType")));
        row.Properties.Add(new PSNoteProperty("SampleTimestamp", GetDbaPfDataCollectorCommand.Member(sample, "Timestamp")));
        row.Properties.Add(new PSNoteProperty("SampleTimestamp100NSec", GetDbaPfDataCollectorCommand.Member(sample, "Timestamp100NSec")));
        row.Properties.Add(new PSNoteProperty("Status", GetDbaPfDataCollectorCommand.Member(sample, "Status")));
        row.Properties.Add(new PSNoteProperty("DefaultScale", GetDbaPfDataCollectorCommand.Member(sample, "DefaultScale")));
        row.Properties.Add(new PSNoteProperty("TimeBase", GetDbaPfDataCollectorCommand.Member(sample, "TimeBase")));
        row.Properties.Add(new PSNoteProperty("Sample", samples));
        row.Properties.Add(new PSNoteProperty("CounterSampleObject", true));
        OutputHelper.SetDefaultDisplayPropertySetExcluding(row, ExcludedColumns);
        return row;
    }

    // PS: "$value" in a message: $null is empty, a collection joins its elements with spaces.
    private static string PsText(object? value)
    {
        if (value is null)
            return String.Empty;
        return LanguagePrimitives.ConvertTo<string>(value) ?? String.Empty;
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

    // PS: Get-Counter @params -ErrorAction Stop inside the pin's try: the engine adds the record it stops on to $Error and to the
    // caller's -ErrorVariable without showing it, whatever this command's own error action or -EnableException. Child-command error
    // owner (operator, 2026-11-12): never written, so the copy carries this command's type as its id suffix in place of
    // GetCounterCommand, and this command as its activity; exception, category and target are Get-Counter's.
    private void KeepCaughtRecord(ErrorRecord source)
    {
        ErrorRecord record = new(source.Exception, source.FullyQualifiedErrorId + "," + GetType().FullName, source.CategoryInfo.Category, source.TargetObject);
        record.CategoryInfo.Activity = MyInvocation.MyCommand.Name;
        object? errors = SessionState.PSVariable.GetValue("global:Error");
        if (errors is System.Collections.ArrayList list)
        {
            list.Insert(0, record);
            // PowerShell 7 defines no $MaximumErrorCount: the engine default, 256, then.
            object? maximumRaw = SessionState.PSVariable.GetValue("MaximumErrorCount");
            int limit = maximumRaw is not null && LanguagePrimitives.TryConvertTo(maximumRaw, CultureInfo.InvariantCulture, out int maximum)
                ? Math.Min(Math.Max(maximum, 0), 32768)
                : 256;
            while (list.Count > limit)
                list.RemoveAt(list.Count - 1);
        }
        // The engine strips one leading '+', the append marker, when it creates the capture list.
        if (MyInvocation.BoundParameters.TryGetValue("ErrorVariable", out object? bound) && bound is string name && name.Length > 0
            && SessionState.PSVariable.GetValue(name[0] == '+' ? name.Substring(1) : name) is System.Collections.ArrayList captured
            && !ReferenceEquals(captured, errors))
            captured.Add(record);
    }
}
