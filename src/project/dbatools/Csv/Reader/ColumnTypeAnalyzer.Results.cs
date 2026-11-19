using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Csv.Reader
{
    internal sealed partial class ColumnTypeAnalyzer
    {
        /// <summary>
        /// Returns the inferred column based on all analyzed values.
        /// </summary>
        public InferredColumn GetInferredColumn()
        {
            var column = new InferredColumn
            {
                ColumnName = _columnName,
                Ordinal = _ordinal,
                TotalCount = _totalCount,
                NonNullCount = _totalCount - _nullCount,
                IsNullable = _nullCount > 0,
                IsUnicode = _hasUnicode,
                MaxLength = _maxLength
            };

            // If all values were null/empty
            if (_totalCount == _nullCount)
            {
                column.SqlDataType = "varchar(1)";
                column.IsNullable = true;
                return column;
            }

            // Determine type in priority order
            // Priority: GUID > Int > BigInt > Decimal > DateTime > Boolean > String
            // Note: Int/BigInt are checked before Boolean because "1" and "0" are valid for both,
            // and integer types are more restrictive (if we saw "2", boolean is eliminated but int remains)

            if ((_possibleTypes & PossibleTypes.Guid) != 0)
            {
                column.SqlDataType = "uniqueidentifier";
            }
            else if ((_possibleTypes & PossibleTypes.Int) != 0)
            {
                column.SqlDataType = "int";
            }
            else if ((_possibleTypes & PossibleTypes.BigInt) != 0)
            {
                column.SqlDataType = "bigint";
            }
            else if ((_possibleTypes & PossibleTypes.Decimal) != 0)
            {
                // Calculate SQL decimal precision and scale
                // SQL Server decimal: precision 1-38, scale 0-precision
                int precision = _maxIntegerDigits + _maxScale;
                int scale = _maxScale;

                // Ensure valid SQL Server decimal bounds
                if (precision < 1) precision = 1;
                if (precision > 38) precision = 38;
                if (scale > precision) scale = precision;
                if (scale < 0) scale = 0;

                // If it's effectively an integer in decimal form
                if (scale == 0 && precision <= 10 && (_possibleTypes & PossibleTypes.Int) != 0)
                {
                    column.SqlDataType = "int";
                }
                else if (scale == 0 && precision <= 19 && (_possibleTypes & PossibleTypes.BigInt) != 0)
                {
                    column.SqlDataType = "bigint";
                }
                else
                {
                    column.SqlDataType = String.Format("decimal({0},{1})", precision, scale);
                    column.Precision = precision;
                    column.Scale = scale;
                }
            }
            else if ((_possibleTypes & PossibleTypes.Boolean) != 0)
            {
                column.SqlDataType = "bit";
            }
            else if ((_possibleTypes & PossibleTypes.DateTime) != 0)
            {
                column.SqlDataType = "datetime2";
            }
            else
            {
                // Fall back to string type
                column.SqlDataType = GetStringType(column);
            }

            return column;
        }

        /// <summary>
        /// Determines the appropriate string type (varchar/nvarchar with length).
        /// </summary>
        private string GetStringType(InferredColumn column)
        {
            string baseType = _hasUnicode ? "nvarchar" : "varchar";
            int maxAllowed = _hasUnicode ? 4000 : 8000;

            if (_maxLength == 0)
            {
                return String.Format("{0}(1)", baseType);
            }
            else if (_maxLength > maxAllowed)
            {
                return String.Format("{0}(max)", baseType);
            }
            else
            {
                return String.Format("{0}({1})", baseType, _maxLength);
            }
        }
    }
}
