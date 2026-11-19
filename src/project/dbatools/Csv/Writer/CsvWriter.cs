using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.IO;
using System.Text;
using Dataplat.Dbatools.Csv.Compression;

namespace Dataplat.Dbatools.Csv.Writer
{
    /// <summary>
    /// High-performance CSV writer with compression support.
    /// Addresses issue #8646 for Export-DbaCsv with compression options.
    /// </summary>
    public sealed partial class CsvWriter : IDisposable
    {

        private readonly TextWriter _writer;
        private readonly CsvWriterOptions _options;
        private readonly bool _ownsWriter;
        private readonly StringBuilder _rowBuilder;
        private bool _isDisposed;
        private bool _headerWritten;
        private string[] _columnNames;
        private long _rowsWritten;



        /// <summary>
        /// Creates a new CSV writer for the specified file.
        /// </summary>
        public CsvWriter(string filePath) : this(filePath, null)
        {
        }

        /// <summary>
        /// Creates a new CSV writer for the specified file with options.
        /// </summary>
        public CsvWriter(string filePath, CsvWriterOptions options)
        {
            if (string.IsNullOrEmpty(filePath))
                throw new ArgumentNullException(nameof(filePath));

            _options = options ?? new CsvWriterOptions();

            Stream stream = CompressionHelper.OpenFileForWriting(
                filePath,
                _options.CompressionType,
                _options.CompressionLevel);

            _writer = new StreamWriter(stream, _options.Encoding, _options.BufferSize);
            _ownsWriter = true;
            _rowBuilder = new StringBuilder(256);
        }

        /// <summary>
        /// Creates a new CSV writer for the specified TextWriter.
        /// </summary>
        public CsvWriter(TextWriter writer, CsvWriterOptions options = null)
        {
            _writer = writer ?? throw new ArgumentNullException(nameof(writer));
            _options = options ?? new CsvWriterOptions();
            _ownsWriter = false;
            _rowBuilder = new StringBuilder(256);
        }

        /// <summary>
        /// Creates a new CSV writer for the specified Stream.
        /// </summary>
        public CsvWriter(Stream stream, CsvWriterOptions options = null)
        {
            if (stream == null)
                throw new ArgumentNullException(nameof(stream));

            _options = options ?? new CsvWriterOptions();

            Stream compressedStream = CompressionHelper.WrapForCompression(
                stream,
                _options.CompressionType,
                _options.CompressionLevel);

            _writer = new StreamWriter(compressedStream, _options.Encoding, _options.BufferSize);
            _ownsWriter = true;
            _rowBuilder = new StringBuilder(256);
        }



        /// <summary>
        /// Writes the header row with the specified column names.
        /// </summary>
        public void WriteHeader(params string[] columnNames)
        {
            ThrowIfDisposed();

            if (_headerWritten)
                throw new InvalidOperationException("Header has already been written");

            if (columnNames == null || columnNames.Length == 0)
                throw new ArgumentException("At least one column name is required", nameof(columnNames));

            _columnNames = columnNames;

            if (_options.WriteHeader)
            {
                WriteRow(columnNames);
                _headerWritten = true;
            }
        }

        /// <summary>
        /// Writes a data row with the specified values.
        /// </summary>
        public void WriteRow(params object[] values)
        {
            ThrowIfDisposed();

            if (values == null)
                throw new ArgumentNullException(nameof(values));

            // Fast path: write directly without StringBuilder for simple cases
            if (_options.QuotingBehavior == CsvQuotingBehavior.AsNeeded && _options.Delimiter.Length == 1)
            {
                WriteRowFast(values);
                return;
            }

            _rowBuilder.Clear();
            string delimiter = _options.Delimiter;

            for (int i = 0; i < values.Length; i++)
            {
                if (i > 0)
                    _rowBuilder.Append(delimiter);

                string formatted = FormatValue(values[i]);
                _rowBuilder.Append(QuoteIfNeeded(formatted, values[i]));
            }

            _writer.Write(_rowBuilder.ToString());
            _writer.Write(_options.NewLine);
            _rowsWritten++;

            if (_options.FlushAfterEachRow)
                _writer.Flush();
        }

        /// <summary>
        /// Fast path for writing rows - writes directly to writer, skips StringBuilder for simple values.
        /// </summary>
        private void WriteRowFast(object[] values)
        {
            char delimChar = _options.Delimiter[0];
            char quote = _options.Quote;
            string newLine = _options.NewLine;

            for (int i = 0; i < values.Length; i++)
            {
                if (i > 0)
                    _writer.Write(delimChar);

                object value = values[i];

                // Fast path for common types that never need quoting
                if (value == null || value == DBNull.Value)
                {
                    _writer.Write(_options.NullValue);
                    continue;
                }

                // Numeric types never need quoting - write directly
                if (value is int intVal)
                {
                    _writer.Write(intVal);
                    continue;
                }
                if (value is long longVal)
                {
                    _writer.Write(longVal);
                    continue;
                }
                if (value is double doubleVal)
                {
                    _writer.Write(doubleVal);
                    continue;
                }
                if (value is decimal decVal)
                {
                    _writer.Write(decVal);
                    continue;
                }
                if (value is bool boolVal)
                {
                    _writer.Write(boolVal ? "true" : "false");
                    continue;
                }

                // String and other types - check if quoting needed
                string formatted = FormatValue(value);
                if (string.IsNullOrEmpty(formatted))
                {
                    _writer.Write(formatted);
                    continue;
                }

                // Quick scan for characters that need quoting
                bool needsQuoting = false;
                for (int j = 0; j < formatted.Length; j++)
                {
                    char c = formatted[j];
                    if (c == delimChar || c == quote || c == '\r' || c == '\n')
                    {
                        needsQuoting = true;
                        break;
                    }
                }

                if (needsQuoting)
                {
                    _writer.Write(quote);
                    // Check if we need to escape quotes
                    if (formatted.IndexOf(quote) >= 0)
                    {
                        _writer.Write(formatted.Replace(quote.ToString(), new string(quote, 2)));
                    }
                    else
                    {
                        _writer.Write(formatted);
                    }
                    _writer.Write(quote);
                }
                else
                {
                    _writer.Write(formatted);
                }
            }

            _writer.Write(newLine);
            _rowsWritten++;

            if (_options.FlushAfterEachRow)
                _writer.Flush();
        }

        /// <summary>
        /// Writes a data row from a dictionary (column name to value mapping).
        /// </summary>
        public void WriteRow(IDictionary<string, object> row)
        {
            ThrowIfDisposed();

            if (row == null)
                throw new ArgumentNullException(nameof(row));

            if (_columnNames == null)
            {
                // Use dictionary keys as column names
                _columnNames = new string[row.Count];
                row.Keys.CopyTo(_columnNames, 0);

                if (_options.WriteHeader && !_headerWritten)
                {
                    WriteRow(_columnNames);
                    _headerWritten = true;
                }
            }

            object[] values = new object[_columnNames.Length];
            for (int i = 0; i < _columnNames.Length; i++)
            {
                row.TryGetValue(_columnNames[i], out values[i]);
            }

            WriteRow(values);
        }

        /// <summary>
        /// Writes all records from an IDataReader.
        /// </summary>
        public long WriteFromReader(IDataReader reader)
        {
            ThrowIfDisposed();

            if (reader == null)
                throw new ArgumentNullException(nameof(reader));

            // Write header from reader schema
            if (!_headerWritten && _options.WriteHeader)
            {
                string[] headers = new string[reader.FieldCount];
                for (int i = 0; i < reader.FieldCount; i++)
                {
                    headers[i] = reader.GetName(i);
                }
                WriteHeader(headers);
            }

            // Write data rows
            object[] values = new object[reader.FieldCount];
            long count = 0;

            while (reader.Read())
            {
                reader.GetValues(values);
                WriteRow(values);
                count++;
            }

            return count;
        }

        /// <summary>
        /// Writes all records from a DataTable.
        /// </summary>
        public long WriteFromDataTable(DataTable table)
        {
            ThrowIfDisposed();

            if (table == null)
                throw new ArgumentNullException(nameof(table));

            // Write header
            if (!_headerWritten && _options.WriteHeader)
            {
                string[] headers = new string[table.Columns.Count];
                for (int i = 0; i < table.Columns.Count; i++)
                {
                    headers[i] = table.Columns[i].ColumnName;
                }
                WriteHeader(headers);
            }

            // Write data rows
            object[] values = new object[table.Columns.Count];

            foreach (DataRow row in table.Rows)
            {
                for (int i = 0; i < table.Columns.Count; i++)
                {
                    values[i] = row[i];
                }
                WriteRow(values);
            }

            return table.Rows.Count;
        }

        /// <summary>
        /// Writes all items from an enumerable collection.
        /// </summary>
        public long WriteFromEnumerable<T>(IEnumerable<T> items, Func<T, object[]> selector)
        {
            ThrowIfDisposed();

            if (items == null)
                throw new ArgumentNullException(nameof(items));
            if (selector == null)
                throw new ArgumentNullException(nameof(selector));

            long count = 0;

            foreach (var item in items)
            {
                WriteRow(selector(item));
                count++;
            }

            return count;
        }

        /// <summary>
        /// Flushes the writer.
        /// </summary>
        public void Flush()
        {
            ThrowIfDisposed();
            _writer.Flush();
        }

        /// <summary>
        /// Gets the number of data rows written (excludes header).
        /// </summary>
        public long RowsWritten => _headerWritten ? _rowsWritten - 1 : _rowsWritten;

    }
}
