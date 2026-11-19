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

        private void ParseLine(string line)
        {
            _fieldsBuffer.Clear();

            if (string.IsNullOrEmpty(line))
                return;

            ReadOnlySpan<char> lineSpan = line.AsSpan();
            string delimiter = _options.Delimiter;
            char quote = _options.Quote;
            char escape = _options.Escape;
            bool lenient = _options.QuoteMode == QuoteMode.Lenient;

            int position = 0;

            while (position <= lineSpan.Length)
            {
                var (field, wasQuoted, newPosition) = ParseField(lineSpan, position, delimiter, quote, escape, lenient);
                _fieldsBuffer.Add(new FieldInfo(field, wasQuoted));
                position = newPosition;

                if (position > lineSpan.Length)
                    break;
            }
        }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private (string value, bool wasQuoted, int newPosition) ParseField(
            ReadOnlySpan<char> line, int start, string delimiter, char quote, char escape, bool lenient)
        {
            if (start >= line.Length)
            {
                // Empty field at end
                return (string.Empty, false, start + delimiter.Length);
            }

            // Check for quoted field
            if (line[start] == quote)
            {
                if (lenient)
                {
                    // In lenient mode, try to parse as quoted field with inline validation
                    // This combines the validation and parsing into a single pass
                    var result = TryParseQuotedFieldLenient(line, start, delimiter, quote, escape);
                    if (result.wasValidQuoted)
                    {
                        return (result.value, true, result.newPosition);
                    }
                    // No valid closing quote found - treat as unquoted field
                    return ParseUnquotedField(line, start, delimiter);
                }
                return ParseQuotedField(line, start, delimiter, quote, escape);
            }

            return ParseUnquotedField(line, start, delimiter);
        }

        /// <summary>
        /// Attempts to parse a quoted field in lenient mode, validating the closing quote in a single pass.
        /// Returns wasValidQuoted=false if no valid closing quote is found.
        /// </summary>
        private (string value, bool wasValidQuoted, int newPosition) TryParseQuotedFieldLenient(
            ReadOnlySpan<char> line, int start, string delimiter, char quote, char escape)
        {
            _quotedFieldBuilder.Clear();
            int i = start + 1; // Skip opening quote

            while (i < line.Length)
            {
                char c = line[i];

                // Check for escaped quote (RFC 4180: "" or custom escape like \")
                if (c == escape && i + 1 < line.Length && line[i + 1] == quote)
                {
                    _quotedFieldBuilder.Append(quote);
                    i += 2;
                }
                // In lenient mode, also handle backslash escape
                else if (c == '\\' && i + 1 < line.Length && line[i + 1] == quote)
                {
                    _quotedFieldBuilder.Append(quote);
                    i += 2;
                }
                else if (c == quote)
                {
                    // Found a quote - check if it's a valid closing quote
                    int afterQuote = i + 1;

                    // Check if at end of line - valid closing
                    if (afterQuote >= line.Length)
                    {
                        string value = TryInternString(_quotedFieldBuilder.ToString());
                        return (value, true, line.Length + delimiter.Length);
                    }

                    // Check for delimiter immediately after quote
                    if (MatchesDelimiter(line, afterQuote, delimiter))
                    {
                        string value = TryInternString(_quotedFieldBuilder.ToString());
                        return (value, true, afterQuote + delimiter.Length);
                    }

                    // Check for whitespace then delimiter or end
                    int checkPos = afterQuote;
                    while (checkPos < line.Length && char.IsWhiteSpace(line[checkPos]))
                        checkPos++;

                    if (checkPos >= line.Length)
                    {
                        string value = TryInternString(_quotedFieldBuilder.ToString());
                        return (value, true, line.Length + delimiter.Length);
                    }

                    if (MatchesDelimiter(line, checkPos, delimiter))
                    {
                        string value = TryInternString(_quotedFieldBuilder.ToString());
                        return (value, true, checkPos + delimiter.Length);
                    }

                    // Quote is not at a valid position - include it in content and continue looking
                    _quotedFieldBuilder.Append(c);
                    i++;
                }
                else
                {
                    _quotedFieldBuilder.Append(c);
                    i++;
                }
            }

            // No valid closing quote found - return invalid
            return (null, false, 0);
        }

        private (string value, bool wasQuoted, int newPosition) ParseQuotedField(
            ReadOnlySpan<char> line, int start, string delimiter, char quote, char escape)
        {
            // Reuse pooled StringBuilder to reduce allocations
            _quotedFieldBuilder.Clear();
            int i = start + 1; // Skip opening quote
            bool wasQuoted = true;

            while (i < line.Length)
            {
                char c = line[i];

                // Check for escaped quote (RFC 4180: "" or custom escape like \")
                if (c == escape && i + 1 < line.Length && line[i + 1] == quote)
                {
                    _quotedFieldBuilder.Append(quote);
                    i += 2;
                }
                else if (c == quote)
                {
                    // End of quoted field
                    i++;

                    // Skip to delimiter or end
                    if (i < line.Length)
                    {
                        if (MatchesDelimiter(line, i, delimiter))
                        {
                            i += delimiter.Length;
                        }
                    }
                    else
                    {
                        // At end of line with no trailing delimiter - add delimiter length to signal end
                        i += delimiter.Length;
                    }

                    string value = TryInternString(_quotedFieldBuilder.ToString());
                    return (value, wasQuoted, i);
                }
                else
                {
                    _quotedFieldBuilder.Append(c);
                    i++;
                }
            }

            // Unclosed quote - return position past end to signal no more fields
            string finalValue = TryInternString(_quotedFieldBuilder.ToString());
            return (finalValue, wasQuoted, line.Length + delimiter.Length);
        }

        private (string value, bool wasQuoted, int newPosition) ParseUnquotedField(
            ReadOnlySpan<char> line, int start, string delimiter)
        {
            int delimiterLength = delimiter.Length;
            ReadOnlySpan<char> remaining = line.Slice(start);

            // Use Span for fast delimiter search when delimiter is single character
            if (delimiterLength == 1)
            {
                char delimChar = delimiter[0];
                int delimIndex = remaining.IndexOf(delimChar);

                if (delimIndex < 0)
                {
                    // No more delimiters - rest of line is the field
                    string value = TryInternString(remaining.ToString());
                    return (value, false, line.Length + delimiterLength);
                }

                string fieldValue = TryInternString(remaining.Slice(0, delimIndex).ToString());
                return (fieldValue, false, start + delimIndex + delimiterLength);
            }

            // Multi-character delimiter - use optimized Span.IndexOf for the first char, then verify
            ReadOnlySpan<char> delimSpan = delimiter.AsSpan();
            char firstDelimChar = delimiter[0];
            int searchStart = 0;

            while (searchStart < remaining.Length)
            {
                // Find next occurrence of first delimiter character
                int firstCharIndex = remaining.Slice(searchStart).IndexOf(firstDelimChar);
                if (firstCharIndex < 0)
                {
                    // No more potential delimiters - rest of line is the field
                    string value = TryInternString(remaining.ToString());
                    return (value, false, line.Length + delimiterLength);
                }

                int candidatePos = searchStart + firstCharIndex;

                // Check if full delimiter matches at this position
                if (candidatePos + delimiterLength <= remaining.Length &&
                    remaining.Slice(candidatePos, delimiterLength).SequenceEqual(delimSpan))
                {
                    string value = TryInternString(remaining.Slice(0, candidatePos).ToString());
                    return (value, false, start + candidatePos + delimiterLength);
                }

                // Not a match, continue searching after this position
                searchStart = candidatePos + 1;
            }

            // No delimiter found - rest of line is the field
            string finalValue = TryInternString(remaining.ToString());
            return (finalValue, false, line.Length + delimiterLength);
        }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private static bool MatchesDelimiter(ReadOnlySpan<char> line, int position, string delimiter)
        {
            if (position + delimiter.Length > line.Length)
                return false;

            for (int i = 0; i < delimiter.Length; i++)
            {
                if (line[position + i] != delimiter[i])
                    return false;
            }
            return true;
        }



        // Threshold for stackalloc vs ArrayPool - 512 chars = 1KB on stack
        private const int StackAllocThreshold = 512;

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private static string NormalizeSmartQuotes(string input)
        {
            if (input == null)
                return null;

            ReadOnlySpan<char> inputSpan = input.AsSpan();

            // Fast path: check if any smart quotes exist
            int firstSmartQuoteIndex = -1;
            for (int i = 0; i < inputSpan.Length; i++)
            {
                char c = inputSpan[i];
                if (c == LeftSingleQuote || c == RightSingleQuote ||
                    c == LeftDoubleQuote || c == RightDoubleQuote)
                {
                    firstSmartQuoteIndex = i;
                    break;
                }
            }

            if (firstSmartQuoteIndex < 0)
                return input;

            // Slow path: replace smart quotes using Span
            return inputSpan.Length <= StackAllocThreshold
                ? NormalizeSmartQuotesStackAlloc(inputSpan, firstSmartQuoteIndex)
                : NormalizeSmartQuotesPooled(inputSpan, firstSmartQuoteIndex);
        }

        private static string NormalizeSmartQuotesStackAlloc(ReadOnlySpan<char> input, int firstSmartQuoteIndex)
        {
            Span<char> buffer = stackalloc char[input.Length];

            // Copy prefix that has no smart quotes
            input.Slice(0, firstSmartQuoteIndex).CopyTo(buffer);

            // Process remainder
            int writePos = firstSmartQuoteIndex;
            for (int i = firstSmartQuoteIndex; i < input.Length; i++)
            {
                char c = input[i];
                buffer[writePos++] = NormalizeSmartQuoteChar(c);
            }

            // Use char array constructor for .NET Framework compatibility
            return buffer.Slice(0, writePos).ToString();
        }

        private static string NormalizeSmartQuotesPooled(ReadOnlySpan<char> input, int firstSmartQuoteIndex)
        {
            char[] buffer = ArrayPool<char>.Shared.Rent(input.Length);
            try
            {
                Span<char> bufferSpan = buffer.AsSpan(0, input.Length);

                // Copy prefix that has no smart quotes
                input.Slice(0, firstSmartQuoteIndex).CopyTo(bufferSpan);

                // Process remainder
                int writePos = firstSmartQuoteIndex;
                for (int i = firstSmartQuoteIndex; i < input.Length; i++)
                {
                    char c = input[i];
                    bufferSpan[writePos++] = NormalizeSmartQuoteChar(c);
                }

                return bufferSpan.Slice(0, writePos).ToString();
            }
            finally
            {
                ArrayPool<char>.Shared.Return(buffer);
            }
        }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private static char NormalizeSmartQuoteChar(char c)
        {
            if (c == LeftSingleQuote || c == RightSingleQuote)
                return '\'';
            if (c == LeftDoubleQuote || c == RightDoubleQuote)
                return '"';
            return c;
        }

    }
}
