#nullable enable

using System;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaErrorLog.ps1 at refs/pins/dbatools-2026-10-22: the error log rows of each instance, oldest log first when no -LogNumber is given, each row the SMO DataRow with the instance notes and the default view.
// Expected values as the pin measured on both editions: evidence/pin-errorlog-20261104.txt and pin-errorlog2-20261104.txt, whose case names the comments below use.
/// <summary>Retrieves SQL Server error log entries for troubleshooting and monitoring</summary>
/// <para>
/// Retrieves entries from SQL Server error logs across all available log files (0-99, where 0 is current and 99 is oldest).
/// Essential for troubleshooting SQL Server issues, monitoring login failures, tracking system events, and compliance auditing.
/// Supports filtering by log number, source type, text patterns, and date ranges to quickly locate specific errors or events.
/// Reads from all available error logs by default, so you don't have to check each log file manually.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaErrorLog -SqlInstance sql01\sharepoint
/// </code>
/// <para>
/// Returns every log entry from sql01\sharepoint SQL Server instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaErrorLog -SqlInstance sql01\sharepoint -LogNumber 3, 6
/// </code>
/// <para>
/// Returns all log entries for log number 3 and 6 on sql01\sharepoint SQL Server instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaErrorLog -SqlInstance sql01\sharepoint -Source Logon
/// </code>
/// <para>
/// Returns every log entry, with a source of Logon, from sql01\sharepoint SQL Server instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaErrorLog -SqlInstance sql01\sharepoint -LogNumber 3 -Text "login failed"
/// </code>
/// <para>
/// Returns every log entry for log number 3, with "login failed" in the text, from sql01\sharepoint SQL Server instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
/// PS C:\&gt; $servers | Get-DbaErrorLog -LogNumber 0
/// </code>
/// <para>
/// Returns the most recent SQL Server error logs for "sql2014","sql2016" and "sqlcluster\sharepoint"
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaErrorLog -SqlInstance sql01\sharepoint -After '2016-11-14 00:00:00'
/// </code>
/// <para>
/// Returns every log entry found after the date 14 November 2016 from sql101\sharepoint SQL Server instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaErrorLog -SqlInstance sql01\sharepoint -Before '2016-08-16 00:00:00'
/// </code>
/// <para>
/// Returns every log entry found before the date 16 August 2016 from sql101\sharepoint SQL Server instance.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Logging, Instance, ErrorLog
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
/// <seealso href="https://dbatools.io/Get-DbaErrorLog" />
[Cmdlet(VerbsCommon.Get, "DbaErrorLog")]
public sealed class GetDbaErrorLogCommand : DbaInstanceCmdlet
{
    private const int NewestLog = 0;
    private const int OldestLog = 99;

    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

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
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies which error log file to read by index number (0-99), where 0 is the current active log and higher numbers are older archived logs.
    /// Use this to target specific log files when troubleshooting issues from a particular time period or to avoid reading all logs for performance.
    /// SQL Server keeps 6 log files by default but can be configured up to 99 archived logs.
    /// </para>
    [Parameter(Position = 2)]
    [ValidateRange(NewestLog, OldestLog)]
    public int[]? LogNumber { get; set; }

    /// <para>
    /// Filters log entries by the source component that generated the message, such as "Logon", "Server", "Backup", or "spid123".
    /// Use this to focus on specific SQL Server subsystems when troubleshooting authentication issues, backup problems, or tracking activity from particular processes.
    /// </para>
    [Parameter(Position = 3)]
    public object[]? Source { get; set; }

    /// <para>
    /// Searches for log entries containing specific text patterns using wildcard matching (supports * wildcards).
    /// Use this to find specific error messages, user names, database names, or any text string within log entries for targeted troubleshooting.
    /// </para>
    [Parameter(Position = 4)]
    public string? Text { get; set; }

    /// <para>
    /// Returns only log entries that occurred after the specified date and time.
    /// Use this to focus on recent events or investigate issues that started after a known point in time, such as after a deployment or configuration change.
    /// </para>
    [Parameter(Position = 5)]
    [PsDateTimeCast]
    public DateTime After { get; set; }

    /// <para>
    /// Returns only log entries that occurred before the specified date and time.
    /// Use this to investigate historical issues, exclude recent events from analysis, or focus on problems that existed prior to a specific incident or change.
    /// </para>
    [Parameter(Position = 6)]
    [PsDateTimeCast]
    public DateTime Before { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        // no-instance, instance-null, piped-null: nothing to read and nothing written.
        if (SqlInstance is null)
            return;

        WildcardPattern? textPattern = String.IsNullOrEmpty(Text) ? null : new WildcardPattern("*" + Text + "*", WildcardOptions.IgnoreCase);

        foreach (DbaInstanceParameter? instance in SqlInstance)
        {
            // PS: Connect-DbaInstance declares -SqlInstance mandatory, so a null element faults inside the pinned try (instance-null-element, instance-null-element-ee).
            if (instance is null)
            {
                ParameterBindingException refused = new("Cannot bind argument to parameter 'SqlInstance' because it is null.");
                StopFunction("Failure", errorRecord: new ErrorRecord(refused, "ParameterArgumentValidationErrorNullNotAllowed", ErrorCategory.InvalidData, null),
                    category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            // Azure SQL Database has no error log, so it is refused as Connect-DbaInstance -AzureUnsupported does (correction azure-refusal).
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
                continue;

            foreach (int number in LogNumbers())
            {
                if (!TryReadLog(server, number, out DataTable? log) || log is null)
                    continue;

                foreach (DataRow row in log.Rows)
                {
                    if (SkipsRow(row, textPattern))
                        continue;

                    WriteMessage(MessageLevel.Verbose, "Processing " + row);
                    PSObject output = PSObject.AsPSObject(row);
                    OutputHelper.AddInstanceProperties(output, server);
                    OutputHelper.AddAliasProperty(output, "Source", "ProcessInfo");
                    OutputHelper.SetDefaultDisplayPropertySet(output, "ComputerName", "InstanceName", "SqlInstance", "LogDate", "Source", "Text");
                    WriteObject(output);
                }
            }
        }
    }

    // PS: every log from the oldest to the newest unless -LogNumber is bound; a bound empty array reads none (lognumber-empty), and bound numbers keep their order and repeats (lognumber-zero-one, lognumber-repeated).
    private int[] LogNumbers()
    {
        if (TestBound("LogNumber"))
            return LogNumber ?? new int[0];

        int[] numbers = new int[OldestLog - NewestLog + 1];
        for (int index = 0; index < numbers.Length; index++)
            numbers[index] = OldestLog - index;
        return numbers;
    }

    // PS: foreach ($object in $server.ReadErrorLog($number)), outside any try, on the connection as it stands: the same call writes one record per log number for a login that may not read the log
    // (low-plain, low-two-logs, low-all-logs) and on Azure SQL Database (azure-zero, azure-two), and the loop goes on to the next log number.
    private bool TryReadLog(Server server, int number, out DataTable? log)
    {
        log = null;
        ErrorRecord fault;
        try
        {
            log = server.ReadErrorLog(number);
            return true;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            fault = new ErrorRecord(new MethodInvocationException(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"ReadErrorLog\" with \"1\" argument(s): \"{0}\"", failure.Message), failure), failure.GetType().Name, ErrorCategory.NotSpecified, null);
        }
        ReportFault(fault);
        return false;
    }

    // PS: ($Source -and $object.ProcessInfo -ne $Source) -or ($Text -and $object.Text -notlike "*$Text*") -or ($After -and $object.LogDate -lt $After) -or ($Before -and $object.LogDate -gt $Before),
    // tested in that order and stopping at the first that holds. A bound -After or -Before is true even at DateTime.MinValue (filter-before-minvalue), and an unbound one is false.
    private bool SkipsRow(DataRow row, WildcardPattern? textPattern)
    {
        if (PsOps.IsTrue(Source) && !MatchesSource(row["ProcessInfo"]))
            return true;

        if (textPattern is not null)
        {
            ErrorRecord? fault = null;
            try
            {
                if (!textPattern.IsMatch(LanguagePrimitives.ConvertTo<string>(row["Text"])))
                    return true;
            }
            catch (WildcardPatternException failure)
            {
                fault = new ErrorRecord(failure, "RuntimeException", ErrorCategory.NotSpecified, null);
            }

            // text-lone-bracket: an invalid pattern faults the pin's whole if statement on each row -Source lets through, so that row has one record and goes out with neither -After nor -Before tested.
            if (fault is not null)
            {
                ReportFault(fault);
                return false;
            }
        }

        return (TestBound("After") && PsOps.Compare(row["LogDate"], After) < 0) || (TestBound("Before") && PsOps.Compare(row["LogDate"], Before) > 0);
    }

    // Correction source-array: in the pin $object.ProcessInfo -ne $Source turns an array into one string, so two values match nothing and the command returns nothing with no error
    // (source-two, source-two-same, source-null-element). Here each value is compared as -ne compares one value (source-one, source-case).
    private bool MatchesSource(object processInfo)
    {
        foreach (object? value in Source!)
        {
            if (PsOps.Eq(processInfo, value))
                return true;
        }
        return false;
    }

    // Accepted differences kept by the keep-going section's point 3: -EnableException stops here with this record, where the pin writes it and goes on (low-ee, azure-ee); -ErrorAction Stop has the
    // effect PowerShell gives WriteError (low-stop). $ErrorActionPreference set in the caller's scope acts on this WriteError as for any compiled command, where the pin ignores it:
    // harness-edits.md, "Script-scope preferences and the one-line connect warning", points 1 and 2.
    private void ReportFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }

        // A plain call goes on; under a caller try the record stops the command, as the fault stops the pin's statement (low-plain, low-try).
        StatementFault.Surface(this, fault);
    }
}
