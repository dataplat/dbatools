using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;

namespace Dataplat.Dbatools.Utility
{
    /// <summary>PowerShell expandable-string rendering with the caller's OFS separator.</summary>
    public static class PowerShellText
    {
        /// <summary>Convert null, scalar, PSObject and enumerable values as an expandable string.</summary>
        public static string Expand(object value, SessionState sessionState)
        {
            if (value == null)
            {
                return string.Empty;
            }
            object baseValue = value is PSObject wrapped ? wrapped.BaseObject : value;
            if (!(baseValue is string) && LanguagePrimitives.GetEnumerable(baseValue) is IEnumerable elements)
            {
                List<string> parts = new List<string>();
                foreach (object element in elements)
                {
                    parts.Add(Expand(element, sessionState));
                }
                string separator = " ";
                try
                {
                    object ofsValue = sessionState.PSVariable.GetValue("OFS");
                    if (ofsValue != null)
                    {
                        separator = (string)LanguagePrimitives.ConvertTo(ofsValue, typeof(string), CultureInfo.InvariantCulture);
                    }
                }
                catch
                {
                    // keep the default single space
                }
                return string.Join(separator, parts);
            }
            return (string)LanguagePrimitives.ConvertTo(value, typeof(string), CultureInfo.InvariantCulture);
        }
    }
}
