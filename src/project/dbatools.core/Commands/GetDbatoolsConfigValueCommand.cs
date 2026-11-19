#nullable enable

using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves a specific dbatools configuration value by its exact name.</summary>
/// <para>Retrieves the actual value stored in a specific dbatools configuration setting using its full name (Module.Name format). This function is primarily used internally by dbatools functions to access their configuration settings, but can also be used by DBAs in custom scripts to retrieve specific module preferences like connection timeouts, default file paths, or email settings. Unlike Get-DbatoolsConfig which lists multiple configurations, this function returns the raw value of a single setting with optional fallback support.</para>
/// <list type="alertSet">
///   <item>
///     <term></term>
///     <description>
///       <para>Tags: Module</para>
///       <para>Author: Friedrich Weinmann (@FredWeinmann)</para>
///       <para>Website: https://dbatools.io</para>
///       <para>Copyright: (c) 2018 by dbatools, licensed under MIT</para>
///       <para>License: MIT https://opensource.org/licenses/MIT</para>
///     </description>
///   </item>
///   <item><term>OUTPUTS</term><description>
///     <para>object</para>
///     <para>Returns the value stored in the specified dbatools configuration setting. The return type depends on which configuration setting is retrieved - can be string, int, bool, datetime, or any object type stored in that configuration.</para>
///     <para>Return behavior:</para>
///     <para>- If the configuration exists and has a value, returns that value</para>
///     <para>- If the configuration doesn't exist or is null AND -Fallback is specified, returns the Fallback value</para>
///     <para>- If the configuration doesn't exist or is null AND -NotNull is specified, throws an error</para>
///     <para>- If the configuration doesn't exist or is null AND neither -Fallback nor -NotNull is specified, returns $null</para>
///     <para>Special handling: String values of "Mandatory" are automatically converted to $true and "Optional" are converted to $false to prevent switch parameter parsing issues.</para>
///   </description></item>
/// </list>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbatoolsConfigValue -Name 'System.MailServer'</code>
///   <para>Returns the configured value that was assigned to the key 'System.MailServer'</para>
/// </example>
/// <example>
///   <prefix>PS C:\&gt;</prefix>
///   <code>Get-DbatoolsConfigValue -Name 'Default.CoffeeMilk' -Fallback 0</code>
///   <para>Returns the configured value for 'Default.CoffeeMilk'. If no such value is configured, it returns '0' instead.</para>
/// </example>
/// <seealso href="https://dbatools.io/Get-DbatoolsConfigValue"/>
[Cmdlet(VerbsCommon.Get, "DbatoolsConfigValue")]
[OutputType(typeof(object))]
public sealed class GetDbatoolsConfigValueCommand : DbaBaseCmdlet
{
    /// <para>Specifies the exact configuration setting name in Module.Name format (like 'sql.connection.timeout' or 'path.dbatoolsdata').</para>
    /// <para>Use this to retrieve specific dbatools module settings that control behavior like connection timeouts, default file paths, or email configurations.</para>
    [Alias("Name")]
    [Parameter(Mandatory = true, Position = 0)]
    [PsStringCast]
    public string? FullName { get; set; }

    /// <para>Provides a default value to return when the specified configuration setting doesn't exist or is set to null.</para>
    /// <para>Use this in scripts when you need a reliable value even if the configuration hasn't been set, such as providing a default timeout of 30 seconds when no custom timeout is configured.</para>
    [Parameter(Position = 1)]
    public object? Fallback { get; set; }

    /// <para>Forces the function to throw an error instead of returning null when no configuration value is found.</para>
    /// <para>Use this when your script requires a specific configuration setting to be present and should fail gracefully rather than continue with null values that could cause unexpected behavior.</para>
    [Parameter]
    public SwitchParameter NotNull { get; set; }

    /// <summary>Retains internal error handling without adding a parameter absent upstream.</summary>
    public override SwitchParameter EnableException
    {
        get => base.EnableException;
        set => base.EnableException = value;
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        string fullName = FullName!.ToLowerInvariant();

        object? temp = ConfigurationValueLookup.Read(fullName, this);
        if (temp is null)
        {
            temp = Fallback;
        }

        if (NotNull.IsPresent && temp is null)
        {
            // PS: Stop-Function ... -EnableException $true (hardcoded regardless of the
            // caller); the base reads the cmdlet's EnableException, so force it on - the
            // call throws immediately and nothing follows.
            EnableException = SwitchParameter.Present;
            StopFunction("No Configuration Value available for " + fullName, target: fullName, category: ErrorCategory.InvalidData);
            return;
        }

        WriteObject(temp, true);
    }
}
