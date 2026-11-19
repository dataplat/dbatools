using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading;

namespace Dataplat.Dbatools.Csv.Reader
{
    /// <summary>
    /// Provides SQL Server schema inference for CSV files.
    /// Analyzes CSV data to determine optimal column types for database import.
    /// </summary>
    public static partial class CsvSchemaInference
    {
        /// <summary>
        /// Default number of rows to sample for schema inference.
        /// </summary>
        public const int DefaultSampleRows = 1000;

        /// <summary>
        /// Default progress report interval (percentage points).
        /// </summary>
        private const double ProgressReportInterval = 0.01; // 1%


        /// <summary>
        /// Infers SQL Server schema by sampling the first N rows of a CSV file.
        /// Fast but has a small risk if data patterns change after the sample.
        /// </summary>
        /// <param name="path">Path to the CSV file.</param>
        /// <param name="options">CSV reader options (delimiter, encoding, etc.). If null, defaults are used.</param>
        /// <param name="sampleRows">Number of rows to sample. Default is 1000.</param>
        /// <returns>List of inferred column definitions.</returns>
        /// <exception cref="ArgumentNullException">Thrown when path is null.</exception>
        /// <exception cref="FileNotFoundException">Thrown when the file does not exist.</exception>
        public static List<InferredColumn> InferSchemaFromSample(string path, CsvReaderOptions options = null, int sampleRows = DefaultSampleRows)
        {
            if (path == null)
                throw new ArgumentNullException(nameof(path));
            if (!File.Exists(path))
                throw new FileNotFoundException("CSV file not found.", path);
            if (sampleRows < 1)
                throw new ArgumentOutOfRangeException(nameof(sampleRows), "Sample rows must be at least 1.");

            options = options ?? new CsvReaderOptions();

            // Create options copy to avoid modifying the caller's options
            var inferOptions = options.Clone();
            inferOptions.ProgressCallback = null;

            using (var reader = new CsvDataReader(path, inferOptions))
            {
                return InferSchemaCore(reader, sampleRows, null, inferOptions.CancellationToken);
            }
        }

        /// <summary>
        /// Infers SQL Server schema by sampling the first N rows from a stream.
        /// </summary>
        /// <param name="stream">Stream containing CSV data.</param>
        /// <param name="options">CSV reader options.</param>
        /// <param name="sampleRows">Number of rows to sample.</param>
        /// <param name="cancellationToken">Cancellation token.</param>
        /// <returns>List of inferred column definitions.</returns>
        public static List<InferredColumn> InferSchemaFromSample(Stream stream, CsvReaderOptions options = null, int sampleRows = DefaultSampleRows, CancellationToken cancellationToken = default)
        {
            if (stream == null)
                throw new ArgumentNullException(nameof(stream));
            if (sampleRows < 1)
                throw new ArgumentOutOfRangeException(nameof(sampleRows), "Sample rows must be at least 1.");

            options = options ?? new CsvReaderOptions();

            var inferOptions = options.Clone();
            inferOptions.CancellationToken = cancellationToken;
            inferOptions.ProgressCallback = null;

            using (var reader = new CsvDataReader(stream, inferOptions))
            {
                return InferSchemaCore(reader, sampleRows, null, cancellationToken);
            }
        }

        /// <summary>
        /// Infers SQL Server schema by sampling the first N rows from a TextReader.
        /// </summary>
        /// <param name="textReader">TextReader containing CSV data.</param>
        /// <param name="options">CSV reader options.</param>
        /// <param name="sampleRows">Number of rows to sample.</param>
        /// <param name="cancellationToken">Cancellation token.</param>
        /// <returns>List of inferred column definitions.</returns>
        public static List<InferredColumn> InferSchemaFromSample(TextReader textReader, CsvReaderOptions options = null, int sampleRows = DefaultSampleRows, CancellationToken cancellationToken = default)
        {
            if (textReader == null)
                throw new ArgumentNullException(nameof(textReader));
            if (sampleRows < 1)
                throw new ArgumentOutOfRangeException(nameof(sampleRows), "Sample rows must be at least 1.");

            options = options ?? new CsvReaderOptions();

            var inferOptions = options.Clone();
            inferOptions.CancellationToken = cancellationToken;
            inferOptions.ProgressCallback = null;

            using (var reader = new CsvDataReader(textReader, inferOptions))
            {
                return InferSchemaCore(reader, sampleRows, null, cancellationToken);
            }
        }



        /// <summary>
        /// Infers SQL Server schema by scanning the entire CSV file.
        /// Slower but guarantees no import failures due to type mismatches.
        /// </summary>
        /// <param name="path">Path to the CSV file.</param>
        /// <param name="options">CSV reader options (delimiter, encoding, etc.). If null, defaults are used.</param>
        /// <param name="progressCallback">Optional callback receiving progress (0.0 to 1.0).</param>
        /// <param name="cancellationToken">Cancellation token.</param>
        /// <returns>List of inferred column definitions.</returns>
        /// <exception cref="ArgumentNullException">Thrown when path is null.</exception>
        /// <exception cref="FileNotFoundException">Thrown when the file does not exist.</exception>
        public static List<InferredColumn> InferSchema(string path, CsvReaderOptions options = null, Action<double> progressCallback = null, CancellationToken cancellationToken = default)
        {
            if (path == null)
                throw new ArgumentNullException(nameof(path));
            if (!File.Exists(path))
                throw new FileNotFoundException("CSV file not found.", path);

            options = options ?? new CsvReaderOptions();

            // Get file size for progress reporting
            long fileSize = new FileInfo(path).Length;

            var inferOptions = options.Clone();
            inferOptions.CancellationToken = cancellationToken;
            inferOptions.ProgressCallback = null;

            using (var reader = new CsvDataReader(path, inferOptions))
            {
                return InferSchemaCore(reader, int.MaxValue, WrapProgressCallback(progressCallback, fileSize), cancellationToken);
            }
        }

        /// <summary>
        /// Infers SQL Server schema by scanning the entire stream.
        /// </summary>
        /// <param name="stream">Stream containing CSV data.</param>
        /// <param name="options">CSV reader options.</param>
        /// <param name="progressCallback">Optional callback receiving progress (0.0 to 1.0).</param>
        /// <param name="cancellationToken">Cancellation token.</param>
        /// <returns>List of inferred column definitions.</returns>
        public static List<InferredColumn> InferSchema(Stream stream, CsvReaderOptions options = null, Action<double> progressCallback = null, CancellationToken cancellationToken = default)
        {
            if (stream == null)
                throw new ArgumentNullException(nameof(stream));

            options = options ?? new CsvReaderOptions();

            // Try to get stream length for progress
            long streamLength = -1;
            try
            {
                if (stream.CanSeek)
                {
                    streamLength = stream.Length;
                }
            }
            catch
            {
                // Ignore - some streams don't support Length
            }

            var inferOptions = options.Clone();
            inferOptions.CancellationToken = cancellationToken;
            inferOptions.ProgressCallback = null;

            using (var reader = new CsvDataReader(stream, inferOptions))
            {
                return InferSchemaCore(reader, int.MaxValue, WrapProgressCallback(progressCallback, streamLength), cancellationToken);
            }
        }

        /// <summary>
        /// Infers SQL Server schema by scanning the entire TextReader content.
        /// Note: Progress callback will not report accurate percentages for TextReader.
        /// </summary>
        /// <param name="textReader">TextReader containing CSV data.</param>
        /// <param name="options">CSV reader options.</param>
        /// <param name="progressCallback">Optional callback (will not provide accurate progress for TextReader).</param>
        /// <param name="cancellationToken">Cancellation token.</param>
        /// <returns>List of inferred column definitions.</returns>
        public static List<InferredColumn> InferSchema(TextReader textReader, CsvReaderOptions options = null, Action<double> progressCallback = null, CancellationToken cancellationToken = default)
        {
            if (textReader == null)
                throw new ArgumentNullException(nameof(textReader));

            options = options ?? new CsvReaderOptions();

            var inferOptions = options.Clone();
            inferOptions.CancellationToken = cancellationToken;
            inferOptions.ProgressCallback = null;

            using (var reader = new CsvDataReader(textReader, inferOptions))
            {
                // For TextReader, we can't report accurate progress since we don't know total size
                return InferSchemaCore(reader, int.MaxValue, null, cancellationToken);
            }
        }



        /// <summary>
        /// Core implementation for schema inference using CsvDataReader.
        /// </summary>
        private static List<InferredColumn> InferSchemaCore(CsvDataReader csvReader, int maxRows, Action<long, long> progressCallback, CancellationToken cancellationToken)
        {
            var result = new List<InferredColumn>();
            ColumnTypeAnalyzer[] analyzers = null;

            long rowCount = 0;
            long lastProgressReport = 0;
            const long progressInterval = 10000; // Report every 10K rows

            while (csvReader.Read() && rowCount < maxRows)
            {
                cancellationToken.ThrowIfCancellationRequested();

                // Initialize analyzers on first row (after Read() populates field count)
                if (analyzers == null)
                {
                    int fieldCount = csvReader.FieldCount;
                    analyzers = new ColumnTypeAnalyzer[fieldCount];

                    var readerOptions = GetReaderOptions(csvReader);
                    for (int i = 0; i < fieldCount; i++)
                    {
                        string columnName = csvReader.GetName(i);
                        analyzers[i] = new ColumnTypeAnalyzer(
                            columnName,
                            i,
                            readerOptions != null ? readerOptions.DateTimeFormats : null,
                            readerOptions != null ? readerOptions.Culture : System.Globalization.CultureInfo.InvariantCulture);
                    }
                }

                // Analyze each field
                for (int i = 0; i < analyzers.Length; i++)
                {
                    string value = csvReader.GetString(i);
                    analyzers[i].AnalyzeValue(value);
                }

                rowCount++;

                // Report progress periodically
                if (progressCallback != null && rowCount - lastProgressReport >= progressInterval)
                {
                    progressCallback(rowCount, maxRows < int.MaxValue ? maxRows : -1);
                    lastProgressReport = rowCount;
                }
            }

            // Build results
            if (analyzers != null)
            {
                foreach (var analyzer in analyzers)
                {
                    result.Add(analyzer.GetInferredColumn());
                }
            }
            else if (csvReader.FieldCount > 0)
            {
                // Headers only (no data rows) - return varchar(1) NULL for each column
                for (int i = 0; i < csvReader.FieldCount; i++)
                {
                    result.Add(new InferredColumn
                    {
                        ColumnName = csvReader.GetName(i),
                        Ordinal = i,
                        SqlDataType = "varchar(1)",
                        IsNullable = true,
                        TotalCount = 0,
                        NonNullCount = 0,
                        MaxLength = 0
                    });
                }
            }

            // Final progress report
            if (progressCallback != null)
            {
                progressCallback(rowCount, rowCount);
            }

            return result;
        }

        /// <summary>
        /// Gets the options from a CsvDataReader.
        /// </summary>
        private static CsvReaderOptions GetReaderOptions(CsvDataReader reader)
        {
            return reader.Options;
        }

        /// <summary>
        /// Wraps a user progress callback with file-size based progress calculation.
        /// </summary>
        private static Action<long, long> WrapProgressCallback(Action<double> userCallback, long totalSize)
        {
            if (userCallback == null)
                return null;

            double lastReported = -1;

            return (rowsRead, totalRows) =>
            {
                double progress;
                if (totalRows > 0)
                {
                    progress = (double)rowsRead / totalRows;
                }
                else if (totalSize > 0)
                {
                    // Estimate based on rows read (assume average row size)
                    // This is rough but better than nothing
                    progress = Math.Min(0.99, rowsRead * 100.0 / totalSize);
                }
                else
                {
                    // Can't calculate progress
                    return;
                }

                if (progress > 1.0) progress = 1.0;

                // Only report if progress changed significantly
                if (progress - lastReported >= ProgressReportInterval || progress >= 1.0)
                {
                    userCallback(progress);
                    lastReported = progress;
                }
            };
        }

    }
}
