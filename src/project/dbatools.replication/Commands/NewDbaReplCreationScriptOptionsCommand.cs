#nullable enable

using System;
using System.Management.Automation;
using Microsoft.SqlServer.Replication;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a Microsoft.SqlServer.Replication.CreationScriptOptions flags value.
/// Port of public/New-DbaReplCreationScriptOptions.ps1. Pure flags constructor: no instance
/// connection and no state change (the source carries a PSUseShouldProcessForStateChangingFunctions
/// suppression, so there is deliberately NO SupportsShouldProcess here). Emits one CreationScriptOptions.
///
/// PARITY NOTE (reproduce, not sanitize): the source accumulates with `$cso += $_` where $_ is a
/// string. PowerShell's += on an enum is ARITHMETIC addition of the underlying value (empirically:
/// [System.Reflection.BindingFlags]Instance + Instance = 8/Static, NOT 4/Instance), it is NOT a
/// bitwise OR. For the 11 distinct default flags arithmetic == OR, but a user -Options value that
/// overlaps a default (or repeats itself) arithmetic-doubles the bit — that latent behaviour is
/// reproduced here, not "fixed" to |=. Accumulation runs through Convert.ToInt64 / Enum.ToObject so
/// it is faithful regardless of the enum's underlying integer type (no int/long truncation).
/// Enum parsing is case-insensitive to match PowerShell string->enum conversion; an unknown option
/// name throws a terminating conversion error exactly as the source's `+=` does (the source function
/// has no try/catch around the accumulation).
///
/// EnableException is inherited from DbaBaseCmdlet - never redeclared.
/// Surface pinned by migration/baselines/New-DbaReplCreationScriptOptions.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaReplCreationScriptOptions")]
[OutputType(typeof(CreationScriptOptions))]
public sealed class NewDbaReplCreationScriptOptionsCommand : DbaBaseCmdlet
{
    /// <summary>Additional CreationScriptOptions flag names to include beyond the default set.</summary>
    // The source declares no explicit Position; as a non-switch parameter it auto-binds to
    // position 0 (baseline pins Options = 0), so the compiled surface pins it here.
    [Parameter(Position = 0)]
    public string[]? Options { get; set; }

    /// <summary>Start from an empty option set instead of the SSMS-default flags.</summary>
    [Parameter]
    public SwitchParameter NoDefaults { get; set; }

    // The SSMS-default flags applied unless -NoDefaults, verbatim order and names from the source.
    private static readonly string[] DefaultOptionNames =
    {
        "PrimaryObject",
        "CustomProcedures",
        "Identity",
        "KeepTimestamp",
        "ClusteredIndexes",
        "DriPrimaryKey",
        "Collation",
        "DriUniqueKeys",
        "MarkReplicatedCheckConstraintsAsNotForReplication",
        "MarkReplicatedForeignKeyConstraintsAsNotForReplication",
        "Schema"
    };

    protected override void ProcessRecord()
    {
        // PS: $cso = New-Object Microsoft.SqlServer.Replication.CreationScriptOptions  (default enum value = 0)
        long accumulated = 0;

        // PS: if (-not $NoDefaults) { <defaults> | ForEach-Object { $cso += $_ } }
        if (!NoDefaults.ToBool())
        {
            foreach (string name in DefaultOptionNames)
            {
                accumulated += Convert.ToInt64(Enum.Parse(typeof(CreationScriptOptions), name, ignoreCase: true));
            }
        }

        // PS: foreach ($opt in $options) { $cso += $opt }   ($options $null => zero iterations)
        if (Options != null)
        {
            foreach (string opt in Options)
            {
                accumulated += Convert.ToInt64(Enum.Parse(typeof(CreationScriptOptions), opt, ignoreCase: true));
            }
        }

        // PS: $cso   (single emit of the raw CreationScriptOptions flags value; no Select-DefaultView)
        WriteObject((CreationScriptOptions)Enum.ToObject(typeof(CreationScriptOptions), accumulated));
    }
}
