using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Csv.Reader
{
    /// <summary>
    /// Analyzes values for a single column to determine the optimal SQL Server data type.
    /// Uses incremental analysis with early exit when types are eliminated.
    /// </summary>
    internal sealed partial class ColumnTypeAnalyzer
    {
        // Type flags - tracks which types are still possible
        [Flags]
        private enum PossibleTypes
        {
            None = 0,
            Guid = 1 << 0,
            Boolean = 1 << 1,
            Int = 1 << 2,
            BigInt = 1 << 3,
            Decimal = 1 << 4,
            DateTime = 1 << 5,
            String = 1 << 6,  // Always possible as fallback
            All = Guid | Boolean | Int | BigInt | Decimal | DateTime | String
        }

        private static readonly HashSet<string> BooleanTrueValues = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "true", "yes", "1", "on", "y", "t"
        };

        private static readonly HashSet<string> BooleanFalseValues = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "false", "no", "0", "off", "n", "f"
        };

        // Standard DateTime formats to try
        private static readonly string[] StandardDateTimeFormats = new[]
        {
            "yyyy-MM-dd HH:mm:ss.fff",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd",
            "MM/dd/yyyy HH:mm:ss",
            "MM/dd/yyyy",
            "dd/MM/yyyy HH:mm:ss",
            "dd/MM/yyyy",
            "dd-MM-yyyy HH:mm:ss",
            "dd-MM-yyyy",
            "M/d/yyyy HH:mm:ss",
            "M/d/yyyy",
            "yyyyMMdd",
            "yyyyMMddHHmmss",
            "yyyy-MM-ddTHH:mm:ss",
            "yyyy-MM-ddTHH:mm:ss.fff",
            "yyyy-MM-ddTHH:mm:ssZ",
            "yyyy-MM-ddTHH:mm:ss.fffZ",
        };

        private readonly string _columnName;
        private readonly int _ordinal;
        private readonly string[] _customDateTimeFormats;
        private readonly CultureInfo _culture;

        private PossibleTypes _possibleTypes = PossibleTypes.All;
        private long _totalCount;
        private long _nullCount;
        private int _maxLength;
        private bool _hasUnicode;

        // Decimal tracking
        private int _maxPrecision;  // Max total digits
        private int _maxScale;      // Max digits after decimal point
        private int _maxIntegerDigits; // Max digits before decimal point

        /// <summary>
        /// Creates a new column type analyzer.
        /// </summary>
        /// <param name="columnName">The column name from the CSV header.</param>
        /// <param name="ordinal">The zero-based column position.</param>
        /// <param name="customDateTimeFormats">Optional custom DateTime formats to try first.</param>
        /// <param name="culture">The culture for parsing numbers and dates.</param>
        public ColumnTypeAnalyzer(string columnName, int ordinal, string[] customDateTimeFormats, CultureInfo culture)
        {
            _columnName = columnName;
            _ordinal = ordinal;
            _customDateTimeFormats = customDateTimeFormats;
            _culture = culture ?? CultureInfo.InvariantCulture;
        }

        /// <summary>
        /// Analyzes a single value and updates type statistics.
        /// </summary>
        /// <param name="value">The string value to analyze.</param>
        public void AnalyzeValue(string value)
        {
            _totalCount++;

            // Handle null/empty
            if (string.IsNullOrEmpty(value) || string.IsNullOrWhiteSpace(value))
            {
                _nullCount++;
                return;
            }

            string trimmed = value.Trim();
            if (trimmed.Length == 0)
            {
                _nullCount++;
                return;
            }

            // Track max length for string types
            if (trimmed.Length > _maxLength)
            {
                _maxLength = trimmed.Length;
            }

            // Check for Unicode characters (non-ASCII)
            if (!_hasUnicode)
            {
                foreach (char c in trimmed)
                {
                    if (c > 127)
                    {
                        _hasUnicode = true;
                        break;
                    }
                }
            }

            // Try each type in priority order, eliminating as they fail
            // Early exit: if a type is already eliminated, skip checking it

            // 1. GUID check (most specific)
            if ((_possibleTypes & PossibleTypes.Guid) != 0)
            {
                if (!Guid.TryParse(trimmed, out _))
                {
                    _possibleTypes &= ~PossibleTypes.Guid;
                }
            }

            // 2. Boolean check
            if ((_possibleTypes & PossibleTypes.Boolean) != 0)
            {
                if (!BooleanTrueValues.Contains(trimmed) && !BooleanFalseValues.Contains(trimmed))
                {
                    _possibleTypes &= ~PossibleTypes.Boolean;
                }
            }

            // 3. Integer checks (int then bigint)
            if ((_possibleTypes & PossibleTypes.Int) != 0)
            {
                if (!int.TryParse(trimmed, NumberStyles.Integer, _culture, out _))
                {
                    _possibleTypes &= ~PossibleTypes.Int;
                }
            }

            if ((_possibleTypes & PossibleTypes.BigInt) != 0)
            {
                if (!long.TryParse(trimmed, NumberStyles.Integer, _culture, out _))
                {
                    _possibleTypes &= ~PossibleTypes.BigInt;
                }
            }

            // 4. Decimal check - track precision and scale
            if ((_possibleTypes & PossibleTypes.Decimal) != 0)
            {
                if (decimal.TryParse(trimmed, NumberStyles.Number, _culture, out decimal decVal))
                {
                    // Calculate precision and scale
                    AnalyzeDecimalPrecision(trimmed, decVal);
                }
                else
                {
                    _possibleTypes &= ~PossibleTypes.Decimal;
                }
            }

            // 5. DateTime check
            if ((_possibleTypes & PossibleTypes.DateTime) != 0)
            {
                if (!TryParseDateTime(trimmed))
                {
                    _possibleTypes &= ~PossibleTypes.DateTime;
                }
            }
        }

        /// <summary>
        /// Analyzes decimal precision and scale from a parsed value.
        /// </summary>
        private void AnalyzeDecimalPrecision(string original, decimal value)
        {
            // Use the string representation to count actual digits
            // This handles scientific notation and trailing zeros correctly

            string normalized = original.Trim();

            // Remove sign
            if (normalized.StartsWith("-") || normalized.StartsWith("+"))
            {
                normalized = normalized.Substring(1);
            }

            // Handle scientific notation - fall back to string analysis of the decimal
            if (normalized.IndexOf('e') >= 0 || normalized.IndexOf('E') >= 0)
            {
                // Use decimal's string representation for scientific notation
                normalized = Math.Abs(value).ToString(CultureInfo.InvariantCulture);
            }

            // Remove thousands separators
            normalized = normalized.Replace(",", "").Replace(" ", "");

            // Find decimal point
            int decimalIndex = normalized.IndexOf('.');
            if (decimalIndex < 0)
            {
                // Use culture-specific decimal separator
                string decSep = _culture.NumberFormat.NumberDecimalSeparator;
                decimalIndex = normalized.IndexOf(decSep, StringComparison.Ordinal);
            }

            int integerDigits;
            int fractionalDigits;

            if (decimalIndex >= 0)
            {
                // Count integer part digits (excluding leading zeros for values < 1)
                string intPart = normalized.Substring(0, decimalIndex);
                integerDigits = CountSignificantDigits(intPart, true);

                // Count fractional digits (including trailing zeros as they indicate precision)
                string fracPart = normalized.Substring(decimalIndex + 1);
                fractionalDigits = fracPart.Length;
            }
            else
            {
                integerDigits = CountSignificantDigits(normalized, true);
                fractionalDigits = 0;
            }

            // Track maximums
            if (integerDigits > _maxIntegerDigits)
            {
                _maxIntegerDigits = integerDigits;
            }
            if (fractionalDigits > _maxScale)
            {
                _maxScale = fractionalDigits;
            }

            int totalPrecision = integerDigits + fractionalDigits;
            if (totalPrecision > _maxPrecision)
            {
                _maxPrecision = totalPrecision;
            }
        }

        /// <summary>
        /// Counts significant digits in a numeric string.
        /// </summary>
        private static int CountSignificantDigits(string value, bool isIntegerPart)
        {
            int count = 0;
            bool foundNonZero = false;

            foreach (char c in value)
            {
                if (char.IsDigit(c))
                {
                    if (isIntegerPart)
                    {
                        // For integer part, count after first non-zero (or all if it's just "0")
                        if (c != '0')
                        {
                            foundNonZero = true;
                        }
                        if (foundNonZero || value.Length == 1)
                        {
                            count++;
                        }
                    }
                    else
                    {
                        // For fractional part, count all digits
                        count++;
                    }
                }
            }

            return count > 0 ? count : 1; // At least 1 digit
        }

        /// <summary>
        /// Attempts to parse a value as DateTime using custom and standard formats.
        /// </summary>
        private bool TryParseDateTime(string value)
        {
            DateTimeStyles styles = DateTimeStyles.AllowWhiteSpaces;

            // Try custom formats first
            if (_customDateTimeFormats != null && _customDateTimeFormats.Length > 0)
            {
                if (DateTime.TryParseExact(value, _customDateTimeFormats, _culture, styles, out _))
                {
                    return true;
                }
            }

            // Try culture-native parsing before hardcoded formats so the culture's
            // own day/month ordering takes precedence (fixes de-CH dd.MM.yyyy vs MM.dd.yyyy)
            if (DateTime.TryParse(value, _culture, styles, out _))
            {
                return true;
            }

            // Fall back to standard formats for unusual patterns the culture doesn't cover
            return DateTime.TryParseExact(value, StandardDateTimeFormats, _culture, styles, out _);
        }
    }
}
