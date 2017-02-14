
#region Source Code
$source = @'
using System;

namespace sqlcollective.dbatools
{
    namespace Configuration
    {
        using System.Collections;

        /// <summary>
        /// Configuration Manager as well as individual configuration object.
        /// </summary>
        [Serializable]
        public class Config
        {
            public static Hashtable Cfg = new Hashtable();

            public string Name;
            public string Module;
            public string Type
            {
                get { return Value.GetType().FullName; }
                set { }
            }
            public Object Value;
            public bool Hidden = false;
        }
    }
}
'@
#endregion Source Code

try { Add-Type $source -ErrorAction Stop }
catch
{
    throw
}