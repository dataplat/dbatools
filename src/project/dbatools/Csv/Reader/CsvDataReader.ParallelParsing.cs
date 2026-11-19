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
        /// Thread-safe line parsing that uses provided buffers instead of instance fields.
        /// </summary>
        private void ParseLineThreadSafe(string line, List<FieldInfo> fieldsBuffer, StringBuilder quotedFieldBuilder)
        {
            fieldsBuffer.Clear();

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
                var (field, wasQuoted, newPosition) = ParseFieldThreadSafe(lineSpan, position, delimiter, quote, escape, lenient, quotedFieldBuilder);
                fieldsBuffer.Add(new FieldInfo(field, wasQuoted));
                position = newPosition;

                if (position > lineSpan.Length)
                    break;
            }
        }

        /// <summary>
        /// Thread-safe field parsing that uses provided StringBuilder.
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private (string value, bool wasQuoted, int newPosition) ParseFieldThreadSafe(
            ReadOnlySpan<char> line, int start, string delimiter, char quote, char escape, bool lenient, StringBuilder quotedFieldBuilder)
        {
            if (start >= line.Length)
            {
                return (string.Empty, false, start + delimiter.Length);
            }

            if (line[start] == quote)
            {
                if (lenient)
                {
                    var result = TryParseQuotedFieldLenientThreadSafe(line, start, delimiter, quote, escape, quotedFieldBuilder);
                    if (result.wasValidQuoted)
                    {
                        return (result.value, true, result.newPosition);
                    }
                    return ParseUnquotedField(line, start, delimiter);
                }
                return ParseQuotedFieldThreadSafe(line, start, delimiter, quote, escape, quotedFieldBuilder);
            }

            return ParseUnquotedField(line, start, delimiter);
        }

        private (string value, bool wasValidQuoted, int newPosition) TryParseQuotedFieldLenientThreadSafe(
            ReadOnlySpan<char> line, int start, string delimiter, char quote, char escape, StringBuilder quotedFieldBuilder)
        {
            quotedFieldBuilder.Clear();
            int i = start + 1;

            while (i < line.Length)
            {
                char c = line[i];

                if (c == escape && i + 1 < line.Length && line[i + 1] == quote)
                {
                    quotedFieldBuilder.Append(quote);
                    i += 2;
                }
                else if (c == '\\' && i + 1 < line.Length && line[i + 1] == quote)
                {
                    quotedFieldBuilder.Append(quote);
                    i += 2;
                }
                else if (c == quote)
                {
                    int afterQuote = i + 1;

                    if (afterQuote >= line.Length)
                    {
                        string value = TryInternString(quotedFieldBuilder.ToString());
                        return (value, true, line.Length + delimiter.Length);
                    }

                    if (MatchesDelimiter(line, afterQuote, delimiter))
                    {
                        string value = TryInternString(quotedFieldBuilder.ToString());
                        return (value, true, afterQuote + delimiter.Length);
                    }

                    int checkPos = afterQuote;
                    while (checkPos < line.Length && char.IsWhiteSpace(line[checkPos]))
                        checkPos++;

                    if (checkPos >= line.Length)
                    {
                        string value = TryInternString(quotedFieldBuilder.ToString());
                        return (value, true, line.Length + delimiter.Length);
                    }

                    if (MatchesDelimiter(line, checkPos, delimiter))
                    {
                        string value = TryInternString(quotedFieldBuilder.ToString());
                        return (value, true, checkPos + delimiter.Length);
                    }

                    quotedFieldBuilder.Append(c);
                    i++;
                }
                else
                {
                    quotedFieldBuilder.Append(c);
                    i++;
                }
            }

            return (null, false, 0);
        }

        private (string value, bool wasQuoted, int newPosition) ParseQuotedFieldThreadSafe(
            ReadOnlySpan<char> line, int start, string delimiter, char quote, char escape, StringBuilder quotedFieldBuilder)
        {
            quotedFieldBuilder.Clear();
            int i = start + 1;
            bool wasQuoted = true;

            while (i < line.Length)
            {
                char c = line[i];

                if (c == escape && i + 1 < line.Length && line[i + 1] == quote)
                {
                    quotedFieldBuilder.Append(quote);
                    i += 2;
                }
                else if (c == quote)
                {
                    i++;

                    if (i < line.Length)
                    {
                        if (MatchesDelimiter(line, i, delimiter))
                        {
                            i += delimiter.Length;
                        }
                    }
                    else
                    {
                        i += delimiter.Length;
                    }

                    string value = TryInternString(quotedFieldBuilder.ToString());
                    return (value, wasQuoted, i);
                }
                else
                {
                    quotedFieldBuilder.Append(c);
                    i++;
                }
            }

            string finalValue = TryInternString(quotedFieldBuilder.ToString());
            return (finalValue, wasQuoted, line.Length + delimiter.Length);
        }

        private void HandleFieldCountMismatchThreadSafe(List<FieldInfo> fieldsBuffer, string line, int expectedCount)
        {
            int actualCount = fieldsBuffer.Count;

            switch (_options.MismatchedFieldAction)
            {
                case MismatchedFieldAction.ThrowException:
                    throw new FormatException(
                        String.Format("Row has {0} field(s) but expected {1} based on header. Row content: '{2}'", actualCount, expectedCount, line));

                case MismatchedFieldAction.PadWithNulls:
                    while (fieldsBuffer.Count < expectedCount)
                    {
                        fieldsBuffer.Add(new FieldInfo(string.Empty, false));
                    }
                    break;

                case MismatchedFieldAction.TruncateExtra:
                    while (fieldsBuffer.Count > expectedCount)
                    {
                        fieldsBuffer.RemoveAt(fieldsBuffer.Count - 1);
                    }
                    break;

                case MismatchedFieldAction.PadOrTruncate:
                    while (fieldsBuffer.Count < expectedCount)
                    {
                        fieldsBuffer.Add(new FieldInfo(string.Empty, false));
                    }
                    while (fieldsBuffer.Count > expectedCount)
                    {
                        fieldsBuffer.RemoveAt(fieldsBuffer.Count - 1);
                    }
                    break;
            }
        }

        /// <summary>
        /// Thread-safe record conversion that creates a new values array.
        /// </summary>
        private object[] ConvertRecordThreadSafe(List<FieldInfo> fieldsBuffer, long recordIndex)
        {
            var values = new object[_columns.Count + _staticColumns.Count];

            for (int i = 0; i < _columns.Count; i++)
            {
                var column = _columns[i];
                int sourceIndex = column.SourceIndex;

                string rawValue = sourceIndex < fieldsBuffer.Count ? fieldsBuffer[sourceIndex].Value : null;
                bool wasQuoted = sourceIndex < fieldsBuffer.Count && fieldsBuffer[sourceIndex].WasQuoted;

                // Apply trimming
                rawValue = ApplyTrimming(rawValue, wasQuoted);

                // Check for explicit null value
                if (rawValue != null && _options.NullValue != null && rawValue == _options.NullValue)
                {
                    rawValue = null;
                    wasQuoted = false;
                }

                // Handle null/empty values
                if (string.IsNullOrEmpty(rawValue))
                {
                    if (_options.DistinguishEmptyFromNull)
                    {
                        if (wasQuoted)
                        {
                            if (column.DataType == typeof(string))
                            {
                                values[i] = string.Empty;
                            }
                            else if (column.UseDefaultForNull || _options.UseColumnDefaults)
                            {
                                values[i] = column.DefaultValue;
                            }
                            else
                            {
                                values[i] = DBNull.Value;
                            }
                        }
                        else
                        {
                            if (column.UseDefaultForNull || _options.UseColumnDefaults)
                            {
                                values[i] = column.DefaultValue;
                            }
                            else
                            {
                                values[i] = DBNull.Value;
                            }
                        }
                    }
                    else
                    {
                        if (column.UseDefaultForNull || _options.UseColumnDefaults)
                        {
                            values[i] = column.DefaultValue;
                        }
                        else
                        {
                            values[i] = DBNull.Value;
                        }
                    }
                    continue;
                }

                // Convert to target type
                values[i] = ConvertValue(rawValue, column);
            }

            // Add static column values
            for (int i = 0; i < _staticColumns.Count; i++)
            {
                values[_columns.Count + i] = _staticColumns[i].GetValue(recordIndex);
            }

            return values;
        }

    }
}
