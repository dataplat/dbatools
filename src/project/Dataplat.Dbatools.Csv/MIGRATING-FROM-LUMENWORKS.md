# Migrating from LumenWorks CsvReader

This guide helps you migrate from [LumenWorks.Framework.IO](https://github.com/phatcher/CsvReader) to Dataplat.Dbatools.Csv.

## Why Migrate?

| Feature | LumenWorks | Dataplat.Dbatools.Csv |
|---------|------------|----------------------|
| Performance | Baseline | **20%+ faster** |
| Buffer size | 4KB | 64KB (configurable) |
| Multi-char delimiters | No | **Yes** (`::`, `\|\|`, etc.) |
| Compression support | No | **GZip, Deflate, Brotli, ZLib** |
| Parallel processing | No | **Yes** (2-4x on large files) |
| String interning | No | **Yes** (reduces GC pressure) |
| Decompression bomb protection | No | **Yes** (10GB default limit) |
| Active maintenance | Limited | **Active** |
| .NET 8 optimizations | No | **Yes** (Span, ArrayPool) |

## Quick Start

**Before (LumenWorks):**
```csharp
using LumenWorks.Framework.IO.Csv;

using (var reader = new CsvReader(new StreamReader("data.csv"), true))
{
    while (reader.ReadNextRecord())
    {
        string name = reader["Name"];
        string value = reader[1];
    }
}
```

**After (Dataplat.Dbatools.Csv):**
```csharp
using Dataplat.Dbatools.Csv.Reader;

using (var reader = new CsvDataReader("data.csv"))
{
    while (reader.Read())
    {
        string name = reader.GetString("Name");
        string value = reader.GetString(1);
    }
}
```

## Namespace Changes

| LumenWorks | Dataplat.Dbatools.Csv |
|------------|----------------------|
| `LumenWorks.Framework.IO.Csv` | `Dataplat.Dbatools.Csv.Reader` |
| `LumenWorks.Framework.IO.Csv.CsvReader` | `Dataplat.Dbatools.Csv.Reader.CsvDataReader` |

## Constructor Migration

### Basic Usage

**LumenWorks:**
```csharp
// TextReader with headers
var reader = new CsvReader(textReader, hasHeaders: true);

// With delimiter
var reader = new CsvReader(textReader, true, delimiter: ';');

// Full constructor
var reader = new CsvReader(textReader, true, ';', '"', '"', '#',
    ValueTrimmingOptions.UnquotedOnly, 4096, null);
```

**Dataplat.Dbatools.Csv:**
```csharp
// File path (simplest - handles streams automatically)
var reader = new CsvDataReader("data.csv");

// TextReader
var reader = new CsvDataReader(textReader);

// With options
var options = new CsvReaderOptions
{
    HasHeaderRow = true,
    Delimiter = ";",
    Quote = '"',
    Escape = '"',
    Comment = '#',
    TrimmingOptions = ValueTrimmingOptions.UnquotedOnly,
    BufferSize = 65536
};
var reader = new CsvDataReader("data.csv", options);
```

## Property Mapping

| LumenWorks Property | Dataplat.Dbatools.Csv Equivalent |
|---------------------|----------------------------------|
| `Delimiter` (char) | `CsvReaderOptions.Delimiter` (string - supports multi-char) |
| `Quote` | `CsvReaderOptions.Quote` |
| `Escape` | `CsvReaderOptions.Escape` |
| `Comment` | `CsvReaderOptions.Comment` |
| `HasHeaders` | `CsvReaderOptions.HasHeaderRow` |
| `FieldCount` | `CsvDataReader.FieldCount` |
| `CurrentRecordIndex` | `CsvDataReader.CurrentRecordIndex` |
| `TrimmingOption` | `CsvReaderOptions.TrimmingOptions` |
| `SupportsMultiline` | `CsvReaderOptions.AllowMultilineFields` |
| `SkipEmptyLines` | `CsvReaderOptions.SkipEmptyLines` |
| `NullValue` | `CsvReaderOptions.NullValue` |
| `BufferSize` | `CsvReaderOptions.BufferSize` |
| `MaxQuotedFieldLength` | `CsvReaderOptions.MaxQuotedFieldLength` |
| `UseColumnDefaults` | `CsvReaderOptions.UseColumnDefaults` |
| `DefaultHeaderName` | Auto-generated as `Column0`, `Column1`, etc. |

## Method Mapping

### Reading Records

| LumenWorks | Dataplat.Dbatools.Csv |
|------------|----------------------|
| `ReadNextRecord()` | `Read()` |
| `reader[0]` (indexer) | `GetString(0)` or `GetValue(0)` |
| `reader["Name"]` (indexer) | `GetString("Name")` or `reader["Name"]` |
| `GetFieldHeaders()` | `GetName(i)` for each field, or loop `FieldCount` |
| `GetFieldIndex("Name")` | `GetOrdinal("Name")` |
| `HasHeader("Name")` | `HasColumn("Name")` |
| `CopyCurrentRecordTo(array)` | `GetValues(array)` |
| `MoveTo(recordIndex)` | Not supported (forward-only) |

### Type Conversion

LumenWorks returns strings; you must convert manually. Dataplat.Dbatools.Csv has built-in type conversion:

**LumenWorks:**
```csharp
int value = int.Parse(reader["Count"]);
DateTime date = DateTime.Parse(reader["Date"]);
```

**Dataplat.Dbatools.Csv:**
```csharp
// Set column types upfront
reader.SetColumnType("Count", typeof(int));
reader.SetColumnType("Date", typeof(DateTime));

// Or via options
var options = new CsvReaderOptions
{
    ColumnTypes = new Dictionary<string, Type>
    {
        ["Count"] = typeof(int),
        ["Date"] = typeof(DateTime)
    }
};

// Then use typed getters
int count = reader.GetInt32("Count");
DateTime date = reader.GetDateTime("Date");
```

## Error Handling Migration

### ParseErrorAction

| LumenWorks | Dataplat.Dbatools.Csv |
|------------|----------------------|
| `ParseErrorAction.RaiseEvent` | `CsvParseErrorAction.RaiseEvent` + `CollectParseErrors = true` |
| `ParseErrorAction.AdvanceToNextLine` | `CsvParseErrorAction.AdvanceToNextLine` |
| `ParseErrorAction.ThrowException` | `CsvParseErrorAction.ThrowException` (default) |

**LumenWorks:**
```csharp
reader.DefaultParseErrorAction = ParseErrorAction.RaiseEvent;
reader.ParseError += (sender, e) => {
    Console.WriteLine($"Error: {e.Error.Message}");
    e.Action = ParseErrorAction.AdvanceToNextLine;
};
```

**Dataplat.Dbatools.Csv:**
```csharp
var options = new CsvReaderOptions
{
    CollectParseErrors = true,
    MaxParseErrors = 100,
    ParseErrorAction = CsvParseErrorAction.AdvanceToNextLine
};

using var reader = new CsvDataReader("data.csv", options);
while (reader.Read()) { /* process */ }

// After reading, check collected errors
foreach (var error in reader.ParseErrors)
{
    Console.WriteLine($"Row {error.RowIndex}: {error.Message}");
}
```

### MissingFieldAction

| LumenWorks | Dataplat.Dbatools.Csv |
|------------|----------------------|
| `MissingFieldAction.ParseError` | `MismatchedFieldAction.ThrowException` |
| `MissingFieldAction.ReplaceByEmpty` | `MismatchedFieldAction.PadWithNulls` + empty default |
| `MissingFieldAction.ReplaceByNull` | `MismatchedFieldAction.PadWithNulls` |

**Note:** Dataplat.Dbatools.Csv's `MismatchedFieldAction` handles both missing and extra fields:
- `ThrowException` - Fail on any mismatch (default)
- `PadWithNulls` - Add nulls for missing fields
- `TruncateExtra` - Ignore extra fields
- `PadOrTruncate` - Handle both cases

## Duplicate Header Handling

**LumenWorks:**
```csharp
reader.DuplicateHeaderEncountered += (sender, e) => {
    e.HeaderName = $"{e.HeaderName}_{e.Index}";
};
```

**Dataplat.Dbatools.Csv:**
```csharp
var options = new CsvReaderOptions
{
    DuplicateHeaderBehavior = DuplicateHeaderBehavior.Rename // Name, Name_2, Name_3
    // Other options: ThrowException, UseFirstOccurrence, UseLastOccurrence, Ignore
};
```


## Additional Migration Topics

- [New features without LumenWorks equivalents](MIGRATING-FROM-LUMENWORKS-FEATURES.md)
- [SqlBulkCopy, complete example, and troubleshooting](MIGRATING-FROM-LUMENWORKS-EXAMPLE.md)
