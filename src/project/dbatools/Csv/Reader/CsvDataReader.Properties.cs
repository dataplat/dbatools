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
        /// Gets the current record index (zero-based).
        /// </summary>
        /// <remarks>
        /// Thread-safety: Uses atomic read to prevent torn reads on 64-bit values.
        /// </remarks>
        public long CurrentRecordIndex => Interlocked.Read(ref _currentRecordIndex);

        /// <summary>
        /// Gets the current line number in the file (one-based).
        /// </summary>
        public long CurrentLineNumber => _currentLineNumber;

        /// <summary>
        /// Gets whether the end of the CSV stream has been reached.
        /// Returns true after Read() has returned false.
        /// </summary>
        /// <remarks>
        /// Provides LumenWorks CsvReader compatibility.
        /// </remarks>
        public bool EndOfStream => _readReturnedFalse;

        /// <summary>
        /// Gets whether the current record had missing fields that were padded with nulls.
        /// Only set when MismatchedFieldAction is PadWithNulls or PadOrTruncate.
        /// Reset to false at the start of each Read() call.
        /// </summary>
        /// <remarks>
        /// Provides LumenWorks CsvReader compatibility.
        /// Note: This flag may not be accurate when parallel processing is enabled.
        /// </remarks>
        public bool MissingFieldFlag => _missingFieldFlag;

        /// <summary>
        /// Gets whether the current record had a parse error that was handled by skipping.
        /// Only set when ParseErrorAction is AdvanceToNextLine or RaiseEvent (with AdvanceToNextLine action).
        /// Reset to false at the start of each Read() call.
        /// </summary>
        /// <remarks>
        /// Provides LumenWorks CsvReader compatibility.
        /// Note: This flag may not be accurate when parallel processing is enabled.
        /// </remarks>
        public bool ParseErrorFlag => _parseErrorFlag;

        /// <summary>
        /// Gets the collection of parse errors encountered during reading.
        /// Only populated when CollectParseErrors is true.
        /// </summary>
        public IReadOnlyList<CsvParseError> ParseErrors => _parseErrors;

        /// <summary>
        /// Gets the column definitions.
        /// </summary>
        public IReadOnlyList<CsvColumn> Columns
        {
            get
            {
                Initialize();
                return _columns;
            }
        }

        /// <summary>
        /// Gets the static column definitions.
        /// </summary>
        public IReadOnlyList<StaticColumn> StaticColumnsList => _staticColumns;

        /// <summary>
        /// Gets the options used by this reader.
        /// </summary>
        public CsvReaderOptions Options => _options;

        /// <summary>
        /// Gets the field headers.
        /// </summary>
        public string[] GetFieldHeaders()
        {
            Initialize();
            var headers = new string[_columns.Count + _staticColumns.Count];
            for (int i = 0; i < _columns.Count; i++)
            {
                headers[i] = _columns[i].Name;
            }
            for (int i = 0; i < _staticColumns.Count; i++)
            {
                headers[_columns.Count + i] = _staticColumns[i].Name;
            }
            return headers;
        }

        /// <summary>
        /// Gets whether the column with the specified name exists.
        /// </summary>
        public bool HasColumn(string name)
        {
            Initialize();
            if (name == null)
                return false;

            for (int i = 0; i < _columns.Count; i++)
            {
                if (string.Equals(_columns[i].Name, name, StringComparison.OrdinalIgnoreCase))
                    return true;
            }

            for (int i = 0; i < _staticColumns.Count; i++)
            {
                if (string.Equals(_staticColumns[i].Name, name, StringComparison.OrdinalIgnoreCase))
                    return true;
            }

            return false;
        }

        /// <summary>
        /// Gets the index of the field with the specified header name.
        /// </summary>
        /// <param name="header">The header name to find.</param>
        /// <returns>The zero-based index of the field, or -1 if not found.</returns>
        /// <remarks>
        /// Provides LumenWorks CsvReader compatibility. Unlike GetOrdinal(),
        /// returns -1 instead of throwing when the header is not found.
        /// </remarks>
        public int GetFieldIndex(string header)
        {
            Initialize();
            if (header == null)
                return -1;

            for (int i = 0; i < _columns.Count; i++)
            {
                if (string.Equals(_columns[i].Name, header, StringComparison.OrdinalIgnoreCase))
                    return i;
            }

            for (int i = 0; i < _staticColumns.Count; i++)
            {
                if (string.Equals(_staticColumns[i].Name, header, StringComparison.OrdinalIgnoreCase))
                    return _columns.Count + i;
            }

            return -1;
        }

        /// <summary>
        /// Sets the type for a column. Must be called before reading.
        /// </summary>
        public void SetColumnType(string columnName, Type type)
        {
            Initialize();
            for (int i = 0; i < _columns.Count; i++)
            {
                if (string.Equals(_columns[i].Name, columnName, StringComparison.OrdinalIgnoreCase))
                {
                    _columns[i].DataType = type;
                    // Re-cache the converter for this column
                    if (type != typeof(string))
                    {
                        _columns[i].CachedConverter = _columns[i].Converter ?? _options.TypeConverterRegistry?.GetConverter(type);
                        // Invalidate fast path when non-string column type is set
                        _useFastConversion = false;
                        _useFastParsing = false;
                    }
                    else
                    {
                        _columns[i].CachedConverter = null;
                    }
                    return;
                }
            }

            // Also check static columns - they already have a type set, but allow changing it
            for (int i = 0; i < _staticColumns.Count; i++)
            {
                if (string.Equals(_staticColumns[i].Name, columnName, StringComparison.OrdinalIgnoreCase))
                {
                    _staticColumns[i].DataType = type;
                    return;
                }
            }

            throw new ArgumentException(String.Format("Column '{0}' not found", columnName), nameof(columnName));
        }

        /// <summary>
        /// Adds a static column to inject values into each record.
        /// </summary>
        public void AddStaticColumn(StaticColumn column)
        {
            if (column == null)
                throw new ArgumentNullException(nameof(column));

            _staticColumns.Add(column);

            var convertedValues = _convertedValues;
            if (convertedValues != null)
            {
                // Resize converted values array
                Array.Resize(ref convertedValues, _columns.Count + _staticColumns.Count);
                _convertedValues = convertedValues;
            }
        }

        /// <summary>
        /// Gets the current record as a raw CSV string representation.
        /// This reconstructs the line from the parsed field values using the configured delimiter and quote character.
        /// Useful for debugging and error reporting.
        /// </summary>
        /// <remarks>
        /// This method provides LumenWorks CsvReader compatibility. Note that the returned string is a
        /// reconstruction from parsed values, so it may differ slightly from the original line
        /// (e.g., unnecessary quotes may be omitted, whitespace may be trimmed based on options).
        /// </remarks>
        /// <returns>A CSV-formatted string of the current record, or an empty string if no record is current.</returns>
        public string GetCurrentRawData()
        {
            var record = _currentRecord;
            if (record == null || _currentRecordIndex < 0)
                return string.Empty;

            var wasQuoted = _currentRecordWasQuoted;
            string delimiter = _options.Delimiter;
            char quote = _options.Quote;

            var sb = new StringBuilder();
            int fieldCount = Math.Min(record.Length, _columns.Count);

            for (int i = 0; i < fieldCount; i++)
            {
                if (i > 0)
                    sb.Append(delimiter);

                string value = record[i];
                if (value == null)
                    continue;

                // Quote the field if it was originally quoted, or if it contains special characters
                bool needsQuoting = (wasQuoted != null && i < wasQuoted.Length && wasQuoted[i]) ||
                                   value.Contains(delimiter) ||
                                   value.IndexOf(quote) >= 0 ||
                                   value.IndexOf('\r') >= 0 ||
                                   value.IndexOf('\n') >= 0;

                if (needsQuoting)
                {
                    sb.Append(quote);
                    // Escape any quotes within the value
                    foreach (char c in value)
                    {
                        if (c == quote)
                            sb.Append(quote); // Double the quote to escape
                        sb.Append(c);
                    }
                    sb.Append(quote);
                }
                else
                {
                    sb.Append(value);
                }
            }

            return sb.ToString();
        }

        /// <summary>
        /// Copies all field values from the current record to the specified string array.
        /// This provides an efficient way to get all field values at once without repeated indexer calls.
        /// </summary>
        /// <remarks>
        /// This method provides LumenWorks CsvReader compatibility. Only CSV columns are copied,
        /// not static columns. Use <see cref="GetValues(object[])"/> to get all values including static columns.
        /// </remarks>
        /// <param name="array">The destination array. Must have sufficient capacity starting from <paramref name="index"/>.</param>
        /// <param name="index">The zero-based index in <paramref name="array"/> at which copying begins. Default is 0.</param>
        /// <exception cref="ArgumentNullException">Thrown when <paramref name="array"/> is null.</exception>
        /// <exception cref="ArgumentOutOfRangeException">Thrown when <paramref name="index"/> is negative.</exception>
        /// <exception cref="ArgumentException">Thrown when the destination array has insufficient capacity.</exception>
        /// <exception cref="InvalidOperationException">Thrown when no current record is available (call Read() first).</exception>
        public void CopyCurrentRecordTo(string[] array, int index = 0)
        {
            if (array == null)
                throw new ArgumentNullException(nameof(array));
            if (index < 0)
                throw new ArgumentOutOfRangeException(nameof(index), index, "Index cannot be negative.");

            var record = _currentRecord;
            if (record == null || _currentRecordIndex < 0)
                throw new InvalidOperationException("No current record. Call Read() first.");

            int fieldCount = _columns.Count;
            if (array.Length - index < fieldCount)
                throw new ArgumentException(String.Format("Destination array has insufficient capacity. Required: {0}, available: {1}.", fieldCount, array.Length - index), nameof(array));

            for (int i = 0; i < fieldCount; i++)
            {
                // Map from column to source index
                int sourceIndex = _columns[i].SourceIndex;
                if (sourceIndex >= 0 && sourceIndex < record.Length)
                {
                    array[index + i] = record[sourceIndex];
                }
                else
                {
                    array[index + i] = null;
                }
            }
        }

    }
}
