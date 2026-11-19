using System;

namespace Dataplat.Dbatools.Csv.Reader
{
    /// <summary>
    /// Represents a static column that provides the same value for every row.
    /// Used for injecting metadata like filename, import date, etc.
    /// Addresses issue #6676: Static column mappings for storing/tagging metadata.
    /// </summary>
    public sealed class StaticColumn
    {
        /// <summary>
        /// Gets or sets the column name.
        /// </summary>
        public string Name { get; set; }

        /// <summary>
        /// Gets or sets the static value for this column.
        /// </summary>
        public object Value { get; set; }

        /// <summary>
        /// Gets or sets the data type of this column.
        /// </summary>
        public Type DataType { get; set; }

        /// <summary>
        /// Gets or sets a function that dynamically generates the value.
        /// If set, takes precedence over the static Value.
        /// The function receives the current record index.
        /// </summary>
        public Func<long, object> ValueGenerator { get; set; }

        /// <summary>
        /// Initializes a new instance of the StaticColumn class.
        /// </summary>
        public StaticColumn()
        {
            DataType = typeof(string);
        }

        /// <summary>
        /// Initializes a new instance with a name and value.
        /// </summary>
        public StaticColumn(string name, object value)
        {
            Name = name;
            Value = value;
            DataType = value?.GetType() ?? typeof(string);
        }

        /// <summary>
        /// Initializes a new instance with a name, value, and explicit type.
        /// </summary>
        public StaticColumn(string name, object value, Type dataType)
        {
            Name = name;
            Value = value;
            DataType = dataType ?? value?.GetType() ?? typeof(string);
        }

        /// <summary>
        /// Initializes a new instance with a dynamic value generator.
        /// </summary>
        public StaticColumn(string name, Func<long, object> valueGenerator, Type dataType)
        {
            Name = name;
            ValueGenerator = valueGenerator;
            DataType = dataType ?? typeof(object);
        }

        /// <summary>
        /// Gets the value for a specific record.
        /// </summary>
        public object GetValue(long recordIndex)
        {
            if (ValueGenerator != null)
            {
                return ValueGenerator(recordIndex);
            }
            return Value;
        }

        /// <summary>
        /// Creates a static column for storing the source file name.
        /// </summary>
        public static StaticColumn FileName(string name, string fileName)
        {
            return new StaticColumn(name, fileName, typeof(string));
        }

        /// <summary>
        /// Creates a static column for storing the import timestamp.
        /// </summary>
        public static StaticColumn ImportDate(string name)
        {
            DateTime importTime = DateTime.UtcNow;
            return new StaticColumn(name, importTime, typeof(DateTime));
        }

        /// <summary>
        /// Creates a static column for storing the row number (1-based).
        /// </summary>
        public static StaticColumn RowNumber(string name)
        {
            return new StaticColumn(name, (long recordIndex) => recordIndex + 1, typeof(long));
        }
    }
}
