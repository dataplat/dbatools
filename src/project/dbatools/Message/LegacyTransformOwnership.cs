using System;
using System.Runtime.CompilerServices;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Message
{
    /// <summary>
    /// Separates caller-supplied legacy transform registrations from the library-owned
    /// defaults that LegacyMessageTransforms seeds. Native processing uses this query to
    /// reject caller registrations explicitly and to ignore library defaults. The query
    /// compares references only: it creates, inspects and invokes no script, and it does
    /// not initialize the legacy defaults.
    /// </summary>
    public static class LegacyTransformOwnership
    {
        // Weak keys: ownership never keeps a released registry entry alive.
        private static readonly ConditionalWeakTable<object, object> owned = new ConditionalWeakTable<object, object>();

        /// <summary>Records a registration object that the library created.</summary>
        /// <param name="registration">A library-owned default script or condition.</param>
        internal static void MarkLibraryOwned(object registration)
        {
            if (registration == null)
                throw new ArgumentNullException("registration");
            owned.GetValue(registration, CreateMarker);
        }

        /// <summary>
        /// Records a library-created condition with the default script it was created with. The condition
        /// counts as library-owned only while it still holds that script, so a caller who replaces the
        /// condition's script has made a caller registration.
        /// </summary>
        /// <param name="condition">The library-owned default condition.</param>
        /// <param name="script">The library-owned default script assigned to it.</param>
        internal static void MarkLibraryOwned(TransformCondition condition, object script)
        {
            if (condition == null)
                throw new ArgumentNullException("condition");
            if (script == null)
                throw new ArgumentNullException("script");
            object recorded;
            if (!owned.TryGetValue(condition, out recorded))
                owned.Add(condition, script);
        }

        /// <summary>
        /// Reports whether a caller-supplied legacy registration matches a type, module and
        /// function. Library-owned defaults never match, whatever their position. Exact
        /// entries are owned when their value is a library default script; conditions are
        /// owned while the library-created condition object still holds its library default script.
        /// All matching conditions are considered, not just the first, so registration order
        /// cannot hide a caller entry.
        /// </summary>
        /// <param name="type">The transform kind.</param>
        /// <param name="typeName">The lower-case full type name being transformed.</param>
        /// <param name="moduleName">The module of the command writing the message.</param>
        /// <param name="functionName">The command writing the message.</param>
        /// <returns>Whether a caller registration applies.</returns>
        public static bool HasCallerRegistration(TransformType type, string typeName, string moduleName, string functionName)
        {
            if (type != TransformType.Target && type != TransformType.Exception)
                throw new ArgumentOutOfRangeException("type");

            var exact = type == TransformType.Target ? MessageHost.TargetTransforms : MessageHost.ExceptionTransforms;
            TransformList conditional = type == TransformType.Target ? MessageHost.TargetTransformlist : MessageHost.ExceptionTransformList;

            if (typeName != null && exact.ContainsKey(typeName) && !IsLibraryOwned(exact[typeName]))
                return true;

            foreach (TransformCondition condition in conditional.GetAll())
            {
                if (IsUnmodifiedLibraryCondition(condition))
                    continue;
                if (!UtilityHost.IsLike(typeName, condition.TypeName))
                    continue;
                if (!UtilityHost.IsLike(moduleName, condition.ModuleName))
                    continue;
                if (!UtilityHost.IsLike(functionName, condition.FunctionName))
                    continue;
                return true;
            }
            return false;
        }

        private static bool IsLibraryOwned(object registration)
        {
            object marker;
            return registration != null && owned.TryGetValue(registration, out marker);
        }

        private static bool IsUnmodifiedLibraryCondition(TransformCondition condition)
        {
            object script;
            return condition != null && owned.TryGetValue(condition, out script) && condition.HoldsScript(script);
        }

        private static object CreateMarker(object key)
        {
            return new object();
        }
    }
}
