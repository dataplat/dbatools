#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaMaintenanceSolutionLog.ps1 at refs/pins/dbatools-2026-10-22: reads the IndexOptimize text logs of
// Ola Hallengren's MaintenanceSolution from the instance's log directory over its admin share, one object per operation.
/// <summary>Parses IndexOptimize text log files from Ola Hallengren's MaintenanceSolution when database logging is disabled.</summary>
/// <para>
/// Retrieves detailed execution information from IndexOptimize text log files when LogToTable='N' is configured in Ola Hallengren's MaintenanceSolution. This function parses the text files written to the SQL Server instance's log directory, extracting index operation details including start times, duration, fragmentation levels, and any errors encountered.
/// </para>
/// <para>
/// This command specifically targets scenarios where database logging is disabled and only file-based logging is available. The parsed output includes granular details about each index operation, such as the specific ALTER INDEX commands executed, statistics updates, partition information, and operation outcomes.
/// </para>
/// <para>
/// Be aware that this command only works if sqlcmd is used to execute the procedures, which is a legacy method not used by newer installations. Currently, only IndexOptimize log parsing is supported - DatabaseBackup and DatabaseIntegrityCheck parsing are not yet available.
/// </para>
/// <para>
/// For modern deployments, we recommend using Install-DbaMaintenanceSolution and configuring procedures with LogToTable='Y' to enable database-based logging, which provides more reliable access to maintenance history.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaMaintenanceSolutionLog -SqlInstance sqlserver2014a
/// </code>
/// <para>
/// Gets the outcome of the IndexOptimize job on sql instance sqlserver2014a.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaMaintenanceSolutionLog -SqlInstance sqlserver2014a -SqlCredential $credential
/// </code>
/// <para>
/// Gets the outcome of the IndexOptimize job on sqlserver2014a, using SQL Authentication.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'sqlserver2014a', 'sqlserver2020test' | Get-DbaMaintenanceSolutionLog
/// </code>
/// <para>
/// Gets the outcome of the IndexOptimize job on sqlserver2014a and sqlserver2020test.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaMaintenanceSolutionLog -SqlInstance sqlserver2014a -Path 'D:\logs\maintenancesolution\'
/// </code>
/// <para>
/// Gets the outcome of the IndexOptimize job on sqlserver2014a, reading the log files in their custom location.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaMaintenanceSolutionLog -SqlInstance sqlserver2014a -Since '2017-07-18'
/// </code>
/// <para>
/// Gets the outcome of the IndexOptimize job on sqlserver2014a, starting from july 18, 2017.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaMaintenanceSolutionLog -SqlInstance sqlserver2014a -LogType IndexOptimize
/// </code>
/// <para>
/// Gets the outcome of the IndexOptimize job on sqlserver2014a, the other options are not yet available! sorry
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Community, OlaHallengren
/// Author: Klaas Vandenberghe (@powerdbaklaas) | Simone Bizzotto (@niphlod)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// <para>
/// https://ola.hallengren.com
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaMaintenanceSolutionLog" />
[Cmdlet(VerbsCommon.Get, "DbaMaintenanceSolutionLog", DefaultParameterSetName = "Default")]
public sealed class GetDbaMaintenanceSolutionLogCommand : DbaInstanceCmdlet
{
    // PS: the -match patterns of process-block, which -match runs with RegexOptions.IgnoreCase. Correction operation-names: the
    // database part of the name is optional, since the bundled IndexOptimize writes two-part names in the database's context, and
    // so is ALTER INDEX's WITH clause, which a RESUME (or a rebuild with no option) has not.
    private static readonly Regex AlterIndexPattern = new Regex(@"(SET LOCK_TIMEOUT (?<timeout>\d+); )?ALTER INDEX \[(?<index>[^\]]+)\] ON (\[(?<database>[^\]]+)\]\.)?\[(?<schema>[^]]+)\]\.\[(?<table>[^\]]+)\] (?<action>[^\ ]+)( PARTITION = (?<partition>\d+))?( WITH \((?<options>[^\)]+))?", RegexOptions.IgnoreCase);
    private static readonly Regex UpdateStatisticsPattern = new Regex(@"(SET LOCK_TIMEOUT (?<timeout>\d+); )?UPDATE STATISTICS (\[(?<database>[^\]]+)\]\.)?\[(?<schema>[^]]+)\]\.\[(?<table>[^\]]+)\] \[(?<stat>[^\]]+)\]", RegexOptions.IgnoreCase);

    // PS: -split ': ', 2 and -split ', ', regular expressions that match only their literal text.
    private static readonly Regex KeySeparator = new Regex(": ", RegexOptions.IgnoreCase);
    private static readonly Regex CommentSeparator = new Regex(", ", RegexOptions.IgnoreCase);

    // The fields a matched command sets, in the pin's order.
    private static readonly string[] OperationNames = { "Index", "Statistics", "Schema", "Table", "Action", "Options", "Timeout", "Partition" };

    // PS: the keys the database block drops before it becomes the remembered fields.
    private static readonly string[] DatabaseBlockDropped = { "Is accessible", "User access", "Date and time", "Standby", "Recovery Model", "Updateability" };

    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

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
    /// Specifies which Ola Hallengren maintenance solution log type to parse from text files. Accepts 'IndexOptimize', 'DatabaseBackup', or 'DatabaseIntegrityCheck'.
    /// Currently only IndexOptimize parsing is supported - use this when you need to analyze index rebuild and reorganize operations from file-based logs.
    /// DatabaseBackup and DatabaseIntegrityCheck parsing are planned for future releases.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    [ValidateSet("IndexOptimize", "DatabaseBackup", "DatabaseIntegrityCheck")]
    public string[] LogType { get; set; } = { "IndexOptimize" };

    /// <para>
    /// Filters log files to include only those created on or after the specified date and time.
    /// Use this when you need to focus on recent maintenance operations or investigate issues that started after a specific point in time.
    /// The function examines both the filename timestamp and file creation time to determine which logs to process.
    /// </para>
    [Parameter(Position = 3)]
    [PsDateTimeCast]
    public DateTime Since { get; set; }

    /// <para>
    /// Specifies a custom directory path where maintenance solution log files are stored. Defaults to the SQL Server instance's error log directory.
    /// Use this when your maintenance solution jobs write logs to a non-standard location, such as a dedicated maintenance logs folder or shared network path.
    /// The path must be accessible from the machine where you're running the command.
    /// </para>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string? Path { get; set; }

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
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: $computername = $instance.ComputerName
            string computerName = instance.ComputerName;

            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential }
            //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
                continue;

            // PS: if ($LogType -ne 'IndexOptimize'): the array's elements other than IndexOptimize (ignoring case); any left warns
            // with the whole array as "$LogType" joins it, with a space.
            if (HasOtherLogType())
            {
                WriteMessage(MessageLevel.Warning, "Parsing " + String.Join(" ", LogType ?? Array.Empty<string>()) + " is not supported at the moment");
                continue;
            }

            // PS: if (!$instance.IsLocalHost -and $server.HostPlatform -ne "Windows")
            if (!instance.IsLocalHost && !LanguagePrimitives.Equals(server.HostPlatform, "Windows", true, CultureInfo.InvariantCulture))
            {
                WriteMessage(MessageLevel.Warning, "The target instance is not Windows so logs cannot be fetched remotely");
                continue;
            }

            // PS: Join-AdminUnc -Servername $server.ComputerName -Filepath ($Path, or $server.errorlogpath when $Path is empty).
            // Join-AdminUnc's -Filepath is [ValidateNotNullOrEmpty()]: where the server reports no error log path (Azure SQL Database),
            // its binder writes the record and the assignment leaves $logDir null, which is the next warning.
            string serverComputerName = SmoServerExtensions.GetComputerName(server) ?? String.Empty;
            string? logDir = null;
            if (!String.IsNullOrEmpty(Path))
            {
                logDir = JoinAdminUnc(serverComputerName, Path!);
            }
            else
            {
                string? errorLogPath = ErrorLogPathOf(server);
                if (String.IsNullOrEmpty(errorLogPath))
                    ReportBindingFault();
                else
                    logDir = JoinAdminUnc(serverComputerName, errorLogPath);
            }
            if (String.IsNullOrEmpty(logDir))
            {
                WriteMessage(MessageLevel.Warning, "No log directory returned from " + instance);
                continue;
            }

            WriteMessage(MessageLevel.Verbose, "Log directory on " + computerName + " is " + logDir);
            // PS: Test-Path $logDir, true for a directory or a file.
            if (!(Directory.Exists(logDir) || File.Exists(logDir)))
            {
                WriteMessage(MessageLevel.Warning, "Directory " + logDir + " is not accessible");
                continue;
            }

            List<string> logFiles = SelectLogFiles(logDir!);
            // PS: if (! $logFiles.count -ge 1)
            if (logFiles.Count < 1)
            {
                WriteMessage(MessageLevel.Warning, "No log files returned from " + computerName);
                continue;
            }

            foreach (string file in logFiles)
            {
                WriteMessage(MessageLevel.Verbose, "Reading " + file);
                ReadLog(file, computerName, server);
            }
        }
    }

    private bool HasOtherLogType()
    {
        if (LogType is null)
            return false;
        foreach (string type in LogType)
        {
            if (!LanguagePrimitives.Equals(type, "IndexOptimize", true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    // PS: $server.errorlogpath. PowerShell reads a property whose getter throws as $null, with no record.
    private static string? ErrorLogPathOf(Server server)
    {
        try
        {
            return server.ErrorLogPath;
        }
        catch (Exception failure) when (!(failure is PipelineStoppedException))
        {
            // The getter's fault is not reported, as PowerShell's property read does not report it.
            return null;
        }
    }

    // harness-edits.md, "Get-DbaMaintenanceSolutionLog: the Join-AdminUnc binder record on Azure SQL Database", points 2 and 3, with
    // the binder section's point 1: the record of Join-AdminUnc's binder rejecting a null -Filepath. The binder's own exception type is
    // internal, so the record carries its public base and the Reason callers read. The pin's activity follows its id suffix: the
    // nested command when the caller has no try and the call has no -ErrorAction Stop; under either, the engine's default is the pin's.
    private void ReportBindingFault()
    {
        ErrorRecord fault = new ErrorRecord(
            new ParameterBindingException("Cannot validate argument on parameter 'filepath'. The argument is null or empty. Provide an argument that is not null or empty, and then try the command again."),
            "ParameterArgumentValidationError", ErrorCategory.InvalidData, null);
        fault.CategoryInfo.Reason = "ParameterBindingValidationException";
        bool stopAsked = MyInvocation.BoundParameters.TryGetValue("ErrorAction", out object? errorAction)
            && String.Equals(LanguagePrimitives.ConvertTo<string>(errorAction), "Stop", StringComparison.OrdinalIgnoreCase);
        if (!stopAsked && !StatementFault.CallerHasEnclosingTry(this))
            fault.CategoryInfo.Activity = "Join-AdminUnc";

        // A plain call goes on to the warning.
        ReportFault(fault);
    }

    // A statement fault of the pin. Accepted difference of the keep-going section: -EnableException stops here with the record, where
    // the pin writes it and goes on. Otherwise StatementFault.Surface: a plain call writes it and goes on, -ErrorAction Stop has the
    // effect PowerShell gives WriteError, and under a caller try the record stops the command, as the fault stops the pin's statement.
    private void ReportFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }
        StatementFault.Surface(this, fault);
    }

    /// <summary>
    /// PS: Join-AdminUnc. A path already on a share, and any path when PowerShell runs on Linux or macOS, comes back as it is;
    /// otherwise Join-Path "\\server\" with the path's colon as $, where Join-Path turns / into \ and joins with one \.
    /// </summary>
    private static string? JoinAdminUnc(string serverName, string? filePath)
    {
        if (String.IsNullOrEmpty(filePath))
            return null;
        if (Environment.OSVersion.Platform != PlatformID.Win32NT || filePath!.StartsWith("\\\\", StringComparison.Ordinal))
            return filePath;

        string child = filePath.Replace(':', '$').Replace('/', '\\');
        if (child.StartsWith("\\", StringComparison.Ordinal))
            child = child.Substring(1);
        return "\\\\" + serverName.Split('\\')[0] + "\\" + child;
    }

    /// <summary>
    /// PS: [System.IO.Directory]::EnumerateFiles("$logDir", "IndexOptimize_*.txt"), then the Since filter. A [datetime] is always
    /// true, so the filter always runs, against DateTime.MinValue when -Since is not given: a file's date is its name's last 15
    /// characters read as yyyyMMdd_HHmmss in the current culture, else its creation time, and it is kept when later than Since.
    /// </summary>
    private List<string> SelectLogFiles(string logDir)
    {
        List<string> filtered = new List<string>();
        IEnumerable<string> logFiles;
        try
        {
            logFiles = Directory.EnumerateFiles(logDir, "IndexOptimize_*.txt");
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS: the call's statement fails, $logFiles stays $null and the filter keeps nothing.
            ReportFault(MethodFault("EnumerateFiles", 2, failure));
            return filtered;
        }

        try
        {
            foreach (string l in logFiles)
            {
                string fileDate = l.Substring(l.Length - 15, 15);
                DateTime dateFile;
                if (!DateTime.TryParseExact(fileDate, "yyyyMMdd_HHmmss", CultureInfo.CurrentCulture, DateTimeStyles.None, out dateFile))
                {
                    // PS: Get-ItemProperty -Path $l | Select-Object -ExpandProperty CreationTime. A file gone since the listing gives
                    // Get-ItemProperty's not-found record and no date, so it is not kept; that record is not reproduced.
                    FileInfo info = new FileInfo(l);
                    if (!info.Exists)
                        continue;
                    dateFile = info.CreationTime;
                }
                if (dateFile > Since)
                    filtered.Add(l);
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS: an enumeration fault ends the foreach statement; the files kept so far are read.
            ReportFault(StatementFault.Record(failure, "BadEnumeration"));
        }
        return filtered;
    }

    /// <summary>PS: the StreamReader loop of one file.</summary>
    private void ReadLog(string file, string computerName, Server server)
    {
        StreamReader text;
        try
        {
            text = new StreamReader(file);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS: New-Object System.IO.StreamReader fails with ConstructorInvokedThrowException; the pin then reads the previous
            // file's closed reader (or $null) and writes the records of those calls, which the port does not make.
            ReportFault(new ErrorRecord(new MethodInvocationException(MethodFaultMessage(".ctor", 1, failure), failure), "ConstructorInvokedThrowException", ErrorCategory.InvalidOperation, null));
            return;
        }

        using (text)
        {
            ArrayList block = new ArrayList();
            Hashtable remember = NewHashtable(0);
            while (true)
            {
                string? line;
                try
                {
                    line = text.ReadLine();
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    ReportFault(MethodFault("ReadLine", 0, failure));
                    return;
                }

                // PS: while ($line = $text.ReadLine()) ends at the end of the file and at the first empty line. Correction
                // empty-line-stop: only the end of the file ends the loop; an empty line separates blocks, as a tab line does.
                if (line is null)
                    break;

                string real = line.Trim();
                if (real.Length != 0)
                {
                    block.Add(real);
                    continue;
                }

                Hashtable processed = ProcessBlock(block);
                block = new ArrayList();
                if (processed.ContainsKey("Procedure"))
                    continue;

                if (processed.ContainsKey("Database"))
                {
                    WriteMessage(MessageLevel.Verbose, "Index and Stats Optimizations on Database " + processed["Database"] + " on " + computerName);
                    foreach (string dropped in DatabaseBlockDropped)
                        processed.Remove(dropped);
                    processed["Database"] = Convert.ToString(processed["Database"], CultureInfo.InvariantCulture)?.Trim('[', ']');
                    remember = (Hashtable)processed.Clone();
                    continue;
                }

                // Correction operation-blocks: only a block with a Command line is an operation. The pin also wrote the parameter
                // listing and the closing date of the procedure as objects, the listing with a ParseExact fault for its missing date
                // and the closing date as a copy of the last operation; such a block leaves the remembered fields as they are.
                if (!processed.ContainsKey("Command"))
                    continue;

                EmitOperation(processed, remember, server);
            }
        }
    }

    /// <summary>
    /// PS: the else branch: the block's keys over the remembered fields, StartTime as a [dbadatetime] of the start date, Duration
    /// -as [timespan], and [PSCustomObject]$remember, whose properties follow the hashtable's enumeration order.
    /// </summary>
    private void EmitOperation(Hashtable processed, Hashtable remember, Server server)
    {
        foreach (object key in processed.Keys)
            remember[key] = processed[key];
        remember.Remove("Command");

        // PS: $remember['StartTime'] = [dbadatetime]([DateTime]::ParseExact($remember['Date and time'], "yyyy-MM-dd HH:mm:ss", $null)).
        // A fault writes the call's record, leaves StartTime as it was and goes on to the next statement (a caller's try or -EnableException ends the
        // command there instead). PowerShell passes "" for a missing date to the string parameter, so the fault is the runtime's
        // FormatException for an empty string.
        try
        {
            string started = remember["Date and time"] is null ? String.Empty : LanguagePrimitives.ConvertTo<string>(remember["Date and time"]);
            remember["StartTime"] = new DbaDateTime(DateTime.ParseExact(started, "yyyy-MM-dd HH:mm:ss", CultureInfo.CurrentCulture));
        }
        catch (FormatException failure)
        {
            ReportFault(MethodFault("ParseExact", 3, failure));
        }
        remember.Remove("Date and time");
        remember["Duration"] = AsTimeSpan(remember["Duration"]);

        // Correction instance-properties: the pin built ComputerName, InstanceName and SqlInstance ($instanceInfo) and never added
        // them; they come first, as on every dbatools object. A log key of the same name, which IndexOptimize never writes, is left out.
        PSObject output = new PSObject();
        OutputHelper.AddInstanceProperties(output, server);
        foreach (DictionaryEntry entry in remember)
        {
            string name = Convert.ToString(entry.Key, CultureInfo.InvariantCulture)!;
            if (output.Properties[name] is null)
                output.Properties.Add(new PSNoteProperty(name, entry.Value));
        }
        WriteObject(output);
    }

    /// <summary>
    /// PS: process-block. The ten fields every block starts with; each "key: value" line with a key of at most 20 characters sets
    /// its key (a second "Date and time" is the end date and is skipped), any other line joins Error; then the command's names
    /// and the comment's known fields.
    /// </summary>
    private static Hashtable ProcessBlock(ArrayList block)
    {
        Hashtable fresh = NewHashtable(10);
        fresh.Add("ObjectType", null);
        fresh.Add("IndexType", null);
        fresh.Add("ImageText", null);
        fresh.Add("NewLOB", null);
        fresh.Add("FileStream", null);
        fresh.Add("ColumnStore", null);
        fresh.Add("AllowPageLocks", null);
        fresh.Add("PageCount", null);
        fresh.Add("Fragmentation", null);
        fresh.Add("Error", null);

        foreach (string l in block)
        {
            string[] splitted = KeySeparator.Split(l, 2);
            if (splitted.Length != 2 || splitted[0].Length > 20)
            {
                if (fresh["Error"] is null)
                    fresh["Error"] = new ArrayList();
                // PS: $fresh['Error'].Add($l); an Error key read from the log as a string has no Add and keeps its value.
                if (fresh["Error"] is ArrayList errors)
                    errors.Add(l);
                continue;
            }
            string k = splitted[0];
            string v = splitted[1];
            if (String.Equals(k, "Date and Time", StringComparison.OrdinalIgnoreCase) && fresh.ContainsKey(k))
                continue;
            fresh[k] = v;
        }

        if (fresh.ContainsKey("Command"))
        {
            string command = LanguagePrimitives.ConvertTo<string>(fresh["Command"]) ?? String.Empty;
            Match alter = AlterIndexPattern.Match(command);
            Match statistics = alter.Success ? Match.Empty : UpdateStatisticsPattern.Match(command);
            if (alter.Success)
            {
                fresh["Index"] = alter.Groups["index"].Value;
                fresh["Statistics"] = null;
                fresh["Schema"] = alter.Groups["schema"].Value;
                fresh["Table"] = alter.Groups["table"].Value;
                fresh["Action"] = alter.Groups["action"].Value;
                fresh["Options"] = GroupValue(alter, "options");
                fresh["Timeout"] = GroupValue(alter, "timeout");
                fresh["Partition"] = GroupValue(alter, "partition");
            }
            else if (statistics.Success)
            {
                fresh["Index"] = null;
                fresh["Statistics"] = statistics.Groups["stat"].Value;
                fresh["Schema"] = statistics.Groups["schema"].Value;
                fresh["Table"] = statistics.Groups["table"].Value;
                fresh["Action"] = null;
                fresh["Options"] = null;
                fresh["Timeout"] = GroupValue(statistics, "timeout");
                fresh["Partition"] = null;
            }
            else
            {
                // Correction operation-names: a command neither pattern reads names nothing, where the pin's object kept the names
                // the previous operation left in the remembered fields.
                foreach (string name in OperationNames)
                    fresh[name] = null;
            }
        }

        if (fresh.ContainsKey("Comment"))
        {
            string comment = LanguagePrimitives.ConvertTo<string>(fresh["Comment"]) ?? String.Empty;
            foreach (string part in CommentSeparator.Split(comment))
            {
                // PS: $indKey, $indValue = $part -split ': ', 2
                string[] pair = KeySeparator.Split(part, 2);
                string indKey = pair[0];
                string? indValue = pair.Length > 1 ? pair[1] : null;
                if (fresh.ContainsKey(indKey))
                    fresh[indKey] = indValue;
            }
        }

        if (fresh["Error"] is not null)
            fresh["Error"] = fresh["Error"] is ArrayList lines ? String.Join("\n", lines.ToArray()) : fresh["Error"];

        return fresh;
    }

    // PS: $Matches.<name>: a group that did not take part in the match is not in $Matches, so it reads $null.
    private static string? GroupValue(Match match, string name)
    {
        Group group = match.Groups[name];
        return group.Success ? group.Value : null;
    }

    // PS: a hashtable literal is new Hashtable(<pair count>, StringComparer.CurrentCultureIgnoreCase); the same capacity, comparer
    // and order of insertion give the pin's enumeration order (on .NET Framework; string hashing changes per process on .NET).
    private static Hashtable NewHashtable(int capacity)
    {
        return new Hashtable(capacity, StringComparer.CurrentCultureIgnoreCase);
    }

    // PS: $value -as [timespan], $null when the value does not convert (or is $null).
    private static object? AsTimeSpan(object? value)
    {
        if (value is null)
            return null;
        object converted;
        return LanguagePrimitives.TryConvertTo(value, typeof(TimeSpan), CultureInfo.InvariantCulture, out converted) ? converted : null;
    }

    // PS: the record of a .NET method call that throws: a MethodInvocationException over the fault, the fault's type name as its id.
    private static ErrorRecord MethodFault(string method, int argumentCount, Exception failure)
    {
        return new ErrorRecord(new MethodInvocationException(MethodFaultMessage(method, argumentCount, failure), failure), failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    private static string MethodFaultMessage(string method, int argumentCount, Exception failure)
    {
        return String.Format(CultureInfo.InvariantCulture, "Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"", method, argumentCount, failure.Message);
    }
}
