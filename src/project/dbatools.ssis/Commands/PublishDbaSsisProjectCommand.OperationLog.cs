#nullable enable

using System;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

public sealed partial class PublishDbaSsisProjectCommand
{
    // The refusal the catalog raises when a deployment is logged but failed:
    // "Failed to deploy project. For more information, query the operation_messages view for the
    // operation identifier '%I64d'." The number identifies it on any server language, which the
    // text does not, and its one substitution is the id this command needs.
    private const int DeployFailedMessageNumber = 27203;

    /// <summary>
    /// Reads the log of one known operation. Anything wider would be a guess: two windows
    /// deploying the same project name to one catalog produce operations that differ only by id,
    /// so a name-and-range match can hand back the other deployment's errors as this one's.
    /// </summary>
    private string ReadOperationMessages(Server server, long operationId)
    {
        using SqlCommand command = new("SELECT TOP 10 messages.message FROM [SSISDB].[catalog].[operation_messages] messages WHERE messages.operation_id = @operationId ORDER BY messages.operation_message_id", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@operationId", operationId);
        return CollectMessages(command);
    }

    /// <summary>
    /// The last resort, for a refusal that named no operation: the proc raised before assigning the
    /// OUTPUT parameter, so the only handle left is the project name among the operations logged
    /// since this call started. That handle is not unique - a peer deploying the same project name
    /// at the same moment logs an operation the range also matches - so an ambiguous range reports
    /// nothing at all and the caller falls back to the raised text. A plausible wrong reason is
    /// worse than a thin one: it reads exactly like an explanation of the failure in hand.
    /// </summary>
    private string ReadOperationMessagesSince(Server server, long priorOperationId)
    {
        long? soleMatch = ReadSoleDeployOperationSince(server, priorOperationId);
        return soleMatch.HasValue ? ReadOperationMessages(server, soleMatch.Value) : string.Empty;
    }

    /// <summary>
    /// The one deploy operation for this project name logged after the watermark, or null when
    /// there is none or more than one. TOP 2 because the count past two changes nothing.
    /// </summary>
    private long? ReadSoleDeployOperationSince(Server server, long priorOperationId)
    {
        using SqlCommand command = new("SELECT TOP 2 operations.operation_id FROM [SSISDB].[catalog].[operations] operations WHERE operations.operation_id > @priorOperationId AND operations.operation_type = @operationType AND operations.object_name = @projectName ORDER BY operations.operation_id", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@priorOperationId", priorOperationId);
        command.Parameters.AddWithValue("@operationType", DeployOperationType);
        command.Parameters.AddWithValue("@projectName", Project);

        try
        {
            SetActiveCommand(command);
            try
            {
                using SqlDataReader reader = command.ExecuteReader();
                if (!reader.Read())
                {
                    return null;
                }
                long candidate = Convert.ToInt64(reader[0], CultureInfo.InvariantCulture);
                return reader.Read() ? null : candidate;
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
        catch (Exception)
        {
            return null;
        }
    }

    /// <summary>
    /// The operation id the catalog put in its own refusal, when it put one there. Matching on the
    /// SQL error number rather than on the message text keeps this working on a server whose
    /// messages are not English, and the id makes the log read exact rather than a search by
    /// project name that a concurrent deployment of the same name also answers.
    /// </summary>
    private static bool TryReadFailedOperationId(Exception? ex, out long operationId)
    {
        operationId = 0;
        for (Exception? current = ex; current is not null; current = current.InnerException)
        {
            if (current is not SqlException sqlException)
            {
                continue;
            }

            foreach (SqlError error in sqlException.Errors)
            {
                if (error.Number == DeployFailedMessageNumber && TryReadSoleNumber(error.Message, out operationId))
                {
                    return true;
                }
            }
        }

        return false;
    }

    /// <summary>
    /// The id is the message's only substitution, so a message carrying exactly one run of digits
    /// yields it whatever the surrounding words and quoting are. Two runs mean the assumption does
    /// not hold on this server and the caller must not treat the guess as an id.
    /// </summary>
    private static bool TryReadSoleNumber(string message, out long value)
    {
        value = 0;
        string? found = null;
        int index = 0;
        while (index < message.Length)
        {
            if (!char.IsDigit(message[index]))
            {
                index++;
                continue;
            }

            int start = index;
            while (index < message.Length && char.IsDigit(message[index]))
            {
                index++;
            }

            if (found is not null)
            {
                return false;
            }
            found = message.Substring(start, index - start);
        }

        return found is not null && long.TryParse(found, NumberStyles.None, CultureInfo.InvariantCulture, out value);
    }

    private string CollectMessages(SqlCommand command)
    {
        StringBuilder detail = new();
        try
        {
            SetActiveCommand(command);
            try
            {
                using SqlDataReader reader = command.ExecuteReader();
                while (reader.Read())
                {
                    object raw = reader["message"];
                    if (raw is DBNull)
                    {
                        continue;
                    }
                    if (detail.Length > 0)
                    {
                        detail.Append(" | ");
                    }
                    detail.Append(Convert.ToString(raw, CultureInfo.InvariantCulture));
                }
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
        catch (Exception)
        {
            // The deployment failure is the news; losing the explanation must not replace it with
            // a failure to read the explanation.
            return string.Empty;
        }

        return detail.ToString();
    }
}
