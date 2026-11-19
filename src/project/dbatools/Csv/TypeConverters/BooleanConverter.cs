using System;
using System.Collections.Generic;

namespace Dataplat.Dbatools.Csv.TypeConverters
{
    /// <summary>
    /// Converts string values to boolean values.
    /// Supports: true/false, yes/no, 1/0, on/off, y/n, t/f.
    /// </summary>
    public sealed class BooleanConverter : TypeConverterBase<bool>
    {
        private static readonly HashSet<string> TrueValues = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "true", "yes", "1", "on", "y", "t"
        };

        private static readonly HashSet<string> FalseValues = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "false", "no", "0", "off", "n", "f"
        };

        /// <summary>
        /// Gets the default instance of the boolean converter.
        /// </summary>
        public static BooleanConverter Default { get; } = new BooleanConverter();

        /// <summary>
        /// Gets or sets custom values that should be treated as true.
        /// </summary>
        public HashSet<string> CustomTrueValues { get; set; }

        /// <summary>
        /// Gets or sets custom values that should be treated as false.
        /// </summary>
        public HashSet<string> CustomFalseValues { get; set; }

        /// <summary>
        /// Attempts to convert the string value to a boolean.
        /// </summary>
        public override bool TryConvert(string value, out bool result)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                result = false;
                return false;
            }

            string trimmed = value.Trim();

            // Check custom values first
            if (CustomTrueValues != null && CustomTrueValues.Contains(trimmed))
            {
                result = true;
                return true;
            }

            if (CustomFalseValues != null && CustomFalseValues.Contains(trimmed))
            {
                result = false;
                return true;
            }

            // Check standard values
            if (TrueValues.Contains(trimmed))
            {
                result = true;
                return true;
            }

            if (FalseValues.Contains(trimmed))
            {
                result = false;
                return true;
            }

            result = false;
            return false;
        }
    }
}
