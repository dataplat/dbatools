using System;

namespace Dataplat.Dbatools.Csv.TypeConverters
{
    /// <summary>
    /// Converts string values to GUID values.
    /// Supports standard GUID formats: N, D, B, P, X.
    /// </summary>
    public sealed class GuidConverter : TypeConverterBase<Guid>
    {
        /// <summary>
        /// Gets the default instance of the GUID converter.
        /// </summary>
        public static GuidConverter Default { get; } = new GuidConverter();

        /// <summary>
        /// Attempts to convert the string value to a GUID.
        /// </summary>
        public override bool TryConvert(string value, out Guid result)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                result = Guid.Empty;
                return false;
            }

            return Guid.TryParse(value.Trim(), out result);
        }
    }
}
