using System;
using System.Buffers;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Data;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Dataplat.Dbatools.Csv.Compression;
using Dataplat.Dbatools.Csv.TypeConverters;

namespace Dataplat.Dbatools.Csv.Reader
{
    public sealed partial class CsvDataReader
    {

        /// <summary>
        /// Creates a new CSV reader for the specified file.
        /// </summary>
        public CsvDataReader(string filePath) : this(filePath, null)
        {
        }

        /// <summary>
        /// Creates a new CSV reader for the specified file with options.
        /// </summary>
        public CsvDataReader(string filePath, CsvReaderOptions options)
        {
            if (string.IsNullOrEmpty(filePath))
                throw new ArgumentNullException(nameof(filePath));

            _options = options ?? new CsvReaderOptions();

            // Get file size for progress reporting before opening
            try
            {
                var fileInfo = new FileInfo(filePath);
                if (fileInfo.Exists)
                    _totalFileSize = fileInfo.Length;
            }
            catch { /* Ignore file info errors */ }

            Stream stream = CompressionHelper.OpenFileForReading(filePath, _options.AutoDetectCompression, _options.MaxDecompressedSize);
            _underlyingStream = stream;
            _reader = new StreamReader(stream, _options.Encoding, detectEncodingFromByteOrderMarks: true,
                bufferSize: _options.BufferSize);
            _ownsReader = true;

            InitializeBuffers();
            InitializeProgressTracking();
            _columns = new List<CsvColumn>();
            _staticColumns = _options.StaticColumns != null ? new List<StaticColumn>(_options.StaticColumns) : new List<StaticColumn>();
            _parseErrors = _options.CollectParseErrors ? new List<CsvParseError>() : null;
            _headerNameCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        }

        /// <summary>
        /// Creates a new CSV reader for the specified TextReader.
        /// </summary>
        public CsvDataReader(TextReader reader, CsvReaderOptions options = null)
        {
            _reader = reader ?? throw new ArgumentNullException(nameof(reader));
            _options = options ?? new CsvReaderOptions();
            _ownsReader = false;

            InitializeBuffers();
            InitializeProgressTracking();
            _columns = new List<CsvColumn>();
            _staticColumns = _options.StaticColumns != null ? new List<StaticColumn>(_options.StaticColumns) : new List<StaticColumn>();
            _parseErrors = _options.CollectParseErrors ? new List<CsvParseError>() : null;
            _headerNameCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        }

        /// <summary>
        /// Creates a new CSV reader for the specified Stream.
        /// </summary>
        public CsvDataReader(Stream stream, CsvReaderOptions options = null)
        {
            if (stream == null)
                throw new ArgumentNullException(nameof(stream));

            _options = options ?? new CsvReaderOptions();

            // Try to get stream length for progress reporting
            if (stream.CanSeek)
            {
                try { _totalFileSize = stream.Length; }
                catch { /* Ignore errors */ }
            }

            CompressionType compressionType = _options.AutoDetectCompression
                ? CompressionHelper.DetectFromStream(stream)
                : _options.CompressionType;

            Stream decompressedStream = CompressionHelper.WrapForDecompression(stream, compressionType, _options.MaxDecompressedSize);
            _underlyingStream = decompressedStream;
            _reader = new StreamReader(decompressedStream, _options.Encoding, detectEncodingFromByteOrderMarks: true,
                bufferSize: _options.BufferSize);
            _ownsReader = true;

            InitializeBuffers();
            InitializeProgressTracking();
            _columns = new List<CsvColumn>();
            _staticColumns = _options.StaticColumns != null ? new List<StaticColumn>(_options.StaticColumns) : new List<StaticColumn>();
            _parseErrors = _options.CollectParseErrors ? new List<CsvParseError>() : null;
            _headerNameCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        }

        private void InitializeBuffers()
        {
            // Use ArrayPool for the main read buffer
            _buffer = ArrayPool<char>.Shared.Rent(_options.BufferSize);
            _bufferFromPool = true;
            _lineBuilder = new StringBuilder(512);
            _fieldsBuffer = new List<FieldInfo>(64);
            _quotedFieldBuilder = new StringBuilder(256);

            // Initialize direct field parsing state
            _delimiterFirstChar = _options.Delimiter[0];
            _singleCharDelimiter = _options.Delimiter.Length == 1;
            _fieldAccumulator = new StringBuilder(256);

#if NET8_0_OR_GREATER
            // Create SIMD-accelerated search values for field terminators
            // For single-char delimiter: search for delimiter, \r, \n
            if (_singleCharDelimiter)
            {
                _fieldTerminators = System.Buffers.SearchValues.Create(
                    new char[] { _delimiterFirstChar, '\r', '\n' });
            }
#endif

            // Initialize string interning if enabled
            if (_options.InternStrings)
            {
                InitializeStringInterning();
            }
        }

        private void InitializeStringInterning()
        {
            // Start with common values that frequently appear in CSV files
            _internedStrings = new HashSet<string>(StringComparer.Ordinal)
            {
                string.Empty,
                "NULL",
                "null",
                "Null",
                "N/A",
                "n/a",
                "NA",
                "na",
                "-",
                "0",
                "1",
                "true",
                "True",
                "TRUE",
                "false",
                "False",
                "FALSE",
                "Yes",
                "yes",
                "YES",
                "No",
                "no",
                "NO",
                "Y",
                "N",
                "y",
                "n"
            };

            // Add custom intern strings if specified
            if (_options.CustomInternStrings != null)
            {
                foreach (var s in _options.CustomInternStrings)
                {
                    _internedStrings.Add(s);
                }
            }

            // Intern the null value if configured
            if (_options.NullValue != null)
            {
                _internedStrings.Add(_options.NullValue);
            }
        }

        private void InitializeProgressTracking()
        {
            // Start stopwatch if progress reporting is enabled
            if (_options.ProgressCallback != null && _options.ProgressReportInterval > 0)
            {
                _progressStopwatch = Stopwatch.StartNew();
            }
        }

        /// <summary>
        /// Attempts to return an interned string for the given value.
        /// Fast path rejects strings that are too long for interning.
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private string TryInternString(string value)
        {
            // Fast path: skip lookup if interning disabled or string too long
            // Most interned strings are short (null, true, false, empty, etc.)
            if (_internedStrings == null || value.Length > 10)
                return value;

            if (_internedStrings.TryGetValue(value, out string interned))
                return interned;

            return value;
        }

    }
}
