using System;
using System.Collections;
using System.Linq;
using System.Management.Automation;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.Parameter
{
    /// <summary>
    /// Class that automatically parses input chosen for the -Property parameter of Select-PSUObject
    /// </summary>
    public class DbaSelectParameter
    {
        /// <summary>
        /// The original input object
        /// </summary>
        public object InputObject;

        /// <summary>
        /// The value as Select-Object wants it
        /// </summary>
        public object Value;

        /// <summary>
        /// Builds a property parameter from string
        /// </summary>
        /// <param name="Value">The string to interpret</param>
        public DbaSelectParameter(string Value)
        {
            InputObject = Value;

            if (!Value.Contains(" "))
            {
                this.Value = Value;
                return;
            }

            #region Process Input
            // Runtime properties
            string valueName = "";
            string propertyName = "";
            string castType = "";
            string fromName = "_";
            string wherePropInput = "";
            string wherePropOutput = "";
            string sizeName = "";
            uint sizeDecimals = 0;
            bool sizeShow = false;

            string tempValue = Value.Trim();
            propertyName = tempValue.Split(' ')[0];
            valueName = propertyName;
            tempValue = tempValue.Substring(propertyName.Length);

            if (Regex.IsMatch(tempValue, @" as \w+", RegexOptions.IgnoreCase))
            {
                propertyName = Regex.Match(tempValue, @" as (\w+)", RegexOptions.IgnoreCase).Groups[1].Value;
                tempValue = Regex.Replace(tempValue, @" as \w+", "", RegexOptions.IgnoreCase);
            }

            if (Regex.IsMatch(tempValue, @" from [\w_]+", RegexOptions.IgnoreCase))
            {
                fromName = Regex.Match(tempValue, @" from ([\w_]+)", RegexOptions.IgnoreCase).Groups[1].Value;
                tempValue = Regex.Replace(tempValue, @" from [\w_]+", "", RegexOptions.IgnoreCase);
            }

            if (Regex.IsMatch(tempValue, @" where [\w_]+ = [\w_]+", RegexOptions.IgnoreCase))
            {
                Match match = Regex.Match(tempValue, @" where ([\w_]+) = ([\w_]+)", RegexOptions.IgnoreCase);
                wherePropOutput = match.Groups[1].Value;
                wherePropInput = match.Groups[2].Value;
                tempValue = Regex.Replace(tempValue, @" where [\w_]+ = [\w_]+", "", RegexOptions.IgnoreCase);
            }

            if (Regex.IsMatch(tempValue, @" to [\w\.]+", RegexOptions.IgnoreCase))
            {
                castType = Regex.Match(tempValue, @" to ([\w\.]+)", RegexOptions.IgnoreCase).Groups[1].Value;
                tempValue = Regex.Replace(tempValue, @" to [\w\.]+", "", RegexOptions.IgnoreCase);
            }

            if (Regex.IsMatch(tempValue, @" size \w+(:\d){1,2}", RegexOptions.IgnoreCase))
            {
                Match match = Regex.Match(tempValue, @" size (\w+)(:\d){1,2}", RegexOptions.IgnoreCase);
                sizeName = match.Groups[1].Value;
                sizeDecimals = UInt32.Parse(match.Groups[2].Captures[0].Value.Trim(':'));
                if (match.Groups[2].Captures.Count > 1)
                    sizeShow = match.Groups[2].Captures[1].Value == ":1";
                tempValue = Regex.Replace(tempValue, @" size \w+(:\d){1,2}", "", RegexOptions.IgnoreCase);
            }

            if (!String.IsNullOrEmpty(tempValue))
                throw new ArgumentException(String.Format("Failed to parse input! Original input: {0} | Unprocessed leftovers: {1}", Value, tempValue));
            #endregion Process Input

            #region Build Hashtable
            Hashtable table = new Hashtable();
            table["Name"] = propertyName;

            // Process cast strings
            string stringCast = "";
            if (!String.IsNullOrEmpty(castType))
                stringCast = String.Format("[{0}]", castType);

            // Process size strings
            string stringSizeStart = "";
            string stringSizeEnd = "";
            if (sizeName != "")
            {
                stringSizeStart = "[System.Math]::Round((";
                stringSizeEnd = String.Format(" / 1{0}), {1})", sizeName, sizeDecimals);
                if (sizeShow)
                {
                    stringSizeStart = String.Format("\"$({0}", stringSizeStart);
                    stringSizeEnd = String.Format("{0}) {1}\"", stringSizeEnd, sizeName);
                }
            }

            // Process value strings
            string stringGuidVar = "${" + Guid.NewGuid().ToString() + "}";
            string preLine = String.Format("{0} = $_\n", stringGuidVar);
            string stringValue = String.Format("${0}", fromName);
            if (fromName != "_" && wherePropInput != "")
            {
                stringValue = String.Format("({1} | Where-Object {2} -eq {0}.{3})", stringGuidVar, stringValue, wherePropOutput, wherePropInput);
            }

            if (propertyName != ".")
                stringValue = String.Format("{0}.{1}", stringValue, valueName);

            // <guid> = $_
            // "(<size>(<cast>(<value>))<sizeName>)"
            string script = String.Format("{0}({1}({2}({3})){4})", preLine, stringSizeStart, stringCast, stringValue, stringSizeEnd);

            table["Expression"] = ScriptBlock.Create(script);
            this.Value = table;
            #endregion Build Hashtable
        }

        /// <summary>
        /// Builds a select parameter from a hashtable (pretty straightforward)
        /// </summary>
        /// <param name="Hash">The hashtable to accept</param>
        public DbaSelectParameter(Hashtable Hash)
        {
            InputObject = Hash;
            Value = Hash;
        }
    }
}
