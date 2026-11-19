using System;
using System.Collections.Generic;
using System.Management.Automation;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Utility
{
    /// <summary>
    /// The C# equivalent of the PowerShell Select-DefaultView helper: shapes cmdlet output by
    /// attaching PSStandardMembers display sets, inserting dbatools type names, adding alias
    /// properties and appending the canonical instance property triple. This is the only
    /// sanctioned way for ported cmdlets to shape their output
    /// (migration/specs/architecture.md section 6).
    /// </summary>
    public static class OutputHelper
    {
        /// <summary>
        /// Attaches a PSStandardMembers member set carrying a DefaultDisplayPropertySet so that
        /// Format-Table shows exactly the curated columns while Select-Object * and property
        /// access still expose everything. Mirrors Select-DefaultView -Property.
        /// </summary>
        /// <param name="obj">The object whose display set is being defined</param>
        /// <param name="names">The property names to display by default, in order</param>
        public static void SetDefaultDisplayPropertySet(PSObject obj, params string[] names)
        {
            if (obj == null)
                throw new ArgumentNullException("obj");
            if (names == null || names.Length == 0)
                throw new ArgumentException("At least one property name is required", "names");

            PSPropertySet displaySet = new PSPropertySet("DefaultDisplayPropertySet", names);
            PSMemberSet standardMembers = new PSMemberSet("PSStandardMembers", new PSMemberInfo[] { displaySet });
            obj.Members.Remove("PSStandardMembers");
            obj.Members.Add(standardMembers);
        }

        /// <summary>
        /// The Select-DefaultView -ExcludeProperty path: the display set becomes every current
        /// property except the excluded names. When the base object is a DataRow, the DataRow
        /// infrastructure properties are excluded automatically.
        /// </summary>
        /// <param name="obj">The object whose display set is being defined</param>
        /// <param name="excluded">Property names to omit from the default display</param>
        public static void SetDefaultDisplayPropertySetExcluding(PSObject obj, string[] excluded)
        {
            if (obj == null)
                throw new ArgumentNullException("obj");

            List<string> excludedNames = new List<string>(excluded ?? new string[0]);
            if (obj.BaseObject is System.Data.DataRow)
            {
                excludedNames.AddRange(new string[] { "Item", "RowError", "RowState", "Table", "ItemArray", "HasErrors" });
            }

            List<PSPropertyInfo> properties = new List<PSPropertyInfo>();
            foreach (PSPropertyInfo property in obj.Properties.Match("*",
                PSMemberTypes.Property | PSMemberTypes.NoteProperty | PSMemberTypes.AliasProperty))
            {
                bool skip = false;
                foreach (string excludedName in excludedNames)
                {
                    if (String.Equals(property.Name, excludedName, StringComparison.OrdinalIgnoreCase))
                    {
                        skip = true;
                        break;
                    }
                }
                if (!skip)
                    properties.Add(property);
            }
            // Get-Member orders by member kind first, then name, before the pinned helper filters.
            properties.Sort((first, second) =>
            {
                int kindOrder = String.Compare(first.MemberType.ToString(), second.MemberType.ToString(), StringComparison.OrdinalIgnoreCase);
                return kindOrder != 0 ? kindOrder : String.Compare(first.Name, second.Name, StringComparison.OrdinalIgnoreCase);
            });
            List<string> names = new List<string>();
            foreach (PSPropertyInfo property in properties)
                names.Add(property.Name);
            SetDefaultDisplayPropertySet(obj, names.ToArray());
        }

        /// <summary>
        /// Inserts "dbatools." + typeName at index 0 of the object's type name list. Used ONLY
        /// where the PS source passed -TypeName to Select-DefaultView: the type string is
        /// load-bearing for ps1xml formatting (BP-601) and adding one where PS had none is a
        /// parity break.
        /// </summary>
        /// <param name="obj">The object receiving the type name</param>
        /// <param name="typeName">The type name without the dbatools. prefix</param>
        public static void InsertTypeName(PSObject obj, string typeName)
        {
            if (obj == null)
                throw new ArgumentNullException("obj");
            if (String.IsNullOrEmpty(typeName))
                throw new ArgumentException("A type name is required", "typeName");

            obj.TypeNames.Insert(0, "dbatools." + typeName);
        }

        /// <summary>
        /// The "Old as New" alias support of Select-DefaultView: adds an alias property so that
        /// referencedName (the existing member) is reachable as aliasName. The caller includes
        /// aliasName in the display set where the PS source did.
        /// </summary>
        /// <param name="obj">The object receiving the alias</param>
        /// <param name="aliasName">The new alias name</param>
        /// <param name="referencedName">The existing member the alias points at</param>
        public static void AddAliasProperty(PSObject obj, string aliasName, string referencedName)
        {
            if (obj == null)
                throw new ArgumentNullException("obj");

            obj.Properties.Add(new PSAliasProperty(aliasName, referencedName));
        }

        /// <summary>
        /// Appends the canonical instance property triple in order: ComputerName,
        /// InstanceName (server.ServiceName), SqlInstance (server.DomainInstanceName).
        /// Property names, order and types match the PS emission exactly (BP-605).
        /// </summary>
        /// <param name="obj">The output object being decorated</param>
        /// <param name="server">The connected SMO server the values come from</param>
        public static void AddInstanceProperties(PSObject obj, Server server)
        {
            if (obj == null)
                throw new ArgumentNullException("obj");
            if (server == null)
                throw new ArgumentNullException("server");

            obj.Properties.Add(new PSNoteProperty("ComputerName", Connection.SmoServerExtensions.GetComputerName(server)));
            // server.ServiceName is a live SMO read, so guard it the same way the sibling reads in
            // this triple already guard theirs (GetComputerName wraps NetName, GetDomainInstanceName
            // wraps InstanceName). A connected server always reports its ServiceName, so this is
            // behavior-identical in production; the guard only affects an unconnected server (used by
            // the offline unit test), yielding a null InstanceName instead of a "Failed to connect" throw.
            string instanceName = null;
            try { instanceName = server.ServiceName; }
            catch { /* an unconnected server cannot report ServiceName - the PS decoration surfaces nothing there either */ }
            obj.Properties.Add(new PSNoteProperty("InstanceName", instanceName));
            obj.Properties.Add(new PSNoteProperty("SqlInstance", Connection.SmoServerExtensions.GetDomainInstanceName(server)));
        }
    }
}
