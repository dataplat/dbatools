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
        /// Reads the next record directly from the buffer without creating intermediate line strings.
        /// This is the high-performance path that eliminates ~1 string allocation per row.
        /// </summary>
        private bool ReadNextRecordDirect()
        {
            _fieldsBuffer.Clear();
            _endOfRecord = false;

            // Skip empty lines and comments
            while (!_endOfStream)
            {
                // Skip whitespace at start of line if needed
                if (!EnsureBufferData())
                {
                    return _fieldsBuffer.Count > 0;
                }

                // Check for empty line
                char c = _buffer[_bufferPosition];
                if (c == '\r' || c == '\n')
                {
                    SkipNewline();
                    _currentLineNumber++;
                    if (_options.SkipEmptyLines)
                        continue;
                    // Empty line as a record with empty fields is not typical, return no fields
                    return false;
                }

                // Check for comment line
                if (c == _options.Comment)
                {
                    SkipToEndOfLine();
                    _currentLineNumber++;
                    continue;
                }

                // Found start of data - parse fields
                break;
            }

            if (_endOfStream && _bufferPosition >= _bufferLength)
                return false;

            // Parse all fields in the record
            while (!_endOfRecord && !_endOfStream)
            {
                ReadNextFieldDirect();
            }

            _currentLineNumber++;
            return _fieldsBuffer.Count > 0 || !_endOfStream;
        }

        /// <summary>
        /// Reads the next field directly from the buffer.
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private void ReadNextFieldDirect()
        {
            if (!EnsureBufferData())
            {
                // EOF right after a delimiter means an empty trailing field (e.g. "Jane,")
                _fieldsBuffer.Add(new FieldInfo(string.Empty, false));
                _endOfRecord = true;
                return;
            }

            char c = _buffer[_bufferPosition];

            // Check for quoted field after optional smart quote normalization.
            if (NormalizeForQuoteParsing(c) == _options.Quote)
            {
                if (_options.QuoteMode == QuoteMode.Lenient)
                {
                    ReadQuotedFieldDirectLenient();
                }
                else
                {
                    ReadQuotedFieldDirect();
                }
                return;
            }

            // Unquoted field - fast path for single-char delimiter
            if (_singleCharDelimiter)
            {
                ReadUnquotedFieldDirectSingleDelim();
            }
            else
            {
                ReadUnquotedFieldDirectMultiDelim();
            }
        }

        /// <summary>
        /// Fast path for unquoted fields with single-character delimiter.
        /// Uses SIMD-accelerated search on .NET 8+.
        /// </summary>
        private void ReadUnquotedFieldDirectSingleDelim()
        {
            int fieldStart = _bufferPosition;

#if NET8_0_OR_GREATER
            // SIMD-accelerated path for .NET 8+
            if (!_options.NormalizeQuotes)
            {
                ReadUnquotedFieldSimd(fieldStart);
                return;
            }
#endif
            // Scalar path for .NET Framework or when smart quote normalization is enabled
            ReadUnquotedFieldScalar(fieldStart);
        }

#if NET8_0_OR_GREATER
        /// <summary>
        /// SIMD-accelerated unquoted field parsing for .NET 8+.
        /// Uses SearchValues to find delimiter or newline in a single vectorized operation.
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private void ReadUnquotedFieldSimd(int fieldStart)
        {
            char delimChar = _delimiterFirstChar;

            while (true)
            {
                // Create a span from current position to end of buffer
                ReadOnlySpan<char> remaining = _buffer.AsSpan(_bufferPosition, _bufferLength - _bufferPosition);

                // SIMD search for delimiter, \r, or \n
                int idx = remaining.IndexOfAny(_fieldTerminators);

                if (idx >= 0)
                {
                    _bufferPosition += idx;
                    char c = _buffer[_bufferPosition];

                    if (c == delimChar)
                    {
                        // Found delimiter - extract field
                        string value = CreateFieldString(fieldStart, _bufferPosition - fieldStart);
                        _fieldsBuffer.Add(new FieldInfo(value, false));
                        _bufferPosition++; // Skip delimiter
                        return;
                    }

                    // Must be \r or \n - end of record
                    string fieldValue = CreateFieldString(fieldStart, _bufferPosition - fieldStart);
                    _fieldsBuffer.Add(new FieldInfo(fieldValue, false));
                    SkipNewline();
                    _endOfRecord = true;
                    return;
                }

                // No terminator found in current buffer - field spans buffers
                _bufferPosition = _bufferLength;
                ReadUnquotedFieldSpanningBuffer(fieldStart);
                return;
            }
        }
#endif

    }
}
