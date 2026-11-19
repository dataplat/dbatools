#nullable enable

using System;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The catalog calls Publish-DbaSsisProject makes, kept apart from the cmdlet's own lifecycle.
/// </summary>
public sealed partial class PublishDbaSsisProjectCommand : DbaInstanceCmdlet
{
    /// <summary>
    /// The project file goes in as a varbinary parameter. Formatting megabytes of build output as
    /// a hex literal in the statement text would be an injection-policy violation and would not
    /// survive real project sizes anyway.
    /// </summary>
    private long Deploy(Server server)
    {
        using SqlCommand command = new("EXEC [SSISDB].[catalog].[deploy_project] @folder_name = @folderName, @project_name = @projectName, @project_stream = @projectStream, @operation_id = @operationId OUTPUT", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", Folder);
        command.Parameters.AddWithValue("@projectName", Project);
        SqlParameter streamParameter = command.Parameters.Add("@projectStream", System.Data.SqlDbType.VarBinary, -1);
        streamParameter.Value = projectStream;
        SqlParameter operationIdParameter = command.Parameters.Add("@operationId", System.Data.SqlDbType.BigInt);
        operationIdParameter.Direction = System.Data.ParameterDirection.Output;
        // A deployment validates every package it carries, which routinely outlives SqlCommand's
        // 30 second default; the connection's own budget is the one the caller configured.
        command.CommandTimeout = server.ConnectionContext.StatementTimeout;

        SetActiveCommand(command);
        try
        {
            command.ExecuteNonQuery();
        }
        finally
        {
            SetActiveCommand(null);
        }

        return operationIdParameter.Value is DBNull or null
            ? 0
            : Convert.ToInt64(operationIdParameter.Value, CultureInfo.InvariantCulture);
    }

    private long ReadLastOperationId(Server server)
    {
        using SqlCommand command = new("SELECT ISNULL(MAX(operation_id), 0) FROM [SSISDB].[catalog].[operations]", server.ConnectionContext.SqlConnectionObject);
        SetActiveCommand(command);
        try
        {
            object? result = command.ExecuteScalar();
            return result is null or DBNull ? 0 : Convert.ToInt64(result, CultureInfo.InvariantCulture);
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    private int ReadOperationStatus(Server server, long operationId)
    {
        using SqlCommand command = new("SELECT status FROM [SSISDB].[catalog].[operations] WHERE operation_id = @operationId", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@operationId", operationId);
        SetActiveCommand(command);
        try
        {
            object? result = command.ExecuteScalar();
            return result is null or DBNull ? 0 : Convert.ToInt32(result, CultureInfo.InvariantCulture);
        }
        finally
        {
            SetActiveCommand(null);
        }
    }
}
