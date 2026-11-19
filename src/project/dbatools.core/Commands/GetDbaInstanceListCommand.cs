#nullable enable

using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>Returns the user-maintained list of SQL Server instances used for tab completion.</summary>
[Cmdlet(VerbsCommon.Get, "DbaInstanceList")]
public sealed class GetDbaInstanceListCommand : DbaBaseCmdlet
{
    /// <summary>Retains the existing parameterless command surface.</summary>
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        object? value = ConfigurationValueLookup.Read("tabexpansion.knowninstances");
        if (value is null)
        {
            value = new object[0];
        }

        WriteObject(value, true);
    }
}
