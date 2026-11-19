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
        /// <summary>
        /// Reads the next record from the parallel pipeline.
        /// </summary>
        private bool ReadParallel()
        {
            // Check for pipeline errors
            if (_pipelineException != null)
            {
                throw _pipelineException;
            }

            while (true)
            {
                // Check if we have a result ready in the pending buffer
                lock (_resultLock)
                {
                    if (_pendingResults.TryGetValue(_nextExpectedRecordIndex, out var record))
                    {
                        _pendingResults.Remove(_nextExpectedRecordIndex);
                        _nextExpectedRecordIndex++;

                        // Skip error records in AdvanceToNextLine mode
                        if (record.Error != null)
                        {
                            if (_options.ParseErrorAction == CsvParseErrorAction.RaiseEvent)
                            {
                                var args = new CsvParseErrorEventArgs(record.Error, CsvParseErrorAction.AdvanceToNextLine);
                                ParseError?.Invoke(this, args);
                                if (args.Action == CsvParseErrorAction.ThrowException)
                                {
                                    throw new CsvParseException("CSV parse error", record.Error);
                                }
                            }
                            continue;
                        }

                        _currentParsedRecord = record;
                        Interlocked.Exchange(ref _currentRecordIndex, record.RecordIndex);
                        Array.Copy(record.Values, _convertedValues, record.Values.Length);
                        return true;
                    }
                }

                // Try to read from result queue
                ParsedRecord result;
                try
                {
                    if (!_resultQueue.TryTake(out result, 100))
                    {
                        // Check if completed
                        if (_resultQueue.IsCompleted)
                        {
                            // Check for any remaining buffered results
                            lock (_resultLock)
                            {
                                if (_pendingResults.Count > 0 && _pendingResults.TryGetValue(_nextExpectedRecordIndex, out var lastRecord))
                                {
                                    _pendingResults.Remove(_nextExpectedRecordIndex);
                                    _nextExpectedRecordIndex++;

                                    if (lastRecord.Error != null)
                                    {
                                        continue;
                                    }

                                    _currentParsedRecord = lastRecord;
                                    Interlocked.Exchange(ref _currentRecordIndex, lastRecord.RecordIndex);
                                    Array.Copy(lastRecord.Values, _convertedValues, lastRecord.Values.Length);
                                    return true;
                                }
                            }

                            // Check for pipeline errors one more time
                            if (_pipelineException != null)
                            {
                                throw _pipelineException;
                            }

                            _currentRecord = null;
                            return false;
                        }

                        // Check for pipeline errors
                        if (_pipelineException != null)
                        {
                            throw _pipelineException;
                        }

                        continue;
                    }
                }
                catch (InvalidOperationException)
                {
                    // Collection completed
                    if (_pipelineException != null)
                    {
                        throw _pipelineException;
                    }

                    _currentRecord = null;
                    return false;
                }

                // Check for pipeline errors after reading
                if (_pipelineException != null)
                {
                    throw _pipelineException;
                }

                // If this is the next expected record, use it directly
                if (result.RecordIndex == _nextExpectedRecordIndex)
                {
                    _nextExpectedRecordIndex++;

                    // Skip error records
                    if (result.Error != null)
                    {
                        if (_options.ParseErrorAction == CsvParseErrorAction.RaiseEvent)
                        {
                            var args = new CsvParseErrorEventArgs(result.Error, CsvParseErrorAction.AdvanceToNextLine);
                            ParseError?.Invoke(this, args);
                            if (args.Action == CsvParseErrorAction.ThrowException)
                            {
                                throw new CsvParseException("CSV parse error", result.Error);
                            }
                        }
                        continue;
                    }

                    // Synchronize to prevent GetValue/GetValues from reading during Array.Copy
                    lock (_resultLock)
                    {
                        _currentParsedRecord = result;
                        Interlocked.Exchange(ref _currentRecordIndex, result.RecordIndex);
                        Array.Copy(result.Values, _convertedValues, result.Values.Length);
                    }
                    return true;
                }

                // Out of order - buffer it
                lock (_resultLock)
                {
                    _pendingResults[result.RecordIndex] = result;
                }
            }
        }

        private void StopParallelPipeline()
        {
            if (!_useParallelProcessing)
                return;

            _cancellationSource?.Cancel();

            try
            {
                // Wait for producer thread to complete
                if (_producerThread != null && _producerThread.IsAlive)
                {
                    _producerThread.Join(TimeSpan.FromSeconds(5));
                }

                // Wait for worker threads to complete
                if (_workerThreads != null)
                {
                    foreach (var thread in _workerThreads)
                    {
                        if (thread != null && thread.IsAlive)
                        {
                            thread.Join(TimeSpan.FromSeconds(5));
                        }
                    }
                }
            }
            finally
            {
                _cancellationSource?.Dispose();
                _cancellationSource = null;

                _lineQueue?.Dispose();
                _lineQueue = null;

                _resultQueue?.Dispose();
                _resultQueue = null;

                _useParallelProcessing = false;
            }

            // Transfer parallel errors to main error list
            if (_parallelParseErrors != null && _parseErrors != null)
            {
                while (_parallelParseErrors.TryDequeue(out var error))
                {
                    _parseErrors.Add(error);
                }
            }
        }

    }
}
