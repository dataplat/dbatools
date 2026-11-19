#nullable enable

using System.Collections.Generic;
using System.IO;
using Dataplat.Dbatools.Csv.Reader;
using Dataplat.Dbatools.dbaSystem;

namespace Dataplat.Dbatools.Commands;

/// <summary>The shipped randomizer catalog shared by its native readers.</summary>
internal static class NativeRandomizerCatalog
{
    internal static List<NativeRandomizerType> Read()
    {
        string path = Path.Combine(SystemHost.ModuleBase, "bin", "randomizer", "en.randomizertypes.csv");
        return ReadFile(path);
    }

    internal static List<NativeRandomizerType> ReadFile(string path)
    {
        List<NativeRandomizerType> rows = new();
        using CsvDataReader reader = new(path, new CsvReaderOptions { AutoDetectCompression = false });
        while (reader.Read())
        {
            rows.Add(new NativeRandomizerType(
                reader.GetString(reader.GetOrdinal("Type")),
                reader.GetString(reader.GetOrdinal("SubType")),
                reader.GetString(reader.GetOrdinal("RequiredParameter"))));
        }
        return rows;
    }
}

internal sealed class NativeRandomizerType
{
    internal string Type { get; }
    internal string SubType { get; }
    internal string RequiredParameter { get; }

    internal NativeRandomizerType(string type, string subType, string requiredParameter)
    {
        Type = type;
        SubType = subType;
        RequiredParameter = requiredParameter;
    }
}
