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
        /// Reads a quoted field directly from the buffer.
        /// </summary>
        private void ReadQuotedFieldDirect()
        {
            _bufferPosition++; // Skip opening quote
            _quotedFieldBuilder.Clear();

            char quote = _options.Quote;
            char escape = _options.Escape;
            int quotedLength = 0;

            while (true)
            {
                if (!EnsureBufferData())
                {
                    // Unterminated quoted field at end of file
                    string value = TryInternString(_quotedFieldBuilder.ToString());
                    _fieldsBuffer.Add(new FieldInfo(value, true));
                    _endOfRecord = true;
                    return;
                }

                char c = _buffer[_bufferPosition];
                char normalized = NormalizeForQuoteParsing(c);

                // Handle escaped quotes (RFC 4180: "" or custom escape like \")
                char peekNext;
                if (normalized == escape && TryPeekNextChar(out peekNext))
                {
                    if (NormalizeForQuoteParsing(peekNext) == quote)
                    {
                        _quotedFieldBuilder.Append(quote);
                        _bufferPosition += 2;
                        quotedLength += 2;
                        CheckQuotedFieldLength(quotedLength);
                        continue;
                    }
                }

                // Check for closing quote (including smart quotes when NormalizeQuotes is enabled)
                if (normalized == quote)
                {
                    // Found closing quote
                    _bufferPosition++; // Skip closing quote

                    // Skip to delimiter or newline
                    SkipAfterQuotedField();

                    string value = TryInternString(_quotedFieldBuilder.ToString());
                    _fieldsBuffer.Add(new FieldInfo(value, true));
                    return;
                }

                _quotedFieldBuilder.Append(normalized);
                _bufferPosition++;
                quotedLength++;
                CheckQuotedFieldLength(quotedLength);
            }
        }

        /// <summary>
        /// Reads a quoted field in lenient mode - if the quote doesn't properly close,
        /// treat it as a literal character and return the whole field as unquoted.
        /// </summary>
        private void ReadQuotedFieldDirectLenient()
        {
            char openingQuote = NormalizeForQuoteParsing(_buffer[_bufferPosition]);
            _bufferPosition++; // Skip opening quote
            _quotedFieldBuilder.Clear();

            // In lenient mode, we also track the raw content in case we need to return it as unquoted
            _fieldAccumulator.Clear();
            _fieldAccumulator.Append(openingQuote); // Include opening quote in raw content

            char quote = _options.Quote;
            char escape = _options.Escape;
            int quotedLength = 0;

            while (true)
            {
                if (!EnsureBufferData())
                {
                    // EOF - return accumulated raw content as unquoted (no valid closing quote found)
                    string value = TryInternString(_fieldAccumulator.ToString());
                    _fieldsBuffer.Add(new FieldInfo(value, false));
                    _endOfRecord = true;
                    return;
                }

                char c = _buffer[_bufferPosition];
                char normalized = NormalizeForQuoteParsing(c);

                // Handle escaped quotes (RFC 4180: "" or backslash escape)
                char peekNext;
                if (normalized == escape && TryPeekNextChar(out peekNext))
                {
                    if (NormalizeForQuoteParsing(peekNext) == quote)
                    {
                        _quotedFieldBuilder.Append(quote);
                        _fieldAccumulator.Append(normalized);
                        _fieldAccumulator.Append(NormalizeForQuoteParsing(peekNext));
                        _bufferPosition += 2;
                        quotedLength += 2;
                        CheckQuotedFieldLength(quotedLength);
                        continue;
                    }
                }

                // Backslash escape in lenient mode
                if (c == '\\' && TryPeekNextChar(out peekNext))
                {
                    if (NormalizeForQuoteParsing(peekNext) == quote)
                    {
                        _quotedFieldBuilder.Append(quote);
                        _fieldAccumulator.Append(c);
                        _fieldAccumulator.Append(NormalizeForQuoteParsing(peekNext));
                        _bufferPosition += 2;
                        quotedLength += 2;
                        CheckQuotedFieldLength(quotedLength);
                        continue;
                    }
                }

                // Check for closing quote
                if (normalized == quote)
                {
                    int afterQuote = _bufferPosition + 1;

                    // Validate closing quote position - must be followed by delimiter, newline, or EOF
                    if (afterQuote >= _bufferLength)
                    {
                        // Need more data to validate
                        bool hadMoreData = PeekMoreDataWithoutMoving();
                        if (!hadMoreData)
                        {
                            // EOF - this is a valid closing quote
                            _bufferPosition++; // Skip closing quote
                            string value = TryInternString(_quotedFieldBuilder.ToString());
                            _fieldsBuffer.Add(new FieldInfo(value, true));
                            _endOfRecord = true;
                            return;
                        }
                        // There's more data - continue checking
                        afterQuote = _bufferPosition + 1;
                    }

                    if (afterQuote < _bufferLength)
                    {
                        char afterChar = _buffer[afterQuote];

                        // Valid close: followed by delimiter
                        if ((_singleCharDelimiter && afterChar == _delimiterFirstChar) ||
                            (!_singleCharDelimiter && afterChar == _delimiterFirstChar && MatchesDelimiterAt(afterQuote)))
                        {
                            _bufferPosition++; // Skip closing quote
                            _bufferPosition += _singleCharDelimiter ? 1 : _options.Delimiter.Length; // Skip delimiter
                            string value = TryInternString(_quotedFieldBuilder.ToString());
                            _fieldsBuffer.Add(new FieldInfo(value, true));
                            return;
                        }

                        // Valid close: followed by newline
                        if (afterChar == '\r' || afterChar == '\n')
                        {
                            _bufferPosition++; // Skip closing quote
                            SkipNewline();
                            string value = TryInternString(_quotedFieldBuilder.ToString());
                            _fieldsBuffer.Add(new FieldInfo(value, true));
                            _endOfRecord = true;
                            return;
                        }

                        // Valid close: followed by whitespace then delimiter/newline
                        int checkPos = afterQuote;
                        while (checkPos < _bufferLength && char.IsWhiteSpace(_buffer[checkPos]) &&
                               _buffer[checkPos] != '\r' && _buffer[checkPos] != '\n')
                        {
                            checkPos++;
                        }

                        if (checkPos < _bufferLength)
                        {
                            char checkChar = _buffer[checkPos];
                            if ((_singleCharDelimiter && checkChar == _delimiterFirstChar) ||
                                checkChar == '\r' || checkChar == '\n')
                            {
                                _bufferPosition = checkPos;
                                if (checkChar == '\r' || checkChar == '\n')
                                {
                                    SkipNewline();
                                    _endOfRecord = true;
                                }
                                else
                                {
                                    _bufferPosition += _singleCharDelimiter ? 1 : _options.Delimiter.Length;
                                }
                                string value = TryInternString(_quotedFieldBuilder.ToString());
                                _fieldsBuffer.Add(new FieldInfo(value, true));
                                return;
                            }
                        }

                        // Not a valid closing position - treat quote as literal and include it
                        _quotedFieldBuilder.Append(normalized);
                        _fieldAccumulator.Append(normalized);
                        _bufferPosition++;
                        quotedLength++;
                        CheckQuotedFieldLength(quotedLength);
                        continue;
                    }
                }

                // Handle newline - if we reach newline without valid closing quote, return raw content
                if (c == '\r' || c == '\n')
                {
                    string value = TryInternString(_fieldAccumulator.ToString());
                    _fieldsBuffer.Add(new FieldInfo(value, false));
                    SkipNewline();
                    _endOfRecord = true;
                    return;
                }

                _quotedFieldBuilder.Append(normalized);
                _fieldAccumulator.Append(normalized);
                _bufferPosition++;
                quotedLength++;
                CheckQuotedFieldLength(quotedLength);
            }
        }
    }
}
