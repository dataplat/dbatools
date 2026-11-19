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
        /// Scalar (non-SIMD) unquoted field parsing. Used on .NET Framework
        /// and when smart quote normalization is enabled.
        /// </summary>
        private void ReadUnquotedFieldScalar(int fieldStart)
        {
            char delimChar = _delimiterFirstChar;

            // Scan for delimiter, newline, or end of buffer
            while (_bufferPosition < _bufferLength)
            {
                char c = _buffer[_bufferPosition];

                if (c == delimChar)
                {
                    // Found delimiter - extract field
                    string value = CreateFieldString(fieldStart, _bufferPosition - fieldStart);
                    _fieldsBuffer.Add(new FieldInfo(value, false));
                    _bufferPosition++; // Skip delimiter
                    return;
                }

                if (c == '\r' || c == '\n')
                {
                    // End of record
                    string value = CreateFieldString(fieldStart, _bufferPosition - fieldStart);
                    _fieldsBuffer.Add(new FieldInfo(value, false));
                    SkipNewline();
                    _endOfRecord = true;
                    return;
                }

                // Handle smart quotes if enabled
                if (_options.NormalizeQuotes && IsSmartQuote(c))
                {
                    // Need to handle smart quote normalization - fall back to accumulator
                    ReadUnquotedFieldWithNormalization(fieldStart);
                    return;
                }

                _bufferPosition++;
            }

            // Hit end of buffer - field may span buffers
            ReadUnquotedFieldSpanningBuffer(fieldStart);
        }

        /// <summary>
        /// Handles unquoted fields that span buffer boundaries.
        /// </summary>
        private void ReadUnquotedFieldSpanningBuffer(int fieldStart)
        {
            _fieldAccumulator.Clear();

            // Append what we have so far
            if (_bufferPosition > fieldStart)
            {
                _fieldAccumulator.Append(_buffer, fieldStart, _bufferPosition - fieldStart);
            }

            char delimChar = _delimiterFirstChar;

            // Continue reading until we find delimiter or newline
            while (true)
            {
                if (!RefillBuffer())
                {
                    // End of stream - whatever we accumulated is the field
                    string value = TryInternString(_fieldAccumulator.ToString());
                    _fieldsBuffer.Add(new FieldInfo(value, false));
                    _endOfRecord = true;
                    return;
                }

                while (_bufferPosition < _bufferLength)
                {
                    char c = _buffer[_bufferPosition];

                    if (_singleCharDelimiter && c == delimChar)
                    {
                        string value = TryInternString(_fieldAccumulator.ToString());
                        _fieldsBuffer.Add(new FieldInfo(value, false));
                        _bufferPosition++;
                        return;
                    }

                    if (!_singleCharDelimiter && c == delimChar && MatchesDelimiterAtPosition())
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

                    // Handle smart quote normalization
                    if (_options.NormalizeQuotes)
                    {
                        c = NormalizeSmartQuoteChar(c);
                    }

                    _fieldAccumulator.Append(c);
                    _bufferPosition++;
                }
            }
        }

        /// <summary>
        /// Handles unquoted fields with smart quote normalization.
        /// </summary>
        private void ReadUnquotedFieldWithNormalization(int fieldStart)
        {
            _fieldAccumulator.Clear();

            // Copy and normalize what we've seen so far
            for (int i = fieldStart; i < _bufferPosition; i++)
            {
                _fieldAccumulator.Append(NormalizeSmartQuoteChar(_buffer[i]));
            }

            char delimChar = _delimiterFirstChar;

            while (true)
            {
                while (_bufferPosition < _bufferLength)
                {
                    char c = _buffer[_bufferPosition];

                    if (_singleCharDelimiter && c == delimChar)
                    {
                        string value = TryInternString(_fieldAccumulator.ToString());
                        _fieldsBuffer.Add(new FieldInfo(value, false));
                        _bufferPosition++;
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

                    _fieldAccumulator.Append(NormalizeSmartQuoteChar(c));
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
        /// Path for unquoted fields with multi-character delimiter.
        /// </summary>
        private void ReadUnquotedFieldDirectMultiDelim()
        {
            int fieldStart = _bufferPosition;
            char delimFirstChar = _delimiterFirstChar;
            int delimLength = _options.Delimiter.Length;

            while (_bufferPosition < _bufferLength)
            {
                char c = _buffer[_bufferPosition];

                if (c == delimFirstChar && _bufferPosition + delimLength <= _bufferLength)
                {
                    if (MatchesDelimiterAtPosition())
                    {
                        string value = CreateFieldString(fieldStart, _bufferPosition - fieldStart);
                        _fieldsBuffer.Add(new FieldInfo(value, false));
                        _bufferPosition += delimLength;
                        return;
                    }
                }

                if (c == '\r' || c == '\n')
                {
                    string value = CreateFieldString(fieldStart, _bufferPosition - fieldStart);
                    _fieldsBuffer.Add(new FieldInfo(value, false));
                    SkipNewline();
                    _endOfRecord = true;
                    return;
                }

                if (_options.NormalizeQuotes && IsSmartQuote(c))
                {
                    ReadUnquotedFieldWithNormalization(fieldStart);
                    return;
                }

                _bufferPosition++;
            }

            // Hit end of buffer
            ReadUnquotedFieldSpanningBuffer(fieldStart);
        }
    }
}
