#nullable enable

using System;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>Executes a fixed statistics-reset statement and shapes the source Query outcome.</summary>
internal static class NativeStatisticsReset
{
    internal static PSObject Execute(Server server, string statement)
    {
        object status;
        try
        {
            // Current pinned reset commands discard Query's result before emitting the outcome.
            server.ConnectionContext.ExecuteNonQuery(statement);
            status = "Success";
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            // Server.Query joins its inner exception messages, then the script-method binder
            // wraps the string throw. Keep an exception object in Status, not just its text.
            StringBuilder message = new StringBuilder();
            for (Exception? current = ex; current is not null; current = current.InnerException)
                message.Append(current.Message);
            string text = message.ToString();
            status = new MethodInvocationException(
                string.Format("Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", text), new RuntimeException(text));
        }

        PSObject result = new PSObject();
        OutputHelper.AddInstanceProperties(result, server);
        result.Properties.Add(new PSNoteProperty("Status", status));
        return result;
    }
}
