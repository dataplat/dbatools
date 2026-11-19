using System;

namespace Dataplat.Dbatools.Utility
{
    /// <summary>
    /// Replicates PowerShell's array-parameter truthiness for ported filter guards: the PS
    /// pattern "if ($ArrayParam) { ... }" treats a single-element array as the truthiness of
    /// its element, so -Database '' or -TraceFlag 0 silently DISABLES the filter instead of
    /// filtering everything out. Cross-model review finding, 2026-07-06.
    /// </summary>
    public static class FilterHelper
    {
        /// <summary>PS truthiness of a string-array filter parameter.</summary>
        /// <param name="values">The parameter value</param>
        /// <returns>True when the PS source's if-guard would run the filter</returns>
        public static bool IsActive(string[] values)
        {
            if (values == null || values.Length == 0)
                return false;
            if (values.Length == 1)
                return !String.IsNullOrEmpty(values[0]);
            return true;
        }

        /// <summary>PS truthiness of an object-array filter parameter.</summary>
        /// <param name="values">The parameter value</param>
        /// <returns>True when the PS source's if-guard would run the filter</returns>
        public static bool IsActive(object[] values)
        {
            if (values == null || values.Length == 0)
                return false;
            if (values.Length == 1)
            {
                object single = values[0];
                if (single == null)
                    return false;
                string text = single as string;
                if (text != null)
                    return text.Length > 0;
                if (single is int)
                    return (int)single != 0;
                return true;
            }
            return true;
        }

        /// <summary>PS truthiness of an int-array filter parameter.</summary>
        /// <param name="values">The parameter value</param>
        /// <returns>True when the PS source's if-guard would run the filter</returns>
        public static bool IsActive(int[] values)
        {
            if (values == null || values.Length == 0)
                return false;
            if (values.Length == 1)
                return values[0] != 0;
            return true;
        }
    }
}
