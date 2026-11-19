#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>Creates directories on SQL Server machines using the SQL Server service account</summary>
/// <para>Creates directories on local or remote SQL Server machines by executing the xp_create_subdir extended stored procedure. This is particularly useful when you need to create backup directories, log shipping paths, or database file locations where the SQL Server service account needs to have access. The function checks if the path already exists before attempting creation and returns the success status for each operation.</para>
/// <list type="alertSet">
///   <item><term></term><description>
///     <para>Tags: Storage, Path, Directory, Folder</para>
///     <para>Author: Stuart Moore</para>
///     <para>Website: https://dbatools.io</para>
///     <para>Copyright: (c) 2018 by dbatools, licensed under MIT</para>
///     <para>License: MIT https://opensource.org/licenses/MIT</para>
///     <para>Requires: Admin access to server (not SQL Services), Remoting must be enabled and accessible if $SqlInstance is not local</para>
///   </description></item>
///   <item><term>OUTPUTS</term><description>
///     <para>PSCustomObject</para>
///     <para>Returns one object per SQL Server instance specified in -SqlInstance, providing the directory creation status for each instance.</para>
///     <para>Properties:</para>
///     <para>- Server: The SQL Server instance name that was targeted for directory creation</para>
///     <para>- Path: The full directory path that was created on the SQL Server machine</para>
///     <para>- Created: Boolean ($true or $false) indicating whether the directory was successfully created</para>
///     <para>The function only returns output if the path does not already exist and the ShouldProcess operation is confirmed (when -WhatIf is not specified or user confirms the action).</para>
///   </description></item>
/// </list>
/// <example><prefix>PS C:\&gt;</prefix>
///   <code>New-DbaDirectory -SqlInstance sqlcluster -Path L:\MSAS12.MSSQLSERVER\OLAP</code>
///   <para>If the SQL Server instance sqlcluster can create the path L:\MSAS12.MSSQLSERVER\OLAP it will do and return $true, if not it will return $false.</para>
/// </example>
/// <example><prefix>PS C:\&gt;</prefix>
///   <code>$credential = Get-Credential</code>
///   <para>PS C:\&gt; New-DbaDirectory -SqlInstance sqlcluster -SqlCredential $credential -Path L:\MSAS12.MSSQLSERVER\OLAP If the SQL Server instance sqlcluster can create the path L:\MSAS12.MSSQLSERVER\OLAP it will do and return $true, if not it will return $false. Uses a SqlCredential to connect</para>
/// </example>
/// <seealso href="https://dbatools.io/New-DbaDirectory" />
[Cmdlet(VerbsCommon.New, "DbaDirectory", SupportsShouldProcess = true)]
[OutputType(typeof(PSCustomObject))]
public sealed class NewDbaDirectoryCommand : DbaInstanceCmdlet
{
    /// <para>The SQL Server you want to run the test on.</para>
    [Parameter(Mandatory = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>Specifies the full directory path to create on the SQL Server machine using the SQL Server service account. Use this when you need to create backup directories, database file paths, or log shipping folders where SQL Server needs access. The function will check if the path already exists and skip creation if it does.</para>
    [Parameter(Mandatory = true, Position = 1)]
    [PsStringCast]
    public string Path { get; set; } = null!;

    /// <para>Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).</para>
    /// <para>Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.</para>
    /// <para>For MFA support, please use Connect-DbaInstance.</para>
    [Parameter(Position = 2)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message. This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting. Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.</para>
    [Parameter]
    public override SwitchParameter EnableException
    {
        get => base.EnableException;
        set => base.EnableException = value;
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, azureUnsupported: true);
            if (server is null)
                continue;

            if (PathExists(server, Path))
            {
                StopFunction(String.Format(CultureInfo.CurrentCulture, "{0} already exists", Path), target: server, continueLoop: true);
                continue;
            }

            // The pin prints the SQL literal. The actual command always binds the path separately.
            WriteMessage(MessageLevel.Debug, String.Format(CultureInfo.CurrentCulture, "EXEC master.dbo.xp_create_subdir '{0}'", Path.Replace("'", "''")));
            if (!ShouldProcess(Path, String.Format(CultureInfo.CurrentCulture, "Creating a new path on {0}", server.Name)))
                continue;

            bool created = true;
            try
            {
                ExecutePathCommand(server, Path, checkExists: false);
            }
            catch (Exception error) when (error is not PipelineStoppedException)
            {
                created = false;
                ErrorRecord record = new(error, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
                StopFunction("Failure", errorRecord: record);
            }
            PSObject output = new();
            output.Properties.Add(new PSNoteProperty("Server", instance));
            output.Properties.Add(new PSNoteProperty("Path", Path));
            output.Properties.Add(new PSNoteProperty("Created", created));
            WriteObject(output);
        }
    }

    private bool PathExists(Server server, string path)
    {
        DbaInstanceParameter instance = new(server);
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            // Test-DbaPath passes the connected server and its own unbound SqlCredential.
            server = ConnectionService.GetServer(new SmoConnectionRequest
            {
                Instance = instance,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
                MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
            });
            SetActiveConnection(server.ConnectionContext);
        }
        catch (Exception error) when (error is not PipelineStoppedException)
        {
            ErrorRecord record = new(error, "dbatools_Test-DbaPath", ErrorCategory.ConnectionError, instance);
            WarnNestedStopFunction("Test-DbaPath", "Failure", instance, record, ErrorCategory.ConnectionError);
            return false;
        }
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
        try
        {
            return ExecutePathCommand(server, path, checkExists: true);
        }
        catch (Exception error) when (error is not PipelineStoppedException)
        {
            string text = String.Format(CultureInfo.CurrentCulture, "Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", error.Message);
            WriteAttributedMessage("Test-DbaPath", MessageLevel.Warning, String.Format(CultureInfo.CurrentCulture,
                "xp_fileexist execution failed for path(s) on {0}, so existence could not be determined and the path(s) are reported as not found. The SQL Server service account may not have access to the specified path(s). Error: {1}",
                instance, text));
            return false;
        }
    }

    private bool ExecutePathCommand(Server server, string path, bool checkExists)
    {
        ServerConnection connection = server.ConnectionContext;
        bool opened = false;
        try
        {
            if (!connection.IsOpen)
            {
                connection.Connect();
                opened = true;
            }
            using SqlCommand command = connection.SqlConnectionObject.CreateCommand();
            command.CommandText = checkExists ? "EXEC master.dbo.xp_fileexist @path" : "EXEC master.dbo.xp_create_subdir @path";
            command.CommandTimeout = connection.StatementTimeout;
            command.Parameters.Add(new SqlParameter("@path", SqlDbType.NVarChar) { Value = path });
            SetActiveCommand(command);
            if (!checkExists)
            {
                command.ExecuteNonQuery();
                return true;
            }
            using SqlDataReader reader = command.ExecuteReader();
            return reader.Read() && (Convert.ToBoolean(reader[0], CultureInfo.InvariantCulture) || Convert.ToBoolean(reader[1], CultureInfo.InvariantCulture));
        }
        finally
        {
            SetActiveCommand(null);
            if (opened && !connection.NonPooledConnection && connection.AutoDisconnectMode == AutoDisconnectMode.DisconnectIfPooled)
                connection.Disconnect();
        }
    }
}
