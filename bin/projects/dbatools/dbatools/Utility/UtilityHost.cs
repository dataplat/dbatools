using System;
using System.Collections.Generic;

namespace Sqlcollaborative.Dbatools.Utility
{
    /// <summary>
    /// Provides static resources to utility-namespaced stuff
    /// </summary>
    public static class UtilityHost
    {
        /// <summary>
        /// Restores all DateTime objects to their default display behavior
        /// </summary>
        public static bool DisableCustomDateTime = false;

        /// <summary>
        /// Restores all timespan objects to their default display behavior.
        /// </summary>
        public static bool DisableCustomTimeSpan = false;

        /// <summary>
        /// Formating string for date-style datetime objects.
        /// </summary>
        public static string FormatDate = "dd MMM yyyy";

        /// <summary>
        /// Formating string for datetime-style datetime objects
        /// </summary>
        public static string FormatDateTime = "yyyy-MM-dd HH:mm:ss.fff";

        /// <summary>
        /// Formating string for time-style datetime objects
        /// </summary>
        public static string FormatTime = "HH:mm:ss";

        /// <summary>
        /// The number of digits a size object shows by default
        /// </summary>
        public static int SizeDigits = 2;

        /// <summary>
        /// The way size objects are usually displayed
        /// </summary>
        public static SizeStyle SizeStyle = SizeStyle.Dynamic;

        /// <summary>
        /// Implement's VB's Like operator logic.
        /// </summary>
        /// <param name="CaseSensitive">Whether the comparison is case sensitive</param>
        /// <param name="Pattern">The pattern the string is compared with</param>
        /// <param name="String">The string that is being compared with a pattern</param>
        public static bool IsLike(string String, string Pattern, bool CaseSensitive = false)
        {
            if (!CaseSensitive)
            {
                String = String.ToLower();
                Pattern = Pattern.ToLower();
            }

            // Characters matched so far
            int matched = 0;

            // Loop through pattern string
            for (int i = 0; i < Pattern.Length;)
            {
                // Check for end of string
                if (matched > String.Length)
                    return false;

                // Get next pattern character
                char c = Pattern[i++];
                if (c == '[') // Character list
                {
                    // Test for exclude character
                    bool exclude = (i < Pattern.Length && Pattern[i] == '!');
                    if (exclude)
                        i++;
                    // Build character list
                    int j = Pattern.IndexOf(']', i);
                    if (j < 0)
                        j = String.Length;
                    HashSet<char> charList = CharListToSet(Pattern.Substring(i, j - i));
                    i = j + 1;

                    if (charList.Contains(String[matched]) == exclude)
                        return false;
                    matched++;
                }
                else if (c == '?') // Any single character
                {
                    matched++;
                }
                else if (c == '#') // Any single digit
                {
                    if (!Char.IsDigit(String[matched]))
                        return false;
                    matched++;
                }
                else if (c == '*') // Zero or more characters
                {
                    if (i < Pattern.Length)
                    {
                        // Matches all characters until
                        // next character in pattern
                        char next = Pattern[i];
                        int j = String.IndexOf(next, matched);
                        if (j < 0)
                            return false;
                        matched = j;
                    }
                    else
                    {
                        // Matches all remaining characters
                        matched = String.Length;
                        break;
                    }
                }
                else // Exact character
                {
                    if (matched >= String.Length || c != String[matched])
                        return false;
                    matched++;
                }
            }
            // Return true if all characters matched
            return (matched == String.Length);
        }

        /// <summary>
        /// Converts a string of characters to a HashSet of characters. If the string
        /// contains character ranges, such as A-Z, all characters in the range are
        /// also added to the returned set of characters.
        /// </summary>
        /// <param name="charList">Character list string</param>
        private static HashSet<char> CharListToSet(string charList)
        {
            HashSet<char> set = new HashSet<char>();

            for (int i = 0; i < charList.Length; i++)
            {
                if ((i + 1) < charList.Length && charList[i + 1] == '-')
                {
                    // Character range
                    char startChar = charList[i++];
                    i++; // Hyphen
                    char endChar = (char)0;
                    if (i < charList.Length)
                        endChar = charList[i++];
                    for (int j = startChar; j <= endChar; j++)
                        set.Add((char)j);
                }
                else set.Add(charList[i]);
            }
            return set;
        }
    }
}