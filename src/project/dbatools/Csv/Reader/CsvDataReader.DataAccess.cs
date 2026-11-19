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
        /// Gets the value at the specified column index.
        /// </summary>
        /// <remarks>
        /// Thread-safety: In parallel mode, this method is thread-safe and can be called
        /// from any thread while Read() is being called from another thread. However,
        /// the value returned represents a snapshot and may change after the next Read() call.
        /// </remarks>
        public object GetValue(int ordinal)
        {
            ThrowIfClosed();
            ValidateOrdinal(ordinal);

            // In parallel mode, synchronize access to prevent torn reads during Array.Copy
            if (_useParallelProcessing)
            {
                lock (_resultLock)
                {
                    return _convertedValues[ordinal];
                }
            }
            return _convertedValues[ordinal];
        }

        /// <summary>
        /// Gets all values in the current record.
        /// </summary>
        /// <remarks>
        /// Thread-safety: In parallel mode, this method is thread-safe and can be called
        /// from any thread while Read() is being called from another thread. However,
        /// the values returned represent a snapshot and may change after the next Read() call.
        /// </remarks>
        public int GetValues(object[] values)
        {
            ThrowIfClosed();
            if (values == null)
                throw new ArgumentNullException(nameof(values));

            // In parallel mode, synchronize access to prevent torn reads during Array.Copy
            if (_useParallelProcessing)
            {
                lock (_resultLock)
                {
                    int count = Math.Min(values.Length, _convertedValues.Length);
                    Array.Copy(_convertedValues, values, count);
                    return count;
                }
            }

            int seqCount = Math.Min(values.Length, _convertedValues.Length);
            Array.Copy(_convertedValues, values, seqCount);
            return seqCount;
        }

        /// <summary>
        /// Gets the column name at the specified index.
        /// </summary>
        public string GetName(int ordinal)
        {
            Initialize();
            ValidateOrdinal(ordinal);

            if (ordinal < _columns.Count)
                return _columns[ordinal].Name;
            else
                return _staticColumns[ordinal - _columns.Count].Name;
        }

        /// <summary>
        /// Gets the column index for the specified name.
        /// </summary>
        public int GetOrdinal(string name)
        {
            Initialize();
            if (name == null)
                throw new ArgumentNullException(nameof(name));

            for (int i = 0; i < _columns.Count; i++)
            {
                if (string.Equals(_columns[i].Name, name, StringComparison.OrdinalIgnoreCase))
                    return i;
            }

            for (int i = 0; i < _staticColumns.Count; i++)
            {
                if (string.Equals(_staticColumns[i].Name, name, StringComparison.OrdinalIgnoreCase))
                    return _columns.Count + i;
            }

            throw new ArgumentException(String.Format("Column '{0}' not found", name), nameof(name));
        }

        /// <summary>
        /// Gets the data type of the specified column.
        /// </summary>
        public Type GetFieldType(int ordinal)
        {
            Initialize();
            ValidateOrdinal(ordinal);

            if (ordinal < _columns.Count)
                return _columns[ordinal].DataType;
            else
                return _staticColumns[ordinal - _columns.Count].DataType;
        }

        /// <summary>
        /// Gets the data type name of the specified column.
        /// </summary>
        public string GetDataTypeName(int ordinal)
        {
            return GetFieldType(ordinal).Name;
        }

        /// <summary>
        /// Determines whether the specified column contains a null value.
        /// </summary>
        public bool IsDBNull(int ordinal)
        {
            ThrowIfClosed();
            ValidateOrdinal(ordinal);
            return _convertedValues[ordinal] == null || _convertedValues[ordinal] == DBNull.Value;
        }



        /// <inheritdoc />
        public bool GetBoolean(int ordinal) => (bool)GetValue(ordinal);
        /// <inheritdoc />
        public byte GetByte(int ordinal) => (byte)GetValue(ordinal);
        /// <inheritdoc />
        public char GetChar(int ordinal) => (char)GetValue(ordinal);
        /// <inheritdoc />
        public DateTime GetDateTime(int ordinal) => (DateTime)GetValue(ordinal);
        /// <inheritdoc />
        public decimal GetDecimal(int ordinal) => (decimal)GetValue(ordinal);
        /// <inheritdoc />
        public double GetDouble(int ordinal) => (double)GetValue(ordinal);
        /// <inheritdoc />
        public float GetFloat(int ordinal) => (float)GetValue(ordinal);
        /// <inheritdoc />
        public Guid GetGuid(int ordinal) => (Guid)GetValue(ordinal);
        /// <inheritdoc />
        public short GetInt16(int ordinal) => (short)GetValue(ordinal);
        /// <inheritdoc />
        public int GetInt32(int ordinal) => (int)GetValue(ordinal);
        /// <inheritdoc />
        public long GetInt64(int ordinal) => (long)GetValue(ordinal);
        /// <inheritdoc />
        public string GetString(int ordinal) => GetValue(ordinal)?.ToString();

        /// <inheritdoc />
        public long GetBytes(int ordinal, long fieldOffset, byte[] buffer, int bufferOffset, int length)
        {
            throw new NotSupportedException("GetBytes is not supported for CSV data");
        }

        /// <inheritdoc />
        public long GetChars(int ordinal, long fieldOffset, char[] buffer, int bufferOffset, int length)
        {
            string value = GetString(ordinal);
            if (value == null)
                return 0;

            int copyLength = Math.Min(length, value.Length - (int)fieldOffset);
            value.CopyTo((int)fieldOffset, buffer, bufferOffset, copyLength);
            return copyLength;
        }

        /// <inheritdoc />
        public IDataReader GetData(int ordinal)
        {
            throw new NotSupportedException("Nested data readers are not supported for CSV data");
        }

    }
}
