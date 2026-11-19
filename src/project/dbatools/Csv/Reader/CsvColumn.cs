using System;
using Dataplat.Dbatools.Csv.TypeConverters;

namespace Dataplat.Dbatools.Csv.Reader
{
    /// <summary>
    /// Represents a column definition for CSV reading with optional type conversion.
    /// </summary>
    public sealed class CsvColumn
    {
        /// <summary>
        /// Gets or sets the column name (from header or auto-generated).
        /// </summary>
        public string Name { get; set; }

        /// <summary>
        /// Gets the zero-based ordinal index of the column in the output.
        /// </summary>
        public int Ordinal { get; internal set; }

        /// <summary>
        /// Gets the zero-based index of the source field in the CSV file.
        /// Used for mapping when columns are filtered or duplicates are handled.
        /// </summary>
        public int SourceIndex { get; internal set; }

        /// <summary>
        /// Gets or sets the target .NET type for this column.
        /// Defaults to string if not specified.
        /// </summary>
        public Type DataType { get; set; } = typeof(string);

        /// <summary>
        /// Gets or sets a custom type converter for this column.
        /// If null, the registry's converter for DataType will be used.
        /// </summary>
        public ITypeConverter Converter { get; set; }

        /// <summary>
        /// Gets or sets the cached converter for this column (resolved from Converter or registry).
        /// This is set internally during initialization to avoid per-row registry lookups.
        /// </summary>
        internal ITypeConverter CachedConverter { get; set; }

        /// <summary>
        /// Gets or sets whether this column allows null values.
        /// </summary>
        public bool AllowNull { get; set; } = true;

        /// <summary>
        /// Gets or sets the default value to use when the column value is null or empty.
        /// </summary>
        public object DefaultValue { get; set; }

        /// <summary>
        /// Gets or sets whether to use the default value for null/empty values.
        /// </summary>
        public bool UseDefaultForNull { get; set; }

        /// <summary>
        /// Initializes a new instance of the CsvColumn class.
        /// </summary>
        public CsvColumn()
        {
        }

        /// <summary>
        /// Initializes a new instance of the CsvColumn class with a name.
        /// </summary>
        public CsvColumn(string name)
        {
            Name = name;
        }

        /// <summary>
        /// Initializes a new instance of the CsvColumn class with a name and type.
        /// </summary>
        public CsvColumn(string name, Type dataType)
        {
            Name = name;
            DataType = dataType ?? typeof(string);
        }

        /// <summary>
        /// Initializes a new instance of the CsvColumn class with full configuration.
        /// </summary>
        public CsvColumn(string name, int ordinal, Type dataType)
        {
            Name = name;
            Ordinal = ordinal;
            DataType = dataType ?? typeof(string);
        }

        /// <summary>
        /// Returns a string representation of this column.
        /// </summary>
        public override string ToString()
        {
            return $"{Name} ({DataType.Name}) [{Ordinal}]";
        }
    }
}
