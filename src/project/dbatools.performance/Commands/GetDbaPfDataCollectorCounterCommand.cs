#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaPfDataCollectorCounter.ps1 at refs/pins/dbatools-2026-10-22. The pin reads each computer's collectors through the
// nested Get-DbaPfDataCollector, called without -EnableException; here that call is GetDbaPfDataCollectorCommand.CollectorReader, the
// code the native Get-DbaPfDataCollector runs, writing to this command's streams. The counters are then read from each collector row.
/// <summary>Retrieves performance counter configurations from Windows Performance Monitor Data Collector Sets.</summary>
/// <para>
/// Retrieves the list of performance counters that are configured within Windows Performance Monitor Data Collector Sets. This is useful for auditing performance monitoring configurations, verifying which SQL Server and system counters are being collected, and understanding your performance data collection setup. The function extracts counter details from existing Data Collector objects, showing you exactly which performance metrics are being tracked for troubleshooting and capacity planning.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollectorCounter
/// </code>
/// <para>
/// Gets all counters for all Collector Sets on localhost.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollectorCounter -ComputerName sql2017
/// </code>
/// <para>
/// Gets all counters for all Collector Sets on  on sql2017.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollectorCounter -ComputerName sql2017 -Counter '\Processor(_Total)\% Processor Time'
/// </code>
/// <para>
/// Gets the '\Processor(_Total)\% Processor Time' counter on sql2017.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollectorCounter -ComputerName sql2017, sql2016 -Credential ad\sqldba -CollectorSet 'System Correlation'
/// </code>
/// <para>
/// Gets all counters for the 'System Correlation' CollectorSet on sql2017 and sql2016 using alternative credentials.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollectorSet -CollectorSet 'System Correlation' | Get-DbaPfDataCollector | Get-DbaPfDataCollectorCounter
/// </code>
/// <para>
/// Gets all counters for the 'System Correlation' CollectorSet.
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
/// <seealso href="https://dbatools.io/Get-DbaPfDataCollectorCounter" />
[Cmdlet(VerbsCommon.Get, "DbaPfDataCollectorCounter")]
public sealed class GetDbaPfDataCollectorCounterCommand : DbaBaseCmdlet
{
    /// <para>
    /// Specifies the target server(s) where Performance Monitor Data Collector Sets are configured.
    /// Use this to audit performance counters on remote SQL Server instances or retrieve counter configurations from multiple servers at once.
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
    /// Filters results to specific Data Collector Set names such as 'System Correlation' or custom SQL performance monitoring sets.
    /// Use this when you need to examine counters for particular monitoring scenarios rather than reviewing all configured performance data collection.
    /// </para>
    [Parameter(Position = 2)]
    [Alias("DataCollectorSet")]
    public string[]? CollectorSet { get; set; }

    /// <para>
    /// Filters results to specific Data Collector names within a Collector Set.
    /// Use this to narrow down results when a Collector Set contains multiple data collectors and you only need counter details from specific ones.
    /// </para>
    [Parameter(Position = 3)]
    [Alias("DataCollector")]
    public string[]? Collector { get; set; }

    /// <para>
    /// Searches for specific performance counter names using the exact Windows Performance Monitor format like '\SQLServer:Buffer Manager\Page life expectancy' or '\Processor(_Total)\% Processor Time'.
    /// Use this to verify if critical SQL Server or system performance counters are being monitored in your data collection setup.
    /// </para>
    [Parameter(Position = 4)]
    public string[]? Counter { get; set; }

    /// <para>
    /// Accepts Data Collector objects from Get-DbaPfDataCollector via the pipeline to extract counter configurations.
    /// Use this for chaining commands when you want to drill down from Collector Sets to specific Data Collectors and then to their individual performance counters.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public object[]? InputObject { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    // PS: Select-DefaultView -ExcludeProperty DataCollectorObject, Credential, CounterObject, DataCollectorSetXml
    private static readonly string[] ExcludedColumns = { "DataCollectorObject", "Credential", "CounterObject", "DataCollectorSetXml" };

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
            object? inputCredential = GetDbaPfDataCollectorCommand.MemberEnumeration(inputs, "Credential");
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

        // PS: if (-not $InputObject -or ($InputObject -and (Test-Bound -ParameterName ComputerName))) {
        //         foreach ($computer in $ComputerName) { $InputObject += Get-DbaPfDataCollector -ComputerName $computer -Credential $Credential -CollectorSet $CollectorSet -Collector $Collector } }
        // The nested Get-DbaPfDataCollector has no input and no -EnableException: its nested Get-DbaPfDataCollectorSet failure only warns.
        // Its statement errors (a set whose XML cannot be read) are written here, and stop under this command's -EnableException as this
        // command's own do ("Operator decision: keep going unless -EnableException", point 3).
        if (!GetDbaPfDataCollectorCommand.IsTrueList(inputs) || TestBound("ComputerName"))
        {
            GetDbaPfDataCollectorCommand.CollectorReader reader = new(this, CollectorSet, Collector,
                (function, message, target, record) => WarnNestedStopFunction(function, message, target: target, errorRecord: record),
                (function, message) => WriteAttributedMessage(function, MessageLevel.Verbose, message),
                ReportFault);
            foreach (DbaInstanceParameter? computer in ComputerName ?? Array.Empty<DbaInstanceParameter>())
            {
                // PS: Get-DbaPfDataCollector -ComputerName $null reads no computer.
                if (computer is null)
                    continue;
                reader.ReadComputer(computer.ComputerName, credential, inputs.Add);
            }
        }

        // PS: if ($InputObject) { if (-not $InputObject.DataCollectorObject) { Stop-Function -Message "..."; return } }
        // No Test-FunctionInterrupt follows in the pin, so a later pipeline record is still read. A property read that fails in the
        // condition is a statement error, and the collectors are read.
        bool wrongType = false;
        try
        {
            wrongType = GetDbaPfDataCollectorCommand.IsTrueList(inputs) && !LanguagePrimitives.IsTrue(GetDbaPfDataCollectorCommand.MemberEnumeration(inputs, "DataCollectorObject"));
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
            StopFunction("InputObject is not of the right type. Please use Get-DbaPfDataCollector.");
            return;
        }

        foreach (object? counterObject in inputs)
            WriteCounterRows(counterObject, Counter, credential, ReportFault, WriteObject);
    }

    // PS (public/Get-DbaPfDataCollectorCounterSample.ps1): Get-DbaPfDataCollectorCounter -ComputerName $computer -Credential $Credential
    // -CollectorSet $CollectorSet -Collector $Collector, with no input and no -Counter: the computer's collectors through the reader, then
    // the counter rows of each. The sample command supplies the reader and its own statement-error path, as this command does.
    internal static void ReadComputerCounters(GetDbaPfDataCollectorCommand.CollectorReader reader, string computer, PSCredential? credential,
        Action<Exception, string> fault, Action<PSObject> emit)
    {
        List<object?> collectors = new();
        reader.ReadComputer(computer, credential, collectors.Add);
        foreach (object? collector in collectors)
            WriteCounterRows(collector, null, credential, fault, emit);
    }

    // The counter rows of one collector row: the pin's loop over $counterobject.Counters with its -Counter filter.
    private static void WriteCounterRows(object? counterObject, string[]? counter, PSCredential? credential, Action<Exception, string> fault,
        Action<PSObject> emit)
    {
        // PS: foreach ($countername in $counterobject.Counters): a read that fails is a statement error, and the loop goes on
        // with the next collector.
        List<object?> counters;
        try
        {
            counters = GetDbaPfDataCollectorCommand.ForeachItems(GetDbaPfDataCollectorCommand.Member(counterObject, "Counters"));
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            fault(ex, "RuntimeException");
            return;
        }

        foreach (object? counterName in counters)
        {
            // PS: if ($Counter -and $Counter -notcontains $countername) { continue }
            if (LanguagePrimitives.IsTrue(counter) && !CounterListed(counter!, counterName))
                continue;

            // PS: [PSCustomObject]@{ ... } | Select-DefaultView ...: a property read that fails is a statement error, and the loop
            // goes on with the next counter.
            try
            {
                emit(CounterRow(counterObject, counterName, credential));
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                fault(ex, "RuntimeException");
            }
        }
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

    // PS: the 8-property PSCustomObject, in its written order, and Select-DefaultView -ExcludeProperty.
    private static PSObject CounterRow(object? counterObject, object? counterName, PSCredential? credential)
    {
        PSObject row = new();
        row.Properties.Add(new PSNoteProperty("ComputerName", GetDbaPfDataCollectorCommand.Member(counterObject, "ComputerName"))); // style-ok: cs-output-props pinned Windows computer of the collector; no SQL Server connection exists.
        row.Properties.Add(new PSNoteProperty("DataCollectorSet", GetDbaPfDataCollectorCommand.Member(counterObject, "DataCollectorSet")));
        row.Properties.Add(new PSNoteProperty("DataCollector", GetDbaPfDataCollectorCommand.Member(counterObject, "Name")));
        row.Properties.Add(new PSNoteProperty("DataCollectorSetXml", GetDbaPfDataCollectorCommand.Member(counterObject, "DataCollectorSetXml")));
        row.Properties.Add(new PSNoteProperty("Name", counterName));
        row.Properties.Add(new PSNoteProperty("FileName", GetDbaPfDataCollectorCommand.Member(counterObject, "FileName")));
        row.Properties.Add(new PSNoteProperty("CounterObject", true));
        row.Properties.Add(new PSNoteProperty("Credential", credential));
        OutputHelper.SetDefaultDisplayPropertySetExcluding(row, ExcludedColumns);
        return row;
    }

    // PS: -contains, case-insensitive with the invariant culture. The help asks for the exact counter path, so no wildcard matching.
    // Get-DbaPfDataCollectorCounterSample's -notcontains filter is the same comparison.
    internal static bool CounterListed(string[] counters, object? counterName)
    {
        foreach (string listed in counters)
        {
            if (LanguagePrimitives.Equals(listed, counterName, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }
}
