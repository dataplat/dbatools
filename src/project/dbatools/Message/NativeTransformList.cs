using System.Collections.Generic;

namespace Dataplat.Dbatools.Message
{
    /// <summary>Ordered native conditions with duplicate-filter suppression.</summary>
    public sealed class NativeTransformList
    {
        private readonly List<NativeTransformCondition> conditions = new List<NativeTransformCondition>();

        /// <summary>Returns the original conditions in insertion order.</summary>
        public NativeTransformCondition[] GetAll()
        {
            return conditions.ToArray();
        }

        /// <summary>Tests membership by condition identity.</summary>
        public bool IsListed(NativeTransformCondition condition)
        {
            return conditions.Contains(condition);
        }

        /// <summary>Tests literal filter/type equality independently of the descriptor.</summary>
        public bool IsContained(NativeTransformCondition condition)
        {
            foreach (NativeTransformCondition existing in conditions)
                if (existing.HasSameFilters(condition))
                    return true;
            return false;
        }

        /// <summary>Adds a condition only when its filter/type tuple is absent.</summary>
        public void Add(NativeTransformCondition condition)
        {
            if (!IsContained(condition))
                conditions.Add(condition);
        }

        /// <summary>Removes the supplied condition by identity.</summary>
        public void Remove(NativeTransformCondition condition)
        {
            conditions.Remove(condition);
        }

        /// <summary>Returns the first matching condition, or null.</summary>
        public NativeTransformCondition Get(string typeName, string moduleName, string functionName)
        {
            foreach (NativeTransformCondition condition in conditions)
                if (condition.Matches(typeName, moduleName, functionName))
                    return condition;
            return null;
        }
    }
}
