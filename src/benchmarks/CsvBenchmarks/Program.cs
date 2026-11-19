using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Configs;
using BenchmarkDotNet.Jobs;
using BenchmarkDotNet.Running;
using BenchmarkDotNet.Columns;
using BenchmarkDotNet.Reports;
using BenchmarkDotNet.Diagnosers;
using BenchmarkDotNet.Exporters;
using System.Data;
using System.Text;
using System.Globalization;
using Dataplat.Dbatools.Csv.Reader;
using nietras.SeparatedValues;
using CsvHelper;
using CsvHelper.Configuration;

// Alias to avoid ambiguity with Sylvan and CsvHelper
using DataplatCsvReader = Dataplat.Dbatools.Csv.Reader.CsvDataReader;

namespace CsvBenchmarks;

public class Program
{
    public static void Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "--quick")
        {
            QuickTest.Run();
            return;
        }

        var config = ManualConfig.Create(DefaultConfig.Instance)
            .AddDiagnoser(MemoryDiagnoser.Default)
            .WithSummaryStyle(SummaryStyle.Default.WithRatioStyle(RatioStyle.Percentage))
            .AddColumn(StatisticColumn.OperationsPerSecond)
            .AddExporter(MarkdownExporter.GitHub);

        BenchmarkRunner.Run<CsvReaderBenchmarks>(config);
    }
}

[MemoryDiagnoser]
[RankColumn]
public partial class CsvReaderBenchmarks
{
    private string _smallCsvPath;
    private string _mediumCsvPath;
    private string _largeCsvPath;
    private string _wideCsvPath;
    private string _quotedCsvPath;

    [GlobalSetup]
    public void Setup()
    {
        var dataDir = Path.Combine(Path.GetDirectoryName(typeof(CsvReaderBenchmarks).Assembly.Location), "TestData");
        Directory.CreateDirectory(dataDir);

        // Small: 1,000 rows, 10 columns
        _smallCsvPath = Path.Combine(dataDir, "small.csv");
        GenerateCsv(_smallCsvPath, 1_000, 10, quoteAll: false);

        // Medium: 100,000 rows, 10 columns
        _mediumCsvPath = Path.Combine(dataDir, "medium.csv");
        GenerateCsv(_mediumCsvPath, 100_000, 10, quoteAll: false);

        // Large: 1,000,000 rows, 10 columns
        _largeCsvPath = Path.Combine(dataDir, "large.csv");
        GenerateCsv(_largeCsvPath, 1_000_000, 10, quoteAll: false);

        // Wide: 100,000 rows, 50 columns
        _wideCsvPath = Path.Combine(dataDir, "wide.csv");
        GenerateCsv(_wideCsvPath, 100_000, 50, quoteAll: false);

        // Quoted: 100,000 rows, 10 columns with quoted fields
        _quotedCsvPath = Path.Combine(dataDir, "quoted.csv");
        GenerateCsv(_quotedCsvPath, 100_000, 10, quoteAll: true);

        Console.WriteLine(String.Format("Small CSV: {0:N0} KB", new FileInfo(_smallCsvPath).Length / 1024.0));
        Console.WriteLine(String.Format("Medium CSV: {0:N0} KB", new FileInfo(_mediumCsvPath).Length / 1024.0));
        Console.WriteLine(String.Format("Large CSV: {0:N1} MB", new FileInfo(_largeCsvPath).Length / 1024.0 / 1024.0));
        Console.WriteLine(String.Format("Wide CSV: {0:N0} KB", new FileInfo(_wideCsvPath).Length / 1024.0));
        Console.WriteLine(String.Format("Quoted CSV: {0:N0} KB", new FileInfo(_quotedCsvPath).Length / 1024.0));
    }

    private void GenerateCsv(string path, int rows, int cols, bool quoteAll)
    {
        if (File.Exists(path))
            return;

        using var writer = new StreamWriter(path, false, Encoding.UTF8);

        // Header
        writer.WriteLine(string.Join(",", Enumerable.Range(0, cols).Select(i => String.Format("Column{0}", i))));

        var random = new Random(42);
        var sb = new StringBuilder();

        for (int row = 0; row < rows; row++)
        {
            sb.Clear();
            for (int col = 0; col < cols; col++)
            {
                if (col > 0) sb.Append(',');

                string value = col switch
                {
                    0 => row.ToString(),
                    1 => String.Format("Name{0}", row),
                    2 => random.Next(1, 100).ToString(),
                    3 => random.NextDouble().ToString("F4"),
                    4 => DateTime.Now.AddDays(-random.Next(365)).ToString("yyyy-MM-dd"),
                    5 => random.Next(0, 2) == 0 ? "true" : "false",
                    _ => String.Format("Value{0}_{1}", row, col)
                };

                if (quoteAll)
                    sb.Append(String.Format("\"{0}\"", value));
                else
                    sb.Append(value);
            }
            writer.WriteLine(sb.ToString());
        }
    }
}
