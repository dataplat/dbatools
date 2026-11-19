using System;
using System.Buffers;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Data;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Dataplat.Dbatools.Csv.Compression;
using Dataplat.Dbatools.Csv.TypeConverters;

namespace Dataplat.Dbatools.Csv.Reader
{
    public sealed partial class CsvDataReader
    {

        private void StartParallelPipeline()
        {
            _useParallelProcessing = true;
            _cancellationSource = new CancellationTokenSource();

            int workerCount = _options.MaxDegreeOfParallelism > 0
                ? _options.MaxDegreeOfParallelism
                : Environment.ProcessorCount;

            int queueCapacity = _options.ParallelQueueDepth * _options.ParallelBatchSize;

            // Create bounded blocking collections for backpressure
            _lineQueue = new BlockingCollection<LineData>(new ConcurrentQueue<LineData>(), queueCapacity);
            _resultQueue = new BlockingCollection<ParsedRecord>(new ConcurrentQueue<ParsedRecord>(), queueCapacity);

            // Initialize thread-safe error collection
            if (_options.CollectParseErrors)
            {
                _parallelParseErrors = new ConcurrentQueue<CsvParseError>();
            }

            _nextExpectedRecordIndex = 0;
            _activeWorkers = workerCount;

            // Start producer thread (line reader)
            _producerThread = new Thread(ProducerLoop)
            {
                Name = "CsvReader-Producer",
                IsBackground = true
            };
            _producerThread.Start();

            // Start worker threads (parsers)
            _workerThreads = new Thread[workerCount];
            for (int i = 0; i < workerCount; i++)
            {
                _workerThreads[i] = new Thread(WorkerLoop)
                {
                    Name = String.Format("CsvReader-Worker-{0}", i),
                    IsBackground = true
                };
                _workerThreads[i].Start();
            }
        }

        private void ProducerLoop()
        {
            try
            {
                long recordIndex = 0;
                var ct = _cancellationSource.Token;

                while (!ct.IsCancellationRequested)
                {
                    string line;

                    // Check for buffered first line (no-header mode)
                    if (_hasBufferedFirstLine)
                    {
                        line = _bufferedFirstLine;
                        _hasBufferedFirstLine = false;
                        _bufferedFirstLine = null;
                        // Line number was already incremented during initialization
                    }
                    else
                    {
                        if (!ReadLine(out line))
                        {
                            break;
                        }

                        Interlocked.Increment(ref _currentLineNumber);

                        // Skip empty lines if configured
                        if (string.IsNullOrEmpty(line) && _options.SkipEmptyLines)
                        {
                            continue;
                        }

                        // Skip comment lines
                        if (line != null && line.Length > 0 && line[0] == _options.Comment)
                        {
                            continue;
                        }
                    }

                    // Normalize smart quotes if enabled (must be done in producer for consistency)
                    if (_options.NormalizeQuotes && line != null)
                    {
                        line = NormalizeSmartQuotes(line);
                    }

                    var lineData = new LineData(line, Interlocked.Read(ref _currentLineNumber), recordIndex++);

                    // Add to queue with cancellation support
                    try
                    {
                        _lineQueue.Add(lineData, ct);
                    }
                    catch (OperationCanceledException)
                    {
                        break;
                    }
                }
            }
            catch (Exception ex)
            {
                _pipelineException = ex;
            }
            finally
            {
                _lineQueue.CompleteAdding();
            }
        }

        private void WorkerLoop()
        {
            // Thread-local parsing state
            var fieldsBuffer = new List<FieldInfo>(64);
            var quotedFieldBuilder = new StringBuilder(256);
            var ct = _cancellationSource.Token;

            try
            {
                foreach (var lineData in _lineQueue.GetConsumingEnumerable(ct))
                {
                    if (ct.IsCancellationRequested)
                        break;

                    ParsedRecord result;
                    try
                    {
                        // Parse line
                        ParseLineThreadSafe(lineData.Line, fieldsBuffer, quotedFieldBuilder);

                        // Handle field count mismatch
                        int expectedCount = _maxSourceIndex >= 0 ? _maxSourceIndex + 1 : fieldsBuffer.Count;
                        if (fieldsBuffer.Count != expectedCount)
                        {
                            HandleFieldCountMismatchThreadSafe(fieldsBuffer, lineData.Line, expectedCount);
                        }

                        // Convert to typed values
                        object[] values = ConvertRecordThreadSafe(fieldsBuffer, lineData.RecordIndex);

                        result = new ParsedRecord(values, lineData.RecordIndex, lineData.LineNumber);
                    }
                    catch (Exception ex)
                    {
                        var error = new CsvParseError(
                            lineData.RecordIndex + 1,
                            -1,
                            lineData.Line,
                            ex.Message,
                            ex,
                            lineData.LineNumber,
                            0);

                        if (_parallelParseErrors != null)
                        {
                            _parallelParseErrors.Enqueue(error);

                            if (_options.MaxParseErrors > 0 && _parallelParseErrors.Count >= _options.MaxParseErrors)
                            {
                                _pipelineException = new CsvParseException(String.Format("Maximum parse errors ({0}) exceeded", _options.MaxParseErrors), error) { IsMaxErrorsExceeded = true };
                                _cancellationSource.Cancel();
                                return;
                            }
                        }

                        if (_options.ParseErrorAction == CsvParseErrorAction.ThrowException)
                        {
                            _pipelineException = new CsvParseException("CSV parse error", error);
                            _cancellationSource.Cancel();
                            return;
                        }

                        // For AdvanceToNextLine, create error record
                        result = new ParsedRecord(error, lineData.RecordIndex, lineData.LineNumber);
                    }

                    try
                    {
                        _resultQueue.Add(result, ct);
                    }
                    catch (OperationCanceledException)
                    {
                        break;
                    }
                }
            }
            catch (OperationCanceledException)
            {
                // Normal cancellation
            }
            catch (InvalidOperationException)
            {
                // Collection completed, normal completion
            }
            catch (Exception ex)
            {
                _pipelineException = ex;
                _cancellationSource.Cancel();
            }
            finally
            {
                // Signal completion when all workers are done
                if (Interlocked.Decrement(ref _activeWorkers) == 0)
                {
                    _resultQueue.CompleteAdding();
                }
            }
        }

    }
}
