using System.Management.Automation;

namespace Dataplat.Dbatools.Utility
{
    /// <summary>Preserves the version tables from the pinned private configuration-default helper.</summary>
    public static partial class SqlConfigurationDefaults
    {
        /// <summary>Returns a fresh ordered property table, or null for an unmatched version string.</summary>
        public static PSObject Get(string version)
        {
            switch (version)
            {
                case "8": return Create(8);
                case "9": return Create(9);
                case "10": return Create(10);
                case "11": return Create(11);
                case "12": return Create(12);
                case "13": return Create(13);
                case "14": return Create(14);
                case "15": return Create(15);
                case "16": return Create(16);
                default: return null;
            }
        }

        private static PSObject Create(int version)
        {
            PSObject defaults = new PSObject();
            AddOptionsThroughFullText(defaults, version);
            AddOptionsThroughRemoteQuery(defaults, version);
            AddRemainingOptions(defaults, version);
            return defaults;
        }

        private static void Add(PSObject target, int version, int firstVersion, int lastVersion, string name, int value)
        {
            if (version >= firstVersion && version <= lastVersion)
                target.Properties.Add(new PSNoteProperty(name, value));
        }
    }
}
