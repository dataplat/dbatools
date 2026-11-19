using System;
using System.Collections.Generic;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using DbaMessageLevel = Dataplat.Dbatools.Message.MessageLevel;

namespace Dataplat.Dbatools.Connection.Test
{
    /// <summary>
    /// TB-001 coverage for ConnectionService.RegisterConnection, the C# parity port of
    /// private/functions/Add-ConnectionHashValue.ps1: pooled values replace the
    /// ActiveConnections entry, non-pooled Server values append to it, and the debug
    /// message fires before any work exactly like the PS original. The PS helper's live
    /// call sites (retired Connect-DbaInstance.ps1:1246 SqlConnection leg, :1367 Server
    /// leg) drive the scenarios; unreachable-input divergences (null/empty key or value
    /// no-op instead of a binding error) are pinned as the port's documented behavior.
    /// ActiveConnections is process-wide shared state, so the class opts out of
    /// parallel execution and every test owns only its prefixed or sentinel keys.
    /// </summary>
    [TestClass]
    [DoNotParallelize]
    public class ConnectionServiceRegisterConnectionTest
    {
        private const string KeyPrefix = "dbatools-tests-registerconnection-";

        private static string UniqueKey()
        {
            return KeyPrefix + Guid.NewGuid().ToString("N");
        }

        [TestCleanup]
        public void RemoveTestEntries()
        {
            lock (ConnectionHost.ActiveConnections)
            {
                List<string> stale = new List<string>();
                foreach (string key in ConnectionHost.ActiveConnections.Keys)
                {
                    if (key.StartsWith(KeyPrefix, StringComparison.OrdinalIgnoreCase))
                        stale.Add(key);
                }
                foreach (string key in stale)
                    ConnectionHost.ActiveConnections.Remove(key);
            }
        }

        [TestMethod]
        public void RegisterConnection_PooledSqlConnectionReplacesEntry()
        {
            // Mirrors retired Connect-DbaInstance.ps1:1246 - the -SqlConnectionOnly leg
            // registers the raw SqlConnection, which member-misses both NonPooledConnection
            // probes in PS and must land in the pooled/replace branch.
            string key = UniqueKey();
            SqlConnection first = new SqlConnection();
            SqlConnection second = new SqlConnection();

            ConnectionService.RegisterConnection(key, first, null);
            ConnectionService.RegisterConnection(key, second, null);

            List<object> entries = ConnectionHost.ActiveConnections[key];
            Assert.AreEqual(1, entries.Count);
            Assert.AreSame(second, entries[0]);
        }

        [TestMethod]
        public void RegisterConnection_NonPooledServerAppendsToEntry()
        {
            string key = UniqueKey();
            Server first = new Server("dbatools-tests-nonpooled");
            first.ConnectionContext.NonPooledConnection = true;
            Server second = new Server("dbatools-tests-nonpooled");
            second.ConnectionContext.NonPooledConnection = true;

            ConnectionService.RegisterConnection(key, first, null);
            ConnectionService.RegisterConnection(key, second, null);

            List<object> entries = ConnectionHost.ActiveConnections[key];
            Assert.AreEqual(2, entries.Count);
            Assert.AreSame(first, entries[0]);
            Assert.AreSame(second, entries[1]);
        }

        [TestMethod]
        public void RegisterConnection_NonPooledServerAppendsAfterPooledValue()
        {
            // PS parity: the non-pooled leg only re-creates the list when the entry is
            // missing/falsy, so an existing pooled entry is APPENDED to, never replaced.
            string key = UniqueKey();
            SqlConnection pooled = new SqlConnection();
            Server nonPooled = new Server("dbatools-tests-pooled-then-nonpooled");
            nonPooled.ConnectionContext.NonPooledConnection = true;

            ConnectionService.RegisterConnection(key, pooled, null);
            ConnectionService.RegisterConnection(key, nonPooled, null);

            List<object> entries = ConnectionHost.ActiveConnections[key];
            Assert.AreEqual(2, entries.Count);
            Assert.AreSame(pooled, entries[0]);
            Assert.AreSame(nonPooled, entries[1]);
        }

        [TestMethod]
        public void RegisterConnection_PooledServerReplacesNonPooledBacklog()
        {
            string key = UniqueKey();
            Server nonPooled = new Server("dbatools-tests-mixed");
            nonPooled.ConnectionContext.NonPooledConnection = true;
            Server pooled = new Server("dbatools-tests-mixed");

            ConnectionService.RegisterConnection(key, nonPooled, null);
            ConnectionService.RegisterConnection(key, nonPooled, null);
            ConnectionService.RegisterConnection(key, pooled, null);

            List<object> entries = ConnectionHost.ActiveConnections[key];
            Assert.AreEqual(1, entries.Count);
            Assert.AreSame(pooled, entries[0]);
        }

        [TestMethod]
        public void RegisterConnection_NullEntryIsRecreatedOnAppend()
        {
            // PS parity: -not $connections["$Key"] treats a stored $null exactly like a
            // missing key, so the non-pooled leg re-creates the list instead of throwing.
            string key = UniqueKey();
            lock (ConnectionHost.ActiveConnections)
            {
                ConnectionHost.ActiveConnections[key] = null;
            }
            Server nonPooled = new Server("dbatools-tests-nullentry");
            nonPooled.ConnectionContext.NonPooledConnection = true;

            ConnectionService.RegisterConnection(key, nonPooled, null);

            List<object> entries = ConnectionHost.ActiveConnections[key];
            Assert.AreEqual(1, entries.Count);
            Assert.AreSame(nonPooled, entries[0]);
        }

        [TestMethod]
        public void RegisterConnection_KeyComparerIsOrdinalIgnoreCase()
        {
            // The PS helper and the port share one static store; connection strings must
            // collide case-insensitively AND culture-independently (OrdinalIgnoreCase),
            // not merely under the current culture's casing rules.
            Assert.AreSame(StringComparer.OrdinalIgnoreCase, ConnectionHost.ActiveConnections.Comparer);

            string key = UniqueKey();
            ConnectionService.RegisterConnection(key.ToLowerInvariant(), new SqlConnection(), null);
            ConnectionService.RegisterConnection(key.ToUpperInvariant(), new SqlConnection(), null);

            int matches = 0;
            lock (ConnectionHost.ActiveConnections)
            {
                foreach (string existing in ConnectionHost.ActiveConnections.Keys)
                {
                    if (String.Equals(existing, key, StringComparison.OrdinalIgnoreCase))
                        matches++;
                }
            }
            Assert.AreEqual(1, matches);
            Assert.AreEqual(1, ConnectionHost.ActiveConnections[key].Count);
        }

        [TestMethod]
        public void RegisterConnection_EmitsDebugMessageBeforeEveryGuard()
        {
            // The PS helper writes "Adding to connection hash" before touching the cache;
            // the port keeps that order, so every guarded no-op input (null key, empty
            // key, null value) still emits exactly one debug message per call — and for
            // the valid call the callback itself observes the key is NOT registered yet,
            // proving message-before-mutation rather than just message-happened.
            string validKey = UniqueKey();
            List<string> seen = new List<string>();
            Action<DbaMessageLevel, string> countingSink = delegate (DbaMessageLevel level, string message)
            {
                Assert.AreEqual(DbaMessageLevel.Debug, level);
                seen.Add(message);
            };
            Action<DbaMessageLevel, string> orderingSink = delegate (DbaMessageLevel level, string message)
            {
                lock (ConnectionHost.ActiveConnections)
                {
                    Assert.IsFalse(ConnectionHost.ActiveConnections.ContainsKey(validKey));
                }
                countingSink(level, message);
            };

            ConnectionService.RegisterConnection(validKey, new SqlConnection(), orderingSink);
            Assert.IsTrue(ConnectionHost.ActiveConnections.ContainsKey(validKey));
            Assert.AreEqual(1, seen.Count);

            ConnectionService.RegisterConnection(null, new SqlConnection(), countingSink);
            Assert.AreEqual(2, seen.Count);
            ConnectionService.RegisterConnection(String.Empty, new SqlConnection(), countingSink);
            Assert.AreEqual(3, seen.Count);
            string nullValueKey = UniqueKey();
            ConnectionService.RegisterConnection(nullValueKey, null, countingSink);
            Assert.AreEqual(4, seen.Count);
            Assert.IsFalse(ConnectionHost.ActiveConnections.ContainsKey(nullValueKey));

            foreach (string message in seen)
                Assert.AreEqual("Adding to connection hash", message);
        }

        [TestMethod]
        public void RegisterConnection_GuardedInputsLeaveExistingStateUntouched()
        {
            // Sentinels pin that the guards are true no-ops: an existing empty-key entry
            // and an existing prefixed entry keep their exact list references and
            // contents through null-key, empty-key and null-value calls. The process-wide
            // empty-key slot is not ours: snapshot whatever was there and restore it.
            string key = UniqueKey();
            object sentinelValue = new object();
            List<object> emptyKeySentinel = new List<object>();
            emptyKeySentinel.Add(sentinelValue);
            List<object> keyedSentinel = new List<object>();
            keyedSentinel.Add(sentinelValue);
            bool hadEmptyKey;
            List<object> priorEmptyKey;
            int before;
            lock (ConnectionHost.ActiveConnections)
            {
                hadEmptyKey = ConnectionHost.ActiveConnections.TryGetValue(String.Empty, out priorEmptyKey);
                ConnectionHost.ActiveConnections[String.Empty] = emptyKeySentinel;
                ConnectionHost.ActiveConnections[key] = keyedSentinel;
                before = ConnectionHost.ActiveConnections.Count;
            }

            try
            {
                ConnectionService.RegisterConnection(null, new SqlConnection(), null);
                ConnectionService.RegisterConnection(String.Empty, new SqlConnection(), null);
                ConnectionService.RegisterConnection(key, null, null);

                lock (ConnectionHost.ActiveConnections)
                {
                    Assert.AreEqual(before, ConnectionHost.ActiveConnections.Count);
                    Assert.AreSame(emptyKeySentinel, ConnectionHost.ActiveConnections[String.Empty]);
                    Assert.AreEqual(1, emptyKeySentinel.Count);
                    Assert.AreSame(sentinelValue, emptyKeySentinel[0]);
                    Assert.AreSame(keyedSentinel, ConnectionHost.ActiveConnections[key]);
                    Assert.AreEqual(1, keyedSentinel.Count);
                    Assert.AreSame(sentinelValue, keyedSentinel[0]);
                }
            }
            finally
            {
                lock (ConnectionHost.ActiveConnections)
                {
                    if (hadEmptyKey)
                        ConnectionHost.ActiveConnections[String.Empty] = priorEmptyKey;
                    else
                        ConnectionHost.ActiveConnections.Remove(String.Empty);
                }
            }
        }
    }
}
