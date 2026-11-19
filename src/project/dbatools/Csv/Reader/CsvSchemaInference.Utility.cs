using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading;

namespace Dataplat.Dbatools.Csv.Reader
{
    public static partial class CsvSchemaInference
    {

        /// <summary>
        /// Generates a CREATE TABLE statement from inferred columns.
        /// </summary>
        /// <param name="columns">The inferred column definitions.</param>
        /// <param name="tableName">The name of the table to create.</param>
        /// <param name="schemaName">Optional schema name (default: dbo).</param>
        /// <returns>A CREATE TABLE SQL statement.</returns>
        public static string GenerateCreateTableStatement(List<InferredColumn> columns, string tableName, string schemaName = "dbo")
        {
            if (columns == null)
                throw new ArgumentNullException(nameof(columns));
            if (string.IsNullOrWhiteSpace(tableName))
                throw new ArgumentException("Table name is required.", nameof(tableName));

            var sb = new StringBuilder();
            // Escape ] as ]] to prevent SQL injection via identifier names
            string escapedSchema = schemaName?.Replace("]", "]]") ?? "dbo";
            string escapedTable = tableName.Replace("]", "]]");
            sb.AppendLine(string.Format("CREATE TABLE [{0}].[{1}]", escapedSchema, escapedTable));
            sb.AppendLine("(");

            bool first = true;
            foreach (var column in columns)
            {
                if (!first)
                {
                    sb.AppendLine(",");
                }
                first = false;

                sb.Append(string.Format("    {0}", column.ToSqlDefinition()));
            }

            sb.AppendLine();
            sb.AppendLine(");");

            return sb.ToString();
        }

        /// <summary>
        /// Converts inferred columns to a ColumnTypes dictionary for use with CsvReaderOptions.
        /// </summary>
        /// <param name="columns">The inferred column definitions.</param>
        /// <returns>A dictionary mapping column names to .NET types.</returns>
        public static Dictionary<string, Type> ToColumnTypes(List<InferredColumn> columns)
        {
            if (columns == null)
                throw new ArgumentNullException(nameof(columns));

            var result = new Dictionary<string, Type>(StringComparer.OrdinalIgnoreCase);

            foreach (var column in columns)
            {
                Type netType = SqlTypeToNetType(column.SqlDataType);
                result[column.ColumnName] = netType;
            }

            return result;
        }

        /// <summary>
        /// Maps SQL Server data type strings to .NET types.
        /// </summary>
        private static Type SqlTypeToNetType(string sqlType)
        {
            if (string.IsNullOrEmpty(sqlType))
                return typeof(string);

            // Normalize: remove parentheses and content
            string baseType = sqlType.ToLowerInvariant();
            int parenIndex = baseType.IndexOf('(');
            if (parenIndex > 0)
            {
                baseType = baseType.Substring(0, parenIndex);
            }

            switch (baseType)
            {
                case "bit":
                    return typeof(bool);
                case "int":
                    return typeof(int);
                case "bigint":
                    return typeof(long);
                case "smallint":
                    return typeof(short);
                case "tinyint":
                    return typeof(byte);
                case "decimal":
                case "numeric":
                case "money":
                case "smallmoney":
                    return typeof(decimal);
                case "float":
                    return typeof(double);
                case "real":
                    return typeof(float);
                case "datetime":
                case "datetime2":
                case "date":
                case "smalldatetime":
                    return typeof(DateTime);
                case "uniqueidentifier":
                    return typeof(Guid);
                default:
                    return typeof(string);
            }
        }

    }
}
