#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Data;
using System.Diagnostics;
using System.Globalization;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Csv.Reader;
using Dataplat.Dbatools.IO;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

public sealed partial class ImportDbaCsvCommand
{
    private enum InstanceOutcome
    {
        Next,
        ReturnFromProcess
    }

    protected override void ProcessRecord()
    {
        // PS: foreach over an unbound $Path enumerates nothing.
        if (Path is null)
            return;

        foreach (object? rawFile in Path)
        {
            // PS: if (-not $PSBoundParameters.ColumnMap) { $ColumnMap = $null } - resets a
            // map auto-built for the previous file; a bound map is reused as-is.
            _columnMap = BoundTruthy("ColumnMap") ? ColumnMap : null;

            object? filenameToken = rawFile;
            object? fullName = PsProperty.Get(filenameToken, "FullName");
            if (LanguagePrimitives.IsTrue(fullName))
                filenameToken = fullName;
            string filenameText = PsText(filenameToken);

            // PS: if (-not (Test-Path -Path $filename)) - provider semantics incl. wildcards.
            bool exists;
            try
            {
                exists = SessionState.InvokeProvider.Item.Exists(filenameText);
            }
            catch
            {
                exists = false;
            }
            if (!exists)
            {
                StopFunction(filenameText + " cannot be found", continueLoop: true);
                continue;
            }

            // PS: $file = (Resolve-Path -Path $filename).ProviderPath - a multi-match
            // wildcard leaves $file an ARRAY: the METHOD binder space-joins it for
            // GetExtension/OpenRead-style calls (lab-proven, codex r2 F1) while provider
            // cmdlets like Get-Content receive the array itself.
            Collection<string> resolvedPaths = SessionState.Path.GetResolvedProviderPathFromPSPath(filenameText, out _);
            object fileValue;
            string file;
            if (resolvedPaths.Count == 1)
            {
                fileValue = resolvedPaths[0];
                file = resolvedPaths[0];
            }
            else
            {
                string[] resolvedArray = new string[resolvedPaths.Count];
                resolvedPaths.CopyTo(resolvedArray, 0);
                fileValue = resolvedArray;
                file = string.Join(" ", resolvedArray);
            }

            string ext = System.IO.Path.GetExtension(file).ToLower();
            bool isCompressed = PsString.Eq(ext, ".gz");

            if (!isCompressed)
            {
                // Does the data section contain the specified delimiter?
                // Account for SkipRows when checking
                List<string?> firstlines;
                try
                {
                    long linesToRead = SkipRows + 2;
                    firstlines = GetContentLines(fileValue, linesToRead);
                    // Get only the lines after SkipRows for delimiter check
                    if (SkipRows > 0 && firstlines.Count > SkipRows)
                        firstlines = firstlines.GetRange(SkipRows, firstlines.Count - SkipRows);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    StopFunction("Failure reading " + file, errorRecord: RecordFrom(ex), continueLoop: true);
                    continue;
                }
                if (!SingleColumn.IsPresent)
                {
                    string delimiterPattern = Regex.Escape(Delimiter);
                    bool delimiterFound = false;
                    foreach (string? line in firstlines)
                    {
                        if (line is not null && Regex.IsMatch(line, delimiterPattern, RegexOptions.IgnoreCase))
                        {
                            delimiterFound = true;
                            break;
                        }
                    }
                    if (!delimiterFound)
                    {
                        StopFunction("Delimiter (" + Delimiter + ") not found in first few rows of " + file + ". If this is a single column import, please specify -SingleColumn");
                        return;
                    }
                }
            }

            string filename = System.IO.Path.GetFileNameWithoutExtension(file);

            // already trimmed the ".gz", if there is a ".csv", trim it as well.
            if (isCompressed && filename.EndsWith(".csv", StringComparison.OrdinalIgnoreCase))
                filename = System.IO.Path.GetFileNameWithoutExtension(filename);

            // Automatically generate Table name if not specified
            if (!BoundTruthy("Table"))
            {
                if (filename.IndexOf('.') != -1)
                    _periodFound = true;

                if (UseFileNameForSchema.IsPresent && _periodFound && !BoundTruthy("Schema"))
                {
                    _table = filename.Remove(0, filename.IndexOf('.') + 1);
                    WriteMessage(MessageLevel.Verbose, "Table name not specified, using " + _table + " from file name");
                }
                else
                {
                    _table = filename;
                    WriteMessage(MessageLevel.Verbose, "Table name not specified, using " + _table);
                }
            }

            // Use dbo as schema name if not specified in params, or as first string before a period in filename
            if (!BoundTruthy("Schema"))
            {
                if (UseFileNameForSchema.IsPresent)
                {
                    if (filename.IndexOf('.') == -1)
                    {
                        _schema = "dbo";
                        WriteMessage(MessageLevel.Verbose, "Schema not specified, and not found in file name, using dbo");
                    }
                    else
                    {
                        _schema = filename.Substring(0, filename.IndexOf('.'));
                        WriteMessage(MessageLevel.Verbose, "Schema detected in filename, using " + _schema);
                    }
                }
                else
                {
                    _schema = "dbo";
                    WriteMessage(MessageLevel.Verbose, "Schema not specified, using dbo");
                }
            }

            // Normalize table and schema names using Get-ObjectNameParts.
            // This handles bracketed names (e.g. [My.Table]) and two-part names (e.g. schema.[My.Table]).
            // sys.tables/sys.schemas store bare names without brackets, so we must strip them
            // before using the values in parameterized metadata queries.
            ObjectNameParts parsedTable = GetObjectNameParts(_table);
            if (parsedTable.Parsed)
            {
                if (!string.IsNullOrEmpty(parsedTable.Schema) && !BoundTruthy("Schema"))
                {
                    _schema = parsedTable.Schema!;
                    WriteMessage(MessageLevel.Verbose, "Schema extracted from table name, using " + _schema);
                }
                if (!string.IsNullOrEmpty(parsedTable.Name))
                    _table = parsedTable.Name!;
            }
            // Strip surrounding brackets from schema in case the user passed -Schema "[dbo]"
            if (_schema.Length >= 2 && _schema[0] == '[' && _schema[_schema.Length - 1] == ']')
                _schema = _schema.Substring(1, _schema.Length - 2);

            foreach (DbaInstanceParameter instance in SqlInstance)
            {
                if (ImportIntoInstance(instance, file, fileValue) == InstanceOutcome.ReturnFromProcess)
                    return;
            }
        }
    }

    private InstanceOutcome ImportIntoInstance(DbaInstanceParameter instance, string file, object fileValue)
    {
        Stopwatch elapsed = Stopwatch.StartNew();
        // Open Connection to SQL Server
        // Detect if user passed an already-open connection that we should preserve
        _startedWithAnOpenConnection = false;
        try
        {
            // Check if user passed a Server SMO object with an open connection
            // Following the pattern from Invoke-DbaQuery.ps1
            object? inputObject = instance.InputObject;
            if (inputObject is PSObject wrapped)
                inputObject = wrapped.BaseObject;
            if (PsString.Eq(inputObject!.GetType().Name, "Server") && SqlCredential is null)
            {
                Server? smoInput = inputObject as Server;
                if (PsString.Eq(smoInput?.ConnectionContext.DatabaseName, Database) || !LanguagePrimitives.IsTrue(Database))
                {
                    _startedWithAnOpenConnection = true;
                    WriteMessage(MessageLevel.Debug, "User provided an open connection - will preserve it after import");
                }
            }

            // PS: $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -MinimumVersion 9
            // The REAL command runs nested so its failure-path warning (display-suppressed
            // but -WarningVariable-captured) bubbles exactly like the function's nested call.
            ErrorRecord? connectFailure = ConnectViaCommand(instance);
            if (connectFailure is not null)
            {
                StopFunction("Failure", target: instance, errorRecord: connectFailure, category: ErrorCategory.ConnectionError, continueLoop: true);
                return InstanceOutcome.Next;
            }
            if (_server is null)
            {
                // PS: a nested Connect that emits nothing leaves $server null; the reads
                // null-propagate and $sqlconn.Open() faults with the null-method text
                // inside this try (codex r2 F2).
                throw new RuntimeException("You cannot call a method on a null-valued expression.");
            }
            SetActiveConnection(_server.ConnectionContext);
            _sqlconn = (SqlConnection)_server.ConnectionContext.SqlConnectionObject;
            if (_sqlconn.State != ConnectionState.Open)
                _sqlconn.Open();
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            ErrorRecord record = new(ex, string.Format("dbatools_{0}", MyInvocation.MyCommand.Name), ErrorCategory.ConnectionError, instance);
            StopFunction("Failure", target: instance, errorRecord: record, category: ErrorCategory.ConnectionError, continueLoop: true);
            return InstanceOutcome.Next;
        }

        // PS never resets $transaction between iterations: when a later iteration's
        // "Starting transaction" prompt is DECLINED, the stale committed transaction rides
        // into the SqlCommands and faults them (codex r1 F1) - so no reset here either.
        if (!NoTransaction.IsPresent)
        {
            if (ShouldProcess(instance.ToString(), "Starting transaction in " + Database))
            {
                // Everything will be contained within 1 transaction, even creating a new table if required
                // and truncating the table, if specified.
                _transaction = _sqlconn.BeginTransaction();
            }
        }

        // Determine if we should auto-create (type detection also implies auto-create)
        bool shouldAutoCreate = AutoCreateTable.IsPresent || _useTypeDetection;

        // Ensure Schema exists
        SqlCommand sqlcmd = new("SELECT COUNT(*) FROM sys.schemas WHERE name = @schema", _sqlconn, _transaction);
        sqlcmd.Parameters.AddWithValue("schema", _schema);
        // If Schema doesn't exist create it
        // Defaulting to dbo.
        if (Convert.ToInt32(sqlcmd.ExecuteScalar()) == 0)
        {
            if (!shouldAutoCreate)
            {
                StopFunction("Schema " + _schema + " does not exist and AutoCreateTable was not specified", continueLoop: true);
                return InstanceOutcome.Next;
            }
            if (ShouldProcess(instance.ToString(), "Creating schema " + _schema))
            {
                sqlcmd = new SqlCommand("CREATE SCHEMA [" + _schema + "] AUTHORIZATION dbo", _sqlconn, _transaction);
                try
                {
                    sqlcmd.ExecuteNonQuery();
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    StopFunction("Could not create " + _schema, errorRecord: RecordFrom(ex), continueLoop: true);
                    return InstanceOutcome.Next;
                }
            }
        }

        // Ensure table or view exists
        sqlcmd = new SqlCommand("SELECT COUNT(*) FROM sys.tables WHERE name = @table AND schema_id = schema_id(@schema)", _sqlconn, _transaction);
        sqlcmd.Parameters.AddWithValue("schema", _schema);
        sqlcmd.Parameters.AddWithValue("table", _table);

        SqlCommand sqlcmd2 = new("SELECT COUNT(*) FROM sys.views WHERE name = @table AND schema_id=schema_id(@schema)", _sqlconn, _transaction);
        sqlcmd2.Parameters.AddWithValue("schema", _schema);
        sqlcmd2.Parameters.AddWithValue("table", _table);

        // this variable enables the machinery that needs to build a precise mapping from the table definition
        // to the type of the columns BulkCopy needs. Lumen has support for it, but since it's a tad bit expensive
        // we opt-in only if the table already exists but not when we create the default table (which is basic, and it's all nvarchar(max)s columns)
        bool shouldMapCorrectTypes = false;

        // Store inferred columns for later use with CsvDataReader type mapping
        List<InferredColumn>? inferredColumns = null;

        // Track if we created a "fat" table (nvarchar(MAX) for all columns) that needs post-import optimization
        bool createdFatTable = false;

        // Create the table if required. Remember, this will occur within a transaction, so if the script fails, the
        // new table will no longer exist.
        if (Convert.ToInt32(sqlcmd.ExecuteScalar()) == 0 && Convert.ToInt32(sqlcmd2.ExecuteScalar()) == 0)
        {
            if (!shouldAutoCreate)
            {
                StopFunction("Table or view " + _table + " does not exist and AutoCreateTable was not specified", continueLoop: true);
                return InstanceOutcome.Next;
            }
            WriteMessage(MessageLevel.Verbose, "Table does not exist");

            if (_useTypeDetection)
            {
                // Build CsvReaderOptions for schema inference
                CsvReaderOptions inferOptions = new();
                inferOptions.HasHeaderRow = _firstRowHeader;
                inferOptions.Delimiter = Delimiter;
                inferOptions.Quote = Quote;
                inferOptions.Escape = Escape;
                inferOptions.Comment = Comment;
                inferOptions.Encoding = MapEncoding(Encoding);
                inferOptions.AllowMultilineFields = _allowMultilineFields;
                if (BoundTruthy("DateTimeFormats"))
                    inferOptions.DateTimeFormats = DateTimeFormats;
                if (BoundTruthy("Culture"))
                    inferOptions.Culture = new CultureInfo(Culture!);

                // Infer schema (this happens before the import timer starts)
                if (DetectColumnTypes.IsPresent)
                {
                    // Full scan - guarantees zero risk
                    WriteMessage(MessageLevel.Verbose, "Performing full file scan for type detection (zero risk)...");
                    inferredColumns = GetInferredSchema(file, inferOptions, 0, fullScan: true);
                }
                else
                {
                    // Sample-based
                    WriteMessage(MessageLevel.Verbose, "Sampling " + SampleRows + " rows for type detection...");
                    inferredColumns = GetInferredSchema(file, inferOptions, SampleRows, fullScan: false);
                }

                if (ShouldProcess(instance.ToString(), "Creating table " + _table + " with inferred column types"))
                {
                    try
                    {
                        // The helper's internal Stop-Function -Continue unwinds (dynamically)
                        // to this instance loop, bypassing the catch below.
                        if (!CreateSqlTableWithInferredSchema(inferredColumns))
                            return InstanceOutcome.Next;
                        // With inferred types, we want to use type conversion during import
                        shouldMapCorrectTypes = true;
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        StopFunction("Failure creating table with inferred types", errorRecord: RecordFrom(ex), continueLoop: true);
                        return InstanceOutcome.Next;
                    }
                }
            }
            else
            {
                // Original behavior - nvarchar(MAX) for all columns, then optimize after import
                if (ShouldProcess(instance.ToString(), "Creating table " + _table))
                {
                    try
                    {
                        if (!CreateSqlTable(file, Delimiter, _firstRowHeader))
                            return InstanceOutcome.Next;
                        createdFatTable = true;
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        StopFunction("Failure", errorRecord: RecordFrom(ex), continueLoop: true);
                        return InstanceOutcome.Next;
                    }
                }
            }
        }
        else
        {
            shouldMapCorrectTypes = true;
            WriteMessage(MessageLevel.Verbose, "Table exists");
        }

        // Reset the elapsed timer if we did type detection, so output reflects import time only
        if (_useTypeDetection && LanguagePrimitives.IsTrue(inferredColumns))
            elapsed.Restart();

        // Truncate if specified. Remember, this will occur within a transaction, so if the script fails, the
        // truncate will not be committed.
        if (Truncate.IsPresent)
        {
            if (ShouldProcess(instance.ToString(), "Performing TRUNCATE TABLE [" + _schema + "].[" + _table + "] on " + Database))
            {
                sqlcmd = new SqlCommand("TRUNCATE TABLE [" + _schema + "].[" + _table + "]", _sqlconn, _transaction);
                try
                {
                    sqlcmd.ExecuteNonQuery();
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    StopFunction("Could not truncate " + _schema + "." + _table, errorRecord: RecordFrom(ex), continueLoop: true);
                    return InstanceOutcome.Next;
                }
            }
        }

        // Setup bulk copy
        WriteMessage(MessageLevel.Verbose, "Starting bulk copy for " + System.IO.Path.GetFileName(file));

        // Setup bulk copy options
        int bulkCopyOptions = (int)SqlBulkCopyOptions.Default;
        if (TableLock.IsPresent)
            bulkCopyOptions += (int)SqlBulkCopyOptions.TableLock;
        if (CheckConstraints.IsPresent)
            bulkCopyOptions += (int)SqlBulkCopyOptions.CheckConstraints;
        if (FireTriggers.IsPresent)
            bulkCopyOptions += (int)SqlBulkCopyOptions.FireTriggers;
        if (KeepIdentity.IsPresent)
            bulkCopyOptions += (int)SqlBulkCopyOptions.KeepIdentity;
        if (KeepNulls.IsPresent)
            bulkCopyOptions += (int)SqlBulkCopyOptions.KeepNulls;

        if (ShouldProcess(instance.ToString(), "Performing import from " + file))
        {
            try
            {
                // Create SqlBulkCopy using default options, or options specified in command line.
                if (bulkCopyOptions != 0)
                    _bulkcopy = new SqlBulkCopy(_sqlconn, (SqlBulkCopyOptions)bulkCopyOptions, _transaction);
                else
                    _bulkcopy = new SqlBulkCopy(_sqlconn, SqlBulkCopyOptions.Default, _transaction);

                _bulkcopy.DestinationTableName = "[" + _schema + "].[" + _table + "]";
                _bulkcopy.BulkCopyTimeout = 0;
                _bulkcopy.BatchSize = BatchSize;
                _bulkcopy.NotifyAfter = NotifyAfter;
                _bulkcopy.EnableStreaming = true;

                // If the first column has quotes, then we have to setup a column map
                string quotematch = GetFirstLineToString(fileValue);

                if ((!KeepOrdinalOrder.IsPresent && !AutoCreateTable.IsPresent) || Regex.IsMatch(quotematch, "'", RegexOptions.IgnoreCase) || Regex.IsMatch(quotematch, "\"", RegexOptions.IgnoreCase))
                {
                    if (LanguagePrimitives.IsTrue(_columnMap))
                    {
                        WriteMessage(MessageLevel.Verbose, "ColumnMap was supplied. Additional auto-mapping will not be attempted.");
                    }
                    else if (NoHeaderRow.IsPresent)
                    {
                        WriteMessage(MessageLevel.Verbose, "NoHeaderRow was supplied. Additional auto-mapping will not be attempted.");
                    }
                    else
                    {
                        try
                        {
                            Hashtable autoMap = PsHashtable.Literal(0);
                            _columnMap = autoMap;
                            List<string?> firstlineItems = GetContentLines(fileValue, 1);
                            string firstline = (firstlineItems.Count > 0 ? firstlineItems[0] : null) ?? "";
                            bool isFirst = true;
                            // PS: -split "$Delimiter", 0, "SimpleMatch" - literal but
                            // CASE-INSENSITIVE like every -split (codex r1 F3).
                            foreach (string cell in Regex.Split(firstline, Regex.Escape(Delimiter), RegexOptions.IgnoreCase))
                            {
                                string trimmed = cell.Trim('"');
                                // Remove UTF-8 BOM from first column if present (U+FEFF)
                                if (isFirst)
                                {
                                    trimmed = trimmed.TrimStart('\uFEFF');
                                    isFirst = false;
                                }
                                WriteMessage(MessageLevel.Verbose, "Adding " + trimmed + " to ColumnMap");
                                autoMap.Add(trimmed, trimmed);
                            }
                        }
                        catch (PipelineStoppedException)
                        {
                            throw;
                        }
                        catch
                        {
                            // oh well, we tried
                            WriteMessage(MessageLevel.Verbose, "Couldn't auto create ColumnMap :(");
                            _columnMap = null;
                        }
                    }
                }

                if (LanguagePrimitives.IsTrue(_columnMap))
                {
                    //sort added in case of column maps done by ordinal
                    foreach (object key in SortKeys(_columnMap!.Keys))
                        AddColumnMapping(_bulkcopy, key, _columnMap[key]);
                }

                if (LanguagePrimitives.IsTrue(Column))
                {
                    foreach (string columnname in Column!)
                        _bulkcopy.ColumnMappings.Add(columnname, columnname);
                }

                // Add static column mappings for metadata tagging (issue #6676)
                if (BoundTruthy("StaticColumns"))
                {
                    foreach (object key in StaticColumns!.Keys)
                        AddColumnMapping(_bulkcopy, key, key);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction("Failure", errorRecord: RecordFrom(ex), continueLoop: true);
                return InstanceOutcome.Next;
            }

            // Write to server :D
            bool continueInstance = false;
            try
            {
                System.IO.Stream stream = System.IO.File.OpenRead(file);

                // ProgressStream callback doesn't work with parallel processing
                // (background threads can't access PowerShell runspace)
                if (!Parallel.IsPresent)
                {
                    Action<double> progressCallback = progress =>
                    {
                        if (!NoProgress.IsPresent)
                        {
                            double timetaken = Math.Round(elapsed.Elapsed.TotalSeconds, 2);
                            int percent = Convert.ToInt32(progress * 100);
                            // PS: Write-ProgressHelper -StepNumber $percent -TotalSteps 100 renders
                            // Write-Progress (default id 0) with PercentComplete = $percent.
                            ProgressBridge.Write(this, 0, "Importing from " + file,
                                string.Format("Progress: {0} rows {1}% in {2} seconds", _totalRowsCopied, percent, timetaken),
                                percentComplete: percent);
                        }
                    };
                    stream = new ProgressStream(stream, progressCallback, 0.05);
                }

                // Build CsvReaderOptions with all configuration
                CsvReaderOptions csvOptions = new();
                csvOptions.HasHeaderRow = _firstRowHeader;
                csvOptions.Delimiter = Delimiter;
                csvOptions.Quote = Quote;
                csvOptions.Escape = Escape;
                csvOptions.Comment = Comment;
                csvOptions.TrimmingOptions = (Csv.ValueTrimmingOptions)Enum.Parse(typeof(Csv.ValueTrimmingOptions), TrimmingOption, true);
                csvOptions.BufferSize = BufferSize;
                csvOptions.Encoding = MapEncoding(Encoding);
                if (LanguagePrimitives.IsTrue(NullValue))
                    csvOptions.NullValue = NullValue;
                csvOptions.MaxDecompressedSize = MaxDecompressedSize;
                csvOptions.SkipRows = SkipRows;
                csvOptions.QuoteMode = (QuoteMode)Enum.Parse(typeof(QuoteMode), QuoteMode, true);
                csvOptions.DuplicateHeaderBehavior = (DuplicateHeaderBehavior)Enum.Parse(typeof(DuplicateHeaderBehavior), DuplicateHeaderBehavior, true);
                csvOptions.MismatchedFieldAction = (MismatchedFieldAction)Enum.Parse(typeof(MismatchedFieldAction), MismatchedFieldAction, true);
                csvOptions.DistinguishEmptyFromNull = DistinguishEmptyFromNull.IsPresent;
                csvOptions.NormalizeQuotes = NormalizeQuotes.IsPresent;
                csvOptions.CollectParseErrors = CollectParseErrors.IsPresent;
                csvOptions.MaxParseErrors = MaxParseErrors;
                csvOptions.SkipEmptyLines = SkipEmptyLine.IsPresent;
                csvOptions.AllowMultilineFields = _allowMultilineFields;
                csvOptions.UseColumnDefaults = UseColumnDefault.IsPresent;
                if (BoundTruthy("MaxQuotedFieldLength"))
                    csvOptions.MaxQuotedFieldLength = MaxQuotedFieldLength;
                csvOptions.ParseErrorAction = (Csv.CsvParseErrorAction)Enum.Parse(typeof(Csv.CsvParseErrorAction), ParseErrorAction, true);
                if (BoundTruthy("DateTimeFormats"))
                    csvOptions.DateTimeFormats = DateTimeFormats;
                if (BoundTruthy("Culture"))
                    csvOptions.Culture = new CultureInfo(Culture!);
                if (BoundTruthy("StaticColumns"))
                {
                    List<StaticColumn> staticColumnsList = new();
                    foreach (object key in StaticColumns!.Keys)
                    {
                        object? value = StaticColumns[key];
                        if (value is PSObject wrappedValue)
                            value = wrappedValue.BaseObject;
                        staticColumnsList.Add(new StaticColumn((string)LanguagePrimitives.ConvertTo(key, typeof(string), CultureInfo.InvariantCulture), value!));
                    }
                    csvOptions.StaticColumns = staticColumnsList;
                }
                csvOptions.EnableParallelProcessing = Parallel.IsPresent;
                if (BoundTruthy("ThrottleLimit"))
                    csvOptions.MaxDegreeOfParallelism = ThrottleLimit;
                if (BoundTruthy("ParallelBatchSize"))
                    csvOptions.ParallelBatchSize = ParallelBatchSize;

                _reader = new CsvDataReader(stream, csvOptions);

                if (shouldMapCorrectTypes)
                {
                    if (_firstRowHeader)
                    {
                        // we can get default columns, all strings. This "fills" the $reader.Columns list, that we use later
                        _reader.GetFieldHeaders();
                        // we get the table definition
                        // we do not use $server because the connection is active here
                        List<TableColumnDef> tableDef = GetTableDefinitionFromInfoSchema(_table, _schema, _sqlconn!, _transaction);
                        if (tableDef.Count == 0)
                        {
                            // PS falls through after this Stop-Function (no return): the
                            // mapping loop below iterates an empty definition and the
                            // import proceeds untyped.
                            StopFunction("Could not fetch table definition for table " + _table + " in schema " + _schema);
                        }
                        foreach (SqlBulkCopyColumnMapping bcMapping in _bulkcopy.ColumnMappings)
                        {
                            // loop over mappings, we need to be careful and assign the correct type
                            string colNameFromSql = bcMapping.DestinationColumn;
                            string colNameFromCsv = bcMapping.SourceColumn;
                            foreach (TableColumnDef sqlCol in tableDef)
                            {
                                if (PsString.Eq(sqlCol.Name, colNameFromSql))
                                {
                                    // now we know the column, we need to get the type, let's be extra-obvious here
                                    string colTypeFromSql = sqlCol.DataType;
                                    // and now we translate to C# type
                                    Type colTypeCSharp = ConvertToDotnetType(colTypeFromSql);
                                    // and now we assign the type to the CsvDataReader column
                                    _reader.SetColumnType(colNameFromCsv, colTypeCSharp);
                                    // PS interpolates a Type through its ETS ToString ("int", not "System.Int32").
                                    WriteMessage(MessageLevel.Verbose, "Mapped " + colNameFromCsv + " --> " + colNameFromSql + " (" + PsTypeName(colTypeCSharp) + " --> " + colTypeFromSql + ")");
                                    break;
                                }
                            }
                        }
                    }
                    else
                    {
                        // For no-header scenarios, we need to set up column types based on table definition
                        // We cannot call Read() here as that would consume the first data row
                        List<TableColumnDef> tableDef = GetTableDefinitionFromInfoSchema(_table, _schema, _sqlconn!, _transaction);
                        if (tableDef.Count == 0)
                        {
                            StopFunction("Could not fetch table definition for table " + _table + " in schema " + _schema);
                        }
                        if (_bulkcopy.ColumnMappings.Count == 0)
                        {
                            // if we land here, we aren't forcing any mappings, but we need them for later
                            foreach (TableColumnDef dataRow in tableDef)
                                _bulkcopy.ColumnMappings.Add(dataRow.Index, dataRow.Index);
                        }
                        // For no-header mode, column names are auto-generated as "Column0", "Column1", etc.
                        // Set up types by ordinal using the table definition
                        foreach (TableColumnDef sqlCol in tableDef)
                        {
                            Type colTypeCSharp = ConvertToDotnetType(sqlCol.DataType);
                            string colName = "Column" + sqlCol.Index;
                            _reader.SetColumnType(colName, colTypeCSharp);
                            WriteMessage(MessageLevel.Verbose, "Mapped " + colName + " --> " + sqlCol.Name + " (" + PsTypeName(colTypeCSharp) + ")");
                        }
                    }
                }

                // The legacy bulk copy library uses a 4 byte integer to track the RowsCopied, so the only option is to use
                // integer wrap so that copy operations of row counts greater than [int32]::MaxValue will report accurate numbers.
                // See https://github.com/dataplat/dbatools/issues/6927 for more details
                _prevRowsCopied = 0;
                _totalRowsCopied = 0;

                // Add rowcount output
                _bulkcopy.SqlRowsCopied += (sender, args) =>
                {
                    _totalRowsCopied += GetAdjustedTotalRowsCopied(args.RowsCopied, _prevRowsCopied);

                    WriteMessage(MessageLevel.Verbose, " Total rows copied = " + _totalRowsCopied);
                    // progress is written by the ProgressStream callback
                    // save the previous count of rows copied to be used on the next event notification
                    _prevRowsCopied = args.RowsCopied;
                };

                _bulkcopy.WriteToServer(_reader);

                _completed = true;
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                _completed = false;
                StopFunction("Failure", errorRecord: RecordFrom(ex), continueLoop: true);
                continueInstance = true;
            }
            finally
            {
                try
                {
                    _reader!.Close();
                    _reader!.Dispose();
                }
                catch
                {
                }

                if (!NoTransaction.IsPresent)
                {
                    if (_completed == true)
                    {
                        try
                        {
                            _transaction!.Commit();
                        }
                        catch
                        {
                        }

                        // Optimize column sizes after commit if we created a fat table
                        if (createdFatTable && !NoColumnOptimize.IsPresent)
                        {
                            try
                            {
                                OptimizeColumnSize(_sqlconn!, _schema, _table);
                            }
                            catch (Exception optimizeError)
                            {
                                WriteMessage(MessageLevel.Warning, "Column size optimization failed: " + optimizeError.Message);
                            }
                        }
                    }
                    else
                    {
                        try
                        {
                            _transaction!.Rollback();
                        }
                        catch
                        {
                        }
                    }
                }
                else if (_completed == true && createdFatTable && !NoColumnOptimize.IsPresent)
                {
                    // NoTransaction mode - still optimize if we created a fat table
                    try
                    {
                        OptimizeColumnSize(_sqlconn!, _schema, _table);
                    }
                    catch (Exception optimizeError)
                    {
                        WriteMessage(MessageLevel.Warning, "Column size optimization failed: " + optimizeError.Message);
                    }
                }

                // Only close connection if we created it (not user-provided)
                if (!_startedWithAnOpenConnection)
                {
                    try
                    {
                        _sqlconn!.Close();
                        _sqlconn!.Dispose();
                    }
                    catch
                    {
                    }
                }

                try
                {
                    _bulkcopy!.Close();
                    // SqlBulkCopy implements IDisposable explicitly; PS's binder resolves it anyway.
                    ((IDisposable)_bulkcopy!).Dispose();
                }
                catch
                {
                }

                long finalRowCountReported = GetBulkRowsCopiedCount(_bulkcopy!);

                _totalRowsCopied += GetAdjustedTotalRowsCopied(finalRowCountReported, _prevRowsCopied);

                if (_completed == true)
                    ProgressBridge.Write(this, 1, "Inserting " + _totalRowsCopied + " rows", "Complete", completed: true);
                else
                    ProgressBridge.Write(this, 1, "Inserting " + _totalRowsCopied + " rows", "Failed", completed: true);
            }
            if (continueInstance)
                return InstanceOutcome.Next;
        }

        if (ShouldProcess(instance.ToString(), "Finalizing import"))
        {
            if (_completed == true)
            {
                // "Note: This count does not take into consideration the number of rows actually inserted when Ignore Duplicates is set to ON."
                long elapsedMilliseconds = elapsed.ElapsedMilliseconds;
                if (elapsedMilliseconds == 0)
                {
                    // PS integer division by a zero ElapsedMilliseconds is statement-terminating.
                    throw new RuntimeException("Attempted to divide by zero.");
                }
                double rowsPerSec = Math.Round((double)_totalRowsCopied / elapsedMilliseconds * 1000.0, 1);

                WriteMessage(MessageLevel.Verbose, _totalRowsCopied + " total rows copied");

                PSObject output = new();
                output.Properties.Add(new PSNoteProperty("ComputerName", SmoServerExtensions.GetComputerName(_server!)));
                output.Properties.Add(new PSNoteProperty("InstanceName", _server!.ServiceName));
                output.Properties.Add(new PSNoteProperty("SqlInstance", SmoServerExtensions.GetDomainInstanceName(_server!)));
                output.Properties.Add(new PSNoteProperty("Database", Database));
                output.Properties.Add(new PSNoteProperty("Table", _table));
                output.Properties.Add(new PSNoteProperty("Schema", _schema));
                output.Properties.Add(new PSNoteProperty("RowsCopied", _totalRowsCopied));
                output.Properties.Add(new PSNoteProperty("Elapsed", new DbaTimeSpanPretty(elapsed.Elapsed)));
                output.Properties.Add(new PSNoteProperty("RowsPerSecond", rowsPerSec));
                output.Properties.Add(new PSNoteProperty("Path", file));
                WriteObject(output);
            }
            else
            {
                StopFunction("Transaction rolled back. Was the proper delimiter specified? Is the first row the column name?");
                return InstanceOutcome.ReturnFromProcess;
            }
        }

        return InstanceOutcome.Next;
    }
}
