using BenchmarkDotNet.Attributes;
using Dataplat.Dbatools.Csv.TypeConverters;
using System.Linq;

namespace CsvBenchmarks;

/// <summary>
/// Benchmarks for TypeConverter implementations, focusing on performance-critical scenarios.
/// </summary>
[MemoryDiagnoser]
[RankColumn]
public class TypeConverterBenchmarks
{
    private string _smallVector;
    private string _largeVector;
    private string _openAiVector;
    private VectorConverter _converter;

    [GlobalSetup]
    public void Setup()
    {
        _converter = VectorConverter.Default;

        // Small vector: 3 dimensions
        _smallVector = "[0.1, 0.2, 0.3]";

        // Large vector: 100 dimensions
        _largeVector = "[" + string.Join(", ", Enumerable.Range(0, 100).Select(i => (i * 0.01f).ToString("F3"))) + "]";

        // OpenAI ada-002 embedding size: 1536 dimensions
        _openAiVector = "[" + string.Join(", ", Enumerable.Range(0, 1536).Select(i => (i * 0.001f).ToString("F4"))) + "]";
    }

    [Benchmark(Baseline = true, Description = "Small Vector (3 dims)")]
    [BenchmarkCategory("VectorConverter")]
    public float[] VectorConverter_Small()
    {
        _converter.TryConvert(_smallVector, out float[] result);
        return result;
    }

    [Benchmark(Description = "Large Vector (100 dims)")]
    [BenchmarkCategory("VectorConverter")]
    public float[] VectorConverter_Large()
    {
        _converter.TryConvert(_largeVector, out float[] result);
        return result;
    }

    [Benchmark(Description = "OpenAI Vector (1536 dims)")]
    [BenchmarkCategory("VectorConverter")]
    public float[] VectorConverter_OpenAI()
    {
        _converter.TryConvert(_openAiVector, out float[] result);
        return result;
    }

    [Benchmark(Description = "Scientific Notation")]
    [BenchmarkCategory("VectorConverter")]
    public float[] VectorConverter_Scientific()
    {
        _converter.TryConvert("[1.5e-3, 2.0E2, -3.5e1]", out float[] result);
        return result;
    }
}
