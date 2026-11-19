using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Threading;
using Dataplat.Dbatools.Csv.Compression;
using Dataplat.Dbatools.Csv.TypeConverters;

namespace Dataplat.Dbatools.Csv.Reader
{
    /// <summary>
    /// Configuration options for the CSV reader.
    /// </summary>
    public sealed partial class CsvReaderOptions
    {
        /// <summary>
        /// Default buffer size in bytes (64KB).
        /// </summary>
        public const int DefaultBufferSize = 65536;

        private int _skipRows;
        private int _bufferSize = DefaultBufferSize;
        private int _maxQuotedFieldLength;
        private int _maxParseErrors = 1000;
        private int _maxDegreeOfParallelism;
        private int _parallelBatchSize = 100;
        private int _parallelQueueDepth = 10;

        /// <summary>
        /// Gets or sets whether the first row contains column headers.
        /// Default is true.
        /// </summary>
        public bool HasHeaderRow { get; set; } = true;

        /// <summary>
        /// Gets or sets the number of rows to skip at the beginning of the file
        /// before reading headers or data. Addresses issue #7173 (FirstRow feature).
        /// </summary>
        /// <exception cref="ArgumentOutOfRangeException">Thrown when value is negative.</exception>
        public int SkipRows
        {
            get => _skipRows;
            set
            {
                if (value < 0)
                    throw new ArgumentOutOfRangeException(nameof(value), value, "SkipRows cannot be negative.");
                _skipRows = value;
            }
        }

        private string _delimiter = ",";

        /// <summary>
        /// Gets or sets the field delimiter. Can be multiple characters.
        /// Default is comma. Addresses issue #6488 (multi-character delimiters).
        /// </summary>
        /// <exception cref="ArgumentNullException">Thrown when value is null.</exception>
        /// <exception cref="ArgumentException">Thrown when value is empty.</exception>
        public string Delimiter
        {
            get => _delimiter;
            set
            {
                if (value == null)
                    throw new ArgumentNullException(nameof(value), "Delimiter cannot be null.");
                if (value.Length == 0)
                    throw new ArgumentException("Delimiter cannot be empty.", nameof(value));
                _delimiter = value;
            }
        }

        /// <summary>
        /// Gets or sets the quote character used to enclose fields.
        /// Default is double-quote.
        /// </summary>
        public char Quote { get; set; } = '"';

        /// <summary>
        /// Gets or sets the escape character used within quoted fields.
        /// Default is double-quote (RFC 4180 standard).
        /// </summary>
        public char Escape { get; set; } = '"';

        /// <summary>
        /// Gets or sets the comment character. Lines starting with this character are ignored.
        /// Default is #.
        /// </summary>
        public char Comment { get; set; } = '#';

        /// <summary>
        /// Gets or sets the value trimming options.
        /// Default is None.
        /// </summary>
        public ValueTrimmingOptions TrimmingOptions { get; set; } = ValueTrimmingOptions.None;

        /// <summary>
        /// Gets or sets the internal buffer size in bytes.
        /// Default is <see cref="DefaultBufferSize"/> (64KB) for better performance than LumenWorks' 4KB.
        /// Minimum value is 128 bytes.
        /// </summary>
        /// <exception cref="ArgumentOutOfRangeException">Thrown when value is less than 128.</exception>
        public int BufferSize
        {
            get => _bufferSize;
            set
            {
                if (value < 128)
                    throw new ArgumentOutOfRangeException(nameof(value), value, "BufferSize must be at least 128 bytes.");
                _bufferSize = value;
            }
        }

        /// <summary>
        /// Gets or sets the file encoding.
        /// Default is UTF-8.
        /// </summary>
        public Encoding Encoding { get; set; } = Encoding.UTF8;

        /// <summary>
        /// Gets or sets the string value to treat as null.
        /// Default is null (no special null handling).
        /// </summary>
        public string NullValue { get; set; }

        /// <summary>
        /// Gets or sets the action to take when a parse error occurs.
        /// Default is ThrowException.
        /// </summary>
        public CsvParseErrorAction ParseErrorAction { get; set; } = CsvParseErrorAction.ThrowException;

        /// <summary>
        /// Gets or sets whether to skip empty lines.
        /// Default is true.
        /// </summary>
        public bool SkipEmptyLines { get; set; } = true;

        /// <summary>
        /// Gets or sets whether quoted fields can span multiple lines.
        /// Default is true.
        /// </summary>
        public bool AllowMultilineFields { get; set; } = true;

        /// <summary>
        /// Gets or sets the maximum length of a quoted field in characters.
        /// Used to prevent memory issues with malformed data or denial-of-service attacks.
        /// Default is 0 (no limit). Set to a positive value to enforce a limit.
        /// </summary>
        /// <exception cref="ArgumentOutOfRangeException">Thrown when value is negative.</exception>
        public int MaxQuotedFieldLength
        {
            get => _maxQuotedFieldLength;
            set
            {
                if (value < 0)
                    throw new ArgumentOutOfRangeException(nameof(value), value, "MaxQuotedFieldLength cannot be negative.");
                _maxQuotedFieldLength = value;
            }
        }

        /// <summary>
        /// Gets or sets whether to detect the compression type automatically.
        /// Default is true.
        /// </summary>
        public bool AutoDetectCompression { get; set; } = true;

        /// <summary>
        /// Gets or sets the explicit compression type.
        /// Only used when AutoDetectCompression is false.
        /// </summary>
        public CompressionType CompressionType { get; set; } = CompressionType.None;

        /// <summary>
        /// Gets or sets the maximum decompressed size in bytes for compressed files.
        /// Used to prevent decompression bomb attacks.
        /// Default is 10GB. Set to 0 for unlimited.
        /// Only applies to compressed files (GZip, Deflate, Brotli, ZLib).
        /// </summary>
        public long MaxDecompressedSize { get; set; } = CompressionHelper.DefaultMaxDecompressedSize;

        /// <summary>
        /// Gets or sets the type converter registry to use for automatic type conversion.
        /// Default is TypeConverterRegistry.Default.
        /// </summary>
        public TypeConverterRegistry TypeConverterRegistry { get; set; } = TypeConverterRegistry.Default;

        /// <summary>
        /// Gets or sets whether to use column defaults when values are null or empty.
        /// Default is false.
        /// </summary>
        public bool UseColumnDefaults { get; set; }

        /// <summary>
        /// Gets or sets the static columns to inject into each record.
        /// Addresses issue #6676.
        /// </summary>
        public List<StaticColumn> StaticColumns { get; set; }

        /// <summary>
        /// Gets or sets the column type mappings.
        /// Key is the column name, value is the target type.
        /// </summary>
        public Dictionary<string, Type> ColumnTypes { get; set; }

        /// <summary>
        /// Gets or sets a custom date format for DateTime parsing.
        /// Addresses issue #9694.
        /// </summary>
        public string[] DateTimeFormats { get; set; }

        /// <summary>
        /// Gets or sets whether to collect parse errors instead of throwing.
        /// When true, errors are collected and can be retrieved after reading.
        /// Addresses issue #6899 (view/log bad rows).
        /// </summary>
        public bool CollectParseErrors { get; set; }

        /// <summary>
        /// Gets or sets the maximum number of parse errors to collect before stopping.
        /// Default is 1000. Set to 0 for unlimited.
        /// </summary>
        /// <exception cref="ArgumentOutOfRangeException">Thrown when value is negative.</exception>
        public int MaxParseErrors
        {
            get => _maxParseErrors;
            set
            {
                if (value < 0)
                    throw new ArgumentOutOfRangeException(nameof(value), value, "MaxParseErrors cannot be negative.");
                _maxParseErrors = value;
            }
        }

        /// <summary>
        /// Gets or sets the column names to include (filter).
        /// If null or empty, all columns are included.
        /// </summary>
        public HashSet<string> IncludeColumns { get; set; }

        /// <summary>
        /// Gets or sets the column names to exclude.
        /// Applied after IncludeColumns filter.
        /// </summary>
        public HashSet<string> ExcludeColumns { get; set; }

        /// <summary>
        /// Gets or sets whether to distinguish between null (missing) and empty string values.
        /// When true: ,, becomes null, ,"", becomes empty string.
        /// When false (default): both become empty string.
        /// Addresses LumenWorks issue #68.
        /// </summary>
        public bool DistinguishEmptyFromNull { get; set; }

        /// <summary>
        /// Gets or sets how to handle duplicate column headers.
        /// Default is ThrowException.
        /// Addresses LumenWorks issue #39.
        /// </summary>
        public DuplicateHeaderBehavior DuplicateHeaderBehavior { get; set; } = DuplicateHeaderBehavior.ThrowException;

        private string _defaultHeaderName = "Column";

        /// <summary>
        /// Gets or sets the default header name prefix used for empty or whitespace-only headers.
        /// The column index will be appended to the specified name (e.g., "Column0", "Column1").
        /// Default is "Column".
        /// This matches the behavior of the LumenWorks CSV library.
        /// </summary>
        /// <exception cref="ArgumentNullException">Thrown when value is null.</exception>
        /// <exception cref="ArgumentException">Thrown when value is empty or whitespace-only.</exception>
        public string DefaultHeaderName
        {
            get => _defaultHeaderName;
            set
            {
                if (value == null)
                    throw new ArgumentNullException(nameof(value), "DefaultHeaderName cannot be null.");
                if (string.IsNullOrWhiteSpace(value))
                    throw new ArgumentException("DefaultHeaderName cannot be empty or whitespace-only.", nameof(value));
                _defaultHeaderName = value;
            }
        }

        /// <summary>
        /// Gets or sets the culture to use for parsing numbers and dates.
        /// Default is InvariantCulture.
        /// Addresses LumenWorks issue #66.
        /// </summary>
        public CultureInfo Culture { get; set; } = CultureInfo.InvariantCulture;

        /// <summary>
        /// Gets or sets the quote parsing mode.
        /// Strict follows RFC 4180, Lenient handles common malformed data.
        /// Default is Strict.
        /// Addresses LumenWorks issues #47 and #56.
        /// <para>
        /// <b>Security Note:</b> Use <see cref="Reader.QuoteMode.Lenient"/> only for known
        /// malformed data sources. Lenient mode may parse data differently than expected
        /// and has additional performance overhead. See <see cref="Reader.QuoteMode"/> for details.
        /// </para>
        /// </summary>
        public QuoteMode QuoteMode { get; set; } = QuoteMode.Strict;

        /// <summary>
        /// Gets or sets how to handle rows with mismatched field counts.
        /// Default is ThrowException.
        /// <para>
        /// <b>Data Integrity Note:</b> Non-default values may mask data corruption or cause silent data loss:
        /// <list type="bullet">
        /// <item><see cref="Reader.MismatchedFieldAction.PadWithNulls"/> - Missing fields become null, potentially hiding truncated rows.</item>
        /// <item><see cref="Reader.MismatchedFieldAction.TruncateExtra"/> - Extra fields are silently discarded.</item>
        /// </list>
        /// Use with caution and validate results when processing untrusted data.
        /// </para>
        /// </summary>
        public MismatchedFieldAction MismatchedFieldAction { get; set; } = MismatchedFieldAction.ThrowException;

        /// <summary>
        /// Gets or sets whether to normalize smart/curly quotes to standard ASCII quotes.
        /// Converts ' ' to ' and " " to ".
        /// Useful for data exported from Word or Excel.
        /// Addresses LumenWorks issue #25.
        /// </summary>
        public bool NormalizeQuotes { get; set; }

        /// <summary>
        /// Gets or sets whether to intern commonly occurring string values to reduce memory allocations.
        /// When enabled, frequently occurring values like empty strings and common markers are interned.
        /// This can significantly reduce GC pressure for large files with many repeated values.
        /// Default is false.
        /// </summary>
        public bool InternStrings { get; set; }

        /// <summary>
        /// Gets or sets custom string values to intern when InternStrings is enabled.
        /// These are in addition to the built-in set (empty string, "NULL", "null", "N/A", etc.).
        /// Set to null to use only the built-in intern values.
        /// </summary>
        public HashSet<string> CustomInternStrings { get; set; }
    }
}
