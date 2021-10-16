using System.Collections.Generic;

namespace Sqlcollaborative.Dbatools.Parameter
{
    /// <summary>
    /// Base class of all parameter classes
    /// </summary>
    [ParameterClass]
    public abstract class ParameterClass
    {
        #region Fields of contract
        /// <summary>
        /// The original item presented as input
        /// </summary>
        [ParameterContract(ParameterContractType.Field, ParameterContractBehavior.Mandatory)]
        public object InputObject;
        #endregion Fields of contract

        #region Static tools
        /// <summary>
        /// Contains the list of property mappings.
        /// Types can be registered to it, allowing the parameter class to blindly interpret unknown types
        /// </summary>
        internal static Dictionary<string, List<string>> _PropertyMapping = new Dictionary<string, List<string>>();

        /// <summary>
        /// Assigns a property mapping for a given type, allowing the parameter class to handle unknown types
        /// </summary>
        /// <param name="Name">The name of the type. Use the FullName of the type</param>
        /// <param name="PropertyName">The property names to register. When parsing input, it will move down this list until a valid property was found</param>
        public static void SetTypePropertyMapping(string Name, List<string> PropertyName)
        {
            _PropertyMapping[Name.ToLower()] = PropertyName;
        }
        #endregion Static tools

        #region Methods
        /// <summary>
        /// Returns the string representation of the parameter. Should be overridden by inheriting classes.
        /// </summary>
        /// <returns>The string representation of the object</returns>
        public abstract override string ToString();
        #endregion Methods
    }
}
