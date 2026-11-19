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
        /// Handles parse errors consistently for both parsing paths.
        /// </summary>
        private bool HandleParseError(Exception ex, string line)
        {
            var error = new CsvParseError(
                _currentRecordIndex + 1,
                -1,
                line ?? "(direct parsing - line not available)",
                ex.Message,
                ex,
                _currentLineNumber,
                0);

            if (_parseErrors != null)
            {
                _parseErrors.Add(error);

                if (_options.MaxParseErrors > 0 && _parseErrors.Count >= _options.MaxParseErrors)
                {
                    throw new CsvParseException(String.Format("Maximum parse errors ({0}) exceeded", _options.MaxParseErrors), error) { IsMaxErrorsExceeded = true };
                }
            }

            switch (_options.ParseErrorAction)
            {
                case CsvParseErrorAction.ThrowException:
                    throw new CsvParseException("CSV parse error", error);

                case CsvParseErrorAction.AdvanceToNextLine:
                    _parseErrorFlag = true;
                    return false; // Signal to continue

                case CsvParseErrorAction.RaiseEvent:
                    var args = new CsvParseErrorEventArgs(error, CsvParseErrorAction.AdvanceToNextLine);
                    ParseError?.Invoke(this, args);
                    if (args.Action == CsvParseErrorAction.ThrowException)
                    {
                        throw new CsvParseException("CSV parse error", error);
                    }
                    _parseErrorFlag = true;
                    return false; // Signal to continue
            }

            return false;
        }

        /// <summary>
        /// Handles field count mismatch for direct parsing mode.
        /// </summary>
        private void HandleFieldCountMismatchDirect(int expectedCount)
        {
            int actualCount = _fieldsBuffer.Count;

            switch (_options.MismatchedFieldAction)
            {
                case MismatchedFieldAction.ThrowException:
                    throw new FormatException(
                        String.Format("Row has {0} field(s) but expected {1} based on header.", actualCount, expectedCount));

                case MismatchedFieldAction.PadWithNulls:
                    if (_fieldsBuffer.Count < expectedCount)
                    {
                        _missingFieldFlag = true;
                        while (_fieldsBuffer.Count < expectedCount)
                        {
                            _fieldsBuffer.Add(new FieldInfo(string.Empty, false));
                        }
                    }
                    break;

                case MismatchedFieldAction.TruncateExtra:
                    while (_fieldsBuffer.Count > expectedCount)
                    {
                        _fieldsBuffer.RemoveAt(_fieldsBuffer.Count - 1);
                    }
                    break;

                case MismatchedFieldAction.PadOrTruncate:
                    if (_fieldsBuffer.Count < expectedCount)
                    {
                        _missingFieldFlag = true;
                        while (_fieldsBuffer.Count < expectedCount)
                        {
                            _fieldsBuffer.Add(new FieldInfo(string.Empty, false));
                        }
                    }
                    while (_fieldsBuffer.Count > expectedCount)
                    {
                        _fieldsBuffer.RemoveAt(_fieldsBuffer.Count - 1);
                    }
                    break;
            }
        }

        private void HandleFieldCountMismatch(string line, int expectedCount)
        {
            int actualCount = _fieldsBuffer.Count;

            switch (_options.MismatchedFieldAction)
            {
                case MismatchedFieldAction.ThrowException:
                    throw new FormatException(
                        String.Format("Row has {0} field(s) but expected {1} based on header. Row content: '{2}'", actualCount, expectedCount, line));

                case MismatchedFieldAction.PadWithNulls:
                    // Pad missing fields with empty values (will become null)
                    if (_fieldsBuffer.Count < expectedCount)
                    {
                        _missingFieldFlag = true;
                        while (_fieldsBuffer.Count < expectedCount)
                        {
                            _fieldsBuffer.Add(new FieldInfo(string.Empty, false));
                        }
                    }
                    break;

                case MismatchedFieldAction.TruncateExtra:
                    // Remove extra fields
                    while (_fieldsBuffer.Count > expectedCount)
                    {
                        _fieldsBuffer.RemoveAt(_fieldsBuffer.Count - 1);
                    }
                    break;

                case MismatchedFieldAction.PadOrTruncate:
                    // Both pad and truncate
                    if (_fieldsBuffer.Count < expectedCount)
                    {
                        _missingFieldFlag = true;
                        while (_fieldsBuffer.Count < expectedCount)
                        {
                            _fieldsBuffer.Add(new FieldInfo(string.Empty, false));
                        }
                    }
                    while (_fieldsBuffer.Count > expectedCount)
                    {
                        _fieldsBuffer.RemoveAt(_fieldsBuffer.Count - 1);
                    }
                    break;
            }
        }

        private void ConvertCurrentRecord()
        {
            // Fast path: all columns are strings with no special handling needed
            if (_useFastConversion)
            {
                ConvertCurrentRecordFast();
                return;
            }

            // Standard path with all options supported
            for (int i = 0; i < _columns.Count; i++)
            {
                var column = _columns[i];
                int sourceIndex = column.SourceIndex;

                string rawValue = sourceIndex < _currentRecord.Length ? _currentRecord[sourceIndex] : null;
                bool wasQuoted = sourceIndex < _currentRecordWasQuoted.Length && _currentRecordWasQuoted[sourceIndex];

                // Apply trimming
                rawValue = ApplyTrimming(rawValue, wasQuoted);

                // Check for explicit null value
                if (rawValue != null && _options.NullValue != null && rawValue == _options.NullValue)
                {
                    rawValue = null;
                    wasQuoted = false;  // Treat as unquoted null
                }

                // Handle null/empty values with distinction
                if (string.IsNullOrEmpty(rawValue))
                {
                    if (_options.DistinguishEmptyFromNull)
                    {
                        // If it was quoted (""), it's an explicit empty string
                        // If it was unquoted (,,), it's null
                        if (wasQuoted)
                        {
                            // Explicit empty string
                            if (column.DataType == typeof(string))
                            {
                                _convertedValues[i] = string.Empty;
                            }
                            else if (column.UseDefaultForNull || _options.UseColumnDefaults)
                            {
                                _convertedValues[i] = column.DefaultValue;
                            }
                            else
                            {
                                _convertedValues[i] = DBNull.Value;
                            }
                        }
                        else
                        {
                            // True null
                            if (column.UseDefaultForNull || _options.UseColumnDefaults)
                            {
                                _convertedValues[i] = column.DefaultValue;
                            }
                            else
                            {
                                _convertedValues[i] = DBNull.Value;
                            }
                        }
                    }
                    else
                    {
                        // Original behavior: treat both as DBNull
                        if (column.UseDefaultForNull || _options.UseColumnDefaults)
                        {
                            _convertedValues[i] = column.DefaultValue;
                        }
                        else
                        {
                            _convertedValues[i] = DBNull.Value;
                        }
                    }
                    continue;
                }

                // Convert to target type
                _convertedValues[i] = ConvertValue(rawValue, column);
            }

            // Add static column values
            for (int i = 0; i < _staticColumns.Count; i++)
            {
                _convertedValues[_columns.Count + i] = _staticColumns[i].GetValue(_currentRecordIndex);
            }
        }

        /// <summary>
        /// Fast conversion path for simple string-only columns with no special handling.
        /// This avoids all the per-column checks and branching.
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private void ConvertCurrentRecordFast()
        {
            int columnCount = _columns.Count;
            var record = _currentRecord;
            var values = _convertedValues;

            // Direct copy of string values - no conversion, trimming, or null handling
            for (int i = 0; i < columnCount; i++)
            {
                int sourceIndex = _columns[i].SourceIndex;
                string rawValue = sourceIndex < record.Length ? record[sourceIndex] : null;

                // Empty strings become DBNull for consistency with database behavior
                if (string.IsNullOrEmpty(rawValue))
                {
                    values[i] = DBNull.Value;
                }
                else
                {
                    values[i] = rawValue;
                }
            }
        }

        private object ConvertValue(string value, CsvColumn column)
        {
            if (column.DataType == typeof(string))
            {
                return value;
            }

            // Use cached converter (resolved during initialization) to avoid per-row registry lookups
            ITypeConverter converter = column.CachedConverter;

            if (converter != null)
            {
                // Pass culture to converter if it supports it
                if (converter is ICultureAwareConverter cultureAware)
                {
                    if (cultureAware.TryConvert(value, _options.Culture, out object result))
                    {
                        return result;
                    }
                }
                else if (converter.TryConvert(value, out object result))
                {
                    return result;
                }
                throw new FormatException(String.Format("Cannot convert value '{0}' to type {1} for column '{2}'", value, column.DataType.Name, column.Name));
            }

            // Fall back to Convert.ChangeType with culture
            try
            {
                return Convert.ChangeType(value, column.DataType, _options.Culture);
            }
            catch (Exception ex)
            {
                throw new FormatException(String.Format("Cannot convert value '{0}' to type {1} for column '{2}'", value, column.DataType.Name, column.Name), ex);
            }
        }

        private string ApplyTrimming(string value, bool isQuoted)
        {
            if (value == null || _options.TrimmingOptions == ValueTrimmingOptions.None)
                return value;

            bool shouldTrim = false;

            if ((_options.TrimmingOptions & ValueTrimmingOptions.UnquotedOnly) != 0 && !isQuoted)
                shouldTrim = true;

            if ((_options.TrimmingOptions & ValueTrimmingOptions.QuotedOnly) != 0 && isQuoted)
                shouldTrim = true;

            return shouldTrim ? value.Trim() : value;
        }

        /// <summary>
        /// Gets the number of columns in the current record.
        /// </summary>
        public int FieldCount
        {
            get
            {
                Initialize();
                return _columns.Count + _staticColumns.Count;
            }
        }

        /// <summary>
        /// Gets the value at the specified column index.
        /// </summary>
        public object this[int ordinal]
        {
            get { return GetValue(ordinal); }
        }

        /// <summary>
        /// Gets the value at the specified column name.
        /// </summary>
        public object this[string name]
        {
            get
            {
                int ordinal = GetOrdinal(name);
                return GetValue(ordinal);
            }
        }

    }
}
