#nullable enable

using System;
using System.Management.Automation;
using System.Runtime.InteropServices;
using System.Security;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// <para type="synopsis">Creates variables in an SSIS catalog environment.</para>
/// <para type="description">Creates one or more variables in an environment of the SSIS catalog (SSISDB). Environment variables are the values a project execution binds its parameters to, which is what lets one deployed project run against development, test and production settings.</para>
/// <para type="description">Calls catalog.create_environment_variable with parameterized T-SQL rather than the Integration Services object model, so it works on both PowerShell editions and on Linux. Each variable is created, emitted and errored independently.</para>
/// <para type="description">A sensitive value is supplied through -SecureValue as a SecureString and is never accepted as plain text: a password passed as an ordinary value would survive in the caller's command history and in any transcript. Sensitivity is decided at creation and is effectively one-way - the catalog can promote a variable to sensitive later but refuses to take a stored sensitive value back out of encryption - so it is worth getting right here.</para>
/// <para type="description">-DataType is the SSIS type name the catalog validates against, not a guess made from the value: Boolean, Byte, DateTime, Decimal, Double, Int16, Int32, Int64, SByte, Single, String, UInt32 or UInt64. Omit it for an ordinary value and it is derived from the .NET type - Boolean, Byte, DateTime, Decimal, Double, Int16 (Int16), Int32 (Int32), Int64 (Int64), Single and String map across directly. A null value has no type to derive from, so it needs -DataType named. It is required alongside -Sensitive, because a SecureString carries no type information at all, and there it has to be String: the secret is bound as text and the catalog refuses text carrying any other declared type.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; New-DbaSsisEnvironmentVariable -SqlInstance sql2019 -Folder Finance -Environment Production -Variable BatchSize -Value 500</code>
///   <para>Creates the BatchSize variable as an Int32 in the Production environment, deriving the type from the value.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; New-DbaSsisEnvironmentVariable -SqlInstance sql2019 -Folder Finance -Environment Production -Variable Threshold -Value 2.5 -DataType Decimal</code>
///   <para>Creates Threshold as a Decimal rather than the Double the .NET type would have implied. State the type whenever the SSIS parameter it binds to is particular about it.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; New-DbaSsisEnvironmentVariable -SqlInstance sql2019 -Folder Finance -Environment Production -Variable ServicePassword -SecureValue (Read-Host -AsSecureString) -Sensitive -DataType String</code>
///   <para>Creates an encrypted variable. -Sensitive requires -SecureValue and -DataType, and there is no way to pass the value as plain text.</para>
/// </example>
[Cmdlet(VerbsCommon.New, "DbaSsisEnvironmentVariable", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(PSObject))]
public sealed class NewDbaSsisEnvironmentVariableCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The SSIS catalog folder the environment lives in.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public string Folder { get; set; } = null!;

    /// <summary>The environment to create the variables in. It has to exist already; use New-DbaSsisEnvironment for that.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    public string Environment { get; set; } = null!;

    /// <summary>The name or names of the variables to create. Every name in one call gets the same value, type and description.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    [Alias("Name")]
    public string[] Variable { get; set; } = null!;

    /// <summary>The SSIS type name the catalog records for the variable. Omit it for an ordinary value and it is derived from the .NET type; it is required with -Sensitive.</summary>
    [Parameter(Position = 5)]
    public string? DataType { get; set; }

    /// <summary>The value for an ordinary variable. Pass the real .NET type - the catalog stores it in a sql_variant and checks it against the declared type.</summary>
    [Parameter(Position = 6)]
    public object? Value { get; set; }

    /// <summary>The value for a sensitive variable. This is the only way to supply one, and it requires -Sensitive.</summary>
    [Parameter(Position = 7)]
    public SecureString? SecureValue { get; set; }

    /// <summary>Stores the variable encrypted. Requires -SecureValue and -DataType, and cannot be undone once a sensitive value is stored.</summary>
    [Parameter]
    public SwitchParameter Sensitive { get; set; }

    /// <summary>A description to set on each variable created by this call.</summary>
    [Parameter(Position = 8)]
    public string? Description { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>
    /// The value parameters are settled before anything connects, because every one of these is a
    /// caller mistake rather than a server condition - and the one that matters most, a secret
    /// arriving through the plain -Value parameter, has already leaked into the caller's history
    /// by the time a connection would have been opened.
    /// </summary>
    protected override void BeginProcessing()
    {
        if (TestBound(nameof(Value)) && TestBound(nameof(SecureValue)))
        {
            StopFunction("You must supply either -Value or -SecureValue, not both", category: ErrorCategory.InvalidArgument);
            return;
        }

        if (!TestBound(nameof(Value)) && !TestBound(nameof(SecureValue)))
        {
            StopFunction("You must supply either -Value or -SecureValue", category: ErrorCategory.InvalidArgument);
            return;
        }

        if (Sensitive.ToBool() && !TestBound(nameof(SecureValue)))
        {
            StopFunction("-Sensitive requires -SecureValue: a sensitive value is never accepted as plain text", category: ErrorCategory.InvalidArgument);
            return;
        }

        if (TestBound(nameof(SecureValue)) && !Sensitive.ToBool())
        {
            StopFunction("-SecureValue requires -Sensitive: a value supplied securely and then stored in the clear is a false assurance", category: ErrorCategory.InvalidArgument);
            return;
        }

        if (Sensitive.ToBool() && !TestBound(nameof(DataType)))
        {
            StopFunction("-Sensitive requires -DataType: a SecureString carries no type information", category: ErrorCategory.InvalidArgument);
            return;
        }

        // A SecureString is text, and the only way to bind it without materialising the secret as
        // a managed string is as nvarchar. The catalog checks the sql_variant's base type against
        // the declared one, so naming any other type here reaches the server and comes back as
        // "The data type of the input value is not compatible with the data type of the 'Int32'" -
        // measured on SQL 2019. Refusing here says which parameter is wrong.
        if (Sensitive.ToBool() && TestBound(nameof(DataType)) && !string.Equals(DataType, "String", StringComparison.OrdinalIgnoreCase))
        {
            StopFunction($"-Sensitive requires -DataType String, not {DataType}: a sensitive value is supplied as a SecureString and the catalog stores it as text", category: ErrorCategory.InvalidArgument);
            return;
        }

        if (!TestBound(nameof(DataType)) && !TryDeriveDataType(GetValueType(Value), out _))
        {
            // A bound null is the case worth naming separately: there is no type to derive from at
            // all, and the generic message would have to describe the absence of a type.
            string described = Value == null
                ? "a null -Value"
                : $"{GetValueType(Value)!.FullName}";
            StopFunction($"Cannot derive an SSIS data type from {described}; supply -DataType", category: ErrorCategory.InvalidArgument);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // The SSIS catalog schema arrived in SQL 2012, so an older instance is refused with
            // the version message rather than failing later on a missing catalog schema.
            Server server = ConnectInstance(instance, "Failure", minimumVersion: 11);
            if (server == null)
            {
                continue;
            }

            try
            {
                // ConnectionService hands back a Server whose ConnectionContext may still be
                // lazy; SqlConnectionObject is only usable once it has actually connected.
                if (!server.ConnectionContext.IsOpen)
                {
                    server.ConnectionContext.Connect();
                }

                if (!CatalogExists(server))
                {
                    StopFunction($"No SSIS catalog (SSISDB) found on {instance}", target: instance, continueLoop: true);
                    continue;
                }

                string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);
                foreach (string variableName in Variable)
                {
                    if (!ShouldProcess(target, $"Creating SSIS environment variable {variableName} in {Folder}\\{Environment}"))
                    {
                        continue;
                    }

                    try
                    {
                        CreateVariable(server, variableName);
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        StopFunction($"Failure creating SSIS environment variable {variableName} in {Folder}\\{Environment} on {instance}", target: instance, exception: ex, continueLoop: true);
                        continue;
                    }

                    // The read-back reaches further than the create did - it reads the catalog
                    // views directly, where create_environment_variable is a proc - so a caller who
                    // may create variables but not select from those views fails here and nowhere
                    // else. Outside its own catch that failure escaped to the per-instance handler
                    // and dropped every variable after this one. The variable exists either way,
                    // which is why this does not report a creation failure.
                    try
                    {
                        EmitVariable(server, variableName);
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        StopFunction($"SSIS environment variable {variableName} was created in {Folder}\\{Environment} on {instance} but could not be read back", target: instance, exception: ex, continueLoop: true);
                        continue;
                    }
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction($"Failure creating SSIS environment variables on {instance}", target: instance, exception: ex, continueLoop: true);
            }
        }
    }

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

    private void CreateVariable(Server server, string variableName)
    {
        using SqlCommand command = new("EXEC [SSISDB].[catalog].[create_environment_variable] @folder_name = @folderName, @environment_name = @environmentName, @variable_name = @variableName, @data_type = @dataType, @sensitive = @sensitive, @value = @value, @description = @description", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", Folder);
        command.Parameters.AddWithValue("@environmentName", Environment);
        command.Parameters.AddWithValue("@variableName", variableName);
        command.Parameters.AddWithValue("@dataType", ResolveDataType());
        command.Parameters.AddWithValue("@sensitive", Sensitive.ToBool());
        command.Parameters.AddWithValue("@description", (object?)Description ?? DBNull.Value);

        // The secret is copied out of the SecureString into a char array bound straight to the
        // parameter, so it never becomes a managed string that would sit in memory until a
        // collection nobody controls. Both the unmanaged buffer and the array are cleared below.
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
                command.Parameters.AddWithValue("@value", Value ?? (object)DBNull.Value);
            }

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
    /// The type is passed through, never inferred from the value when the caller named one: the
    /// catalog validates it against internal.data_type_mapping, and guessing Int32 where the SSIS
    /// parameter wants Int16 produces a variable that binds to nothing.
    /// </summary>
    private string ResolveDataType()
    {
        if (TestBound(nameof(DataType)))
        {
            return DataType!;
        }

        // BeginProcessing has already refused anything this cannot answer.
        TryDeriveDataType(GetValueType(Value), out string derived);
        return derived;
    }

    /// <summary>
    /// internal.data_type_mapping is what the proc validates @data_type against, and it maps each
    /// SSIS type name to the sql_variant base types allowed to carry it. Only the .NET types
    /// SqlClient can bind to one of those base types are derivable; SByte, UInt32 and UInt64 have
    /// no SqlClient binding of their own and have to be named explicitly.
    /// </summary>
    private static bool TryDeriveDataType(Type? valueType, out string dataType)
    {
        dataType = valueType switch
        {
            null => "",
            _ when valueType == typeof(bool) => "Boolean",
            _ when valueType == typeof(byte) => "Byte",
            _ when valueType == typeof(DateTime) => "DateTime",
            _ when valueType == typeof(decimal) => "Decimal",
            _ when valueType == typeof(double) => "Double",
            _ when valueType == typeof(short) => "Int16",
            _ when valueType == typeof(int) => "Int32",
            _ when valueType == typeof(long) => "Int64",
            _ when valueType == typeof(float) => "Single",
            _ when valueType == typeof(string) => "String",
            _ => ""
        };

        return dataType.Length > 0;
    }

    private static Type? GetValueType(object? value)
    {
        // PowerShell hands an argument bound to an [object] parameter over as a PSObject often
        // enough that unwrapping it is not optional; the CLR type underneath is what decides.
        object? bare = value is PSObject wrapper ? wrapper.BaseObject : value;
        return bare?.GetType();
    }

    /// <summary>
    /// The new variable is re-emitted in Get-DbaSsisEnvironmentVariable's shape so New -&gt; Get
    /// pipelines compose. Value is read from the stored column, which the proc leaves null for a
    /// sensitive variable - so a secret is not echoed back, without that having to be a special
    /// case here; the ciphertext lives in a separate column that is deliberately not read.
    /// <para>The read is against internal.environment_variables rather than the catalog view
    /// because base_data_type exists only on the internal table, which is also where
    /// Get-DbaSsisEnvironmentVariable reads it from.</para>
    /// </summary>
    private void EmitVariable(Server server, string variableName)
    {
        using SqlCommand command = new("SELECT variables.variable_id, variables.name, variables.description, variables.type, variables.sensitive, variables.value, variables.base_data_type FROM [SSISDB].[internal].[environment_variables] variables JOIN [SSISDB].[catalog].[environments] environments ON environments.environment_id = variables.environment_id JOIN [SSISDB].[catalog].[folders] folders ON folders.folder_id = environments.folder_id WHERE folders.name = @folderName AND environments.name = @environmentName AND variables.name = @variableName", server.ConnectionContext.SqlConnectionObject);
        command.Parameters.AddWithValue("@folderName", Folder);
        command.Parameters.AddWithValue("@environmentName", Environment);
        command.Parameters.AddWithValue("@variableName", variableName);

        SetActiveCommand(command);
        try
        {
            using SqlDataReader reader = command.ExecuteReader();
            while (reader.Read())
            {
                PSObject variable = new();
                OutputHelper.AddInstanceProperties(variable, server);
                variable.Properties.Add(new PSNoteProperty("Folder", Folder));
                variable.Properties.Add(new PSNoteProperty("Environment", Environment));
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
