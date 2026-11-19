# Usage Examples

[Back to README](README.md)

## Quick Start

### Reading CSV Files

```csharp
using Dataplat.Dbatools.Csv.Reader;

// Simple usage
using var reader = new CsvDataReader("data.csv");
while (reader.Read())
{
    var name = reader.GetString(0);
    var value = reader.GetInt32(1);
}

// With options
var options = new CsvReaderOptions
{
    Delimiter = ";",
    HasHeaderRow = true,
    Culture = CultureInfo.GetCultureInfo("de-DE")
};
using var reader = new CsvDataReader("data.csv", options);
```

### Reading Compressed Files

```csharp
// Automatically detects compression from extension (.gz, .gzip, .deflate, .br, .zlib)
using var reader = new CsvDataReader("data.csv.gz");

// Or specify explicitly
var options = new CsvReaderOptions
{
    CompressionType = CompressionType.GZip,
    MaxDecompressedSize = 100 * 1024 * 1024  // 100MB limit
};
using var reader = new CsvDataReader(stream, options);
```

### Bulk Loading to SQL Server

```csharp
using var reader = new CsvDataReader("data.csv");
using var connection = new SqlConnection(connectionString);
connection.Open();

using var bulkCopy = new SqlBulkCopy(connection);
bulkCopy.DestinationTableName = "MyTable";
bulkCopy.WriteToServer(reader);  // Streams directly, low memory usage
```

### Parallel Processing (Large Files)

```csharp
var options = new CsvReaderOptions
{
    EnableParallelProcessing = true,
    MaxDegreeOfParallelism = Environment.ProcessorCount
};

using var reader = new CsvDataReader("large-file.csv", options);
// Process as normal - parallel parsing happens automatically
```

### Writing CSV Files

```csharp
using Dataplat.Dbatools.Csv.Writer;

var options = new CsvWriterOptions
{
    Delimiter = ",",
    QuoteAllFields = false,
    Culture = CultureInfo.InvariantCulture
};

using var writer = new CsvWriter("output.csv", options);
writer.WriteHeader(new[] { "Id", "Name", "Date" });
writer.WriteRecord(new object[] { 1, "Test", DateTime.Now });
```

### Error Handling

```csharp
var options = new CsvReaderOptions
{
    CollectParseErrors = true,
    MaxParseErrors = 100,
    ParseErrorAction = CsvParseErrorAction.AdvanceToNextLine
};

using var reader = new CsvDataReader("data.csv", options);
while (reader.Read())
{
    // Process valid records
}

// Check collected errors
foreach (var error in reader.ParseErrors)
{
    Console.WriteLine($"Row {error.RowIndex}, Line {error.LineNumber}: {error.Message}");
}
```

### Handling Malformed Data

```csharp
// Handle files with duplicate column names
var options = new CsvReaderOptions
{
    DuplicateHeaderBehavior = DuplicateHeaderBehavior.Rename  // Name, Name_2, Name_3
};

// Handle rows with wrong number of fields
var options = new CsvReaderOptions
{
    MismatchedFieldAction = MismatchedFieldAction.PadOrTruncate
};

// Handle malformed quotes (e.g., unmatched quotes, backslash escapes)
var options = new CsvReaderOptions
{
    QuoteMode = QuoteMode.Lenient
};

// Normalize smart/curly quotes from Word/Excel
var options = new CsvReaderOptions
{
    NormalizeQuotes = true
};

// Distinguish between null and empty string (see examples below)
var options = new CsvReaderOptions
{
    DistinguishEmptyFromNull = true
};
```

### Cancellation Support

```csharp
using var cts = new CancellationTokenSource();

var options = new CsvReaderOptions
{
    CancellationToken = cts.Token
};

// In another thread or after timeout
cts.CancelAfter(TimeSpan.FromSeconds(30));

try
{
    using var reader = new CsvDataReader("large-file.csv", options);
    while (reader.Read())
    {
        // Process records - will throw OperationCanceledException when cancelled
    }
}
catch (OperationCanceledException)
{
    Console.WriteLine("Import was cancelled");
}
```

### Progress Reporting

```csharp
var options = new CsvReaderOptions
{
    ProgressReportInterval = 10000,  // Report every 10,000 records
    ProgressCallback = progress =>
    {
        Console.WriteLine($"Processed {progress.RecordsRead:N0} records " +
                          $"({progress.RowsPerSecond:N0} rows/sec)");

        if (progress.PercentComplete >= 0)
            Console.WriteLine($"Progress: {progress.PercentComplete:F1}%");
    }
};

using var reader = new CsvDataReader("large-file.csv", options);
while (reader.Read())
{
    // Process records
}
```

