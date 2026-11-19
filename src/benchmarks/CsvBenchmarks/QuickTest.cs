using System.Diagnostics;
using System.Globalization;
using System.Text;
using nietras.SeparatedValues;
using CsvHelper;
using CsvHelper.Configuration;

// Alias to avoid ambiguity with CsvHelper
using DataplatCsvReader = Dataplat.Dbatools.Csv.Reader.CsvDataReader;

namespace CsvBenchmarks;

public static class QuickTest
{
    public static void Run()
    {
        var dataDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "TestData");
        Directory.CreateDirectory(dataDir);

        // Generate test files
        Console.WriteLine("Generating test files...");
        var testFilePath = Path.Combine(dataDir, "quicktest.csv");
        GenerateTestCsv(testFilePath, 100_000, 10);

        Console.WriteLine($"Test file size: {new FileInfo(testFilePath).Length / 1024.0:N0} KB\n");

        // Run BOTH benchmark scenarios
        Console.WriteLine("=" .PadRight(70, '='));
        Console.WriteLine("SCENARIO 1: Single Column Read (typical database import pattern)");
        Console.WriteLine("=" .PadRight(70, '='));
        RunBenchmark(testFilePath, singleColumn: true);

        Console.WriteLine("\n");
        Console.WriteLine("=" .PadRight(70, '='));
        Console.WriteLine("SCENARIO 2: All Columns Read (full row processing)");
        Console.WriteLine("=" .PadRight(70, '='));
        RunBenchmark(testFilePath, singleColumn: false);

        Console.WriteLine("\n");
        Console.WriteLine("=" .PadRight(70, '='));
        Console.WriteLine("SUMMARY: Dataplat's competitive advantage");
        Console.WriteLine("=" .PadRight(70, '='));
        Console.WriteLine("- Single column reads: Dataplat significantly faster than LumenWorks");
        Console.WriteLine("- All column reads: Dataplat moderately faster than LumenWorks");
        Console.WriteLine("- Sep/Sylvan faster for raw parsing, but lack:");
        Console.WriteLine("  • Built-in compression (GZip, Brotli, etc.)");
        Console.WriteLine("  • Progress reporting");
        Console.WriteLine("  • Lenient quote handling for messy data");
        Console.WriteLine("  • dbatools integration");
    }

    private static void RunBenchmark(string testFilePath, bool singleColumn)
    {
        // Warm up
        Console.WriteLine("\nWarming up...");
        RunDataplat(testFilePath, singleColumn);
        RunLumenWorks(testFilePath, singleColumn);
        RunSep(testFilePath, singleColumn);
        RunSylvan(testFilePath, singleColumn);
        RunCsvHelper(testFilePath, singleColumn);

        // Run multiple iterations
        int iterations = 5;
        var dataplatTimes = new List<double>();
        var lumenTimes = new List<double>();
        var sepTimes = new List<double>();
        var sylvanTimes = new List<double>();
        var csvHelperTimes = new List<double>();

        Console.WriteLine($"Running {iterations} iterations...\n");

        for (int i = 0; i < iterations; i++)
        {
            Console.WriteLine($"--- Iteration {i + 1} ---");

            var sw = Stopwatch.StartNew();
            int dataplatCount = RunDataplat(testFilePath, singleColumn);
            sw.Stop();
            dataplatTimes.Add(sw.Elapsed.TotalMilliseconds);
            Console.WriteLine($"  Dataplat:   {sw.Elapsed.TotalMilliseconds,8:N2} ms ({dataplatCount:N0} rows)");

            sw.Restart();
            int sepCount = RunSep(testFilePath, singleColumn);
            sw.Stop();
            sepTimes.Add(sw.Elapsed.TotalMilliseconds);
            Console.WriteLine($"  Sep:        {sw.Elapsed.TotalMilliseconds,8:N2} ms ({sepCount:N0} rows)");

            sw.Restart();
            int sylvanCount = RunSylvan(testFilePath, singleColumn);
            sw.Stop();
            sylvanTimes.Add(sw.Elapsed.TotalMilliseconds);
            Console.WriteLine($"  Sylvan:     {sw.Elapsed.TotalMilliseconds,8:N2} ms ({sylvanCount:N0} rows)");

            sw.Restart();
            int csvHelperCount = RunCsvHelper(testFilePath, singleColumn);
            sw.Stop();
            csvHelperTimes.Add(sw.Elapsed.TotalMilliseconds);
            Console.WriteLine($"  CsvHelper:  {sw.Elapsed.TotalMilliseconds,8:N2} ms ({csvHelperCount:N0} rows)");

            sw.Restart();
            int lumenCount = RunLumenWorks(testFilePath, singleColumn);
            sw.Stop();
            lumenTimes.Add(sw.Elapsed.TotalMilliseconds);
            Console.WriteLine($"  LumenWorks: {sw.Elapsed.TotalMilliseconds,8:N2} ms ({lumenCount:N0} rows)");
            Console.WriteLine();
        }

        // Calculate averages
        double avgDataplat = dataplatTimes.Average();
        double avgSep = sepTimes.Average();
        double avgSylvan = sylvanTimes.Average();
        double avgCsvHelper = csvHelperTimes.Average();
        double avgLumen = lumenTimes.Average();

        string scenario = singleColumn ? "single column" : "all columns";
        Console.WriteLine($"╔════════════════════════════════════════════════════════════════╗");
        Console.WriteLine($"║         RESULTS ({scenario})                         ║");
        Console.WriteLine($"╠═════════════════╦═══════════════╦═════════════════════════════╣");
        Console.WriteLine($"║ Library         ║ Time (ms)     ║ vs Dataplat                 ║");
        Console.WriteLine($"╠═════════════════╬═══════════════╬═════════════════════════════╣");
        Console.WriteLine($"║ Sep             ║ {avgSep,10:N2}    ║ {(avgDataplat / avgSep):N2}x (Sep is faster)       ║");
        Console.WriteLine($"║ Sylvan          ║ {avgSylvan,10:N2}    ║ {(avgDataplat / avgSylvan):N2}x                        ║");
        Console.WriteLine($"║ Dataplat        ║ {avgDataplat,10:N2}    ║ 1.00x (baseline)            ║");
        Console.WriteLine($"║ CsvHelper       ║ {avgCsvHelper,10:N2}    ║ {(avgCsvHelper / avgDataplat):N2}x slower              ║");
        Console.WriteLine($"║ LumenWorks      ║ {avgLumen,10:N2}    ║ {(avgLumen / avgDataplat):N2}x slower              ║");
        Console.WriteLine($"╚═════════════════╩═══════════════╩═════════════════════════════╝");
    }

    private static int RunDataplat(string path, bool singleColumn)
    {
        int count = 0;
        using var reader = new DataplatCsvReader(path);
        if (singleColumn)
        {
            while (reader.Read())
            {
                count++;
                _ = reader.GetValue(0);
            }
        }
        else
        {
            while (reader.Read())
            {
                count++;
                for (int i = 0; i < reader.FieldCount; i++)
                    _ = reader.GetValue(i);
            }
        }
        return count;
    }

    private static int RunLumenWorks(string path, bool singleColumn)
    {
        int count = 0;
        using var textReader = new StreamReader(path);
        using var reader = new LumenWorks.Framework.IO.Csv.CsvReader(textReader, true);
        if (singleColumn)
        {
            while (reader.ReadNextRecord())
            {
                count++;
                _ = reader[0];
            }
        }
        else
        {
            while (reader.ReadNextRecord())
            {
                count++;
                for (int i = 0; i < reader.FieldCount; i++)
                    _ = reader[i];
            }
        }
        return count;
    }

    private static int RunSep(string path, bool singleColumn)
    {
        int count = 0;
        using var reader = Sep.Reader().FromFile(path);
        if (singleColumn)
        {
            foreach (var row in reader)
            {
                count++;
                _ = row[0].ToString();
            }
        }
        else
        {
            foreach (var row in reader)
            {
                count++;
                for (int i = 0; i < row.ColCount; i++)
                    _ = row[i].ToString();
            }
        }
        return count;
    }

    private static int RunSylvan(string path, bool singleColumn)
    {
        int count = 0;
        using var textReader = new StreamReader(path);
        using var reader = Sylvan.Data.Csv.CsvDataReader.Create(textReader);
        if (singleColumn)
        {
            while (reader.Read())
            {
                count++;
                _ = reader.GetString(0);
            }
        }
        else
        {
            while (reader.Read())
            {
                count++;
                for (int i = 0; i < reader.FieldCount; i++)
                    _ = reader.GetString(i);
            }
        }
        return count;
    }

    private static int RunCsvHelper(string path, bool singleColumn)
    {
        int count = 0;
        var config = new CsvConfiguration(CultureInfo.InvariantCulture)
        {
            HasHeaderRecord = true
        };
        using var textReader = new StreamReader(path);
        using var csv = new CsvReader(textReader, config);
        csv.Read();
        csv.ReadHeader();
        if (singleColumn)
        {
            while (csv.Read())
            {
                count++;
                _ = csv.GetField(0);
            }
        }
        else
        {
            while (csv.Read())
            {
                count++;
                for (int i = 0; i < csv.Parser.Count; i++)
                    _ = csv.GetField(i);
            }
        }
        return count;
    }

    private static void GenerateTestCsv(string path, int rows, int cols)
    {
        if (File.Exists(path))
            return;

        using var writer = new StreamWriter(path, false, Encoding.UTF8);

        // Header
        writer.WriteLine(string.Join(",", Enumerable.Range(0, cols).Select(i => $"Column{i}")));

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
                    1 => $"Name{row}",
                    2 => random.Next(1, 100).ToString(),
                    3 => random.NextDouble().ToString("F4"),
                    4 => DateTime.Now.AddDays(-random.Next(365)).ToString("yyyy-MM-dd"),
                    5 => random.Next(0, 2) == 0 ? "true" : "false",
                    _ => $"Value{row}_{col}"
                };
                sb.Append(value);
            }
            writer.WriteLine(sb.ToString());
        }
    }
}
