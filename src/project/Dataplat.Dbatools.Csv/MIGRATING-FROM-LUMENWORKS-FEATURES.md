# New Features Without LumenWorks Equivalents

[Back to migration guide](MIGRATING-FROM-LUMENWORKS.md)

## New Features (No LumenWorks Equivalent)

### Multi-Character Delimiters

```csharp
var options = new CsvReaderOptions { Delimiter = "::" };
var options = new CsvReaderOptions { Delimiter = "||" };
var options = new CsvReaderOptions { Delimiter = "\t\t" };
```

### Compression Support

```csharp
// Automatic detection from file extension
using var reader = new CsvDataReader("data.csv.gz");

// Explicit configuration
var options = new CsvReaderOptions
{
    CompressionType = CompressionType.GZip,
    MaxDecompressedSize = 100 * 1024 * 1024 // 100MB limit
};
```

### Parallel Processing

```csharp
var options = new CsvReaderOptions
{
    EnableParallelProcessing = true,
    MaxDegreeOfParallelism = 4,
    ParallelBatchSize = 100
};
```

### String Interning

```csharp
var options = new CsvReaderOptions
{
    InternStrings = true,
    CustomInternStrings = new HashSet<string> { "Active", "Inactive", "Pending" }
};
```

### Static Columns

Inject computed columns into every record:

```csharp
var options = new CsvReaderOptions
{
    StaticColumns = new List<StaticColumn>
    {
        new StaticColumn("ImportDate", DateTime.Now),
        new StaticColumn("SourceFile", "data.csv")
    }
};
```

### Column Filtering

```csharp
var options = new CsvReaderOptions
{
    IncludeColumns = new HashSet<string> { "Id", "Name", "Email" },
    // Or exclude specific columns:
    ExcludeColumns = new HashSet<string> { "InternalId", "TempField" }
};
```

### Skip Rows (Preamble)

```csharp
var options = new CsvReaderOptions
{
    SkipRows = 3 // Skip first 3 rows before reading headers
};
```

### Lenient Quote Handling

For malformed CSVs with unmatched quotes or backslash escapes:

```csharp
var options = new CsvReaderOptions
{
    QuoteMode = QuoteMode.Lenient
};
```

### Null vs Empty String Distinction

```csharp
// Distinguish between ,, (null) and ,"", (empty string)
var options = new CsvReaderOptions
{
    DistinguishEmptyFromNull = true
};
```

