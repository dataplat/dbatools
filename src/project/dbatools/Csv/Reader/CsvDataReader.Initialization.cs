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

        private void Initialize()
        {
            if (_isInitialized) return;
            _isInitialized = true;

            // Skip initial rows if specified
            for (int i = 0; i < _options.SkipRows; i++)
            {
                if (!ReadLine(out _))
                {
                    break;
                }
                _currentLineNumber++;
            }

            // Read header row if present
            if (_options.HasHeaderRow)
            {
                if (ReadLine(out string headerLine) && !string.IsNullOrEmpty(headerLine))
                {
                    _currentLineNumber++;

                    // Normalize smart quotes if enabled
                    if (_options.NormalizeQuotes)
                    {
                        headerLine = NormalizeSmartQuotes(headerLine);
                    }

                    ParseLine(headerLine);

                    // Process headers with duplicate handling
                    ProcessHeaders();
                }
            }
            else
            {
                // No header row - peek at first data row to create columns
                // This allows SetColumnType to be called before Read()
                InitializeColumnsFromFirstDataRow();
            }

            // Cache converters for each column to avoid per-row registry lookups
            CacheColumnConverters();

            // Determine if we can use fast path optimizations
            InitializeFastPathOptimizations();

            // Prepare converted values array
            _convertedValues = new object[_columns.Count + _staticColumns.Count];

            // Start parallel processing pipeline if enabled
            if (_options.EnableParallelProcessing)
            {
                StartParallelPipeline();
            }
        }

        private void CacheColumnConverters()
        {
            foreach (var column in _columns)
            {
                // Skip string columns - they don't need conversion
                if (column.DataType == typeof(string))
                    continue;

                // Use custom converter if specified
                if (column.Converter != null)
                {
                    column.CachedConverter = column.Converter;
                    continue;
                }

                // For DateTime columns, check if we need a custom converter with DateTimeFormats/Culture
                if (column.DataType == typeof(DateTime) || column.DataType == typeof(DateTime?))
                {
                    bool hasCustomFormats = _options.DateTimeFormats != null && _options.DateTimeFormats.Length > 0;
                    bool hasCustomCulture = _options.Culture != null && !_options.Culture.Equals(CultureInfo.InvariantCulture);

                    if (hasCustomFormats || hasCustomCulture)
                    {
                        // Create a custom DateTimeConverter with the specified formats and culture
                        column.CachedConverter = new DateTimeConverter
                        {
                            CustomFormats = _options.DateTimeFormats,
                            Culture = _options.Culture ?? CultureInfo.InvariantCulture
                        };
                        continue;
                    }
                }

                // Fall back to registry default converter
                column.CachedConverter = _options.TypeConverterRegistry?.GetConverter(column.DataType);
            }
        }

        /// <summary>
        /// Initializes fast path optimization flags based on options and column configuration.
        /// </summary>
        private void InitializeFastPathOptimizations()
        {
            // Check if all columns are strings (no type conversion needed)
            bool hasNonStringColumns = false;
            for (int i = 0; i < _columns.Count; i++)
            {
                if (_columns[i].DataType != typeof(string) || _columns[i].CachedConverter != null)
                {
                    hasNonStringColumns = true;
                    break;
                }
            }

            // Static columns always need conversion (they compute values)
            if (_staticColumns.Count > 0)
            {
                hasNonStringColumns = true;
            }

            // Determine if we can use the fast conversion path:
            // - No trimming options
            // - No null value configured
            // - No DistinguishEmptyFromNull
            // - No UseColumnDefaults
            // - No static columns
            // - All columns are strings
            _useFastConversion = !hasNonStringColumns
                && _options.TrimmingOptions == ValueTrimmingOptions.None
                && _options.NullValue == null
                && !_options.DistinguishEmptyFromNull
                && !_options.UseColumnDefaults
                && _staticColumns.Count == 0;

            // Determine if we can use the ultra-fast inline parsing path:
            // - Single-character delimiter
            // - No quote normalization
            // - No comment character
            // - No parallel processing
            // All of the above plus fast conversion conditions
            _useFastParsing = _useFastConversion
                && _singleCharDelimiter
                && !_options.NormalizeQuotes
                && _options.Comment == '\0'
                && !_options.EnableParallelProcessing
                && _options.QuoteMode != QuoteMode.Lenient;
        }

        private void InitializeColumnsFromFirstDataRow()
        {
            // Read the first data row to determine column count
            // Buffer it so it can be returned on the first Read() call
            while (true)
            {
                if (!ReadLine(out string line))
                {
                    // No data rows - leave columns empty
                    return;
                }

                _currentLineNumber++;

                // Skip empty lines if configured
                if (string.IsNullOrEmpty(line) && _options.SkipEmptyLines)
                {
                    continue;
                }

                // Skip comment lines
                if (line != null && line.Length > 0 && line[0] == _options.Comment)
                {
                    continue;
                }

                // Normalize smart quotes if enabled
                if (_options.NormalizeQuotes && line != null)
                {
                    line = NormalizeSmartQuotes(line);
                }

                // Parse the line to get field count
                ParseLine(line);

                // Create columns based on field count
                for (int i = 0; i < _fieldsBuffer.Count; i++)
                {
                    var col = new CsvColumn(String.Format("Column{0}", i), _columns.Count, typeof(string));
                    col.SourceIndex = i;
                    _columns.Add(col);
                }

                // Cache max source index
                _maxSourceIndex = _fieldsBuffer.Count - 1;

                // Buffer this line so it's returned on the first Read()
                _bufferedFirstLine = line;
                _hasBufferedFirstLine = true;

                break;
            }
        }

        private void ProcessHeaders()
        {
            _headerNameCounts.Clear();
            var headerIndicesToSkip = new HashSet<int>();

            // First pass: count occurrences for UseLastOccurrence mode
            if (_options.DuplicateHeaderBehavior == DuplicateHeaderBehavior.UseLastOccurrence)
            {
                var lastOccurrence = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                for (int i = 0; i < _fieldsBuffer.Count; i++)
                {
                    string name = GetTrimmedHeaderName(_fieldsBuffer[i].Value, i);
                    lastOccurrence[name] = i;
                }

                // Mark non-last occurrences for renaming
                var tempCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                for (int i = 0; i < _fieldsBuffer.Count; i++)
                {
                    string name = GetTrimmedHeaderName(_fieldsBuffer[i].Value, i);
                    if (lastOccurrence[name] != i)
                    {
                        // This is not the last occurrence, will be renamed
                        if (!tempCounts.ContainsKey(name))
                            tempCounts[name] = 0;
                        tempCounts[name]++;
                    }
                }
            }

            // Second pass: create columns
            for (int i = 0; i < _fieldsBuffer.Count; i++)
            {
                string name = GetTrimmedHeaderName(_fieldsBuffer[i].Value, i);

                // Check include/exclude filters first
                if (!ShouldIncludeColumn(name))
                    continue;

                // Handle duplicate headers
                string finalName = HandleDuplicateHeader(name, i);
                if (finalName == null)
                {
                    // Skip this column (UseFirstOccurrence mode, not the first)
                    continue;
                }

                var column = new CsvColumn(finalName, _columns.Count, GetColumnType(name));
                column.SourceIndex = i;  // Track original index for field mapping
                _columns.Add(column);

                // Update cached max source index
                if (i > _maxSourceIndex)
                    _maxSourceIndex = i;
            }
        }

        private string GetTrimmedHeaderName(string name, int fieldIndex)
        {
            string result = name;

            if (_options.TrimmingOptions != ValueTrimmingOptions.None && result != null)
            {
                result = result.Trim();
            }

            // Generate default header name for empty or whitespace-only headers (LumenWorks compatibility)
            if (string.IsNullOrWhiteSpace(result))
            {
                result = _options.DefaultHeaderName + fieldIndex;
            }

            return result ?? string.Empty;
        }

        private string HandleDuplicateHeader(string name, int fieldIndex)
        {
            if (!_headerNameCounts.TryGetValue(name, out int count))
            {
                // First occurrence
                _headerNameCounts[name] = 1;
                return name;
            }

            // Duplicate found
            switch (_options.DuplicateHeaderBehavior)
            {
                case DuplicateHeaderBehavior.ThrowException:
                    throw new CsvParseException(String.Format("Duplicate column header '{0}' found at index {1}. ", name, fieldIndex) +
                        "Use DuplicateHeaderBehavior option to handle duplicates.");

                case DuplicateHeaderBehavior.Rename:
                    _headerNameCounts[name] = count + 1;
                    string newName = String.Format("{0}_{1}", name, count + 1);
                    // Ensure the new name is also unique
                    while (_headerNameCounts.ContainsKey(newName))
                    {
                        count++;
                        _headerNameCounts[name] = count + 1;
                        newName = String.Format("{0}_{1}", name, count + 1);
                    }
                    _headerNameCounts[newName] = 1;
                    return newName;

                case DuplicateHeaderBehavior.UseFirstOccurrence:
                    // Skip this duplicate
                    return null;

                case DuplicateHeaderBehavior.UseLastOccurrence:
                    // Rename earlier occurrences, keep this one
                    _headerNameCounts[name] = count + 1;
                    return name;

                default:
                    return name;
            }
        }

        private bool ShouldIncludeColumn(string name)
        {
            if (_options.IncludeColumns != null && _options.IncludeColumns.Count > 0)
            {
                if (!_options.IncludeColumns.Contains(name))
                    return false;
            }

            if (_options.ExcludeColumns != null && _options.ExcludeColumns.Contains(name))
            {
                return false;
            }

            return true;
        }

        private Type GetColumnType(string columnName)
        {
            if (_options.ColumnTypes != null && _options.ColumnTypes.TryGetValue(columnName, out Type type))
            {
                return type;
            }
            return typeof(string);
        }

    }
}
