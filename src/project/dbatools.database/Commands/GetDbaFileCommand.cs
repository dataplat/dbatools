#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaFile.ps1 at refs/pins/dbatools-2026-10-22: the files and directories xp_dirtree lists under each path of each instance,
// the instance's default data directory when no -Path is given. Expected values as the pin measured on both editions: evidence/pin-file-20261104.txt.
/// <summary>Enumerates files and directories on remote SQL Server instances using xp_dirtree</summary>
/// <para>
/// Searches directories on SQL Server machines remotely without requiring direct file system access or RDP connections. Uses the xp_dirtree extended stored procedure to return file listings that can be filtered by extension and searched recursively to specified depths. Defaults to the instance's data directory but accepts additional paths for comprehensive file system exploration.
/// </para>
/// <para>
/// Common use cases include locating orphaned database files, finding backup files for restores, auditing disk usage, and preparing for file migrations.
/// </para>
/// <para>
/// You can filter by extension using the -FileType parameter. By default, the default data directory will be returned. You can provide and additional paths to search using the -Path parameter.
/// </para>
/// <para>
/// Thanks to serg-52 for the query:  https://www.sqlservercentral.com/Forums/Topic1642213-391-1.aspx
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaFile -SqlInstance sqlserver2014a -Path E:\Dir1
/// </code>
/// <para>
/// Logs into the SQL Server "sqlserver2014a" using Windows credentials and searches E:\Dir for all files
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaFile -SqlInstance sqlserver2014a -SqlCredential $cred -Path 'E:\sql files'
/// </code>
/// <para>
/// Logs into the SQL Server "sqlserver2014a" using alternative credentials and returns all files in 'E:\sql files'
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $all = Get-DbaDefaultPath -SqlInstance sql2014
/// PS C:\&gt; Get-DbaFile -SqlInstance sql2014 -Path $all.Data, $all.Log, $all.Backup -Depth 3
/// </code>
/// <para>
/// Returns the files in the default data, log and backup directories on sql2014, 3 directories deep (recursively).
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaFile -SqlInstance sql2014 -Path 'E:\Dir1', 'E:\Dir2'
/// </code>
/// <para>
/// Returns the files in "E:\Dir1" and "E:Dir2" on sql2014
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaFile -SqlInstance sql2014, sql2016 -Path 'E:\Dir1' -FileType fsf, mld
/// </code>
/// <para>
/// Finds files in E:\Dir1 ending with ".fsf" and ".mld" for both the servers sql2014 and sql2016.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Storage, File, Path
/// Author: Brandon Abshire, netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaFile" />
[Cmdlet(VerbsCommon.Get, "DbaFile")]
public sealed class GetDbaFileCommand : DbaInstanceCmdlet
{
    // PS: the query parts of the nested Get-SQLDirTreeQuery, with the text of the pin. Each path goes in as the string literal between
    // QueryPathStart and QueryPathBlock, where the pin's block read 'dirname'.
    private const string QueryHead = @"DECLARE @myPath NVARCHAR(4000);
                    DECLARE @depth SMALLINT = {0};

                    IF OBJECT_ID('tempdb..#DirectoryTree') IS NOT NULL
                    DROP TABLE #DirectoryTree;

                    CREATE TABLE #DirectoryTree (
                       id INT IDENTITY(1,1)
                       ,subdirectory NVARCHAR(512)
                       ,depth INT
                       ,isfile BIT
                       , ParentDirectory INT
                       ,flag TINYINT DEFAULT(0));";

    private const string QueryPathStart = "SET @myPath = ";

    private const string QueryPathBlock = @"
                    -- top level directory
                    INSERT #DirectoryTree (subdirectory,depth,isfile)
                       VALUES (@myPath,0,0);
                    -- all the rest under top level
                    INSERT #DirectoryTree (subdirectory,depth,isfile)
                       EXEC master.sys.xp_dirtree @myPath,@depth,1;


                    UPDATE #DirectoryTree
                       SET ParentDirectory = (
                          SELECT MAX(id) FROM #DirectoryTree
                          WHERE depth = d.depth - 1 AND id < d.id   )
                    FROM #DirectoryTree d
                    WHERE ParentDirectory IS NULL;";

    private const string QueryFiles = @"-- SEE all with full paths
                    WITH dirs AS (
                        SELECT
                           id,subdirectory,depth,isfile,ParentDirectory,flag
                           , CAST (NULL AS NVARCHAR(MAX)) AS container
                           , CAST([subdirectory] AS NVARCHAR(MAX)) AS dpath
                           FROM #DirectoryTree
                           WHERE ParentDirectory IS NULL
                        UNION ALL
                        SELECT
                           d.id,d.subdirectory,d.depth,d.isfile,d.ParentDirectory,d.flag
                           , dpath AS container
                           , dpath +'\'+d.[subdirectory]
                        FROM #DirectoryTree AS d
                        INNER JOIN dirs ON  d.ParentDirectory = dirs.id
                        WHERE dpath NOT LIKE '%RECYCLE.BIN%'
                    )
                    SELECT subdirectory AS filename, container AS filepath, isfile, dpath AS fullpath FROM dirs
                    WHERE container IS NOT NULL
                    -- Dir style ordering
                    ORDER BY container, isfile, subdirectory";

    private static readonly string[] HiddenProperties = { "ComputerName", "InstanceName", "RemoteFilename" };

    // PS: $FileTypeComparison, set once in the begin block.
    private string[]? _fileTypeComparison;

    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>
    /// Allows you to login to servers using alternative credentials
    /// </para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies additional directory paths to search beyond the instance's default data directory. Accepts multiple paths as an array.
    /// Use this when you need to scan specific locations for orphaned files, backup locations, or custom database file directories.
    /// Defaults to the instance's data directory if not specified.
    /// </para>
    [Parameter(Position = 2)]
    public string[]? Path { get; set; }

    /// <para>
    /// Filters results to only show files with specific extensions. Pass extensions without the dot (e.g., 'mdf', 'ldf', 'bak').
    /// Use this to find specific database files like data files (mdf, ndf), log files (ldf), or backup files (bak, trn).
    /// Accepts multiple extensions to search for different file types simultaneously.
    /// </para>
    [Parameter(Position = 3)]
    public string[]? FileType { get; set; }

    /// <para>
    /// Controls how many subdirectory levels to search recursively. Default is 1 (current directory only).
    /// Increase this value when searching deep folder structures for scattered database files or backup archives.
    /// Higher values take more time but ensure comprehensive file discovery across complex directory trees.
    /// </para>
    [Parameter(Position = 4)]
    public int Depth { get; set; } = 1;

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // PS: if ($FileType) { $FileTypeComparison = $FileType | ForEach-Object { $_.ToLowerInvariant() } | Where-Object { $_ } | Sort-Object | Get-Unique }
        // The binder turns a null element of [string[]] into an empty string, which the Where-Object drops; none left means no filter.
        if (FileType is null)
            return;

        List<string> lowered = new();
        foreach (string? type in FileType)
        {
            if (!String.IsNullOrEmpty(type))
                lowered.Add(type!.ToLowerInvariant());
        }
        lowered.Sort(StringComparer.CurrentCultureIgnoreCase);

        List<string> unique = new();
        foreach (string type in lowered)
        {
            if (unique.Count == 0 || !String.Equals(unique[unique.Count - 1], type, StringComparison.Ordinal))
                unique.Add(type);
        }
        _fileTypeComparison = unique.Count > 0 ? unique.ToArray() : null;
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Correction azure-refusal: Azure SQL Database has no extended stored procedures and no file system access, so it is refused as
            // Connect-DbaInstance -AzureUnsupported does, where the pin connected and xp_dirtree faulted.
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
                continue;

            // PS: if (-not (Test-Bound -ParameterName Path)) { $Path = (Get-DbaDefaultPath -SqlInstance $server).Data }
            string?[]? paths = TestBound(nameof(Path)) ? Path : DefaultDataPath(server);

            // PS: if (Test-HostOSLinux -SqlInstance $server) { $separator = "/" } else { $separator = "\" }
            string separator = HostIsLinux(server) ? "/" : "\\";

            WriteMessage(MessageLevel.Verbose, "Adding paths");
            string sql = DirTreeQuery(paths);
            WriteMessage(MessageLevel.Debug, sql);

            // PS: $datatable = $server.ConnectionContext.ExecuteWithResults($sql).Tables.Rows, outside any try. Correction stale-rows: a faulted query
            // gives no rows, where the pin's $datatable kept the rows of the call before it and wrote them again under this instance's name.
            List<DataRow>? rows = RunQuery(server, sql);

            // Correction file-count: the count of the rows, where the pin's $datatable.Rows.Count read 0 for one row.
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "{0} files found.", rows?.Count ?? 0));
            if (rows is null)
                continue;

            foreach (DataRow row in rows)
            {
                string fullPath = Convert.ToString(row["fullpath"], CultureInfo.InvariantCulture)!;
                if (_fileTypeComparison is null)
                {
                    // PS: $fullpath.Replace("\", $separator).Replace("\\", "\").Replace("//", "/"). Correction unc-path: the leading \\ of a share is kept,
                    // as the -FileType branch keeps it, where the pin turned it into one \.
                    WriteFile(server, SharePath(fullPath, separator));
                    continue;
                }

                string fileName = Convert.ToString(row["filename"], CultureInfo.InvariantCulture)!.ToLowerInvariant();
                foreach (string type in _fileTypeComparison)
                {
                    // PS: $row.filename.ToLowerInvariant().EndsWith(".$type"), String.EndsWith(String) with the current culture.
                    if (fileName.EndsWith("." + type, StringComparison.CurrentCulture))
                        WriteFile(server, SharePath(fullPath, separator));
                }
            }
        }
    }

    /// <summary>
    /// PS: the -FileType branch's path: separators adapted, doubled backslashes collapsed, but a leading \\ of a share kept. The branch without
    /// -FileType takes it too (correction unc-path).
    /// </summary>
    private static string SharePath(string fullPath, string separator)
    {
        string path = fullPath.Replace("\\", separator);
        // PS: $is_smb_share_path = $fullpath.SubString(0, 2) -eq "\\"
        bool isShare = path.Substring(0, 2) == "\\\\";
        path = path.Replace("\\\\", "\\");
        if (isShare && path.StartsWith("\\", StringComparison.Ordinal))
        {
            // PS: $fullpath -replace "^\\", "\\"
            path = "\\" + path;
        }
        return path.Replace("//", "/");
    }

    /// <summary>
    /// PS: [PSCustomObject]@{ ComputerName; InstanceName; SqlInstance; Filename; RemoteFilename } | Select-DefaultView -ExcludeProperty ComputerName, InstanceName, RemoteFilename
    /// </summary>
    private void WriteFile(Server server, string fullPath)
    {
        PSObject result = new();
        OutputHelper.AddInstanceProperties(result, server);
        string computerName = Convert.ToString(result.Properties["ComputerName"].Value, CultureInfo.InvariantCulture) ?? String.Empty;
        result.Properties.Add(new PSNoteProperty("Filename", fullPath));
        result.Properties.Add(new PSNoteProperty("RemoteFilename", JoinAdminUnc(computerName, fullPath)));
        OutputHelper.SetDefaultDisplayPropertySetExcluding(result, HiddenProperties);
        WriteObject(result);
    }

    /// <summary>
    /// PS: Join-AdminUnc -Servername $server.ComputerName -Filepath $fullpath. A path already on a share, and any path when PowerShell runs on Linux
    /// or macOS, comes back as it is; otherwise Join-Path "\\server\" with the path's colon as $, where Join-Path turns / into \ and joins with one \.
    /// </summary>
    private static string JoinAdminUnc(string serverName, string filePath)
    {
        if (filePath.Length == 0 || Environment.OSVersion.Platform != PlatformID.Win32NT || filePath.StartsWith("\\\\", StringComparison.Ordinal))
            return filePath;

        string child = filePath.Replace(':', '$').Replace('/', '\\');
        if (child.StartsWith("\\", StringComparison.Ordinal))
            child = child.Substring(1);
        return "\\\\" + serverName.Split('\\')[0] + "\\" + child;
    }

    /// <summary>
    /// PS: Get-SQLDirTreeQuery $Path: the head, one block for each path that is not an empty string, the file query. The pin joins two or more blocks
    /// with a space, as PowerShell joins an array added to a string.
    /// </summary>
    private string DirTreeQuery(string?[]? paths)
    {
        StringBuilder sql = new();
        sql.Append(String.Format(CultureInfo.InvariantCulture, QueryHead, Depth));
        bool first = true;
        if (paths is not null)
        {
            foreach (string? path in paths)
            {
                if (path is not null && path.Length == 0)
                    continue;
                if (!first)
                    sql.Append(' ');
                first = false;
                // PS: "$([System.Environment]::Newline)$($q2 -Replace 'dirname', $_)". Correction path-literal: the text goes in as one N'' literal with its
                // quotes doubled, where the pin's '' literal let a quote end it and lost characters outside the code page. Correction dollar-path: it goes in
                // as it is, where -Replace read $_, $& and the like in it as substitutions.
                string literal = "N'" + (path ?? String.Empty).Replace("'", "''") + "'";
                sql.Append(Environment.NewLine).Append(QueryPathStart).Append(literal).Append(QueryPathBlock);
            }
        }
        sql.Append(QueryFiles);
        return sql.ToString();
    }

    /// <summary>
    /// PS: (Get-DbaDefaultPath -SqlInstance $server).Data: the configured default data directory, else SERVERPROPERTY('InstanceDefaultDataPath'),
    /// else the directory of model's first file, else the master database's directory, trimmed of spaces and a closing backslash.
    /// </summary>
    private string?[]? DefaultDataPath(Server server)
    {
        string? data;
        try
        {
            data = server.DefaultFile;
            if (String.IsNullOrEmpty(data))
            {
                object? value = server.ConnectionContext.ExecuteScalar("SELECT SERVERPROPERTY('InstanceDefaultDataPath') AS Data");
                data = value is null || value is DBNull ? null : Convert.ToString(value, CultureInfo.InvariantCulture);
            }
            if (String.IsNullOrEmpty(data))
                data = System.IO.Path.GetDirectoryName(server.Databases["model"].FileGroups[0].Files[0].FileName);
            if (String.IsNullOrEmpty(data))
                data = server.Information.MasterDBPath;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ReportFault(new ErrorRecord(failure, failure.GetType().Name, ErrorCategory.NotSpecified, null));
            return null;
        }
        return data is null ? null : new string?[] { data.Trim().TrimEnd('\\') };
    }

    /// <summary>
    /// PS: Test-HostOSLinux: $server.ConnectionContext.ExecuteScalar("SELECT @@VERSION") -match "Linux".
    /// </summary>
    private bool HostIsLinux(Server server)
    {
        object? version;
        try
        {
            version = server.ConnectionContext.ExecuteScalar("SELECT @@VERSION");
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ReportFault(MethodFault("ExecuteScalar", failure));
            return false;
        }
        string? text = version is null || version is DBNull ? null : Convert.ToString(version, CultureInfo.InvariantCulture);
        return text is not null && text.IndexOf("Linux", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    /// <summary>
    /// The rows of every table the batch returns, or null when the call faulted, after its record.
    /// </summary>
    private List<DataRow>? RunQuery(Server server, string sql)
    {
        DataSet result;
        try
        {
            result = server.ConnectionContext.ExecuteWithResults(sql);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ReportFault(MethodFault("ExecuteWithResults", failure));
            return null;
        }

        List<DataRow> rows = new();
        foreach (DataTable table in result.Tables)
        {
            foreach (DataRow row in table.Rows)
                rows.Add(row);
        }
        return rows;
    }

    /// <summary>
    /// The engine's record of a .NET method that threw: 'Exception calling "name" with "1" argument(s): "message"' over the failure, the failure's
    /// type name as its id.
    /// </summary>
    private static ErrorRecord MethodFault(string method, Exception failure)
    {
        MethodInvocationException wrapped = new(String.Format(CultureInfo.InvariantCulture, "Exception calling \"{0}\" with \"1\" argument(s): \"{1}\"", method, failure.Message), failure);
        return new ErrorRecord(wrapped, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    // Accepted differences kept by the keep-going section's point 3: -EnableException stops here with this record, where the pin writes it and goes on;
    // -ErrorAction Stop has the effect PowerShell gives WriteError. $ErrorActionPreference set in the caller's scope acts on this WriteError as for any
    // compiled command, where the pin ignores it: harness-edits.md, "Script-scope preferences and the one-line connect warning", points 1 and 2.
    private void ReportFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }

        // A plain call goes on; under a caller try the record stops the command, as the fault stops the pin's statement.
        StatementFault.Surface(this, fault);
    }
}
