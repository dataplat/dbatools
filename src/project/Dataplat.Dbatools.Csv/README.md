# Dataplat.Dbatools.Csv

[![NuGet](https://img.shields.io/nuget/v/Dataplat.Dbatools.Csv.svg)](https://www.nuget.org/packages/Dataplat.Dbatools.Csv)
[![NuGet Downloads](https://img.shields.io/nuget/dt/Dataplat.Dbatools.Csv.svg)](https://www.nuget.org/packages/Dataplat.Dbatools.Csv)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

**The performance-optimized CSV library built for SQL Server.** High-performance CSV reader and writer for .NET from the trusted [dbatools](https://dbatools.io) project.

**What makes this library unique:**
- **Native IDataReader** - Stream directly to SqlBulkCopy with zero intermediate allocations
- **Schema Inference** - Auto-detect SQL Server column types (int, bigint, decimal, datetime2, bit, uniqueidentifier, varchar/nvarchar)
- **Built-in compression** - GZip, Brotli, Deflate, ZLib with decompression bomb protection
- **Real-world data handling** - Lenient parsing, smart quotes, duplicate headers, field count mismatches
- **Faster than LumenWorks & CsvHelper** - ~1.5x faster with modern .NET (Span<T>, ArrayPool)
- **Cancellation & Progress** - CancellationToken support and progress callbacks for long imports

## Installation

```bash
dotnet add package Dataplat.Dbatools.Csv
```

Or via Package Manager:

```powershell
Install-Package Dataplat.Dbatools.Csv
```

## Features

- **Streaming IDataReader** - Works seamlessly with SqlBulkCopy and other ADO.NET consumers
- **Schema Inference** - Analyze CSV data to determine optimal SQL Server column types
- **Strongly Typed Columns** - Define column types for automatic conversion with built-in and custom converters
- **High Performance** - ~1.5x faster than LumenWorks/CsvHelper with ArrayPool-based memory management
- **Parallel Processing** - Optional multi-threaded parsing for large files (25K+ rows/sec)
- **String Interning** - Reduce memory for files with repeated values
- **Compression Support** - Automatic handling of GZip, Deflate, Brotli (.NET 8+), and ZLib (.NET 8+)
- **Culture-Aware Parsing** - Configurable type converters for dates, numbers, booleans, and GUIDs
- **Flexible Delimiters** - Single or multi-character delimiters (e.g., `::`, `||`)
- **Robust Error Handling** - Collect errors, throw on first error, or skip bad rows
- **Security Built-in** - Decompression bomb protection, max field length limits
- **Smart Quote Handling** - Normalize curly/smart quotes from Word/Excel
- **Lenient Parsing Mode** - Handle real-world malformed CSV data gracefully
- **Duplicate Header Support** - Rename, ignore, or use first/last occurrence
- **Field Count Mismatch Handling** - Pad with nulls, truncate, or fail on row length mismatches

## Performance

Benchmark: 100,000 rows × 10 columns (.NET 8, AVX-512)

**Single column read (typical SqlBulkCopy/IDataReader pattern):**

| Library | Time (ms) | vs Dataplat |
|---------|-----------|-------------|
| Sep | 18 ms | 3.7x faster |
| Sylvan | 27 ms | 2.5x faster |
| **Dataplat** | **67 ms** | **baseline** |
| CsvHelper | 76 ms | 1.1x slower |
| LumenWorks | 395 ms | **5.9x slower** |

**All columns read (full row processing):**

| Library | Time (ms) | vs Dataplat |
|---------|-----------|-------------|
| Sep | 30 ms | 1.8x faster |
| Sylvan | 35 ms | 1.6x faster |
| **Dataplat** | **55 ms** | **baseline** |
| CsvHelper | 97 ms | 1.8x slower |
| LumenWorks | 102 ms | 1.9x slower |

### Understanding the performance tradeoffs

Sep achieves 21 GB/s by using `Span<T>` and only materializing strings when explicitly requested. Sylvan uses similar techniques. Both avoid allocations until the last possible moment.

**Why Dataplat can't match this:** The `IDataReader` interface requires `GetValue()` to return actual `object` instances. For string columns, this means creating real `string` objects—we can't return spans. This is a fundamental architectural tradeoff for SqlBulkCopy compatibility.

**When each library shines:**

| Scenario | Bottleneck | Winner |
|----------|-----------|--------|
| CSV → SqlBulkCopy → SQL Server | Network/disk I/O, not parsing | Dataplat (integrated) |
| CSV.gz → SQL Server | Decompression overhead | Dataplat (built-in) |
| Messy enterprise exports | Error handling complexity | Dataplat (lenient mode) |
| Raw in-memory parsing benchmark | CPU/allocations | Sep/Sylvan |

For database import workflows, the complete `file.csv.gz → SqlBulkCopy → SQL Server` pipeline with Dataplat is often comparable to combining Sep + manual decompression + custom IDataReader wrapper, while requiring less code.


## Guides

- [Usage examples](USAGE.md)
- [Schema inference and typed columns](SCHEMA-AND-TYPES.md)
- [Migrating from LumenWorks](MIGRATING-FROM-LUMENWORKS.md)

## Configuration Options

### CsvReaderOptions

| Option | Default | Description |
|--------|---------|-------------|
| `Delimiter` | `","` | Field delimiter (supports multi-character) |
| `HasHeaderRow` | `true` | First row contains column names |
| `SkipRows` | `0` | Number of rows to skip before reading |
| `Culture` | `InvariantCulture` | Culture for parsing numbers/dates |
| `ParseErrorAction` | `ThrowException` | How to handle parse errors |
| `CollectParseErrors` | `false` | Collect errors instead of throwing |
| `MaxParseErrors` | `1000` | Maximum errors to collect |
| `TrimmingOptions` | `None` | Whitespace trimming options |
| `CompressionType` | `None` | Compression format (auto-detected by default) |
| `MaxDecompressedSize` | `10GB` | Limit for decompression bomb protection |
| `MaxQuotedFieldLength` | `0` | Limit for quoted field length (0 = unlimited) |
| `QuoteMode` | `Strict` | RFC 4180 strict or lenient parsing mode |
| `DuplicateHeaderBehavior` | `ThrowException` | How to handle duplicate column names |
| `MismatchedFieldAction` | `ThrowException` | How to handle rows with wrong field count |
| `NormalizeQuotes` | `false` | Convert smart/curly quotes to ASCII quotes |
| `DistinguishEmptyFromNull` | `false` | Distinguish `,,` (null) from `,"",` (empty) |
| `EnableParallelProcessing` | `false` | Enable multi-threaded parsing |
| `MaxDegreeOfParallelism` | `0` | Worker threads (0 = processor count) |
| `InternStrings` | `false` | Intern common string values |
| `CancellationToken` | `None` | Token to monitor for cancellation requests |
| `ProgressReportInterval` | `10000` | Records between progress reports (0 = disabled) |
| `ProgressCallback` | `null` | Callback receiving `CsvProgress` updates |

## Thread Safety

When **parallel processing is enabled**, `CsvDataReader` provides the following thread-safety guarantees:

| Method/Property | Thread-Safe | Notes |
|-----------------|-------------|-------|
| `GetValue()` | Yes | Returns consistent snapshot of current record |
| `GetValues()` | Yes | Atomic copy of all values in current record |
| `CurrentRecordIndex` | Yes | No torn reads on 64-bit values |
| `Close()` / `Dispose()` | Yes | Safely stops parallel pipeline from any thread |
| `Read()` | No | Only one thread should call Read() |

### Usage Pattern

```csharp
var options = new CsvReaderOptions
{
    EnableParallelProcessing = true,
    MaxDegreeOfParallelism = 4
};

using var reader = new CsvDataReader("large-file.csv", options);

while (reader.Read())  // Main thread only
{
    // Safe to read values from multiple threads concurrently
    Parallel.For(0, 4, _ =>
    {
        var values = new object[reader.FieldCount];
        reader.GetValues(values);  // Thread-safe
        ProcessValues(values);
    });
}
```

### Important Notes

- **Sequential mode** (parallel processing disabled): The reader is **not thread-safe**. All access should be from a single thread.
- **Snapshot semantics**: Values returned by `GetValue()`/`GetValues()` represent a snapshot that may change after the next `Read()` call.
- **Single reader thread**: Only one thread should call `Read()` at a time. Concurrent `Read()` calls are not supported.

## Target Frameworks

- .NET Framework 4.7.2
- .NET 8.0

## Security Considerations

- **QuoteMode.Lenient**: Deviates from RFC 4180 and may parse data differently than expected. Use only for known malformed data sources.
- **MismatchedFieldAction.PadWithNulls/TruncateExtra**: May mask data corruption or cause silent data loss. Use with caution on untrusted data.
- **MaxDecompressedSize**: Always set an appropriate limit when processing compressed files from untrusted sources to prevent decompression bomb attacks.
- **MaxQuotedFieldLength**: Set a limit when processing untrusted data to prevent memory exhaustion from malformed multiline quoted fields.

## Related Projects

- [dbatools](https://github.com/dataplat/dbatools) - PowerShell module for SQL Server DBAs
- [dbatools.library](https://github.com/dataplat/dbatools.library) - Core library for dbatools

## License

MIT License - see the [LICENSE](https://github.com/dataplat/dbatools.library/blob/main/LICENSE) file for details.

## Development

This CSV library was created using [Claude Code](https://claude.com/claude-code) (Opus 4.5) with the following initial prompt:

> the dbatools repo is at C:\github\dbatools and this repo is at C:\github\dbatools.library
>
> i would like to create a replacement for LumenWorks.Framework.IO.dll PLUS the additional functionality requested in dbatools issues on github which you can find using the `gh` command
>
> the source code for lumenworks is https://github.com/phatcher/CsvReader/tree/master/code/LumenWorks.Framework.IO
>
> This library was written over a decade ago. considering the advances in .NET and SqlClient etc, please add a CSV reader of better quality (more functionality often seen in paid systems, faster) using recent .NET and Microsoft Data best practices
>
> Please ultrathink about the best way to go about creating this new, extensive functionality within the dbatools library. if it should be a new project that is linked or whatever, do it in this repo.

Additional refinements included a security review and feature additions based on [dbatools GitHub issues](https://github.com/dataplat/dbatools/issues).
