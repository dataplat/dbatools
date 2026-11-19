#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Microsoft.Data.SqlClient;

namespace Dataplat.Dbatools.Commands;

/// <summary>Clears all SQL Server connection pools on the specified computer to resolve connection issues.</summary>
/// <remarks>
/// This command now clears the SqlClient connection pools of the current PowerShell process only. Earlier versions accepted -ComputerName and -Credential and ran ClearAllPools through PowerShell remoting, which cleared the pools of a short-lived remote process and never affected the caller's pools or any pool on the target. Those parameters were removed because they could not do what the help described.
/// </remarks>
[Cmdlet(VerbsCommon.Clear, "DbaConnectionPool")]
public sealed class ClearDbaConnectionPoolCommand : DbaBaseCmdlet
{
    protected override void ProcessRecord()
    {
        WriteMessage(MessageLevel.Verbose, "Clearing all local pools");
        SqlConnection.ClearAllPools();
    }
}
