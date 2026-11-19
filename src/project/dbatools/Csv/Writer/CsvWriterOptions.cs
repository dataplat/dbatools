using System;
using System.IO.Compression;
using System.Text;
using Dataplat.Dbatools.Csv.Compression;

namespace Dataplat.Dbatools.Csv.Writer
{
    /// <summary>
    /// Configuration options for the CSV writer.
    /// Addresses issue #8646 for Export-DbaCsv with compression options.
    /// </summary>
    public sealed class CsvWriterOptions
    {
        /// <summary>
        /// Default buffer size in bytes (64KB).
        /// </summary>
        public const int DefaultBufferSize = 65536;

        /// <summary>
        /// Gets or sets whether to write a header row.
        /// Default is true.
        /// </summary>
        public bool WriteHeader { get; set; } = true;

        /// <summary>
        /// Gets or sets the field delimiter.
        /// Default is comma.
        /// </summary>
        public string Delimiter { get; set; } = ",";

        /// <summary>
        /// Gets or sets the quote character used to enclose fields.
        /// Default is double-quote.
        /// </summary>
        public char Quote { get; set; } = '"';

        /// <summary>
        /// Gets or sets the newline sequence to use.
        /// Default is Environment.NewLine.
        /// </summary>
        public string NewLine { get; set; } = Environment.NewLine;

        /// <summary>
        /// Gets or sets the file encoding.
        /// Default is UTF-8 without BOM.
        /// </summary>
        public Encoding Encoding { get; set; } = new UTF8Encoding(false);

        /// <summary>
        /// Gets or sets when to quote field values.
        /// Default is AsNeeded.
        /// </summary>
        public CsvQuotingBehavior QuotingBehavior { get; set; } = CsvQuotingBehavior.AsNeeded;

        /// <summary>
        /// Gets or sets the string to use for null values.
        /// Default is empty string.
        /// </summary>
        public string NullValue { get; set; } = "";

        /// <summary>
        /// Gets or sets the compression type for output.
        /// Default is None.
        /// </summary>
        public CompressionType CompressionType { get; set; } = CompressionType.None;

        /// <summary>
        /// Gets or sets the compression level.
        /// Default is Optimal.
        /// </summary>
        public CompressionLevel CompressionLevel { get; set; } = CompressionLevel.Optimal;

        /// <summary>
        /// Gets or sets the buffer size in bytes.
        /// Default is <see cref="DefaultBufferSize"/> (64KB).
        /// </summary>
        public int BufferSize { get; set; } = DefaultBufferSize;

        /// <summary>
        /// Gets or sets the date time format string for DateTime values.
        /// Default is ISO 8601 format.
        /// </summary>
        public string DateTimeFormat { get; set; } = "yyyy-MM-dd HH:mm:ss.fff";

        /// <summary>
        /// Gets or sets whether to use UTC for DateTime values.
        /// Default is false.
        /// </summary>
        public bool UseUtc { get; set; }

        /// <summary>
        /// Gets or sets whether to flush after each row.
        /// Default is false for performance.
        /// </summary>
        public bool FlushAfterEachRow { get; set; }

        /// <summary>
        /// Creates a default options instance.
        /// </summary>
        public static CsvWriterOptions Default => new CsvWriterOptions();

        /// <summary>
        /// Creates options for tab-delimited output.
        /// </summary>
        public static CsvWriterOptions TabDelimited => new CsvWriterOptions { Delimiter = "\t" };

        /// <summary>
        /// Creates options for GZip-compressed output.
        /// </summary>
        public static CsvWriterOptions GZipCompressed => new CsvWriterOptions
        {
            CompressionType = CompressionType.GZip,
            CompressionLevel = CompressionLevel.Optimal
        };

        /// <summary>
        /// Creates a clone of these options.
        /// </summary>
        public CsvWriterOptions Clone()
        {
            return new CsvWriterOptions
            {
                WriteHeader = WriteHeader,
                Delimiter = Delimiter,
                Quote = Quote,
                NewLine = NewLine,
                Encoding = Encoding,
                QuotingBehavior = QuotingBehavior,
                NullValue = NullValue,
                CompressionType = CompressionType,
                CompressionLevel = CompressionLevel,
                BufferSize = BufferSize,
                DateTimeFormat = DateTimeFormat,
                UseUtc = UseUtc,
                FlushAfterEachRow = FlushAfterEachRow
            };
        }
    }

    /// <summary>
    /// Specifies when to quote field values.
    /// </summary>
    public enum CsvQuotingBehavior
    {
        /// <summary>
        /// Quote fields only when necessary (contains delimiter, quote, or newline).
        /// </summary>
        AsNeeded = 0,

        /// <summary>
        /// Always quote all fields.
        /// </summary>
        Always = 1,

        /// <summary>
        /// Never quote fields (may produce invalid CSV with some data).
        /// </summary>
        Never = 2,

        /// <summary>
        /// Quote only non-numeric fields.
        /// </summary>
        NonNumeric = 3
    }
}
