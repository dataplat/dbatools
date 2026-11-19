using System;
using System.Collections.Generic;
using System.Management.Automation;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Utility
{
    /// <summary>
    /// private/functions/Compare-DbaCollationSensitiveObject.ps1 parity: filters a sequence
    /// by comparing a named property against value(s) with the SMO string comparer for a
    /// given SQL Server collation (an unconnected Server supplies the comparer, exactly like
    /// the helper's New-Object Smo.Server call; an unknown collation faults the same way).
    /// Faithful quirks: PS-FALSY input items are skipped (the helper's `if (-not $obj)`
    /// guard - so null, empty string, 0 and $false items all drop, not just null); In with a
    /// null Value yields nothing while NotIn yields everything (PS foreach over $null
    /// iterates zero times - LanguagePrimitives.GetEnumerable reproduces the same statement
    /// semantics); a missing property compares as null, so Eq against a null Value emits the
    /// item; comparands pass RAW to IComparer.Compare(object, object) - the exact overload
    /// the PS method binder resolves (GetStringComparer returns IComparer), with only the
    /// PSObject wrapper unwrapped as the binder does. The helper's
    /// begin-block named-argument re-invocation is pipeline plumbing with no compiled
    /// equivalent - callers pass the sequence directly. Sole PS caller: Get-DbaDatabase
    /// (helper retained at refcount 2).
    /// </summary>
    public static class CollationSensitiveFilter
    {
        /// <summary>The helper's four parameter sets.</summary>
        public enum FilterMode
        {
            /// <summary>Emit items whose property matches any of the values.</summary>
            In,
            /// <summary>Emit items whose property matches none of the values.</summary>
            NotIn,
            /// <summary>Emit items whose property equals the value.</summary>
            Eq,
            /// <summary>Emit items whose property differs from the value.</summary>
            Ne
        }

        /// <summary>
        /// Filters <paramref name="inputObject"/> like the PS helper's process block,
        /// emitting matches lazily in input order.
        /// </summary>
        public static IEnumerable<object> Compare(IEnumerable<object> inputObject, string property, FilterMode mode, object value, string collation)
        {
            if (inputObject == null)
                throw new ArgumentNullException("inputObject");
            if (String.IsNullOrEmpty(property))
                throw new ArgumentNullException("property");
            if (String.IsNullOrEmpty(collation))
                throw new ArgumentNullException("collation");

            // Helper line 80: an unconnected SMO Server resolves the collation's comparer
            // client-side; invalid collations fault here, before any item is read.
            System.Collections.IComparer stringComparer = new Server().GetStringComparer(collation);
            return FilterIterator(inputObject, property, mode, value, stringComparer);
        }

        private static IEnumerable<object> FilterIterator(IEnumerable<object> inputObject, string property, FilterMode mode, object value, System.Collections.IComparer stringComparer)
        {
            foreach (object item in inputObject)
            {
                // Helper line 84: `if (-not $obj) { return }` - PS truthiness, per record.
                if (!LanguagePrimitives.IsTrue(item))
                    continue;

                // The helper reads $obj.$Property INSIDE each comparison (per candidate),
                // so a null Value never touches the property at all - the lookup is
                // deliberately not hoisted, keeping even throwing/side-effecting getters
                // parity-exact.
                switch (mode)
                {
                    case FilterMode.In:
                        foreach (object candidate in EnumerateLikePsForeach(value))
                        {
                            if (stringComparer.Compare(GetPropertyValue(item, property), Unwrap(candidate)) == 0)
                            {
                                // Helper line 89: process-block `return $obj` = emit and
                                // move to the next pipeline item.
                                yield return item;
                                break;
                            }
                        }
                        break;
                    case FilterMode.NotIn:
                        bool matchFound = false;
                        foreach (object candidate in EnumerateLikePsForeach(value))
                        {
                            if (stringComparer.Compare(GetPropertyValue(item, property), Unwrap(candidate)) == 0)
                                matchFound = true;
                        }
                        if (!matchFound)
                            yield return item;
                        break;
                    case FilterMode.Eq:
                        if (stringComparer.Compare(GetPropertyValue(item, property), Unwrap(value)) == 0)
                            yield return item;
                        break;
                    case FilterMode.Ne:
                        if (stringComparer.Compare(GetPropertyValue(item, property), Unwrap(value)) != 0)
                            yield return item;
                        break;
                }
            }
        }

        /// <summary>PS `$obj.$Property`: PSObject-aware lookup; a missing property is null.
        /// Lookup is PROPERTY-based (note + adapted properties) - Hashtable KEY access,
        /// which the PS binder would also resolve for `$h.a`, is out of scope; no caller
        /// passes dictionaries.</summary>
        private static object GetPropertyValue(object item, string property)
        {
            PSObject wrapped = PSObject.AsPSObject(item);
            PSPropertyInfo info = wrapped.Properties[property];
            object propertyValue = info == null ? null : info.Value;
            if (propertyValue is PSObject psValue)
                propertyValue = psValue.BaseObject;
            return propertyValue;
        }

        /// <summary>PS `foreach ($dif in $Value)` statement semantics: null iterates zero
        /// times, collections iterate their items, scalars iterate once.</summary>
        private static IEnumerable<object> EnumerateLikePsForeach(object value)
        {
            if (value == null)
                yield break;
            System.Collections.IEnumerable enumerable = LanguagePrimitives.GetEnumerable(value);
            if (enumerable == null)
            {
                yield return value;
                yield break;
            }
            foreach (object item in enumerable)
                yield return item;
        }

        /// <summary>The PS method binder passes arguments to Compare(object, object) with
        /// only the PSObject transit wrapper unwrapped.</summary>
        private static object Unwrap(object value)
        {
            if (value is PSObject psValue)
                return psValue.BaseObject;
            return value;
        }
    }
}
