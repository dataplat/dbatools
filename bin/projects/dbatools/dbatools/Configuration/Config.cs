using System;
using System.Management.Automation;

namespace Sqlcollaborative.Dbatools.Configuration
{
    /// <summary>
    /// Configuration Manager as well as individual configuration object.
    /// </summary>
    [Serializable]
    public class Config
    {
        /// <summary>
        /// The Name of the setting
        /// </summary>
        public string Name { get; set; }

        /// <summary>
        /// The full name of the configuration entry, comprised of both Module and Name.
        /// </summary>
        public string FullName
        {
            get { return Module + "." + Name; }
        }

        /// <summary>
        /// The module of the setting. Helps being able to group configurations.
        /// </summary>
        public string Module { get; set; }

        /// <summary>
        /// A description of the specific setting
        /// </summary>
        public string Description { get; set; }

        /// <summary>
        /// The data type of the value stored in the configuration element.
        /// </summary>
        public string Type
        {
            get
            {
                if (Value == null)
                    return null;
                return Value.GetType().FullName;
            }
        }

        /// <summary>
        /// The value stored in the configuration element
        /// </summary>
        public Object Value { get; set; }

        /// <summary>
        /// The handler script that is run whenever the configuration value is set.
        /// </summary>
        public ScriptBlock Handler { get; set; }

        /// <summary>
        /// Validates the user input
        /// </summary>
        public ScriptBlock Validation { get; set; }

        /// <summary>
        /// Setting this to true will cause the element to not be discovered unless using the '-Force' parameter on "Get-DbaConfig"
        /// </summary>
        public bool Hidden { get; set; }

        /// <summary>
        /// Whether the setting has been initialized. This handles module imports and avoids modules overwriting settings when imported in multiple runspaces.
        /// </summary>
        public bool Initialized { get; set; }

        /// <summary>
        /// Whether this setting was set by policy
        /// </summary>
        public bool PolicySet { get; set; }

        /// <summary>
        /// Whether this setting was set by policy and forbids deletion.
        /// </summary>
        public bool PolicyEnforced
        {
            get { return _PolicyEnforced; }
            set
            {
                if (_PolicyEnforced == false) { _PolicyEnforced = value; }
            }
        }
        private bool _PolicyEnforced = false;

        /// <summary>
        /// The finalized value to put into the registry value when using policy to set this setting.
        /// </summary>
        public string RegistryData
        {
            get
            {
                switch (Type)
                {
                    case "System.Boolean":
                        if ((bool)Value)
                            return "bool:true";
                        return "bool:false";
                    case "System.Int16":
                        return String.Format("int:{0}", Value);
                    case "System.Int32":
                        return String.Format("int:{0}", Value);
                    case "System.Int64":
                        return String.Format("long:{0}", Value);
                    case "System.UInt16":
                        return String.Format("int:{0}", Value);
                    case "System.UInt32":
                        return String.Format("long:{0}", Value);
                    case "System.UInt64":
                        return String.Format("long:{0}", Value);
                    case "System.Double":
                        return String.Format("double:{0}", Value);
                    case "System.String":
                        return String.Format("string:{0}", Value);
                    case "System.TimeSpan":
                        return String.Format("timespan:{0}", ((TimeSpan)Value).Ticks);
                    case "System.DateTime":
                        return String.Format("datetime:{0}", ((DateTime)Value).Ticks);
                    case "System.ConsoleColor":
                        return String.Format("consolecolor:{0}", Value);
                    default:
                        return "<type not supported>";
                }
            }
        }
    }
}