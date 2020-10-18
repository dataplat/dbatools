using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace Sqlcollaborative.Dbatools.Parameter
{
    /// <summary>
    /// Parameter class parsing various inputs for scriptmethod properties
    /// </summary>
    [ParameterClass]
    public class SelectScriptMethodParameter : ParameterClass
    {
        /// <summary>
        /// The name to script mappings that make up the script properties or methods
        /// </summary>
        public Dictionary<string, ScriptBlock> Value = new Dictionary<string, ScriptBlock>(StringComparer.InvariantCultureIgnoreCase);

        /// <summary>
        /// Retrieve a list of script methods. Results will be automatically cached on first retrieval
        /// </summary>
        public List<PSScriptMethod> Methods
        {
            get
            {
                if (_Methods == null)
                {
                    _Methods = new List<PSScriptMethod>();
                    foreach (string key in Value.Keys)
                        _Methods.Add(new PSScriptMethod(key, Value[key]));
                }
                return _Methods;
            }
        }
        List<PSScriptMethod> _Methods;

        /// <summary>
        /// Convert hashtables to scriptmethod properties
        /// </summary>
        /// <param name="Hashtable">A hashtable mapping name to scriptblock</param>
        public SelectScriptMethodParameter(Hashtable Hashtable)
        {
            InputObject = Hashtable;
            foreach (string key in Hashtable.Keys)
            {
                if (String.IsNullOrEmpty(key))
                    throw new ArgumentNullException("Cannot convert a null or empty string as key!");
                if (Hashtable[key] == null)
                    throw new ArgumentNullException(String.Format("There is no value defined for key '{0}'!", key));
                if (!(Hashtable[key] is ScriptBlock))
                    throw new ArgumentException(String.Format("The value for the key '{0}' was not a scriptblock!", key));

                Value[key] = (ScriptBlock)Hashtable[key];
            }
        }

        /// <summary>
        /// Parses a string input into one or multiple alias expressions.
        /// </summary>
        /// <param name="StringValue">the string to parse</param>
        public SelectScriptMethodParameter(string StringValue)
        {
            InputObject = StringValue;
            foreach (string value in StringValue.Split(','))
            {
                if (!Regex.IsMatch(value, " => ", RegexOptions.IgnoreCase))
                    throw new ArgumentException(String.Format("Invalid input string, could not evaluate '{0}' as scriptmethod!", value));
                Match match = Regex.Match(value, "^(.*?) => (.*?)$", RegexOptions.IgnoreCase);
                Value[match.Groups[1].Value.Trim()] = ScriptBlock.Create(match.Groups[2].Value.Trim());
            }
        }

        /// <summary>
        /// Create a script method from a scriptblock. Scriptblock is processed as string!
        /// </summary>
        /// <param name="ScriptBlock">The scriptblock to evaluate</param>
        public SelectScriptMethodParameter(ScriptBlock ScriptBlock)
            : this(ScriptBlock == null ? null : ScriptBlock.ToString().Trim())
        {
            InputObject = ScriptBlock;
        }

        /// <summary>
        /// Create a scriptmethod from ... a scriptmethod!
        /// </summary>
        /// <param name="Method">The scriptmethod to integrate</param>
        public SelectScriptMethodParameter(PSScriptMethod Method)
        {
            InputObject = Method;
            Value[Method.Name] = Method.Script;
        }

        /// <summary>
        /// Returnd the string representation of the scriptmethod
        /// </summary>
        /// <returns></returns>
        public override string ToString()
        {
            List<string> strings = new List<string>();
            foreach (string key in Value.Keys)
                strings.Add(String.Format("{0}() => {1}", key, Value[key]));
            return String.Join(", ", strings);
        }
    }
}
