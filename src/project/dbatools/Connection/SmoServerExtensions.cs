using System;
using System.Collections.Generic;
using Dataplat.Dbatools.Exceptions;
using System.Management.Automation;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Connection
{
    /// <summary>
    /// Readers for the ETS note properties Connect-DbaInstance (and ConnectionService) attach
    /// to SMO Server objects, with the same fallbacks the PS code uses. Cmdlet code never
    /// re-derives these ad hoc (migration/specs/architecture.md section 4.4).
    /// </summary>
    public static class SmoServerExtensions
    {
        /// <summary>
        /// The ComputerName note property when present, else NetName, else the instance name
        /// SMO reports - the same resolution order the PS decoration uses.
        /// </summary>
        /// <param name="server">The connected server</param>
        /// <returns>The computer name for output objects</returns>
        public static string GetComputerName(Server server)
        {
            if (server == null)
                return null;
            object noteValue = GetNoteProperty(server, "ComputerName");
            if (noteValue != null)
                return noteValue.ToString();
            string netName = null;
            try { netName = server.NetName; }
            catch { /* NetName can throw on Azure targets; fall through to the SMO name */ }
            if (!String.IsNullOrEmpty(netName))
                return netName;
            return server.Name;
        }

        /// <summary>
        /// The server's DomainInstanceName (COMPUTER\INSTANCE). Not a compiled CLR property on
        /// SMO's Server - it surfaces only through the PowerShell adapter - so it is read via
        /// the PSObject view, the same route DbaInstanceParameter's SMO constructor has always
        /// used, with a NetName-composed fallback.
        /// </summary>
        /// <param name="server">The connected server</param>
        /// <returns>The domain instance name for output objects</returns>
        public static string GetDomainInstanceName(Server server)
        {
            if (server == null)
                return null;
            object adapted = GetNoteProperty(server, "DomainInstanceName");
            if (adapted != null)
                return adapted.ToString();

            string computerName = GetComputerName(server);
            string instanceName = null;
            try { instanceName = server.InstanceName; }
            catch { /* metadata may be unavailable before a full connect */ }
            if (String.IsNullOrEmpty(instanceName))
                return computerName;
            return String.Format("{0}\\{1}", computerName, instanceName);
        }

        /// <summary>The IsAzure note property when present, else false.</summary>
        /// <param name="server">The connected server</param>
        /// <returns>Whether the target is Azure SQL Database</returns>
        public static bool GetIsAzure(Server server)
        {
            object noteValue = GetNoteProperty(server, "IsAzure");
            if (noteValue is bool)
                return (bool)noteValue;
            return false;
        }

        /// <summary>
        /// Reads any PSObject-visible property (ETS note properties from PS decorations like
        /// Get-DbaDatabase's ComputerName, or adapter-only SMO properties) off any SMO object.
        /// Returns null when absent - callers supply their own SMO fallback.
        /// </summary>
        /// <param name="smoObject">The object to read from</param>
        /// <param name="name">The property name</param>
        /// <returns>The value, or null when the property is missing or unreadable</returns>
        public static object GetPSProperty(object smoObject, string name)
        {
            if (smoObject == null)
                return null;
            PSObject wrapped = PSObject.AsPSObject(smoObject);
            PSPropertyInfo property = wrapped.Properties[name];
            if (property == null)
                return null;
            EnsureNativeProperty(wrapped, property);
            try { return property.Value; }
            catch { return null; }
        }

        // Constructors retain their existing missing-member and getter exception wrapping.
        internal static object ReadPSProperty(PSObject wrapped, string name)
        {
            PSPropertyInfo property = wrapped.Properties[name];
            EnsureNativeProperty(wrapped, property);
            return property.Value;
        }

        private static void EnsureNativeProperty(PSObject wrapped, PSPropertyInfo property)
        {
            if (property == null)
                return;
            string requestedName = property.Name;
            var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            while (property != null && visited.Add(property.Name))
            {
                if (property.MemberType == PSMemberTypes.ScriptProperty)
                    throw new NativeMetadataException(String.Format(
                        "Native metadata property {0} resolves to script property {1}. Supply a note or native CLR property instead.",
                        requestedName, property.Name));
                PSAliasProperty alias = property as PSAliasProperty;
                if (alias == null)
                    return;
                property = wrapped.Properties[alias.ReferencedMemberName];
            }
            // Missing or cyclic aliases keep the engine's original getter failure behavior.
        }

        private static object GetNoteProperty(Server server, string name)
        {
            return GetPSProperty(server, name);
        }
    }
}
