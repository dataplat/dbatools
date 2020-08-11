using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace Sqlcollaborative.Dbatools.Parameter
{
    /// <summary>
    /// A parameter class for binding specific alias property mappings
    /// </summary>
    [ParameterClass]
    public class SelectAliasParameter : ParameterClass
    {
        /// <summary>
        /// The aliases to map
        /// </summary>
        public Dictionary<string, string> Value = new Dictionary<string, string>(StringComparer.InvariantCultureIgnoreCase);

        /// <summary>
        /// The alias objects to use. Will be cached on first retrieval
        /// </summary>
        public List<PSAliasProperty> Aliases
        {
            get
            {
                if (_Aliases == null)
                {
                    _Aliases = new List<PSAliasProperty>();
                    foreach (string key in Value.Keys)
                        _Aliases.Add(new PSAliasProperty(key, Value[key]));
                }
                return _Aliases;
            }
        }
        private List<PSAliasProperty> _Aliases;

        /// <summary>
        /// Convert hashtables to alias properties
        /// </summary>
        /// <param name="Hashtable">A hashtable mapping alias name to reference property</param>
        public SelectAliasParameter(Hashtable Hashtable)
        {
            InputObject = Hashtable;
            foreach (string key in Hashtable.Keys)
                if (!String.IsNullOrEmpty(key) && (Hashtable[key] != null) && !String.IsNullOrEmpty((string)Hashtable[key]))
                    Value[key] = (string)Hashtable[key];
        }

        /// <summary>
        /// Parses a string input into one or multiple alias expressions.
        /// </summary>
        /// <param name="StringValue">the string to parse</param>
        public SelectAliasParameter(string StringValue)
        {
            InputObject = StringValue;
            foreach (string value in StringValue.Split(','))
            {
                if (!Regex.IsMatch(value, " as ", RegexOptions.IgnoreCase))
                    throw new ArgumentException(String.Format("Invalid input string, could not evaluate '{0}' as alias!", value));
                Match match = Regex.Match(value, "^(.*?) as (.*?)$", RegexOptions.IgnoreCase);
                Value[match.Groups[2].Value.Trim()] = match.Groups[1].Value.Trim();
            }
        }

        /// <summary>
        /// Builds the string display of the parameter class
        /// </summary>
        /// <returns>The string representation of the aliases to create</returns>
        public override string ToString()
        {
            List<string> strings = new List<string>();
            foreach (string key in Value.Keys)
                strings.Add(String.Format("{0} as {1}", key, Value[key]));
            return String.Join(", ", strings);
        }
    }
}
