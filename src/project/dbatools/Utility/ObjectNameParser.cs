using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Utility
{
    /// <summary>
    /// The parts of private/functions/Get-ObjectNameParts.ps1: a one, two or three part name, where a part may be bracketed, a
    /// closing bracket inside one is doubled and an empty schema reads database..table. More parts split nothing.
    /// </summary>
    public static class ObjectNameParser
    {
        private static readonly Regex Part = new Regex("(\\[.+?\\])|([^\\.]+)");

        /// <summary>Splits a name into its schema and object parts. A part left out, or a name that does not split, comes back null.</summary>
        /// <param name="objectName">The name as the caller wrote it</param>
        /// <param name="schema">The schema part without its brackets</param>
        /// <param name="name">The object part without its brackets</param>
        public static void Split(string objectName, out string schema, out string name)
        {
            string database;
            Split(objectName, out database, out schema, out name);
        }

        /// <summary>Splits a name into its parts. A part left out, or a name that does not split, comes back null.</summary>
        /// <param name="objectName">The name as the caller wrote it; null reads as an empty name, as the function's string parameter does</param>
        /// <param name="database">The database part without its brackets</param>
        /// <param name="schema">The schema part without its brackets</param>
        /// <param name="name">The object part without its brackets</param>
        public static void Split(string objectName, out string database, out string schema, out string name)
        {
            database = null;
            schema = null;
            name = null;
            string working = objectName ?? "";

            // Stand-ins for what the part expression must not see: a doubled bracket, and the empty schema it could not count.
            string closingBracket = null;
            if (working.Contains("]]"))
            {
                closingBracket = FirstUnusedCharacter(working);
                working = working.Replace("]]", closingBracket);
            }
            string emptySchema = null;
            if (working.Contains(".."))
            {
                emptySchema = FirstUnusedCharacter(working);
                working = working.Replace("..", "." + emptySchema + ".");
            }

            MatchCollection parts = Part.Matches(working);
            if (parts.Count == 1)
            {
                name = working;
            }
            else if (parts.Count == 2 || parts.Count == 3)
            {
                schema = parts[parts.Count - 2].Value;
                name = parts[parts.Count - 1].Value;
                if (parts.Count == 3)
                {
                    database = parts[0].Value;
                }
            }

            database = WithoutBrackets(database, closingBracket);
            schema = WithoutBrackets(schema, closingBracket);
            name = WithoutBrackets(name, closingBracket);
            if (emptySchema != null)
            {
                database = WithoutStandIn(database, emptySchema);
                schema = schema == emptySchema ? null : WithoutStandIn(schema, emptySchema);
                name = WithoutStandIn(name, emptySchema);
            }
        }

        private static string WithoutStandIn(string part, string standIn)
        {
            return part == null ? null : part.Replace(standIn, "");
        }

        private static string WithoutBrackets(string part, string closingBracket)
        {
            if (part == null || part.Length < 2 || part[0] != '[' || part[part.Length - 1] != ']')
            {
                return part;
            }
            string inner = part.Substring(1, part.Length - 2);
            return closingBracket == null ? inner : inner.Replace(closingBracket, "]");
        }

        private static string FirstUnusedCharacter(string text)
        {
            char candidate = '\0';
            while (text.IndexOf(candidate) >= 0)
            {
                candidate++;
            }
            return candidate.ToString();
        }
    }
}
