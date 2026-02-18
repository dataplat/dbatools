function New-DbaSqlParameter {
    <#
    .SYNOPSIS
        Creates a SqlParameter object for use with parameterized queries and stored procedures.

    .DESCRIPTION
        Creates a Microsoft.Data.SqlClient.SqlParameter object with specified properties like data type, direction, size, and value. This is essential for executing parameterized queries and stored procedures safely through Invoke-DbaQuery, preventing SQL injection while providing precise control over parameter behavior. Supports all SqlParameter properties including output parameters, table-valued parameters, and column encryption for secure data handling.

    .PARAMETER CompareInfo
        Defines how string comparisons are performed when this parameter is used in SQL operations. Controls case sensitivity, accent sensitivity, and other collation behaviors.
        Use this when you need specific string comparison rules that differ from the database's default collation settings.

    .PARAMETER DbType
        Specifies the .NET data type for the parameter using System.Data.DbType enumeration. This is an alternative to SqlDbType for cross-database compatibility.
        Use SqlDbType instead for SQL Server-specific operations, as it provides better type mapping and performance.

    .PARAMETER Direction
        Specifies whether the parameter passes data into the query (Input), returns data from a stored procedure (Output), or both (InputOutput).
        Required when creating output parameters for stored procedures that return values through parameters rather than result sets.

    .PARAMETER ForceColumnEncryption
        Enforces encryption of a parameter when using Always Encrypted.

        If SQL Server informs the driver that the parameter does not need to be encrypted, the query using the parameter will fail.

        This property provides additional protection against security attacks that involve a compromised SQL Server providing incorrect encryption metadata to the client, which may lead to data disclosure.

    .PARAMETER IsNullable
        Indicates whether the parameter can accept null values, but does not enforce null validation during query execution.
        This is primarily used for metadata purposes and DataAdapter operations, not for runtime null checking.

    .PARAMETER LocaleId
        Specifies the locale identifier (LCID) that determines regional formatting conventions for the parameter value.
        Use this when working with locale-specific data formatting, particularly for date, time, and numeric values that need specific regional representation.

    .PARAMETER Offset
        Specifies the starting position within the parameter value when working with binary or text data types.
        Useful when you need to read or write data starting from a specific byte position rather than the beginning of the value.

    .PARAMETER ParameterName
        Specifies the name of the parameter as it appears in the SQL query or stored procedure, including the '@' prefix.
        Must match exactly with parameter names defined in your SQL statements for proper parameter binding.

    .PARAMETER Precision
        Defines the total number of digits for numeric data types like decimal or numeric columns.
        Required when working with precise financial calculations or when the target column has specific precision requirements.

    .PARAMETER Scale
        Specifies the number of decimal places for numeric data types, working together with Precision.
        Essential for financial data and calculations where exact decimal representation is required to prevent rounding errors.

    .PARAMETER Size
        Defines the maximum length for variable-length data types like varchar, nvarchar, or varbinary columns.
        Use -1 for MAX data types (varchar(max), nvarchar(max)) to handle large text or binary data without size restrictions.

    .PARAMETER SourceColumn
        Maps the parameter to a specific column name in a DataTable or DataSet for bulk operations.
        Used primarily with DataAdapter operations when you need to map parameter values to specific columns during data updates.

    .PARAMETER SourceColumnNullMapping
        Indicates whether the source column allows null values, helping SqlCommandBuilder generate correct UPDATE statements.
        Important for DataAdapter scenarios where the framework needs to understand column nullability for proper SQL generation.

    .PARAMETER SourceVersion
        Specifies which version of data to use from a DataRow when the parameter value comes from a DataSet.
        Use 'Current' for modified data, 'Original' for unchanged data, or 'Proposed' for uncommitted changes during DataAdapter operations.

    .PARAMETER SqlDbType
        Specifies the SQL Server data type for the parameter, ensuring proper type mapping and optimal performance.
        Prefer this over DbType for SQL Server operations as it provides exact type matching with SQL Server's native data types.

    .PARAMETER SqlValue
        Sets the parameter value using SQL Server-specific data types (like SqlString, SqlInt32) instead of standard .NET types.
        Use this when you need to handle SQL null values explicitly or work with SQL Server-specific type behaviors that differ from .NET types.

    .PARAMETER TypeName
        Specifies the user-defined table type name when passing DataTable objects as table-valued parameters to stored procedures.
        The type name must match a table type defined in the database schema and is essential for bulk data operations.

    .PARAMETER UdtTypeName
        Specifies the name of a user-defined data type (UDT) or CLR type when working with custom SQL Server data types.
        Required when passing complex objects or custom data structures that extend beyond standard SQL Server data types.

    .PARAMETER Value
        Specifies the actual data value to pass to the SQL parameter, automatically handling type conversion from .NET to SQL types.
        The most commonly used parameter property for passing data into queries and stored procedures safely.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Microsoft.Data.SqlClient.SqlParameter

        Returns a single SqlParameter object configured with the specified properties. The returned parameter object is ready to be used with Invoke-DbaQuery or other data access operations that accept parameterized queries.

        Properties available on the returned object include:
        - CompareInfo: String comparison rules for the parameter
        - DbType: .NET data type from System.Data.DbType enumeration
        - Direction: Parameter direction (Input, Output, InputOutput, or ReturnValue)
        - ForceColumnEncryption: Boolean indicating Always Encrypted enforcement
        - IsNullable: Boolean indicating if parameter accepts null values
        - LocaleId: Integer locale identifier (LCID) for formatting
        - Offset: Starting position within parameter value for binary/text data
        - ParameterName: The name of the parameter (including '@' prefix)
        - Precision: Total number of digits for numeric types
        - Scale: Number of decimal places for numeric types
        - Size: Maximum length for variable-length data types (use -1 for MAX)
        - SourceColumn: Column name mapping for DataTable operations
        - SourceColumnNullMapping: Boolean for DataAdapter null mapping
        - SourceVersion: Data version selection (Original, Current, Proposed, Default)
        - SqlDbType: SQL Server-specific data type
        - SqlValue: Parameter value using SQL Server-specific types
        - TypeName: User-defined table type name for table-valued parameters
        - UdtTypeName: User-defined data type (UDT) or CLR type name
        - Value: The actual parameter value passed to SQL

    .NOTES
        Tags: Utility, Query
        Author: Chrissy LeMaire (@cl), netnerds.net
        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaSqlParameter

    .EXAMPLE
        PS C:\> New-DbaSqlParameter -ParameterName json_result -SqlDbType NVarChar -Size -1 -Direction Output

        Creates a SqlParameter object that can be used with Invoke-DbaQuery

    .EXAMPLE
        PS C:\> $output = New-DbaSqlParameter -ParameterName json_result -SqlDbType NVarChar -Size -1 -Direction Output
        PS C:\> Invoke-DbaQuery -SqlInstance localhost -Database master -CommandType StoredProcedure -Query my_proc -SqlParameter $output
        PS C:\> $output.Value

        Creates an output parameter and uses it to invoke a stored procedure.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet("None", "IgnoreCase", "IgnoreNonSpace", "IgnoreKanaType", "IgnoreWidth", "BinarySort2", "BinarySort")]
        [string]$CompareInfo,
        [ValidateSet("AnsiString", "Binary", "Byte", "Boolean", "Currency", "Date", "DateTime", "Decimal", "Double", "Guid", "Int16", "Int32", "Int64", "Object", "SByte", "Single", "String", "Time", "UInt16", "UInt32", "UInt64", "VarNumeric", "AnsiStringFixedLength", "StringFixedLength", "Xml", "DateTime2", "DateTimeOffset")]
        [string]$DbType,
        [ValidateSet("Input", "Output", "InputOutput", "ReturnValue")]
        [string]$Direction,
        [switch]$ForceColumnEncryption,
        [switch]$IsNullable,
        [int]$LocaleId,
        [string]$Offset,
        [Alias("Name")]
        [string]$ParameterName,
        [string]$Precision,
        [string]$Scale,
        [int]$Size,
        [string]$SourceColumn,
        [switch]$SourceColumnNullMapping,
        [ValidateSet("Original", "Current", "Proposed", "Default")]
        [string]$SourceVersion,
        [ValidateSet("BigInt", "Binary", "Bit", "Char", "DateTime", "Decimal", "Float", "Image", "Int", "Money", "NChar", "NText", "NVarChar", "Real", "UniqueIdentifier", "SmallDateTime", "SmallInt", "SmallMoney", "Text", "Timestamp", "TinyInt", "VarBinary", "VarChar", "Variant", "Xml", "Udt", "Structured", "Date", "Time", "DateTime2", "DateTimeOffset")]
        [string]$SqlDbType,
        [object]$SqlValue,
        [string]$TypeName,
        [string]$UdtTypeName,
        [object]$Value,
        [switch]$EnableException
    )

    $param = New-Object Microsoft.Data.SqlClient.SqlParameter

    try {

        if (Test-Bound -ParameterName CompareInfo) {
            $param.CompareInfo = $CompareInfo
        }

        if (Test-Bound -ParameterName DbType) {
            $param.DbType = $DbType
        }

        if (Test-Bound -ParameterName Direction) {
            $param.Direction = $Direction
        }

        if (Test-Bound -ParameterName ForceColumnEncryption) {
            $param.ForceColumnEncryption = $ForceColumnEncryption
        }

        if (Test-Bound -ParameterName IsNullable) {
            $param.IsNullable = $IsNullable
        }

        if (Test-Bound -ParameterName LocaleId) {
            $param.LocaleId = $LocaleId
        }

        if (Test-Bound -ParameterName Offset) {
            $param.Offset = $Offset
        }

        if (Test-Bound -ParameterName ParameterName) {
            $param.ParameterName = $ParameterName
        }

        if (Test-Bound -ParameterName Precision) {
            $param.Precision = $Precision
        }

        if (Test-Bound -ParameterName Scale) {
            $param.Scale = $Scale
        }

        if (Test-Bound -ParameterName Size) {
            $param.Size = $Size
        }

        if (Test-Bound -ParameterName SourceColumn) {
            $param.SourceColumn = $SourceColumn
        }

        if (Test-Bound -ParameterName SourceColumnNullMapping) {
            $param.SourceColumnNullMapping = $SourceColumnNullMapping
        }

        if (Test-Bound -ParameterName SourceVersion) {
            $param.SourceVersion = $SourceVersion
        }

        if (Test-Bound -ParameterName SqlDbType) {
            $param.SqlDbType = $SqlDbType
        }

        if (Test-Bound -ParameterName SqlValue) {
            $param.SqlValue = $SqlValue
        }

        if (Test-Bound -ParameterName TypeName) {
            $param.TypeName = $TypeName
        }

        if (Test-Bound -ParameterName UdtTypeName) {
            $param.UdtTypeName = $UdtTypeName
        }

        if (Test-Bound -ParameterName Value) {
            $param.Value = $Value
        }
        $param
    } catch {
        Stop-Function -Message "Failure" -ErrorRecord $_
        return
    }
}