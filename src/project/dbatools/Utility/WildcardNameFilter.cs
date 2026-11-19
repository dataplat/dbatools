using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;

namespace Dataplat.Dbatools.Utility
{
    /// <summary>
    /// Name matching for ported filters whose pinned help documents wildcards while the source
    /// compares with -in, -notin or Get-DbaDatabase's exact matching, so the documented pattern
    /// never takes effect (rule E+, Fable a8531b76). A filter value matches a name when the
    /// command's existing literal comparison matches it. A string value containing * or ? is also
    /// tried as a case-insensitive wildcard pattern, unless it equals, by that same literal
    /// comparison, the name of an object in the filter's unfiltered scope: then it stays literal
    /// only, so a caller passing a real object name never reaches other objects. Brackets alone
    /// never make a value a pattern (an SMO object bound to a string array becomes "[name]"), and
    /// an invalid pattern stays a literal-only value. Exclusion filters use the same rule.
    /// </summary>
    public static class WildcardNameFilter
    {
        private static readonly char[] PatternCharacters = { '*', '?' };

        /// <summary>
        /// True when the value is a string, or a PSObject wrapping one, that contains * or ?.
        /// </summary>
        /// <param name="value">A filter value as bound by the cmdlet</param>
        /// <returns>True when the value may be tried as a wildcard pattern</returns>
        public static bool IsPatternCandidate(object value)
        {
            return PatternText(value) != null;
        }

        /// <summary>
        /// True only when the value is a pattern candidate that compiles as a case-insensitive
        /// WildcardPattern and matches the name. It does not apply the scope collision rule.
        /// </summary>
        /// <param name="value">A filter value as bound by the cmdlet</param>
        /// <param name="name">The object name being tested</param>
        /// <returns>True when the value matches the name as a wildcard pattern</returns>
        public static bool PatternMatches(object value, string name)
        {
            string text = PatternText(value);
            if (name == null || text == null)
                return false;
            try
            {
                return WildcardPattern.Get(text, WildcardOptions.IgnoreCase).IsMatch(name);
            }
            catch (WildcardPatternException)
            {
                // An invalid expression such as "db[*" is not a pattern; the literal comparison
                // alone decides it, as it did before wildcards were honoured.
                return false;
            }
        }

        /// <summary>
        /// Builds the matcher for one filter over one scope.
        /// </summary>
        /// <param name="values">The filter values; null matches nothing</param>
        /// <param name="allowPatterns">True only where the pinned help documents wildcards</param>
        /// <param name="literal">The command's existing literal comparison of one value and a name</param>
        /// <param name="scope">The names of every object in the filter's unfiltered scope (for
        /// example all databases of the instance). Enumerated only when patterns are allowed and
        /// a value is a pattern candidate; required in that case.</param>
        /// <returns>A matcher that decides each name of that scope</returns>
        public static WildcardNameMatcher CreateMatcher(IEnumerable values, bool allowPatterns,
            Func<object, string, bool> literal, IEnumerable<string> scope)
        {
            if (literal == null)
                throw new ArgumentNullException("literal");
            List<object> filters = new List<object>();
            List<bool> patterns = new List<bool>();
            List<string> names = null;
            if (values != null)
            {
                foreach (object value in values)
                {
                    bool pattern = false;
                    if (allowPatterns && IsPatternCandidate(value))
                    {
                        if (names == null)
                        {
                            if (scope == null)
                                throw new ArgumentNullException("scope", "Wildcard filters need the unfiltered scope to keep real names literal.");
                            names = new List<string>(scope);
                        }
                        pattern = !Collides(value, names, literal);
                    }
                    filters.Add(value);
                    patterns.Add(pattern);
                }
            }
            return new WildcardNameMatcher(filters.ToArray(), patterns.ToArray(), literal);
        }

        private static bool Collides(object value, List<string> names, Func<object, string, bool> literal)
        {
            foreach (string name in names)
            {
                if (literal(value, name))
                    return true;
            }
            return false;
        }

        private static string PatternText(object value)
        {
            PSObject wrapped = value as PSObject;
            string text = (wrapped != null ? wrapped.BaseObject : value) as string;
            return text != null && text.IndexOfAny(PatternCharacters) >= 0 ? text : null;
        }
    }

    /// <summary>
    /// One filter's values over one scope, built by <see cref="WildcardNameFilter.CreateMatcher"/>.
    /// </summary>
    public sealed class WildcardNameMatcher
    {
        private readonly object[] _values;
        private readonly bool[] _patterns;
        private readonly Func<object, string, bool> _literal;

        internal WildcardNameMatcher(object[] values, bool[] patterns, Func<object, string, bool> literal)
        {
            _values = values;
            _patterns = patterns;
            _literal = literal;
        }

        /// <summary>
        /// True when a value selects the name: by the literal comparison, or as a wildcard
        /// pattern for a value that is a pattern and is not the real name of an object in scope.
        /// </summary>
        /// <param name="name">The object name being tested</param>
        /// <returns>True when a value selects the name</returns>
        public bool Matches(string name)
        {
            for (int index = 0; index < _values.Length; index++)
            {
                if (_literal(_values[index], name))
                    return true;
                if (_patterns[index] && WildcardNameFilter.PatternMatches(_values[index], name))
                    return true;
            }
            return false;
        }
    }
}
