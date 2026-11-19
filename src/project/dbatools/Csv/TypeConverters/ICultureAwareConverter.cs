using System.Globalization;

namespace Dataplat.Dbatools.Csv.TypeConverters
{
    /// <summary>
    /// Interface for type converters that support culture-aware parsing.
    /// Converters implementing this interface can use custom CultureInfo for number and date parsing.
    /// </summary>
    public interface ICultureAwareConverter
    {
        /// <summary>
        /// Attempts to convert the string value to the target type using the specified culture.
        /// </summary>
        /// <param name="value">The string value to convert.</param>
        /// <param name="culture">The culture to use for parsing.</param>
        /// <param name="result">The converted value if successful.</param>
        /// <returns>True if conversion succeeded, false otherwise.</returns>
        bool TryConvert(string value, CultureInfo culture, out object result);
    }
}
