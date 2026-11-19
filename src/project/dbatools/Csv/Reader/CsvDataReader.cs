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
    /// <summary>
    /// High-performance CSV reader that implements IDataReader for SqlBulkCopy compatibility.
    /// Supports multi-character delimiters, type conversion, compression, error tracking, and static columns.
    /// Uses Span-based parsing and ArrayPool for maximum performance.
    /// </summary>
    /// <remarks>
    /// <para><b>Thread-Safety Guarantees:</b></para>
    /// <para>
    /// When parallel processing is enabled (<see cref="CsvReaderOptions.EnableParallelProcessing"/>),
    /// this class provides the following thread-safety guarantees:
    /// </para>
    /// <list type="bullet">
    /// <item><description>
    /// <see cref="GetValue"/> and <see cref="GetValues"/> are thread-safe and can be called
    /// from multiple threads concurrently while <see cref="Read"/> is executing on another thread.
    /// These methods return consistent snapshots of the current record's data.
    /// </description></item>
    /// <item><description>
    /// <see cref="CurrentRecordIndex"/> is safe to read from any thread without torn reads.
    /// </description></item>
    /// <item><description>
    /// <see cref="Close"/> and <see cref="Dispose"/> can be called from any thread and will
    /// safely stop the parallel processing pipeline.
    /// </description></item>
    /// </list>
    /// <para>
    /// <b>Important:</b> While the above methods are thread-safe for concurrent reads,
    /// the values returned represent a snapshot that may change after the next <see cref="Read"/> call.
    /// Only one thread should call <see cref="Read"/> at a time.
    /// </para>
    /// <para>
    /// In sequential mode (parallel processing disabled), the class is not thread-safe.
    /// All access should be from a single thread.
    /// </para>
    /// </remarks>
    public sealed partial class CsvDataReader : IDataReader
    {

        private readonly TextReader _reader;
        private readonly CsvReaderOptions _options;
        private readonly bool _ownsReader;
        private readonly List<CsvColumn> _columns;
        private readonly List<StaticColumn> _staticColumns;
        private readonly List<CsvParseError> _parseErrors;

        // Thread-safety note: These fields are accessed from the main thread during Read() and from
        // user threads via GetValue()/GetValues(). We use volatile for reference visibility and
        // lock (_resultLock) for atomic operations involving _convertedValues.
        private volatile string[] _currentRecord;
        private volatile bool[] _currentRecordWasQuoted;  // Track which fields were quoted for null vs empty
        private string[] _recordBuffer;
        private bool[] _quotedBuffer;
        private volatile object[] _convertedValues;
        private bool _isInitialized;
        private volatile bool _isClosed;
        private long _currentRecordIndex = -1;
        private long _currentLineNumber;

        // LumenWorks compatibility flags - reset at start of each Read()
        private bool _missingFieldFlag;
        private bool _parseErrorFlag;
        private bool _readReturnedFalse;  // True after Read() returns false (EndOfStream)

        // Buffer for first data row when no header row (needed to create columns during Initialize)
        private string _bufferedFirstLine;
        private bool _hasBufferedFirstLine;

        // Buffer for efficient reading - using ArrayPool
        private char[] _buffer;
        // Dispose-during-read contract (TB-012): Read() holds an active-read count; Close
        // returns the pooled _buffer (and nulls the field) ONLY when no read is active,
        // otherwise it defers - the array is simply left to the GC, so an in-flight read can
        // never observe a null field, never writes through a returned array (cross-renter
        // corruption), and terminates via the disposed inner reader's own ObjectDisposedException
        // at its next refill. The lock orders the count check against the return.
        private readonly object _bufferLifecycleLock = new object();
        private int _activeReads;
        private bool _bufferFromPool;
        private int _bufferLength;
        private int _bufferPosition;
        private bool _endOfStream;

        // Field parsing state
        private StringBuilder _lineBuilder;
        private List<FieldInfo> _fieldsBuffer;

        // Header name tracking for duplicate detection
        private readonly Dictionary<string, int> _headerNameCounts;

        // Cached max source index to avoid LINQ per-row (volatile for thread visibility in parallel mode)
        private volatile int _maxSourceIndex = -1;

        // Reusable StringBuilder for quoted field parsing to reduce allocations
        private StringBuilder _quotedFieldBuilder;

        // String interning for common values to reduce allocations
        private HashSet<string> _internedStrings;

        // Smart quote characters for normalization
        private const char LeftSingleQuote = '\u2018';  // '
        private const char RightSingleQuote = '\u2019'; // '
        private const char LeftDoubleQuote = '\u201C';  // "
        private const char RightDoubleQuote = '\u201D'; // "

        // Direct field parsing state (eliminates intermediate line string allocation)
        private char _delimiterFirstChar;              // First char of delimiter for fast check
        private bool _singleCharDelimiter;             // True if delimiter is single char (common case)
        private bool _endOfRecord;                     // True when we've hit newline
        private StringBuilder _fieldAccumulator;       // For fields spanning buffer boundaries

#if NET8_0_OR_GREATER
        // SIMD-accelerated search for delimiter and newlines (NET 8+ only)
        private System.Buffers.SearchValues<char> _fieldTerminators;
#endif

        // Fast path optimization flags - determined during initialization
        private bool _useFastConversion;               // True when simple string-only conversion can be used
        private bool _useFastParsing;                  // True when ultra-fast inline parsing can be used

        /// <summary>
        /// Holds information about a parsed field including its value and whether it was quoted.
        /// </summary>
        private struct FieldInfo
        {
            public string Value;
            public bool WasQuoted;

            public FieldInfo(string value, bool wasQuoted)
            {
                Value = value;
                WasQuoted = wasQuoted;
            }
        }

        /// <summary>
        /// Represents a line read from the input with its metadata.
        /// </summary>
        private struct LineData
        {
            public string Line;
            public long LineNumber;
            public long RecordIndex;

            public LineData(string line, long lineNumber, long recordIndex)
            {
                Line = line;
                LineNumber = lineNumber;
                RecordIndex = recordIndex;
            }
        }

        /// <summary>
        /// Represents a fully parsed and converted record ready for consumption.
        /// </summary>
        private sealed class ParsedRecord
        {
            public object[] Values;
            public long RecordIndex;
            public long LineNumber;
            public CsvParseError Error;

            public ParsedRecord(object[] values, long recordIndex, long lineNumber)
            {
                Values = values;
                RecordIndex = recordIndex;
                LineNumber = lineNumber;
                Error = null;
            }

            public ParsedRecord(CsvParseError error, long recordIndex, long lineNumber)
            {
                Values = null;
                RecordIndex = recordIndex;
                LineNumber = lineNumber;
                Error = error;
            }
        }

        // Parallel processing state (volatile for thread visibility across main/worker threads)
        private volatile bool _useParallelProcessing;
        private BlockingCollection<LineData> _lineQueue;
        private BlockingCollection<ParsedRecord> _resultQueue;
        private Thread _producerThread;
        private Thread[] _workerThreads;
        private CancellationTokenSource _cancellationSource;
        private volatile Exception _pipelineException;
        private int _activeWorkers;

        // Thread-safe error collection for parallel mode
        private ConcurrentQueue<CsvParseError> _parallelParseErrors;

        // Progress tracking
        private Stopwatch _progressStopwatch;
        private long _totalFileSize = -1;
        private long _lastProgressReport;
        private Stream _underlyingStream;

        // Result queue for ordered delivery
        private readonly object _resultLock = new object();
        private long _nextExpectedRecordIndex;
        private readonly SortedDictionary<long, ParsedRecord> _pendingResults = new SortedDictionary<long, ParsedRecord>();
        private ParsedRecord _currentParsedRecord;

    }
}
