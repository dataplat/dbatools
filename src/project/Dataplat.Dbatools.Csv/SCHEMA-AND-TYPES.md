# Schema Inference and Typed Columns

[Back to README](README.md)

### Schema Inference

Automatically detect optimal SQL Server column types from CSV data. No more `nvarchar(MAX)` for everything:

```csharp
using Dataplat.Dbatools.Csv.Reader;

// Fast: Sample first 1000 rows (tiny risk if data changes after sample)
var columns = CsvSchemaInference.InferSchemaFromSample("data.csv");

// Safe: Scan entire file with progress reporting (zero risk of type mismatches)
var columns = CsvSchemaInference.InferSchema("data.csv", null, progress => {
    Console.WriteLine($"Progress: {progress:P0}");
});

// Examine inferred types
foreach (var col in columns)
{
    Console.WriteLine($"{col.ColumnName}: {col.SqlDataType} {(col.IsNullable ? "NULL" : "NOT NULL")}");
}
// Output:
// Id: int NOT NULL
// Name: nvarchar(100) NULL
// Price: decimal(10,2) NOT NULL
// Created: datetime2 NULL

// Generate CREATE TABLE statement
string sql = CsvSchemaInference.GenerateCreateTableStatement(columns, "Products", "dbo");
// CREATE TABLE [dbo].[Products] (
//     [Id] int NOT NULL,
//     [Name] nvarchar(100) NULL,
//     [Price] decimal(10,2) NOT NULL,
//     [Created] datetime2 NULL
// );

// Use inferred types with CsvDataReader
var typeMap = CsvSchemaInference.ToColumnTypes(columns);
var options = new CsvReaderOptions { ColumnTypes = typeMap };
using var reader = new CsvDataReader("data.csv", options);
```

**Detected types:** `uniqueidentifier`, `bit`, `int`, `bigint`, `decimal(p,s)`, `datetime2`, `varchar(n)`, `nvarchar(n)` (when Unicode is detected)

**InferredColumn properties:**

| Property | Type | Description |
|----------|------|-------------|
| `ColumnName` | string | Column header name |
| `SqlDataType` | string | SQL Server data type (e.g., `int`, `decimal(10,2)`, `nvarchar(50)`) |
| `IsNullable` | bool | True if any NULL/empty values were found |
| `IsUnicode` | bool | True if non-ASCII characters detected |
| `MaxLength` | int | Maximum string length observed |
| `Precision` | int | Decimal precision (total digits) |
| `Scale` | int | Decimal scale (digits after decimal point) |
| `Ordinal` | int | Column position (0-based) |
| `TotalCount` | long | Total rows analyzed |
| `NonNullCount` | long | Rows with non-null values |

### Strongly Typed Columns

Define column types explicitly for automatic conversion during reading:

```csharp
var options = new CsvReaderOptions
{
    ColumnTypes = new Dictionary<string, Type>
    {
        ["Id"] = typeof(int),
        ["Price"] = typeof(decimal),
        ["IsActive"] = typeof(bool),
        ["Created"] = typeof(DateTime),
        ["UniqueId"] = typeof(Guid)
    }
};

using var reader = new CsvDataReader("data.csv", options);
while (reader.Read())
{
    int id = reader.GetInt32(0);           // Already converted from string
    decimal price = reader.GetDecimal(1);  // Culture-aware parsing
    bool active = reader.GetBoolean(2);    // Handles true/false/yes/no/1/0
    DateTime created = reader.GetDateTime(3);
    Guid guid = reader.GetGuid(4);
}
```

**Built-in type converters:** `Guid`, `bool`, `DateTime`, `short`, `int`, `long`, `float`, `double`, `decimal`, `byte`, `string`, `money`, `vector` (SQL Server 2025)

**Combine with schema inference:**

```csharp
// Infer types from CSV data, then use them for reading
var columns = CsvSchemaInference.InferSchemaFromSample("data.csv");
var typeMap = CsvSchemaInference.ToColumnTypes(columns);

var options = new CsvReaderOptions { ColumnTypes = typeMap };
using var reader = new CsvDataReader("data.csv", options);
```

**Custom type converters:**

```csharp
using Dataplat.Dbatools.Csv.TypeConverters;

// Create a custom converter for enums or custom types
public class StatusConverter : TypeConverterBase<OrderStatus>
{
    public override bool TryConvert(string value, out OrderStatus result)
    {
        return Enum.TryParse(value, true, out result);
    }
}

// Register and use
var registry = TypeConverterRegistry.Default;
registry.Register(new StatusConverter());

var options = new CsvReaderOptions
{
    TypeConverterRegistry = registry,
    ColumnTypes = new Dictionary<string, Type> { ["Status"] = typeof(OrderStatus) }
};
```

### Null vs Empty String Handling

CSV files can represent missing data in two ways: an empty field (`,,`) or an explicitly quoted empty string (`,"",...`). The `DistinguishEmptyFromNull` option controls how these are interpreted.

**Example CSV:**
```csv
Name,Description,Notes
Alice,,""
Bob,"",
Charlie,"Has value","Also has value"
```

**Default behavior (`DistinguishEmptyFromNull = false`):**

Both empty fields and quoted empty strings become empty string (`""`):

```csharp
var options = new CsvReaderOptions { DistinguishEmptyFromNull = false }; // default
using var reader = new CsvDataReader("data.csv", options);

reader.Read(); // Alice row
reader.IsDBNull(1);  // false - Description is ""
reader.IsDBNull(2);  // false - Notes is ""
reader.GetString(1); // ""
reader.GetString(2); // ""
```

**With `DistinguishEmptyFromNull = true`:**

Empty fields become `null`, quoted empty strings remain empty string:

```csharp
var options = new CsvReaderOptions { DistinguishEmptyFromNull = true };
using var reader = new CsvDataReader("data.csv", options);

reader.Read(); // Alice row
reader.IsDBNull(1);  // true  - Description (,,) is NULL
reader.IsDBNull(2);  // false - Notes ("") is empty string
reader.GetString(1); // throws InvalidCastException (value is null)
reader.GetValue(1);  // DBNull.Value
reader.GetString(2); // ""
```

**When to use this option:**

| Use Case | Recommendation |
|----------|----------------|
| SQL bulk import where NULL matters | Enable (`true`) |
| Database columns with NOT NULL constraints | Disable (`false`) - default |
| Preserving exact semantics from source system | Enable (`true`) |
| Simple data processing | Disable (`false`) - default |

**Quick reference:**

| CSV Input | `DistinguishEmptyFromNull = false` | `DistinguishEmptyFromNull = true` |
|-----------|-----------------------------------|----------------------------------|
| `,,` (empty field) | `""` (empty string) | `null` (DBNull.Value) |
| `,"",` (quoted empty) | `""` (empty string) | `""` (empty string) |
| `,value,` | `"value"` | `"value"` |

### LumenWorks Compatibility

For projects migrating from LumenWorks CsvReader, these methods provide familiar APIs:

```csharp
using var reader = new CsvDataReader("data.csv");

while (reader.Read())
{
    // Get column index by name (-1 if not found, unlike GetOrdinal which throws)
    int idx = reader.GetFieldIndex("ColumnName");

    // Get current record as reconstructed CSV string (useful for error logging)
    string rawData = reader.GetCurrentRawData();

    // Efficiently copy all fields to an array
    string[] values = new string[reader.FieldCount];
    reader.CopyCurrentRecordTo(values);

    // Check if current record had issues
    if (reader.MissingFieldFlag)
        Console.WriteLine("Record had missing fields (padded with nulls)");
    if (reader.ParseErrorFlag)
        Console.WriteLine("Record had a parse error that was skipped");
}

// Check if stream is fully consumed
if (reader.EndOfStream)
    Console.WriteLine("Finished reading all data");
```

### Empty Header Handling

CSV files with empty or whitespace-only headers are automatically assigned default names:

```csharp
// CSV: Name,,Value
// Headers become: Name, Column1, Value

var options = new CsvReaderOptions
{
    DefaultHeaderName = "Field"  // Custom prefix (default is "Column")
};
// Headers become: Name, Field1, Value
```

