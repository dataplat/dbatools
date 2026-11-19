#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Text;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Csv.Compression;
using Dataplat.Dbatools.Csv.Writer;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports SQL query results or piped objects to CSV files with optional compression.
/// Port of public/Export-DbaCsv.ps1 (its private helper Get-ObjectNameParts absorbed);
/// surface pinned by migration/baselines/Export-DbaCsv.json (auto-assigned positions 0-14,
/// no OutputType attribute).
/// </summary>
[Cmdlet(VerbsData.Export, "DbaCsv", SupportsShouldProcess = true)]
public sealed class ExportDbaCsvCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database to run the query or table export against.</summary>
    [Parameter(Position = 2)]
    public string? Database { get; set; }

    /// <summary>The T-SQL query whose results are exported.</summary>
    [Parameter(Position = 3)]
    public string? Query { get; set; }

    /// <summary>The table to export (one- or two-part name; bracketed names supported).</summary>
    [Parameter(Position = 4)]
    public string? Table { get; set; }

    /// <summary>Objects to export, piped or bound.</summary>
    [Parameter(Position = 5, ValueFromPipeline = true)]
    public object[]? InputObject { get; set; }

    /// <summary>The output CSV file path.</summary>
    [Parameter(Position = 6, Mandatory = true)]
    [PsStringCast]
    public string Path { get; set; } = null!;

    /// <summary>The field delimiter (default comma).</summary>
    [Parameter(Position = 7)]
    public string Delimiter { get; set; } = ",";

    /// <summary>Suppresses the header row.</summary>
    [Parameter]
    public SwitchParameter NoHeader { get; set; }

    /// <summary>The quote character (default double quote).</summary>
    [Parameter(Position = 8)]
    public char Quote { get; set; } = '"';

    /// <summary>How fields are quoted.</summary>
    [Parameter(Position = 9)]
    [PsStringCast]
    [ValidateSet("AsNeeded", "Always", "Never", "NonNumeric")]
    public string QuotingBehavior { get; set; } = "AsNeeded";

    /// <summary>The output text encoding.</summary>
    [Parameter(Position = 10)]
    [PsStringCast]
    [ValidateSet("ASCII", "BigEndianUnicode", "Unicode", "UTF7", "UTF8", "UTF32")]
    public string Encoding { get; set; } = "UTF8";

    /// <summary>The text written for null values.</summary>
    [Parameter(Position = 11)]
    public string NullValue { get; set; } = "";

    /// <summary>The DateTime format string.</summary>
    [Parameter(Position = 12)]
    public string DateTimeFormat { get; set; } = "yyyy-MM-dd HH:mm:ss.fff";

    /// <summary>Converts DateTime values to UTC before formatting.</summary>
    [Parameter]
    public SwitchParameter UseUtc { get; set; }

    /// <summary>The compression applied to the output file.</summary>
    [Parameter(Position = 13)]
    [PsStringCast]
    [ValidateSet("None", "GZip", "Deflate", "Brotli", "ZLib")]
    public string CompressionType { get; set; } = "None";

    /// <summary>The compression level.</summary>
    [Parameter(Position = 14)]
    [PsStringCast]
    [ValidateSet("Fastest", "Optimal", "SmallestSize", "NoCompression")]
    public string CompressionLevel { get; set; } = "Optimal";

    /// <summary>Appends to an existing file instead of overwriting.</summary>
    [Parameter]
    public SwitchParameter Append { get; set; }

    /// <summary>Refuses to overwrite an existing file.</summary>
    [Parameter]
    public SwitchParameter NoClobber { get; set; }

    private CsvWriterOptions _writerOptions = null!;
    private CsvWriter? _writer;
    private long _rowsWritten;
    private bool _rowsWidened;
    private List<object?> _inputObjects = null!;
    private Stopwatch _elapsed = null!;

    protected override void BeginProcessing()
    {
        // PS: parameter-combination validation with exact Stop-Function messages.
        if (TestBound("SqlInstance"))
        {
            if (!TestBound("Query") && !TestBound("Table"))
            {
                StopFunction("When using -SqlInstance, you must specify either -Query or -Table to define what data to export");
                return;
            }
            if (TestBound("Query") && TestBound("Table"))
            {
                StopFunction("You cannot specify both -Query and -Table. Please use one or the other");
                return;
            }
            if (!TestBound("Database"))
            {
                StopFunction("When using -SqlInstance with -Query or -Table, you must specify -Database");
                return;
            }
        }

        // PS: auto-detect compression from the file extension when not specified. The switch
        // compares the lowercased extension (case-insensitive by construction).
        string compressionType = CompressionType;
        if (PsString.Eq(compressionType, "None"))
        {
            string extension = System.IO.Path.GetExtension(Path).ToLower();
            switch (extension)
            {
                case ".gz": compressionType = "GZip"; break;
                case ".br": compressionType = "Brotli"; break;
                case ".deflate": compressionType = "Deflate"; break;
                case ".zlib": compressionType = "ZLib"; break;
            }
        }
        CompressionType = compressionType;

        // PS: if ($NoClobber -and (Test-Path -Path $Path) -and -not $Append) { stop }
        if (NoClobber.ToBool() && FileOrDirectoryExists(Path) && !Append.ToBool())
        {
            StopFunction($"File '{Path}' already exists and -NoClobber was specified");
            return;
        }

        _writerOptions = new CsvWriterOptions();
        _writerOptions.Delimiter = Delimiter;
        _writerOptions.Quote = Quote;
        _writerOptions.WriteHeader = !NoHeader.ToBool();
        _writerOptions.NullValue = NullValue;
        _writerOptions.DateTimeFormat = DateTimeFormat;
        _writerOptions.UseUtc = UseUtc.ToBool();
        // PS: [Enum]::$Name static member access is case-insensitive, like the ValidateSet.
        _writerOptions.QuotingBehavior = (CsvQuotingBehavior)Enum.Parse(typeof(CsvQuotingBehavior), QuotingBehavior, true);
        _writerOptions.CompressionType = (Dataplat.Dbatools.Csv.Compression.CompressionType)Enum.Parse(typeof(Dataplat.Dbatools.Csv.Compression.CompressionType), CompressionType, true);

        // PS: SmallestSize was added in .NET 6 — map to Optimal on Windows PowerShell with a
        // warning (the compiled net472 build only ever runs there).
        string effectiveCompressionLevel = CompressionLevel;
#if NETFRAMEWORK
        if (PsString.Eq(CompressionLevel, "SmallestSize"))
        {
            WriteMessage(MessageLevel.Warning, "CompressionLevel 'SmallestSize' is not available in Windows PowerShell. Using 'Optimal' instead.");
            effectiveCompressionLevel = "Optimal";
        }
#endif
        _writerOptions.CompressionLevel = (System.IO.Compression.CompressionLevel)Enum.Parse(typeof(System.IO.Compression.CompressionLevel), effectiveCompressionLevel, true);

        // PS: switch ($Encoding) — case-INSENSITIVE like the ValidateSet binding.
        if (PsString.Eq(Encoding, "ASCII")) { _writerOptions.Encoding = System.Text.Encoding.ASCII; }
        else if (PsString.Eq(Encoding, "BigEndianUnicode")) { _writerOptions.Encoding = System.Text.Encoding.BigEndianUnicode; }
        else if (PsString.Eq(Encoding, "Unicode")) { _writerOptions.Encoding = System.Text.Encoding.Unicode; }
#pragma warning disable SYSLIB0001
        else if (PsString.Eq(Encoding, "UTF7")) { _writerOptions.Encoding = System.Text.Encoding.UTF7; }
#pragma warning restore SYSLIB0001
        else if (PsString.Eq(Encoding, "UTF8")) { _writerOptions.Encoding = new UTF8Encoding(false); }
        else if (PsString.Eq(Encoding, "UTF32")) { _writerOptions.Encoding = System.Text.Encoding.UTF32; }

        // PS: suppress the header when appending to an existing file.
        if (Append.ToBool() && FileOrDirectoryExists(Path))
        {
            _writerOptions.WriteHeader = false;
        }

        _writer = null;
        _rowsWritten = 0;
        _rowsWidened = false;
        _inputObjects = new List<object?>();
        _elapsed = Stopwatch.StartNew();
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
        {
            return;
        }

        // PS: if ($PSBoundParameters.InputObject) — the BOUND VALUE's truthiness (an empty
        // bound array is falsy and falls through to the SqlInstance loop).
        if (TestBound("InputObject") && PsOps.IsTrue(InputObject))
        {
            foreach (object? inputElement in InputObject!)
            {
                _inputObjects.Add(inputElement);
            }
            return;
        }

        if (SqlInstance is null)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server;
            try
            {
                SmoConnectionRequest request = new SmoConnectionRequest();
                request.Instance = instance;
                request.SqlCredential = SqlCredential;
                request.Database = Database;
                server = ConnectionService.GetServer(request);
                SetActiveConnection(server.ConnectionContext);
            }
            catch (Exception ex)
            {
                // PS: Stop-Function -Message "Failed to connect to $instance" -ErrorRecord $_ -Target $instance -Continue
                StopFunction($"Failed to connect to {instance}",
                    target: instance,
                    errorRecord: new ErrorRecord(ex, "Export-DbaCsv", ErrorCategory.NotSpecified, instance),
                    continueLoop: true);
                continue;
            }

            string? sqlToExecute = null;

            if (TestBound("Query") && PsOps.IsTrue(Query))
            {
                sqlToExecute = Query;
            }
            else if (TestBound("Table") && PsOps.IsTrue(Table))
            {
                // PS: Get-ObjectNameParts handles bracketed and two-part names.
                ObjectNameParts parsedTable = ParseObjectNameParts(Table!);
                string schemaName;
                string? tableName;
                if (parsedTable.Parsed && !string.IsNullOrEmpty(parsedTable.Schema))
                {
                    schemaName = parsedTable.Schema!;
                    tableName = parsedTable.Name;
                }
                else if (parsedTable.Parsed)
                {
                    schemaName = "dbo";
                    tableName = parsedTable.Name;
                }
                else
                {
                    schemaName = "dbo";
                    tableName = Table;
                }
                sqlToExecute = $"SELECT * FROM [{schemaName}].[{tableName}]";
            }

            if (ShouldProcess(instance.ToString(), $"Exporting data to {Path}"))
            {
                IDataReader? reader = null;
                try
                {
                    WriteMessage(MessageLevel.Verbose, $"Executing query on {instance}");

                    // PS: raw SqlCommand over the SMO connection's SqlConnectionObject.
                    IDbConnection connection = (IDbConnection)server.ConnectionContext.SqlConnectionObject;
                    IDbCommand command = connection.CreateCommand();
                    command.CommandText = sqlToExecute;
                    command.CommandTimeout = 0;

                    if (connection.State != ConnectionState.Open)
                    {
                        connection.Open();
                    }

                    reader = command.ExecuteReader();

                    if (_writer is null)
                    {
                        _writer = new CsvWriter(Path, _writerOptions);
                    }

                    _rowsWritten += _writer.WriteFromReader(reader);
                    // PS: += with the reader's Int64 return widens $rowsWritten to Int64.
                    _rowsWidened = true;

                    reader.Close();
                    reader.Dispose();
                }
                catch (Exception ex)
                {
                    // PS: Stop-Function -Message "Failed to export data from $instance" -ErrorRecord $_ -Target $instance -Continue
                    StopFunction($"Failed to export data from {instance}",
                        target: instance,
                        errorRecord: new ErrorRecord(ex, "Export-DbaCsv", ErrorCategory.NotSpecified, instance),
                        continueLoop: true);
                    continue;
                }
            }
        }
    }

    protected override void EndProcessing()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
        {
            return;
        }

        // PS: process collected pipeline objects.
        if (_inputObjects.Count > 0)
        {
            if (ShouldProcess("InputObject", $"Exporting {_inputObjects.Count} objects to {Path}"))
            {
                try
                {
                    if (_writer is null)
                    {
                        _writer = new CsvWriter(Path, _writerOptions);
                    }

                    // PS: header columns come from the first object's NoteProperties, falling
                    // back to ALL properties when none exist.
                    object? firstObject = _inputObjects[0];
                    List<string> properties = new List<string>();
                    if (firstObject is not null)
                    {
                        foreach (PSPropertyInfo property in PSObject.AsPSObject(firstObject).Properties)
                        {
                            if (property.MemberType == PSMemberTypes.NoteProperty)
                            {
                                properties.Add(property.Name);
                            }
                        }
                        if (properties.Count == 0)
                        {
                            foreach (PSPropertyInfo property in PSObject.AsPSObject(firstObject).Properties)
                            {
                                properties.Add(property.Name);
                            }
                        }
                    }

                    if (_writerOptions.WriteHeader)
                    {
                        // PS: $writer.WriteHeader($properties) — the method binder converts the
                        // object[] property-name array to the params string[] by STRINGIFYING
                        // THE WHOLE ARRAY into one $OFS-joined cell (lab-observed: the function
                        // writes "Id Label Stamp" as a single header column). A lone name
                        // passes through unchanged either way, and a PROPERTY-LESS first object
                        // leaves $properties null in PS — the writer receives null.
                        if (properties.Count > 1)
                        {
                            _writer.WriteHeader(string.Join(GetOfsSeparator(), properties));
                        }
                        else if (properties.Count == 1)
                        {
                            _writer.WriteHeader(properties.ToArray());
                        }
                        else
                        {
                            _writer.WriteHeader((string[]?)null!);
                        }
                    }

                    foreach (object? inputElement in _inputObjects)
                    {
                        // PS: $values = foreach ($prop in $properties) { $obj.$prop } — the
                        // loop-expression collects EXPLICIT nulls (lab-proven both editions),
                        // flattens enumerable results one level KEEPING inner nulls, and only
                        // zero iterations (no properties) leave $values null for the writer.
                        List<object?> values = new List<object?>();
                        foreach (string propertyName in properties)
                        {
                            object? propertyValue = GetPropertyValue(inputElement, propertyName);
                            object? baseValue = propertyValue is PSObject valueWrapped ? valueWrapped.BaseObject : propertyValue;
                            if (propertyValue is not null && baseValue is not string && LanguagePrimitives.GetEnumerable(baseValue) is IEnumerable valueElements)
                            {
                                foreach (object? valueElement in valueElements)
                                {
                                    values.Add(valueElement);
                                }
                            }
                            else
                            {
                                values.Add(propertyValue);
                            }
                        }
                        if (values.Count == 0)
                        {
                            _writer.WriteRow((object[]?)null!);
                        }
                        else
                        {
                            _writer.WriteRow(values.ToArray());
                        }
                        _rowsWritten++;
                    }
                }
                catch (Exception ex)
                {
                    // PS: Stop-Function -Message "Failed to export input objects" -ErrorRecord $_
                    StopFunction("Failed to export input objects",
                        errorRecord: new ErrorRecord(ex, "Export-DbaCsv", ErrorCategory.NotSpecified, null));
                }
            }
        }

        // PS: dispose the writer, downgrading failures to a verbose line.
        if (_writer is not null)
        {
            try
            {
                _writer.Dispose();
            }
            catch (Exception ex)
            {
                WriteMessage(MessageLevel.Verbose, $"Error disposing CSV writer: {ex.Message}");
            }
        }

        _elapsed.Stop();

        // PS: emit the summary object only when rows were written.
        if (_rowsWritten > 0)
        {
            FileInfo? fileInfo = null;
            try
            {
                FileInfo candidate = new FileInfo(Path);
                if (candidate.Exists)
                {
                    fileInfo = candidate;
                }
            }
            catch
            {
                // PS: Get-Item -ErrorAction SilentlyContinue — a failed stat leaves $fileInfo null.
            }

            PSObject result = new PSObject();
            result.Properties.Add(new PSNoteProperty("Path", Path));
            // PS: $rowsWritten starts as Int32 and only WIDENS to Int64 when the reader path's
            // long return joins the sum (+=); pure piped-object ++ keeps Int32.
            result.Properties.Add(new PSNoteProperty("RowsExported", _rowsWidened ? _rowsWritten : (object)(int)_rowsWritten));
            // PS: else-branch 0 literals are Int32 while $fileInfo.Length is Int64.
            result.Properties.Add(new PSNoteProperty("FileSizeBytes", fileInfo is not null ? fileInfo.Length : (object)0));
            result.Properties.Add(new PSNoteProperty("FileSizeMB", fileInfo is not null ? Math.Round(fileInfo.Length / 1048576.0, 2) : (object)0));
            result.Properties.Add(new PSNoteProperty("CompressionType", CompressionType));
            result.Properties.Add(new PSNoteProperty("Elapsed", _elapsed.Elapsed));
            result.Properties.Add(new PSNoteProperty("RowsPerSecond", Math.Round(_rowsWritten / _elapsed.Elapsed.TotalSeconds, 1)));
            WriteObject(result);
        }
    }

    /// <summary>The session $OFS as the PS method binder's array-to-string conversion resolves it.</summary>
    private string GetOfsSeparator()
    {
        object? ofsValue;
        try
        {
            ofsValue = SessionState.PSVariable.GetValue("OFS");
        }
        catch
        {
            ofsValue = null;
        }
        if (ofsValue is null)
        {
            return " ";
        }
        return (string)LanguagePrimitives.ConvertTo(ofsValue, typeof(string), CultureInfo.InvariantCulture);
    }

    /// <summary>
    /// PS: $obj.$prop — dot access with the binder unwrap for bags. A THROWING getter
    /// propagates (the enclosing try turns it into the Stop-Function failure, exactly like
    /// the PS statement inside the export try).
    /// </summary>
    private static object? GetPropertyValue(object? item, string name)
    {
        if (item is null)
        {
            return null;
        }
        PSPropertyInfo? property = PSObject.AsPSObject(item).Properties[name];
        if (property is null)
        {
            return null;
        }
        object? value = property.Value;
        if (value is PSObject wrapped && wrapped.BaseObject is not PSCustomObject)
        {
            return wrapped.BaseObject;
        }
        return value;
    }

    /// <summary>
    /// PS: Test-Path — runs through the provider so WILDCARD characters ([a], *, ?) match
    /// like Test-Path does, not like a literal File.Exists. Provider failures (unknown
    /// drive) surface as a non-terminating error and read false, exactly like Test-Path.
    /// </summary>
    private bool FileOrDirectoryExists(string path)
    {
        try
        {
            return SessionState.InvokeProvider.Item.Exists(path);
        }
        catch (Exception ex)
        {
            WriteError(new ErrorRecord(ex, "Export-DbaCsv", ErrorCategory.ObjectNotFound, path));
            return false;
        }
    }

    internal sealed class ObjectNameParts
    {
        public string? Database;
        public string? Schema;
        public string? Name;
        public bool Parsed;
    }

    /// <summary>
    /// Private helper Get-ObjectNameParts absorbed: splits a one/two/three-part object name,
    /// honoring bracket quoting, ]]-escapes (temporarily swapped for the first unused
    /// character) and the empty dbo schema in database..table form.
    /// </summary>
    internal static ObjectNameParts ParseObjectNameParts(string objectName)
    {
        string working = objectName ?? "";
        string? fixChar = null;
        if (working.Contains("]]"))
        {
            for (int i = 0; i <= 65535; i++)
            {
                string candidate = ((char)i).ToString();
                if (!working.Contains(candidate))
                {
                    fixChar = candidate;
                    working = working.Replace("]]", candidate);
                    break;
                }
            }
        }
        string? fixSchema = null;
        if (working.Contains(".."))
        {
            for (int i = 0; i <= 65535; i++)
            {
                string candidate = ((char)i).ToString();
                if (!working.Contains(candidate))
                {
                    fixSchema = candidate;
                    working = working.Replace("..", "." + candidate + ".");
                    break;
                }
            }
        }

        List<string> splitName = new List<string>();
        foreach (Match match in Regex.Matches(working, "(\\[.+?\\])|([^\\.]+)"))
        {
            splitName.Add(match.Value);
        }

        string? dbName = null;
        string? schema = null;
        string? name = null;
        bool parsed;
        switch (splitName.Count)
        {
            case 1:
                name = working;
                parsed = true;
                break;
            case 2:
                schema = splitName[0];
                name = splitName[1];
                parsed = true;
                break;
            case 3:
                dbName = splitName[0];
                schema = splitName[1];
                name = splitName[2];
                parsed = true;
                break;
            default:
                parsed = false;
                break;
        }

        dbName = UnwrapBrackets(dbName, fixChar);
        schema = UnwrapBrackets(schema, fixChar);
        name = UnwrapBrackets(name, fixChar);

        if (fixSchema is not null)
        {
            if (!string.IsNullOrEmpty(dbName))
            {
                dbName = dbName!.Replace(fixSchema, "");
            }
            if (schema == fixSchema)
            {
                schema = null;
            }
            else if (!string.IsNullOrEmpty(schema))
            {
                schema = schema!.Replace(fixSchema, "");
            }
            if (!string.IsNullOrEmpty(name))
            {
                name = name!.Replace(fixSchema, "");
            }
        }

        ObjectNameParts parts = new ObjectNameParts();
        parts.Database = dbName;
        parts.Schema = schema;
        parts.Name = name;
        parts.Parsed = parsed;
        return parts;
    }

    private static string? UnwrapBrackets(string? value, string? fixChar)
    {
        // PS: if ($x -like "[[]*[]]") { trim the outer brackets, restore ]] escapes }
        if (value is null || value.Length < 2 || value[0] != '[' || value[value.Length - 1] != ']')
        {
            return value;
        }
        string trimmed = value.Substring(1, value.Length - 2);
        if (fixChar is not null)
        {
            trimmed = trimmed.Replace(fixChar, "]");
        }
        return trimmed;
    }
}
