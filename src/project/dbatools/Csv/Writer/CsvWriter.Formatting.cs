using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.IO;
using System.Text;
using Dataplat.Dbatools.Csv.Compression;

namespace Dataplat.Dbatools.Csv.Writer
{
    public sealed partial class CsvWriter
    {

        private string FormatValue(object value)
        {
            if (value == null || value == DBNull.Value)
                return _options.NullValue;

            if (value is DateTime dt)
            {
                if (_options.UseUtc)
                    dt = dt.ToUniversalTime();
                return dt.ToString(_options.DateTimeFormat, CultureInfo.InvariantCulture);
            }

            if (value is DateTimeOffset dto)
            {
                if (_options.UseUtc)
                    dto = dto.ToUniversalTime();
                return dto.ToString(_options.DateTimeFormat, CultureInfo.InvariantCulture);
            }

            if (value is bool b)
                return b ? "true" : "false";

            if (value is byte[] bytes)
                return Convert.ToBase64String(bytes);

            if (value is IFormattable formattable)
                return formattable.ToString(null, CultureInfo.InvariantCulture);

            return value.ToString();
        }

        private string QuoteIfNeeded(string value, object originalValue)
        {
            if (string.IsNullOrEmpty(value))
                return value;

            bool needsQuoting;

            switch (_options.QuotingBehavior)
            {
                case CsvQuotingBehavior.Always:
                    needsQuoting = true;
                    break;

                case CsvQuotingBehavior.Never:
                    needsQuoting = false;
                    break;

                case CsvQuotingBehavior.NonNumeric:
                    needsQuoting = !IsNumericType(originalValue);
                    break;

                case CsvQuotingBehavior.AsNeeded:
                default:
                    needsQuoting = NeedsQuoting(value);
                    break;
            }

            if (!needsQuoting)
                return value;

            // Escape quotes by doubling them (RFC 4180)
            string escaped = value.Replace(_options.Quote.ToString(), new string(_options.Quote, 2));
            return String.Format("{0}{1}{0}", _options.Quote, escaped);
        }

        private bool NeedsQuoting(string value)
        {
            // Single pass check for delimiter, quote, or newline
            string delimiter = _options.Delimiter;
            char quote = _options.Quote;
            int delimiterLength = delimiter.Length;

            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];

                // Check for quote or newline characters
                if (c == quote || c == '\r' || c == '\n')
                    return true;

                // Check for delimiter match (supports multi-character delimiters)
                if (c == delimiter[0] && delimiterLength == 1)
                    return true;

                if (c == delimiter[0] && i + delimiterLength <= value.Length)
                {
                    bool match = true;
                    for (int j = 1; j < delimiterLength; j++)
                    {
                        if (value[i + j] != delimiter[j])
                        {
                            match = false;
                            break;
                        }
                    }
                    if (match)
                        return true;
                }
            }

            return false;
        }

        private bool IsNumericType(object value)
        {
            return value is byte || value is sbyte ||
                   value is short || value is ushort ||
                   value is int || value is uint ||
                   value is long || value is ulong ||
                   value is float || value is double ||
                   value is decimal;
        }

        private void ThrowIfDisposed()
        {
            if (_isDisposed)
                throw new ObjectDisposedException(GetType().Name);
        }



        /// <summary>
        /// Disposes the writer and releases resources.
        /// </summary>
        public void Dispose()
        {
            if (!_isDisposed)
            {
                _isDisposed = true;

                if (_ownsWriter)
                {
                    _writer.Flush();
                    _writer.Dispose();
                }
            }
        }

    }
}
