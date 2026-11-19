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
        /// Reads the next record from the CSV file.
        /// </summary>
        /// <exception cref="OperationCanceledException">Thrown when the <see cref="CsvReaderOptions.CancellationToken"/> is cancelled.</exception>
        public bool Read()
        {
            // Admission is atomic with Close's count-check (same lock): either this read is
            // admitted first (Close then defers the pool return) or Close wins (this throws).
            // A bare check-then-increment left a window where Close could observe zero, return
            // the buffer, and let the admitted read NRE (codex r5).
            lock (_bufferLifecycleLock)
            {
                ThrowIfClosed();
                System.Threading.Interlocked.Increment(ref _activeReads);
            }
            try
            {
                return ReadUnderActiveCount();
            }
            finally
            {
                System.Threading.Interlocked.Decrement(ref _activeReads);
            }
        }

        private bool ReadUnderActiveCount()
        {

            // Reset LumenWorks compatibility flags
            _missingFieldFlag = false;
            _parseErrorFlag = false;

            // Check for cancellation
            _options.CancellationToken.ThrowIfCancellationRequested();

            Initialize();

            bool result;

            // Use parallel pipeline if enabled
            if (_useParallelProcessing)
            {
                result = ReadParallel();
            }
            // Handle buffered first line from no-header initialization (must use line-based parsing)
            else if (_hasBufferedFirstLine)
            {
                result = ReadBufferedFirstLine();
            }
            else
            {
                // Use direct field-by-field parsing (high-performance path)
                result = ReadSequentialDirect();
            }

            // Report progress if enabled
            if (result)
            {
                ReportProgressIfNeeded();
            }
            else
            {
                // Mark end of stream when Read() returns false
                _readReturnedFalse = true;
            }

            return result;
        }

        /// <summary>
        /// Reports progress to the callback if configured and interval has been reached.
        /// </summary>
        private void ReportProgressIfNeeded()
        {
            var callback = _options.ProgressCallback;
            int interval = _options.ProgressReportInterval;

            if (callback == null || interval <= 0)
                return;

            long currentRecord = _currentRecordIndex;
            if (currentRecord - _lastProgressReport >= interval)
            {
                _lastProgressReport = currentRecord;

                long bytesRead = -1;
                if (_underlyingStream != null && _underlyingStream.CanSeek)
                {
                    try { bytesRead = _underlyingStream.Position; }
                    catch { /* Ignore seek errors */ }
                }

                var elapsed = _progressStopwatch?.Elapsed ?? TimeSpan.Zero;
                var progress = new CsvProgress(
                    currentRecord,
                    _currentLineNumber,
                    bytesRead,
                    _totalFileSize,
                    elapsed);

                callback(progress);
            }
        }

        /// <summary>
        /// Handles the special case of reading the buffered first line from no-header initialization.
        /// </summary>
        private bool ReadBufferedFirstLine()
        {
            string line = _bufferedFirstLine;
            _hasBufferedFirstLine = false;
            _bufferedFirstLine = null;

            try
            {
                ParseLine(line);
                _currentRecordIndex++;

                int expectedCount = _maxSourceIndex >= 0 ? _maxSourceIndex + 1 : _fieldsBuffer.Count;
                if (_fieldsBuffer.Count != expectedCount)
                {
                    HandleFieldCountMismatch(line, expectedCount);
                }

                EnsureRecordBufferCapacity(_fieldsBuffer.Count);
                for (int i = 0; i < _fieldsBuffer.Count; i++)
                {
                    _recordBuffer[i] = _fieldsBuffer[i].Value;
                    _quotedBuffer[i] = _fieldsBuffer[i].WasQuoted;
                }
                _currentRecord = _recordBuffer;
                _currentRecordWasQuoted = _quotedBuffer;

                ConvertCurrentRecord();
                return true;
            }
            catch (Exception ex) when (!(ex is CsvParseException parseEx && parseEx.IsMaxErrorsExceeded))
            {
                return HandleParseError(ex, line);
            }
        }

        /// <summary>
        /// High-performance sequential reading using direct field-by-field parsing.
        /// Eliminates intermediate line string allocation for ~10-15% performance improvement.
        /// </summary>
        private bool ReadSequentialDirect()
        {
#if NET8_0_OR_GREATER
            // Ultra-fast path: inline parsing directly to _convertedValues for simple CSV
            if (_useFastParsing && _isInitialized)
            {
                return ReadSequentialUltraFast();
            }
#endif

            while (true)
            {
                try
                {
                    if (!ReadNextRecordDirect())
                    {
                        _currentRecord = null;
                        return false;
                    }

                    _currentRecordIndex++;

                    // Handle field count mismatch
                    int expectedCount = _maxSourceIndex >= 0 ? _maxSourceIndex + 1 : _fieldsBuffer.Count;
                    if (_fieldsBuffer.Count != expectedCount)
                    {
                        HandleFieldCountMismatchDirect(expectedCount);
                    }

                    // Copy fields to record buffer
                    EnsureRecordBufferCapacity(_fieldsBuffer.Count);
                    for (int i = 0; i < _fieldsBuffer.Count; i++)
                    {
                        _recordBuffer[i] = _fieldsBuffer[i].Value;
                        _quotedBuffer[i] = _fieldsBuffer[i].WasQuoted;
                    }
                    _currentRecord = _recordBuffer;
                    _currentRecordWasQuoted = _quotedBuffer;

                    // Convert values to typed objects
                    ConvertCurrentRecord();

                    return true;
                }
                catch (Exception ex) when (!(ex is CsvParseException parseEx && parseEx.IsMaxErrorsExceeded))
                {
                    if (!HandleParseError(ex, null))
                    {
                        // AdvanceToNextLine - continue to next record
                        continue;
                    }
                    // If HandleParseError returns true, an exception was thrown or we should return
                }
            }
        }

#if NET8_0_OR_GREATER
        /// <summary>
        /// Ultra-fast inline parsing for simple CSV files (no quotes, no special options).
        /// Writes directly to _convertedValues, skipping all intermediate buffers.
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveOptimization)]
        private bool ReadSequentialUltraFast()
        {
            char delimChar = _delimiterFirstChar;
            char quoteChar = _options.Quote;
            int columnCount = _columns.Count;
            var values = _convertedValues;

            while (true)
            {
                // Ensure we have data
                if (_bufferPosition >= _bufferLength)
                {
                    if (!RefillBuffer())
                    {
                        _currentRecord = null;
                        return false;
                    }
                }

                // Skip empty lines
                while (_bufferPosition < _bufferLength)
                {
                    char c = _buffer[_bufferPosition];
                    if (c == '\r')
                    {
                        _bufferPosition++;
                        _currentLineNumber++;
                        if (_bufferPosition < _bufferLength && _buffer[_bufferPosition] == '\n')
                            _bufferPosition++;
                        continue;
                    }
                    if (c == '\n')
                    {
                        _bufferPosition++;
                        _currentLineNumber++;
                        continue;
                    }
                    break; // Found start of record
                }

                if (_bufferPosition >= _bufferLength)
                    continue; // Need more data

                // Parse the record directly into _convertedValues
                _currentRecordIndex++;
                int fieldIndex = 0;

                while (fieldIndex < columnCount)
                {
                    if (_bufferPosition >= _bufferLength)
                    {
                        // Buffer exhausted mid-record - fall back to standard path
                        _currentRecordIndex--;
                        _useFastParsing = false;
                        return ReadSequentialDirect();
                    }

                    char c = _buffer[_bufferPosition];

                    // Check for quoted field - fall back to standard path
                    if (c == quoteChar)
                    {
                        _currentRecordIndex--;
                        _useFastParsing = false;
                        return ReadSequentialDirect();
                    }

                    int fieldStart = _bufferPosition;

                    // Use SIMD to find delimiter or newline
                    ReadOnlySpan<char> remaining = _buffer.AsSpan(_bufferPosition, _bufferLength - _bufferPosition);
                    int idx = remaining.IndexOfAny(_fieldTerminators);

                    if (idx < 0)
                    {
                        // No terminator found - fall back to standard path
                        _currentRecordIndex--;
                        _useFastParsing = false;
                        return ReadSequentialDirect();
                    }

                    _bufferPosition += idx;
                    c = _buffer[_bufferPosition];

                    // Create field string
                    int sourceIndex = _columns[fieldIndex].SourceIndex;
                    if (sourceIndex == fieldIndex) // Common case: sequential columns
                    {
                        int length = _bufferPosition - fieldStart;
                        if (length == 0)
                        {
                            values[fieldIndex] = DBNull.Value;
                        }
                        else
                        {
                            values[fieldIndex] = new string(_buffer, fieldStart, length);
                        }
                    }
                    else
                    {
                        // Column mapping is non-trivial - fall back
                        _currentRecordIndex--;
                        _useFastParsing = false;
                        return ReadSequentialDirect();
                    }

                    if (c == delimChar)
                    {
                        _bufferPosition++; // Skip delimiter
                        fieldIndex++;
                    }
                    else // c == '\r' || c == '\n'
                    {
                        // End of record - skip newline
                        if (c == '\r')
                        {
                            _bufferPosition++;
                            if (_bufferPosition < _bufferLength && _buffer[_bufferPosition] == '\n')
                                _bufferPosition++;
                        }
                        else
                        {
                            _bufferPosition++;
                        }
                        fieldIndex++;
                        break;
                    }
                }

                // Fill remaining columns with DBNull
                while (fieldIndex < columnCount)
                {
                    values[fieldIndex] = DBNull.Value;
                    fieldIndex++;
                }

                _currentRecord = _recordBuffer;
                _currentLineNumber++;
                return true;
            }
        }
#endif

    }
}
