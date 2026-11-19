#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaPfDataCollectorSet.ps1 at refs/pins/dbatools-2026-10-22. The pin runs its set script block through
// Invoke-Command2 for each computer: in this process for a local address, in a remote session otherwise, and passes the rows through
// Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName and Select-DefaultView. The script block
// is GetDbaPfDataCollectorCommand.CollectorReader, which Get-DbaPfDataCollector and Get-DbaPfDataCollectorCounter also read sets
// with: the local computer through the Task Scheduler and Performance Logs and Alerts COM objects, a remote computer in a remote
// runspace by one script that takes -CollectorSet as a parameter. This command asks the reader for the full rows built here.
/// <summary>Retrieves Windows Performance Monitor Data Collector Sets and their configuration details.</summary>
/// <para>
/// Retrieves detailed information about Windows Performance Monitor Data Collector Sets, which are used to collect performance counters for SQL Server monitoring and troubleshooting. Data Collector Sets define what performance counters to collect, when to collect them, and where to store the collected data. This function helps DBAs inventory existing collector sets, check their status (running, stopped, scheduled), and review their configuration including output locations and schedules. Particularly useful when inheriting a SQL Server environment or auditing existing performance monitoring setup.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollectorSet
/// </code>
/// <para>
/// Gets all Collector Sets on localhost.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollectorSet -ComputerName sql2017
/// </code>
/// <para>
/// Gets all Collector Sets on sql2017.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollectorSet -ComputerName sql2017 -Credential ad\sqldba -CollectorSet 'System Correlation'
/// </code>
/// <para>
/// Gets the 'System Correlation' CollectorSet on sql2017 using alternative credentials.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPfDataCollectorSet | Select-Object *
/// </code>
/// <para>
/// Displays extra columns and also exposes the original COM object in DataCollectorSetObject.
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
/// <seealso href="https://dbatools.io/Get-DbaPfDataCollectorSet" />
[Cmdlet(VerbsCommon.Get, "DbaPfDataCollectorSet")]
public sealed class GetDbaPfDataCollectorSetCommand : DbaBaseCmdlet
{
    /// <para>
    /// Specifies the Windows server(s) where you want to inventory Performance Monitor Data Collector Sets.
    /// Use this when checking collector sets across multiple SQL Server hosts or when managing performance monitoring from a central location.
    /// Accepts multiple computer names and defaults to the local computer.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 0)]
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
    /// Specifies the name(s) of specific Data Collector Sets to retrieve instead of returning all collector sets.
    /// Use this when you need to check the status or configuration of specific performance monitoring setups like 'SQL Server Default' or custom collector sets.
    /// Accepts wildcards and multiple collector set names for targeted monitoring inventory.
    /// </para>
    [Parameter(Position = 2)]
    [Alias("DataCollectorSet")]
    public string[]? CollectorSet { get; set; }

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
        "ComputerName", "Name", "DisplayName", "Description", "State", "Duration", "OutputLocation", "LatestOutputLocation", "RootPath",
        "SchedulesEnabled", "Segment", "SegmentMaxDuration", "SegmentMaxSize", "SerialNumber", "Server", "StopOnCompletion", "Subdirectory",
        "SubdirectoryFormat", "SubdirectoryFormatPattern", "Task", "TaskArguments", "TaskRunAsSelf", "TaskUserTextArguments", "UserAccount",
    };

    // PS (set script): the [PSCustomObject] row's properties, in order. The IDataCollectorSet values between RootPath and
    // StopOnCompletion are read under their own names.
    internal static readonly string[] RowProperties =
    {
        "ComputerName", "Name", "LatestOutputLocation", "OutputLocation", "RemoteOutputLocation", "RemoteLatestOutputLocation", "RootPath",
        "Duration", "Description", "DescriptionUnresolved", "DisplayName", "DisplayNameUnresolved", "Keywords", "Segment", "SegmentMaxDuration",
        "SegmentMaxSize", "SerialNumber", "Server", "Status", "Subdirectory", "SubdirectoryFormat", "SubdirectoryFormatPattern", "Task",
        "TaskRunAsSelf", "TaskArguments", "TaskUserTextArguments", "Schedules", "SchedulesEnabled", "UserAccount", "Xml", "Security",
        "StopOnCompletion", "State", "DataCollectorSetObject", "TaskObject", "Credential",
    };

    // PS: Invoke-Command2 without -Raw: Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName.
    private static readonly string[] RemotingProperties = { "PSComputerName", "RunspaceId", "PSShowComputerName" };

    // PS: [DbaInstance[]]$ComputerName = $env:COMPUTERNAME; an unset variable leaves the parameter null.
    private static DbaInstanceParameter[]? DefaultComputerName()
    {
        string? name = Environment.GetEnvironmentVariable("COMPUTERNAME");
        return String.IsNullOrEmpty(name) ? null : new[] { new DbaInstanceParameter(name) };
    }

    protected override void ProcessRecord()
    {
        // PS: try { Invoke-Command2 ... -ErrorAction Stop | Select-DefaultView -Property $columns }
        //     catch { Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue }
        // under this command's -EnableException. Rows read before a failure are already written, as the pipeline streams them.
        GetDbaPfDataCollectorCommand.CollectorReader reader = new(this, CollectorSet, null,
            (function, message, target, record) => StopFunction(message, target: target, errorRecord: record, continueLoop: true),
            (function, message) => WriteAttributedMessage(function, MessageLevel.Verbose, message),
            // The statement-error path of the collector read, which this command never takes: it reads no collectors.
            (fault, errorId) => throw new InvalidOperationException(fault.Message, fault),
            fullRows: true);

        // PS: foreach ($computer in $ComputerName.ComputerName): member enumeration skips a null element.
        foreach (DbaInstanceParameter? computer in ComputerName ?? Array.Empty<DbaInstanceParameter>())
        {
            if (computer is null)
                continue;
            reader.ReadCollectorSets(computer.ComputerName, Credential, row =>
            {
                PSObject output = (PSObject)row!;
                OutputHelper.SetDefaultDisplayPropertySet(output, Columns);
                WriteObject(output);
            });
        }
    }

    // PS (set script): if ($outputlocation) { $dir = (Split-Path $outputlocation).Replace(':', '$'); $remote = "\\$env:COMPUTERNAME\$dir" }
    // else { $remote = $null }; if ($latestoutputlocation) { $dir = ($latestoutputlocation).Replace(':', '$');
    // $remotelatest = "\\$env:COMPUTERNAME\$dir" } else { $remotelatest = $null }. The two variables live across the set loop.
    // Split-Path's parent is the session's PathIntrinsics.ParseParent, the call Split-Path makes.
    // Correction remote-locations: the pin's last else sets $remote = $null, so a set that has not run reports no
    // RemoteOutputLocation and the previous set's RemoteLatestOutputLocation.
    internal static void RemoteLocations(PathIntrinsics paths, string? computerName, object? outputLocation, object? latestOutputLocation,
        ref object? remote, ref object? remoteLatest)
    {
        if (LanguagePrimitives.IsTrue(outputLocation))
        {
            string dir = paths.ParseParent(LanguagePrimitives.ConvertTo<string>(outputLocation), String.Empty).Replace(':', '$');
            remote = @"\\" + computerName + @"\" + dir;
        }
        else
        {
            remote = null;
        }

        if (LanguagePrimitives.IsTrue(latestOutputLocation))
        {
            string dir = LanguagePrimitives.ConvertTo<string>(latestOutputLocation).Replace(':', '$');
            remoteLatest = @"\\" + computerName + @"\" + dir;
        }
        else
        {
            remoteLatest = null;
        }
    }

    // PS (set script): the [PSCustomObject] row of one set, as Invoke-Command2's Select-Object copies it. values holds the set's
    // IDataCollectorSet properties by name.
    internal static PSObject LocalRow(string? computerName, object? setName, IDictionary<string, object?> values, object? remote,
        object? remoteLatest, string state, object? task, PSCredential? credential)
    {
        Dictionary<string, object?> named = new(values, StringComparer.Ordinal)
        {
            ["ComputerName"] = computerName,
            ["Name"] = setName,
            ["RemoteOutputLocation"] = remote,
            ["RemoteLatestOutputLocation"] = remoteLatest,
            ["State"] = state,
            ["DataCollectorSetObject"] = true,
            ["TaskObject"] = task,
            ["Credential"] = credential,
        };
        object?[] cells = new object?[RowProperties.Length];
        for (int index = 0; index < RowProperties.Length; index++)
            cells[index] = named.TryGetValue(RowProperties[index], out object? value) ? value : null;
        return SelectedRow(RowProperties, cells);
    }

    // PS: a row the remote script block returned, as Invoke-Command2's Select-Object copies it without the remoting properties. The
    // remote script returns every property but Credential ($args[1], the caller's -Credential), which is added here.
    internal static PSObject RemoteRow(PSObject row, PSCredential? credential)
    {
        List<string> names = new();
        List<object?> cells = new();
        foreach (PSPropertyInfo property in row.Properties)
        {
            if (Array.IndexOf(RemotingProperties, property.Name) >= 0)
                continue;
            names.Add(property.Name);
            cells.Add(property.Value);
        }
        names.Add(RowProperties[RowProperties.Length - 1]);
        cells.Add(credential);
        return SelectedRow(names.ToArray(), cells.ToArray());
    }

    // PS: Select-Object -Property * writes a new PSCustomObject whose type names start with "Selected." and the input's base type.
    private static PSObject SelectedRow(string[] names, object?[] cells)
    {
        PSObject row = new();
        for (int index = 0; index < names.Length; index++)
            row.Properties.Add(new PSNoteProperty(names[index], cells[index]));
        row.TypeNames.Insert(0, "Selected." + typeof(PSCustomObject).FullName);
        return row;
    }
}
