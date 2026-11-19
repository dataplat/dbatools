#nullable enable

using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Data;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Reads detached SQL Server database files to extract metadata and file structure without attaching them.
/// </summary>
/// <para>
/// Analyzes detached MDF files to retrieve essential database metadata including name, SQL Server version, collation, and complete file structure. This lets you examine database files sitting in storage or archives without the risk of attaching them to a live instance.
/// </para>
/// <para>
/// Perfect for migration planning when you need to verify compatibility before moving databases between SQL Server versions. Also invaluable for troubleshooting scenarios where you have detached database files and need to understand their structure or requirements before reattachment.
/// </para>
/// <para>
/// The function reads the MDF file header using SQL Server's built-in methods, so it requires an online SQL Server instance to interpret the binary data. All file paths must be accessible to the specified SQL Server service account.
/// </para>
/// <para>
/// Returns comprehensive details including the original database name, exact SQL Server version (mapped from internal version numbers), collation settings, and complete lists of associated data and log files as they existed when detached.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbDetachedFileInfo -SqlInstance sql2016 -Path M:\Archive\mydb.mdf
/// </code>
/// <para>
/// Returns information about the detached database file M:\Archive\mydb.mdf using the SQL Server instance sql2016. The M drive is relative to the SQL Server instance.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Database, Detach
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
/// <seealso href="https://dbatools.io/Get-DbaDbDetachedFileInfo" />
[Cmdlet(VerbsCommon.Get, "DbaDbDetachedFileInfo")]
public sealed class GetDbaDbDetachedFileInfoCommand : DbaBaseCmdlet
{
    /// <para>
    /// Source SQL Server. This instance must be online and is required to parse the information contained with in the detached database file.
    /// </para>
    /// <para>
    /// This function will not attach the database file, it will only use SQL Server to read its contents.
    /// </para>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter SqlInstance { get; set; } = null!;

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
    /// Specifies the full file path to one or more detached MDF database files to analyze. The SQL Server service account must have read access to these file locations.
    /// Use this when you need to examine database files in archives, backups, or migration staging areas before deciding whether to attach them.
    /// Supports multiple file paths and accepts wildcards, but each MDF file must be accessible from the specified SQL Server instance.
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 2)]
    [Alias("Mdf", "FilePath", "FullName")]
    [PsStringArrayCast]
    public string[] Path { get; set; } = null!;

    // Source: https://sqlserverbuilds.blogspot.com/2014/01/sql-server-internal-database-versions.html
    private static readonly Dictionary<string, string> VersionNames = new()
    {
        ["998"] = "SQL Server 2025",
        ["957"] = "SQL Server 2022",
        ["904"] = "SQL Server 2019",
        ["869"] = "SQL Server 2017",
        ["868"] = "SQL Server 2017",
        ["852"] = "SQL Server 2016",
        ["782"] = "SQL Server 2014",
        ["706"] = "SQL Server 2012",
        ["661"] = "SQL Server 2008 R2",
        ["660"] = "SQL Server 2008 R2",
        ["655"] = "SQL Server 2008 SP2+",
        ["612"] = "SQL Server 2005",
        ["611"] = "SQL Server 2005",
        ["539"] = "SQL Server 2000",
        ["515"] = "SQL Server 7.0",
        ["408"] = "SQL Server 6.5"
    };

    private static readonly char[] Separators = { '\\', '/' };
    private static readonly char[] Wildcards = { '*', '?' };

    private Server? _server;

    /// <summary>Connects once; every record of -Path uses this connection.</summary>
    protected override void BeginProcessing()
    {
        try
        {
            SmoConnectionRequest request = new()
            {
                Instance = SqlInstance,
                SqlCredential = SqlCredential,
                AzureUnsupported = true,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
                MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
            };
            _server = ConnectionService.GetServer(request);
            SetActiveConnection(_server.ConnectionContext);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record = new(failure, "dbatools_Get-DbaDbDetachedFileInfo", ErrorCategory.ConnectionError, SqlInstance);
            StopFunction("Failure", target: SqlInstance, errorRecord: record, category: ErrorCategory.ConnectionError);
        }
    }

    /// <summary>Reads each path of the record.</summary>
    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;
        foreach (string filepath in Path)
        {
            foreach (string file in ExpandPath(_server!, filepath))
                ReadFile(_server!, file);
        }
    }

    /// <summary>
    /// The files one -Path names. The help accepts wildcards, so a star or a question mark in the file name lists its
    /// folder, and each match reads as its own path. No match, a wildcard in the folder or a folder that cannot be
    /// listed keeps the text as given, and the message of a file that cannot be accessed applies.
    /// </summary>
    private List<string> ExpandPath(Server server, string filepath)
    {
        int separator = filepath.LastIndexOfAny(Separators);
        string folder = filepath.Substring(0, separator + 1);
        string leaf = filepath.Substring(separator + 1);
        List<string> files = new();
        if (separator >= 0 && leaf.IndexOfAny(Wildcards) >= 0 && folder.IndexOfAny(Wildcards) < 0)
        {
            WildcardPattern pattern = new(leaf.Replace("`", "``").Replace("[", "`[").Replace("]", "`]"), WildcardOptions.IgnoreCase);
            try
            {
                DataSet listing = server.ConnectionContext.ExecuteWithResults(String.Format("EXEC master.sys.xp_dirtree {0}, 1, 1", SqlText(folder)));
                foreach (DataRow row in listing.Tables[0].Rows)
                {
                    // The columns are the name, the depth and whether it is a file, as the pinned Find-DbaOrphanedFile reads them.
                    string name = ToText(row[0]);
                    if (IsSet(row[2]) && pattern.IsMatch(name))
                        files.Add(String.Concat(folder, name));
                }
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                WriteMessage(MessageLevel.Verbose, String.Format("Could not list {0}: {1}", folder, failure.Message));
            }
        }
        if (files.Count == 0)
            files.Add(filepath);
        return files;
    }

    private void ReadFile(Server server, string filepath)
    {
        if (!PathExists(server, filepath))
        {
            StopFunction(String.Format("{0} cannot access the file {1}. Does the file exist and does the service account ({2}) have access to the path?", server.Name, filepath, ServiceAccount(server)), continueLoop: true);
            return;
        }

        object? name;
        object? exactVersion;
        object? collationId;
        try
        {
            DataTable header = server.DetachedDatabaseInfo(filepath);
            name = HeaderValue(header, "Database name");
            exactVersion = HeaderValue(header, "Database version");
            collationId = HeaderValue(header, "Collation");
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            StopFunction(String.Format("{0} cannot read the file {1}. Is the database detached?", server.Name, filepath), continueLoop: true);
            return;
        }

        object? collation = ResolveCollation(server, collationId);

        object dataFiles;
        object logFiles;
        try
        {
            dataFiles = ToFileList(server.EnumDetachedDatabaseFiles(filepath));
            logFiles = ToFileList(server.EnumDetachedLogFiles(filepath));
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            StopFunction(String.Format("{0} unable to enumerate database or log structure information for {1}", server.Name, filepath), continueLoop: true);
            return;
        }

        PSObject output = new();
        // The pin reads these three from -SqlInstance, not from the server, so OutputHelper would change their values.
        output.Properties.Add(new PSNoteProperty("ComputerName", SqlInstance.ComputerName)); // style-ok: cs-output-props the pin's values come from the parameter
        output.Properties.Add(new PSNoteProperty("InstanceName", SqlInstance.InstanceName)); // style-ok: cs-output-props the pin's values come from the parameter
        output.Properties.Add(new PSNoteProperty("SqlInstance", SqlInstance.InputObject)); // style-ok: cs-output-props the pin's values come from the parameter
        output.Properties.Add(new PSNoteProperty("Name", name));
        output.Properties.Add(new PSNoteProperty("Version", VersionNames.TryGetValue(ToText(exactVersion), out string? version) ? version : "Unknown"));
        output.Properties.Add(new PSNoteProperty("ExactVersion", exactVersion));
        output.Properties.Add(new PSNoteProperty("Collation", collation));
        output.Properties.Add(new PSNoteProperty("DataFiles", dataFiles));
        output.Properties.Add(new PSNoteProperty("LogFiles", logFiles));
        WriteObject(output);
    }

    /// <summary>
    /// What the pin's Test-DbaPath answers for one path: true for a file or a folder. A failed check is the warning
    /// Test-DbaPath writes, and reads as not found.
    /// </summary>
    private bool PathExists(Server server, string filepath)
    {
        try
        {
            DataSet result = server.ConnectionContext.ExecuteWithResults(String.Format("EXEC master.dbo.xp_fileexist {0}", SqlText(filepath)));
            DataRow row = result.Tables[0].Rows[0];
            return IsSet(row[0]) || IsSet(row[1]);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            string error = String.Format("Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", failure.Message);
            WriteAttributedMessage("Test-DbaPath", MessageLevel.Warning, String.Format("xp_fileexist execution failed for path(s) on {0}, so existence could not be determined and the path(s) are reported as not found. The SQL Server service account may not have access to the specified path(s). Error: {1}", new DbaInstanceParameter(server), error));
            return false;
        }
    }

    // Only the failure message needs it; an unreadable value leaves the parentheses empty there, as the pin's null does.
    private static string ServiceAccount(Server server)
    {
        try
        {
            return server.ServiceAccount ?? String.Empty;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return String.Empty;
        }
    }

    /// <summary>
    /// The collation name, or the id from the file when the name cannot be resolved. The query runs on the connection
    /// of the caller, never through master, which would leave that connection there (#10555). The id comes out of a
    /// file, so only a number reaches the statement.
    /// </summary>
    private static object? ResolveCollation(Server server, object? collationId)
    {
        string id = ToText(collationId);
        if (!Int64.TryParse(id, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out long number))
            return collationId;
        try
        {
            string sql = String.Format(CultureInfo.InvariantCulture, "SELECT name FROM fn_helpcollations() WHERE COLLATIONPROPERTY(name, N'COLLATIONID')  = {0}", number);
            string name = ToText(server.ConnectionContext.ExecuteWithResults(sql).Tables[0].Rows[0][0]);
            return name.Length > 0 ? name : collationId;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return collationId;
        }
    }

    private static object? HeaderValue(DataTable header, string property)
    {
        DataRow? row = header.Rows.Cast<DataRow>().FirstOrDefault(entry => String.Equals(ToText(entry["Property"]), property, StringComparison.OrdinalIgnoreCase));
        return row?["Value"];
    }

    // The pin's += on a StringCollection: an array once a file is added, the empty collection without one.
    private static object ToFileList(StringCollection files)
    {
        if (files.Count == 0)
            return new StringCollection();
        return files.Cast<object>().ToArray();
    }

    private static bool IsSet(object value) => value is not DBNull && Convert.ToInt32(value, CultureInfo.InvariantCulture) != 0;

    private static string ToText(object? value) => LanguagePrimitives.ConvertTo<string>(value) ?? String.Empty;

    /// <summary>Caller text as a T-SQL string literal.</summary>
    private static string SqlText(string text) => String.Concat("N'", text.Replace("'", "''"), "'");
}
