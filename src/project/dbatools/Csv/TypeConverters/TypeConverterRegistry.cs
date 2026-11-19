using System;
using System.Collections.Generic;

namespace Dataplat.Dbatools.Csv.TypeConverters
{
    /// <summary>
    /// Registry for type converters used during CSV parsing.
    /// Provides automatic type conversion based on target column types.
    /// </summary>
    public sealed class TypeConverterRegistry
    {
        private readonly Dictionary<Type, ITypeConverter> _converters = new Dictionary<Type, ITypeConverter>();
        private readonly bool _isReadOnly;

        // Internal shared instance that contains the default converters
        private static readonly TypeConverterRegistry _sharedDefault = CreateDefault();

        /// <summary>
        /// Gets a new registry instance with all built-in converters registered.
        /// Each call returns a new instance to prevent shared state mutation issues.
        /// </summary>
        public static TypeConverterRegistry Default => _sharedDefault.Clone();

        /// <summary>
        /// Creates an empty registry. Use this to build a custom registry from scratch.
        /// </summary>
        public TypeConverterRegistry()
        {
        }

        private TypeConverterRegistry(bool isReadOnly)
        {
            _isReadOnly = isReadOnly;
        }

        private static TypeConverterRegistry CreateDefault()
        {
            var registry = new TypeConverterRegistry(isReadOnly: true);

            // Register all built-in converters (internal registration bypasses read-only check)
            registry._converters[typeof(Guid)] = GuidConverter.Default;
            registry._converters[typeof(bool)] = BooleanConverter.Default;
            registry._converters[typeof(DateTime)] = DateTimeConverter.Default;
            registry._converters[typeof(short)] = Int16Converter.Default;
            registry._converters[typeof(int)] = Int32Converter.Default;
            registry._converters[typeof(long)] = Int64Converter.Default;
            registry._converters[typeof(float)] = SingleConverter.Default;
            registry._converters[typeof(double)] = DoubleConverter.Default;
            registry._converters[typeof(decimal)] = DecimalConverter.Default;
            registry._converters[typeof(byte)] = ByteConverter.Default;
            registry._converters[typeof(string)] = new StringConverter();
            registry._converters[typeof(float[])] = VectorConverter.Default;

            return registry;
        }

        /// <summary>
        /// Registers a type converter for its target type.
        /// </summary>
        /// <exception cref="InvalidOperationException">Thrown when the registry is read-only.</exception>
        public void Register(ITypeConverter converter)
        {
            if (converter == null) throw new ArgumentNullException(nameof(converter));
            ThrowIfReadOnly();
            _converters[converter.TargetType] = converter;
        }

        /// <summary>
        /// Registers a type converter for a specific type.
        /// </summary>
        /// <exception cref="InvalidOperationException">Thrown when the registry is read-only.</exception>
        public void Register<T>(ITypeConverter<T> converter)
        {
            if (converter == null) throw new ArgumentNullException(nameof(converter));
            ThrowIfReadOnly();
            _converters[typeof(T)] = converter;
        }

        private void ThrowIfReadOnly()
        {
            if (_isReadOnly)
                throw new InvalidOperationException("This registry instance is read-only. Use Clone() to create a modifiable copy.");
        }

        /// <summary>
        /// Gets a converter for the specified type.
        /// </summary>
        /// <returns>The converter, or null if no converter is registered for the type.</returns>
        public ITypeConverter GetConverter(Type type)
        {
            if (type == null) throw new ArgumentNullException(nameof(type));

            // Handle nullable types
            Type underlyingType = Nullable.GetUnderlyingType(type);
            if (underlyingType != null)
            {
                type = underlyingType;
            }

            _converters.TryGetValue(type, out ITypeConverter converter);
            return converter;
        }

        /// <summary>
        /// Gets a typed converter for the specified type.
        /// </summary>
        public ITypeConverter<T> GetConverter<T>()
        {
            return GetConverter(typeof(T)) as ITypeConverter<T>;
        }

        /// <summary>
        /// Attempts to convert a string value to the specified type.
        /// </summary>
        public bool TryConvert(string value, Type targetType, out object result)
        {
            if (targetType == null) throw new ArgumentNullException(nameof(targetType));

            // Handle null/empty for nullable types
            Type underlyingType = Nullable.GetUnderlyingType(targetType);
            if (underlyingType != null && string.IsNullOrEmpty(value))
            {
                result = null;
                return true;
            }

            // Handle string type directly
            if (targetType == typeof(string))
            {
                result = value;
                return true;
            }

            var converter = GetConverter(targetType);
            if (converter != null)
            {
                return converter.TryConvert(value, out result);
            }

            // Fall back to Convert.ChangeType
            try
            {
                result = Convert.ChangeType(value, underlyingType ?? targetType);
                return true;
            }
            catch (Exception ex) when (ex is FormatException || ex is InvalidCastException || ex is OverflowException)
            {
                result = null;
                return false;
            }
        }

        /// <summary>
        /// Creates a new modifiable registry with the same converters.
        /// </summary>
        public TypeConverterRegistry Clone()
        {
            var clone = new TypeConverterRegistry();
            foreach (var kvp in _converters)
            {
                clone._converters[kvp.Key] = kvp.Value;
            }
            return clone;
        }

        /// <summary>
        /// Gets whether this registry is read-only.
        /// </summary>
        public bool IsReadOnly => _isReadOnly;
    }

    /// <summary>
    /// Pass-through converter for string values.
    /// </summary>
    internal sealed class StringConverter : TypeConverterBase<string>
    {
        public override bool TryConvert(string value, out string result)
        {
            result = value;
            return true;
        }
    }
}
