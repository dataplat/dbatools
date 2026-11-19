namespace Dataplat.Dbatools.Csv.Reader
{
    /// <summary>
    /// Represents the inferred SQL Server schema for a CSV column.
    /// </summary>
    public sealed class InferredColumn
    {
        /// <summary>
        /// Gets or sets the column name from the CSV header.
        /// </summary>
        public string ColumnName { get; set; }

        /// <summary>
        /// Gets or sets the inferred SQL Server data type.
        /// Examples: "int", "bigint", "varchar(47)", "nvarchar(255)", "datetime2", "bit", "uniqueidentifier", "decimal(18,4)"
        /// </summary>
        public string SqlDataType { get; set; }

        /// <summary>
        /// Gets or sets the maximum length observed for string types.
        /// For non-string types, this is 0.
        /// </summary>
        public int MaxLength { get; set; }

        /// <summary>
        /// Gets or sets whether the column contains null or empty values.
        /// When true, the SQL column should allow NULLs.
        /// </summary>
        public bool IsNullable { get; set; }

        /// <summary>
        /// Gets or sets whether non-ASCII (Unicode) characters were detected.
        /// When true, nvarchar should be used instead of varchar.
        /// </summary>
        public bool IsUnicode { get; set; }

        /// <summary>
        /// Gets or sets the precision for decimal types.
        /// Total number of digits (before + after decimal point).
        /// </summary>
        public int Precision { get; set; }

        /// <summary>
        /// Gets or sets the scale for decimal types.
        /// Number of digits after the decimal point.
        /// </summary>
        public int Scale { get; set; }

        /// <summary>
        /// Gets the zero-based ordinal position of this column.
        /// </summary>
        public int Ordinal { get; internal set; }

        /// <summary>
        /// Gets or sets the number of distinct non-null values sampled.
        /// Useful for estimating cardinality.
        /// </summary>
        public long NonNullCount { get; set; }

        /// <summary>
        /// Gets or sets the total number of values examined for this column.
        /// </summary>
        public long TotalCount { get; set; }

        /// <summary>
        /// Returns a string representation of this inferred column.
        /// </summary>
        public override string ToString()
        {
            string nullability = IsNullable ? " NULL" : " NOT NULL";
            return $"{ColumnName} {SqlDataType}{nullability}";
        }

        /// <summary>
        /// Gets the full SQL column definition suitable for CREATE TABLE.
        /// </summary>
        /// <param name="quoted">Whether to quote the column name with square brackets.</param>
        /// <returns>A SQL column definition string.</returns>
        public string ToSqlDefinition(bool quoted = true)
        {
            // Escape ] as ]] to prevent SQL injection via column names
            string escapedName = ColumnName?.Replace("]", "]]") ?? "";
            string name = quoted ? $"[{escapedName}]" : escapedName;
            string nullability = IsNullable ? "NULL" : "NOT NULL";
            return $"{name} {SqlDataType} {nullability}";
        }
    }
}
