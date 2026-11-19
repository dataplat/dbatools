using System;
using System.Runtime.CompilerServices;

namespace Dataplat.Dbatools.Message
{
    /// <summary>Remembers explicit legacy activation for each pair of public registry objects.</summary>
    public static class LegacyTransformRegistryMode
    {
        private static readonly ConditionalWeakTable<object, ConditionalWeakTable<object, object>> targets = new ConditionalWeakTable<object, ConditionalWeakTable<object, object>>();
        private static readonly ConditionalWeakTable<object, ConditionalWeakTable<object, object>> exceptions = new ConditionalWeakTable<object, ConditionalWeakTable<object, object>>();

        /// <summary>Activates a pair without retaining either registry after its owner releases it.</summary>
        /// <param name="type">The transform kind.</param>
        /// <param name="exactRegistry">The exact-match registry object.</param>
        /// <param name="conditionalRegistry">The conditional registry object.</param>
        public static void Activate(TransformType type, object exactRegistry, object conditionalRegistry)
        {
            GetPairs(type).GetValue(exactRegistry, CreatePairs).GetValue(conditionalRegistry, CreateMarker);
        }

        /// <summary>Uses legacy mode for an activated pair or a pair containing registrations.</summary>
        /// <param name="type">The transform kind.</param>
        /// <param name="exactRegistry">The exact-match registry object.</param>
        /// <param name="conditionalRegistry">The conditional registry object.</param>
        /// <param name="hasRegistrations">Whether either captured registry contains an entry.</param>
        /// <returns>Whether the frontend must use only this legacy pair.</returns>
        public static bool UseLegacy(TransformType type, object exactRegistry, object conditionalRegistry, bool hasRegistrations)
        {
            if (hasRegistrations)
            {
                Activate(type, exactRegistry, conditionalRegistry);
                return true;
            }
            ConditionalWeakTable<object, object> pairs;
            object marker;
            return GetPairs(type).TryGetValue(exactRegistry, out pairs) && pairs.TryGetValue(conditionalRegistry, out marker);
        }

        private static ConditionalWeakTable<object, ConditionalWeakTable<object, object>> GetPairs(TransformType type)
        {
            if (type == TransformType.Target) return targets;
            if (type == TransformType.Exception) return exceptions;
            throw new ArgumentOutOfRangeException("type");
        }

        private static ConditionalWeakTable<object, object> CreatePairs(object key)
        {
            return new ConditionalWeakTable<object, object>();
        }

        private static object CreateMarker(object key)
        {
            return new object();
        }
    }
}
