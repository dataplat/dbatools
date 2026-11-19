using System;

namespace Dataplat.Dbatools.Csv.TypeConverters
{
    /// <summary>
    /// Defines the interface for converting string values to typed values.
    /// </summary>
    public interface ITypeConverter
    {
        /// <summary>
        /// Gets the type that this converter produces.
        /// </summary>
        Type TargetType { get; }

        /// <summary>
        /// Attempts to convert the string value to the target type.
        /// </summary>
        /// <param name="value">The string value to convert.</param>
        /// <param name="result">When this method returns, contains the converted value if successful.</param>
        /// <returns>True if the conversion was successful; otherwise, false.</returns>
        bool TryConvert(string value, out object result);

        /// <summary>
        /// Converts the string value to the target type.
        /// </summary>
        /// <param name="value">The string value to convert.</param>
        /// <returns>The converted value.</returns>
        /// <exception cref="FormatException">Thrown when conversion fails.</exception>
        object Convert(string value);
    }

    /// <summary>
    /// Generic interface for type-safe conversion.
    /// </summary>
    /// <typeparam name="T">The target type.</typeparam>
    public interface ITypeConverter<T> : ITypeConverter
    {
        /// <summary>
        /// Attempts to convert the string value to type T.
        /// </summary>
        /// <param name="value">The string value to convert.</param>
        /// <param name="result">When this method returns, contains the converted value if successful.</param>
        /// <returns>True if the conversion was successful; otherwise, false.</returns>
        bool TryConvert(string value, out T result);

        /// <summary>
        /// Converts the string value to type T.
        /// </summary>
        /// <param name="value">The string value to convert.</param>
        /// <returns>The converted value.</returns>
        new T Convert(string value);
    }
}
