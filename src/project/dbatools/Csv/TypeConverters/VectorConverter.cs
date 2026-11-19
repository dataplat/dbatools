using System;
using System.Globalization;

namespace Dataplat.Dbatools.Csv.TypeConverters
{
    /// <summary>
    /// Converts string values to float arrays for SQL Server 2025 VECTOR data type.
    /// Supports JSON array format: "[0.1, 0.2, 0.3, ...]"
    /// Supports comma-separated format: "0.1, 0.2, 0.3, ..."
    /// </summary>
    public sealed class VectorConverter : TypeConverterBase<float[]>
    {
        /// <summary>Cached separator array for Split operations to avoid repeated allocations.</summary>
        private static readonly char[] CommaSeparator = new[] { ',' };

        /// <summary>Gets the default instance of the converter.</summary>
        public static VectorConverter Default { get; } = new VectorConverter();

        /// <summary>
        /// Gets or sets the format provider to use for parsing individual float values.
        /// Defaults to InvariantCulture.
        /// </summary>
        public IFormatProvider FormatProvider { get; set; } = CultureInfo.InvariantCulture;

        /// <summary>
        /// Attempts to convert the string value to a float array.
        /// Supports both JSON array format "[0.1, 0.2]" and comma-separated format "0.1, 0.2"
        /// </summary>
        public override bool TryConvert(string value, out float[] result)
        {
            result = null;

            if (string.IsNullOrWhiteSpace(value))
            {
                return false;
            }

            // Trim whitespace
            value = value.Trim();

            // Check for JSON array format and strip brackets
            if (value.StartsWith("[") && value.EndsWith("]") && value.Length >= 2)
            {
                value = value.Substring(1, value.Length - 2);
            }

            // Split by comma and parse each value
            string[] parts = value.Split(CommaSeparator, StringSplitOptions.RemoveEmptyEntries);

            if (parts.Length == 0)
            {
                return false;
            }

            float[] vector = new float[parts.Length];

            for (int i = 0; i < parts.Length; i++)
            {
                string part = parts[i].Trim();

                // Try parsing with Float styles to support scientific notation
                if (!float.TryParse(part, NumberStyles.Float | NumberStyles.AllowThousands, FormatProvider, out vector[i]))
                {
                    return false;
                }
            }

            result = vector;
            return true;
        }
    }
}
