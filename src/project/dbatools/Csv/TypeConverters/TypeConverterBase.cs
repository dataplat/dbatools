using System;

namespace Dataplat.Dbatools.Csv.TypeConverters
{
    /// <summary>
    /// Base class for type converters providing common functionality.
    /// </summary>
    /// <typeparam name="T">The target type for conversion.</typeparam>
    public abstract class TypeConverterBase<T> : ITypeConverter<T>
    {
        /// <summary>
        /// Gets the type that this converter produces.
        /// </summary>
        public Type TargetType => typeof(T);

        /// <summary>
        /// Attempts to convert the string value to type T.
        /// </summary>
        public abstract bool TryConvert(string value, out T result);

        /// <summary>
        /// Converts the string value to type T.
        /// </summary>
        public virtual T Convert(string value)
        {
            if (TryConvert(value, out T result))
            {
                return result;
            }
            throw new FormatException($"Cannot convert '{value}' to {typeof(T).Name}");
        }

        bool ITypeConverter.TryConvert(string value, out object result)
        {
            if (TryConvert(value, out T typedResult))
            {
                result = typedResult;
                return true;
            }
            result = default(T);
            return false;
        }

        object ITypeConverter.Convert(string value) => Convert(value);
    }
}
