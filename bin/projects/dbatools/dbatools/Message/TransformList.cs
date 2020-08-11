using Sqlcollaborative.Dbatools.Utility;
using System.Collections.Generic;

namespace Sqlcollaborative.Dbatools.Message
{
    /// <summary>
    /// List engine, managing the lists for a message transformation type
    /// </summary>
    public class TransformList
    {
        private List<TransformCondition> list = new List<TransformCondition>();

        /// <summary>
        /// Returns all entries in the list.
        /// </summary>
        /// <returns>The list of transforms contained within</returns>
        public TransformCondition[] GetAll()
        {
            return list.ToArray();
        }

        /// <summary>
        /// Returns whether the actual object is part of the list
        /// </summary>
        /// <param name="Condition">The object to test for list membership</param>
        /// <returns>Whether the object is listed</returns>
        public bool IsListed(TransformCondition Condition)
        {
            return list.IndexOf(Condition) >= 0;
        }

        /// <summary>
        /// Returns whether a condition with equal conditions already exists
        /// </summary>
        /// <param name="Condition">The condition to test</param>
        /// <returns>Whether the referenced condition is already listed</returns>
        public bool IsContained(TransformCondition Condition)
        {
            foreach (TransformCondition con in list)
            {
                if (con.TypeName != Condition.TypeName)
                    continue;
                if (con.ModuleName != Condition.ModuleName)
                    continue;
                if (con.FunctionName != Condition.FunctionName)
                    continue;
                if (con.Type != Condition.Type)
                    continue;

                return true;
            }
            return false;
        }

        /// <summary>
        /// Adds a condition to the list, if there is no equivalent condition present.
        /// </summary>
        /// <param name="Condition">The condition to add</param>
        public void Add(TransformCondition Condition)
        {
            if (!IsContained(Condition))
                list.Add(Condition);
        }

        /// <summary>
        /// Removes a condition from the lsit of conditional transforms
        /// </summary>
        /// <param name="Condition">The condition to remove</param>
        public void Remove(TransformCondition Condition)
        {
            list.Remove(Condition);
        }

        /// <summary>
        /// Returns the first transform whose filter is similar enough to work out.
        /// </summary>
        /// <param name="TypeName">The name of the type to check for a transform</param>
        /// <param name="ModuleName">The module of the command that wrote the message with the transformable object</param>
        /// <param name="Functionname">The command that wrote the message with the transformable object</param>
        /// <returns>Either a transform or null, if no fitting transform was found</returns>
        public TransformCondition Get(string TypeName, string ModuleName, string Functionname)
        {
            foreach (TransformCondition con in list)
            {
                if (!UtilityHost.IsLike(TypeName, con.TypeName))
                    continue;
                if (!UtilityHost.IsLike(ModuleName, con.ModuleName))
                    continue;
                if (!UtilityHost.IsLike(Functionname, con.FunctionName))
                    continue;

                return con;
            }

            return null;
        }
    }
}
