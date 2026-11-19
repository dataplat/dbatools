#nullable enable

using System;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Configures Extended Protection for Authentication on SQL Server network protocols
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaExtendedProtection", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low, DefaultParameterSetName = "Default")]
public sealed class SetDbaExtendedProtectionCommand : ExtendedProtectionCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; } = LocalComputer();

    /// <summary>Allows you to login to the computer (not SQL Server instance) using alternative Windows credentials</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>
    /// Specifies the Extended Protection level for SQL Server network protocols. Accepts "Off", "Allowed", or "Required" (or equivalent integers 0, 1, 2).
    /// Use "Off" to disable Extended Protection, "Allowed" to accept both protected and unprotected connections, or "Required" to enforce Extended Protection for all client connections.
    /// Defaults to "Off" when not specified. Setting to "Required" may prevent older applications from connecting unless they support Extended Protection authentication.
    /// </summary>
    [Parameter(Position = 2)]
    [ValidateSet("0", "Off", "1", "Allowed", "2", "Required")]
    public object Value { get; set; } = "Off";

    /// <summary>
    /// Specifies the service principal names SQL Server accepts for Extended Protection service binding. Multiple values are stored as a semicolon-delimited registry value.
    /// When this parameter is supplied without Value, the current Extended Protection level is left unchanged. Pass an empty string to clear the accepted SPN list.
    /// </summary>
    [Parameter(Position = 3)]
    [AllowEmptyString]
    public string[]? AcceptedSpn { get; set; }

    private bool _setAcceptedSpn;
    private bool _setExtendedProtection;
    private string _acceptedSpnValue = String.Empty;
    private object? _level;

    /// <inheritdoc />
    protected override DbaInstanceParameter[]? Targets => SqlInstance;

    /// <inheritdoc />
    protected override PSCredential? WindowsCredential => Credential;

    /// <inheritdoc />
    protected override string ConfirmAction => "Connecting to {0} to modify Extended Protection settings in {1} for {2}";

    protected override void BeginProcessing()
    {
        base.BeginProcessing();
        // PS begin: Test-Bound for both switches of work, the SPN list joined with ";", and the level as 0, 1 or 2.
        _setAcceptedSpn = TestBound("AcceptedSpn");
        _setExtendedProtection = TestBound("Value") || !_setAcceptedSpn;
        _acceptedSpnValue = AcceptedSpn is null ? String.Empty : String.Join(";", AcceptedSpn);
        _level = Level(Value);
    }

    /// <inheritdoc />
    protected override void WriteSettingMessages(DbaInstanceParameter instance)
    {
        WriteMessage(MessageLevel.Verbose, "Value: " + (_level is null ? String.Empty : LanguagePrimitives.ConvertTo<string>(_level)), target: instance);
        if (_setAcceptedSpn)
        {
            WriteMessage(MessageLevel.Verbose, "Accepted SPNs: " + _acceptedSpnValue, target: instance);
        }
    }

    /// <inheritdoc />
    protected override ExtendedProtectionRegistry.Settings Apply(string computerName, string regRoot)
    {
        return ExtendedProtectionRegistry.Write(computerName, regRoot, Credential,
            _setExtendedProtection, _level, _setAcceptedSpn, _acceptedSpnValue);
    }

    /// <inheritdoc />
    protected override void Applied(string computerName, string? instanceName, DbaInstanceParameter instance)
    {
        WriteMessage(MessageLevel.Critical, String.Format("Extended Protection settings were successfully set on {0} for the {1} instance. The change takes effect immediately for new connections.", computerName, instanceName), target: instance);
    }

    // PS: if (($Value -notin 0, 1, 2) -and ($null -ne $Value)) { $Value = switch ($Value) { "Off" { 0 } "Allowed" { 1 } "Required" { 2 } } }
    private static object? Level(object? value)
    {
        object? raw = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (raw is null)
        {
            return null;
        }
        foreach (int level in new[] { 0, 1, 2 })
        {
            // -notin compares each list element on the left: 0 -eq $Value.
            if (LanguagePrimitives.Equals(level, raw, true, CultureInfo.InvariantCulture))
            {
                return raw;
            }
        }
        string text = LanguagePrimitives.ConvertTo<string>(raw) ?? String.Empty;
        if (String.Equals(text, "Off", StringComparison.OrdinalIgnoreCase))
        {
            return 0;
        }
        if (String.Equals(text, "Allowed", StringComparison.OrdinalIgnoreCase))
        {
            return 1;
        }
        if (String.Equals(text, "Required", StringComparison.OrdinalIgnoreCase))
        {
            return 2;
        }
        // A switch with no matching clause yields nothing, so $Value becomes $null.
        return null;
    }
}
