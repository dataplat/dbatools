#nullable enable

using System;
using System.Collections;
using System.Diagnostics;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Csv.Reader;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Imports CSV files into SQL Server tables using SqlBulkCopy over the Dataplat CSV reader.
/// Port of public/Import-DbaCsv.ps1 with its begin-block helpers (New-SqlTable,
/// New-SqlTableWithInferredSchema, Get-InferredSchema, Optimize-ColumnSize,
/// ConvertTo-DotnetType, Get-TableDefinitionFromInfoSchema) and the private helpers
/// Get-ObjectNameParts, Get-AdjustedTotalRowsCopied and Get-BulkRowsCopiedCount absorbed.
/// Surface pinned by migration/baselines/Import-DbaCsv.json (auto-assigned positions 0-31).
/// Import-DbaCsv never calls Test-FunctionInterrupt, so ProcessRecord deliberately does
/// NOT guard on Interrupted: a non-continue Stop-Function only ends the current process
/// block (via return at the call site) and later pipeline input still processes.
/// </summary>
[Cmdlet(VerbsData.Import, "DbaCsv", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed partial class ImportDbaCsvCommand : DbaInstanceCmdlet
{
    /// <summary>The CSV file paths to import; accepts pipeline input from Get-ChildItem.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    [Alias("Csv", "FullPath")]
    public object[]? Path { get; set; }

    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 2)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The target database for the CSV import.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [PsStringCast]
    public string Database { get; set; } = null!;

    /// <summary>The destination table name; defaults to the CSV file name.</summary>
    [Parameter(Position = 4)]
    public string? Table { get; set; }

    /// <summary>The target schema; defaults to dbo.</summary>
    [Parameter(Position = 5)]
    public string? Schema { get; set; }

    /// <summary>Removes all existing data from the destination table before importing.</summary>
    [Parameter]
    public SwitchParameter Truncate { get; set; }

    /// <summary>The field separator; multi-character delimiters are supported.</summary>
    [Parameter(Position = 6)]
    [ValidateNotNullOrEmpty]
    [Alias("DelimiterChar")]
    public string Delimiter { get; set; } = ",";

    /// <summary>Indicates the CSV contains only one column of data without delimiters.</summary>
    [Parameter]
    public SwitchParameter SingleColumn { get; set; }

    /// <summary>Rows per bulk copy batch.</summary>
    [Parameter(Position = 7)]
    public int BatchSize { get; set; } = 50000;

    /// <summary>Progress notification interval in rows.</summary>
    [Parameter(Position = 8)]
    public int NotifyAfter { get; set; } = 50000;

    /// <summary>Acquires an exclusive table lock for the import.</summary>
    [Parameter]
    public SwitchParameter TableLock { get; set; }

    /// <summary>Enforces check constraints during the import.</summary>
    [Parameter]
    public SwitchParameter CheckConstraints { get; set; }

    /// <summary>Executes INSERT triggers during the bulk copy.</summary>
    [Parameter]
    public SwitchParameter FireTriggers { get; set; }

    /// <summary>Preserves identity values from the CSV.</summary>
    [Parameter]
    public SwitchParameter KeepIdentity { get; set; }

    /// <summary>Preserves NULL values instead of applying column defaults.</summary>
    [Parameter]
    public SwitchParameter KeepNulls { get; set; }

    /// <summary>Imports only the specified columns.</summary>
    [Parameter(Position = 9)]
    public string[]? Column { get; set; }

    /// <summary>Maps CSV columns to table columns; keys are CSV names (or ordinals), values table names.</summary>
    [Parameter(Position = 10)]
    public Hashtable? ColumnMap { get; set; }

    /// <summary>Maps columns by position rather than by name.</summary>
    [Parameter]
    public SwitchParameter KeepOrdinalOrder { get; set; }

    /// <summary>Creates the destination table automatically with nvarchar(max) columns.</summary>
    [Parameter]
    public SwitchParameter AutoCreateTable { get; set; }

    /// <summary>Skips the post-import column size optimization after AutoCreateTable.</summary>
    [Parameter]
    public SwitchParameter NoColumnOptimize { get; set; }

    /// <summary>Disables the progress bar display.</summary>
    [Parameter]
    public SwitchParameter NoProgress { get; set; }

    /// <summary>Treats the first row as data instead of column headers.</summary>
    [Parameter]
    public SwitchParameter NoHeaderRow { get; set; }

    /// <summary>Extracts the schema name from the file name using the first period.</summary>
    [Parameter]
    public SwitchParameter UseFileNameForSchema { get; set; }

    /// <summary>The character used to quote fields.</summary>
    [Parameter(Position = 11)]
    public char Quote { get; set; } = '"';

    /// <summary>The character used to escape quote characters within quoted fields.</summary>
    [Parameter(Position = 12)]
    public char Escape { get; set; } = '"';

    /// <summary>The character that marks comment lines.</summary>
    [Parameter(Position = 13)]
    public char Comment { get; set; } = '#';

    /// <summary>Controls automatic whitespace removal from field values.</summary>
    [Parameter(Position = 14)]
    [PsStringCast]
    [ValidateSet("All", "None", "UnquotedOnly", "QuotedOnly")]
    public string TrimmingOption { get; set; } = "None";

    /// <summary>Internal read buffer size in bytes.</summary>
    [Parameter(Position = 15)]
    public int BufferSize { get; set; } = 4096;

    /// <summary>How malformed rows are handled during import.</summary>
    [Parameter(Position = 16)]
    [PsStringCast]
    [ValidateSet("AdvanceToNextLine", "ThrowException")]
    public string ParseErrorAction { get; set; } = "ThrowException";

    /// <summary>The text encoding of the CSV file.</summary>
    [Parameter(Position = 17)]
    [PsStringCast]
    [ValidateSet("ASCII", "BigEndianUnicode", "Byte", "String", "Unicode", "UTF7", "UTF8", "Unknown")]
    public string Encoding { get; set; } = "UTF8";

    /// <summary>The text value treated as SQL NULL.</summary>
    [Parameter(Position = 18)]
    public string? NullValue { get; set; }

    /// <summary>Maximum allowed length in bytes for quoted fields.</summary>
    [Parameter(Position = 19)]
    public int MaxQuotedFieldLength { get; set; }

    /// <summary>Ignores completely empty lines.</summary>
    [Parameter]
    public SwitchParameter SkipEmptyLine { get; set; }

    /// <summary>Controls whether quoted values may span multiple lines.</summary>
    [Parameter]
    public SwitchParameter SupportsMultiline { get; set; }

    /// <summary>Applies table column defaults for missing or empty CSV fields.</summary>
    [Parameter]
    public SwitchParameter UseColumnDefault { get; set; }

    /// <summary>Disables the automatic transaction wrapper.</summary>
    [Parameter]
    public SwitchParameter NoTransaction { get; set; }

    /// <summary>Maximum decompressed size in bytes for compressed CSV files.</summary>
    [Parameter(Position = 20)]
    public long MaxDecompressedSize { get; set; } = 10737418240;

    /// <summary>Rows to skip at the beginning of the file.</summary>
    [Parameter(Position = 21)]
    public int SkipRows { get; set; } = 0;

    /// <summary>How quoted fields are parsed (Strict RFC 4180 or Lenient).</summary>
    [Parameter(Position = 22)]
    [PsStringCast]
    [ValidateSet("Strict", "Lenient")]
    public string QuoteMode { get; set; } = "Strict";

    /// <summary>How duplicate column headers are handled.</summary>
    [Parameter(Position = 23)]
    [PsStringCast]
    [ValidateSet("ThrowException", "Rename", "UseFirstOccurrence", "UseLastOccurrence")]
    public string DuplicateHeaderBehavior { get; set; } = "ThrowException";

    /// <summary>What happens when a row has more or fewer fields than expected.</summary>
    [Parameter(Position = 24)]
    [PsStringCast]
    [ValidateSet("ThrowException", "PadWithNulls", "TruncateExtra", "PadOrTruncate")]
    public string MismatchedFieldAction { get; set; } = "ThrowException";

    /// <summary>Treats empty quoted fields as empty strings and unquoted empties as null.</summary>
    [Parameter]
    public SwitchParameter DistinguishEmptyFromNull { get; set; }

    /// <summary>Converts smart quotes to standard ASCII quotes before parsing.</summary>
    [Parameter]
    public SwitchParameter NormalizeQuotes { get; set; }

    /// <summary>Collects parse errors instead of throwing immediately.</summary>
    [Parameter]
    public SwitchParameter CollectParseErrors { get; set; }

    /// <summary>Maximum parse errors to collect before stopping.</summary>
    [Parameter(Position = 25)]
    public int MaxParseErrors { get; set; } = 1000;

    /// <summary>Static column names and values added to every row.</summary>
    [Parameter(Position = 26)]
    public Hashtable? StaticColumns { get; set; }

    /// <summary>Custom date/time format strings for parsing date columns.</summary>
    [Parameter(Position = 27)]
    public string[]? DateTimeFormats { get; set; }

    /// <summary>The culture name used for parsing numbers and dates.</summary>
    [Parameter(Position = 28)]
    public string? Culture { get; set; }

    /// <summary>Enables type detection by sampling the first N rows.</summary>
    [Parameter(Position = 29)]
    public int SampleRows { get; set; }

    /// <summary>Enables type detection by scanning the entire file before import.</summary>
    [Parameter]
    public SwitchParameter DetectColumnTypes { get; set; }

    /// <summary>Enables parallel line reading, parsing and type conversion.</summary>
    [Parameter]
    public SwitchParameter Parallel { get; set; }

    /// <summary>Maximum worker threads for parallel processing.</summary>
    [Parameter(Position = 30)]
    public int ThrottleLimit { get; set; } = 0;

    /// <summary>Records batched before yielding to the consumer in parallel mode.</summary>
    [Parameter(Position = 31)]
    public int ParallelBatchSize { get; set; } = 100;

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Function-scope state: the PS begin/process/end blocks share one variable scope, so
    // these survive across pipeline items exactly like the function's locals did.
    private bool _firstRowHeader;
    private Stopwatch _scriptElapsed = null!;
    private bool _useTypeDetection;
    private bool _allowMultilineFields;
    private string _schema = "";
    private string _table = "";
    // PS: $periodFound is assigned but never reset - once a file name with a period is
    // seen, the flag stays true for every later file in the same invocation.
    private bool _periodFound;
    // PS: $completed persists across iterations; the Finalizing block reads whatever the
    // last import attempt left (undefined on the first pass when import was gated off).
    private bool? _completed;
    private bool _startedWithAnOpenConnection;
    private Server? _server;
    private SqlConnection? _sqlconn;
    private SqlTransaction? _transaction;
    private SqlBulkCopy? _bulkcopy;
    private CsvDataReader? _reader;
    private Hashtable? _columnMap;
    // PS: $script:prevRowsCopied / $script:totalRowsCopied
    private long _prevRowsCopied;
    private long _totalRowsCopied;

    /// <summary>Whether the named parameter was bound AND its bound value is PS-truthy
    /// (the source tests $PSBoundParameters.Name, which is value truthiness, not presence).</summary>
    private bool BoundTruthy(string parameterName)
    {
        object? value;
        if (!MyInvocation.BoundParameters.TryGetValue(parameterName, out value))
            return false;
        return LanguagePrimitives.IsTrue(value);
    }

    protected override void BeginProcessing()
    {
        // PS: $FirstRowHeader = $NoHeaderRow -eq $false
        _firstRowHeader = !NoHeaderRow.IsPresent;
        _scriptElapsed = Stopwatch.StartNew();

        if (BoundTruthy("UseFileNameForSchema") && BoundTruthy("Schema"))
            WriteMessage(MessageLevel.Warning, "Schema and UseFileNameForSchema parameters both specified. UseSchemaInFileName will be ignored.");

        // Type detection implies AutoCreateTable behavior
        _useTypeDetection = BoundTruthy("SampleRows") || DetectColumnTypes.IsPresent;
        if (_useTypeDetection && !AutoCreateTable.IsPresent)
            WriteMessage(MessageLevel.Verbose, "Type detection enabled - AutoCreateTable behavior will be used for table creation.");

        if (BoundTruthy("SampleRows") && DetectColumnTypes.IsPresent)
            WriteMessage(MessageLevel.Warning, "Both SampleRows and DetectColumnTypes specified. DetectColumnTypes (full scan) takes precedence for zero-risk type detection.");

        bool supportsMultilineSpecified = TestBound("SupportsMultiline");
        if (PsString.Eq(QuoteMode, "Strict") && !supportsMultilineSpecified)
            _allowMultilineFields = true;
        else
            _allowMultilineFields = SupportsMultiline.IsPresent;

        _schema = Schema ?? "";
        _table = Table ?? "";

        // PS: "$(Get-Date)" interpolation renders through LanguagePrimitives = invariant culture.
        WriteMessage(MessageLevel.Verbose, "Started at " + DateTime.Now.ToString(CultureInfo.InvariantCulture));
    }

    protected override void EndProcessing()
    {
        // PS: one try around all four closes; the first null-valued call throws and the
        // empty catch swallows it, skipping the rest - the null-forgiving calls below
        // deliberately reproduce that (an NRE lands in the catch exactly like PS).
        try
        {
            if (!_startedWithAnOpenConnection)
            {
                _sqlconn!.Close();
                _sqlconn!.Dispose();
            }
            _bulkcopy!.Close();
            // SqlBulkCopy implements IDisposable explicitly; PS's binder resolves it anyway.
            ((IDisposable)_bulkcopy!).Dispose();
            _reader!.Close();
            _reader!.Dispose();
        }
        catch
        {
            // PS: here to avoid an empty catch ($null = 1)
        }

        // Script is finished. Show elapsed time.
        double totaltime = Math.Round(_scriptElapsed.Elapsed.TotalSeconds, 2);
        WriteMessage(MessageLevel.Verbose, "Total Elapsed Time for everything: " + totaltime.ToString(CultureInfo.InvariantCulture) + " seconds");
    }
}
