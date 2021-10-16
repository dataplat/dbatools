using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Sqlcollaborative.Dbatools.Utility;

namespace Sqlcollaborative.Dbatools.TabExpansion
{
    /// <summary>
    /// Contains information used to transmit Tepp Assignment
    /// </summary>
    public class TabCompletionSet
    {
        /// <summary>
        /// The name of the command to complete. "*" if all commands that have the parameter should be selected instead
        /// </summary>
        public string Command;

        /// <summary>
        /// The parameter to complete
        /// </summary>
        public string Parameter;

        /// <summary>
        /// The name of the script to complete with
        /// </summary>
        public string Script;

        /// <summary>
        /// Creates a new tab completion set object with all information prefilled
        /// </summary>
        /// <param name="Command">The name of the command to complete. "*" if all commands that have the parameter should be selected instead</param>
        /// <param name="Parameter">The parameter to complete</param>
        /// <param name="Script">The name of the script to complete with</param>
        public TabCompletionSet(string Command, string Parameter, string Script)
        {
            this.Command = Command;
            this.Parameter = Parameter;
            this.Script = Script;
        }

        /// <summary>
        /// Tests, whether the completion set applies to the specified parameter / command combination
        /// </summary>
        /// <param name="Command">The command to test</param>
        /// <param name="Parameter">The parameter of the command to test</param>
        /// <returns>Whether this completion set applies to the specified combination of parameter / command</returns>
        public bool Applies(string Command, string Parameter)
        {
            if ((UtilityHost.IsLike(Command, this.Command)) && (UtilityHost.IsLike(Parameter, this.Parameter)))
                return true;
            return false;
        }
    }
}
