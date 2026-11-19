#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The catalog reads and writes Set-DbaSsisFolder makes, kept apart from the cmdlet's own lifecycle.
/// </summary>
public sealed partial class SetDbaSsisFolderCommand : DbaInstanceCmdlet
{
    /// <summary>
    /// Presence is asked of the instance rather than of SMO's Databases collection: enumerating
    /// every database to answer a one-name question drags in whatever state the other databases
    /// are in, and a single-user database is enough to poison the shared connection.
    /// </summary>
    private bool CatalogExists(Server server)
    {
        using SqlCommand presence = new("SELECT DB_ID('SSISDB')", server.ConnectionContext.SqlConnectionObject);
        SetActiveCommand(presence);
        try
        {
            object? result = presence.ExecuteScalar();
            return result != null && result is not DBNull;
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    private bool FolderExists(Server server, string folderName)
    {
        using SqlCommand command = new("SELECT COUNT(*) FROM [SSISDB].[catalog].[folders] WHERE name = @folderName", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", folderName);
        SetActiveCommand(command);
        try
        {
            return Convert.ToInt32(command.ExecuteScalar(), CultureInfo.InvariantCulture) > 0;
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    /// <summary>
    /// Bound-parameter presence, not string emptiness: set_folder_description accepts "" and that
    /// is how a description is cleared, so "not supplied" and "supplied empty" are different asks.
    /// </summary>
    private bool ApplyDescription(FolderTarget target)
    {
        if (!TestBound(nameof(Description)))
        {
            return true;
        }

        string instance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(target.Server);
        if (!ShouldProcess(instance, $"Setting description on SSIS folder {target.Name}"))
        {
            return false;
        }

        try
        {
            using SqlCommand command = new("EXEC [SSISDB].[catalog].[set_folder_description] @folder_name = @folderName, @folder_description = @folderDescription", target.Server.ConnectionContext.SqlConnectionObject);
            command.Parameters.AddWithValue("@folderName", target.Name);
            command.Parameters.AddWithValue("@folderDescription", Description ?? String.Empty);
            SetActiveCommand(command);
            try
            {
                command.ExecuteNonQuery();
            }
            finally
            {
                SetActiveCommand(null);
            }
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            StopFunction($"Failure setting the description on SSIS folder {target.Name} on {instance}", target: target.Name, exception: ex, continueLoop: true);
            return false;
        }

        return true;
    }

    private bool ApplyRename(FolderTarget target)
    {
        string instance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(target.Server);
        if (!ShouldProcess(instance, $"Renaming SSIS folder {target.Name} to {NewName}"))
        {
            return false;
        }

        try
        {
            using SqlCommand command = new("EXEC [SSISDB].[catalog].[rename_folder] @old_name = @oldName, @new_name = @newName", target.Server.ConnectionContext.SqlConnectionObject);
            command.Parameters.AddWithValue("@oldName", target.Name);
            command.Parameters.AddWithValue("@newName", NewName!);
            SetActiveCommand(command);
            try
            {
                command.ExecuteNonQuery();
            }
            finally
            {
                SetActiveCommand(null);
            }
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            StopFunction($"Failure renaming SSIS folder {target.Name} to {NewName} on {instance}", target: target.Name, exception: ex, continueLoop: true);
            return false;
        }

        // Everything after this point looks the folder up under the name it now has.
        target.Name = NewName!;
        return true;
    }
}
