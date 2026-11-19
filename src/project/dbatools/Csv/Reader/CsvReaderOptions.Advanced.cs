using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Threading;
using Dataplat.Dbatools.Csv.Compression;
using Dataplat.Dbatools.Csv.TypeConverters;

namespace Dataplat.Dbatools.Csv.Reader
{
    public sealed partial class CsvReaderOptions
    {

        /// <summary>
        /// Gets or sets whether to enable parallel processing for improved performance on large files.
        /// When enabled, line reading, parsing, and type conversion are performed in parallel using
        /// a producer-consumer pipeline. This can provide 2-4x performance improvement on multi-core systems.
        /// Default is false (sequential processing).
        /// <para>
        /// <b>Note:</b> Parallel processing is most beneficial for large files (>100K rows) with
        /// complex type conversions. For small files, sequential processing may be faster due to
        /// lower overhead.
        /// </para>
        /// </summary>
        public bool EnableParallelProcessing { get; set; }

        /// <summary>
        /// Gets or sets the maximum number of worker threads for parallel processing.
        /// Default is 0, which uses Environment.ProcessorCount.
        /// Set to 1 to effectively disable parallelism while still using the pipeline architecture.
        /// Only used when EnableParallelProcessing is true.
        /// </summary>
        /// <exception cref="ArgumentOutOfRangeException">Thrown when value is negative.</exception>
        public int MaxDegreeOfParallelism
        {
            get => _maxDegreeOfParallelism;
            set
            {
                if (value < 0)
                    throw new ArgumentOutOfRangeException(nameof(value), value, "MaxDegreeOfParallelism cannot be negative.");
                _maxDegreeOfParallelism = value;
            }
        }

        /// <summary>
        /// Gets or sets the number of records to batch before yielding to the consumer.
        /// Larger batches reduce synchronization overhead but increase memory usage and latency.
        /// Default is 100. Minimum is 1.
        /// Only used when EnableParallelProcessing is true.
        /// </summary>
        /// <exception cref="ArgumentOutOfRangeException">Thrown when value is less than 1.</exception>
        public int ParallelBatchSize
        {
            get => _parallelBatchSize;
            set
            {
                if (value < 1)
                    throw new ArgumentOutOfRangeException(nameof(value), value, "ParallelBatchSize must be at least 1.");
                _parallelBatchSize = value;
            }
        }

        /// <summary>
        /// Gets or sets the maximum number of batches to queue before applying backpressure.
        /// This limits memory usage when production outpaces consumption.
        /// Default is 10. Minimum is 1.
        /// Only used when EnableParallelProcessing is true.
        /// </summary>
        /// <exception cref="ArgumentOutOfRangeException">Thrown when value is less than 1.</exception>
        public int ParallelQueueDepth
        {
            get => _parallelQueueDepth;
            set
            {
                if (value < 1)
                    throw new ArgumentOutOfRangeException(nameof(value), value, "ParallelQueueDepth must be at least 1.");
                _parallelQueueDepth = value;
            }
        }



        /// <summary>
        /// Gets or sets the cancellation token to monitor for cancellation requests.
        /// When cancelled, the reader will throw an OperationCanceledException on the next Read() call.
        /// Default is CancellationToken.None.
        /// </summary>
        public CancellationToken CancellationToken { get; set; } = CancellationToken.None;

        private int _progressReportInterval = 10000;

        /// <summary>
        /// Gets or sets the interval (in records) at which to report progress.
        /// Set to 0 to disable progress reporting. Default is 10000.
        /// Progress is reported via the <see cref="ProgressCallback"/> delegate.
        /// </summary>
        /// <exception cref="ArgumentOutOfRangeException">Thrown when value is negative.</exception>
        public int ProgressReportInterval
        {
            get => _progressReportInterval;
            set
            {
                if (value < 0)
                    throw new ArgumentOutOfRangeException(nameof(value), value, "ProgressReportInterval cannot be negative.");
                _progressReportInterval = value;
            }
        }

        /// <summary>
        /// Gets or sets the callback to invoke when progress is reported.
        /// The callback receives a <see cref="CsvProgress"/> object with current progress information.
        /// Called every <see cref="ProgressReportInterval"/> records.
        /// </summary>
        public Action<CsvProgress> ProgressCallback { get; set; }


        /// <summary>
        /// Creates a default options instance.
        /// </summary>
        public static CsvReaderOptions Default => new CsvReaderOptions();

        /// <summary>
        /// Creates options for tab-delimited files.
        /// </summary>
        public static CsvReaderOptions TabDelimited => new CsvReaderOptions { Delimiter = "\t" };

        /// <summary>
        /// Creates options for pipe-delimited files.
        /// </summary>
        public static CsvReaderOptions PipeDelimited => new CsvReaderOptions { Delimiter = "|" };

        /// <summary>
        /// Creates options for semicolon-delimited files (common in European locales).
        /// </summary>
        public static CsvReaderOptions SemicolonDelimited => new CsvReaderOptions { Delimiter = ";" };

        /// <summary>
        /// Creates a clone of these options.
        /// </summary>
        public CsvReaderOptions Clone()
        {
            return new CsvReaderOptions
            {
                HasHeaderRow = HasHeaderRow,
                SkipRows = SkipRows,
                Delimiter = Delimiter,
                Quote = Quote,
                Escape = Escape,
                Comment = Comment,
                TrimmingOptions = TrimmingOptions,
                BufferSize = BufferSize,
                Encoding = Encoding,
                NullValue = NullValue,
                ParseErrorAction = ParseErrorAction,
                SkipEmptyLines = SkipEmptyLines,
                AllowMultilineFields = AllowMultilineFields,
                MaxQuotedFieldLength = MaxQuotedFieldLength,
                AutoDetectCompression = AutoDetectCompression,
                CompressionType = CompressionType,
                MaxDecompressedSize = MaxDecompressedSize,
                TypeConverterRegistry = TypeConverterRegistry,
                UseColumnDefaults = UseColumnDefaults,
                StaticColumns = StaticColumns != null ? new List<StaticColumn>(StaticColumns) : null,
                ColumnTypes = ColumnTypes != null ? new Dictionary<string, Type>(ColumnTypes) : null,
                DateTimeFormats = DateTimeFormats,
                CollectParseErrors = CollectParseErrors,
                MaxParseErrors = MaxParseErrors,
                IncludeColumns = IncludeColumns != null ? new HashSet<string>(IncludeColumns) : null,
                ExcludeColumns = ExcludeColumns != null ? new HashSet<string>(ExcludeColumns) : null,
                DistinguishEmptyFromNull = DistinguishEmptyFromNull,
                DuplicateHeaderBehavior = DuplicateHeaderBehavior,
                DefaultHeaderName = DefaultHeaderName,
                Culture = Culture,
                QuoteMode = QuoteMode,
                MismatchedFieldAction = MismatchedFieldAction,
                NormalizeQuotes = NormalizeQuotes,
                InternStrings = InternStrings,
                CustomInternStrings = CustomInternStrings != null ? new HashSet<string>(CustomInternStrings) : null,
                EnableParallelProcessing = EnableParallelProcessing,
                MaxDegreeOfParallelism = MaxDegreeOfParallelism,
                ParallelBatchSize = ParallelBatchSize,
                ParallelQueueDepth = ParallelQueueDepth,
                CancellationToken = CancellationToken,
                ProgressReportInterval = ProgressReportInterval,
                ProgressCallback = ProgressCallback
            };
        }
    }
}
