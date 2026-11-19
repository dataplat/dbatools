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

public partial class CsvReaderBenchmarks
{
    // ===================== Small File Benchmarks =====================

    [Benchmark(Baseline = true, Description = "Dataplat-Small")]
    [BenchmarkCategory("Small")]
    public int Dataplat_Small()
    {
        int count = 0;
        using var reader = new DataplatCsvReader(_smallCsvPath);
        while (reader.Read())
        {
            count++;
            _ = reader.GetValue(0);
        }
        return count;
    }

    [Benchmark(Description = "LumenWorks-Small")]
    [BenchmarkCategory("Small")]
    public int LumenWorks_Small()
    {
        int count = 0;
        using var textReader = new StreamReader(_smallCsvPath);
        using var reader = new LumenWorks.Framework.IO.Csv.CsvReader(textReader, true);
        while (reader.ReadNextRecord())
        {
            count++;
            _ = reader[0];
        }
        return count;
    }

    // ===================== Medium File Benchmarks =====================

    [Benchmark(Description = "Dataplat-Medium")]
    [BenchmarkCategory("Medium")]
    public int Dataplat_Medium()
    {
        int count = 0;
        using var reader = new DataplatCsvReader(_mediumCsvPath);
        while (reader.Read())
        {
            count++;
            _ = reader.GetValue(0);
        }
        return count;
    }

    [Benchmark(Description = "LumenWorks-Medium")]
    [BenchmarkCategory("Medium")]
    public int LumenWorks_Medium()
    {
        int count = 0;
        using var textReader = new StreamReader(_mediumCsvPath);
        using var reader = new LumenWorks.Framework.IO.Csv.CsvReader(textReader, true);
        while (reader.ReadNextRecord())
        {
            count++;
            _ = reader[0];
        }
        return count;
    }

    // ===================== Large File Benchmarks =====================

    [Benchmark(Description = "Dataplat-Large")]
    [BenchmarkCategory("Large")]
    public int Dataplat_Large()
    {
        int count = 0;
        using var reader = new DataplatCsvReader(_largeCsvPath);
        while (reader.Read())
        {
            count++;
            _ = reader.GetValue(0);
        }
        return count;
    }

    [Benchmark(Description = "LumenWorks-Large")]
    [BenchmarkCategory("Large")]
    public int LumenWorks_Large()
    {
        int count = 0;
        using var textReader = new StreamReader(_largeCsvPath);
        using var reader = new LumenWorks.Framework.IO.Csv.CsvReader(textReader, true);
        while (reader.ReadNextRecord())
        {
            count++;
            _ = reader[0];
        }
        return count;
    }

    // ===================== Wide File Benchmarks =====================

    [Benchmark(Description = "Dataplat-Wide")]
    [BenchmarkCategory("Wide")]
    public int Dataplat_Wide()
    {
        int count = 0;
        using var reader = new DataplatCsvReader(_wideCsvPath);
        while (reader.Read())
        {
            count++;
            _ = reader.GetValue(0);
        }
        return count;
    }

    [Benchmark(Description = "LumenWorks-Wide")]
    [BenchmarkCategory("Wide")]
    public int LumenWorks_Wide()
    {
        int count = 0;
        using var textReader = new StreamReader(_wideCsvPath);
        using var reader = new LumenWorks.Framework.IO.Csv.CsvReader(textReader, true);
        while (reader.ReadNextRecord())
        {
            count++;
            _ = reader[0];
        }
        return count;
    }

    // ===================== Quoted File Benchmarks =====================

    [Benchmark(Description = "Dataplat-Quoted")]
    [BenchmarkCategory("Quoted")]
    public int Dataplat_Quoted()
    {
        int count = 0;
        using var reader = new DataplatCsvReader(_quotedCsvPath);
        while (reader.Read())
        {
            count++;
            _ = reader.GetValue(0);
        }
        return count;
    }

    [Benchmark(Description = "LumenWorks-Quoted")]
    [BenchmarkCategory("Quoted")]
    public int LumenWorks_Quoted()
    {
        int count = 0;
        using var textReader = new StreamReader(_quotedCsvPath);
        using var reader = new LumenWorks.Framework.IO.Csv.CsvReader(textReader, true);
        while (reader.ReadNextRecord())
        {
            count++;
            _ = reader[0];
        }
        return count;
    }

    // ===================== Modern Library Comparisons (Medium) =====================

    [Benchmark(Description = "Sep-Medium")]
    [BenchmarkCategory("Modern")]
    public int Sep_Medium()
    {
        int count = 0;
        using var reader = Sep.Reader().FromFile(_mediumCsvPath);
        foreach (var row in reader)
        {
            count++;
            _ = row[0].ToString();
        }
        return count;
    }

    [Benchmark(Description = "Sylvan-Medium")]
    [BenchmarkCategory("Modern")]
    public int Sylvan_Medium()
    {
        int count = 0;
        using var textReader = new StreamReader(_mediumCsvPath);
        using var reader = Sylvan.Data.Csv.CsvDataReader.Create(textReader);
        while (reader.Read())
        {
            count++;
            _ = reader.GetString(0);
        }
        return count;
    }

    [Benchmark(Description = "CsvHelper-Medium")]
    [BenchmarkCategory("Modern")]
    public int CsvHelper_Medium()
    {
        int count = 0;
        var config = new CsvConfiguration(CultureInfo.InvariantCulture)
        {
            HasHeaderRecord = true
        };
        using var textReader = new StreamReader(_mediumCsvPath);
        using var csv = new CsvHelper.CsvReader(textReader, config);
        csv.Read();
        csv.ReadHeader();
        while (csv.Read())
        {
            count++;
            _ = csv.GetField(0);
        }
        return count;
    }

    [Benchmark(Description = "Dataplat-Medium-Modern")]
    [BenchmarkCategory("Modern")]
    public int Dataplat_Medium_Modern()
    {
        int count = 0;
        using var reader = new Dataplat.Dbatools.Csv.Reader.CsvDataReader(_mediumCsvPath);
        while (reader.Read())
        {
            count++;
            _ = reader.GetValue(0);
        }
        return count;
    }

    // ===================== Modern Library Comparisons (Large) =====================

    [Benchmark(Description = "Sep-Large")]
    [BenchmarkCategory("ModernLarge")]
    public int Sep_Large()
    {
        int count = 0;
        using var reader = Sep.Reader().FromFile(_largeCsvPath);
        foreach (var row in reader)
        {
            count++;
            _ = row[0].ToString();
        }
        return count;
    }

    [Benchmark(Description = "Sylvan-Large")]
    [BenchmarkCategory("ModernLarge")]
    public int Sylvan_Large()
    {
        int count = 0;
        using var textReader = new StreamReader(_largeCsvPath);
        using var reader = Sylvan.Data.Csv.CsvDataReader.Create(textReader);
        while (reader.Read())
        {
            count++;
            _ = reader.GetString(0);
        }
        return count;
    }

    [Benchmark(Description = "CsvHelper-Large")]
    [BenchmarkCategory("ModernLarge")]
    public int CsvHelper_Large()
    {
        int count = 0;
        var config = new CsvConfiguration(CultureInfo.InvariantCulture)
        {
            HasHeaderRecord = true
        };
        using var textReader = new StreamReader(_largeCsvPath);
        using var csv = new CsvHelper.CsvReader(textReader, config);
        csv.Read();
        csv.ReadHeader();
        while (csv.Read())
        {
            count++;
            _ = csv.GetField(0);
        }
        return count;
    }

    [Benchmark(Description = "Dataplat-Large-Modern")]
    [BenchmarkCategory("ModernLarge")]
    public int Dataplat_Large_Modern()
    {
        int count = 0;
        using var reader = new Dataplat.Dbatools.Csv.Reader.CsvDataReader(_largeCsvPath);
        while (reader.Read())
        {
            count++;
            _ = reader.GetValue(0);
        }
        return count;
    }

    // ===================== All Values Access Benchmarks =====================

    [Benchmark(Description = "Dataplat-AllValues")]
    [BenchmarkCategory("AllValues")]
    public int Dataplat_AllValues()
    {
        int count = 0;
        var options = new CsvReaderOptions { BufferSize = 65536 };
        using var reader = new DataplatCsvReader(_mediumCsvPath, options);
        object[] values = new object[reader.FieldCount];
        while (reader.Read())
        {
            count++;
            reader.GetValues(values);
        }
        return count;
    }

    [Benchmark(Description = "LumenWorks-AllValues")]
    [BenchmarkCategory("AllValues")]
    public int LumenWorks_AllValues()
    {
        int count = 0;
        using var textReader = new StreamReader(_mediumCsvPath);
        using var reader = new LumenWorks.Framework.IO.Csv.CsvReader(textReader, true);
        while (reader.ReadNextRecord())
        {
            count++;
            for (int i = 0; i < reader.FieldCount; i++)
            {
                _ = reader[i];
            }
        }
        return count;
    }
}
