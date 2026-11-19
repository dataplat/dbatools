#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>Adds extended properties to SQL Server objects for metadata storage and documentation</summary>
[Cmdlet(VerbsCommon.Add, "DbaExtendedProperty", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class AddDbaExtendedPropertyCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>The name of the extended property.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [Alias("Property")]
    [PsStringCast]
    public string Name { get; set; } = null!;

    /// <summary>The value of the extended property.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    [PsStringCast]
    public string Value { get; set; } = null!;

    /// <summary>The object(s) to add the extended property to.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public PSObject[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (LanguagePrimitives.IsTrue(SqlInstance))
        {
            var inputs = new List<PSObject>();
            foreach (Microsoft.SqlServer.Management.Smo.Database database in NativeDatabaseSelection.GatherMatching(this, SqlInstance, SqlCredential,
                Database, true, null, false, server => SetActiveConnection(server.ConnectionContext), () => Stopping))
            {
                if (database.IsAccessible)
                    inputs.Add(PSObject.AsPSObject(database));
            }
            InputObject = inputs.ToArray();
        }
        foreach (PSObject input in InputObject ?? Array.Empty<PSObject>())
        {
            object? parentName = null;
            try
            {
                parentName = input.Properties["Name"]?.Value;
                var parent = (SqlSmoObject)input.BaseObject;
                // Server is object identity, never a function-scope value from an earlier record.
                Server server = ConnectionParent(parent);
                SetActiveConnection(server.ConnectionContext);
                object? computer = input.Properties["ComputerName"]?.Value;
                object? instance = input.Properties["InstanceName"]?.Value;
                object? sqlInstance = input.Properties["SqlInstance"]?.Value;
                if (!LanguagePrimitives.IsTrue(computer) || !LanguagePrimitives.IsTrue(instance) || !LanguagePrimitives.IsTrue(sqlInstance))
                {
                    string serverName = QueryServerName(server);
                    var identity = new DbaInstanceParameter(serverName);
                    if (!LanguagePrimitives.IsTrue(computer))
                        computer = identity.ComputerName;
                    if (!LanguagePrimitives.IsTrue(instance))
                        instance = identity.InstanceName;
                    if (!LanguagePrimitives.IsTrue(sqlInstance))
                        sqlInstance = serverName;
                }
                if (!ShouldProcess(Convert.ToString(parentName), string.Format("Adding an extended property named {0} with a value of '{1}'", Name, Value)))
                    continue;

                var property = new ExtendedProperty(parent, Name, Value);
                property.Create();
                PSObject output = PSObject.AsPSObject(property);
                OutputHelper.AddInstanceProperties(output, server);
                output.Properties["ComputerName"].Value = computer;
                output.Properties["InstanceName"].Value = instance;
                output.Properties["SqlInstance"].Value = sqlInstance;
                output.Properties.Add(new PSNoteProperty("ParentName", parentName));
                output.Properties.Add(new PSNoteProperty("Type", parent.GetType().Name));
                output.Properties.Add(new PSNoteProperty("Server", server));
                OutputHelper.SetDefaultDisplayPropertySet(output, "ComputerName", "InstanceName", "SqlInstance", "ParentName", "Type", "Name", "Value");
                WriteObject(output);
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception exception)
            {
                StopFunction(string.Format("Failed to add extended property {0} with a value of '{1}' to {2}", Name, Value, parentName),
                    errorRecord: new ErrorRecord(exception, exception.GetType().Name, ErrorCategory.NotSpecified, null));
            }
        }
    }

    private static string QueryServerName(Server server)
    {
        try
        {
            DataSet result = server.ConnectionContext.ExecuteWithResults("SELECT @@SERVERNAME AS servername");
            return Convert.ToString(result.Tables[0].Rows[0]["servername"])!;
        }
        catch (Exception exception) when (exception is not PipelineStoppedException)
        {
            string message = string.Empty;
            for (Exception? error = exception; error is not null; error = error.InnerException)
                message += error.Message;
            throw new MethodInvocationException(string.Format(
                "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message));
        }
    }

    private static Server ConnectionParent(SqlSmoObject input)
    {
        SqlSmoObject? current = input;
        for (int depth = 0; depth <= 11 && current is not null; depth++)
        {
            if (current is Server server)
                return server;
            // SMO declares Parent on concrete object types rather than on SqlSmoObject.
            current = current.GetType().GetProperty("Parent")?.GetValue(current, null) as SqlSmoObject;
        }
        throw new RuntimeException("You cannot call a method on a null-valued expression.");
    }
}
