# Changelog

All notable changes to Dataplat.Dbatools.Csv will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Empty header name generation** - Empty or whitespace-only CSV headers are now automatically assigned default names (e.g., `Column0`, `Column1`) instead of throwing errors. This matches LumenWorks CsvReader behavior and fixes SQL bulk insert failures when CSV files have missing header names.
- **`DefaultHeaderName` option** - New `CsvReaderOptions.DefaultHeaderName` property allows customizing the prefix for generated header names (default is `"Column"`).
- **`GetCurrentRawData()` method** - Returns the current record as a reconstructed CSV string. Useful for debugging and error reporting. Provides LumenWorks CsvReader compatibility.
- **`CopyCurrentRecordTo()` method** - Efficiently copies all field values from the current record to a string array. Provides LumenWorks CsvReader compatibility.
- **`EndOfStream` property** - Indicates when the CSV stream has been fully consumed. Provides LumenWorks CsvReader compatibility.
- **`MissingFieldFlag` property** - Indicates if the current record had missing fields that were padded with nulls.
- **`ParseErrorFlag` property** - Indicates if the current record had a parse error that was handled by skipping.
- **`GetFieldIndex()` method** - Returns the column index for a header name, or -1 if not found. Unlike `GetOrdinal()`, does not throw for unknown headers.

## [1.1.10] - 2025-12-26

### Added
- **SQL Server schema inference** - New `CsvSchemaInference` class that analyzes CSV data to determine optimal SQL Server column types. Two modes available:
  - `InferSchemaFromSample()` - Fast inference from first N rows (default 1000)
  - `InferSchema()` - Full file scan with progress callback for zero-risk type detection
- `InferredColumn` class containing column name, SQL data type, max length, nullability, unicode flag, and decimal precision/scale
- Type detection for: `uniqueidentifier`, `bit`, `int`, `bigint`, `decimal(p,s)`, `datetime2`, `varchar(n)`, `nvarchar(n)`
- `GenerateCreateTableStatement()` utility to produce SQL DDL from inferred schema
- `ToColumnTypes()` utility to convert inferred schema to `CsvReaderOptions.ColumnTypes` dictionary
- Early exit optimization: types are eliminated as values fail validation, reducing unnecessary checks
- Progress callback support for full-scan mode (fires every ~1% or 10K rows)
- **MoneyConverter** for SQL Server `money`/`smallmoney` types with support for currency symbols, thousands separators, and accounting format
- **VectorConverter** for SQL Server 2025 `VECTOR` data type with support for JSON array and comma-separated formats

### Fixed
- **DecimalConverter scientific notation support** - Changed `NumberStyles` from `Number` to `Float | AllowThousands` to properly parse scientific notation (e.g., `1.2345678E5`)
- **SQL identifier escaping** - Escape closing brackets in schema, table, and column names to prevent SQL injection in generated `CREATE TABLE` statements

## [1.1.1] - 2025-12-04

### Changed
- **~25% performance improvement** for all-columns read scenarios (55ms vs 73ms for 100K rows)
- Added fast conversion path for simple string-only columns, bypassing unnecessary checks
- Added ultra-fast inline parsing path (.NET 8+) that writes directly to output, skipping intermediate buffers
- Gap vs Sylvan reduced from 2.0x to 1.6x for all-columns reads
- Added fast write path for CsvWriter - writes numeric types directly without StringBuilder allocation

## [1.1.0] - 2025-12-04

### Added
- **CancellationToken support** - Pass a cancellation token via `CsvReaderOptions.CancellationToken` to enable cancellation during long-running imports. Reader throws `OperationCanceledException` when cancelled.
- **Progress reporting** - New `CsvReaderOptions.ProgressCallback` and `CsvReaderOptions.ProgressReportInterval` for monitoring large file imports. Callback receives `CsvProgress` with records read, line number, bytes read, elapsed time, and rows per second.
- **Benchmark suite with modern libraries** - Added benchmarks comparing against Sep, Sylvan.Data.Csv, and CsvHelper for transparent performance comparison.
- Null and empty string validation for `Delimiter` property to prevent runtime errors
- Decompression bomb protection tests verifying `LimitedReadStream` security feature

### Changed
- Build script now uses XML parsing for version updates instead of regex (safer for edge cases)
- Updated performance positioning to be honest about competitive landscape (Sep is faster for raw parsing; Dataplat excels at database workflows with IDataReader + compression)

## [1.0.0] - 2024-11-28

### Added
- High-performance CSV reader implementing `IDataReader` for seamless `SqlBulkCopy` integration
- High-performance CSV writer with streaming support
- Multi-character delimiter support (e.g., `::`, `||`, `\t`)
- Automatic compression detection and handling (GZip, Deflate, Brotli, ZLib)
- Decompression bomb protection via configurable `MaxDecompressedSize` limit (default 10GB)
- Parallel processing pipeline for 2-4x performance on large files
- String interning for reduced memory allocations on repeated values
- Culture-aware type conversion with customizable converters
- Configurable error handling: throw, skip, or collect parse errors
- Quote handling modes: Strict (RFC 4180) and Lenient for malformed data
- Mismatched field count handling: throw, pad with nulls, or truncate
- Duplicate header handling options
- Static column injection for adding computed values to each record
- Column filtering (include/exclude)
- `DistinguishEmptyFromNull` option for precise null vs empty string semantics
- Smart/curly quote normalization
- Skip rows feature for files with preamble content
- SourceLink support for debugging NuGet packages

### Performance
- 20%+ faster than LumenWorks CsvReader in benchmarks
- 64KB default buffer size (vs 4KB in LumenWorks)
- Span-based parsing with `ArrayPool<T>` for minimal allocations
- SIMD-optimized delimiter matching via `Span.SequenceEqual`
- Zero-copy direct field parsing where possible
