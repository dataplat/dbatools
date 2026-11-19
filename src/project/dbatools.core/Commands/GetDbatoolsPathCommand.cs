#nullable enable

using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves configured file paths used by dbatools functions for storing temporary files, logs, and output data.</summary>
/// <para>
/// Retrieves file paths that have been configured for use by dbatools functions. These paths define where the module stores temporary files, exports, logs, and other data during SQL Server operations. DBAs can customize these paths to control where dbatools writes files, ensuring compliance with organizational file storage policies and avoiding permission issues.
/// </para>
/// <para>
/// Paths can be configured using Set-DbatoolsPath or directly through the configuration system by creating settings with the format "Path.Managed.&lt;PathName&gt;". Common predefined paths include Temp, LocalAppData, AppData, and ProgramData, but custom paths can be defined for specific workflows like backup file staging or export destinations.
/// </para>
/// <example>
/// <prefix>PS C:\&gt;</prefix>
/// <code>Get-DbatoolsPath -Name 'temp'</code>
/// <para>Returns the temp path.</para>
/// </example>
/// <list type="alertSet">
/// <item><term /><description><para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para></description></item>
/// <item><term>OUTPUTS</term><description>
/// <para>System.String</para>
/// <para>Returns the configured file path as a string. The returned path represents the location where dbatools will store files for the specified path name (Temp, LocalAppData, AppData, ProgramData, or custom-defined path). Returns $null if the specified path name is not configured.</para>
/// </description></item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbatoolsPath" />
[Cmdlet(VerbsCommon.Get, "DbatoolsPath")]
[OutputType(typeof(string))]
public sealed class GetDbatoolsPathCommand : DbaBaseCmdlet
{
    /// <para>
    /// Specifies the name of the configured path to retrieve. Common predefined paths include 'Temp' for temporary file operations, 'LocalAppData' for user-specific application data, 'AppData' for roaming profile data, and 'ProgramData' for system-wide application data.
    /// Use this when you need to determine where dbatools will write files for export operations, temporary processing, or when configuring custom paths for specific workflows like backup staging directories or report output locations.
    /// Custom path names can be defined using Set-DbatoolsPath and referenced here for consistent file management across your SQL Server administration scripts.
    /// </para>
    [Parameter(Mandatory = true, Position = 0)]
    [PsStringCast]
    public string? Name { get; set; }

    /// <summary>Retains internal error handling without adding a parameter absent upstream.</summary>
    public override SwitchParameter EnableException
    {
        get => base.EnableException;
        set => base.EnableException = value;
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        WriteObject(ConfigurationValueLookup.Read("Path.Managed." + Name, this), true);
    }
}
