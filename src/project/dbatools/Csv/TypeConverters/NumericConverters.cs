using System;
using System.Globalization;

namespace Dataplat.Dbatools.Csv.TypeConverters
{
    /// <summary>
    /// Converts string values to Int16 (short) values.
    /// Supports culture-aware parsing.
    /// </summary>
    public sealed class Int16Converter : CultureAwareConverterBase<short>
    {
        /// <summary>Gets the default instance of the converter.</summary>
        public static Int16Converter Default { get; } = new Int16Converter();

        /// <summary>Initializes a new instance of the <see cref="Int16Converter"/> class.</summary>
        public Int16Converter()
        {
            NumberStyles = NumberStyles.Integer;
        }

        /// <inheritdoc />
        protected override bool TryParseCore(string value, NumberStyles styles, IFormatProvider provider, out short result)
            => short.TryParse(value, styles, provider, out result);

#if NET8_0_OR_GREATER
        /// <inheritdoc />
        protected override bool TryParseSpan(ReadOnlySpan<char> value, NumberStyles styles, IFormatProvider provider, out short result)
            => short.TryParse(value, styles, provider, out result);
#endif
    }

    /// <summary>
    /// Converts string values to Int32 (int) values.
    /// Supports culture-aware parsing.
    /// </summary>
    public sealed class Int32Converter : CultureAwareConverterBase<int>
    {
        /// <summary>Gets the default instance of the converter.</summary>
        public static Int32Converter Default { get; } = new Int32Converter();

        /// <summary>Initializes a new instance of the <see cref="Int32Converter"/> class.</summary>
        public Int32Converter()
        {
            NumberStyles = NumberStyles.Integer;
        }

        /// <inheritdoc />
        protected override bool TryParseCore(string value, NumberStyles styles, IFormatProvider provider, out int result)
            => int.TryParse(value, styles, provider, out result);

#if NET8_0_OR_GREATER
        /// <inheritdoc />
        protected override bool TryParseSpan(ReadOnlySpan<char> value, NumberStyles styles, IFormatProvider provider, out int result)
            => int.TryParse(value, styles, provider, out result);
#endif
    }

    /// <summary>
    /// Converts string values to Int64 (long) values.
    /// Supports culture-aware parsing.
    /// </summary>
    public sealed class Int64Converter : CultureAwareConverterBase<long>
    {
        /// <summary>Gets the default instance of the converter.</summary>
        public static Int64Converter Default { get; } = new Int64Converter();

        /// <summary>Initializes a new instance of the <see cref="Int64Converter"/> class.</summary>
        public Int64Converter()
        {
            NumberStyles = NumberStyles.Integer;
        }

        /// <inheritdoc />
        protected override bool TryParseCore(string value, NumberStyles styles, IFormatProvider provider, out long result)
            => long.TryParse(value, styles, provider, out result);

#if NET8_0_OR_GREATER
        /// <inheritdoc />
        protected override bool TryParseSpan(ReadOnlySpan<char> value, NumberStyles styles, IFormatProvider provider, out long result)
            => long.TryParse(value, styles, provider, out result);
#endif
    }

    /// <summary>
    /// Converts string values to Single (float) values.
    /// Supports culture-aware parsing for decimal separators.
    /// </summary>
    public sealed class SingleConverter : CultureAwareConverterBase<float>
    {
        /// <summary>Gets the default instance of the converter.</summary>
        public static SingleConverter Default { get; } = new SingleConverter();

        /// <summary>Initializes a new instance of the <see cref="SingleConverter"/> class.</summary>
        public SingleConverter()
        {
            NumberStyles = NumberStyles.Float | NumberStyles.AllowThousands;
        }

        /// <inheritdoc />
        protected override bool TryParseCore(string value, NumberStyles styles, IFormatProvider provider, out float result)
            => float.TryParse(value, styles, provider, out result);

#if NET8_0_OR_GREATER
        /// <inheritdoc />
        protected override bool TryParseSpan(ReadOnlySpan<char> value, NumberStyles styles, IFormatProvider provider, out float result)
            => float.TryParse(value, styles, provider, out result);
#endif
    }

    /// <summary>
    /// Converts string values to Double values.
    /// Supports culture-aware parsing for decimal separators.
    /// </summary>
    public sealed class DoubleConverter : CultureAwareConverterBase<double>
    {
        /// <summary>Gets the default instance of the converter.</summary>
        public static DoubleConverter Default { get; } = new DoubleConverter();

        /// <summary>Initializes a new instance of the <see cref="DoubleConverter"/> class.</summary>
        public DoubleConverter()
        {
            NumberStyles = NumberStyles.Float | NumberStyles.AllowThousands;
        }

        /// <inheritdoc />
        protected override bool TryParseCore(string value, NumberStyles styles, IFormatProvider provider, out double result)
            => double.TryParse(value, styles, provider, out result);

#if NET8_0_OR_GREATER
        /// <inheritdoc />
        protected override bool TryParseSpan(ReadOnlySpan<char> value, NumberStyles styles, IFormatProvider provider, out double result)
            => double.TryParse(value, styles, provider, out result);
#endif
    }

    /// <summary>
    /// Converts string values to Decimal values.
    /// Supports culture-aware parsing for decimal separators, thousands separators, and scientific notation.
    /// Addresses LumenWorks issue #66 for Czech locale decimal parsing.
    /// <para>
    /// Note: Uses NumberStyles.Float | NumberStyles.AllowThousands, which enables parsing of:
    /// - Scientific notation (e.g., "1.23E5")
    /// - Thousands separators (e.g., "1,234.56")
    /// This may allow values that were previously rejected. If you need strict parsing without
    /// thousands separators, use a custom DecimalConverter with NumberStyles.Float only.
    /// </para>
    /// </summary>
    public sealed class DecimalConverter : CultureAwareConverterBase<decimal>
    {
        /// <summary>Gets the default instance of the converter.</summary>
        public static DecimalConverter Default { get; } = new DecimalConverter();

        /// <summary>Initializes a new instance of the <see cref="DecimalConverter"/> class.</summary>
        public DecimalConverter()
        {
            NumberStyles = NumberStyles.Float | NumberStyles.AllowThousands;
        }

        /// <inheritdoc />
        protected override bool TryParseCore(string value, NumberStyles styles, IFormatProvider provider, out decimal result)
            => decimal.TryParse(value, styles, provider, out result);

#if NET8_0_OR_GREATER
        /// <inheritdoc />
        protected override bool TryParseSpan(ReadOnlySpan<char> value, NumberStyles styles, IFormatProvider provider, out decimal result)
            => decimal.TryParse(value, styles, provider, out result);
#endif
    }

    /// <summary>
    /// Converts string values to Byte values.
    /// Supports culture-aware parsing.
    /// </summary>
    public sealed class ByteConverter : CultureAwareConverterBase<byte>
    {
        /// <summary>Gets the default instance of the converter.</summary>
        public static ByteConverter Default { get; } = new ByteConverter();

        /// <summary>Initializes a new instance of the <see cref="ByteConverter"/> class.</summary>
        public ByteConverter()
        {
            NumberStyles = NumberStyles.Integer;
        }

        /// <inheritdoc />
        protected override bool TryParseCore(string value, NumberStyles styles, IFormatProvider provider, out byte result)
            => byte.TryParse(value, styles, provider, out result);

#if NET8_0_OR_GREATER
        /// <inheritdoc />
        protected override bool TryParseSpan(ReadOnlySpan<char> value, NumberStyles styles, IFormatProvider provider, out byte result)
            => byte.TryParse(value, styles, provider, out result);
#endif
    }

    /// <summary>
    /// Converts string values to Decimal values with currency symbol support.
    /// Supports culture-aware parsing for currency symbols, decimal separators, thousands separators,
    /// accounting format (negative values in parentheses), and scientific notation.
    /// Designed for SQL Server money and smallmoney data types.
    /// <para>
    /// Note: This converter is NOT registered by default in TypeConverterRegistry because it targets
    /// the same type (decimal) as DecimalConverter. To use this converter for columns containing
    /// currency symbols, you must clone the registry and register it manually:
    /// </para>
    /// <example>
    /// <code>
    /// // Clone the default registry to avoid modifying the global singleton
    /// var registry = TypeConverterRegistry.Default.Clone();
    /// registry.Register(MoneyConverter.Default);
    /// // Use this custom registry with your CSV reader
    /// </code>
    /// </example>
    /// </summary>
    public sealed class MoneyConverter : CultureAwareConverterBase<decimal>
    {
        /// <summary>Gets the default instance of the converter.</summary>
        public static MoneyConverter Default { get; } = new MoneyConverter();

        /// <summary>Initializes a new instance of the <see cref="MoneyConverter"/> class.</summary>
        public MoneyConverter()
        {
            NumberStyles = NumberStyles.Currency;
        }

        /// <inheritdoc />
        protected override bool TryParseCore(string value, NumberStyles styles, IFormatProvider provider, out decimal result)
            => decimal.TryParse(value, styles, provider, out result);

#if NET8_0_OR_GREATER
        /// <inheritdoc />
        protected override bool TryParseSpan(ReadOnlySpan<char> value, NumberStyles styles, IFormatProvider provider, out decimal result)
            => decimal.TryParse(value, styles, provider, out result);
#endif
    }
}
