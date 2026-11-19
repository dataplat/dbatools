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
        /// Reads an unquoted field starting from the current position (used for lenient mode fallback).
        /// </summary>
        private void ReadUnquotedFieldFromCurrentPosition()
        {
            _fieldAccumulator.Clear();

            while (true)
            {
                while (_bufferPosition < _bufferLength)
                {
                    char c = _buffer[_bufferPosition];

                    if (_singleCharDelimiter && c == _delimiterFirstChar)
                    {
                        string value = TryInternString(_fieldAccumulator.ToString());
                        _fieldsBuffer.Add(new FieldInfo(value, false));
                        _bufferPosition++;
                        return;
                    }

                    if (!_singleCharDelimiter && c == _delimiterFirstChar && MatchesDelimiterAtPosition())
                    {
                        string value = TryInternString(_fieldAccumulator.ToString());
                        _fieldsBuffer.Add(new FieldInfo(value, false));
                        _bufferPosition += _options.Delimiter.Length;
                        return;
                    }

                    if (c == '\r' || c == '\n')
                    {
                        string value = TryInternString(_fieldAccumulator.ToString());
                        _fieldsBuffer.Add(new FieldInfo(value, false));
                        SkipNewline();
                        _endOfRecord = true;
                        return;
                    }

                    _fieldAccumulator.Append(c);
                    _bufferPosition++;
                }

                if (!RefillBuffer())
                {
                    string value = TryInternString(_fieldAccumulator.ToString());
                    _fieldsBuffer.Add(new FieldInfo(value, false));
                    _endOfRecord = true;
                    return;
                }
            }
        }

        /// <summary>
        /// Checks if the delimiter matches at the specified position.
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private bool MatchesDelimiterAt(int position)
        {
            string delimiter = _options.Delimiter;
            int delimLength = delimiter.Length;
            if (position + delimLength > _bufferLength)
                return false;

            // Use Span.SequenceEqual for vectorized comparison on multi-char delimiters
            ReadOnlySpan<char> bufferSlice = _buffer.AsSpan(position, delimLength);
            return bufferSlice.SequenceEqual(delimiter.AsSpan());
        }

        /// <summary>
        /// Attempts to peek more data into the buffer without consuming it.
        /// </summary>
        private bool PeekMoreData()
        {
            if (_endOfStream)
                return false;

            int remaining = _bufferLength - _bufferPosition;
            if (remaining > 0)
            {
                // Move remaining data to start of buffer
                Array.Copy(_buffer, _bufferPosition, _buffer, 0, remaining);
            }

            int read = _reader.Read(_buffer, remaining, _buffer.Length - remaining);
            _bufferLength = remaining + read;
            _bufferPosition = 0;

            if (read == 0)
            {
                _endOfStream = true;
                return _bufferLength > 0;
            }

            return true;
        }

        /// <summary>
        /// Checks if there's more data available without moving buffer contents.
        /// Returns true if more data was read, false if at EOF.
        /// </summary>
        private bool PeekMoreDataWithoutMoving()
        {
            if (_endOfStream)
                return false;

            // If there's room in the buffer, try to read more
            if (_bufferLength < _buffer.Length)
            {
                int read = _reader.Read(_buffer, _bufferLength, _buffer.Length - _bufferLength);
                _bufferLength += read;

                if (read == 0)
                {
                    _endOfStream = true;
                    return false;
                }

                return true;
            }

            // Buffer is full - need to compact and read
            int remaining = _bufferLength - _bufferPosition;
            if (remaining > 0)
            {
                Array.Copy(_buffer, _bufferPosition, _buffer, 0, remaining);
            }

            int newRead = _reader.Read(_buffer, remaining, _buffer.Length - remaining);
            _bufferLength = remaining + newRead;
            _bufferPosition = 0;

            if (newRead == 0)
            {
                _endOfStream = true;
                return false;
            }

            return true;
        }

        /// <summary>
        /// Skips whitespace and delimiter after a quoted field.
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private void SkipAfterQuotedField()
        {
            // Skip any whitespace between closing quote and delimiter
            while (_bufferPosition < _bufferLength)
            {
                char c = _buffer[_bufferPosition];

                if (c == '\r' || c == '\n')
                {
                    SkipNewline();
                    _endOfRecord = true;
                    return;
                }

                if (_singleCharDelimiter && c == _delimiterFirstChar)
                {
                    _bufferPosition++;
                    return;
                }

                if (!_singleCharDelimiter && c == _delimiterFirstChar && MatchesDelimiterAtPosition())
                {
                    _bufferPosition += _options.Delimiter.Length;
                    return;
                }

                // Skip whitespace between quote and delimiter (lenient)
                if (char.IsWhiteSpace(c))
                {
                    _bufferPosition++;
                    continue;
                }

                // Unexpected character - in strict mode this would be an error
                // For now, just stop here
                return;
            }

            // End of buffer - try to refill
            if (RefillBuffer())
            {
                SkipAfterQuotedField();
            }
            else
            {
                _endOfRecord = true;
            }
        }

        /// <summary>
        /// Creates a string from a range in the buffer, with optional interning.
        /// Optimized for the common case of non-interned strings.
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private string CreateFieldString(int start, int length)
        {
            if (length == 0)
                return string.Empty;

            // Fast path: no interning or string too long for intern table
            if (_internedStrings == null || length > 10)
            {
                return new string(_buffer, start, length);
            }

            // Check intern table for short strings
            string s = new string(_buffer, start, length);
            if (_internedStrings.TryGetValue(s, out string interned))
                return interned;
            return s;
        }

        /// <summary>
        /// Checks if the delimiter matches at the current buffer position.
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private bool MatchesDelimiterAtPosition()
        {
            string delimiter = _options.Delimiter;
            int delimLength = delimiter.Length;
            if (_bufferPosition + delimLength > _bufferLength)
                return false;

            // Use Span.SequenceEqual for vectorized comparison on multi-char delimiters
            ReadOnlySpan<char> bufferSlice = _buffer.AsSpan(_bufferPosition, delimLength);
            return bufferSlice.SequenceEqual(delimiter.AsSpan());
        }

        /// <summary>
        /// Skips newline characters (handles \r, \n, and \r\n).
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private void SkipNewline()
        {
            if (_bufferPosition >= _bufferLength)
                return;

            char c = _buffer[_bufferPosition];
            if (c == '\r')
            {
                _bufferPosition++;
                // Check for \r\n
                if (_bufferPosition < _bufferLength && _buffer[_bufferPosition] == '\n')
                {
                    _bufferPosition++;
                }
                else if (_bufferPosition >= _bufferLength)
                {
                    // Need to check across buffer boundary
                    if (RefillBuffer() && _bufferPosition < _bufferLength && _buffer[_bufferPosition] == '\n')
                    {
                        _bufferPosition++;
                    }
                }
            }
            else if (c == '\n')
            {
                _bufferPosition++;
            }
        }

        /// <summary>
        /// Skips to the end of the current line (for comments).
        /// </summary>
        private void SkipToEndOfLine()
        {
            while (_bufferPosition < _bufferLength)
            {
                char c = _buffer[_bufferPosition];
                if (c == '\r' || c == '\n')
                {
                    SkipNewline();
                    return;
                }
                _bufferPosition++;
            }

            // Continue skipping if we hit buffer boundary
            if (RefillBuffer())
            {
                SkipToEndOfLine();
            }
        }

        /// <summary>
        /// Ensures there is data available in the buffer. Returns false if end of stream.
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private bool EnsureBufferData()
        {
            if (_bufferPosition < _bufferLength)
                return true;

            return RefillBuffer();
        }

        /// <summary>
        /// Refills the buffer from the reader.
        /// </summary>
        private bool RefillBuffer()
        {
            if (_endOfStream)
                return false;

            _bufferLength = _reader.Read(_buffer, 0, _buffer.Length);
            _bufferPosition = 0;

            if (_bufferLength == 0)
            {
                _endOfStream = true;
                return false;
            }

            return true;
        }

        private bool TryPeekNextChar(out char next)
        {
            if (_bufferPosition + 1 < _bufferLength)
            {
                next = _buffer[_bufferPosition + 1];
                return true;
            }

            if (!PeekMoreDataWithoutMoving())
            {
                next = '\0';
                return false;
            }

            if (_bufferPosition + 1 < _bufferLength)
            {
                next = _buffer[_bufferPosition + 1];
                return true;
            }

            next = '\0';
            return false;
        }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private char NormalizeForQuoteParsing(char c)
        {
            return _options.NormalizeQuotes ? NormalizeSmartQuoteChar(c) : c;
        }

        /// <summary>
        /// Checks if a character is a smart quote.
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private static bool IsSmartQuote(char c)
        {
            return c == LeftSingleQuote || c == RightSingleQuote ||
                   c == LeftDoubleQuote || c == RightDoubleQuote;
        }

    }
}
