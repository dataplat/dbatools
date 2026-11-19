#nullable enable

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Remoting;
using System.Management.Automation.Runspaces;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Discovers installed SQL Server features and components across multiple servers
/// </summary>
/// <para>
/// Executes SQL Server's built-in feature discovery report to inventory all installed SQL Server components, editions, and instances across one or more servers. This function automates the manual process of running setup.exe /Action=RunDiscovery and parsing the resulting XML report, making it perfect for compliance auditing, license tracking, and environment documentation.
/// </para>
/// <para>
/// The function returns structured data showing exactly what SQL Server features are installed, which instances they belong to, their versions, editions, and configuration status. This is essential for DBAs who need to understand their SQL Server landscape without manually checking each server or running discovery reports individually.
/// </para>
/// <para>
/// Inspired by Dave Mason's (@BeginTry) post at
/// https://itsalljustelectrons.blogspot.be/2018/04/SQL-Server-Discovery-Report.html
/// </para>
/// <para>
/// Assumptions:
/// 1. The sub-folder "Microsoft SQL Server" exists in [System.Environment]::GetFolderPath("ProgramFiles"),
/// even if SQL was installed to a non-default path. This has been
/// verified on SQL 2008R2 and SQL 2012. Further verification may be needed.
/// 2. The discovery report displays installed components for the version of SQL
/// Server associated with setup.exe, along with installed components of all
/// lesser versions of SQL Server that are installed.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaFeature -ComputerName sql2017, sql2016, sql2005
/// </code>
/// <para>
/// Gets all SQL Server features for all instances on sql2017, sql2016 and sql2005.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaFeature -Verbose
/// </code>
/// <para>
/// Gets all SQL Server features for all instances on localhost. Outputs to screen if no instances are found.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaFeature -ComputerName sql2017 -Credential ad\sqldba
/// </code>
/// <para>
/// Gets all SQL Server features for all instances on sql2017 using the ad\sqladmin credential (which has access to the Windows Server).
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Feature, Component, General
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
/// <seealso href="https://dbatools.io/Get-DbaFeature" />
[Cmdlet(VerbsCommon.Get, "DbaFeature")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaFeatureCommand : DbaBaseCmdlet
{
    /// <para>
    /// Specifies the Windows computer names where you want to discover SQL Server features and components. Accepts multiple computers for bulk discovery operations.
    /// Use this when you need to inventory SQL Server installations across your environment for compliance auditing or license tracking.
    /// Requires PowerShell remoting to be enabled on remote computers. Note that this targets the Windows host, not SQL instance names.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <para>
    /// Allows you to login to servers using alternative credentials. To use:
    /// </para>
    /// <para>
    /// $cred = Get-Credential, then pass $cred object to the -Credential parameter.
    /// </para>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private const string SetupArguments = "/Action=RunDiscovery /q";
    private const string ReportName = "SqlDiscoveryReport.xml";

    // The pin's Where-Object filter on the setup.exe candidates (-match: case-insensitive).
    private static readonly Regex[] SetupPaths =
    {
        new Regex(@"Setup Bootstrap\\SQL", RegexOptions.IgnoreCase),
        new Regex(@"Bootstrap\\Release\\Setup.exe", RegexOptions.IgnoreCase),
        new Regex(@"Bootstrap\\Setup.exe", RegexOptions.IgnoreCase)
    };

    protected override void ProcessRecord()
    {
        if (ComputerName is null)
        {
            return;
        }

        foreach (DbaInstanceParameter computer in ComputerName)
        {
            try
            {
                // PS: $text = Invoke-Command2 -ComputerName $Computer -ScriptBlock $scriptBlock -Credential $Credential -Raw
                // Invoke-Command2 runs the script block in this process for the local computer, and in a remote
                // session otherwise; a null element is not local, so its session fails to open.
                object? text = computer is not null && computer.IsLocalHost ? DiscoverLocal() : DiscoverRemote(computer);

                if (!LanguagePrimitives.IsTrue(text))
                {
                    WriteMessage(MessageLevel.Verbose, "No features found on " + computer);
                }

                // PS: $xml = [xml]($text) - the engine's own cast: a line array joins through $OFS before parsing,
                // $null casts to null, and text that is not XML throws into the catch below.
                XmlDocument? xml = LanguagePrimitives.ConvertTo<XmlDocument>(text);

                // PS: foreach ($result in $xml.ArrayOfDiscoveryInformation.DiscoveryInformation)
                object? infoItems = GetMemberValue(GetMemberValue(xml, "ArrayOfDiscoveryInformation"), "DiscoveryInformation");
                foreach (object item in EnumerateValue(infoItems))
                {
                    PSObject output = new();
                    output.Properties.Add(new PSNoteProperty("ComputerName", computer));
                    foreach (string name in new[] { "Product", "Instance", "InstanceID", "Feature", "Language", "Edition", "Version", "Clustered", "Configured" })
                    {
                        output.Properties.Add(new PSNoteProperty(name, GetMemberValue(item, name)));
                    }

                    WriteObject(output);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException rex)
            {
                // $_ in the pin's catch holds the exception itself; a RuntimeException that carries no record of its
                // own (a session that fails to open) builds one around a ParentContainsErrorRecordException, which
                // the engine replaces with the exception as it hands the record to a catch.
                ErrorRecord record = rex.ErrorRecord;
                if (record.Exception is ParentContainsErrorRecordException)
                {
                    record = new ErrorRecord(record, rex);
                }

                StopFunction("Failure", errorRecord: record, continueLoop: true);
            }
            catch (Exception ex)
            {
                StopFunction("Failure", exception: ex, continueLoop: true);
            }
        }
    }

    // ---------- the local computer: the script block's work in this process ----------

    private object? DiscoverLocal()
    {
        // PS: Get-ChildItem -Recurse -Include setup.exe -Path "$(...GetFolderPath("ProgramFiles"))\Microsoft SQL Server"
        //     -ErrorAction SilentlyContinue | Where-Object {...} | Sort-Object FullName -Descending | Select-Object -First 1
        string root = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles) + "\\Microsoft SQL Server";
        string? setup = NewestSetup(FindFiles(root, "setup.exe", null).Select(file => file.FullName));
        if (setup is null)
        {
            return null;
        }

        // PS: $null = Start-Process -FilePath $setup.FullName -ArgumentList "/Action=RunDiscovery /q" -Wait
        RunAndWaitForTree(setup);

        // PS: $parent = Split-Path (Split-Path $setup.Fullname)
        //     $xmlfile = Get-ChildItem -Recurse -Include SqlDiscoveryReport.xml -Path $parent | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        string parent = ParentPath(ParentPath(setup));
        List<ErrorRecord> errors = new();
        FileInfo? report = FindFiles(parent, ReportName, errors)
            .OrderByDescending(file => file.LastWriteTime)
            .FirstOrDefault();
        foreach (ErrorRecord error in errors)
        {
            WriteError(error);
        }

        // PS: if ($xmlfile) { Get-Content -Path $xmlfile }
        return report is null ? null : ReadLines(report.FullName);
    }

    // Get-ChildItem -Recurse -Include <name> -Path <root>: matching files in the folder and every folder below it,
    // hidden items left out as Get-ChildItem leaves them out without -Force. A folder that cannot be read is a
    // non-terminating error, or nothing at all under -ErrorAction SilentlyContinue (errors is null).
    private List<FileInfo> FindFiles(string root, string name, List<ErrorRecord>? errors)
    {
        List<FileInfo> found = new();
        DirectoryInfo start = new(root);
        if (!start.Exists)
        {
            string missing = string.Format(CultureInfo.InvariantCulture, "Cannot find path '{0}' because it does not exist.", root);
            errors?.Add(new ErrorRecord(new ItemNotFoundException(missing), "PathNotFound", ErrorCategory.ObjectNotFound, root));
            return found;
        }

        Stack<DirectoryInfo> pending = new();
        pending.Push(start);
        while (pending.Count > 0)
        {
            if (CancellationToken.IsCancellationRequested)
            {
                throw new PipelineStoppedException();
            }

            DirectoryInfo folder = pending.Pop();
            FileSystemInfo[] entries;
            try
            {
                entries = folder.GetFileSystemInfos();
            }
            catch (UnauthorizedAccessException e)
            {
                errors?.Add(new ErrorRecord(e, "DirUnauthorizedAccessError", ErrorCategory.PermissionDenied, folder.FullName));
                continue;
            }
            catch (IOException e)
            {
                errors?.Add(new ErrorRecord(e, "DirIOError", ErrorCategory.ReadError, folder.FullName));
                continue;
            }

            for (int index = entries.Length - 1; index >= 0; index--)
            {
                FileSystemInfo entry = entries[index];
                if ((entry.Attributes & FileAttributes.Hidden) != 0)
                {
                    continue;
                }

                if (entry is DirectoryInfo child)
                {
                    if ((child.Attributes & FileAttributes.ReparsePoint) == 0)
                    {
                        pending.Push(child);
                    }
                }
                else if (entry is FileInfo file && string.Equals(file.Name, name, StringComparison.OrdinalIgnoreCase))
                {
                    found.Add(file);
                }
            }
        }

        return found;
    }

    // Start-Process -Wait: the process starts as Start-Process starts it (shell execute, in the current file system
    // location) and the wait lasts until the process and every process it started have exited.
    private void RunAndWaitForTree(string setup)
    {
        ProcessStartInfo start = new(setup, SetupArguments)
        {
            UseShellExecute = true,
            WorkingDirectory = SessionState.Path.CurrentFileSystemLocation.ProviderPath
        };

        Process? process;
        try
        {
            process = Process.Start(start);
        }
        catch (Win32Exception e)
        {
            // Start-Process reports a failed start this way, and the pin's try catches it.
            throw new InvalidOperationException("This command cannot be run due to the error: " + e.Message + ".", e);
        }

        if (process is null)
        {
            return;
        }

        using (process)
        {
            IntPtr job = CreateJobObject(IntPtr.Zero, null);
            try
            {
                bool tracked = job != IntPtr.Zero && !process.HasExited && AssignProcessToJobObject(job, process.Handle);
                while (!process.WaitForExit(200))
                {
                    if (CancellationToken.IsCancellationRequested)
                    {
                        throw new PipelineStoppedException();
                    }
                }

                while (tracked && ActiveProcesses(job) > 0)
                {
                    if (CancellationToken.WaitHandle.WaitOne(200))
                    {
                        throw new PipelineStoppedException();
                    }
                }
            }
            finally
            {
                if (job != IntPtr.Zero)
                {
                    CloseHandle(job);
                }
            }
        }
    }

    // JOBOBJECT_BASIC_ACCOUNTING_INFORMATION: four LARGE_INTEGER times, then the DWORDs TotalPageFaultCount,
    // TotalProcesses, ActiveProcesses and TotalTerminatedProcesses.
    private static int ActiveProcesses(IntPtr job)
    {
        const int size = 48;
        const int activeProcessesOffset = 40;
        IntPtr buffer = Marshal.AllocHGlobal(size);
        try
        {
            if (!QueryInformationJobObject(job, JobObjectBasicAccountingInformationClass, buffer, size, IntPtr.Zero))
            {
                return 0;
            }

            return Marshal.ReadInt32(buffer, activeProcessesOffset);
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    // Get-Content -Path <file>: one string per line, read as each edition's Get-Content reads a file without
    // -Encoding (a byte order mark wins; otherwise the system code page on Windows PowerShell, UTF-8 on PowerShell 7).
    private static object? ReadLines(string path)
    {
        List<object> lines = new();
        using (StreamReader reader = new(path, Encoding.Default, true))
        {
            string? line;
            while ((line = reader.ReadLine()) is not null)
            {
                lines.Add(line);
            }
        }

        return Collapse(lines);
    }

    // ---------- a remote computer: the same steps in a remote session ----------

    // Invoke-Command2 opens a session (New-PSSession -ErrorAction Stop, so a failed open lands in the pin's catch) and
    // runs the script block there. The session runs each of the script block's commands with the caller's values as
    // parameter values; the filtering and sorting happen here on the returned paths, as the script block does them.
    private object? DiscoverRemote(DbaInstanceParameter? computer)
    {
        if (computer is null)
        {
            // PS: New-PSSession -ComputerName $null - the binder refuses the null name before any connection.
            throw new ParameterBindingException("Cannot validate argument on parameter 'ComputerName'. The argument is null or empty. Provide an argument that is not null or empty, and then try the command again.");
        }

        string target = computer.ComputerName;
        bool useSsl = LanguagePrimitives.IsTrue(GetConfigValue("psremoting.pssession.usessl"));
        bool hasPort = LanguagePrimitives.TryConvertTo<int>(GetConfigValue("psremoting.pssession.port"), out int configuredPort) && configuredPort > 0;
        if (hasPort)
        {
            WriteAttributedMessage("Invoke-Command2", MessageLevel.Verbose, "Using Port: " + configuredPort.ToString(CultureInfo.InvariantCulture));
        }

        int port = hasPort ? configuredPort : (useSsl ? 5986 : 5985);
        PSCredential? credential = Credential;
        using System.Management.Automation.Runspaces.Runspace session = RunspaceFactory.CreateRunspace(new WSManConnectionInfo(useSsl, target, port, "/wsman", "http://schemas.microsoft.com/powershell/Microsoft.PowerShell", credential)
        {
            IdleTimeout = 600000,
            IncludePortInSPN = LanguagePrimitives.IsTrue(GetConfigValue("psremoting.pssessionoption.includeportinspn")),
            SkipCACheck = LanguagePrimitives.IsTrue(GetConfigValue("psremoting.pssessionoption.skipcacheck")),
            SkipCNCheck = LanguagePrimitives.IsTrue(GetConfigValue("psremoting.pssessionoption.skipcncheck")),
            SkipRevocationCheck = LanguagePrimitives.IsTrue(GetConfigValue("psremoting.pssessionoption.skiprevocationcheck"))
        });
        session.Open();

        // [System.Environment]::GetFolderPath("ProgramFiles") of the remote session's process.
        const string programFilesPath = "Env:ProgramFiles";
        string? programFiles = null;
        using (PowerShell read = PowerShell.Create().AddCommand("Get-Item").AddParameter("LiteralPath", programFilesPath))
        {
            read.Runspace = session;
            foreach (PSObject item in RunRemote(read))
            {
                programFiles = item.Properties["Value"]?.Value as string;
            }
        }

        string root = programFiles + "\\Microsoft SQL Server";
        List<string> candidates = new();
        using (PowerShell find = PowerShell.Create().AddCommand("Get-ChildItem").AddParameter("Recurse").AddParameter("Include", "setup.exe").AddParameter("Path", root).AddParameter("ErrorAction", ActionPreference.SilentlyContinue))
        {
            find.Runspace = session;
            foreach (PSObject item in RunRemote(find))
            {
                if (item.Properties["FullName"]?.Value is string fullName)
                {
                    candidates.Add(fullName);
                }
            }
        }

        string? setup = NewestSetup(candidates);
        if (setup is null)
        {
            return null;
        }

        using (PowerShell run = PowerShell.Create().AddCommand("Start-Process").AddParameter("FilePath", setup).AddParameter("ArgumentList", SetupArguments).AddParameter("Wait"))
        {
            run.Runspace = session;
            RunRemote(run);
        }

        string parent = ParentPath(ParentPath(setup));
        List<PSObject> reports = new();
        using (PowerShell report = PowerShell.Create().AddCommand("Get-ChildItem").AddParameter("Recurse").AddParameter("Include", ReportName).AddParameter("Path", parent))
        {
            report.Runspace = session;
            reports.AddRange(RunRemote(report));
        }

        // PS: Sort-Object LastWriteTime -Descending | Select-Object -First 1
        PSObject? newest = reports
            .OrderByDescending(item => item.Properties["LastWriteTime"]?.Value is DateTime written ? written : DateTime.MinValue)
            .FirstOrDefault();
        if (newest?.Properties["FullName"]?.Value is not string reportPath)
        {
            return null;
        }

        List<object> lines = new();
        using (PowerShell content = PowerShell.Create().AddCommand("Get-Content").AddParameter("Path", reportPath))
        {
            content.Runspace = session;
            foreach (PSObject line in RunRemote(content))
            {
                lines.Add(line);
            }
        }

        return Collapse(lines);
    }

    // One statement of the remote script block. Its errors reach the caller as Invoke-Command forwards them; an error
    // that ends the statement ends only that statement, as in the script block. A lost session ends the whole call.
    private List<PSObject> RunRemote(PowerShell statement)
    {
        List<PSObject> output = new();
        IAsyncResult running = statement.BeginInvoke();
        while (!running.AsyncWaitHandle.WaitOne(200))
        {
            if (CancellationToken.IsCancellationRequested)
            {
                statement.Stop();
            }
        }

        ErrorRecord? ended = null;
        try
        {
            output.AddRange(statement.EndInvoke(running));
        }
        catch (RuntimeException e) when (e is not PipelineStoppedException && e is not PSRemotingTransportException)
        {
            ended = e.ErrorRecord.Exception is ParentContainsErrorRecordException ? new ErrorRecord(e.ErrorRecord, e) : e.ErrorRecord;
        }

        if (CancellationToken.IsCancellationRequested)
        {
            throw new PipelineStoppedException();
        }

        foreach (ErrorRecord error in statement.Streams.Error)
        {
            WriteError(error);
        }

        if (ended is not null && statement.Streams.Error.Count == 0)
        {
            WriteError(ended);
        }

        return output;
    }

    // ---------- shared by both paths ----------

    // Where-Object on the three path patterns, then Sort-Object FullName -Descending | Select-Object -First 1
    // (Sort-Object compares strings in the current culture, ignoring case).
    private static string? NewestSetup(IEnumerable<string> candidates)
    {
        return candidates
            .Where(path => SetupPaths.Any(pattern => pattern.IsMatch(path)))
            .OrderByDescending(path => path, StringComparer.Create(CultureInfo.CurrentCulture, true))
            .FirstOrDefault();
    }

    // Split-Path <path>: the path without its last element.
    private static string ParentPath(string path)
    {
        string trimmed = path.TrimEnd('\\', '/');
        int last = trimmed.LastIndexOfAny(new[] { '\\', '/' });
        if (last < 0)
        {
            return string.Empty;
        }

        string parent = trimmed.Substring(0, last);
        return parent.EndsWith(":", StringComparison.Ordinal) ? parent + "\\" : parent;
    }

    // PS pipeline assignment: nothing is $null, one item is the item, more are an array.
    private static object? Collapse(List<object> items)
    {
        if (items.Count == 0)
        {
            return null;
        }

        return items.Count == 1 ? items[0] : items.ToArray();
    }

    // PS foreach over a value: $null iterates zero times, an array element by element, anything else once.
    private static IEnumerable<object> EnumerateValue(object? value)
    {
        if (value is null)
        {
            yield break;
        }

        if (value is object[] many)
        {
            foreach (object item in many)
            {
                if (item is not null)
                {
                    yield return item;
                }
            }

            yield break;
        }

        yield return value;
    }

    // PS member access through the engine's adapters ($xml.a.b): XML child elements read back as the XML adapter
    // gives them, and a read on an array collects each element's value (member enumeration).
    private static object? GetMemberValue(object? source, string name)
    {
        if (source is null)
        {
            return null;
        }

        if (source is object[] many)
        {
            List<object> values = new();
            foreach (object item in many)
            {
                if (item is not null && PSObject.AsPSObject(item).Properties[name]?.Value is object value)
                {
                    values.Add(value);
                }
            }

            return Collapse(values);
        }

        return PSObject.AsPSObject(source).Properties[name]?.Value;
    }

    private static object? GetConfigValue(string key)
    {
        return ConfigurationHost.Configurations.TryGetValue(key, out Config? config) && config is not null ? config.Value : null;
    }

    // PS: [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME
    private static DbaInstanceParameter[]? DefaultComputerName()
    {
        string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(machine))
        {
            return null;
        }

        return new[] { new DbaInstanceParameter(machine) };
    }

    private const int JobObjectBasicAccountingInformationClass = 1;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateJobObject(IntPtr jobAttributes, string? name);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool QueryInformationJobObject(IntPtr job, int informationClass, IntPtr information, int length, IntPtr returnLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);
}
