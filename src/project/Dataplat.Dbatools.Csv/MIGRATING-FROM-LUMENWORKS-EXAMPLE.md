# SqlBulkCopy, Complete Example, and Troubleshooting

[Back to migration guide](MIGRATING-FROM-LUMENWORKS.md)

## SqlBulkCopy Integration

Both libraries implement `IDataReader`, so SqlBulkCopy usage is identical:

```csharp
using var reader = new CsvDataReader("data.csv");
using var connection = new SqlConnection(connectionString);
connection.Open();

using var bulkCopy = new SqlBulkCopy(connection);
bulkCopy.DestinationTableName = "MyTable";
bulkCopy.WriteToServer(reader);
```

## Complete Migration Example

**LumenWorks:**
```csharp
using LumenWorks.Framework.IO.Csv;

using (var textReader = new StreamReader("data.csv"))
using (var reader = new CsvReader(textReader, true, ';', '"', '"', '#',
    ValueTrimmingOptions.UnquotedOnly, 4096, "NULL"))
{
    reader.MissingFieldAction = MissingFieldAction.ReplaceByNull;
    reader.DefaultParseErrorAction = ParseErrorAction.AdvanceToNextLine;

    while (reader.ReadNextRecord())
    {
        string id = reader["Id"];
        string name = reader["Name"];
        int count = int.Parse(reader["Count"]);
        // Process record...
    }
}
```

**Dataplat.Dbatools.Csv:**
```csharp
using Dataplat.Dbatools.Csv.Reader;

var options = new CsvReaderOptions
{
    Delimiter = ";",
    Quote = '"',
    Escape = '"',
    Comment = '#',
    TrimmingOptions = ValueTrimmingOptions.UnquotedOnly,
    BufferSize = 65536, // Larger default for better performance
    NullValue = "NULL",
    MismatchedFieldAction = MismatchedFieldAction.PadWithNulls,
    ParseErrorAction = CsvParseErrorAction.AdvanceToNextLine,
    CollectParseErrors = true,
    ColumnTypes = new Dictionary<string, Type>
    {
        ["Count"] = typeof(int)
    }
};

using (var reader = new CsvDataReader("data.csv", options))
{
    while (reader.Read())
    {
        string id = reader.GetString("Id");
        string name = reader.GetString("Name");
        int count = reader.GetInt32("Count"); // Direct typed access
        // Process record...
    }

    // Check for any errors that occurred
    if (reader.ParseErrors.Any())
    {
        foreach (var error in reader.ParseErrors)
        {
            Console.WriteLine($"Row {error.RowIndex}: {error.Message}");
        }
    }
}
```

## Troubleshooting

### "Column not found" errors

LumenWorks is case-sensitive by default. Dataplat.Dbatools.Csv uses case-insensitive column lookup by default. If you have columns with names differing only by case, use `GetOrdinal()` to get the exact index.

### Performance regression

If you see slower performance after migration:
1. Increase `BufferSize` (default is already 64KB vs LumenWorks' 4KB)
2. Enable `InternStrings` for files with many repeated values
3. Enable `EnableParallelProcessing` for files over 100K rows

### Different null handling

LumenWorks treats empty fields as empty strings by default. If you need null semantics:
```csharp
var options = new CsvReaderOptions
{
    DistinguishEmptyFromNull = true
};
```

### Missing MoveTo() functionality

Dataplat.Dbatools.Csv is forward-only for performance. If you need random access:
1. Read all records into a collection first
2. Use the collection for random access
