using System;
using System.Collections.Generic;

namespace Sqlcollaborative.Dbatools.Message
{
    /// <summary>
    /// A modification to a given message's level
    /// </summary>
    public class MessageLevelModifier
    {
        /// <summary>
        /// Name of the modifier. Prevents duplication in a multi-runspace scenario.
        /// </summary>
        public string Name;

        /// <summary>
        /// The amount to modify the level by
        /// </summary>
        public int Modifier;

        /// <summary>
        /// Apply modifier only to messages from this function.
        /// </summary>
        public string IncludeFunctionName;

        /// <summary>
        /// Apply modifier not when the message is written by this function.
        /// </summary>
        public string ExcludeFunctionName;

        /// <summary>
        /// Apply modifier only to messages from this module
        /// </summary>
        public string IncludeModuleName;

        /// <summary>
        /// Do not apply modifier to messages from this module
        /// </summary>
        public string ExcludeModuleName;

        /// <summary>
        /// Only apply this modifier to a message that includes at least one of these tags
        /// </summary>
        public List<string> IncludeTags = new List<string>();

        /// <summary>
        /// Do not apply this modifier to a message that includes any of the following tags
        /// </summary>
        public List<string> ExcludeTags = new List<string>();

        /// <summary>
        /// Tests, whether a message a message should be modified by this modiier
        /// </summary>
        /// <param name="FunctionName">The name of the function writing the message</param>
        /// <param name="ModuleName">The name of the module, the function writing this message comes from</param>
        /// <param name="Tags">The tags of the message written</param>
        /// <returns>Whether the message applies</returns>
        public bool AppliesTo(string FunctionName, string ModuleName, List<string> Tags)
        {
            // Negatives
            if (ExcludeFunctionName == FunctionName)
                return false;
            if (ExcludeModuleName == ModuleName)
                return false;
            if (Tags != null)
                foreach (string tag in ExcludeTags)
                    foreach (string tag2 in Tags)
                        if (tag == tag2)
                            return false;

            // Positives
            if (!String.IsNullOrEmpty(IncludeFunctionName))
                if (IncludeFunctionName != FunctionName)
                    return false;
            if (!String.IsNullOrEmpty(IncludeModuleName))
                if (IncludeModuleName != ModuleName)
                    return false;

            if (IncludeTags.Count > 0)
            {
                if (Tags != null)
                    foreach (string tag in IncludeTags)
                        foreach (string tag2 in Tags)
                            if (tag == tag2)
                                return true;

                return false;
            }

            return true;
        }
    }
}
