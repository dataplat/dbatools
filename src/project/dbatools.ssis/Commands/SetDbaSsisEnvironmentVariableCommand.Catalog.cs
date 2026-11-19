#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Runtime.InteropServices;
using System.Text;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The catalog reads and writes Set-DbaSsisEnvironmentVariable makes, kept apart from the cmdlet's
/// own lifecycle.
/// </summary>
public sealed partial class SetDbaSsisEnvironmentVariableCommand : DbaInstanceCmdlet
{
    /// <summary>The catalog error raised when a type change cannot convert the value already stored.</summary>
    private const int ConversionRefusedError = 27210;

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

    /// <summary>
    /// The variables a selection resolves to, with the stored sensitivity and type read at the same
    /// time - both decide whether the change is legal at all, and asking for them separately would
    /// mean a round trip per variable. The read is against internal.environment_variables because
    /// that is where the sensitivity flag lives with the rest of the row.
    /// </summary>
    private List<VariableTarget> ResolveVariables(Server server, string[]? folderNames, string[]? environmentNames, string[]? variableNames)
    {
        List<KeyValuePair<string, object>> queryParameters = new();
        StringBuilder sql = new();
        sql.Append("SELECT folders.name AS folder_name, environments.name AS environment_name, variables.name AS variable_name, variables.sensitive, variables.type");
        sql.Append(" FROM [SSISDB].[internal].[environment_variables] variables");
        sql.Append(" JOIN [SSISDB].[catalog].[environments] environments ON environments.environment_id = variables.environment_id");
        sql.Append(" JOIN [SSISDB].[catalog].[folders] folders ON folders.folder_id = environments.folder_id");
        bool hasFilter = AppendNameFilter(sql, queryParameters, "folders.name", folderNames, "folder", true);
        hasFilter = AppendNameFilter(sql, queryParameters, "environments.name", environmentNames, "environment", !hasFilter) || hasFilter;
        AppendNameFilter(sql, queryParameters, "variables.name", variableNames, "variable", !hasFilter);
        sql.Append(" ORDER BY folders.name, environments.name, variables.name");

        List<VariableTarget> resolved = new();
        using SqlCommand command = new(sql.ToString(), server.ConnectionContext.SqlConnectionObject);
        foreach (KeyValuePair<string, object> parameter in queryParameters)
        {
            command.Parameters.AddWithValue(parameter.Key, parameter.Value);
        }

        SetActiveCommand(command);
        try
        {
            using SqlDataReader reader = command.ExecuteReader();
            while (reader.Read())
            {
                resolved.Add(new VariableTarget
                {
                    Server = server,
                    FolderName = Convert.ToString(reader["folder_name"], CultureInfo.InvariantCulture) ?? String.Empty,
                    EnvironmentName = Convert.ToString(reader["environment_name"], CultureInfo.InvariantCulture) ?? String.Empty,
                    Name = Convert.ToString(reader["variable_name"], CultureInfo.InvariantCulture) ?? String.Empty,
                    IsSensitive = reader["sensitive"] is not DBNull && Convert.ToBoolean(reader["sensitive"], CultureInfo.InvariantCulture),
                    StoredDataType = Convert.ToString(reader["type"], CultureInfo.InvariantCulture) ?? String.Empty
                });
            }
        }
        finally
        {
            SetActiveCommand(null);
        }

        return resolved;
    }

    private static bool AppendNameFilter(StringBuilder sql, List<KeyValuePair<string, object>> queryParameters, string column, string[]? names, string parameterPrefix, bool first)
    {
        if (!FilterHelper.IsActive(names))
        {
            return false;
        }

        sql.Append(first ? " WHERE " : " AND ");
        sql.Append(column).Append(" IN (");
        int ordinal = 0;
        foreach (string name in names!)
        {
            ordinal++;
            string parameterName = parameterPrefix + ordinal.ToString(CultureInfo.InvariantCulture);
            if (ordinal > 1)
            {
                sql.Append(", ");
            }
            sql.Append('@').Append(parameterName);
            queryParameters.Add(new KeyValuePair<string, object>(parameterName, name));
        }
        sql.Append(')');
        return true;
    }

    private bool ApplyProtection(VariableTarget target)
    {
        if (!TestBound(nameof(Sensitive)))
        {
            return true;
        }

        string instance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(target.Server);
        if (!ShouldProcess(instance, $"Setting sensitivity on SSIS environment variable {target.Name} in environment {target.EnvironmentName} of folder {target.FolderName}"))
        {
            return false;
        }

        using SqlCommand command = new("EXEC [SSISDB].[catalog].[set_environment_variable_protection] @folder_name = @folderName, @environment_name = @environmentName, @variable_name = @variableName, @sensitive = @sensitive", target.Server.ConnectionContext.SqlConnectionObject);
        AddAddressParameters(command, target);
        command.Parameters.AddWithValue("@sensitive", Sensitive.ToBool());

        if (!Execute(command, $"Failure setting the sensitivity of SSIS environment variable {target.Name} in {target.FolderName}\\{target.EnvironmentName} on {instance}", target.Name))
        {
            return false;
        }

        // The value column moves between plaintext and ciphertext with this call, so everything
        // after it has to know which one it is looking at.
        target.IsSensitive = Sensitive.ToBool();
        return true;
    }

    /// <summary>
    /// The catalog's TYPE branch re-reads the stored value and converts it - decrypting and
    /// re-encrypting first when the variable is sensitive. Measured on SQL 2019 SSISDB schema 6,
    /// internal.convert_value coerces rather than refusing: "not a number" to Int32 lands 0 and
    /// "abc" to DateTime lands the current date, both without an error. So the type change is
    /// destructive to the stored value, which is what the warning below is for. Error 27210 is
    /// still raised when the conversion yields NULL, and its message names both types because a
    /// bare failure would leave the caller with no way to tell which pair collided.
    /// </summary>
    private bool ApplyDataType(VariableTarget target)
    {
        if (!TestBound(nameof(DataType)))
        {
            return true;
        }

        if (!TestBound(nameof(Value)) && !TestBound(nameof(SecureValue)))
        {
            WriteMessage(MessageLevel.Warning, $"Changing SSIS environment variable {target.Name} in {target.FolderName}\\{target.EnvironmentName} from {target.StoredDataType} to {DataType} converts the value it already holds, and the catalog's conversion silently substitutes a default rather than failing on data the new type cannot represent. Pass -Value in the same call to set the value you want");
        }

        string instance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(target.Server);
        if (!ShouldProcess(instance, $"Setting TYPE on SSIS environment variable {target.Name} in environment {target.EnvironmentName} of folder {target.FolderName}"))
        {
            return false;
        }

        using SqlCommand command = BuildPropertyCommand(target, "TYPE", DataType!);
        try
        {
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
        catch (SqlException ex) when (ex.Number == ConversionRefusedError)
        {
            StopFunction($"Cannot change SSIS environment variable {target.Name} in {target.FolderName}\\{target.EnvironmentName} from {target.StoredDataType} to {DataType}: the value it already holds does not convert. Give it a value the new type can hold first, or remove and recreate it", target: target.Name, exception: ex, continueLoop: true);
            return false;
        }
        catch (Exception ex)
        {
            StopFunction($"Failure setting the type of SSIS environment variable {target.Name} in {target.FolderName}\\{target.EnvironmentName} on {instance}", target: target.Name, exception: ex, continueLoop: true);
            return false;
        }

        target.StoredDataType = DataType!;
        return true;
    }

    /// <summary>
    /// A sensitive value is copied out of the SecureString into a char array bound straight to the
    /// parameter, so it never becomes a managed string that would sit in memory until a collection
    /// nobody controls. Both the unmanaged buffer and the array are cleared in the finally.
    /// </summary>
    private bool ApplyValue(VariableTarget target)
    {
        if (!TestBound(nameof(Value), nameof(SecureValue)))
        {
            return true;
        }

        string instance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(target.Server);
        if (!ShouldProcess(instance, $"Setting value on SSIS environment variable {target.Name} in environment {target.EnvironmentName} of folder {target.FolderName}"))
        {
            return false;
        }

        using SqlCommand command = new("EXEC [SSISDB].[catalog].[set_environment_variable_value] @folder_name = @folderName, @environment_name = @environmentName, @variable_name = @variableName, @value = @value", target.Server.ConnectionContext.SqlConnectionObject);
        AddAddressParameters(command, target);

        char[]? secureCharacters = null;
        IntPtr secureBuffer = IntPtr.Zero;
        try
        {
            if (SecureValue != null)
            {
                secureBuffer = Marshal.SecureStringToGlobalAllocUnicode(SecureValue);
                secureCharacters = new char[SecureValue.Length];
                Marshal.Copy(secureBuffer, secureCharacters, 0, secureCharacters.Length);
                Marshal.ZeroFreeGlobalAllocUnicode(secureBuffer);
                secureBuffer = IntPtr.Zero;

                SqlParameter valueParameter = command.Parameters.Add("@value", System.Data.SqlDbType.NVarChar, secureCharacters.Length);
                valueParameter.Value = secureCharacters;
            }
            else
            {
                // PowerShell hands an argument bound to an [object] parameter over as a PSObject
                // often enough that unwrapping it is not optional; sql_variant takes the CLR type
                // underneath, and a PSObject binds as nothing at all.
                object? bare = Value is PSObject wrapper ? wrapper.BaseObject : Value;
                command.Parameters.AddWithValue("@value", bare ?? (object)DBNull.Value);
            }

            return Execute(command, $"Failure setting the value of SSIS environment variable {target.Name} in {target.FolderName}\\{target.EnvironmentName} on {instance}", target.Name);
        }
        finally
        {
            if (secureBuffer != IntPtr.Zero)
            {
                Marshal.ZeroFreeGlobalAllocUnicode(secureBuffer);
            }
            if (secureCharacters != null)
            {
                Array.Clear(secureCharacters, 0, secureCharacters.Length);
            }
        }
    }

    /// <summary>
    /// Bound-parameter presence, not string emptiness: the catalog accepts "" and that is how a
    /// description is cleared, so "not supplied" and "supplied empty" are different asks.
    /// </summary>
    private bool ApplyDescription(VariableTarget target)
    {
        if (!TestBound(nameof(Description)))
        {
            return true;
        }

        string instance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(target.Server);
        if (!ShouldProcess(instance, $"Setting DESCRIPTION on SSIS environment variable {target.Name} in environment {target.EnvironmentName} of folder {target.FolderName}"))
        {
            return false;
        }

        using SqlCommand command = BuildPropertyCommand(target, "DESCRIPTION", Description ?? String.Empty);
        return Execute(command, $"Failure setting the description of SSIS environment variable {target.Name} in {target.FolderName}\\{target.EnvironmentName} on {instance}", target.Name);
    }

    private bool ApplyRename(VariableTarget target)
    {
        if (!TestBound(nameof(NewName)))
        {
            return true;
        }

        string instance = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(target.Server);
        if (!ShouldProcess(instance, $"Renaming SSIS environment variable {target.Name} to {NewName}"))
        {
            return false;
        }

        using SqlCommand command = BuildPropertyCommand(target, "NAME", NewName!);
        if (!Execute(command, $"Failure renaming SSIS environment variable {target.Name} in {target.FolderName}\\{target.EnvironmentName} to {NewName} on {instance}", target.Name))
        {
            return false;
        }

        // Everything after this point looks the variable up under the name it now has.
        target.Name = NewName!;
        return true;
    }

    private SqlCommand BuildPropertyCommand(VariableTarget target, string propertyName, string propertyValue)
    {
        SqlCommand command = new("EXEC [SSISDB].[catalog].[set_environment_variable_property] @folder_name = @folderName, @environment_name = @environmentName, @variable_name = @variableName, @property_name = @propertyName, @property_value = @propertyValue", target.Server.ConnectionContext.SqlConnectionObject);
        AddAddressParameters(command, target);
        command.Parameters.AddWithValue("@propertyName", propertyName);
        command.Parameters.AddWithValue("@propertyValue", propertyValue);
        return command;
    }

    private static void AddAddressParameters(SqlCommand command, VariableTarget target)
    {
        command.Parameters.AddWithValue("@folderName", target.FolderName);
        command.Parameters.AddWithValue("@environmentName", target.EnvironmentName);
        command.Parameters.AddWithValue("@variableName", target.Name);
    }

    private bool Execute(SqlCommand command, string failureMessage, string target)
    {
        try
        {
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
            StopFunction(failureMessage, target: target, exception: ex, continueLoop: true);
            return false;
        }

        return true;
    }

    /// <summary>
    /// Re-read rather than re-report, in the shape New-DbaSsisEnvironmentVariable emits so the two
    /// compose. Value comes from the stored column, which the catalog leaves null for a sensitive
    /// variable - so a secret is not echoed back without that having to be a special case here; the
    /// ciphertext lives in a separate column that is deliberately not read.
    /// </summary>
    private void EmitVariable(VariableTarget target)
    {
        using SqlCommand command = new("SELECT variables.variable_id, variables.name, variables.description, variables.type, variables.sensitive, variables.value, variables.base_data_type FROM [SSISDB].[internal].[environment_variables] variables JOIN [SSISDB].[catalog].[environments] environments ON environments.environment_id = variables.environment_id JOIN [SSISDB].[catalog].[folders] folders ON folders.folder_id = environments.folder_id WHERE folders.name = @folderName AND environments.name = @environmentName AND variables.name = @variableName", target.Server.ConnectionContext.SqlConnectionObject);
        AddAddressParameters(command, target);

        SetActiveCommand(command);
        try
        {
            using SqlDataReader reader = command.ExecuteReader();
            while (reader.Read())
            {
                PSObject variable = new();
                OutputHelper.AddInstanceProperties(variable, target.Server);
                variable.Properties.Add(new PSNoteProperty("Folder", target.FolderName));
                variable.Properties.Add(new PSNoteProperty("Environment", target.EnvironmentName));
                variable.Properties.Add(new PSNoteProperty("Id", ValueOrNull(reader["variable_id"])));
                variable.Properties.Add(new PSNoteProperty("Name", ValueOrNull(reader["name"])));
                variable.Properties.Add(new PSNoteProperty("Description", ValueOrNull(reader["description"])));
                variable.Properties.Add(new PSNoteProperty("Type", ValueOrNull(reader["type"])));
                variable.Properties.Add(new PSNoteProperty("IsSensitive", ValueOrNull(reader["sensitive"])));
                variable.Properties.Add(new PSNoteProperty("BaseDataType", ValueOrNull(reader["base_data_type"])));
                variable.Properties.Add(new PSNoteProperty("Value", ValueOrNull(reader["value"])));
                WriteObject(variable);
            }
        }
        finally
        {
            SetActiveCommand(null);
        }
    }

    private static object? ValueOrNull(object raw)
    {
        return raw is DBNull ? null : raw;
    }
}
