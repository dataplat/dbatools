using System;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Utility;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Utility.Test
{
    /// <summary>
    /// Offline coverage for WildcardNameFilter rule E+ (Fable a8531b76): the literal comparison
    /// still decides every value it matches; a string value containing * or ? also matches as a
    /// case-insensitive pattern unless it is the real name of an object in the unfiltered scope
    /// (then literal only); brackets alone stay literal; an invalid pattern is literal-only; an
    /// exclusion matcher follows the same rule and the caller applies it after inclusion.
    /// </summary>
    [TestClass]
    public class WildcardNameFilterTest
    {
        private static readonly string[] Scope = { "db_*", "db_?", "db_a", "db_b", "db_[a]", "master" };

        private static bool NameFirst(object value, string name)
        {
            return LanguagePrimitives.Equals(name, value, true, CultureInfo.InvariantCulture);
        }

        private static bool ValueFirst(object value, string name)
        {
            PSObject wrapped = value as PSObject;
            return LanguagePrimitives.Equals(wrapped != null ? wrapped.BaseObject : value, name, true, CultureInfo.InvariantCulture);
        }

        private static string[] Selected(object[] values, bool allowPatterns, string[] scope)
        {
            WildcardNameMatcher matcher = WildcardNameFilter.CreateMatcher(values, allowPatterns, NameFirst, scope);
            return Array.FindAll(scope, matcher.Matches);
        }

        private static string[] Included(object[] include, object[] exclude, string[] scope)
        {
            WildcardNameMatcher included = WildcardNameFilter.CreateMatcher(include, true, NameFirst, scope);
            WildcardNameMatcher excluded = WildcardNameFilter.CreateMatcher(exclude, true, NameFirst, scope);
            return Array.FindAll(scope, name => included.Matches(name) && !excluded.Matches(name));
        }

        [TestMethod]
        public void PatternsDisabled_IsLiteralOnly()
        {
            CollectionAssert.AreEqual(new string[0], Selected(new object[] { "mast*" }, false, Scope));
            CollectionAssert.AreEqual(new[] { "master" }, Selected(new object[] { "MASTER" }, false, Scope));
        }

        [TestMethod]
        public void NonCollidingPattern_ExpandsCaseInsensitively()
        {
            CollectionAssert.AreEqual(new[] { "master" }, Selected(new object[] { "MAST*" }, true, Scope));
            CollectionAssert.AreEqual(new[] { "master" }, Selected(new object[] { "maste?" }, true, Scope));
            CollectionAssert.AreEqual(Scope, Selected(new object[] { "*" }, true, Scope));
            CollectionAssert.AreEqual(new[] { "db_*", "db_?", "db_a", "db_b", "db_[a]" }, Selected(new object[] { "db*" }, true, Scope));
        }

        [TestMethod]
        public void RealNameWithStarOrQuestion_SelectsOnlyThatObject()
        {
            CollectionAssert.AreEqual(new[] { "db_*" }, Selected(new object[] { "db_*" }, true, Scope));
            CollectionAssert.AreEqual(new[] { "db_?" }, Selected(new object[] { "DB_?" }, true, Scope));
        }

        [TestMethod]
        public void SamePatternExpandsWhereNoRealNameCollides()
        {
            string[] scope = { "db_a", "db_b", "db_[a]" };
            CollectionAssert.AreEqual(scope, Selected(new object[] { "db_*" }, true, scope));
            CollectionAssert.AreEqual(new[] { "db_a", "db_b" }, Selected(new object[] { "db_?" }, true, scope));
        }

        [TestMethod]
        public void CollisionUsesTheLiteralComparer()
        {
            // Value-first comparison: the PSObject-wrapped value is unwrapped before comparing.
            WildcardNameMatcher matcher = WildcardNameFilter.CreateMatcher(new object[] { PSObject.AsPSObject("db_*") }, true, ValueFirst, Scope);
            CollectionAssert.AreEqual(new[] { "db_*" }, Array.FindAll(Scope, matcher.Matches));
            matcher = WildcardNameFilter.CreateMatcher(new object[] { PSObject.AsPSObject("mast*") }, true, ValueFirst, Scope);
            CollectionAssert.AreEqual(new[] { "master" }, Array.FindAll(Scope, matcher.Matches));
        }

        [TestMethod]
        public void Exclusion_FollowsTheSameRuleAndWins()
        {
            CollectionAssert.AreEqual(new[] { "db_*", "db_a", "db_b", "db_[a]" }, Included(new object[] { "db*" }, new object[] { "db_?" }, Scope));
            CollectionAssert.AreEqual(new[] { "db_?", "db_[a]" }, Included(new object[] { "db_?", "db_[a]" }, new object[] { "db_x", "db_*" }, Scope));
            CollectionAssert.AreEqual(new string[0], Included(new object[] { "db_a" }, new object[] { "DB_*" }, new[] { "db_a", "db_b" }));
            CollectionAssert.AreEqual(new[] { "master" }, Included(new object[] { "*" }, new object[] { "db*" }, Scope));
        }

        [TestMethod]
        public void BracketsAloneStayLiteral()
        {
            Assert.IsFalse(WildcardNameFilter.IsPatternCandidate("[test]"));
            CollectionAssert.AreEqual(new string[0], Selected(new object[] { "[test]" }, true, new[] { "t", "e", "s" }));
            CollectionAssert.AreEqual(new[] { "db_[a]" }, Selected(new object[] { "db_[a]" }, true, Scope));
        }

        [TestMethod]
        public void BracketsInsideAPatternKeepClassSemantics()
        {
            CollectionAssert.AreEqual(new[] { "db_b" }, Selected(new object[] { "db_[b]*" }, true, Scope));
        }

        [TestMethod]
        public void InvalidPattern_IsLiteralOnlyAndDoesNotThrow()
        {
            Assert.IsFalse(WildcardNameFilter.PatternMatches("db[*", "db[x"));
            CollectionAssert.AreEqual(new string[0], Selected(new object[] { "db[*" }, true, new[] { "db[x", "db" }));
            CollectionAssert.AreEqual(new[] { "db[*" }, Selected(new object[] { "db[*" }, true, new[] { "db[*", "db[x" }));
        }

        [TestMethod]
        public void NonStringValuesAreNeverPatterns()
        {
            Assert.IsFalse(WildcardNameFilter.IsPatternCandidate(1));
            string[] scope = { "01", "02" };
            WildcardNameMatcher matcher = WildcardNameFilter.CreateMatcher(new object[] { 1 }, true, ValueFirst, scope);
            CollectionAssert.AreEqual(new[] { "01" }, Array.FindAll(scope, matcher.Matches));
        }

        [TestMethod]
        public void NullValuesMatchNothing()
        {
            Assert.IsFalse(WildcardNameFilter.CreateMatcher(null, true, NameFirst, Scope).Matches("master"));
            Assert.IsFalse(WildcardNameFilter.PatternMatches(null, "master"));
            Assert.IsFalse(WildcardNameFilter.PatternMatches("m*", null));
        }

        [TestMethod]
        public void ScopeIsReadOnlyWhenAPatternValueNeedsIt()
        {
            // Literal-only filters never enumerate the scope; a pattern value without one is refused.
            Assert.IsTrue(WildcardNameFilter.CreateMatcher(new object[] { "master" }, true, NameFirst, null).Matches("master"));
            Assert.IsFalse(WildcardNameFilter.CreateMatcher(new object[] { "m*" }, false, NameFirst, null).Matches("master"));
        }

        [TestMethod]
        [ExpectedException(typeof(ArgumentNullException))]
        public void PatternValueRequiresTheScope()
        {
            WildcardNameFilter.CreateMatcher(new object[] { "m*" }, true, NameFirst, null);
        }

        [TestMethod]
        [ExpectedException(typeof(ArgumentNullException))]
        public void RequiresALiteralComparison()
        {
            WildcardNameFilter.CreateMatcher(new object[] { "m*" }, true, null, Scope);
        }
    }
}
