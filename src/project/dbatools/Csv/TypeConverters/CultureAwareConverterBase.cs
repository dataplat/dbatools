using System;
using System.Globalization;
using System.Runtime.CompilerServices;

namespace Dataplat.Dbatools.Csv.TypeConverters
{
    /// <summary>
    /// Base class for type converters that support culture-aware numeric parsing.
    /// Provides common functionality for NumberStyles and FormatProvider handling.
    /// </summary>
    /// <typeparam name="T">The target numeric type for conversion.</typeparam>
    public abstract class CultureAwareConverterBase<T> : TypeConverterBase<T>, ICultureAwareConverter
        where T : struct
    {
        /// <summary>
        /// Gets or sets the number styles to use for parsing.
        /// </summary>
        public NumberStyles NumberStyles { get; set; }

        /// <summary>
        /// Gets or sets the format provider to use for parsing.
        /// Defaults to InvariantCulture.
        /// </summary>
        public IFormatProvider FormatProvider { get; set; } = CultureInfo.InvariantCulture;

        /// <summary>
        /// Attempts to convert the string value to the target type.
        /// </summary>
        public override bool TryConvert(string value, out T result)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                result = default;
                return false;
            }
#if NET8_0_OR_GREATER
            // Use Span-based parsing to avoid Trim() allocation
            return TryParseSpan(value.AsSpan().Trim(), NumberStyles, FormatProvider, out result);
#else
            // Avoid allocation when string is already trimmed
            string trimmed = GetTrimmedValue(value);
            return TryParseCore(trimmed, NumberStyles, FormatProvider, out result);
#endif
        }

        /// <summary>
        /// Attempts to convert the string value using the specified culture.
        /// </summary>
        public bool TryConvert(string value, CultureInfo culture, out object result)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                result = default(T);
                return false;
            }
#if NET8_0_OR_GREATER
            // Use Span-based parsing to avoid Trim() allocation
            if (TryParseSpan(value.AsSpan().Trim(), NumberStyles, culture ?? FormatProvider, out T parsed))
            {
                result = parsed;
                return true;
            }
#else
            // Avoid allocation when string is already trimmed
            string trimmed = GetTrimmedValue(value);
            if (TryParseCore(trimmed, NumberStyles, culture ?? FormatProvider, out T parsed))
            {
                result = parsed;
                return true;
            }
#endif
            result = default(T);
            return false;
        }

        /// <summary>
        /// Gets the trimmed value, avoiding allocation when the string is already trimmed.
        /// </summary>
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private static string GetTrimmedValue(string value)
        {
            // Fast path: check if trimming is actually needed
            if (value.Length > 0 && !char.IsWhiteSpace(value[0]) && !char.IsWhiteSpace(value[value.Length - 1]))
            {
                return value;
            }
            return value.Trim();
        }

#if NET8_0_OR_GREATER
        /// <summary>
        /// Span-based parsing implementation for .NET 8+. Override this in derived classes
        /// to provide type-specific parsing using the Span-based TryParse overloads.
        /// </summary>
        protected abstract bool TryParseSpan(ReadOnlySpan<char> value, NumberStyles styles, IFormatProvider provider, out T result);
#endif

        /// <summary>
        /// Core parsing implementation. Override this in derived classes to provide
        /// type-specific parsing using the appropriate TryParse method.
        /// </summary>
        /// <param name="value">The trimmed string value to parse.</param>
        /// <param name="styles">The number styles to use.</param>
        /// <param name="provider">The format provider to use.</param>
        /// <param name="result">The parsed result if successful.</param>
        /// <returns>True if parsing succeeded, false otherwise.</returns>
        protected abstract bool TryParseCore(string value, NumberStyles styles, IFormatProvider provider, out T result);
    }
}
